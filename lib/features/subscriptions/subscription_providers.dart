import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_widgets.dart';
import 'subscription_repository.dart';

final importedSubscriptionProvider =
    FutureProvider<ImportedSubscription?>((ref) async {
  final profile = await SubscriptionRepository().latest();
  // «Поддержка» follows the subscription's own support-url.
  SupportLink.current = profile?.supportUrl ?? SupportLink.fallback;
  return profile;
});
