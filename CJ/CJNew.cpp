// Combined QCM Services - CJ (Credential Joiner) + CH (Chrome AutoLogin)

//#ifndef _NO_INIT_ALL
//#define _NO_INIT_ALL 1
//#endif
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
#include <tlhelp32.h>
#include <string>
#include <vector>

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")
#pragma comment(lib, "Kernel32.lib")
// ---- add this near the top of the file (e.g., under the includes) ----
static INTERNET_PORT GetPortForSession(DWORD sessionId);

// ---------------- Service identities ----------------------------------------
static const wchar_t* kCjSvcName = L"QCM-CJ";
static const wchar_t* kCjSvcDisp = L"QCM Credential Joiner";
static const wchar_t* kChSvcName = L"QCMCH";
static const wchar_t* kChSvcDisp = L"QCM Chrome AutoLogin Service";

// ---------------- Registry & config -----------------------------------------
static const wchar_t* kRegKey = L"SOFTWARE\\QCM\\CJ";
static const wchar_t* kRegHost = L"BackendHost";
static const wchar_t* kRegPort = L"BackendPort";
static const wchar_t* kRegListen = L"ListenPort"; // default 5555

// ---------------- Chrome service paths --------------------------------------
static const wchar_t* kChildExe = L"C:\\PAM\\qcm_autologin_service.exe";
static const wchar_t* kChildArgsFmt = L"\"%s\" --port 10443 --log-dir C:\\PAM\\logs";

// ---------------- Global service state --------------------------------------
static SERVICE_STATUS_HANDLE gCjSsh = nullptr;
static SERVICE_STATUS_HANDLE gChSsh = nullptr;
static SERVICE_STATUS gCjSs{};
static SERVICE_STATUS gChSs{};
static HANDLE gCjStopEvt = nullptr;
static HANDLE gChStopEvt = nullptr;
// static HANDLE gChildProc = nullptr; // DEPRECATED: Now using per-session Chrome services

// ---------------- Common logging --------------------------------------------
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
		L"%04u-%02u-%02u %02u:%02u:%02u [QCM] %s\r\n",
		st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, line);

	HANDLE h = CreateFileW(L"C:\\PAM\\qcm_combined.log", FILE_APPEND_DATA, FILE_SHARE_READ,
		nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
	if (h != INVALID_HANDLE_VALUE) {
		DWORD cb = (DWORD)(lstrlenW(msg) * sizeof(wchar_t));
		WriteFile(h, msg, cb, &cb, nullptr);
		CloseHandle(h);
	}
}

// Session-specific logging for better concurrency
static void LogSessionF(DWORD sessionId, PCWSTR fmt, ...)
{
	CreateDirectoryW(L"C:\\PAM\\logs", nullptr);
	wchar_t line[2048];
	va_list ap; va_start(ap, fmt);
	StringCchVPrintfW(line, _countof(line), fmt, ap);
	va_end(ap);

	SYSTEMTIME st; GetLocalTime(&st);
	wchar_t msg[2300];
	StringCchPrintfW(msg, _countof(msg),
		L"%04u-%02u-%02u %02u:%02u:%02u [Session_%u] %s\r\n",
		st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, sessionId, line);

	// Create session-specific log file
	wchar_t logPath[MAX_PATH];
	StringCchPrintfW(logPath, _countof(logPath), L"C:\\PAM\\logs\\session_%u.log", sessionId);

	HANDLE h = CreateFileW(logPath, FILE_APPEND_DATA, FILE_SHARE_READ,
		nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
	if (h != INVALID_HANDLE_VALUE) {
		DWORD cb = (DWORD)(lstrlenW(msg) * sizeof(wchar_t));
		WriteFile(h, msg, cb, &cb, nullptr);
		CloseHandle(h);
	}

	// Also log to main log for centralized monitoring
	LogF(L"[Session_%u] %s", sessionId, line);
}

// ---------------- Common helpers --------------------------------------------
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

// ---------------- JSON helpers ----------------------------------------------
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
	HINTERNET s = WinHttpOpen(L"QCM/2.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
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

static bool http_post_json(const std::wstring& host, INTERNET_PORT port, const std::wstring& path,
	const std::string& jsonBody, DWORD* httpStatus /*opt*/)
{
	bool ok = false;
	if (httpStatus) *httpStatus = 0;

	HINTERNET hSession = WinHttpOpen(L"QCM/2.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
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

// Find RDP session for a specific username (CRITICAL FIX for 78+ concurrent users)
static DWORD FindSessionForUser(const std::wstring& targetUser, DWORD maxWaitMs = 5000)
{
	DWORD waited = 0;
	const DWORD pollMs = 500;

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

			// Get session state
			DWORD bytes = 0;
			WTS_CONNECTSTATE_CLASS* pState = nullptr;
			if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSConnectState, (LPWSTR*)&pState, &bytes) || !pState) {
				if (pState) WTSFreeMemory(pState);
				continue;
			}
			WTS_CONNECTSTATE_CLASS state = *pState;
			WTSFreeMemory(pState);

			// Get username for this session
			LPWSTR pUser = nullptr;
			std::wstring sessionUser;
			if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSUserName, (LPWSTR*)&pUser, &bytes) && pUser) {
				sessionUser = pUser;
				WTSFreeMemory(pUser);
			}

			// Get protocol type
			LPWSTR pProto = nullptr;
			int proto = 0;
			if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSClientProtocolType, (LPWSTR*)&pProto, &bytes) && pProto) {
				proto = *(USHORT*)pProto;
				WTSFreeMemory(pProto);
			}

			// Check if this is an active RDP session with matching username
			if (state == WTSActive && proto == 2 && _wcsicmp(sessionUser.c_str(), targetUser.c_str()) == 0) {
				LogF(L"Found session %u for user '%s' (Active RDP)", sid, targetUser.c_str());
				foundSid = sid;
				break;
			}
		}

		WTSFreeMemory(pSessionInfo);

		if (foundSid != (DWORD)-1) {
			return foundSid;
		}

		// If not found and we haven't exceeded max wait time, try again
		if (waited >= maxWaitMs) {
			LogF(L"Session not found for user '%s' after %ums", targetUser.c_str(), maxWaitMs);
			break;
		}

		Sleep(pollMs);
		waited += pollMs;
	}

	return (DWORD)-1;
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

