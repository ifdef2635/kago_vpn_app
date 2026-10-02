import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/mihomo_controller.dart';

void main() {
  Map<String, dynamic> proxies() => <String, dynamic>{
        'GLOBAL': <String, dynamic>{
          'type': 'Selector',
          'now': 'DIRECT',
          'all': <String>['KaGo VPN', 'Auto', 'DIRECT'],
        },
        'Auto': <String, dynamic>{
          'type': 'URLTest',
          'now': 'Berlin',
          'all': <String>['Berlin', 'Oslo'],
        },
        'KaGo VPN': <String, dynamic>{
          'type': 'Selector',
          'now': 'Berlin',
          'all': <String>['Berlin', 'Oslo', 'Down'],
        },
        'Berlin': <String, dynamic>{
          'type': 'Vless',
          'history': <dynamic>[
            <String, dynamic>{'time': 't0', 'delay': 300},
            <String, dynamic>{'time': 't1', 'delay': 120},
          ],
        },
        'Oslo': <String, dynamic>{'type': 'Trojan', 'history': <dynamic>[]},
        'Down': <String, dynamic>{
          'type': 'Shadowsocks',
          'history': <dynamic>[
            <String, dynamic>{'time': 't', 'delay': 0},
          ],
        },
        'DIRECT': <String, dynamic>{'type': 'Direct'},
      };

  test('groups keep config order from GLOBAL.all and GLOBAL goes last', () {
    final groups = MihomoController.parseProxies(proxies());

    // Alphabetical order would be Auto, GLOBAL, KaGo VPN.
    expect(groups.map((group) => group.name),
        <String>['KaGo VPN', 'Auto', 'GLOBAL']);
  });

  test('nodes carry protocol type and the last measured delay', () {
    final group = MihomoController.parseProxies(proxies())
        .firstWhere((group) => group.name == 'KaGo VPN');
    final byName = {for (final node in group.nodes) node.name: node};

    expect(byName['Berlin']!.type, 'Vless');
    expect(byName['Berlin']!.delay, 120);
    expect(byName['Oslo']!.delay, isNull);
    expect(byName['Down']!.delay, 0);
    expect(group.selected, 'Berlin');
  });

  test('only Selector groups accept a manual choice', () {
    final groups = MihomoController.parseProxies(proxies());

    expect(groups.firstWhere((g) => g.name == 'KaGo VPN').isSelectable, isTrue);
    expect(groups.firstWhere((g) => g.name == 'Auto').isSelectable, isFalse);
  });
}
