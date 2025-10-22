use sqlx::{PgPool, FromRow};
use anyhow::Result;
use uuid::Uuid;
use std::net::IpAddr;
use chrono::{DateTime, Utc};
use crate::models::{Recording, RecordingResponse, CreateRecordingRequest, UpdateRecordingRequest};
use crate::services::SessionService;

#[derive(Debug, FromRow)]
struct RecordingWithSessionDevice {
    // Recording fields
    pub id: i32,
    pub session_uuid: Uuid,
    pub file_path: Option<String>,
    pub duration: Option<i32>,
    pub file_size: Option<i64>,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub start_time: Option<DateTime<Utc>>,
    pub end_time: Option<DateTime<Utc>>,
    // Session/Device fields (nullable now)
    pub username: Option<String>,
    pub protocol: Option<String>,
    pub device_name: Option<String>,
    pub device_ip: Option<IpAddr>,
    pub task_number: Option<String>,
    pub chg_number: Option<String>,
}

#[derive(Clone)]
pub struct RecordingService {
    pool: PgPool,
    session_service: SessionService,
}

impl RecordingService {

    // return the file_path for a recording id (download uses this)
pub async fn get_file_path(&self, id: i32) -> anyhow::Result<Option<String>> {
    let row = sqlx::query!("SELECT file_path FROM recordings WHERE id = $1", id)
        .fetch_optional(&self.pool)
        .await?;
    Ok(row.and_then(|r| r.file_path))
}

// set file_path + file_size by session UUID after we receive the upload
pub async fn set_file_info_by_uuid(
    &self,
    session_uuid: uuid::Uuid,
    file_path: &str,
    file_size: i64,
) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE recordings
         SET file_path = $2,
             file_size = $3,
             updated_at = NOW()
         WHERE session_uuid = $1",
        session_uuid,
        file_path,
        file_size
    )
    .execute(&self.pool)
    .await?;
    Ok(())
}

    pub async fn update_recording_end(
    &self,
    uuid: &str,
    start_time: Option<String>,
    end_time: Option<String>,
    file_size: Option<i64>,
) -> anyhow::Result<()> {
    let uuid = Uuid::parse_str(uuid)
        .map_err(|_| anyhow::anyhow!("Invalid UUID"))?;

    // --- Parse timestamps safely ---
    fn parse_dt(s: &str) -> anyhow::Result<DateTime<Utc>> {
        if let Ok(dt) = DateTime::parse_from_rfc3339(s) {
            Ok(dt.with_timezone(&Utc))
        } else {
            let naive = chrono::NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%S")?;
            Ok(DateTime::<Utc>::from_utc(naive, Utc))
        }
    }

    let start = if let Some(s) = &start_time { Some(parse_dt(s)?) } else { None };
    let end   = if let Some(s) = &end_time   { Some(parse_dt(s)?) } else { None };

    let duration_secs = if let (Some(s), Some(e)) = (start, end) {
        Some((e - s).num_seconds() as i32)
    } else {
        None
    };

    // --- Get session basic info ---
    let session = self.session_service
        .get_session_basic(&uuid)
        .await?
        .ok_or_else(|| anyhow::anyhow!("Session not found"))?;

    // --- Get device name ---
    let device: (String,) = sqlx::query_as(
        "SELECT name FROM devices WHERE id = $1"
    )
    .bind(session.device_id)
    .fetch_one(&self.pool)
    .await?;

    // --- Fetch task_number & chg_number from session_tickets ---
    let ticket_row = sqlx::query!(
        "SELECT task_number, chg_number FROM session_tickets WHERE session_uuid = $1 LIMIT 1",
        uuid
    )
    .fetch_optional(&self.pool)
    .await?;

    let (task_number, chg_number) = if let Some(row) = ticket_row {
        (row.task_number, row.chg_number)
    } else {
        (None, None)
    };

    // --- Update recordings table ---
    sqlx::query(
        "UPDATE recordings
         SET start_time  = COALESCE($2, start_time),
             end_time    = COALESCE($3, end_time),
             duration    = COALESCE($4, duration),
             file_size   = COALESCE($5, file_size),
             status      = 'Available',
             user_name   = COALESCE($6, user_name),
             device_name = COALESCE($7, device_name),
             protocol    = COALESCE($8, protocol),
             task_number = COALESCE($9, task_number),
             chg_number  = COALESCE($10, chg_number),
             updated_at  = NOW()
         WHERE session_uuid = $1"
    )
    .bind(uuid)
    .bind(start)
    .bind(end)
    .bind(duration_secs)
    .bind(file_size)
    .bind(session.username)
    .bind(device.0)
    .bind(session.protocol)
    .bind(task_number)
    .bind(chg_number)
    .execute(&self.pool)
    .await?;

    Ok(())
}

    pub fn new(pool: PgPool) -> Self {
        let session_service = SessionService::new(pool.clone());
        Self { pool, session_service }
    }

    pub async fn list_recordings(
    &self,
    status: Option<&str>,
    search: Option<&str>,
) -> Result<Vec<RecordingResponse>> {
    let mut query = String::from(
        "SELECT r.id, r.session_uuid, r.file_path, r.duration, r.file_size, r.status,
                r.created_at, r.updated_at,
                r.user_name as username,
                r.protocol,
                r.start_time,
                r.end_time,
                r.device_name,
                d.ip as device_ip,
                r.task_number,
                r.chg_number
         FROM recordings r
         LEFT JOIN devices d ON r.device_name = d.name
         WHERE 1=1"
    );

    let mut params: Vec<String> = Vec::new();
    let mut bind_index = 1;

    if let Some(status_filter) = status {
        query.push_str(&format!(" AND r.status = ${}", bind_index));
        params.push(status_filter.to_string());
        bind_index += 1;
    }

    if let Some(search_text) = search {
        query.push_str(&format!(
            " AND (r.task_number ILIKE ${} OR r.chg_number ILIKE ${})",
            bind_index, bind_index + 1
        ));
        params.push(format!("%{}%", search_text));
        params.push(format!("%{}%", search_text));
        bind_index += 2;
    }

    query.push_str(" ORDER BY r.created_at DESC");

    let mut qb = sqlx::query_as::<_, RecordingWithSessionDevice>(&query);
    for param in params {
        qb = qb.bind(param);
    }

    let recordings = qb.fetch_all(&self.pool).await?;

    Ok(recordings
        .into_iter()
        .map(|r| RecordingResponse {
            id: r.id,
            session_uuid: r.session_uuid.to_string(),
            session_id: format!("C{}", r.id),
            user: r.username.unwrap_or_default(),
            device_name: r.device_name.unwrap_or_default(),
            device_ip: r.device_ip.map(|ip| ip.to_string()).unwrap_or_default(),
            protocol: r.protocol.unwrap_or_default(),
            file_path: r.file_path,
            duration: r.duration.map(|d| d.to_string()),
            file_size: r.file_size.map(|s| s.to_string()),
            status: r.status,
            date: r.created_at,
            created_at: r.created_at,
            start_time: r.start_time,
            end_time: r.end_time,
            task_number: r.task_number,
            chg_number: r.chg_number,
        })
        .collect())
}

    pub async fn get_recording(&self, id: i32) -> Result<Option<RecordingResponse>> {
        let result = sqlx::query_as::<_, RecordingWithSessionDevice>(
           "SELECT r.id, r.session_uuid, r.file_path, r.duration, r.file_size, r.status,
            r.created_at, r.updated_at,
            r.user_name as username,
            r.protocol,
            r.device_name,
            d.ip as device_ip,
            r.start_time,
            r.end_time,
            r.task_number,
            r.chg_number
            FROM recordings r
            LEFT JOIN devices d ON r.device_name = d.name
            WHERE r.id = $1"
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(result.map(|r| RecordingResponse {
            id: r.id,
            session_uuid: r.session_uuid.to_string(),
            session_id: format!("C{}", r.id),
            user: r.username.unwrap_or_default(),
            device_name: r.device_name.unwrap_or_default(),
            device_ip: r.device_ip.map(|ip| ip.to_string()).unwrap_or_default(),
            protocol: r.protocol.unwrap_or_default(),
            file_path: r.file_path,
            duration: r.duration.map(|d| d.to_string()),
            file_size: r.file_size.map(|s| s.to_string()),
            status: r.status,
            date: r.created_at,
            created_at: r.created_at,
            start_time: r.start_time,
            end_time: r.end_time,
            task_number: r.task_number,
            chg_number: r.chg_number,
        }))
    }

    pub async fn create_recording(&self, request: CreateRecordingRequest) -> Result<RecordingResponse> {
    // Step 1: Get session basic info
    let session = self.session_service.get_session_basic(&request.session_uuid).await?
        .ok_or_else(|| anyhow::anyhow!("Session not found"))?;

    // Fetch ALL task/change numbers for this session_uuid
let ticket_rows = sqlx::query!(
    "SELECT task_number, chg_number FROM session_tickets WHERE session_uuid = $1",
    request.session_uuid
)
.fetch_all(&self.pool)
.await?;

// Combine them into comma-separated strings
let mut all_tasks: Vec<String> = Vec::new();
let mut all_changes: Vec<String> = Vec::new();

for row in ticket_rows {
    if let Some(t) = row.task_number {
        all_tasks.push(t);
    }
    if let Some(c) = row.chg_number {
        all_changes.push(c);
    }
}

let task_number = if all_tasks.is_empty() { None } else { Some(all_tasks.join(", ")) };
let chg_number  = if all_changes.is_empty() { None } else { Some(all_changes.join(", ")) };

    // Step 3: Insert recording including task_number & chg_number
    let recording = sqlx::query_as::<_, Recording>(
        "INSERT INTO recordings (session_uuid, file_path, duration, file_size, status, task_number, chg_number)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING *"
    )
    .bind(request.session_uuid)
    .bind(&request.file_path)
    .bind(request.duration)
    .bind(request.file_size)
    .bind(request.status.unwrap_or_else(|| "Processing".to_string()))
    .bind(task_number)
    .bind(chg_number)
    .fetch_one(&self.pool)
    .await?;

    // Step 4: Fetch related info for response
    let result = sqlx::query_as::<_, (Option<String>, Option<String>, Option<String>, Option<IpAddr>)>(
        "SELECT s.username, s.protocol, d.name as device_name, d.ip as device_ip
         FROM sessions s
         JOIN devices d ON s.device_id = d.id
         WHERE s.uuid = $1"
    )
    .bind(request.session_uuid)
    .fetch_one(&self.pool)
    .await?;

    //  Step 5: Build response
    let mut response = RecordingResponse::from(recording);
    response.user = result.0.unwrap_or_default();
    response.protocol = result.1.unwrap_or_default();
    response.device_name = result.2.unwrap_or_default();
    response.device_ip = result.3.map(|ip| ip.to_string()).unwrap_or_default();

    Ok(response)
}
    pub async fn update_recording(&self, id: i32, request: UpdateRecordingRequest) -> Result<Option<RecordingResponse>> {
        let mut set_clauses = Vec::new();
        let mut param_count = 1;

        if request.file_path.is_some() {
            set_clauses.push(format!("file_path = ${}", param_count));
            param_count += 1;
        }
        if request.duration.is_some() {
            set_clauses.push(format!("duration = ${}", param_count));
            param_count += 1;
        }
        if request.file_size.is_some() {
            set_clauses.push(format!("file_size = ${}", param_count));
            param_count += 1;
        }
        if request.status.is_some() {
            set_clauses.push(format!("status = ${}", param_count));
            param_count += 1;
        }

        if set_clauses.is_empty() {
            return self.get_recording(id).await;
        }

        set_clauses.push("updated_at = NOW()".to_string());

        let query = format!(
            "UPDATE recordings SET {} WHERE id = ${} RETURNING *",
            set_clauses.join(", "),
            param_count
        );

        let mut qb = sqlx::query_as::<_, Recording>(&query);
        if let Some(f) = request.file_path { qb = qb.bind(f); }
        if let Some(d) = request.duration { qb = qb.bind(d); }
        if let Some(s) = request.file_size { qb = qb.bind(s); }
        if let Some(st) = request.status { qb = qb.bind(st); }
        qb = qb.bind(id);

        let rec = qb.fetch_optional(&self.pool).await?;

        Ok(rec.map(|r| {
            let mut resp = RecordingResponse::from(r);
            resp
        }))
    }

    pub async fn delete_recording(&self, id: i32) -> Result<bool> {
        let res = sqlx::query("DELETE FROM recordings WHERE id = $1")
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(res.rows_affected() > 0)
    }

    pub async fn get_recordings_by_session(&self, session_uuid: &Uuid) -> Result<Vec<RecordingResponse>> {
        let rows = sqlx::query_as::<_, RecordingWithSessionDevice>(
            "SELECT r.id, r.session_uuid, r.file_path, r.duration, r.file_size, r.status,
            r.created_at, r.updated_at,
            r.user_name as username,
            r.protocol,
            r.device_name,
            d.ip as device_ip,
            r.start_time,
            r.end_time,
            r.task_number,
            r.chg_number
            FROM recordings r
            LEFT JOIN devices d ON r.device_name = d.name
            WHERE r.session_uuid = $1
            ORDER BY r.created_at DESC"
        )
        .bind(session_uuid)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows.into_iter().map(|r| RecordingResponse {
            id: r.id,
            session_uuid: r.session_uuid.to_string(),
            session_id: format!("C{}", r.id),
            user: r.username.unwrap_or_default(),
            device_name: r.device_name.unwrap_or_default(),
            device_ip: r.device_ip.map(|ip| ip.to_string()).unwrap_or_default(),
            protocol: r.protocol.unwrap_or_default(),
            file_path: r.file_path,
            duration: r.duration.map(|d| d.to_string()),
            file_size: r.file_size.map(|s| s.to_string()),
            status: r.status,
            date: r.created_at,
            created_at: r.created_at,
            start_time: r.start_time,
            end_time: r.end_time,
            task_number: r.task_number,
            chg_number: r.chg_number,
        }).collect())
    }

    pub async fn cleanup_old_recordings(&self, retention_days: i32) -> Result<usize> {
        let cutoff = chrono::Utc::now() - chrono::Duration::days(retention_days as i64);
        let res = sqlx::query(
            "DELETE FROM recordings WHERE created_at < $1 AND status = 'Archived'"
        )
        .bind(cutoff)
        .execute(&self.pool)
        .await?;
        Ok(res.rows_affected() as usize)
    }

    pub async fn search_recordings(
        &self,
        device_name: Option<&str>,
        date_from: Option<DateTime<Utc>>,
        date_to: Option<DateTime<Utc>>,
    ) -> Result<Vec<RecordingResponse>> {
        let mut query = "SELECT r.id, r.session_uuid, r.file_path, r.duration, r.file_size, r.status,
                 r.created_at, r.updated_at,
                 r.user_name as username,
                 r.protocol,
                 r.device_name,
                 d.ip as device_ip,
                 r.start_time,
                 r.end_time,
                 r.task_number,
                 r.chg_number
          FROM recordings r
          LEFT JOIN devices d ON r.device_name = d.name
          WHERE 1=1".to_string();

        let mut conditions: Vec<String> = Vec::new();
        let mut param_count = 1;

        if device_name.is_some() {
            conditions.push(format!("d.name ILIKE ${}", param_count));
            param_count += 1;
        }
        if date_from.is_some() {
            conditions.push(format!("r.created_at >= ${}", param_count));
            param_count += 1;
        }
        if date_to.is_some() {
            conditions.push(format!("r.created_at <= ${}", param_count));
            param_count += 1;
        }

        if !conditions.is_empty() {
            query.push_str(" AND ");
            query.push_str(&conditions.join(" AND "));
        }

        query.push_str(" ORDER BY r.created_at DESC");

        let mut qb = sqlx::query_as::<_, RecordingWithSessionDevice>(&query);

        if let Some(dn) = device_name {
            qb = qb.bind(format!("%{}%", dn));
        }
        if let Some(df) = date_from {
            qb = qb.bind(df);
        }
        if let Some(dt) = date_to {
            qb = qb.bind(dt);
        }

        let recs = qb.fetch_all(&self.pool).await?;

        Ok(recs.into_iter().map(|r| RecordingResponse {
            id: r.id,
            session_uuid: r.session_uuid.to_string(),
            session_id: format!("C{}", r.id),
            user: r.username.unwrap_or_default(),
            device_name: r.device_name.unwrap_or_default(),
            device_ip: r.device_ip.map(|ip| ip.to_string()).unwrap_or_default(),
            protocol: r.protocol.unwrap_or_default(),
            file_path: r.file_path,
            duration: r.duration.map(|d| d.to_string()),
            file_size: r.file_size.map(|s| s.to_string()),
            status: r.status,
            date: r.created_at,
            created_at: r.created_at,
            start_time: r.start_time,
            end_time: r.end_time,
            task_number: r.task_number,
            chg_number: r.chg_number,
        }).collect())
    }

    pub async fn update_ticket_info_for_recording(&self, session_uuid: Uuid) -> anyhow::Result<()> {
    // Fetch task_number & chg_number from session_tickets
    let ticket_row = sqlx::query!(
        "SELECT task_number, chg_number FROM session_tickets WHERE session_uuid = $1 LIMIT 1",
        session_uuid
    )
    .fetch_optional(&self.pool)
    .await?;

    if let Some(row) = ticket_row {
        sqlx::query!(
            "UPDATE recordings
             SET task_number = $2,
                 chg_number  = $3,
                 updated_at  = NOW()
             WHERE session_uuid = $1",
            session_uuid,
            row.task_number,
            row.chg_number
        )
        .execute(&self.pool)
        .await?;
    }

    Ok(())
}


}
