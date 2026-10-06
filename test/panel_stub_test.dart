import 'package:flutter_test/flutter_test.dart';
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
}
