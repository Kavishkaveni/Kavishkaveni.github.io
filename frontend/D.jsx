import { useState, useEffect } from "react"
import ApiService from "../services/api"

export default function Devices() {
  const [devices, setDevices] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const [showAddModal, setShowAddModal] = useState(false)
  const [showEditModal, setShowEditModal] = useState(false)
  const [showConnectModal, setShowConnectModal] = useState(false)
  const [showDeleteModal, setShowDeleteModal] = useState(false)
  const [selectedDevice, setSelectedDevice] = useState(null)
  const [searchTerm, setSearchTerm] = useState("")

  const [formData, setFormData] = useState({
    name: "",
    ip: "",
    type: "",
    access: "",
    status: "Online",
  })

  // Load devices from API
  useEffect(() => {
    loadDevices()
  }, [])

  const loadDevices = async (search = '') => {
    try {
      setLoading(true)
      setError(null)
      const response = await ApiService.getDevices(search)
      setDevices(response)
    } catch (err) {
      setError('Failed to load devices. Please check if the backend is running.')
      console.error('Error loading devices:', err)
      setDevices([])
    } finally {
      setLoading(false)
    }
  }

  // Filter devices based on search term (now handled by API)
  const handleSearch = (searchTerm) => {
    setSearchTerm(searchTerm)
    loadDevices(searchTerm)
  }

  const filteredDevices = devices

  const StatusBadge = ({ status, type = "status" }) => {
    const getStatusClass = () => {
      if (type === "protocol") {
        const protocolColors = {
          SSH: "bg-primary bg-opacity-10 text-primary",
          RDP: "bg-secondary bg-opacity-10 text-secondary",
          HTTPS: "bg-success bg-opacity-10 text-success",
        }
        return protocolColors[status] || "bg-light text-dark"
      }

      const statusColors = {
        Online: "bg-success bg-opacity-10 text-success",
        Offline: "bg-danger bg-opacity-10 text-danger",
      }
      return statusColors[status] || "bg-light text-dark"
    }

    return (
      <span className={`badge ${getStatusClass()} fw-medium`} style={{ fontSize: "11px" }}>
        {status}
      </span>
    )
  }

  const handleAddDevice = () => {
    setFormData({
      name: "",
      ip: "",
      type: "",
      access: "",
      status: "Online",
    })
    setShowAddModal(true)
  }

  const handleEditDevice = (device) => {
    setSelectedDevice(device)
    setFormData({
      name: device.name,
      ip: device.ip,
      type: device.device_type || device.type,
      access: device.access_protocol || device.access,
      status: device.status,
    })
    setShowEditModal(true)
  }

  const handleConnectDevice = (device) => {
    setSelectedDevice(device)
    setShowConnectModal(true)
  }

  const handleDeleteDevice = (device) => {
    setSelectedDevice(device)
    setShowDeleteModal(true)
  }

  const submitAddDevice = async (e) => {
    e.preventDefault()
    try {
      await ApiService.createDevice(formData)
      await loadDevices(searchTerm)
      setShowAddModal(false)
      setFormData({
        name: "",
        ip: "",
        type: "",
        access: "",
        status: "Online",
      })
    } catch (err) {
      setError('Failed to create device')
      console.error('Error creating device:', err)
    }
  }

  const submitEditDevice = async (e) => {
    e.preventDefault()
    try {
      await ApiService.updateDevice(selectedDevice.id, formData)
      await loadDevices(searchTerm)
      setShowEditModal(false)
      setSelectedDevice(null)
    } catch (err) {
      setError('Failed to update device')
      console.error('Error updating device:', err)
    }
  }

  const confirmDelete = async () => {
    try {
      await ApiService.deleteDevice(selectedDevice.id)
      await loadDevices(searchTerm)
      setShowDeleteModal(false)
      setSelectedDevice(null)
    } catch (err) {
      setError('Failed to delete device')
      console.error('Error deleting device:', err)
    }
  }

  const handleConnect = async (protocol) => {
    if (!selectedDevice) return

    try {
      setError(null)

      // get credentials from vault
      const vaultEntries = await ApiService.getVaultEntries(selectedDevice.id)
      if (vaultEntries.length === 0) {
        setError(`No credentials found for ${selectedDevice.name}. Please add credentials in the Password Vault first.`)
        return
      }
      const credentials = vaultEntries[0]

      // create session
      const sessionData = {
        device_id: selectedDevice.id,
        protocol: protocol, // SSH / RDP / HTTPS
        username: credentials.username,
        user_identity: "admin",
      }
      console.log('Creating session with data:', sessionData)
      const sessionResponse = await ApiService.createSession(sessionData)
      console.log('Session created:', sessionResponse)

      if (protocol === 'RDP') {
        await ApiService.downloadRdpFile(sessionResponse.uuid)
        setShowConnectModal(false)
        setSelectedDevice(null)
        return
      }

      if (protocol === 'SSH') {
        console.log('SSH connection initiated for:', selectedDevice.name)
        setShowConnectModal(false)
        setSelectedDevice(null)
        return
      }

      // NEW: Web (Chrome) connection
      if (protocol === 'HTTPS') {
        console.log('Web (HTTPS) connection initiated for:', selectedDevice.name)
        // backend/CH will handle launching Chrome after createSession
        setShowConnectModal(false)
        setSelectedDevice(null)
        return
      }

    } catch (err) {
      setError(`Failed to initiate ${protocol} connection: ${err.message}`)
      console.error('Error creating session:', err)
    }
  }

  const closeModal = () => {
    setShowAddModal(false)
    setShowEditModal(false)
    setShowConnectModal(false)
    setShowDeleteModal(false)
    setSelectedDevice(null)
  }

  const Modal = ({ show, onClose, title, children }) => {
    if (!show) return null

    return (
      <div
        className="position-fixed top-0 start-0 w-100 h-100 d-flex align-items-center justify-content-center"
        style={{ backgroundColor: "rgba(0,0,0,0.5)", zIndex: 1050 }}
      >
        <div
          className="bg-white rounded-3 shadow-lg"
          style={{ width: "90%", maxWidth: "500px", maxHeight: "90vh", overflowY: "auto" }}
        >
          <div className="d-flex justify-content-between align-items-center p-4 border-bottom">
            <h5 className="mb-0 fw-semibold">{title}</h5>
            <button className="btn-close" onClick={onClose}></button>
          </div>
          {children}
        </div>
      </div>
    )
  }

  return (
    <div className="w-100">
      <div className="d-flex flex-column flex-md-row justify-content-between align-items-start align-items-md-center mb-4 gap-3">
        <div className="position-relative">
          <input
            type="text"
            className="form-control ps-5"
            placeholder="Search devices..."
            value={searchTerm}
            onChange={(e) => handleSearch(e.target.value)}
            style={{ minWidth: "250px" }}
          />
          <span className="position-absolute top-50 start-0 translate-middle-y ms-3">🔍</span>
        </div>
        <button className="btn btn-primary" onClick={handleAddDevice}>
          + Add Device
        </button>
      </div>

      {error && (
        <div className="alert alert-danger d-flex align-items-center mb-4" role="alert">
          <span className="me-2">⚠️</span>
          <div>
            {error}
            <button
              className="btn btn-link btn-sm p-0 ms-2 text-decoration-none"
              onClick={() => loadDevices(searchTerm)}
            >
              Try again
            </button>
          </div>
        </div>
      )}

      <div className="bg-white rounded-3 p-4 shadow-sm">
        <div className="table-responsive">
          {loading ? (
            <div className="text-center py-5">
              <div className="spinner-border text-primary" role="status">
                <span className="visually-hidden">Loading...</span>
              </div>
              <p className="mt-2 text-muted">Loading devices...</p>
            </div>
          ) : filteredDevices.length === 0 ? (
            <div className="text-center py-5 text-muted">
              <div style={{ fontSize: "3rem" }}>📱</div>
              <h6>No devices found</h6>
              <p>
                {searchTerm
                  ? `No devices match "${searchTerm}"`
                  : "Start by adding your first device"
                }
              </p>
            </div>
          ) : (
            <table className="table table-hover">
              <thead>
                <tr>
                  <th>NAME</th>
                  <th>IP ADDRESS</th>
                  <th>TYPE</th>
                  <th>ACCESS</th>
                  <th>LAST ACCESSED</th>
                  <th>STATUS</th>
                  <th>ACTIONS</th>
                </tr>
              </thead>
              <tbody>
                {filteredDevices.map((device) => (
                  <tr key={device.id}>
                    <td className="fw-medium">{device.name}</td>
                    <td>{device.ip}</td>
                    <td>{device.device_type || device.type}</td>
                    <td>
                      <StatusBadge status={device.access_protocol || device.access} type="protocol" />
                    </td>
                    <td>{device.last_accessed || device.lastAccessed || 'Never'}</td>
                    <td>
                      <StatusBadge status={device.status} />
                    </td>
                    <td>
                      <button
                        className="btn btn-link btn-sm p-1 text-muted"
                        title="Connect"
                        onClick={() => handleConnectDevice(device)}
                      >
                        🔗
                      </button>
                      <button
                        className="btn btn-link btn-sm p-1 text-muted"
                        title="Edit"
                        onClick={() => handleEditDevice(device)}
                      >
                        ✏️
                      </button>
                      <button className="btn btn-link btn-sm p-1 text-muted" title="Info">
                        ℹ️
                      </button>
                      <button
                        className="btn btn-link btn-sm p-1 text-muted"
                        title="Delete"
                        onClick={() => handleDeleteDevice(device)}
                      >
                        🗑️
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Add Device Modal */}
      <Modal show={showAddModal} onClose={closeModal} title="Add New Device">
        <form onSubmit={submitAddDevice}>
          <div className="p-4">
            <div className="mb-3">
              <label className="form-label">Device Name</label>
              <input
                type="text"
                className="form-control"
                value={formData.name}
                autoFocus
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, name: e.target.value }))
                }
                required
              />
            </div>

            <div className="mb-3">
              <label className="form-label">IP Address</label>
              <input
                type="text"
                className="form-control"
                value={formData.ip}
                onChange={(e) =>
                  setFormData((prev) => ({ ...prev, ip: e.target.value }))
                }
                required
              />
            </div>

            <div className="mb-3">
              <label className="form-label">Device Type</label>
              <select
                className="form-select"
                value={formData.type}
                onChange={(e) => setFormData({ ...formData, type: e.target.value })}
                required
              >
                <option value="">Select Type</option>
                <option value="Linux Server">Linux Server</option>
                <option value="Windows Server">Windows Server</option>
                <option value="Database">Database</option>
                <option value="Web Server">Web Server</option>
                <option value="API Server">API Server</option>
              </select>
            </div>

            <div className="mb-3">
              <label className="form-label">Access Protocol</label>
              <select
                className="form-select"
                value={formData.access}
                onChange={(e) => setFormData({ ...formData, access: e.target.value })}
                required
              >
                <option value="">Select Protocol</option>
                <option value="SSH">SSH</option>
                <option value="RDP">RDP</option>
                <option value="HTTPS">HTTPS</option>
              </select>
            </div>

            <div className="mb-3">
              <label className="form-label">Status</label>
              <select
                className="form-select"
                value={formData.status}
                onChange={(e) => setFormData({ ...formData, status: e.target.value })}
              >
                <option value="Online">Online</option>
                <option value="Offline">Offline</option>
              </select>
            </div>
          </div>
          <div className="d-flex justify-content-end gap-2 p-4 border-top">
            <button type="button" className="btn btn-secondary" onClick={closeModal}>
              Cancel
            </button>
            <button type="submit" className="btn btn-primary">
              Add Device
            </button>
          </div>
        </form>
      </Modal>

      {/* Edit Device Modal */}
      <Modal show={showEditModal} onClose={closeModal} title="Edit Device">
        <form onSubmit={submitEditDevice}>
          <div className="p-4">
            <div className="mb-3">
              <label className="form-label">Device Name</label>
              <input
                type="text"
                className="form-control"
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                required
              />
            </div>
            <div className="mb-3">
              <label className="form-label">IP Address</label>
              <input
                type="text"
                className="form-control"
                value={formData.ip}
                onChange={(e) => setFormData({ ...formData, ip: e.target.value })}
                required
              />
            </div>
            <div className="mb-3">
              <label className="form-label">Device Type</label>
              <select
                className="form-select"
                value={formData.type}
                onChange={(e) => setFormData({ ...formData, type: e.target.value })}
                required
              >
                <option value="">Select Type</option>
                <option value="Linux Server">Linux Server</option>
                <option value="Windows Server">Windows Server</option>
                <option value="Database">Database</option>
                <option value="Web Server">Web Server</option>
                <option value="API Server">API Server</option>
              </select>
            </div>
            <div className="mb-3">
              <label className="form-label">Access Protocol</label>
              <select
                className="form-select"
                value={formData.access}
                onChange={(e) => setFormData({ ...formData, access: e.target.value })}
                required
              >
                <option value="">Select Protocol</option>
                <option value="SSH">SSH</option>
                <option value="RDP">RDP</option>
                <option value="HTTPS">HTTPS</option>
              </select>
            </div>
            <div className="mb-3">
              <label className="form-label">Status</label>
              <select
                className="form-select"
                value={formData.status}
                onChange={(e) => setFormData({ ...formData, status: e.target.value })}
              >
                <option value="Online">Online</option>
                <option value="Offline">Offline</option>
              </select>
            </div>
          </div>
          <div className="d-flex justify-content-end gap-2 p-4 border-top">
            <button type="button" className="btn btn-secondary" onClick={closeModal}>
              Cancel
            </button>
            <button type="submit" className="btn btn-primary">
              Save Changes
            </button>
          </div>
        </form>
      </Modal>

      {/* Connect Modal */}
      {showConnectModal && selectedDevice && (
        <Modal show={showConnectModal} onClose={closeModal} title={`Connect to ${selectedDevice.name}`}>
          <div className="p-4">
            <p className="text-muted mb-4">Choose connection method for {selectedDevice.ip}</p>
            <div className="d-grid gap-3">
              <button
                className="btn btn-outline-primary d-flex align-items-center justify-content-start gap-3 p-3"
                onClick={() => handleConnect("SSH")}
              >
                <span style={{ fontSize: "1.5rem" }}>🖥️</span>
                <div className="text-start">
                  <div className="fw-medium">SSH Connection</div>
                  <small className="text-muted">Secure Shell access</small>
                </div>
              </button>

              {/* NEW: Web (HTTPS) Connection button */}
              <button
                className="btn btn-outline-primary d-flex align-items-center justify-content-start gap-3 p-3"
                onClick={() => handleConnect("HTTPS")}
              >
                <span style={{ fontSize: "1.5rem" }}>🌐</span>
                <div className="text-start">
                  <div className="fw-medium">Web Connection</div>
                  <small className="text-muted">Open in Chrome & auto-login</small>
                </div>
              </button>

              <button
                className="btn btn-outline-primary d-flex align-items-center justify-content-start gap-3 p-3"
                onClick={() => handleConnect("RDP")}
              >
                <span style={{ fontSize: "1.5rem" }}>🖱️</span>
                <div className="text-start">
                  <div className="fw-medium">RDP Connection</div>
                  <small className="text-muted">Remote Desktop Protocol</small>
                </div>
              </button>
            </div>
          </div>
          <div className="d-flex justify-content-end p-4 border-top">
            <button type="button" className="btn btn-secondary" onClick={closeModal}>
              Cancel
            </button>
          </div>
        </Modal>
      )}

      {/* Delete Confirmation Modal */}
      {showDeleteModal && selectedDevice && (
        <Modal show={showDeleteModal} onClose={closeModal} title="Delete Device">
          <div className="p-4 text-center">
            <div className="mb-3" style={{ fontSize: "3rem" }}>
              ⚠️
            </div>
            <h6>Are you sure you want to delete this device?</h6>
            <p className="text-muted">
              <strong>{selectedDevice.name}</strong> ({selectedDevice.ip})
              <br />
              This action cannot be undone.
            </p>
          </div>
          <div className="d-flex justify-content-end gap-2 p-4 border-top">
            <button type="button" className="btn btn-secondary" onClick={closeModal}>
              Cancel
            </button>
            <button type="button" className="btn btn-danger" onClick={confirmDelete}>
              Delete Device
            </button>
          </div>
        </Modal>
      )}
    </div>
  )
}
