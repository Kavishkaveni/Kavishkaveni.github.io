// qcmrec_dxgi.cpp
// Minimal DXGI Desktop Duplication recorder (PNG frames) for manual testing.
// No FFmpeg, no Media Foundation.
// Usage: QCMREC.exe start
// Saves frames to C:\REC\capture_<timestamp>_frameNNNN.png
// Stop by pressing ENTER in the console.
#ifndef _NO_INIT_ALL
#define _NO_INIT_ALL 1
#endif

#define WINVER 0x0601
#define _WIN32_WINNT 0x0601
#define NTDDI_VERSION NTDDI_WIN7

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wincodec.h>
#include <strsafe.h>
#include <conio.h>
#include <atomic>
#include <chrono>
#include <thread>
#include <wrl/client.h>
#include <fstream>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "dxguid.lib")
#pragma comment(lib, "windowscodecs.lib")

// Globals to hold UUID & Session from command line
std::wstring g_uuid;
std::wstring g_session;

// ---------- small helpers ----------
static void EnsureRecFolder()
{
	CreateDirectoryW(L"C:\\REC", nullptr); // ok if already exists
}

static LPCWSTR HResultText(HRESULT hr, wchar_t* buf, size_t cch)
{
	FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
		nullptr, hr, 0, buf, (DWORD)cch, nullptr);
	return buf;
}



// Save BGRA8 buffer to BMP
void SaveFrameBMP(const wchar_t* path, int width, int height, const void* dataBGRA)
{
	BITMAPFILEHEADER bfh = { 0 };
	BITMAPINFOHEADER bih = { 0 };

	bfh.bfType = 0x4D42; // 'BM'
	bfh.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
	bfh.bfSize = bfh.bfOffBits + width * height * 4;

	bih.biSize = sizeof(BITMAPINFOHEADER);
	bih.biWidth = width;
	bih.biHeight = -height; // negative for top-down
	bih.biPlanes = 1;
	bih.biBitCount = 32;
	bih.biCompression = BI_RGB;

	std::ofstream f(path, std::ios::binary);
	f.write(reinterpret_cast<const char*>(&bfh), sizeof(bfh));
	f.write(reinterpret_cast<const char*>(&bih), sizeof(bih));
	f.write(reinterpret_cast<const char*>(dataBGRA), width * height * 4);
}

// Save BGRA8 buffer to PNG via WIC
static HRESULT SavePNG(IWICImagingFactory* wic,
	const wchar_t* path,
	UINT width, UINT height,
	UINT stride, const BYTE* dataBGRA)
{
	Microsoft::WRL::ComPtr<IWICStream> stream;
	Microsoft::WRL::ComPtr<IWICBitmapEncoder> encoder;
	Microsoft::WRL::ComPtr<IWICBitmapFrameEncode> frame;
	WICPixelFormatGUID fmt = GUID_WICPixelFormat32bppBGRA;

	HRESULT hr = wic->CreateStream(&stream);
	if (SUCCEEDED(hr)) hr = stream->InitializeFromFilename(path, GENERIC_WRITE);
	if (SUCCEEDED(hr)) hr = wic->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
	if (SUCCEEDED(hr)) hr = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
	if (SUCCEEDED(hr)) hr = encoder->CreateNewFrame(&frame, nullptr);
	if (SUCCEEDED(hr)) hr = frame->Initialize(nullptr);
	if (SUCCEEDED(hr)) hr = frame->SetSize(width, height);
	if (SUCCEEDED(hr)) hr = frame->SetPixelFormat(&fmt);
	if (SUCCEEDED(hr)) hr = frame->WritePixels(height, stride, stride * height, const_cast<BYTE*>(dataBGRA));
	if (SUCCEEDED(hr)) hr = frame->Commit();
	if (SUCCEEDED(hr)) hr = encoder->Commit();
	return hr;
}

// Build path like C:\REC\capture_YYYYMMDD_HHMMSS_frame0001.png
extern std::wstring g_uuid;
extern std::wstring g_session;

static void BuildFramePath(wchar_t* out, size_t cch, int frameIndex)
{
	SYSTEMTIME st; GetLocalTime(&st);
	StringCchPrintfW(out, cch,
		L"C:\\REC\\%s_%s_%04u%02u%02u_%02u%02u%02u_frame%04d.png",
		g_uuid.c_str(), g_session.c_str(),
		st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, frameIndex);
}

