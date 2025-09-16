// Minimal Windows service wrapper that runs C:\PAM\ch.exe as a child process.
// Build: Release x64. Link with Advapi32.lib, Shell32.lib, Userenv.lib.
// VS: Project Properties -> C/C++ -> Language -> Treat wchar_t as Built-in: Yes

#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <userenv.h>
#include <shellapi.h>
#include <strsafe.h>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Shell32.lib")
#pragma comment(lib, "Userenv.lib")

// ---------- service config ----------
static const wchar_t* kSvcName   = L"QCMCH";
static const wchar_t* kSvcDisp   = L"QCM Chrome Auto-Login (CH)";
static const wchar_t* kLogPath   = L"C:\\PAM\\logs\\ch_svc.log";
static const wchar_t* kChExe     = L"C:\\PAM\\ch.exe";
static const wchar_t* kChArgs    = L" --port 10443 --log-dir C:\\PAM\\logs --chrome-port 9222";
// -----------------------------------

static SERVICE_STATUS_HANDLE g_ssHandle = nullptr;
static SERVICE_STATUS        g_status   {};
static HANDLE                g_stopEvt  = nullptr;
static HANDLE                g_child    = nullptr;

static void LogF(const wchar_t* fmt, ...)
{
    CreateDirectoryW(L"C:\\PAM", nullptr);
    CreateDirectoryW(L"C:\\PAM\\logs", nullptr);

    wchar_t line[2048];
    va_list ap; va_start(ap, fmt);
    StringCchVPrintfW(line, _countof(line), fmt, ap);
    va_end(ap);

    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t msg[2300];
    StringCchPrintfW(msg, _countof(msg),
        L"%04u-%02u-%02u %02u:%02u:%02u [CH-SVC] %s\r\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, line);

    HANDLE h = CreateFileW(kLogPath, FILE_APPEND_DATA, FILE_SHARE_READ,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h != INVALID_HANDLE_VALUE) { DWORD cb; WriteFile(h, msg, (DWORD)(lstrlenW(msg) * 2), &cb, nullptr); CloseHandle(h); }
}

static void SetState(DWORD s, DWORD win32 = NO_ERROR, DWORD waitHintMs = 0)
{
    g_status.dwServiceType             = SERVICE_WIN32_OWN_PROCESS;
    g_status.dwCurrentState            = s;
    g_status.dwWin32ExitCode           = win32;
    g_status.dwWaitHint                = waitHintMs;
    g_status.dwControlsAccepted        = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    SetServiceStatus(g_ssHandle, &g_status);
}

static DWORD LaunchChild()
{
    wchar_t cmd[1024];
    StringCchPrintfW(cmd, _countof(cmd), L"\"%s\"%s", kChExe, kChArgs);

    STARTUPINFOW si{}; si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    BOOL ok = CreateProcessW(
        kChExe,          // application
        cmd,             // command line (mutable)
        nullptr, nullptr, FALSE,
        CREATE_NEW_CONSOLE, // give it its own console (easier to see)
        nullptr, nullptr,
        &si, &pi);

    if (!ok) {
        DWORD ec = GetLastError();
        LogF(L"CreateProcess failed ec=%lu cmd=%s", ec, cmd);
        return ec;
    }

    LogF(L"Started ch.exe pid=%lu cmd=%s", pi.dwProcessId, cmd);
    g_child = pi.hProcess;
    CloseHandle(pi.hThread);
    return 0;
}

static DWORD WINAPI Worker(LPVOID)
{
    // loop: keep ch.exe alive until stop event is signaled
    for (;;) {
        // start child if not running
        if (!g_child) {
            DWORD ec = LaunchChild();
            if (ec != 0) {
                // backoff a bit to avoid tight loop if ch.exe missing
                if (WaitForSingleObject(g_stopEvt, 5000) == WAIT_OBJECT_0) break;
                continue;
            }
        }

        HANDLE waitOn[2] = { g_stopEvt, g_child };
        DWORD wr = WaitForMultipleObjects(2, waitOn, FALSE, INFINITE);
        if (wr == WAIT_OBJECT_0) {
            // stop requested
            LogF(L"Stop requested");
            if (g_child) {
                TerminateProcess(g_child, 0);
                CloseHandle(g_child); g_child = nullptr;
            }
            break;
        } else if (wr == WAIT_OBJECT_0 + 1) {
            // child exited; restart after short delay
            DWORD exitCode = 0; GetExitCodeProcess(g_child, &exitCode);
            LogF(L"ch.exe exited code=%lu; restarting in 3s", exitCode);
            CloseHandle(g_child); g_child = nullptr;
            if (WaitForSingleObject(g_stopEvt, 3000) == WAIT_OBJECT_0) break;
        } else {
            LogF(L"Wait error %lu", GetLastError());
            break;
        }
    }
    LogF(L"Worker exit");
    return 0;
}

static void WINAPI CtrlHandler(DWORD ctrl)
{
    if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
        LogF(L"Ctrl: stop/shutdown");
        SetState(SERVICE_STOP_PENDING, NO_ERROR, 5000);
        if (g_stopEvt) SetEvent(g_stopEvt);
    }
}

