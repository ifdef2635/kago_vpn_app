import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/subscriptions/subscription_parser.dart';

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
}
