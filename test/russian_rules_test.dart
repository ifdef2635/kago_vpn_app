import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/subscriptions/russian_rules.dart';

void main() {
  Map<String, dynamic> config(List<String> rules,
          [List<Map<String, dynamic>> groups = const []]) =>
      <String, dynamic>{'rules': rules, 'proxy-groups': groups};

  test('GEOSITE/GEOIP/DOMAIN-SUFFIX to DIRECT count as Russian routing', () {
    expect(RussianRules.present(config(['GEOSITE,category-ru,DIRECT'])), true);
    expect(RussianRules.present(config(['GEOSITE,ru,DIRECT'])), true);
    expect(RussianRules.present(config(['GEOIP,RU,DIRECT,no-resolve'])), true);
    expect(RussianRules.present(config(['DOMAIN-SUFFIX,ru,DIRECT'])), true);
    expect(RussianRules.present(config(['DOMAIN-SUFFIX,.рф,DIRECT'])), true);
    expect(RussianRules.present(config(['RULE-SET,ru-domains,DIRECT'])), true);
  });

  test('a group with DIRECT first is a direct target', () {
    final groups = <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Россия',
        'type': 'select',
        'proxies': <String>['DIRECT', 'Proxy'],
      },
      <String, dynamic>{
        'name': 'Proxy',
        'type': 'select',
        'proxies': <String>['DE', 'DIRECT'],
      },
    ];
    expect(RussianRules.present(config(['GEOIP,RU,Россия'], groups)), true);
    expect(RussianRules.present(config(['GEOIP,RU,Proxy'], groups)), false);
  });

  test('other rules do not count', () {
    expect(RussianRules.present(<String, dynamic>{}), false);
    expect(RussianRules.present(config(['MATCH,Proxy'])), false);
    expect(RussianRules.present(config(['GEOSITE,category-ru,Proxy'])), false);
    expect(RussianRules.present(config(['GEOSITE,rutracker,DIRECT'])), false);
    expect(RussianRules.present(config(['GEOSITE,private,DIRECT'])), false);
    expect(
        RussianRules.present(config(['DOMAIN-SUFFIX,run.app,DIRECT'])), false);
    expect(
        RussianRules.present(
            config(['PROCESS-NAME,ru.yandex.music,DIRECT', 'GEOIP,CN,DIRECT'])),
        false);
  });
}
