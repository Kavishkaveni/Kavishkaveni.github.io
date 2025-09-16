// QCMCH.cpp - Windows Service wrapper for Rust CH (qcm_autologin_service.exe)
// Build: Release x64, Unicode
// Linker -> Input -> add: Advapi32.lib; Wtsapi32.lib; Userenv.lib

#define UNICODE
#define _UNICODE
#include <windows.h>
#include <strsafe.h>
#include <tlhelp32.h>
#include <wtsapi32.h>
#include <userenv.h>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")

static const wchar_t* kSvcName = L"QCM-CH";
static const wchar_t* kSvcDisp = L"QCM Chrome AutoLogin Service";

static SERVICE_STATUS_HANDLE gSsh = nullptr;
static SERVICE_STATUS gSs{};
static HANDLE gChildProc = nullptr;
static HANDLE gStopEvent = nullptr;

// ---------------- state helper ----------------
static void SetState(DWORD s, DWORD win32 = NO_ERROR, DWORD waitHintMs = 0) {
    gSs.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    gSs.dwCurrentState = s;
    gSs.dwWin32ExitCode = win32;
    gSs.dwControlsAccepted = (s == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    gSs.dwWaitHint = waitHintMs;
    SetServiceStatus(gSsh, &gSs);
}

// ---------------- process helpers ----------------
static void KillProcessTree(HANDLE hProcess) {
    if (!hProcess) return;
    DWORD pid = GetProcessId(hProcess);
    if (!pid) return;

    // Try terminate main
    TerminateProcess(hProcess, 0);

    // Best-effort: kill direct children too
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

// ---------------- launch CH in active session ----------------
static HANDLE LaunchRustCHInSession() {
    // Adjust if your exe / args differ
    const wchar_t* exePath = L"C:\\PAM\\qcm_autologin_service.exe";
    const wchar_t* args    = L" --port 10443 --log-dir C:\\PAM\\logs";

    wchar_t cmd[1024];
    StringCchPrintfW(cmd, 1024, L"\"%s\"%s", exePath, args);

    // 1) Find interactive session (console/RDP)
    DWORD sid = WTSGetActiveConsoleSessionId();
    if (sid == 0xFFFFFFFF) {
        // No interactive session -> don't start
        return nullptr;
    }

    // 2) Get user token
    HANDLE hUserToken = nullptr;
    if (!WTSQueryUserToken(sid, &hUserToken)) {
        return nullptr;
    }

    // 3) Primary token
    HANDLE hPrimary = nullptr;
    if (!DuplicateTokenEx(
            hUserToken,
            TOKEN_ALL_ACCESS,
            nullptr,
            SecurityIdentification,
            TokenPrimary,
            &hPrimary)) {
        CloseHandle(hUserToken);
        return nullptr;
    }

    // 4) User environment (optional but helps Chrome)
    LPVOID env = nullptr;
    if (!CreateEnvironmentBlock(&env, hPrimary, FALSE)) {
        env = nullptr; // continue without env
    }

    // 5) Create process on interactive desktop
    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.lpDesktop = const_cast<LPWSTR>(L"winsta0\\default");

    PROCESS_INFORMATION pi{};
    BOOL ok = CreateProcessAsUserW(
        hPrimary,
        exePath,
        cmd, // command line with args
        nullptr, nullptr, FALSE,
        CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_PROCESS_GROUP,
        env,
        L"C:\\PAM",
        &si,
        &pi
    );

    if (env) DestroyEnvironmentBlock(env);
    CloseHandle(hPrimary);
    CloseHandle(hUserToken);

    if (!ok) return nullptr;

    CloseHandle(pi.hThread);
    return pi.hProcess; // caller must CloseHandle()
}

// ---------------- worker thread ----------------
static DWORD WINAPI Worker(LPVOID) {
    CreateDirectoryW(L"C:\\PAM", nullptr);
    CreateDirectoryW(L"C:\\PAM\\logs", nullptr);

    for (;;) {
        if (WaitForSingleObject(gStopEvent, 0) == WAIT_OBJECT_0) break;

        if (!gChildProc) {
            gChildProc = LaunchRustCHInSession();
        }

        HANDLE waitHandles[2] = { gStopEvent, gChildProc ? gChildProc : gStopEvent };
        DWORD count = gChildProc ? 2 : 1;

        DWORD wr = WaitForMultipleObjects(count, waitHandles, FALSE, 1000);
        if (wr == WAIT_OBJECT_0) {
            // stop requested
            if (gChildProc) { KillProcessTree(gChildProc); CloseHandle(gChildProc); gChildProc = nullptr; }
            break;
        }
        if (wr == WAIT_OBJECT_0 + 1) {
            // child exited -> restart after small backoff
            if (gChildProc) { CloseHandle(gChildProc); gChildProc = nullptr; }
            Sleep(1500);
        }
        // else timeout, loop
    }

    if (gChildProc) { KillProcessTree(gChildProc); CloseHandle(gChildProc); gChildProc = nullptr; }
    return 0;
}

// ---------------- SCM plumbing ----------------
static void WINAPI CtrlHandler(DWORD ctrl) {
    if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
        SetEvent(gStopEvent);
        SetState(SERVICE_STOP_PENDING, NO_ERROR, 4000);
    }
}

static void WINAPI SvcMain(DWORD, LPWSTR*) {
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
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int) {
    SERVICE_TABLE_ENTRYW ste[] = {
        { (LPWSTR)kSvcName, SvcMain },
        { nullptr, nullptr }
    };
    StartServiceCtrlDispatcherW(ste);
    return 0;
}
