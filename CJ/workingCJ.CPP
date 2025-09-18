// CJ.cpp   QCM Credential Joiner (service + manual)
// RDP flow (unchanged) + WEB flow: forward to local CH (127.0.0.1:10443)
//
// Build: VS2017+  /MT, Unicode; link winhttp, shell32, advapi32, ws2_32, Wtsapi32, Userenv
#ifndef _NO_INIT_ALL
#define _NO_INIT_ALL 1
#endif
#ifdef _MSC_VER
#pragma warning(disable:5030)
#endif

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <winhttp.h>
#include <shellapi.h>
#include <strsafe.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <string>
#include <vector>

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")

// ---------------- logging -> C:\PAM\cj.log ----------------------------------
static void LogF(PCWSTR fmt, ...)
{
	CreateDirectoryW(L"C:\\PAM", nullptr);
	wchar_t line[2048];
	va_list ap; va_start(ap, fmt);
	StringCchVPrintfW(line, _countof(line), fmt, ap);
	va_end(ap);

	SYSTEMTIME st; GetLocalTime(&st);
	wchar_t msg[2300];
	StringCchPrintfW(msg, _countof(msg),
		L"%04u-%02u-%02u %02u:%02u:%02u [CJ] %s\r\n",
		st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, line);

	HANDLE h = CreateFileW(L"C:\\PAM\\cj.log", FILE_APPEND_DATA, FILE_SHARE_READ,
		nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
	if (h != INVALID_HANDLE_VALUE) {
		DWORD cb = (DWORD)(lstrlenW(msg) * sizeof(wchar_t));
		WriteFile(h, msg, cb, &cb, nullptr);
		CloseHandle(h);
	}
}

// ---------------- helpers ----------------------------------------------------
static std::wstring ToW(const std::string& s) {
	if (s.empty()) return L"";
	int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
	std::wstring out(n, 0);
	MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &out[0], n);
	return out;
}
static std::string ToA(const std::wstring& s) {
	if (s.empty()) return std::string();
	int n = WideCharToMultiByte(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0, nullptr, nullptr);
	std::string out(n, 0);
	WideCharToMultiByte(CP_UTF8, 0, s.c_str(), (int)s.size(), &out[0], n, nullptr, nullptr);
	return out;
}

// Accept raw UUID or "CJ/1 UUID=<uuid>"
static std::wstring ExtractUuid(const std::wstring& line)
{
	if (line.size() >= 36 && line.find(L'-') != std::wstring::npos && line.find(L"UUID=") == std::wstring::npos) {
		std::wstring u = line;
		while (!u.empty() && (u.back() == L'\r' || u.back() == L'\n')) u.pop_back();
		return u;
	}
	size_t p = line.find(L"UUID=");
	if (p != std::wstring::npos) {
		p += 5;
		std::wstring u = line.substr(p);
		while (!u.empty() && (u.back() == L'\r' || u.back() == L'\n' || u.back() == L' ' || u.back() == L'\t')) u.pop_back();
		return u;
	}
	size_t sp = line.find_last_of(L" \t");
	std::wstring out = (sp == std::wstring::npos) ? line : line.substr(sp + 1);
	while (!out.empty() && (out.back() == L'\r' || out.back() == L'\n')) out.pop_back();
	return out;
}

// ---------------- tolerant JSON pickers -------------------------------------
static std::string json_get_any(const std::string& body, const char* key)
{
	std::string needle = std::string("\"") + key + "\"";
	size_t p = body.find(needle);
	if (p == std::string::npos) return "";
	p = body.find(':', p);
	if (p == std::string::npos) return "";
	while (p < body.size() && (body[p] == ':' || body[p] == ' ' || body[p] == '\t')) ++p;
	if (p >= body.size()) return "";

	if (body[p] == '"') {
		size_t q = body.find('"', p + 1);
		if (q == std::string::npos) return "";
		return body.substr(p + 1, q - (p + 1));
	}
	else {
		size_t q = p;
		while (q < body.size() && body[q] != ',' && body[q] != '}') ++q;
		size_t r = q;
		while (r > p && (body[r - 1] == ' ' || body[r - 1] == '\t')) --r;
		return body.substr(p, r - p);
	}
}
static std::wstring json_ws(const std::string& body, const char* key) {
	return ToW(json_get_any(body, key));
}
static unsigned json_u32(const std::string& body, const char* key, unsigned defv) {
	std::string v = json_get_any(body, key);
	if (v.empty()) return defv;
	try { return (unsigned)std::stoul(v); }
	catch (...) { return defv; }
}

