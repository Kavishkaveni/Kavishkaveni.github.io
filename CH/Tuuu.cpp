// QCM-CH.cpp — Windows service-style wrapper that launches the Rust CH
// Build: x64, Unicode. Link: Advapi32.lib; Wtsapi32.lib; Userenv.lib; Version.lib

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <strsafe.h>
#include <cstdio>
#include <ctime>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")

// ====== config ======
static const wchar_t* kLogFile  = L"C:\\PAM\\logs\\ch_wrapper.txt";
static const wchar_t* kChildExe = L"C:\\PAM\\qcm_autologin_service.exe";
static const wchar_t* kArgsFmt  = L"\"%s\" --port 10443 --log-dir C:\\PAM\\logs";
static const DWORD    kPollMs   = 1000;       // poll for session/child changes
static const DWORD    kRestartDelayMs = 2000; // small delay before relaunch
// =====================

static void log_line(const wchar_t* fmt, ...)
{
    HANDLE h = CreateFileW(kLogFile, FILE_APPEND_DATA, FILE_SHARE_READ, NULL,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return;

    wchar_t buf[2048];
    wchar_t ts[64];
    std::time_t t = std::time(nullptr);
    std::tm tm{};
    localtime_s(&tm, &t);
    wcsftime(ts, 64, L"%Y-%m-%d %H:%M:%S", &tm);

    va_list ap;
    va_start(ap, fmt);
    StringCchVPrintfW(buf, 2048, fmt, ap);
    va_end(ap);

    wchar_t line[2300];
    StringCchPrintfW(line, 2300, L"%s [CH-WRAPPER] %s\r\n", ts, buf);

    DWORD bytes = 0;
    WriteFile(h, line, (DWORD)(wcslen(line) * sizeof(wchar_t)), &bytes, NULL);
    CloseHandle(h);
}

static BOOL enable_privilege(LPCWSTR name)
{
    HANDLE hToken = NULL;
    if (!OpenProcessToken(GetCurrentProcess(),
                          TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken)) {
        log_line(L"enable_privilege: OpenProcessToken failed ec=%lu", GetLastError());
        return FALSE;
    }
    TOKEN_PRIVILEGES tp{};
    LUID luid{};
    if (!LookupPrivilegeValueW(NULL, name, &luid)) {
        log_line(L"enable_privilege: LookupPrivilegeValue failed ec=%lu", GetLastError());
        CloseHandle(hToken);
        return FALSE;
    }
    tp.PrivilegeCount = 1;
    tp.Privileges[0].Luid = luid;
    tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
    if (!AdjustTokenPrivileges(hToken, FALSE, &tp, sizeof(tp), NULL, NULL)) {
        log_line(L"enable_privilege: AdjustTokenPrivileges failed ec=%lu", GetLastError());
        CloseHandle(hToken);
        return FALSE;
    }
    CloseHandle(hToken);
    return TRUE;
}

static DWORD find_active_rdp_session()
{
    PWTS_SESSION_INFO pInfo = nullptr;
    DWORD count = 0;
    DWORD activeId = 0xFFFFFFFF;

    if (WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &pInfo, &count)) {
        for (DWORD i = 0; i < count; ++i) {
            if (pInfo[i].State == WTSActive) {
                // Prefer RDP sessions (name starts with "RDP-")
                if (pInfo[i].pWinStationName && wcsncmp(pInfo[i].pWinStationName, L"RDP-", 4) == 0) {
                    activeId = pInfo[i].SessionId;
                    break;
                }
                // Otherwise keep last WTSActive
                activeId = pInfo[i].SessionId;
            }
        }
        WTSFreeMemory(pInfo);
    }

    if (activeId == 0xFFFFFFFF) {
        return (DWORD)-1;
    }
    return activeId;
}

static HANDLE get_primary_token_for_session(DWORD sessionId)
{
    HANDLE userTok = NULL;
    if (!WTSQueryUserToken(sessionId, &userTok)) {
        log_line(L"WTSQueryUserToken(%lu) failed ec=%lu", sessionId, GetLastError());
        return NULL;
    }

    HANDLE primaryTok = NULL;
    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    if (!DuplicateTokenEx(userTok, TOKEN_ALL_ACCESS, &sa,
                          SecurityIdentification, TokenPrimary, &primaryTok)) {
        log_line(L"DuplicateTokenEx failed ec=%lu", GetLastError());
        CloseHandle(userTok);
        return NULL;
    }
    CloseHandle(userTok);
    return primaryTok;
}

