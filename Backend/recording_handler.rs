use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    routing::{get, post, put, delete},
    Router,
};

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
}

pub fn recording_routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/recordings", get(list_recordings).post(create_recording))
        .route("/recordings/:id", get(get_recording).put(update_recording).delete(delete_recording))
        .route("/recordings/search", get(search_recordings))
        .route("/upload", post(upload_recording).layer(DefaultBodyLimit::max(1_000_000_000)))
}

pub async fn list_recordings(
    State(state): State<Arc<AppState>>,
    Query(query): Query<RecordingQuery>,
) -> Result<Json<Vec<RecordingResponse>>, (StatusCode, String)> {
    match state.recording_service.list_recordings(query.status.as_deref()).await {
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
    State(_state): State<Arc<AppState>>,   // we don't touch DB here
    headers: HeaderMap,
    body: Bytes,
) -> Result<String, (StatusCode, String)> {
    // Read optional headers for naming
    let uuid = headers.get("X-UUID").and_then(|v| v.to_str().ok()).unwrap_or("no-uuid");
    let session_id = headers.get("X-Session").and_then(|v| v.to_str().ok()).unwrap_or("no-session");

    // Ensure save folder exists
    let mut save_dir = PathBuf::from(r"C:\REC");
    if let Err(e) = fs::create_dir_all(&save_dir) {
        return Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Create dir failed: {e}")));
    }

    // Build filename and write
    let filename = format!("{}_{}.mp4", uuid, session_id);
    save_dir.push(&filename);

    if let Err(e) = fs::write(&save_dir, &body) {
        return Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Write failed: {e}")));
    }

    Ok("Upload saved to C:\\REC".to_string())
}
