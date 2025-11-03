use axum::{
    extract::{State, Path, Json},
    http::StatusCode,
    routing::{get, post, delete},
    Router,
};
use std::sync::Arc;
use hyper::{HeaderMap, header::HeaderValue};

use crate::AppState;
use crate::models::certificate::{CreateCSRRequest, CSRResponse};

// ----------------------------------------------------
// ROUTES
// ----------------------------------------------------
pub fn certificate_routes() -> Router<Arc<AppState>> {
    Router::new()
        // CSR
        .route("/certificate/csr", post(create_csr).get(list_csrs))
        .route("/certificate/csr/:id/download", get(download_csr))
        .route("/certificate/csr/:id/delete", delete(delete_csr))
        // Certs
        .route("/certificate/selfsign/:id", post(create_self_signed_certificate))
        .route("/certificate/selfsign/upload", post(upload_and_selfsign_certificate))
        .route("/certificate/list", get(list_certificates))
        .route("/certificate/:id/view", get(view_certificate))
        .route("/certificate/:id/download", get(download_certificate))   
        .route("/certificate/:id/delete", delete(delete_certificate))

        .route("/certificate/link", post(create_certificate_link))
        .route("/certificate/links", get(list_certificate_links))
        .route("/certificate/link/:id/delete", delete(delete_certificate_link))
}

// ----------------------------------------------------
// CREATE CSR
// ----------------------------------------------------
pub async fn create_csr(
    State(state): State<Arc<AppState>>,
    Json(req): Json<CreateCSRRequest>,
) -> Result<Json<CSRResponse>, (StatusCode, String)> {
    match state.certificate_service.create_csr(req).await {
        Ok(csr) => Ok(Json(csr)),
        Err(e) => {
            tracing::error!("Failed to create CSR: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to create CSR: {}", e)))
        }
    }
}

// ----------------------------------------------------
// LIST ALL CSRs
// ----------------------------------------------------
pub async fn list_csrs(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<CSRResponse>>, (StatusCode, String)> {
    match state.certificate_service.list_csrs().await {
        Ok(csrs) => Ok(Json(csrs)),
        Err(e) => {
            tracing::error!("Failed to list CSRs: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to retrieve CSRs".to_string()))
        }
    }
}

// ----------------------------------------------------
// DOWNLOAD CSR FILE
// ----------------------------------------------------
pub async fn download_csr(
    Path(id): Path<i32>,
    State(state): State<Arc<AppState>>,
) -> Result<(HeaderMap, Vec<u8>), (StatusCode, String)> {
    let csr = sqlx::query!(
        "SELECT csr_text FROM certificate_requests WHERE id = $1",
        id
    )
    .fetch_one(state.certificate_service.get_pool())
    .await
    .map_err(|e| (StatusCode::NOT_FOUND, e.to_string()))?;

    let mut headers = HeaderMap::new();
    headers.insert(
        "Content-Disposition",
        HeaderValue::from_str(&format!("attachment; filename=\"csr_{}.csr\"", id)).unwrap(),
    );
    headers.insert("Content-Type", HeaderValue::from_static("application/x-pem-file"));

    Ok((headers, csr.csr_text.unwrap_or_default().into_bytes()))
}

// ----------------------------------------------------
// DELETE CSR
// ----------------------------------------------------
pub async fn delete_csr(
    Path(id): Path<i32>,
    State(state): State<Arc<AppState>>,
) -> Result<(StatusCode, String), (StatusCode, String)> {
    match sqlx::query!("DELETE FROM certificate_requests WHERE id = $1", id)
        .execute(state.certificate_service.get_pool())
        .await
    {
        Ok(_) => Ok((StatusCode::OK, "CSR deleted successfully".to_string())),
        Err(e) => {
            tracing::error!("Failed to delete CSR: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
        }
    }
}

// ----------------------------------------------------
// CREATE SELF-SIGNED CERTIFICATE (FROM EXISTING CSR)
// ----------------------------------------------------
pub async fn create_self_signed_certificate(
    Path(csr_id): Path<i32>,
    State(state): State<Arc<AppState>>,
    Json(payload): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let cert_name = payload["certificate_name"]
        .as_str()
        .unwrap_or("Unnamed Certificate")
        .to_string();

    match state
        .certificate_service
        .create_self_signed_certificate(csr_id, cert_name)
        .await
    {
        Ok(()) => Ok(Json(serde_json::json!({ "message": "Certificate created successfully" }))),
        Err(e) => {
            tracing::error!("Failed to create self-signed certificate: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to create certificate: {}", e)))
        }
    }
}

// ----------------------------------------------------
// UPLOAD + SELF-SIGN (FROM FILE)
// ----------------------------------------------------
pub async fn upload_and_selfsign_certificate(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let csr_b64 = payload["csr_text"].as_str().unwrap_or("").trim().to_string();
    let cert_name = payload["certificate_name"].as_str().unwrap_or("").trim().to_string();

    if csr_b64.is_empty() || cert_name.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "csr_text or certificate_name missing".into()));
    }

    // decode base64 -> PEM
    let csr_bytes = base64::decode(&csr_b64).map_err(|_| (StatusCode::BAD_REQUEST, "Invalid base64 CSR".into()))?;
    let csr_pem = String::from_utf8(csr_bytes).map_err(|_| (StatusCode::BAD_REQUEST, "CSR not UTF-8".into()))?;

    match state
        .certificate_service
        .create_self_signed_from_file(csr_pem, cert_name)
        .await
    {
        Ok(()) => Ok(Json(serde_json::json!({ "message": "Certificate created successfully" }))),
        Err(e) => {
            tracing::error!("Failed to create self-signed certificate from file: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to create certificate: {}", e)))
        }
    }
}

