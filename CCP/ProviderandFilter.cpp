// --- VS2017: silence unknown [[no_init_all]] seen in newer SDKs -------------
#ifndef _NO_INIT_ALL
#define _NO_INIT_ALL 1
#endif
#ifdef _MSC_VER
#pragma warning(disable:5030)  // ‘unknown attribute’
#endif
// ----------------------------------------------------------------------------
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <combaseapi.h>   // CoTaskMemAlloc/Free
#include <credentialprovider.h>
#include <wincred.h>
#include <strsafe.h>
#include <shlwapi.h>
#include <new>
#include <cstdarg>

#include "ComGlobals.h"     // CLSID_QCM_PAM_CP / CLSID_QCM_PAM_FILTER
#include "FieldHelpers.h"   // FieldDescriptorCopy / FieldDescriptorAllocString
#include "Credential.h"     // QcmPamCredential + TryExtractUuidToken + FetchLocalCreds + PackCreds + FIELD_ID

#pragma comment(lib, "Ws2_32.lib")
#pragma comment(lib, "shlwapi.lib")

#ifndef CPUS_REMOTE_CREDENTIAL
#define CPUS_REMOTE_CREDENTIAL ((CREDENTIAL_PROVIDER_USAGE_SCENARIO)5)
#endif

// --------- tiny file logger: C:\ProgramData\QCM\cp.log ----------------------
static void QcmFileLog(PCWSTR tag, PCWSTR fmt, ...)
{
	CreateDirectoryW(L"C:\\ProgramData\\QCM", nullptr);

	wchar_t line[1024];
	va_list ap; va_start(ap, fmt);
	StringCchVPrintfW(line, _countof(line), fmt, ap);
	va_end(ap);

	SYSTEMTIME st; GetLocalTime(&st);
	wchar_t msg[1200];
	StringCchPrintfW(msg, _countof(msg),
		L"%04u-%02u-%02u %02u:%02u:%02u [%s] %s\r\n",
		st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, tag, line);

	HANDLE h = CreateFileW(L"C:\\ProgramData\\QCM\\cp.log",
		FILE_APPEND_DATA, FILE_SHARE_READ, nullptr, OPEN_ALWAYS,
		FILE_ATTRIBUTE_NORMAL, nullptr);
	if (h != INVALID_HANDLE_VALUE) {
		DWORD cb = (DWORD)(lstrlenW(msg) * sizeof(wchar_t));
		WriteFile(h, msg, cb, &cb, nullptr);
		CloseHandle(h);
	}
}
#define LOGF(TAG, ...) QcmFileLog(TAG, __VA_ARGS__)
// ----------------------------------------------------------------------------
// --- notify CJ service on localhost:5555 with UUID ---
static void NotifyCJ_Localhost5555(const std::wstring& uuidW) {
	WSADATA w;
	if (WSAStartup(MAKEWORD(2, 2), &w) != 0) return;

	SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	if (s == INVALID_SOCKET) { WSACleanup(); return; }

	sockaddr_in a{};
	a.sin_family = AF_INET;
	a.sin_port = htons(5555);
	inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);

	if (connect(s, reinterpret_cast<sockaddr*>(&a), sizeof(a)) == 0) {
		std::string line = "CJ/1 UUID=" + std::string(uuidW.begin(), uuidW.end()) + "\n";
		send(s, line.c_str(), (int)line.size(), 0);
	}

	closesocket(s);
	WSACleanup();
}


//==========================================================================//
//                              Provider                                    //
//==========================================================================//

class QcmPamProvider : public ICredentialProvider
{
public:
	QcmPamProvider() : _cRef(1) { ZeroMemory(&_fields, sizeof(_fields)); }
	~QcmPamProvider() { if (_events) _events->Release(); if (_cred) _cred->Release(); }

