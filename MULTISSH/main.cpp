#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <objidl.h>
#include <gdiplus.h>
#include <string>
#include <shellapi.h>
#include <fstream>
#include <ctime>
#include <iomanip>
#include <winhttp.h>
#include <vector>

// Forward declaration
std::wstring FetchDevicesFromBackend();
void ShowPAMLoginDialog(HWND hwndParent);

void logEvent(const std::wstring& msg) {
	std::wofstream log(L"C:\\PAM\\MultiSSH_Client_Log.txt", std::ios::app);
	if (log.is_open()) {
		time_t now = time(0);
		struct tm localTime;
		localtime_s(&localTime, &now);
		log << std::put_time(&localTime, L"%Y-%m-%d %H:%M:%S ") << msg << L"\n";
		log.close();
	}
}

using namespace Gdiplus;
#pragma comment (lib, "gdiplus.lib")
#pragma comment (lib, "comctl32.lib")
#pragma comment(lib, "winhttp.lib")

// ------------------------------------------------------------
//  COLORS
// ------------------------------------------------------------
#define COLOR_BG RGB(244, 246, 250)
#define COLOR_SIDEBAR RGB(236, 238, 241)
#define COLOR_HEADER RGB(255, 255, 255)
#define COLOR_BLUE RGB(44, 104, 255)
#define COLOR_GRAY RGB(150, 150, 150)
#define COLOR_TEXT RGB(40, 40, 40)

HINSTANCE hInst;
HWND hTaskBtn, hChangerBtn, hDeviceBtn, hUserBtn, hSearchBox, hSearchBtn, hSearchDevices;
bool isTask = true;
bool isDevice = true;

// ------------------------------------------------------------
// Helper: Draw centered text
// ------------------------------------------------------------
void DrawCenteredText(HDC hdc, LPCWSTR text, RECT rc, COLORREF color, int size = 18)
{
	SetBkMode(hdc, TRANSPARENT);
	SetTextColor(hdc, color);
	HFONT hFont = CreateFont(size, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
		DEFAULT_CHARSET, OUT_OUTLINE_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
		VARIABLE_PITCH, L"Segoe UI");
	HFONT hOld = (HFONT)SelectObject(hdc, hFont);
	DrawText(hdc, text, -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
	SelectObject(hdc, hOld);
	DeleteObject(hFont);
}

// ------------------------------------------------------------
// Draw rounded background for buttons
// ------------------------------------------------------------
void FillRoundedRect(HDC hdc, RECT rc, COLORREF color, int radius)
{
	Graphics graphics(hdc);
	SolidBrush brush(Color(GetRValue(color), GetGValue(color), GetBValue(color)));
	GraphicsPath path;
	path.AddArc(rc.left, rc.top, radius, radius, 180, 90);
	path.AddArc(rc.right - radius, rc.top, radius, radius, 270, 90);
	path.AddArc(rc.right - radius, rc.bottom - radius, radius, radius, 0, 90);
	path.AddArc(rc.left, rc.bottom - radius, radius, radius, 90, 90);
	path.CloseFigure();
	graphics.FillPath(&brush, &path);
}

// ------------------------------------------------------------
// Draw the search icon
// ------------------------------------------------------------
void DrawSearchIcon(HDC hdc, int x, int y)
{
	Graphics g(hdc);
	Pen pen(Color(120, 120, 120), 2);
	g.DrawEllipse(&pen, x, y, 10, 10);
	g.DrawLine(&pen, x + 9, y + 9, x + 14, y + 14);
}

// ------------------------------------------------------------
// Subclassed Edit Control (placeholder behavior)
// ------------------------------------------------------------
LRESULT CALLBACK EditProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam,
	UINT_PTR uIdSubclass, DWORD_PTR dwRefData)
{
	std::wstring placeholder = (LPCWSTR)dwRefData;
	static bool placeholderVisible = true;

	switch (msg)
	{
	case WM_SETFOCUS:
		if (placeholderVisible)
		{
			SetWindowText(hwnd, L"");
			placeholderVisible = false;
		}
		break;

	case WM_KILLFOCUS:
		if (GetWindowTextLength(hwnd) == 0)
		{
			SetWindowText(hwnd, placeholder.c_str());
			placeholderVisible = true;
		}
		break;
	}
	return DefSubclassProc(hwnd, msg, wParam, lParam);
}

