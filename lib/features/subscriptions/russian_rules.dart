import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config_builder.dart';

/// Whether the subscription itself sends Russian sites around the VPN
/// (`GEOSITE,category-ru,DIRECT`, `GEOIP,RU,DIRECT`,
/// `DOMAIN-SUFFIX,ru,DIRECT`, a `RULE-SET` named after Russia …). Then the
/// "Russian sites directly" switch on Windows/macOS is not needed: the core
/// already routes them, and the subscription knows the exceptions better than
/// a fixed list of the system proxy.
abstract final class RussianRules {
  static final _ruToken = RegExp(r'(^|[^a-z])(ru|russia)([^a-z]|$)');
  static const _ruSuffixes = <String>{'ru', 'su', 'xn--p1ai', 'рф'};

  static bool present(Map<String, dynamic> config) {
    final rules = config['rules'];
    if (rules is! List) return false;
    final direct = _directTargets(config);
    for (final rule in rules) {
      if (rule is! String) continue;
      final parts = rule.split(',').map((part) => part.trim()).toList();
      if (parts.length < 3) continue;
      if (!direct.contains(parts[2])) continue;
      if (_isRussian(parts[0].toUpperCase(), parts[1].toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  static bool _isRussian(String type, String value) => switch (type) {
        'GEOSITE' || 'RULE-SET' => _ruToken.hasMatch(value),
        'GEOIP' => value == 'ru',
        'DOMAIN-SUFFIX' => _ruSuffixes.contains(value.replaceFirst('.', '')),
        _ => false,
      };

  /// `DIRECT` and groups that go direct by default (a select group with
  /// `DIRECT` first, as panel templates do for "Russia").
  static Set<String> _directTargets(Map<String, dynamic> config) {
    final targets = <String>{'DIRECT'};
    final groups = config['proxy-groups'];
    if (groups is List) {
      for (final group in groups) {
        if (group is! Map) continue;
        final name = group['name'];
        final proxies = group['proxies'];
        if (name is String &&
            proxies is List &&
            proxies.isNotEmpty &&
            proxies.first == 'DIRECT') {
          targets.add(name);
        }
      }
    }
    return targets;
  }
}

/// The saved profile has its own rules for Russian sites (re-read each time
/// the settings open).
final subscriptionRoutesRussiaProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final file = await const MihomoConfigBuilder().activeConfigFile();
  if (!await file.exists()) return false;
  final Object? decoded = jsonDecode(await file.readAsString());
  return decoded is Map<String, dynamic> && RussianRules.present(decoded);
});
