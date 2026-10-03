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
      'external-controller-cors',
      'listeners',
      'authentication',
    ]) {
      expect(config.containsKey(key), isFalse, reason: key);
    }
    expect(config['proxies'], isNotEmpty);
  });
}
