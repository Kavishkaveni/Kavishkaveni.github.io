#define _WIN32_WINNT 0x0600
#include <windows.h>
#include <wtsapi32.h>
#include <strsafe.h>
#include <userenv.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dwmapi.h>

#pragma comment(lib,"wtsapi32.lib")
#pragma comment(lib,"advapi32.lib")
#pragma comment(lib,"userenv.lib")
#pragma comment(lib,"d3d11.lib")
#pragma comment(lib,"dxgi.lib")

#ifndef WTS_SESSION_DISCONNECT
#define WTS_SESSION_DISCONNECT 0x6
#endif
#ifndef WTS_SESSION_LOCK
#define WTS_SESSION_LOCK 0x7
#endif
#ifndef WTS_SESSION_UNLOCK
#define WTS_SESSION_UNLOCK 0x8
#endif

SERVICE_STATUS        g_ServiceStatus = {};
SERVICE_STATUS_HANDLE g_StatusHandle = nullptr;
PROCESS_INFORMATION   g_RecProc = {};
DWORD                 g_RecordingSessionId = 0;
HANDLE                g_RecPollThread = nullptr;
volatile BOOL         g_ShouldPollSession = FALSE;

#define SERVICE_NAME   L"QCMREC"
#define RECORDER_PATH  L"C:\\PAM\\ffmpeg.exe"
#define REC_OUTPUT     L"C:\\PAM\\recordings\\session.mp4"
#define LOG_FILE       L"C:\\PAM\\qcmrec.log"
#define MANUAL_TRIGGER L"C:\\PAM\\start.txt"

void LogLine(LPCWSTR msg)
{
    HANDLE f = CreateFileW(LOG_FILE, FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
        OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;

    SYSTEMTIME st;
    GetLocalTime(&st);
    wchar_t buf[1024];
    StringCchPrintfW(buf, 1024, L"%04d-%02d-%02d %02d:%02d:%02d  %s\r\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, msg);
    DWORD written = 0;
    WriteFile(f, buf, (DWORD)(wcslen(buf) * sizeof(wchar_t)), &written, nullptr);
    CloseHandle(f);
}

void StopRecorder()
{
    g_ShouldPollSession = FALSE;
    if (g_RecPollThread) {
        WaitForSingleObject(g_RecPollThread, 5000);
        CloseHandle(g_RecPollThread);
        g_RecPollThread = nullptr;
    }
    if (g_RecProc.hProcess) {
        TerminateProcess(g_RecProc.hProcess, 0);
        CloseHandle(g_RecProc.hProcess);
        g_RecProc.hProcess = nullptr;
        LogLine(L"Recording stopped");
    }
    g_RecordingSessionId = 0;
}

// Polls session state and stops recording if disconnected
DWORD WINAPI PollSessionStateThread(LPVOID param)
{
    DWORD sessionId = *(DWORD*)param;
    delete (DWORD*)param;
    while (g_ShouldPollSession) {
        WTS_CONNECTSTATE_CLASS state = WTSDisconnected;
        LPTSTR pState = nullptr;
        DWORD bytes = 0;
        if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sessionId, WTSConnectState, &pState, &bytes) && pState) {
            state = *(WTS_CONNECTSTATE_CLASS*)pState;
            WTSFreeMemory(pState);
        }
        if (state != WTSActive) {
            wchar_t msg[128];
            StringCchPrintfW(msg, 128, L"Session %lu is no longer active (state=%d). Stopping recorder.", sessionId, (int)state);
            LogLine(msg);
            StopRecorder();
            return 0;
        }
        Sleep(2000);
    }
    return 0;
}