	// IUnknown
	IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
		if (!ppv) return E_POINTER; *ppv = nullptr;
		if (riid == IID_IUnknown || riid == IID_ICredentialProvider) {
			*ppv = static_cast<ICredentialProvider*>(this); AddRef(); return S_OK;
		}
		return E_NOINTERFACE;
	}
	IFACEMETHODIMP_(ULONG) AddRef() override { return (ULONG)InterlockedIncrement(&_cRef); }
	IFACEMETHODIMP_(ULONG) Release() override {
		LONG c = InterlockedDecrement(&_cRef); if (!c) delete this; return (ULONG)c;
	}

	// ICredentialProvider
	IFACEMETHODIMP SetUsageScenario(CREDENTIAL_PROVIDER_USAGE_SCENARIO cpus, DWORD) override {
		_cpus = cpus;
		_auto = FALSE;
		LOGF(L"PROV", L"SetUsageScenario s=%u", (unsigned)cpus);

		// Build field descriptors once
		ZeroMemory(&_fields, sizeof(_fields));
		_fields[FI_TITLE].dwFieldID = FI_TITLE;
		_fields[FI_TITLE].cpft = CPFT_LARGE_TEXT;
		FieldDescriptorAllocString(L"QCM Secure Login", &_fields[FI_TITLE].pszLabel);

		_fields[FI_USER].dwFieldID = FI_USER;
		_fields[FI_USER].cpft = CPFT_EDIT_TEXT;
		FieldDescriptorAllocString(L"Token (qcm@<uuid>)", &_fields[FI_USER].pszLabel);

		_fields[FI_SUBMIT].dwFieldID = FI_SUBMIT;
		_fields[FI_SUBMIT].cpft = CPFT_SUBMIT_BUTTON;
		FieldDescriptorAllocString(L"Sign in", &_fields[FI_SUBMIT].pszLabel);

		return S_OK;
	}

	IFACEMETHODIMP SetSerialization(const CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION* pcpcs) override {
		// RDP often pre-fills this; capture user text so our tile can auto-submit.
		if (!pcpcs || !pcpcs->rgbSerialization || !pcpcs->cbSerialization) return S_OK;

		DWORD cu = 0, cd = 0, cp = 0;
		CredUnPackAuthenticationBufferW(0, (PVOID)pcpcs->rgbSerialization, pcpcs->cbSerialization,
			nullptr, &cu, nullptr, &cd, nullptr, &cp);

		if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && cu) {
			std::wstring u(cu, L'\0'), d(cd, L'\0'), p(cp, L'\0');
			if (CredUnPackAuthenticationBufferW(0, (PVOID)pcpcs->rgbSerialization, pcpcs->cbSerialization,
				&u[0], &cu, &d[0], &cd, &p[0], &cp)) {
				u.resize(cu); d.resize(cd);
				std::wstring full = d.empty() ? u : (d + L"\\" + u);
				LOGF(L"PROV", L"SetSerialization user='%s'", full.c_str());

				// Only auto-logon if it's our qcm@UUID token
				std::wstring tmp;
				if (TryExtractUuidToken(u.c_str(), tmp)) {
					_prefill = L"qcm@" + tmp;
					_auto = TRUE;
				}
				else {
					_prefill.clear();
					_auto = FALSE;
				}
			}
		}
		return S_OK;
	}

	IFACEMETHODIMP Advise(ICredentialProviderEvents* ev, UINT_PTR ctx) override {
		if (_events) _events->Release();
		_events = ev; _ctx = ctx;
		if (_events) _events->AddRef();
		LOGF(L"PROV", L"Advise");
		return S_OK;
	}

	IFACEMETHODIMP UnAdvise() override {
		LOGF(L"PROV", L"UnAdvise");
		if (_events) { _events->Release(); _events = nullptr; }
		_ctx = 0;
		return S_OK;
	}

	IFACEMETHODIMP GetFieldDescriptorCount(DWORD* count) override {
		if (!count) return E_POINTER; *count = FI_COUNT; return S_OK;
	}

	IFACEMETHODIMP GetFieldDescriptorAt(DWORD index, CREDENTIAL_PROVIDER_FIELD_DESCRIPTOR** ppcpfd) override {
		if (!ppcpfd) return E_POINTER;
		if (index >= FI_COUNT) return E_INVALIDARG;
		return FieldDescriptorCopy(_fields[index], ppcpfd);
	}

	IFACEMETHODIMP GetCredentialCount(DWORD* count, DWORD* def, BOOL* autoLogon) override {
		if (!count || !def || !autoLogon) return E_POINTER;
		*count = 1; *def = 0; *autoLogon = _auto;
		LOGF(L"PROV", L"GetCredentialCount auto=%u", (unsigned)_auto);
		return S_OK;
	}

	IFACEMETHODIMP GetCredentialAt(DWORD index, ICredentialProviderCredential** ppCred) override {
		if (!ppCred) return E_POINTER;
		if (index != 0) return E_INVALIDARG;

		if (!_cred) {
			_cred = new (std::nothrow) QcmPamCredential();
			if (!_cred) return E_OUTOFMEMORY;
			LOGF(L"CRED", L"constructed");
		}
		if (!_prefill.empty()) {
			LOGF(L"CRED", L"Prefill='%s'", _prefill.c_str());
			_cred->Prefill(_prefill.c_str());
			_prefill.clear();
		}
		_cred->AddRef();
		*ppCred = _cred;
		return S_OK;
	}

