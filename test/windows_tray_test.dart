import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/desktop/windows_tray.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('«Выход» stops the core before the window closes', () async {
    var stopped = false;
    final reply = await WindowsTray.handle(const MethodCall('quit'), () async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      stopped = true;
    });
    expect(stopped, isTrue);
    expect(reply, isTrue);
  });

  test('a failing or hanging stop still lets the app quit', () async {
    expect(
        await WindowsTray.handle(
            const MethodCall('quit'), () async => throw StateError('core')),
        isTrue);
    final started = DateTime.now();
    expect(
        await WindowsTray.handle(
            const MethodCall('quit'), () => Completer<void>().future),
        isTrue);
    expect(DateTime.now().difference(started),
        lessThan(WindowsTray.quitTimeout + const Duration(seconds: 1)));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('the tray hint is shown once', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await WindowsTray.handle(const MethodCall('hintShown'), () async {});
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('kago.windows.tray.hint.v1'), isTrue);
  });

  test('unknown calls are reported as not implemented', () {
    expect(WindowsTray.handle(const MethodCall('other'), () async {}),
        throwsA(isA<MissingPluginException>()));
  });
}
