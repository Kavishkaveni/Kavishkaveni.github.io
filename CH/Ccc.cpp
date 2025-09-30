#define _WIN32_WINNT 0x0600
#include <windows.h>
#include <wtsapi32.h>
#include <strsafe.h>
#include <userenv.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <string>

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
SERVICE_STATUS_HANDLE g_StatusHandle  = nullptr;
HANDLE                g_PollThread    = nullptr;
HANDLE                g_CaptureThread = nullptr;
volatile BOOL         g_ShouldPoll    = FALSE;
volatile BOOL         g_ShouldCapture = FALSE;

#define SERVICE_NAME   L"QCMREC"
#define LOG_FILE       L"C:\\PAM\\qcmrec.log"
#define RECORD_PATH    L"C:\\PAM\\recordings\\session.mp4"

void LogLine(LPCWSTR msg)
{
    HANDLE f = CreateFileW(LOG_FILE, FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
        OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;

    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t buf[1024];
    StringCchPrintfW(buf, 1024, L"%04d-%02d-%02d %02d:%02d:%02d  %s\r\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, msg);
    DWORD written = 0;
    WriteFile(f, buf, (DWORD)(wcslen(buf) * sizeof(wchar_t)), &written, nullptr);
    CloseHandle(f);
}

void StopRecorder()
{
    g_ShouldPoll = FALSE;
    g_ShouldCapture = FALSE;
    if (g_PollThread)    { WaitForSingleObject(g_PollThread, 5000); CloseHandle(g_PollThread);    g_PollThread = nullptr; }
    if (g_CaptureThread) { WaitForSingleObject(g_CaptureThread,5000); CloseHandle(g_CaptureThread); g_CaptureThread=nullptr; }
    LogLine(L"Recording stopped");
}

DWORD WINAPI PollSessionStateThread(LPVOID param)
{
    DWORD sessionId = *(DWORD*)param; delete (DWORD*)param;
    while (g_ShouldPoll) {
        WTS_CONNECTSTATE_CLASS state = WTSDisconnected;
        LPTSTR pState = nullptr; DWORD bytes = 0;
        if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sessionId, WTSConnectState, &pState, &bytes) && pState) {
            state = *(WTS_CONNECTSTATE_CLASS*)pState;
            WTSFreeMemory(pState);
        }
        if (state != WTSActive) {
            wchar_t m[128];
            StringCchPrintfW(m,128,L"Session %lu became inactive (state=%d).",sessionId,(int)state);
            LogLine(m);
            StopRecorder();
            return 0;
        }
        Sleep(2000);
    }
    return 0;
}

// ======== DXGI CAPTURE THREAD ========
DWORD WINAPI CaptureThreadProc(LPVOID)
{
    LogLine(L"DXGI capture thread starting...");
    IDXGIFactory1* pFactory=nullptr; IDXGIAdapter1* pAdapter=nullptr; IDXGIOutput* pOutput=nullptr;
    IDXGIOutput1* pOutput1=nullptr; IDXGIOutputDuplication* pDup=nullptr;
    ID3D11Device* pDevice=nullptr; ID3D11DeviceContext* pCtx=nullptr;

    if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1),(void**)&pFactory))) { LogLine(L"CreateDXGIFactory1 failed"); return 0; }
    if (FAILED(pFactory->EnumAdapters1(0,&pAdapter)))                          { LogLine(L"EnumAdapters1 failed"); return 0; }
    if (FAILED(pAdapter->EnumOutputs(0,&pOutput)))                             { LogLine(L"EnumOutputs failed"); return 0; }
    if (FAILED(pOutput->QueryInterface(__uuidof(IDXGIOutput1),(void**)&pOutput1))) { LogLine(L"QI IDXGIOutput1 failed"); return 0; }
    if (FAILED(D3D11CreateDevice(pAdapter,D3D_DRIVER_TYPE_UNKNOWN,nullptr,0,nullptr,0,D3D11_SDK_VERSION,&pDevice,nullptr,&pCtx))) { LogLine(L"D3D11CreateDevice failed"); return 0; }
    if (FAILED(pOutput1->DuplicateOutput(pDevice,&pDup)))                      { LogLine(L"DuplicateOutput failed"); return 0; }

    DXGI_OUTPUT_DESC od; pOutput->GetDesc(&od);
    RECT rc = od.DesktopCoordinates; int W=rc.right-rc.left, H=rc.bottom-rc.top;

    // Launch ffmpeg
    wchar_t cmd[1024];
    swprintf(cmd,1024,L"ffmpeg -y -f rawvideo -pixel_format bgra -video_size %dx%d -framerate 15 -i - -c:v libx264 \"%s\"",W,H,RECORD_PATH);
    SECURITY_ATTRIBUTES sa={sizeof(sa),NULL,TRUE}; HANDLE r=NULL,w=NULL;
    CreatePipe(&r,&w,&sa,0);
    STARTUPINFOW si={sizeof(si)}; si.hStdInput=r; si.dwFlags|=STARTF_USESTDHANDLES;
    PROCESS_INFORMATION pi={};
    if(!CreateProcessW(nullptr,cmd,nullptr,nullptr,TRUE,CREATE_NO_WINDOW,nullptr,nullptr,&si,&pi)){
        LogLine(L"Failed to spawn ffmpeg"); return 0;
    }
    CloseHandle(r);

    g_ShouldCapture=TRUE;
    while(g_ShouldCapture){
        DXGI_OUTDUPL_FRAME_INFO fi={}; IDXGIResource* pRes=nullptr;
        if(FAILED(pDup->AcquireNextFrame(500,&fi,&pRes))) continue;
        ID3D11Texture2D* pTex=nullptr; pRes->QueryInterface(__uuidof(ID3D11Texture2D),(void**)&pTex);
        D3D11_TEXTURE2D_DESC d; pTex->GetDesc(&d); d.Usage=D3D11_USAGE_STAGING; d.BindFlags=0; d.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
        ID3D11Texture2D* pCopy=nullptr; pDevice->CreateTexture2D(&d,nullptr,&pCopy);
        pCtx->CopyResource(pCopy,pTex);
        D3D11_MAPPED_SUBRESOURCE m;
        if(SUCCEEDED(pCtx->Map(pCopy,0,D3D11_MAP_READ,0,&m))){
            DWORD written; WriteFile(w,m.pData,d.Width*d.Height*4,&written,NULL);
            pCtx->Unmap(pCopy,0);
        }
        pCopy->Release(); pTex->Release(); pDup->ReleaseFrame(); pRes->Release();
    }
    CloseHandle(w);
    LogLine(L"DXGI thread exiting");
    return 0;
}

