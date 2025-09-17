// QCMCH.cpp - Windows Service wrapper that launches Rust CH in the active RDP session.
// Build: Release | x64, Unicode. Link: Advapi32.lib; Wtsapi32.lib; Userenv.lib

#define UNICODE
#define _UNICODE
#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <strsafe.h>
#include <tlhelp32.h>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")

// ----------------------------- Config ----------------------------------------
static const wchar_t* kSvcName   = L"QCM-CH";
static const wchar_t* kSvcDisp   = L"QCM Chrome AutoLogin Service";
static const wchar_t* kChildExe  = L"C:\\PAM\\qcm_autologin_service.exe";
static const wchar_t* kChildArgs = L" --port 10443 --log-dir C:\\PAM\\logs";
static const wchar_t* kWorkDir   = L"C:\\PAM";
static const DWORD    kWaitFindRdpMs = 15000;    // wait up to 15s for an active RDP session
static const DWORD    kPollMs        = 1000;     // poll every 1s

// ----------------------------- Globals ---------------------------------------
static SERVICE_STATUS_HANDLE gSsh = nullptr;
static SERVICE_STATUS        gSs  = {};
static HANDLE                gStopEvent = nullptr;
static HANDLE                gChildProc = nullptr;

// ----------------------------- Logging ---------------------------------------
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
        L"%04u-%02u-%02u %02u:%02u:%02u [CHWRAP] %s\r\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, line);

    HANDLE h = CreateFileW(L"C:\\PAM\\ch_wrapper.log", FILE_APPEND_DATA,
        FILE_SHARE_READ, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h != INVALID_HANDLE_VALUE) {
        DWORD cb = (DWORD)(lstrlenW(msg) * sizeof(wchar_t));
        WriteFile(h, msg, cb, &cb, nullptr);
        CloseHandle(h);
    }
}

static void SetState(DWORD s, DWORD win32 = NO_ERROR, DWORD waitHintMs = 0)
{
    gSs.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    gSs.dwCurrentState = s;
    gSs.dwWin32ExitCode = win32;
    gSs.dwControlsAccepted = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    gSs.dwWaitHint = waitHintMs;
    SetServiceStatus(gSsh, &gSs);
}

// ----------------------- RDP Session Discovery -------------------------------
static std::wstring ClientAddrToString(PWTS_CLIENT_ADDRESS addr)
{
    if (!addr) return L"";
    if (addr->AddressFamily == AF_INET) {
        const unsigned char* a = (const unsigned char*)addr->Address;
        wchar_t buf[64];
        // bytes 2..5 hold IPv4
        StringCchPrintfW(buf, _countof(buf), L"%u.%u.%u.%u",
            (unsigned)a[2], (unsigned)a[3], (unsigned)a[4], (unsigned)a[5]);
        return std::wstring(buf);
    }
    return L"";
}

static DWORD FindActiveRdpSessionWithWait(DWORD maxWaitMs, DWORD pollMs, std::wstring& outUser, std::wstring& outIp)
{
    DWORD waited = 0;
    for (;;) {
        PWTS_SESSION_INFO pInfo = nullptr;
        DWORD count = 0;
        if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &pInfo, &count)) {
            LogF(L"WTSEnumerateSessionsW failed ec=%lu", GetLastError());
            return (DWORD)-1;
        }

        DWORD foundSid = (DWORD)-1;
        for (DWORD i = 0; i < count; ++i) {
            DWORD sid = pInfo[i].SessionId;

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
                user = pUser; WTSFreeMemory(pUser);
            }

            LPWSTR pProto = nullptr;
            int proto = 0;
            if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSClientProtocolType, (LPWSTR*)&pProto, &bytes) && pProto) {
                proto = *(USHORT*)pProto; // 2 = RDP
                WTSFreeMemory(pProto);
            }

            PWTS_CLIENT_ADDRESS pAddr = nullptr;
            std::wstring ip;
            if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSClientAddress, (LPWSTR*)&pAddr, &bytes) && pAddr) {
                ip = ClientAddrToString(pAddr);
                WTSFreeMemory(pAddr);
            }

            LogF(L"Inventory: sid=%u state=%d proto=%d user=%s ip=%s",
                 sid, (int)state, proto, user.c_str(), ip.c_str());

            if (state == WTSActive && proto == 2) {
                foundSid = sid;
                outUser = user;
                outIp = ip;
                break;
            }
        }

        WTSFreeMemory(pInfo);

        if (foundSid != (DWORD)-1) {
            LogF(L"Active RDP session found: sid=%u user=%s ip=%s", foundSid, outUser.c_str(), outIp.c_str());
            return foundSid;
        }

        if (waited >= maxWaitMs) {
            LogF(L"No ACTIVE RDP session found after waiting.");
            return (DWORD)-1;
        }
        Sleep(pollMs);
        waited += pollMs;
    }
}

