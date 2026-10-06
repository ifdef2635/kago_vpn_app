import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/mihomo_macos.dart';
import 'package:kago_vpn/core/network/mihomo_windows_system_proxy.dart';

void main() {
  test('network services: skips the note and disabled services', () {
    const output = '''
An asterisk (*) denotes that a network service is disabled.
Wi-Fi
*Thunderbolt Bridge
USB 10/100/1000 LAN

''';
    expect(MihomoMacosSystemProxy.parseServices(output),
        <String>['Wi-Fi', 'USB 10/100/1000 LAN']);
  });

  test('bypass list includes Russian sites only when asked', () {
    final plain = MihomoMacosSystemProxy.bypassFor(bypassRussian: false);
    final russian = MihomoMacosSystemProxy.bypassFor(bypassRussian: true);
    expect(plain, contains('localhost'));
    expect(plain, isNot(contains('*.ru')));
    expect(russian, containsAll(MihomoWindowsSystemProxy.russianBypass));
  });
}
