import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/offline_proxy_groups.dart';
import 'package:kago_vpn/features/subscriptions/config_builder.dart';
import 'package:kago_vpn/features/subscriptions/subscription_repository.dart';

/// Answers from a table: url -> (status, headers, body); records requests.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.routes);
  final Map<String, (int, Map<String, List<String>>, List<int>)> routes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final (status, headers, body) = routes[options.uri.toString()]!;
    return ResponseBody.fromBytes(body, status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const device = <String, String>{
    'User-Agent': 'mihomo/1 KaGoVPN/1',
    'x-hwid': 'SECRET-HWID',
  };

  Dio dio(_Adapter adapter) => Dio()..httpClientAdapter = adapter;

  test('device headers stay on the subscription host after a redirect',
      () async {
    final adapter = _Adapter({
      'https://panel.example/sub': (
        302,
        {
          'location': ['https://cdn.other.example/file']
        },
        <int>[]
      ),
      'https://cdn.other.example/file': (200, {}, utf8.encode('proxies: []')),
    });
    final result = await SubscriptionRepository.fetch(
        dio(adapter), Uri.parse('https://panel.example/sub'),
        method: 'GET', deviceHeaders: device);
    expect(result.body, 'proxies: []');
    expect(adapter.requests.first.headers['x-hwid'], 'SECRET-HWID');
    expect(adapter.requests.last.headers.containsKey('x-hwid'), isFalse);
    expect(adapter.requests.last.headers['User-Agent'], 'mihomo/1 KaGoVPN/1');
  });

  test('a redirect to plain HTTP is refused', () async {
    final adapter = _Adapter({
      'https://panel.example/sub': (
        301,
        {
          'location': ['http://panel.example/sub']
        },
        <int>[]
      ),
    });
    await expectLater(
        SubscriptionRepository.fetch(
            dio(adapter), Uri.parse('https://panel.example/sub'),
            method: 'GET', deviceHeaders: device),
        throwsFormatException);
  });

  test('a huge body is refused', () async {
    final adapter = _Adapter({
      'https://panel.example/sub': (
        200,
        {},
        List<int>.filled(SubscriptionRepository.maxBodyBytes + 1, 0x61)
      ),
    });
    await expectLater(
        SubscriptionRepository.fetch(
            dio(adapter), Uri.parse('https://panel.example/sub'),
            method: 'GET', deviceHeaders: device),
        throwsFormatException);
  });

  test('a YAML alias bomb is refused instead of exhausting memory', () {
    final yaml =
        StringBuffer('proxies: []\na0: &a0 [x, x, x, x, x, x, x, x]\n');
    for (var i = 1; i < 12; i++) {
      yaml.writeln(
          'a$i: &a$i [*a${i - 1}, *a${i - 1}, *a${i - 1}, *a${i - 1}, *a${i - 1}, *a${i - 1}, *a${i - 1}, *a${i - 1}]');
    }
    expect(() => const MihomoConfigBuilder().build(yaml.toString()),
        throwsFormatException);
  });

  test('catastrophic group filters are skipped', () {
    expect(safeGroupFilter('^(a+)+\$'), isNull);
    expect(safeGroupFilter('(x*)*y'), isNull);
    expect(safeGroupFilter('a' * 300), isNull);
    expect(safeGroupFilter('germany|de')?.hasMatch('de-1'), isTrue);
  });
}
