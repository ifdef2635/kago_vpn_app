import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../l10n/l10n.dart';

/// The public IP the internet currently sees for this device, with a rough
/// location and provider name.
class IpInfo {
  const IpInfo(
      {required this.ip,
      this.country,
      this.countryCode,
      this.city,
      this.isp,
      this.timeZone,
      this.viaVpn});
  final String ip;
  final String? country;
  final String? countryCode;
  final String? city;
  final String? isp;

  /// IANA time zone of the address (`Europe/Berlin`), if the service knows.
  final String? timeZone;

  /// Looked up through the VPN (true) or directly (false); null if unknown.
  final bool? viaVpn;

  IpInfo withRoute({required bool viaVpn}) => IpInfo(
      ip: ip,
      country: country,
      countryCode: countryCode,
      city: city,
      isp: isp,
      timeZone: timeZone,
      viaVpn: viaVpn);

  /// Regional-indicator flag emoji for [countryCode], or an empty string.
  String get flag {
    final code = countryCode?.toUpperCase();
    if (code == null || !RegExp(r'^[A-Z]{2}$').hasMatch(code)) return '';
    return String.fromCharCodes(
        code.codeUnits.map((unit) => 0x1F1E6 + unit - 0x41));
  }

  /// "Frankfurt am Main, Germany", whichever parts are known.
  String get place => <String?>[city, country]
      .whereType<String>()
      .where((part) => part.trim().isNotEmpty)
      .join(', ');

  static String? _text(Object? value) {
    final text = value is String ? value.trim() : null;
    return text == null || text.isEmpty ? null : text;
  }

  static String _validIp(Object? value) {
    final ip = _text(value);
    if (ip == null || !(ip.contains('.') || ip.contains(':'))) {
      throw FormatException(tr('Сервис не вернул IP-адрес.'));
    }
    return ip;
  }

  /// https://ipwho.is/
  factory IpInfo.fromIpWhoIs(Map<String, dynamic> json) {
    if (json['success'] == false) {
      throw FormatException(_text(json['message']) ?? tr('ipwho.is: отказ.'));
    }
    final connection = json['connection'];
    final zone = json['timezone'];
    return IpInfo(
      timeZone: zone is Map<String, dynamic> ? _text(zone['id']) : null,
      ip: _validIp(json['ip']),
      country: _text(json['country']),
      countryCode: _text(json['country_code']),
      city: _text(json['city']),
      isp: connection is Map<String, dynamic>
          ? _text(connection['isp']) ?? _text(connection['org'])
          : null,
    );
  }

  /// https://api.ip.sb/geoip
  factory IpInfo.fromIpSb(Map<String, dynamic> json) => IpInfo(
        ip: _validIp(json['ip']),
        timeZone: _text(json['timezone']),
        country: _text(json['country']),
        countryCode: _text(json['country_code']),
        city: _text(json['city']),
        isp: _text(json['isp']) ?? _text(json['organization']),
      );

  /// https://api.ipify.org?format=json (address only)
  factory IpInfo.fromIpify(Map<String, dynamic> json) =>
      IpInfo(ip: _validIp(json['ip']));
}

/// Looks the public IP up on a few independent HTTPS services, in order, until
/// one answers. Only these third-party services see the request.
///
/// On desktop the app's own HTTP client ignores the Windows system proxy, so
/// pass [proxyPort] while the local core runs to send the request through it
/// and get the VPN address instead of the real one. On Android the VPN already
/// covers this app, so no proxy is needed.
class IpInfoService {
  IpInfoService({Dio? dio}) : _dio = dio;
  final Dio? _dio;

  static final List<(String, IpInfo Function(Map<String, dynamic>))>
      _endpoints = <(String, IpInfo Function(Map<String, dynamic>))>[
    ('https://ipwho.is/', IpInfo.fromIpWhoIs),
    ('https://api.ip.sb/geoip', IpInfo.fromIpSb),
    ('https://api.ipify.org?format=json', IpInfo.fromIpify),
  ];

  Future<IpInfo> fetch({int? proxyPort}) async {
    final dio = _dio ?? _newDio(proxyPort);
    Object? lastError;
    StackTrace? lastStack;
    for (final (url, parse) in _endpoints) {
      try {
        final response = await dio.get<Object?>(url);
        final data = response.data;
        if (data is Map<String, dynamic>) return parse(data);
        throw FormatException(tr('Неожиданный ответ сервиса IP.'));
      } catch (error, stackTrace) {
        lastError = error;
        lastStack = stackTrace;
      }
    }
    Error.throwWithStackTrace(
        lastError ?? StateError(tr('Нет сервисов для определения IP.')),
        lastStack ?? StackTrace.current);
  }

  static Dio _newDio(int? proxyPort) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      responseType: ResponseType.json,
      headers: const <String, String>{'Accept': 'application/json'},
    ));
    if (proxyPort != null) {
      dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
        return client;
      });
    }
    return dio;
  }
}
