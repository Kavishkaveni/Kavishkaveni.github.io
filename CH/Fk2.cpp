// QCM-CH.cpp  — Windows Service wrapper for Rust CH (qcm_autologin_service.exe)
// Build: Release x64, Unicode
// Linker -> Input: Advapi32.lib; Wtsapi32.lib; Userenv.lib
// Subsystem: Windows (/SUBSYSTEM:WINDOWS)  ← no console window for the service

#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <strsafe.h>
#include <wtsapi32.h>
#include <userenv.h>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")

// ====== Config you may adjust ======
static const wchar_t* kSvcName  = L"QCMCH";                       // SERVICE NAME
static const wchar_t* kSvcDisp  = L"QCM Chrome AutoLogin Service";
static const wchar_t* kChExe    = L"C:\\PAM\\qcm_autologin_service.exe";
static const wchar_t* kWorkDir  = L"C:\\PAM";
static const wchar_t* kArgs     = L" --port 10443 --log-dir C:\\PAM\\logs";
// ===================================

// ------------- tiny file logger ----------------
static void LogLine(PCWSTR fmt, ...)
{
    CreateDirectoryW(L"C:\\PAM", nullptr);
    wchar_t line[2048];
    va_list ap; va_start(ap, fmt);
    StringCchVPrintfW(line, _countof(line), fmt, ap);
    va_end(ap);

    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t msg[2300];
    StringCchPrintfW(msg, _countof(msg),
        L"%04u-%02u-%02u %02u:%02u:%02u [QCM-CH] %s\r\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, line);

    HANDLE h = CreateFileW(L"C:\\PAM\\ch_wrapper.log", FILE_APPEND_DATA, FILE_SHARE_READ,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h != INVALID_HANDLE_VALUE) {
        DWORD cb = (DWORD)(lstrlenW(msg) * sizeof(wchar_t));
        WriteFile(h, msg, cb, &cb, nullptr);
        CloseHandle(h);
    }
}

// ------------- service globals -----------------
static SERVICE_STATUS_HANDLE gSsh = nullptr;
static SERVICE_STATUS        gSs  = {};
static HANDLE                gStopEvent = nullptr;
static HANDLE                gChildProc = nullptr;

// ------------- service helpers -----------------
static void SetState(DWORD s, DWORD exitCode = NO_ERROR, DWORD waitHintMs = 0)
{
    gSs.dwServiceType             = SERVICE_WIN32_OWN_PROCESS;
    gSs.dwCurrentState            = s;
    gSs.dwWin32ExitCode           = exitCode;
    gSs.dwControlsAccepted        = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    gSs.dwWaitHint                = waitHintMs;
    SetServiceStatus(gSsh, &gSs);
}

// ------------- session helpers -----------------
// Find ACTIVE RDP session (proto=2). Fallback to console if none.
static DWORD FindActiveRdpSessionWithWait(DWORD maxWaitMs = 10000, DWORD pollMs = 1000)
{
    DWORD waited = 0;
    for (;;) {
        PWTS_SESSION_INFO pInfo = nullptr;
        DWORD count = 0;
        if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &pInfo, &count)) {
            LogLine(L"WTSEnumerateSessionsW failed ec=%lu", GetLastError());
            return (DWORD)-1;
        }

        DWORD found = (DWORD)-1;
        for (DWORD i = 0; i < count; ++i) {
            DWORD sid = pInfo[i].SessionId;

            // state
            DWORD bytes = 0;
            WTS_CONNECTSTATE_CLASS* pState = nullptr;
            if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSConnectState, (LPWSTR*)&pState, &bytes) || !pState) {
                if (pState) WTSFreeMemory(pState);
                continue;
            }
            WTS_CONNECTSTATE_CLASS state = *pState;
            WTSFreeMemory(pState);

            // protocol
            USHORT proto = 0;
            LPWSTR pProto = nullptr;
            if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSClientProtocolType, (LPWSTR*)&pProto, &bytes) && pProto) {
                proto = *(USHORT*)pProto;
                WTSFreeMemory(pProto);
            }

            if (state == WTSActive && proto == 2) { // 2 = RDP
                found = sid;
                break;
            }
        }
        WTSFreeMemory(pInfo);

        if (found != (DWORD)-1) {
            LogLine(L"Active RDP session found: %u", found);
            return found;
        }
        if (waited >= maxWaitMs) {
            LogLine(L"No ACTIVE RDP session (proto=2) after waiting.");
            break;
        }
        Sleep(pollMs);
        waited += pollMs;
    }

    DWORD consoleSid = WTSGetActiveConsoleSessionId();
    if (consoleSid == 0xFFFFFFFF) {
        LogLine(L"No console session.");
        return (DWORD)-1;
    }
    LogLine(L"Falling back to console session: %u", consoleSid);
    return consoleSid;
}

