// QCM-CH.cpp — Windows service wrapper that launches Rust CH in the active RDP user session
// Build: x64, Unicode. Link: Advapi32.lib; Wtsapi32.lib; Userenv.lib; Kernel32.lib

#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <strsafe.h>
#include <tlhelp32.h>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")
#pragma comment(lib, "Kernel32.lib")

// ---------------- service identity ----------------
static const wchar_t* kSvcName = L"QCMCH";
static const wchar_t* kSvcDisp = L"QCM Chrome AutoLogin Service";

// ---------------- globals ----------------
static SERVICE_STATUS_HANDLE gSsh = nullptr;
static SERVICE_STATUS        gSs  = {};
static HANDLE                gStopEvt = nullptr;
static HANDLE                gChild   = nullptr;

// ---------------- tiny logger ----------------
static void LogF(const wchar_t* fmt, ...)
{
    CreateDirectoryW(L"C:\\PAM", nullptr);
    wchar_t buf[1024];
    va_list ap; va_start(ap, fmt);
    StringCchVPrintfW(buf, 1024, fmt, ap);
    va_end(ap);

    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t line[1400];
    StringCchPrintfW(line, 1400, L"%04u-%02u-%02u %02u:%02u:%02u [CH-WRAPPER] %s\r\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, buf);

    HANDLE f = CreateFileW(L"C:\\PAM\\ch_wrapper.log", FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f != INVALID_HANDLE_VALUE) {
        DWORD cb = (DWORD)(lstrlenW(line) * sizeof(wchar_t));
        WriteFile(f, line, cb, &cb, nullptr);
        CloseHandle(f);
    }
}

// ---------------- service state helper ----------------
static void SetState(DWORD s, DWORD waitHintMs = 0, DWORD win32 = NO_ERROR)
{
    gSs.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    gSs.dwCurrentState = s;
    gSs.dwWin32ExitCode = win32;
    gSs.dwControlsAccepted = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    gSs.dwWaitHint = waitHintMs;
    SetServiceStatus(gSsh, &gSs);
}

// ---------------- session discovery ----------------
static DWORD FindActiveRdpSession()
{
    PWTS_SESSION_INFO p = nullptr; DWORD count = 0;
    if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &p, &count))
        return (DWORD)-1;

    DWORD sid = (DWORD)-1;
    for (DWORD i = 0; i < count; ++i) {
        if (p[i].State == WTSActive && p[i].SessionId != 0 /*not services*/) {
            sid = p[i].SessionId;
            break;
        }
    }
    if (p) WTSFreeMemory(p);
    return sid;
}

static bool QuerySessionUser(DWORD sid, std::wstring& user, std::wstring& domain)
{
    user.clear(); domain.clear();
    DWORD bytes = 0; LPWSTR pUser = nullptr, pDom = nullptr;
    if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSUserName, &pUser, &bytes) && pUser) {
        user = pUser; WTSFreeMemory(pUser);
    }
    if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSDomainName, &pDom, &bytes) && pDom) {
        domain = pDom; WTSFreeMemory(pDom);
    }
    return !user.empty();
}

// Wait until user desktop is really ready: explorer.exe present in this session
static bool WaitForUserDesktopReady(DWORD sid, DWORD maxWaitMs)
{
    const DWORD step = 1000;
    DWORD waited = 0;
    for (;;) {
        // enumerate processes and look for explorer.exe with matching session
        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snap != INVALID_HANDLE_VALUE) {
            PROCESSENTRY32 pe{}; pe.dwSize = sizeof(pe);
            if (Process32First(snap, &pe)) {
                do {
                    if (_wcsicmp(pe.szExeFile, L"explorer.exe") == 0) {
                        DWORD psid = 0;
                        if (ProcessIdToSessionId(pe.th32ProcessID, &psid) && psid == sid) {
                            CloseHandle(snap);
                            LogF(L"Desktop readiness: explorer.exe detected in session %u", sid);
                            return true;
                        }
                    }
                } while (Process32Next(snap, &pe));
            }
            CloseHandle(snap);
        }
        if (waited >= maxWaitMs) return false;
        if (WaitForSingleObject(gStopEvt, step) == WAIT_OBJECT_0) return false;
        waited += step;
    }
}