// ------------------------------------------------------------
// Window Procedure
// ------------------------------------------------------------
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	switch (msg)
	{
	case WM_CREATE:
	{
		// Header buttons
		hTaskBtn = CreateWindow(L"BUTTON", L"Task",
			WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 70, 25, 80, 30, hwnd, (HMENU)1, hInst, NULL);
		hChangerBtn = CreateWindow(L"BUTTON", L"Changer",
			WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 160, 25, 100, 30, hwnd, (HMENU)2, hInst, NULL);

		// Search box with placeholder
		hSearchBox = CreateWindow(L"EDIT", L"Search by task number...",
			WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL, 420, 25, 260, 25, hwnd, (HMENU)10, hInst, NULL);
		SetWindowSubclass(hSearchBox, EditProc, 0, (DWORD_PTR)L"Search by task number...");

		hSearchBtn = CreateWindow(L"BUTTON", L"Search",
			WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 690, 25, 80, 25, hwnd, (HMENU)3, hInst, NULL);

		// Devices section
		CreateWindow(L"STATIC", L"Devices", WS_CHILD | WS_VISIBLE,
			40, 100, 100, 25, hwnd, NULL, hInst, NULL);

		hDeviceBtn = CreateWindow(L"BUTTON", L"Device",
			WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 30, 130, 100, 30, hwnd, (HMENU)4, hInst, NULL);
		hUserBtn = CreateWindow(L"BUTTON", L"Username",
			WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 140, 130, 100, 30, hwnd, (HMENU)5, hInst, NULL);

		// Search Devices box with placeholder
		hSearchDevices = CreateWindow(L"EDIT", L"Search devices...",
			WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
			30, 170, 210, 25, hwnd, (HMENU)11, hInst, NULL);
		SetWindowSubclass(hSearchDevices, EditProc, 0, (DWORD_PTR)L"Search devices...");

		// ------------------------------------------------------------
// Fetch devices and display them in GUI sidebar
// ------------------------------------------------------------

		std::wstring jsonResponse = FetchDevicesFromBackend();
		if (!jsonResponse.empty()) {
			logEvent(L"[INFO] Parsing device names...");

			std::string utf8(jsonResponse.begin(), jsonResponse.end());
			size_t pos = 0;
			int yOffset = 210;
			int count = 0;

			while ((pos = utf8.find("\"name\":\"", pos)) != std::string::npos) {
				pos += 8;
				size_t end = utf8.find("\"", pos);
				if (end == std::string::npos) break;

				std::string name = utf8.substr(pos, end - pos);
				std::wstring wname(name.begin(), name.end());

				CreateWindow(
					L"BUTTON", wname.c_str(),
					WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
					30, yOffset, 200, 25,
					hwnd, (HMENU)(INT_PTR)(1000 + count), hInst, NULL
				);

				yOffset += 30;
				count++;
				pos = end;
			}

			if (count > 0)
				logEvent(L"[INFO] " + std::to_wstring(count) + L" devices displayed in GUI");
			else
				logEvent(L"[WARN] No devices parsed from backend JSON.");
		}
		else {
			logEvent(L"[WARN] No devices found to display.");
		}

	}
	break;

	case WM_COMMAND:
		switch (LOWORD(wParam))
		{
		case 1: isTask = true; InvalidateRect(hwnd, NULL, TRUE); break;
		case 2: isTask = false; InvalidateRect(hwnd, NULL, TRUE); break;
		case 4: isDevice = true; InvalidateRect(hwnd, NULL, TRUE); break;
		case 5: isDevice = false; InvalidateRect(hwnd, NULL, TRUE); break;
		}
		// Detect dynamic device buttons (ID range 1000–1999)
		if (LOWORD(wParam) >= 1000 && LOWORD(wParam) < 2000) {
			ShowPAMLoginDialog(hwnd);
		}
		break;

	case WM_DRAWITEM:
	{
		LPDRAWITEMSTRUCT dis = (LPDRAWITEMSTRUCT)lParam;
		HDC hdc = dis->hDC;
		RECT rc = dis->rcItem;
		int id = dis->CtlID;

		COLORREF bg = COLOR_HEADER;
		COLORREF text = COLOR_TEXT;

		if ((id == 1 && isTask) || (id == 2 && !isTask) ||
			(id == 4 && isDevice) || (id == 5 && !isDevice) || id == 3)
			bg = COLOR_BLUE, text = RGB(255, 255, 255);

		FillRoundedRect(hdc, rc, bg, 5);
		SetBkMode(hdc, TRANSPARENT);
		SetTextColor(hdc, text);

		wchar_t buf[64];
		GetWindowText(dis->hwndItem, buf, 64);
		DrawText(hdc, buf, -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
	}
	return TRUE;

	case WM_PAINT:
	{
		PAINTSTRUCT ps;
		HDC hdc = BeginPaint(hwnd, &ps);
		RECT rc; GetClientRect(hwnd, &rc);

		// Main background
		HBRUSH bg = CreateSolidBrush(COLOR_BG);
		FillRect(hdc, &rc, bg);
		DeleteObject(bg);

		// Header
		RECT rcHeader = { 0, 0, rc.right, 70 };
		HBRUSH header = CreateSolidBrush(COLOR_HEADER);
		FillRect(hdc, &rcHeader, header);
		DeleteObject(header);

		// Header line
		HPEN pen = CreatePen(PS_SOLID, 1, RGB(220, 220, 220));
		HPEN oldPen = (HPEN)SelectObject(hdc, pen);
		MoveToEx(hdc, 0, 70, NULL);
		LineTo(hdc, rc.right, 70);
		SelectObject(hdc, oldPen);
		DeleteObject(pen);

		// Sidebar
		RECT rcSidebar = { 0, 70, 280, rc.bottom };
		HBRUSH sidebar = CreateSolidBrush(COLOR_SIDEBAR);
		FillRect(hdc, &rcSidebar, sidebar);
		DeleteObject(sidebar);

		// Draw search icon before Task button
		DrawSearchIcon(hdc, 40, 35);

		// Center text area
		RECT rcText = { 280, rc.bottom / 2 - 30, rc.right, rc.bottom / 2 };
		DrawCenteredText(hdc, L"No Active Sessions", rcText, COLOR_TEXT, 20);

		RECT rcSub = { 280, rc.bottom / 2, rc.right, rc.bottom / 2 + 25 };
		DrawCenteredText(hdc, L"Select a device from the left panel to start a new SSH session.", rcSub, COLOR_GRAY, 14);

		EndPaint(hwnd, &ps);
	}
	break;

	case WM_DESTROY:
		PostQuitMessage(0);
		break;

	default:
		return DefWindowProc(hwnd, msg, wParam, lParam);
	}
	return 0;
}


