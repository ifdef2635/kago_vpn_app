import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kago_vpn/app/kago_app.dart';
import 'package:kago_vpn/core/theme/app_widgets.dart';
import 'package:kago_vpn/core/models/mihomo_models.dart';
import 'package:kago_vpn/core/network/app_providers.dart';
import 'package:kago_vpn/core/network/desktop_recovery.dart';
import 'package:kago_vpn/core/network/ip_info_service.dart';
import 'package:kago_vpn/core/network/mihomo_controller.dart';
import 'package:kago_vpn/core/network/mihomo_process_manager.dart';
import 'package:kago_vpn/core/network/mihomo_windows_core_updater.dart';
import 'package:kago_vpn/features/guest/guest_telegram.dart';
import 'package:kago_vpn/features/proxies/proxy_mode.dart';
import 'package:kago_vpn/features/subscriptions/subscription_providers.dart';
import 'package:kago_vpn/features/subscriptions/subscription_repository.dart';
import 'package:kago_vpn/features/update/update_flow.dart';

const _groups = <ProxyGroup>[
  ProxyGroup(
      name: 'Автовыбор KAGO',
      type: 'Selector',
      selected: 'Нидерланды · NL-1',
      nodes: <ProxyNode>[
        ProxyNode(name: 'Нидерланды · NL-1', type: 'Vless', delay: 42),
        ProxyNode(name: 'Германия · DE-2', type: 'Vless', delay: 58),
        ProxyNode(name: 'Финляндия · FI-1', type: 'Vless', delay: 73),
        ProxyNode(name: 'Нидерланды · NL-2', type: 'Vless', delay: 91),
      ]),
  ProxyGroup(
      name: 'Мессенджеры',
      type: 'URLTest',
      selected: 'Германия · DE-2',
      nodes: <ProxyNode>[
        ProxyNode(name: 'Германия · DE-2', type: 'Vless', delay: 58),
      ]),
];
final _profile = ImportedSubscription(
    name: 'KAGO Plus',
    url: 'https://example.invalid/subscription',
    usedBytes: 33 * 1024 * 1024 * 1024,
    totalBytes: 100 * 1024 * 1024 * 1024,
    expiresAt: DateTime(2099, 11, 18),
    groups: const <String>['Автовыбор KAGO']);
const _boundaryKey = ValueKey<String>('mobile-render');

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool guest = false,
  bool connected = true,
  bool busy = false,
  bool recovering = false,
  bool limited = true,
  bool groupsFail = false,
  bool? ipRoute,
  ThemeMode theme = ThemeMode.dark,
  int tab = 0,
  double width = 390,
  double scale = 1,
  ProxyMode mode = ProxyMode.rule,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'kago.theme.mode': theme.name,
    'kago.language': 'ru',
  });
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(ProviderScope(overrides: <Override>[
    mihomoControllerProvider.overrideWithValue(_FakeController()),
    mihomoProcessProvider.overrideWithValue(_FakeProcess()),
    desktopCoreRunningProvider.overrideWith((ref) => connected),
    desktopVpnBusyProvider.overrideWith((ref) => busy),
    desktopRecoveryStatusProvider.overrideWith(
        (ref) => recovering ? RecoveryStatus.recovering : RecoveryStatus.idle),
    vpnActiveProvider.overrideWithValue(connected),
    guestModeNeededProvider.overrideWithValue(guest),
    guestModeActiveProvider.overrideWith((ref) => guest && connected),
    effectiveProxyModeProvider.overrideWithValue(mode),
    proxyModeSyncProvider.overrideWith((ref) {}),
    rootTabIndexProvider.overrideWith((ref) => tab),
    coreVersionProvider.overrideWith((ref) async => 'v1.19.32'),
    proxyGroupsProvider.overrideWith((ref) async {
      if (groupsFail) throw StateError('Synthetic controller error');
      return _groups;
    }),
    connectionsSnapshotProvider.overrideWith((ref) => Stream.value(
        const ConnectionsSnapshot(
            connections: <ActiveConnection>[],
            downloadSpeed: 5033164,
            uploadSpeed: 880640,
            downloadTotal: 1331439861,
            uploadTotal: 228589568))),
    importedSubscriptionProvider.overrideWith((ref) async => guest
        ? null
        : limited
            ? _profile
            : ImportedSubscription(
                name: _profile.name,
                url: _profile.url,
                usedBytes: _profile.usedBytes,
                totalBytes: 0,
                expiresAt: _profile.expiresAt,
                groups: _profile.groups)),
    appUpdateProvider.overrideWith((ref) async => null),
    ipInfoProvider.overrideWith(
        (ref) async => IpInfo(ip: '203.0.113.7', viaVpn: ipRoute ?? connected)),
    subscriptionUsageRefresherProvider.overrideWith((ref) {}),
    subscriptionAutoUpdaterProvider.overrideWith((ref) {}),
  ], child: const RepaintBoundary(key: _boundaryKey, child: KaGoApp())));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return ProviderScope.containerOf(tester.element(find.byType(KaGoApp)));
}

