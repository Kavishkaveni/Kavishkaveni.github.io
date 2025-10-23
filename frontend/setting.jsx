
export default function Settings() {
  return (
    <div className="w-100">
      <div className="row justify-content-center">
        <div className="col-12 col-lg-10 col-xl-8">
          <div className="bg-white p-4 rounded shadow-sm">
            <h4 className="mb-2">System Settings</h4>
            <p className="text-muted mb-4">Configure your PAM system preferences below.</p>

            <div className="row">
              {/* Left column settings */}
              <div className="col-md-6">
                <div className="mb-4">
                  <label className="form-label fw-medium">Session Timeout (minutes)</label>
                  <input type="number" className="form-control" defaultValue="30" min="1" />
                </div>
                <div className="mb-4">
                  <label className="form-label fw-medium">Max Concurrent Sessions</label>
                  <input type="number" className="form-control" defaultValue="10" min="1" />
                </div>
                <div className="mb-4">
                  <div className="form-check">
                    <input className="form-check-input" type="checkbox" id="recording" defaultChecked />
                    <label className="form-check-label" htmlFor="recording">
                      Enable session recording
                    </label>
                  </div>
                </div>
              </div>

              {/* Right column settings */}
              <div className="col-md-6">
                <div className="mb-4">
                  <label className="form-label fw-medium">Default Protocol</label>
                  <select className="form-select">
                    <option>SSH</option>
                    <option>RDP</option>
                    <option>WEB</option>
                    <option>MULTISSH</option>
                  </select>
                </div>
                <div className="mb-4">
                  <label className="form-label fw-medium">Log Retention (days)</label>
                  <input type="number" className="form-control" defaultValue="90" min="1" />
                </div>
                <div className="mb-4">
                  <div className="form-check">
                    <input className="form-check-input" type="checkbox" id="alerts" defaultChecked />
                    <label className="form-check-label" htmlFor="alerts">
                      Send security alerts
                    </label>
                  </div>
                </div>
              </div>
            </div>

            <hr className="my-4" />

            <div className="d-flex flex-column flex-sm-row gap-2 justify-content-end">
              <button className="btn btn-primary">💾 Save Changes</button>
              <button className="btn btn-outline-secondary">🔄 Reset to Defaults</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
