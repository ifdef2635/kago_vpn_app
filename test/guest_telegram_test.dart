import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

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

  test('duplicates, panel placeholders and broken dialer-proxy are skipped',
      () {
    const body = '''
proxies:
  - {name: de, type: ss, server: de.example.com, port: 443, cipher: aes-128-gcm, password: p}
  - {name: de, type: ss, server: de2.example.com, port: 443, cipher: aes-128-gcm, password: p}
  - {name: "Подписка истекла", type: ss, server: 0.0.0.0, port: 1, cipher: aes-128-gcm, password: p}
  - {name: local, type: ss, server: 127.0.0.1, port: 1, cipher: aes-128-gcm, password: p}
  - {name: chained, type: ss, server: nl.example.com, port: 443, cipher: aes-128-gcm, password: p, dialer-proxy: missing}
  - {name: via-de, type: ss, server: fi.example.com, port: 443, cipher: aes-128-gcm, password: p, dialer-proxy: de}
''';
    expect(GuestTelegram.proxiesFrom(body).map((proxy) => proxy['name']),
        <String>['de', 'via-de']);
  });

  group('download from a server that checks the User-Agent', () {
    late HttpServer server;
    late HttpServer panel;
    final seen = <String, Map<String, String?>>{};
    const appAgent = 'mihomo/1.19.32 KaGoVPN/2.0.4 (Windows 24H2)';
    const yaml = '''
proxies:
  - {name: guest-de, type: vless, server: de.example.com, port: 443, uuid: 11111111-2222-3333-4444-555555555555, network: tcp, tls: true}
proxy-groups:
  - {name: Proxy, type: select, proxies: [guest-de]}
rules:
  - MATCH,Proxy
''';

    setUp(() async {
      seen.clear();
      // The panel on another host: only the User-Agent may reach it.
      panel = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      panel.listen((request) {
        seen['panel'] = <String, String?>{
          'ua': request.headers.value('user-agent'),
          'hwid': request.headers.value('x-hwid'),
        };
        request.response
          ..headers.contentType = ContentType.text
          ..write(yaml)
          ..close();
      });
      // usekago.net: like the nginx rule in the README.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        final agent = request.headers.value('user-agent') ?? '';
        seen['site'] = <String, String?>{'ua': agent};
        if (!agent.toLowerCase().contains('kagovpn/')) {
          request.response
            ..statusCode = 404
            ..close();
          return;
        }
        request.response
          ..statusCode = 302
          ..headers.set('location', 'http://localhost:${panel.port}/sub/guest')
          ..close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      await panel.close(force: true);
    });

    Uri site() => Uri.parse('http://127.0.0.1:${server.port}/guest/telegram');

    test('the app gets the servers through the redirect, without HWID',
        () async {
      final proxies =
          await GuestTelegram.download(source: site(), userAgent: appAgent);
      expect(proxies.single['name'], 'guest-de');
      expect(seen['site']!['ua'], appAgent);
      expect(seen['panel']!['ua'], appAgent);
      expect(seen['panel']!['hwid'], isNull);
      // And the config the core gets is valid for the app.
      final config = GuestTelegram.buildConfig(proxies);
      expect((config['rules'] as List).last, 'MATCH,DIRECT');
    });

    test('anyone else gets 404, reported in plain words', () async {
      Object? error;
      try {
        await GuestTelegram.download(
            source: site(), userAgent: 'Mozilla/5.0', dio: Dio());
      } catch (caught) {
        error = caught;
      }
      expect(error, isA<DioException>());
      expect(seen['panel'], isNull);
      expect(GuestTelegram.reason(error!), contains('404'));
    });
  });
}