// ----------------------------------------------------
// LIST ALL CERTIFICATES
// ----------------------------------------------------
pub async fn list_certificates(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<serde_json::Value>>, (StatusCode, String)> {
    match sqlx::query!(
        "SELECT id, certificate_name, csr_id, serial_number, issuer, issued_date, expiry_date, status
         FROM certificates ORDER BY issued_date DESC"
    )
    .fetch_all(state.certificate_service.get_pool())
    .await
    {
        Ok(rows) => {
            let list: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|r| serde_json::json!({
                    "id": r.id,
                    "certificate_name": r.certificate_name,
                    "csr_id": r.csr_id,
                    "serial_number": r.serial_number, // stays in API; your FE can ignore
                    "issuer": r.issuer,
                    "issued_date": r.issued_date,
                    "expiry_date": r.expiry_date,
                    "status": r.status
                }))
                .collect();
            Ok(Json(list))
        }
        Err(e) => {
            tracing::error!("List certificates failed: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
        }
    }
}

// ----------------------------------------------------
// VIEW CERTIFICATE (return PEM text)
// ----------------------------------------------------
pub async fn view_certificate(
    Path(id): Path<i32>,
    State(state): State<Arc<AppState>>,
) -> Result<(StatusCode, String), (StatusCode, String)> {
    let cert = sqlx::query!(
        "SELECT cert_pem FROM certificates WHERE id = $1",
        id
    )
    .fetch_one(state.certificate_service.get_pool())
    .await
    .map_err(|e| (StatusCode::NOT_FOUND, e.to_string()))?;

    Ok((StatusCode::OK, cert.cert_pem))
}

// ----------------------------------------------------
// DOWNLOAD CERTIFICATE (as attachment)
// ----------------------------------------------------
pub async fn download_certificate(
    Path(id): Path<i32>,
    State(state): State<Arc<AppState>>,
) -> Result<(HeaderMap, Vec<u8>), (StatusCode, String)> {
    let cert = sqlx::query!(
        "SELECT cert_pem FROM certificates WHERE id = $1",
        id
    )
    .fetch_one(state.certificate_service.get_pool())
    .await
    .map_err(|e| (StatusCode::NOT_FOUND, e.to_string()))?;

    let pem = cert.cert_pem.into_bytes();

    let mut headers = HeaderMap::new();
    headers.insert(
        "Content-Disposition",
        HeaderValue::from_str(&format!("attachment; filename=\"certificate_{}.pem\"", id)).unwrap(),
    );
    headers.insert("Content-Type", HeaderValue::from_static("application/x-pem-file"));

    Ok((headers, pem))
}

// ----------------------------------------------------
// DELETE CERTIFICATE
// ----------------------------------------------------
pub async fn delete_certificate(
    Path(id): Path<i32>,
    State(state): State<Arc<AppState>>,
) -> Result<(StatusCode, String), (StatusCode, String)> {
    match sqlx::query!("DELETE FROM certificates WHERE id = $1", id)
        .execute(state.certificate_service.get_pool())
        .await
    {
        Ok(_) => Ok((StatusCode::OK, "Certificate deleted successfully".to_string())),
        Err(e) => {
            tracing::error!("Failed to delete certificate: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
        }
    }
}

// ----------------------------------------------------
// CREATE LINK
// ----------------------------------------------------
pub async fn create_certificate_link(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let vault_id = payload["vault_id"].as_i64().map(|v| v as i32);
    let vault_name = payload["vault_name"].as_str().unwrap_or_default().to_string();
    let certificate_id = payload["certificate_id"].as_i64().map(|v| v as i32);
    let certificate_name = payload["certificate_name"].as_str().unwrap_or_default().to_string();

    sqlx::query!(
    "INSERT INTO certificate_vault_links (vault_id, vault_name, certificate_id, certificate_name, status)
     VALUES ($1, $2, $3, $4, 'Linked')",
    vault_id,
    vault_name,
    certificate_id,
    certificate_name
)
.execute(state.certificate_service.get_pool())
.await
.map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

// AFTER INSERT — update vault_groups
sqlx::query!(
    "UPDATE vault_groups SET certificate_id = $1 WHERE id = $2",
    certificate_id,
    vault_id
)
.execute(state.certificate_service.get_pool())
.await
.map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

Ok(Json(serde_json::json!({"message": "Link created successfully"})))
}

// ----------------------------------------------------
// LIST LINKS
// ----------------------------------------------------
pub async fn list_certificate_links(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<serde_json::Value>>, (StatusCode, String)> {
    match sqlx::query!(
        "SELECT id, vault_id, vault_name, certificate_id, certificate_name, status, linked_at 
         FROM certificate_vault_links ORDER BY linked_at DESC"
    )
    .fetch_all(state.certificate_service.get_pool())
    .await
    {
        Ok(rows) => {
            let list: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|r| serde_json::json!({
                    "id": r.id,
                    "vault_id": r.vault_id,
                    "vault_name": r.vault_name,
                    "certificate_id": r.certificate_id,
                    "certificate_name": r.certificate_name,
                    "status": r.status,
                    "linked_at": r.linked_at
                }))
                .collect();
            Ok(Json(list))
        }
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

// ----------------------------------------------------
// DELETE LINK
// ----------------------------------------------------
pub async fn delete_certificate_link(
    Path(id): Path<i32>,
    State(state): State<Arc<AppState>>,
) -> Result<(StatusCode, String), (StatusCode, String)> {
    match sqlx::query!("DELETE FROM certificate_vault_links WHERE id = $1", id)
        .execute(state.certificate_service.get_pool())
        .await
    {
        Ok(_) => Ok((StatusCode::OK, "Link deleted successfully".to_string())),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}
