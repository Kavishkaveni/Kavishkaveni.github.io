// qcm_ch.cpp — QCM Chrome AutoLogin Windows Service Wrapper (Jump Host)
// Build: VS2017+, x64, Unicode. Link: Advapi32.lib; Wtsapi32.lib; Userenv.lib

#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <strsafe.h>
#include <string>
#include <vector>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")

// ----- service identity -----
static const wchar_t* kSvcName = L"QCMCH";
static const wchar_t* kSvcDisp = L"QCM Chrome AutoLogin Service";

// ----- globals -----
static SERVICE_STATUS_HANDLE gSsh = nullptr;
static SERVICE_STATUS        gSs = {};
static HANDLE                gStopEvt = nullptr;
static HANDLE                gChildProc = nullptr;
static DWORD                 gChildSid = (DWORD)-1;   // session id where child runs
static HANDLE                gProfileToken = nullptr; // token used to load profile
static HANDLE                gUserProfile = nullptr;  // HPROFILE kept while child alive

// ----- tiny logger -----
static void log_line(const wchar_t* fmt, ...)
{
    wchar_t buf[1024];
    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t ts[64];
    StringCchPrintfW(ts, 64, L"%04u-%02u-%02u %02u:%02u:%02u",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

    va_list ap; va_start(ap, fmt);
    StringCchVPrintfW(buf, 1024, fmt, ap);
    va_end(ap);

    CreateDirectoryW(L"C:\\PAM", nullptr);
    HANDLE f = CreateFileW(L"C:\\PAM\\ch_wrapper.log", GENERIC_WRITE, FILE_SHARE_READ,
        nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f != INVALID_HANDLE_VALUE) {
        SetFilePointer(f, 0, nullptr, FILE_END);
        DWORD dw;
        wchar_t line[1400];
        StringCchPrintfW(line, 1400, L"%s [CH-WRAPPER] %s\r\n", ts, buf);
        WriteFile(f, line, (DWORD)(wcslen(line) * sizeof(wchar_t)), &dw, nullptr);
        CloseHandle(f);
    }
}

// ----- service helpers -----
static void set_state(DWORD s, DWORD win32 = NO_ERROR, DWORD waitHintMs = 0)
{
    gSs.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    gSs.dwCurrentState = s;
    gSs.dwWin32ExitCode = win32;
    gSs.dwControlsAccepted = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    gSs.dwWaitHint = waitHintMs;
    SetServiceStatus(gSsh, &gSs);
}

static void unload_profile_if_any()
{
    if (gUserProfile && gProfileToken) {
        UnloadUserProfile(gProfileToken, gUserProfile);
    }
    if (gProfileToken) CloseHandle(gProfileToken);
    gUserProfile = nullptr;
    gProfileToken = nullptr;
}

static void kill_child()
{
    if (!gChildProc) return;
    log_line(L"Stopping child...");
    TerminateProcess(gChildProc, 0);
    WaitForSingleObject(gChildProc, 4000);
    CloseHandle(gChildProc);
    gChildProc = nullptr;
    gChildSid = (DWORD)-1;
    unload_profile_if_any();
}

// ----- WTS helpers -----
static bool get_session_string(DWORD sid, WTS_INFO_CLASS cls, std::wstring& out)
{
    LPWSTR p = nullptr; DWORD bytes = 0;
    if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, cls, &p, &bytes) && p) {
        out.assign(p);
        WTSFreeMemory(p);
        return true;
    }
    return false;
}

static bool get_session_state(DWORD sid, WTS_CONNECTSTATE_CLASS& state)
{
    LPTSTR p = nullptr; DWORD bytes = 0;
    if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSConnectState, &p, &bytes) && p) {
        state = *(WTS_CONNECTSTATE_CLASS*)p;
        WTSFreeMemory(p);
        return true;
    }
    return false;
}

struct SessionPick {
    DWORD sid = (DWORD)-1;
    std::wstring user;
    WTS_CONNECTSTATE_CLASS state = WTSDown;
};

