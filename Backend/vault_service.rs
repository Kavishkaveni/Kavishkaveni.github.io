use anyhow::Result;
use chrono::{DateTime, Utc};
use sqlx::{FromRow, PgPool};
use std::net::IpAddr;

use openssl::pkey::PKey;
use openssl::rsa::Padding;

use crate::models::{
    CreateVaultEntryRequest, UpdateVaultEntryRequest, VaultEntry, VaultEntryResponse,
};
use crate::services::{DeviceService, SettingsService};
use crate::services::certificate_service::CertificateService;

#[derive(Debug, FromRow)]
struct VaultEntryWithDevice {
    // VaultEntry fields
    pub id: i32,
    pub device_id: i32,
    pub username: String,
    pub encrypted_password: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub group_id: Option<i32>,
    // Device fields
    pub device_name: String,
    pub device_ip: IpAddr,
}

#[derive(Clone)]
pub struct VaultService {
    pool: PgPool,
    device_service: DeviceService,
    certificate_service: CertificateService,
}

impl VaultService {
    // Constructor
    pub fn new(pool: PgPool, certificate_service: CertificateService) -> Self {
        let device_service = DeviceService::new(pool.clone());
        Self {
            pool,
            device_service,
            certificate_service,
        }
    }

    // List vault entries filtered by group_id
    pub async fn list_vault_entries_by_group(
        &self,
        group_id: Option<i32>,
    ) -> Result<Vec<VaultEntryResponse>> {
        let base = "SELECT v.id, v.device_id, v.username, v.encrypted_password, \
                    v.group_id, v.created_at, v.updated_at, \
                    d.name as device_name, d.ip as device_ip \
                    FROM vault v \
                    JOIN devices d ON v.device_id = d.id \
                    WHERE v.group_id = $1 \
                    ORDER BY d.name, v.username";

        let entries: Vec<VaultEntryWithDevice> =
            sqlx::query_as::<_, VaultEntryWithDevice>(base)
                .bind(group_id)
                .fetch_all(&self.pool)
                .await?;

        Ok(entries
            .into_iter()
            .map(|e| VaultEntryResponse {
                id: e.id,
                device_id: e.device_id,
                device_name: e.device_name,
                device_ip: e.device_ip.to_string(),
                username: e.username,
                group_id: e.group_id,
                created_at: e.created_at,
                updated_at: e.updated_at,
            })
            .collect())
    }

    // Admin-side list/read/write
    pub async fn list_vault_entries(
        &self,
        device_id: Option<i32>,
    ) -> Result<Vec<VaultEntryResponse>> {
        let base = "SELECT v.id, v.device_id, v.username, v.encrypted_password, \
            v.created_at, v.updated_at, v.group_id, \
            d.name as device_name, d.ip as device_ip \
            FROM vault v JOIN devices d ON v.device_id = d.id";

        let entries: Vec<VaultEntryWithDevice> = if let Some(did) = device_id {
            let q = format!("{base} WHERE v.device_id = $1 ORDER BY d.name, v.username");
            sqlx::query_as(&q).bind(did).fetch_all(&self.pool).await?
        } else {
            let q = format!("{base} ORDER BY d.name, v.username");
            sqlx::query_as(&q).fetch_all(&self.pool).await?
        };

        Ok(entries
            .into_iter()
            .map(|e| VaultEntryResponse {
                id: e.id,
                device_id: e.device_id,
                device_name: e.device_name,
                device_ip: e.device_ip.to_string(),
                username: e.username,
                group_id: e.group_id,
                created_at: e.created_at,
                updated_at: e.updated_at,
            })
            .collect())
    }

    pub async fn get_vault_entry(&self, id: i32) -> Result<Option<VaultEntryResponse>> {
        let q = "SELECT v.id, v.device_id, v.username, v.encrypted_password, v.created_at, v.updated_at, \
                 v.group_id, d.name as device_name, d.ip as device_ip \
                 FROM vault v JOIN devices d ON v.device_id = d.id WHERE v.id = $1";

        Ok(sqlx::query_as::<_, VaultEntryWithDevice>(q)
            .bind(id)
            .fetch_optional(&self.pool)
            .await?
            .map(|e| VaultEntryResponse {
                id: e.id,
                device_id: e.device_id,
                device_name: e.device_name,
                device_ip: e.device_ip.to_string(),
                username: e.username,
                group_id: e.group_id,
                created_at: e.created_at,
                updated_at: e.updated_at,
            }))
    }

    pub async fn create_vault_entry(
        &self,
        request: CreateVaultEntryRequest,
    ) -> Result<VaultEntryResponse> {
        let device = self
            .device_service
            .get_device_basic(request.device_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("Device not found"))?;

        let settings_service = SettingsService::new(self.pool.clone());
        let encryption_enabled = settings_service.is_encryption_enabled().await.unwrap_or(true);

        // ---------------------------------------------
// 1) find which certificate is attached to this vault-group
// ---------------------------------------------
let cert_row = sqlx::query!(
    "SELECT c.public_key
     FROM vault_groups vg
     JOIN certificates c ON vg.certificate_id = c.id
     WHERE vg.id = $1",
    request.group_id
)
.fetch_optional(&self.pool)
.await?;

let password_to_store = if let Some(row) = cert_row {
    let public_key_pem = row.public_key.unwrap_or_default();
    let public_key = PKey::public_key_from_pem(public_key_pem.as_bytes())?;

    let rsa = public_key.rsa()?;
    let mut buf = vec![0; rsa.size() as usize];
    let len = rsa.public_encrypt(request.password.as_bytes(), &mut buf, Padding::PKCS1)?;
    base64::encode(&buf[..len])
} else {
    request.password.clone()
};

        let entry = sqlx::query_as::<_, VaultEntry>(
            "INSERT INTO vault (device_id, username, encrypted_password, group_id) \
             VALUES ($1, $2, $3, $4) \
             ON CONFLICT (device_id, username) DO UPDATE \
             SET encrypted_password = EXCLUDED.encrypted_password, \
                 group_id = EXCLUDED.group_id, \
                 updated_at = NOW() \
             RETURNING *",
        )
        .bind(request.device_id)
        .bind(&request.username)
        .bind(&password_to_store)
        .bind(request.group_id)
        .fetch_one(&self.pool)
        .await?;

        let mut resp = VaultEntryResponse::from(entry);
        resp.device_name = device.name;
        resp.device_ip = device.ip.to_string();
        Ok(resp)
    }

