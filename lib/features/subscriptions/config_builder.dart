import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';
import '../../core/l10n/l10n.dart';

class MihomoConfigBuilder {
  const MihomoConfigBuilder();

  Map<String, dynamic> build(String source,
      {String? secret, bool enableTun = true}) {
    final parsed = loadYaml(source);
    if (parsed is! YamlMap) {
      throw FormatException(
          tr('Корень конфигурации Mihomo должен быть YAML-объектом.'));
    }
    final config = _convertMap(parsed);
    if (config['proxies'] is! List && config['proxy-providers'] is! Map) {
      throw FormatException(
          tr('В подписке не найдены proxies или proxy-providers.'));
    }
    config.putIfAbsent('mixed-port', () => 7890);
    _lockToLoopback(config);
    config.putIfAbsent('mode', () => 'rule');
    config.putIfAbsent('log-level', () => 'info');
    _performanceDefaults(config);
    config['external-controller'] = '127.0.0.1:9090';
    if (secret != null && secret.isNotEmpty) config['secret'] = secret;
    if (enableTun) {
      final existing = config['tun'];
      final tun =
          existing is Map<String, dynamic> ? existing : <String, dynamic>{};
      tun['enable'] = true;
      tun.putIfAbsent('stack', () => 'system');
      tun.putIfAbsent('auto-route', () => true);
      tun.putIfAbsent('auto-detect-interface', () => true);
      config['tun'] = tun;
    }
    return config;
  }

  String encode(String source, {String? secret, bool enableTun = true}) =>
      jsonEncode(build(source, secret: secret, enableTun: enableTun));

  Future<File> activeConfigFile() async {
    final directory = await getApplicationSupportDirectory();
    final profiles =
        Directory('${directory.path}${Platform.pathSeparator}profiles');
    return File('${profiles.path}${Platform.pathSeparator}active_config.yaml');
  }

