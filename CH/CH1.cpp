// qcm_ch.cpp — QCM Chrome AutoLogin Windows Service Wrapper
// Build: VS2017+, x64, Unicode. Link with Advapi32.lib; Wtsapi32.lib; Userenv.lib

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

static void kill_child()
{
    if (!gChildProc) return;
    log_line(L"Stopping child...");
    TerminateProcess(gChildProc, 0);
    WaitForSingleObject(gChildProc, 4000);
    CloseHandle(gChildProc);
    gChildProc = nullptr;
}

// ----- enumerate sessions (CJ-style) -----
static DWORD find_active_rdp_session()
{
    PWTS_SESSION_INFOW p = nullptr; DWORD count = 0;
    if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &p, &count))
        return (DWORD)-1;

    DWORD foundSid = (DWORD)-1;

    for (DWORD i = 0; i < count; ++i) {
        DWORD sid = p[i].SessionId;

        // Query state
        DWORD bytes = 0;
        WTS_CONNECTSTATE_CLASS* pState = nullptr;
        if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSConnectState, (LPWSTR*)&pState, &bytes) && pState) {
            if (*pState == WTSActive) {
                // Query protocol
                LPWSTR pProto = nullptr; int proto = 0;
                if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSClientProtocolType, (LPWSTR*)&pProto, &bytes) && pProto) {
                    proto = *(USHORT*)pProto;
                    WTSFreeMemory(pProto);
                }
                if (proto == 2) { // RDP
                    foundSid = sid;
                    log_line(L"Active RDP session found sid=%u", sid);
                    break;
                }
            }
            WTSFreeMemory(pState);
        }
    }

    if (p) WTSFreeMemory(p);
    return foundSid;
}

// fallback: console session
static DWORD get_console_session()
{
    DWORD sid = WTSGetActiveConsoleSessionId();
    if (sid == 0xFFFFFFFF) return (DWORD)-1;
    return sid;
}

// ----- launch Rust CH inside user session -----
static HANDLE launch_rust_in_session(DWORD sessionId)
{
    HANDLE userTok = nullptr, primaryTok = nullptr;
    if (!WTSQueryUserToken(sessionId, &userTok)) {
        log_line(L"WTSQueryUserToken failed ec=%lu (sid=%u)", GetLastError(), sessionId);
        return nullptr;
    }

    if (!DuplicateTokenEx(userTok, TOKEN_ALL_ACCESS, nullptr,
        SecurityIdentification, TokenPrimary, &primaryTok)) {
        log_line(L"DuplicateTokenEx failed ec=%lu", GetLastError());
        CloseHandle(userTok);
        return nullptr;
    }
    CloseHandle(userTok);

    // load profile (best effort)
    PROFILEINFOW prof{}; prof.dwSize = sizeof(prof); prof.lpUserName = NULL;
    LoadUserProfileW(primaryTok, &prof);

    LPVOID env = nullptr;
    CreateEnvironmentBlock(&env, primaryTok, FALSE);

    const wchar_t* exe = L"C:\\PAM\\qcm_autologin_service.exe";
    wchar_t cmd[512];
    StringCchPrintfW(cmd, 512, L"\"%s\" --port 10443 --log-dir C:\\PAM\\logs", exe);

    STARTUPINFOW si{}; si.cb = sizeof(si);
    si.lpDesktop = (LPWSTR)L"winsta0\\default";
    PROCESS_INFORMATION pi{};

    BOOL ok = CreateProcessAsUserW(
        primaryTok,
        exe,
        cmd,
        nullptr, nullptr, FALSE,
        CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_PROCESS_GROUP,
        env,
        L"C:\\PAM",
        &si,
        &pi);

    if (!ok) {
        log_line(L"CreateProcessAsUser failed ec=%lu", GetLastError());
        if (env) DestroyEnvironmentBlock(env);
        if (primaryTok) { UnloadUserProfile(primaryTok, prof.hProfile); CloseHandle(primaryTok); }
        return nullptr;
    }

    if (env) DestroyEnvironmentBlock(env);
    if (primaryTok) { UnloadUserProfile(primaryTok, prof.hProfile); CloseHandle(primaryTok); }

    CloseHandle(pi.hThread);
    log_line(L"Launched Rust CH in session %u pid=%lu", sessionId, pi.dwProcessId);
    return pi.hProcess;
}

// ----- worker thread -----
static DWORD WINAPI worker(LPVOID)
{
    log_line(L"Service worker start");
    CreateDirectoryW(L"C:\\PAM\\logs", nullptr);

    for (;;) {
        if (WaitForSingleObject(gStopEvt, 0) == WAIT_OBJECT_0) break;

        DWORD sid = find_active_rdp_session();
        if (sid == (DWORD)-1) sid = get_console_session();

        if (sid != (DWORD)-1) {
            if (!gChildProc) {
                gChildProc = launch_rust_in_session(sid);
            } else {
                if (WaitForSingleObject(gChildProc, 0) == WAIT_OBJECT_0) {
                    DWORD ec = 0; GetExitCodeProcess(gChildProc, &ec);
                    log_line(L"Rust CH exited code=%lu", ec);
                    CloseHandle(gChildProc); gChildProc = nullptr;
                }
            }
        } else {
            if (gChildProc) {
                log_line(L"No active session, stopping child");
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
