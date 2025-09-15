use axum::{
    extract::{OriginalUri, Path, State},
    http::{HeaderMap, StatusCode},
    response::Json,
    routing::get,
    Router,
};
use serde::Serialize;
use std::{sync::Arc, time::Instant};
use tracing::{debug, error, info, warn};
use uuid::Uuid;
use sqlx::Row; // for row.get()

use crate::AppState;

#[derive(Serialize)]
struct CjResolveResp {
    status: &'static str,
    target_ip: String,
    target_port: u16,
    protocol: String,          // dynamic
    username: String,
    password: String,
    ttl_secs: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    url: Option<String>,       // present for WEB so CH can open Chrome
}

fn header(headers: &HeaderMap, name: &str) -> String {
    headers
        .get(name)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("-")
        .to_string()
}

fn mask(s: &str) -> String {
    if s.is_empty() { return String::new(); }
    let n = s.len();
    match n {
        0..=2 => "*".repeat(n),
        3..=6 => format!("{}{}", &s[..1], "*".repeat(n - 2)),
        _ => format!("{}{}{}", &s[..2], "*".repeat(n - 4), &s[n - 2..]),
    }
}

pub fn cj_routes() -> Router<Arc<AppState>> {
    // public (not under /api)
    Router::new().route("/cj/resolve/:token", get(cj_resolve))
}

pub async fn cj_resolve(
    State(state): State<Arc<AppState>>,
    Path(token): Path<String>,
    headers: HeaderMap,
    OriginalUri(uri): OriginalUri,
) -> Result<Json<CjResolveResp>, StatusCode> {
    let started = Instant::now();
    let req_tail = token.get(token.len().saturating_sub(8)..).unwrap_or(&token);
    let ua = header(&headers, "user-agent");
    let xff = header(&headers, "x-forwarded-for");

    info!(target: "cj", %uri, %req_tail, %xff, %ua, "cj_resolve: received");

    // 1) Strict UUID
    let uuid = Uuid::parse_str(token.trim())
        .map_err(|e| { warn!(target: "cj", token=%token, error=%e, "BAD uuid"); StatusCode::BAD_REQUEST })?;

    // 2) Load session -> which device + username (+ protocol)
    let session = match state.session_service.get_session(&uuid).await {
        Ok(Some(s)) => {
            debug!(target: "cj",
                   device_id=%s.device_id, device_ip=%s.device_ip, status=%s.status, user=%s.username, proto=%s.protocol,
                   "session loaded");
            s
        }
        Ok(None) => {
            warn!(target: "cj", %uuid, "session NOT_FOUND");
            return Err(StatusCode::NOT_FOUND);
        }
        Err(e) => {
            error!(target: "cj", error=?e, "DB error on get_session");
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }
    };

    // Must be Active
    if session.status.as_str() != "Active" {
        warn!(target: "cj", status=%session.status, "status not Active");
        return Err(StatusCode::UNAUTHORIZED);
    }

    // 3) Pull TARGET creds from vault
    let wanted_username = session.username.trim();
    let (user, pass) = if !wanted_username.is_empty() {
        match state.vault_service
            .get_credentials_for_session(session.device_id, wanted_username)
            .await
        {
            Ok(Some(pw)) => (wanted_username.to_string(), pw),
            Ok(None) => {
                match state.vault_service
                    .get_first_credentials_for_device(session.device_id)
                    .await
                {
                    Ok(Some((u,p))) => (u,p),
                    Ok(None) => {
                        warn!(target:"cj", device_id=%session.device_id, "no creds in vault");
                        return Err(StatusCode::NOT_FOUND);
                    }
                    Err(e) => {
                        error!(target:"cj", error=?e, "vault query failed");
                        return Err(StatusCode::INTERNAL_SERVER_ERROR);
                    }
                }
            }
            Err(e) => {
                error!(target:"cj", error=?e, "vault query failed");
                return Err(StatusCode::INTERNAL_SERVER_ERROR);
            }
        }
    } else {
        match state.vault_service
            .get_first_credentials_for_device(session.device_id)
            .await
        {
            Ok(Some((u,p))) => (u,p),
            Ok(None) => {
                warn!(target:"cj", device_id=%session.device_id, "no creds in vault");
                return Err(StatusCode::NOT_FOUND);
            }
            Err(e) => {
                error!(target:"cj", error=?e, "vault query failed");
                return Err(StatusCode::INTERNAL_SERVER_ERROR);
            }
        }
    };

    // 4) Decide protocol/port/url
    let proto = session.protocol.to_ascii_uppercase();
    let target_ip = session.device_ip.clone();

    // defaults
    let mut target_port: u16 = 3389;
    let mut url_opt: Option<String> = None;

    match proto.as_str() {
        "WEB" => {
            // Try to read devices.web_url for this device
            // NOTE: AppState must expose a sqlx::PgPool as `pool`.
            // If your field name differs, adjust below.
            let web_url: Option<String> = match sqlx::query("SELECT web_url FROM devices WHERE id = $1")
                .bind(session.device_id)
                .fetch_optional(&state.pool)
                .await
            {
                Ok(Some(row)) => row.try_get::<Option<String>, _>("web_url").ok().flatten(),
                Ok(None) => None,
                Err(e) => {
                    error!(target:"cj", error=?e, "query devices.web_url failed");
                    None
                }
            };

            // Port for web: use 443 by default (Palo Alto often 443 or 9443).
            // If your URLs include an explicit port (e.g. https://host:9443) that wins.
            target_port = 443;

            // Choose URL: prefer DB value, else derive from IP
            let url = web_url.unwrap_or_else(|| format!("https://{}", target_ip));
            url_opt = Some(url);
        }
        "SSH" => {
            target_port = 22;
        }
        "RDP" | _ => {
            // Keep your RDP default (pull from settings if present)
            target_port = match state.settings_service.get_default_rdp_port().await {
                Ok(Some(p)) => p,
                Ok(None) => 3389,
                Err(e) => { error!(target:"cj", error=?e, "get_default_rdp_port failed"); 3389 }
            };
        }
    }

    // TTL from settings.default_cj_ttl_secs (fallback 300)
    let ttl_secs: u32 = match state.settings_service.get_default_cj_ttl_secs().await {
        Ok(Some(t)) => t,
        Ok(None) => 300,
        Err(e) => { error!(target:"cj", error=?e, "get_default_cj_ttl_secs failed"); 300 }
    };

    info!(
        target:"cj",
        uuid=%uuid,
        protocol=%proto,
        target_ip = %target_ip,
        target_port = target_port,
        login_user = %user,
        login_pass_masked = %mask(&pass),
        url=?url_opt,
        ttl = ttl_secs,
        ms = %started.elapsed().as_millis(),
        "OK -> returning target creds"
    );

    Ok(Json(CjResolveResp {
        status: "ok",
        target_ip,
        target_port,
        protocol: proto,   // use session’s protocol
        username: user,
        password: pass,
        ttl_secs,
        url: url_opt,      // CH will use this for WEB
    }))
}
