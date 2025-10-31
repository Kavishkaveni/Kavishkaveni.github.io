/* eslint-disable no-unused-vars */
import { useEffect, useState } from "react";
import Modal from "../components/Modal";
import ApiService from "../services/api";

export default function Certificate() {
  const [csrList, setCsrList] = useState([]);
  const [showCsrModal, setShowCsrModal] = useState(false);
  const [formData, setFormData] = useState({
    common_name: "",
    organization: "",
    org_unit: "",
    country: "",
    validity_days: "",
  });


  const [certificates, setCertificates] = useState([]);
  const [showSelfSignModal, setShowSelfSignModal] = useState(false);
  const [showUploadCertModal, setShowUploadCertModal] = useState(false);

  // Vault group fetching for Section 3 (dynamic vaults)
  const [vaults, setVaults] = useState([]);
  const [linkages, setLinkages] = useState([]);
  const [showLinkModal, setShowLinkModal] = useState(false);
  const [selectedVault, setSelectedVault] = useState("");
  const [selectedCert, setSelectedCert] = useState("");

  useEffect(() => {
    const fetchVaultGroups = async () => {
      try {
        const response = await ApiService.getVaultGroups();
        setVaults(response);
      } catch (err) {
        console.error("Error loading vault groups:", err);
      }
    };
    fetchVaultGroups();
  }, []);

  // Fetch all CSRs when page loads or refreshes
useEffect(() => {
  const fetchCsrs = async () => {
    try {
      const data = await ApiService.request('/certificate/csr', { method: 'GET' });
      setCsrList(data);
    } catch (err) {
      console.error('Failed to load CSRs:', err);
    }
  };
  fetchCsrs();
}, []);

  const handleDownloadCSR = async (id) => {
  try {
    const response = await fetch(`http://localhost:9000/api/certificate/csr/${id}/download`);
    if (!response.ok) throw new Error("Download failed");

    const blob = await response.blob();
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `csr_${id}.csr`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    window.URL.revokeObjectURL(url);
  } catch (err) {
    console.error("Download error:", err);
    alert("Failed to download CSR file.");
  }
};

  // handle generate CSR
const handleGenerateCSR = async (e) => {
  e.preventDefault();
  try {
    const response = await ApiService.request('/certificate/csr', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        common_name: formData.common_name,
        organization: formData.organization,
        org_unit: formData.org_unit,
        country: formData.country,
        validity_days: parseInt(formData.validity_days, 10),
      }),
    });
    setCsrList((prev) => [...prev, response]);
    setShowCsrModal(false);
    setFormData({
      common_name: '',
      organization: '',
      org_unit: '',
      country: '',
      validity_days: '',
    });
  } catch (err) {
    console.error('Failed to generate CSR:', err);
    alert('Failed to generate CSR. Please check backend logs.');
  }
};

