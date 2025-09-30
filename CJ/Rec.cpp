#define _WIN32_WINNT 0x0602   // Windows 8+ needed for Desktop Duplication
#include <windows.h>
#include <wtsapi32.h>
#include <strsafe.h>
#include <userenv.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <string>
#include <memory>

#pragma comment(lib,"wtsapi32.lib")
#pragma comment(lib,"advapi32.lib")
#pragma comment(lib,"userenv.lib")
#pragma comment(lib,"d3d11.lib")
#pragma comment(lib,"dxgi.lib")

SERVICE_STATUS        g_ServiceStatus = {};
SERVICE_STATUS_HANDLE g_StatusHandle = nullptr;
HANDLE                g_RecPollThread = nullptr;
HANDLE                g_CaptureThread = nullptr;
volatile BOOL         g_ShouldPollSession = FALSE;
volatile BOOL         g_ShouldCapture = FALSE;

#define SERVICE_NAME   L"QCMREC"
#define LOG_FILE       L"C:\\PAM\\qcmrec.log"
#define RECORDER_PATH  L"C:\\PAM\\ffmpeg.exe"

void LogLine(const wchar_t* msg) {
    HANDLE f = CreateFileW(LOG_FILE, FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;
    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t buf[1024];
    StringCchPrintfW(buf, 1024, L"%04d-%02d-%02d %02d:%02d:%02d  %s\r\n",
                     st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, msg);
    DWORD written = 0;
    WriteFile(f, buf, (DWORD)(wcslen(buf)*sizeof(wchar_t)), &written, nullptr);
    CloseHandle(f);
}

void StopRecorder() {
    g_ShouldPollSession = FALSE;
    g_ShouldCapture = FALSE;
    if (g_RecPollThread) { WaitForSingleObject(g_RecPollThread, 5000); CloseHandle(g_RecPollThread); g_RecPollThread=nullptr; }
    if (g_CaptureThread) { WaitForSingleObject(g_CaptureThread, 5000); CloseHandle(g_CaptureThread); g_CaptureThread=nullptr; }
    LogLine(L"Recording stopped");
}

DWORD WINAPI PollSessionStateThread(LPVOID param) {
    DWORD sid = *(DWORD*)param; delete (DWORD*)param;
    while (g_ShouldPollSession) {
        WTS_CONNECTSTATE_CLASS state = WTSDisconnected;
        LPTSTR pState=nullptr; DWORD bytes=0;
        if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, sid, WTSConnectState, &pState, &bytes) && pState) {
            state = *(WTS_CONNECTSTATE_CLASS*)pState; WTSFreeMemory(pState);
        }
        if (state != WTSActive) { LogLine(L"Session not active; stopping recorder"); StopRecorder(); return 0; }
        Sleep(2000);
    }
    return 0;
}

// ---------------- DXGI capture ------------------
struct CaptureCtx { HANDLE token; std::wstring outFile; };

