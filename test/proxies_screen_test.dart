import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/models/mihomo_models.dart';
import 'package:kago_vpn/core/network/app_providers.dart';
import 'package:kago_vpn/core/network/mihomo_controller.dart';
import 'package:kago_vpn/features/guest/guest_telegram.dart';
import 'package:kago_vpn/features/proxies/proxies_screen.dart';
import 'package:kago_vpn/features/proxies/proxy_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _groups = <ProxyGroup>[
  ProxyGroup(
      name: '🌍 VPN',
      type: 'Selector',
      selected: 'Германия',
      nodes: <ProxyNode>[
        ProxyNode(name: '⚡️ Самый быстрый', type: 'URLTest'),
        ProxyNode(name: 'Германия', type: 'Vless', delay: 84),
        ProxyNode(name: 'Нидерланды', type: 'Vless'),
      ]),
  ProxyGroup(
      name: '⚡️ Самый быстрый',
      type: 'URLTest',
      selected: 'Германия',
      nodes: <ProxyNode>[
        ProxyNode(name: 'Германия', type: 'Vless', delay: 84),
        ProxyNode(name: 'Швеция', type: 'Vless'),
      ]),
  ProxyGroup(
      name: 'Служебная',
      type: 'Selector',
      hidden: true,
      nodes: <ProxyNode>[ProxyNode(name: 'Скрытый', type: 'Vless')]),
  ProxyGroup(
      name: 'GLOBAL',
      type: 'Selector',
      nodes: <ProxyNode>[ProxyNode(name: '🌍 VPN', type: 'Selector')]),
];

Future<void> _pump(WidgetTester tester, {MihomoController? controller}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: <Override>[
    vpnActiveProvider.overrideWithValue(true),
    proxyGroupsProvider.overrideWith((ref) async => _groups),
    if (controller != null)
      mihomoControllerProvider.overrideWithValue(controller),
  ], child: const MaterialApp(home: Scaffold(body: ProxiesScreen()))));
  await tester.pumpAndSettle();
}

class _ModeController extends MihomoController {
  final modes = <String>[];
  final selected = <String>[];

  @override
  Future<void> setMode(String mode) async => modes.add(mode);

  @override
  Future<void> selectProxy(String group, String node) async =>
      selected.add('$group/$node');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('global mode lists only GLOBAL', () {
    expect(
        visibleProxyGroups(_groups, mode: ProxyMode.global)
            .map((group) => group.name),
        <String>['GLOBAL']);
    // Without the core there is no GLOBAL: the groups by rules.
    expect(visibleProxyGroups(_groups.take(2).toList(), mode: ProxyMode.global),
        hasLength(2));
  });

  test('search keeps the matching servers and their groups', () {
    final found = filterProxyGroups(visibleProxyGroups(_groups), 'швец');
    expect(found.map((group) => group.name), <String>['⚡️ Самый быстрый']);
    expect(found.single.nodes.map((node) => node.name), <String>['Швеция']);
    expect(filterProxyGroups(_groups, '  '), same(_groups));
  });

  test('the chosen mode reaches the core when the VPN is up, not for guests',
      () async {
    final controller = _ModeController();
    final container = ProviderContainer(overrides: <Override>[
      vpnActiveProvider.overrideWithValue(true),
      mihomoControllerProvider.overrideWithValue(controller),
      proxyGroupsProvider.overrideWith((ref) async => _groups),
    ]);
    addTearDown(container.dispose);
    final sync = container.listen(proxyModeSyncProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    expect(controller.modes, <String>['rule']);

    await container.read(proxyModeProvider.notifier).set(ProxyMode.global);
    container.read(proxyModeSyncProvider);
    await Future<void>.delayed(Duration.zero);
    expect(controller.modes, <String>['rule', 'global']);
    expect((await SharedPreferences.getInstance()).getString('kago.proxy.mode'),
        'global');

    // Free Telegram access always runs by its rules.
    container.read(guestModeActiveProvider.notifier).state = true;
    container.read(proxyModeSyncProvider);
    await Future<void>.delayed(Duration.zero);
    expect(controller.modes.last, 'rule');
    sync.close();
  });

  test('hidden groups and GLOBAL are not listed', () {
    expect(visibleProxyGroups(_groups).map((group) => group.name),
        <String>['🌍 VPN', '⚡️ Самый быстрый']);
  });

  test('the core reports hidden groups', () {
    final group = ProxyGroup.fromJson('Служебная', <String, dynamic>{
      'type': 'Selector',
      'all': <String>['A'],
      'hidden': true,
    });
    expect(group.hidden, isTrue);
    expect(
        ProxyGroup.fromJson('VPN', <String, dynamic>{'all': <String>[]}).hidden,
        isFalse);
  });

  testWidgets('groups fold like FlClashX; the first one starts unfolded',
      (tester) async {
    await _pump(tester);

    // Group headers: name and the current server.
    expect(find.text('🌍 VPN'), findsOneWidget);
    expect(find.text('Самый быстрый · Германия'), findsOneWidget);
    // «Германия» three times: the manual group's header names its choice,
    // the nested group's card names the server it uses, and the server's card.
    expect(find.text('Германия'), findsNWidgets(3));
    expect(find.text('Служебная'), findsNothing);
    expect(find.text('GLOBAL'), findsNothing);

    // Only the first group shows its servers.
    expect(find.text('Нидерланды'), findsOneWidget);
    expect(find.text('Швеция'), findsNothing);
    expect(find.text('84 мс'), findsWidgets);

    await tester.tap(find.byTooltip('Развернуть'));
    await tester.pumpAndSettle();
    expect(find.text('Швеция'), findsOneWidget);
  });

  testWidgets('a server of an automatic group is not picked by hand',
      (tester) async {
    final controller = _ModeController();
    await _pump(tester, controller: controller);
    await tester.tap(find.byTooltip('Развернуть'));
    await tester.pumpAndSettle();

    // The card does not react and nothing pops up at the bottom.
    await tester.tap(find.text('Швеция'));
    await tester.pump();
    expect(controller.selected, isEmpty);
    expect(find.byType(SnackBar), findsNothing);

    // A server of a manual group is chosen.
    await tester.tap(find.text('Нидерланды'));
    await tester.pump();
    expect(controller.selected, <String>['🌍 VPN/Нидерланды']);
  });

  testWidgets('search finds a server in a folded group', (tester) async {
    await _pump(tester);
    expect(find.text('Швеция'), findsNothing);

    await tester.tap(find.byTooltip('Поиск'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'шве');
    await tester.pumpAndSettle();
    expect(find.text('Швеция'), findsOneWidget);
    expect(find.text('Нидерланды'), findsNothing);
  });

  testWidgets('the mode menu offers rules and global', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Режим'));
    await tester.pumpAndSettle();
    expect(find.text('По правилам'), findsOneWidget);
    await tester.tap(find.text('Глобальный'));
    await tester.pumpAndSettle();
    // Only GLOBAL is listed now.
    expect(find.text('GLOBAL'), findsOneWidget);
    expect(find.text('Самый быстрый · Германия'), findsNothing);
  });
}