static void WINAPI SvcMain(DWORD, LPWSTR*)
{
    g_ssHandle = RegisterServiceCtrlHandlerW(kSvcName, CtrlHandler);
    if (!g_ssHandle) return;

    SetState(SERVICE_START_PENDING, NO_ERROR, 5000);
    g_stopEvt = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!g_stopEvt) { SetState(SERVICE_STOPPED, GetLastError(), 0); return; }

    HANDLE th = CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);
    if (!th) { SetState(SERVICE_STOPPED, GetLastError(), 0); return; }

    SetState(SERVICE_RUNNING, NO_ERROR, 0);
    WaitForSingleObject(th, INFINITE);
    CloseHandle(th);
    if (g_stopEvt) CloseHandle(g_stopEvt);
    SetState(SERVICE_STOPPED, NO_ERROR, 0);
}

// ------- self-install / uninstall helpers (so you don’t need sc.exe) --------
static bool InstallService()
{
    wchar_t path[MAX_PATH];
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring bin = L"\""; bin += path; bin += L"\" --service";

    SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CREATE_SERVICE);
    if (!scm) { LogF(L"OpenSCManager failed %lu", GetLastError()); return false; }

    SC_HANDLE svc = CreateServiceW(
        scm, kSvcName, kSvcDisp,
        SERVICE_ALL_ACCESS,
        SERVICE_WIN32_OWN_PROCESS,
        SERVICE_AUTO_START,
        SERVICE_ERROR_NORMAL,
        bin.c_str(),
        nullptr, nullptr, nullptr, nullptr, nullptr);

    if (!svc) {
        LogF(L"CreateService failed %lu", GetLastError());
        CloseServiceHandle(scm);
        return false;
    }
    LogF(L"Service installed. BinPath: %s", bin.c_str());

    BOOL ok = StartServiceW(svc, 0, nullptr);
    if (!ok) LogF(L"StartService failed %lu", GetLastError());
    else     LogF(L"Service start requested");

    CloseServiceHandle(svc);
    CloseServiceHandle(scm);
    return true;
}

static void UninstallService()
{
    SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
    if (!scm) { LogF(L"OpenSCManager failed %lu", GetLastError()); return; }

    SC_HANDLE svc = OpenServiceW(scm, kSvcName, SERVICE_STOP | DELETE | SERVICE_QUERY_STATUS);
    if (!svc) { LogF(L"OpenService failed %lu", GetLastError()); CloseServiceHandle(scm); return; }

    SERVICE_STATUS ss{};
    ControlService(svc, SERVICE_CONTROL_STOP, &ss); // best-effort
    DeleteService(svc);
    LogF(L"Service deleted");
    CloseServiceHandle(svc);
    CloseServiceHandle(scm);
}

// ------------------------------- main ----------------------------------------
int wmain(int argc, wchar_t* argv[])
{
    if (argc >= 2 && lstrcmpiW(argv[1], L"--install") == 0) {
        return InstallService() ? 0 : 1;
    }
    if (argc >= 2 && lstrcmpiW(argv[1], L"--uninstall") == 0) {
        UninstallService();
        return 0;
    }
    if (argc >= 2 && lstrcmpiW(argv[1], L"--service") == 0) {
        SERVICE_TABLE_ENTRYW ste[] = { { (LPWSTR)kSvcName, SvcMain }, { nullptr, nullptr } };
        StartServiceCtrlDispatcherW(ste);
        return 0;
    }

    // If launched by double-click: run child once (useful for quick test)
    LogF(L"Standalone run: launching child once");
    LaunchChild();
    if (g_child) { WaitForSingleObject(g_child, INFINITE); CloseHandle(g_child); g_child = nullptr; }
    return 0;
}