// ---------------- HTTP helpers ----------------------------------------------
static bool http_get(const std::wstring& host, INTERNET_PORT port, const std::wstring& path, std::string& out)
{
	bool ok = false;
	HINTERNET s = WinHttpOpen(L"CJ/1.1", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
		WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
	if (!s) { LogF(L"WinHttpOpen failed ec=%lu", GetLastError()); return false; }

	HINTERNET c = WinHttpConnect(s, host.c_str(), port, 0);
	if (!c) { LogF(L"WinHttpConnect failed ec=%lu", GetLastError()); WinHttpCloseHandle(s); return false; }

	HINTERNET r = WinHttpOpenRequest(c, L"GET", path.c_str(), nullptr,
		WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
	if (!r) { LogF(L"WinHttpOpenRequest failed ec=%lu", GetLastError()); WinHttpCloseHandle(c); WinHttpCloseHandle(s); return false; }

	if (WinHttpSendRequest(r, WINHTTP_NO_ADDITIONAL_HEADERS, 0, 0, 0, 0, 0) &&
		WinHttpReceiveResponse(r, nullptr))
	{
		for (;;) {
			DWORD avail = 0;
			if (!WinHttpQueryDataAvailable(r, &avail)) { LogF(L"WinHttpQueryDataAvailable failed ec=%lu", GetLastError()); break; }
			if (avail == 0) { ok = true; break; }
			std::string chunk(avail, '\0');
			DWORD rd = 0;
			if (!WinHttpReadData(r, &chunk[0], avail, &rd)) { LogF(L"WinHttpReadData failed ec=%lu", GetLastError()); break; }
			if (rd == 0) { ok = true; break; }
			chunk.resize(rd);
			out.append(chunk);
		}
	}
	else {
		LogF(L"HTTP send/recv failed ec=%lu", GetLastError());
	}

	WinHttpCloseHandle(r);
	WinHttpCloseHandle(c);
	WinHttpCloseHandle(s);
	return ok;
}

// NEW: tiny POST JSON helper (talk to CH at 127.0.0.1:10443)
static bool http_post_json(const std::wstring& host, INTERNET_PORT port, const std::wstring& path,
	const std::string& jsonBody, DWORD* httpStatus /*opt*/)
{
	bool ok = false;
	if (httpStatus) *httpStatus = 0;

	HINTERNET hSession = WinHttpOpen(L"CJ/1.1", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
		WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
	if (!hSession) { LogF(L"WinHttpOpen(POST) failed ec=%lu", GetLastError()); return false; }

	HINTERNET hConnect = WinHttpConnect(hSession, host.c_str(), port, 0);
	if (!hConnect) { LogF(L"WinHttpConnect(POST) failed ec=%lu", GetLastError()); WinHttpCloseHandle(hSession); return false; }

	HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"POST", path.c_str(), nullptr,
		WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
	if (!hRequest) { LogF(L"WinHttpOpenRequest(POST) failed ec=%lu", GetLastError()); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession); return false; }

	static const wchar_t* kHdr = L"Content-Type: application/json\r\n";
	BOOL sent = WinHttpSendRequest(hRequest, kHdr, (DWORD)wcslen(kHdr),
		(LPVOID)jsonBody.data(), (DWORD)jsonBody.size(), (DWORD)jsonBody.size(), 0);

	if (!sent) {
		LogF(L"WinHttpSendRequest(POST) failed ec=%lu", GetLastError());
	}
	else if (!WinHttpReceiveResponse(hRequest, nullptr)) {
		LogF(L"WinHttpReceiveResponse(POST) failed ec=%lu", GetLastError());
	}
	else {
		DWORD status = 0, slen = sizeof(status);
		if (WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
			WINHTTP_HEADER_NAME_BY_INDEX, &status, &slen, WINHTTP_NO_HEADER_INDEX)) {
			if (httpStatus) *httpStatus = status;
			ok = (status >= 200 && status < 300);
			LogF(L"POST %s -> HTTP %lu", path.c_str(), status);
		}
		else {
			ok = true; // no status header, treat as ok if no error so far
		}
	}

	WinHttpCloseHandle(hRequest);
	WinHttpCloseHandle(hConnect);
	WinHttpCloseHandle(hSession);
	return ok;
}

// run console tool hidden (manual mode helper)
static DWORD runHidden(PCWSTR exe, std::wstring& cmdline)
{
	STARTUPINFOW si{}; si.cb = sizeof(si);
	si.dwFlags = STARTF_USESHOWWINDOW; si.wShowWindow = SW_HIDE;
	PROCESS_INFORMATION pi{};
	if (!CreateProcessW(exe, &cmdline[0], nullptr, nullptr, FALSE,
		CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
		return GetLastError();
	}
	DWORD ec = 0;
	WaitForSingleObject(pi.hProcess, INFINITE);
	GetExitCodeProcess(pi.hProcess, &ec);
	CloseHandle(pi.hThread);
	CloseHandle(pi.hProcess);
	return ec;
}

// ---------------- Session helpers (RDP) -------------------------------------

static std::wstring ClientAddrToString(PWTS_CLIENT_ADDRESS addr)
{
	if (!addr) return L"";
	if (addr->AddressFamily == AF_INET) {
		unsigned char* a = (unsigned char*)addr->Address;
		wchar_t buf[64];
		StringCchPrintfW(buf, _countof(buf), L"%u.%u.%u.%u", (unsigned)a[2], (unsigned)a[3], (unsigned)a[4], (unsigned)a[5]);
		return std::wstring(buf);
	}
	return L"";
}

static void LogSessionRow(DWORD sid, const wchar_t* label, const std::wstring& user, int state, int proto, const std::wstring& ip)
{
	const wchar_t* st = L"?";
	switch ((WTS_CONNECTSTATE_CLASS)state) {
	case WTSActive: st = L"Active"; break;
	case WTSConnected: st = L"Connected"; break;
	case WTSConnectQuery: st = L"ConnectQuery"; break;
	case WTSShadow: st = L"Shadow"; break;
	case WTSDisconnected: st = L"Disconnected"; break;
	case WTSIdle: st = L"Idle"; break;
	case WTSListen: st = L"Listen"; break;
	case WTSReset: st = L"Reset"; break;
	case WTSDown: st = L"Down"; break;
	case WTSInit: st = L"Init"; break;
	}
	LogF(L"  sid=%u state=%s user='%s' proto=%d ip=%s  %s",
		sid, st, user.c_str(), proto, ip.c_str(), label ? label : L"");
}

// Find first *Active RDP* session, with small wait window
static DWORD FindActiveRdpSessionWithWait(DWORD maxWaitMs = 12000, DWORD pollMs = 1000)
{
	DWORD waited = 0;
	for (;;) {
		PWTS_SESSION_INFO pSessionInfo = nullptr;
		DWORD count = 0;
		if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &pSessionInfo, &count)) {
			LogF(L"WTSEnumerateSessionsW failed ec=%u", GetLastError());
			return (DWORD)-1;
		}

		DWORD foundSid = (DWORD)-1;

		for (DWORD i = 0; i < count; ++i) {
			DWORD sid = pSessionInfo[i].SessionId;

			DWORD bytes = 0;
			WTS_CONNECTSTATE_CLASS* pState = nullptr;
			if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSConnectState, (LPWSTR*)&pState, &bytes) || !pState) {
				if (pState) WTSFreeMemory(pState);
				continue;
			}
			WTS_CONNECTSTATE_CLASS state = *pState;
			WTSFreeMemory(pState);

			LPWSTR pUser = nullptr;
			std::wstring user;
			if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSUserName, (LPWSTR*)&pUser, &bytes) && pUser) {
				user = pUser;
				WTSFreeMemory(pUser);
			}

			LPWSTR pProto = nullptr;
			int proto = 0;
			if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSClientProtocolType, (LPWSTR*)&pProto, &bytes) && pProto) {
				proto = *(USHORT*)pProto; // USHORT
				WTSFreeMemory(pProto);
			}

			PWTS_CLIENT_ADDRESS pAddr = nullptr;
			std::wstring ip;
			if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSClientAddress, (LPWSTR*)&pAddr, &bytes) && pAddr) {
				ip = ClientAddrToString(pAddr);
				WTSFreeMemory(pAddr);
			}

			LogSessionRow(sid, L"(inventory)", user, (int)state, proto, ip);

			if (state == WTSActive && proto == 2) {
				foundSid = sid;
				break;
			}
		}

		WTSFreeMemory(pSessionInfo);

		if (foundSid != (DWORD)-1) {
			LogF(L"Active RDP session found: sid=%u", foundSid);
			return foundSid;
		}
		if (waited >= maxWaitMs) {
			LogF(L"No ACTIVE RDP session found after waiting (proto=2).");
			return (DWORD)-1;
		}
		Sleep(pollMs);
		waited += pollMs;
	}
}

