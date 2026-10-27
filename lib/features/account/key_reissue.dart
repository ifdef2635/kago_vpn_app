import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_providers.dart';
import '../dashboard/dashboard_screen.dart';
import '../subscriptions/subscription_providers.dart';
import '../subscriptions/subscription_repository.dart';
import 'account_providers.dart';
import 'kago_api.dart';

/// The key re-issued elsewhere — on the site, in the Telegram bot or on
/// another device — leaves this device with a dead link: the panel answers
/// 404 to it (and «Обновить» failed with that), and the running VPN has the
/// revoked credentials. The account always knows the current link, so the
/// device takes it over by itself.
abstract final class KeyReissue {
  /// The account's link that replaces the [saved] one, or null. Only when
  /// the links differ, the saved one is gone ([gone]) and the account's one
  /// is not:
  ///  - a saved link that still works is another subscription the user kept
  ///    on purpose (signed in to another account), which «Добавить на это
  ///    устройство» offers to switch;
  ///  - both answering 404 is a server that does not let this app in (its
  ///    User-Agent not allowed yet), not a re-issued key.
  static Future<String?> replacement(
      {required String? saved,
      required String? account,
      required Future<bool> Function(String url) gone}) async {
    if (saved == null || saved.isEmpty || account == null || account.isEmpty) {
      return null;
    }
    if (_same(saved, account) || !await gone(saved) || await gone(account)) {
      return null;
    }
    return account;
  }

  static bool _same(String left, String right) {
    try {
      return SubscriptionRepository.validateSubscriptionUrl(left).toString() ==
          SubscriptionRepository.validateSubscriptionUrl(right).toString();
    } on FormatException {
      return left == right;
    }
  }

  static Future<bool>? _running;

  /// Different saved and account links checked last, and when: the account
  /// tab reads the subscription every 5 seconds, and the panel is asked
  /// about the same pair at most every 10 minutes.
  static String? _checkedPair;
  static DateTime? _checkedAt;

  /// Puts the account's new link on this device when the saved one was
  /// re-issued, and restarts a running VPN with it. [account] is the
  /// account's subscription when the caller has just read it; [force]
  /// (the «Обновить» button) skips the 10-minute pause. True when the link
  /// was replaced. Never throws.
  static Future<bool> sync(BuildContext context, WidgetRef ref,
          {KagoSubscription? account, bool force = false}) =>
      _running ??= _sync(context, ref, account, force)
          .catchError((Object _) => false)
          .whenComplete(() => _running = null);

  static Future<bool> _sync(BuildContext context, WidgetRef ref,
      KagoSubscription? account, bool force) async {
    final repository = SubscriptionRepository();
    final saved = (await repository.latest())?.url;
    if (saved == null || saved.isEmpty) return false;
    final api = ref.read(kagoApiProvider);
    if (account == null) {
      if (!await api.cookies.hasSession) return false;
      account = await api.subscription();
    }
    final current = account?.url;
    if (current == null || current.isEmpty || _same(saved, current)) {
      return false;
    }
    final pair = '$saved\n$current';
    final checkedAt = _checkedAt;
    if (!force &&
        pair == _checkedPair &&
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < const Duration(minutes: 10)) {
      return false;
    }
    _checkedPair = pair;
    _checkedAt = DateTime.now();
    final next = await replacement(
        saved: saved, account: current, gone: repository.linkGone);
    if (next == null) return false;
    await repository.import(next);
    await repository.forget(saved);
    ref.invalidate(importedSubscriptionProvider);
    ref.invalidate(proxyGroupsProvider);
    refreshAccount(ref);
    // The running core still has the revoked credentials.
    if (ref.read(vpnActiveProvider) && context.mounted) {
      await DashboardScreen.reconnect(context, ref);
    }
    return true;
  }
}

/// Checks for a re-issued key a few seconds after start, every 15 minutes
/// and on each return to the app, and whenever the account tab reads the
/// subscription.
class KeyReissueWatch extends ConsumerStatefulWidget {
  const KeyReissueWatch({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<KeyReissueWatch> createState() => _KeyReissueWatchState();
}

class _KeyReissueWatchState extends ConsumerState<KeyReissueWatch> {
  Timer? _first;
  Timer? _periodic;

  @override
  void initState() {
    super.initState();
    _first = Timer(const Duration(seconds: 5), _check);
    _periodic = Timer.periodic(const Duration(minutes: 15), (_) => _check());
  }

  @override
  void dispose() {
    _first?.cancel();
    _periodic?.cancel();
    super.dispose();
  }

  void _check({KagoSubscription? account}) {
    if (!mounted || !ref.read(appForegroundProvider)) return;
    unawaited(KeyReissue.sync(context, ref, account: account));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(appForegroundProvider, (previous, next) {
      if (next && previous == false) _check();
    });
    ref.listen<AsyncValue<KagoSubscription?>>(accountSubscriptionProvider,
        (_, next) {
      final account = next.valueOrNull;
      if (account != null) _check(account: account);
    });
    return widget.child;
  }
}
