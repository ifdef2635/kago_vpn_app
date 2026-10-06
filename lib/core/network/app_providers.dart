import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../features/subscriptions/subscription_providers.dart';
import '../../features/subscriptions/subscription_repository.dart';
import '../models/mihomo_models.dart';
import 'android_vpn_events.dart';
import 'ip_info_service.dart';
import 'mihomo_controller.dart';
import 'mihomo_process_manager.dart';
import 'mihomo_release_api.dart';
import 'offline_proxy_groups.dart';
import 'mihomo_windows_core_updater.dart';
import '../l10n/l10n.dart';

final mihomoControllerProvider =
    Provider<MihomoController>((ref) => MihomoController());

/// Groups and servers. With the core running they come from the controller (with
/// protocol and latency); otherwise from the saved profile, so the servers tab
/// is not an error just because the core is off.
final proxyGroupsProvider = FutureProvider<List<ProxyGroup>>((ref) async {
  if (!ref.watch(vpnActiveProvider)) return loadOfflineProxyGroups();
  return ref.watch(mihomoControllerProvider).proxies();
});

/// Polls `/connections` once per second while something watches it, and derives
/// the current download/upload speed from the cumulative counters.
final connectionsSnapshotProvider =
    StreamProvider.autoDispose<ConnectionsSnapshot>((ref) {
  final controller = ref.watch(mihomoControllerProvider);
  final output = StreamController<ConnectionsSnapshot>();
  DateTime? previousAt;
  int? previousDownload;
  int? previousUpload;
  var polling = false;

  Future<void> poll() async {
    if (polling || output.isClosed) return;
    polling = true;
    try {
      final raw = await controller.connectionsSnapshot();
      final now = DateTime.now();
      var download = 0;
      var upload = 0;
      final lastAt = previousAt;
      final lastDownload = previousDownload;
      final lastUpload = previousUpload;
      if (lastAt != null && lastDownload != null && lastUpload != null) {
        final seconds = now.difference(lastAt).inMilliseconds / 1000;
        if (seconds > 0) {
          // Counters drop when the core restarts; treat that as zero speed.
          if (raw.downloadTotal >= lastDownload) {
            download = ((raw.downloadTotal - lastDownload) / seconds).round();
          }
          if (raw.uploadTotal >= lastUpload) {
            upload = ((raw.uploadTotal - lastUpload) / seconds).round();
          }
        }
      }
      previousAt = now;
      previousDownload = raw.downloadTotal;
      previousUpload = raw.uploadTotal;
      if (!output.isClosed) {
        output.add(raw.withSpeed(download: download, upload: upload));
      }
    } catch (error, stackTrace) {
      previousAt = null;
      previousDownload = null;
      previousUpload = null;
      if (!output.isClosed) output.addError(error, stackTrace);
    } finally {
      polling = false;
    }
  }

  final timer =
      Timer.periodic(const Duration(seconds: 1), (_) => unawaited(poll()));
  ref.onDispose(() {
    timer.cancel();
    unawaited(output.close());
  });
  unawaited(poll());
  return output.stream;
});

enum ProxySort { config, delay, name }

/// Group tab chosen on the servers screen (null: the first group).
final selectedProxyGroupProvider = StateProvider<String?>((ref) => null);
final proxySortProvider = StateProvider<ProxySort>((ref) => ProxySort.config);

/// Latency measured from this app, node name -> ms (-1: test failed).
final proxyDelaysProvider =
    StateProvider<Map<String, int>>((ref) => const <String, int>{});

/// Node names whose latency test is currently running.
final proxyDelayTestingProvider =
    StateProvider<Set<String>>((ref) => const <String>{});
final coreVersionProvider = FutureProvider<String>((ref) async {
  if (Platform.isAndroid) {
    final nativeVersion =
        await ref.watch(androidNativeCoreVersionProvider.future);
    if (nativeVersion != null && nativeVersion.trim().isNotEmpty) {
      return nativeVersion;
    }
  }
  return ref.watch(mihomoControllerProvider).version();
});
final mihomoReleaseApiProvider =
    Provider<MihomoReleaseApi>((ref) => MihomoReleaseApi());
final latestMihomoReleaseProvider = FutureProvider<MihomoReleaseInfo>(
    (ref) => ref.watch(mihomoReleaseApiProvider).latestStable());
