import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/device/device_identity.dart';
import '../../core/l10n/l10n.dart';
import '../../core/storage/secure_storage.dart';

/// usekago.net personal account API (Remnashop, `openapi.json` in the site
/// repository). The site's reverse proxy serves it under `/api/v1/public`.
const kagoSiteUrl = 'https://usekago.net';
const kagoApiBase = '$kagoSiteUrl/api/v1/public';

class KagoApiException implements Exception {
  const KagoApiException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// The session is gone (logged out, or the refresh token expired).
class KagoUnauthorized extends KagoApiException {
  KagoUnauthorized() : super(tr('Сессия истекла. Войдите снова.'), status: 401);
}

class KagoUser {
  const KagoUser({
    required this.name,
    this.email,
    this.username,
    this.telegramId,
    this.isEmailVerified = false,
    this.pendingEmail,
    this.authType = 'email',
  });

  factory KagoUser.fromJson(Map<String, dynamic> json) => KagoUser(
        name: json['name'] as String? ?? '',
        email: json['email'] as String?,
        username: json['username'] as String?,
        telegramId: (json['telegram_id'] as num?)?.toInt(),
        isEmailVerified: json['is_email_verified'] as bool? ?? false,
        pendingEmail: json['pending_email'] as String?,
        authType: json['auth_type'] as String? ?? 'email',
      );

  final String name;
  final String? email;
  final String? username;
  final int? telegramId;
  final bool isEmailVerified;
  final String? pendingEmail;
  final String authType;
}

class KagoSubscription {
  const KagoSubscription({
    required this.status,
    required this.isTrial,
    required this.trafficLimitGb,
    required this.deviceLimit,
    required this.expireAt,
    required this.url,
    required this.planName,
    this.usedTrafficBytes,
  });

  factory KagoSubscription.fromJson(Map<String, dynamic> json) =>
      KagoSubscription(
        status: json['status'] as String? ?? '',
        isTrial: json['is_trial'] as bool? ?? false,
        trafficLimitGb: (json['traffic_limit'] as num?)?.toInt() ?? 0,
        deviceLimit: (json['device_limit'] as num?)?.toInt() ?? 0,
        expireAt: DateTime.tryParse(json['expire_at'] as String? ?? ''),
        url: json['url'] as String? ?? '',
        planName: json['plan_name'] as String? ?? '',
        usedTrafficBytes: (json['used_traffic_bytes'] as num?)?.toInt(),
      );

  final String status;
  final bool isTrial;

  /// Traffic limit in GB; 0 means unlimited (the site multiplies by 1e9).
  final int trafficLimitGb;
  final int deviceLimit;
  final DateTime? expireAt;
  final String url;
  final String planName;
  final int? usedTrafficBytes;

  bool get isActive => status.toUpperCase() == 'ACTIVE';

  /// The site treats year 2099 as a lifetime plan (shown as ∞, cannot be renewed).
  bool get isLifetime => (expireAt?.year ?? 0) >= 2099;
}

class KagoDevice {
  const KagoDevice(
      {required this.hwid, this.platform, this.model, this.osVersion});

  factory KagoDevice.fromJson(Map<String, dynamic> json) => KagoDevice(
        hwid: json['hwid'] as String? ?? '',
        platform: json['platform'] as String?,
        model: json['device_model'] as String?,
        osVersion: json['os_version'] as String?,
      );

  final String hwid;
  final String? platform;
  final String? model;
  final String? osVersion;
}

class KagoDevices {
  const KagoDevices(
      {required this.devices, required this.current, required this.max});

