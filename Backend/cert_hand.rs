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
        // CSR Operations
        .route("/certificate/csr", post(create_csr).get(list_csrs))
        .route("/certificate/csr/:id/download", get(download_csr))
        .route("/certificate/csr/:id/delete", delete(delete_csr))

        // Certificate Operations
        .route("/certificate/selfsign/:id", post(create_self_signed_certificate))
        .route("/certificate/selfsign/upload", post(upload_and_selfsign_certificate))
        .route("/certificate/list", get(list_certificates))
        .route("/certificate/:id/view", get(view_certificate))
        .route("/certificate/:id/delete", delete(delete_certificate))
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
        Ok(()) => Ok(Json(serde_json::json!({
            "message": "Certificate created successfully"
        }))),
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

    // Decode base64 -> CSR PEM
    let csr_bytes = match base64::decode(&csr_b64) {
        Ok(b) => b,
        Err(_) => return Err((StatusCode::BAD_REQUEST, "Invalid base64 CSR".into())),
    };
    let csr_pem = match String::from_utf8(csr_bytes) {
        Ok(s) => s,
        Err(_) => return Err((StatusCode::BAD_REQUEST, "CSR not UTF-8".into())),
    };

    // Generate certificate directly
    match state
        .certificate_service
        .create_self_signed_from_file(csr_pem, cert_name)
        .await
    {
        Ok(()) => Ok(Json(serde_json::json!({
            "message": "Certificate created successfully"
        }))),
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
                    "serial_number": r.serial_number,
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
// VIEW CERTIFICATE (RETURN PEM TEXT)
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

    Ok((StatusCode::OK, cert.cert_pem.unwrap_or_default()))
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
