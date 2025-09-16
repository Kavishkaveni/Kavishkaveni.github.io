// QCM-CH.cpp  — Windows Service wrapper for Rust CH (qcm_autologin_service.exe)
// Build: Release x64, Unicode. Linker -> Additional Dependencies:
// Advapi32.lib; Wtsapi32.lib; Userenv.lib

#define UNICODE
#define _UNICODE
#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <tlhelp32.h>
#include <strsafe.h>
#include <stdio.h>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")

// ---------- service identity ----------
static const wchar_t* kSvcName  = L"QCMCH";
static const wchar_t* kSvcDisp  = L"QCM Chrome AutoLogin Service";

// ---------- paths / args ----------
static const wchar_t* kRustExe  = L"C:\\PAM\\qcm_autologin_service.exe";
static const wchar_t* kWorkDir  = L"C:\\PAM";
static const wchar_t* kArgs     = L" --port 10443 --log-dir C:\\PAM\\logs";

// ---------- globals ----------
static SERVICE_STATUS_HANDLE gSsh = nullptr;
static SERVICE_STATUS        gSs  = {};
static HANDLE                gStopEvent = nullptr;
static HANDLE                gChildProc = nullptr;
static DWORD                 gChildPid  = 0;
static DWORD                 gChildSess = 0xFFFFFFFF;

static CRITICAL_SECTION      gLogCs;

// ---------- tiny logger ----------
static void Logf(const wchar_t* fmt, ...)
{
    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t line[2048];

    va_list ap; va_start(ap, fmt);
    wchar_t body[1600];
    StringCchVPrintfW(body, _countof(body), fmt, ap);
    va_end(ap);

    StringCchPrintfW(line, _countof(line),
        L"%04u-%02u-%02u %02u:%02u:%02u [%s] %s\r\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
        L"CH-WRAPPER", body);

    EnterCriticalSection(&gLogCs);
    CreateDirectoryW(L"C:\\PAM", nullptr);
    HANDLE h = CreateFileW(L"C:\\PAM\\ch_wrapper.log",
                           FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h != INVALID_HANDLE_VALUE) {
        DWORD cb = (DWORD)(wcslen(line) * sizeof(wchar_t));
        WriteFile(h, line, cb, &cb, nullptr);
        CloseHandle(h);
    }
    LeaveCriticalSection(&gLogCs);
}

// ---------- helpers ----------
static void SetState(DWORD s, DWORD win32 = NO_ERROR, DWORD waitHintMs = 0)
{
    gSs.dwServiceType             = SERVICE_WIN32_OWN_PROCESS;
    gSs.dwCurrentState            = s;
    gSs.dwWin32ExitCode           = win32;
    gSs.dwWaitHint                = waitHintMs;
    gSs.dwControlsAccepted        = (s == SERVICE_START_PENDING) ? 0 :
                                    (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    SetServiceStatus(gSsh, &gSs);
}

static bool EnablePrivilege(LPCWSTR name)
{
    HANDLE h;
    if (!OpenProcessToken(GetCurrentProcess(),
                          TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &h)) return false;

    TOKEN_PRIVILEGES tp{};
    LUID luid{};
    bool ok = false;
    if (LookupPrivilegeValueW(nullptr, name, &luid)) {
        tp.PrivilegeCount = 1;
        tp.Privileges[0].Luid = luid;
        tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
        ok = AdjustTokenPrivileges(h, FALSE, &tp, sizeof(tp), nullptr, nullptr);
    }
    CloseHandle(h);
    return ok;
}

static void KillProcessTree(HANDLE hProcess)
{
    if (!hProcess) return;

    DWORD pid = 0;
    GetProcessId(hProcess) ? (pid = GetProcessId(hProcess)) : 0;
    if (!pid) return;

    // Kill children first
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

    TerminateProcess(hProcess, 0);
}

static DWORD FindActiveRdpSession()
{
    PWTS_SESSION_INFOW p = nullptr; DWORD count = 0;
    DWORD sid = 0xFFFFFFFF;

    if (WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &p, &count)) {
        for (DWORD i = 0; i < count; ++i) {
            // Prefer RDP sessions (WinStation like "RDP-Tcp#x") in Active state
            if (p[i].State == WTSActive && p[i].pWinStationName &&
                (wcsnicmp(p[i].pWinStationName, L"RDP-Tcp", 7) == 0))
            {
                sid = p[i].SessionId;
                break;
            }
        }
        WTSFreeMemory(p);
    }

    // If none, no active RDP
    return sid;
}

static bool GetPrimaryUserTokenForSession(DWORD sessionId, HANDLE& hOut)
{
    hOut = nullptr;

    HANDLE imp = nullptr;
    if (!WTSQueryUserToken(sessionId, &imp)) {
        Logf(L"WTSQueryUserToken failed ec=%lu (sid=%lu)", GetLastError(), sessionId);
        return false;
    }

    HANDLE pri = nullptr;
    BOOL ok = DuplicateTokenEx(imp,
                               TOKEN_ALL_ACCESS,
                               nullptr,
                               SecurityImpersonation,
                               TokenPrimary,
                               &pri);
    CloseHandle(imp);

    if (!ok) {
        Logf(L"DuplicateTokenEx failed ec=%lu (sid=%lu)", GetLastError(), sessionId);
        return false;
    }

    hOut = pri;
    return true;
}

