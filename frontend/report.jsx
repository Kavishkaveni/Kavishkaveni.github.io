import { useEffect, useState } from "react";

export default function Reports() {
  const [dateRange, setDateRange] = useState("Last 30 days");
  const [reportData, setReportData] = useState(null);
  const [sessionTrendData, setSessionTrendData] = useState([]);

  useEffect(() => {
    const fetchReports = async () => {
      try {
        const response = await fetch("http://localhost:9000/api/reports");
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }
        const data = await response.json();
        setReportData(data);
      } catch (error) {
        console.error("Error fetching report data:", error);
      }
    };
    const fetchTrends = async () => {
    try {
      const response = await fetch("http://localhost:9000/api/reports/trends");
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
      const data = await response.json();

      const allDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
      const filledData = allDays.map(day => {
        const found = data.find(item => item.day.toLowerCase().startsWith(day.toLowerCase()));
        return { day, sessions: found ? found.sessions : 0 };
      });

      setSessionTrendData(filledData);
    } catch (error) {
      console.error("Error fetching session trends:", error);
    }
  };

  fetchReports();
  fetchTrends();
}, []);


  const auditEvents = [];

  return (
    <div className="container-fluid">
      {/* Header and Controls */}
      <div className="d-flex flex-column flex-lg-row justify-content-between align-items-start align-items-lg-center mb-4 gap-3">
        <p className="text-muted mb-0">
          Comprehensive reporting and audit trail analysis
        </p>
        <div className="btn-group" role="group" aria-label="Reports controls">
          <button
            type="button"
            className="btn btn-outline-secondary btn-sm"
            aria-label="Select date range"
          >
            📅 Date Range
          </button>
          <button
            type="button"
            className="btn btn-outline-secondary btn-sm"
            aria-label="Filter reports"
          >
            🔽 Filter
          </button>
          <button
            type="button"
            className="btn btn-outline-secondary btn-sm"
            aria-label="Export CSV"
          >
            📤 Export CSV
          </button>
        </div>
      </div>

      {/* Metrics */}
      <div className="row g-3 mb-4">
        {[
          {
            title: "Total Sessions",
            value: reportData
              ? reportData.total_sessions.toLocaleString()
              : "--",
            trend: "+25%",
            icon: "👥",
            color: "primary",
          },
          {
            title: "Avg Session Time (min)",
            value: reportData
              ? reportData.avg_session_time_minutes.toFixed(2)
              : "--",
            trend: "+8%",
            icon: "⏱",
            color: "success",
          },
          {
            title: "Security Events",
            value: reportData ? reportData.security_events : "--",
            trend: "+15%",
            icon: "🚨",
            color: "warning",
          },
          {
            title: "Reports Generated",
            value: reportData ? reportData.reports_generated : "--",
            trend: "+5%",
            icon: "📊",
            color: "info",
          },
        ].map(({ title, value, trend, icon, color }, i) => (
          <div key={i} className="col-xl-3 col-lg-6 col-md-6 col-12">
            <div
              className={`card border-start border-4 border-${color} shadow-sm h-100`}
            >
              <div className="card-body d-flex justify-content-between align-items-start">
                <div>
                  <h6 className="text-muted">{title}</h6>
                  <h3 className="fw-bold">{value}</h3>
                  <small className={`text-${color}`}>
                    📈 {trend} vs last month
                  </small>
                </div>
                <div style={{ fontSize: "1.8rem" }} aria-hidden="true">
                  {icon}
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Charts Row */}
      <div className="row g-4 mb-4">
        {/* Session Trends */}
<div className="col-lg-8 col-12">
  <div className="card shadow-sm">
    <div className="card-body">
      <h5 className="card-title mb-3">Session Trends</h5>

      <div className="d-flex align-items-end" style={{ height: "200px", overflowX: "auto" }}>
        {(() => {
          // Compute max AFTER data is fetched
          const maxSessions = Math.max(...sessionTrendData.map(d => d.sessions), 1);

          return sessionTrendData.map((item, idx) => (
            <div
  key={idx}
  className="flex-fill text-center me-2"
  style={{
    minWidth: "60px",
    display: "flex",
    flexDirection: "column",
    justifyContent: "flex-end",
    alignItems: "center",
  }}
>
  {item.sessions > 0 ? (
    <div
      style={{
        width: "28px",
        height: `${(item.sessions / Math.max(...sessionTrendData.map(d => d.sessions), 1)) * 180 + 10}px`,
        backgroundColor: "#0d6efd",
        borderRadius: "4px 4px 0 0",
        marginBottom: "8px",
        transition: "height 0.3s ease",
      }}
    ></div>
  ) : (
    <div style={{ height: "0px", width: "28px", marginBottom: "8px" }}></div>
  )}
  <small className="text-muted">{item.day}</small>
</div>
          ));
        })()}
      </div>
    </div>
  </div>
</div>
        {/* Connection Types */}
        <div className="col-lg-4 col-12">
          <div className="card shadow-sm">
            <div className="card-body">
              <h5 className="card-title mb-3">Connection Types</h5>
              <ul className="list-group list-group-flush">
                {reportData ? (
                  <>
                    <li className="list-group-item d-flex justify-content-between align-items-center">
                      <span>
                        <span className="badge bg-primary me-2"></span>SSH
                      </span>
                      <span className="fw-bold">
                        {reportData.connection_types.ssh.toFixed(2)}%
                      </span>
                    </li>
                    <li className="list-group-item d-flex justify-content-between align-items-center">
                      <span>
                        <span className="badge bg-success me-2"></span>RDP
                      </span>
                      <span className="fw-bold">
                        {reportData.connection_types.rdp.toFixed(2)}%
                      </span>
                    </li>
                    <li className="list-group-item d-flex justify-content-between align-items-center">
                      <span>
                        <span className="badge bg-warning me-2"></span>WEB
                      </span>
                      <span className="fw-bold">
                        {reportData.connection_types.web.toFixed(2)}%
                      </span>
                    </li>
                    <li className="list-group-item d-flex justify-content-between align-items-center">
                      <span>
                        <span className="badge bg-info me-2"></span>MULTISSH
                      </span>
                      <span className="fw-bold">
                        {reportData.connection_types.multissh.toFixed(2)}%
                      </span>
                    </li>
                  </>
                ) : (
                  <li className="list-group-item text-center text-muted py-3">
                    Loading...
                  </li>
                )}
              </ul>
            </div>
          </div>
        </div>
      </div>

      {/* Audit Events */}
      <div className="card shadow-sm">
        <div className="card-body">
          <h5 className="card-title mb-3">Recent Audit Events</h5>
          <div className="table-responsive">
            <table className="table table-hover table-bordered table-sm align-middle">
              <thead className="table-light">
                <tr>
                  <th scope="col">Time</th>
                  <th scope="col">User</th>
                  <th scope="col">Action</th>
                  <th scope="col">Device</th>
                  <th scope="col">Level</th>
                  <th scope="col">Details</th>
                </tr>
              </thead>
              <tbody>
                {auditEvents.length === 0 ? (
                  <tr>
                    <td colSpan="6" className="text-center text-muted py-4">
                      No recent audit events to display
                    </td>
                  </tr>
                ) : (
                  auditEvents.map((event, i) => (
                    <tr key={i}>
                      <td>{event.time}</td>
                      <td>{event.user}</td>
                      <td>{event.action}</td>
                      <td>{event.device}</td>
                      <td>{event.level}</td>
                      <td>{event.details}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}
