import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/offline_proxy_groups.dart';

void main() {
  final config = <String, dynamic>{
    'proxies': <dynamic>[
      <String, dynamic>{'name': 'Berlin', 'type': 'vless'},
      <String, dynamic>{'name': 'Oslo', 'type': 'ss'},
      <String, dynamic>{'name': 'Tokyo', 'type': 'trojan'},
    ],
    'proxy-groups': <dynamic>[
      <String, dynamic>{
        'name': 'KaGo VPN',
        'type': 'select',
        'proxies': <String>['Auto', 'Berlin', 'Oslo', 'DIRECT'],
      },
      <String, dynamic>{
        'name': 'Auto',
        'type': 'url-test',
        'proxies': <String>['Berlin', 'Oslo'],
      },
      <String, dynamic>{
        'name': 'Asia',
        'type': 'select',
        'include-all': true,
        'filter': 'Tokyo',
      },
    ],
  };

  test('groups keep config order and nodes get protocol types', () {
    final groups = proxyGroupsFromConfig(config);

    expect(groups.map((g) => g.name), <String>['KaGo VPN', 'Auto', 'Asia']);
    final main = groups.first;
    expect(main.isSelectable, isTrue);
    final byName = {for (final n in main.nodes) n.name: n};
    expect(byName['Berlin']!.type, 'Vless');
    expect(byName['Oslo']!.type, 'Shadowsocks');
    expect(byName['DIRECT']!.type, 'Direct');
    // A nested group shows up as a group, not as a server.
    expect(byName['Auto']!.isGroup, isTrue);
  });

  test('without the core nothing is claimed to be selected', () {
    expect(proxyGroupsFromConfig(config).every((g) => g.selected == null),
        isTrue);
  });

  test('url-test groups are not manually selectable', () {
    final auto = proxyGroupsFromConfig(config).firstWhere((g) => g.name == 'Auto');

    expect(auto.isSelectable, isFalse);
  });

  test('include-all with a filter lists only matching servers', () {
    final asia = proxyGroupsFromConfig(config).last;

    expect(asia.nodes.map((n) => n.name), <String>['Tokyo']);
  });

  test('a config without groups gives an empty list', () {
    expect(proxyGroupsFromConfig(<String, dynamic>{}), isEmpty);
  });
}
