use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use chrono::{DateTime, Utc};
use uuid::Uuid;
use validator::Validate;

#[derive(Debug, Serialize, Deserialize, FromRow, Clone)]
pub struct Session {
    pub id: i32,
    pub uuid: Uuid,
    pub device_id: i32,
    pub protocol: String,
    pub username: String,
    pub status: String,
    pub start_time: DateTime<Utc>,
    pub end_time: Option<DateTime<Utc>>,
    pub user_identity: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize, Validate)]
pub struct CreateSessionRequest {
    pub device_id: i32,
    #[validate(custom(function = "validate_protocol"))]
    pub protocol: String,
    #[validate(length(min = 1, max = 255))]
    pub username: String,
    pub user_identity: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SessionResponse {
    pub id: i32,
    pub uuid: String,
    pub device_id: i32,
    pub device_name: String,
    pub device_ip: String,
    pub protocol: String,
    pub username: String,
    pub status: String,
    pub start_time: DateTime<Utc>,
    pub end_time: Option<DateTime<Utc>>,
    pub duration: Option<String>, // Human readable duration
    pub user_identity: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SessionDetailResponse {
    pub uuid: String,
    pub device_id: i32,
    pub device_name: String,
    pub device_ip: String,
    pub protocol: String,
    pub username: String,
    pub encrypted_password: String, // For agent consumption
    pub status: String,
    pub start_time: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EndSessionRequest {
    pub end_time: Option<DateTime<Utc>>,
    pub status: Option<String>, // 'Ended' or 'Failed'
}

fn validate_protocol(protocol: &str) -> Result<(), validator::ValidationError> {
    // accept common spellings, case-insensitive
    match protocol.to_ascii_uppercase().as_str() {
        "SSH" | "RDP" | "WEB" | "HTTPS" | "CHROME" => Ok(()),
        _ => Err(validator::ValidationError::new("invalid_protocol")),
    }
}

impl From<Session> for SessionResponse {
    fn from(session: Session) -> Self {
        let duration = if let Some(end_time) = session.end_time {
            let duration = end_time.signed_duration_since(session.start_time);
            let hours = duration.num_hours();
            let minutes = duration.num_minutes() % 60;
            if hours > 0 {
                Some(format!("{}h {}m", hours, minutes))
            } else {
                Some(format!("{}m", minutes))
            }
        } else {
            // Calculate current duration for active sessions
            let duration = Utc::now().signed_duration_since(session.start_time);
            let hours = duration.num_hours();
            let minutes = duration.num_minutes() % 60;
            if hours > 0 {
                Some(format!("{}h {}m", hours, minutes))
            } else {
                Some(format!("{}m", minutes))
            }
        };

        Self {
            id: session.id,
            uuid: session.uuid.to_string(),
            device_id: session.device_id,
            device_name: String::new(), // filled by service layer
            device_ip: String::new(),   // filled by service layer
            protocol: session.protocol,
            username: session.username,
            status: session.status,
            start_time: session.start_time,
            end_time: session.end_time,
            duration,
            user_identity: session.user_identity,
        }
    }
}
