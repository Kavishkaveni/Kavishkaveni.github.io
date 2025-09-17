// QCM-CH.cpp - Service wrapper that launches Rust CH in the ACTIVE RDP session
// Build: x64, Unicode. Link: Advapi32.lib; Wtsapi32.lib; Userenv.lib

#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <strsafe.h>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")

// -------- configuration --------
static const wchar_t* kServiceName   = L"QCMCH";
static const wchar_t* kDisplayName   = L"QCM Chrome AutoLogin Service";
static const wchar_t* kLogDir        = L"C:\\PAM";
static const wchar_t* kLogPath       = L"C:\\PAM\\ch_wrapper.log";
static const wchar_t* kChildExePath  = L"C:\\PAM\\qcm_autologin_service.exe";
// NOTE: no --service flag; run as a normal app inside the user session
static const wchar_t* kChildArgs     = L" --port 10443 --log-dir C:\\PAM\\logs";

// -------- globals --------
static SERVICE_STATUS_HANDLE gSsh = nullptr;
static SERVICE_STATUS        gSs  = {};
static HANDLE                gStopEvt = nullptr;
static HANDLE                gChild   = nullptr;
static DWORD                 gChildSid = (DWORD)-1;

// -------- tiny logger --------
static void LogF(PCWSTR fmt, ...)
{
    CreateDirectoryW(kLogDir, nullptr);

    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t ts[64];
    StringCchPrintfW(ts, 64, L"%04u-%02u-%02u %02u:%02u:%02u",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

    wchar_t line[1600];
    va_list ap; va_start(ap, fmt);
    StringCchVPrintfW(line, 1600, fmt, ap);
    va_end(ap);

    HANDLE f = CreateFileW(kLogPath, FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f != INVALID_HANDLE_VALUE) {
        wchar_t out[1800];
        StringCchPrintfW(out, 1800, L"%s [CH-WRAPPER] %s\r\n", ts, line);
        DWORD cb = (DWORD)(lstrlenW(out) * sizeof(wchar_t));
        WriteFile(f, out, cb, &cb, nullptr);
        CloseHandle(f);
    }
}

// -------- service helpers --------
static void SetState(DWORD s, DWORD win32 = NO_ERROR, DWORD waitHintMs = 0)
{
    gSs.dwServiceType             = SERVICE_WIN32_OWN_PROCESS;
    gSs.dwCurrentState            = s;
    gSs.dwWin32ExitCode           = win32;
    gSs.dwControlsAccepted        = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    gSs.dwWaitHint                = waitHintMs;
    SetServiceStatus(gSsh, &gSs);
}

static void KillChild()
{
    if (!gChild) return;
    LogF(L"Stopping child (sid=%lu)...", (unsigned)gChildSid);
    TerminateProcess(gChild, 0);
    WaitForSingleObject(gChild, 4000);
    CloseHandle(gChild);
    gChild = nullptr;
    gChildSid = (DWORD)-1;
}

// Enable a privilege on the service process token (needed by CreateProcessAsUser on some systems)
static void EnablePriv(LPCWSTR name)
{
    HANDLE tok = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &tok))
        return;
    TOKEN_PRIVILEGES tp{};
    LUID luid{};
    if (LookupPrivilegeValueW(nullptr, name, &luid)) {
        tp.PrivilegeCount = 1;
        tp.Privileges[0].Luid = luid;
        tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
        AdjustTokenPrivileges(tok, FALSE, &tp, sizeof(tp), nullptr, nullptr);
    }
    CloseHandle(tok);
}

// -------- session helpers --------

// Return Active RDP session id (proto==2), or (DWORD)-1 if none
static DWORD FindActiveRdpSession()
{
    PWTS_SESSION_INFO p = nullptr; DWORD count = 0;
    if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &p, &count))
        return (DWORD)-1;

    DWORD found = (DWORD)-1;

    for (DWORD i = 0; i < count; ++i) {
        DWORD sid = p[i].SessionId;

        DWORD bytes = 0;
        WTS_CONNECTSTATE_CLASS* pState = nullptr;
        if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSConnectState, (LPWSTR*)&pState, &bytes) || !pState) {
            if (pState) WTSFreeMemory(pState);
            continue;
        }
        WTS_CONNECTSTATE_CLASS state = *pState;
        WTSFreeMemory(pState);

        USHORT proto = 0;
        LPWSTR pProto = nullptr;
        if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSClientProtocolType, (LPWSTR*)&pProto, &bytes) && pProto) {
            proto = *(USHORT*)pProto;
            WTSFreeMemory(pProto);
        }

        if (state == WTSActive && proto == 2) { // RDP
            found = sid;
            break;
        }
    }

    if (p) WTSFreeMemory(p);
    return found;
}

