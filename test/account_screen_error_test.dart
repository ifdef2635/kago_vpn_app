import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/theme/kago_theme.dart';
import 'package:kago_vpn/features/account/account_providers.dart';
import 'package:kago_vpn/features/account/account_screen.dart';
import 'package:kago_vpn/features/account/kago_api.dart';
import 'package:kago_vpn/features/subscriptions/subscription_providers.dart';

/// A failed request to usekago.net must show an error panel, not break the
/// whole tab (AsyncValue.value rethrows the error; the screen reads
/// valueOrNull).
void main() {
  testWidgets('account tab survives a site API error', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountUserProvider.overrideWith(
            (ref) async => throw const KagoApiException('HTTP 403')),
        importedSubscriptionProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
          theme: KaGoTheme.dark(), home: const Scaffold(body: AccountScreen())),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('HTTP 403'), findsOneWidget);
  });
}
