#include "flutter_window.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
// Closes the window outside the Dart reply callback (the engine must not be
// destroyed from inside its own callback).
constexpr UINT kFinishQuitMessage = WM_APP + 2;
constexpr UINT_PTR kQuitTimer = 1;
constexpr UINT kMenuOpen = 1;
constexpr UINT kMenuQuit = 2;
// "Quit" waits this long for Dart to stop the core, then closes anyway.
constexpr UINT kQuitTimeoutMs = 10000;
// Windows ends the process soon after WM_ENDSESSION.
constexpr ULONGLONG kSessionEndWaitMs = 4500;

std::wstring Utf16FromUtf8(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int length = ::MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                           static_cast<int>(text.size()),
                                           nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring result(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        result.data(), length);
  return result;
}

std::optional<std::wstring> TextArgument(const flutter::EncodableMap* map,
                                         const char* key) {
  if (!map) return std::nullopt;
  const auto found = map->find(flutter::EncodableValue(key));
  if (found == map->end()) return std::nullopt;
  const auto* text = std::get_if<std::string>(&found->second);
  if (!text) return std::nullopt;
  return Utf16FromUtf8(*text);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  RemoveTrayIcon();
  if (tray_hicon_) {
    ::DestroyIcon(tray_hicon_);
    tray_hicon_ = nullptr;
  }
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  tray_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "net.usekago.app/tray",
          &flutter::StandardMethodCodec::GetInstance());
  tray_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* map =
            std::get_if<flutter::EncodableMap>(call.arguments());
        const std::string& method = call.method_name();
        if (method == "configure" || method == "setTooltip") {
          if (auto text = TextArgument(map, "open")) label_open_ = *text;
          if (auto text = TextArgument(map, "quit")) label_quit_ = *text;
          if (auto text = TextArgument(map, "hint")) hint_ = *text;
          if (auto text = TextArgument(map, "tooltip")) tooltip_ = *text;
          AddTrayIcon();
          result->Success(flutter::EncodableValue(tray_added_));
        } else if (method == "remove") {
          RemoveTrayIcon();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  taskbar_created_ = ::RegisterWindowMessageW(L"TaskbarCreated");
  // Run as administrator, the window would not get these from a normal
  // process (UIPI): a second launch, the installer, a restarted Explorer.
  for (const UINT allowed :
       {KagoShowMessage(), KagoQuitMessage(), taskbar_created_}) {
    ::ChangeWindowMessageFilterEx(GetHandle(), allowed, MSGFLT_ALLOW, nullptr);
  }
  AddTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  // Before the engine: no channel call may reach a destroyed engine.
  tray_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::AddTrayIcon() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  if (!tray_hicon_) {
    tray_hicon_ = static_cast<HICON>(::LoadImageW(
        ::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON),
        IMAGE_ICON, ::GetSystemMetrics(SM_CXSMICON),
        ::GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
  }
  tray_icon_ = {};
  tray_icon_.cbSize = sizeof(tray_icon_);
  tray_icon_.hWnd = hwnd;
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayMessage;
  tray_icon_.hIcon = tray_hicon_;
  wcsncpy_s(tray_icon_.szTip, tooltip_.c_str(), _TRUNCATE);
  if (tray_added_ && ::Shell_NotifyIconW(NIM_MODIFY, &tray_icon_)) return;
  tray_added_ = ::Shell_NotifyIconW(NIM_ADD, &tray_icon_) != FALSE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) return;
  ::Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
  tray_added_ = false;
}

void FlutterWindow::ShowFromTray() {
  HWND hwnd = GetHandle();
  if (!hwnd || quitting_) return;
  ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(hwnd);
}

void FlutterWindow::HideToTray() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  if (!tray_added_) AddTrayIcon();
  if (!tray_added_) {
    // No notification area (Explorer not running, another shell): there would
    // be no «Выход», so the close button quits as before the tray.
    RequestQuit(false);
    return;
  }
  ::ShowWindow(hwnd, SW_HIDE);
  ShowHint();
}