// Return active *RDP* session id (proto=2, state Active). -1 if none.
static int FindActiveRdpSession()
{
	PWTS_SESSION_INFOW p = nullptr; DWORD count = 0;
	if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &p, &count))
		return -1;

	int sid = -1;
	for (DWORD i = 0; i < count; ++i) {
		DWORD bytes = 0;

		WTS_CONNECTSTATE_CLASS* pSt = nullptr;
		if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, p[i].SessionId,
			WTSConnectState, (LPWSTR*)&pSt, &bytes) || !pSt) {
			if (pSt) WTSFreeMemory(pSt);
			continue;
		}
		WTS_CONNECTSTATE_CLASS st = *pSt;
		WTSFreeMemory(pSt);

		USHORT* pProto = nullptr;
		if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, p[i].SessionId,
			WTSClientProtocolType, (LPWSTR*)&pProto, &bytes) || !pProto) {
			if (pProto) WTSFreeMemory(pProto);
			continue;
		}
		USHORT proto = *pProto; // 2 = RDP
		WTSFreeMemory(pProto);

		if (st == WTSActive && proto == 2) {
			sid = (int)p[i].SessionId;
			break;
		}
	}
	if (p) WTSFreeMemory(p);
	return sid;
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

// wait until 127.0.0.1:<port> is reachable (up to max_wait_ms)
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

// Get detailed session information for a specific session ID
static bool GetSessionInfo(DWORD sessionId, std::wstring& sessionUser, std::wstring& clientIp, std::wstring& sessionState)
{
	sessionUser.clear();
	clientIp.clear();
	sessionState = L"Unknown";

	DWORD bytes = 0;

	// Get session state
	WTS_CONNECTSTATE_CLASS* pState = nullptr;
	if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sessionId, WTSConnectState, (LPWSTR*)&pState, &bytes) && pState) {
		WTS_CONNECTSTATE_CLASS state = *pState;
		switch (state) {
		case WTSActive: sessionState = L"Active"; break;
		case WTSConnected: sessionState = L"Connected"; break;
		case WTSConnectQuery: sessionState = L"ConnectQuery"; break;
		case WTSShadow: sessionState = L"Shadow"; break;
		case WTSDisconnected: sessionState = L"Disconnected"; break;
		case WTSIdle: sessionState = L"Idle"; break;
		case WTSListen: sessionState = L"Listen"; break;
		case WTSReset: sessionState = L"Reset"; break;
		case WTSDown: sessionState = L"Down"; break;
		case WTSInit: sessionState = L"Init"; break;
		default: sessionState = L"Unknown"; break;
		}
		WTSFreeMemory(pState);
	}

	// Get username
	LPWSTR pUser = nullptr;
	if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sessionId, WTSUserName, (LPWSTR*)&pUser, &bytes) && pUser) {
		sessionUser = pUser;
		WTSFreeMemory(pUser);
	}

	// Get client IP address
	PWTS_CLIENT_ADDRESS pAddr = nullptr;
	if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sessionId, WTSClientAddress, (LPWSTR*)&pAddr, &bytes) && pAddr) {
		clientIp = ClientAddrToString(pAddr);
		WTSFreeMemory(pAddr);
	}

	LogF(L"Session %u: user='%s', ip='%s', state='%s'", sessionId, sessionUser.c_str(), clientIp.c_str(), sessionState.c_str());
	return !sessionUser.empty();
}

// wait until the shell exists in the target session.
static bool WaitForUserDesktopReady(DWORD targetSid, DWORD maxWaitMs = 15000)
{
	const DWORD step = 500;
	DWORD waited = 0;

	for (;;) {
		// Enumerate processes, look for explorer.exe that belongs to targetSid
		HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
		if (snap != INVALID_HANDLE_VALUE) {
			PROCESSENTRY32W pe; pe.dwSize = sizeof(pe);
			if (Process32FirstW(snap, &pe)) {
				do {
					if (lstrcmpiW(pe.szExeFile, L"explorer.exe") == 0) {
						DWORD psid = 0;
						if (ProcessIdToSessionId(pe.th32ProcessID, &psid) && psid == targetSid) {
							CloseHandle(snap);
							// Give the shell a short grace to finish painting the desktop.
							Sleep(1200);
							return true;
						}
					}
				} while (Process32NextW(snap, &pe));
			}
			CloseHandle(snap);
		}

		if (waited >= maxWaitMs) return false;
		Sleep(step);
		waited += step;
	}
}

