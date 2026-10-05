import 'dart:convert';

import 'package:yaml/yaml.dart';
import '../../core/l10n/l10n.dart';

/// Normalizes common provider formats into a Mihomo-compatible YAML document.
class SubscriptionContentParser {
  const SubscriptionContentParser();

  String toMihomoConfig(String responseBody) {
    final original = responseBody.trim();
    if (original.isEmpty) {
      throw FormatException(tr('Подписка вернула пустой ответ.'));
    }
    for (final candidate in <String>[
      original,
      ..._decodedCandidates(original)
    ]) {
      if (_isMihomoDocument(candidate)) return candidate;
      final links = _parseShareLinks(candidate);
      if (links.isNotEmpty) return jsonEncode(_makeDocument(links));
    }
    throw FormatException(
        tr('Ответ не является Clash/Mihomo YAML или поддерживаемым списком ссылок VLESS/VMess/Trojan/SS/Hysteria2/TUIC.'));
  }

  Iterable<String> _decodedCandidates(String input) sync* {
    final compact = input.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 16 ||
        !RegExp(r'^[A-Za-z0-9_+/=-]+$').hasMatch(compact)) {
      return;
    }
    try {
      final decoded = _decodeBase64Text(compact);
      if (decoded.trim().isNotEmpty && decoded.trim() != input) {
        yield decoded.trim();
      }
    } on FormatException {
      // Plain YAML and URI lists are considered below.
    }
  }

  bool _isMihomoDocument(String candidate) {
    try {
      final root = loadYaml(candidate);
      return root is YamlMap &&
          (root['proxies'] is YamlList || root['proxy-providers'] is YamlMap);
    } on FormatException {
      return false;
    }
  }

  List<Map<String, dynamic>> _parseShareLinks(String body) {
    final result = <Map<String, dynamic>>[];
    for (final rawLine in body.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final scheme = _scheme(line);
      if (scheme == null) continue;
      final proxy = switch (scheme) {
        'vmess' => _parseVmess(line),
        'vless' => _parseVless(line),
        'trojan' => _parseTrojan(line),
        'ss' => _parseShadowsocks(line),
        'hysteria2' || 'hy2' => _parseHysteria2(line),
        'tuic' => _parseTuic(line),
        _ => null,
      };
      if (proxy != null) result.add(proxy);
    }
    final seen = <String>{};
    return result.where((proxy) => seen.add(proxy['name'] as String)).toList();
  }

  String? _scheme(String input) {
    final match = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://').firstMatch(input);
    return match?.group(1)?.toLowerCase();
  }

  Map<String, dynamic> _parseVless(String source) {
    final uri = Uri.parse(source);
    final id = Uri.decodeComponent(uri.userInfo);
    if (id.isEmpty) throw FormatException(tr('VLESS URI не содержит UUID.'));
    final proxy = <String, dynamic>{
      'name': _name(uri, 'VLESS ${uri.host}'),
      'type': 'vless',
      'server': _requireHost(uri),
      'port': _requirePort(uri),
      'uuid': id,
      'udp': true,
      'network': _network(uri.queryParameters['type']),
    };
    final query = uri.queryParameters;
    final security = query['security']?.toLowerCase() ?? 'tls';
    if (security != 'none') {
      proxy['tls'] = true;
      _addTls(proxy, query);
    }
    final flow = query['flow'];
    if (flow != null && flow.isNotEmpty) proxy['flow'] = flow;
    _addTransport(proxy, query);
    return proxy;
  }

  Map<String, dynamic> _parseTrojan(String source) {
    final uri = Uri.parse(source);
    if (uri.userInfo.isEmpty) {
      throw FormatException(tr('Trojan URI не содержит пароль.'));
    }
    final query = uri.queryParameters;
    final proxy = <String, dynamic>{
      'name': _name(uri, 'Trojan ${uri.host}'),
      'type': 'trojan',
      'server': _requireHost(uri),
      'port': _requirePort(uri),
      'password': Uri.decodeComponent(uri.userInfo),
      'udp': true,
      'sni': query['sni'] ?? query['peer'] ?? query['host'],
      'skip-cert-verify': _isTrue(query['allowInsecure'] ?? query['insecure']),
      'network': _network(query['type']),
    };
    if (proxy['sni'] == null) proxy.remove('sni');
    _addTransport(proxy, query);
    return proxy;
  }

  Map<String, dynamic> _parseVmess(String source) {
    final payload = source.substring('vmess://'.length).split('#').first;
    final decoded = _decodeBase64Text(payload);
    final data = jsonDecode(decoded);
    if (data is! Map<String, dynamic>) {
      throw FormatException(tr('VMess URI должен содержать JSON-профиль.'));
    }
    final server = _stringValue(data['add']);
    final id = _stringValue(data['id']);
    final port = _intValue(data['port']);
    if (server.isEmpty || id.isEmpty || port < 1 || port > 65535) {
      throw FormatException(
          tr('VMess URI содержит неполный адрес, порт или UUID.'));
    }
    final name = _fragmentName(source) ?? _stringValue(data['ps']);
    final proxy = <String, dynamic>{
      'name': name.isEmpty ? 'VMess $server' : name,
      'type': 'vmess',
      'server': server,
      'port': port,
      'uuid': id,
      'alterId': _intValue(data['aid']),
      'cipher': _stringValue(data['scy']).isEmpty
          ? 'auto'
          : _stringValue(data['scy']),
      'udp': true,
    };
    final security = _stringValue(data['tls']).toLowerCase();
    if (security.isNotEmpty && security != 'none') {
      proxy['tls'] = true;
      final sni = _stringValue(data['sni']);
      if (sni.isNotEmpty) proxy['servername'] = sni;
      proxy['skip-cert-verify'] = _isTrue(_stringValue(data['allowInsecure']));
    }
    final network = _network(_stringValue(data['net']));
    proxy['network'] = network;
    final query = <String, String>{
      'type': network,
      'host': _stringValue(data['host']),
      'path': _stringValue(data['path']),
    };
    _addTransport(proxy, query);
    return proxy;
  }

  Map<String, dynamic> _parseShadowsocks(String source) {
    var body = source.substring('ss://'.length);
    final fragmentIndex = body.indexOf('#');
    final fragment =
        fragmentIndex < 0 ? null : body.substring(fragmentIndex + 1);
    if (fragmentIndex >= 0) body = body.substring(0, fragmentIndex);
    final queryIndex = body.indexOf('?');
    if (queryIndex >= 0) body = body.substring(0, queryIndex);
    if (!body.contains('@')) {
      try {
        body = _decodeBase64Text(body);
      } on FormatException {
        throw FormatException(
            tr('Shadowsocks URI содержит неверную Base64-строку.'));
      }
    }
    final separator = body.lastIndexOf('@');
    if (separator <= 0 || separator == body.length - 1) {
      throw FormatException(
          tr('Shadowsocks URI должен содержать method:password@host:port.'));
    }
    final credentials = body.substring(0, separator);
    final address = Uri.parse('ss://${body.substring(separator + 1)}');
    final decodedCredentials = credentials.contains(':')
        ? credentials
        : _decodeBase64Text(credentials);
    final credentialParts = decodedCredentials.split(':');
    if (credentialParts.length < 2) {
      throw FormatException(
          tr('Shadowsocks URI не содержит method/password.'));
    }
    final name = fragment == null || fragment.isEmpty
        ? 'SS ${address.host}'
        : Uri.decodeComponent(fragment);
    return <String, dynamic>{
      'name': name,
      'type': 'ss',
      'server': _requireHost(address),
      'port': _requirePort(address),
      'cipher': Uri.decodeComponent(credentialParts.first),
      'password': Uri.decodeComponent(credentialParts.sublist(1).join(':')),
      'udp': true,
    };
  }

  Map<String, dynamic> _parseHysteria2(String source) {
    final uri = Uri.parse(source);
    if (uri.userInfo.isEmpty) {
      throw FormatException(tr('Hysteria2 URI не содержит пароль.'));
    }
    final query = uri.queryParameters;
    final proxy = <String, dynamic>{
      'name': _name(uri, 'Hysteria2 ${uri.host}'),
      'type': 'hysteria2',
      'server': _requireHost(uri),
      'port': _requirePort(uri),
      'password': Uri.decodeComponent(uri.userInfo),
      'skip-cert-verify': _isTrue(query['insecure']),
      'udp': true,
    };
    final sni = query['sni'] ?? query['peer'];
    if (sni != null && sni.isNotEmpty) proxy['sni'] = sni;
    final obfs = query['obfs'];
    if (obfs != null && obfs.isNotEmpty) {
      proxy['obfs'] = obfs;
      final obfsPassword = query['obfs-password'];
      if (obfsPassword != null) proxy['obfs-password'] = obfsPassword;
    }
    return proxy;
  }

  Map<String, dynamic> _parseTuic(String source) {
    final uri = Uri.parse(source);
    final credentials = uri.userInfo.split(':');
    if (credentials.length < 2) {
      throw FormatException(tr('TUIC URI должен содержать UUID и пароль.'));
    }
    final query = uri.queryParameters;
    final proxy = <String, dynamic>{
      'name': _name(uri, 'TUIC ${uri.host}'),
      'type': 'tuic',
      'server': _requireHost(uri),
      'port': _requirePort(uri),
      'uuid': Uri.decodeComponent(credentials.first),
      'password': Uri.decodeComponent(credentials.sublist(1).join(':')),
      'congestion-controller': query['congestion_control'] ??
          query['congestion-controller'] ??
          'bbr',
      'udp-relay-mode':
          query['udp_relay_mode'] ?? query['udp-relay-mode'] ?? 'native',
      'skip-cert-verify': _isTrue(query['allowInsecure'] ?? query['insecure']),
      'udp': true,
    };
    final sni = query['sni'] ?? query['peer'];
    if (sni != null && sni.isNotEmpty) proxy['sni'] = sni;
    if (query['alpn'] case final alpn? when alpn.isNotEmpty) {
      proxy['alpn'] = alpn.split(',');
    }
    return proxy;
  }

  Map<String, dynamic> _makeDocument(List<Map<String, dynamic>> proxies) {
    final names = proxies.map((proxy) => proxy['name'] as String).toList();
    const group = 'KaGo VPN';
    return <String, dynamic>{
      'mixed-port': 7890,
      'mode': 'rule',
      'log-level': 'info',
      'proxies': proxies,
      'proxy-groups': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': group,
          'type': 'select',
          'proxies': <String>[...names, 'DIRECT'],
        }
      ],
      'rules': <String>['MATCH,$group'],
    };
  }

  String _requireHost(Uri uri) {
    if (uri.host.isEmpty) {
      throw FormatException(tr('URI не содержит сервер.'));
    }
    return uri.host;
  }

  int _requirePort(Uri uri) {
    final port = uri.port;
    if (port < 1 || port > 65535) {
      throw FormatException(tr('URI содержит неверный порт.'));
    }
    return port;
  }

  // Uri.fragment keeps percent-encoding ("%F0%9F%87%A9 %D0%93..."), so share-link
  // names must be decoded or servers show up as escaped gibberish.
  String _name(Uri uri, String fallback) {
    final name = _decodeFragment(uri.fragment).trim();
    return name.isEmpty ? fallback : name;
  }

  String? _fragmentName(String source) {
    final index = source.indexOf('#');
    if (index < 0) return null;
    final value = _decodeFragment(source.substring(index + 1));
    return value.isEmpty ? null : value;
  }

  String _decodeFragment(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    } on FormatException {
      return value;
    }
  }

  void _addTls(Map<String, dynamic> proxy, Map<String, String> query) {
    final sni = query['sni'] ?? query['peer'];
    if (sni != null && sni.isNotEmpty) proxy['servername'] = sni;
    final fingerprint = query['fp'];
    if (fingerprint != null && fingerprint.isNotEmpty) {
      proxy['client-fingerprint'] = fingerprint;
    }
    proxy['skip-cert-verify'] =
        _isTrue(query['allowInsecure'] ?? query['insecure']);
    if (query['security']?.toLowerCase() == 'reality') {
      final publicKey = query['pbk'] ?? query['publicKey'];
      final shortId = query['sid'] ?? query['shortId'];
      proxy['reality-opts'] = <String, String>{
        if (publicKey != null && publicKey.isNotEmpty) 'public-key': publicKey,
        if (shortId != null && shortId.isNotEmpty) 'short-id': shortId,
      };
    }
  }

  String _network(String? value) {
    final network = (value ?? 'tcp').toLowerCase();
    return switch (network) {
      'ws' || 'grpc' || 'h2' || 'http' || 'tcp' => network,
      'raw' => 'tcp',
      _ => 'tcp',
    };
  }

  void _addTransport(Map<String, dynamic> proxy, Map<String, String> query) {
    switch (_network(query['type'])) {
      case 'ws':
        final headers = <String, String>{};
        final host = query['host'];
        if (host != null && host.isNotEmpty) headers['Host'] = host;
        proxy['ws-opts'] = <String, dynamic>{
          'path': query['path'] ?? '/',
          if (headers.isNotEmpty) 'headers': headers,
        };
        break;
      case 'grpc':
        final serviceName = query['serviceName'] ?? query['service-name'];
        proxy['grpc-opts'] = <String, dynamic>{
          if (serviceName != null && serviceName.isNotEmpty)
            'grpc-service-name': serviceName,
        };
        break;
      case 'h2':
        final host = query['host'];
        proxy['h2-opts'] = <String, dynamic>{
          'path': query['path'] ?? '/',
          if (host != null && host.isNotEmpty) 'host': host.split(','),
        };
        break;
    }
  }

  bool _isTrue(String? value) => value == '1' || value?.toLowerCase() == 'true';

  String _stringValue(Object? value) => value?.toString() ?? '';

  int _intValue(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

  String _decodeBase64Text(String input) {
    final standard = input.replaceAll('-', '+').replaceAll('_', '/');
    return utf8.decode(base64.decode(base64.normalize(standard)));
  }
}
