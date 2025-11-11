#include <windows.h>
#include <iostream>
#include <filesystem>
#include <string>
#include <fstream>

#pragma comment(lib, "Shlwapi.lib")
namespace fs = std::filesystem;

static void ShowMessage(const std::wstring& text,
	const std::wstring& title = L"QCM Installer",
	UINT type = MB_OK | MB_ICONINFORMATION) {
	MessageBoxW(NULL, text.c_str(), title.c_str(), type);
}

int main() {
	// Terms & Conditions
	int resp = MessageBoxW(NULL,
		L"By continuing, you agree to install QCM components.\n\nDo you accept the Terms and Conditions?",
		L"QCM Installer - Terms and Conditions",
		MB_YESNO | MB_ICONQUESTION);
	if (resp == IDNO) {
		ShowMessage(L"Installation cancelled by user.");
		return 0;
	}

	// Ask backend URL/IP (console prompt)
	std::wstring backendUrl;
	std::wcout << L"=== QCM Installer Started ===\n";
	std::wcout << L"Enter backend URL or IP (e.g., http://192.168.8.199:9000): ";
	std::getline(std::wcin, backendUrl);
	if (backendUrl.empty()) {
		ShowMessage(L"No backend entered. Aborting.", L"QCM Installer", MB_OK | MB_ICONERROR);
		return 1;
	}

	// Install directory
	const std::wstring installDir = L"C:\\Program Files\\QCM\\";
	try { fs::create_directories(installDir); }
	catch (...) {
		ShowMessage(L"Failed to create installation directory.", L"QCM Installer", MB_OK | MB_ICONERROR);
		return 1;
	}

	// Save config
	{
		std::wofstream cfg(installDir + L"config.txt");
		cfg << L"BACKEND_URL=" << backendUrl << std::endl;
	}

	// Copy payload EXEs (CJNew.exe, QCMREC.exe) from .\payload
	const std::wstring payload = L".\\payload\\";
	try {
		for (const auto& f : fs::directory_iterator(payload)) {
			fs::path src = f.path();
			fs::path dst = installDir + src.filename().wstring();
			fs::copy_file(src, dst, fs::copy_options::overwrite_existing);
			std::wcout << L"Copied: " << src.filename().wstring() << L"\n";
		}
	}
	catch (...) {
		ShowMessage(L"Copy failed. Ensure \\payload has the EXEs.", L"QCM Installer", MB_OK | MB_ICONERROR);
		return 1;
	}

	// Install services
	const std::wstring cjPath = installDir + L"CJNew.exe";
	const std::wstring recPath = installDir + L"QCMREC.exe";

	// CJ uses your existing CLI:  CJNew.exe --install-cj <host> <port> [listen=5555]
	// Extract host/port if user typed http://host:port ; otherwise default port 9000.
	std::wstring host = backendUrl, port = L"9000";
	// crude parse: if contains "://", strip scheme
	size_t p = host.find(L"://"); if (p != std::wstring::npos) host = host.substr(p + 3);
	// if contains colon, split host:port
	p = host.find(L':'); if (p != std::wstring::npos) { port = host.substr(p + 1); host = host.substr(0, p); }

	std::wstring cmdCJ = L"\"" + cjPath + L"\" --install-cj " + host + L" " + port + L" 5555";
	std::wstring cmdREC = L"sc create QCMREC binPath= \"" + recPath + L"\" start= auto";

	_wsystem(cmdCJ.c_str());
	_wsystem(cmdREC.c_str());

	// Start services
	_wsystem(L"sc start CJService");
	_wsystem(L"sc start QCMRECService");

	// ---- Install & start CH (Chrome Auto-Login) service ----
	std::wstring chPath = installDir + L"qcm_autologin_service.exe";

	// Step 1: Install CH service using its own internal --install command
	std::wstring cmdCHInstall = L"\"" + chPath + L"\" --install";
	_wsystem(cmdCHInstall.c_str());

	// Step 2: Start the CH service after installation
	_wsystem(L"sc start QCMChromeService");

	ShowMessage(L"Installation complete.\nServices installed/started.\nReboot recommended.");
	return 0;
}