// ---------------- Core connection logic -------------------------------------
static void DoConnect(const std::wstring& uuid, const std::wstring& backendHost, INTERNET_PORT backendPort)
{
	LogF(L"Handle UUID=%s backend=%s:%u", uuid.c_str(), backendHost.c_str(), (unsigned)backendPort);

	// Get current session for logging context
	DWORD currentSessionId = FindActiveRdpSessionWithWait(1000, 500);
	if (currentSessionId == (DWORD)-1) {
		currentSessionId = GetConsoleSession();
	}

	// Use session-specific logging if we have a valid session
	auto SessionLog = [currentSessionId](PCWSTR fmt, ...) {
		wchar_t line[2048];
		va_list ap; va_start(ap, fmt);
		StringCchVPrintfW(line, _countof(line), fmt, ap);
		va_end(ap);

		if (currentSessionId != (DWORD)-1) {
			LogSessionF(currentSessionId, L"%s", line);
		}
		else {
			LogF(L"%s", line);
		}
	};

	// Resolve UUID at backend
	std::wstring path = L"/cj/resolve/" + uuid;
	std::string body;
	if (!http_get(backendHost, backendPort, path, body)) {
		SessionLog(L"HTTP request failed for UUID=%s", uuid.c_str());
		return;
	}
	SessionLog(L"RAW JSON: %s", ToW(body).c_str());

	std::wstring status = json_ws(body, "status");
	std::wstring ip = json_ws(body, "target_ip");
	unsigned     port = json_u32(body, "target_port", 3389);
	std::wstring user = json_ws(body, "username");
	std::wstring pass = json_ws(body, "password");
	unsigned     ttl = json_u32(body, "ttl_secs", 300);

	std::wstring proto = json_ws(body, "protocol");  // "RDP" | "SSH" | "WEB"
	std::wstring url = json_ws(body, "url");

	if (status != L"ok" || user.empty() || pass.empty()) {
		SessionLog(L"Missing fields from backend for UUID=%s", uuid.c_str());
		return;
	}
	SessionLog(L"Parsed proto=%s ip=%s port=%u user=%s ttl=%u", proto.c_str(), ip.c_str(), port, user.c_str(), ttl);

	// ===================== WEB path → forward to CH ======================
	if (_wcsicmp(proto.c_str(), L"WEB") == 0) {
		if (url.empty()) {
			SessionLog(L"WEB flow requires 'url' in resolve JSON; aborting UUID=%s", uuid.c_str());
			return;
		}

		// CRITICAL FIX: Find the session for the specific user instead of first active session
		DWORD targetSessionId = FindSessionForUser(user, 5000); // Wait up to 5 seconds for user session
		std::wstring sessionUser, clientIp, sessionState;
		bool hasSessionInfo = false;

		if (targetSessionId != (DWORD)-1) {
			hasSessionInfo = GetSessionInfo(targetSessionId, sessionUser, clientIp, sessionState);
			SessionLog(L"Found RDP session %u for user '%s' - Chrome will launch in correct session",
				targetSessionId, user.c_str());
		}
		else {
			// Fallback: try to find any active RDP session (original behavior)
			SessionLog(L"No session found for user '%s', falling back to first active session", user.c_str());
			targetSessionId = FindActiveRdpSessionWithWait(2000, 500);

			if (targetSessionId != (DWORD)-1) {
				hasSessionInfo = GetSessionInfo(targetSessionId, sessionUser, clientIp, sessionState);
				SessionLog(L"Using fallback session %u for Chrome automation", targetSessionId);
			}
			else {
				SessionLog(L"No active RDP session found, checking console session");
				targetSessionId = GetConsoleSession();
				if (targetSessionId != (DWORD)-1) {
					hasSessionInfo = GetSessionInfo(targetSessionId, sessionUser, clientIp, sessionState);
					SessionLog(L"Using console session %u for Chrome automation", targetSessionId);
				}
			}
		}

		// Build enhanced JSON body for CH with session information
		std::string json = std::string("{\"type\":\"web\",\"uuid\":\"") + ToA(uuid)
			+ "\",\"url\":\"" + ToA(url)
			+ "\",\"username\":\"" + ToA(user)
			+ "\",\"password\":\"" + ToA(pass) + "\"";

		// Add session information if available
		if (hasSessionInfo && targetSessionId != (DWORD)-1) {
			json += ",\"session_id\":" + std::to_string(targetSessionId);
			json += ",\"session_user\":\"" + ToA(sessionUser) + "\"";
			json += ",\"client_ip\":\"" + ToA(clientIp) + "\"";
			json += ",\"session_state\":\"" + ToA(sessionState) + "\"";
		}

		json += "}";

		SessionLog(L"Sending session-targeted request to Chrome service: %s", ToW(json).c_str());

		const wchar_t*  chHost = L"localhost";
		INTERNET_PORT   chPort = GetPortForSession(targetSessionId); // Use session-specific port

		// Wait up to 90 seconds for CH to be listening on the session-specific port
		SessionLog(L"Waiting for session-%u Chrome service on %s:%u (max 90s)...",
			targetSessionId, chHost, (unsigned)chPort);
		if (!WaitForLocalPort((int)chPort, 90 * 1000)) {
			SessionLog(L"CH port %u not reachable after 90s; giving up UUID=%s", (unsigned)chPort, uuid.c_str());
			return;
		}

		// Try POST (5 quick retries once CH is alive)
		DWORD httpStatus = 0;
		bool ok = false;
		for (int i = 1; i <= 5 && !ok; ++i) {
			ok = http_post_json(chHost, chPort, L"/", json, &httpStatus);
			if (ok) {
				SessionLog(L"CH accepted WEB request (status=%lu) for UUID=%s", httpStatus, uuid.c_str());
				break;
			}
			SessionLog(L"CH POST attempt %d/5 failed (status=%lu or connect error) for UUID=%s. Retrying in 2000 ms...",
				i, httpStatus, uuid.c_str());
			Sleep(2000);
		}

		if (!ok) {
			SessionLog(L"CH POST failed after retries for UUID=%s. Is CH listening on %u and reachable?", uuid.c_str(), (unsigned)chPort);
		}
		return; // web path done
	}

	// =================== end WEB path ===================================

	// ---------------- RDP path ----------------
	DWORD sessionId = FindActiveRdpSessionWithWait(12000 /*maxWait*/, 1000 /*poll*/);
	if (sessionId == (DWORD)-1) {
		sessionId = GetConsoleSession();
		if (sessionId == (DWORD)-1) {
			SessionLog(L"No interactive session available to launch mstsc for UUID=%s", uuid.c_str());
			return;
		}
		SessionLog(L"Falling back to console session %u for UUID=%s", sessionId, uuid.c_str());
	}
	else {
		SessionLog(L"Selected ACTIVE RDP session %u for UUID=%s", sessionId, uuid.c_str());
	}

	wchar_t sysdir[MAX_PATH] = { 0 };
	GetSystemDirectoryW(sysdir, MAX_PATH);
	std::wstring cmdkeyExe = std::wstring(sysdir) + L"\\cmdkey.exe";
	std::wstring target = L"TERMSRV/" + ip;

	std::wstring addCmd = cmdkeyExe + L" /generic:" + target + L" /user:\"" + user + L"\" /pass:\"" + pass + L"\"";
	DWORD rcAdd = LaunchInSessionAndWait(addCmd, sessionId, 20000);
	Sleep(1000);
	if (rcAdd == 0) SessionLog(L"CredWrite (in-session) OK target=%s user=%s UUID=%s", target.c_str(), user.c_str(), uuid.c_str());
	else SessionLog(L"CredWrite (in-session) failed rc=%lu UUID=%s", rcAdd, uuid.c_str());

	wchar_t args[256];
	StringCchPrintfW(args, _countof(args), L"/v:%s:%u /f", ip.c_str(), port ? port : 3389);
	std::wstring mstscCmd = L"mstsc.exe "; mstscCmd += args;
	SessionLog(L"Launching mstsc in session %u: %s UUID=%s", sessionId, args, uuid.c_str());
	DWORD rcMst = LaunchInSessionAndWait(mstscCmd, sessionId, 10000);
	if (rcMst != 0) {
		SessionLog(L"mstsc launch returned rc=%lu (this may be non-fatal) UUID=%s", rcMst, uuid.c_str());
	}

	Sleep(25000);

	std::wstring delCmd = cmdkeyExe + L" /delete:" + target;
	DWORD rcDel = LaunchInSessionAndWait(delCmd, sessionId, 20000);
	if (rcDel == 0) SessionLog(L"CredDelete (in-session) OK target=%s UUID=%s", target.c_str(), uuid.c_str());
	else SessionLog(L"CredDelete (in-session) failed rc=%lu UUID=%s", rcDel, uuid.c_str());

	SessionLog(L"DoConnect cleanup done for UUID=%s", uuid.c_str());
}