std::wstring FetchDevicesFromBackend()
{
	std::wstring response;

	HINTERNET hSession = WinHttpOpen(L"QCM MultiSSH/1.0",
		WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
		WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);

	if (!hSession) {
		logEvent(L"[ERROR] WinHttpOpen failed, code: " + std::to_wstring(GetLastError()));
		return L"";
	}

	HINTERNET hConnect = WinHttpConnect(hSession, L"192.168.8.199", 9000, 0);
	if (!hConnect) {
		logEvent(L"[ERROR] WinHttpConnect failed, code: " + std::to_wstring(GetLastError()));
		WinHttpCloseHandle(hSession);
		return L"";
	}

	HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", L"/api/devices",
		NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
	if (!hRequest) {
		logEvent(L"[ERROR] WinHttpOpenRequest failed, code: " + std::to_wstring(GetLastError()));
		WinHttpCloseHandle(hConnect);
		WinHttpCloseHandle(hSession);
		return L"";
	}

	BOOL bResults = WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
		WINHTTP_NO_REQUEST_DATA, 0, 0, 0);

	if (!bResults || !WinHttpReceiveResponse(hRequest, NULL)) {
		logEvent(L"[ERROR] Failed to send/receive request, code: " + std::to_wstring(GetLastError()));
	}
	else {
		DWORD statusCode = 0;
		DWORD size = sizeof(statusCode);
		if (WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
			WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &size, WINHTTP_NO_HEADER_INDEX))
		{
			switch (statusCode) {
			case 401:
				logEvent(L"[ERROR] Invalid PAM credentials. Please try again.");
				break;
			case 403:
				logEvent(L"[ERROR] You don't have permission to access this device.");
				break;
			case 404:
				logEvent(L"[ERROR] Session expired or device not available anymore.");
				break;
			case 410:
				logEvent(L"[ERROR] Session has expired — please re-initiate from PAM UI.");
				break;
			case 500:
				logEvent(L"[ERROR] Server error — contact admin.");
				break;
			default:
				if (statusCode >= 200 && statusCode < 300)
					logEvent(L"[INFO] Backend responded OK (" + std::to_wstring(statusCode) + L")");
				else
					logEvent(L"[WARN] Unexpected status code: " + std::to_wstring(statusCode));
				break;
			}
		}

		DWORD dwSize = 0;
		do {
			WinHttpQueryDataAvailable(hRequest, &dwSize);
			if (!dwSize) break;

			std::vector<char> buffer(dwSize + 1);
			DWORD dwDownloaded = 0;

			if (WinHttpReadData(hRequest, buffer.data(), dwSize, &dwDownloaded) && dwDownloaded > 0) {
				buffer[dwDownloaded] = '\0';
				std::wstring wPart(buffer.begin(), buffer.end());
				response += wPart;
			}
		} while (dwSize > 0);
	}

	WinHttpCloseHandle(hRequest);
	WinHttpCloseHandle(hConnect);
	WinHttpCloseHandle(hSession);

	if (response.empty())
		logEvent(L"[WARN] Empty response received from backend");
	else
		logEvent(L"[INFO] Devices fetched successfully from backend");

	return response;
}

