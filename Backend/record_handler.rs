use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    routing::{get, post, put, delete},
    Router,
};

use axum::response::IntoResponse;
use tokio::fs::File;
use tokio_util::io::ReaderStream;
use hyper::header::{self, HeaderValue};

use axum::extract::DefaultBodyLimit;
use serde::Deserialize;
use validator::Validate;
use std::sync::Arc;
use chrono::{DateTime, Utc};
use openssl::pkey::PKey;
use openssl::rsa::Padding;

use crate::models::{CreateRecordingRequest, UpdateRecordingRequest, RecordingResponse};
use crate::AppState;

#[derive(Debug, Deserialize)]
pub struct RecordingQuery {
    status: Option<String>,
    device_name: Option<String>,
    date_from: Option<DateTime<Utc>>,
    date_to: Option<DateTime<Utc>>,
    pub search: Option<String>,
}

pub fn recording_routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/recordings", get(list_recordings).post(create_recording))
        .route("/recordings/:id", get(get_recording).put(update_recording).delete(delete_recording))
        .route("/recordings/search", get(search_recordings))
        .route("/upload", post(upload_recording).layer(DefaultBodyLimit::max(1_000_000_000)))
        .route("/recordings/end", post(update_recording_end))
        .route("/recordings/start", post(start_recording))
        .route("/recordings/:id/download", get(download_recording))
        .route("/recordings/:id/stream", get(stream_recording))
        .route("/recordings/keys", get(get_recording_keys))
        .route("/recordings/privateKey", get(get_recording_private_key))
}

pub async fn list_recordings(
    State(state): State<Arc<AppState>>,
    Query(query): Query<RecordingQuery>,
) -> Result<Json<Vec<RecordingResponse>>, (StatusCode, String)> {
    match state
    .recording_service
    .list_recordings(query.status.as_deref(), query.search.as_deref())
    .await {
        Ok(recordings) => Ok(Json(recordings)),
        Err(e) => {
            tracing::error!("Failed to list recordings: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to retrieve recordings".to_string()))
        }
    }
}

