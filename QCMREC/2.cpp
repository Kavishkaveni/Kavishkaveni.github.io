// qcmrec.cpp
#define _WIN32_WINNT 0x0600

#include <windows.h>
#include <wtsapi32.h>
#include <strsafe.h>
#include <userenv.h>

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "wtsapi32.lib")
#pragma comment(lib, "userenv.lib")

#ifndef WTS_SESSION_LOGOFF
#define WTS_SESSION_LOGOFF 0x4
#endif
#ifndef WTS_SESSION_LOGON
#define WTS_SESSION_LOGON 0x5
#endif
#ifndef WTS_SESSION_DISCONNECT
#define WTS_SESSION_DISCONNECT 0x6
#endif

SERVICE_STATUS        g_ServiceStatus{};
SERVICE_STATUS_HANDLE g_StatusHandle = nullptr;

PROCESS_INFORMATION   g_FFmpegProc{};
DWORD                 g_SessionId = 0;
HANDLE                g_PollThread = nullptr;
volatile BOOL         g_ShouldPoll = FALSE;

#define SERVICE_NAME   L"QCMREC"
#define FFMPEG_PATH    L"C:\\PAM\\ffmpeg.exe"
#define REC_DIR        L"C:\\PAM\\recordings"
#define LOG_FILE       L"C:\\PAM\\qcmrec.log"
#define MANUAL_TRIGGER L"C:\\PAM\\start.txt"

// ------------------- Logging -------------------
void LogLine(LPCWSTR msg)
{
    HANDLE f = CreateFileW(LOG_FILE, FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
        OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;
    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t line[512];
    StringCchPrintfW(line, 512, L"%04u-%02u-%02u %02u:%02u:%02u  %s\r\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, msg);
    DWORD cb; WriteFile(f, line, (DWORD)(wcslen(line) * sizeof(wchar_t)), &cb, nullptr);
    CloseHandle(f);
}
void EnsureRecDir() { if (GetFileAttributesW(REC_DIR) == INVALID_FILE_ATTRIBUTES) CreateDirectoryW(REC_DIR, nullptr); }

// ------------------- Stop recorder -------------------
void StopRecorder()
{
    g_ShouldPoll = FALSE;
    if (g_PollThread) { WaitForSingleObject(g_PollThread, 3000); CloseHandle(g_PollThread); g_PollThread = nullptr; }
    if (g_FFmpegProc.hProcess) { TerminateProcess(g_FFmpegProc.hProcess, 0); CloseHandle(g_FFmpegProc.hProcess); g_FFmpegProc.hProcess = nullptr; }
    g_SessionId = 0;
    LogLine(L"Recording stopped");
}

// ------------------- Poll session (keep watching state) -------------------
DWORD WINAPI PollThread(LPVOID p)
{
    DWORD sid = *(DWORD*)p;
    delete (DWORD*)p;

    while (g_ShouldPoll) {
        LPTSTR ps = nullptr; DWORD cb = 0;
        WTS_CONNECTSTATE_CLASS st = WTSDisconnected;

        if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSConnectState, &ps, &cb) && ps) {
            st = *(WTS_CONNECTSTATE_CLASS*)ps;
            WTSFreeMemory(ps);
        }

        if (st == WTSActive) {
            // still active — keep recording
        }
        else if (st == WTSDisconnected) {
            wchar_t m[128];
            StringCchPrintfW(m, 128, L"Session %lu disconnected — waiting to confirm.", sid);
            LogLine(m);

            bool stillDisconnected = true;
            for (int i = 0; i < 10; i++) {
                Sleep(1000);
                LPTSTR ps2 = nullptr; DWORD cb2 = 0; WTS_CONNECTSTATE_CLASS st2 = WTSDisconnected;
                if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSConnectState, &ps2, &cb2) && ps2) {
                    st2 = *(WTS_CONNECTSTATE_CLASS*)ps2;
                    WTSFreeMemory(ps2);
                }
                if (st2 == WTSActive) {
                    LogLine(L"Session became active again — continue recording.");
                    stillDisconnected = false;
                    break;
                }
            }

            if (stillDisconnected) {
                LogLine(L"Session stayed disconnected — stopping recorder.");
                StopRecorder();
                break;
            }
        }
        else {
            wchar_t m[128];
            StringCchPrintfW(m, 128, L"Session %lu still not active (%d). Waiting...", sid, (int)st);
            LogLine(m);
        }

        Sleep(1500);
    }
    return 0;
}

