// QCM-CH.cpp  — Windows service wrapper that launches CH into the active RDP desktop.
// Target: Win10+, VS2017, x64, Unicode.
// Link: Advapi32.lib; Wtsapi32.lib; Userenv.lib

#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <strsafe.h>
#include <stdio.h>
#include <time.h>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")

// ---------- config ----------
static const wchar_t* kChildExe      = L"C:\\PAM\\qcm_autologin_service.exe";
static const wchar_t* kChildArgsFmt  = L" --port 10443 --log-dir C:\\PAM\\logs";
static const DWORD    kPollMs        = 3000;
// ----------------------------

static void log_line(const wchar_t* fmt, ...)
{
    wchar_t buf[1024];
    va_list ap; va_start(ap, fmt);
    StringCchVPrintfW(buf, _countof(buf), fmt, ap);
    va_end(ap);

    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t line[1400];
    StringCchPrintfW(line, _countof(line),
        L"%04u-%02u-%02u %02u:%02u:%02u [%s] %s\r\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
        L"CH-WRAPPER", buf);

    // write to C:\PAM\logs\ch_wrapper.txt (best-effort)
    CreateDirectoryW(L"C:\\PAM\\logs", nullptr);
    HANDLE h = CreateFileW(L"C:\\PAM\\logs\\ch_wrapper.txt",
                           FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h != INVALID_HANDLE_VALUE) {
        DWORD bytes = 0;
        WriteFile(h, (const void*)line, (DWORD)(lstrlenW(line) * sizeof(wchar_t)), &bytes, nullptr);
        CloseHandle(h);
    }
}

// Enable a privilege in the current process token (needed for CreateProcessAsUser, env block, etc.)
static BOOL enable_privilege(LPCWSTR priv)
{
    HANDLE hTok = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hTok))
        return FALSE;

    TOKEN_PRIVILEGES tp{};
    LUID luid;
    BOOL ok = FALSE;

    if (LookupPrivilegeValueW(nullptr, priv, &luid)) {
        tp.PrivilegeCount = 1;
        tp.Privileges[0].Luid = luid;
        tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
        ok = AdjustTokenPrivileges(hTok, FALSE, &tp, sizeof(tp), nullptr, nullptr);
    }
    CloseHandle(hTok);
    return ok;
}

static DWORD find_active_rdp_session()
{
    PWTS_SESSION_INFOW sessions = nullptr;
    DWORD count = 0;
    DWORD activeId = 0;

    if (WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &sessions, &count)) {
        for (DWORD i = 0; i < count; ++i) {
            if (sessions[i].State == WTSActive && sessions[i].SessionId >= 1) {
                activeId = sessions[i].SessionId;
                break;
            }
        }
        WTSFreeMemory(sessions);
    }
    return activeId; // 0 means none
}

static BOOL query_username_for_session(DWORD sessionId, wchar_t* out, DWORD cch)
{
    LPTSTR pUser = nullptr; DWORD bytes = 0;
    if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sessionId, WTSUserName, &pUser, &bytes))
        return FALSE;

    BOOL ok = FALSE;
    if (pUser && *pUser) {
        ok = SUCCEEDED(StringCchCopyW(out, cch, pUser));
    }
    if (pUser) WTSFreeMemory(pUser);
    return ok;
}

static HANDLE get_primary_token_for_session(DWORD sessionId)
{
    HANDLE impTok = nullptr;   // impersonation token from WTS
    HANDLE primTok = nullptr;  // primary token we will return

    if (!WTSQueryUserToken(sessionId, &impTok)) {
        log_line(L"WTSQueryUserToken failed ec=%lu", GetLastError());
        return nullptr;
    }

    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);

    if (!DuplicateTokenEx(
            impTok,
            TOKEN_ALL_ACCESS,
            &sa,
            SecurityImpersonation,
            TokenPrimary,
            &primTok))
    {
        log_line(L"DuplicateTokenEx failed ec=%lu", GetLastError());
        CloseHandle(impTok);
        return nullptr;
    }

    CloseHandle(impTok);
    return primTok;
}

