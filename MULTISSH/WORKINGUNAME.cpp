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
#include <map>
#include <thread>  
#include <dwmapi.h>
#include <algorithm>   // transform
#include <cwctype>     // std::towlower

// If EM_SETCUEBANNER isn’t defined on your SDK, define it:
#ifndef EM_SETCUEBANNER
#define EM_SETCUEBANNER 0x1501
#endif



// Simple fallback JSON extractor (no dependencies)
std::string json_s(const std::string& response, const std::string& key)
{
	std::string pattern = "\"" + key + "\":\"";
	size_t start = response.find(pattern);
	if (start == std::string::npos)
		return "";

	start += pattern.length();
	size_t end = response.find("\"", start);
	if (end == std::string::npos)
		return "";

	return response.substr(start, end - start);
}

// Convert std::string (UTF-8 / ANSI) → std::wstring (UTF-16)
std::wstring s2ws(const std::string& str)
{
	if (str.empty()) return L"";
	int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
	std::wstring wstrTo(size_needed, 0);
	MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
	return wstrTo;
}
// ------------------------------------------------------------
// JSON helpers (temporary mock implementations)
// ------------------------------------------------------------
std::wstring json_ws(const std::string& json, const std::string& key) {
	// Just returns dummy value for now
	return L"";
}

unsigned json_u32(const std::string& json, const std::string& key, unsigned def) {
	// Just returns default until backend parsing logic added
	return def;
}

// Temporary declarations to remove red lines
std::wstring g_sessionUuid;
int selectedDeviceId;
bool http_post_json(const wchar_t* host, int port, const std::wstring& path,
	const std::string& body, DWORD* status, std::string& responseOut);
std::wstring json_ws(const std::string&, const std::string&);
unsigned json_u32(const std::string&, const std::string&, unsigned def = 22);

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
#pragma comment(lib, "dwmapi.lib")


struct DeviceInfo {
	int id;
	std::wstring name;
	std::wstring username;
	std::wstring ip;
	int port;
	COLORREF statusColor;
};

std::vector<DeviceInfo> g_devices; // global list of devices

std::string vaultUtf8; // global vault cache for usernames

std::vector<DeviceInfo> g_filteredDevices; // filtered devices for display

struct SessionInfo {
	std::wstring device;
	std::wstring user;
	std::wstring ip;
	bool active;
};

