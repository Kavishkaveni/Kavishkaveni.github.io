// qcmrec_dxgi.cpp
// DXGI Desktop recorder with manual mode and Windows Service mode

#define _SILENCE_CXX17_CODECVT_HEADER_DEPRECATION_WARNING
#define WINVER 0x0601
#define _WIN32_WINNT 0x0601
#define NTDDI_VERSION NTDDI_WIN7

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <winsvc.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <d3d11.h>
#include <dxgi.h>
#include <dxgi1_2.h>
#include <wincodec.h>
#include <strsafe.h>
#include <conio.h>
#include <atomic>
#include <chrono>
#include <thread>
#include <wrl/client.h>
#include <fstream>
#include <sstream>
#include <locale>
#include <codecvt>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "dxguid.lib")
#pragma comment(lib, "windowscodecs.lib")

// Globals
std::wstring g_uuid;
std::wstring g_session;

// ----------------- Helpers -----------------
static void EnsureRecFolder() { CreateDirectoryW(L"C:\\REC", nullptr); }

// ----------------- Capture Loop -----------------
static void RunCaptureLoop(std::atomic<bool>& running)
{
    EnsureRecFolder();
    // NOTE: MessageBox will block service start — you may comment out if running as service
    MessageBoxW(nullptr, L"Recording started.\n(Stops when CJ disconnects or ENTER in manual mode)", L"QCMREC", MB_OK);

    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(hr)) return;

    Microsoft::WRL::ComPtr<IWICImagingFactory> wic;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic)))) { CoUninitialize(); return; }

    D3D_FEATURE_LEVEL flOut;
    Microsoft::WRL::ComPtr<ID3D11Device> device;
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
    if (FAILED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, &device, &flOut, &context)))) { CoUninitialize(); return; }

    Microsoft::WRL::ComPtr<IDXGIDevice> dxgiDevice;
    device.As(&dxgiDevice);
    Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
    dxgiDevice->GetAdapter(&adapter);
    Microsoft::WRL::ComPtr<IDXGIOutput> output;
    if (FAILED(adapter->EnumOutputs(0, &output))) { CoUninitialize(); return; }
    Microsoft::WRL::ComPtr<IDXGIOutput1> output1;
    output.As(&output1);

    Microsoft::WRL::ComPtr<IDXGIOutputDuplication> dupl;
    if (FAILED(output1->DuplicateOutput(device.Get(), &dupl))) { CoUninitialize(); return; }

    Microsoft::WRL::ComPtr<ID3D11Texture2D> staging;
    UINT width = 0, height = 0, pitch = 0;
    int frameIndex = 0;
    const int targetFps = 10;
    const int frameIntervalMs = 1000 / targetFps;
    Microsoft::WRL::ComPtr<IMFSinkWriter> writer;
    DWORD streamIndex = 0;

    while (running)
    {
        DXGI_OUTDUPL_FRAME_INFO fi{};
        Microsoft::WRL::ComPtr<IDXGIResource> res;
        hr = dupl->AcquireNextFrame(500, &fi, &res);
        if (hr == DXGI_ERROR_WAIT_TIMEOUT) continue;
        if (hr == DXGI_ERROR_ACCESS_LOST) { dupl->ReleaseFrame(); dupl.Reset(); output1->DuplicateOutput(device.Get(), &dupl); continue; }
        if (FAILED(hr)) break;

        Microsoft::WRL::ComPtr<ID3D11Texture2D> frameTex; res.As(&frameTex);

        if (!staging)
        {
            D3D11_TEXTURE2D_DESC desc{}; frameTex->GetDesc(&desc);
            width = desc.Width; height = desc.Height;

            D3D11_TEXTURE2D_DESC s{}; s.Width = width; s.Height = height; s.MipLevels = 1; s.ArraySize = 1;
            s.Format = DXGI_FORMAT_B8G8R8A8_UNORM; s.SampleDesc.Count = 1; s.Usage = D3D11_USAGE_STAGING; s.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
            if (FAILED(device->CreateTexture2D(&s, nullptr, &staging))) { dupl->ReleaseFrame(); break; }

            pitch = width * 4;
            MFStartup(MF_VERSION);

            wchar_t videoPath[MAX_PATH];
            SYSTEMTIME st; GetLocalTime(&st);
            StringCchPrintfW(videoPath, MAX_PATH, L"C:\\REC\\%s_%s_%04u%02u%02u_%02u%02u%02u.mp4", g_uuid.c_str(), g_session.c_str(), st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

            if (FAILED(MFCreateSinkWriterFromURL(videoPath, nullptr, nullptr, &writer))) { dupl->ReleaseFrame(); break; }

            Microsoft::WRL::ComPtr<IMFMediaType> outType; MFCreateMediaType(&outType);
            outType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
            outType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
            outType->SetUINT32(MF_MT_AVG_BITRATE, 8000000);
            outType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
            MFSetAttributeSize(outType.Get(), MF_MT_FRAME_SIZE, width, height);
            MFSetAttributeRatio(outType.Get(), MF_MT_FRAME_RATE, targetFps, 1);
            MFSetAttributeRatio(outType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
            writer->AddStream(outType.Get(), &streamIndex);

            Microsoft::WRL::ComPtr<IMFMediaType> inType; MFCreateMediaType(&inType);
            inType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
            inType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
            MFSetAttributeSize(inType.Get(), MF_MT_FRAME_SIZE, width, height);
            MFSetAttributeRatio(inType.Get(), MF_MT_FRAME_RATE, targetFps, 1);
            MFSetAttributeRatio(inType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
            writer->SetInputMediaType(streamIndex, inType.Get(), nullptr);
            writer->BeginWriting();
        }

        context->CopyResource(staging.Get(), frameTex.Get());
        D3D11_MAPPED_SUBRESOURCE map{};
        hr = context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &map);
        if (SUCCEEDED(hr))
        {
            Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer; MFCreateMemoryBuffer(map.RowPitch * height, &buffer);
            BYTE* dst = nullptr; DWORD maxLen = 0;
            buffer->Lock(&dst, &maxLen, nullptr);
            BYTE* src = (BYTE*)map.pData;
            for (UINT y = 0; y < height; ++y) memcpy(dst + y * pitch, src + (height - 1 - y) * map.RowPitch, pitch);
            buffer->Unlock(); buffer->SetCurrentLength(pitch * height);

            Microsoft::WRL::ComPtr<IMFSample> sample; MFCreateSample(&sample);
            sample->AddBuffer(buffer.Get());
            LONGLONG pts = frameIndex * 10000000 / targetFps;
            sample->SetSampleTime(pts); sample->SetSampleDuration(10000000 / targetFps);
            writer->WriteSample(streamIndex, sample.Get());
            context->Unmap(staging.Get(), 0);
            frameIndex++;
        }
        dupl->ReleaseFrame();
        std::this_thread::sleep_for(std::chrono::milliseconds(frameIntervalMs));
    }

    if (writer) writer->Finalize();
    MFShutdown(); CoUninitialize();
}

// ----------------- TCP Server -----------------
int RunServiceMode()
{
    WSADATA wsa; WSAStartup(MAKEWORD(2, 2), &wsa);
    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    sockaddr_in addr{}; addr.sin_family = AF_INET; addr.sin_port = htons(10444); addr.sin_addr.s_addr = INADDR_ANY;
    bind(s, (sockaddr*)&addr, sizeof(addr));
    listen(s, 1);
    SOCKET c = accept(s, NULL, NULL);
    if (c == INVALID_SOCKET) { closesocket(s); WSACleanup(); return 1; }

    char buf[256] = {}; int len = recv(c, buf, sizeof(buf) - 1, 0);
    if (len > 0) {
        buf[len] = 0;
        std::wstring cmd, uuid, sess;
        std::wstringstream ss(std::wstring_convert<std::codecvt_utf8<wchar_t>>().from_bytes(buf));
        ss >> cmd >> uuid >> sess;
        if (_wcsicmp(cmd.c_str(), L"start") == 0) {
            g_uuid = uuid; g_session = sess;
            std::atomic<bool> running{ true };
            std::thread t([&] { char tmp[8]; while (recv(c, tmp, sizeof(tmp), 0) > 0) {} running = false; });
            RunCaptureLoop(running);
            t.join();
        }
    }
    closesocket(c); closesocket(s); WSACleanup();
    return 0;
}

// ----------------- Windows Service -----------------
SERVICE_STATUS gSvcStatus = {};
SERVICE_STATUS_HANDLE gSvcStatusHandle = nullptr;

void ReportSvcStatus(DWORD state) {
    gSvcStatus.dwCurrentState = state;
    gSvcStatus.dwControlsAccepted = (state == SERVICE_START_PENDING) ? 0 : SERVICE_ACCEPT_STOP;
    gSvcStatus.dwWin32ExitCode = NO_ERROR; gSvcStatus.dwCheckPoint = 0; gSvcStatus.dwWaitHint = 0;
    SetServiceStatus(gSvcStatusHandle, &gSvcStatus);
}

void WINAPI SvcCtrlHandler(DWORD ctrl) {
    if (ctrl == SERVICE_CONTROL_STOP) {
        ReportSvcStatus(SERVICE_STOP_PENDING);
        // rely on TCP disconnect to stop capture
        ReportSvcStatus(SERVICE_STOPPED);
    }
}

void WINAPI SvcMain(DWORD, LPTSTR*) {
    gSvcStatusHandle = RegisterServiceCtrlHandler(L"QCMREC", SvcCtrlHandler);
    if (!gSvcStatusHandle) return;

    ZeroMemory(&gSvcStatus, sizeof(gSvcStatus));
    gSvcStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;

    ReportSvcStatus(SERVICE_START_PENDING);
    ReportSvcStatus(SERVICE_RUNNING);

    RunServiceMode();

    ReportSvcStatus(SERVICE_STOPPED);
}

// ----------------- main -----------------
int wmain(int argc, wchar_t** argv)
{
    if (argc >= 4 && _wcsicmp(argv[1], L"start") == 0) {
        g_uuid = argv[2]; g_session = argv[3];
        std::atomic<bool> running{ true };
        std::thread stopper([&] { _getch(); running = false; });
        RunCaptureLoop(running);
        stopper.join();
        return 0;
    }
    else if (argc == 1) {
        SERVICE_TABLE_ENTRY DispatchTable[] = {
            { (LPWSTR)L"QCMREC", (LPSERVICE_MAIN_FUNCTION)SvcMain },
            { NULL, NULL }
        };
        if (!StartServiceCtrlDispatcher(DispatchTable)) {
            // fallback if run manually without args
            RunServiceMode();
        }
        return 0;
    }
    MessageBoxW(nullptr, L"Usage:\nQCMREC.exe start <UUID> <SESSIONID>\nOr run with no args to run as service.", L"QCMREC", MB_OK);
    return 0;
}
