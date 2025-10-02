
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
#include <Wtsapi32.h>
#include <UserEnv.h>

#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Userenv.lib")
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

// ---------------- Logging --------------------------
static void LogRec(const wchar_t* fmt, ...)
{
	CreateDirectoryW(L"C:\\PAM", nullptr);
	wchar_t buf[2048];
	va_list ap; va_start(ap, fmt);
	StringCchVPrintfW(buf, _countof(buf), fmt, ap);
	va_end(ap);

	SYSTEMTIME st; GetLocalTime(&st);
	wchar_t msg[2300];
	StringCchPrintfW(msg, _countof(msg),
		L"%04u-%02u-%02u %02u:%02u:%02u [QCMREC] %s\r\n",
		st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, buf);

	HANDLE h = CreateFileW(L"C:\\PAM\\qcmrec.log", FILE_APPEND_DATA, FILE_SHARE_READ,
		nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
	if (h != INVALID_HANDLE_VALUE) {
		DWORD cb = (DWORD)(lstrlenW(msg) * sizeof(wchar_t));
		WriteFile(h, msg, cb, &cb, nullptr);
		CloseHandle(h);
	}
}

// --- Forward declare upload function ---
static void UploadFileToHost(const std::wstring& filePath,
	const std::wstring& uuid,
	const std::wstring& session);

// ----------------- Capture Loop -----------------
static void RunCaptureLoop(std::atomic<bool>& running)
{
	EnsureRecFolder();
	// NOTE: MessageBox will block service start 
	//MessageBoxW(nullptr, L"Recording started.\n(Stops when CJ disconnects or ENTER in manual mode)", L"QCMREC", MB_OK);

	HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	if (FAILED(hr)) return;

	wchar_t videoPath[MAX_PATH] = L"";

	Microsoft::WRL::ComPtr<IWICImagingFactory> wic;
	if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic)))) { CoUninitialize(); return; }

	D3D_FEATURE_LEVEL flOut;
	Microsoft::WRL::ComPtr<ID3D11Device> device;
	Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
	if (FAILED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, &device, &flOut, &context))) { CoUninitialize(); return; }

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

			//wchar_t videoPath[MAX_PATH];
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
	MFShutdown();
	CoUninitialize();
	UploadFileToHost(videoPath, g_uuid, g_session);

}

// ----------------- Upload to backend -----------------
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")

