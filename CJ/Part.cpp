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
    unsigned     ttl  = json_u32(body, "ttl_secs", 300);

    std::wstring proto = json_ws(body, "protocol");  // "RDP" | "SSH" | "WEB"
    std::wstring url   = json_ws(body, "url");

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

        const wchar_t*  chHost = L"localhost";   // keep localhost/127.0.0.1
        INTERNET_PORT   chPort = 10443;

        LogF(L"WEB: Forwarding to CH %s:%u url=%s", chHost, (unsigned)chPort, url.c_str());

        // ADDED: retry loop to avoid racing CH startup or brief restarts
        const int kMaxAttempts = 5;   // total ~10s
        const DWORD kDelayMs   = 2000;
        DWORD httpStatus = 0;
        bool ok = false;

        for (int i = 1; i <= kMaxAttempts; ++i) {
            ok = http_post_json(chHost, chPort, L"/", json, &httpStatus);
            if (ok) {
                LogF(L"CH accepted WEB request (status=%lu).", httpStatus);
                break;
            }
            LogF(L"CH POST attempt %d/%d failed (status=%lu or connect error). Retrying in %lu ms...",
                 i, kMaxAttempts, httpStatus, kDelayMs);
            Sleep(kDelayMs);
        }

        if (!ok) {
            LogF(L"CH POST failed after retries. Is CH listening on %u and reachable from this session?", (unsigned)chPort);
        }
        return; // web path done
    }
    // =================== end WEB path ===================================

    // ---------------- RDP path (unchanged) ----------------
    DWORD sessionId = FindActiveRdpSessionWithWait(12000 /*maxWait*/, 1000 /*poll*/);
    if (sessionId == (DWORD)-1) {
        sessionId = GetConsoleSession();
        if (sessionId == (DWORD)-1) {
            LogF(L"No interactive session available to launch mstsc");
            return;
        }
        LogF(L"Falling back to console session %u", sessionId);
    } else {
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
