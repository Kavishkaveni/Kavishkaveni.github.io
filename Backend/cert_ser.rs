use anyhow::Result;
use sqlx::{PgPool, FromRow};
use chrono::Utc;

use crate::models::certificate::{CertificateSigningRequest, CreateCSRRequest, CSRResponse};
use openssl::x509::{X509NameBuilder, X509Req};
use openssl::pkey::PKey;
use openssl::rsa::Rsa;
use openssl::hash::MessageDigest;

#[derive(Clone)]
pub struct CertificateService {
    pool: PgPool,
}

impl CertificateService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    
    pub fn get_pool(&self) -> &PgPool {
        &self.pool
    }

    // ---------- CSR ----------
    pub async fn create_csr(&self, req: CreateCSRRequest) -> Result<CSRResponse> {
    //Generate Private Key
    let rsa = Rsa::generate(2048)?;                       // generate private key (2048-bit)
    let private_key_pem = rsa.private_key_to_pem()?;      // convert to PEM text format
    let pkey = PKey::from_rsa(rsa)?;

    // Build CSR Subject Details
    let mut name_builder = X509NameBuilder::new()?;
    name_builder.append_entry_by_text("CN", &req.common_name)?;
    name_builder.append_entry_by_text("O", &req.organization)?;
    name_builder.append_entry_by_text("OU", &req.org_unit)?;
    name_builder.append_entry_by_text("ST", &req.country)?;
    let name = name_builder.build();

    // Create CSR (Certificate Signing Request)
    let mut csr_builder = X509Req::builder()?;
    csr_builder.set_subject_name(&name)?;
    csr_builder.set_pubkey(&pkey)?;
    csr_builder.sign(&pkey, MessageDigest::sha256())?;

    // Convert CSR to PEM string
    let csr_pem = csr_builder.build().to_pem()?;
    let csr_text = String::from_utf8(csr_pem)?;

    // Save to database (only CSR + Private key)
    let csr = sqlx::query_as::<_, CertificateSigningRequest>(
        "INSERT INTO certificate_requests
        (common_name, organization, org_unit, country, validity_days, csr_text, private_key, created_at, status)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING id, common_name, organization, org_unit, country, validity_days, csr_text, created_at, status"
    )
    .bind(&req.common_name)
    .bind(&req.organization)
    .bind(&req.org_unit)
    .bind(&req.country)
    .bind(req.validity_days)
    .bind(&csr_text)
    .bind(&String::from_utf8(private_key_pem)?)
    .bind(Utc::now())
    .bind("active")
    .fetch_one(&self.pool)
    .await?;

    // Return Response
    Ok(CSRResponse {
        id: csr.id,
        common_name: csr.common_name,
        organization: csr.organization,
        org_unit: csr.org_unit,
        country: csr.country,
        created_at: csr.created_at,
        status: csr.status,
        validity_days: csr.validity_days,
    })
}
    // ---------- List of all CSRs ----------
pub async fn list_csrs(&self) -> Result<Vec<CSRResponse>> {
    let csrs = sqlx::query_as::<_, CertificateSigningRequest>(
        "SELECT id, common_name, organization, org_unit, country, validity_days, csr_text, created_at, status
         FROM certificate_requests
         ORDER BY created_at DESC"
    )
    .fetch_all(&self.pool)
    .await?;

    Ok(csrs
        .into_iter()
        .map(|c| CSRResponse {
            id: c.id,
            common_name: c.common_name,
            organization: c.organization,
            org_unit: c.org_unit,
            country: c.country,
            created_at: c.created_at,
            status: c.status,
            validity_days: c.validity_days,
        })
        .collect())
}
}
