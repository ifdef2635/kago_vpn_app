import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yaml/yaml.dart';

import '../../core/device/device_identity.dart';
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
                headers: await _deviceHeaders(),
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 300));
    final body = response.data ?? '';
    if (body.trim().isEmpty) {
      throw FormatException(tr('Ссылка вернула пустой профиль.'));
    }
    final hwidProblem = hwidNotice(response.headers.map);
    if (hwidProblem != null) throw FormatException(hwidProblem);
    final normalized = const SubscriptionContentParser().toMihomoConfig(body);
    final stub = panelStubMessage(normalized);
    if (stub != null) {
      throw FormatException(tr(
          'Сервер подписки не выдал серверы: «{message}». Проверьте лимит устройств в «Кабинете» → «Устройства» и обновите подписку.',
          <String, Object?>{'message': stub}));
    }
    final metadata = SubscriptionMetadata.parse(
        yaml: normalized, responseHeaders: response.headers.map);
    await const MihomoConfigBuilder().writeConfig(normalized);
    final fields =
        parseUserInfo(_header(response.headers.map, 'subscription-userinfo'));
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
    // HEAD is cheap, but some panels only send the header on GET. Remember
    // which one worked, so a GET-only panel is not asked with HEAD first every
    // minute; the other method is still tried if the known one stops working.
    final known = _workingMethod[uri.toString()];
    final order = known == 'GET'
        ? const <String>['GET', 'HEAD']
        : const <String>['HEAD', 'GET'];
    for (final method in order) {
      try {
        final response = await client.request<String>(uri.toString(),
            options: Options(
                method: method,
                headers: await _deviceHeaders(),
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 300));
        fields = parseUserInfo(
            _header(response.headers.map, 'subscription-userinfo'));
        if (fields.isNotEmpty) {
          _workingMethod[uri.toString()] = method;
          break;
        }
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

  static Future<Map<String, String>> _deviceHeaders() async {
    try {
      return await DeviceIdentity.instance.headers();
    } catch (_) {
      return const <String, String>{};
    }
  }

  /// The panel's HWID verdict from the response headers, as FlClashX reads
  /// them: `x-hwid-max-devices-reached: true` with the panel's text in
  /// `announce` (optionally `base64:`), or `x-hwid-not-supported: true`.
  static String? hwidNotice(Map<String, List<String>> headers) {
    String? value(String name) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == name) {
          return entry.value.join(',').trim();
        }
      }
      return null;
    }

    if (value('x-hwid-max-devices-reached')?.toLowerCase() == 'true') {
      final announce = _decodeAnnounce(value('announce'));
      return announce.isNotEmpty
          ? announce
          : tr(
              'Достигнут лимит устройств подписки. Удалите лишнее устройство в «Кабинете» → «Устройства» и обновите подписку.');
    }
    if (value('x-hwid-not-supported')?.toLowerCase() == 'true') {
      return tr(
          'Сервер подписки не принял идентификатор устройства (HWID). Обновите приложение или напишите в поддержку.');
    }
    return null;
  }

  static String _decodeAnnounce(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final text = raw.startsWith('base64:') ? raw.substring(7) : raw;
    try {
      return utf8.decode(base64.decode(base64.normalize(text))).trim();
    } catch (_) {
      return raw;
    }
  }

  /// Remnawave answers a request it will not serve (no HWID, device limit
  /// reached, expired or unknown client) with placeholder servers whose
  /// names carry the reason and whose address is 0.0.0.0 or 127.0.0.1.
  /// Returns that reason, or null for a real profile.
  static String? panelStubMessage(String mihomoYaml) {
    final dynamic root;
    try {
      root = loadYaml(mihomoYaml);
    } catch (_) {
      return null;
    }
    final proxies = root is YamlMap ? root['proxies'] : null;
    if (proxies is! YamlList || proxies.isEmpty) return null;
    final names = <String>[];
    for (final proxy in proxies.whereType<YamlMap>()) {
      final server = '${proxy['server'] ?? ''}'.trim();
      if (!const <String>{'0.0.0.0', '127.0.0.1', '::', '::1', 'localhost'}
          .contains(server)) {
        return null;
      }
      final name = '${proxy['name'] ?? ''}'.trim();
      if (name.isNotEmpty) names.add(name);
    }
    return names.isEmpty ? null : names.join(' · ');
  }

  /// Subscription URL -> the request method that returned the counters.
  static final _workingMethod = <String, String>{};

  static Uri validateSubscriptionUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    final isLoopback = uri != null &&
        <String>['127.0.0.1', 'localhost'].contains(uri.host.toLowerCase());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback))) {
      throw FormatException(tr(
          'Для внешней подписки используйте HTTPS; HTTP допустим только на localhost. Ссылки с userinfo/fragment запрещены.'));
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