// --- NEW DXGI Desktop Duplication based recorder ---
BOOL LaunchRecorderInSession(DWORD sessionId)
{
    LogLine(L"Trying to get user token...");

    HANDLE hUser = nullptr;
    for (int i = 0; i < 30; ++i) {
        if (WTSQueryUserToken(sessionId, &hUser)) break;
        Sleep(1000);
    }
    if (!hUser) {
        wchar_t m[128];
        StringCchPrintfW(m, 128, L"WTSQueryUserToken failed after retries ec=%lu", GetLastError());
        LogLine(m);
        return FALSE;
    }

    LPTSTR userNameBuf = nullptr;
    DWORD userNameLen = 0;
    BOOL gotUserName = WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sessionId,
                                                   WTSUserName, &userNameBuf, &userNameLen)
                       && userNameBuf && *userNameBuf;

    HANDLE hPrimary = nullptr;
    if (!DuplicateTokenEx(hUser, TOKEN_ALL_ACCESS, nullptr,
                          SecurityImpersonation, TokenPrimary, &hPrimary)) {
        wchar_t m[128];
        StringCchPrintfW(m, 128, L"DuplicateTokenEx failed ec=%lu", GetLastError());
        LogLine(m);
        CloseHandle(hUser);
        if (gotUserName) WTSFreeMemory(userNameBuf);
        return FALSE;
    }
    CloseHandle(hUser);

    if (!SetTokenInformation(hPrimary, TokenSessionId, &sessionId, sizeof(sessionId))) {
        wchar_t m[128];
        StringCchPrintfW(m, 128, L"SetTokenInformation failed ec=%lu", GetLastError());
        LogLine(m);
        CloseHandle(hPrimary);
        if (gotUserName) WTSFreeMemory(userNameBuf);
        return FALSE;
    }

    PROFILEINFOW pi = {};
    pi.dwSize = sizeof(pi);
    wchar_t emptyUserName[1] = L"";
    if (gotUserName) pi.lpUserName = userNameBuf;
    else             pi.lpUserName = emptyUserName;

    if (!LoadUserProfileW(hPrimary, &pi)) {
        wchar_t m[256];
        StringCchPrintfW(m, 256, L"LoadUserProfile failed ec=%lu", GetLastError());
        LogLine(m);
    }
    if (gotUserName) WTSFreeMemory(userNameBuf);

    LPVOID env = nullptr;
    if (!CreateEnvironmentBlock(&env, hPrimary, FALSE)) {
        wchar_t m[128];
        StringCchPrintfW(m, 128, L"CreateEnvironmentBlock failed ec=%lu", GetLastError());
        LogLine(m);
        env = nullptr;
    }

    // Start DXGI capture thread
    auto CaptureThread = [](LPVOID) -> DWORD {
        LogLine(L"DXGI capture thread starting...");
        IDXGIFactory1* pFactory = nullptr;
        if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1), (void**)&pFactory))) {
            LogLine(L"CreateDXGIFactory1 failed"); return 0;
        }

        IDXGIAdapter1* pAdapter = nullptr;
        pFactory->EnumAdapters1(0, &pAdapter);
        ID3D11Device* pDevice = nullptr;
        ID3D11DeviceContext* pContext = nullptr;
        if (FAILED(D3D11CreateDevice(pAdapter, D3D_DRIVER_TYPE_UNKNOWN, NULL, 0, NULL, 0,
                                     D3D11_SDK_VERSION, &pDevice, NULL, &pContext))) {
            LogLine(L"D3D11CreateDevice failed"); return 0;
        }

        IDXGIOutput* pOutput = nullptr;
        pAdapter->EnumOutputs(0, &pOutput);
        IDXGIOutput1* pOutput1 = nullptr;
        pOutput->QueryInterface(__uuidof(IDXGIOutput1), (void**)&pOutput1);

        IDXGIOutputDuplication* pDeskDupl = nullptr;
        if (FAILED(pOutput1->DuplicateOutput(pDevice, &pDeskDupl))) {
            LogLine(L"DuplicateOutput failed"); return 0;
        }

        // Launch ffmpeg to encode raw BGRA frames
        SECURITY_ATTRIBUTES sa = { sizeof(sa), NULL, TRUE };
        HANDLE hRead = NULL, hWrite = NULL;
        CreatePipe(&hRead, &hWrite, &sa, 0);
        STARTUPINFOW si = { sizeof(si) };
        si.hStdInput = hRead;
        si.dwFlags |= STARTF_USESTDHANDLES;
        PROCESS_INFORMATION pi = {};
        std::wstring cmd = L"\"" + std::wstring(RECORDER_PATH) +
                           L"\" -y -f rawvideo -pixel_format bgra -video_size 1920x1080 "
                           L"-framerate 30 -i - -c:v libx264 \"" +
                           std::wstring(REC_OUTPUT) + L"\"";
        if (!CreateProcessW(NULL, &cmd[0], NULL, NULL, TRUE,
                            CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
            LogLine(L"Failed to spawn ffmpeg"); return 0;
        }

        for (;;) {
            DXGI_OUTDUPL_FRAME_INFO fi;
            IDXGIResource* pRes = nullptr;
            if (FAILED(pDeskDupl->AcquireNextFrame(500, &fi, &pRes))) continue;
            ID3D11Texture2D* pTex = nullptr;
            pRes->QueryInterface(__uuidof(ID3D11Texture2D), (void**)&pTex);

            D3D11_MAPPED_SUBRESOURCE map;
            if (SUCCEEDED(pContext->Map(pTex, 0, D3D11_MAP_READ, 0, &map))) {
                DWORD written;
                WriteFile(hWrite, map.pData, map.RowPitch * 1080, &written, NULL);
                pContext->Unmap(pTex, 0);
            }
            pTex->Release(); pRes->Release();
            pDeskDupl->ReleaseFrame();
        }
        CloseHandle(hWrite);
        return 0;
    };
    CreateThread(NULL, 0, CaptureThread, NULL, 0, NULL);
    LogLine(L"DXGI capture thread launched");

    g_RecordingSessionId = sessionId;
    g_ShouldPollSession  = TRUE;
    DWORD *sidCopy       = new DWORD(sessionId);
    DWORD tid            = 0;
    g_RecPollThread = CreateThread(nullptr, 0, PollSessionStateThread, sidCopy, 0, &tid);

    CloseHandle(hPrimary);
    if (env) DestroyEnvironmentBlock(env);
    return TRUE;
}

