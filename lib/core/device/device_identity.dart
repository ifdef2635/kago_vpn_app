import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:win32_registry/win32_registry.dart';

/// The device headers a Remnawave subscription expects (`x-hwid` and
/// friends, as FlClashX and Happ send them).
///
/// With a device limit on the subscription, the panel answers a request
/// without `x-hwid` with a stub server named "Приложение не поддерживается!"
/// instead of the real ones. The HWID is stable for the device: on Android
/// it comes from ANDROID_ID, on Windows from the MachineGuid, so reinstalling
/// the app does not take one more device slot. Only a hash leaves the device.
class DeviceIdentity {
  DeviceIdentity._();
  static final instance = DeviceIdentity._();

  static const _channel = MethodChannel('net.usekago.app/service');
  static const _storageKey = 'kago.device.hwid.v1';

  Future<Map<String, String>>? _headers;

  Future<Map<String, String>> headers() => _headers ??= _build();

  Future<Map<String, String>> _build() async {
    var source = '';
    var os = Platform.operatingSystem;
    var osVersion = '';
    var model = '';
    if (Platform.isAndroid) {
      os = 'Android';
      try {
        final info =
            await _channel.invokeMapMethod<String, String>('deviceInfo') ??
                const <String, String>{};
        source = info['id'] ?? '';
        osVersion = info['os'] ?? '';
        model = info['model'] ?? '';
      } catch (_) {
        // Falls back to a stored random id below.
      }
    } else if (Platform.isWindows) {
      os = 'Windows';
      source = _windowsMachineGuid() ?? '';
      osVersion = _windowsVersion();
      model = 'PC';
    }
    final hwid = source.isNotEmpty ? _hash(source) : await _storedRandomId();
    return <String, String>{
      'x-hwid': hwid,
      'x-device-os': os,
      if (osVersion.isNotEmpty) 'x-ver-os': osVersion,
      if (model.isNotEmpty) 'x-device-model': _ascii(model),
    };
  }

  /// App-specific, so the id says nothing outside KaGo VPN.
  static String _hash(String source) => sha256
      .convert(utf8.encode('kago-vpn-hwid:$source'))
      .toString()
      .substring(0, 32);

  static Future<String> _storedRandomId() async {
    const storage = FlutterSecureStorage();
    try {
      final saved = await storage.read(key: _storageKey);
      if (saved != null && saved.isNotEmpty) return saved;
    } catch (_) {}
    final random = Random.secure();
    final id = List<String>.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    try {
      await storage.write(key: _storageKey, value: id);
    } catch (_) {}
    return id;
  }

  static String? _windowsMachineGuid() {
    try {
      final key = Registry.openPath(RegistryHive.localMachine,
          path: r'SOFTWARE\Microsoft\Cryptography');
      try {
        return key.getStringValue('MachineGuid');
      } finally {
        key.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// "10.0.22631" from `"Windows 10 Pro" 10.0 (Build 22631)`.
  static String _windowsVersion() {
    final text = Platform.operatingSystemVersion;
    final version = RegExp(r'(\d+\.\d+)').firstMatch(text)?.group(1);
    final build = RegExp(r'Build (\d+)').firstMatch(text)?.group(1);
    if (version == null) return '';
    return build == null ? version : '$version.$build';
  }

  /// HTTP header values must be plain ASCII.
  static String _ascii(String value) =>
      value.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
}
