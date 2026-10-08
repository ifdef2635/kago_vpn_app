#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // One copy only: the app keeps running in the tray, so starting it again
  // (Start menu, desktop shortcut) shows the running window instead of a
  // second app with a second core. While the old copy is still quitting, wait
  // for it.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, FALSE, L"Local\\KaGoVPN.SingleInstance");
  if (instance_mutex && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing =
        ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"KaGo VPN");
    if (existing) {
      DWORD process_id = 0;
      ::GetWindowThreadProcessId(existing, &process_id);
      ::AllowSetForegroundWindow(process_id);
      DWORD_PTR shown = 0;
      // Not answered (hung, or quitting): wait for that copy to end below.
      if (::SendMessageTimeoutW(existing, KagoShowMessage(), 0, 0,
                                SMTO_ABORTIFHUNG, 2000, &shown) &&
          shown == 1) {
        ::CloseHandle(instance_mutex);
        return EXIT_SUCCESS;
      }
    }
  }
  if (instance_mutex) {
    const DWORD wait = ::WaitForSingleObject(instance_mutex, 15000);
    if (wait != WAIT_OBJECT_0 && wait != WAIT_ABANDONED) {
      ::CloseHandle(instance_mutex);
      return EXIT_SUCCESS;
    }
  }

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
  if (!window.Create(L"KaGo VPN", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex) {
    ::ReleaseMutex(instance_mutex);
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
