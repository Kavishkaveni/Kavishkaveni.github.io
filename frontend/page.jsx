

// import { useState } from "react"

// export default function Dashboard() {
//   const [chartData] = useState([
//     { day: "Mon", sessions: 15 },
//     { day: "Tue", sessions: 22 },
//     { day: "Wed", sessions: 28 },
//     { day: "Thu", sessions: 25 },
//     { day: "Fri", sessions: 32 },
//     { day: "Sat", sessions: 18 },
//     { day: "Sun", sessions: 12 },
//   ])

//   const recentSessions = [
//     { user: "John Doe", device: "PROD-SRV-01", type: "SSH", status: "Active", duration: "1h 24m", actions: ["👁️", "✏️"] },
//     { user: "Jane Smith", device: "DB-SRV-02", type: "RDP", status: "Active", duration: "2h 15m", actions: ["👁️", "✏️"] },
//     { user: "Mike Johnson", device: "WEB-SRV-03", type: "SSH", status: "Ended", duration: "45m", actions: ["👁️"] },
//     {
//       user: "Sarah Wilson",
//       device: "API-SRV-04",
//       type: "HTTPS",
//       status: "Active",
//       duration: "1.5h",
//       actions: ["👁️", "✏️"],
//     },
//   ]

//   const topUsers = [
//     { name: "John Doe", sessions: 15 },
//     { name: "Jane Smith", sessions: 12 },
//     { name: "Mike Johnson", sessions: 8 },
//     { name: "Sarah Wilson", sessions: 6 },
//   ]

//   const MetricCard = ({ title, value, change, icon, color = "primary" }) => (
//     <div className="bg-white rounded-3 p-4 shadow-sm h-100">
//       <div className="d-flex justify-content-between align-items-center">
//         <div>
//           <h6 className="text-muted mb-1">{title}</h6>
//           <h2 className="mb-0 fw-bold">{value}</h2>
//           <small className={`text-${change.includes("+") ? "success" : "danger"}`}>{change}</small>
//         </div>
//         <div className={`text-${color}`} style={{ fontSize: "2rem" }}>
//           {icon}
//         </div>
//       </div>
//     </div>
//   )

//   const StatusBadge = ({ status, type = "status" }) => {
//     const getStatusClass = () => {
//       if (type === "protocol") {
//         const protocolColors = {
//           SSH: "bg-primary bg-opacity-10 text-primary",
//           RDP: "bg-secondary bg-opacity-10 text-secondary",
//           HTTPS: "bg-success bg-opacity-10 text-success",
//         }
//         return protocolColors[status] || "bg-light text-dark"
//       }

//       const statusColors = {
//         Active: "bg-info bg-opacity-10 text-info",
//         Ended: "bg-danger bg-opacity-10 text-danger",
//         Online: "bg-success bg-opacity-10 text-success",
//         Offline: "bg-danger bg-opacity-10 text-danger",
//       }
//       return statusColors[status] || "bg-light text-dark"
//     }

//     return (
//       <span className={`badge ${getStatusClass()} fw-medium`} style={{ fontSize: "11px" }}>
//         {status}
//       </span>
//     )
//   }

//   return (
//     <div className="w-100">
//       {/* Metrics Row */}
//       <div className="row g-3 mb-4">
//         <div className="col-lg-4 col-md-6">
//           <MetricCard title="Active Sessions" value="24" change="↗️ +12%" icon="📈" color="primary" />
//         </div>
//         <div className="col-lg-4 col-md-6">
//           <MetricCard title="Total Devices" value="156" change="💚 All Online" icon="🖥️" color="success" />
//         </div>
//         <div className="col-lg-4 col-md-12">
//           <MetricCard title="Security Alerts" value="3" change="⚠️ New" icon="🚨" color="warning" />
//         </div>
//       </div>

