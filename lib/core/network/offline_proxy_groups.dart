import 'dart:convert';

import '../../features/subscriptions/config_builder.dart';
import '../models/mihomo_models.dart';

/// Servers and groups of the saved profile, read from its config file. Used
/// while the core is not running, when the controller cannot be asked.
Future<List<ProxyGroup>> loadOfflineProxyGroups() async {
  final file = await const MihomoConfigBuilder().activeConfigFile();
  if (!await file.exists()) return const <ProxyGroup>[];
  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) return const <ProxyGroup>[];
  return proxyGroupsFromConfig(decoded);
}

/// Builds the same group/node model the controller returns, from a Mihomo config.
/// Which node is selected is unknown without the core, so `selected` is null.
List<ProxyGroup> proxyGroupsFromConfig(Map<String, dynamic> config) {
  final rawGroups = config['proxy-groups'];
  if (rawGroups is! List<dynamic>) return const <ProxyGroup>[];

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
      final extra =
          _filtered(proxyNames, item).where((n) => !names.contains(n)).toList();
      names.addAll(extra);
    }
    groups.add(ProxyGroup(
      name: name,
      type: groupTypes[name] ?? 'Selector',
      nodes: names
          .map((node) => ProxyNode(
              name: node, type: groupTypes[node] ?? proxyTypes[node] ?? 'Proxy'))
          .toList(growable: false),
      description: item['description'] as String?,
    ));
  }
  return groups;
}

Iterable<String> _filtered(List<String> names, Map<String, dynamic> group) {
  Iterable<String> result = names;
  final filter = group['filter'];
  final exclude = group['exclude-filter'];
  try {
    if (filter is String && filter.isNotEmpty) {
      final pattern = RegExp(filter);
      result = result.where(pattern.hasMatch);
    }
    if (exclude is String && exclude.isNotEmpty) {
      final pattern = RegExp(exclude);
      result = result.where((name) => !pattern.hasMatch(name));
    }
  } on FormatException {
    // Mihomo uses Go regular expressions; keep the unfiltered list if Dart
    // cannot parse one.
  }
  return result.toList(growable: false);
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
