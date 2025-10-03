import React, { useState, useEffect } from "react";

export default function Recordings() {
  const [searchTerm, setSearchTerm] = useState("");
  const [recordings, setRecordings] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchRecordings() {
      try {
        const res = await fetch("http://localhost:9000/api/recordings");
        if (!res.ok) throw new Error("Failed to fetch");
        const data = await res.json();
        setRecordings(data);
      } catch (err) {
        console.error("Failed to fetch recordings:", err);
      } finally {
        setLoading(false);
      }
    }
    fetchRecordings();
  }, []);

  const filtered = recordings.filter(
    (r) =>
      (r.session_id || "").toLowerCase().includes(searchTerm.toLowerCase()) ||
      (r.user_name || "").toLowerCase().includes(searchTerm.toLowerCase()) ||
      (r.device_name || "").toLowerCase().includes(searchTerm.toLowerCase())
  );

  const getStatusClass = (status) => {
    switch (status) {
      case "Available":
        return "badge bg-success";
      case "Processing":
        return "badge bg-warning text-dark";
      case "Archived":
        return "badge bg-secondary";
      default:
        return "badge bg-light text-dark";
    }
  };

  const getProtocolClass = (type) => {
    if (!type) return "badge bg-light text-dark";
    switch (type.toLowerCase()) {
      case "ssh":
        return "badge bg-primary";
      case "rdp":
        return "badge bg-info text-dark";
      case "https":
        return "badge bg-warning text-dark";
      default:
        return "badge bg-light text-dark";
    }
  };

  const formatDate = (value) => {
    if (!value) return "-";
    return new Date(value).toLocaleDateString();
  };

  const formatTime = (value) => {
    if (!value) return "-";
    return new Date(value).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  };

  const formatSize = (size) => {
    if (!size) return "-";
    return `${(size / 1024 / 1024).toFixed(1)} MB`;
  };

  const formatDuration = (seconds) => {
    if (!seconds) return "-";
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  };

  return (
    <div className="container-fluid">
      {/* Header */}
      <div className="mb-4">
        <p className="text-muted mb-3">View and manage recorded sessions</p>

        {/* Search */}
        <div className="d-flex flex-column flex-md-row justify-content-between align-items-start align-items-md-center mb-4 gap-3">
          <div className="position-relative w-100" style={{ maxWidth: "350px" }}>
            <input
              type="text"
              className="form-control ps-5"
              placeholder="Search by user, session or device"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
            <span
              className="position-absolute top-50 start-0 translate-middle-y ms-3 text-muted"
              style={{ fontSize: "1.25rem" }}
            >
              🔍
            </span>
          </div>
        </div>
      </div>

      {/* Recordings Table */}
      <div className="card shadow-sm">
        <div className="card-header d-flex justify-content-between align-items-center">
          <h5 className="mb-0">Recording Library</h5>
          <button className="btn btn-link btn-sm">View All</button>
        </div>

        <div className="table-responsive">
          <table className="table table-hover align-middle mb-0">
            <thead className="table-light">
              <tr>
                <th>SESSION</th>
                <th>USER</th>
                <th>DEVICE</th>
                <th>TYPE</th>
                <th>DATE</th>
                <th>START TIME</th>
                <th>END TIME</th>
                <th>DURATION</th>
                <th>SIZE</th>
                <th>STATUS</th>
                <th>ACTIONS</th>
              </tr>
            </thead>

            <tbody>
              {loading ? (
                <tr>
                  <td colSpan="11" className="text-center py-4">
                    Loading...
                  </td>
                </tr>
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan="11" className="text-center text-muted py-4">
                    No recordings found.
                  </td>
                </tr>
              ) : (
                filtered.map((rec, i) => (
                  <tr key={i}>
                    <td>{rec.session_id}</td>
                    <td>{rec.user_name}</td>
                    <td>{rec.device_name}</td>
                    <td>
                      <span className={getProtocolClass(rec.protocol)}>{rec.protocol}</span>
                    </td>
                    <td>{formatDate(rec.start_time)}</td>
                    <td>{formatTime(rec.start_time)}</td>
                    <td>{formatTime(rec.end_time)}</td>
                    <td>{formatDuration(rec.duration)}</td>
                    <td>{formatSize(rec.file_size)}</td>
                    <td>
                      <span className={getStatusClass(rec.status)}>{rec.status}</span>
                    </td>
                    <td>
                      <div className="d-flex gap-2">
                        <button
                          className="btn btn-sm btn-outline-primary"
                          disabled={rec.status !== "Available"}
                          title="Play recording"
                        >
                          ▶️ <span className="d-none d-md-inline ms-1">Play</span>
                        </button>
                        <button
                          className="btn btn-sm btn-outline-secondary"
                          disabled={rec.status !== "Available"}
                          title="Download recording"
                        >
                          ⬇️ <span className="d-none d-md-inline ms-1">Download</span>
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
