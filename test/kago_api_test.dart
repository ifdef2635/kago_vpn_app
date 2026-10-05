import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/account/kago_api.dart';

/// Answers like the usekago.net API: login sets the session cookies, an
/// expired access cookie gets 401 until /auth/refresh issues a new one.
class _FakeServer implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  String access = 'a1';
  bool refreshWorks = true;

  ResponseBody _json(Object body, int status,
          {List<String> cookies = const <String>[]}) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
        if (cookies.isNotEmpty) 'set-cookie': cookies,
      });

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final cookie = options.headers['Cookie'] as String? ?? '';
    switch (options.path) {
      case '/auth/login':
        return _json(<String, String>{'expires_at': ''}, 200, cookies: <String>[
          'access_token=$access; Path=/; HttpOnly; Secure; SameSite=Lax',
          'refresh_token=r1; Path=/api/v1/public/auth/refresh; HttpOnly',
        ]);
      case '/auth/refresh':
        if (!refreshWorks || !cookie.contains('refresh_token=r1')) {
          return _json(<String, String>{'detail': 'expired'}, 401);
        }
        access = 'a2';
        return _json(<String, String>{}, 200,
            cookies: <String>['access_token=a2; Path=/; HttpOnly']);
      case '/auth/me':
        if (!cookie.contains('access_token=$access')) {
          return _json(<String, String>{'detail': 'Not authenticated'}, 401);
        }
        return _json(<String, Object?>{
          'name': 'So Os',
          'email': 'user@example.com',
          'is_email_verified': false,
          'telegram_id': 42,
        }, 200);
      case '/subscription/promocode':
        return _json(<String, Object>{
          'detail': <Map<String, String>>[
            <String, String>{'msg': 'Промокод не найден'},
          ],
        }, 422);
      default:
        return _json(<String, String>{'detail': 'Not Found'}, 404);
    }
  }

  @override
  void close({bool force = false}) {}
}

KagoApi _api(_FakeServer server) {
  final dio = Dio(BaseOptions(
      baseUrl: kagoApiBase,
      responseType: ResponseType.plain,
      validateStatus: (_) => true))
    ..httpClientAdapter = server;
  return KagoApi(dio: dio);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('login keeps the session cookies and sends them back', () async {
    final server = _FakeServer();
    final api = _api(server);
    await api.login('user@example.com', 'secret');
    expect(await api.cookies.hasSession, isTrue);
    final user = await api.me();
    expect(user.name, 'So Os');
    expect(user.telegramId, 42);
    expect(server.requests.last.headers['Cookie'], contains('access_token=a1'));
  });

  test('an expired access cookie is refreshed once and the call retried',
      () async {
    final server = _FakeServer();
    final api = _api(server);
    await api.login('user@example.com', 'secret');
    server.access = 'stale'; // the server no longer accepts a1
    // /auth/refresh rotates the access cookie to a2.
    server.refreshWorks = true;
    final user = await api.me();
    expect(user.email, 'user@example.com');
    expect(server.requests.map((r) => r.path),
        containsAllInOrder(<String>['/auth/me', '/auth/refresh', '/auth/me']));
  });

  test('a dead session clears the cookies and reports logout', () async {
    final server = _FakeServer();
    final api = _api(server);
    await api.login('user@example.com', 'secret');
    server
      ..access = 'stale'
      ..refreshWorks = false;
    await expectLater(api.me(), throwsA(isA<KagoUnauthorized>()));
    expect(await api.cookies.hasSession, isFalse);
  });

  test('FastAPI validation errors become a readable message', () async {
    final api = _api(_FakeServer());
    await expectLater(
        api.activatePromocode('NOPE'),
        throwsA(isA<KagoApiException>()
            .having((e) => e.message, 'message', 'Промокод не найден')
            .having((e) => e.status, 'status', 422)));
  });

  test('subscription fields follow the site (GB limit, 2099 = lifetime)', () {
    final sub = KagoSubscription.fromJson(<String, Object?>{
      'status': 'ACTIVE',
      'is_trial': false,
      'traffic_limit': 0,
      'device_limit': 5,
      'expire_at': '2099-11-15T00:00:00Z',
      'url': 'https://sub.example/abc',
      'plan_name': 'VIP для друзей',
    });
    expect(sub.isActive, isTrue);
    expect(sub.isLifetime, isTrue);
    expect(sub.trafficLimitGb, 0);
  });
}