pub async fn get_recording(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<Json<RecordingResponse>, (StatusCode, String)> {
    match state.recording_service.get_recording(id).await {
        Ok(Some(recording)) => Ok(Json(recording)),
        Ok(None) => Err((StatusCode::NOT_FOUND, "Recording not found".to_string())),
        Err(e) => {
            tracing::error!("Failed to get recording {}: {}", id, e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to retrieve recording".to_string()))
        }
    }
}

pub async fn create_recording(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CreateRecordingRequest>,
) -> Result<Json<RecordingResponse>, (StatusCode, String)> {
    if let Err(e) = request.validate() {
        return Err((StatusCode::BAD_REQUEST, format!("Validation error: {}", e)));
    }

    match state.recording_service.create_recording(request).await {
        Ok(recording) => Ok(Json(recording)),
        Err(e) => {
            tracing::error!("Failed to create recording: {}", e);
            if e.to_string().contains("Session not found") {
                Err((StatusCode::BAD_REQUEST, "Session not found".to_string()))
            } else {
                Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to create recording".to_string()))
            }
        }
    }
}

pub async fn update_recording(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
    Json(request): Json<UpdateRecordingRequest>,
) -> Result<Json<RecordingResponse>, (StatusCode, String)> {
    if let Err(e) = request.validate() {
        return Err((StatusCode::BAD_REQUEST, format!("Validation error: {}", e)));
    }

    match state.recording_service.update_recording(id, request).await {
        Ok(Some(recording)) => Ok(Json(recording)),
        Ok(None) => Err((StatusCode::NOT_FOUND, "Recording not found".to_string())),
        Err(e) => {
            tracing::error!("Failed to update recording {}: {}", id, e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to update recording".to_string()))
        }
    }
}

pub async fn delete_recording(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<StatusCode, (StatusCode, String)> {
    match state.recording_service.delete_recording(id).await {
        Ok(true) => Ok(StatusCode::NO_CONTENT),
        Ok(false) => Err((StatusCode::NOT_FOUND, "Recording not found".to_string())),
        Err(e) => {
            tracing::error!("Failed to delete recording {}: {}", id, e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to delete recording".to_string()))
        }
    }
}

pub async fn search_recordings(
    State(state): State<Arc<AppState>>,
    Query(query): Query<RecordingQuery>,
) -> Result<Json<Vec<RecordingResponse>>, (StatusCode, String)> {
    match state.recording_service.search_recordings(
        query.device_name.as_deref(),
        query.date_from,
        query.date_to
    ).await {
        Ok(recordings) => Ok(Json(recordings)),
        Err(e) => {
            tracing::error!("Failed to search recordings: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to search recordings".to_string()))
        }
    }
}

use axum::{body::Bytes, http::HeaderMap};
use std::{fs, path::PathBuf};

pub async fn upload_recording(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<String, (StatusCode, String)> {

    tracing::error!("UPLOAD HEADERS = {:?}", headers);

    // --- UUID ---
    let uuid_header = headers.get("X-UUID");
tracing::error!("[UPLOAD] uuid header = {:?}", uuid_header);

let uuid_str = uuid_header
    .and_then(|v| v.to_str().ok())
    .ok_or((StatusCode::BAD_REQUEST, "Missing X-UUID header".to_string()))?;

    // --- filename optional ---
    let file_name = headers
        .get("X-Filename")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("session.mp4");

    // encrypted AES only
let enc_aes_b64 = headers.get("X-AESKEY").and_then(|v| v.to_str().ok());
let mut enc_aes_key: Option<Vec<u8>> = None;


if let Some(a) = enc_aes_b64 {
    if let Ok(a2) = base64::decode(a) {
        enc_aes_key = Some(a2);
        tracing::error!("[UPLOAD] AES base64 header = {:?}", enc_aes_b64);
    }
}

    // SAVE file
    let mut save_dir = PathBuf::from(r"C:\REC");
    fs::create_dir_all(&save_dir).ok();
    let full_name = format!("{}_{}", uuid_str, file_name);
    save_dir.push(&full_name);

    tracing::error!("[UPLOAD] About to write file: {}", save_dir.to_string_lossy());
tracing::error!("[UPLOAD] body_len = {}", body.len());

    fs::write(&save_dir, &body)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("write failed: {e}")))?;

    // update DB
    let path_str = save_dir.to_string_lossy().to_string();
    let size = body.len() as i64;

    let uuid = uuid::Uuid::parse_str(uuid_str)
        .map_err(|_| (StatusCode::BAD_REQUEST, "Bad UUID".to_string()))?;

    state.recording_service.set_file_info_by_uuid(uuid, &path_str, size).await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("DB update failed: {e}")))?;

    state.recording_service.update_ticket_info_for_recording(uuid).await.ok();

    Ok(format!("Saved {}", path_str))
}


// --- NEW: handle POST /api/recordings/end ---

#[derive(Debug, Deserialize)]
struct RecordingEndRequest {
    uuid: String,
    start_time: Option<String>,
    end_time: Option<String>,
}

pub async fn update_recording_end(
    State(state): State<Arc<AppState>>,
    Json(body): Json<RecordingEndRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    tracing::info!("Received /recordings/end: {:?}", body);

    // Call the service method (we will add it in RecordingService.rs next)
    match state
        .recording_service
        .update_recording_end(
            &body.uuid,
            body.start_time.clone(),
            body.end_time.clone(),
            None, // we’ll pass real file size later if needed
        )
        .await
    {
        Ok(_) => Ok(StatusCode::OK),
        Err(e) => {
            tracing::error!("Failed to update recording end: {}", e);
            Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to update recording".to_string(),
            ))
        }
    }
}

#[derive(Debug, Deserialize)]
struct RecordingStartRequest {
    uuid: String,
}