DWORD FindFirstRdpSession()
{
    PWTS_SESSION_INFO pInfo = nullptr;
    DWORD count = 0;
    DWORD result = 0xFFFFFFFF;

    if (WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &pInfo, &count)) {
        wchar_t buf[256];
        for (DWORD i = 0; i < count; ++i) {
            if (pInfo[i].State == WTSActive) {
                LPTSTR protoBuf = nullptr; DWORD bytes = 0;
                if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE,
                    pInfo[i].SessionId,
                    WTSClientProtocolType,
                    &protoBuf, &bytes)) {
                    USHORT proto = *(USHORT*)protoBuf;
                    StringCchPrintfW(buf, 256, L"SessionId=%lu State=WTSActive ProtocolType=%u", pInfo[i].SessionId, proto);
                    LogLine(buf);
                    WTSFreeMemory(protoBuf);
                    if (proto == 2) { // 2 = RDP
                        result = pInfo[i].SessionId;
                        break;
                    }
                }
            }
        }
        WTSFreeMemory(pInfo);
    }
    return result;
}

DWORD WINAPI ServiceCtrlHandlerEx(DWORD ctrl, DWORD eventType, LPVOID eventData, LPVOID)
{
    switch (ctrl)
    {
    case SERVICE_CONTROL_STOP:
        StopRecorder();
        g_ServiceStatus.dwCurrentState = SERVICE_STOPPED;
        SetServiceStatus(g_StatusHandle, &g_ServiceStatus);
        LogLine(L"Service stopped");
        return NO_ERROR;

    case SERVICE_CONTROL_SESSIONCHANGE:
    {
        DWORD sid = (DWORD)(ULONG_PTR)eventData;
        wchar_t buf[256];
        StringCchPrintfW(buf, 256, L"SESSIONCHANGE event=%u sid=%u", eventType, sid);
        LogLine(buf);

        if (eventType == WTS_SESSION_LOGON) {
            LogLine(L">>> LOGON detected, searching for RDP session...");
            Sleep(1000);
            DWORD rdp = FindFirstRdpSession();
            if (rdp != 0xFFFFFFFF)
                LaunchRecorderInSession(rdp);
            else
                LogLine(L"No RDP session found.");
        }
        else if (eventType == WTS_SESSION_LOGOFF || eventType == WTS_SESSION_DISCONNECT) {
            LogLine(L">>> SESSION END detected — stopping recorder <<<");
            StopRecorder();
        }
    }
    return NO_ERROR;
    }
    return ERROR_CALL_NOT_IMPLEMENTED;
}

void WINAPI ServiceMain(DWORD, LPWSTR*)
{
    g_StatusHandle = RegisterServiceCtrlHandlerExW(SERVICE_NAME, ServiceCtrlHandlerEx, nullptr);
    if (!g_StatusHandle) return;

    g_ServiceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_ServiceStatus.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SESSIONCHANGE;
    g_ServiceStatus.dwCurrentState = SERVICE_START_PENDING;
    SetServiceStatus(g_StatusHandle, &g_ServiceStatus);

    LogLine(L"Service starting");

    g_ServiceStatus.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(g_StatusHandle, &g_ServiceStatus);
    LogLine(L"Service running");

    if (GetFileAttributesW(MANUAL_TRIGGER) != INVALID_FILE_ATTRIBUTES) {
        LogLine(L"Manual trigger file found — starting recorder in current console session");
        DWORD sid = WTSGetActiveConsoleSessionId();
        LaunchRecorderInSession(sid);
    }

    while (g_ServiceStatus.dwCurrentState == SERVICE_RUNNING) {
        Sleep(1000);
    }
}

int wmain()
{
    SERVICE_TABLE_ENTRYW table[] = {
        { (LPWSTR)SERVICE_NAME, (LPSERVICE_MAIN_FUNCTIONW)ServiceMain },
        { nullptr, nullptr }
    };
    if (!StartServiceCtrlDispatcherW(table)) {
        MessageBoxW(nullptr, L"Running QCMREC manually (debug only). Install as service for real use.", SERVICE_NAME, MB_OK);
    }
    return 0;
}