static DWORD GetConsoleSession()
{
	DWORD sid = WTSGetActiveConsoleSessionId();
	if (sid == 0xFFFFFFFF) return (DWORD)-1;
	return sid;
}

static DWORD LaunchInSessionAndWait(const std::wstring& commandLine, DWORD sessionId = (DWORD)-1, DWORD timeoutMs = 30000)
{
	if (sessionId == (DWORD)-1) {
		sessionId = FindActiveRdpSessionWithWait(0, 0);
		if (sessionId == (DWORD)-1)
			sessionId = GetConsoleSession();
		if (sessionId == (DWORD)-1) {
			LogF(L"No session available to launch process");
			return (DWORD)-1;
		}
	}

	HANDLE hUserToken = nullptr;
	if (!WTSQueryUserToken(sessionId, &hUserToken)) {
		DWORD ec = GetLastError();
		LogF(L"WTSQueryUserToken failed ec=%lu sess=%u", ec, sessionId);
		return ec;
	}

	HANDLE hPrimary = nullptr;
	if (!DuplicateTokenEx(hUserToken, MAXIMUM_ALLOWED, nullptr, SecurityIdentification, TokenPrimary, &hPrimary)) {
		DWORD ec = GetLastError();
		LogF(L"DuplicateTokenEx failed ec=%lu", ec);
		CloseHandle(hUserToken);
		return ec;
	}

	LPVOID env = nullptr;
	if (!CreateEnvironmentBlock(&env, hPrimary, FALSE)) {
		DWORD ec = GetLastError();
		LogF(L"CreateEnvironmentBlock failed ec=%lu (continuing without env)", ec);
		env = nullptr;
	}

	STARTUPINFOW si{}; si.cb = sizeof(si);
	si.lpDesktop = const_cast<LPWSTR>(L"winsta0\\default");

	PROCESS_INFORMATION pi{};
	std::wstring cmd = commandLine;

	BOOL ok = CreateProcessAsUserW(
		hPrimary,
		nullptr,
		&cmd[0],
		nullptr,
		nullptr,
		FALSE,
		CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_CONSOLE,
		env,
		nullptr,
		&si,
		&pi
	);

	DWORD rc = 0;
	if (!ok) {
		rc = GetLastError();
		LogF(L"CreateProcessAsUserW failed ec=%lu cmd=%s sess=%u", rc, commandLine.c_str(), sessionId);
	}
	else {
		LogF(L"Created process in session %u pid=%u cmd=%s", sessionId, (unsigned)pi.dwProcessId, commandLine.c_str());
		DWORD wait = WaitForSingleObject(pi.hProcess, timeoutMs);
		if (wait == WAIT_OBJECT_0) {
			DWORD exitCode = 0;
			GetExitCodeProcess(pi.hProcess, &exitCode);
			LogF(L"Process exited with code %u", exitCode);
			rc = exitCode;
		}
		else if (wait == WAIT_TIMEOUT) {
			LogF(L"Process wait timed out after %u ms (pid=%u)", timeoutMs, (unsigned)pi.dwProcessId);
			rc = (DWORD)-1;
		}
		else {
			LogF(L"WaitForSingleObject failed %u", GetLastError());
			rc = (DWORD)-1;
		}
		CloseHandle(pi.hThread);
		CloseHandle(pi.hProcess);
	}

	if (env) DestroyEnvironmentBlock(env);
	CloseHandle(hPrimary);
	CloseHandle(hUserToken);
	return rc;
}
// NEW: wait until 127.0.0.1:<port> is reachable (up to max_wait_ms)
static bool WaitForLocalPort(int port, DWORD max_wait_ms) {
	WSADATA w; if (WSAStartup(MAKEWORD(2, 2), &w) != 0) return false;
	DWORD waited = 0;
	for (;;) {
		SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
		if (s != INVALID_SOCKET) {
			sockaddr_in a{}; a.sin_family = AF_INET; a.sin_port = htons((u_short)port);
			inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
			u_long nb = 1; ioctlsocket(s, FIONBIO, &nb);
			int r = connect(s, (sockaddr*)&a, sizeof(a));
			if (r == 0) { closesocket(s); WSACleanup(); return true; }
			int e = WSAGetLastError();
			if (e == WSAEWOULDBLOCK || e == WSAEINPROGRESS) {
				fd_set wfds; FD_ZERO(&wfds); FD_SET(s, &wfds);
				TIMEVAL tv{ 0, 300 * 1000 };
				if (select(0, nullptr, &wfds, nullptr, &tv) > 0) {
					closesocket(s); WSACleanup(); return true;
				}
			}
			closesocket(s);
		}
		if (waited >= max_wait_ms) { WSACleanup(); return false; }
		Sleep(300);
		waited += 300;
	}
}