// Prefer Active `ad2`, then Disc `ad2`, then Active `db`, then Disc `db`
static SessionPick find_target_session()
{
    SessionPick pref[4]; // store best candidates
    for (auto& e : pref) e.sid = (DWORD)-1;

    PWTS_SESSION_INFOW p = nullptr; DWORD count = 0;
    if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &p, &count)) {
        log_line(L"WTSEnumerateSessionsW failed ec=%lu", GetLastError());
        return {};
    }

    for (DWORD i = 0; i < count; ++i) {
        DWORD sid = p[i].SessionId;

        std::wstring uname;
        if (!get_session_string(sid, WTSUserName, uname) || uname.empty()) continue;

        bool isAD2 = (_wcsicmp(uname.c_str(), L"ad2") == 0);
        bool isDB  = (_wcsicmp(uname.c_str(), L"db")  == 0);
        if (!(isAD2 || isDB)) continue;

        WTS_CONNECTSTATE_CLASS st;
        if (!get_session_state(sid, st)) continue;

        if (st == WTSActive) {
            if (isAD2 && pref[0].sid == (DWORD)-1) { pref[0] = { sid, uname, st }; }
            else if (isDB && pref[2].sid == (DWORD)-1) { pref[2] = { sid, uname, st }; }
        } else if (st == WTSDisconnected) {
            if (isAD2 && pref[1].sid == (DWORD)-1) { pref[1] = { sid, uname, st }; }
            else if (isDB && pref[3].sid == (DWORD)-1) { pref[3] = { sid, uname, st }; }
        } else {
            log_line(L"Found user=%s sid=%u state=%d (ignored)", uname.c_str(), sid, (int)st);
        }
    }
    if (p) WTSFreeMemory(p);

    for (auto& pick : pref) {
        if (pick.sid != (DWORD)-1) {
            log_line(L"Target pick: user=%s sid=%u state=%d", pick.user.c_str(), pick.sid, (int)pick.state);
            return pick;
        }
    }
    return {};
}

// ----- launch Rust CH inside target user session -----
static HANDLE launch_rust_in_session(const SessionPick& sp)
{
    HANDLE userTok = nullptr, primaryTok = nullptr;
    if (!WTSQueryUserToken(sp.sid, &userTok)) {
        log_line(L"WTSQueryUserToken failed ec=%lu (sid=%u user=%s state=%d)",
                 GetLastError(), sp.sid, sp.user.c_str(), (int)sp.state);
        return nullptr;
    }

    // Use SecurityImpersonation for reliability
    SECURITY_ATTRIBUTES sa{}; sa.nLength = sizeof(sa);
    if (!DuplicateTokenEx(userTok, TOKEN_ALL_ACCESS, &sa,
                          SecurityImpersonation, TokenPrimary, &primaryTok)) {
        log_line(L"DuplicateTokenEx failed ec=%lu", GetLastError());
        CloseHandle(userTok);
        return nullptr;
    }
    CloseHandle(userTok);

    // Load user profile (keep loaded while child is alive)
    PROFILEINFOW prof{}; prof.dwSize = sizeof(prof);
    prof.lpUserName = const_cast<LPWSTR>(sp.user.c_str());
    if (!LoadUserProfileW(primaryTok, &prof)) {
        log_line(L"LoadUserProfile failed ec=%lu (continuing)", GetLastError());
        gUserProfile = nullptr;
    } else {
        gUserProfile = prof.hProfile;
        gProfileToken = primaryTok; // keep token handle to unload later
        DuplicateHandle(GetCurrentProcess(), primaryTok, GetCurrentProcess(), &gProfileToken, 0, FALSE, DUPLICATE_SAME_ACCESS);
    }

    LPVOID env = nullptr;
    if (!CreateEnvironmentBlock(&env, primaryTok, FALSE)) {
        log_line(L"CreateEnvironmentBlock failed ec=%lu (continuing with NULL env)", GetLastError());
        env = nullptr;
    }

    const wchar_t* exePath = L"C:\\PAM\\qcm_autologin_service.exe";
    const wchar_t* workDir = L"C:\\PAM";
    wchar_t cmd[512];
    StringCchPrintfW(cmd, 512, L"\"%s\" --port 10443 --log-dir C:\\PAM\\logs", exePath);

    STARTUPINFOW si{}; si.cb = sizeof(si);
    si.lpDesktop = const_cast<LPWSTR>(L"winsta0\\default"); // must be interactive desktop
    PROCESS_INFORMATION pi{};

    // Pass everything via CommandLine (mutable buffer), ApplicationName = nullptr
    BOOL ok = CreateProcessAsUserW(
        primaryTok,
        nullptr,            // ApplicationName
        cmd,                // CommandLine (MUTABLE)
        nullptr, nullptr, FALSE,
        CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_PROCESS_GROUP | CREATE_NEW_CONSOLE,
        env,
        workDir,
        &si,
        &pi);

    if (env) DestroyEnvironmentBlock(env);

    if (!ok) {
        log_line(L"CreateProcessAsUser failed ec=%lu (sid=%u user=%s state=%d)",
                 GetLastError(), sp.sid, sp.user.c_str(), (int)sp.state);
        if (gUserProfile && gProfileToken) {
            UnloadUserProfile(gProfileToken, gUserProfile);
        }
        if (gProfileToken) CloseHandle(gProfileToken);
        gUserProfile = nullptr;
        gProfileToken = nullptr;
        CloseHandle(primaryTok);
        return nullptr;
    }

    CloseHandle(pi.hThread);
    log_line(L"Launched CH: pid=%lu sid=%u user=%s state=%d exe=%s",
             pi.dwProcessId, sp.sid, sp.user.c_str(), (int)sp.state, exePath);

    // Keep token until we unload profile later
    CloseHandle(primaryTok);
    return pi.hProcess;
}

