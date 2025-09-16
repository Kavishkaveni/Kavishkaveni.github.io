// QCM-CH.cpp  (wrapper service that launches Rust CH into the active RDP session)
// Toolset: VS2017 (v141). SDK: pick one your toolset supports (e.g. 10.0.19041 or older).

#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <strsafe.h>
#include <tlhelp32.h>
#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")

// ---- service ids ----
static const wchar_t* kSvcName = L"QCMCH";
static const wchar_t* kSvcDisp = L"QCM Chrome AutoLogin Service";

// ---- globals ----
static SERVICE_STATUS_HANDLE gSsh = nullptr;
static SERVICE_STATUS gSs{};
static HANDLE gStopEvent = nullptr;
static HANDLE gChildProc = nullptr;

// ---- logging ----
static void log_line(const wchar_t* fmt, ...)
{
    wchar_t buf[1024];
    SYSTEMTIME st; GetLocalTime(&st);
    int n = swprintf_s(buf, L"%04d-%02d-%02d %02d:%02d:%02d  [CH-WRAPPER] ",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

    va_list ap; va_start(ap, fmt);
    StringCchVPrintfW(buf + n, _countof(buf) - n, fmt, ap);
    va_end(ap);

    StringCchCatW(buf, _countof(buf), L"\r\n");

    CreateDirectoryW(L"C:\\PAM", nullptr);
    HANDLE h = CreateFileW(L"C:\\PAM\\ch_wrapper.log",
        FILE_APPEND_DATA, FILE_SHARE_READ, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h != INVALID_HANDLE_VALUE) {
        DWORD cb = (DWORD)(wcslen(buf) * sizeof(wchar_t));
        WriteFile(h, buf, cb, &cb, nullptr);
        CloseHandle(h);
    }
}

// ---- service status helper ----
static void SetState(DWORD s, DWORD win32 = NO_ERROR, DWORD waitHintMs = 0)
{
    gSs.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    gSs.dwCurrentState = s;
    gSs.dwWin32ExitCode = win32;
    gSs.dwControlsAccepted = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    gSs.dwWaitHint = waitHintMs;
    SetServiceStatus(gSsh, &gSs);
}

// ---- find the active RDP session id (proto RDP), else return -1 ----
static DWORD FindActiveRdpSession()
{
    PWTS_SESSION_INFOW p = nullptr; DWORD count = 0;
    if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &p, &count))
        return (DWORD)-1;

    DWORD sid = (DWORD)-1;
    for (DWORD i = 0; i < count; ++i) {
        // Prefer an ACTIVE RDP session (name starts with "RDP-")
        if (p[i].State == WTSActive && p[i].pWinStationName) {
            if (_wcsnicmp(p[i].pWinStationName, L"RDP-", 4) == 0 ||
                _wcsnicmp(p[i].pWinStationName, L"RDP-Tcp", 7) == 0) {
                sid = p[i].SessionId;
                break;
            }
        }
    }
    if (p) WTSFreeMemory(p);
    return sid;
}

// ---- kill process tree ----
static void KillProcessTree(HANDLE hProcess)
{
    if (!hProcess) return;
    DWORD pid = GetProcessId(hProcess);
    if (!pid) return;

    // best-effort
    GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, 0);
    TerminateProcess(hProcess, 0);

    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap != INVALID_HANDLE_VALUE) {
        PROCESSENTRY32W pe{ sizeof(pe) };
        if (Process32FirstW(snap, &pe)) {
            do {
                if (pe.th32ParentProcessID == pid) {
                    HANDLE ch = OpenProcess(PROCESS_TERMINATE, FALSE, pe.th32ProcessID);
                    if (ch) { TerminateProcess(ch, 0); CloseHandle(ch); }
                }
            } while (Process32NextW(snap, &pe));
        }
        CloseHandle(snap);
    }
}

