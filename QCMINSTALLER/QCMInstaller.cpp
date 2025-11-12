#include <windows.h>
#include <iostream>
#include <filesystem>
#include <string>
#include <fstream>

#pragma comment(lib, "Shlwapi.lib")
namespace fs = std::filesystem;

// ------------------- Helper MessageBox -------------------
static void ShowMessage(const std::wstring& text,
	const std::wstring& title = L"QCM Installer",
	UINT type = MB_OK | MB_ICONINFORMATION) {
	MessageBoxW(NULL, text.c_str(), title.c_str(), type);
}

// ------------------- Main -------------------
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
	// Step 1: Terms & Conditions
	int resp = MessageBoxW(NULL,
		L"By continuing, you agree to install QCM components.\n\nDo you accept the Terms and Conditions?",
		L"QCM Installer - Terms and Conditions",
		MB_YESNO | MB_ICONQUESTION);
	if (resp == IDNO) {
		ShowMessage(L"Installation cancelled by user.");
		return 0;
	}

	// Step 2: Console input for backend URL/IP
	AllocConsole();
	FILE* fpstdin = stdin, *fpstdout = stdout;
	freopen_s(&fpstdin, "CONIN$", "r", stdin);
	freopen_s(&fpstdout, "CONOUT$", "w", stdout);

	std::wstring backendUrl;
	std::wcout << L"Enter Backend URL or IP (e.g., 192.168.8.199:9000): ";
	std::getline(std::wcin, backendUrl);

	if (backendUrl.empty()) {
		ShowMessage(L"No backend entered. Aborting.", L"QCM Installer", MB_OK | MB_ICONERROR);
		FreeConsole();
		return 1;
	}

	// Step 3: Create install directory
	const std::wstring installDir = L"C:\\Program Files\\QCM\\";
	try { fs::create_directories(installDir); }
	catch (...) {
		ShowMessage(L"Failed to create installation directory.", L"QCM Installer", MB_OK | MB_ICONERROR);
		FreeConsole();
		return 1;
	}

	// Step 4: Save config
	{
		std::wofstream cfg(installDir + L"config.txt");
		cfg << L"BACKEND_URL=" << backendUrl << std::endl;
	}

	// Step 5: Copy payloads
	const std::wstring payload = L".\\payload\\";
	try {
		for (const auto& f : fs::directory_iterator(payload)) {
			fs::path src = f.path();
			fs::path dst = installDir + src.filename().wstring();
			fs::copy_file(src, dst, fs::copy_options::overwrite_existing);
		}
	}
	catch (...) {
		ShowMessage(L"Copy failed. Ensure \\payload has the EXEs.", L"QCM Installer", MB_OK | MB_ICONERROR);
		FreeConsole();
		return 1;
	}

	// Step 6: Install services
	const std::wstring cjPath = installDir + L"CJNew.exe";
	const std::wstring recPath = installDir + L"QCMREC.exe";
	const std::wstring chPath = installDir + L"qcm_autologin_service.exe";

	// Parse host & port
	std::wstring host = backendUrl, port = L"9000";
	size_t p = host.find(L"://"); if (p != std::wstring::npos) host = host.substr(p + 3);
	p = host.find(L':'); if (p != std::wstring::npos) { port = host.substr(p + 1); host = host.substr(0, p); }

	std::wstring cmdCJ = L"\"" + cjPath + L"\" --install-cj " + host + L" " + port + L" 5555";
	std::wstring cmdREC = L"sc create QCMREC binPath= \"" + recPath + L"\" start= auto";
	std::wstring cmdCHInstall = L"\"" + chPath + L"\" --install";

	_wsystem(cmdCJ.c_str());
	_wsystem(cmdREC.c_str());
	_wsystem(cmdCHInstall.c_str());

	_wsystem(L"sc start CJService");
	_wsystem(L"sc start QCMREC");
	_wsystem(L"sc start QCMChromeService");

	ShowMessage(L"Installation complete.\nServices installed/started.\nReboot recommended.");
	FreeConsole();
	return 0;
}
