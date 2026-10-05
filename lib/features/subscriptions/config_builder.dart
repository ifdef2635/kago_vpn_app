import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

class MihomoConfigBuilder {
  const MihomoConfigBuilder();

  Map<String, dynamic> build(String source,
      {String? secret, bool enableTun = true}) {
    final parsed = loadYaml(source);
    if (parsed is! YamlMap) {
      throw const FormatException(
          'Корень конфигурации Mihomo должен быть YAML-объектом.');
    }
    final config = _convertMap(parsed);
    if (config['proxies'] is! List && config['proxy-providers'] is! Map) {
      throw const FormatException(
          'В подписке не найдены proxies или proxy-providers.');
    }
    config.putIfAbsent('mixed-port', () => 7890);
    _lockToLoopback(config);
    config.putIfAbsent('mode', () => 'rule');
    config.putIfAbsent('log-level', () => 'info');
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
      throw const FormatException(
          'Для встроенного Android Mihomo задайте локальный HTTP controller: http://127.0.0.1:<port>.');
    }
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Активная конфигурация Mihomo повреждена.');
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
    _ensureAndroidDns(decoded);
    _lockToLoopback(decoded);
    decoded['external-controller'] = '${uri.host}:${uri.port}';
    if (secret == null || secret.isEmpty) {
      decoded.remove('secret');
    } else {
      decoded['secret'] = secret;
    }
    await file.writeAsString(jsonEncode(decoded), flush: true);
  }

  /// Android has no /etc/resolv.conf, and DNS queries hijacked from the TUN are
  /// answered only by Mihomo's own DNS. Without `dns.enable` every lookup fails
  /// (apps and proxy server hostnames alike), so turn it on when the
  /// subscription does not. A subscription that enables DNS is kept as is.
  static void _ensureAndroidDns(Map<String, dynamic> config) {
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
    'tls',
  ];

  static void _lockToLoopback(Map<String, dynamic> config) {
    config['allow-lan'] = false;
    config['bind-address'] = '127.0.0.1';
    for (final key in _dropped) {
      config.remove(key);
    }
  }

  Map<String, dynamic> _convertMap(YamlMap input) => <String, dynamic>{
        for (final entry in input.entries)
          if (entry.key is String) entry.key as String: _convert(entry.value),
      };

  dynamic _convert(dynamic value) {
    if (value is YamlMap) return _convertMap(value);
    if (value is YamlList) return value.map(_convert).toList(growable: false);
    return value;
  }
}
