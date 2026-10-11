/// Routes of the Android VpnService from the subscription's `tun` section.
///
/// On Android the VpnService owns the routes (the core runs with
/// `auto-route: false`), so `tun.route-address` and
/// `tun.route-exclude-address` of the config would be ignored. A KAGO
/// subscription excludes the local networks (192.168.0.0/16, 10.0.0.0/8…):
/// the printer, the router page and casting must not go into the VPN. Android
/// before 13 cannot exclude a route, so the excluded ranges are cut out of
/// the included ones here, and the service adds what is left.
abstract final class AndroidRoutes {
  /// Key in the config's `tun` the service reads (the core ignores it).
  static const configKey = 'kago-android-routes';

  /// The VpnService's own networks (`KaGoVpnService`: address and in-tunnel
  /// DNS). They always stay inside the tunnel.
  static const tunnelIpv4 = '172.19.0.0/30';
  static const tunnelIpv6 = 'fdfe:dcba:9876::/126';

  /// More routes than this (an exclusion list of single addresses): the
  /// whole traffic goes into the tunnel, as without the list.
  static const maxRoutes = 1500;

  /// Writes the routes into `tun[configKey]`; removes the key when the
  /// subscription sets none (the service then routes everything).
  static void apply(Map<String, dynamic> config) {
    final tun = config['tun'];
    if (tun is! Map<String, dynamic>) return;
    final routes = compute(config);
    if (routes == null) {
      tun.remove(configKey);
    } else {
      tun[configKey] = routes;
    }
  }

  /// The routes for [config], or null for "everything" (0.0.0.0/0, ::/0).
  static List<String>? compute(Map<String, dynamic> config) {
    final tun = config['tun'];
    if (tun is! Map<String, dynamic>) return null;
    final ipv6 = config['ipv6'] == true;
    final included = _prefixes(tun, const <String>[
      'route-address',
      'inet4-route-address',
      'inet6-route-address',
    ]);
    final excluded = _prefixes(tun, const <String>[
      'route-exclude-address',
      'inet4-route-exclude-address',
      'inet6-route-exclude-address',
    ]);
    if (included.isEmpty && excluded.isEmpty) return null;

    final kept = <IpPrefix>[
      IpPrefix.parse(tunnelIpv4)!,
      IpPrefix.parse(tunnelIpv6)!,
      ..._fakeIpRanges(config),
    ];
    final targets = included.isEmpty
        ? <IpPrefix>[IpPrefix.parse('0.0.0.0/0')!, IpPrefix.parse('::/0')!]
        : <IpPrefix>[...included, ...kept];
    // The tunnel's own addresses and the fake IPs of the core's DNS are never
    // excluded: without them no name would resolve.
    final cuts = <IpPrefix>[
      for (final range in excluded) ...range.without(kept),
    ];
    final routes = <IpPrefix>[];
    for (final target in targets) {
      if (target.v6 && !ipv6) continue;
      routes.addAll(target.without(cuts));
      if (routes.length > maxRoutes) return null;
    }
    if (!routes.any((route) => !route.v6)) return null;
    final unique = <String>{};
    return <String>[
      for (final route in routes)
        if (unique.add(route.toString())) route.toString(),
    ];
  }

  static List<IpPrefix> _prefixes(Map<String, dynamic> tun, List<String> keys) {
    final result = <IpPrefix>[];
    for (final key in keys) {
      final list = tun[key];
      if (list is! List<dynamic>) continue;
      for (final item in list) {
        final prefix = item is String ? IpPrefix.parse(item) : null;
        if (prefix != null) result.add(prefix);
      }
    }
    return result;
  }

  static List<IpPrefix> _fakeIpRanges(Map<String, dynamic> config) {
    final dns = config['dns'];
    final map = dns is Map<String, dynamic> ? dns : const <String, dynamic>{};
    final v4 = map['fake-ip-range'];
    final v6 = map['fake-ip-range6'];
    return <IpPrefix>[
      IpPrefix.parse(v4 is String && v4.isNotEmpty ? v4 : '198.18.0.1/16') ??
          IpPrefix.parse('198.18.0.0/16')!,
      if (v6 is String && IpPrefix.parse(v6) != null) IpPrefix.parse(v6)!,
    ];
  }
}

/// An IPv4 or IPv6 network (`192.168.0.0/16`), normalised to its first
/// address.
class IpPrefix {
  IpPrefix._(this.v6, BigInt address, this.length)
      : address = address & _mask(v6, length);

  final bool v6;
  final BigInt address;
  final int length;

  int get bits => v6 ? 128 : 32;

  static BigInt _mask(bool v6, int length) {
    final bits = v6 ? 128 : 32;
    final all = (BigInt.one << bits) - BigInt.one;
    return all ^ ((BigInt.one << (bits - length)) - BigInt.one);
  }

  /// `a.b.c.d/n`, `x:y::z/n` or a single address; null when invalid.
  static IpPrefix? parse(String text) {
    final parts = text.trim().split('/');
    if (parts.length > 2 || parts.first.isEmpty) return null;
    try {
      final v6 = parts.first.contains(':');
      final bytes = v6
          ? Uri.parseIPv6Address(parts.first)
          : Uri.parseIPv4Address(parts.first);
      var value = BigInt.zero;
      for (final byte in bytes) {
        value = (value << 8) | BigInt.from(byte);
      }
      final bits = v6 ? 128 : 32;
      final length = parts.length == 2 ? int.parse(parts[1]) : bits;
      if (length < 0 || length > bits) return null;
      return IpPrefix._(v6, value, length);
    } on FormatException {
      return null;
    }
  }

  bool contains(IpPrefix other) =>
      v6 == other.v6 &&
      length <= other.length &&
      (other.address & _mask(v6, length)) == address;

  bool overlaps(IpPrefix other) => contains(other) || other.contains(this);

  /// This network without [cuts]: the smallest set of networks that covers
  /// the rest.
  List<IpPrefix> without(List<IpPrefix> cuts) {
    final relevant = cuts.where(overlaps).toList();
    if (relevant.isEmpty) return <IpPrefix>[this];
    if (relevant.any((cut) => cut.contains(this))) return const <IpPrefix>[];
    final half = BigInt.one << (bits - length - 1);
    return <IpPrefix>[
      ...IpPrefix._(v6, address, length + 1).without(relevant),
      ...IpPrefix._(v6, address + half, length + 1).without(relevant),
    ];
  }

  @override
  String toString() {
    if (!v6) {
      final octets = <int>[
        for (var shift = 24; shift >= 0; shift -= 8)
          ((address >> shift) & BigInt.from(255)).toInt(),
      ];
      return '${octets.join('.')}/$length';
    }
    final groups = <String>[
      for (var shift = 112; shift >= 0; shift -= 16)
        ((address >> shift) & BigInt.from(0xffff)).toInt().toRadixString(16),
    ];
    return '${groups.join(':')}/$length';
  }
}
