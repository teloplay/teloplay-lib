#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>   // SHGetPropertyStoreForWindow (shellapi.h, not propsys.h)
#include <shobjidl.h>   // SetCurrentProcessExplicitAppUserModelID + shortcut APIs
#include <shlguid.h>    // CLSID_ShellLink
#include <shlobj.h>     // SHChangeNotify, SHGetFolderPath
#include <propkey.h>    // PKEY_AppUserModel_ID
#include <propvarutil.h>  // InitPropVariantFromString
#include <propsys.h>    // SHGetPropertyStoreForWindow, IPropertyStore

#include "flutter_window.h"
#include "utils.h"

// SMTC / volume flyout shows the name resolved from this AUMID.
// Keep in sync with the shortcut + window property below.
constexpr wchar_t kTeloPlayAumid[] = L"com.piyas.teloplay";
constexpr wchar_t kTeloPlayDisplayName[] = L"TeloPlay";

// Register AppUserModelID in Windows Registry so Windows SMTC media flyout
// and notification controls display "TeloPlay" instead of "Unknown app".
void RegisterAppUserModelId() {
  wchar_t exePath[MAX_PATH];
  ::GetModuleFileNameW(nullptr, exePath, MAX_PATH);

  // IconUri for a classic Win32 exe must be "path,resourceIndex" —
  // a bare exe path is ignored and Windows falls back to "Unknown app".
  wchar_t iconUri[MAX_PATH + 8];
  ::swprintf_s(iconUri, L"%s,0", exePath);

  HKEY hKey;
  const wchar_t* subKey = L"Software\\Classes\\AppUserModelId\\com.piyas.teloplay";
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, subKey, 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr,
                        &hKey, nullptr) == ERROR_SUCCESS) {
    ::RegSetValueExW(hKey, L"DisplayName", 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(kTeloPlayDisplayName),
                     static_cast<DWORD>((wcslen(kTeloPlayDisplayName) + 1) * sizeof(wchar_t)));
    ::RegSetValueExW(hKey, L"IconUri", 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(iconUri),
                     static_cast<DWORD>((wcslen(iconUri) + 1) * sizeof(wchar_t)));
    DWORD showInSettings = 1;
    ::RegSetValueExW(hKey, L"ShowInSettings", 0, REG_DWORD,
                     reinterpret_cast<const BYTE*>(&showInSettings),
                     sizeof(DWORD));
    ::RegCloseKey(hKey);
  }
}

// Windows resolves the SMTC/volume-flyout app name through a Start Menu
// shortcut carrying the same AUMID. Without this shortcut an unpackaged
// Win32 app (like `flutter run` / `flutter build windows` output) shows up
// as "Unknown app" even when the process AUMID + registry are correct.
// Re-created on every launch so `flutter run` rebuilds (new exe path)
// never leave a stale shortcut behind.
void EnsureStartMenuShortcut() {
  wchar_t exePath[MAX_PATH];
  ::GetModuleFileNameW(nullptr, exePath, MAX_PATH);

  wchar_t programsDir[MAX_PATH];
  if (FAILED(::SHGetFolderPathW(nullptr, CSIDL_PROGRAMS, nullptr,
                                SHGFP_TYPE_CURRENT, programsDir))) {
    return;
  }

  wchar_t shortcutPath[MAX_PATH];
  ::swprintf_s(shortcutPath, L"%s\\TeloPlay.lnk", programsDir);

  // Skip re-creating when the shortcut already points at this exe.
  DWORD attrs = ::GetFileAttributesW(shortcutPath);
  if (attrs != INVALID_FILE_ATTRIBUTES) {
    IShellLinkW* existing = nullptr;
    if (SUCCEEDED(::CoCreateInstance(CLSID_ShellLink, nullptr,
                                     CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&existing)))) {
      IPersistFile* persist = nullptr;
      if (SUCCEEDED(existing->QueryInterface(IID_PPV_ARGS(&persist)))) {
        if (SUCCEEDED(persist->Load(shortcutPath, STGM_READ))) {
          wchar_t target[MAX_PATH] = {};
          if (SUCCEEDED(existing->GetPath(target, MAX_PATH, nullptr, 0)) &&
              ::_wcsicmp(target, exePath) == 0) {
            persist->Release();
            existing->Release();
            return;
          }
        }
        persist->Release();
      }
      existing->Release();
    }
  }

  IShellLinkW* shellLink = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&shellLink)))) {
    return;
  }

  shellLink->SetPath(exePath);
  shellLink->SetDescription(L"TeloPlay - YouTube Music Stream");
  shellLink->SetIconLocation(exePath, 0);

  // Tag the shortcut itself with our AUMID so the shell maps the
  // running process (same explicit AUMID) back to "TeloPlay".
  IPropertyStore* store = nullptr;
  if (SUCCEEDED(shellLink->QueryInterface(IID_PPV_ARGS(&store)))) {
    PROPVARIANT pv;
    if (SUCCEEDED(::InitPropVariantFromString(kTeloPlayAumid, &pv))) {
      store->SetValue(PKEY_AppUserModel_ID, pv);
      store->Commit();
      ::PropVariantClear(&pv);
    }
    store->Release();
  }

  IPersistFile* persistFile = nullptr;
  if (SUCCEEDED(shellLink->QueryInterface(IID_PPV_ARGS(&persistFile)))) {
    persistFile->Save(shortcutPath, TRUE);
    persistFile->Release();
  }
  shellLink->Release();

  ::SHChangeNotify(SHCNE_CREATE | SHCNE_UPDATEITEM,
                   SHCNF_PATHW, shortcutPath, nullptr);
}

// Tag the top-level window with the same AUMID so taskbar grouping,
// volume flyout and notification center all resolve to "TeloPlay".
void SetWindowAppUserModelId(HWND hwnd) {
  IPropertyStore* store = nullptr;
  if (FAILED(::SHGetPropertyStoreForWindow(hwnd, IID_PPV_ARGS(&store)))) {
    return;
  }
  PROPVARIANT pv;
  if (SUCCEEDED(::InitPropVariantFromString(kTeloPlayAumid, &pv))) {
    store->SetValue(PKEY_AppUserModel_ID, pv);
    ::PropVariantClear(&pv);
  }
  store->Release();
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Register AUMID DisplayName in Registry, make sure a Start Menu
  // shortcut carries the same AUMID, and set the process explicit AUMID
  // so Windows System Media Transport Controls (SMTC) shows "TeloPlay"
  // instead of "Unknown app".
  RegisterAppUserModelId();
  EnsureStartMenuShortcut();
  ::SetCurrentProcessExplicitAppUserModelID(kTeloPlayAumid);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);  // P1-J — unified with Dart WindowOptions (1280x800): the native window
  // used to start at 720px height and visibly jump when Dart applied 800.
  Win32Window::Size size(1280, 800);
  if (!window.Create(L"TeloPlay", origin, size)) {
    return EXIT_FAILURE;
  }
  // Must run after Create() — needs a valid HWND.
  SetWindowAppUserModelId(window.GetHandle());
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}