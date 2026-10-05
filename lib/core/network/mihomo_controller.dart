import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mihomo_models.dart';
import '../l10n/l10n.dart';

class MihomoController {
  MihomoController(
      {FlutterSecureStorage? secureStorage,
      Duration connectTimeout = const Duration(seconds: 4),
      Duration receiveTimeout = const Duration(seconds: 8)})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _connectTimeout = connectTimeout,
        _receiveTimeout = receiveTimeout;
  static const _endpointKey = 'mihomo.endpoint';
  static const _secretKey = 'mihomo.secret';
  final FlutterSecureStorage _secureStorage;
  final Duration _connectTimeout;
  final Duration _receiveTimeout;
  Dio? _cachedClient;
  String? _cachedClientKey;

  /// The secret only changes through [ensureSecret]; reading secure storage
  /// (DPAPI on Windows, Keystore on Android) once a second for the
  /// connections poll is wasted work.
  String? _secretCache;
  bool _secretLoaded = false;

  Future<String?> _secret() async {
    if (!_secretLoaded) {
      _secretCache = await _secureStorage.read(key: _secretKey);
      _secretLoaded = true;
    }
    return _secretCache;
  }

  Future<String> get endpoint async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_endpointKey) ?? 'http://127.0.0.1:9090')
        .replaceAll(RegExp(r'/+$'), '');
  }

  Future<String?> get configuredSecret => _secret();

  /// The controller secret is never typed by the user: it is generated once,
  /// kept in secure storage and written into the config of the core this app
  /// starts, so other local processes and web pages cannot drive the controller.
  Future<String> ensureSecret() async {
    final existing = await _secret();
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final secret = base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    await _secureStorage.write(key: _secretKey, value: secret);
    _secretCache = secret;
    _secretLoaded = true;
    return secret;
  }

  Future<void> saveSettings({required String endpoint}) async {
    final normalized = normalizeEndpoint(endpoint);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_endpointKey, normalized);
  }

  static String normalizeEndpoint(String endpoint) {
    final normalized = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        !<String>['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw FormatException(tr(
          'Укажите корректный HTTPS или локальный HTTP адрес без userinfo/query/fragment.'));
    }
    final isLoopback =
        <String>['127.0.0.1', 'localhost'].contains(uri.host.toLowerCase());
    if (uri.scheme == 'http' && !isLoopback) {
      throw FormatException(tr(
          'HTTP разрешён только для localhost; удалённый контроллер должен использовать HTTPS.'));
    }
    return normalized;
  }

  // Reused between calls: connections are polled every second, and a fresh Dio
  // per request would open a new socket each time.
  Future<Dio> _client() async {
    final secret = await _secret();
    final baseUrl = await endpoint;
    final key = '$baseUrl\n${secret ?? ''}';
    final cached = _cachedClient;
    if (cached != null && _cachedClientKey == key) return cached;
    cached?.close();
    final client = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
      headers: <String, String>{
        if (secret != null && secret.isNotEmpty)
          'Authorization': 'Bearer $secret'
      },
      responseType: ResponseType.json,
    ));
    _cachedClient = client;
    _cachedClientKey = key;
    return client;
  }

  Future<String> version() async {
    final response =
        await (await _client()).get<Map<String, dynamic>>('/version');
    return response.data?['version'] as String? ?? 'Mihomo';
  }

  Future<List<ProxyGroup>> proxies() async {
    final response =
        await (await _client()).get<Map<String, dynamic>>('/proxies');
    return parseProxies(response.data?['proxies'] as Map<String, dynamic>? ??
        const <String, dynamic>{});
  }

  /// Turns the `/proxies` map into groups with node details, ordered like the
  /// config (GLOBAL.all) with GLOBAL itself last.
  static List<ProxyGroup> parseProxies(Map<String, dynamic> raw) {
    final groups = raw.entries
        .where((entry) =>
            entry.value is Map<String, dynamic> &&
            (entry.value as Map<String, dynamic>)['all'] is List<dynamic>)
        .map((entry) => ProxyGroup.fromJson(
            entry.key, entry.value as Map<String, dynamic>, raw))
        .toList();
    // /proxies is an unordered map. GLOBAL.all lists the groups in the order
    // they appear in the config, so use it and keep GLOBAL itself last.
    final configOrder = <String, int>{};
    for (final group in groups) {
      if (group.name == 'GLOBAL') {
        for (final node in group.nodes) {
          configOrder.putIfAbsent(node.name, () => configOrder.length);
        }
      }
    }
    int rank(ProxyGroup group) =>
        group.name == 'GLOBAL' ? 1 << 30 : configOrder[group.name] ?? (1 << 20);
    groups.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.name.compareTo(b.name);
    });
    return groups;
  }

  Future<void> selectProxy(String group, String node) async {
    final client = await _client();
    await client.put<void>('/proxies/${Uri.encodeComponent(group)}',
        data: <String, String>{'name': node});
  }

  Future<int?> testDelay(String proxy,
      {String url = 'https://www.gstatic.com/generate_204'}) async {
    final client = await _client();
    try {
      final response = await client.get<Map<String, dynamic>>(
        '/proxies/${Uri.encodeComponent(proxy)}/delay',
        queryParameters: <String, dynamic>{'url': url, 'timeout': 5000},
      );
      return (response.data?['delay'] as num?)?.toInt();
    } on DioException {
      return null;
    }
  }

  Future<List<ActiveConnection>> connections() async {
    final response =
        await (await _client()).get<Map<String, dynamic>>('/connections');
    final items =
        response.data?['connections'] as List<dynamic>? ?? const <dynamic>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(ActiveConnection.fromJson)
        .toList(growable: false);
  }

  Future<ConnectionsSnapshot> connectionsSnapshot() async {
    final response =
        await (await _client()).get<Map<String, dynamic>>('/connections');
    return ConnectionsSnapshot.fromJson(
        response.data ?? const <String, dynamic>{});
  }

  Future<void> closeConnection(String id) async =>
      (await _client()).delete<void>('/connections/${Uri.encodeComponent(id)}');
  Future<void> closeAllConnections() async =>
      (await _client()).delete<void>('/connections');
}
