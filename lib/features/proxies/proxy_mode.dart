import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/app_providers.dart';
import '../guest/guest_telegram.dart';

/// How the core routes traffic, as the mode menu of FlClashX: by the
/// subscription's rules, or everything through the server chosen in GLOBAL.
enum ProxyMode { rule, global }

/// The chosen mode, saved between launches. The core always starts in the
/// config's `rule` mode; [proxyModeSyncProvider] applies the choice.
class ProxyModeNotifier extends StateNotifier<ProxyMode> {
  ProxyModeNotifier() : super(ProxyMode.rule) {
    _load();
  }

  static const _key = 'kago.proxy.mode';

  Future<void> _load() async {
    try {
      final name = (await SharedPreferences.getInstance()).getString(_key);
      state = ProxyMode.values
          .firstWhere((mode) => mode.name == name, orElse: () => state);
    } catch (_) {
      // Storage unavailable: rules, as in the config.
    }
  }

  Future<void> set(ProxyMode mode) async {
    state = mode;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, mode.name);
    } catch (_) {}
  }
}

final proxyModeProvider = StateNotifierProvider<ProxyModeNotifier, ProxyMode>(
    (ref) => ProxyModeNotifier());

/// The mode the core runs in: the chosen one, except the free Telegram access,
/// which always follows its rules (in global mode all traffic would go to the
/// guest server, which lets only Telegram through).
final effectiveProxyModeProvider = Provider<ProxyMode>((ref) =>
    ref.watch(guestModeActiveProvider)
        ? ProxyMode.rule
        : ref.watch(proxyModeProvider));

/// Tells the running core the mode whenever the VPN comes up (the core starts
/// from the config, in `rule` mode) or the user picks another one.
final proxyModeSyncProvider = Provider<void>((ref) {
  if (!ref.watch(vpnActiveProvider)) return;
  final mode = ref.watch(effectiveProxyModeProvider);
  final controller = ref.watch(mihomoControllerProvider);
  var disposed = false;
  ref.onDispose(() => disposed = true);
  Future<void> apply() async {
    // The controller may still be starting right after the VPN comes up.
    for (var attempt = 0; attempt < 3 && !disposed; attempt++) {
      try {
        await controller.setMode(mode.name);
        if (!disposed) ref.invalidate(proxyGroupsProvider);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  unawaited(apply());
});