// Launch child inside specific session's interactive desktop.
// Returns PROCESS handle if started, else nullptr. Caller closes handle.
static HANDLE LaunchChildInSession(DWORD sessionId)
{
    HANDLE userTok = nullptr;
    if (!WTSQueryUserToken(sessionId, &userTok)) {
        LogF(L"WTSQueryUserToken failed ec=%lu (sid=%lu)", GetLastError(), (unsigned)sessionId);
        return nullptr;
    }

    HANDLE primaryTok = nullptr;
    SECURITY_ATTRIBUTES sa{ sizeof(sa) };
    if (!DuplicateTokenEx(userTok, TOKEN_ALL_ACCESS, &sa, SecurityIdentification, TokenPrimary, &primaryTok)) {
        LogF(L"DuplicateTokenEx failed ec=%lu", GetLastError());
        CloseHandle(userTok);
        return nullptr;
    }
    CloseHandle(userTok);

    PROFILEINFOW pi{}; pi.dwSize = sizeof(pi); // best-effort
    if (!LoadUserProfileW(primaryTok, &pi)) {
        LogF(L"LoadUserProfileW failed ec=%lu (continuing)", GetLastError());
    }

    LPVOID env = nullptr;
    if (!CreateEnvironmentBlock(&env, primaryTok, FALSE)) {
        LogF(L"CreateEnvironmentBlock failed ec=%lu (continuing without env)", GetLastError());
        env = nullptr;
    }

    // Build command line
    wchar_t cmd[1024];
    StringCchCopyW(cmd, 1024, L"\"");
    StringCchCatW(cmd, 1024, kChildExePath);
    StringCchCatW(cmd, 1024, L"\"");
    if (kChildArgs && *kChildArgs) {
        StringCchCatW(cmd, 1024, kChildArgs);
    }

    STARTUPINFOW si{}; si.cb = sizeof(si);
    si.lpDesktop = (LPWSTR)L"winsta0\\default";
    si.dwFlags   = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE; // hide console of Rust EXE

    PROCESS_INFORMATION piProc{};
    BOOL ok = CreateProcessAsUserW(
        primaryTok,
        kChildExePath,     // application
        cmd,               // command line
        nullptr, nullptr, FALSE,
        CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS,
        env,
        L"C:\\PAM",        // working dir
        &si,
        &piProc);

    if (!ok) {
        LogF(L"CreateProcessAsUserW failed ec=%lu (sid=%lu)", GetLastError(), (unsigned)sessionId);
        if (env) DestroyEnvironmentBlock(env);
        if (pi.hProfile) UnloadUserProfile(primaryTok, pi.hProfile);
        CloseHandle(primaryTok);
        return nullptr;
    }

    if (env) DestroyEnvironmentBlock(env);
    if (pi.hProfile) UnloadUserProfile(primaryTok, pi.hProfile);
    CloseHandle(primaryTok);
    CloseHandle(piProc.hThread);

    LogF(L"Launched Rust CH in session %lu, pid %lu", (unsigned)sessionId, (unsigned)piProc.dwProcessId);
    return piProc.hProcess;
}

// -------- worker --------
static DWORD WINAPI Worker(LPVOID)
{
    LogF(L"Service worker start");

    // Make sure we have the two privileges most commonly required
    EnablePriv(SE_ASSIGNPRIMARYTOKEN_NAME);
    EnablePriv(SE_INCREASE_QUOTA_NAME);

    for (;;) {
        if (WaitForSingleObject(gStopEvt, 0) == WAIT_OBJECT_0)
            break;

        DWORD activeSid = FindActiveRdpSession();

        if (activeSid == (DWORD)-1) {
            // No active RDP session → ensure child is stopped
            if (gChild) {
                LogF(L"No active RDP session; stopping child");
                KillChild();
            }
        } else {
            // Active RDP exists
            if (!gChild) {
                gChild = LaunchChildInSession(activeSid);
                gChildSid = activeSid;
            } else {
                // child alive? did session change?
                if (WaitForSingleObject(gChild, 0) == WAIT_OBJECT_0) {
                    DWORD ec = 0; GetExitCodeProcess(gChild, &ec);
                    LogF(L"Rust CH exited (code=%lu). Restarting when session active.", ec);
                    CloseHandle(gChild); gChild = nullptr; gChildSid = (DWORD)-1;
                } else if (gChildSid != activeSid) {
                    LogF(L"Active session changed %lu -> %lu; restarting child", (unsigned)gChildSid, (unsigned)activeSid);
                    KillChild();
                    gChild = LaunchChildInSession(activeSid);
                    gChildSid = activeSid;
                }
            }
        }

        if (WaitForSingleObject(gStopEvt, 1200) == WAIT_OBJECT_0)
            break;
    }

    KillChild();
    LogF(L"Worker exit");
    return 0;
}

// -------- SCM plumbing --------
static void WINAPI CtrlHandler(DWORD code)
{
    if (code == SERVICE_CONTROL_STOP || code == SERVICE_CONTROL_SHUTDOWN) {
        SetState(SERVICE_STOP_PENDING, NO_ERROR, 4000);
        SetEvent(gStopEvt);
    }
}

static void WINAPI SvcMain(DWORD, LPWSTR*)
{
    gSsh = RegisterServiceCtrlHandlerW(kServiceName, CtrlHandler);
    if (!gSsh) return;

    SetState(SERVICE_START_PENDING, NO_ERROR, 4000);

    gStopEvt = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE th = CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);

    SetState(SERVICE_RUNNING);

    WaitForSingleObject(th, INFINITE);
    CloseHandle(th);
    CloseHandle(gStopEvt); gStopEvt = nullptr;

    SetState(SERVICE_STOPPED);
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int)
{
    SERVICE_TABLE_ENTRYW ste[] = {
        { (LPWSTR)kServiceName, SvcMain },
        { nullptr, nullptr }
    };
    StartServiceCtrlDispatcherW(ste);
    return 0;
}
