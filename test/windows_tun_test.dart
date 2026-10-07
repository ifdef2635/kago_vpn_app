import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/mihomo_windows_core_updater.dart';
import 'package:kago_vpn/core/network/mihomo_windows_tun.dart';

void main() {
  String script({String config = r'C:\Users\Анна\AppData\config.yaml'}) =>
      MihomoWindowsTun.script(
        coreSource: r"C:\Users\O'Neil\AppData\Roaming\KaGo\core\mihomo.exe",
        coreSha256: MihomoPinnedCore.exeSha256Hex,
        configSource: config,
        configSha256: 'AB' * 32,
        stopFile: r'C:\Users\O' 'Neil\tun-stop',
        parentPid: 4242,
      );

  test('TUN settings route UDP through the core on Windows', () {
    final config = <String, dynamic>{};
    MihomoWindowsTun.enableTun(config);
    final tun = config['tun'] as Map<String, dynamic>;
    expect(tun['enable'], true);
    expect(tun['stack'], 'gvisor');
    expect(tun['auto-route'], true);
    expect(tun['strict-route'], true);
    expect(tun['dns-hijack'], <String>['any:53']);
  });

  test('the elevated script checks the pinned core and the config hash', () {
    final text = script();
    expect(text, contains(MihomoPinnedCore.exeSha256Hex));
    expect(text, contains("\$cfgHash = '${'ab' * 32}'"));
    expect(text, contains(r"Join-Path $env:ProgramFiles 'KaGo VPN Core'"));
    expect(text, contains(r'$parent = 4242'));
    // Single quotes inside paths are doubled for PowerShell.
    expect(text, contains("O''Neil"));
    expect(text, isNot(contains("O'Neil\\AppData")));
    // The core runs from Program Files, never from the user's folder.
    expect(text, contains(r'Start-Process -FilePath $exe'));
  });

  test('the launcher passes the script inline as UTF-16LE base64', () {
    final text = script();
    final args = MihomoWindowsTun.launcherArguments(text);
    final command = args.last;
    expect(command, contains('-Verb RunAs'));
    final encoded =
        RegExp(r"'-EncodedCommand','([A-Za-z0-9+/=]+)'").firstMatch(command)!;
    final bytes = base64.decode(encoded.group(1)!);
    final units = <int>[
      for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8)
    ];
    expect(String.fromCharCodes(units), text);
    // Windows command lines are limited to 32767 characters.
    expect(args.join(' ').length, lessThan(30000));
  });

  // Windows CI: PowerShell's own parser must accept both scripts.
  test('PowerShell parses the elevated script and the launcher',
      skip: !Platform.isWindows, () async {
    final dir = await Directory.systemTemp.createTemp('kago_tun');
    try {
      final text = script();
      final files = <String, String>{
        'elevated.ps1': text,
        'launcher.ps1': MihomoWindowsTun.launcherArguments(text).last,
      };
      for (final entry in files.entries) {
        final file = File('${dir.path}\\${entry.key}');
        // UTF-8 with BOM: Windows PowerShell 5.1 reads Cyrillic paths right.
        await file
            .writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(entry.value)]);
        final result = await Process.run('powershell.exe', <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'$e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($args[0], [ref]$null, [ref]$e); if ($e) { $e | ForEach-Object { $_.Message }; exit 1 }',
          file.path,
        ]);
        expect(result.exitCode, 0,
            reason: '${entry.key}: ${result.stdout}${result.stderr}');
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