private:
	// state
	LONG _cRef;
	CREDENTIAL_PROVIDER_USAGE_SCENARIO _cpus = CPUS_LOGON;
	BOOL _auto = FALSE;
	ICredentialProviderEvents* _events = nullptr;
	UINT_PTR _ctx = 0;

	CREDENTIAL_PROVIDER_FIELD_DESCRIPTOR _fields[FI_COUNT];
	QcmPamCredential* _cred = nullptr;
	std::wstring _prefill;
};


//==========================================================================//
//                               Filter                                     //
//==========================================================================//

class QcmPamFilter : public ICredentialProviderFilter
{
public:
	QcmPamFilter() : _cRef(1) {}
	~QcmPamFilter() {}

	// IUnknown
	IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
		if (!ppv) return E_POINTER; *ppv = nullptr;
		if (riid == IID_IUnknown || riid == IID_ICredentialProviderFilter) {
			*ppv = static_cast<ICredentialProviderFilter*>(this); AddRef(); return S_OK;
		}
		return E_NOINTERFACE;
	}
	IFACEMETHODIMP_(ULONG) AddRef() override { return (ULONG)InterlockedIncrement(&_cRef); }
	IFACEMETHODIMP_(ULONG) Release() override {
		LONG c = InterlockedDecrement(&_cRef); if (!c) delete this; return (ULONG)c;
	}

	// ICredentialProviderFilter
	IFACEMETHODIMP Filter(CREDENTIAL_PROVIDER_USAGE_SCENARIO cpus,
		DWORD /*dwFlags*/,
		GUID* rgclsidProviders,
		BOOL* rgbAllow,
		DWORD cProviders) override
	{
		if (!rgclsidProviders || !rgbAllow) return E_INVALIDARG;

		if (cpus == CPUS_REMOTE_CREDENTIAL) {
			LOGF(L"FILTER", L"Filter cpus=REMOTE cProviders=%u", (unsigned)cProviders);
			for (DWORD i = 0; i < cProviders; ++i) {
				const bool allow = (rgclsidProviders[i] == CLSID_QCM_PAM_CP);
				rgbAllow[i] = allow ? TRUE : FALSE;
				if (allow)  LOGF(L"FILTER", L"allow QCM idx=%u", (unsigned)i);
				else        LOGF(L"FILTER", L"hide other provider idx=%u", (unsigned)i);
			}
		}
		else {
			for (DWORD i = 0; i < cProviders; ++i) rgbAllow[i] = TRUE;
		}
		return S_OK;
	}

	// *** KEY FIX ***  Transform qcm@UUID -> {user,pass} and return final creds here
	IFACEMETHODIMP UpdateRemoteCredential(
		const CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION* pIn,
		CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION* pOut) override
	{
		if (!pOut) return E_POINTER;
		ZeroMemory(pOut, sizeof(*pOut));
		if (!pIn || !pIn->rgbSerialization || !pIn->cbSerialization) return S_FALSE;

		// Unpack for inspection/logging
		DWORD cu = 0, cd = 0, cp = 0;
		CredUnPackAuthenticationBufferW(0, (PVOID)pIn->rgbSerialization, pIn->cbSerialization,
			nullptr, &cu, nullptr, &cd, nullptr, &cp);

		std::wstring u, d, p;
		if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && cu) {
			u.resize(cu); d.resize(cd); p.resize(cp);
			if (CredUnPackAuthenticationBufferW(0, (PVOID)pIn->rgbSerialization, pIn->cbSerialization,
				&u[0], &cu, &d[0], &cd, &p[0], &cp)) {
				u.resize(cu); d.resize(cd);
			}
		}
		std::wstring full = d.empty() ? u : (d + L"\\" + u);

		// If it's our token, resolve NOW and return the packed real creds
		std::wstring uuid;
		if (TryExtractUuidToken(u.c_str(), uuid)) {
			LOGF(L"FILTER", L"UpdateRemoteCredential: token seen, resolving (user='%s')", u.c_str());

			std::wstring lu, lp;
			if (FetchLocalCreds(uuid, lu, lp)) {
				// Build Negotiate blob (PackCreds sets clsidCredentialProvider to CLSID_PasswordCredentialProvider)
				HRESULT hr = PackCreds(L".", lu, lp, pOut);
				if (SUCCEEDED(hr)) {
					LOGF(L"FILTER", L"UpdateRemoteCredential: transformed token -> '%s'", lu.c_str());
					return S_OK;  // LogonUI will logon immediately with these creds
				}
				LOGF(L"FILTER", L"UpdateRemoteCredential: PackCreds failed hr=0x%08X", (UINT)hr);
				ZeroMemory(pOut, sizeof(*pOut)); // safety
				return S_FALSE; // fall back if pack failed
			}
			LOGF(L"FILTER", L"UpdateRemoteCredential: backend resolve FAILED");
			return S_FALSE; // fall back to UI path if resolve failed
		}

		// Not our token -> keep previous behavior (deep copy + retarget to our provider)
		LOGF(L"FILTER", L"UpdateRemoteCredential: pass-through (user='%s')", full.c_str());
		pOut->ulAuthenticationPackage = pIn->ulAuthenticationPackage;
		pOut->cbSerialization = pIn->cbSerialization;
		pOut->rgbSerialization = (BYTE*)CoTaskMemAlloc(pIn->cbSerialization);
		if (!pOut->rgbSerialization) return E_OUTOFMEMORY;
		CopyMemory(pOut->rgbSerialization, pIn->rgbSerialization, pIn->cbSerialization);
		pOut->clsidCredentialProvider = CLSID_QCM_PAM_CP;
		return S_OK;
	}

private:
	LONG _cRef;
};


//==========================================================================//
//                      Factory entry points (C linkage)                     //
//==========================================================================//

extern "C" HRESULT CreateQcmPamProvider(REFIID riid, void** ppv)
{
	if (!ppv) return E_POINTER; *ppv = nullptr;
	QcmPamProvider* p = new (std::nothrow) QcmPamProvider();
	if (!p) return E_OUTOFMEMORY;
	HRESULT hr = p->QueryInterface(riid, ppv);
	p->Release();
	return hr;
}

extern "C" HRESULT CreateQcmPamFilter(REFIID riid, void** ppv)
{
	if (!ppv) return E_POINTER; *ppv = nullptr;
	QcmPamFilter* p = new (std::nothrow) QcmPamFilter();
	if (!p) return E_OUTOFMEMORY;
	HRESULT hr = p->QueryInterface(riid, ppv);
	p->Release();
	return hr;
}