// ------------------------------------------------------------
// PAM popup dedicated WndProc
// ------------------------------------------------------------
LRESULT CALLBACK PamDialogProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	switch (msg)
	{
	case WM_COMMAND:
		if (HIWORD(wParam) == BN_CLICKED)
		{
			switch (LOWORD(wParam))
			{
			case 201: // OK
			{
				wchar_t username[100], password[100];
				GetWindowText(GetDlgItem(hwnd, 101), username, 100);
				GetWindowText(GetDlgItem(hwnd, 102), password, 100);
				logEvent(L"[PAM LOGIN] Username=" + std::wstring(username) + L" | Password Entered.");
				DestroyWindow(hwnd);
				return 0;
			}
			case 202: // Cancel
				logEvent(L"[PAM LOGIN] Cancel clicked");
				DestroyWindow(hwnd);
				return 0;
			}
		}
		break;

	case WM_CLOSE:
		logEvent(L"[PAM LOGIN] Closed via X button");
		DestroyWindow(hwnd);
		return 0;
	}
	return DefWindowProc(hwnd, msg, wParam, lParam);
}

// ------------------------------------------------------------
// Simple PAM login popup - FINAL VS2017 COMPATIBLE
// ------------------------------------------------------------
void ShowPAMLoginDialog(HWND hwndParent)
{
	HWND hDialog = CreateWindowEx(
		WS_EX_DLGMODALFRAME,
		L"STATIC",
		L"PAM Login",
		WS_CAPTION | WS_SYSMENU | WS_POPUPWINDOW | WS_VISIBLE,
		400, 250, 300, 200,
		hwndParent, NULL, hInst, NULL);

	if (!hDialog) {
		logEvent(L"[ERROR] Failed to create PAM Login window");
		return;
	}

	CreateWindow(L"STATIC", L"Enter PAM Credentials:", WS_CHILD | WS_VISIBLE,
		50, 20, 200, 20, hDialog, NULL, hInst, NULL);

	CreateWindow(L"STATIC", L"Username:", WS_CHILD | WS_VISIBLE,
		30, 60, 70, 20, hDialog, NULL, hInst, NULL);
	HWND hUser = CreateWindow(L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
		110, 60, 140, 20, hDialog, (HMENU)101, hInst, NULL);

	CreateWindow(L"STATIC", L"Password:", WS_CHILD | WS_VISIBLE,
		30, 90, 70, 20, hDialog, NULL, hInst, NULL);
	HWND hPass = CreateWindow(L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_PASSWORD | ES_AUTOHSCROLL,
		110, 90, 140, 20, hDialog, (HMENU)102, hInst, NULL);

	HWND hOk = CreateWindow(L"BUTTON", L"OK", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
		60, 130, 70, 25, hDialog, (HMENU)201, hInst, NULL);
	HWND hCancel = CreateWindow(L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE,
		160, 130, 70, 25, hDialog, (HMENU)202, hInst, NULL);

	// ✅ Assign our custom WndProc
	SetWindowLongPtr(hDialog, GWLP_WNDPROC, (LONG_PTR)PamDialogProc);

	ShowWindow(hDialog, SW_SHOW);
	UpdateWindow(hDialog);
	EnableWindow(hwndParent, FALSE);

	MSG msg;
	while (IsWindow(hDialog) && GetMessage(&msg, NULL, 0, 0))
	{
		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}

	EnableWindow(hwndParent, TRUE);
	SetForegroundWindow(hwndParent);
}
// ------------------------------------------------------------
// WinMain
// ------------------------------------------------------------
int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE, PWSTR, int nCmdShow)
{
	logEvent(L"MultiSSH Client launched with parameters");
	std::wstring devicesJson = FetchDevicesFromBackend();
	logEvent(L"Fetched Devices: " + devicesJson.substr(0, 200)); // just first part
	hInst = hInstance;
	GdiplusStartupInput gdiplusStartupInput;
	ULONG_PTR gdiplusToken;
	GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, NULL);

	// ------------------------------------------------------------