DWORD WINAPI CaptureThreadProc(LPVOID param) {
    std::unique_ptr<CaptureCtx> ctx((CaptureCtx*)param);
    LogLine(L"DXGI capture thread starting...");
    if (!ImpersonateLoggedOnUser(ctx->token)) { LogLine(L"ImpersonateLoggedOnUser failed"); return 0; }

    IDXGIFactory1* f= nullptr; if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1),(void**)&f))){LogLine(L"CreateDXGIFactory1 failed"); RevertToSelf(); return 0;}
    IDXGIAdapter1* a=nullptr;  f->EnumAdapters1(0,&a);
    ID3D11Device* dev=nullptr; ID3D11DeviceContext* ctxImm=nullptr;
    if (FAILED(D3D11CreateDevice(a,D3D_DRIVER_TYPE_UNKNOWN,NULL, D3D11_CREATE_DEVICE_BGRA_SUPPORT, NULL,0,D3D11_SDK_VERSION,&dev,NULL,&ctxImm))){LogLine(L"D3D11CreateDevice failed"); f->Release(); RevertToSelf(); return 0;}
    IDXGIOutput* out=nullptr;  a->EnumOutputs(0,&out);
    IDXGIOutput1* out1=nullptr; out->QueryInterface(__uuidof(IDXGIOutput1),(void**)&out1);
    IDXGIOutputDuplication* dupl=nullptr;
    if (FAILED(out1->DuplicateOutput(dev,&dupl))){LogLine(L"DuplicateOutput failed"); out1->Release(); out->Release(); a->Release(); f->Release(); dev->Release(); ctxImm->Release(); RevertToSelf(); return 0;}

    DXGI_OUTPUT_DESC od={}; out->GetDesc(&od);
    int w = od.DesktopCoordinates.right - od.DesktopCoordinates.left;
    int h = od.DesktopCoordinates.bottom - od.DesktopCoordinates.top;

    SECURITY_ATTRIBUTES sa{sizeof(sa),NULL,TRUE}; HANDLE hR=NULL,hW=NULL; CreatePipe(&hR,&hW,&sa,0);
    wchar_t cmd[1024]; StringCchPrintfW(cmd,1024,L"\"%s\" -y -f rawvideo -pixel_format bgra -video_size %dx%d -framerate 15 -i - -c:v libx264 -preset ultrafast -crf 23 \"%s\"",
                                       RECORDER_PATH,w,h,ctx->outFile.c_str());
    STARTUPINFOW si{sizeof(si)}; si.hStdInput=hR; si.dwFlags|=STARTF_USESTDHANDLES; si.lpDesktop=(LPWSTR)L"winsta0\\default";
    PROCESS_INFORMATION pi{};
    if(!CreateProcessAsUserW(ctx->token,NULL,cmd,NULL,NULL,TRUE,CREATE_NO_WINDOW,NULL,NULL,&si,&pi)){LogLine(L"CreateProcessAsUserW(ffmpeg) failed"); CloseHandle(hR); CloseHandle(hW); return 0;}
    CloseHandle(hR);

    g_ShouldCapture=TRUE;
    while(g_ShouldCapture){
        DXGI_OUTDUPL_FRAME_INFO fi{}; IDXGIResource* res=nullptr;
        HRESULT hr=dupl->AcquireNextFrame(500,&fi,&res);
        if(hr==DXGI_ERROR_WAIT_TIMEOUT) continue;
        if(FAILED(hr)){LogLine(L"AcquireNextFrame failed"); break;}
        ID3D11Texture2D* tex=nullptr; res->QueryInterface(__uuidof(ID3D11Texture2D),(void**)&tex);

        D3D11_TEXTURE2D_DESC d={}; tex->GetDesc(&d);
        D3D11_TEXTURE2D_DESC s=d; s.Usage=D3D11_USAGE_STAGING; s.BindFlags=0; s.MiscFlags=0; s.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
        ID3D11Texture2D* stage=nullptr; dev->CreateTexture2D(&s,nullptr,&stage);
        ctxImm->CopyResource(stage,tex);
        D3D11_MAPPED_SUBRESOURCE m{}; if(SUCCEEDED(ctxImm->Map(stage,0,D3D11_MAP_READ,0,&m))){
            for(int y=0;y<(int)d.Height && g_ShouldCapture;++y){
                DWORD wrote; WriteFile(hW,(BYTE*)m.pData+y*m.RowPitch,d.Width*4,&wrote,NULL);
            }
            ctxImm->Unmap(stage,0);
        }
        stage->Release(); tex->Release(); res->Release(); dupl->ReleaseFrame();
    }
    CloseHandle(hW);
    WaitForSingleObject(pi.hProcess,3000); CloseHandle(pi.hThread); CloseHandle(pi.hProcess);

    dupl->Release(); out1->Release(); out->Release(); a->Release(); f->Release(); dev->Release(); ctxImm->Release();
    RevertToSelf(); LogLine(L"DXGI capture thread exiting"); return 0;
}

