import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/desktop_recovery.dart';
import 'package:kago_vpn/core/network/mihomo_controller.dart';
import 'package:kago_vpn/core/network/mihomo_process_manager.dart';
import 'package:kago_vpn/core/network/app_providers.dart';
import 'package:kago_vpn/core/network/vpn_connection_controller.dart';

class _Manager extends MihomoProcessManager {
  final _events = StreamController<int>.broadcast();
  bool running = true;
  int starts = 0;
  int stops = 0;
  int failures = 0;
  bool expectedElevation = false;
  Completer<void>? startGate;

  @override
  Stream<int> get exits => _events.stream;

  @override
  bool get isRunning => running;

  @override
  Future<void> start(
      {required String configPath, bool allowElevation = true}) async {
    expect(allowElevation, expectedElevation);
    starts++;
    if (startGate != null) await startGate!.future;
    if (failures > 0) {
      failures--;
      throw StateError('temporary core failure');
    }
    running = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }

  void crash() {
    running = false;
    _events.add(1);
  }

  Future<void> close() => _events.close();
}

Future<void> _settle([int milliseconds = 35]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void main() {
  late ProviderContainer container;
  late _Manager manager;
  late DesktopRecovery recovery;

  setUp(() {
    manager = _Manager();
    container = ProviderContainer();
  });

  tearDown(() async {
    recovery.dispose();
    container.dispose();
    await manager.close();
  });

  DesktopRecovery create({
    Future<bool> Function()? health,
    Future<String?> Function()? interfaceSnapshot,
    Future<String?> Function(String, bool)? preflight,
    List<Duration> delays = const <Duration>[Duration(milliseconds: 1)],
  }) {
    final provider = Provider<DesktopRecovery>((ref) => DesktopRecovery(ref,
        manager: manager,
        controller: MihomoController(),
        watchNetwork: false,
        retryDelays: delays,
        networkDebounce: Duration.zero,
        probeInterval: Duration.zero,
        interfaceSnapshot: interfaceSnapshot ?? () async => 'wifi:192.0.2.1',
        remoteHealth: health,
        retryPreflight: preflight ?? (_, __) async => null));
    recovery = container.read(provider);
    recovery.arm('profile.json', guest: true, anonymous: false);
    recovery.connected();
    return recovery;
  }

  test('core crash restarts once and clears recovery state', () async {
    create();
    manager.crash();
    await _settle();
    expect(manager.starts, 1);
    expect(manager.running, true);
    expect(container.read(desktopRecoveryStatusProvider), RecoveryStatus.idle);
  });

  test('network change leaves a healthy core running', () async {
    var probes = 0;
    create(health: () async {
      probes++;
      return true;
    });
    recovery.onNetworkChanged();
    await _settle();
    expect(probes, 1);
    expect(manager.stops, 0);
    expect(manager.starts, 0);
  });

  test('network change restarts only after two failed probes', () async {
    var probes = 0;
    create(health: () async {
      probes++;
      return false;
    });
    recovery.onNetworkChanged();
    await _settle();
    expect(probes, 2);
    expect(manager.stops, 1);
    expect(manager.starts, 1);
  });

  test('no physical network does not stop a running core', () async {
    var probes = 0;
    create(
        interfaceSnapshot: () async => '',
        health: () async {
          probes++;
          return false;
        });
    recovery.onNetworkChanged();
    await _settle();
    expect(probes, 0);
    expect(manager.stops, 0);
  });

  test('retry schedule grows and caps at five minutes', () {
    create();
    expect(
        List<Duration>.generate(8, DesktopRecovery.delayForAttempt), <Duration>[
      const Duration(seconds: 2),
      const Duration(seconds: 5),
      const Duration(seconds: 15),
      const Duration(seconds: 30),
      const Duration(seconds: 60),
      const Duration(minutes: 5),
      const Duration(minutes: 5),
      const Duration(minutes: 5),
    ]);
  });

  test('temporary startup failure is retried', () async {
    manager.failures = 2;
    create();
    manager.crash();
    await _settle(70);
    expect(manager.starts, 3);
    expect(manager.running, true);
  });

  test('manual disconnect cancels a waiting retry', () async {
    create(delays: const <Duration>[Duration(milliseconds: 80)]);
    manager.crash();
    await _settle(5);
    await recovery.disconnect();
    await _settle(100);
    expect(manager.starts, 0);
    expect(recovery.desired, false);
  });

  test('new network bypasses a waiting retry', () async {
    create(delays: const <Duration>[Duration(milliseconds: 100)]);
    manager.crash();
    await _settle(5);
    recovery.onNetworkChanged();
    await _settle();
    expect(manager.starts, 1);
  });

  test('expired subscription stops retries with an actionable error', () async {
    create(preflight: (_, __) async => 'Subscription expired');
    manager.crash();
    await _settle();
    expect(manager.starts, 0);
    expect(recovery.desired, false);
    expect(container.read(desktopRecoveryStatusProvider),
        RecoveryStatus.needsAction);
  });

  test('disconnect waits for an in-flight restart before stopping', () async {
    manager.startGate = Completer<void>();
    create();
    manager.crash();
    await _settle(10);
    expect(manager.starts, 1);
    final stopping = recovery.disconnect();
    manager.startGate!.complete();
    await stopping;
    expect(manager.running, false);
    expect(recovery.desired, false);
  });

  test('account exit can stop during a manual start', () async {
    create();
    manager.expectedElevation = true;
    manager.running = false;
    manager.startGate = Completer<void>();
    final recoveryProvider = Provider<DesktopRecovery>((ref) => DesktopRecovery(
        ref,
        manager: manager,
        controller: MihomoController(),
        watchNetwork: false));
    final scope = ProviderContainer(overrides: [
      mihomoProcessProvider.overrideWith((ref) => manager),
      desktopRecoveryProvider.overrideWith((ref) => ref.read(recoveryProvider)),
    ]);
    final scopedRecovery = scope.read(recoveryProvider);
    final connection = scope.read(vpnConnectionControllerProvider);
    final starting = connection.startDesktop(File('profile.json'),
        guest: true, anonymous: false);
    await _settle(5);
    final stopping = connection.stopDesktop();
    manager.startGate!.complete();
    expect(await starting, false);
    expect(await stopping, true);
    expect(manager.running, false);
    scopedRecovery.dispose();
    scope.dispose();
  });
}
