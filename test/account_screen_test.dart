import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/l10n/l10n.dart';
import 'package:kago_vpn/features/account/account_screen.dart';

void main() {
  final now = DateTime(2026, 10, 5, 12);

  test('open-ended plans show infinity, like the site', () {
    expect(remainingLabel(DateTime(2099, 11, 15), now), '∞');
    expect(remainingLabel(null, now), '∞');
  });

  test('days left are rounded up and never negative', () {
    expect(remainingLabel(DateTime(2026, 10, 15, 13), now), '11 дн.');
    expect(remainingLabel(DateTime(2026, 10, 1), now), '0 дн.');
  });

  test('expiry date is written in Russian', () {
    expect(formatLongDate(DateTime(2099, 11, 15, 12)), '15 ноября 2099 г.');
  });
}
