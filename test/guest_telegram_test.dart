import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/guest/guest_telegram.dart';
import 'package:kago_vpn/features/subscriptions/config_builder.dart';
import 'package:kago_vpn/features/subscriptions/subscription_repository.dart';

void main() {
  ImportedSubscription profile(
          {int used = 0, int total = 0, DateTime? expires, String url = 'x'}) =>
      ImportedSubscription(
          name: 'KaGo',
          url: url,
          usedBytes: used,
          totalBytes: total,
          expiresAt: expires,
          groups: const <String>[]);

  final now = DateTime(2026, 10, 7);

  test('guest mode only without a working subscription', () {
    expect(GuestTelegram.needed(null, now), true);
    expect(GuestTelegram.needed(profile(url: ''), now), true);
    expect(GuestTelegram.needed(profile(expires: DateTime(2026, 10, 6)), now),
        true);
    expect(GuestTelegram.needed(profile(used: 10, total: 10), now), true);
    expect(GuestTelegram.needed(profile(), now), false);
    expect(
        GuestTelegram.needed(
            profile(used: 5, total: 10, expires: DateTime(2026, 11, 1)), now),
        false);
  });

  test('only Telegram goes through the guest server', () {
    final config = GuestTelegram.buildConfig(<Map<String, dynamic>>[
      <String, dynamic>{'name': 'guest-1', 'type': 'vless'},
      <String, dynamic>{'name': 'guest-2', 'type': 'vless'},
    ]);
    final rules = (config['rules'] as List).cast<String>();
    expect(rules.last, 'MATCH,DIRECT');
    expect(rules, contains('DOMAIN-SUFFIX,telegram.org,KaGo Telegram'));
    expect(rules, contains('DOMAIN-SUFFIX,t.me,KaGo Telegram'));
    expect(
        rules, contains('IP-CIDR,149.154.160.0/20,KaGo Telegram,no-resolve'));
    for (final rule in rules.take(rules.length - 1)) {
      expect(rule.split(',')[2], GuestTelegram.groupName);
    }
    final group = (config['proxy-groups'] as List).single as Map;
    expect(group['proxies'], <String>['guest-1', 'guest-2']);
    expect(group['type'], 'fallback');
    expect(() => GuestTelegram.buildConfig(const <Map<String, dynamic>>[]),
        throwsFormatException);
  });

  test('guest config passes the usual lock-down', () {
    final config = GuestTelegram.buildConfig(<Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'guest',
        'type': 'ss',
        'server': 'example.com',
        'port': 443,
        'cipher': 'aes-128-gcm',
        'password': 'p',
      },
    ]);
    final built = const MihomoConfigBuilder().build(jsonEncode(config));
    expect(built['allow-lan'], false);
    expect(built['bind-address'], '127.0.0.1');
    expect((built['dns'] as Map)['enable'], true);
    expect((built['proxy-groups'] as List).single['type'], 'select');
  });

  test('guest servers are read from a Mihomo subscription', () {
    const body = '''
proxies:
  - {name: guest-de, type: ss, server: de.example.com, port: 443, cipher: aes-128-gcm, password: p}
  - {name: broken}
proxy-groups:
  - {name: Proxy, type: select, proxies: [guest-de]}
rules:
  - MATCH,Proxy
''';
    final proxies = GuestTelegram.proxiesFrom(body);
    expect(proxies.map((proxy) => proxy['name']), <String>['guest-de']);
  });
}
