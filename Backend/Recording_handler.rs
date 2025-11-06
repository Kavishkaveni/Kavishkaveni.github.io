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
// 1) Read session UUID and optional filename from headers
// mandatory UUID
let uuid_str = headers
    .get("X-UUID")
    .and_then(|v| v.to_str().ok())
    .ok_or((StatusCode::BAD_REQUEST, "Missing X-UUID header".to_string()))?;

// optional filename
let file_name = headers
    .get("X-Filename")
    .and_then(|v| v.to_str().ok())
    .unwrap_or("session.mp4");

// NEW: encrypted AES key and IV from C++ recorder
let enc_aes_b64 = headers
    .get("X-AESKEY")
    .and_then(|v| v.to_str().ok());

let iv_b64 = headers
    .get("X-IV")
    .and_then(|v| v.to_str().ok());

// log only — we will decode & decrypt later
tracing::info!(
    "upload_recording: uuid={}, file={}, aes_b64={}, iv_b64={}",
    uuid_str,
    file_name,
    enc_aes_b64.is_some(),
    iv_b64.is_some()
);

    // 2) Build target folder and full path: C:\REC\<uuid>_<filename>
    let mut save_dir = PathBuf::from(r"C:\REC");
    if let Err(e) = fs::create_dir_all(&save_dir) {
        return Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Create dir failed: {e}")));
    }

    let full_name = format!("{}_{}", uuid_str, file_name);
    save_dir.push(&full_name);

    // 3) Write the bytes to disk
    if let Err(e) = fs::write(&save_dir, &body) {
        return Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Write failed: {e}")));
    }

    // 4) Update DB -> file_path + file_size for this session_uuid
    let path_str = save_dir.to_string_lossy().to_string();
    let size = body.len() as i64;

    let uuid =
        uuid::Uuid::parse_str(uuid_str).map_err(|_| (StatusCode::BAD_REQUEST, "Bad UUID".to_string()))?;

    if let Err(e) = state
        .recording_service
        .set_file_info_by_uuid(uuid, &path_str, size)
        .await
    {
        return Err((StatusCode::INTERNAL_SERVER_ERROR, format!("DB update failed: {e}")));
    }

    // Link task_number & chg_number from session_tickets automatically
if let Err(e) = state
    .recording_service
    .update_ticket_info_for_recording(uuid)
    .await
{
    tracing::warn!("Failed to link task/change numbers for recording: {}", e);
}

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


