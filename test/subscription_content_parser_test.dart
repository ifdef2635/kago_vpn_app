import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/subscriptions/config_builder.dart';
import 'package:kago_vpn/features/subscriptions/subscription_content_parser.dart';

void main() {
  const parser = SubscriptionContentParser();

  test('preserves a valid Mihomo YAML subscription', () {
    const yaml = '''
proxies:
  - name: node-1
    type: ss
    server: edge.example
    port: 443
    cipher: aes-128-gcm
    password: test
''';

    expect(parser.toMihomoConfig(yaml), yaml.trim());
  });

  test('decodes a base64-encoded Mihomo YAML subscription', () {
    const yaml = 'proxies:\n  - name: node-1\n    type: trojan\n';
    final encoded = base64.encode(utf8.encode(yaml));

    expect(parser.toMihomoConfig(encoded), yaml.trim());
  });

  test('converts VLESS Reality share links to a selectable Mihomo config', () {
    const link =
        'vless://11111111-2222-3333-4444-555555555555@edge.example:443?security=reality&pbk=public-key&sid=0102&type=ws&host=cdn.example&path=%2Fedge&sni=cdn.example&fp=chrome#Tokyo';

    final normalized = parser.toMihomoConfig(link);
    final config = const MihomoConfigBuilder().build(normalized);
    final proxies = config['proxies']! as List<dynamic>;
    final proxy = proxies.single as Map<String, dynamic>;

    expect(proxy['type'], 'vless');
    expect(proxy['server'], 'edge.example');
    expect(proxy['uuid'], '11111111-2222-3333-4444-555555555555');
    expect(proxy['tls'], true);
    expect(proxy['name'], 'Tokyo');
    expect((proxy['reality-opts'] as Map<String, dynamic>)['public-key'],
        'public-key');
    expect(config['rules'], <String>['MATCH,KaGo VPN']);
  });

  test('converts VMess base64 URI and preserves websocket transport', () {
    final payload = base64Url
        .encode(utf8.encode(jsonEncode(<String, Object>{
          'ps': 'Osaka',
          'add': 'vmess.example',
          'port': '8443',
          'id': 'aabbccdd',
          'aid': '0',
          'net': 'ws',
          'host': 'cdn.example',
          'path': '/vmess',
          'tls': 'tls',
        })))
        .replaceAll('=', '');

    final config = const MihomoConfigBuilder()
        .build(parser.toMihomoConfig('vmess://$payload'));
    final proxy =
        (config['proxies']! as List<dynamic>).single as Map<String, dynamic>;

    expect(proxy['type'], 'vmess');
    expect(proxy['name'], 'Osaka');
    expect(proxy['tls'], true);
    expect((proxy['ws-opts'] as Map<String, dynamic>)['path'], '/vmess');
  });

  test('converts Shadowsocks, Hysteria2 and TUIC links', () {
    const body = '''
ss://YWVzLTI1Ni1nY206cGFzcw@ss.example:8388#SS
hysteria2://password@hy2.example:443?sni=hy2.example&obfs=salamander&obfs-password=mask#HY2
tuic://uuid:password@tuic.example:443?congestion_control=bbr&udp_relay_mode=native#TUIC
''';

    final config =
        const MihomoConfigBuilder().build(parser.toMihomoConfig(body));
    final proxies =
        (config['proxies']! as List<dynamic>).cast<Map<String, dynamic>>();

    expect(proxies.map((proxy) => proxy['type']),
        <String>['ss', 'hysteria2', 'tuic']);
    expect(proxies.first['cipher'], 'aes-256-gcm');
    expect(proxies[1]['obfs-password'], 'mask');
    expect(proxies[2]['uuid'], 'uuid');
  });

  test('rejects HTML and unsupported share links instead of saving bad config',
      () {
    expect(() => parser.toMihomoConfig('<html>not a subscription</html>'),
        throwsFormatException);
    expect(() => parser.toMihomoConfig('ssr://unsupported'),
        throwsFormatException);
  });

  test('decodes percent-encoded share-link names (flags, Cyrillic, spaces)',
      () {
    const name =
        '%F0%9F%87%A9%F0%9F%87%AA%20%D0%93%D0%B5%D1%80%D0%BC%D0%B0%D0%BD%D0%B8%D1%8F%20%E2%9A%A1';
    const link =
        'vless://11111111-2222-3333-4444-555555555555@edge.example:443?security=tls&sni=edge.example#$name';

    final normalized = parser.toMihomoConfig(link);
    final config = const MihomoConfigBuilder().build(normalized);
    final proxies = config['proxies']! as List<dynamic>;
    final proxy = proxies.single as Map<String, dynamic>;

    expect(proxy['name'], '\u{1F1E9}\u{1F1EA} Германия \u26A1');
    expect(jsonEncode(config), isNot(contains('%F0%9F')));
  });

  test('does not fail on a stray percent sign in a share-link name', () {
    const link =
        'trojan://secret@edge.example:443?sni=edge.example#100%25%ZZ-broken';

    final normalized = parser.toMihomoConfig(link);
    final config = const MihomoConfigBuilder().build(normalized);
    final proxies = config['proxies']! as List<dynamic>;
    final proxy = proxies.single as Map<String, dynamic>;

    expect(proxy['name'], isNotEmpty);
  });
}
