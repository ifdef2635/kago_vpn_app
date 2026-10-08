#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <shellapi.h>

#include <memory>
#include <string>

#include "win32_window.h"

// Sent by a second copy of the app to bring this one to the front.
inline UINT KagoShowMessage() {
  static const UINT message = ::RegisterWindowMessageW(L"KaGoVPN.Show");
  return message;
}

// Asks the running app to quit as from the tray menu (the installer sends it
// before replacing or removing the files).
inline UINT KagoQuitMessage() {
  static const UINT message = ::RegisterWindowMessageW(L"KaGoVPN.Quit");
  return message;
}

// A window that hosts a Flutter view and lives in the notification area
// (tray): closing the window only hides it, the VPN keeps working, and the
// app quits from the tray menu (channel "net.usekago.app/tray").
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowFromTray();
  void HideToTray();
  void ShowTrayMenu();
  void ShowHint();
  // Asks Dart to stop the core (system proxy, TUN, time zone), then closes.
  void RequestQuit(bool session_ending);
  void OnQuitReplied();
  void FinishQuit();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      tray_channel_;
  NOTIFYICONDATAW tray_icon_{};
  HICON tray_hicon_ = nullptr;
  bool tray_added_ = false;
  UINT taskbar_created_ = 0;
  bool quitting_ = false;
  bool session_ending_ = false;
  bool quit_replied_ = false;
  bool finished_ = false;
  // Replaced by Dart with the app language ("configure").
  std::wstring label_open_ = L"Открыть KaGo VPN";
  std::wstring label_quit_ = L"Выход";
  std::wstring tooltip_ = L"KaGo VPN";
  std::wstring hint_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