  factory KagoDevices.fromJson(Map<String, dynamic> json) => KagoDevices(
        devices: (json['devices'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(KagoDevice.fromJson)
            .toList(growable: false),
        current: (json['current_count'] as num?)?.toInt() ?? 0,
        max: (json['max_count'] as num?)?.toInt() ?? 0,
      );

  final List<KagoDevice> devices;
  final int current;
  final int max;
}

class KagoReferral {
  const KagoReferral(
      {required this.enabled,
      required this.code,
      required this.invited,
      required this.paid});

  factory KagoReferral.fromJson(Map<String, dynamic> json) => KagoReferral(
        enabled: json['enabled'] as bool? ?? false,
        code: json['referral_code'] as String? ?? '',
        invited: (json['invited_count'] as num?)?.toInt() ?? 0,
        paid: (json['invited_with_payment_count'] as num?)?.toInt() ?? 0,
      );

  final bool enabled;
  final String code;
  final int invited;
  final int paid;

  String get link => '$kagoSiteUrl/ref/$code';
}

/// Keeps the httpOnly session cookies the site sets (access + refresh) in
/// secure storage and sends them back, like a browser would.
class KagoCookieStore {
  KagoCookieStore({FlutterSecureStorage? storage})
      : _storage = storage ?? kagoSecureStorage;
  static const _key = 'kago.account.cookies.v1';
  final FlutterSecureStorage _storage;
  Map<String, String>? _cache;

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final raw = await _storage.read(key: _key);
      final decoded = raw == null ? null : jsonDecode(raw);
      _cache = decoded is Map<String, dynamic>
          ? decoded.map((key, value) => MapEntry(key, '$value'))
          : <String, String>{};
    } catch (_) {
      _cache = <String, String>{};
    }
    return _cache!;
  }

  Future<String?> header() async {
    final cookies = await _load();
    if (cookies.isEmpty) return null;
    return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<bool> get hasSession async => (await _load()).isNotEmpty;

  /// A copy of the stored session cookies (name -> value).
  Future<Map<String, String>> all() async =>
      Map<String, String>.of(await _load());

  /// Replaces the session with cookies taken from the in-app site page.
  Future<void> replaceAll(Map<String, String> cookies) async {
    _cache = Map<String, String>.of(cookies);
    await _storage.write(key: _key, value: jsonEncode(_cache));
  }

  Future<void> update(List<String>? setCookies) async {
    if (setCookies == null || setCookies.isEmpty) return;
    final cookies = await _load();
    for (final raw in setCookies) {
      try {
        final cookie = Cookie.fromSetCookieValue(raw);
        final expired = (cookie.maxAge != null && cookie.maxAge! <= 0) ||
            (cookie.expires != null &&
                cookie.expires!.isBefore(DateTime.now())) ||
            cookie.value.isEmpty;
        if (expired) {
          cookies.remove(cookie.name);
        } else {
          cookies[cookie.name] = cookie.value;
        }
      } catch (_) {
        // dart:io is stricter than browsers about cookie values; keep the
        // plain name=value pair in that case.
        final pair = raw.split(';').first;
        final at = pair.indexOf('=');
        if (at > 0) {
          final name = pair.substring(0, at).trim();
          final value = pair.substring(at + 1).trim();
          if (value.isEmpty) {
            cookies.remove(name);
          } else {
            cookies[name] = value;
          }
        }
      }
    }
    await _storage.write(key: _key, value: jsonEncode(cookies));
  }

  Future<void> clear() async {
    _cache = <String, String>{};
    await _storage.delete(key: _key);
  }
}

class KagoApi {
  KagoApi({Dio? dio, KagoCookieStore? cookies})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: kagoApiBase,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              responseType: ResponseType.plain,
              // Errors are mapped below instead of DioException.
              validateStatus: (_) => true,
              headers: <String, String>{'Accept': 'application/json'},
            )),
        cookies = cookies ?? KagoCookieStore();

  final Dio _dio;
  final KagoCookieStore cookies;
  Future<bool>? _refreshing;

  Future<Response<String>> _raw(String method, String path,
      {Object? body}) async {
    final cookie = await cookies.header();
    final userAgent = await _userAgent();
    final response = await _dio.request<String>(path,
        data: body == null ? null : jsonEncode(body),
        options: Options(method: method, headers: <String, String>{
          'Content-Type': 'application/json',
          if (userAgent != null) 'User-Agent': userAgent,
          if (cookie != null) 'Cookie': cookie,
        }));
    await cookies.update(response.headers.map['set-cookie']);
    return response;
  }

  static Future<String?> _userAgent() async {
    try {
      return await DeviceIdentity.instance.apiUserAgent();
    } catch (_) {
      return null;
    }
  }

  /// One shared refresh for parallel 401s (same as the site's `tryRefresh`).
  Future<bool> _refresh() => _refreshing ??= _raw('POST', '/auth/refresh')
      .then((response) => response.statusCode == 200)
      .catchError((Object _) => false)
      .whenComplete(() => _refreshing = null);