// ---------------- launching in a session ----------------
static HANDLE LaunchChildInSession(DWORD sid)
{
    HANDLE userTok = nullptr;
    if (!WTSQueryUserToken(sid, &userTok)) {
        LogF(L"WTSQueryUserToken failed ec=%lu sid=%u", GetLastError(), sid);
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

    // Load user profile of the actual session user
    std::wstring user, dom; QuerySessionUser(sid, user, dom);
    PROFILEINFOW pi{}; pi.dwSize = sizeof(pi);
    pi.lpUserName = user.empty() ? nullptr : const_cast<LPWSTR>(user.c_str());
    HANDLE hProfile = nullptr;
    if (!LoadUserProfileW(primaryTok, &pi)) {
        LogF(L"LoadUserProfileW failed ec=%lu (continuing)", GetLastError());
    } else {
        hProfile = pi.hProfile;
    }

    // Create environment for that user
    LPVOID env = nullptr;
    if (!CreateEnvironmentBlock(&env, primaryTok, FALSE)) {
        LogF(L"CreateEnvironmentBlock failed ec=%lu (continuing without env)", GetLastError());
        env = nullptr;
    }

    // Command to start Rust CH
    CreateDirectoryW(L"C:\\PAM\\logs", nullptr);
    const wchar_t* exe = L"C:\\PAM\\qcm_autologin_service.exe";
    wchar_t cmd[1024];
    StringCchPrintfW(cmd, 1024, L"\"%s\" --port 10443 --log-dir C:\\PAM\\logs", exe);

    STARTUPINFOW si{}; si.cb = sizeof(si);
    si.lpDesktop = const_cast<LPWSTR>(L"winsta0\\default");
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_SHOWNORMAL; // keep visible while stabilizing

    PROCESS_INFORMATION piProc{};
    BOOL ok = CreateProcessAsUserW(
        primaryTok,
        exe,           // application
        cmd,           // command line
        nullptr, nullptr, FALSE,
        CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_PROCESS_GROUP,
        env,
        L"C:\\PAM",
        &si, &piProc);

    if (env) DestroyEnvironmentBlock(env);
    if (hProfile) UnloadUserProfile(primaryTok, hProfile);
    CloseHandle(primaryTok);

    if (!ok) {
        LogF(L"CreateProcessAsUserW failed ec=%lu sid=%u", GetLastError(), sid);
        return nullptr;
    }

    CloseHandle(piProc.hThread);
    LogF(L"Launched Rust CH in session %u, pid %lu", sid, piProc.dwProcessId);
    return piProc.hProcess;
}

static void StopChild()
{
    if (!gChild) return;
    LogF(L"Stopping child...");
    TerminateProcess(gChild, 0);
    WaitForSingleObject(gChild, 4000);
    CloseHandle(gChild);
    gChild = nullptr;
}

// ---------------- worker loop ----------------
static DWORD WINAPI Worker(LPVOID)
{
    LogF(L"Service worker start");

    DWORD currentSid = (DWORD)-1;

    for (;;) {
        if (WaitForSingleObject(gStopEvt, 0) == WAIT_OBJECT_0) break;

        DWORD sid = FindActiveRdpSession();
        if (sid != (DWORD)-1) {
            // new or changed session
            if (sid != currentSid) {
                if (gChild) { StopChild(); }
                currentSid = sid;

                // wait until user desktop is really ready
                if (!WaitForUserDesktopReady(sid, 60000)) {
                    LogF(L"Desktop not ready in session %u within timeout; will retry", sid);
                } else {
                    gChild = LaunchChildInSession(sid);
                }
            } else {
                // same session: if child died, relaunch
                if (gChild && WaitForSingleObject(gChild, 0) == WAIT_OBJECT_0) {
                    DWORD ec = 0; GetExitCodeProcess(gChild, &ec);
                    LogF(L"Rust CH exited (code=%lu). Restarting when session active.", ec);
                    CloseHandle(gChild); gChild = nullptr;

                    if (WaitForUserDesktopReady(sid, 60000))
                        gChild = LaunchChildInSession(sid);
                }
            }
        } else {
            // no active RDP session
            if (gChild) {
                LogF(L"No active RDP session; stopping child");
                StopChild();
            }
            currentSid = (DWORD)-1;
        }

        if (WaitForSingleObject(gStopEvt, 1500) == WAIT_OBJECT_0) break;
    }

    StopChild();
    LogF(L"Worker exit");
    return 0;
}

// ---------------- SCM plumbing ----------------
static void WINAPI CtrlHandler(DWORD code)
{
    if (code == SERVICE_CONTROL_STOP || code == SERVICE_CONTROL_SHUTDOWN) {
        SetState(SERVICE_STOP_PENDING, 4000);
        SetEvent(gStopEvt);
    }
}

static void WINAPI SvcMain(DWORD, LPWSTR*)
{
    gSsh = RegisterServiceCtrlHandlerW(kSvcName, CtrlHandler);
    if (!gSsh) return;

    SetState(SERVICE_START_PENDING, 4000);

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
        { (LPWSTR)kSvcName, SvcMain },
        { nullptr, nullptr }
    };
    StartServiceCtrlDispatcherW(ste);
    return 0;
}
