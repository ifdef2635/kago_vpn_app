class ProxyNode {
  const ProxyNode({required this.name, required this.type, this.delay});
  final String name;
  final String type;

  /// Last latency (ms) the core measured for this node. Null: never tested,
  /// 0: the last test failed.
  final int? delay;

  bool get isGroup => const <String>{
        'selector',
        'urltest',
        'fallback',
        'loadbalance',
        'relay',
      }.contains(type.toLowerCase());

  factory ProxyNode.fromJson(String name, Map<String, dynamic>? json) {
    final history = json?['history'];
    int? delay;
    if (history is List<dynamic> && history.isNotEmpty) {
      final last = history.last;
      if (last is Map<String, dynamic>) {
        delay = (last['delay'] as num?)?.toInt();
      }
    }
    return ProxyNode(
        name: name, type: json?['type'] as String? ?? 'Proxy', delay: delay);
  }
}

class ProxyGroup {
  const ProxyGroup(
      {required this.name,
      required this.type,
      required this.nodes,
      this.selected,
      this.description});
  final String name;
  final String type;
  final List<ProxyNode> nodes;
  final String? selected;
  final String? description;

  /// Mihomo only accepts a manual choice for `Selector` groups; url-test,
  /// fallback and load-balance groups pick their node themselves.
  bool get isSelectable => type.toLowerCase() == 'selector';

  factory ProxyGroup.fromJson(String name, Map<String, dynamic> json,
      [Map<String, dynamic> allProxies = const <String, dynamic>{}]) {
    final names = (json['all'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>();
    return ProxyGroup(
      name: name,
      type: json['type'] as String? ?? 'Proxy',
      nodes: names.map((node) {
        final raw = allProxies[node];
        return ProxyNode.fromJson(node, raw is Map<String, dynamic> ? raw : null);
      }).toList(growable: false),
      selected: json['now'] as String?,
      description: json['description'] as String?,
    );
  }
}

class ActiveConnection {
  const ActiveConnection(
      {required this.id,
      required this.host,
      required this.destination,
      required this.network,
      required this.download,
      required this.upload,
      required this.rule,
      required this.chain});
  final String id;
  final String host;
  final String destination;
  final String network;
  final int download;
  final int upload;
  final String rule;
  final String chain;

  factory ActiveConnection.fromJson(Map<String, dynamic> json) {
    final metadata =
        json['metadata'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final chains = (json['chains'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .toList();
    return ActiveConnection(
      id: json['id'] as String? ?? '',
      host:
          metadata['host'] as String? ?? metadata['sourceIP'] as String? ?? '—',
      destination: metadata['destinationIP'] as String? ??
          metadata['destinationPort']?.toString() ??
          '—',
      network: metadata['network'] as String? ?? 'TCP',
      download: (json['download'] as num?)?.toInt() ?? 0,
      upload: (json['upload'] as num?)?.toInt() ?? 0,
      rule: json['rule'] as String? ?? '—',
      chain: chains.join(' → '),
    );
  }
}

/// One `/connections` poll: the live sessions plus cumulative traffic counters.
/// Speeds are bytes per second, derived from two consecutive polls.
class ConnectionsSnapshot {
  const ConnectionsSnapshot(
      {required this.connections,
      this.downloadTotal = 0,
      this.uploadTotal = 0,
      this.downloadSpeed = 0,
      this.uploadSpeed = 0});
  final List<ActiveConnection> connections;
  final int downloadTotal;
  final int uploadTotal;
  final int downloadSpeed;
  final int uploadSpeed;

  factory ConnectionsSnapshot.fromJson(Map<String, dynamic> json) =>
      ConnectionsSnapshot(
        connections: (json['connections'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ActiveConnection.fromJson)
            .toList(growable: false),
        downloadTotal: (json['downloadTotal'] as num?)?.toInt() ?? 0,
        uploadTotal: (json['uploadTotal'] as num?)?.toInt() ?? 0,
      );

  ConnectionsSnapshot withSpeed({required int download, required int upload}) =>
      ConnectionsSnapshot(
          connections: connections,
          downloadTotal: downloadTotal,
          uploadTotal: uploadTotal,
          downloadSpeed: download,
          uploadSpeed: upload);
}

class SubscriptionProfile {
  const SubscriptionProfile(
      {required this.name,
      required this.url,
      this.uploadBytes = 0,
      this.downloadBytes = 0,
      this.totalBytes = 0,
      this.expireAt});
  final String name;
  final String url;
  final int uploadBytes;
  final int downloadBytes;
  final int totalBytes;
  final DateTime? expireAt;
  int get usedBytes => uploadBytes + downloadBytes;
  double? get usage =>
      totalBytes <= 0 ? null : (usedBytes / totalBytes).clamp(0, 1);
}

String formatSpeed(int bytesPerSecond) => '${formatBytes(bytesPerSecond)}/с';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  const units = <String>['КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes.toDouble();
  var unit = -1;
  do {
    value /= 1024;
    unit++;
  } while (value >= 1024 && unit < units.length - 1);
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}