// Launch the Rust CH inside a specific session using that user token
static HANDLE LaunchRustInSession(DWORD sessionId)
{
    HANDLE hUserToken = nullptr;
    if (!WTSQueryUserToken(sessionId, &hUserToken)) {
        LogLine(L"WTSQueryUserToken failed ec=%lu (sid=%u)", GetLastError(), sessionId);
        return nullptr;
    }

    HANDLE hPrimary = nullptr;
    if (!DuplicateTokenEx(hUserToken, MAXIMUM_ALLOWED, nullptr, SecurityIdentification, TokenPrimary, &hPrimary)) {
        LogLine(L"DuplicateTokenEx failed ec=%lu", GetLastError());
        CloseHandle(hUserToken);
        return nullptr;
    }

    LPVOID env = nullptr;
    if (!CreateEnvironmentBlock(&env, hPrimary, FALSE)) {
        LogLine(L"CreateEnvironmentBlock failed ec=%lu (continuing)", GetLastError());
        env = nullptr;
    }

    // Ensure dirs exist
    CreateDirectoryW(L"C:\\PAM", nullptr);
    CreateDirectoryW(L"C:\\PAM\\logs", nullptr);

    // Build command line: "<exe>" + args
    wchar_t cmd[1024];
    StringCchPrintfW(cmd, _countof(cmd), L"\"%s\"%s", kChExe, kArgs);

    STARTUPINFOW si{}; si.cb = sizeof(si);
    si.lpDesktop = const_cast<LPWSTR>(L"winsta0\\default"); // important: interactive desktop
    PROCESS_INFORMATION pi{};

    // CREATE_NO_WINDOW to avoid a console popping in the user session.
    DWORD flags = CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW;

    BOOL ok = CreateProcessAsUserW(
        hPrimary,
        nullptr,            // application (use from command line)
        cmd,               // command line
        nullptr, nullptr, FALSE,
        flags,
        env,
        kWorkDir,          // working dir
        &si, &pi
    );

    if (!ok) {
        LogLine(L"CreateProcessAsUserW failed ec=%lu (cmd=%s)", GetLastError(), cmd);
        if (env) DestroyEnvironmentBlock(env);
        CloseHandle(hPrimary);
        CloseHandle(hUserToken);
        return nullptr;
    }

    if (env) DestroyEnvironmentBlock(env);
    CloseHandle(hPrimary);
    CloseHandle(hUserToken);

    CloseHandle(pi.hThread);
    LogLine(L"Launched Rust CH in session %u, pid=%u", sessionId, (unsigned)pi.dwProcessId);
    return pi.hProcess; // caller owns
}

// ------------- worker thread -------------
static DWORD WINAPI Worker(LPVOID)
{
    // main supervise loop
    for (;;) {
        // stop requested?
        if (WaitForSingleObject(gStopEvent, 0) == WAIT_OBJECT_0) break;

        // if child not running, start it in current active RDP session
        if (!gChildProc) {
            DWORD sid = FindActiveRdpSessionWithWait(10000, 1000);
            if (sid == (DWORD)-1) {
                Sleep(1500);
                continue;
            }
            gChildProc = LaunchRustInSession(sid);
            if (!gChildProc) {
                Sleep(2000);
                continue;
            }
        }

        // Wait either stop or child exit
        HANDLE hs[2] = { gStopEvent, gChildProc };
        DWORD wr = WaitForMultipleObjects(2, hs, FALSE, 1000);
        if (wr == WAIT_OBJECT_0) { // stop
            break;
        }
        if (wr == WAIT_OBJECT_0 + 1) { // child exited
            DWORD ec = 0; GetExitCodeProcess(gChildProc, &ec);
            LogLine(L"Rust CH exited (code=%lu). Will restart.", ec);
            CloseHandle(gChildProc);
            gChildProc = nullptr;
            Sleep(1500);
        }
        // else timeout: loop
    }

    // cleanup child on stop
    if (gChildProc) {
        // Be gentle; Rust CH will exit when service stops soon anyway.
        TerminateProcess(gChildProc, 0);
        CloseHandle(gChildProc);
        gChildProc = nullptr;
    }
    LogLine(L"Worker exit");
    return 0;
}

// ------------- SCM plumbing --------------
static void WINAPI CtrlHandler(DWORD ctrl)
{
    if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
        LogLine(L"Service stop requested");
        SetState(SERVICE_STOP_PENDING, NO_ERROR, 3000);
        if (gStopEvent) SetEvent(gStopEvent);
    }
}

static void WINAPI SvcMain(DWORD, LPWSTR*)
{
    gSsh = RegisterServiceCtrlHandlerW(kSvcName, CtrlHandler);
    if (!gSsh) return;

    SetState(SERVICE_START_PENDING, NO_ERROR, 4000);

    gStopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE th = CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);

    SetState(SERVICE_RUNNING);

    WaitForSingleObject(th, INFINITE);
    CloseHandle(th);
    if (gStopEvent) { CloseHandle(gStopEvent); gStopEvent = nullptr; }

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
