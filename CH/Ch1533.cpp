// QCM-CH.cpp  — Service wrapper that starts the Rust CH in the *active RDP session*
// Build: x64, Unicode. Link: Advapi32.lib; Wtsapi32.lib; Userenv.lib; Kernel32.lib
// Place the Rust exe at C:\PAM\qcm_autologin_service.exe (adjust kChildExe if needed).

#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <tlhelp32.h>
#include <strsafe.h>
#include <string>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")
#pragma comment(lib, "Kernel32.lib")

// ------------------------------- Service identity ---------------------------------
static const wchar_t* kSvcName  = L"QCMCH";
static const wchar_t* kSvcDisp  = L"QCM Chrome AutoLogin Service";

// ------------------------------- Paths & args -------------------------------------
static const wchar_t* kChildExe = L"C:\\PAM\\qcm_autologin_service.exe";
static const wchar_t* kChildArgsFmt = L"\"%s\" --port 10443 --log-dir C:\\PAM\\logs";

// ------------------------------- Globals ------------------------------------------
static SERVICE_STATUS_HANDLE gSsh = nullptr;
static SERVICE_STATUS        gSs  = {};
static HANDLE                gStopEvt = nullptr;
static HANDLE                gChildProc = nullptr;

// ------------------------------- Tiny file logger ---------------------------------
static void LogF(PCWSTR fmt, ...)
{
    CreateDirectoryW(L"C:\\PAM", nullptr);
    wchar_t line[2048];

    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t ts[64];
    StringCchPrintfW(ts, 64, L"%04u-%02u-%02u %02u:%02u:%02u",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

    va_list ap; va_start(ap, fmt);
    wchar_t msg[1600];
    StringCchVPrintfW(msg, 1600, fmt, ap);
    va_end(ap);

    wchar_t out[2000];
    StringCchPrintfW(out, 2000, L"%s [CH-WRAPPER] %s\r\n", ts, msg);

    HANDLE f = CreateFileW(L"C:\\PAM\\ch_wrapper.log", FILE_APPEND_DATA, FILE_SHARE_READ,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f != INVALID_HANDLE_VALUE) {
        DWORD cb = (DWORD)(lstrlenW(out) * sizeof(wchar_t));
        WriteFile(f, out, cb, &cb, nullptr);
        CloseHandle(f);
    }
}

// ------------------------------- Service helpers ----------------------------------
static void SetState(DWORD s, DWORD ec = NO_ERROR, DWORD waitMs = 0)
{
    gSs.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    gSs.dwCurrentState = s;
    gSs.dwWin32ExitCode = ec;
    gSs.dwControlsAccepted = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    gSs.dwWaitHint = waitMs;
    SetServiceStatus(gSsh, &gSs);
}

static void KillChild()
{
    if (!gChildProc) return;
    LogF(L"Stopping child...");
    TerminateProcess(gChildProc, 0);
    WaitForSingleObject(gChildProc, 4000);
    CloseHandle(gChildProc);
    gChildProc = nullptr;
}

// ------------------------ RDP session discovery / readiness -----------------------

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

// CHANGES: wait until the shell exists in the target session.
// We detect readiness by seeing "explorer.exe" running *in that session*.
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

// -------------------------- Token & process creation ------------------------------

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

    // CHANGES: wait for real desktop before launch
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
        // CHANGES: no console popup from Rust child:
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

// -------------------------------- Worker loop -------------------------------------

static DWORD WINAPI Worker(LPVOID)
{
    LogF(L"Service worker start");
    CreateDirectoryW(L"C:\\PAM\\logs", nullptr);

    for (;;) {
        if (WaitForSingleObject(gStopEvt, 0) == WAIT_OBJECT_0) break;

        int sid = FindActiveRdpSession();
        if (sid > 0) {
            // If we already have a child, check if it died
            if (gChildProc) {
                if (WaitForSingleObject(gChildProc, 0) == WAIT_OBJECT_0) {
                    DWORD ec = 0; GetExitCodeProcess(gChildProc, &ec);
                    LogF(L"Rust CH exited (code=%lu). Restarting when session active.", ec);
                    CloseHandle(gChildProc);
                    gChildProc = nullptr;
                }
            }
            // If no child, launch one into this active session
            if (!gChildProc) {
                gChildProc = LaunchInSession((DWORD)sid);
            }
        } else {
            // No active RDP session: make sure the child is not running
            if (gChildProc) {
                LogF(L"No active RDP session; stopping child");
                KillChild();
            }
        }

        if (WaitForSingleObject(gStopEvt, 1200) == WAIT_OBJECT_0) break;
    }

    KillChild();
    LogF(L"Worker exit");
    return 0;
}

// -------------------------------- SCM plumbing ------------------------------------

static void WINAPI CtrlHandler(DWORD code)
{
    if (code == SERVICE_CONTROL_STOP || code == SERVICE_CONTROL_SHUTDOWN) {
        SetState(SERVICE_STOP_PENDING, NO_ERROR, 3000);
        SetEvent(gStopEvt);
    }
}

static void WINAPI SvcMain(DWORD, LPWSTR*)
{
    gSsh = RegisterServiceCtrlHandlerW(kSvcName, CtrlHandler);
    if (!gSsh) return;

    SetState(SERVICE_START_PENDING, NO_ERROR, 3000);
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
