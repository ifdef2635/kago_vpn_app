import 'dart:convert';

import '../../features/guest/guest_telegram.dart';
import '../../features/subscriptions/config_builder.dart';
import '../models/mihomo_models.dart';

/// Servers and groups of the saved profile, read from its config file. Used
/// while the core is not running, when the controller cannot be asked.
/// Without a saved subscription: the free Telegram server (guest access).
Future<List<ProxyGroup>> loadOfflineProxyGroups() async {
  final file = await const MihomoConfigBuilder().activeConfigFile();
  if (!await file.exists()) {
    final guest = await GuestTelegram.savedOrDownload();
    if (guest.isEmpty) return const <ProxyGroup>[];
    return proxyGroupsFromConfig(GuestTelegram.buildConfig(guest));
  }
  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) return const <ProxyGroup>[];
  return proxyGroupsFromConfig(decoded);
}

/// Descriptions of the saved profile (none without one).
Future<ProfileDescriptions> loadProfileDescriptions() async {
  final file = await const MihomoConfigBuilder().activeConfigFile();
  if (!await file.exists()) return const ProfileDescriptions();
  final Object? decoded = jsonDecode(await file.readAsString());
  return decoded is Map<String, dynamic>
      ? ProfileDescriptions.of(decoded)
      : const ProfileDescriptions();
}

/// Builds the same group/node model the controller returns, from a Mihomo config.
/// Which node is selected is unknown without the core, so `selected` is null.
List<ProxyGroup> proxyGroupsFromConfig(Map<String, dynamic> config) {
  final rawGroups = config['proxy-groups'];
  if (rawGroups is! List<dynamic>) return const <ProxyGroup>[];

  final descriptions = ProfileDescriptions.of(config);
  final proxyTypes = <String, String>{'DIRECT': 'Direct', 'REJECT': 'Reject'};
  final proxyNames = <String>[];
  final proxies = config['proxies'];
  if (proxies is List<dynamic>) {
    for (final item in proxies) {
      if (item is Map<String, dynamic> && item['name'] is String) {
        final name = item['name'] as String;
        proxyNames.add(name);
        proxyTypes[name] = _proxyType(item['type']);
      }
    }
  }

  final groupTypes = <String, String>{};
  for (final item in rawGroups) {
    if (item is Map<String, dynamic> && item['name'] is String) {
      groupTypes[item['name'] as String] = _groupType(item['type']);
    }
  }

  final groups = <ProxyGroup>[];
  for (final item in rawGroups) {
    if (item is! Map<String, dynamic> || item['name'] is! String) continue;
    final name = item['name'] as String;
    final names = <String>[
      ...((item['proxies'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<String>(),
    ];
    if (item['include-all'] == true || item['include-all-proxies'] == true) {
      // The core adds all servers sorted by name, then applies the filters.
      final all = List<String>.of(proxyNames)..sort(compareCodePoints);
      final extra = _filtered(all, item, proxyTypes)
          .where((n) => !names.contains(n))
          .toList();
      names.addAll(extra);
    }
    groups.add(ProxyGroup(
      name: name,
      type: groupTypes[name] ?? 'Selector',
      nodes: names
          .map((node) => ProxyNode(
              name: node,
              type: groupTypes[node] ?? proxyTypes[node] ?? 'Proxy'))
          .toList(growable: false),
      hidden: item['hidden'] == true,
      icon: proxyGroupUrl(item['icon']),
      testUrl: proxyGroupUrl(item['url']),
    ).withDescriptions(descriptions));
  }
  return groups;
}

/// Go's string order (by code points, as the core sorts names); Dart's
/// [String.compareTo] compares UTF-16 units and puts flag emoji elsewhere.
int compareCodePoints(String a, String b) {
  final x = a.runes.iterator;
  final y = b.runes.iterator;
  while (true) {
    final hasX = x.moveNext();
    final hasY = y.moveNext();
    if (!hasX || !hasY) return hasX == hasY ? 0 : (hasX ? 1 : -1);
    if (x.current != y.current) return x.current.compareTo(y.current);
  }
}

/// A subscription's filter regex runs on the UI thread with Dart's
/// backtracking engine: refuse long patterns and nested quantifiers such as
/// `(a+)+`, which can freeze the app ("ReDoS"); the group then lists all
/// servers, as with a pattern Dart cannot parse.
RegExp? safeGroupFilter(String pattern) {
  if (pattern.length > 256 ||
      RegExp(r'\([^()]*[+*][^()]*\)\s*[+*{]').hasMatch(pattern)) {
    return null;
  }
  return RegExp(pattern);
}

/// The patterns of a `filter` / `exclude-filter`: Mihomo takes several,
/// separated by a backtick (`Россия`Авто`). One Dart cannot parse or refuses
/// as unsafe is skipped (Mihomo uses Go regular expressions).
List<RegExp> _patterns(Object? raw) {
  if (raw is! String) return const <RegExp>[];
  final result = <RegExp>[];
  for (final part in raw.split('`')) {
    if (part.isEmpty) continue;
    try {
      final pattern = safeGroupFilter(part);
      if (pattern != null) result.add(pattern);
    } on FormatException {
      // Skipped.
    }
  }
  return result;
}

/// Servers of an `include-all` group, as the core picks them: those that
/// match any `filter` pattern (in the order of the patterns), without those
/// that match an `exclude-filter` pattern or have an `exclude-type`.
Iterable<String> _filtered(
    List<String> names, Map<String, dynamic> group, Map<String, String> types) {
  var result = names;
  final filters = _patterns(group['filter']);
  if (filters.isNotEmpty) {
    final picked = <String>{};
    for (final pattern in filters) {
      picked.addAll(result.where(pattern.hasMatch));
    }
    result = picked.toList();
  }
  final excludes = _patterns(group['exclude-filter']);
  final excludeType = group['exclude-type'];
  final excludedTypes = excludeType is String
      ? excludeType
          .split('|')
          .map((type) => type.trim().toLowerCase())
          .where((type) => type.isNotEmpty)
          .toSet()
      : const <String>{};
  return result
      .where((name) => !excludes.any((pattern) => pattern.hasMatch(name)))
      .where(
          (name) => !excludedTypes.contains(types[name]?.toLowerCase() ?? ''))
      .toList(growable: false);
}

String _groupType(Object? raw) => switch (raw?.toString().toLowerCase()) {
      'select' => 'Selector',
      'url-test' => 'URLTest',
      'fallback' => 'Fallback',
      'load-balance' => 'LoadBalance',
      'relay' => 'Relay',
      _ => 'Selector',
    };

String _proxyType(Object? raw) {
  final type = raw?.toString().toLowerCase() ?? '';
  return switch (type) {
    '' => 'Proxy',
    'ss' => 'Shadowsocks',
    'ssr' => 'ShadowsocksR',
    'socks5' => 'Socks5',
    _ => '${type[0].toUpperCase()}${type.substring(1)}',
  };
}