static BOOL launch_child_in_session(DWORD sessionId, PROCESS_INFORMATION* outPi)
{
    ZeroMemory(outPi, sizeof(*outPi));

    HANDLE hPrimary = get_primary_token_for_session(sessionId);
    if (!hPrimary) return FALSE;

    // Load user profile (best effort)
    PROFILEINFOW pi{};
    pi.dwSize = sizeof(pi);
    pi.lpUserName = L"."; // current user of token
    HANDLE hProfile = NULL;
    if (!LoadUserProfileW(hPrimary, &pi)) {
        log_line(L"LoadUserProfile failed ec=%lu (continuing)", GetLastError());
    } else {
        hProfile = pi.hProfile;
    }

    // Create environment block
    LPVOID env = NULL;
    if (!CreateEnvironmentBlock(&env, hPrimary, FALSE)) {
        log_line(L"CreateEnvironmentBlock failed ec=%lu (continuing)", GetLastError());
    }

    // Compose command line
    wchar_t cmd[1024];
    StringCchPrintfW(cmd, 1024, kArgsFmt, kChildExe);

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.lpDesktop = (LPWSTR)L"winsta0\\default";  // IMPORTANT: visible on RDP desktop
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;                    // hide CH console window

    DWORD flags = CREATE_UNICODE_ENVIRONMENT;
    // (optional) CREATE_NO_WINDOW if you never want a console window for CH
    // flags |= CREATE_NO_WINDOW;

    BOOL ok = CreateProcessAsUserW(
        hPrimary,
        kChildExe,     // application
        cmd,           // command line (can be NULL if you pass args differently)
        NULL, NULL,    // process/thread security
        FALSE,         // inherit handles
        flags,
        env,           // environment
        NULL,          // current directory
        &si, outPi
    );

    if (!ok) {
        log_line(L"CreateProcessAsUser failed ec=%lu", GetLastError());
    } else {
        log_line(L"Launched Rust CH in session %lu, pid %lu", sessionId, outPi->dwProcessId);
    }

    if (env) DestroyEnvironmentBlock(env);
    if (hProfile) UnloadUserProfile(hPrimary, hProfile);
    CloseHandle(hPrimary);

    return ok;
}

static void kill_process_tree(DWORD pid)
{
    if (pid == 0) return;
    HANDLE h = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
    if (h) {
        TerminateProcess(h, 1);
        CloseHandle(h);
    }
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int)
{
    CreateDirectoryW(L"C:\\PAM\\logs", NULL);

    log_line(L"Service worker start");

    // Ensure the service process has the right privileges
    enable_privilege(SE_ASSIGNPRIMARYTOKEN_NAME);
    enable_privilege(SE_INCREASE_QUOTA_NAME);
    enable_privilege(SE_TCB_NAME);

    DWORD lastSession = (DWORD)-1;
    PROCESS_INFORMATION child{};
    ZeroMemory(&child, sizeof(child));
    bool childRunning = false;

    for (;;) {
        DWORD active = find_active_rdp_session();
        if (active == (DWORD)-1) {
            // no active RDP
            if (childRunning) {
                log_line(L"No ACTIVE RDP session; stopping child");
                kill_process_tree(child.dwProcessId);
                if (child.hProcess) CloseHandle(child.hProcess);
                if (child.hThread)  CloseHandle(child.hThread);
                ZeroMemory(&child, sizeof(child));
                childRunning = false;
            }
            Sleep(kPollMs);
            continue;
        }

        // Found active RDP session
        if (!childRunning || active != lastSession) {
            if (childRunning) {
                // session changed; stop old child first
                log_line(L"Active RDP session changed (%lu -> %lu); restarting child", lastSession, active);
                kill_process_tree(child.dwProcessId);
                if (child.hProcess) CloseHandle(child.hProcess);
                if (child.hThread)  CloseHandle(child.hThread);
                ZeroMemory(&child, sizeof(child));
                childRunning = false;
                Sleep(kRestartDelayMs);
            }

            log_line(L"Active RDP session found: %lu", active);
            if (launch_child_in_session(active, &child)) {
                childRunning = true;
                lastSession = active;
            } else {
                // failed to start; try again soon
                Sleep(kRestartDelayMs);
            }
        } else {
            // child should be running for this session; check if it died
            DWORD code = STILL_ACTIVE;
            if (child.hProcess && GetExitCodeProcess(child.hProcess, &code) && code != STILL_ACTIVE) {
                log_line(L"Rust CH exited (code=%lu). Will restart when session is active.", code);
                if (child.hProcess) CloseHandle(child.hProcess);
                if (child.hThread)  CloseHandle(child.hThread);
                ZeroMemory(&child, sizeof(child));
                childRunning = false;
                Sleep(kRestartDelayMs);
            }
        }

        Sleep(kPollMs);
    }

    return 0;
}