//       {/* Charts and Tables Row */}
//       <div className="row g-3">
//         <div className="col-xl-8 col-lg-7">
//           <div className="bg-white rounded-3 p-4 shadow-sm mb-4">
//             <div className="d-flex justify-content-between align-items-center mb-3">
//               <h5 className="mb-0">Session Activity</h5>
//               <button className="btn btn-link btn-sm p-0">View Reports</button>
//             </div>
//             <div className="d-flex align-items-end overflow-auto" style={{ height: "200px" }}>
//               {chartData.map((item, index) => (
//                 <div key={index} className="flex-fill text-center me-2" style={{ minWidth: "60px" }}>
//                   <div
//                     className="bg-primary rounded-top"
//                     style={{
//                       height: `${(item.sessions / 35) * 100}%`,
//                       minHeight: "20px",
//                       marginBottom: "10px",
//                     }}
//                   ></div>
//                   <small className="text-muted">{item.day}</small>
//                   <br />
//                   <small className="fw-bold">{item.sessions}</small>
//                 </div>
//               ))}
//             </div>
//             <div className="text-center mt-2">
//               <small className="text-muted">Total Sessions: 28</small>
//             </div>
//           </div>

//           {/* Recent Sessions Table */}
//           <div className="bg-white rounded-3 p-4 shadow-sm">
//             <div className="d-flex justify-content-between align-items-center mb-3">
//               <h5 className="mb-0">Recent Sessions</h5>
//               <button className="btn btn-link btn-sm p-0">View All Sessions</button>
//             </div>
//             <div className="table-responsive">
//               <table className="table table-hover">
//                 <thead>
//                   <tr>
//                     <th>USER</th>
//                     <th>DEVICE</th>
//                     <th>TYPE</th>
//                     <th>STATUS</th>
//                     <th>DURATION</th>
//                     <th>ACTIONS</th>
//                   </tr>
//                 </thead>
//                 <tbody>
//                   {recentSessions.map((session, index) => (
//                     <tr key={index}>
//                       <td>{session.user}</td>
//                       <td>{session.device}</td>
//                       <td>
//                         <StatusBadge status={session.type} type="protocol" />
//                       </td>
//                       <td>
//                         <StatusBadge status={session.status} />
//                       </td>
//                       <td>{session.duration}</td>
//                       <td>
//                         {session.actions.map((action, i) => (
//                           <button key={i} className="btn btn-link btn-sm p-1 text-muted">
//                             {action}
//                           </button>
//                         ))}
//                       </td>
//                     </tr>
//                   ))}
//                 </tbody>
//               </table>
//             </div>
//           </div>
//         </div>

//         <div className="col-xl-4 col-lg-5">
//           <div className="bg-white rounded-3 p-4 shadow-sm">
//             <h5 className="mb-3">Top Users</h5>
//             {topUsers.map((user, index) => (
//               <div key={index} className="d-flex justify-content-between align-items-center mb-3">
//                 <div className="d-flex align-items-center">
//                   <div className="bg-secondary rounded-circle me-2" style={{ width: "32px", height: "32px" }}></div>
//                   <span>{user.name}</span>
//                 </div>
//                 <span className="badge bg-light text-dark">{user.sessions} sessions</span>
//               </div>
//             ))}
//           </div>
//         </div>
//       </div>
//     </div>
//   )
// }
import { useEffect, useState } from "react";

