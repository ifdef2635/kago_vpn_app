import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/mihomo_windows_system_proxy.dart';

void main() {
  test('local addresses always bypass the proxy', () {
    expect(MihomoWindowsSystemProxy.overrideFor(bypassRussian: false),
        'localhost;127.0.0.1;[::1]');
  });

  test('"Russian sites directly" adds .ru/.рф and Yandex/VK domains', () {
    final value =
        MihomoWindowsSystemProxy.overrideFor(bypassRussian: true).split(';');
    expect(value.take(3), <String>['localhost', '127.0.0.1', '[::1]']);
    expect(
        value,
        containsAll(
            <String>['*.ru', '*.xn--p1ai', '*.vk.com', '*.yandex.net']));
    expect(value.toSet().length, value.length, reason: 'no duplicates');
  });
}
