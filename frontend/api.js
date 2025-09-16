const API_BASE_URL = 'http://localhost:9000/api';

class ApiService {
  async request(endpoint, options = {}) {
    const url = `${API_BASE_URL}${endpoint}`;
    const config = {
      headers: { 'Content-Type': 'application/json', ...options.headers },
      ...options,
    };

    console.log('API Request:', url, config);
    try {
      const response = await fetch(url, config);
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
      const data = await response.json();
      console.log('API Response:', data);
      return data;
    } catch (error) {
      console.error('API request failed:', error);
      throw error;
    }
  }

  // ---------------- Device API ----------------
  async getDevices(search = '') {
    const endpoint = search ? `/devices?search=${encodeURIComponent(search)}` : '/devices';
    return this.request(endpoint);
  }

  async getDevice(id) {
    return this.request(`/devices/${id}`);
  }

  async createDevice(deviceData) {
    // build payload with conditional web_url
    const payload = {
      name: deviceData.name,
      ip: deviceData.ip,
      device_type: deviceData.type,
      access_protocol: deviceData.access,
      status: deviceData.status,
    };
    if (deviceData.web_url && deviceData.web_url.trim()) {
      payload.web_url = deviceData.web_url.trim();
    }
    return this.request('/devices', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  async updateDevice(id, deviceData) {
    const payload = {
      name: deviceData.name,
      ip: deviceData.ip,
      device_type: deviceData.type,
      access_protocol: deviceData.access,
      status: deviceData.status,
    };
    if (deviceData.web_url && deviceData.web_url.trim()) {
      payload.web_url = deviceData.web_url.trim();
    }
    return this.request(`/devices/${id}`, {
      method: 'PUT',
      body: JSON.stringify(payload),
    });
  }

  async deleteDevice(id) {
    return this.request(`/devices/${id}`, { method: 'DELETE' });
  }

  // ---------------- Session API ----------------
  async getSessions(status = '') {
    const endpoint = status ? `/sessions?status=${encodeURIComponent(status)}` : '/sessions';
    return this.request(endpoint);
  }

  async createSession(sessionData) {
    return this.request('/sessions', {
      method: 'POST',
      body: JSON.stringify(sessionData),
    });
  }

  async endSession(sessionUuid, endData) {
    return this.request(`/sessions/${sessionUuid}/end`, {
      method: 'POST',
      body: JSON.stringify(endData),
    });
  }

  // ---------------- RDP File APIs ----------------
  async generateRdpFile(sessionData) {
    return this.request('/sessions/rdp', {
      method: 'POST',
      body: JSON.stringify(sessionData),
    });
  }

  async downloadRdpFile(sessionUuid) {
    const url = `${API_BASE_URL}/sessions/${sessionUuid}/rdp`;
    try {
      const response = await fetch(url, { headers: { 'Content-Type': 'application/json' } });
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
      const blob = await response.blob();
      const downloadUrl = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = downloadUrl;
      link.download = `session-${sessionUuid}.rdp`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      window.URL.revokeObjectURL(downloadUrl);
      return { success: true };
    } catch (error) {
      console.error('Download failed (RDP):', error);
      throw error;
    }
  }

  // ✅ Web flow RDP file (Option A)
  async downloadRdpFileWeb(sessionUuid) {
    const url = `${API_BASE_URL}/sessions/${sessionUuid}/rdp-web`;
    try {
      const response = await fetch(url, { headers: { 'Content-Type': 'application/json' } });
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
      const blob = await response.blob();
      const downloadUrl = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = downloadUrl;
      link.download = `session-${sessionUuid}.rdp`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      window.URL.revokeObjectURL(downloadUrl);
      return { success: true };
    } catch (error) {
      console.error('Download failed (Web RDP):', error);
      throw error;
    }
  }

  // ---------------- Vault API ----------------
  async getVaultEntries(deviceId = '') {
    const endpoint = deviceId ? `/vault?device_id=${deviceId}` : '/vault';
    return this.request(endpoint);
  }

  async createVaultEntry(vaultData) {
    return this.request('/vault', {
      method: 'POST',
      body: JSON.stringify(vaultData),
    });
  }

  async updateVaultEntry(id, vaultData) {
    return this.request(`/vault/${id}`, {
      method: 'PUT',
      body: JSON.stringify(vaultData),
    });
  }

  async deleteVaultEntry(id) {
    return this.request(`/vault/${id}`, { method: 'DELETE' });
  }

  // ---------------- Recording API ----------------
  async getRecordings(status = '') {
    const endpoint = status ? `/recordings?status=${encodeURIComponent(status)}` : '/recordings';
    return this.request(endpoint);
  }
}

export default new ApiService();
