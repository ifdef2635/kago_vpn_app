import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'subscription_repository.dart';

final importedSubscriptionProvider = FutureProvider<ImportedSubscription?>(
    (ref) => SubscriptionRepository().latest());
