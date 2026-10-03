import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/ip_info_service.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._answers);
  final Map<String, Object> _answers; // host -> JSON body or Exception
  final List<String> hosts = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    hosts.add(options.uri.host);
    final answer = _answers[options.uri.host];
    if (answer == null || answer is Exception) {
      throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException('refused'));
    }
    return ResponseBody.fromString(jsonEncode(answer), 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('parses ipwho.is with location and provider', () {
    final info = IpInfo.fromIpWhoIs(<String, dynamic>{
      'success': true,
      'ip': '203.0.113.7',
      'country': 'Germany',
      'country_code': 'DE',
      'city': 'Frankfurt am Main',
      'connection': <String, dynamic>{'isp': 'Example Hosting GmbH'},
    });

    expect(info.ip, '203.0.113.7');
    expect(info.place, 'Frankfurt am Main, Germany');
    expect(info.isp, 'Example Hosting GmbH');
    expect(info.flag, '\u{1F1E9}\u{1F1EA}');
  });

  test('ipwho.is failure and non-IP answers are rejected', () {
    expect(
        () => IpInfo.fromIpWhoIs(
            <String, dynamic>{'success': false, 'message': 'Rate limit'}),
        throwsFormatException);
    expect(() => IpInfo.fromIpSb(<String, dynamic>{'ip': '<html>'}),
        throwsFormatException);
  });

  test('ipify gives the address only; flag and place stay empty', () {
    final info = IpInfo.fromIpify(<String, dynamic>{'ip': '2001:db8::1'});

    expect(info.ip, '2001:db8::1');
    expect(info.place, isEmpty);
    expect(info.flag, isEmpty);
  });

  test('falls back to the next service when the first one fails', () async {
    final adapter = _ScriptedAdapter(<String, Object>{
      'api.ip.sb': <String, dynamic>{
        'ip': '198.51.100.9',
        'country': 'Netherlands',
        'country_code': 'NL',
        'isp': 'Example BV',
      },
    });
    final service = IpInfoService(dio: Dio()..httpClientAdapter = adapter);

    final info = await service.fetch();

    expect(info.ip, '198.51.100.9');
    expect(info.country, 'Netherlands');
    expect(adapter.hosts, <String>['ipwho.is', 'api.ip.sb']);
  });

  test('throws when every service fails', () async {
    final adapter = _ScriptedAdapter(<String, Object>{});
    final service = IpInfoService(dio: Dio()..httpClientAdapter = adapter);

    await expectLater(service.fetch(), throwsA(isA<DioException>()));
    expect(adapter.hosts, hasLength(3));
  });
}
