import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

/// Windows notification-area icon (native part: `windows/runner/
/// flutter_window.cpp`). Closing the window only hides it, so the VPN keeps
/// working; the app quits only from the tray menu («Выход»), or when Windows
/// shuts down. Before it quits, [attach]'s `onQuit` stops the core, which
/// restores the system proxy, the TUN service and the time zone.
abstract final class WindowsTray {
  static const channel = MethodChannel('net.usekago.app/tray');
  static const _hintKey = 'kago.windows.tray.hint.v1';

  /// Longest wait for [attach]'s `onQuit`; the native side closes after 10 s
  /// in any case.
  static const quitTimeout = Duration(seconds: 8);

  /// Handles the tray's calls and sets the menu texts in the app language.
  static Future<void> attach(
      {required Future<void> Function() onQuit,
      required bool connected}) async {
    if (!Platform.isWindows) return;
    channel.setMethodCallHandler((call) => handle(call, onQuit));
    var hint = '';
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!(preferences.getBool(_hintKey) ?? false)) {
        hint = tr(
            'KaGo VPN продолжает работать в трее. Чтобы выйти, нажмите на значок правой кнопкой → «Выход».');
      }
    } catch (_) {
      // Without preferences the hint is simply not shown.
    }
    await _invoke('configure', <String, String>{
      'open': tr('Открыть KaGo VPN'),
      'quit': tr('Выход'),
      'tooltip': tooltip(connected),
      'hint': hint,
    });
  }

  /// The native side's calls: `quit` (stop the core, then the window closes
  /// on the reply) and `hintShown`.
  static Future<Object?> handle(
      MethodCall call, Future<void> Function() onQuit) async {
    switch (call.method) {
      case 'quit':
        try {
          await onQuit().timeout(quitTimeout);
        } catch (_) {
          // Quit anyway; a stale proxy is repaired at the next start.
        }
        return true;
      case 'hintShown':
        try {
          await (await SharedPreferences.getInstance()).setBool(_hintKey, true);
        } catch (_) {}
        return null;
    }
    throw MissingPluginException(call.method);
  }

  static String tooltip(bool connected) =>
      connected ? tr('KaGo VPN — подключено') : tr('KaGo VPN — не подключено');

  static Future<void> setConnected(bool connected) async {
    if (!Platform.isWindows) return;
    await _invoke(
        'setTooltip', <String, String>{'tooltip': tooltip(connected)});
  }

  /// Before the app ends itself (update): a killed process would leave a
  /// dead icon in the tray until the mouse passes over it.
  static Future<void> remove() async {
    if (!Platform.isWindows) return;
    await _invoke('remove');
  }

  static Future<void> _invoke(String method,
      [Map<String, String>? arguments]) async {
    try {
      await channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      // Older runner or tests.
    } on PlatformException {
      // The tray is a convenience; the app works without it.
    }
  }
}