    pub async fn update_vault_entry(
        &self,
        id: i32,
        request: UpdateVaultEntryRequest,
    ) -> Result<Option<VaultEntryResponse>> {
        let encrypted_password = if let Some(p) = &request.password {
            Some(p.clone())
        } else {
            None
        };

        let mut sets: Vec<&str> = Vec::new();
        if request.username.is_some() {
            sets.push("username = $1");
        }
        if request.password.is_some() {
            sets.push("encrypted_password = $2");
        }
        if sets.is_empty() {
            return self.get_vault_entry(id).await;
        }

        let set_sql = sets.join(", ") + ", updated_at = NOW()";
        let q = format!(
            "UPDATE vault SET {set_sql} WHERE id = ${} RETURNING *",
            if request.password.is_some() { 3 } else { 2 }
        );

        let mut qb = sqlx::query_as::<_, VaultEntry>(&q);
        if let Some(u) = &request.username {
            qb = qb.bind(u);
        } else {
            qb = qb.bind(sqlx::types::Json(serde_json::Value::Null));
        }
        if let Some(enc) = &encrypted_password {
            qb = qb.bind(enc);
        }

        qb = qb.bind(id);

        let entry = qb.fetch_optional(&self.pool).await?;
        if let Some(e) = entry {
            let device = self
                .device_service
                .get_device_basic(e.device_id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("Device not found"))?;
            let mut resp = VaultEntryResponse::from(e);
            resp.device_name = device.name;
            resp.device_ip = device.ip.to_string();
            Ok(Some(resp))
        } else {
            Ok(None)
        }
    }

    pub async fn delete_vault_entry(&self, id: i32) -> Result<bool> {
        Ok(sqlx::query("DELETE FROM vault WHERE id = $1")
            .bind(id)
            .execute(&self.pool)
            .await?
            .rows_affected()
            > 0)
    }

    // ---------- CP handler helpers ---------------------------

    pub async fn get_credentials_for_session(
        &self,
        device_id: i32,
        username: &str,
    ) -> Result<Option<String>> {
        let q = "SELECT encrypted_password FROM vault WHERE device_id = $1 AND username = $2";
        if let Some(enc) = sqlx::query_scalar::<_, String>(q)
            .bind(device_id)
            .bind(username)
            .fetch_optional(&self.pool)
            .await?
        {
            let decrypted = enc.clone();
            Ok(Some(decrypted))
        } else {
            Ok(None)
        }
    }

    pub async fn get_first_credentials_for_device(
        &self,
        device_id: i32,
    ) -> Result<Option<(String, String)>> {
        let q = "SELECT username, encrypted_password FROM vault \
                 WHERE device_id = $1 ORDER BY updated_at DESC, id ASC LIMIT 1";
        if let Some((username, enc_pass)) =
            sqlx::query_as::<_, (String, String)>(q)
                .bind(device_id)
                .fetch_optional(&self.pool)
                .await?
        {
            let decrypted = enc_pass.clone();
            Ok(Some((username, decrypted)))
        } else {
            Ok(None)
        }
    }
}

// ------------------- Vault Group Management -------------------

use crate::models::{VaultGroup, VaultGroupResponse, CreateVaultGroupRequest};

impl VaultService {
    pub async fn list_vault_groups(&self) -> Result<Vec<VaultGroupResponse>> {
        let groups = sqlx::query_as::<_, VaultGroup>(
            "SELECT id, name, certificate_id, created_at, updated_at FROM vault_groups ORDER BY created_at DESC"
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(groups.into_iter().map(|g| VaultGroupResponse {
            id: g.id,
            name: g.name,
            certificate_id: g.certificate_id,
            created_at: g.created_at,
            updated_at: g.updated_at,
        }).collect())
    }

    pub async fn create_vault_group(
        &self,
        request: CreateVaultGroupRequest,
    ) -> Result<VaultGroupResponse> {
        let group = sqlx::query_as::<_, VaultGroup>(
            "INSERT INTO vault_groups (name) VALUES ($1)
             RETURNING id, name, certificate_id, created_at, updated_at"
        )
        .bind(&request.name)
        .fetch_one(&self.pool)
        .await?;

        Ok(VaultGroupResponse {
            id: group.id,
            name: group.name,
            certificate_id: group.certificate_id,
            created_at: group.created_at,
            updated_at: group.updated_at,
        })
    }

    pub async fn delete_vault_group(&self, id: i32) -> Result<bool> {
        let res = sqlx::query("DELETE FROM vault_groups WHERE id = $1")
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(res.rows_affected() > 0)
    }
}