// ---- launch Rust CH into a target session, visible on user desktop ----
static HANDLE LaunchRustInSession(DWORD sessionId)
{
    HANDLE userToken = nullptr;
    if (!WTSQueryUserToken(sessionId, &userToken)) {
        log_line(L"WTSQueryUserToken failed ec=%lu (sid=%lu)", GetLastError(), sessionId);
        return nullptr;
    }

    HANDLE primary = nullptr;
    if (!DuplicateTokenEx(userToken, MAXIMUM_ALLOWED, nullptr, SecurityImpersonation, TokenPrimary, &primary)) {
        log_line(L"DuplicateTokenEx failed ec=%lu", GetLastError());
        CloseHandle(userToken);
        return nullptr;
    }
    CloseHandle(userToken);

    // environment for the user
    LPVOID env = nullptr;
    if (!CreateEnvironmentBlock(&env, primary, FALSE)) {
        env = nullptr; // continue without env
        log_line(L"CreateEnvironmentBlock failed ec=%lu (continuing)", GetLastError());
    }

    // prepare startup info for interactive desktop
    STARTUPINFOW si{}; si.cb = sizeof(si);
    wchar_t desktopName[] = L"winsta0\\default";
    si.lpDesktop = desktopName;
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_SHOWNORMAL;

    // working dir & command
    CreateDirectoryW(L"C:\\PAM\\logs", nullptr);
    const wchar_t* exePath = L"C:\\PAM\\qcm_autologin_service.exe";
    wchar_t cmdLine[512];
    StringCchPrintfW(cmdLine, 512, L"\"%s\" --port 10443 --log-dir C:\\PAM\\logs", exePath);

    PROCESS_INFORMATION pi{};
    DWORD flags = CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_CONSOLE;

    BOOL ok = CreateProcessAsUserW(
        primary,        // user token (primary)
        exePath,        // app
        cmdLine,        // command line
        nullptr, nullptr,
        FALSE,
        flags,
        env,
        L"C:\\PAM",     // working dir
        &si, &pi);

    if (!ok) {
        log_line(L"CreateProcessAsUserW failed ec=%lu", GetLastError());
        if (env) DestroyEnvironmentBlock(env);
        CloseHandle(primary);
        return nullptr;
    }

    if (env) DestroyEnvironmentBlock(env);
    CloseHandle(primary);
    CloseHandle(pi.hThread);

    log_line(L"Launched Rust CH in session %lu, PID %lu", sessionId, pi.dwProcessId);
    return pi.hProcess; // caller owns
}

// ---- service worker ----
static DWORD WINAPI Worker(LPVOID)
{
    log_line(L"Service worker start");
    for (;;) {
        if (WaitForSingleObject(gStopEvent, 0) == WAIT_OBJECT_0) break;

        // ensure child exists in the right session
        DWORD targetSid = FindActiveRdpSession();
        if (targetSid == (DWORD)-1) {
            // none: stop child if it exists
            if (gChildProc) {
                log_line(L"No ACTIVE RDP session; stopping child");
                KillProcessTree(gChildProc);
                CloseHandle(gChildProc); gChildProc = nullptr;
            }
        } else {
            // have active RDP session
            if (!gChildProc) {
                log_line(L"Active RDP session found: %lu", targetSid);
                gChildProc = LaunchRustInSession(targetSid);
                if (!gChildProc) {
                    // back off a little to avoid hammering
                    Sleep(2000);
                }
            } else {
                // keep an eye on the child
                DWORD wr = WaitForSingleObject(gChildProc, 0);
                if (wr == WAIT_OBJECT_0) {
                    DWORD ec = 0; GetExitCodeProcess(gChildProc, &ec);
                    log_line(L"Rust CH exited (code=%lu). Will restart.", ec);
                    CloseHandle(gChildProc); gChildProc = nullptr;
                    Sleep(1500);
                }
            }
        }

        Sleep(1000);
    }

    if (gChildProc) {
        KillProcessTree(gChildProc);
        CloseHandle(gChildProc); gChildProc = nullptr;
    }
    log_line(L"Service worker stop");
    return 0;
}

// ---- SCM glue ----
static void WINAPI CtrlHandler(DWORD ctrl)
{
    if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
        SetEvent(gStopEvent);
        SetState(SERVICE_STOP_PENDING, NO_ERROR, 3000);
    }
}

static void WINAPI SvcMain(DWORD, LPWSTR*)
{
    gSsh = RegisterServiceCtrlHandlerW(kSvcName, CtrlHandler);
    if (!gSsh) return;

    SetState(SERVICE_START_PENDING, NO_ERROR, 3000);
    gStopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE th = CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);
    SetState(SERVICE_RUNNING);

    WaitForSingleObject(th, INFINITE);
    CloseHandle(th);
    CloseHandle(gStopEvent); gStopEvent = nullptr;
    SetState(SERVICE_STOPPED);
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int)
{
    SERVICE_TABLE_ENTRYW ste[] = {
        { (LPWSTR)kSvcName, SvcMain },
        { nullptr, nullptr }
    };
    StartServiceCtrlDispatcherW(ste);
    return 0;
}