static BOOL launch_child_in_session(DWORD sessionId, PROCESS_INFORMATION* outPi)
{
    ZeroMemory(outPi, sizeof(*outPi));

    // 1) Acquire primary token for the RDP user
    HANDLE hPrimary = get_primary_token_for_session(sessionId);
    if (!hPrimary) return FALSE;

    // 2) Get username for profile load
    wchar_t userBuf[256] = L"";
    query_username_for_session(sessionId, userBuf, _countof(userBuf));

    // 3) Load user profile (best-effort)
    PROFILEINFOW pi{}; pi.dwSize = sizeof(pi);
    pi.lpUserName = userBuf[0] ? userBuf : nullptr;  // if unknown, let it be null
    if (!LoadUserProfileW(hPrimary, &pi)) {
        log_line(L"LoadUserProfileW failed ec=%lu (continuing)", GetLastError());
        pi.hProfile = nullptr;
    }

    // 4) Build environment block for the user
    LPVOID env = nullptr;
    if (!CreateEnvironmentBlock(&env, hPrimary, FALSE)) {
        log_line(L"CreateEnvironmentBlock failed ec=%lu (continuing with NULL env)", GetLastError());
        env = nullptr;
    }

    // 5) Compose command line: <exe> <args>
    wchar_t cmd[1024];
    StringCchCopyW(cmd, _countof(cmd), kChildExe);
    StringCchCatW(cmd, _countof(cmd), kChildArgsFmt);

    // 6) Startup info — IMPORTANT: bind to interactive desktop
    STARTUPINFOW si{}; si.cb = sizeof(si);
    si.lpDesktop = const_cast<LPWSTR>(L"winsta0\\default");
    si.dwFlags  |= STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_SHOW;  // show CH console (or SW_HIDE if you truly want hidden)

    DWORD creationFlags = CREATE_UNICODE_ENVIRONMENT;

    // 7) Launch!
    BOOL ok = CreateProcessAsUserW(
        hPrimary,
        nullptr,            // lpApplicationName
        cmd,                // lpCommandLine
        nullptr, nullptr,   // proc & thread security
        FALSE,
        creationFlags,
        env,                // environment
        nullptr,            // current dir
        &si,
        outPi);

    if (!ok) {
        log_line(L"CreateProcessAsUserW failed ec=%lu", GetLastError());
    } else {
        log_line(L"Launched Rust CH in session %lu, pid %lu", sessionId, outPi->dwProcessId);
    }

    if (env) DestroyEnvironmentBlock(env);
    if (pi.hProfile) UnloadUserProfile(hPrimary, pi.hProfile);
    CloseHandle(hPrimary);
    return ok;
}

static BOOL process_is_alive(const PROCESS_INFORMATION& pi)
{
    DWORD code = 0;
    if (!GetExitCodeProcess(pi.hProcess, &code)) return FALSE;
    return code == STILL_ACTIVE;
}

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int)
{
    // Make sure we have the privileges required by CreateProcessAsUser
    enable_privilege(SE_INCREASE_QUOTA_NAME);
    enable_privilege(SE_ASSIGNPRIMARYTOKEN_NAME);

    log_line(L"Service worker start");

    PROCESS_INFORMATION childPi{}; ZeroMemory(&childPi, sizeof(childPi));
    DWORD runningInSession = 0;

    for (;;)
    {
        DWORD sid = find_active_rdp_session();
        if (sid == 0) {
            if (childPi.hProcess) {
                log_line(L"No ACTIVE RDP session; stopping child");
                TerminateProcess(childPi.hProcess, 0);
                CloseHandle(childPi.hThread); CloseHandle(childPi.hProcess);
                ZeroMemory(&childPi, sizeof(childPi));
                runningInSession = 0;
            }
            Sleep(kPollMs);
            continue;
        }

        if (!childPi.hProcess || !process_is_alive(childPi) || sid != runningInSession) {
            // (Re)launch for current active session
            if (childPi.hProcess) {
                TerminateProcess(childPi.hProcess, 0);
                CloseHandle(childPi.hThread); CloseHandle(childPi.hProcess);
                ZeroMemory(&childPi, sizeof(childPi));
            }
            log_line(L"Active RDP session found: %lu", sid);
            if (launch_child_in_session(sid, &childPi)) {
                runningInSession = sid;
            } else {
                runningInSession = 0;
            }
        }

        Sleep(kPollMs);
    }
    // (unreachable)
}
