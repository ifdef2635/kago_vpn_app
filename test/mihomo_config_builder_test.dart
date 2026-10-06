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
    await file.writeAsString(
        '{"tun":{"enable":true,"stack":"gvisor"},"find-process-mode":"off"}');

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
    // The embedded core has no gVisor.
    expect(tun['stack'], 'system');
    // App rules of the subscription need the package lookup.
    expect(result['find-process-mode'], 'strict');
  });

  test('Android config gets Mihomo DNS when the subscription has none',
      () async {
    final directory = await Directory.systemTemp.createTemp('kago-dns-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}active.yaml');
    await file.writeAsString('{"dns":{"enable":false}}');

    await const MihomoConfigBuilder()
        .prepareAndroidTunnelConfig(file, endpoint: 'http://127.0.0.1:9090');

    final dns = (jsonDecode(await file.readAsString())
        as Map<String, dynamic>)['dns'] as Map<String, dynamic>;
    expect(dns['enable'], isTrue);
    expect(dns['enhanced-mode'], 'fake-ip');
    expect(dns['nameserver'], isNotEmpty);
  });

  test('Android config closes local proxy ports and verbose logs', () async {
    final directory = await Directory.systemTemp.createTemp('kago-hard-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}active.yaml');
    await file.writeAsString(
        '{"mixed-port":7890,"port":7891,"socks-port":7892,"log-level":"debug"}');

    await const MihomoConfigBuilder()
        .prepareAndroidTunnelConfig(file, endpoint: 'http://127.0.0.1:9090');

    final result =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(result['mixed-port'], 0);
    expect(result.containsKey('port'), isFalse);
    expect(result.containsKey('socks-port'), isFalse);
    expect(result['log-level'], 'warning');
  });

  test('Android config keeps DNS that the subscription enables', () async {
    final directory = await Directory.systemTemp.createTemp('kago-dns-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}active.yaml');
    await file.writeAsString(
        '{"dns":{"enable":true,"nameserver":["https://dns.example/dns-query"]}}');

    await const MihomoConfigBuilder()
        .prepareAndroidTunnelConfig(file, endpoint: 'http://127.0.0.1:9090');

    final dns = (jsonDecode(await file.readAsString())
        as Map<String, dynamic>)['dns'] as Map<String, dynamic>;
    expect(dns['nameserver'], ['https://dns.example/dns-query']);
    expect(dns.containsKey('enhanced-mode'), isFalse);
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

  test('drops a DNS listener from the subscription', () {
    final config = const MihomoConfigBuilder().build(
      'proxies:\n  - name: test\n    type: socks5\n    server: 127.0.0.1\n    port: 1080\n'
      'dns:\n  enable: true\n  listen: 0.0.0.0:53\n',
    );
    final dns = config['dns'] as Map<String, dynamic>;
    expect(dns['enable'], isTrue);
    expect(dns.containsKey('listen'), isFalse);
  });

  test('ensureDns keeps a subscription DNS and adds one when missing', () {
    final own = <String, dynamic>{
      'dns': <String, dynamic>{'enable': true, 'nameserver': <String>['x']}
    };
    MihomoConfigBuilder.ensureDns(own);
    expect((own['dns'] as Map)['nameserver'], <String>['x']);
    final none = <String, dynamic>{};
    MihomoConfigBuilder.ensureDns(none);
    expect((none['dns'] as Map)['enable'], isTrue);
    expect((none['dns'] as Map)['enhanced-mode'], 'fake-ip');
  });
}
