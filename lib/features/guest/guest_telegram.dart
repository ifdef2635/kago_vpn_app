import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';

import '../../core/device/device_identity.dart';
import '../../core/l10n/l10n.dart';
import '../subscriptions/config_builder.dart';
import '../subscriptions/subscription_content_parser.dart';
import '../subscriptions/subscription_providers.dart';
import '../subscriptions/subscription_repository.dart';

/// Free guest access to Telegram: without a working subscription (not signed
/// in, expired, traffic used up) the app still connects, but only Telegram
/// goes through the KAGO guest server, slowly; everything else stays direct.
/// It breaks the loop "Telegram sign-in needs Telegram, Telegram needs a VPN"
/// and works only in this app.
///
/// The guest servers come from [url] — a subscription of a dedicated panel
/// user, served (or redirected to) by usekago.net, so they can change without
/// an app update. These credentials are public by design: the server must
/// itself allow only Telegram for that user and limit its speed (README,
/// «Гостевой доступ к Telegram»). The app sends no HWID or device data there.
abstract final class GuestTelegram {
  static const url = 'https://usekago.net/guest/telegram';
  static const groupName = 'KaGo Telegram';

  /// Health check through the guest server (it lets only Telegram through).
  static const checkUrl = 'https://telegram.org/';

  /// The same site by its address (149.154.160.0/20): the Telegram apps
  /// connect to addresses, not names, so the server must let them through
  /// too (Xray `geoip:telegram`).
  static const addressCheckUrl = 'http://149.154.167.99/';

  /// Checks the running guest connection through the core's controller.
  static Future<GuestCheck> check(
      Future<int?> Function(String url) delayThroughGuest) async {
    if (await delayThroughGuest(checkUrl) == null) return GuestCheck.serverDown;
    if (await delayThroughGuest(addressCheckUrl) == null) {
      return GuestCheck.addressesBlocked;
    }
    return GuestCheck.ok;
  }

  /// File name of the guest profile (also how Android reports it running).
  static const configName = 'guest_config.yaml';

  /// Telegram's own domains and address ranges (core.telegram.org/resources/cidr.txt).
  static const domains = <String>[
    'telegram.org',
    't.me',
    'telegram.me',
    'telegram.dog',
    'telegra.ph',
    'graph.org',
    'telesco.pe',
    'tdesktop.com',
    'cdn-telegram.org',
    'tg.dev',
  ];
  static const ipv4 = <String>[
    '91.105.192.0/23',
    '91.108.4.0/22',
    '91.108.8.0/22',
    '91.108.12.0/22',
    '91.108.16.0/22',
    '91.108.20.0/22',
    '91.108.56.0/22',
    '95.161.64.0/20',
    '149.154.160.0/20',
    '185.76.151.0/24',
  ];
  static const ipv6 = <String>[
    '2001:67c:4e8::/48',
    '2001:b28:f23c::/48',
    '2001:b28:f23d::/48',
    '2001:b28:f23f::/48',
    '2a0a:f280::/32',
  ];

  /// The same for every guest, not the device's id: a panel that requires
  /// an HWID (Remnawave with the device limit on) otherwise serves
  /// placeholder servers instead of the guest ones. All guests count as one
  /// device of the guest user.
  static const guestHwid = 'KAGO-GUEST';

  /// At most this many guest servers are used.
  static const maxProxies = 16;

  /// Guest mode is used when the saved subscription cannot connect.
  static bool needed(ImportedSubscription? profile, DateTime now) {
    if (profile == null || profile.url.isEmpty) return true;
    final expires = profile.expiresAt;
    if (expires != null && expires.isBefore(now)) return true;
    return profile.totalBytes > 0 && profile.usedBytes >= profile.totalBytes;
  }

