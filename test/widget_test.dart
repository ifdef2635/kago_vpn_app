import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kago_vpn/app/kago_app.dart';
import 'package:kago_vpn/core/models/mihomo_models.dart';
import 'package:kago_vpn/core/network/app_providers.dart';
import 'package:kago_vpn/core/network/ip_info_service.dart';
import 'package:kago_vpn/core/network/mihomo_controller.dart';
import 'package:kago_vpn/core/network/mihomo_process_manager.dart';
import 'package:kago_vpn/core/network/mihomo_windows_core_updater.dart';
import 'package:kago_vpn/features/subscriptions/subscription_providers.dart';

void main() {
  testWidgets('KaGo VPN root renders brand and responsive navigation',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The app follows the system language; this test checks the Russian UI.
    tester.platformDispatcher.localeTestValue = const Locale('ru');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          mihomoControllerProvider.overrideWithValue(_FakeController()),
          mihomoProcessProvider.overrideWithValue(_FakeProcessManager()),
          coreVersionProvider.overrideWith((ref) async => 'v1.19.32'),
          proxyGroupsProvider.overrideWith((ref) async => const <ProxyGroup>[]),
          connectionsSnapshotProvider
              .overrideWith((ref) => const Stream<ConnectionsSnapshot>.empty()),
          importedSubscriptionProvider.overrideWith((ref) async => null),
          // No network and no timers in widget tests.
          ipInfoProvider
              .overrideWith((ref) async => const IpInfo(ip: '203.0.113.7')),
          subscriptionUsageRefresherProvider.overrideWith((ref) {}),
        ],
        child: const KaGoApp(),
      ),
    );
    await tester.pump();

    expect(find.text('KaGo VPN'), findsOneWidget);
    expect(find.text('Серверы'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}

class _FakeController extends MihomoController {
  @override
  Future<String> get endpoint async => 'http://127.0.0.1:9090';

  @override
  Future<String?> get configuredSecret async => null;

  @override
  Future<String> version() async => 'v1.19.32';

  @override
  Future<List<ProxyGroup>> proxies() async => const <ProxyGroup>[];

  @override
  Future<List<ActiveConnection>> connections() async =>
      const <ActiveConnection>[];
}

class _FakeProcessManager extends MihomoProcessManager {
  @override
  Future<String?> get executable async => null;

  @override
  Future<MihomoCoreInstall?> installedCore() async => null;
}