// ---------------- Core one-shot ---------------------------------------------
static void DoConnect(const std::wstring& uuid, const std::wstring& backendHost, INTERNET_PORT backendPort)
{
	LogF(L"Handle UUID=%s backend=%s:%u", uuid.c_str(), backendHost.c_str(), (unsigned)backendPort);

	// Resolve UUID at backend
	std::wstring path = L"/cj/resolve/" + uuid;
	std::string body;
	if (!http_get(backendHost, backendPort, path, body)) {
		LogF(L"HTTP request failed");
		return;
	}
	LogF(L"RAW JSON: %s", ToW(body).c_str());

	std::wstring status = json_ws(body, "status");
	std::wstring ip = json_ws(body, "target_ip");
	unsigned     port = json_u32(body, "target_port", 3389);
	std::wstring user = json_ws(body, "username");
	std::wstring pass = json_ws(body, "password");
	unsigned     ttl = json_u32(body, "ttl_secs", 300);

	std::wstring proto = json_ws(body, "protocol");  // "RDP" | "SSH" | "WEB"
	std::wstring url = json_ws(body, "url");

	if (status != L"ok" || user.empty() || pass.empty()) {
		LogF(L"Missing fields from backend");
		return;
	}
	LogF(L"Parsed proto=%s ip=%s port=%u user=%s ttl=%u", proto.c_str(), ip.c_str(), port, user.c_str(), ttl);

	// ===================== WEB path → forward to CH ======================
	if (_wcsicmp(proto.c_str(), L"WEB") == 0) {
		if (url.empty()) {
			LogF(L"WEB flow requires 'url' in resolve JSON; aborting.");
			return;
		}

		// Build JSON body for CH
		std::string json = std::string("{\"type\":\"web\",\"uuid\":\"")
			+ ToA(uuid) + "\",\"url\":\"" + ToA(url)
			+ "\",\"username\":\"" + ToA(user)
			+ "\",\"password\":\"" + ToA(pass) + "\"}";

		const wchar_t*  chHost = L"localhost";
		INTERNET_PORT   chPort = 10443;

		// NEW: Wait up to 90 seconds for CH to be listening
		LogF(L"Waiting for CH on %s:%u (max 90s)...", chHost, (unsigned)chPort);
		if (!WaitForLocalPort((int)chPort, 90 * 1000)) {
			LogF(L"CH port %u not reachable after 90s; giving up.", (unsigned)chPort);
			return;
		}

		// Try POST (5 quick retries once CH is alive)
		DWORD httpStatus = 0;
		bool ok = false;
		for (int i = 1; i <= 5 && !ok; ++i) {
			ok = http_post_json(chHost, chPort, L"/", json, &httpStatus);
			if (ok) {
				LogF(L"CH accepted WEB request (status=%lu).", httpStatus);
				break;
			}
			LogF(L"CH POST attempt %d/5 failed (status=%lu or connect error). Retrying in 2000 ms...",
				i, httpStatus);
			Sleep(2000);
		}

		if (!ok) {
			LogF(L"CH POST failed after retries. Is CH listening on %u and reachable?", (unsigned)chPort);
		}
		return; // web path done
	}
		
	// =================== end WEB path ===================================

	// ---------------- RDP path ----------------
	DWORD sessionId = FindActiveRdpSessionWithWait(12000 /*maxWait*/, 1000 /*poll*/);
	if (sessionId == (DWORD)-1) {
		sessionId = GetConsoleSession();
		if (sessionId == (DWORD)-1) {
			LogF(L"No interactive session available to launch mstsc");
			return;
		}
		LogF(L"Falling back to console session %u", sessionId);
	}
	else {
		LogF(L"Selected ACTIVE RDP session %u", sessionId);
	}

	wchar_t sysdir[MAX_PATH] = { 0 };
	GetSystemDirectoryW(sysdir, MAX_PATH);
	std::wstring cmdkeyExe = std::wstring(sysdir) + L"\\cmdkey.exe";
	std::wstring target = L"TERMSRV/" + ip;

	std::wstring addCmd = cmdkeyExe + L" /generic:" + target + L" /user:\"" + user + L"\" /pass:\"" + pass + L"\"";
	DWORD rcAdd = LaunchInSessionAndWait(addCmd, sessionId, 20000);
	Sleep(1000);
	if (rcAdd == 0) LogF(L"CredWrite (in-session) OK target=%s user=%s", target.c_str(), user.c_str());
	else LogF(L"CredWrite (in-session) failed rc=%lu", rcAdd);

	wchar_t args[256];
	StringCchPrintfW(args, _countof(args), L"/v:%s:%u /f", ip.c_str(), port ? port : 3389);
	std::wstring mstscCmd = L"mstsc.exe "; mstscCmd += args;
	LogF(L"Launching mstsc in session %u: %s", sessionId, args);
	DWORD rcMst = LaunchInSessionAndWait(mstscCmd, sessionId, 10000);
	if (rcMst != 0) {
		LogF(L"mstsc launch returned rc=%lu (this may be non-fatal)", rcMst);
	}

	Sleep(25000);

	std::wstring delCmd = cmdkeyExe + L" /delete:" + target;
	DWORD rcDel = LaunchInSessionAndWait(delCmd, sessionId, 20000);
	if (rcDel == 0) LogF(L"CredDelete (in-session) OK target=%s", target.c_str());
	else LogF(L"CredDelete (in-session) failed rc=%lu", rcDel);

	LogF(L"DoConnect cleanup done");
}

