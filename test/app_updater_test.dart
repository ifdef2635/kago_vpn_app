import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/update/app_updater.dart';

void main() {
  test('versions compare by number, not as text', () {
    expect(AppUpdater.isNewer('1.0.4', '1.0.3'), isTrue);
    expect(AppUpdater.isNewer('v1.0.10', '1.0.9'), isTrue);
    expect(AppUpdater.isNewer('1.1.0', '1.0.99'), isTrue);
    expect(AppUpdater.isNewer('1.0.3', '1.0.3'), isFalse);
    expect(AppUpdater.isNewer('1.0.2', '1.0.3'), isFalse);
    expect(AppUpdater.isNewer('1.0.4-beta', '1.0.3'), isFalse);
    expect(AppUpdater.parseVersion('v2.3.4'), <int>[2, 3, 4]);
  });

  test('checksum is found for the exact file name', () {
    final a = 'a' * 64;
    final b = 'B' * 64;
    final sums = '$a  KaGoVPN-Windows-x64-1.0.4.zip\n'
        '$b *KaGoVPN-Windows-x64-Setup-1.0.4.exe\n';
    expect(AppUpdater.hashFor(sums, 'KaGoVPN-Windows-x64-Setup-1.0.4.exe'),
        'b' * 64);
    expect(AppUpdater.hashFor(sums, 'KaGoVPN-Windows-x64-1.0.4.zip'), 'a' * 64);
    expect(AppUpdater.hashFor(sums, 'other.exe'), isNull);
  });

  test('asset names match what release.yml publishes', () {
    expect(AppUpdater.assetsFor('android', '1.0.4'),
        (asset: 'KaGoVPN-Android-1.0.4.apk', sums: 'SHA256SUMS.txt'));
    expect(AppUpdater.assetsFor('windows', '1.0.4'),
        (asset: 'KaGoVPN-Windows-x64-Setup-1.0.4.exe', sums: 'SHA256SUMS.txt'));
    expect(AppUpdater.assetsFor('macos', '1.0.4'),
        (asset: 'KaGoVPN-macOS-1.0.4.dmg', sums: 'SHA256SUMS.txt'));
    expect(AppUpdater.assetsFor('linux', '1.0.4'), isNull);

    final release = File('.github/workflows/release.yml').readAsStringSync();
    for (final name in <String>[
      r'KaGoVPN-Android-$V.apk',
      r'KaGoVPN-Windows-x64-Setup-$V.exe',
      r'KaGoVPN-macOS-$V.dmg',
      'SHA256SUMS-Android.txt',
      'SHA256SUMS-Windows.txt',
      'SHA256SUMS-macOS.txt',
      'SHA256SUMS.txt.sig',
    ]) {
      expect(release, contains(name));
    }
  });

  test('macOS install script is valid bash', () async {
    final dir = await Directory.systemTemp.createTemp('kago-update-');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/install.sh')
      ..writeAsStringSync(AppUpdater.macosInstallScript);
    final result = await Process.run('bash', <String>['-n', script.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }, skip: Platform.isWindows);

  test('release notes become plain text', () {
    expect(
        AppUpdater.plainNotes(
            'Сделано:\r\n- **TUN** на `macOS`.\n  - DNS — `1.1.1.1`.\n'),
        'Сделано:\n• TUN на macOS.\n  • DNS — 1.1.1.1.');
  });
}