// ----------------------- Launch in User Session ------------------------------
static BOOL LaunchInUserSession(DWORD sessionId, HANDLE& outProc)
{
    outProc = nullptr;

    HANDLE hUserToken = nullptr;
    if (!WTSQueryUserToken(sessionId, &hUserToken)) {
        LogF(L"WTSQueryUserToken(sid=%u) failed ec=%lu", sessionId, GetLastError());
        return FALSE;
    }

    HANDLE hPrimary = nullptr;
    if (!DuplicateTokenEx(hUserToken, MAXIMUM_ALLOWED, nullptr, SecurityIdentification, TokenPrimary, &hPrimary)) {
        LogF(L"DuplicateTokenEx failed ec=%lu", GetLastError());
        CloseHandle(hUserToken);
        return FALSE;
    }
    CloseHandle(hUserToken);

    LPVOID env = nullptr;
    if (!CreateEnvironmentBlock(&env, hPrimary, FALSE)) {
        LogF(L"CreateEnvironmentBlock failed ec=%lu (continuing without env)", GetLastError());
        env = nullptr;
    }

    // Prepare command line: "exe" + args
    wchar_t cmd[1024];
    StringCchPrintfW(cmd, _countof(cmd), L"\"%s\"%s", kChildExe, kChildArgs);

    STARTUPINFOW si{}; si.cb = sizeof(si);
    si.lpDesktop = const_cast<LPWSTR>(L"winsta0\\default"); // bind to interactive desktop
    PROCESS_INFORMATION pi{};

    BOOL ok = CreateProcessAsUserW(
        hPrimary,
        kChildExe,         // application
        cmd,               // command line
        nullptr, nullptr,
        FALSE,
        CREATE_UNICODE_ENVIRONMENT,
        env,
        kWorkDir,
        &si,
        &pi);

    if (!ok) {
        LogF(L"CreateProcessAsUserW failed ec=%lu (sid=%u)", GetLastError(), sessionId);
        if (env) DestroyEnvironmentBlock(env);
        CloseHandle(hPrimary);
        return FALSE;
    }

    if (env) DestroyEnvironmentBlock(env);
    CloseHandle(hPrimary);

    CloseHandle(pi.hThread);
    outProc = pi.hProcess;

    DWORD pid = GetProcessId(outProc);
    LogF(L"Launched Rust CH in session %u, PID=%lu", sessionId, (unsigned long)pid);
    return TRUE;
}

// ----------------------- Service Worker -------------------------------------
static DWORD WINAPI Worker(LPVOID)
{
    CreateDirectoryW(L"C:\\PAM", nullptr);
    CreateDirectoryW(L"C:\\PAM\\logs", nullptr);

    for (;;) {
        if (WaitForSingleObject(gStopEvent, 0) == WAIT_OBJECT_0) break;

        // If child is not running, try to start it in active RDP session
        if (!gChildProc) {
            std::wstring user, ip;
            DWORD sid = FindActiveRdpSessionWithWait(kWaitFindRdpMs, kPollMs, user, ip);
            if (sid == (DWORD)-1) {
                LogF(L"No active RDP session; sleeping...");
                Sleep(2000);
                continue;
            }

            HANDLE hProc = nullptr;
            if (LaunchInUserSession(sid, hProc)) {
                gChildProc = hProc;
            } else {
                LogF(L"LaunchInUserSession failed; will retry.");
                Sleep(2000);
                continue;
            }
        }

        // Wait either for stop or child exit
        HANDLE waits[2] = { gStopEvent, gChildProc };
        DWORD wr = WaitForMultipleObjects(2, waits, FALSE, 1000);
        if (wr == WAIT_OBJECT_0) {
            // stop requested
            if (gChildProc) {
                TerminateProcess(gChildProc, 0);
                CloseHandle(gChildProc); gChildProc = nullptr;
            }
            break;
        } else if (wr == WAIT_OBJECT_0 + 1) {
            // child exited; restart loop
            DWORD code = 0; GetExitCodeProcess(gChildProc, &code);
            LogF(L"Rust CH process exited (code=%lu). Will attempt restart.", code);
            CloseHandle(gChildProc); gChildProc = nullptr;
            Sleep(1500);
        }
        // else timeout -> loop
    }

    if (gChildProc) {
        TerminateProcess(gChildProc, 0);
        CloseHandle(gChildProc); gChildProc = nullptr;
    }
    LogF(L"Service worker exit");
    return 0;
}

// ----------------------- SCM Plumbing ---------------------------------------
static void WINAPI CtrlHandler(DWORD ctrl)
{
    if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
        LogF(L"Service stop requested");
        SetEvent(gStopEvent);
        SetState(SERVICE_STOP_PENDING, NO_ERROR, 4000);
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
    LogF(L"Service %s running", kSvcName);

    WaitForSingleObject(th, INFINITE);
    CloseHandle(th);
    CloseHandle(gStopEvent); gStopEvent = nullptr;

    SetState(SERVICE_STOPPED);
    LogF(L"Service %s stopped", kSvcName);
}

// ----------------------- Entry Point (SUBSYSTEM:WINDOWS) ---------------------
int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int)
{
    SERVICE_TABLE_ENTRYW ste[] = {
        { (LPWSTR)kSvcName, SvcMain },
        { nullptr, nullptr }
    };
    if (!StartServiceCtrlDispatcherW(ste)) {
        // If run by accident from desktop, log and exit.
        LogF(L"StartServiceCtrlDispatcherW failed ec=%lu (are you starting as a service?)", GetLastError());
    }
    return 0;
}