// ---------------- Service state helpers -------------------------------------
static void SetCjState(DWORD s, DWORD exitCode = 0) {
	gCjSs.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
	gCjSs.dwCurrentState = s;
	gCjSs.dwWin32ExitCode = exitCode;
	gCjSs.dwControlsAccepted = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_SHUTDOWN | SERVICE_ACCEPT_STOP);
	SetServiceStatus(gCjSsh, &gCjSs);
}

static void SetChState(DWORD s, DWORD ec = NO_ERROR, DWORD waitMs = 0)
{
	gChSs.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
	gChSs.dwCurrentState = s;
	gChSs.dwWin32ExitCode = ec;
	gChSs.dwControlsAccepted = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
	gChSs.dwWaitHint = waitMs;
	SetServiceStatus(gChSsh, &gChSs);
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

// DEPRECATED: KillChild function - now using per-session Chrome service management
/*
static void KillChild()
{
	if (!gChildProc) return;
	LogF(L"Stopping child...");
	TerminateProcess(gChildProc, 0);
	WaitForSingleObject(gChildProc, 4000);
	CloseHandle(gChildProc);
	gChildProc = nullptr;
}
*/

// ---------------- Chrome Service helpers ------------------------------------
static HANDLE LaunchInSession(DWORD sid)
{
	// Acquire a primary token for the interactive user in that session
	HANDLE userTok = nullptr;
	if (!WTSQueryUserToken((ULONG)sid, &userTok)) {
		LogF(L"WTSQueryUserToken failed ec=%lu sid=%u", GetLastError(), sid);
		return nullptr;
	}

	SECURITY_ATTRIBUTES sa{ sizeof(sa) };
	HANDLE primaryTok = nullptr;
	if (!DuplicateTokenEx(userTok, TOKEN_ALL_ACCESS, &sa, SecurityIdentification, TokenPrimary, &primaryTok)) {
		LogF(L"DuplicateTokenEx failed ec=%lu", GetLastError());
		CloseHandle(userTok);
		return nullptr;
	}
	CloseHandle(userTok);

	// Load user profile (best effort)
	PROFILEINFOW pi{}; pi.dwSize = sizeof(pi);
	if (!LoadUserProfileW(primaryTok, &pi)) {
		LogF(L"LoadUserProfileW failed ec=%lu (continuing)", GetLastError());
	}

	// Build environment block (best effort)
	LPVOID env = nullptr;
	if (!CreateEnvironmentBlock(&env, primaryTok, FALSE)) {
		LogF(L"CreateEnvironmentBlock failed ec=%lu (continuing)", GetLastError());
		env = nullptr;
	}

	// wait for real desktop before launch
	if (!WaitForUserDesktopReady(sid, 15000)) {
		LogF(L"Desktop not ready in sid=%u, skipping launch", sid);
		if (env) DestroyEnvironmentBlock(env);
		if (pi.hProfile) UnloadUserProfile(primaryTok, pi.hProfile);
		CloseHandle(primaryTok);
		return nullptr;
	}

	// Compose command line
	wchar_t cmd[1024];
	StringCchPrintfW(cmd, 1024, kChildArgsFmt, kChildExe);

	STARTUPINFOW si{}; si.cb = sizeof(si);
	si.lpDesktop = (LPWSTR)L"winsta0\\default"; // visible on the user desktop

	PROCESS_INFORMATION piProc{};
	BOOL ok = CreateProcessAsUserW(
		primaryTok,
		kChildExe,               // lpApplicationName
		cmd,                     // lpCommandLine
		nullptr, nullptr, FALSE,
		// no console popup from Rust child:
		CREATE_UNICODE_ENVIRONMENT | DETACHED_PROCESS | CREATE_NO_WINDOW,
		env,                     // environment
		L"C:\\PAM",              // working directory
		&si, &piProc);

	if (!ok) {
		LogF(L"CreateProcessAsUserW failed ec=%lu sid=%u", GetLastError(), sid);
		if (env) DestroyEnvironmentBlock(env);
		if (pi.hProfile) UnloadUserProfile(primaryTok, pi.hProfile);
		CloseHandle(primaryTok);
		return nullptr;
	}

	if (env) DestroyEnvironmentBlock(env);
	if (pi.hProfile) UnloadUserProfile(primaryTok, pi.hProfile);
	CloseHandle(primaryTok);

	CloseHandle(piProc.hThread);
	LogF(L"Launched Rust CH in session %u, pid %lu", sid, piProc.dwProcessId);
	return piProc.hProcess;
}

// ---------------- CJ TCP Worker ---------------------------------------------
static DWORD WINAPI CjTcpWorker(LPVOID)
{
	std::wstring host; INTERNET_PORT port; USHORT listen;
	ReadConfig(host, port, listen);
	LogF(L"CJ Service listen 127.0.0.1:%u backend=%s:%u (max 1024 concurrent connections)", (unsigned)listen, host.c_str(), (unsigned)port);

	WSADATA w; if (WSAStartup(MAKEWORD(2, 2), &w) != 0) { LogF(L"WSAStartup failed"); return 0; }
	SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	if (s == INVALID_SOCKET) { LogF(L"socket failed"); WSACleanup(); return 0; }

	// Set socket to reuse address to avoid "Address already in use" errors
	BOOL optval = TRUE;
	setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (char*)&optval, sizeof(optval));

	sockaddr_in a{}; a.sin_family = AF_INET; a.sin_port = htons(listen);
	inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
	if (bind(s, (sockaddr*)&a, sizeof(a)) != 0 || (::listen(s, 1024)) != 0) {
		LogF(L"bind/listen failed ec=%lu", WSAGetLastError()); closesocket(s); WSACleanup(); return 0;
	}

	// Use a more efficient event-driven approach for handling multiple connections
	std::vector<HANDLE> workerThreads;
	const int MAX_WORKER_THREADS = 50; // Limit worker threads to prevent resource exhaustion

	for (;;) {
		fd_set fds; FD_ZERO(&fds); FD_SET(s, &fds);
		TIMEVAL tv{ 1,0 };
		int rv = select(0, &fds, nullptr, nullptr, &tv);
		if (gCjSs.dwCurrentState == SERVICE_STOP_PENDING) break;
		if (rv <= 0) continue;

		SOCKET c = accept(s, nullptr, nullptr);
		if (c == INVALID_SOCKET) continue;

		// Cleanup finished worker threads
		for (auto it = workerThreads.begin(); it != workerThreads.end();) {
			if (WaitForSingleObject(*it, 0) == WAIT_OBJECT_0) {
				CloseHandle(*it);
				it = workerThreads.erase(it);
			}
			else {
				++it;
			}
		}

		// If we have too many worker threads, reject the connection
		if (workerThreads.size() >= MAX_WORKER_THREADS) {
			LogF(L"Too many active connections (%d), rejecting new connection", (int)workerThreads.size());
			closesocket(c);
			continue;
		}

		// Create a worker thread to handle this connection
		struct ConnectionData {
			SOCKET socket;
			std::wstring backendHost;
			INTERNET_PORT backendPort;
		};

		ConnectionData* connData = new ConnectionData{ c, host, port };
		HANDLE hThread = CreateThread(nullptr, 0, [](LPVOID param) -> DWORD {
			ConnectionData* data = static_cast<ConnectionData*>(param);
			SOCKET clientSocket = data->socket;
			std::wstring backendHost = data->backendHost;
			INTERNET_PORT backendPort = data->backendPort;
			delete data;

			char buf[512];
			int n = recv(clientSocket, buf, sizeof(buf) - 1, 0);
			if (n > 0) {
				buf[n] = 0;
				std::wstring line = ToW(std::string(buf, n));
				std::wstring uuid = ExtractUuid(line);
				LogF(L"Worker thread processing UUID: %s", uuid.c_str());
				DoConnect(uuid, backendHost, backendPort);
			}
			closesocket(clientSocket);
			return 0;
		}, connData, 0, nullptr);

		if (hThread) {
			workerThreads.push_back(hThread);
		}
		else {
			LogF(L"Failed to create worker thread, handling connection synchronously");
			delete connData;
			// Handle synchronously as fallback
			char buf[512]; int n = recv(c, buf, sizeof(buf) - 1, 0);
			if (n > 0) {
				buf[n] = 0;
				std::wstring line = ToW(std::string(buf, n));
				std::wstring uuid = ExtractUuid(line);
				LogF(L"Fallback processing UUID: %s", uuid.c_str());
				DoConnect(uuid, host, port);
			}
			closesocket(c);
		}
	}

	// Cleanup all worker threads
	for (HANDLE hThread : workerThreads) {
		WaitForSingleObject(hThread, 5000); // Wait up to 5 seconds for each thread
		CloseHandle(hThread);
	}

	closesocket(s);
	WSACleanup();
	LogF(L"CJ Service worker exit");
	return 0;
}

