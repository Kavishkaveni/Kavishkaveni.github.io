

// export default function Recordings() {
//   const recordings = [
//     {
//       session: "SES-001",
//       user: "John Doe",
//       device: "PROD-SRV-01",
//       type: "SSH",
//       date: "2024-06-26 10:30 AM",
//       duration: "1h 24m",
//       size: "156 MB",
//       status: "Available",
//     },
//     {
//       session: "SES-002",
//       user: "Jane Smith",
//       device: "DB-SRV-02",
//       type: "RDP",
//       date: "2024-06-26 9:15 AM",
//       duration: "2h 15m",
//       size: "312 MB",
//       status: "Available",
//     },
//     {
//       session: "SES-003",
//       user: "Mike Johnson",
//       device: "WEB-SRV-03",
//       type: "SSH",
//       date: "2024-06-25 8:45 AM",
//       duration: "45m",
//       size: "89 MB",
//       status: "Processing",
//     },
//     {
//       session: "SES-004",
//       user: "Sarah Wilson",
//       device: "API-SRV-04",
//       type: "RDP",
//       date: "2024-06-25 11:00 AM",
//       duration: "1.5h",
//       size: "167 MB",
//       status: "Available",
//     },
//     {
//       session: "SES-005",
//       user: "David Brown",
//       device: "TEST-SRV-05",
//       type: "SSH",
//       date: "2024-06-23 7:30 AM",
//       duration: "3h 12m",
//       size: "445 MB",
//       status: "Available",
//     },
//     {
//       session: "SES-006",
//       user: "Emily Davis",
//       device: "STAGING-SRV-06",
//       type: "RDP",
//       date: "2024-06-24 10:45 AM",
//       duration: "2h 45m",
//       size: "389 MB",
//       status: "Archived",
//     },
//   ]

//   const getStatusClass = (status) => {
//     switch (status) {
//       case "Available":
//         return "badge bg-success"
//       case "Processing":
//         return "badge bg-warning text-dark"
//       case "Archived":
//         return "badge bg-secondary"
//       default:
//         return "badge bg-light text-dark"
//     }
//   }

//   const getProtocolClass = (type) => {
//     switch (type.toLowerCase()) {
//       case "ssh":
//         return "badge bg-primary"
//       case "rdp":
//         return "badge bg-info text-dark"
//       case "https":
//         return "badge bg-warning text-dark"
//       default:
//         return "badge bg-light text-dark"
//     }
//   }

//   return (
//     <div className="container-fluid">
//       <div className="mb-4">
//         <p className="text-muted mb-3">View and manage recorded sessions</p>

//         <div className="d-flex flex-column flex-md-row justify-content-between align-items-start align-items-md-center mb-4 gap-3">
//           <div className="position-relative" style={{ minWidth: "250px", width: "100%" }}>
//             <input
//               type="text"
//               className="form-control ps-5"
//               placeholder="Search recordings"
//               aria-label="Search recordings"
//             />
//             <span
//               className="position-absolute top-50 start-0 translate-middle-y ms-3 text-muted"
//               style={{ fontSize: "1.25rem", pointerEvents: "none" }}
//               aria-hidden="true"
//             >
//               🔍
//             </span>
//           </div>
//         </div>

//         {/* Smaller Metrics Row */}
//         <div className="row mb-4">
//           {[
//             { icon: "📹", label: "Total Recordings", value: "6", colorClass: "text-primary" },
//             { icon: "💾", label: "Storage Used", value: "1.2 GB", colorClass: "text-success" },
//             { icon: "📊", label: "This Week", value: "24", colorClass: "text-warning" },
//           ].map(({ icon, label, value, colorClass }, idx) => (
//             <div key={idx} className="col-lg-4 col-md-6 col-12 mb-3">
//               <div className="card text-center shadow-sm py-2 h-100">
//                 <div className={`mb-1 ${colorClass}`} style={{ fontSize: "1.5rem" }}>
//                   {icon}
//                 </div>
//                 <h6 className="text-muted mb-1">{label}</h6>
//                 <h4 className="fw-bold mb-0">{value}</h4>
//               </div>
//             </div>
//           ))}
//         </div>
//       </div>

//       {/* Recording Library Table */}
//       <div className="card shadow-sm">
//         <div className="card-header d-flex justify-content-between align-items-center">
//           <h5 className="mb-0">Recording Library</h5>
//           <button className="btn btn-link btn-sm">View All</button>
//         </div>
//         <div className="table-responsive">
//           <table className="table table-hover align-middle mb-0">
//             <thead className="table-light">
//               <tr>
//                 <th>SESSION</th>
//                 <th>USER</th>
//                 <th>DEVICE</th>
//                 <th>TYPE</th>
//                 <th>DATE</th>
//                 <th>DURATION</th>
//                 <th>SIZE</th>
//                 <th>STATUS</th>
//                 <th>ACTIONS</th>
//               </tr>
//             </thead>
//             <tbody>
//               {recordings.map((recording, i) => (
//                 <tr key={i}>
//                   <td className="fw-semibold">{recording.session}</td>
//                   <td>{recording.user}</td>
//                   <td>{recording.device}</td>
//                   <td>
//                     <span className={getProtocolClass(recording.type)}>{recording.type}</span>
//                   </td>
//                   <td>{recording.date}</td>
//                   <td>{recording.duration}</td>
//                   <td>{recording.size}</td>
//                   <td>
//                     <span className={getStatusClass(recording.status)}>{recording.status}</span>
//                   </td>
//                   <td>
//                     <div className="d-flex gap-2">
//                       <button
//                         className="btn btn-sm btn-outline-primary d-flex align-items-center"
//                         title={`Play recording ${recording.session}`}
//                         aria-label={`Play recording ${recording.session}`}
//                       >
//                         <span className="me-1">▶️</span>
//                         <span className="d-none d-md-inline">Play</span>
//                       </button>
//                       <button
//                         className="btn btn-sm btn-outline-secondary d-flex align-items-center"
//                         title={`Download recording ${recording.session}`}
//                         aria-label={`Download recording ${recording.session}`}
//                       >
//                         <span className="me-1">⬇️</span>
//                         <span className="d-none d-md-inline">Download</span>
//                       </button>
//                     </div>
//                   </td>
//                 </tr>
//               ))}
//             </tbody>
//           </table>
//         </div>
//       </div>
//     </div>
//   )
// }
import { useState } from "react"