// ---------------- Service bits ----------------------------------------------
static const wchar_t* kSvcName = L"QCM-CJ";
static const wchar_t* kSvcDisp = L"QCM Credential Joiner";
static const wchar_t* kRegKey = L"SOFTWARE\\QCM\\CJ";
static const wchar_t* kRegHost = L"BackendHost";
static const wchar_t* kRegPort = L"BackendPort";
static const wchar_t* kRegListen = L"ListenPort"; // default 5555

static SERVICE_STATUS_HANDLE gSsh = nullptr;
static SERVICE_STATUS gSs{};

static void SvcSetState(DWORD s, DWORD exitCode = 0) {
	gSs.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
	gSs.dwCurrentState = s;
	gSs.dwWin32ExitCode = exitCode;
	gSs.dwControlsAccepted = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_SHUTDOWN | SERVICE_ACCEPT_STOP);
	SetServiceStatus(gSsh, &gSs);
}

static void ReadConfig(std::wstring& host, INTERNET_PORT& port, USHORT& listenPort)
{
	host = L"localhost"; port = 9000; listenPort = 5555;
	HKEY h; if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, kRegKey, 0, KEY_READ, &h) == ERROR_SUCCESS) {
		wchar_t buf[256]; DWORD cb = sizeof(buf), dw = 0, type = 0;
		if (RegQueryValueExW(h, kRegHost, 0, &type, (BYTE*)buf, &cb) == ERROR_SUCCESS && type == REG_SZ) host = buf;
		cb = sizeof(dw);
		if (RegQueryValueExW(h, kRegPort, 0, &type, (BYTE*)&dw, &cb) == ERROR_SUCCESS && type == REG_DWORD) port = (INTERNET_PORT)dw;
		cb = sizeof(dw);
		if (RegQueryValueExW(h, kRegListen, 0, &type, (BYTE*)&dw, &cb) == ERROR_SUCCESS && type == REG_DWORD) listenPort = (USHORT)dw;
		RegCloseKey(h);
	}
}