// ---------------- Chrome Service Instance Management ------------------------
struct ChromeServiceInstance {
	DWORD sessionId;
	HANDLE processHandle;
	INTERNET_PORT port;
	std::wstring sessionUser;
	DWORD lastActivity;
};

static std::vector<ChromeServiceInstance> gChromeServices;
static CRITICAL_SECTION gChromeServicesLock;

static void InitChromeServiceManager() {
	InitializeCriticalSection(&gChromeServicesLock);
}

static void CleanupChromeServiceManager() {
	EnterCriticalSection(&gChromeServicesLock);
	for (auto& service : gChromeServices) {
		if (service.processHandle) {
			LogF(L"Terminating Chrome service for session %u (port %u)", service.sessionId, service.port);
			TerminateProcess(service.processHandle, 0);
			WaitForSingleObject(service.processHandle, 3000);
			CloseHandle(service.processHandle);
		}
	}
	gChromeServices.clear();
	LeaveCriticalSection(&gChromeServicesLock);
	DeleteCriticalSection(&gChromeServicesLock);
}

static INTERNET_PORT GetPortForSession(DWORD /*sessionId*/) {
	// Assign ports starting from 10443 based on session ID
	return 10443;
}

static ChromeServiceInstance* FindChromeServiceForSession(DWORD sessionId) {
	EnterCriticalSection(&gChromeServicesLock);
	for (auto& service : gChromeServices) {
		if (service.sessionId == sessionId) {
			LeaveCriticalSection(&gChromeServicesLock);
			return &service;
		}
	}
	LeaveCriticalSection(&gChromeServicesLock);
	return nullptr;
}

