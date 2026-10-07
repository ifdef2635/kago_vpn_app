import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/device/device_identity.dart';
import 'package:kago_vpn/features/subscriptions/subscription_repository.dart';

void main() {
  test('a Remnawave placeholder profile is recognised', () {
    const yaml = '''
proxies:
  - name: "Приложение не поддерживается!"
    type: vless
    server: 0.0.0.0
    port: 1
    uuid: 00000000-0000-0000-0000-000000000000
proxy-groups:
  - name: KaGo VPN
    type: select
    proxies: ["Приложение не поддерживается!", DIRECT]
''';
    expect(SubscriptionRepository.panelStubMessage(yaml),
        'Приложение не поддерживается!');
  });

  test('a real profile is not a placeholder', () {
    const yaml = '''
proxies:
  - name: "Германия"
    type: vless
    server: de.example.com
    port: 443
    uuid: 00000000-0000-0000-0000-000000000000
  - name: "Заглушка"
    type: vless
    server: 0.0.0.0
    port: 1
    uuid: 00000000-0000-0000-0000-000000000000
''';
    expect(SubscriptionRepository.panelStubMessage(yaml), isNull);
    expect(SubscriptionRepository.panelStubMessage('proxies: []'), isNull);
  });

  test('HWID verdict headers from the panel', () {
    final text = base64.encode(utf8.encode('Лимит 3 устройства'));
    expect(
        SubscriptionRepository.hwidNotice(<String, List<String>>{
          'X-Hwid-Max-Devices-Reached': <String>['true'],
          'announce': <String>['base64:$text'],
        }),
        'Лимит 3 устройства');
    expect(
        SubscriptionRepository.hwidNotice(<String, List<String>>{
          'x-hwid-not-supported': <String>['true'],
        }),
        isNotNull);
    expect(
        SubscriptionRepository.hwidNotice(<String, List<String>>{
          'x-hwid-max-devices-reached': <String>['false'],
        }),
        isNull);
  });

  test('Windows HWID is the FlClashX 16-character hash', () {
    // sha256("abc") = ba7816bf8f01cfea…
    expect(DeviceIdentity.compactHwid('abc'), 'BA7816BF8F01CFEA');
  });
}
