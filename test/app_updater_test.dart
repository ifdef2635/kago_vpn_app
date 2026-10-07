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

  test('the Платформы line limits who is offered a release', () {
    expect(AppUpdater.platformsFrom('Сделано:\n- x'), isNull);
    expect(AppUpdater.platformsFrom('Платформы: Android, macOS\n- x'),
        <String>{'android', 'macos'});
    expect(AppUpdater.platformsFrom('**Платформы:** Windows'),
        <String>{'windows'});
    expect(AppUpdater.platformsFrom('Platforms: mac'), <String>{'macos'});
    expect(AppUpdater.platformsFrom('Платформы: все'), isNull);
  });

  test('an update is offered only when a newer release is for this system', () {
    Map<String, Object?> release(String tag, String body) =>
        <String, Object?>{'tag_name': tag, 'body': body, 'draft': false};
    final releases = <Object?>[
      release('v2.0.2', 'Платформы: macOS\n- mac fix'),
      release('v2.0.1', 'Платформы: Android\n- android fix'),
      release('v2.0.0', '- everything'),
      <String, Object?>{'tag_name': 'v2.0.3', 'body': '', 'draft': true},
    ];
    // Windows on 2.0.0: 2.0.1 and 2.0.2 are not for it.
    expect(AppUpdater.pick(releases, 'windows', '2.0.0'), isNull);
    // Windows on 1.0.6: 2.0.0 is for everyone; the newest files are offered.
    final windows = AppUpdater.pick(releases, 'windows', '1.0.6')!;
    expect(windows.tag, 'v2.0.2');
    expect(windows.notes, contains('everything'));
    expect(windows.notes, isNot(contains('mac fix')));
    // Android on 2.0.0 gets 2.0.2 (which also carries 2.0.1).
    final android = AppUpdater.pick(releases, 'android', '2.0.0')!;
    expect(android.tag, 'v2.0.2');
    expect(android.notes, contains('android fix'));
    expect(AppUpdater.pick(releases, 'macos', '2.0.2'), isNull);
  });
}
