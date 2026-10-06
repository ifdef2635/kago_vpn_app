import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/subscriptions/config_builder.dart';

void main() {
  const hostile = '''
proxies:
  - {name: a, type: trojan, server: example.com, port: 443, password: x}
allow-lan: true
bind-address: "*"
external-controller: 0.0.0.0:9090
external-ui: ui
external-ui-url: https://evil.example/ui.zip
external-controller-cors:
  allow-origins: ["*"]
listeners:
  - {name: open, type: mixed, port: 8080, listen: 0.0.0.0}
authentication: ["user:pass"]
''';

  test('a subscription cannot expose the proxy or controller to the LAN', () {
    final config = const MihomoConfigBuilder().build(hostile);

    expect(config['allow-lan'], isFalse);
    expect(config['bind-address'], '127.0.0.1');
    expect(config['external-controller'], '127.0.0.1:9090');
    for (final key in <String>[
      'external-ui',
      'external-ui-url',
      'listeners',
      'authentication',
    ]) {
      expect(config.containsKey(key), isFalse, reason: key);
    }
    expect(config['proxies'], isNotEmpty);
    // Our own CORS replaces the subscription's "*".
    final cors = config['external-controller-cors'] as Map<String, dynamic>;
    expect(cors['allow-origins'], <String>['https://controller.invalid']);
    expect(cors['allow-private-network'], isFalse);
  });

  test('providers cannot overwrite files, ntp cannot set the clock', () {
    final config = const MihomoConfigBuilder().build('''
proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
external-doh-server: /dns-query
ntp: {enable: true, server: time.example, write-to-system: true}
rule-providers:
  evil: {type: http, behavior: domain, url: "https://x.example/r", path: ./active_config.yaml}
  local: {type: file, behavior: domain, path: ./rules/local.yaml}
proxy-providers:
  p: {type: http, url: "https://x.example/p", path: ../../escape.yaml}
''');
    expect(config.containsKey('external-doh-server'), isFalse);
    expect((config['ntp'] as Map)['write-to-system'], isFalse);
    final rules = config['rule-providers'] as Map<String, dynamic>;
    expect((rules['evil'] as Map).containsKey('path'), isFalse);
    expect((rules['local'] as Map)['path'], './rules/local.yaml');
    final proxies = config['proxy-providers'] as Map<String, dynamic>;
    expect((proxies['p'] as Map).containsKey('path'), isFalse);
  });
}