export default function Dashboard() {
  const [dashboard, setDashboard] = useState({
    active_sessions: 0,
    total_devices: 0,
    recent_sessions: [],
    session_activity: [],
    top_users: [],
  });
  const [loading, setLoading] = useState(true);

  // ✅ Fetch data using built-in fetch()
  useEffect(() => {
    const fetchData = async () => {
      try {
        const res = await fetch("http://localhost:9000/api/dashboard");
        const data = await res.json();
        setDashboard(data);
      } catch (error) {
        console.error("Error fetching dashboard:", error);
      } finally {
        setLoading(false);
      }
    };
    fetchData();
  }, []);

  const getStatusBadge = (status) => {
    switch (status) {
      case "Active":
        return <span className="badge bg-success">Active</span>;
      case "Ended":
        return <span className="badge bg-danger">Ended</span>;
      default:
        return <span className="badge bg-secondary">{status}</span>;
    }
  };

  const getTypeBadge = (type) => {
    switch (type) {
      case "SSH":
        return <span className="badge bg-primary">SSH</span>;
      case "RDP":
        return <span className="badge bg-warning text-dark">RDP</span>;
      case "HTTPS":
        return <span className="badge bg-info text-dark">HTTPS</span>;
      case "MULTISSH":
        return <span className="badge bg-dark">MULTISSH</span>;
      default:
        return <span className="badge bg-light text-dark">{type}</span>;
    }
  };

  if (loading) {
    return (
      <div className="text-center mt-5">
        <div className="spinner-border text-primary" role="status"></div>
        <p className="mt-3 text-muted">Loading Dashboard...</p>
      </div>
    );
  }

  return (
    <div className="container-fluid">
      <h4 className="mb-4">Dashboard Overview</h4>

      {/* Metrics Row */}
      <div className="row g-3 mb-4">
        <div className="col-md-4">
          <div className="card border-start border-4 border-success h-100">
            <div className="card-body">
              <h6 className="text-muted">Active Sessions</h6>
              <h3 className="fw-bold">{dashboard.active_sessions}</h3>
              <small className="text-success">Live count from backend</small>
            </div>
          </div>
        </div>
        <div className="col-md-4">
          <div className="card border-start border-4 border-primary h-100">
            <div className="card-body">
              <h6 className="text-muted">Total Devices</h6>
              <h3 className="fw-bold">{dashboard.total_devices}</h3>
              <small className="text-muted">Fetched from backend</small>
            </div>
          </div>
        </div>
        <div className="col-md-4">
          <div className="card border-start border-4 border-danger h-100">
            <div className="card-body">
              <h6 className="text-muted">Security Alerts</h6>
              <h3 className="fw-bold">0</h3>
              <small className="text-danger">⚠ Coming soon</small>
            </div>
          </div>
        </div>
      </div>

      {/* Session Activity + Top Users */}
      <div className="row g-4">
        {/* Session Activity Graph */}
        <div className="col-lg-8">
          <div className="card h-100">
            <div className="card-body">
              <h5 className="card-title mb-3">Session Activity (Last 7 Days)</h5>
              <div
                className="d-flex align-items-end overflow-auto"
                style={{ height: "200px" }}
              >
                {dashboard.session_activity.length > 0 ? (
                  dashboard.session_activity.map((item, i) => (
                    <div
                      key={i}
                      className="flex-fill text-center me-2"
                      style={{ minWidth: "60px" }}
                    >
                      <div
                        className="bg-primary rounded-top"
                        style={{
                          height: `${(item.count / 35) * 100}%`,
                          minHeight: "20px",
                          marginBottom: "10px",
                        }}
                      ></div>
                      <small className="text-muted">{item.day}</small>
                      <br />
                      <small className="fw-bold">{item.count}</small>
                    </div>
                  ))
                ) : (
                  <p className="text-muted">No session activity data</p>
                )}
              </div>
            </div>
          </div>
        </div>

        {/* Top Users */}
        <div className="col-lg-4">
          <div className="card h-100">
            <div className="card-body">
              <h5 className="card-title">Top Users</h5>
              {dashboard.top_users.length > 0 ? (
                <ul className="list-group">
                  {dashboard.top_users.map((user, i) => (
                    <li
                      key={i}
                      className="list-group-item d-flex justify-content-between align-items-center"
                    >
                      {user.name}
                      <span className="badge bg-secondary rounded-pill">
                        {user.sessions}
                      </span>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-muted">No top user data</p>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Recent Sessions */}
      <div className="card mt-4">
        <div className="card-body">
          <h5 className="card-title">Recent Sessions (Live)</h5>
          <div className="table-responsive">
            <table className="table table-bordered table-sm align-middle">
              <thead className="table-light">
                <tr>
                  <th>User</th>
                  <th>Device</th>
                  <th>Protocol</th>
                  <th>Status</th>
                  <th>Start Time</th>
                </tr>
              </thead>
              <tbody>
                {dashboard.recent_sessions.length > 0 ? (
                  dashboard.recent_sessions.map((s, i) => (
                    <tr key={i}>
                      <td>{s.user}</td>
                      <td>{s.device}</td>
                      <td>{getTypeBadge(s.protocol)}</td>
                      <td>{getStatusBadge(s.status)}</td>
                      <td>{new Date(s.start_time).toLocaleString()}</td>
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td colSpan="5" className="text-center text-muted">
                      No recent sessions found
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}
