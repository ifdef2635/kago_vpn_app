import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../../features/guest/guest_telegram.dart';
import '../../features/subscriptions/subscription_repository.dart';
import 'anonymous_mode.dart';
import 'app_providers.dart';
import 'core_authorization_required.dart';
import 'mihomo_controller.dart';
import 'mihomo_macos.dart';
import 'mihomo_process_manager.dart';
import 'mihomo_windows_tun.dart';

enum RecoveryStatus { idle, recovering, needsAction }

final desktopRecoveryStatusProvider =
    StateProvider<RecoveryStatus>((ref) => RecoveryStatus.idle);
final desktopRecoveryErrorProvider = StateProvider<String?>((ref) => null);

final desktopRecoveryProvider = Provider<DesktopRecovery>((ref) {
  final recovery = DesktopRecovery(ref,
      manager: ref.read(mihomoProcessProvider),
      controller: ref.read(mihomoControllerProvider));
  ref.onDispose(recovery.dispose);
  return recovery;
});

/// Remembers a manual connection only for the lifetime of this app process.
/// The core manager reports unexpected exits; a changed physical network
/// triggers a remote check before any disruption of a running connection.
class DesktopRecovery {
  DesktopRecovery(this.ref,
      {required this.manager,
      required this.controller,
      this.watchNetwork = true,
      this.retryDelays = delays,
      this.networkDebounce = const Duration(seconds: 2),
      this.probeInterval = const Duration(seconds: 2),
      this.interfaceSnapshot,
      this.remoteHealth,
      this.retryPreflight}) {
    _exits = manager.exits.listen((_) => _schedule());
  }

