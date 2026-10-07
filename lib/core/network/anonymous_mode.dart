import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/subscriptions/config_builder.dart';
import 'windows_zones.g.dart';

/// "Anonymous" connection profile (the other one is "Normal", the
/// subscription as is). What a checker such as whoer.net compares and what
/// the app can change:
///
/// - DNS: every lookup goes through the VPN (DoH, `respect-rules`), none to
///   the provider; apps get fake IPs, so the VPN server resolves the real
///   names. The DNS server a site sees is then the one of the VPN server — its
///   country is set on the server (README, «Анонимный режим»).
/// - IPv6 is off, so nothing leaves outside the IPv4 tunnel.
/// - Windows: while connected the system time zone is the one of the VPN
///   exit (restored afterwards), so the browser's clock matches the IP.
///
/// Browser language and Do Not Track are browser settings and cannot be
/// changed by a VPN app.
abstract final class AnonymousMode {
  static const key = 'kago.connection.anonymous';

  static Future<bool> enabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(key, value);

  /// DoH servers, reached through the VPN.
  static const nameservers = <String>[
    'https://1.1.1.1/dns-query',
    'https://8.8.8.8/dns-query',
  ];

  /// Only for the VPN servers' own host names (they cannot go through the
  /// VPN before it is up).
  static const bootstrapNameservers = <String>['77.88.8.8', '1.1.1.1'];

  /// Turns a profile into the anonymous one (in place).
  static void apply(Map<String, dynamic> config) {
    config['ipv6'] = false;
    final old = config['dns'];
    final filter = old is Map<String, dynamic> && old['fake-ip-filter'] is List
        ? old['fake-ip-filter']
        : const <String>['*.lan', '+.local'];
    config['dns'] = <String, dynamic>{
      'enable': true,
      'ipv6': false,
      'enhanced-mode': 'fake-ip',
      'fake-ip-range': '198.18.0.1/16',
      'fake-ip-filter': filter,
      // DNS follows the rules: through the VPN unless the site goes direct.
      'respect-rules': true,
      'default-nameserver': bootstrapNameservers,
      'proxy-server-nameserver': bootstrapNameservers,
      'nameserver': nameservers,
    };
    // Apps that connect to bare IPs: the real host name is read from the
    // TLS/HTTP handshake and sent to the VPN server instead.
    config['sniffer'] = <String, dynamic>{
      'enable': true,
      'force-dns-mapping': true,
      'parse-pure-ip': true,
      'override-destination': true,
      'sniff': <String, dynamic>{
        'HTTP': <String, dynamic>{
          'ports': <Object>[80, '8080-8880'],
        },
        'TLS': <String, dynamic>{
          'ports': <Object>[443, 8443],
        },
        'QUIC': <String, dynamic>{
          'ports': <Object>[443, 8443],
        },
      },
    };
  }

  /// Writes the anonymous variant of [source] next to it and returns it.
  static Future<File> write(File source) async {
    final Object? decoded = jsonDecode(await source.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('active config');
    }
    apply(decoded);
    final active = await const MihomoConfigBuilder().activeConfigFile();
    final file = File(
        '${active.parent.path}${Platform.pathSeparator}anonymous_config.yaml');
    await file.writeAsString(jsonEncode(decoded), flush: true);
    return file;
  }
}

/// The running connection uses the anonymous profile (set when it started).
final anonymousActiveProvider = StateProvider<bool>((ref) => false);

/// The saved choice, for the settings screen.
final anonymousModeProvider =
    FutureProvider<bool>((ref) => AnonymousMode.enabled());

/// Windows time zone of the VPN exit while the anonymous profile is
/// connected (tzutil needs no administrator rights). The user's own zone is
/// saved first and restored on disconnect, on quit and at the next start
/// after a crash.
abstract final class WindowsTimeZone {
  static const _savedKey = 'kago.windows.timezone.saved';

  /// IANA zone (`Europe/Berlin`) -> Windows ID (`W. Europe Standard Time`).
  static final Map<String, String> _byIana = <String, String>{
    for (final MapEntry(key: windows, value: zones)
        in windowsZonesByIana.entries)
      for (final zone in zones) zone: windows,
  };

  static String? windowsIdFor(String ianaZone) => _byIana[ianaZone];

  static Future<String?> _current() async {
    final result = await Process.run('tzutil', const <String>['/g']);
    final value = '${result.stdout}'.trim();
    return result.exitCode == 0 && value.isNotEmpty ? value : null;
  }

  static Future<bool> _set(String windowsId) async =>
      (await Process.run('tzutil', <String>['/s', windowsId])).exitCode == 0;

  /// Switches to [ianaZone]; false if it is unknown or could not be set.
  static Future<bool> apply(String ianaZone) async {
    if (!Platform.isWindows) return false;
    final target = windowsIdFor(ianaZone);
    if (target == null) return false;
    final preferences = await SharedPreferences.getInstance();
    final current = await _current();
    if (current == null) return false;
    // Keep the user's zone from the first switch (a reconnect must not save
    // the VPN zone as "the user's").
    if (preferences.getString(_savedKey) == null) {
      await preferences.setString(_savedKey, current);
    }
    if (current == target) return true;
    return _set(target);
  }

  /// Gives the user's own zone back, if KaGo changed it.
  static Future<void> restore() async {
    if (!Platform.isWindows) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_savedKey);
      if (saved == null) return;
      if (await _current() != saved) await _set(saved);
      await preferences.remove(_savedKey);
    } catch (_) {
      // Best effort: tried again at the next start.
    }
  }
}
