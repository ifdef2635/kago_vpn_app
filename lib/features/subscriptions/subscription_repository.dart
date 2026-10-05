import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config_builder.dart';
import 'subscription_content_parser.dart';
import 'subscription_parser.dart';
import '../../core/l10n/l10n.dart';

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
      throw FormatException(tr('Ссылка вернула пустой профиль.'));
    }
    final normalized = const SubscriptionContentParser().toMihomoConfig(body);
    final metadata = SubscriptionMetadata.parse(
        yaml: normalized, responseHeaders: response.headers.map);
    await const MihomoConfigBuilder().writeConfig(normalized);
    final fields = parseUserInfo(
        _header(response.headers.map, 'subscription-userinfo'));
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

  /// Parses `upload=1; download=2; total=3; expire=4` from the
  /// `subscription-userinfo` header. Malformed tokens are skipped.
  static Map<String, int> parseUserInfo(String? header) {
    final fields = <String, int>{};
    for (final token in (header ?? '').split(';')) {
      final pair = token.trim().split('=');
      if (pair.length == 2) {
        final value = int.tryParse(pair.last.trim());
        if (value != null) fields[pair.first.trim()] = value;
      }
    }
    return fields;
  }

  /// Re-reads only the traffic counters and expiry from the saved subscription's
  /// `subscription-userinfo` header and stores them. The saved profile config is
  /// not touched, so this is safe while the core is running. Returns the updated
  /// profile, or null when nothing is saved or the server sent no counters.
  Future<ImportedSubscription?> refreshUsage({Dio? dio}) async {
    final stored = await _storage.read(key: _key);
    if (stored == null) return null;
    final decoded = jsonDecode(stored);
    if (decoded is! List<dynamic> ||
        decoded.isEmpty ||
        decoded.last is! Map<String, dynamic>) {
      return null;
    }
    final item = decoded.last as Map<String, dynamic>;
    final url = item['url'] as String? ?? '';
    if (url.isEmpty) return null;
    final uri = validateSubscriptionUrl(url);
    final client = dio ??
        Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            responseType: ResponseType.plain));
    Map<String, int> fields = const <String, int>{};
    // HEAD is cheap, but some panels only send the header on GET.
    for (final method in const <String>['HEAD', 'GET']) {
      try {
        final response = await client.request<String>(uri.toString(),
            options: Options(
                method: method,
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 300));
        fields = parseUserInfo(
            _header(response.headers.map, 'subscription-userinfo'));
        if (fields.isNotEmpty) break;
      } on DioException {
        // Try the next method; a failed refresh just keeps the old numbers.
      }
    }
    final hasCounters = fields.containsKey('upload') ||
        fields.containsKey('download') ||
        fields.containsKey('total');
    if (!hasCounters) return null;
    final used = (fields['upload'] ?? 0) + (fields['download'] ?? 0);
    final total = fields['total'] ?? 0;
    final expire = fields['expire'];
    final newExpire = expire == null
        ? item['expire']
        : expire > 0
            ? expire * 1000
            : null;
    if (item['used'] != used ||
        item['total'] != total ||
        item['expire'] != newExpire) {
      item['used'] = used;
      item['total'] = total;
      item['expire'] = newExpire;
      await _storage.write(key: _key, value: jsonEncode(decoded));
    }
    return latest();
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
      throw FormatException(
          tr('Для внешней подписки используйте HTTPS; HTTP допустим только на localhost. Ссылки с userinfo/fragment запрещены.'));
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
