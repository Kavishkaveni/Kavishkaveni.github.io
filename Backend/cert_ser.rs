use anyhow::Result;
use sqlx::PgPool;
use chrono::{Utc, Duration};
use std::env;

use openssl::{
    asn1::Asn1Time,
    bn::BigNum,
    hash::MessageDigest,
    pkey::PKey,
    rsa::Rsa,
    x509::{
        extension::{AuthorityKeyIdentifier, BasicConstraints, KeyUsage, SubjectKeyIdentifier},
        X509Builder, X509NameBuilder, X509Req, X509,
    },
};

use crate::models::certificate::{CertificateSigningRequest, CreateCSRRequest, CSRResponse};

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

    // ------------------------------------------------------------------
    // CREATE CSR
    // ------------------------------------------------------------------
    pub async fn create_csr(&self, req: CreateCSRRequest) -> Result<CSRResponse> {
        // generate key
        let rsa = Rsa::generate(2048)?;
        let private_key_pem = rsa.private_key_to_pem()?;
        let pkey = PKey::from_rsa(rsa)?;

        // subject from request (all come from UI here)
        let mut name_builder = X509NameBuilder::new()?;
        name_builder.append_entry_by_text("CN", &req.common_name)?;
        name_builder.append_entry_by_text("O", &req.organization)?;
        name_builder.append_entry_by_text("OU", &req.org_unit)?;
        name_builder.append_entry_by_text("C", &req.country)?;
        let name = name_builder.build();

        // build CSR
        let mut csr_builder = X509Req::builder()?;
        csr_builder.set_subject_name(&name)?;
        csr_builder.set_pubkey(&pkey)?;
        csr_builder.sign(&pkey, MessageDigest::sha256())?;

        let csr_pem = csr_builder.build().to_pem()?;
        let csr_text = String::from_utf8(csr_pem)?;

        // persist
        let csr = sqlx::query_as::<_, CertificateSigningRequest>(
            r#"
            INSERT INTO certificate_requests
                (common_name, organization, org_unit, country, validity_days, csr_text, private_key, created_at, status)
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
            RETURNING id, common_name, organization, org_unit, country, validity_days, csr_text, created_at, status
            "#
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

    // ------------------------------------------------------------------
    // LIST ALL CSRs
    // ------------------------------------------------------------------
    pub async fn list_csrs(&self) -> Result<Vec<CSRResponse>> {
        let csrs = sqlx::query_as::<_, CertificateSigningRequest>(
            r#"
            SELECT id, common_name, organization, org_unit, country, validity_days, csr_text, created_at, status
            FROM certificate_requests
            ORDER BY created_at DESC
            "#
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

    // ------------------------------------------------------------------
    // CREATE SELF-SIGNED CERTIFICATE (from internal CSR row)
    // -> validity_days is taken from that CSR row (no hard-code)
    // ------------------------------------------------------------------
    pub async fn create_self_signed_certificate(
        &self,
        csr_id: i32,
        certificate_name: String,
    ) -> Result<(), anyhow::Error> {
        let csr_data = sqlx::query!(
            "SELECT csr_text, private_key, validity_days FROM certificate_requests WHERE id = $1",
            csr_id
        )
        .fetch_one(&self.pool)
        .await?;

        let csr_pem = csr_data.csr_text.ok_or_else(|| anyhow::anyhow!("CSR text missing"))?;
        let private_key_pem =
            csr_data.private_key.ok_or_else(|| anyhow::anyhow!("Private key missing"))?;
        let validity_days = csr_data.validity_days.unwrap_or(365);

        let csr = X509Req::from_pem(csr_pem.as_bytes())?;
        let pkey = PKey::private_key_from_pem(private_key_pem.as_bytes())?;

        let mut serial = BigNum::new()?;
        serial.pseudo_rand(64, openssl::bn::MsbOption::MAYBE_ZERO, false)?;
        let serial_number = serial.to_asn1_integer()?;

        let mut builder = X509Builder::new()?;
        builder.set_version(2)?;
        builder.set_serial_number(&serial_number)?;
        builder.set_subject_name(csr.subject_name())?;
        builder.set_issuer_name(csr.subject_name())?;
        builder.set_pubkey(&pkey)?;

        let not_before = Asn1Time::days_from_now(0)?;
        let not_after = Asn1Time::days_from_now(validity_days as u32)?;
        builder.set_not_before(&not_before)?;
        builder.set_not_after(&not_after)?;

        builder.append_extension(BasicConstraints::new().critical().build()?)?;
        builder.append_extension(KeyUsage::new().digital_signature().key_cert_sign().build()?)?;
        let subject_key_id =
            SubjectKeyIdentifier::new().build(&builder.x509v3_context(None, None))?;
        builder.append_extension(subject_key_id)?;
        let authority_key_id =
            AuthorityKeyIdentifier::new().keyid(true).build(&builder.x509v3_context(None, None))?;
        builder.append_extension(authority_key_id)?;

        builder.sign(&pkey, MessageDigest::sha256())?;

        let cert = builder.build();
        let cert_pem = cert.to_pem()?;
        let cert_pem_str = String::from_utf8(cert_pem)?;

        let issued_date = Utc::now();
        let expiry_date = issued_date + Duration::days(validity_days as i64);

        sqlx::query!(
            r#"
            INSERT INTO certificates
                (certificate_name, csr_id, serial_number, issuer, issued_date, expiry_date, cert_pem, status)
            VALUES ($1,$2,$3,$4,$5,$6,$7,'active')
            "#
            ,
            certificate_name,
            csr_id,
            serial_number.to_bn()?.to_dec_str()?.to_string(),
            "Self-Signed",
            issued_date,
            expiry_date,
            cert_pem_str
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    // ------------------------------------------------------------------
    // CREATE SELF-SIGNED FROM UPLOADED CSR (no hard-coded subject data)
    // Rules:
    // - Subject (CN/O/OU/C) parsed from CSR.
    // - validity_days picked in this order:
    //     1) match an existing CSR row with same subject -> use its validity_days
    //     2) env CERT_DEFAULT_VALIDITY_DAYS -> parse i64
    //     3) fallback 365
    // ------------------------------------------------------------------
    pub async fn create_self_signed_from_file(
        &self,
        csr_pem: String,
        certificate_name: String,
    ) -> Result<(), anyhow::Error> {
        let csr = X509Req::from_pem(csr_pem.as_bytes())?;
        let (cn, o, ou, c) = extract_subject(&csr)?;

        // Try to reuse validity_days from an existing CSR row with same subject
        let validity_days: i64 = {
            // attempt DB lookup
            if let Ok(row) = sqlx::query!(
                r#"
                SELECT validity_days
                FROM certificate_requests
                WHERE common_name = $1 AND organization = $2 AND org_unit = $3 AND country = $4
                ORDER BY created_at DESC
                LIMIT 1
                "#,
                cn,
                o,
                ou,
                c
            )
            .fetch_optional(&self.pool)
            .await
            {
                if let Some(r) = row {
                    if let Some(v) = r.validity_days { v as i64 } else { pick_default_validity() }
                } else {
                    pick_default_validity()
                }
            } else {
                pick_default_validity()
            }
        };

        // sign with a fresh key (self-signed)
        let rsa = Rsa::generate(2048)?;
        let pkey = PKey::from_rsa(rsa)?;

        let mut serial = BigNum::new()?;
        serial.pseudo_rand(64, openssl::bn::MsbOption::MAYBE_ZERO, false)?;
        let serial_number = serial.to_asn1_integer()?;

        let mut builder = X509Builder::new()?;
        builder.set_version(2)?;
        builder.set_serial_number(&serial_number)?;
        builder.set_subject_name(csr.subject_name())?;
        builder.set_issuer_name(csr.subject_name())?;
        builder.set_pubkey(&pkey)?;

        let not_before = Asn1Time::days_from_now(0)?;
        let not_after = Asn1Time::days_from_now(validity_days as u32)?;
        builder.set_not_before(&not_before)?;
        builder.set_not_after(&not_after)?;
        builder.sign(&pkey, MessageDigest::sha256())?;

        let cert_pem = builder.build().to_pem()?;
        let cert_pem_str = String::from_utf8(cert_pem)?;

        let issued = Utc::now();
        let expiry = issued + Duration::days(validity_days);

        sqlx::query!(
            r#"
            INSERT INTO certificates
                (certificate_name, csr_id, serial_number, issuer, issued_date, expiry_date, cert_pem, status)
            VALUES ($1, NULL, $2, $3, $4, $5, $6, 'active')
            "#,
            certificate_name,
            serial_number.to_bn()?.to_dec_str()?.to_string(),
            "Uploaded CSR",
            issued,
            expiry,
            cert_pem_str
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    // ------------------------------------------------------------------
    // SAVE UPLOADED CSR ONLY (no hard-coded subject)
    // Subject fields taken from CSR; validity_days left NULL (unknown).
    // ------------------------------------------------------------------
    pub async fn save_uploaded_csr(
        &self,
        csr_name_fallback: String,
        csr_text: String,
    ) -> Result<(), anyhow::Error> {
        // parse CSR to extract subject; if some field missing, keep fallback minimal
        let csr = X509Req::from_pem(csr_text.as_bytes())?;
        let (mut cn, mut o, mut ou, mut c) = extract_subject(&csr)?;

        if cn.is_empty() {
            cn = csr_name_fallback; // last-resort fallback name
        }

        // validity_days unknown at "upload csr" time -> store NULL
        let validity_days: Option<i32> = None;

        sqlx::query!(
            r#"
            INSERT INTO certificate_requests
                (common_name, organization, org_unit, country, validity_days, csr_text, created_at, status)
            VALUES ($1,$2,$3,$4,$5,$6,$7,'uploaded')
            "#,
            cn,
            nullable(&o),
            nullable(&ou),
            nullable(&c),
            validity_days,
            csr_text,
            Utc::now()
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}

// ---------- helpers ----------

fn extract_subject(csr: &X509Req) -> Result<(String, String, String, String), anyhow::Error> {
    let subject = csr.subject_name();
    let mut cn = String::new();
    let mut o  = String::new();
    let mut ou = String::new();
    let mut c  = String::new();

    for entry in subject.entries() {
    let val = entry.data().as_utf8()?.to_string();
    let key = entry.object().nid().short_name().unwrap_or("");
    match key {
        "CN" => cn = val,
        "O"  => o  = val,
        "OU" => ou = val,
        "C"  => c  = val,
        _ => {}
    }
}
    Ok((cn, o, ou, c))
}

fn pick_default_validity() -> i64 {
    env::var("CERT_DEFAULT_VALIDITY_DAYS")
        .ok()
        .and_then(|s| s.parse::<i64>().ok())
        .filter(|v| *v > 0)
        .unwrap_or(365)
}

fn nullable(s: &str) -> Option<&str> {
    if s.is_empty() { None } else { Some(s) }
}
