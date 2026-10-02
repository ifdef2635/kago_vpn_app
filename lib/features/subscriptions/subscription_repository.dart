import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config_builder.dart';
import 'subscription_content_parser.dart';
import 'subscription_parser.dart';

class ImportedSubscription {
  const ImportedSubscription(
      {required this.name,
      required this.url,
      required this.usedBytes,
      required this.totalBytes,
      required this.expiresAt,
      required this.groups});
  final String name;
  final String url;
  final int usedBytes;
  final int totalBytes;
  final DateTime? expiresAt;
  final List<String> groups;
}

class SubscriptionRepository {
  SubscriptionRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  static const _key = 'kago.profiles.v1';
  final FlutterSecureStorage _storage;

  Future<ImportedSubscription?> latest() async {
    final stored = await _storage.read(key: _key);
    if (stored == null) return null;
    final decoded = jsonDecode(stored);
    if (decoded is! List<dynamic> ||
        decoded.isEmpty ||
        decoded.last is! Map<String, dynamic>) {
      return null;
    }
    final item = decoded.last as Map<String, dynamic>;
    final expire = item['expire'] as int?;
    return ImportedSubscription(
      name: item['name'] as String? ?? 'KaGo VPN',
      url: item['url'] as String? ?? '',
      usedBytes: item['used'] as int? ?? 0,
      totalBytes: item['total'] as int? ?? 0,
      expiresAt:
          expire == null ? null : DateTime.fromMillisecondsSinceEpoch(expire),
      groups: (item['groups'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Future<ImportedSubscription> import(String rawUrl) async {
    final uri = validateSubscriptionUrl(rawUrl);
    final response = await Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 20),
            responseType: ResponseType.plain))
        .get<String>(uri.toString(),
            options: Options(
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 300));
    final body = response.data ?? '';
    if (body.trim().isEmpty) {
      throw const FormatException('Ссылка вернула пустой профиль.');
    }
    final normalized = const SubscriptionContentParser().toMihomoConfig(body);
    final metadata = SubscriptionMetadata.parse(
        yaml: normalized, responseHeaders: response.headers.map);
    await const MihomoConfigBuilder().writeConfig(normalized);
    final info = _header(response.headers.map, 'subscription-userinfo');
    final fields = <String, int>{};
    for (final token in (info ?? '').split(';')) {
      final pair = token.trim().split('=');
      if (pair.length == 2) {
        fields[pair.first.trim()] = int.tryParse(pair.last.trim()) ?? 0;
      }
    }
    final profile = ImportedSubscription(
      name: metadata.serviceName,
      url: uri.toString(),
      usedBytes: (fields['upload'] ?? 0) + (fields['download'] ?? 0),
      totalBytes: fields['total'] ?? 0,
      expiresAt: (fields['expire'] ?? 0) > 0
          ? DateTime.fromMillisecondsSinceEpoch(fields['expire']! * 1000)
          : null,
      groups: metadata.proxyGroupNames,
    );
    final stored = await _storage.read(key: _key);
    final profiles = stored == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(stored) as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList();
    profiles.removeWhere((item) => item['url'] == profile.url);
    profiles.add(<String, dynamic>{
      'name': profile.name,
      'url': profile.url,
      'used': profile.usedBytes,
      'total': profile.totalBytes,
      'expire': profile.expiresAt?.millisecondsSinceEpoch,
      'groups': profile.groups
    });
    await _storage.write(key: _key, value: jsonEncode(profiles));
    return profile;
  }

  static Uri validateSubscriptionUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    final isLoopback = uri != null &&
        <String>['127.0.0.1', 'localhost'].contains(uri.host.toLowerCase());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback))) {
      throw const FormatException(
          'Для внешней подписки используйте HTTPS; HTTP допустим только на localhost. Ссылки с userinfo/fragment запрещены.');
    }
    return uri;
  }

  String? _header(Map<String, List<String>> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value.join(',');
    }
    return null;
  }
}