  /// A Mihomo config that sends only Telegram through [proxies] (the guest
  /// servers) and everything else directly.
  static Map<String, dynamic> buildConfig(List<Map<String, dynamic>> proxies) {
    if (proxies.isEmpty) {
      throw FormatException(tr('Гостевой сервер не найден.'));
    }
    final names = <String>[
      for (final proxy in proxies) proxy['name'] as String
    ];
    return <String, dynamic>{
      'mode': 'rule',
      'log-level': 'warning',
      'ipv6': false,
      'proxies': proxies,
      'proxy-groups': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': groupName,
          'type': names.length > 1 ? 'fallback' : 'select',
          'proxies': names,
          if (names.length > 1) ...<String, dynamic>{
            'url': checkUrl,
            'interval': 600,
            'lazy': true,
          },
        },
      ],
      // Direct traffic needs a resolver that works without a VPN.
      'dns': <String, dynamic>{
        'enable': true,
        'ipv6': false,
        'enhanced-mode': 'fake-ip',
        'fake-ip-range': '198.18.0.1/16',
        'fake-ip-filter': <String>['*.lan', '+.local'],
        'default-nameserver': <String>['77.88.8.8', '8.8.8.8'],
        'nameserver': <String>['77.88.8.8', '8.8.8.8', '1.1.1.1'],
      },
      'rules': <String>[
        for (final domain in domains) 'DOMAIN-SUFFIX,$domain,$groupName',
        for (final cidr in ipv4) 'IP-CIDR,$cidr,$groupName,no-resolve',
        for (final cidr in ipv6) 'IP-CIDR6,$cidr,$groupName,no-resolve',
        'MATCH,DIRECT',
      ],
    };
  }

  /// The guest servers of a subscription body (any format the app reads).
  /// Skipped: entries without a name, type or server; the placeholders a
  /// panel serves for a disabled user (server 0.0.0.0 or loopback); a repeated
  /// name (Mihomo refuses the whole config); a `dialer-proxy` to a server that
  /// is not in the list.
  static List<Map<String, dynamic>> proxiesFrom(String body) {
    final yaml = const SubscriptionContentParser().toMihomoConfig(body);
    final parsed = loadYaml(yaml);
    final list = parsed is YamlMap ? parsed['proxies'] : null;
    final proxies = <Map<String, dynamic>>[];
    final names = <String>{};
    if (list is YamlList) {
      for (final item in list) {
        if (proxies.length >= maxProxies) break;
        if (item is! YamlMap) continue;
        final proxy = jsonDecode(jsonEncode(item)) as Map<String, dynamic>;
        final name = proxy['name'];
        final server = '${proxy['server'] ?? ''}'.trim().toLowerCase();
        if (name is! String ||
            name.trim().isEmpty ||
            name == groupName ||
            proxy['type'] is! String ||
            _placeholderServer(server) ||
            !names.add(name)) {
          continue;
        }
        proxies.add(proxy);
      }
    }
    return <Map<String, dynamic>>[
      for (final proxy in proxies)
        if (proxy['dialer-proxy'] == null ||
            names.contains(proxy['dialer-proxy']))
          proxy
    ];
  }

  static bool _placeholderServer(String server) =>
      server.isEmpty ||
      server == '0.0.0.0' ||
      server == 'localhost' ||
      server == '::' ||
      server == '::1' ||
      server.startsWith('127.');

  /// Downloads the guest servers. usekago.net answers only this app (by the
  /// `KaGoVPN/` part of the User-Agent, README); anyone else gets 404.
  static Future<List<Map<String, dynamic>>> download(
      {Uri? source, Dio? dio, String? userAgent}) async {
    final agent = userAgent ?? await DeviceIdentity.instance.userAgent();
    final response = await SubscriptionRepository.fetch(
        dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15))),
        source ?? Uri.parse(url),
        method: 'GET',
        deviceHeaders: <String, String>{
          'User-Agent': agent,
          'x-hwid': guestHwid,
        },
        headersOnEveryHost: true);
    final hwidProblem = SubscriptionRepository.hwidNotice(response.headers);
    if (hwidProblem != null) {
      throw FormatException(tr('панель отказала гостю: {message}',
          <String, Object?>{'message': hwidProblem}));
    }
    final proxies = proxiesFrom(response.body);
    if (proxies.isEmpty) {
      // A panel placeholder names its reason in the server names.
      String? stub;
      try {
        stub = SubscriptionRepository.panelStubMessage(
            const SubscriptionContentParser().toMihomoConfig(response.body));
      } catch (_) {}
      throw FormatException(stub == null
          ? tr('Гостевой сервер не найден.')
          : tr('панель выдала заглушку вместо серверов: «{message}»',
              <String, Object?>{'message': stub}));
    }
    return proxies;
  }

  /// A short reason for the user instead of the whole Dio error.
  static String reason(Object error) {
    if (error is FormatException) return error.message;
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status != null) {
        return tr('сервер KAGO ответил {status}, попробуйте позже',
            <String, Object?>{'status': status});
      }
      return tr('нет связи с usekago.net, проверьте интернет');
    }
    return '$error';
  }

  static Future<File> _file(String name) async {
    final active = await const MihomoConfigBuilder().activeConfigFile();
    return File('${active.parent.path}${Platform.pathSeparator}$name');
  }

  /// Fetches the guest servers (the last good list when the site does not
  /// answer) and writes the guest config. Returns its file.
  static Future<File> prepare() async {
    final cache = await _file('guest_proxies.json');
    List<Map<String, dynamic>> proxies;
    try {
      proxies = await download();
      await cache.parent.create(recursive: true);
      await cache.writeAsString(jsonEncode(proxies), flush: true);
    } catch (error) {
      final saved = await _cached(cache);
      if (saved.isEmpty) {
        throw GuestUnavailable(tr(
            'Не удалось получить бесплатный доступ к Telegram: {error}',
            <String, Object?>{'error': reason(error)}));
      }
      proxies = saved;
    }
    final file = await _file(configName);
    await file.parent.create(recursive: true);
    await file.writeAsString(
        const MihomoConfigBuilder().encode(jsonEncode(buildConfig(proxies))),
        flush: true);
    return file;
  }

  /// The guest servers for the servers tab while the core is off: the last
  /// list, or a fresh one (saved for next time); empty when unavailable.
  static Future<List<Map<String, dynamic>>> savedOrDownload() async {
    final cache = await _file('guest_proxies.json');
    final saved = await _cached(cache);
    if (saved.isNotEmpty) return saved;
    try {
      final proxies = await download();
      await cache.parent.create(recursive: true);
      await cache.writeAsString(jsonEncode(proxies), flush: true);
      return proxies;
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  static Future<List<Map<String, dynamic>>> _cached(File cache) async {
    try {
      final Object? decoded = jsonDecode(await cache.readAsString());
      if (decoded is! List) return const <Map<String, dynamic>>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .take(maxProxies)
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// Reachability of Telegram's sign-in server: a few seconds, any HTTP
  /// answer counts.
  static Future<bool> telegramReachable() async {
    try {
      await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
        sendTimeout: const Duration(seconds: 4),
        validateStatus: (_) => true,
      )).head<void>('https://oauth.telegram.org/');
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Result of [GuestTelegram.check].
enum GuestCheck { ok, serverDown, addressesBlocked }

/// Guest access could not start; [message] is for the user.
class GuestUnavailable implements Exception {
  const GuestUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Without a working subscription the connect button starts guest mode.
final guestModeNeededProvider = Provider<bool>((ref) => ref
    .watch(importedSubscriptionProvider)
    .when(
        data: (profile) => GuestTelegram.needed(profile, DateTime.now()),
        loading: () => false,
        error: (_, __) => true));

/// The running connection is the guest one (set when it was started).
final guestModeActiveProvider = StateProvider<bool>((ref) => false);