// ------------------- Popup message to user -------------------
void ShowPopup(DWORD sid) {
    DWORD resp = 0;
    const wchar_t* t = L"Recording"; const wchar_t* b = L"Screen recording started.";
    WTSSendMessageW(WTS_CURRENT_SERVER_HANDLE, sid, (LPWSTR)t, (DWORD)(wcslen(t) * sizeof(wchar_t)),
        (LPWSTR)b, (DWORD)(wcslen(b) * sizeof(wchar_t)), MB_OK | MB_ICONINFORMATION, 0, &resp, FALSE);
}

// ------------------- Select active RDP session -------------------
DWORD FindRdpSession() {
    PWTS_SESSION_INFO info = nullptr; DWORD cnt = 0; DWORD res = 0xFFFFFFFF;
    if (WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &info, &cnt)) {
        for (DWORD i = 0; i < cnt; i++)
            if (info[i].State == WTSActive) {
                LPTSTR pT = nullptr; DWORD cb = 0;
                if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, info[i].SessionId, WTSClientProtocolType, &pT, &cb) && pT) {
                    if (*(USHORT*)pT == 2) { // 2 = RDP
                        res = info[i].SessionId;
                        WTSFreeMemory(pT);
                        break;
                    }
                    WTSFreeMemory(pT);
                }
            }
        WTSFreeMemory(info);
    }
    return res;
}

