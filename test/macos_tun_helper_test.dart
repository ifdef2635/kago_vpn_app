import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/mihomo_macos.dart';
import 'package:kago_vpn/features/subscriptions/config_builder.dart';

/// The set-uid TUN wrapper (macos/helper/kago_tun.c) must accept every config
/// the app produces and refuse the dangerous ones. Built with the system C
/// compiler where there is one (Linux, macOS).
void main() {
  final compiler = Platform.isWindows ? null : _which('cc');

  late Directory dir;
  late String checker;

  setUpAll(() async {
    if (compiler == null) return;
    dir = await Directory.systemTemp.createTemp('kago-tun-');
    checker = '${dir.path}/kago-tun-test';
    final build = await Process.run(compiler, <String>[
      '-Wall',
      '-Wextra',
      '-Werror',
      '-DKAGO_TUN_SELF_TEST',
      '-o',
      checker,
      'macos/helper/kago_tun.c',
    ]);
    expect(build.exitCode, 0, reason: '${build.stderr}');
  });

  tearDownAll(() async {
    if (compiler != null) await dir.delete(recursive: true);
  });

  Future<bool> allowed(String config) async {
    final process = await Process.start(checker, <String>['--check']);
    process.stdin.add(utf8.encode(config));
    await process.stdin.close();
    return await process.exitCode == 0;
  }

  test('built-in self-test', () async {
    final result = await Process.run(checker, const <String>[]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }, skip: compiler == null);

  test('a sanitized hostile subscription is accepted, the raw one refused',
      () async {
    const hostile = '''
proxies:
  - {name: "🇩🇪 Germany \\"1\\"", type: vless, server: de.example, port: 443, uuid: 00000000-0000-0000-0000-000000000000, tls: true}
external-controller-unix: /etc/kago.sock
external-ui: /tmp/ui
listeners: [{name: x, type: mixed, port: 1}]
ntp: {enable: true, server: time.example, write-to-system: true}
rule-providers:
  r: {type: http, behavior: domain, url: "https://x.example/r", path: ./x.yaml}
tun: {enable: true, stack: mixed}
dns: {enable: true, listen: 0.0.0.0:53}
''';
    final config = const MihomoConfigBuilder().build(hostile);
    expect(await allowed(jsonEncode(config)), isTrue);
    expect(await allowed(hostile), isFalse);
  }, skip: compiler == null);

  test('install script is valid sh and checks hashes before chmod', () async {
    final script = MihomoMacosCore.installScript(
      coreSource: "/Applications/KaGo VPN.app/Contents/Resources/mihomo",
      coreHash: 'a' * 64,
      helperSource: "/Applications/KaGo VPN.app/Contents/Resources/kago-tun",
      helperHash: 'b' * 64,
      legacyFile: "/Users/o'neil/Library/Application Support/x/core/mihomo",
    );
    final file = File('${Directory.systemTemp.path}/kago-install-test.sh')
      ..writeAsStringSync(script);
    addTearDown(file.deleteSync);
    final check = await Process.run('sh', <String>['-n', file.path]);
    expect(check.exitCode, 0, reason: '${check.stderr}');
    expect(script.indexOf('a' * 64), lessThan(script.indexOf('chmod 4750')));
    expect(script, contains('set -e'));
    expect(script, contains(r"o'\''neil"));
  }, skip: Platform.isWindows);

  test('root core and wrapper ownership checks', () {
    expect(MihomoMacosCore.isRootOwnedStat('root:wheel -rwxr-xr-x'), isTrue);
    expect(MihomoMacosCore.isRootOwnedStat('user:staff -rwxr-xr-x'), isFalse);
    expect(MihomoMacosCore.isRootOwnedStat('root:wheel -rwxrwxr-x'), isFalse);
    expect(MihomoMacosCore.isRootOwnedStat('root:wheel -rwsr-xr-x'), isFalse);
    expect(MihomoMacosCore.isRootOwnedStat('root:wheel drwxr-xr-x'), isFalse);
  });
}

String? _which(String name) {
  final result = Process.runSync('which', <String>[name]);
  final path = '${result.stdout}'.trim();
  return result.exitCode == 0 && path.isNotEmpty ? path : null;
}
