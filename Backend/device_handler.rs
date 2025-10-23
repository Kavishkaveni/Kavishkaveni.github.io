use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    routing::{get, post, put, delete},
    Router,
};
use serde::Deserialize;
use validator::Validate;
use std::sync::Arc;

use crate::models::{CreateDeviceRequest, UpdateDeviceRequest, DeviceResponse};
use crate::services::DeviceService;
use crate::AppState;

#[derive(Debug, Deserialize)]
pub struct DeviceQuery {
    search: Option<String>,
}

pub fn device_routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/devices", get(list_devices).post(create_device))
        .route("/devices/:id", get(get_device).put(update_device).delete(delete_device))
}

pub async fn list_devices(
    State(state): State<Arc<AppState>>,
    Query(query): Query<DeviceQuery>,
) -> Result<Json<Vec<DeviceResponse>>, (StatusCode, String)> {
    match state.device_service.list_devices(query.search.as_deref()).await {
        Ok(devices) => Ok(Json(devices)),
        Err(e) => {
            tracing::error!("Failed to list devices: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to retrieve devices".to_string()))
        }
    }
}

pub async fn get_device(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<Json<DeviceResponse>, (StatusCode, String)> {
    match state.device_service.get_device(id).await {
        Ok(Some(device)) => Ok(Json(device)),
        Ok(None) => Err((StatusCode::NOT_FOUND, "Device not found".to_string())),
        Err(e) => {
            tracing::error!("Failed to get device {}: {}", id, e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to retrieve device".to_string()))
        }
    }
}

pub async fn create_device(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CreateDeviceRequest>,
) -> Result<Json<DeviceResponse>, (StatusCode, String)> {
    if let Err(e) = request.validate() {
        return Err((StatusCode::BAD_REQUEST, format!("Validation error: {}", e)));
    }

    match state.device_service.create_device(request).await {
        Ok(device) => {
    //  Log this event dynamically (no hardcoding)
    let _ = state.audit_service
        .log_action(
            "system",                  // temporary username; later we can replace with real logged-in user
            "Add Device",              // action name
            Some(&device.name),        // device name from DB
            Some("Device successfully added"),
        )
        .await;
    Ok(Json(device))
},
        Err(e) => {
            tracing::error!("Failed to create device: {}", e);
            if e.to_string().contains("duplicate key") {
                Err((StatusCode::CONFLICT, "Device name already exists".to_string()))
            } else {
                Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to create device".to_string()))
            }
        }
    }
}

pub async fn update_device(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
    Json(request): Json<UpdateDeviceRequest>,
) -> Result<Json<DeviceResponse>, (StatusCode, String)> {
    if let Err(e) = request.validate() {
        return Err((StatusCode::BAD_REQUEST, format!("Validation error: {}", e)));
    }

    match state.device_service.update_device(id, request).await {
        Ok(device) => {
    // Log this event dynamically (no hardcoding)
    let _ = state.audit_service
        .log_action(
            "system",                  // temporary username; later we can replace with real logged-in user
            "Update Device",              // action name
            Some(&device.as_ref().unwrap().name),        // device name from DB
            Some("Device successfully added"),
        )
        .await;
    Ok(Json(device.unwrap()))
},
        Ok(None) => Err((StatusCode::NOT_FOUND, "Device not found".to_string())),
        Err(e) => {
            tracing::error!("Failed to update device {}: {}", id, e);
            if e.to_string().contains("duplicate key") {
                Err((StatusCode::CONFLICT, "Device name already exists".to_string()))
            } else {
                Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to update device".to_string()))
            }
        }
    }
}

pub async fn delete_device(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<StatusCode, (StatusCode, String)> {
    match state.device_service.delete_device(id).await {
        Ok(true) => {
    let _ = state.audit_service
        .log_action(
            "system",
            "Delete Device",
            None,
            Some("Device successfully deleted"),
        )
        .await;
    Ok(StatusCode::NO_CONTENT)
},
        Ok(false) => Err((StatusCode::NOT_FOUND, "Device not found".to_string())),
        Err(e) => {
            tracing::error!("Failed to delete device {}: {}", id, e);
            if e.to_string().contains("foreign key") {
                Err((StatusCode::CONFLICT, "Cannot delete device with active sessions or vault entries".to_string()))
            } else {
                Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to delete device".to_string()))
            }
        }
    }
}
