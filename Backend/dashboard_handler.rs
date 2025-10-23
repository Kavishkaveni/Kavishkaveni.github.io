use axum::{routing::get, http::StatusCode, extract::State, response::Json, Router};
use serde::Serialize;
use std::sync::Arc;
use crate::AppState;

#[derive(Serialize)]
struct RecentSession {
    user: String,
    device: String,
    protocol: String,
    status: String,
    start_time: String,
}

#[derive(Serialize)]
struct DashboardSummary {
    active_sessions: usize,
    total_devices: usize,
    recent_sessions: Vec<RecentSession>,
}

async fn get_dashboard_summary(
    State(state): State<Arc<AppState>>,
) -> Result<Json<DashboardSummary>, (StatusCode, String)> {
    // Get sessions + devices
    let sessions = state.session_service
        .list_sessions(None)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("sessions error: {e}")))?;

    let devices = state.device_service
        .list_devices(None)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("devices error: {e}")))?;

    // Count active sessions
    let active = sessions.iter().filter(|s| s.status.eq_ignore_ascii_case("Active")).count();

    // Take last 5 sessions (sorted by start_time)
    let mut recent: Vec<_> = sessions.clone();
    recent.sort_by(|a, b| b.start_time.cmp(&a.start_time));
    let recent_sessions: Vec<RecentSession> = recent.into_iter()
        .take(5)
        .map(|s| RecentSession {
            user: s.username,
            device: s.device_name,
            protocol: s.protocol,
            status: s.status,
            start_time: s.start_time.to_rfc3339(),
        })
        .collect();

    Ok(Json(DashboardSummary {
        active_sessions: active,
        total_devices: devices.len(),
        recent_sessions,
    }))
}

pub fn dashboard_routes() -> Router<Arc<AppState>> {
    Router::new().route("/dashboard", get(get_dashboard_summary))
}