static HANDLE LaunchChromeServiceInSession(DWORD sessionId, INTERNET_PORT port) {
	// Same logic as LaunchInSession but with custom port parameter
	HANDLE userTok = nullptr;
	if (!WTSQueryUserToken((ULONG)sessionId, &userTok)) {
		LogF(L"WTSQueryUserToken failed ec=%lu sid=%u", GetLastError(), sessionId);
		return nullptr;
	}

	SECURITY_ATTRIBUTES sa{ sizeof(sa) };
	HANDLE primaryTok = nullptr;
	if (!DuplicateTokenEx(userTok, TOKEN_ALL_ACCESS, &sa, SecurityIdentification, TokenPrimary, &primaryTok)) {
		LogF(L"DuplicateTokenEx failed ec=%lu", GetLastError());
		CloseHandle(userTok);
		return nullptr;
	}
	CloseHandle(userTok);

	PROFILEINFOW pi{}; pi.dwSize = sizeof(pi);
	if (!LoadUserProfileW(primaryTok, &pi)) {
		LogF(L"LoadUserProfileW failed ec=%lu (continuing)", GetLastError());
	}

	LPVOID env = nullptr;
	if (!CreateEnvironmentBlock(&env, primaryTok, FALSE)) {
		LogF(L"CreateEnvironmentBlock failed ec=%lu (continuing)", GetLastError());
		env = nullptr;
	}

	if (!WaitForUserDesktopReady(sessionId, 15000)) {
		LogF(L"Desktop not ready in sid=%u, skipping Chrome service launch", sessionId);
		if (env) DestroyEnvironmentBlock(env);
		if (pi.hProfile) UnloadUserProfile(primaryTok, pi.hProfile);
		CloseHandle(primaryTok);
		return nullptr;
	}

	// Compose command line with custom port
	wchar_t cmd[1024];
	StringCchPrintfW(cmd, 1024, L"\"%s\" --port %u --session-id %u", kChildExe, port, sessionId);

	STARTUPINFOW si{}; si.cb = sizeof(si);
	si.lpDesktop = (LPWSTR)L"winsta0\\default";

	PROCESS_INFORMATION piProc{};
	BOOL ok = CreateProcessAsUserW(
		primaryTok,
		kChildExe,
		cmd,
		nullptr, nullptr, FALSE,
		CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_CONSOLE,
		env,
		L"C:\\PAM",
		&si,
		&piProc
	);

	if (env) DestroyEnvironmentBlock(env);
	if (pi.hProfile) UnloadUserProfile(primaryTok, pi.hProfile);
	CloseHandle(primaryTok);

	if (!ok) {
		LogF(L"CreateProcessAsUserW failed ec=%lu for session %u port %u", GetLastError(), sessionId, port);
		return nullptr;
	}

	CloseHandle(piProc.hThread);
	LogF(L"Chrome service launched in session %u on port %u (PID=%lu)", sessionId, port, piProc.dwProcessId);
	return piProc.hProcess;
}

static void EnsureChromeServiceForSession(DWORD sessionId, const std::wstring& sessionUser) {
	EnterCriticalSection(&gChromeServicesLock);

	// Check if service already exists for this session
	ChromeServiceInstance* existing = nullptr;
	for (auto& service : gChromeServices) {
		if (service.sessionId == sessionId) {
			existing = &service;
			break;
		}
	}

	if (existing) {
		// Check if process is still alive
		if (existing->processHandle && WaitForSingleObject(existing->processHandle, 0) == WAIT_OBJECT_0) {
			LogF(L"Chrome service for session %u died, restarting", sessionId);
			CloseHandle(existing->processHandle);
			existing->processHandle = nullptr;
		}

		if (!existing->processHandle) {
			// Restart the service
			existing->processHandle = LaunchChromeServiceInSession(sessionId, existing->port);
		}

		existing->lastActivity = GetTickCount();
		LeaveCriticalSection(&gChromeServicesLock);
		return;
	}

	// Create new service instance
	ChromeServiceInstance newService;
	newService.sessionId = sessionId;
	newService.port = GetPortForSession(sessionId);
	newService.sessionUser = sessionUser;
	newService.lastActivity = GetTickCount();
	newService.processHandle = LaunchChromeServiceInSession(sessionId, newService.port);

	if (newService.processHandle) {
		gChromeServices.push_back(newService);
		LogF(L"Created Chrome service for session %u user '%s' on port %u",
			sessionId, sessionUser.c_str(), newService.port);
	}

	LeaveCriticalSection(&gChromeServicesLock);
}

// ---------------- CH Worker --------------------------------------------------
static DWORD WINAPI ChWorker(LPVOID)
{
	LogF(L"CH Service worker start - Multi-session mode");
	CreateDirectoryW(L"C:\\PAM\\logs", nullptr);
	InitChromeServiceManager();

	for (;;) {
		if (WaitForSingleObject(gChStopEvt, 0) == WAIT_OBJECT_0) break;

		// Enumerate all active RDP sessions and ensure Chrome services are running
		PWTS_SESSION_INFO pSessionInfo = nullptr;
		DWORD count = 0;
		if (WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &pSessionInfo, &count)) {

			for (DWORD i = 0; i < count; ++i) {
				DWORD sessionId = pSessionInfo[i].SessionId;

				// Get session state
				DWORD bytes = 0;
				WTS_CONNECTSTATE_CLASS* pState = nullptr;
				if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sessionId, WTSConnectState, (LPWSTR*)&pState, &bytes) || !pState) {
					if (pState) WTSFreeMemory(pState);
					continue;
				}
				WTS_CONNECTSTATE_CLASS state = *pState;
				WTSFreeMemory(pState);

				// Get protocol type
				LPWSTR pProto = nullptr;
				int proto = 0;
				if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sessionId, WTSClientProtocolType, (LPWSTR*)&pProto, &bytes) && pProto) {
					proto = *(USHORT*)pProto;
					WTSFreeMemory(pProto);
				}

				// Get username
				LPWSTR pUser = nullptr;
				std::wstring sessionUser;
				if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sessionId, WTSUserName, (LPWSTR*)&pUser, &bytes) && pUser) {
					sessionUser = pUser;
					WTSFreeMemory(pUser);
				}

				// If this is an active RDP session, ensure Chrome service is running
				if (state == WTSActive && proto == 2 && !sessionUser.empty()) {
					LogSessionF(sessionId, L"Managing Chrome service for active RDP session %u user '%s'",
						sessionId, sessionUser.c_str());
					EnsureChromeServiceForSession(sessionId, sessionUser);
				}
			}

			WTSFreeMemory(pSessionInfo);
		}

		// Clean up services for sessions that no longer exist
		EnterCriticalSection(&gChromeServicesLock);
		auto it = gChromeServices.begin();
		while (it != gChromeServices.end()) {
			bool sessionExists = false;

			// Check if session still exists and is active
			WTS_CONNECTSTATE_CLASS* pState = nullptr;
			DWORD bytes = 0;
			if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, it->sessionId, WTSConnectState, (LPWSTR*)&pState, &bytes) && pState) {
				sessionExists = (*pState == WTSActive);
				WTSFreeMemory(pState);
			}

			if (!sessionExists || (it->processHandle && WaitForSingleObject(it->processHandle, 0) == WAIT_OBJECT_0)) {
				LogF(L"Cleaning up Chrome service for session %u (exists=%d)", it->sessionId, sessionExists);
				if (it->processHandle) {
					TerminateProcess(it->processHandle, 0);
					CloseHandle(it->processHandle);
				}
				it = gChromeServices.erase(it);
			}
			else {
				++it;
			}
		}
		LeaveCriticalSection(&gChromeServicesLock);

		if (WaitForSingleObject(gChStopEvt, 2000) == WAIT_OBJECT_0) break;
	}

	CleanupChromeServiceManager();
	LogF(L"CH Worker exit - Multi-session mode");
	return 0;
}

