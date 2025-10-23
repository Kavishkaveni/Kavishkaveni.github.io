use axum::{extract::State, http::StatusCode, response::Json, routing::get, Router};
use serde::Serialize;
use std::sync::Arc;

use crate::services::report_service::{ReportStats, ReportService};
use crate::AppState;

#[derive(Serialize)]
pub struct ConnectionTypes {
    ssh: f64,
    rdp: f64,
    web: f64,
    multissh: f64,
}

pub fn report_routes() -> Router<Arc<AppState>> {
    Router::new().route("/reports", get(get_reports))
}

pub async fn get_reports(
    State(state): State<Arc<AppState>>,
) -> Result<Json<ReportStats>, StatusCode> {
    let stats = state.report_service.get_report_stats().await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(stats))
}
