import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import 'mihomo_windows_core_updater.dart';
import 'mihomo_windows_system_proxy.dart';

/// Mihomo shipped inside the macOS app bundle (`Contents/Resources/mihomo`, a
/// universal arm64 + x86_64 binary added by the CI build and signed with the
/// app). It is updated together with the app, like the Android core.
///
/// The system proxy covers only apps that honour it (Safari, Chrome);
/// Telegram, games and most native apps connect directly. "All traffic" (TUN)
/// needs a root core, so — as FlClashX and Clash Verge do — a copy of the
/// bundled core is made setuid root once, after the administrator password.
abstract final class MihomoMacosCore {
  static const tunKey = 'kago.macos.tun';
  static const _pidKey = 'kago.macos.core.pid';
  static const _authorizedHashKey = 'kago.macos.core.authorizedSha256';
  static const _bundledHashKey = 'kago.macos.core.bundledSha256';

  /// `…/KaGo VPN.app/Contents/MacOS/KaGo VPN` -> `…/Contents/Resources/mihomo`.
  static File get executable {
    final macOsDir = File(Platform.resolvedExecutable).parent;
    return File('${macOsDir.parent.path}/Resources/mihomo');
  }

  static Future<MihomoCoreInstall?> installed() async {
    final file = executable;
    if (!await file.exists()) return null;
    return MihomoCoreInstall(
        version: MihomoPinnedCore.version, executable: file, updated: false);
  }

