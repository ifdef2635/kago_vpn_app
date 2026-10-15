import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/subscriptions/config_builder.dart';
import '../../features/guest/guest_telegram.dart';
import 'anonymous_mode.dart';
import 'app_providers.dart';
import 'desktop_recovery.dart';

final vpnConnectionControllerProvider =
    Provider<VpnConnectionController>((ref) => VpnConnectionController(ref));

/// Owns manual start/stop. The Android service owns its background retries;
/// DesktopRecovery owns retries for a desktop core after this controller arms it.
class VpnConnectionController {
  VpnConnectionController(this.ref);

  final Ref ref;
  static const _channel = MethodChannel('net.usekago.app/service');
  Future<void>? _manualStartDone;
  int _generation = 0;

  Future<bool> startDesktop(File config,
      {required bool guest, required bool anonymous}) async {
    final busy = ref.read(desktopVpnBusyProvider.notifier);
    if (busy.state) return false;
    busy.state = true;
    final generation = ++_generation;
    final done = Completer<void>();
    _manualStartDone = done.future;
    final manager = ref.read(mihomoProcessProvider);
    final recovery = ref.read(desktopRecoveryProvider);
    if (Platform.isWindows || Platform.isMacOS) {
      recovery.arm(config.path, guest: guest, anonymous: anonymous);
    }
    try {
      await manager.start(configPath: config.path);
      if (generation != _generation) return false;
      if (!manager.isRunning) throw StateError('Mihomo stopped during start');
      recovery.connected();
      ref.read(guestModeActiveProvider.notifier).state = guest;
      ref.read(anonymousActiveProvider.notifier).state = anonymous;
      ref.read(desktopCoreRunningProvider.notifier).state = true;
      _refreshCoreData();
      if (anonymous && Platform.isWindows) {
        try {
          final info =
              await ref.read(ipInfoServiceProvider).fetch(proxyPort: 7890);
          if (info.timeZone != null) {
            await WindowsTimeZone.apply(info.timeZone!);
          }
        } catch (_) {
          // Time zone matching is optional; a working VPN is kept.
        }
      }
      return true;
    } catch (error) {
      recovery.startFailed(error);
      ref.read(desktopCoreRunningProvider.notifier).state = manager.isRunning;
      _refreshCoreData();
      rethrow;
    } finally {
      busy.state = false;
      done.complete();
      if (identical(_manualStartDone, done.future)) _manualStartDone = null;
    }
  }

  Future<bool> stopDesktop() async {
    final recovery = ref.read(desktopRecoveryProvider);
    _generation++;
    recovery.cancel();
    await _manualStartDone;
    await recovery.disconnect();
    ref.read(desktopCoreRunningProvider.notifier).state = false;
    _refreshCoreData();
    return true;
  }

  void _refreshCoreData() {
    ref.invalidate(coreVersionProvider);
    ref.invalidate(proxyGroupsProvider);
    ref.invalidate(ipInfoProvider);
  }

  Future<void> startAndroid(File config,
      {required bool guest,
      required bool anonymous,
      DateTime? expiresAt}) async {
    ref.read(guestModeActiveProvider.notifier).state = guest;
    ref.read(anonymousActiveProvider.notifier).state = anonymous;
    final controller = ref.read(mihomoControllerProvider);
    await const MihomoConfigBuilder().prepareAndroidTunnelConfig(
      config,
      endpoint: await controller.endpoint,
      secret: await controller.ensureSecret(),
    );
    await _channel
        .invokeMethod<Map<dynamic, dynamic>>('connect', <String, Object?>{
      'configPath': config.path,
      'guest': guest,
      'expiresAt': guest ? 0 : expiresAt?.millisecondsSinceEpoch ?? 0,
    });
  }

  Future<void> stopAndroid() async =>
      _channel.invokeMethod<Map<dynamic, dynamic>>('disconnect');

  Future<void> startOther() async => _channel.invokeMethod<void>('connect');
}