// ------------------- Launch FFmpeg in the user session -------------------
BOOL LaunchRecorder(DWORD sid) {
    LogLine(L"Getting user token...");
    HANDLE hUser = nullptr; for (int i = 0; i < 30; i++) { if (WTSQueryUserToken(sid, &hUser)) break; Sleep(500); }
    if (!hUser) { wchar_t m[128]; StringCchPrintfW(m, 128, L"WTSQueryUserToken failed %lu", GetLastError()); LogLine(m); return FALSE; }

    HANDLE hPrim = nullptr;
    if (!DuplicateTokenEx(hUser, TOKEN_ALL_ACCESS, nullptr, SecurityImpersonation, TokenPrimary, &hPrim)) { CloseHandle(hUser); LogLine(L"DuplicateTokenEx failed"); return FALSE; }
    CloseHandle(hUser);
    if (!SetTokenInformation(hPrim, TokenSessionId, &sid, sizeof(sid))) { CloseHandle(hPrim); LogLine(L"SetTokenInformation failed"); return FALSE; }

    PROFILEINFOW pi{}; pi.dwSize = sizeof(pi); LoadUserProfileW(hPrim, &pi);
    LPVOID env = nullptr; CreateEnvironmentBlock(&env, hPrim, FALSE);
    EnsureRecDir();
    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t out[MAX_PATH];
    StringCchPrintfW(out, MAX_PATH, L"%s\\session_%u_%04u%02u%02u_%02u%02u%02u.mp4", REC_DIR, sid, st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
    const wchar_t* grab = L" -f gdigrab -i desktop ";
    wchar_t cmd[1024]; StringCchPrintfW(cmd, 1024, L"\"%s\" -y%ls-framerate 15 -c:v libx264 -preset ultrafast \"%s\"", FFMPEG_PATH, grab, out);

    // ---- Important: impersonate before launching ----
    ImpersonateLoggedOnUser(hPrim);

    STARTUPINFOW si{}; si.cb = sizeof(si); si.lpDesktop = (LPWSTR)L"winsta0\\default";
    PROCESS_INFORMATION piP{};
    BOOL ok = CreateProcessAsUserW(hPrim, nullptr, cmd, nullptr, nullptr, FALSE,
        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
        env, nullptr, &si, &piP);
    RevertToSelf(); // back to service identity

    if (!ok) {
        LogLine(L"CreateProcessAsUserW failed");
        if (env) DestroyEnvironmentBlock(env);
        CloseHandle(hPrim);
        return FALSE;
    }

    g_FFmpegProc = piP;
    CloseHandle(piP.hThread);
    if (env) DestroyEnvironmentBlock(env);
    CloseHandle(hPrim);

    ShowPopup(sid);
    g_SessionId = sid;
    g_ShouldPoll = TRUE;
    DWORD* s = new DWORD(sid);
    g_PollThread = CreateThread(nullptr, 0, PollThread, s, 0, nullptr);
    LogLine(L"Recording started");
    return TRUE;
}

// ------------------- Control Handler: reacts to logon/logoff -------------------
DWORD WINAPI CtrlHandlerEx(DWORD c, DWORD e, LPVOID d, LPVOID) {
    if (c == SERVICE_CONTROL_STOP) {
        StopRecorder();
        g_ServiceStatus.dwCurrentState = SERVICE_STOPPED;
        SetServiceStatus(g_StatusHandle, &g_ServiceStatus);
        LogLine(L"Service stopped");
        return NO_ERROR;
    }
    if (c == SERVICE_CONTROL_SESSIONCHANGE) {
        DWORD sid = d ? ((WTSSESSION_NOTIFICATION*)d)->dwSessionId : 0;
        wchar_t m[128]; StringCchPrintfW(m, 128, L"SESSIONCHANGE %u sid=%u", e, sid); LogLine(m);
        if (e == WTS_SESSION_LOGON) { Sleep(1000); DWORD r = FindRdpSession(); if (r != 0xFFFFFFFF) LaunchRecorder(r); }
        else if (e == WTS_SESSION_LOGOFF) { StopRecorder(); }
        else if (e == WTS_SESSION_DISCONNECT) {
            LogLine(L"SESSIONCHANGE disconnect — let PollThread decide");
            // DO NOT StopRecorder() here
        }
        return NO_ERROR;
    }
    return ERROR_CALL_NOT_IMPLEMENTED;
}

// ------------------- Service Main -------------------
void WINAPI ServiceMain(DWORD, LPWSTR*) {
    g_StatusHandle = RegisterServiceCtrlHandlerExW(SERVICE_NAME, CtrlHandlerEx, nullptr);
    if (!g_StatusHandle) return;

    // ---- Enable privileges so service can launch user process ----
    HANDLE hToken = NULL;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken)) {
        TOKEN_PRIVILEGES tp; LUID luid;
        if (LookupPrivilegeValue(NULL, SE_ASSIGNPRIMARYTOKEN_NAME, &luid)) {
            tp.PrivilegeCount = 1; tp.Privileges[0].Luid = luid; tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
            AdjustTokenPrivileges(hToken, FALSE, &tp, sizeof(tp), NULL, NULL);
        }
        if (LookupPrivilegeValue(NULL, SE_INCREASE_QUOTA_NAME, &luid)) {
            tp.PrivilegeCount = 1; tp.Privileges[0].Luid = luid; tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
            AdjustTokenPrivileges(hToken, FALSE, &tp, sizeof(tp), NULL, NULL);
        }
        CloseHandle(hToken);
    }

    g_ServiceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_ServiceStatus.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SESSIONCHANGE;
    g_ServiceStatus.dwCurrentState = SERVICE_START_PENDING;
    SetServiceStatus(g_StatusHandle, &g_ServiceStatus);
    LogLine(L"Service starting");

    EnsureRecDir();

    g_ServiceStatus.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(g_StatusHandle, &g_ServiceStatus);
    LogLine(L"Service running");

    if (GetFileAttributesW(MANUAL_TRIGGER) != INVALID_FILE_ATTRIBUTES) {
        DWORD sid = WTSGetActiveConsoleSessionId();
        LaunchRecorder(sid);
    }

    while (g_ServiceStatus.dwCurrentState == SERVICE_RUNNING) Sleep(1000);
}

// ------------------- Entry -------------------
int wmain() {
    SERVICE_TABLE_ENTRYW tbl[] = { {(LPWSTR)SERVICE_NAME,(LPSERVICE_MAIN_FUNCTIONW)ServiceMain},{nullptr,nullptr} };
    if (!StartServiceCtrlDispatcherW(tbl)) {
        MessageBoxW(nullptr, L"Running manually (debug).", SERVICE_NAME, MB_OK);
        EnsureRecDir(); DWORD sid = WTSGetActiveConsoleSessionId(); LaunchRecorder(sid); Sleep(10000); StopRecorder();
    }
    return 0;
}
