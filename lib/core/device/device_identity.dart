import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:win32_registry/win32_registry.dart';
import '../storage/secure_storage.dart';

/// App version for the User-Agent; `test/user_agent_test.dart` keeps it in
/// step with pubspec.yaml.
const kagoAppVersion = '2.0.2';

/// Mihomo core built into the app (Android) and downloaded on Windows.
const kagoCoreVersion = '1.19.32';

/// The device headers a Remnawave subscription expects (`x-hwid`,
/// `x-device-os`, `x-ver-os`, `x-device-model`) and the app's User-Agent.
///
/// The HWID is built exactly as FlClashX builds it, so the panel sees the
/// same kind of id as from FlClashX:
/// * Android: ANDROID_ID as is (per signing key, survives reinstalls);
///   without it `brand-device-hardware-buildId`.
/// * Windows: the first 16 hex characters of SHA-256(MachineGuid), upper
///   case (the same value FlClashX sends on this PC); without a MachineGuid
///   the same hash of `computerName-deviceId-productId`.
/// With a device limit on the subscription, the panel answers a request
/// without `x-hwid` with a stub server ("Приложение не поддерживается!").
class DeviceIdentity {
  DeviceIdentity._();
  static final instance = DeviceIdentity._();

  static const _channel = MethodChannel('net.usekago.app/service');
  static const _storageKey = 'kago.device.hwid.v1';

  Future<Map<String, String>>? _headers;

  Future<Map<String, String>> headers() => _headers ??= _build();

  /// `mihomo/1.19.32 KaGoVPN/0.1.0 (Android 14)`. Starts with the core, so
  /// Remnawave response rules for Mihomo clients serve a full Mihomo config
  /// (groups and rules of the panel); the device list on the site shows
  /// KaGoVPN and the system.
  Future<String> userAgent() async =>
      (await headers())['User-Agent'] ??
      userAgentFor(Platform.operatingSystem, '');

  /// For the usekago.net API: the app and system without the `mihomo/`
  /// prefix, which only selects the subscription format and could look like
  /// a proxy client to the site's protection.
  Future<String> apiUserAgent() async {
    final headers = await this.headers();
    final os = headers['x-device-os'] ?? Platform.operatingSystem;
    return apiUserAgentFor(os, headers['x-ver-os'] ?? '');
  }

  static String apiUserAgentFor(String os, String osVersion) {
    final system = _ascii(osVersion.isEmpty ? os : '$os $osVersion');
    return 'KaGoVPN/$kagoAppVersion ($system)';
  }

  static String userAgentFor(String os, String osVersion) {
    final system = _ascii(osVersion.isEmpty ? os : '$os $osVersion');
    return 'mihomo/$kagoCoreVersion KaGoVPN/$kagoAppVersion ($system)';
  }

  Future<Map<String, String>> _build() async {
    String? hwid;
    var os = Platform.operatingSystem;
    var osVersion = '';
    var model = '';
    if (Platform.isAndroid) {
      os = 'Android';
      try {
        final info =
            await _channel.invokeMapMethod<String, String>('deviceInfo') ??
                const <String, String>{};
        final androidId = info['id'] ?? '';
        hwid = androidId.isNotEmpty ? androidId : info['fallback'];
        osVersion = info['os'] ?? '';
        model = info['model'] ?? '';
      } catch (_) {
        // Falls back to a stored random id below.
      }
    } else if (Platform.isWindows) {
      os = 'Windows';
      final current = _windowsCurrentVersion();
      osVersion = current.displayVersion;
      model = current.productName;
      final guid =
          _registryString(r'SOFTWARE\Microsoft\Cryptography', 'MachineGuid');
      final source = guid != null && guid.isNotEmpty
          ? guid
          : '${Platform.localHostname}-'
              '${_registryString(r'SOFTWARE\Microsoft\SQMClient', 'MachineId') ?? ''}-'
              '${current.productId}';
      hwid = compactHwid(source);
    }
    if (hwid == null || hwid.isEmpty) hwid = await _storedRandomId();
    return <String, String>{
      'User-Agent': userAgentFor(os, osVersion),
      'x-hwid': _ascii(hwid),
      'x-device-os': os,
      if (osVersion.isNotEmpty) 'x-ver-os': _ascii(osVersion),
      if (model.isNotEmpty) 'x-device-model': _ascii(model),
    };
  }

  /// FlClashX's 16-character id: SHA-256, first 16 hex digits, upper case.
  static String compactHwid(String source) => sha256
      .convert(utf8.encode(source))
      .toString()
      .substring(0, 16)
      .toUpperCase();

  static Future<String> _storedRandomId() async {
    const storage = kagoSecureStorage;
    try {
      final saved = await storage.read(key: _storageKey);
      if (saved != null && saved.isNotEmpty) return saved;
    } catch (_) {}
    final random = Random.secure();
    final id = List<String>.generate(
            8, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    try {
      await storage.write(key: _storageKey, value: id);
    } catch (_) {}
    return id;
  }

  static String? _registryString(String path, String name) {
    try {
      final key = Registry.openPath(RegistryHive.localMachine, path: path);
      try {
        return key.getStringValue(name);
      } finally {
        key.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// `DisplayVersion` ("24H2"), `ProductName` ("Windows 11 Pro") and
  /// `ProductId`, as FlClashX reads them (device_info_plus).
  static ({String displayVersion, String productName, String productId})
      _windowsCurrentVersion() {
    const path = r'SOFTWARE\Microsoft\Windows NT\CurrentVersion';
    return (
      displayVersion: _registryString(path, 'DisplayVersion') ?? '',
      productName: _registryString(path, 'ProductName') ?? '',
      productId: _registryString(path, 'ProductId') ?? '',
    );
  }

  /// HTTP header values must be plain ASCII.
  static String _ascii(String value) =>
      value.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
}