// ---------- main capture ----------
int wmain(int argc, wchar_t** argv)
{
	if (argc < 4 || _wcsicmp(argv[1], L"start") != 0) {
		MessageBoxW(nullptr,
			L"Usage:\n\nQCMREC.exe start <UUID> <SESSIONID>\n\n"
			L"- Captures desktop frames via DXGI\n"
			L"- Saves PNGs to C:\\REC\\<UUID>_<SESSIONID>_frameXXXX.png\n"
			L"- Press ENTER in console to stop.",
			L"QCMREC DXGI", MB_OK | MB_ICONINFORMATION);
		return 0;
	}

	g_uuid = argv[2];
	g_session = argv[3];

	EnsureRecFolder();

	// Tell user we’re starting
	MessageBoxW(nullptr,
		L"Recording started.\n\nReturn to this console and press ENTER to stop.",
		L"QCMREC (DXGI)", MB_OK | MB_ICONINFORMATION);

	HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	if (FAILED(hr)) return 1;

	// Create WIC factory (for PNG saving)
	Microsoft::WRL::ComPtr<IWICImagingFactory> wic;
	hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
		IID_PPV_ARGS(&wic));
	if (FAILED(hr)) { CoUninitialize(); return 2; }

	// Create D3D11 device
	D3D_FEATURE_LEVEL flOut;
	Microsoft::WRL::ComPtr<ID3D11Device> device;
	Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
	UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