static DWORD WINAPI TcpWorker(LPVOID)
{
	std::wstring host; INTERNET_PORT port; USHORT listen;
	ReadConfig(host, port, listen);
	LogF(L"Service listen 127.0.0.1:%u backend=%s:%u", (unsigned)listen, host.c_str(), (unsigned)port);

	WSADATA w; if (WSAStartup(MAKEWORD(2, 2), &w) != 0) { LogF(L"WSAStartup failed"); return 0; }
	SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	if (s == INVALID_SOCKET) { LogF(L"socket failed"); WSACleanup(); return 0; }

	sockaddr_in a{}; a.sin_family = AF_INET; a.sin_port = htons(listen);
	inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
	if (bind(s, (sockaddr*)&a, sizeof(a)) != 0 || (::listen(s, 16)) != 0) {
		LogF(L"bind/listen failed ec=%lu", WSAGetLastError()); closesocket(s); WSACleanup(); return 0;
	}

	for (;;) {
		fd_set fds; FD_ZERO(&fds); FD_SET(s, &fds);
		TIMEVAL tv{ 1,0 };
		int rv = select(0, &fds, nullptr, nullptr, &tv);
		if (gSs.dwCurrentState == SERVICE_STOP_PENDING) break;
		if (rv <= 0) continue;

		SOCKET c = accept(s, nullptr, nullptr);
		if (c == INVALID_SOCKET) continue;

		char buf[512]; int n = recv(c, buf, sizeof(buf) - 1, 0);
		if (n > 0) {
			buf[n] = 0;
			std::wstring line = ToW(std::string(buf, n));
			std::wstring uuid = ExtractUuid(line);
			LogF(L"Received UUID line: %s  -> uuid=%s", line.c_str(), uuid.c_str());
			DoConnect(uuid, host, port);
		}
		closesocket(c);
	}

	closesocket(s);
	WSACleanup();
	LogF(L"Service worker exit");
	return 0;
}

