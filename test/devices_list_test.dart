import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/theme/kago_theme.dart';
import 'package:kago_vpn/features/account/account_providers.dart';
import 'package:kago_vpn/features/account/account_screen.dart';
import 'package:kago_vpn/features/account/kago_api.dart';
import 'package:kago_vpn/features/subscriptions/subscription_providers.dart';

class _DevicesApi extends KagoApi {
  final rows = <KagoDevice>[
    const KagoDevice(
        hwid: 'device-a',
        model: 'Pixel test',
        platform: 'Android',
        osVersion: '15'),
    const KagoDevice(
        hwid: 'device-b',
        model: 'Laptop test',
        platform: 'Windows',
        osVersion: '11'),
  ];
  String? removed;
  @override
  Future<KagoDevices> devices() async =>
      KagoDevices(devices: List.of(rows), current: rows.length, max: 5);
  @override
  Future<void> deleteDevice(String hwid) async {
    removed = hwid;
    rows.removeWhere((d) => d.hwid == hwid);
  }
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
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets(
      'devices expand into rows and disconnect only the selected device',
      (tester) async {
    final api = _DevicesApi();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          kagoApiProvider.overrideWithValue(api),
          accountUserProvider.overrideWith(
              (ref) async => const KagoUser(name: 'Test account')),
          accountSubscriptionProvider.overrideWith((ref) async => null),
          accountDevicesProvider.overrideWith((ref) => api.devices()),
          accountReferralProvider.overrideWith((ref) async => null),
          importedSubscriptionProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
            theme: KaGoTheme.light(),
            home: const RepaintBoundary(
                key: ValueKey<String>('devices-render'),
                child: Scaffold(body: AccountScreen())))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final section = find.byKey(const PageStorageKey<String>('account-devices'));
    await tester.ensureVisible(section);
    expect(find.text('Pixel test'), findsNothing);
    expect(find.text('2 / 5'), findsOneWidget);
    await tester.tap(find.text('Устройства'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pixel test'), findsOneWidget);
    expect(find.text('Laptop test'), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets);
    expect(tester.takeException(), isNull);
    const directory = String.fromEnvironment('KAGO_RENDER_DIR');
    if (directory.isNotEmpty) {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey<String>('devices-render')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/kago_flutter_devices_list.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
    final remove = find.byTooltip('Отключить').first;
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.removed, 'device-a');
    expect(find.text('Pixel test'), findsNothing);
    expect(find.text('Laptop test'), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
