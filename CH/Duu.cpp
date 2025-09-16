// qcm_ch.cpp  — Windows service wrapper for Rust CH
// Build: x64, Unicode. Link: Advapi32.lib; Wtsapi32.lib; Userenv.lib

#define UNICODE
#define _UNICODE
#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <strsafe.h>
#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")

// ----- service identity -----
static const wchar_t* kSvcName = L"QCMCH";
static const wchar_t* kSvcDisp = L"QCM Chrome AutoLogin Service";

// ----- globals -----
static SERVICE_STATUS_HANDLE gSsh = nullptr;
static SERVICE_STATUS        gSs  = {};
static HANDLE                gStopEvt = nullptr;
static HANDLE                gChildProc = nullptr;

// ----- tiny file logger -----
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
    gSs.dwServiceType             = SERVICE_WIN32_OWN_PROCESS;
    gSs.dwCurrentState            = s;
    gSs.dwWin32ExitCode           = win32;
    gSs.dwControlsAccepted        = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    gSs.dwWaitHint                = waitHintMs;
    SetServiceStatus(gSsh, &gSs);
}

static void kill_child()
{
    if (!gChildProc) return;
    log_line(L"Stopping child...");
    TerminateProcess(gChildProc, 0);
    WaitForSingleObject(gChildProc, 4000);
    CloseHandle(gChildProc);
    gChildProc = nullptr;
}

// Returns active RDP session id or -1 if none
static int get_active_rdp_session()
{
    PWTS_SESSION_INFOW p = nullptr; DWORD count = 0;
    if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &p, &count))
        return -1;

    int sid = -1;
    for (DWORD i = 0; i < count; ++i) {
        if (p[i].State == WTSActive && p[i].SessionId != 0) { // 0 = services / session0
            sid = (int)p[i].SessionId;
            break;
        }
    }
    if (p) WTSFreeMemory(p);
    return sid;
}

// Launch Rust CH visible in the user session desktop, return PROCESS handle (caller closes)
static HANDLE launch_rust_in_session(int sessionId)
{
    HANDLE userTok = nullptr, primaryTok = nullptr;
    if (!WTSQueryUserToken((ULONG)sessionId, &userTok)) {
        log_line(L"WTSQueryUserToken failed ec=%lu (sid=%d)", GetLastError(), sessionId);
        return nullptr;
    }

    SECURITY_ATTRIBUTES sa{ sizeof(sa) };
    if (!DuplicateTokenEx(userTok, TOKEN_ALL_ACCESS, &sa,
                          SecurityIdentification, TokenPrimary, &primaryTok)) {
        log_line(L"DuplicateTokenEx failed ec=%lu", GetLastError());
        CloseHandle(userTok);
        return nullptr;
    }
    CloseHandle(userTok);

    PROFILEINFOW pi{}; 
    pi.dwSize = sizeof(pi);
    pi.lpUserName = L".";
    HANDLE hProfile = nullptr;
    // Try loading profile (best-effort; ignore failure)
    LoadUserProfileW(primaryTok, &pi);

    // Build environment for the user
    LPVOID env = nullptr;
    CreateEnvironmentBlock(&env, primaryTok, FALSE);

    // Prepare command
    const wchar_t* exe = L"C:\\PAM\\qcm_autologin_service.exe";
    wchar_t cmd[1024]; 
    StringCchPrintfW(cmd, 1024,
        L"\"%s\" --port 10443 --log-dir C:\\PAM\\logs", exe);

    STARTUPINFOW si{}; si.cb = sizeof(si);
    si.lpDesktop = (LPWSTR)L"winsta0\\default";           // *** visible on RDP desktop ***
    si.dwFlags  |= STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;                             // hide CH console window

    PROCESS_INFORMATION piProc{};
    BOOL ok = CreateProcessAsUserW(
        primaryTok,
        exe,                   // lpApplicationName
        cmd,                   // lpCommandLine
        nullptr, nullptr, FALSE,
        CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS,
        env,                   // environment
        L"C:\\PAM",            // working dir
        &si, &piProc);

    if (!ok) {
        log_line(L"CreateProcessAsUser failed ec=%lu (sid=%d)", GetLastError(), sessionId);
        if (env) DestroyEnvironmentBlock(env);
        if (primaryTok) { UnloadUserProfile(primaryTok, hProfile); CloseHandle(primaryTok); }
        return nullptr;
    }

    if (env) DestroyEnvironmentBlock(env);
    if (primaryTok) { UnloadUserProfile(primaryTok, hProfile); CloseHandle(primaryTok); }

    CloseHandle(piProc.hThread);
    log_line(L"Launched Rust CH in session %d, pid %lu", sessionId, piProc.dwProcessId);
    return piProc.hProcess;
}

// ----- worker thread -----
static DWORD WINAPI worker(LPVOID)
{
    log_line(L"Service worker start");
    CreateDirectoryW(L"C:\\PAM\\logs", nullptr);

    int lastSid = -1;

    for (;;) {
        // stop?
        if (WaitForSingleObject(gStopEvt, 0) == WAIT_OBJECT_0) break;

        int sid = get_active_rdp_session();
        if (sid > 0) {
            if (!gChildProc) {
                log_line(L"Active RDP session found: %d", sid);
                gChildProc = launch_rust_in_session(sid);
                lastSid = sid;
            } else {
                // if child died, clear handle and try again next loop
                if (WaitForSingleObject(gChildProc, 0) == WAIT_OBJECT_0) {
                    DWORD ec = 0; GetExitCodeProcess(gChildProc, &ec);
                    log_line(L"Rust CH exited (code=%lu). Will restart when session is active.", ec);
                    CloseHandle(gChildProc); gChildProc = nullptr;
                }
            }
        } else {
            // no active RDP session -> if child running, stop it
            if (gChildProc) {
                log_line(L"No ACTIVE RDP session; stopping child");
                kill_child();
            }
        }

        // wait a bit
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
