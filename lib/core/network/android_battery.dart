import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_providers.dart';

/// Battery optimization of the app on Android. With it on, the system (and
/// OEM savers on Xiaomi, Huawei, Samsung…) may stop the app in the
/// background: the VPN drops, or its notification stays while it is off.
abstract final class AndroidBattery {
  static const _channel = MethodChannel('net.usekago.app/service');
  static const askedKey = 'kago.battery.asked';

  /// True when the system does not restrict the app (or not on Android).
  static Future<bool> unrestricted() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('batteryUnrestricted') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the system request (or its settings list).
  static Future<bool> request() async {
    try {
      return await _channel.invokeMethod<bool>('requestBatteryUnrestricted') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// The first connection asks once; later only «Настройки → Работа в фоне».
  static Future<void> askOnce() async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(askedKey) ?? false) return;
      if (await unrestricted()) return;
      await prefs.setBool(askedKey, true);
      await request();
    } catch (_) {
      // Not essential for the connection.
    }
  }
}

/// Read again whenever the app comes back (after the system dialog).
final androidBatteryUnrestrictedProvider = FutureProvider<bool>((ref) {
  ref.watch(appForegroundProvider);
  return AndroidBattery.unrestricted();
});
