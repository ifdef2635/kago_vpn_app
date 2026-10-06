import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/device/device_identity.dart';
import 'package:kago_vpn/core/network/mihomo_windows_core_updater.dart';

void main() {
  test('app version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version =
        RegExp(r'^version:\s*([\d.]+)', multiLine: true).firstMatch(pubspec);
    expect(kagoAppVersion, version?.group(1));
  });

  test('core version matches the pinned Windows core', () {
    expect('v$kagoCoreVersion', MihomoPinnedCore.version);
  });

  test('User-Agent starts with mihomo and names the app and system', () {
    expect(DeviceIdentity.userAgentFor('Android', '14'),
        'mihomo/$kagoCoreVersion KaGoVPN/$kagoAppVersion (Android 14)');
    expect(DeviceIdentity.userAgentFor('Windows', ''),
        'mihomo/$kagoCoreVersion KaGoVPN/$kagoAppVersion (Windows)');
  });
}