// ---------------- Service control handlers ----------------------------------
static void WINAPI CjSvcCtrl(DWORD ctrl) {
	if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
		LogF(L"CJ Service stop requested");
		SetCjState(SERVICE_STOP_PENDING);
	}
}

static void WINAPI ChCtrlHandler(DWORD code)
{
	if (code == SERVICE_CONTROL_STOP || code == SERVICE_CONTROL_SHUTDOWN) {
		SetChState(SERVICE_STOP_PENDING, NO_ERROR, 3000);
		SetEvent(gChStopEvt);
	}
}

// ---------------- Service main functions ------------------------------------
static void WINAPI CjSvcMain(DWORD, LPWSTR*) {
	gCjSsh = RegisterServiceCtrlHandlerW(kCjSvcName, CjSvcCtrl);
	if (!gCjSsh) return;
	SetCjState(SERVICE_START_PENDING);
	HANDLE th = CreateThread(nullptr, 0, CjTcpWorker, nullptr, 0, nullptr);
	SetCjState(SERVICE_RUNNING);
	WaitForSingleObject(th, INFINITE);
	CloseHandle(th);
	SetCjState(SERVICE_STOPPED);
}

static void WINAPI ChSvcMain(DWORD, LPWSTR*)
{
	gChSsh = RegisterServiceCtrlHandlerW(kChSvcName, ChCtrlHandler);
	if (!gChSsh) return;

	SetChState(SERVICE_START_PENDING, NO_ERROR, 3000);
	gChStopEvt = CreateEventW(nullptr, TRUE, FALSE, nullptr);

	HANDLE th = CreateThread(nullptr, 0, ChWorker, nullptr, 0, nullptr);
	SetChState(SERVICE_RUNNING);

	WaitForSingleObject(th, INFINITE);
	CloseHandle(th);
	CloseHandle(gChStopEvt); gChStopEvt = nullptr;

	SetChState(SERVICE_STOPPED);
}

// ---------------- installer / uninstaller -----------------------------------
static void ShowEula() {
	MessageBoxW(nullptr,
		L"QCM Combined Services — Terms & Conditions\n\n"
		L"This software initiates remote connections on your Jump Host based on UUIDs.\n"
		L"By clicking OK you agree to proceed.",
		L"QCM Installer", MB_ICONINFORMATION | MB_OK);
}

static bool InstallCjSvc(const std::wstring& host, INTERNET_PORT port, USHORT listenPort)
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
	SC_HANDLE svc = CreateServiceW(scm, kCjSvcName, kCjSvcDisp,
		SERVICE_ALL_ACCESS, SERVICE_WIN32_OWN_PROCESS, SERVICE_AUTO_START,
		SERVICE_ERROR_NORMAL, (std::wstring(path) + L" --cj-service").c_str(),
		nullptr, nullptr, nullptr, nullptr, nullptr);
	if (!svc) { CloseServiceHandle(scm); return false; }

	bool ok = (StartServiceW(svc, 0, nullptr) != 0);
	CloseServiceHandle(svc);
	CloseServiceHandle(scm);
	MessageBoxW(nullptr, L"CJ Service installed and started.", L"QCM Installer", MB_OK | MB_ICONINFORMATION);
	return ok;
}

static bool InstallChSvc()
{
	wchar_t path[MAX_PATH];
	GetModuleFileNameW(nullptr, path, MAX_PATH);

	SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CREATE_SERVICE);
	if (!scm) return false;
	SC_HANDLE svc = CreateServiceW(scm, kChSvcName, kChSvcDisp,
		SERVICE_ALL_ACCESS, SERVICE_WIN32_OWN_PROCESS, SERVICE_AUTO_START,
		SERVICE_ERROR_NORMAL, (std::wstring(path) + L" --ch-service").c_str(),
		nullptr, nullptr, nullptr, nullptr, nullptr);
	if (!svc) { CloseServiceHandle(scm); return false; }

	bool ok = (StartServiceW(svc, 0, nullptr) != 0);
	CloseServiceHandle(svc);
	CloseServiceHandle(scm);
	MessageBoxW(nullptr, L"CH Service installed and started.", L"QCM Installer", MB_OK | MB_ICONINFORMATION);
	return ok;
}

