// qcmrec_dxgi.cpp
// Simple DXGI Desktop Duplication test (console)
// Captures screen frames and saves BMP images in C:\REC\

#define _WIN32_WINNT 0x0600
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wincodec.h>
#include <strsafe.h>
#include <iostream>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "windowscodecs.lib")

// Save an ID3D11Texture2D to BMP using WIC
bool SaveTextureToBMP(ID3D11Device* device, ID3D11DeviceContext* ctx, ID3D11Texture2D* tex, const std::wstring& filename)
{
    // Map texture to CPU
    D3D11_TEXTURE2D_DESC desc;
    tex->GetDesc(&desc);
    D3D11_TEXTURE2D_DESC cpuDesc = desc;
    cpuDesc.Usage = D3D11_USAGE_STAGING;
    cpuDesc.BindFlags = 0;
    cpuDesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    cpuDesc.MiscFlags = 0;
    ID3D11Texture2D* cpuTex = nullptr;
    if (FAILED(device->CreateTexture2D(&cpuDesc, nullptr, &cpuTex))) return false;
    ctx->CopyResource(cpuTex, tex);

    D3D11_MAPPED_SUBRESOURCE map;
    if (FAILED(ctx->Map(cpuTex, 0, D3D11_MAP_READ, 0, &map))) { cpuTex->Release(); return false; }

    // Init WIC
    IWICImagingFactory* wic = nullptr;
    CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic));
    IWICBitmapEncoder* encoder = nullptr;
    IWICStream* stream = nullptr;
    IWICBitmapFrameEncode* frame = nullptr;
    IPropertyBag2* props = nullptr;

    if (wic && SUCCEEDED(wic->CreateStream(&stream)) &&
        SUCCEEDED(stream->InitializeFromFilename(filename.c_str(), GENERIC_WRITE)) &&
        SUCCEEDED(wic->CreateEncoder(GUID_ContainerFormatBmp, nullptr, &encoder)) &&
        SUCCEEDED(encoder->Initialize(stream, WICBitmapEncoderNoCache)) &&
        SUCCEEDED(encoder->CreateNewFrame(&frame, &props)) &&
        SUCCEEDED(frame->Initialize(props)) &&
        SUCCEEDED(frame->SetSize(desc.Width, desc.Height)) &&
        SUCCEEDED(frame->SetPixelFormat((WICPixelFormatGUID*)&GUID_WICPixelFormat32bppBGRA))) {

        // Write each line (BGRA)
        frame->WritePixels(desc.Height, map.RowPitch, map.RowPitch * desc.Height, (BYTE*)map.pData);
        frame->Commit();
        encoder->Commit();
    }

    if (frame) frame->Release();
    if (encoder) encoder->Release();
    if (stream) stream->Release();
    if (wic) wic->Release();

    ctx->Unmap(cpuTex, 0);
    cpuTex->Release();
    return true;
}

int wmain()
{
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);

    // Create D3D11 device
    ID3D11Device* device = nullptr;
    ID3D11DeviceContext* ctx = nullptr;
    D3D_FEATURE_LEVEL fl;
    if (FAILED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
        &device, &fl, &ctx))) {
        std::wcout << L"Failed to create D3D11 device\n";
        return -1;
    }

    // Get DXGI output
    IDXGIDevice* dxgiDev = nullptr;
    device->QueryInterface(__uuidof(IDXGIDevice), (void**)&dxgiDev);
    IDXGIAdapter* adapter = nullptr;
    dxgiDev->GetAdapter(&adapter);
    IDXGIOutput* output = nullptr;
    adapter->EnumOutputs(0, &output);
    IDXGIOutput1* output1 = nullptr;
    output->QueryInterface(__uuidof(IDXGIOutput1), (void**)&output1);
    IDXGIOutputDuplication* dup = nullptr;
    if (FAILED(output1->DuplicateOutput(device, &dup))) {
        std::wcout << L"DuplicateOutput failed\n";
        return -1;
    }

    std::wcout << L"=== Recording started. Press ENTER to stop ===\n";

    int frameCount = 0;
    while (true) {
        IDXGIResource* res = nullptr;
        DXGI_OUTDUPL_FRAME_INFO info;
        if (SUCCEEDED(dup->AcquireNextFrame(100, &info, &res))) {
            ID3D11Texture2D* tex = nullptr;
            res->QueryInterface(__uuidof(ID3D11Texture2D), (void**)&tex);
            if (tex) {
                wchar_t fname[260];
                StringCchPrintfW(fname, 260, L"C:\\REC\\frame_%04d.bmp", frameCount++);
                SaveTextureToBMP(device, ctx, tex, fname);
                tex->Release();
            }
            dup->ReleaseFrame();
            res->Release();
        }

        if (GetAsyncKeyState(VK_RETURN)) break;
        Sleep(100);
    }

    std::wcout << L"=== Recording stopped ===\n";

    if (dup) dup->Release();
    if (output1) output1->Release();
    if (output) output->Release();
    if (adapter) adapter->Release();
    if (dxgiDev) dxgiDev->Release();
    if (ctx) ctx->Release();
    if (device) device->Release();
    CoUninitialize();
    return 0;
}