// ========= Self-Sign: upload CSR (.csr/.pem) and create certificate =========
const handleSelfSignSubmit = async (e) => {
  e.preventDefault();
  const form = e.target;
  const file = form.csrFile.files[0];
  const certName = form.certificateName.value.trim();

  if (!file) { alert("Choose a CSR file"); return; }
  if (!certName) { alert("Enter certificate name"); return; }

  // Read CSR file text and send as base64 in JSON
  const csrText = await file.text();
  try {
    await ApiService.request('/certificate/selfsign/upload', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        csr_name: file.name,
        csr_text: btoa(csrText),
        certificate_name: certName,
      }),
    });

    alert('Certificate created successfully!');
    setShowSelfSignModal(false);
    form.reset();
  } catch (err) {
    console.error('Self-sign failed:', err);
    alert('Failed to create certificate.');
  }
};


  const handleDelete = (id) => {
    setCsrList(csrList.filter((csr) => csr.id !== id));
  };

  return (
    <div className="w-100 p-4">
      {/* -------- SECTION 1: Generate CSR -------- */}
      <div className="d-flex justify-content-between align-items-center mb-4">
        <h4 className="fw-semibold mb-0"> Generate CSR</h4>
        <button className="btn btn-primary" onClick={() => setShowCsrModal(true)}>
          + Generate CSR
        </button>
      </div>

      {/* CSR Table */}
      <div className="bg-white rounded-3 p-4 shadow-sm">
        {csrList.length === 0 ? (
          <div className="text-center py-5 text-muted">
            <div style={{ fontSize: "3rem" }}>📜</div>
            <h6>No CSR found</h6>
            <p>Click “+ Generate CSR” to create a new one</p>
          </div>
        ) : (
          <table className="table table-hover">
            <thead>
              <tr>
                <th>CSR ID</th>
                <th>Common Name</th>
                <th>Organization</th>
                <th>Created At</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {csrList.map((csr) => (
                <tr key={csr.id}>
                  <td>{csr.id}</td>
                  <td>{csr.common_name}</td>
                  <td>{csr.organization}</td>
                  <td>{new Date(csr.created_at).toISOString().split('T')[0]}</td>
                  <td>{csr.status}</td>
                  <td>
                    <button
                      className="btn btn-link btn-sm p-1 text-muted"
                      title="View"
                      onClick={() => alert(`Viewing CSR #${csr.id}`)}
                    >
                      👁
                    </button>
                    <button
                      className="btn btn-link btn-sm p-1 text-muted"
                      title="Edit"
                      onClick={() => alert(`Editing CSR #${csr.id}`)}
                    >
                      ✏️
                    </button>
                    <button
                      className="btn btn-link btn-sm p-1 text-muted"
                      title="Delete"
                      onClick={() => handleDelete(csr.id)}
                    >
                       🗑️
                    </button>
                    <button
                      className="btn btn-link btn-sm p-1 text-muted"
                      title="Download"
                      onClick={() => handleDownloadCSR(csr.id)}
                    >
                      ⬇
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* -------- Modal: Generate CSR -------- */}
      {showCsrModal && (
        <div
          className="position-fixed top-0 start-0 w-100 h-100 d-flex align-items-center justify-content-center"
          style={{ backgroundColor: "rgba(0,0,0,0.5)", zIndex: 1050 }}
        >
          <div
            className="bg-white rounded-3 shadow-lg"
            style={{ width: "90%", maxWidth: "500px", maxHeight: "90vh", overflowY: "auto" }}
          >
            <div className="d-flex justify-content-between align-items-center p-4 border-bottom">
              <h5 className="mb-0 fw-semibold">Generate CSR</h5>
              <button className="btn-close" onClick={() => setShowCsrModal(false)}></button>
            </div>

            <form onSubmit={handleGenerateCSR}>
              <div className="p-4">
                <div className="mb-3">
                  <label className="form-label">Common Name (CN)</label>
                  <input
                    type="text"
                    className="form-control"
                    value={formData.common_name}
                    onChange={(e) =>
                      setFormData({ ...formData, common_name: e.target.value })
                    }
                    required
                  />
                </div>

                <div className="mb-3">
                  <label className="form-label">Organization (O)</label>
                  <input
                    type="text"
                    className="form-control"
                    value={formData.organization}
                    onChange={(e) =>
                      setFormData({ ...formData, organization: e.target.value })
                    }
                    required
                  />
                </div>

                <div className="mb-3">
                  <label className="form-label">Organizational Unit (OU)</label>
                  <select
                    className="form-select"
                    value={formData.org_unit}
                    onChange={(e) =>
                      setFormData({ ...formData, org_unit: e.target.value })
                    }
                    required
                  >
                    <option value="">Select OU</option>
                    <option value="Security Division">Security Division</option>
                    <option value="IT Department">IT Department</option>
                    <option value="Web Service">Web Service</option>
                  </select>
                </div>

                <div className="mb-3">
                  <label className="form-label">Country (C)</label>
                  <input
  type="text"
  className="form-control"
  placeholder="e.g. Sri Lanka"
  value={formData.country}
  onChange={(e) =>
    setFormData({ ...formData, country: e.target.value })
  }
  required
/>
<div className="mb-3">
  <label className="form-label">Validity (Days)</label>
  <select
    className="form-select"
    value={formData.validity_days}
    onChange={(e) =>
      setFormData({ ...formData, validity_days: e.target.value })
    }
    required
  >
    <option value="">Select validity</option>
    <option value="30">30 Days</option>
    <option value="90">90 Days</option>
    <option value="180">180 Days</option>
    <option value="365">1 Year</option>
    <option value="730">2 Years</option>
  </select>
</div>
                </div>
              </div>

              <div className="d-flex justify-content-end gap-2 p-4 border-top">
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => setShowCsrModal(false)}
                >
                  Cancel
                </button>
                <button type="submit" className="btn btn-primary">
                  Generate
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
      {/* ================== SECTION 2 – CERTIFICATES ================== */}
<div className="mt-5">
  {/* Header */}
  <div className="d-flex justify-content-between align-items-center mb-3">
    <h5 className="fw-semibold mb-0">Certificates</h5>
    <div className="d-flex gap-2">
      <button
        className="btn btn-secondary"
        onClick={() => setShowUploadCertModal(true)}
      >
        📤 Upload Certificate
      </button>
      <button
        className="btn btn-primary"
        onClick={() => setShowSelfSignModal(true)}
      >
        🔐 Self-Sign Certificate
      </button>
    </div>
  </div>

  {/* Certificate Table */}
  <div className="bg-white rounded-3 shadow-sm p-4">
    {certificates.length === 0 ? (
      <div className="text-center text-muted py-5">
        <div style={{ fontSize: "3rem" }}>📄</div>
        <h6>No certificates found</h6>
        <p>
          Click “Self-Sign Certificate” or “Upload Certificate” to add one.
        </p>
      </div>
    ) : (
      <div className="table-responsive">
        <table className="table table-hover">
          <thead>
            <tr>
              <th>Certificate ID</th>
              <th>Certificate Name</th>
              <th>Issued Date</th>
              <th>Expiry Date</th>
              <th>Validity (Days)</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {certificates.map((cert) => (
              <tr key={cert.id}>
                <td>{cert.id}</td>
                <td>{cert.certificate_name}</td>
                <td>{cert.issued_date}</td>
                <td>{cert.expiry_date}</td>
                <td>{cert.validity}</td>
                <td>
                  <span
                    className={
                      cert.status === "Active"
                        ? "badge bg-success"
                        : cert.status === "Revoked"
                        ? "badge bg-danger"
                        : "badge bg-secondary"
                    }
                  >
                    {cert.status}
                  </span>
                </td>
                <td>
                  <button
                    className="btn btn-link btn-sm p-1 text-muted"
                    title="View"
                    onClick={() => alert(`Viewing certificate #${cert.id}`)}
                  >
                    👁
                  </button>
                  <button
                    className="btn btn-link btn-sm p-1 text-muted"
                    title="Revoke"
                    onClick={() => alert(`Revoking certificate #${cert.id}`)}
                  >
                    🚫
                  </button>
                  <button
                    className="btn btn-link btn-sm p-1 text-muted"
                    title="Delete"
                    onClick={() => alert(`Deleting certificate #${cert.id}`)}
                  >
                    🗑
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    )}
  </div>
</div>

{/* ---------- Self-Sign Certificate Modal ---------- */}
<Modal
  show={showSelfSignModal}
  onClose={() => setShowSelfSignModal(false)}
  title="Self-Sign Certificate"
>
  <form onSubmit={handleSelfSignSubmit}>
    <div className="p-4">

      {/* Upload CSR file */}
      <div className="mb-3">
        <label className="form-label">Upload CSR File</label>
        <input
          type="file"
          name="csrFile"
          accept=".csr,.pem,.txt"
          className="form-control"
          required
        />
        <p className="text-muted small mb-0">
          Upload a valid CSR (.csr / .pem). We’ll parse and self-sign it.
        </p>
      </div>

      {/* Certificate Name */}
      <div className="mb-3">
        <label className="form-label">Certificate Name</label>
        <input
          type="text"
          name="certificateName"
          className="form-control"
          placeholder="Enter certificate name"
          required
        />
      </div>

    </div>

    <div className="d-flex justify-content-end gap-2 p-4 border-top">
      <button
        type="button"
        className="btn btn-secondary"
        onClick={() => setShowSelfSignModal(false)}
      >
        Cancel
      </button>
      <button type="submit" className="btn btn-primary">
        Generate
      </button>
    </div>
  </form>
</Modal>


{/* ---------- Upload Certificate Modal ---------- */}
<Modal
  show={showUploadCertModal}
  onClose={() => setShowUploadCertModal(false)}
  title="Upload Certificate"
>
  <form onSubmit={(e) => e.preventDefault()}>
    <div className="p-4">
      <label className="form-label">Upload Certificate File</label>
      <input
        type="file"
        accept=".crt,.pem,.cer"
        className="form-control mb-3"
        required
      />
      <label className="form-label">Expiry Date</label>
      <input type="date" className="form-control mb-3" required />
      <label className="form-label">Status</label>
      <select className="form-select">
        <option>Active</option>
        <option>Pending</option>
      </select>
    </div>
    <div className="d-flex justify-content-end gap-2 p-4 border-top">
      <button
        type="button"
        className="btn btn-secondary"
        onClick={() => setShowUploadCertModal(false)}
      >
        Cancel
      </button>
      <button type="submit" className="btn btn-primary">
        Upload
      </button>
    </div>
  </form>
</Modal>
    {/* ================== SECTION 3 – LINK CERTIFICATE TO VAULT ================== */}
<div className="mt-5">
  {/* Header */}
  <div className="d-flex justify-content-between align-items-center mb-3">
    <h5 className="fw-semibold mb-0">Link Certificate to Vault</h5>
    <button
      className="btn btn-primary"
      onClick={() => setShowLinkModal(true)}
    >
      + Add Link
    </button>
  </div>

  {/* Link Table */}
  <div className="bg-white rounded-3 shadow-sm p-4">
    {linkages.length === 0 ? (
      <div className="text-center text-muted py-5">
        <div style={{ fontSize: "3rem" }}>🔗</div>
        <h6>No links found</h6>
        <p>Click “+ Add Link” to link a certificate to a vault.</p>
      </div>
    ) : (
      <div className="table-responsive">
        <table className="table table-hover">
          <thead>
            <tr>
              <th>Vault Name</th>
              <th>Linked Certificate</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {linkages.map((link) => (
              <tr key={link.id}>
                <td>{link.vault_name}</td>
                <td>{link.certificate_name}</td>
                <td>
                  <span
                    className={
                      link.status === "Linked"
                        ? "badge bg-success"
                        : "badge bg-secondary"
                    }
                  >
                    {link.status}
                  </span>
                </td>
                <td>
                  <button
                    className="btn btn-link btn-sm p-1 text-muted"
                    title="Link"
                    onClick={() => alert(`Linking ${link.vault_name}`)}
                  >
                    🔗
                  </button>
                  <button
                    className="btn btn-link btn-sm p-1 text-muted"
                    title="Change"
                    onClick={() => alert(`Changing link for ${link.vault_name}`)}
                  >
                    ✏
                  </button>
                  <button
                    className="btn btn-link btn-sm p-1 text-muted"
                    title="Unlink"
                    onClick={() => alert(`Unlinking ${link.vault_name}`)}
                  >
                    ❌
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    )}
  </div>
</div>

{/* ---------- Add Link Modal ---------- */}
<Modal
  show={showLinkModal}
  onClose={() => setShowLinkModal(false)}
  title="Link Certificate to Vault"
>
  <form
    onSubmit={(e) => {
      e.preventDefault();
      const newLink = {
        id: linkages.length + 1,
        vault_name: selectedVault,
        certificate_name: selectedCert,
        status: "Linked",
      };
      setLinkages([...linkages, newLink]);
      setShowLinkModal(false);
      setSelectedVault("");
      setSelectedCert("");
    }}
  >
    <div className="p-4">
      <div className="mb-3">
        <label className="form-label">Select Vault</label>
        <select
          className="form-select"
          value={selectedVault}
          onChange={(e) => setSelectedVault(e.target.value)}
          required
        >
          <option value="">Select Vault</option>
          {vaults.map((v) => (
            <option key={v.id} value={v.name}>
              {v.name}
            </option>
          ))}
        </select>
      </div>

      <div className="mb-3">
        <label className="form-label">Select Certificate</label>
        <select
          className="form-select"
          value={selectedCert}
          onChange={(e) => setSelectedCert(e.target.value)}
          required
        >
          <option value="">Select Certificate</option>
          {certificates
            .filter((c) => c.status === "Active")
            .map((c) => (
              <option key={c.id} value={c.common_name}>
                {c.common_name}
              </option>
            ))}
        </select>
      </div>
    </div>

    <div className="d-flex justify-content-end gap-2 p-4 border-top">
      <button
        type="button"
        className="btn btn-secondary"
        onClick={() => setShowLinkModal(false)}
      >
        Cancel
      </button>
      <button type="submit" className="btn btn-primary">
        Link Certificate
      </button>
    </div>
  </form>
</Modal>
    </div>
  );
}