static void WINAPI SvcCtrl(DWORD ctrl) {
	if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
		LogF(L"Service stop requested");
		SvcSetState(SERVICE_STOP_PENDING);
	}
}
static void WINAPI SvcMain(DWORD, LPWSTR*) {
	gSsh = RegisterServiceCtrlHandlerW(kSvcName, SvcCtrl);
	if (!gSsh) return;
	SvcSetState(SERVICE_START_PENDING);
	HANDLE th = CreateThread(nullptr, 0, TcpWorker, nullptr, 0, nullptr);
	SvcSetState(SERVICE_RUNNING);
	WaitForSingleObject(th, INFINITE);
	CloseHandle(th);
	SvcSetState(SERVICE_STOPPED);
}

// ---------------- installer / uninstaller -----------------------------------
static void ShowEula() {
	MessageBoxW(nullptr,
		L"QCM CJ — Terms & Conditions\n\n"
		L"This software initiates remote connections on your Jump Host based on UUIDs.\n"
		L"By clicking OK you agree to proceed.",
		L"CJ Installer", MB_ICONINFORMATION | MB_OK);
}
static bool InstallSvc(const std::wstring& host, INTERNET_PORT port, USHORT listenPort)
{
	ShowEula();

	HKEY h; if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, kRegKey, 0, nullptr, 0, KEY_WRITE, nullptr, &h, nullptr) != ERROR_SUCCESS)
		return false;
	RegSetValueExW(h, kRegHost, 0, REG_SZ, (BYTE*)host.c_str(), (DWORD)((host.size() + 1) * sizeof(wchar_t)));
	DWORD dw = port;   RegSetValueExW(h, kRegPort, 0, REG_DWORD, (BYTE*)&dw, sizeof(dw));
	dw = listenPort;   RegSetValueExW(h, kRegListen, 0, REG_DWORD, (BYTE*)&dw, sizeof(dw));
	RegCloseKey(h);

	wchar_t path[MAX_PATH];
	GetModuleFileNameW(nullptr, path, MAX_PATH);

	SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CREATE_SERVICE);
	if (!scm) return false;
	SC_HANDLE svc = CreateServiceW(scm, kSvcName, kSvcDisp,
		SERVICE_ALL_ACCESS, SERVICE_WIN32_OWN_PROCESS, SERVICE_AUTO_START,
		SERVICE_ERROR_NORMAL, (std::wstring(path) + L" --service").c_str(),
		nullptr, nullptr, nullptr, nullptr, nullptr);
	if (!svc) { CloseServiceHandle(scm); return false; }

	bool ok = (StartServiceW(svc, 0, nullptr) != 0);
	CloseServiceHandle(svc);
	CloseServiceHandle(scm);
	MessageBoxW(nullptr, L"Service installed and started.", L"CJ Installer", MB_OK | MB_ICONINFORMATION);
	return ok;
}
static void UninstallSvc()
{
	SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
	if (!scm) return;
	SC_HANDLE svc = OpenServiceW(scm, kSvcName, SERVICE_ALL_ACCESS);
	if (svc) {
		SERVICE_STATUS ss{};
		ControlService(svc, SERVICE_CONTROL_STOP, &ss);
		DeleteService(svc);
		CloseServiceHandle(svc);
	}
	CloseServiceHandle(scm);
	MessageBoxW(nullptr, L"Service uninstalled.", L"CJ Installer", MB_OK | MB_ICONINFORMATION);
}

