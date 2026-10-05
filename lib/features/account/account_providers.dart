import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kago_api.dart';

final kagoApiProvider = Provider<KagoApi>((ref) => KagoApi());

/// The signed-in usekago.net user, or null for a guest. A dead session (the
/// refresh token expired) is treated as logged out, like the site does.
final accountUserProvider = FutureProvider<KagoUser?>((ref) async {
  final api = ref.watch(kagoApiProvider);
  if (!await api.cookies.hasSession) return null;
  try {
    return await api.me();
  } on KagoUnauthorized {
    return null;
  }
});

final accountSubscriptionProvider =
    FutureProvider<KagoSubscription?>((ref) async {
  final user = await ref.watch(accountUserProvider.future);
  if (user == null) return null;
  return ref.watch(kagoApiProvider).subscription();
});

final accountDevicesProvider = FutureProvider<KagoDevices?>((ref) async {
  final user = await ref.watch(accountUserProvider.future);
  if (user == null) return null;
  return ref.watch(kagoApiProvider).devices();
});

final accountReferralProvider = FutureProvider<KagoReferral?>((ref) async {
  final user = await ref.watch(accountUserProvider.future);
  if (user == null) return null;
  return ref.watch(kagoApiProvider).referral();
});

/// Re-reads everything after a change (login, reissue, promo code…).
void refreshAccount(WidgetRef ref) {
  ref.invalidate(accountUserProvider);
  ref.invalidate(accountSubscriptionProvider);
  ref.invalidate(accountDevicesProvider);
  ref.invalidate(accountReferralProvider);
}
