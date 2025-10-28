import { useState } from "react";

export default function CertificateManagement() {
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState("");

  //  Step 1: When button clicked → trigger backend
  const handleGenerate = async () => {
    setLoading(true);
    setMsg("");

    try {
      const res = await fetch("http://localhost:9000/api/certificates/generate", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
      });

      //  Step 2: Parse backend response
      if (res.ok) {
        const data = await res.json();
        setMsg(data.message || "Certificate generated successfully and set active.");
      } else {
        const err = await res.text();
        setMsg(`Failed to generate certificate: ${err || res.statusText}`);
      }
    } catch (err) {
      setMsg(`Error: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };
  

  // Step 3: Render simple UI
  return (
    <div className="w-100">
      <div className="row justify-content-center">
        <div className="col-12 col-lg-10 col-xl-8">
          <div className="bg-white p-4 rounded shadow-sm">
            <h4 className="mb-2 fw-bold">Certificate Management</h4>
            <p className="text-muted mb-4">
              Generate and manage the active RSA key pair used for vault encryption.
            </p>

            <button
              className="btn btn-primary px-4 py-2"
              onClick={handleGenerate}
              disabled={loading}
            >
              {loading ? " Generating..." : " Generate Certificate"}
            </button>

            {msg && (
              <div
                className="alert mt-4 text-center"
                style={{
                  backgroundColor: "#f8f9fa",
                  border: "1px solid #e0e0e0",
                  borderRadius: "6px",
                  padding: "10px",
                  color: msg.includes("!") ? "green" : "red",
                }}
              >
                {msg}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