static bool LoadUser(HANDLE hToken, LPVOID& pEnvOut)
{
    pEnvOut = nullptr;

    // Optional: load profile so Chrome picks correct dirs
    PROFILEINFOW pi{}; pi.dwSize = sizeof(pi);
    pi.lpUserName = L"RDPUser"; // name not required to be exact
    LoadUserProfileW(hToken, &pi); // ignore failure; not fatal

    if (!CreateEnvironmentBlock(&pEnvOut, hToken, FALSE)) {
        Logf(L"CreateEnvironmentBlock failed ec=%lu", GetLastError());
        pEnvOut = nullptr; // still try without env
    }
    return true;
}

static bool LaunchRustInSession(DWORD sessionId)
{
    // Ensure privileges once
    EnablePrivilege(SE_ASSIGNPRIMARYTOKEN_NAME);
    EnablePrivilege(SE_INCREASE_QUOTA_NAME);

    HANDLE hTok = nullptr;
    if (!GetPrimaryUserTokenForSession(sessionId, hTok))
        return false;

    LPVOID env = nullptr;
    LoadUser(hTok, env);

    // Build command line: "exe" + args (CreateProcessAsUser wants writable buffer)
    wchar_t cmd[1024];
    StringCchPrintfW(cmd, _countof(cmd), L"\"%s\"%s", kRustExe, kArgs);

    STARTUPINFOW si{}; si.cb = sizeof(si);
    si.lpDesktop   = const_cast<LPWSTR>(L"winsta0\\default");
    si.dwFlags     = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_SHOWNORMAL;

    PROCESS_INFORMATION pi{};
    DWORD flags = CREATE_UNICODE_ENVIRONMENT
                | CREATE_NEW_PROCESS_GROUP
                | DETACHED_PROCESS        // hide Rust console window
                | CREATE_NO_WINDOW;       // extra safety against console

    BOOL ok = CreateProcessAsUserW(
        hTok,
        kRustExe,        // lpApplicationName
        cmd,             // lpCommandLine (mutable)
        nullptr, nullptr,
        FALSE,
        flags,
        env,             // environment (may be null)
        kWorkDir,        // current dir
        &si, &pi);

    if (env) DestroyEnvironmentBlock(env);
    CloseHandle(hTok);

    if (!ok) {
        Logf(L"CreateProcessAsUser failed ec=%lu (sid=%lu)", GetLastError(), sessionId);
        return false;
    }

    if (gChildProc) { CloseHandle(gChildProc); gChildProc = nullptr; }
    gChildProc = pi.hProcess;
    CloseHandle(pi.hThread);

    gChildPid  = pi.dwProcessId;
    gChildSess = sessionId;

    Logf(L"Launched Rust CH in session %lu, PID %lu", sessionId, gChildPid);
    return true;
}

static void StopChild()
{
    if (!gChildProc) return;

    Logf(L"Stopping child (PID %lu)", gChildPid);
    KillProcessTree(gChildProc);
    CloseHandle(gChildProc);
    gChildProc = nullptr; gChildPid = 0; gChildSess = 0xFFFFFFFF;
}

// ---------- worker ----------
static DWORD WINAPI Worker(LPVOID)
{
    Logf(L"Service worker start");

    // Ensure directories exist
    CreateDirectoryW(L"C:\\PAM",      nullptr);
    CreateDirectoryW(L"C:\\PAM\\logs",nullptr);

    DWORD lastSession = 0xFFFFFFFF;

    while (WaitForSingleObject(gStopEvent, 1000) == WAIT_TIMEOUT) {
        // Did child exit?
        if (gChildProc) {
            DWORD wr = WaitForSingleObject(gChildProc, 0);
            if (wr == WAIT_OBJECT_0) {
                DWORD ec = 0; GetExitCodeProcess(gChildProc, &ec);
                Logf(L"Rust CH exited (code=%lu). Will restart when appropriate.", ec);
                CloseHandle(gChildProc); gChildProc = nullptr; gChildPid = 0;
                gChildSess = 0xFFFFFFFF;
            }
        }

        DWORD sid = FindActiveRdpSession();

        if (sid == 0xFFFFFFFF) {
            // No active RDP session; keep child down
            if (gChildProc) {
                Logf(L"No ACTIVE RDP session; stopping child");
                StopChild();
            }
            continue; // wait again
        }

        if (lastSession != sid) {
            Logf(L"Active RDP session found: %lu", sid);
            lastSession = sid;
        }

        // If child not running -> launch. If running but in another session -> restart.
        if (!gChildProc || gChildSess != sid) {
            if (gChildProc) StopChild();
            LaunchRustInSession(sid);
        }
    }

    // Stop requested
    StopChild();
    return 0;
}

// ---------- service plumbing ----------
static void WINAPI CtrlHandler(DWORD ctrl)
{
    if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
        SetState(SERVICE_STOP_PENDING, NO_ERROR, 3000);
        SetEvent(gStopEvent);
    }
}

static void WINAPI SvcMain(DWORD, LPWSTR*)
{
    InitializeCriticalSection(&gLogCs);

    gSsh = RegisterServiceCtrlHandlerW(kSvcName, CtrlHandler);
    if (!gSsh) return;

    SetState(SERVICE_START_PENDING, NO_ERROR, 4000);

    gStopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE th = CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);

    SetState(SERVICE_RUNNING);

    WaitForSingleObject(th, INFINITE);
    CloseHandle(th);
    CloseHandle(gStopEvent); gStopEvent = nullptr;

    SetState(SERVICE_STOPPED);
    DeleteCriticalSection(&gLogCs);
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