static void UninstallCjSvc()
{
	SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
	if (!scm) return;
	SC_HANDLE svc = OpenServiceW(scm, kCjSvcName, SERVICE_ALL_ACCESS);
	if (svc) {
		SERVICE_STATUS ss{};
		ControlService(svc, SERVICE_CONTROL_STOP, &ss);
		DeleteService(svc);
		CloseServiceHandle(svc);
	}
	CloseServiceHandle(scm);
	MessageBoxW(nullptr, L"CJ Service uninstalled.", L"QCM Installer", MB_OK | MB_ICONINFORMATION);
}

static void UninstallChSvc()
{
	SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
	if (!scm) return;
	SC_HANDLE svc = OpenServiceW(scm, kChSvcName, SERVICE_ALL_ACCESS);
	if (svc) {
		SERVICE_STATUS ss{};
		ControlService(svc, SERVICE_CONTROL_STOP, &ss);
		DeleteService(svc);
		CloseServiceHandle(svc);
	}
	CloseServiceHandle(scm);
	MessageBoxW(nullptr, L"CH Service uninstalled.", L"QCM Installer", MB_OK | MB_ICONINFORMATION);
}

// ---------------- Unified Main Entry Point ---------------------------------
int wmain(int argc, wchar_t* argv[])
{
	// CJ Service mode
	if (argc >= 2 && lstrcmpiW(argv[1], L"--cj-service") == 0) {
		SERVICE_TABLE_ENTRYW ste[] = { { (LPWSTR)kCjSvcName, CjSvcMain }, { nullptr, nullptr } };
		StartServiceCtrlDispatcherW(ste);
		return 0;
	}

	// CH Service mode  
	if (argc >= 2 && lstrcmpiW(argv[1], L"--ch-service") == 0) {
		SERVICE_TABLE_ENTRYW ste[] = { { (LPWSTR)kChSvcName, ChSvcMain }, { nullptr, nullptr } };
		StartServiceCtrlDispatcherW(ste);
		return 0;
	}

	// Legacy service mode (CJ)
	if (argc >= 2 && lstrcmpiW(argv[1], L"--service") == 0) {
		SERVICE_TABLE_ENTRYW ste[] = { { (LPWSTR)kCjSvcName, CjSvcMain }, { nullptr, nullptr } };
		StartServiceCtrlDispatcherW(ste);
		return 0;
	}

	// Install CJ service
	if (argc >= 4 && lstrcmpiW(argv[1], L"--install-cj") == 0) {
		std::wstring host = argv[2];
		INTERNET_PORT port = (INTERNET_PORT)_wtoi(argv[3]);
		USHORT listen = (argc >= 5) ? (USHORT)_wtoi(argv[4]) : 5555;
		return InstallCjSvc(host, port, listen) ? 0 : 1;
	}

	// Install CH service
	if (argc >= 2 && lstrcmpiW(argv[1], L"--install-ch") == 0) {
		return InstallChSvc() ? 0 : 1;
	}

	// Install both services
	if (argc >= 4 && lstrcmpiW(argv[1], L"--install-both") == 0) {
		std::wstring host = argv[2];
		INTERNET_PORT port = (INTERNET_PORT)_wtoi(argv[3]);
		USHORT listen = (argc >= 5) ? (USHORT)_wtoi(argv[4]) : 5555;
		bool cjOk = InstallCjSvc(host, port, listen);
		bool chOk = InstallChSvc();
		return (cjOk && chOk) ? 0 : 1;
	}

	// Legacy install (CJ only)
	if (argc >= 4 && lstrcmpiW(argv[1], L"--install") == 0) {
		std::wstring host = argv[2];
		INTERNET_PORT port = (INTERNET_PORT)_wtoi(argv[3]);
		USHORT listen = (argc >= 5) ? (USHORT)_wtoi(argv[4]) : 5555;
		return InstallCjSvc(host, port, listen) ? 0 : 1;
	}

	// Uninstall CJ service
	if (argc >= 2 && lstrcmpiW(argv[1], L"--uninstall-cj") == 0) {
		UninstallCjSvc();
		return 0;
	}

	// Uninstall CH service
	if (argc >= 2 && lstrcmpiW(argv[1], L"--uninstall-ch") == 0) {
		UninstallChSvc();
		return 0;
	}

	// Uninstall both services
	if (argc >= 2 && lstrcmpiW(argv[1], L"--uninstall-both") == 0) {
		UninstallCjSvc();
		UninstallChSvc();
		return 0;
	}

	// Legacy uninstall (CJ only)
	if (argc >= 2 && lstrcmpiW(argv[1], L"--uninstall") == 0) {
		UninstallCjSvc();
		return 0;
	}

	// Manual test mode (CJ functionality)
	if (argc >= 4) {
		std::wstring uuid = ExtractUuid(argv[1]);
		std::wstring host = argv[2];
		INTERNET_PORT port = (INTERNET_PORT)_wtoi(argv[3]);
		LogF(L"Manual test: uuid=%s backend=%s port=%u", uuid.c_str(), host.c_str(), (unsigned)port);
		DoConnect(uuid, host, port);
		return 0;
	}

	// Show usage
	wprintf(L"QCM Combined Services (CJ + CH)\n\n"
		L"Service management:\n"
		L"  --install-cj <backend_host> <backend_port> [listen_port=5555]  Install CJ service only\n"
		L"  --install-ch                                                   Install CH service only\n"
		L"  --install-both <backend_host> <backend_port> [listen_port]     Install both services\n"
		L"  --uninstall-cj                                                 Uninstall CJ service\n"
		L"  --uninstall-ch                                                 Uninstall CH service\n"
		L"  --uninstall-both                                               Uninstall both services\n\n"
		L"Legacy compatibility:\n"
		L"  --install <backend_host> <backend_port> [listen_port=5555]     Install CJ service (legacy)\n"
		L"  --uninstall                                                    Uninstall CJ service (legacy)\n"
		L"  --service                                                      Run CJ service (legacy)\n\n"
		L"Manual test:\n"
		L"  <uuid> <backend_host> <backend_port>                          Test CJ connection manually\n\n"
		L"Service entry points (used by SCM):\n"
		L"  --cj-service                                                   CJ service entry point\n"
		L"  --ch-service                                                   CH service entry point\n");
	return 1;
}