// ======== START CAPTURE IN SESSION ========
BOOL LaunchRecorderInSession(DWORD sessionId)
{
    LogLine(L"Trying to get user token...");
    HANDLE hUser=nullptr;
    for(int i=0;i<30 && !WTSQueryUserToken(sessionId,&hUser);++i) Sleep(1000);
    if(!hUser){ LogLine(L"Cannot get user token"); return FALSE; }

    HANDLE hPrimary=nullptr;
    if(!DuplicateTokenEx(hUser,TOKEN_ALL_ACCESS,nullptr,SecurityImpersonation,TokenPrimary,&hPrimary)){
        LogLine(L"DuplicateTokenEx failed"); CloseHandle(hUser); return FALSE; }
    CloseHandle(hUser);
    SetTokenInformation(hPrimary,TokenSessionId,&sessionId,sizeof(sessionId));

    PROFILEINFOW pi={}; pi.dwSize=sizeof(pi); pi.lpUserName=L"";
    LoadUserProfileW(hPrimary,&pi);
    CreateEnvironmentBlock(nullptr,hPrimary,FALSE);

    // Show popup in that user session
    WTSPostMessageW(WTS_CURRENT_SERVER_HANDLE,sessionId,L"Recording started",L"QCMREC",MB_OK,0);

    g_CaptureThread=CreateThread(nullptr,0,CaptureThreadProc,nullptr,0,nullptr);
    g_ShouldPoll=TRUE;
    DWORD* sid=new DWORD(sessionId);
    g_PollThread=CreateThread(nullptr,0,PollSessionStateThread,sid,0,nullptr);

    return TRUE;
}

// ======== FIND FIRST ACTIVE RDP ========
DWORD FindFirstRdpSession()
{
    PWTS_SESSION_INFO pInfo=nullptr; DWORD count=0,result=0xFFFFFFFF;
    if(WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE,0,1,&pInfo,&count)){
        for(DWORD i=0;i<count;i++){
            if(pInfo[i].State==WTSActive){
                LPTSTR protoBuf=nullptr; DWORD b=0;
                if(WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE,pInfo[i].SessionId,WTSClientProtocolType,&protoBuf,&b)){
                    if(*(USHORT*)protoBuf==2){ result=pInfo[i].SessionId; WTSFreeMemory(protoBuf); break; }
                    WTSFreeMemory(protoBuf);
                }
            }
        }
        WTSFreeMemory(pInfo);
    }
    return result;
}

// ======== SERVICE CTRL ========
DWORD WINAPI ServiceCtrlHandlerEx(DWORD ctrl,DWORD eventType,LPVOID,LPVOID){
    if(ctrl==SERVICE_CONTROL_STOP){
        StopRecorder(); g_ServiceStatus.dwCurrentState=SERVICE_STOPPED; SetServiceStatus(g_StatusHandle,&g_ServiceStatus); return NO_ERROR;
    }
    if(ctrl==SERVICE_CONTROL_SESSIONCHANGE){
        if(eventType==WTS_SESSION_LOGON){
            LogLine(L">>> LOGON detected, searching for RDP...");
            Sleep(1000);
            DWORD r=FindFirstRdpSession(); if(r!=0xFFFFFFFF) LaunchRecorderInSession(r);
            else LogLine(L"No RDP session found");
        }
        if(eventType==WTS_SESSION_LOGOFF||eventType==WTS_SESSION_DISCONNECT){ StopRecorder(); }
    }
    return NO_ERROR;
}

// ======== MAIN ========
void WINAPI ServiceMain(DWORD,LPWSTR*){
    g_StatusHandle=RegisterServiceCtrlHandlerExW(SERVICE_NAME,ServiceCtrlHandlerEx,nullptr);
    g_ServiceStatus.dwServiceType=SERVICE_WIN32_OWN_PROCESS;
    g_ServiceStatus.dwControlsAccepted=SERVICE_ACCEPT_STOP|SERVICE_ACCEPT_SESSIONCHANGE;
    g_ServiceStatus.dwCurrentState=SERVICE_START_PENDING; SetServiceStatus(g_StatusHandle,&g_ServiceStatus);
    LogLine(L"Service starting");
    g_ServiceStatus.dwCurrentState=SERVICE_RUNNING; SetServiceStatus(g_StatusHandle,&g_ServiceStatus);
    LogLine(L"Service running");
    while(g_ServiceStatus.dwCurrentState==SERVICE_RUNNING) Sleep(1000);
}

int wmain(){
    SERVICE_TABLE_ENTRYW t[]={{(LPWSTR)SERVICE_NAME,(LPSERVICE_MAIN_FUNCTIONW)ServiceMain},{nullptr,nullptr}};
    if(!StartServiceCtrlDispatcherW(t)){
        MessageBoxW(nullptr,L"Run as service",L"QCMREC",MB_OK);
    }
    return 0;
}