  /// The setuid-root copy: `~/Library/Application Support/net.usekago.app/core/mihomo`.
  static Future<File> privilegedFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/core/mihomo');
  }

  /// "All traffic through VPN" (TUN) is on by default.
  static Future<bool> tunEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(tunKey) ?? true;

  static Future<void> setTunEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(tunKey, value);

  /// `stat -f '%Su:%Sg %Sp'` of a core that may run as root: owned by
  /// root:admin, setuid, not writable by group or others.
  static bool isPrivilegedStat(String output) {
    final parts = output.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts[0] != 'root:admin') return false;
    final mode = parts[1];
    return mode.length == 10 &&
        mode[3] == 's' &&
        mode[5] != 'w' &&
        mode[8] != 'w';
  }

  /// SHA-256 of the bundled core, cached by size and modification time
  /// (hashing the ~60 MB universal binary takes a moment).
  static Future<String> _bundledHash() async {
    final prefs = await SharedPreferences.getInstance();
    final stat = await executable.stat();
    final stamp = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    final cached = prefs.getString(_bundledHashKey);
    if (cached != null && cached.startsWith('$stamp=')) {
      return cached.substring(stamp.length + 1);
    }
    final hash = (await sha256.bind(executable.openRead()).first).toString();
    await prefs.setString(_bundledHashKey, '$stamp=$hash');
    return hash;
  }

  /// The root copy, if it exists and holds the same core as the app bundle.
  /// Compared by content, so an app update with the same core version does
  /// not ask for the password again; a new core does. The copy is root-owned,
  /// so only root can change it after it was hashed.
  static Future<File?> authorizedCore() async {
    if (!Platform.isMacOS) return null;
    final file = await privilegedFile();
    if (!await file.exists() || !await executable.exists()) return null;
    final result = await Process.run(
        '/usr/bin/stat', <String>['-f', '%Su:%Sg %Sp', file.path]);
    if (result.exitCode != 0 || !isPrivilegedStat('${result.stdout}')) {
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    final authorized = prefs.getString(_authorizedHashKey);
    return authorized != null && authorized == await _bundledHash()
        ? file
        : null;
  }

  static String shellQuote(String value) =>
      "'${value.replaceAll("'", r"'\''")}'";

  /// AppleScript `do shell script … with administrator privileges` for [command].
  static String adminScript(String command, String prompt) {
    String escape(String value) =>
        value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return 'do shell script "${escape(command)}" '
        'with prompt "${escape(prompt)}" with administrator privileges';
  }

  /// Makes the root copy (one macOS password prompt). Only members of the
  /// `admin` group may run it (mode 4750), so a standard account on the same
  /// Mac cannot start a root process with it. Returns null on success, or why
  /// it failed.
  static Future<String?> authorize() async {
    final groups = await Process.run('/usr/bin/id', const <String>['-Gn']);
    if (!'${groups.stdout}'.split(RegExp(r'\s+')).contains('admin')) {
      return tr('Нужна учётная запись администратора macOS.');
    }
    final file = await privilegedFile();
    await file.parent.create(recursive: true);
    final hash = await _bundledHash();
    final target = shellQuote(file.path);
    final command = <String>[
      'rm -f $target',
      'cp -p ${shellQuote(executable.path)} $target',
      'xattr -c $target',
      'chown root:admin $target',
      'chmod 4750 $target',
    ].join(' && ');
    final result = await Process.run('/usr/bin/osascript', <String>[
      '-e',
      adminScript(command,
          tr('KaGo VPN включает режим «Весь трафик через VPN». Это нужно один раз.')),
    ]);
    if (result.exitCode == 0) {
      final copied =
          (await sha256.bind(file.openRead()).first).toString() == hash;
      if (!copied) return tr('Не удалось скопировать ядро.');
      await (await SharedPreferences.getInstance())
          .setString(_authorizedHashKey, hash);
      return null;
    }
    final error = '${result.stderr}'.trim();
    return error.contains('-128') ? tr('Отменено.') : error;
  }

  /// The core to run and whether to turn TUN on. Asks for the password at
  /// most once: if the user cancels, TUN is switched off in settings and the
  /// app keeps working through the system proxy.
  static Future<({File binary, bool tun})> resolve(
      void Function(String) log) async {
    var core = await authorizedCore();
    final wantTun = await tunEnabled();
    if (core == null && wantTun) {
      final error = await authorize();
      if (error == null) {
        core = await authorizedCore();
      } else {
        await setTunEnabled(false);
        log(tr('Режим «Весь трафик через VPN» выключен: {error}',
            <String, Object?>{'error': error}));
      }
    }
    // Once authorized, the root core runs in both modes, so its cache and
    // rule files in the profile folder stay writable by one owner.
    return (binary: core ?? executable, tun: core != null && wantTun);
  }

  static Future<void> rememberPid(int? pid) async {
    final prefs = await SharedPreferences.getInstance();
    if (pid == null) {
      await prefs.remove(_pidKey);
    } else {
      await prefs.setInt(_pidKey, pid);
    }
  }

  /// A core left running by a crashed app keeps the ports and, as root, the
  /// TUN routes; stop it before starting a new one.
  static Future<void> killStale() async {
    final prefs = await SharedPreferences.getInstance();
    final pid = prefs.getInt(_pidKey);
    if (pid == null) return;
    await prefs.remove(_pidKey);
    final result =
        await Process.run('/bin/ps', <String>['-p', '$pid', '-o', 'comm=']);
    if ('${result.stdout}'.trim().endsWith('mihomo')) {
      Process.killPid(pid);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}

/// Reversible macOS system proxy (System Settings → Network → Proxies) for
/// every enabled network service, set with `networksetup` as Clash Verge
/// does. Apps that honour the system proxy go through Mihomo on
/// 127.0.0.1:7890. With TUN on, DNS of those services is pointed at public
/// resolvers so lookups enter the TUN and Mihomo answers them (a router
/// address on the LAN would bypass it), as FlClashX does.
class MihomoMacosSystemProxy {
  static const _networksetup = '/usr/sbin/networksetup';
  static const _host = '127.0.0.1';
  static const _port = '7890';
  static const _ownedKey = 'mihomo.macos.proxy.services.v1';
  static const _dnsKey = 'mihomo.macos.dns.v1';
  static const tunDns = <String>['1.1.1.1', '8.8.8.8'];
  static const _baseBypass = <String>[
    'localhost',
    '127.0.0.1',
    '::1',
    '*.local',
    '169.254/16',
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
  ];

  /// Proxy exceptions for the current "Russian sites directly" choice (the
  /// same list and setting as on Windows).
  static List<String> bypassFor({required bool bypassRussian}) => bypassRussian
      ? <String>[..._baseBypass, ...MihomoWindowsSystemProxy.russianBypass]
      : List<String>.of(_baseBypass);

  /// Parses `networksetup -listallnetworkservices`: the first line is a note,
  /// and disabled services start with `*`.
  static List<String> parseServices(String output) => output
      .split('\n')
      .skip(1)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('*'))
      .toList(growable: false);

  /// Parses `networksetup -getdnsservers`: one address per line, or a
  /// sentence when the servers come from DHCP (restored with `Empty`).
  static List<String> parseDnsServers(String output) => output
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.contains(' '))
      .toList(growable: false);

  Future<List<String>> _services() async {
    final result = await Process.run(
        _networksetup, const <String>['-listallnetworkservices']);
    if (result.exitCode != 0) {
      throw StateError(tr('Не удалось получить список сетей macOS: {error}',
          <String, Object?>{'error': '${result.stderr}'.trim()}));
    }
    return parseServices('${result.stdout}');
  }

  Future<String?> _run(List<String> arguments) async {
    final result = await Process.run(_networksetup, arguments);
    if (result.exitCode == 0) return null;
    final error = '${result.stderr}'.trim();
    return error.isEmpty ? '${result.stdout}'.trim() : error;
  }

  Future<void> enable({bool tun = false}) async {
    _requireMacos();
    await restoreIfOwned();
    final preferences = await SharedPreferences.getInstance();
    final bypass = bypassFor(
        bypassRussian:
            preferences.getBool(MihomoWindowsSystemProxy.bypassRussianKey) ??
                false);
    final owned = <String>[];
    final savedDns = <String, List<String>>{};
    String? lastError;
    for (final service in await _services()) {
      final errors = <String?>[
        await _run(<String>['-setwebproxy', service, _host, _port]),
        await _run(<String>['-setsecurewebproxy', service, _host, _port]),
        await _run(<String>['-setsocksfirewallproxy', service, _host, _port]),
        await _run(<String>['-setproxybypassdomains', service, ...bypass]),
      ].whereType<String>().toList();
      if (errors.isEmpty) {
        owned.add(service);
      } else {
        lastError = errors.first;
      }
      if (tun) {
        final current = await Process.run(
            _networksetup, <String>['-getdnsservers', service]);
        if (current.exitCode == 0 &&
            await _run(<String>['-setdnsservers', service, ...tunDns]) ==
                null) {
          savedDns[service] = parseDnsServers('${current.stdout}');
        }
      }
    }
    await preferences.setStringList(_ownedKey, owned);
    if (savedDns.isNotEmpty) {
      await preferences.setString(_dnsKey, jsonEncode(savedDns));
    }
    if (owned.isEmpty) {
      throw StateError(tr(
          'Не удалось включить системный прокси macOS: {error}. Нужна учётная запись администратора.',
          <String, Object?>{'error': lastError ?? tr('нет активных сетей')}));
    }
  }

  /// Applies the "Russian sites directly" choice right away while the KaGo
  /// proxy is on.
  Future<void> setBypassRussian(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(MihomoWindowsSystemProxy.bypassRussianKey, value);
    if (!Platform.isMacOS) return;
    final bypass = bypassFor(bypassRussian: value);
    for (final service
        in preferences.getStringList(_ownedKey) ?? const <String>[]) {
      await _run(<String>['-setproxybypassdomains', service, ...bypass]);
    }
  }

  /// Turns the proxies off and gives back the DNS servers on the services
  /// KaGo changed (also after a crash, at the next start).
  Future<void> restoreIfOwned() async {
    if (!Platform.isMacOS) return;
    final preferences = await SharedPreferences.getInstance();
    final owned = preferences.getStringList(_ownedKey);
    if (owned != null) {
      for (final service in owned) {
        await _run(<String>['-setwebproxystate', service, 'off']);
        await _run(<String>['-setsecurewebproxystate', service, 'off']);
        await _run(<String>['-setsocksfirewallproxystate', service, 'off']);
      }
      await preferences.remove(_ownedKey);
    }
    final dns = preferences.getString(_dnsKey);
    if (dns != null) {
      final Object? decoded = jsonDecode(dns);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final servers = entry.value is List
              ? (entry.value as List).whereType<String>().toList()
              : const <String>[];
          await _run(<String>[
            '-setdnsservers',
            entry.key,
            if (servers.isEmpty) 'Empty' else ...servers,
          ]);
        }
      }
      await preferences.remove(_dnsKey);
    }
  }

  void _requireMacos() {
    if (!Platform.isMacOS) {
      throw UnsupportedError(
          tr('Системный прокси macOS доступен только в macOS.'));
    }
  }
}
