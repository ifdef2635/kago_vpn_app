import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/settings/app_routing_screen.dart';

/// The subscription's own list of apps that bypass the VPN on Android
/// (`tun.exclude-package`); the VPN service merges it with the user's choice.
void main() {
  test('apps the subscription sends around the VPN', () {
    final json = jsonEncode(<String, Object>{
      'tun': <String, Object>{
        'enable': false,
        'exclude-package': <Object>[
          'ru.sberbankmobile',
          ' ru.ozon.app.android ',
          '',
          42
        ],
      },
    });
    expect(bypassPackagesOf(json),
        <String>{'ru.sberbankmobile', 'ru.ozon.app.android'});
    expect(bypassPackagesOf('tun:\n  exclude-package:\n    - com.vk.im\n'),
        <String>{'com.vk.im'});
    expect(bypassPackagesOf('{"mode": "rule"}'), isEmpty);
  });
}