// ----- worker thread -----
static DWORD WINAPI worker(LPVOID)
{
    log_line(L"Service worker start");
    CreateDirectoryW(L"C:\\PAM\\logs", nullptr);

    for (;;) {
        if (WaitForSingleObject(gStopEvt, 0) == WAIT_OBJECT_0) break;

        SessionPick sp = find_target_session();

        if (sp.sid != (DWORD)-1) {
            // If child not running → start; if running in different SID → restart
            if (!gChildProc) {
                log_line(L"No child running; launching in sid=%u user=%s", sp.sid, sp.user.c_str());
                gChildProc = launch_rust_in_session(sp);
                gChildSid  = (gChildProc ? sp.sid : (DWORD)-1);
            } else {
                if (WaitForSingleObject(gChildProc, 0) == WAIT_OBJECT_0) {
                    DWORD ec = 0; GetExitCodeProcess(gChildProc, &ec);
                    log_line(L"Child exited code=%lu; clearing", ec);
                    CloseHandle(gChildProc); gChildProc = nullptr;
                    unload_profile_if_any();
                    gChildSid = (DWORD)-1;
                } else if (gChildSid != sp.sid) {
                    log_line(L"Target session changed (%u -> %u); recycling child", gChildSid, sp.sid);
                    kill_child();
                    gChildProc = launch_rust_in_session(sp);
                    gChildSid  = (gChildProc ? sp.sid : (DWORD)-1);
                }
            }
        } else {
            // No ad2/db session exists → stop child if any
            if (gChildProc) {
                log_line(L"No ad2/db session present; stopping child");
                kill_child();
            }
        }

        if (WaitForSingleObject(gStopEvt, 1500) == WAIT_OBJECT_0) break;
    }

    kill_child();
    log_line(L"Worker exit");
    return 0;
}

// ----- SCM plumbing -----
static void WINAPI ctrl_handler(DWORD code)
{
    if (code == SERVICE_CONTROL_STOP || code == SERVICE_CONTROL_SHUTDOWN) {
        set_state(SERVICE_STOP_PENDING, NO_ERROR, 4000);
        SetEvent(gStopEvt);
    }
}

static void WINAPI svc_main(DWORD, LPWSTR*)
{
    gSsh = RegisterServiceCtrlHandlerW(kSvcName, ctrl_handler);
    if (!gSsh) return;

    set_state(SERVICE_START_PENDING, NO_ERROR, 4000);
    gStopEvt = CreateEventW(nullptr, TRUE, FALSE, nullptr);

    HANDLE th = CreateThread(nullptr, 0, worker, nullptr, 0, nullptr);
    set_state(SERVICE_RUNNING);

    WaitForSingleObject(th, INFINITE);
    CloseHandle(th);
    CloseHandle(gStopEvt); gStopEvt = nullptr;

    set_state(SERVICE_STOPPED);
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int)
{
    SERVICE_TABLE_ENTRYW ste[] = {
        { (LPWSTR)kSvcName, svc_main },
        { nullptr, nullptr }
    };
    StartServiceCtrlDispatcherW(ste);
    return 0;
}