std::vector<SessionInfo> g_sessions;
// ------------------------------------------------------------
// Validate PAM Credentials by calling backend API
// ------------------------------------------------------------
int ValidatePAMCredentials(const std::string& username, const std::string& password)
{
	HINTERNET hSession = WinHttpOpen(L"MultiSSHClient/1.0",
		WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
		WINHTTP_NO_PROXY_NAME,
		WINHTTP_NO_PROXY_BYPASS,
		0);
	if (!hSession) return 0;

	HINTERNET hConnect = WinHttpConnect(hSession, L"192.168.8.199", 9000, 0);
	if (!hConnect)
	{
		WinHttpCloseHandle(hSession);
		return 0;
	}

	HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"POST",
		L"/api/login",
		NULL, WINHTTP_NO_REFERER,
		WINHTTP_DEFAULT_ACCEPT_TYPES, 0);

	std::string body = "{\"username\":\"" + username + "\",\"password\":\"" + password + "\"}";

	BOOL bResults = WinHttpSendRequest(hRequest,
		L"Content-Type: application/json\r\n",
		-1L,
		(LPVOID)body.c_str(),
		body.size(),
		body.size(),
		0);

	if (!bResults)
	{
		WinHttpCloseHandle(hRequest);
		WinHttpCloseHandle(hConnect);
		WinHttpCloseHandle(hSession);
		return 0;
	}

	WinHttpReceiveResponse(hRequest, NULL);

	DWORD statusCode = 0;
	DWORD size = sizeof(statusCode);
	if (!WinHttpQueryHeaders(hRequest,
		WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
		WINHTTP_HEADER_NAME_BY_INDEX,
		&statusCode,
		&size,
		WINHTTP_NO_HEADER_INDEX))
	{
		statusCode = 0;
	}

	WinHttpCloseHandle(hRequest);
	WinHttpCloseHandle(hConnect);
	WinHttpCloseHandle(hSession);

	// Only return 200 if backend actually says OK, otherwise fail
	return (int)statusCode;
}
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
	//  Prevent crash if dwRefData is NULL
	std::wstring placeholder;
	if (dwRefData)
		placeholder = (LPCWSTR)dwRefData;
	else
		placeholder = L""; // fallback safe string

	bool placeholderVisible = (GetWindowTextLength(hwnd) == 0);

	switch (msg)
	{
	case WM_SETFOCUS:
		// When user clicks/focuses the box
		if (placeholderVisible)
		{
			SetWindowText(hwnd, L"");
			placeholderVisible = false;
		}
		break;

	case WM_KILLFOCUS:
		// When focus is lost, if box is empty → restore placeholder
		if (GetWindowTextLength(hwnd) == 0)
		{
			SetWindowText(hwnd, placeholder.c_str());
			placeholderVisible = true;
		}
		break;

	case WM_CHAR:
		// Handle typing: if user types while placeholder visible, clear it
		if (placeholderVisible)
		{
			SetWindowText(hwnd, L"");
			placeholderVisible = false;
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
		// --- Header Buttons ---
		hTaskBtn = CreateWindow(L"BUTTON", L"Task",
			WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 70, 25, 80, 30, hwnd, (HMENU)1, hInst, NULL);
		hChangerBtn = CreateWindow(L"BUTTON", L"Changer",
			WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 160, 25, 100, 30, hwnd, (HMENU)2, hInst, NULL);

		// --- Search box (Task/Changer) ---
		hSearchBox = CreateWindow(L"EDIT", L"",
			WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
			420, 25, 260, 25, hwnd, (HMENU)10, hInst, NULL);

		// --- Search Button ---
		hSearchBtn = CreateWindow(L"BUTTON", L"Search",
			WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 690, 25, 80, 25, hwnd, (HMENU)3, hInst, NULL);

		// --- Device/User toggle buttons ---
		hDeviceBtn = CreateWindow(L"BUTTON", L"Device",
			WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 30, 130, 100, 30, hwnd, (HMENU)4, hInst, NULL);
		hUserBtn = CreateWindow(L"BUTTON", L"Username",
			WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 140, 130, 100, 30, hwnd, (HMENU)5, hInst, NULL);

		// --- Left Search box (Devices/Usernames) ---
		hSearchDevices = CreateWindowEx(
			0, L"EDIT", L"",
			WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | WS_TABSTOP,
			30, 170, 210, 25,
			hwnd, (HMENU)11, hInst, NULL);


		// --- Cue banners (visible placeholders fix) ---
		SendMessageW(hSearchBox, EM_SETCUEBANNER, TRUE, (LPARAM)L"Search by task number...");
		SendMessageW(hSearchDevices, EM_SETCUEBANNER, TRUE, (LPARAM)L"Search devices...");

		// --- Final Working Placeholder Subclass ---
		auto PlaceholderProc = [](HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam,
			UINT_PTR, DWORD_PTR refData) -> LRESULT
		{
			switch (msg)
			{
			case WM_PAINT:
			{
				wchar_t buf[128]{};
				GetWindowText(hwnd, buf, 128);
				bool empty = (wcslen(buf) == 0);

				PAINTSTRUCT ps;
				HDC hdc = BeginPaint(hwnd, &ps);

				if (empty)
				{
					SetBkMode(hdc, TRANSPARENT);
					SetTextColor(hdc, RGB(150, 150, 150)); // Light grey placeholder
					HFONT hFont = CreateFont(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
						DEFAULT_CHARSET, OUT_OUTLINE_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
						VARIABLE_PITCH, L"Segoe UI");
					HFONT oldFont = (HFONT)SelectObject(hdc, hFont);

					RECT rc; GetClientRect(hwnd, &rc);
					rc.left += 6; rc.top += 4;
					DrawTextW(hdc, (LPCWSTR)refData, -1, &rc, DT_LEFT | DT_SINGLELINE | DT_TOP);

					SelectObject(hdc, oldFont);
					DeleteObject(hFont);
				}

				EndPaint(hwnd, &ps);
				return 0; // stop default processing
			}
			}
			return DefSubclassProc(hwnd, msg, wParam, lParam);
		};

		// Attach both placeholders
		SetWindowSubclass(hSearchBox, PlaceholderProc, 0, (DWORD_PTR)L"Search by task number...");
		SetWindowSubclass(hSearchDevices, PlaceholderProc, 0, (DWORD_PTR)L"Search devices...");

		// --- Text limits ---
		SendMessage(hSearchBox, EM_LIMITTEXT, 100, 0);
		SendMessage(hSearchDevices, EM_LIMITTEXT, 100, 0);

		// --- Fetch backend devices ---
		std::wstring jsonResponse = FetchDevicesFromBackend();
		if (!jsonResponse.empty()) {
			logEvent(L"[INFO] Parsing device names...");

			std::string utf8(jsonResponse.begin(), jsonResponse.end());
			size_t pos = 0;
			int yOffset = 210;
			int count = 0;
			g_devices.clear();

			while ((pos = utf8.find("\"id\":", pos)) != std::string::npos) {
				pos += 5;
				size_t endId = utf8.find(",", pos);
				if (endId == std::string::npos) break;
				int id = std::stoi(utf8.substr(pos, endId - pos));

				size_t nameStart = utf8.find("\"name\":\"", endId);
				if (nameStart == std::string::npos) break;
				nameStart += 8;
				size_t nameEnd = utf8.find("\"", nameStart);
				if (nameEnd == std::string::npos) break;
				std::string name = utf8.substr(nameStart, nameEnd - nameStart);
				std::wstring wname(name.begin(), name.end());

				size_t ipStart = utf8.find("\"ip\":\"", nameEnd);
				std::wstring wip = L"";
				if (ipStart != std::string::npos) {
					ipStart += 6;
					size_t ipEnd = utf8.find("\"", ipStart);
					if (ipEnd != std::string::npos) {
						std::string ip = utf8.substr(ipStart, ipEnd - ipStart);
						wip.assign(ip.begin(), ip.end());
					}
				}

				size_t portStart = utf8.find("\"port\":", ipStart);
				int port = 22;
				if (portStart != std::string::npos) {
					portStart += 7;
					size_t portEnd = utf8.find(",", portStart);
					if (portEnd == std::string::npos)
						portEnd = utf8.find("}", portStart);
					if (portEnd != std::string::npos) {
						try { port = std::stoi(utf8.substr(portStart, portEnd - portStart)); }
						catch (...) { port = 22; }
					}
				}

				// Find matching username from vault by device_ip
				std::wstring wuser = L"admin";  // fallback default
				std::string searchKey = "\"device_ip\":\"" + std::string(wip.begin(), wip.end()) + "\"";
				size_t vaultPos = vaultUtf8.find(searchKey);
				if (vaultPos != std::string::npos) {
					size_t userStart = vaultUtf8.find("\"username\":\"", vaultPos);
					if (userStart != std::string::npos) {
						userStart += 12;
						size_t userEnd = vaultUtf8.find("\"", userStart);
						if (userEnd != std::string::npos) {
							std::string username = vaultUtf8.substr(userStart, userEnd - userStart);
							wuser.assign(username.begin(), username.end());
						}
					}
				}

				g_devices.push_back({
					id,
					wname,
					wuser,
					wip,
					port,
					(count % 3 == 0 ? RGB(0, 200, 0) : (count % 3 == 1 ? RGB(255, 150, 0) : RGB(220, 0, 0)))
					});

				yOffset += 75;
				count++;
				pos = nameEnd;
			}

			if (count > 0)
				logEvent(L"[INFO] " + std::to_wstring(count) + L" devices parsed successfully");
			else
				logEvent(L"[WARN] No devices parsed.");
		}
		else {
			logEvent(L"[WARN] Empty backend response.");
		}

		break;
	}
	case WM_COMMAND:
	{
		//if (HIWORD(wParam) == EN_SETFOCUS) {
			//HWND hEdit = (HWND)lParam;
			//SetWindowText(hEdit, L"");
		//}
		//  Detect typing in the left search bar
		if (HIWORD(wParam) == EN_CHANGE && (HWND)lParam == hSearchDevices)
		{
			wchar_t input[100]{};
			GetWindowText(hSearchDevices, input, 100);

			std::wstring query(input);
			std::transform(query.begin(), query.end(), query.begin(), ::towlower);

			g_filteredDevices.clear();

			for (const auto& d : g_devices)
			{
				std::wstring dev = d.name;
				std::wstring usr = d.username;
				std::transform(dev.begin(), dev.end(), dev.begin(), ::towlower);
				std::transform(usr.begin(), usr.end(), usr.begin(), ::towlower);

				bool matchDevice = dev.find(query) != std::wstring::npos;
				bool matchUser = usr.find(query) != std::wstring::npos;

				if (query.empty() || matchDevice || matchUser)
					g_filteredDevices.push_back(d);
			}

			InvalidateRect(hwnd, NULL, TRUE);
		}
		switch (LOWORD(wParam))
		{
		case 1: // Task
		{
			isTask = true;
			// Set banner first, then clear text (fixes overwriting delay)
			SendMessage(hSearchBox, EM_SETCUEBANNER, 0, (LPARAM)L"Search task number...");
			SetWindowText(hSearchBox, L"");
			SetFocus(hSearchBox);

			InvalidateRect(hTaskBtn, NULL, TRUE);
			InvalidateRect(hChangerBtn, NULL, TRUE);
			UpdateWindow(hTaskBtn);
			UpdateWindow(hChangerBtn);
		}
		break;

		case 2: // Changer
		{
			isTask = false;
			SendMessage(hSearchBox, EM_SETCUEBANNER, 0, (LPARAM)L"Search change number...");
			SetWindowText(hSearchBox, L"");
			SetFocus(hSearchBox);

			InvalidateRect(hTaskBtn, NULL, TRUE);
			InvalidateRect(hChangerBtn, NULL, TRUE);
			UpdateWindow(hTaskBtn);
			UpdateWindow(hChangerBtn);
		}
		break;

		case 4: // Device
		{
			isDevice = true;
			SendMessage(hSearchDevices, EM_SETCUEBANNER, 0, (LPARAM)L"Search devices...");
			SetWindowText(hSearchDevices, L"");
			SetFocus(hSearchDevices);

			// Force redraw of both buttons
			InvalidateRect(hDeviceBtn, NULL, TRUE);
			InvalidateRect(hUserBtn, NULL, TRUE);
			UpdateWindow(hDeviceBtn);
			UpdateWindow(hUserBtn);
		}
		break;

		case 5: // Username
		{
			isDevice = false;
			SendMessage(hSearchDevices, EM_SETCUEBANNER, 0, (LPARAM)L"Search username...");
			SetWindowText(hSearchDevices, L"");
			SetFocus(hSearchDevices);

			// Force redraw of both buttons
			InvalidateRect(hDeviceBtn, NULL, TRUE);
			InvalidateRect(hUserBtn, NULL, TRUE);
			UpdateWindow(hDeviceBtn);
			UpdateWindow(hUserBtn);
		}
		break;

		// ---------- Top search button ----------
		case 3: // Search button clicked (task/change)
		{
			wchar_t input[100];
			GetWindowText(hSearchBox, input, 100);
			std::wstring query(input);
			std::transform(query.begin(), query.end(), query.begin(), ::towlower);
			g_filteredDevices.clear();

			//  mapping TSK/CHG numbers
			std::map<std::wstring, std::vector<int>> ticketMap = {
				{L"tsk123", {43, 41, 15, 16}},
				{L"chg123", {43, 41, 15, 16}},
				{L"tsk124", {45, 14, 13, 11}},
				{L"chg124", {45, 14, 13, 11}},
				{L"tsk125", {10, 9, 8, 7}},
				{L"chg125", {10, 9, 8, 7}},
				{L"tsk126", {6, 4, 1, 42}},
				{L"chg126", {6, 4, 1, 42}}
			};

			std::wstring lowerQuery = query;
			std::transform(lowerQuery.begin(), lowerQuery.end(), lowerQuery.begin(), ::towlower);

			// --- Support numeric-only input for task search ---
			bool isNumeric = !lowerQuery.empty() &&
				std::all_of(lowerQuery.begin(), lowerQuery.end(), ::iswdigit);

			if (isNumeric && isTask) {
				lowerQuery = L"tsk" + lowerQuery;  // prepend "tsk" automatically
			}

			for (const auto& d : g_devices)
			{
				for (const auto& kv : ticketMap)
				{
					if (lowerQuery == kv.first)
					{
						// show only matching devices
						if (std::find(kv.second.begin(), kv.second.end(), d.id) != kv.second.end())
						{
							g_filteredDevices.push_back(d);
						}
					}
				}
			}

			InvalidateRect(hwnd, NULL, TRUE);
		}
		break;

		// ---------- Right search box (Enter key) ----------
		case 11:
		{
			wchar_t input[100]{};
			GetWindowText(hSearchDevices, input, 100);

			std::wstring query(input);
			std::transform(query.begin(), query.end(), query.begin(),
				[](wchar_t c) { return std::towlower(c); });

			g_filteredDevices.clear();

			for (const auto& d : g_devices)
			{
				std::wstring dev = d.name;
				std::wstring usr = d.username;

				std::transform(dev.begin(), dev.end(), dev.begin(),
					[](wchar_t c) { return std::towlower(c); });
				std::transform(usr.begin(), usr.end(), usr.begin(),
					[](wchar_t c) { return std::towlower(c); });

				bool matchDevice = dev.find(query) != std::wstring::npos;
				bool matchUser = usr.find(query) != std::wstring::npos;

				if (query.empty() || matchDevice || matchUser)
					g_filteredDevices.push_back(d);
			}

			InvalidateRect(hwnd, NULL, TRUE);
		}
		break;

		// ---------- Device card clicks ----------
		default:
			if (LOWORD(wParam) >= 1000 && LOWORD(wParam) < 2000)
			{
				int index = LOWORD(wParam) - 1000;
				if (index >= 0 && index < (int)g_devices.size())
				{
					selectedDeviceId = g_devices[index].id;
					logEvent(L"[INFO] Selected Device: " + g_devices[index].name +
						L" (ID=" + std::to_wstring(selectedDeviceId) + L")");
					ShowPAMLoginDialog(hwnd);
				}
			}
			break;
		}
	}
	break;

	case WM_DRAWITEM:
	{
		LPDRAWITEMSTRUCT dis = (LPDRAWITEMSTRUCT)lParam;
		HDC hdc = dis->hDC;
		RECT rc = dis->rcItem;
		int id = dis->CtlID;

		// ------------------------------
//  Device Cards (IDs 1000–1999)
// ------------------------------
		if (id >= 1000 && id < 2000) {
			int index = id - 1000;
			if (index >= 0 && index < (int)g_devices.size()) {
				const auto& d = g_devices[index];
				RECT rcCard = dis->rcItem;

				// Background - rounded white card with soft border
				FillRoundedRect(hdc, rcCard, RGB(255, 255, 255), 18);
				HPEN penBorder = CreatePen(PS_SOLID, 1, RGB(220, 220, 220));
				HPEN oldPen = (HPEN)SelectObject(hdc, penBorder);
				RoundRect(hdc, rcCard.left, rcCard.top, rcCard.right, rcCard.bottom, 10, 10);
				SelectObject(hdc, oldPen);
				DeleteObject(penBorder);



				// Text setup
				SetBkMode(hdc, TRANSPARENT);

				// Device Name - bold black
				SetTextColor(hdc, RGB(30, 30, 30));
				HFONT hFontName = CreateFont(17, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
					DEFAULT_CHARSET, OUT_OUTLINE_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
					VARIABLE_PITCH, L"Segoe UI");
				HFONT oldFont = (HFONT)SelectObject(hdc, hFontName);
				TextOut(hdc, rcCard.left + 15, rcCard.top + 8, d.name.c_str(), d.name.size());
				SelectObject(hdc, oldFont);
				DeleteObject(hFontName);

				// Line 2: admin@ip - small gray
				SetTextColor(hdc, RGB(100, 100, 100));
				HFONT hFontSmall = CreateFont(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
					DEFAULT_CHARSET, OUT_OUTLINE_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
					VARIABLE_PITCH, L"Segoe UI");
				oldFont = (HFONT)SelectObject(hdc, hFontSmall);
				std::wstring line2 = d.username + L"@" + d.ip;
				TextOut(hdc, rcCard.left + 15, rcCard.top + 30, line2.c_str(), line2.size());

				// Line 3: Port
				std::wstring line3 = L"Port: " + std::to_wstring(d.port);
				TextOut(hdc, rcCard.left + 15, rcCard.top + 48, line3.c_str(), line3.size());

				SelectObject(hdc, oldFont);
				DeleteObject(hFontSmall);

				return TRUE; // Stop default button paint
			}
		}

		// ------------------------------
		//  Header Buttons (Task / Changer / Search / Device / Username)
		// ------------------------------
		COLORREF bg = COLOR_HEADER;
		COLORREF text = COLOR_TEXT;

		// Highlight logic for active buttons
		if ((id == 1 && isTask) || (id == 2 && !isTask))
		{
			bg = COLOR_BLUE;
			text = RGB(255, 255, 255);
		}
		else if ((id == 4 && isDevice) || (id == 5 && !isDevice))
		{
			bg = COLOR_BLUE;
			text = RGB(255, 255, 255);
		}
		else if (id == 3)  // <-- Search button (custom look)
		{
			bg = COLOR_BLUE;             // blue background
			text = RGB(255, 255, 255);
		}
		else
		{
			bg = COLOR_HEADER;
			text = COLOR_TEXT;
		}

		FillRoundedRect(hdc, rc, bg, 5);
		SetBkMode(hdc, TRANSPARENT);
		SetTextColor(hdc, text);

		wchar_t buf[64];
		GetWindowText(dis->hwndItem, buf, 64);
		DrawText(hdc, buf, -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

		return TRUE;
	}

	case WM_PAINT:
	{
		PAINTSTRUCT ps;
		HDC hdc = BeginPaint(hwnd, &ps);
		RECT rc; GetClientRect(hwnd, &rc);

		// ------------------------------------------------------------
// Modern background and layout styling
// ------------------------------------------------------------
		HBRUSH bg = CreateSolidBrush(RGB(246, 248, 251));  // soft blue-gray background (#F6F8FB)
		FillRect(hdc, &rc, bg);
		DeleteObject(bg);

		// Header bar (white)
		RECT rcHeader = { 0, 0, rc.right, 70 };
		HBRUSH header = CreateSolidBrush(RGB(255, 255, 255));
		FillRect(hdc, &rcHeader, header);
		DeleteObject(header);

		// --- Rounded background behind TOP search (with subtle shadow) ---
		{
			RECT r = { 420, 25, 420 + 260, 25 + 25 };

			// soft shadow background
			RECT shadow = r;
			OffsetRect(&shadow, 2, 2);
			FillRoundedRect(hdc, shadow, RGB(220, 220, 220), 8); // light gray shadow

			// main white box
			FillRoundedRect(hdc, r, RGB(255, 255, 255), 8);

			// border to separate from background
			HPEN p = CreatePen(PS_SOLID, 1, RGB(180, 180, 180)); // slightly darker border
			HGDIOBJ old = SelectObject(hdc, p);
			RoundRect(hdc, r.left, r.top, r.right, r.bottom, 8, 8);
			SelectObject(hdc, old);
			DeleteObject(p);
		}

		// --- Rounded background behind LEFT search (Devices/Username) ---
		{
			RECT r = { 25, 165, 25 + 220, 165 + 30 };
			FillRoundedRect(hdc, r, RGB(255, 255, 255), 12);
			HPEN p = CreatePen(PS_SOLID, 1, RGB(200, 200, 200));
			HGDIOBJ old = SelectObject(hdc, p);
			RoundRect(hdc, r.left, r.top, r.right, r.bottom, 12, 12);
			SelectObject(hdc, old);
			DeleteObject(p);
		}

		// Soft bottom border under header
		HPEN penHeader = CreatePen(PS_SOLID, 1, RGB(225, 225, 225));
		HPEN oldPenHeader = (HPEN)SelectObject(hdc, penHeader);
		MoveToEx(hdc, 0, 70, NULL);
		LineTo(hdc, rc.right, 70);
		SelectObject(hdc, oldPenHeader);
		DeleteObject(penHeader);

		// ------------------------------------------------------------
// Sidebar panel (two-tone)
// ------------------------------------------------------------
		RECT rcSidebarTop = { 0, 70, 260, 200 };           // top area (Devices + filters)
		RECT rcSidebarBottom = { 0, 200, 260, rc.bottom }; // device list area

		// Slightly darker gray for header part
		HBRUSH brTop = CreateSolidBrush(RGB(220, 222, 226));    // #DCDC E2
		FillRect(hdc, &rcSidebarTop, brTop);
		DeleteObject(brTop);

		// Lighter shade for device list background
		HBRUSH brBottom = CreateSolidBrush(RGB(235, 237, 240)); // #EBEDF0
		FillRect(hdc, &rcSidebarBottom, brBottom);
		DeleteObject(brBottom);

		// Optional subtle line between the two tones
		HPEN penSep = CreatePen(PS_SOLID, 1, RGB(210, 210, 210));
		HPEN oldPenSep = (HPEN)SelectObject(hdc, penSep);
		MoveToEx(hdc, 0, 200, NULL);
		LineTo(hdc, 260, 200);
		SelectObject(hdc, oldPenSep);
		DeleteObject(penSep);

		// Draw sidebar header text "Devices"
		SetBkMode(hdc, TRANSPARENT);
		SetTextColor(hdc, RGB(30, 30, 30));  // dark gray text
		HFONT hFontHeader = CreateFont(20, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
			DEFAULT_CHARSET, OUT_OUTLINE_PRECIS, CLIP_DEFAULT_PRECIS,
			CLEARTYPE_QUALITY, VARIABLE_PITCH, TEXT("Segoe UI"));
		HFONT hOldFont = (HFONT)SelectObject(hdc, hFontHeader);

		//  Adjust X and Y for alignment — you can tweak
		TextOut(hdc, 15, 100, L"Devices", 7);

		SelectObject(hdc, hOldFont);
		DeleteObject(hFontHeader);
		// ------------------------------------------------------------
	   // Draw Device Cards (left sidebar section)
	   // ------------------------------------------------------------
		int cardY = 210; // start position
		const auto& list = g_filteredDevices.empty() ? g_devices : g_filteredDevices;
		for (int i = 0; i < (int)list.size(); ++i) {
			const auto& d = list[i];

			RECT rcCard = { 15, cardY, 235, cardY + 65 };

			// --- Smooth rounded white card ---
			FillRoundedRect(hdc, rcCard, RGB(255, 255, 255), 18); // smoother corners (18 px)

			// Device Name (bold black)
			SetBkMode(hdc, TRANSPARENT);
			SetTextColor(hdc, RGB(30, 30, 30));
			HFONT hFontName = CreateFont(17, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
				DEFAULT_CHARSET, OUT_OUTLINE_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
				VARIABLE_PITCH, L"Segoe UI");
			HFONT oldFont = (HFONT)SelectObject(hdc, hFontName);
			TextOut(hdc, rcCard.left + 15, rcCard.top + 8, d.name.c_str(), d.name.size());
			SelectObject(hdc, oldFont);
			DeleteObject(hFontName);

			// Line 2: admin@IP
			SetTextColor(hdc, RGB(100, 100, 100));
			std::wstring line2 = d.username + L"@" + d.ip;
			HFONT hSmallFont = CreateFont(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
				DEFAULT_CHARSET, OUT_OUTLINE_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
				VARIABLE_PITCH, L"Segoe UI");
			HFONT oldFont2 = (HFONT)SelectObject(hdc, hSmallFont);
			TextOut(hdc, rcCard.left + 15, rcCard.top + 32, line2.c_str(), line2.size());

			// Line 3: Port 22
			std::wstring line3 = L"Port: " + std::to_wstring(d.port);
			TextOut(hdc, rcCard.left + 15, rcCard.top + 50, line3.c_str(), line3.size());

			SelectObject(hdc, oldFont2);
			DeleteObject(hSmallFont);

			cardY += 75;
		}


		// Light separator line between sidebar and content
		HPEN penSide = CreatePen(PS_SOLID, 1, RGB(220, 220, 220));
		HPEN oldPenSide = (HPEN)SelectObject(hdc, penSide);
		MoveToEx(hdc, 260, 70, NULL);
		LineTo(hdc, 260, rc.bottom);
		SelectObject(hdc, oldPenSide);
		DeleteObject(penSide);

		// Header line
		HPEN pen = CreatePen(PS_SOLID, 1, RGB(220, 220, 220));
		HPEN oldPen = (HPEN)SelectObject(hdc, pen);
		MoveToEx(hdc, 0, 70, NULL);
		LineTo(hdc, rc.right, 70);
		SelectObject(hdc, oldPen);
		DeleteObject(pen);

		// Draw search icon before Task button
		DrawSearchIcon(hdc, 40, 35);

		// ------------------------------------------------------------
		// Right Panel: Session History List
		// ------------------------------------------------------------
		RECT rcText = { 300, 120, rc.right - 50, rc.bottom - 100 };
		int lineY = rcText.top;
		SetBkMode(hdc, TRANSPARENT);

		HFONT hFont = CreateFont(18, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
			DEFAULT_CHARSET, OUT_OUTLINE_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
			VARIABLE_PITCH, L"Segoe UI");
		HFONT oldFont = (HFONT)SelectObject(hdc, hFont);

		SetTextColor(hdc, RGB(0, 102, 204));
		TextOut(hdc, rcText.left, lineY, L"Session History:", 17);
		lineY += 35;

		if (g_sessions.empty()) {
			SetTextColor(hdc, COLOR_GRAY);
			TextOut(hdc, rcText.left + 20, lineY, L"No active sessions", 19);
		}
		else {
			for (const auto& s : g_sessions) {
				// Draw main session info
				std::wstring line = L"Device: " + s.device + L" | User: " + s.user +
					L" | IP: " + s.ip + L" | Status:";

				SetTextColor(hdc, RGB(0, 102, 204)); // blue text for info
				TextOut(hdc, rcText.left + 20, lineY, line.c_str(), line.size());

				// Draw status aligned in one straight column
				int statusX = rcText.left + 550;
				COLORREF statusColor = s.active ? RGB(0, 180, 0) : RGB(220, 0, 0);
				SetTextColor(hdc, statusColor);
				std::wstring status = s.active ? L"Active" : L"Ended";
				TextOut(hdc, statusX, lineY, status.c_str(), status.size());

				lineY += 25;
			}
		}
		SelectObject(hdc, oldFont);
		DeleteObject(hFont);

		// --- Draw rounded borders around search boxes ---
		{
			HPEN penBorder = CreatePen(PS_SOLID, 1, RGB(210, 210, 210));
			HGDIOBJ oldPen = SelectObject(hdc, penBorder);
			HBRUSH hNull = (HBRUSH)GetStockObject(NULL_BRUSH);
			HGDIOBJ oldBrush = SelectObject(hdc, hNull);

			// top search bar
			RoundRect(hdc, 420, 25, 420 + 260, 25 + 25, 10, 10);

			// right search bar
			RoundRect(hdc, 30, 170, 30 + 210, 170 + 25, 10, 10);

			SelectObject(hdc, oldPen);
			SelectObject(hdc, oldBrush);
			DeleteObject(penBorder);
		}


		EndPaint(hwnd, &ps);
	}
	break;

	case WM_KEYDOWN:
		// Detect when Enter is pressed
		if (wParam == VK_RETURN)
		{
			HWND focus = GetFocus();
			if (focus == hSearchBox)
			{
				// Trigger top search (task/change)
				SendMessage(hwnd, WM_COMMAND, MAKEWPARAM(3, BN_CLICKED), 0);
			}
			else if (focus == hSearchDevices)
			{
				// Trigger right search (device/username)
				SendMessage(hwnd, WM_COMMAND, MAKEWPARAM(11, BN_CLICKED), 0);
			}
		}
		break;

	case WM_LBUTTONDOWN:
	{
		int x = GET_X_LPARAM(lParam);
		int y = GET_Y_LPARAM(lParam);

		int cardY = 210;  // same y start as your card drawing
		for (int i = 0; i < (int)g_devices.size(); ++i) {
			RECT rcCard = { 30, cardY, 250, cardY + 65 };

			// If mouse click is inside this card rectangle
			if (PtInRect(&rcCard, POINT{ x, y })) {
				selectedDeviceId = g_devices[i].id;
				logEvent(L"[CLICK] Device clicked: " + g_devices[i].name);

				// Open PAM login window
				ShowPAMLoginDialog(hwnd);
				break;
			}

			cardY += 75; // move to next card position
		}
	}
	break;

	case WM_CTLCOLOREDIT:
	{
		HDC hdcEdit = (HDC)wParam;
		HWND hwndEdit = (HWND)lParam;

		// For the LEFT sidebar search bar
		if (hwndEdit == hSearchDevices)
		{
			SetBkColor(hdcEdit, RGB(255, 255, 255));   // white background
			SetTextColor(hdcEdit, RGB(0, 0, 0));       // black text visible typing
			static HBRUSH hbrWhite = CreateSolidBrush(RGB(255, 255, 255));
			return (INT_PTR)hbrWhite;
		}

		// For the TOP search bar (optional same style)
		if (hwndEdit == hSearchBox)
		{
			SetBkColor(hdcEdit, RGB(255, 255, 255));
			SetTextColor(hdcEdit, RGB(0, 0, 0));
			static HBRUSH hbrWhiteTop = CreateSolidBrush(RGB(255, 255, 255));
			return (INT_PTR)hbrWhiteTop;
		}

		return DefWindowProc(hwnd, msg, wParam, lParam);
	}

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

	// -------------------- FETCH /api/vault --------------------
	std::wstring vaultResponse;
	HINTERNET hSessionVault = WinHttpOpen(L"QCM MultiSSH/1.0",
		WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
		WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);

	if (hSessionVault)
	{
		HINTERNET hConnectVault = WinHttpConnect(hSessionVault, L"192.168.8.199", 9000, 0);
		if (hConnectVault)
		{
			HINTERNET hRequestVault = WinHttpOpenRequest(hConnectVault, L"GET", L"/api/vault",
				NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
			if (hRequestVault)
			{
				if (WinHttpSendRequest(hRequestVault, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
					WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
					WinHttpReceiveResponse(hRequestVault, NULL))
				{
					DWORD dwSizeVault = 0;
					do {
						WinHttpQueryDataAvailable(hRequestVault, &dwSizeVault);
						if (!dwSizeVault) break;

						std::vector<char> buffer(dwSizeVault + 1);
						DWORD dwDownloadedVault = 0;

						if (WinHttpReadData(hRequestVault, buffer.data(), dwSizeVault, &dwDownloadedVault) && dwDownloadedVault > 0) {
							buffer[dwDownloadedVault] = '\0';
							std::wstring wPart(buffer.begin(), buffer.end());
							vaultResponse += wPart;
						}
					} while (dwSizeVault > 0);

					logEvent(L"[INFO] Vault data fetched successfully");
				}
				else {
					logEvent(L"[ERROR] Failed to fetch /api/vault, code: " + std::to_wstring(GetLastError()));
				}

				WinHttpCloseHandle(hRequestVault);
			}
			WinHttpCloseHandle(hConnectVault);
		}
		WinHttpCloseHandle(hSessionVault);
	}

	vaultUtf8.assign(vaultResponse.begin(), vaultResponse.end());

	if (response.empty())
		logEvent(L"[WARN] Empty response received from backend");
	else
		logEvent(L"[INFO] Devices fetched successfully from backend");

	return response;
}

// ------------------------------------------------------------
// PAM popup WndProc (with ticket validation)
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
			case 201: // OK clicked
			{
				wchar_t username[100], password[100], ticketno[100];

				// --- Fetch all three fields properly ---
				GetWindowText(GetDlgItem(hwnd, 101), username, 100);   // Username
				GetWindowText(GetDlgItem(hwnd, 102), password, 100);   // Password
				GetWindowText(GetDlgItem(hwnd, 103), ticketno, 100);   // TSK/CHG number

				// --- Convert to std::string ---
				std::string userStr(username, username + wcslen(username));
				std::string passStr(password, password + wcslen(password));
				std::string ticketStr(ticketno, ticketno + wcslen(ticketno));

				//  Validation: Either Task No OR Change No must be filled
				if (ticketStr.empty()) {
					MessageBox(hwnd, L"Please enter Task Number or Change Number.", L"Input Required", MB_OK | MB_ICONWARNING);
					return 0;
				}

				// --- Step 1: Validate PAM credentials ---
				int result = ValidatePAMCredentials(userStr, passStr);
				if (result != 200)
				{
					MessageBox(hwnd, L"Invalid credentials or server error.", L"Error", MB_OK | MB_ICONERROR);
					return 0;
				}

				logEvent(L"[PAM LOGIN] Auth success; validating ticket...");


				// --- Step 2: Validate Ticket ---
				DWORD status = 0;
				std::string response;

				std::string body = "{";
				body += "\"device_id\":" + std::to_string(selectedDeviceId);

				if (!ticketStr.empty()) {
					if (ticketStr.rfind("TSK", 0) == 0 || ticketStr.rfind("tsk", 0) == 0)
						body += ", \"task_number\": \"" + ticketStr + "\"";
					else if (ticketStr.rfind("CHG", 0) == 0 || ticketStr.rfind("chg", 0) == 0)
						body += ", \"change_number\": \"" + ticketStr + "\"";
					else
						body += ", \"ticket_number\": \"" + ticketStr + "\""; // fallback generic key
				}

				body += "}";

				logEvent(L"[DEBUG] Ticket JSON: " + s2ws(body));

				bool ok = http_post_json(L"192.168.8.199", 9000, L"/api/validate_ticket", body, &status, response);

				// --- handle response ---
				if (!ok) {
					logEvent(L"[ERROR] HTTP request failed");
					MessageBox(hwnd, L"Server connection failed.", L"Error", MB_OK | MB_ICONERROR);
					return 0;
				}

				if (status != 200) {
					std::wstring msg = L"Server returned status " + std::to_wstring(status);
					logEvent(msg);
					MessageBox(hwnd, msg.c_str(), L"Error", MB_OK | MB_ICONERROR);
					return 0;
				}

				if (response.find("\"allowed\":true") == std::string::npos) {
					MessageBox(hwnd, L"Access denied. Invalid or missing ticket.", L"Ticket Validation Failed", MB_OK | MB_ICONERROR);
					logEvent(L"[ACCESS DENIED] Ticket validation failed");
					return 0;
				}

				// --- Step 3: Launch SSH session (same as before) ---
				std::wstring postUrl = L"/api/sessions/" + g_sessionUuid + L"/device/" +
					std::to_wstring(selectedDeviceId) + L"/authenticate";
				std::string jsonBody = std::string("{\"username\":\"") + userStr + "\",\"password\":\"" + passStr + "\"}";

				if (http_post_json(L"192.168.8.199", 9000, postUrl, jsonBody, &status, response))
				{
					std::wstring sshUser = s2ws(json_s(response, "ssh_username"));
					std::wstring sshPass = s2ws(json_s(response, "ssh_password"));
					std::wstring sshHost = s2ws(json_s(response, "host"));

					std::wstring cmd = L"\"C:\\Program Files\\PuTTY\\putty.exe\" -ssh " +
						sshHost + L" -l \"" + sshUser + L"\" -pw \"" + sshPass + L"\"";

					STARTUPINFOW si = { sizeof(si) };
					PROCESS_INFORMATION pi{};
					if (CreateProcessW(nullptr, &cmd[0], nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi))
					{
						logEvent(L"[INFO] SSH session launched via PuTTY");

						// Add new active session to global vector
						SessionInfo s;

						// Find matching device name from g_devices using selectedDeviceId
						auto it = std::find_if(g_devices.begin(), g_devices.end(),
							[](const DeviceInfo& d) { return d.id == selectedDeviceId; });

						if (it != g_devices.end())
							s.device = it->name;  // use actual device name
						else
							s.device = L"Unknown Device";

						s.user = sshUser;
						s.ip = sshHost;
						s.active = true;

						g_sessions.push_back(s);

						// Immediately refresh UI
						InvalidateRect(GetParent(hwnd), NULL, TRUE);
						UpdateWindow(GetParent(hwnd));

						// ------------------------------------------------------------
					   // Background thread: independent watcher for each SSH session
					   // ------------------------------------------------------------
						HANDLE hProcCopy = pi.hProcess;
						HANDLE hThreadCopy = pi.hThread;
						std::wstring thisUser = sshUser;
						std::wstring thisHost = sshHost;

						std::thread([hProcCopy, hThreadCopy, thisUser, thisHost, hwnd]() {
							DWORD waitResult = WaitForSingleObject(hProcCopy, INFINITE);

							// Debug log — to confirm detection
							logEvent(L"[THREAD] PuTTY process ended for " + thisUser + L"@" + thisHost +
								L" (WaitForSingleObject=" + std::to_wstring(waitResult) + L")");

							CloseHandle(hThreadCopy);
							CloseHandle(hProcCopy);

							// Mark this session as Ended
							bool updated = false;
							for (auto& sess : g_sessions) {
								if (sess.user == thisUser && sess.ip == thisHost && sess.active) {
									sess.active = false;
									updated = true;
									logEvent(L"[SESSION] Marked Ended for " + thisUser + L"@" + thisHost);
									break;
								}
							}

							// Refresh UI if updated
							if (updated) {
								HWND parent = GetParent(hwnd);
								if (parent) {
									logEvent(L"[UI REFRESH] Session status updated on screen");
									InvalidateRect(parent, NULL, TRUE);
									UpdateWindow(parent);                // force immediate repaint
								}
							}
							else {
								logEvent(L"[WARN] Session not found for update (" + thisUser + L"@" + thisHost + L")");
							}
						}).detach();

						MessageBoxW(hwnd, L"SSH session launched successfully!", L"Success", MB_OK);
					}
					else
					{
						MessageBoxW(hwnd, L"Failed to start SSH session.", L"Error", MB_OK);
					}
				}
				else
				{
					MessageBoxW(hwnd, L"Failed to fetch SSH credentials.", L"Error", MB_OK);
				}

				DestroyWindow(hwnd);
				return 0;
			}
			case 202:
				DestroyWindow(hwnd);
				return 0;
			}
		}
		break;

	case WM_CLOSE:
		DestroyWindow(hwnd);
		return 0;
	}
	return DefWindowProc(hwnd, msg, wParam, lParam);
}
// ------------------------------------------------------------
// Simple PAM login popup (now with Task + Change number fields)
// ------------------------------------------------------------
void ShowPAMLoginDialog(HWND hwndParent)
{
	HWND hDialog = CreateWindowEx(
		WS_EX_DLGMODALFRAME,
		L"STATIC",
		L"PAM Login",
		WS_CAPTION | WS_SYSMENU | WS_POPUPWINDOW | WS_VISIBLE,
		400, 250, 320, 270,
		hwndParent, NULL, hInst, NULL);

	if (!hDialog) {
		logEvent(L"[ERROR] Failed to create PAM Login window");
		return;
	}

	CreateWindow(L"STATIC", L"Enter PAM Credentials:", WS_CHILD | WS_VISIBLE,
		50, 20, 200, 20, hDialog, NULL, hInst, NULL);

	CreateWindow(L"STATIC", L"Username:", WS_CHILD | WS_VISIBLE,
		30, 55, 80, 20, hDialog, NULL, hInst, NULL);
	CreateWindow(L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
		120, 55, 160, 20, hDialog, (HMENU)101, hInst, NULL);

	CreateWindow(L"STATIC", L"Password:", WS_CHILD | WS_VISIBLE,
		30, 85, 80, 20, hDialog, NULL, hInst, NULL);
	CreateWindow(L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_PASSWORD | ES_AUTOHSCROLL,
		120, 85, 160, 20, hDialog, (HMENU)102, hInst, NULL);

	CreateWindow(L"STATIC", L"TSK / CHG No:", WS_CHILD | WS_VISIBLE,
		30, 115, 90, 20, hDialog, NULL, hInst, NULL);
	CreateWindow(L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
		130, 115, 150, 20, hDialog, (HMENU)103, hInst, NULL);

	CreateWindow(L"BUTTON", L"OK", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
		70, 190, 70, 25, hDialog, (HMENU)201, hInst, NULL);
	CreateWindow(L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE,
		170, 190, 70, 25, hDialog, (HMENU)202, hInst, NULL);

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

	std::wstring cmdLine = GetCommandLineW();
	logEvent(L"[INFO] Command line: " + cmdLine);

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


	if (!uuid.empty()) {
		g_sessionUuid = uuid;  //  set global for later use
		std::wstring msg = L"[MultiSSH] Started with UUID=" + uuid + L" Protocol=" + protocol;
		OutputDebugStringW(msg.c_str());
		logEvent(msg);  // optional, to log it
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
		WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
		CW_USEDEFAULT, CW_USEDEFAULT, 950, 600,
		NULL, NULL, hInstance, NULL);

	// ------------------------------------------------------------
   // Enable dark title bar (Windows 10+)
   // ------------------------------------------------------------
	BOOL dark = TRUE;
	DwmSetWindowAttribute(hwnd, 20, &dark, sizeof(dark));  // DWMWA_USE_IMMERSIVE_DARK_MODE

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

bool http_post_json(const wchar_t* host, int port, const std::wstring& path,
	const std::string& body, DWORD* status, std::string& responseOut) {
	HINTERNET hSession = WinHttpOpen(L"MultiSSHClient/1.0",
		WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
	if (!hSession) return false;

	HINTERNET hConnect = WinHttpConnect(hSession, host, port, 0);
	if (!hConnect) { WinHttpCloseHandle(hSession); return false; }

	HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"POST", path.c_str(),
		NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
	if (!hRequest) { WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession); return false; }

	BOOL bResults = WinHttpSendRequest(hRequest,
		L"Content-Type: application/json\r\n", -1L,
		(LPVOID)body.c_str(), body.size(), body.size(), 0);

	if (!bResults) {
		WinHttpCloseHandle(hRequest); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession);
		return false;
	}

	WinHttpReceiveResponse(hRequest, NULL);

	DWORD statusCode = 0; DWORD size = sizeof(statusCode);
	WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
		WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &size, WINHTTP_NO_HEADER_INDEX);
	*status = statusCode;

	DWORD dwSize = 0;
	responseOut.clear();
	do {
		WinHttpQueryDataAvailable(hRequest, &dwSize);
		if (!dwSize) break;
		std::vector<char> buffer(dwSize + 1);
		DWORD dwDownloaded = 0;
		if (WinHttpReadData(hRequest, buffer.data(), dwSize, &dwDownloaded)) {
			buffer[dwDownloaded] = '\0';
			responseOut += buffer.data();
		}
	} while (dwSize > 0);

	WinHttpCloseHandle(hRequest);
	WinHttpCloseHandle(hConnect);
	WinHttpCloseHandle(hSession);

	return true;
}
