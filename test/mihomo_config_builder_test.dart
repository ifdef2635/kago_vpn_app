import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/subscriptions/config_builder.dart';

void main() {
  test('preserves profile proxies and adds local controller and TUN defaults',
      () {
    const builder = MihomoConfigBuilder();
    final config = builder.build(
      'proxies:\n  - name: test\n    type: socks5\n    server: 127.0.0.1\n    port: 1080\n'
      'proxy-groups:\n  - name: Proxy\n    type: select\n    proxies: [test]\n',
    );
    expect(config['mixed-port'], 7890);
    expect(config['external-controller'], '127.0.0.1:9090');
    expect((config['tun'] as Map<String, dynamic>)['enable'], isTrue);
    expect((config['proxies'] as List<dynamic>).length, 1);
    expect(config.containsKey('secret'), isFalse);
  });

  test('prepares a loopback controller and external Android TUN config',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('kago-controller-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}active.yaml');
    await file.writeAsString('{"tun":{"enable":true}}');

    await const MihomoConfigBuilder().prepareAndroidTunnelConfig(
      file,
      endpoint: 'http://127.0.0.1:9901',
      secret: 'test-secret',
    );

    final result =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(result['external-controller'], '127.0.0.1:9901');
    expect(result['secret'], 'test-secret');
    final tun = result['tun'] as Map<String, dynamic>;
    expect(tun['enable'], isFalse);
    expect(tun['auto-route'], isFalse);
  });

  test('rejects non-loopback embedded controller endpoints', () async {
    final directory =
        await Directory.systemTemp.createTemp('kago-controller-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}active.yaml');
    await file.writeAsString('{"tun":{"enable":true}}');

    await expectLater(
      const MihomoConfigBuilder().prepareAndroidTunnelConfig(file,
          endpoint: 'https://api.example.net:9090'),
      throwsFormatException,
    );
  });
}