  Future<File> writeConfig(String source,
      {String? secret, bool enableTun = true}) async {
    final file = await activeConfigFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
        encode(source, secret: secret, enableTun: enableTun),
        flush: true);
    return file;
  }

  Future<void> prepareAndroidTunnelConfig(File file,
      {required String endpoint, String? secret}) async {
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'http' ||
        !<String>['127.0.0.1', 'localhost'].contains(uri.host.toLowerCase())) {
      throw FormatException(tr(
          'Для встроенного Android Mihomo задайте локальный HTTP controller: http://127.0.0.1:<port>.'));
    }
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(tr('Активная конфигурация Mihomo повреждена.'));
    }
    final tunValue = decoded['tun'];
    final Map<String, dynamic> tun;
    if (tunValue is Map<String, dynamic>) {
      tun = tunValue;
    } else {
      tun = <String, dynamic>{};
      decoded['tun'] = tun;
    }
    // Android VpnService owns routes and the TUN fd; the Go adapter attaches it to Mihomo.
    // Do not let Mihomo create a second OS TUN or rewrite the routes itself.
    tun['enable'] = false;
    tun['auto-route'] = false;
    // The embedded core has no gVisor: a panel template with `gvisor` or
    // `mixed` would fail with "gVisor is not included in this build".
    tun['stack'] = 'system';
    ensureDns(decoded);
    _performanceDefaults(decoded);
    _hardenAndroid(decoded);
    _lockToLoopback(decoded);
    decoded['external-controller'] = '${uri.host}:${uri.port}';
    if (secret == null || secret.isEmpty) {
      decoded.remove('secret');
    } else {
      decoded['secret'] = secret;
    }
    await file.writeAsString(jsonEncode(decoded), flush: true);
  }

  /// DNS queries hijacked from a TUN (Android, macOS "all traffic") are
  /// answered only by Mihomo's own DNS. Without `dns.enable` every lookup fails
  /// (apps and proxy server hostnames alike), so turn it on when the
  /// subscription does not. A subscription that enables DNS is kept as is.
  static void ensureDns(Map<String, dynamic> config) {
    final existing = config['dns'];
    if (existing is Map<String, dynamic> && existing['enable'] == true) return;
    config['dns'] = <String, dynamic>{
      'enable': true,
      'ipv6': false,
      'enhanced-mode': 'fake-ip',
      'fake-ip-range': '198.18.0.1/16',
      'fake-ip-filter': <String>[
        '*.lan',
        '+.local',
        '+.msftconnecttest.com',
        '+.msftncsi.com',
        'time.*.com',
        '+.ntp.org',
      ],
      'default-nameserver': <String>['1.1.1.1', '8.8.8.8'],
      'nameserver': <String>[
        'https://1.1.1.1/dns-query',
        'https://8.8.8.8/dns-query',
      ],
    };
  }

  /// Faster connections, unless the subscription says otherwise:
  /// `tcp-concurrent` dials all resolved IPs of a host at once and keeps the
  /// first that answers; `unified-delay` measures node latency without the
  /// TLS/handshake overhead (as FlClash does), so numbers are comparable.
  static void _performanceDefaults(Map<String, dynamic> config) {
    config.putIfAbsent('tcp-concurrent', () => true);
    config.putIfAbsent('unified-delay', () => true);
  }

  static const _localProxyPorts = <String>[
    'port',
    'socks-port',
    'redir-port',
    'tproxy-port',
  ];

  /// On Android all traffic goes through the VpnService TUN, so the local
  /// HTTP/SOCKS ports are not needed. Left open they are an unauthenticated
  /// proxy for every app on the phone: any app could find the port on
  /// 127.0.0.1, see that a VPN is running and learn the VPN exit address.
  /// `info` logs list every visited domain; keep only warnings and errors.
  static void _hardenAndroid(Map<String, dynamic> config) {
    config['mixed-port'] = 0;
    for (final key in _localProxyPorts) {
      config.remove(key);
    }
    final level = config['log-level'];
    if (level != 'error' && level != 'silent') config['log-level'] = 'warning';
    // PROCESS-NAME rules (the subscription's routing of Russian apps) need
    // the package lookup; `off` would silently skip them.
    if (config['find-process-mode'] != 'always') {
      config['find-process-mode'] = 'strict';
    }
  }

  /// Subscription YAML is untrusted. It must not expose the local proxy or the
  /// controller to other machines, start extra listeners, or make the core
  /// download/serve an external web UI.
  static const _dropped = <String>[
    'listeners',
    'tunnels',
    'authentication',
    'skip-auth-prefixes',
    'lan-allowed-ips',
    'lan-disallowed-ips',
    'external-ui',
    'external-ui-name',
    'external-ui-url',
    'external-controller-tls',
    'external-controller-unix',
    'external-controller-pipe',
    'external-controller-cors',
    // Answers DNS on the controller port without the secret.
    'external-doh-server',
    'tls',
    // Inbound servers: a subscription must not make the core accept connections.
    'tuic-server',
    'ss-config',
    'vmess-config',
  ];

  /// Applied to every config before the core starts (also re-applied by the
  /// desktop process manager to the file it reads back from disk).
  static void lockToLoopback(Map<String, dynamic> config) =>
      _lockToLoopback(config);

  static void _lockToLoopback(Map<String, dynamic> config) {
    config['allow-lan'] = false;
    config['bind-address'] = '127.0.0.1';
    for (final key in _dropped) {
      config.remove(key);
    }
    // Empty allow-origins means "any origin" in the core's CORS library:
    // name one that never matches, so no web page can read controller
    // replies, and refuse Private Network Access preflights.
    config['external-controller-cors'] = <String, dynamic>{
      'allow-origins': const <String>['https://controller.invalid'],
      'allow-private-network': false,
    };
    // The macOS TUN core runs as root: a subscription must not set the clock.
    final ntp = config['ntp'];
    if (ntp is Map<String, dynamic>) {
      ntp['write-to-system'] = false;
    } else if (ntp != null) {
      config.remove('ntp');
    }
    // An HTTP provider writes what it downloads to its `path`, which may be
    // any file in the core's folder — the active config included. Without a
    // path the core stores it under a hash of the URL.
    for (final key in const <String>['rule-providers', 'proxy-providers']) {
      final providers = config[key];
      if (providers is! Map<String, dynamic>) continue;
      for (final provider in providers.values) {
        if (provider is Map<String, dynamic> && provider['type'] != 'file') {
          provider.remove('path');
        }
      }
    }
    // A DNS server on 0.0.0.0:53 would answer the whole LAN (the macOS TUN
    // core runs as root and could bind it). Hijacked queries need no listener.
    final dns = config['dns'];
    if (dns is Map<String, dynamic>) dns.remove('listen');
  }

  /// YAML aliases are shared nodes; copying them could blow a small
  /// "billion laughs" document up exponentially. A real profile has far
  /// fewer nodes than this.
  static const maxNodes = 500000;

  Map<String, dynamic> _convertMap(YamlMap input) =>
      _NodeBudget(maxNodes).map(input);
}

class _NodeBudget {
  _NodeBudget(this._left);
  int _left;

  void _spend() {
    if (--_left < 0) {
      throw FormatException(tr('Профиль подписки слишком большой.'));
    }
  }

  Map<String, dynamic> map(YamlMap input) {
    _spend();
    return <String, dynamic>{
      for (final entry in input.entries)
        if (entry.key is String) entry.key as String: value(entry.value),
    };
  }

  dynamic value(dynamic node) {
    _spend();
    if (node is YamlMap) return map(node);
    if (node is YamlList) return node.map(value).toList(growable: false);
    return node;
  }
}