static void UploadFileToHost(const std::wstring& filePath,
	const std::wstring& uuid,
	const std::wstring& session)
{
	LogRec(L"UploadFileToHost: %s (UUID=%s, SESSION=%s)",
		filePath.c_str(), uuid.c_str(), session.c_str());

	HANDLE hFile = CreateFileW(filePath.c_str(), GENERIC_READ, FILE_SHARE_READ, NULL,
		OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (hFile == INVALID_HANDLE_VALUE) {
		LogRec(L"Failed to open file for upload. ec=%lu", GetLastError());
		return;
	}

	DWORD fileSize = GetFileSize(hFile, NULL);
	if (fileSize == INVALID_FILE_SIZE || fileSize == 0) {
		LogRec(L"Invalid file size: %lu", GetLastError());
		CloseHandle(hFile);
		return;
	}

	BYTE* buffer = new BYTE[fileSize];
	DWORD bytesRead = 0;
	if (!ReadFile(hFile, buffer, fileSize, &bytesRead, NULL) || bytesRead != fileSize) {
		LogRec(L"Failed to read file. ec=%lu", GetLastError());
		delete[] buffer;
		CloseHandle(hFile);
		return;
	}
	CloseHandle(hFile);

	HINTERNET hSession = WinHttpOpen(L"QCMREC/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
		WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
	if (!hSession) {
		LogRec(L"WinHttpOpen failed ec=%lu", GetLastError());
		delete[] buffer;
		return;
	}

	// --- CHANGE YOUR HOST & PORT HERE ---
	const wchar_t* host = L"192.168.8.199";   // your host PC IP
	INTERNET_PORT port = 9000;                // backend port
	HINTERNET hConnect = WinHttpConnect(hSession, host, port, 0);
	if (!hConnect) {
		LogRec(L"WinHttpConnect failed ec=%lu", GetLastError());
		WinHttpCloseHandle(hSession);
		delete[] buffer;
		return;
	}

	HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"POST",
		L"/api/upload", NULL, WINHTTP_NO_REFERER,
		WINHTTP_DEFAULT_ACCEPT_TYPES,
		0);
	if (!hRequest) {
		LogRec(L"WinHttpOpenRequest failed ec=%lu", GetLastError());
		WinHttpCloseHandle(hConnect);
		WinHttpCloseHandle(hSession);
		delete[] buffer;
		return;
	}

	// Simple custom header
	std::wstringstream hdr;
	hdr << L"X-UUID: " << uuid << L"\r\n"
		<< L"X-Session: " << session << L"\r\n";
	WinHttpAddRequestHeaders(hRequest, hdr.str().c_str(),
		(ULONG)-1L, WINHTTP_ADDREQ_FLAG_ADD);

	BOOL sent = WinHttpSendRequest(hRequest,
		WINHTTP_NO_ADDITIONAL_HEADERS, 0,
		buffer, fileSize, fileSize, 0);
	if (!sent) {
		LogRec(L"WinHttpSendRequest failed ec=%lu", GetLastError());
	}
	else if (!WinHttpReceiveResponse(hRequest, NULL)) {
		LogRec(L"WinHttpReceiveResponse failed ec=%lu", GetLastError());
	}
	else {
		LogRec(L"Upload done");
	}

	WinHttpCloseHandle(hRequest);
	WinHttpCloseHandle(hConnect);
	WinHttpCloseHandle(hSession);
	delete[] buffer;
}

// --- Run capture inside a specific RDP session (service mode) ---
static void RunCaptureInSession(DWORD targetSession, const std::wstring& uuid)
{
	HANDLE hUserToken = nullptr;
	if (!WTSQueryUserToken(targetSession, &hUserToken)) {
		LogRec(L"WTSQueryUserToken failed ec=%lu for sid=%u", GetLastError(), targetSession);
		return;
	}

	HANDLE hPrimary = nullptr;
	if (!DuplicateTokenEx(hUserToken, TOKEN_ALL_ACCESS, nullptr, SecurityIdentification, TokenPrimary, &hPrimary)) {
		LogRec(L"DuplicateTokenEx failed ec=%lu for sid=%u", GetLastError(), targetSession);
		CloseHandle(hUserToken);
		return;
	}
	CloseHandle(hUserToken);

	LPVOID env = nullptr;
	if (!CreateEnvironmentBlock(&env, hPrimary, FALSE)) {
		LogRec(L"CreateEnvironmentBlock failed ec=%lu (continuing)", GetLastError());
		env = nullptr;
	}

	// launch this same exe in user session with args:  start <uuid> <sid>
	wchar_t exe[MAX_PATH]; GetModuleFileNameW(nullptr, exe, MAX_PATH);
	wchar_t cmd[512];
	StringCchPrintfW(cmd, 512, L"\"%s\" start %s %u", exe, uuid.c_str(), targetSession);

	STARTUPINFOW si{}; si.cb = sizeof(si);
	si.lpDesktop = (LPWSTR)L"winsta0\\default";
	si.dwFlags = STARTF_USESHOWWINDOW;
	si.wShowWindow = SW_HIDE;
	PROCESS_INFORMATION pi{};
	BOOL ok = CreateProcessAsUserW(
		hPrimary,
		exe,
		cmd,
		nullptr, nullptr, FALSE,
		CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
		env,
		nullptr,
		&si,
		&pi
	);
	if (!ok) {
		LogRec(L"CreateProcessAsUserW failed ec=%lu for sid=%u", GetLastError(), targetSession);
	}
	else {
		LogRec(L"Launched QCMREC in session %u (pid=%u)", targetSession, (unsigned)pi.dwProcessId);
		CloseHandle(pi.hThread);
		CloseHandle(pi.hProcess);
	}

	if (env) DestroyEnvironmentBlock(env);
	CloseHandle(hPrimary);
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

	LogRec(L"Accepted connection on 10444 from CJ");

	char buf[256] = {}; int len = recv(c, buf, sizeof(buf) - 1, 0);
	if (len > 0) {
		buf[len] = 0;
		LogRec(L"Received raw: %S", buf);

		std::wstring cmd, uuid, sess;
		std::wstringstream ss(std::wstring_convert<std::codecvt_utf8<wchar_t>>().from_bytes(buf));
		ss >> cmd >> uuid >> sess;

		LogRec(L"Parsed cmd='%s' uuid='%s' sess='%s'", cmd.c_str(), uuid.c_str(), sess.c_str());

		if (_wcsicmp(cmd.c_str(), L"start") == 0) {
			LogRec(L"Start command received — UUID=%s SID=%s", uuid.c_str(), sess.c_str());
			g_uuid = uuid; g_session = sess;

			DWORD sid = _wtoi(sess.c_str());
			if (sid == 0 || sid == (DWORD)-1) {
				LogRec(L"Invalid SID received: %s", sess.c_str());
			}
			else {
				RunCaptureInSession(sid, uuid);  // launch a new QCMREC in that user session
			}
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
	gSvcStatus.dwWin32ExitCode = NO_ERROR;
	gSvcStatus.dwCheckPoint = 0;
	gSvcStatus.dwWaitHint = 0;
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

	//  Keep listening forever; each CJ connect spawns capture in that user session
	while (true) {
		RunServiceMode();    // waits for CJ connection and launches capture
		Sleep(1000);         // small pause before next accept loop
	}

	ReportSvcStatus(SERVICE_STOPPED);
}


// ----------------- main -----------------
int wmain(int argc, wchar_t** argv)
{
	// ---------- MANUAL / TEST MODE ----------
	// When run manually: QCMREC.exe start <UUID> <SESSIONID>
	if (argc >= 4 && _wcsicmp(argv[1], L"start") == 0) {
		g_uuid = argv[2];
		g_session = argv[3];

		std::atomic<bool> running{ true };

		// Popup only in manual mode
		MessageBoxW(nullptr, L"Recording started.\n(Stops when ENTER)", L"QCMREC", MB_OK);

		std::thread stopper([&] { _getch(); running = false; });
		RunCaptureLoop(running);
		stopper.join();
		return 0;
	}

	// ---------- SERVICE MODE ----------
	// No args → run as Windows Service
	SERVICE_TABLE_ENTRY DispatchTable[] = {
		{ (LPWSTR)L"QCMREC", (LPSERVICE_MAIN_FUNCTION)SvcMain },
		{ NULL, NULL }
	};

	if (!StartServiceCtrlDispatcher(DispatchTable)) {
		// Fallback: if not actually started by SCM but run with no args
		RunServiceMode();
	}
	return 0;
}