// ---------------- main ------------------------------------------------------
int wmain(int argc, wchar_t* argv[])
{
	if (argc >= 2 && lstrcmpiW(argv[1], L"--service") == 0) {
		SERVICE_TABLE_ENTRYW ste[] = { { (LPWSTR)kSvcName, SvcMain }, { nullptr, nullptr } };
		StartServiceCtrlDispatcherW(ste);
		return 0;
	}
	if (argc >= 2 && lstrcmpiW(argv[1], L"--uninstall") == 0) {
		UninstallSvc();
		return 0;
	}
	if (argc >= 4 && lstrcmpiW(argv[1], L"--install") == 0) {
		std::wstring host = argv[2];
		INTERNET_PORT port = (INTERNET_PORT)_wtoi(argv[3]);
		USHORT listen = (argc >= 5) ? (USHORT)_wtoi(argv[4]) : 5555;
		return InstallSvc(host, port, listen) ? 0 : 1;
	}

	if (argc < 4) {
		wprintf(L"Usage:\n"
			L"  CJ.exe --install <backend_host> <backend_port> [listen_port=5555]\n"
			L"  CJ.exe --uninstall\n"
			L"  (Service runs with: CJ.exe --service)\n\n"
			L"Manual test:\n"
			L"  CJ.exe <uuid> <backend_host> <backend_port>\n");
		return 1;
	}

	std::wstring uuid = ExtractUuid(argv[1]);
	std::wstring host = argv[2];
	INTERNET_PORT port = (INTERNET_PORT)_wtoi(argv[3]);
	LogF(L"Start uuid=%s backend=%s port=%u", uuid.c_str(), host.c_str(), (unsigned)port);
	DoConnect(uuid, host, port);
	return 0;
}
