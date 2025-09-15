use axum::{
    extract::{Path, Query, State},
    http::{header, StatusCode},
    response::{Json, Response},
    routing::{get, post, put},
    Router,
};
use serde::Deserialize;
use std::sync::Arc;
use uuid::Uuid;
use validator::Validate;

use crate::models::{
    CreateSessionRequest, EndSessionRequest, SessionDetailResponse, SessionResponse,
};
use crate::utils::generate_rdp_file;
use crate::AppState;

#[derive(Debug, Deserialize)]
pub struct SessionQuery {
    pub status: Option<String>,
}

pub fn session_routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/sessions", get(list_sessions).post(create_session))
        .route("/sessions/:uuid", get(get_session))
        .route("/sessions/:uuid/end", post(end_session))
        .route("/sessions/:uuid/rdp", get(download_rdp_file))
        // Same RDP for web option (CJ decides WEB in /cj/resolve)
        .route("/sessions/:uuid/rdp-web", get(download_rdp_file_for_web))
        .route("/sessions/:uuid/status", put(update_session_status))
        .route("/sessions/:uuid/heartbeat", post(session_heartbeat))
        .route("/sessions/:uuid/security-events", post(report_security_event))
}

/// Shared: load session, choose Jump Host, register CP session, build .rdp (unchanged format)
async fn prepare_rdp_response(
    state: &Arc<AppState>,
    uuid: Uuid,
) -> Result<Response, (StatusCode, String)> {
    // 1) Load session
    let session = match state.session_service.get_session(&uuid).await {
        Ok(Some(s)) => s,
        Ok(None) => return Err((StatusCode::NOT_FOUND, "Session not found".to_string())),
        Err(e) => {
            tracing::error!("Failed to get session {} for RDP generation: {}", uuid, e);
            return Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to retrieve session".to_string(),
            ));
        }
    };

    // 2) Pick Jump Host (prefer Online)
    let jh_list = match state.jump_host_service.list().await {
        Ok(v) if !v.is_empty() => v,
        Ok(_) => {
            return Err((
                StatusCode::PRECONDITION_FAILED,
                "No Jump Host configured".to_string(),
            ))
        }
        Err(e) => {
            tracing::error!("Failed to list jump hosts: {}", e);
            return Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to list jump hosts".to_string(),
            ));
        }
    };

    let jh = jh_list
        .iter()
        .find(|jh| jh.status.eq_ignore_ascii_case("Online"))
        .or_else(|| jh_list.get(0))
        .ok_or_else(|| {
            (
                StatusCode::PRECONDITION_FAILED,
                "No Jump Host configured".to_string(),
            )
        })?;

    let jump_host_ip = jh.ip.to_string();

    tracing::info!(
        "RDP(gen): Jump Host id={} name={} ip={} for uuid={} (device_id={})",
        jh.id, jh.name, jump_host_ip, uuid, session.device_id
    );

    // 3) Register CP session (so CJ/CP/CPF can resolve token later)
    if let Err(e) = state
        .session_service
        .register_cp_session(uuid, session.device_id as i32, &session.username)
        .await
    {
        tracing::warn!("register_cp_session failed for {}: {}", uuid, e);
    }

    // 4) Generate the SAME RDP content you already use
    let rdp = match generate_rdp_file(&uuid, &jump_host_ip, Some(3389)) {
        Ok(c) => c,
        Err(e) => {
            tracing::error!("Failed to generate RDP file for {}: {}", uuid, e);
            return Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to generate RDP file".to_string(),
            ));
        }
    };

    let filename = format!("session-{}.rdp", uuid);
    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/rdp")
        .header(
            header::CONTENT_DISPOSITION,
            format!("attachment; filename=\"{}\"", filename),
        )
        .body(rdp.into())
        .unwrap())
}

/// Normal RDP download (unchanged)
pub async fn download_rdp_file(
    State(state): State<Arc<AppState>>,
    Path(uuid): Path<Uuid>,
) -> Result<Response, (StatusCode, String)> {
    prepare_rdp_response(&state, uuid).await
}

/// Web-as-RDP download (identical file; CJ switches to WEB after resolve)
pub async fn download_rdp_file_for_web(
    State(state): State<Arc<AppState>>,
    Path(uuid): Path<Uuid>,
) -> Result<Response, (StatusCode, String)> {
    prepare_rdp_response(&state, uuid).await
}
