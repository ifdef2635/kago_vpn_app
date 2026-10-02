import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../models/mihomo_models.dart';
import 'mihomo_controller.dart';
import 'mihomo_process_manager.dart';
import 'mihomo_release_api.dart';
import 'mihomo_windows_core_updater.dart';

final mihomoControllerProvider =
    Provider<MihomoController>((ref) => MihomoController());
final proxyGroupsProvider = FutureProvider<List<ProxyGroup>>(
    (ref) => ref.watch(mihomoControllerProvider).proxies());

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
final proxyDelaysProvider = StateProvider<Map<String, int>>(
    (ref) => const <String, int>{});

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
    return await const MethodChannel('net.usekago.vpn/service')
        .invokeMethod<String>('coreVersion');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
});
final androidCoreUpdateStatusProvider = FutureProvider<String>((ref) async {
  if (!Platform.isAndroid) {
    return 'Проверка Android core доступна только на Android.';
  }
  final latest = await ref.watch(latestMihomoReleaseProvider.future);
  final installed = await ref.watch(androidNativeCoreVersionProvider.future);
  if (installed == null || installed.trim().isEmpty) {
    return 'В этой сборке не найден native Mihomo. Android .so должен входить в подписанный APK/AAB.';
  }
  final match = RegExp(r'v?\d+\.\d+\.\d+').firstMatch(installed);
  if (match == null) {
    return 'Версия встроенного Mihomo не распознана: $installed';
  }
  if (MihomoReleaseApi.compareStableVersions(latest.version, match.group(0)!) >
      0) {
    return 'Доступен Mihomo ${latest.version}. На Android ядро обновляется вместе с новой KaGo VPN сборкой.';
  }
  return 'Встроенный Mihomo $installed актуален.';
});
final pureBlackProvider = StateProvider<bool>((ref) => false);
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
  ref.onDispose(() => unawaited(manager.dispose()));
  return manager;
});
final desktopCoreRunningProvider = StateProvider<bool>((ref) => false);

/// Index of the selected root tab (0 = home, 1 = servers, 2 = traffic,
/// 3 = settings), so any screen can jump to another tab.
final rootTabIndexProvider = StateProvider<int>((ref) => 0);