  final Ref ref;
  final MihomoProcessManager manager;
  final MihomoController controller;
  final bool watchNetwork;
  final List<Duration> retryDelays;
  final Duration networkDebounce;
  final Duration probeInterval;
  final Future<String?> Function()? interfaceSnapshot;
  final Future<bool> Function()? remoteHealth;
  final Future<String?> Function(String path, bool guest)? retryPreflight;
  static const delays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(minutes: 5),
  ];

  static Duration delayForAttempt(int attempt,
          [List<Duration> schedule = delays]) =>
      schedule[attempt.clamp(0, schedule.length - 1)];

  StreamSubscription<int>? _exits;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Timer? _interfacesTimer;
  Timer? _networkDebounce;
  Timer? _retryTimer;
  String? _configPath;
  String? _interfaces;
  bool _guest = false;
  bool _anonymous = false;
  bool _desired = false;
  bool _ready = false;
  bool _probing = false;
  bool _retrying = false;
  bool _pendingRetry = false;
  bool _pendingImmediate = false;
  Future<void>? _inflight;
  int _attempt = 0;
  int _generation = 0;

  bool get desired => _desired;

  void arm(String configPath, {required bool guest, required bool anonymous}) {
    _generation++;
    _desired = true;
    _ready = false;
    _configPath = configPath;
    _guest = guest;
    _anonymous = anonymous;
    _attempt = 0;
    _pendingRetry = false;
    _pendingImmediate = false;
    _retryTimer?.cancel();
    ref.read(desktopRecoveryStatusProvider.notifier).state =
        RecoveryStatus.idle;
    ref.read(desktopRecoveryErrorProvider.notifier).state = null;
    _watchNetwork();
  }

  void connected() {
    if (!_desired) return;
    _ready = true;
    _attempt = 0;
    _pendingRetry = false;
    _pendingImmediate = false;
    _retryTimer?.cancel();
    ref.read(desktopRecoveryStatusProvider.notifier).state =
        RecoveryStatus.idle;
    ref.read(desktopRecoveryErrorProvider.notifier).state = null;
  }

  void startFailed(Object error) {
    if (!_desired) return;
    _ready = true;
    if (error is FormatException ||
        error is FileSystemException ||
        error is CoreAuthorizationRequired) {
      _needAction('$error');
      return;
    }
    _schedule();
  }

  void cancel() {
    _generation++;
    _desired = false;
    _ready = false;
    _pendingRetry = false;
    _pendingImmediate = false;
    _configPath = null;
    _retryTimer?.cancel();
    _networkDebounce?.cancel();
    _connectivity?.cancel();
    _connectivity = null;
    _interfacesTimer?.cancel();
    _interfacesTimer = null;
    ref.read(desktopRecoveryStatusProvider.notifier).state =
        RecoveryStatus.idle;
    ref.read(desktopRecoveryErrorProvider.notifier).state = null;
  }

  void dispose() {
    cancel();
    _exits?.cancel();
  }

  /// Cancel first, then wait for an in-flight start to finish before stopping.
  Future<void> disconnect() async {
    cancel();
    await _inflight;
    await manager.stop();
  }

  void _watchNetwork() {
    if (!watchNetwork) return;
    if (_connectivity != null || (!Platform.isWindows && !Platform.isMacOS)) {
      return;
    }
    try {
      _connectivity = Connectivity()
          .onConnectivityChanged
          .listen((_) => onNetworkChanged());
    } catch (_) {
      // Interface snapshots still catch most Wi-Fi and Ethernet changes.
    }
    unawaited(_readInterfaces().then((value) => _interfaces = value));
    _interfacesTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final current = await _readInterfaces();
      if (current == null) return;
      final previous = _interfaces;
      _interfaces = current;
      if (previous != null && previous != current) onNetworkChanged();
    });
  }

  Future<String?> _readInterfaces() async {
    try {
      final interfaces = await NetworkInterface.list(
          includeLoopback: false, includeLinkLocal: false);
      final addresses = <String>[
        for (final item in interfaces)
          if (!RegExp(r'kago|utun|wintun|loopback', caseSensitive: false)
              .hasMatch(item.name))
            for (final address in item.addresses)
              '${item.name}:${address.address}',
      ]..sort();
      return addresses.join('|');
    } catch (_) {
      return null;
    }
  }

  /// Called by connectivity_plus and physical-interface address changes.
  void onNetworkChanged() {
    if (!_desired || !_ready) return;
    _networkDebounce?.cancel();
    _networkDebounce = Timer(networkDebounce, () {
      if (!_desired) return;
      if (manager.isRunning) {
        unawaited(_checkAfterNetworkChange());
      } else {
        _schedule(immediate: true);
      }
    });
  }

  Future<void> _checkAfterNetworkChange() async {
    if (_probing || !_desired || !manager.isRunning) return;
    _probing = true;
    final generation = _generation;
    try {
      if (await (interfaceSnapshot?.call() ?? _readInterfaces()) == '') return;
      if (await (remoteHealth?.call() ?? _healthy())) return;
      await Future<void>.delayed(probeInterval);
      if (generation != _generation ||
          !manager.isRunning ||
          await (remoteHealth?.call() ?? _healthy())) {
        return;
      }
      await manager.stop();
      if (generation != _generation) return;
      ref.read(desktopCoreRunningProvider.notifier).state = false;
      ref.invalidate(proxyGroupsProvider);
      _schedule(immediate: true);
    } catch (_) {
      if (generation == _generation) _schedule();
    } finally {
      _probing = false;
    }
  }

  Future<bool> _healthy() async {
    try {
      await controller.version();
      final groups = await controller.proxies();
      final candidates = groups.where((group) => group.name != 'GLOBAL');
      if (groups.isEmpty) return false;
      final group = _guest
          ? candidates.firstWhere(
              (item) => item.name == GuestTelegram.groupName,
              orElse: () => groups.first)
          : candidates.firstWhere((item) => item.selected != null,
              orElse: () => groups.first);
      final target = _guest
          ? GuestTelegram.checkUrl
          : group.testUrl ?? 'https://www.gstatic.com/generate_204';
      if (await controller.testDelay(group.name, url: target) != null) {
        return true;
      }
      return !_guest &&
          await controller.testDelay(group.name, url: 'https://usekago.net/') !=
              null;
    } catch (_) {
      return false;
    }
  }

  void _schedule({bool immediate = false}) {
    if (!_desired || _configPath == null) return;
    if (_retrying) {
      _pendingRetry = true;
      _pendingImmediate |= immediate;
      return;
    }
    _retryTimer?.cancel();
    ref.read(desktopRecoveryStatusProvider.notifier).state =
        RecoveryStatus.recovering;
    final delay =
        immediate ? Duration.zero : delayForAttempt(_attempt, retryDelays);
    if (!immediate) _attempt++;
    _retryTimer = Timer(delay, () {
      _inflight = _retry();
    });
  }

  Future<void> _retry() async {
    if (!_desired || _retrying || manager.isRunning) return;
    final generation = _generation;
    final path = _configPath;
    if (path == null) return;
    _retrying = true;
    try {
      final blockingError = await (retryPreflight?.call(path, _guest) ??
          _defaultPreflight(path, _guest));
      if (blockingError != null) {
        _needAction(blockingError);
        return;
      }
      if (generation != _generation) return;
      ref.read(desktopVpnBusyProvider.notifier).state = true;
      await manager.start(configPath: path, allowElevation: false);
      if (!manager.isRunning) throw StateError('Mihomo stopped during restart');
      if (generation != _generation) {
        await manager.stop();
        return;
      }
      ref.read(guestModeActiveProvider.notifier).state = _guest;
      ref.read(anonymousActiveProvider.notifier).state = _anonymous;
      ref.read(desktopCoreRunningProvider.notifier).state = true;
      ref.invalidate(coreVersionProvider);
      ref.invalidate(proxyGroupsProvider);
      ref.invalidate(ipInfoProvider);
      if (_anonymous && Platform.isWindows) {
        try {
          final info =
              await ref.read(ipInfoServiceProvider).fetch(proxyPort: 7890);
          if (info.timeZone != null) {
            await WindowsTimeZone.apply(info.timeZone!);
          }
        } catch (_) {}
      }
      connected();
    } on CoreAuthorizationRequired catch (error) {
      _needAction(error.message);
    } catch (_) {
      if (generation == _generation) {
        _schedule();
      }
    } finally {
      ref.read(desktopVpnBusyProvider.notifier).state = false;
      _retrying = false;
      if (_pendingRetry && _desired) {
        final immediate = _pendingImmediate;
        _pendingRetry = false;
        _pendingImmediate = false;
        _schedule(immediate: immediate);
      }
    }
  }

  Future<String?> _defaultPreflight(String path, bool guest) async {
    if (!await File(path).exists()) {
      return tr('Профиль VPN удалён. Подключитесь вручную.');
    }
    if (!guest) {
      final profile = await SubscriptionRepository().latest();
      final expired = profile?.expiresAt?.isAfter(DateTime.now()) == false;
      final exhausted = profile != null &&
          profile.totalBytes > 0 &&
          profile.usedBytes >= profile.totalBytes;
      if (profile == null || expired || exhausted) {
        return tr('Подписка недействительна. Проверьте кабинет.');
      }
    }
    if (Platform.isWindows &&
        await MihomoWindowsTun.enabled() &&
        !await MihomoWindowsTun.isInstalled()) {
      return tr('Для TUN требуется ручное подключение.');
    }
    if (Platform.isMacOS &&
        await MihomoMacosCore.tunEnabled() &&
        await MihomoMacosCore.authorizedHelper() == null) {
      return tr('Для TUN требуется ручное подключение.');
    }
    return null;
  }

  void _needAction(String message) {
    _retryTimer?.cancel();
    _desired = false;
    ref.read(desktopRecoveryStatusProvider.notifier).state =
        RecoveryStatus.needsAction;
    ref.read(desktopRecoveryErrorProvider.notifier).state = message;
  }
}