final androidNativeCoreVersionProvider = FutureProvider<String?>((ref) async {
  if (!Platform.isAndroid) return null;
  try {
    return await const MethodChannel('net.usekago.app/service')
        .invokeMethod<String>('coreVersion');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
});
final androidCoreUpdateStatusProvider = FutureProvider<String>((ref) async {
  if (!Platform.isAndroid) {
    return tr('Проверка Android core доступна только на Android.');
  }
  final latest = await ref.watch(latestMihomoReleaseProvider.future);
  final installed = await ref.watch(androidNativeCoreVersionProvider.future);
  if (installed == null || installed.trim().isEmpty) {
    return tr(
        'В этой сборке не найден native Mihomo. Android .so должен входить в подписанный APK/AAB.');
  }
  final match = RegExp(r'v?\d+\.\d+\.\d+').firstMatch(installed);
  if (match == null) {
    return tr('Версия встроенного Mihomo не распознана: {installed}',
        <String, Object?>{'installed': installed});
  }
  if (MihomoReleaseApi.compareStableVersions(latest.version, match.group(0)!) >
      0) {
    return tr(
        'Доступен Mihomo {version}. На Android ядро обновляется вместе с новой KaGo VPN сборкой.',
        <String, Object?>{'version': latest.version});
  }
  return tr('Встроенный Mihomo {installed} актуален.',
      <String, Object?>{'installed': installed});
});
final mihomoWindowsCoreUpdaterProvider = Provider<MihomoWindowsCoreUpdater>(
    (ref) => MihomoWindowsCoreUpdater(
        releases: ref.watch(mihomoReleaseApiProvider)));
final mihomoProcessProvider = Provider<MihomoProcessManager>((ref) {
  final manager = MihomoProcessManager(
      coreUpdater: ref.watch(mihomoWindowsCoreUpdaterProvider));
  if (Platform.isWindows) {
    unawaited(manager.recoverStaleSystemProxy());
    unawaited(manager.prepareCore());
  }
  // If the core dies by itself the system proxy is already restored; make the
  // UI say "disconnected" instead of staying on "connected".
  final exitSubscription = manager.exits.listen((_) {
    ref.read(desktopCoreRunningProvider.notifier).state = false;
    ref.invalidate(proxyGroupsProvider);
    ref.invalidate(coreVersionProvider);
  });
  ref.onDispose(() {
    unawaited(exitSubscription.cancel());
    unawaited(manager.dispose());
  });
  return manager;
});
final desktopCoreRunningProvider = StateProvider<bool>((ref) => false);

/// True while a VPN core is up: the desktop core process or the Android service.
final vpnActiveProvider = Provider<bool>((ref) {
  final desktop = ref.watch(desktopCoreRunningProvider);
  final android = Platform.isAndroid &&
      ref.watch(androidVpnEventProvider
          .select((event) => event.value?['state'] == 'connected'));
  return desktop || android;
});

final ipInfoServiceProvider = Provider<IpInfoService>((ref) => IpInfoService());

/// Hides the address on screen (for screenshots and screen sharing).
final ipHiddenProvider = StateProvider<bool>((ref) => false);

/// The IP the internet currently sees. Re-checked when the VPN turns on or off
/// and every three minutes; call `ref.invalidate` after changing the node.
/// While the desktop core runs the request goes through its local proxy,
/// otherwise the app's own client would show the real IP.
final ipInfoProvider = FutureProvider.autoDispose<IpInfo>((ref) async {
  final active = ref.watch(vpnActiveProvider);
  final timer = Timer(const Duration(minutes: 3), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  // Give the proxy / VPN a moment to come up or go away after a state change.
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  return ref
      .read(ipInfoServiceProvider)
      .fetch(proxyPort: !Platform.isAndroid && active ? 7890 : null);
});

/// Keeps the traffic counters of the saved subscription fresh. Without this
/// they changed only when the subscription was re-imported. Runs at start and
/// whenever the VPN turns on or off, then every minute while connected and
/// every five minutes otherwise. Only the counters are re-read; the saved
/// profile config is untouched.
final subscriptionUsageRefresherProvider = Provider<void>((ref) {
  final active = ref.watch(vpnActiveProvider);
  var busy = false;

  Future<void> refresh() async {
    if (busy) return;
    busy = true;
    try {
      final updated = await SubscriptionRepository().refreshUsage();
      if (updated != null) ref.invalidate(importedSubscriptionProvider);
    } catch (_) {
      // Offline or the panel is down: keep showing the last known numbers.
    } finally {
      busy = false;
    }
  }

  final timer = Timer.periodic(
      active ? const Duration(minutes: 1) : const Duration(minutes: 5),
      (_) => unawaited(refresh()));
  ref.onDispose(timer.cancel);
  unawaited(refresh());
});

/// Index of the selected root tab (0 = home, 1 = servers, 2 = traffic,
/// 3 = account, 4 = settings), so any screen can jump to another tab.
final rootTabIndexProvider = StateProvider<int>((ref) => 0);
