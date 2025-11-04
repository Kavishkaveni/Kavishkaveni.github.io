/* eslint-disable no-unused-vars */
import { useEffect, useState } from "react";
import Modal from "../components/Modal"; //  externalized modal
import ApiService from "../services/api";
import { createJumpHostCredential } from "../services/jumpHostApi";

export default function PasswordVault() {
  const [vaultGroups, setVaultGroups] = useState([]);
  const [selectedGroup, setSelectedGroup] = useState(null);
  const [vaultEntries, setVaultEntries] = useState([]);
  const [devices, setDevices] = useState([]);
  const [jumpHostDevices, setJumpHostDevices] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showAddVaultModal, setShowAddVaultModal] = useState(false);
  const [showAddEntryModal, setShowAddEntryModal] = useState(false);
  const [newVaultName, setNewVaultName] = useState("");
  const [formData, setFormData] = useState({
    device_id: "",
    username: "",
    password: "",
  });

  useEffect(() => {
    loadVaultGroups();
    loadDevices();
    loadJumpHosts();   
  }, []);



  const loadVaultGroups = async () => {
    try {
      const response = await ApiService.getVaultGroups();
      setVaultGroups(response);
    } catch (err) {
      console.error("Error loading vault groups:", err);
    }
  };

  const loadVaultEntries = async (groupId) => {
  try {
    setLoading(true);
    setError(null);

    let response;

    // if this vault = JumpHost → load from jump host vault table
    if (selectedGroup?.name === "JumpHost") {
      response = await ApiService.request("/jump-host-vault");
    } else {
      response = await ApiService.getVaultEntriesByGroup(groupId);
    }

    setVaultEntries(response);
  } catch (err) {
    setError("Failed to load vault entries. Please check backend.");
    console.error("Error loading vault entries:", err);
    setVaultEntries([]);
  } finally {
    setLoading(false);
  }
};

  const loadDevices = async () => {
    try {
      const response = await ApiService.getDevices();
      setDevices(response);
    } catch (err) {
      console.error("Error loading devices:", err);
    }
  };

  const loadJumpHosts = async () => {
  try {
    const data = await ApiService.request("/jump-hosts");
    setJumpHostDevices(data);
  } catch(e) {
    console.error("jump hosts load failed", e);
  }
};

  // Create new Vault Group
  const handleCreateVaultGroup = async (e) => {
    e.preventDefault();
    try {
      await ApiService.createVaultGroup({ name: newVaultName });
      setShowAddVaultModal(false);
      setNewVaultName("");
      await loadVaultGroups();
    } catch (err) {
      console.error("Error creating vault group:", err);
    }
  };

  // Add new credential
  const submitAddEntry = async (e) => {
    e.preventDefault();
    try {
      // if this group is JumpHost → call jump host API
if (selectedGroup.name === "JumpHost") {
  await createJumpHostCredential({
    jump_host_id: parseInt(formData.device_id),
    username: formData.username,
    password: formData.password,
  });
} else {
  // normal vault
  await ApiService.createVaultEntry({
    device_id: parseInt(formData.device_id),
    username: formData.username,
    password: formData.password,
    group_id: selectedGroup.id,
  });
}
      await loadVaultEntries(selectedGroup.id);
      setShowAddEntryModal(false);
      setFormData({ device_id: "", username: "", password: "" });
    } catch (err) {
      setError("Failed to create vault entry");
      console.error("Error creating vault entry:", err);
    }
  };

  // --- Edit and Delete handlers ---

const handleEditEntry = (entry) => {
  setFormData({
    device_id: entry.device_id.toString(),
    username: entry.username,
    password: "",
  });
  setShowAddEntryModal(true);
};