  Future<dynamic> request(String method, String path, {Object? body}) async {
    Response<String> response;
    try {
      response = await _raw(method, path, body: body);
      if (response.statusCode == 401 &&
          path != '/auth/refresh' &&
          path != '/auth/login') {
        if (!await _refresh()) {
          await cookies.clear();
          throw KagoUnauthorized();
        }
        response = await _raw(method, path, body: body);
      }
    } on DioException catch (error) {
      throw KagoApiException(_networkMessage(error));
    }
    final status = response.statusCode ?? 0;
    final text = response.data ?? '';
    dynamic json;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } catch (_) {
        json = null;
      }
    }
    if (status == 401) {
      await cookies.clear();
      throw KagoUnauthorized();
    }
    if (status < 200 || status >= 300) {
      throw KagoApiException(errorDetail(json, status), status: status);
    }
    return json;
  }

  static String _networkMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return tr(
            'usekago.net не отвечает. Проверьте интернет и попробуйте ещё раз.');
      default:
        return tr(
            'Нет связи с usekago.net. Проверьте интернет и попробуйте ещё раз.');
    }
  }

  /// FastAPI `detail`: a string, or a list of validation errors.
  static String errorDetail(dynamic body, int status) {
    final detail = body is Map<String, dynamic> ? body['detail'] : null;
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty) {
      final messages = detail
          .whereType<Map<String, dynamic>>()
          .map((item) => item['msg'])
          .whereType<String>()
          .where((msg) => msg.isNotEmpty)
          .join('. ');
      if (messages.isNotEmpty) return messages;
    }
    return tr(
        'Ошибка сервера (HTTP {status})', <String, Object?>{'status': status});
  }

  Map<String, dynamic> _map(dynamic json) =>
      json is Map<String, dynamic> ? json : <String, dynamic>{};

  // ─── Auth ──────────────────────────────────────────────────

  Future<void> login(String email, String password) =>
      request('POST', '/auth/login',
          body: <String, String>{'email': email.trim(), 'password': password});

  Future<void> register(String email, String password, {String? name}) =>
      request('POST', '/auth/register', body: <String, Object?>{
        'email': email.trim(),
        'password': password,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      });

  /// Telegram OIDC: exchanges the `id_token` from Telegram's login popup for
  /// a session (same call as the site's `telegramLogin`).
  Future<void> telegramLogin(String idToken) =>
      request('POST', '/auth/telegram',
          body: <String, String>{'id_token': idToken});

  Future<void> logout() async {
    try {
      await request('POST', '/auth/logout');
    } catch (_) {
      // Forget the session locally even if the server is unreachable.
    }
    await cookies.clear();
  }

  Future<KagoUser> me() async =>
      KagoUser.fromJson(_map(await request('GET', '/auth/me')));

  Future<void> changePassword(String current, String next) =>
      request('POST', '/auth/change-password', body: <String, String>{
        'current_password': current,
        'new_password': next
      });

  Future<String> changeEmail(String email) async {
    final json = _map(await request('POST', '/auth/email/change',
        body: <String, String>{'email': email.trim()}));
    return json['pending_email'] as String? ?? email.trim();
  }

  Future<void> requestEmailVerification([String? email]) =>
      request('POST', '/auth/email/request-verification',
          body: email == null
              ? <String, String>{}
              : <String, String>{'email': email});

  Future<void> confirmEmail(String code) =>
      request('POST', '/auth/email/confirm',
          body: <String, String>{'code': code.trim()});

  // ─── Subscription ──────────────────────────────────────────

  Future<KagoSubscription?> subscription() async {
    final json = await request('GET', '/subscription/current');
    return json is Map<String, dynamic>
        ? KagoSubscription.fromJson(json)
        : null;
  }

  Future<KagoDevices> devices() async =>
      KagoDevices.fromJson(_map(await request('GET', '/subscription/devices')));

  Future<void> deleteDevice(String hwid) =>
      request('DELETE', '/subscription/devices/${Uri.encodeComponent(hwid)}');

  Future<void> deleteAllDevices() => request('DELETE', '/subscription/devices');

  Future<void> reissue() => request('POST', '/subscription/reissue');

  Future<void> activatePromocode(String code) =>
      request('POST', '/subscription/promocode',
          body: <String, String>{'code': code.trim()});

  Future<KagoReferral> referral() async =>
      KagoReferral.fromJson(_map(await request('GET', '/referral/program')));
}
