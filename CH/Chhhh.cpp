#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <tlhelp32.h>
#include <tchar.h>
#include <string>
#include <fstream>

#pragma comment(lib, "wtsapi32.lib")
#pragma comment(lib, "userenv.lib")

SERVICE_STATUS g_ServiceStatus = { 0 };
SERVICE_STATUS_HANDLE g_StatusHandle = NULL;
HANDLE g_ServiceStopEvent = NULL;

std::ofstream logFile("C:\\QCMCH_service.log", std::ios::app);

void Log(const std::string& msg) {
    SYSTEMTIME st;
    GetLocalTime(&st);
    logFile << "[" << st.wHour << ":" << st.wMinute << ":" << st.wSecond << "] " << msg << std::endl;
    logFile.flush();
}

bool LaunchInActiveSession(const std::wstring& exePath) {
    DWORD sessionId = WTSGetActiveConsoleSessionId();
    if (sessionId == 0xFFFFFFFF) {
        Log("❌ No active console session found.");
        return false;
    }
    Log("✅ Active session ID found: " + std::to_string(sessionId));

    HANDLE hUserToken = NULL;
    if (!WTSQueryUserToken(sessionId, &hUserToken)) {
        Log("❌ WTSQueryUserToken failed: " + std::to_string(GetLastError()));
        return false;
    }
    Log("✅ User token retrieved.");

    HANDLE hDupToken = NULL;
    if (!DuplicateTokenEx(hUserToken, TOKEN_ALL_ACCESS, NULL, SecurityImpersonation, TokenPrimary, &hDupToken)) {
        Log("❌ DuplicateTokenEx failed: " + std::to_string(GetLastError()));
        CloseHandle(hUserToken);
        return false;
    }
    Log("✅ Token duplicated.");

    PROFILEINFO pi = { sizeof(PROFILEINFO) };
    pi.dwFlags = PI_NOUI;
    WCHAR userName[256];
    DWORD size = 256;
    if (GetUserNameW(userName, &size)) {
        pi.lpUserName = userName;
        if (!LoadUserProfile(hDupToken, &pi)) {
            Log("⚠️ LoadUserProfile failed: " + std::to_string(GetLastError()));
        } else {
            Log("✅ User profile loaded.");
        }
    }

    STARTUPINFO si = { 0 };
    PROCESS_INFORMATION piProc = { 0 };
    si.cb = sizeof(si);
    si.lpDesktop = (LPWSTR)L"winsta0\\default";

    std::wstring cmd = L"\"" + exePath + L"\"";

    if (!CreateProcessAsUser(
        hDupToken,
        NULL,
        (LPWSTR)cmd.c_str(),
        NULL,
        NULL,
        FALSE,
        CREATE_NEW_CONSOLE,
        NULL,
        NULL,
        &si,
        &piProc))
    {
        Log("❌ CreateProcessAsUser failed: " + std::to_string(GetLastError()));
        CloseHandle(hDupToken);
        CloseHandle(hUserToken);
        return false;
    }

    Log("✅ Process launched successfully (PID=" + std::to_string(piProc.dwProcessId) + ").");

    CloseHandle(piProc.hProcess);
    CloseHandle(piProc.hThread);
    CloseHandle(hDupToken);
    CloseHandle(hUserToken);

    return true;
}

void WINAPI ServiceCtrlHandler(DWORD CtrlCode) {
    if (CtrlCode == SERVICE_CONTROL_STOP) {
        if (g_ServiceStatus.dwCurrentState != SERVICE_RUNNING)
            return;

        g_ServiceStatus.dwControlsAccepted = 0;
        g_ServiceStatus.dwCurrentState = SERVICE_STOP_PENDING;
        SetServiceStatus(g_StatusHandle, &g_ServiceStatus);

        SetEvent(g_ServiceStopEvent);
    }
}

void WINAPI ServiceMain(DWORD argc, LPWSTR* argv) {
    g_StatusHandle = RegisterServiceCtrlHandler(L"QCMCH", ServiceCtrlHandler);
    if (!g_StatusHandle) return;

    g_ServiceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_ServiceStatus.dwControlsAccepted = SERVICE_ACCEPT_STOP;
    g_ServiceStatus.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(g_StatusHandle, &g_ServiceStatus);

    g_ServiceStopEvent = CreateEvent(NULL, TRUE, FALSE, NULL);

    Log("🚀 QCMCH Service started. Running in Session 0.");

    std::wstring exePath = L"C:\\PAM\\ch.exe"; // ⚠️ Adjust path to your Rust CH

    while (WaitForSingleObject(g_ServiceStopEvent, 5000) == WAIT_TIMEOUT) {
        if (!LaunchInActiveSession(exePath)) {
            Log("⚠️ Retry: Active session not ready, will check again.");
        }
    }

    Log("🛑 QCMCH Service stopping.");
    g_ServiceStatus.dwCurrentState = SERVICE_STOPPED;
    SetServiceStatus(g_StatusHandle, &g_ServiceStatus);
}

int wmain(int argc, wchar_t* argv[]) {
    SERVICE_TABLE_ENTRY ServiceTable[] = {
        { (LPWSTR)L"QCMCH", (LPSERVICE_MAIN_FUNCTION)ServiceMain },
        { NULL, NULL }
    };

    if (!StartServiceCtrlDispatcher(ServiceTable)) {
        Log("❌ Failed to start service control dispatcher: " + std::to_string(GetLastError()));
    }
    return 0;
}
