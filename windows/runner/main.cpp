#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>  // SetCurrentProcessExplicitAppUserModelID-এর জন্য

#include "flutter_window.h"
#include "utils.h"

// Register AppUserModelID in Windows Registry so Windows SMTC media flyout
// and notification controls display "TeloPlay" instead of "Unknown app".
void RegisterAppUserModelId() {
  wchar_t exePath[MAX_PATH];
  ::GetModuleFileNameW(nullptr, exePath, MAX_PATH);

  HKEY hKey;
  const wchar_t* subKey = L"Software\\Classes\\AppUserModelId\\com.piyas.teloplay";
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, subKey, 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr,
                        &hKey, nullptr) == ERROR_SUCCESS) {
    const wchar_t* displayName = L"TeloPlay";
    ::RegSetValueExW(hKey, L"DisplayName", 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(displayName),
                     static_cast<DWORD>((wcslen(displayName) + 1) * sizeof(wchar_t)));
    ::RegSetValueExW(hKey, L"IconUri", 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(exePath),
                     static_cast<DWORD>((wcslen(exePath) + 1) * sizeof(wchar_t)));
    DWORD showInSettings = 1;
    ::RegSetValueExW(hKey, L"ShowInSettings", 0, REG_DWORD,
                     reinterpret_cast<const BYTE*>(&showInSettings),
                     sizeof(DWORD));
    ::RegCloseKey(hKey);
  }
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

  // Register AUMID DisplayName in Registry and set process explicit AUMID
  // so Windows System Media Transport Controls (SMTC) shows "TeloPlay"
  // instead of "Unknown app".
  RegisterAppUserModelId();
  ::SetCurrentProcessExplicitAppUserModelID(L"com.piyas.teloplay");

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"TeloPlay", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}