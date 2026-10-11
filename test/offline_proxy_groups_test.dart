import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/models/mihomo_models.dart';
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
    expect(
        proxyGroupsFromConfig(config).every((g) => g.selected == null), isTrue);
  });

  test('url-test groups are not manually selectable', () {
    final auto =
        proxyGroupsFromConfig(config).firstWhere((g) => g.name == 'Auto');

    expect(auto.isSelectable, isFalse);
  });

  test('include-all with a filter lists only matching servers', () {
    final asia = proxyGroupsFromConfig(config).last;

    expect(asia.nodes.map((n) => n.name), <String>['Tokyo']);
  });

  test('a config without groups gives an empty list', () {
    expect(proxyGroupsFromConfig(<String, dynamic>{}), isEmpty);
  });

  // As the KAGO subscription: «Самый быстрый» takes all servers except
  // Россия and Авто (two patterns separated by a backtick).
  final kago = <String, dynamic>{
    'proxies': <dynamic>[
      for (final name in <String>[
        '🇩🇪 Германия ⚡️',
        '🇳🇱 Нидерланды',
        '🇷🇺 Россия',
        '🇩🇪 Германия',
        'Резерв HTTP',
      ])
        <String, dynamic>{
          'name': name,
          'type': name.startsWith('Резерв') ? 'http' : 'vless',
          if (name == '🇳🇱 Нидерланды') 'server-description': ' 10 Гбит/с ',
        },
    ],
    'proxy-groups': <dynamic>[
      <String, dynamic>{
        'name': '🌍 VPN',
        'type': 'select',
        'description': 'Основная группа',
        'proxies': <String>['⚡️ Самый быстрый', '🇳🇱 Нидерланды'],
      },
      <String, dynamic>{
        'name': '⚡️ Самый быстрый',
        'type': 'url-test',
        'include-all': true,
        'exclude-filter': 'Россия`Авто',
        'exclude-type': 'Http|Socks5',
      },
      <String, dynamic>{
        'name': 'Германия',
        'type': 'select',
        'include-all': true,
        'filter': 'Нидерланды`Германия',
      },
    ],
  };

  test('filters: several patterns, exclude-type, sorted like the core', () {
    final groups = proxyGroupsFromConfig(kago);
    // The core sorts include-all servers by code point (Go string order).
    expect(groups[1].nodes.map((n) => n.name), <String>[
      '🇩🇪 Германия',
      '🇩🇪 Германия ⚡️',
      '🇳🇱 Нидерланды',
    ]);
    // Matches of the first pattern first, then of the next one.
    expect(groups[2].nodes.map((n) => n.name), <String>[
      '🇳🇱 Нидерланды',
      '🇩🇪 Германия',
      '🇩🇪 Германия ⚡️',
    ]);
  });

  test('group and server descriptions come from the config', () {
    final groups = proxyGroupsFromConfig(kago);
    expect(groups.first.description, 'Основная группа');
    expect(groups[1].description, isNull);
    final node =
        groups.first.nodes.firstWhere((n) => n.name == '🇳🇱 Нидерланды');
    expect(node.description, '10 Гбит/с');
  });

  test('the running core\'s groups get the profile descriptions', () {
    final descriptions = ProfileDescriptions.of(kago);
    const live =
        ProxyGroup(name: '🌍 VPN', type: 'Selector', nodes: <ProxyNode>[
      ProxyNode(name: '🇳🇱 Нидерланды', type: 'Vless', delay: 80),
    ]);
    final group = live.withDescriptions(descriptions);
    expect(group.description, 'Основная группа');
    expect(group.nodes.single.description, '10 Гбит/с');
    expect(group.nodes.single.delay, 80);
    expect(
        ProfileDescriptions.of(<String, dynamic>{
          'proxies': <dynamic>[
            <String, dynamic>{'name': 'A', 'serverDescription': 'Быстрый'},
          ],
        }).servers,
        <String, String>{'A': 'Быстрый'});
  });
}