export default function Recordings() {
  const [searchTerm, setSearchTerm] = useState("")

  const recordings = [
    {
      session: "SES-001",
      user: "John Doe",
      device: "PROD-SRV-01",
      type: "SSH",
      date: "2024-06-26 10:30 AM",
      duration: "1h 24m",
      size: "156 MB",
      status: "Available",
    },
    {
      session: "SES-002",
      user: "Jane Smith",
      device: "DB-SRV-02",
      type: "RDP",
      date: "2024-06-26 9:15 AM",
      duration: "2h 15m",
      size: "312 MB",
      status: "Available",
    },
    {
      session: "SES-003",
      user: "Mike Johnson",
      device: "WEB-SRV-03",
      type: "SSH",
      date: "2024-06-25 8:45 AM",
      duration: "45m",
      size: "89 MB",
      status: "Processing",
    },
    {
      session: "SES-004",
      user: "Sarah Wilson",
      device: "API-SRV-04",
      type: "RDP",
      date: "2024-06-25 11:00 AM",
      duration: "1.5h",
      size: "167 MB",
      status: "Available",
    },
    {
      session: "SES-005",
      user: "David Brown",
      device: "TEST-SRV-05",
      type: "SSH",
      date: "2024-06-23 7:30 AM",
      duration: "3h 12m",
      size: "445 MB",
      status: "Available",
    },
    {
      session: "SES-006",
      user: "Emily Davis",
      device: "STAGING-SRV-06",
      type: "RDP",
      date: "2024-06-24 10:45 AM",
      duration: "2h 45m",
      size: "389 MB",
      status: "Archived",
    },
  ]

  const filtered = recordings.filter(
    (r) =>
      r.session.toLowerCase().includes(searchTerm.toLowerCase()) ||
      r.user.toLowerCase().includes(searchTerm.toLowerCase()) ||
      r.device.toLowerCase().includes(searchTerm.toLowerCase())
  )

  const getStatusClass = (status) => {
    switch (status) {
      case "Available":
        return "badge bg-success"
      case "Processing":
        return "badge bg-warning text-dark"
      case "Archived":
        return "badge bg-secondary"
      default:
        return "badge bg-light text-dark"
    }
  }

  const getProtocolClass = (type) => {
    switch (type.toLowerCase()) {
      case "ssh":
        return "badge bg-primary"
      case "rdp":
        return "badge bg-info text-dark"
      case "https":
        return "badge bg-warning text-dark"
      default:
        return "badge bg-light text-dark"
    }
  }

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

        {/* Metric Cards */}
        <div className="row mb-4">
          {[
            { icon: "📹", label: "Total Recordings", value: recordings.length, colorClass: "text-primary" },
            { icon: "💾", label: "Storage Used", value: "1.2 GB", colorClass: "text-success" },
            { icon: "📊", label: "This Week", value: "24", colorClass: "text-warning" },
          ].map(({ icon, label, value, colorClass }, idx) => (
            <div key={idx} className="col-lg-4 col-md-6 col-12 mb-3">
              <div className="card text-center shadow-sm py-3 h-100 hover-shadow border-0">
                <div className={`mb-1 ${colorClass}`} style={{ fontSize: "1.6rem" }}>
                  {icon}
                </div>
                <div className="text-muted small">{label}</div>
                <h5 className="fw-bold mb-0">{value}</h5>
              </div>
            </div>
          ))}
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
                <th>DURATION</th>
                <th>SIZE</th>
                <th>STATUS</th>
                <th>ACTIONS</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((recording, i) => (
                <tr key={i}>
                  <td className="fw-semibold">{recording.session}</td>
                  <td>{recording.user}</td>
                  <td>{recording.device}</td>
                  <td>
                    <span className={getProtocolClass(recording.type)}>{recording.type}</span>
                  </td>
                  <td>{recording.date}</td>
                  <td>{recording.duration}</td>
                  <td>{recording.size}</td>
                  <td>
                    <span className={getStatusClass(recording.status)}>{recording.status}</span>
                  </td>
                  <td>
                    <div className="d-flex gap-2">
                      <button
                        className="btn btn-sm btn-outline-primary"
                        disabled={recording.status !== "Available"}
                        title="Play recording"
                      >
                        ▶️ <span className="d-none d-md-inline ms-1">Play</span>
                      </button>
                      <button
                        className="btn btn-sm btn-outline-secondary"
                        disabled={recording.status !== "Available"}
                        title="Download recording"
                      >
                        ⬇️ <span className="d-none d-md-inline ms-1">Download</span>
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan="9" className="text-center text-muted py-4">
                    No recordings found.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
