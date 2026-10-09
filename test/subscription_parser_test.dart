import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/subscriptions/subscription_parser.dart';
import 'package:kago_vpn/features/subscriptions/subscription_repository.dart';

void main() {
  test('reads service name and proxy group names from subscription', () {
    final result = SubscriptionMetadata.parse(
      yaml:
          'proxy-groups:\n  - name: GLOBAL\n    type: select\n    proxies: [DIRECT]\n  - name: Auto\n    type: url-test\n',
      responseHeaders: <String, List<String>>{
        'flclashx-servicename': <String>['KaGo Premium'],
        'flclashx-newboard': <String>['true'],
        'content-type': <String>['text/yaml'],
      },
    );
    expect(result.serviceName, 'KaGo Premium');
    expect(result.proxyGroupNames, <String>['GLOBAL', 'Auto']);
    expect(result.headers, contains('flclashx-newboard'));
  });

  test('support-url and profile-update-interval come from the panel', () {
    final result = SubscriptionMetadata.parse(
      yaml: 'proxies: []\n',
      responseHeaders: <String, List<String>>{
        // As the KAGO panel sends them (2026-10-08).
        'Support-Url': <String>[
          'https://usekago.net/help?openchat&tgid=&email='
        ],
        'profile-update-interval': <String>['6'],
      },
    );
    expect(result.supportUrl, 'https://usekago.net/help?openchat&tgid=&email=');
    expect(result.updateInterval, const Duration(hours: 6));
  });

  test('odd header values are ignored or kept in range', () {
    expect(httpsUrl('http://usekago.net/help'), isNull);
    expect(httpsUrl('javascript:alert(1)'), isNull);
    expect(httpsUrl(null), isNull);
    expect(updateIntervalOf('0'), isNull);
    expect(updateIntervalOf('soon'), isNull);
    expect(updateIntervalOf('0.1'), const Duration(hours: 1));
    expect(updateIntervalOf('100000'), const Duration(days: 7));
    expect(updateIntervalOf('1.5'), const Duration(minutes: 90));
  });

  test('a subscription is re-downloaded after its interval', () {
    final now = DateTime(2026, 10, 9, 12);
    ImportedSubscription saved(DateTime? at, Duration? every) =>
        ImportedSubscription(
            name: 'KaGo',
            url: 'https://example.com/sub',
            usedBytes: 0,
            totalBytes: 0,
            expiresAt: null,
            groups: const <String>[],
            updatedAt: at,
            updateInterval: every);
    const six = Duration(hours: 6);
    expect(saved(now.subtract(const Duration(hours: 5)), six).updateDue(now),
        isFalse);
    expect(saved(now.subtract(six), six).updateDue(now), isTrue);
    // Without the header: once a day.
    expect(saved(now.subtract(const Duration(hours: 23)), null).updateDue(now),
        isFalse);
    expect(saved(now.subtract(const Duration(days: 1)), null).updateDue(now),
        isTrue);
    // Saved before 2.0.8 (no date): at once.
    expect(saved(null, six).updateDue(now), isTrue);
  });
}