void FlutterWindow::ShowHint() {
  if (hint_.empty() || !tray_added_) return;
  NOTIFYICONDATAW data = tray_icon_;
  data.uFlags = NIF_INFO;
  wcsncpy_s(data.szInfoTitle, L"KaGo VPN", _TRUNCATE);
  wcsncpy_s(data.szInfo, hint_.c_str(), _TRUNCATE);
  data.dwInfoFlags = NIIF_INFO;
  ::Shell_NotifyIconW(NIM_MODIFY, &data);
  hint_.clear();
  if (tray_channel_) tray_channel_->InvokeMethod("hintShown", nullptr);
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (!hwnd || quitting_) return;
  HMENU menu = ::CreatePopupMenu();
  if (!menu) return;
  ::AppendMenuW(menu, MF_STRING, kMenuOpen, label_open_.c_str());
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kMenuQuit, label_quit_.c_str());
  ::SetMenuDefaultItem(menu, kMenuOpen, FALSE);
  POINT point;
  ::GetCursorPos(&point);
  // Without this the menu does not close when clicking elsewhere.
  ::SetForegroundWindow(hwnd);
  const UINT command = static_cast<UINT>(::TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, point.x, point.y,
      0, hwnd, nullptr));
  ::PostMessageW(hwnd, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
  if (command == kMenuOpen) {
    ShowFromTray();
  } else if (command == kMenuQuit) {
    RequestQuit(false);
  }
}

void FlutterWindow::RequestQuit(bool session_ending) {
  if (quitting_) return;
  quitting_ = true;
  session_ending_ = session_ending;
  quit_replied_ = false;
  if (!tray_channel_) {
    FinishQuit();
    return;
  }
  tray_channel_->InvokeMethod(
      "quit", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*) { OnQuitReplied(); },
          [this](const std::string&, const std::string&,
                 const flutter::EncodableValue*) { OnQuitReplied(); },
          [this]() { OnQuitReplied(); }));
  if (!session_ending) {
    ::SetTimer(GetHandle(), kQuitTimer, kQuitTimeoutMs, nullptr);
    return;
  }
  // Windows is shutting down: run the message loop here until Dart has
  // stopped the core (so the system proxy is not left pointing at it), for a
  // few seconds at most; Windows ends the process afterwards.
  const ULONGLONG deadline = ::GetTickCount64() + kSessionEndWaitMs;
  MSG msg;
  while (!quit_replied_ && ::GetTickCount64() < deadline) {
    if (::PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) {
        ::PostQuitMessage(static_cast<int>(msg.wParam));
        break;
      }
      ::TranslateMessage(&msg);
      ::DispatchMessageW(&msg);
    } else {
      ::MsgWaitForMultipleObjects(0, nullptr, FALSE, 50, QS_ALLINPUT);
    }
  }
  // Also ends the app when the Restart Manager (installer) sent the message.
  FinishQuit();
}

void FlutterWindow::OnQuitReplied() {
  quit_replied_ = true;
  HWND hwnd = GetHandle();
  if (!session_ending_ && hwnd) {
    ::PostMessageW(hwnd, kFinishQuitMessage, 0, 0);
  }
}

void FlutterWindow::FinishQuit() {
  if (finished_) return;
  finished_ = true;
  HWND hwnd = GetHandle();
  if (hwnd) ::KillTimer(hwnd, kQuitTimer);
  RemoveTrayIcon();
  if (hwnd) ::DestroyWindow(hwnd);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Before Flutter: closing the window hides it to the tray instead of
  // quitting (the engine would otherwise start the app's exit).
  if (message == KagoShowMessage()) {
    // 1: shown. 0 while quitting: the second copy then waits and starts.
    if (quitting_) return 0;
    ShowFromTray();
    return 1;
  }
  if (message == KagoQuitMessage()) {
    RequestQuit(false);
    return 0;
  }
  if (taskbar_created_ != 0 && message == taskbar_created_) {
    // Explorer restarted: the icon has to be added again.
    tray_added_ = false;
    AddTrayIcon();
    return 0;
  }
  switch (message) {
    case WM_CLOSE:
      // While quitting, FinishQuit closes the window; the engine must not
      // start a second exit (and a second core stop) meanwhile.
      if (!quitting_) HideToTray();
      return 0;
    case kTrayMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          ShowFromTray();
          break;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          break;
      }
      return 0;
    case kFinishQuitMessage:
      FinishQuit();
      return 0;
    case WM_TIMER:
      if (wparam == kQuitTimer) {
        FinishQuit();
        return 0;
      }
      break;
    case WM_QUERYENDSESSION:
      return TRUE;
    case WM_ENDSESSION:
      if (wparam) RequestQuit(true);
      return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
