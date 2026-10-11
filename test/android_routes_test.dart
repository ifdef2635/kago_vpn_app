import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/android_routes.dart';

/// Whether [address] goes into the tunnel with [routes].
bool routed(List<String> routes, String address) {
  final target = IpPrefix.parse(address)!;
  return routes.any((route) => IpPrefix.parse(route)!.contains(target));
}

Map<String, dynamic> config({bool ipv6 = false, List<String>? exclude}) =>
    <String, dynamic>{
      'ipv6': ipv6,
      'dns': <String, dynamic>{
        'enable': true,
        'fake-ip-range': '198.18.0.1/16',
      },
      'tun': <String, dynamic>{
        // As the KAGO subscription.
        'route-exclude-address': exclude ??
            <String>[
              '0.0.0.0/8',
              '10.0.0.0/8',
              '100.64.0.0/10',
              '127.0.0.0/8',
              '169.254.0.0/16',
              '172.16.0.0/12',
              '192.0.0.0/24',
              '192.0.2.0/24',
              '192.88.99.0/24',
              '192.168.0.0/16',
              '198.51.100.0/24',
              '203.0.113.0/24',
              '224.0.0.0/3',
            ],
      },
    };

void main() {
  test('local networks bypass the VPN, the internet goes through it', () {
    final routes = AndroidRoutes.compute(config())!;
    for (final local in <String>['192.168.1.1', '10.0.0.5', '224.0.0.251']) {
      expect(routed(routes, local), isFalse, reason: local);
    }
    for (final remote in <String>['8.8.8.8', '1.1.1.1', '95.0.0.1']) {
      expect(routed(routes, remote), isTrue, reason: remote);
    }
    // 172.16.0.0/12 holds the tunnel's own DNS: it stays inside.
    expect(routed(routes, '172.19.0.2'), isTrue);
    expect(routed(routes, '172.20.0.1'), isFalse);
    // The fake IPs of the core's DNS.
    expect(routed(routes, '198.18.3.4'), isTrue);
    expect(routes.any((route) => route.contains(':')), isFalse);
    expect(routes.length, lessThan(200));
  });

  test('IPv6 routes only with IPv6 on', () {
    final routes = AndroidRoutes.compute(
        config(ipv6: true, exclude: <String>['192.168.0.0/16', 'fc00::/7']))!;
    expect(routed(routes, '2001:4860::8888'), isTrue);
    expect(routed(routes, 'fd00::1'), isFalse);
    expect(routed(routes, 'fdfe:dcba:9876::2'), isTrue);
  });

  test('no route settings: everything, as before', () {
    final plain = config(exclude: const <String>[]);
    expect(AndroidRoutes.compute(plain), isNull);
    AndroidRoutes.apply(plain);
    expect((plain['tun'] as Map).containsKey(AndroidRoutes.configKey), isFalse);
  });

  test('route-address limits the tunnel, keeping its DNS and fake IPs', () {
    final c = config(exclude: const <String>[]);
    (c['tun'] as Map<String, dynamic>)['route-address'] = <String>[
      '91.108.0.0/16',
    ];
    final routes = AndroidRoutes.compute(c)!;
    expect(routed(routes, '91.108.4.1'), isTrue);
    expect(routed(routes, '8.8.8.8'), isFalse);
    expect(routed(routes, '172.19.0.2'), isTrue);
    expect(routed(routes, '198.18.0.9'), isTrue);
  });

  test('the result is the same when prepared again', () {
    final c = config();
    AndroidRoutes.apply(c);
    final first = List<String>.of(
        (c['tun'] as Map)[AndroidRoutes.configKey] as List<String>);
    AndroidRoutes.apply(c);
    expect((c['tun'] as Map)[AndroidRoutes.configKey], first);
  });

  test('prefixes are parsed and normalised', () {
    expect(IpPrefix.parse('192.168.1.7/16').toString(), '192.168.0.0/16');
    expect(IpPrefix.parse('8.8.8.8').toString(), '8.8.8.8/32');
    expect(IpPrefix.parse('fc00::/7').toString(), 'fc00:0:0:0:0:0:0:0/7');
    for (final bad in <String>['', '1.2.3/8', '10.0.0.0/33', 'x', '1.2.3.4/']) {
      expect(IpPrefix.parse(bad), isNull, reason: bad);
    }
  });
}