#if _DEBUG
	// flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif
	hr = D3D11CreateDevice(
		nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
		flags, nullptr, 0, D3D11_SDK_VERSION,
		&device, &flOut, &context);
	if (FAILED(hr)) { CoUninitialize(); return 3; }

	// Get output (monitor) 0
	Microsoft::WRL::ComPtr<IDXGIDevice> dxgiDevice;
	device.As(&dxgiDevice);
	Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
	dxgiDevice->GetAdapter(&adapter);
	Microsoft::WRL::ComPtr<IDXGIOutput> output;
	hr = adapter->EnumOutputs(0, &output); // first monitor
	if (FAILED(hr)) { CoUninitialize(); return 4; }

	Microsoft::WRL::ComPtr<IDXGIOutput1> output1;
	output.As(&output1);

	// Duplicate the output
	Microsoft::WRL::ComPtr<IDXGIOutputDuplication> dupl;
	hr = output1->DuplicateOutput(device.Get(), &dupl);
	if (FAILED(hr)) {
		wchar_t msg[256]; HResultText(hr, msg, 256);
		MessageBoxW(nullptr, msg, L"DuplicateOutput failed", MB_OK | MB_ICONERROR);
		CoUninitialize(); return 5;
	}

	// Setup staging texture (we’ll size it after first frame)
	Microsoft::WRL::ComPtr<ID3D11Texture2D> staging;
	UINT width = 0, height = 0, pitch = 0;

	std::atomic<bool> running{ true };
	// Stop condition thread (ENTER)
	std::thread stopper([&] {
		_getch();          // any key
		running = false;
	});

	int frameIndex = 0;
	const int targetFps = 10;
	const int frameIntervalMs = 1000 / targetFps;
	Microsoft::WRL::ComPtr<IMFSinkWriter> writer; // <--- move here so it's visible later
	DWORD streamIndex = 0;                        // also move this out so loop can use
	
	///
	while (running) {
		DXGI_OUTDUPL_FRAME_INFO fi{};
		Microsoft::WRL::ComPtr<IDXGIResource> res;
		hr = dupl->AcquireNextFrame(500, &fi, &res);
		if (hr == DXGI_ERROR_WAIT_TIMEOUT) continue;
		if (hr == DXGI_ERROR_ACCESS_LOST) { // need to re-duplicate
			dupl->ReleaseFrame();
			dupl.Reset();
			output1->DuplicateOutput(device.Get(), &dupl);
			continue;
		}
		if (FAILED(hr)) break;

		Microsoft::WRL::ComPtr<ID3D11Texture2D> frameTex;
		res.As(&frameTex);

		// Create staging tex (once) with correct size/format and init Media Foundation writer
		if (!staging) {
			D3D11_TEXTURE2D_DESC desc{};
			frameTex->GetDesc(&desc);
			width = desc.Width;
			height = desc.Height;

			D3D11_TEXTURE2D_DESC s{};
			s.Width = width;
			s.Height = height;
			s.MipLevels = 1;
			s.ArraySize = 1;
			s.Format = DXGI_FORMAT_B8G8R8A8_UNORM;           // expected
			s.SampleDesc.Count = 1;
			s.Usage = D3D11_USAGE_STAGING;
			s.BindFlags = 0;
			s.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
			s.MiscFlags = 0;
			hr = device->CreateTexture2D(&s, nullptr, &staging);
			if (FAILED(hr)) { dupl->ReleaseFrame(); break; }

			pitch = width * 4;

			// ---- Initialize Media Foundation and sink writer ----
			MFStartup(MF_VERSION);

			wchar_t videoPath[MAX_PATH];
			SYSTEMTIME stMF; GetLocalTime(&stMF);
			StringCchPrintfW(videoPath, MAX_PATH,
				L"C:\\REC\\%s_%s_%04u%02u%02u_%02u%02u%02u.mp4",
				g_uuid.c_str(), g_session.c_str(),
				stMF.wYear, stMF.wMonth, stMF.wDay, stMF.wHour, stMF.wMinute, stMF.wSecond);

			hr = MFCreateSinkWriterFromURL(videoPath, nullptr, nullptr, &writer);
			if (FAILED(hr)) { dupl->ReleaseFrame(); break; }

			// Output type (H.264)
			Microsoft::WRL::ComPtr<IMFMediaType> outType;
			MFCreateMediaType(&outType);
			outType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
			outType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
			outType->SetUINT32(MF_MT_AVG_BITRATE, 8000000);
			outType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
			MFSetAttributeSize(outType.Get(), MF_MT_FRAME_SIZE, width, height);
			MFSetAttributeRatio(outType.Get(), MF_MT_FRAME_RATE, targetFps, 1);
			MFSetAttributeRatio(outType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
			writer->AddStream(outType.Get(), &streamIndex);

			// Input type (RGB32)
			Microsoft::WRL::ComPtr<IMFMediaType> inType;
			MFCreateMediaType(&inType);
			inType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
			inType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
			MFSetAttributeSize(inType.Get(), MF_MT_FRAME_SIZE, width, height);
			MFSetAttributeRatio(inType.Get(), MF_MT_FRAME_RATE, targetFps, 1);
			MFSetAttributeRatio(inType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
			writer->SetInputMediaType(streamIndex, inType.Get(), nullptr);

			writer->BeginWriting();
		}

		// Copy GPU -> CPU staging
		context->CopyResource(staging.Get(), frameTex.Get());

		// Map and push frame to Media Foundation
		D3D11_MAPPED_SUBRESOURCE map{};
		hr = context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &map);
		if (SUCCEEDED(hr)) {
			Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer;
			MFCreateMemoryBuffer(map.RowPitch * height, &buffer);

			BYTE* dst = nullptr; DWORD maxLen = 0;
			buffer->Lock(&dst, &maxLen, nullptr);
			// --- FIX: flip vertically so video is upright ---
			BYTE* src = (BYTE*)map.pData;
			for (UINT y = 0; y < height; ++y) {
				memcpy(dst + y * pitch,                       // pitch = width*4 above
					src + (height - 1 - y) * map.RowPitch,
					pitch);
			}

			buffer->Unlock();
			buffer->SetCurrentLength(pitch * height);

			Microsoft::WRL::ComPtr<IMFSample> sample;
			MFCreateSample(&sample);
			sample->AddBuffer(buffer.Get());

			// Set time in 100-ns units
			LONGLONG pts = frameIndex * 10000000 / targetFps;
			sample->SetSampleTime(pts);
			sample->SetSampleDuration(10000000 / targetFps);

			writer->WriteSample(streamIndex, sample.Get());
			context->Unmap(staging.Get(), 0);

			frameIndex++;
		}

		dupl->ReleaseFrame();
		std::this_thread::sleep_for(std::chrono::milliseconds(frameIntervalMs));
	}

	stopper.join();

	// Finish & shutdown Media Foundation
	writer->Finalize();
	MFShutdown();
	CoUninitialize();

	MessageBoxW(nullptr,
		L"Recording stopped. Check C:\\REC for MP4 file.",
		L"QCMREC (DXGI)", MB_OK | MB_ICONINFORMATION);
}
