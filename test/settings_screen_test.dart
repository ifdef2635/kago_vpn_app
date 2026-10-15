import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/app_providers.dart';
import 'package:kago_vpn/features/settings/settings_screen.dart';
import 'package:kago_vpn/features/subscriptions/subscription_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, {required bool running}) async {
  tester.view.physicalSize = const Size(420, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: <Override>[
    vpnActiveProvider.overrideWithValue(running),
    importedSubscriptionProvider.overrideWith((ref) async => null),
  ], child: const MaterialApp(home: Scaffold(body: SettingsScreen()))));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the last row restarts the core, as in FlClashX', (tester) async {
    await _pump(tester, running: true);
    expect(find.text('Перезапустить ядро'), findsOneWidget);
    expect(find.text('Работает'), findsOneWidget);
    // The last row of the screen.
    final rows = find.byType(InkWell).evaluate().toList();
    final restart = find
        .ancestor(
            of: find.text('Перезапустить ядро'), matching: find.byType(InkWell))
        .evaluate()
        .first;
    expect(rows.last, restart);
    expect((restart.widget as InkWell).onTap, isNotNull);
    // The advanced section is gone.
    expect(find.text('Дополнительно'.toUpperCase()), findsNothing);
  });

  testWidgets('with the core stopped there is nothing to restart',
      (tester) async {
    await _pump(tester, running: false);
    expect(find.text('Остановлено'), findsOneWidget);
    final restart = find
        .ancestor(
            of: find.text('Перезапустить ядро'), matching: find.byType(InkWell))
        .evaluate()
        .first;
    expect((restart.widget as InkWell).onTap, isNull);
  });
}
