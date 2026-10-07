import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/anonymous_mode.dart';
import 'package:kago_vpn/core/network/ip_info_service.dart';
import 'package:kago_vpn/features/subscriptions/config_builder.dart';

void main() {
  test('anonymous profile: DNS only through the VPN, no IPv6', () {
    final config = <String, dynamic>{
      'ipv6': true,
      'dns': <String, dynamic>{
        'enable': true,
        'nameserver': <String>['https://dns.provider.ru/dns-query'],
        'fake-ip-filter': <String>['+.example.ru'],
      },
      'proxies': <Object>[],
    };
    AnonymousMode.apply(config);
    expect(config['ipv6'], false);
    final dns = config['dns'] as Map<String, dynamic>;
    expect(dns['respect-rules'], true);
    expect(dns['ipv6'], false);
    expect(dns['enhanced-mode'], 'fake-ip');
    expect(dns['nameserver'], AnonymousMode.nameservers);
    expect(dns['proxy-server-nameserver'], isNotEmpty);
    expect(dns['fake-ip-filter'], <String>['+.example.ru']);
    expect((config['sniffer'] as Map)['enable'], true);
  });

  test(
      'the anonymous profile still passes the usual lock-down and the '
      'macOS TUN filter', () {
    final config = <String, dynamic>{
      'proxies': <Map<String, dynamic>>[
        <String, dynamic>{'name': 'de', 'type': 'ss'},
      ],
    };
    AnonymousMode.apply(config);
    final built = const MihomoConfigBuilder().build(jsonEncode(config));
    expect(built['allow-lan'], false);
    final text = jsonEncode(built).toLowerCase();
    for (final forbidden in <String>[
      'external-controller-unix',
      'external-ui',
      'write-to-system',
      'listeners',
      '!!',
    ]) {
      expect(text, isNot(contains(forbidden)));
    }
  });

  test('IANA zones map to Windows time zone IDs', () {
    expect(WindowsTimeZone.windowsIdFor('Europe/Berlin'),
        'W. Europe Standard Time');
    expect(
        WindowsTimeZone.windowsIdFor('Europe/Helsinki'), 'FLE Standard Time');
    expect(WindowsTimeZone.windowsIdFor('America/New_York'),
        'Eastern Standard Time');
    expect(WindowsTimeZone.windowsIdFor('Europe/Amsterdam'),
        'W. Europe Standard Time');
    expect(WindowsTimeZone.windowsIdFor('Mars/Olympus'), isNull);
  });

  test('IP services report the time zone of the address', () {
    expect(
        IpInfo.fromIpWhoIs(<String, dynamic>{
          'ip': '31.76.47.118',
          'timezone': <String, dynamic>{'id': 'Europe/Berlin'},
        }).timeZone,
        'Europe/Berlin');
    expect(
        IpInfo.fromIpSb(<String, dynamic>{
          'ip': '31.76.47.118',
          'timezone': 'Europe/Berlin',
        }).timeZone,
        'Europe/Berlin');
  });
}
