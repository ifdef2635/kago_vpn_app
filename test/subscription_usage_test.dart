import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/subscriptions/subscription_repository.dart';

/// Answers each HTTP method with the given `subscription-userinfo` value
/// (null: no header at all).
class _UserInfoAdapter implements HttpClientAdapter {
  _UserInfoAdapter(this._headerByMethod);
  final Map<String, String?> _headerByMethod;
  final List<String> methods = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    methods.add(options.method);
    final value = _headerByMethod[options.method];
    return ResponseBody.fromString('', 200, headers: <String, List<String>>{
      if (value != null) 'Subscription-Userinfo': <String>[value],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'kago.profiles.v1';
  const url = 'https://example.com/sub/token';

  SubscriptionRepository repositoryWithProfile() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      key: jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'KaGo',
          'url': url,
          'used': 1,
          'total': 10,
          'expire': null,
          'groups': <String>['KaGo VPN'],
        },
      ]),
    });
    return SubscriptionRepository(storage: const FlutterSecureStorage());
  }

  test('parseUserInfo reads counters and skips malformed tokens', () {
    expect(
      SubscriptionRepository.parseUserInfo(
          'upload=100; download=200; total=1000; expire=1893456000; junk; x=y'),
      <String, int>{
        'upload': 100,
        'download': 200,
        'total': 1000,
        'expire': 1893456000,
      },
    );
    expect(SubscriptionRepository.parseUserInfo(null), isEmpty);
  });

  test('refreshUsage updates the counters from a cheap HEAD request', () async {
    final repository = repositoryWithProfile();
    final adapter = _UserInfoAdapter(<String, String?>{
      'HEAD': 'upload=100; download=200; total=1000; expire=1893456000',
    });

    final updated =
        await repository.refreshUsage(dio: Dio()..httpClientAdapter = adapter);

    expect(adapter.methods, <String>['HEAD']);
    expect(updated, isNotNull);
    expect(updated!.usedBytes, 300);
    expect(updated.totalBytes, 1000);
    expect(updated.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1893456000 * 1000));
    // Name and groups of the saved profile are left alone.
    expect(updated.name, 'KaGo');
    expect(updated.groups, <String>['KaGo VPN']);
    expect((await repository.latest())!.usedBytes, 300);
  });

  test('refreshUsage falls back to GET when HEAD carries no header', () async {
    final repository = repositoryWithProfile();
    final adapter = _UserInfoAdapter(<String, String?>{
      'HEAD': null,
      'GET': 'upload=5; download=6; total=100',
    });

    final updated =
        await repository.refreshUsage(dio: Dio()..httpClientAdapter = adapter);

    expect(adapter.methods, <String>['HEAD', 'GET']);
    expect(updated!.usedBytes, 11);
    expect(updated.totalBytes, 100);
  });

  test('refreshUsage keeps the old numbers when the server sends none',
      () async {
    final repository = repositoryWithProfile();
    final adapter = _UserInfoAdapter(<String, String?>{});

    final updated =
        await repository.refreshUsage(dio: Dio()..httpClientAdapter = adapter);

    expect(updated, isNull);
    expect((await repository.latest())!.usedBytes, 1);
  });
}