const handleDeleteEntry = async (entry) => {
  if (window.confirm(`Delete ${entry.username} on ${entry.device_name}?`)) {
    await ApiService.deleteVaultEntry(entry.id);
    await loadVaultEntries(selectedGroup.id);
  }
};

  return (
    <div className="w-100">
      {/* HEADER */}
      <div className="d-flex justify-content-between align-items-center mb-4">
        <h4 className="fw-semibold mb-0">
          {selectedGroup ? selectedGroup.name : "Password Vaults"}
        </h4>
        <button
          className="btn btn-primary"
          onClick={() => {
  if (!selectedGroup) {
    setShowAddVaultModal(true);
    return;
  }

  if (!selectedGroup.certificate_id) {
    alert("⚠ Please complete certificate linking first.");
    window.location.href = "/certificates"; // change if route name diff
    return;
  }

  setShowAddEntryModal(true);
}}
        >
          {selectedGroup ? "+ Add Credential" : "+ Add Sub Vault"}
        </button>
      </div>

      {/* ------------------- VAULT GROUP GRID ------------------- */}
      {!selectedGroup && (
        <div className="d-flex flex-wrap gap-3">
          {vaultGroups.map((group) => (
            <div
              key={group.id}
              className="card p-4 text-center shadow-sm"
              style={{
                width: "200px",
                cursor: "pointer",
                border: "1px solid #ddd",
                borderRadius: "10px",
              }}
              onClick={() => {
                setSelectedGroup(group);
                loadVaultEntries(group.id);
              }}
            >
              <div style={{ fontSize: "2rem" }}>🔒</div>
              <h6 className="mt-2 mb-0">{group.name}</h6>
            </div>
          ))}
          {vaultGroups.length === 0 && (
            <p className="text-muted">
              No vaults found. Click “+ Add Sub Vault” to create one.
            </p>
          )}
        </div>
      )}

      {/* ------------------- CREDENTIAL TABLE ------------------- */}
      {selectedGroup && (
        <div className="bg-white rounded-3 p-4 shadow-sm mt-3">
          {loading ? (
            <div className="text-center py-5">
              <div className="spinner-border text-primary" role="status"></div>
              <p className="mt-2 text-muted">Loading credentials...</p>
            </div>
          ) : vaultEntries.length === 0 ? (
            <div className="text-center py-5 text-muted">
              <div style={{ fontSize: "3rem" }}>🔐</div>
              <h6>No credentials found in this vault</h6>
            </div>
          ) : (
            <table className="table table-hover">
              <thead>
  <tr>
    <th>DEVICE</th>
    <th>IP ADDRESS</th>
    <th>USERNAME</th>
    <th>CREATED</th>
    <th>UPDATED</th>
    <th>ACTIONS</th>
  </tr>
</thead>
<tbody>
  {vaultEntries.map((entry) => (
    <tr key={entry.id}>
      <td>{ selectedGroup?.name === "JumpHost" ? entry.jh_name : entry.device_name }</td>
<td>{ selectedGroup?.name === "JumpHost" ? entry.jh_ip   : entry.device_ip   }</td>
      <td>{entry.username}</td>
      <td>{new Date(entry.created_at).toLocaleDateString()}</td>
      <td>{new Date(entry.updated_at).toLocaleDateString()}</td>
      <td>
  <button
    className="btn btn-link btn-sm p-1 text-muted"
    title="Edit"
    onClick={() => handleEditEntry(entry)}  
  >
    ✏️
  </button>
  <button
    className="btn btn-link btn-sm p-1 text-muted"
    title="Delete"
    onClick={() => handleDeleteEntry(entry)}  
  >
    🗑️
  </button>
</td>
    </tr>
  ))}
</tbody>
            </table>
          )}
          <button
            className="btn btn-link mt-3"
            onClick={() => setSelectedGroup(null)}
          >
            ← Back to Vaults
          </button>
        </div>
      )}

      {/* ------------------- ADD SUB VAULT MODAL ------------------- */}
      <Modal
        show={showAddVaultModal}
        onClose={() => setShowAddVaultModal(false)}
        title="Create New Vault"
      >
        <form onSubmit={handleCreateVaultGroup}>
          <div className="p-4">
            <label className="form-label">Vault Name</label>
            <input
              type="text"
              autoFocus
              className="form-control"
              value={newVaultName}
              onChange={(e) => setNewVaultName(e.target.value)}
              required
            />
          </div>
          <div className="d-flex justify-content-end gap-2 p-4 border-top">
            <button
              type="button"
              className="btn btn-secondary"
              onClick={() => setShowAddVaultModal(false)}
            >
              Cancel
            </button>
            <button type="submit" className="btn btn-primary">
              Create
            </button>
          </div>
        </form>
      </Modal>

      {/* ------------------- ADD CREDENTIAL MODAL ------------------- */}
      <Modal
        show={showAddEntryModal}
        onClose={() => setShowAddEntryModal(false)}
        title="Add New Credential"
      >
        <form onSubmit={submitAddEntry}>
          <div className="p-4">
            <div className="mb-3">
              <label className="form-label">Device</label>
              <select
                className="form-select"
                value={formData.device_id}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, device_id: e.target.value }))
                }
                required
              >
                <option value="">Select Device</option>
                {(selectedGroup?.name === "JumpHost" ? jumpHostDevices : devices).map((device) => (
                  <option key={device.id} value={device.id}>
                    {device.name} ({device.ip})
                  </option>
                ))}
              </select>
            </div>

            <div className="mb-3">
              <label className="form-label">Username</label>
              <input
                type="text"
                className="form-control"
                value={formData.username}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, username: e.target.value }))
                }
                required
              />
            </div>

            <div className="mb-3">
              <label className="form-label">Password</label>
              <input
                type="password"
                className="form-control"
                value={formData.password}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, password: e.target.value }))
                }
                required
              />
            </div>
          </div>
          <div className="d-flex justify-content-end gap-2 p-4 border-top">
            <button
              type="button"
              className="btn btn-secondary"
              onClick={() => setShowAddEntryModal(false)}
            >
              Cancel
            </button>
            <button type="submit" className="btn btn-primary">
              Add
            </button>
          </div>
        </form>
      </Modal>
    </div>
  );
}