pub async fn start_recording(
    State(state): State<Arc<AppState>>,
    Json(body): Json<RecordingStartRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    tracing::info!("Received /recordings/start: {:?}", body);

    let req = CreateRecordingRequest {
    session_uuid: uuid::Uuid::parse_str(&body.uuid)
        .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid UUID".to_string()))?,
    file_path: None,
    duration: None,
    file_size: None,
    status: Some("Processing".to_string()),
};

    match state.recording_service.create_recording(req).await {
        Ok(_) => Ok(StatusCode::OK),
        Err(e) => {
            tracing::error!("Failed to create recording at start: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to create recording".to_string()))
        }
    }
}


pub async fn download_recording(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> impl IntoResponse {
    let rec = match state.recording_service.get_recording(id).await {
        Ok(Some(r)) => r,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let Some(path) = rec.file_path else {
        return StatusCode::NOT_FOUND.into_response();
    };

    let filename = std::path::Path::new(&path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("recording.mp4");

    let file = match File::open(&path).await {
        Ok(f) => f,
        Err(_) => return StatusCode::NOT_FOUND.into_response(),
    };

    let stream = ReaderStream::new(file);

    (
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, HeaderValue::from_static("video/mp4")),
            (
                header::CONTENT_DISPOSITION,
                HeaderValue::from_str(&format!("attachment; filename=\"{}\"", filename)).unwrap(),
            ),
        ],
        axum::body::Body::from_stream(stream),
    )
        .into_response()
}

/// GET /api/recordings/:id/stream
pub async fn stream_recording(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> impl IntoResponse {
    let rec = match state.recording_service.get_recording(id).await {
        Ok(Some(r)) => r,
        _ => return StatusCode::NOT_FOUND.into_response(),
    };

    let Some(path) = rec.file_path else {
        return StatusCode::NOT_FOUND.into_response();
    };

    let file = match tokio::fs::File::open(&path).await {
        Ok(f) => f,
        Err(_) => return StatusCode::NOT_FOUND.into_response(),
    };
    let stream = ReaderStream::new(file);

    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, HeaderValue::from_static("video/mp4"))],
        axum::body::Body::from_stream(stream),
    )
        .into_response()
}

use serde_json::json;


pub async fn get_recording_keys(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {

    // 1) get public key
    let public_key = match state.vault_service.get_public_key_for_recordings().await {
        Ok(Some(pk)) => pk,
        _ => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    // 2) get encrypted aes_key_enc
    let aes_key_enc: Option<String> = match sqlx::query_scalar!(
        "SELECT aes_key_enc FROM certificates WHERE certificate_name='Recordings' LIMIT 1"
    )
    .fetch_optional(&state.device_service.pool)
    .await
    {
        Ok(v) => v.flatten(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    if aes_key_enc.is_none() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    // 3) get private key to decrypt
    let private_key_pem = match state.vault_service.get_private_key_for_vault("Recordings").await {
        Ok(Some(pk)) => pk,
        _ => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    // 4) decrypt AES
    let rsa_priv = PKey::private_key_from_pem(private_key_pem.as_bytes()).unwrap().rsa().unwrap();
    let enc_bytes = base64::decode(aes_key_enc.unwrap()).unwrap();
    let mut out = vec![0; rsa_priv.size() as usize];
    let len = rsa_priv.private_decrypt(&enc_bytes, &mut out, Padding::PKCS1).unwrap();
    let aes_raw = &out[..len];

    // 5) return RAW AES base64
    let aes_raw_b64 = base64::encode(aes_raw);

    let body = json!({
        "public_key": public_key,
        "aes_key": aes_raw_b64
    });

    (StatusCode::OK, Json(body)).into_response()
}

pub async fn get_recording_private_key(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    match state.recording_service.get_recordings_private_key().await {
        Ok(Some(pk)) => (StatusCode::OK, pk).into_response(),
        _ => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}