// Handle command line arguments (from CJ)
// ------------------------------------------------------------
	int argc = 0;
	LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
	std::wstring uuid, protocol;

	if (argc >= 5) {
		for (int i = 1; i < argc; i++) {
			if (wcscmp(argv[i], L"--uuid") == 0 && i + 1 < argc)
				uuid = argv[i + 1];
			if (wcscmp(argv[i], L"--protocol") == 0 && i + 1 < argc)
				protocol = argv[i + 1];
		}
	}

	// Optional: Debug log (silent)
	if (!uuid.empty()) {
		std::wstring msg = L"[MultiSSH] Started with UUID=" + uuid + L" Protocol=" + protocol;
		OutputDebugStringW(msg.c_str());
	}

	LocalFree(argv);

	const wchar_t CLASS_NAME[] = L"MultiSSHUI";
	WNDCLASS wc = {};
	wc.lpfnWndProc = WndProc;
	wc.hInstance = hInstance;
	wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
	wc.lpszClassName = CLASS_NAME;
	RegisterClass(&wc);

	HWND hwnd = CreateWindowEx(
		0, CLASS_NAME, L"SSH Client Manager - QCM MultiSSH",
		WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 950, 600,
		NULL, NULL, hInstance, NULL);

	ShowWindow(hwnd, nCmdShow);
	UpdateWindow(hwnd);

	MSG msg = {};
	while (GetMessage(&msg, NULL, 0, 0))
	{
		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}

	GdiplusShutdown(gdiplusToken);
	return 0;
}