Future<void> _render(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('KAGO_RENDER_DIR');
  if (directory.isEmpty) return;
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/kago_flutter_$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    final onest = FontLoader('Onest');
    for (final weight in <String>[
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black'
    ]) {
      onest.addFont(rootBundle.load('assets/fonts/Onest-$weight.ttf'));
    }
    await onest.load();
    final flags = FontLoader('KagoFlags')
      ..addFont(rootBundle.load('assets/fonts/TwemojiCountryFlags.ttf'));
    await flags.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final theme in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    for (final screen in <String>[
      'connected',
      'guest',
      'guest_connected',
      'servers'
    ]) {
      testWidgets(
          '${theme.name} mobile $screen has working navigation and no overflow',
          (tester) async {
        final container = await _pump(tester,
            theme: theme,
            guest: screen.startsWith('guest'),
            connected: screen != 'guest',
            tab: screen == 'servers' ? 1 : 0);
        expect(tester.takeException(), isNull);
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        if (screen == 'connected') {
          expect(find.text('VPN включён'), findsOneWidget);
          expect(
              find.text('Маршрутизация по правилам подписки'), findsOneWidget);
          await tester.tap(find.text('Ваш сервер'));
          await tester.pump(const Duration(seconds: 1));
          expect(container.read(rootTabIndexProvider), 1);
          container.read(rootTabIndexProvider.notifier).state = 0;
          await tester.pump(const Duration(seconds: 1));
        } else if (screen == 'guest') {
          expect(find.text('Подключить Telegram'), findsOneWidget);
          expect(
              find.text('Сейчас сайты открываются напрямую'), findsOneWidget);
          expect(find.text('Без подписки доступен Telegram'), findsOneWidget);
        } else if (screen == 'guest_connected') {
          expect(
              find.byKey(const ValueKey<String>('server-ip')), findsOneWidget);
          expect(find.text('IP через VPN'), findsNothing);
          expect(find.text('Ваш IP'), findsOneWidget);
        } else {
          expect(find.byType(TextField), findsOneWidget);
          expect(find.text('Нидерланды · NL-1'), findsNWidgets(2));
        }
        await _render(tester, '${theme.name}_$screen');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('busy mobile connect action is disabled and shows its state',
      (tester) async {
    await _pump(tester, connected: false, busy: true);
    expect(find.text('Подключение…'), findsWidgets);
    final button = tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('global and recovering states do not claim subscription rules',
      (tester) async {
    await _pump(tester, mode: ProxyMode.global, recovering: true, busy: true);
    expect(find.text('Восстанавливаем соединение'), findsOneWidget);
    expect(
        find.text('Весь трафик идёт через выбранный сервер'), findsOneWidget);
    expect(find.text('Маршрутизация по правилам подписки'), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(find.byType(OutlinedButton).first)
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('IP belongs to the chosen server and can be hidden',
      (tester) async {
    await _pump(tester);
    final ip = find.byKey(const ValueKey<String>('server-ip'));
    final server =
        find.ancestor(of: ip, matching: find.byType(SurfaceCard)).first;
    expect(find.descendant(of: server, matching: find.text('Ваш сервер')),
        findsOneWidget);
    expect(find.text('203.0.113.7'), findsOneWidget);
    await tester.tap(find.byTooltip('Скрыть IP'));
    await tester.pump();
    expect(find.text('203.0.113.7'), findsNothing);
    expect(find.byTooltip('Показать IP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('an address from the previous route is not presented as VPN IP',
      (tester) async {
    await _pump(tester, ipRoute: false);
    expect(find.text('203.0.113.7'), findsNothing);
    expect(find.text('Определяем…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('a controller error keeps the independently loaded IP visible',
      (tester) async {
    await _pump(tester, groupsFail: true);
    expect(find.text('Не удалось загрузить список серверов.'), findsOneWidget);
    expect(find.text('203.0.113.7'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('server-ip')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('unlimited plan hides byte totals and quota progress',
      (tester) async {
    await _pump(tester, limited: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Безлимит'), findsOneWidget);
    expect(find.textContaining('33.0 ГБ'), findsNothing);
    expect(find.text('1.2 ГБ'), findsNothing);
    expect(find.text('218 МБ'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('limited plan keeps usage and its progress indicator',
      (tester) async {
    await _pump(tester);
    expect(find.textContaining('33.0 ГБ из 100 ГБ'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('218 МБ'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final tab in <int>[0, 1]) {
    testWidgets('narrow screen and larger text remain scrollable, tab $tab',
        (tester) async {
      await _pump(tester, width: 320, scale: 1.6, tab: tab);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _FakeController extends MihomoController {
  @override
  Future<String> get endpoint async => 'http://127.0.0.1:9090';
  @override
  Future<String?> get configuredSecret async => null;
  @override
  Future<void> setMode(String mode) async {}
}

class _FakeProcess extends MihomoProcessManager {
  @override
  Future<String?> get executable async => null;
  @override
  Future<MihomoCoreInstall?> installedCore() async => null;
}
