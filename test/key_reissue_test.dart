import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/account/key_reissue.dart';
import 'package:kago_vpn/features/subscriptions/subscription_repository.dart';

/// Answers every request with [status].
class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);
  final int status;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString('proxies: []', status);

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const oldLink = 'https://panel.example/sub/old';
  const newLink = 'https://panel.example/sub/new';

  Future<String?> replacement(
          {String? saved = oldLink,
          String? account = newLink,
          Set<String> gone = const <String>{oldLink}}) =>
      KeyReissue.replacement(
          saved: saved,
          account: account,
          gone: (url) async => gone.contains(url));

  test('a re-issued key: the old link is gone, the new one works', () async {
    expect(await replacement(), newLink);
  });

  test('a saved link that still works is kept', () async {
    expect(await replacement(gone: const <String>{}), isNull);
  });

  test('both links answering 404 is a server that does not let the app in',
      () async {
    expect(await replacement(gone: const <String>{oldLink, newLink}), isNull);
  });

  test('the same link, no saved link or no account link: nothing to do',
      () async {
    expect(await replacement(account: oldLink), isNull);
    expect(await replacement(saved: null), isNull);
    expect(await replacement(saved: ''), isNull);
    expect(await replacement(account: null), isNull);
    expect(await replacement(account: ''), isNull);
  });

  group('SubscriptionRepository', () {
    const key = 'kago.profiles.v1';

    SubscriptionRepository repository() {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        key: jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{'name': 'KaGo', 'url': oldLink},
          <String, dynamic>{'name': 'KaGo', 'url': newLink},
        ]),
      });
      return SubscriptionRepository(storage: const FlutterSecureStorage());
    }

    test('forget removes only the old link', () async {
      final subscriptions = repository();
      await subscriptions.forget(oldLink);
      expect((await subscriptions.latest())!.url, newLink);
      final stored = await const FlutterSecureStorage().read(key: key);
      expect(jsonDecode(stored!), hasLength(1));
    });

    test('a link is gone on 404 and 410, not on other answers', () async {
      final subscriptions = repository();
      Future<bool> gone(int status) => subscriptions.linkGone(oldLink,
          dio: Dio()..httpClientAdapter = _StatusAdapter(status));
      expect(await gone(404), isTrue);
      expect(await gone(410), isTrue);
      expect(await gone(200), isFalse);
      expect(await gone(500), isFalse);
      expect(await gone(403), isFalse);
    });
  });
}
