#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

// Lets the website open the app with v3ai-music:// links. Per-user, no admin needed;
// re-written on each start so it follows the app if its folder moves.
static void RegisterLinkScheme() {
  wchar_t exe[MAX_PATH];
  if (!::GetModuleFileNameW(nullptr, exe, MAX_PATH)) return;
  std::wstring command = L"\"" + std::wstring(exe) + L"\" \"%1\"";
  const wchar_t* key = L"Software\\Classes\\v3ai-music";
  const wchar_t* name = L"URL:music";
  ::RegSetKeyValueW(HKEY_CURRENT_USER, key, nullptr, REG_SZ, name,
                    static_cast<DWORD>((wcslen(name) + 1) * sizeof(wchar_t)));
  ::RegSetKeyValueW(HKEY_CURRENT_USER, key, L"URL Protocol", REG_SZ, L"",
                    sizeof(wchar_t));
  ::RegSetKeyValueW(HKEY_CURRENT_USER, L"Software\\Classes\\v3ai-music\\shell\\open\\command",
                    nullptr, REG_SZ, command.c_str(),
                    static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Only one copy at a time: a second launch brings the first window forward.
  HANDLE single = ::CreateMutexW(nullptr, TRUE, L"io.github.v3ai.music.single");
  if (single != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"music");
    if (existing != nullptr) {
      if (::IsIconic(existing)) ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
    return EXIT_SUCCESS;
  }
  RegisterLinkScheme();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"music", origin, size)) {
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
