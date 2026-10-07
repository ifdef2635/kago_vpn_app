import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/mihomo_windows_core_updater.dart';
import 'package:kago_vpn/core/network/mihomo_windows_tun.dart';
import 'package:kago_vpn/features/subscriptions/config_builder.dart';

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
        'service.ps1': MihomoWindowsTun.serviceScript(),
        'setup.ps1': MihomoWindowsTun.setupScript(
            coreSource: r'C:\Users\Анна\mihomo.exe',
            coreSha256: MihomoPinnedCore.exeSha256Hex,
            account: r'PC\Анна',
            service: MihomoWindowsTun.serviceScript()),
        'waiting-launcher.ps1':
            MihomoWindowsTun.waitingLauncherArguments(text).last,
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
          // -Command has no $args: the path goes into the command itself.
          "\$e = \$null; [void][System.Management.Automation.Language.Parser]::ParseFile('${file.path.replaceAll("'", "''")}', [ref]\$null, [ref]\$e); if (\$e) { \$e | ForEach-Object { \$_.Message }; exit 1 }",
        ]);
        expect(result.exitCode, 0,
            reason: '${entry.key}: ${result.stdout}${result.stderr}');
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });

  /// What the process manager hands the elevated core: a sanitized profile
  /// with the loopback controller and Windows TUN.
  String appConfig() {
    final config = const MihomoConfigBuilder().build('''
proxies:
  - {name: "DE 🇩🇪 Германия", type: ss, server: de.example.com, port: 443, cipher: aes-128-gcm, password: "p\\\\w"}
proxy-groups:
  - {name: Proxy, type: select, proxies: ["DE 🇩🇪 Германия"]}
rules:
  - GEOIP,RU,DIRECT
  - MATCH,Proxy
''', enableTun: false);
    MihomoConfigBuilder.lockToLoopback(config);
    config['external-controller'] = '127.0.0.1:9090';
    config['secret'] = 'secret';
    MihomoWindowsTun.enableTun(config);
    MihomoConfigBuilder.ensureDns(config);
    return jsonEncode(config);
  }

  test('the service script runs only the pinned core and checks the config',
      () {
    final text = MihomoWindowsTun.serviceScript();
    expect(text, contains(MihomoPinnedCore.exeSha256Hex));
    expect(text, contains('function Test-KagoConfig'));
    expect(text, contains(r'$refused = Test-KagoConfig $text'));
    for (final word in MihomoWindowsTun.forbidden) {
      expect(text, contains("'$word'"));
    }
    // Written with a fixed encoding by the setup: ASCII only.
    expect(text.codeUnits.every((unit) => unit < 128), true);
    // Reads only %APPDATA%\KaGo\tun from the user.
    expect(text, contains(r"Join-Path $env:APPDATA 'KaGo\tun'"));
  });

  test('the setup installs the service script and the scheduled task', () {
    final service = MihomoWindowsTun.serviceScript();
    final text = MihomoWindowsTun.setupScript(
      coreSource: r'C:\Users\Анна\AppData\Roaming\KaGo\core\mihomo.exe',
      coreSha256: MihomoPinnedCore.exeSha256Hex,
      account: r"PC\O'Neil",
      service: service,
    );
    final embedded = RegExp(r"FromBase64String\('([^']+)'\)").firstMatch(text)!;
    expect(utf8.decode(base64.decode(embedded.group(1)!)), service);
    expect(text, contains(r"$user = 'PC\O''Neil'"));
    expect(text, contains('-RunLevel Highest'));
    expect(text, contains('-MultipleInstances Queue'));
    expect(text, contains(r"-TaskName 'KaGo VPN TUN' -TaskPath '\KaGo VPN\'"));
    final launcher = MihomoWindowsTun.waitingLauncherArguments(text).last;
    expect(launcher, contains('-Wait -PassThru'));
    expect(launcher, contains(r'exit $p.ExitCode'));
  });

  test('the app config is plain JSON the service accepts', () {
    final text = appConfig();
    expect(text, contains('"external-controller":"127.0.0.1:9090"'));
    expect(text, isNot(contains(r'\u')));
    for (final word in MihomoWindowsTun.forbidden) {
      expect(text.toLowerCase(), isNot(contains(word)));
    }
  });

  // Windows CI: the real check, in PowerShell, on good and hostile configs.
  test('Test-KagoConfig accepts the app config and refuses hostile ones',
      skip: !Platform.isWindows, () async {
    final dir = await Directory.systemTemp.createTemp('kago_check');
    try {
      final cases = <String, String>{
        'app': appConfig(),
        'unix socket':
            r'{"external-controller":"127.0.0.1:9090","external-controller-unix":"C:\\x"}',
        'lan controller': r'{"external-controller":"0.0.0.0:9090"}',
        'two controllers':
            r'{"external-controller":"127.0.0.1:9090","external-controller":"0.0.0.0:1"}',
        'unicode escape':
            r'{"external-controller":"127.0.0.1:9090","external-\u0075i":"x"}',
        'allow lan':
            r'{"external-controller":"127.0.0.1:9090","allow-lan":true}',
        'listeners': r'{"external-controller":"127.0.0.1:9090","listeners":[]}',
      };
      for (final entry in cases.entries) {
        final file =
            File('${dir.path}\\${entry.key.replaceAll(' ', '_')}.json');
        await file.writeAsString(entry.value);
        final path = file.path.replaceAll("'", "''");
        final command = '${MihomoWindowsTun.configCheckFunction()}'
            "\$t = [IO.File]::ReadAllText('$path', [Text.Encoding]::UTF8); "
            r'$r = Test-KagoConfig $t; if ($r) { Write-Output $r; exit 1 } else { exit 0 }';
        final result = await Process.run('powershell.exe',
            <String>['-NoProfile', '-NonInteractive', '-Command', command]);
        expect(result.exitCode, entry.key == 'app' ? 0 : 1,
            reason: '${entry.key}: ${result.stdout}${result.stderr}');
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