BOOL LaunchRecorderInSession(DWORD sid){
    LogLine(L"Trying to get user token...");
    HANDLE hUser=NULL; for(int i=0;i<30;++i){ if(WTSQueryUserToken(sid,&hUser)) break; Sleep(1000);}
    if(!hUser){LogLine(L"WTSQueryUserToken failed"); return FALSE;}
    HANDLE hPrimary=NULL;
    if(!DuplicateTokenEx(hUser,TOKEN_ALL_ACCESS,NULL,SecurityImpersonation,TokenPrimary,&hPrimary)){LogLine(L"DuplicateTokenEx failed"); CloseHandle(hUser); return FALSE;}
    CloseHandle(hUser);
    if(!SetTokenInformation(hPrimary,TokenSessionId,&sid,sizeof(sid))){LogLine(L"SetTokenInformation failed"); CloseHandle(hPrimary); return FALSE;}
    PROFILEINFOW pi{};pi.dwSize=sizeof(pi);pi.lpUserName=L"";LoadUserProfileW(hPrimary,&pi);

    std::wstring out=L"C:\\PAM\\recordings\\session_"+std::to_wstring(sid)+L".mp4";
    CaptureCtx* ctx=new CaptureCtx{hPrimary,out};
    g_CaptureThread=CreateThread(NULL,0,CaptureThreadProc,ctx,0,NULL);
    g_ShouldPollSession=TRUE; DWORD* sCopy=new DWORD(sid);
    g_RecPollThread=CreateThread(NULL,0,PollSessionStateThread,sCopy,0,NULL);
    return TRUE;
}

DWORD FindFirstRdpSession(){
    PWTS_SESSION_INFO p=nullptr;DWORD c=0,res=0xFFFFFFFF;
    if(WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE,0,1,&p,&c)){
        for(DWORD i=0;i<c;++i){ if(p[i].State==WTSActive){
            LPTSTR proto=nullptr;DWORD b=0; if(WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE,p[i].SessionId,WTSClientProtocolType,&proto,&b)){
                if(*(USHORT*)proto==2){res=p[i].SessionId; WTSFreeMemory(proto); break;}
                WTSFreeMemory(proto);
            }}}
        WTSFreeMemory(p);
    }
    return res;
}

DWORD WINAPI ServiceCtrlHandlerEx(DWORD ctrl,DWORD evt,LPVOID data,LPVOID){
    switch(ctrl){
    case SERVICE_CONTROL_STOP:StopRecorder();g_ServiceStatus.dwCurrentState=SERVICE_STOPPED;SetServiceStatus(g_StatusHandle,&g_ServiceStatus);LogLine(L"Service stopped");return NO_ERROR;
    case SERVICE_CONTROL_SESSIONCHANGE:{
        DWORD sid=(DWORD)(ULONG_PTR)data;
        if(evt==WTS_SESSION_LOGON){LogLine(L"LOGON detected");Sleep(1000);DWORD r=FindFirstRdpSession();if(r!=0xFFFFFFFF)LaunchRecorderInSession(r);}
        else if(evt==WTS_SESSION_LOGOFF||evt==WTS_SESSION_DISCONNECT){StopRecorder();}
    }return NO_ERROR;}
    return ERROR_CALL_NOT_IMPLEMENTED;
}

void WINAPI ServiceMain(DWORD,LPWSTR*){
    g_StatusHandle=RegisterServiceCtrlHandlerExW(SERVICE_NAME,ServiceCtrlHandlerEx,nullptr);
    if(!g_StatusHandle)return;
    g_ServiceStatus.dwServiceType=SERVICE_WIN32_OWN_PROCESS;
    g_ServiceStatus.dwControlsAccepted=SERVICE_ACCEPT_STOP|SERVICE_ACCEPT_SESSIONCHANGE;
    g_ServiceStatus.dwCurrentState=SERVICE_START_PENDING;
    SetServiceStatus(g_StatusHandle,&g_ServiceStatus);
    LogLine(L"Service starting");
    g_ServiceStatus.dwCurrentState=SERVICE_RUNNING;SetServiceStatus(g_StatusHandle,&g_ServiceStatus);
    LogLine(L"Service running");
    while(g_ServiceStatus.dwCurrentState==SERVICE_RUNNING)Sleep(1000);
}

int wmain(){
    SERVICE_TABLE_ENTRYW t[]={{(LPWSTR)SERVICE_NAME,(LPSERVICE_MAIN_FUNCTIONW)ServiceMain},{nullptr,nullptr}};
    if(!StartServiceCtrlDispatcherW(t)){MessageBoxW(nullptr,L"Run as service","QCMREC",MB_OK);}
    return 0;
}
