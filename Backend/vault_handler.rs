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

use crate::models::{CreateVaultEntryRequest, UpdateVaultEntryRequest, VaultEntryResponse};
use crate::AppState;

#[derive(Debug, Deserialize)]
pub struct VaultQuery {
    device_id: Option<i32>,
}

pub fn vault_routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/vault", get(list_vault_entries).post(create_vault_entry))
        .route("/vault/:id", get(get_vault_entry).put(update_vault_entry).delete(delete_vault_entry))
}

pub async fn list_vault_entries(
    State(state): State<Arc<AppState>>,
    Query(query): Query<VaultQuery>,
) -> Result<Json<Vec<VaultEntryResponse>>, (StatusCode, String)> {
    match state.vault_service.list_vault_entries(query.device_id).await {
        Ok(entries) => Ok(Json(entries)),
        Err(e) => {
            tracing::error!("Failed to list vault entries: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to retrieve vault entries".to_string()))
        }
    }
}

pub async fn get_vault_entry(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<Json<VaultEntryResponse>, (StatusCode, String)> {
    match state.vault_service.get_vault_entry(id).await {
        Ok(Some(entry)) => Ok(Json(entry)),
        Ok(None) => Err((StatusCode::NOT_FOUND, "Vault entry not found".to_string())),
        Err(e) => {
            tracing::error!("Failed to get vault entry {}: {}", id, e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to retrieve vault entry".to_string()))
        }
    }
}

pub async fn create_vault_entry(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CreateVaultEntryRequest>,
) -> Result<Json<VaultEntryResponse>, (StatusCode, String)> {
    if let Err(e) = request.validate() {
        return Err((StatusCode::BAD_REQUEST, format!("Validation error: {}", e)));
    }

    match state.vault_service.create_vault_entry(request).await {
        Ok(entry) => Ok(Json(entry)),
        Err(e) => {
            tracing::error!("Failed to create vault entry: {}", e);
            if e.to_string().contains("Device not found") {
                Err((StatusCode::BAD_REQUEST, "Device not found".to_string()))
            } else {
                Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to create vault entry".to_string()))
            }
        }
    }
}

pub async fn update_vault_entry(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
    Json(request): Json<UpdateVaultEntryRequest>,
) -> Result<Json<VaultEntryResponse>, (StatusCode, String)> {
    if let Err(e) = request.validate() {
        return Err((StatusCode::BAD_REQUEST, format!("Validation error: {}", e)));
    }

    match state.vault_service.update_vault_entry(id, request).await {
        Ok(Some(entry)) => Ok(Json(entry)),
        Ok(None) => Err((StatusCode::NOT_FOUND, "Vault entry not found".to_string())),
        Err(e) => {
            tracing::error!("Failed to update vault entry {}: {}", id, e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to update vault entry".to_string()))
        }
    }
}

pub async fn delete_vault_entry(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<StatusCode, (StatusCode, String)> {
    match state.vault_service.delete_vault_entry(id).await {
        Ok(true) => Ok(StatusCode::NO_CONTENT),
        Ok(false) => Err((StatusCode::NOT_FOUND, "Vault entry not found".to_string())),
        Err(e) => {
            tracing::error!("Failed to delete vault entry {}: {}", id, e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to delete vault entry".to_string()))
        }
    }
}
