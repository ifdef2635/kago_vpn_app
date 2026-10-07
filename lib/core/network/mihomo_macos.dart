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
/// needs a root core. After the administrator password the app installs, in
/// the root-owned [rootDir], a root copy of the core and `kago-tun`
/// (macos/helper/kago_tun.c) — the only set-uid program, which ignores its
/// arguments and environment, runs the core with a fixed root-owned home and
/// takes the config on stdin, refusing keys that would let it write outside
/// that home or set the clock. (A set-uid Mihomo itself, as FlClashX ships it,
/// gives root to any program of an admin user.)
abstract final class MihomoMacosCore {
  static const tunKey = 'kago.macos.tun';
  static const _pidKey = 'kago.macos.core.pid';
  static const rootDir = '/Library/Application Support/net.usekago.app';
  static const rootCorePath = '$rootDir/mihomo';
  static const helperPath = '$rootDir/kago-tun';

  static String get _resources =>
      '${File(Platform.resolvedExecutable).parent.parent.path}/Resources';

  /// `…/KaGo VPN.app/Contents/MacOS/KaGo VPN` -> `…/Contents/Resources/mihomo`.
  static File get executable => File('$_resources/mihomo');

  /// The bundled set-uid wrapper (`Contents/Resources/kago-tun`).
  static File get bundledHelper => File('$_resources/kago-tun');

  static Future<MihomoCoreInstall?> installed() async {
    final file = executable;
    if (!await file.exists()) return null;
    return MihomoCoreInstall(
        version: MihomoPinnedCore.version, executable: file, updated: false);
  }

  /// The set-uid core of versions 1.0.3–1.0.4 in the user's folder; removed.
  static Future<File> _legacyPrivilegedFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/core/mihomo');
  }

  /// "All traffic through VPN" (TUN) is on by default.
  static Future<bool> tunEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(tunKey) ?? true;

  static Future<void> setTunEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(tunKey, value);

  /// `stat -f '%Su:%Sg %Sp'` of the wrapper: owned by root:admin, set-uid,
  /// not writable by group or others.
  static bool isPrivilegedStat(String output) {
    final parts = output.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts[0] != 'root:admin') return false;
    final mode = parts[1];
    return mode.length == 10 &&
        mode[3] == 's' &&
        mode[5] != 'w' &&
        mode[8] != 'w';
  }

  /// `stat` of the root core: a regular file owned by root, not set-uid, not
  /// writable by group or others.
  static bool isRootOwnedStat(String output) {
    final parts = output.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || !parts[0].startsWith('root:')) return false;
    final mode = parts[1];
    return mode.length == 10 &&
        mode[0] == '-' &&
        mode[3] != 's' &&
        mode[5] != 'w' &&
        mode[8] != 'w';
  }

  static final Map<String, String> _hashCache = <String, String>{};

  /// SHA-256 of [file], cached for this run by path, size and modification
  /// time (hashing the ~60 MB universal core takes a moment).
  static Future<String> _hash(File file) async {
    final stat = await file.stat();
    final key =
        '${file.path}:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    final cached = _hashCache[key];
    if (cached != null) return cached;
    final hash = (await sha256.bind(file.openRead()).first).toString();
    _hashCache[key] = hash;
    return hash;
  }

  static Future<String> _stat(String path) async {
    final result =
        await Process.run('/usr/bin/stat', <String>['-f', '%Su:%Sg %Sp', path]);
    return result.exitCode == 0 ? '${result.stdout}' : '';
  }

  /// The installed wrapper, if it and the root core are root-owned and hold
  /// the same files as this app bundle (compared by content, so an app update
  /// asks for the password again only when one of them changed).
  static Future<File?> authorizedHelper() async {
    if (!Platform.isMacOS) return null;
    final helper = File(helperPath);
    final core = File(rootCorePath);
    if (!await helper.exists() ||
        !await core.exists() ||
        !await executable.exists() ||
        !await bundledHelper.exists()) {
      return null;
    }
    if (!isPrivilegedStat(await _stat(helperPath)) ||
        !isRootOwnedStat(await _stat(rootCorePath))) {
      return null;
    }
    try {
      final same = await _hash(core) == await _hash(executable) &&
          await _hash(helper) == await _hash(bundledHelper);
      return same ? helper : null;
    } on FileSystemException {
      return null;
    }
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

  /// The root install script. Everything is written inside the root-owned
  /// [rootDir] (no user-writable path is written as root), and each file is
  /// checked against the hash taken from the bundle before it gets its owner
  /// and mode, so a file swapped in the meantime is refused.
  static String installScript({
    required String coreSource,
    required String coreHash,
    required String helperSource,
    required String helperHash,
    required String legacyFile,
  }) {
    String hashOf(String path) =>
        '"\$(/usr/bin/shasum -a 256 $path | /usr/bin/cut -d " " -f 1)"';
    return <String>[
      'set -e',
      'umask 077',
      'D=${shellQuote(rootDir)}',
      r'[ ! -L "$D" ]',
      r'/bin/mkdir -p "$D"',
      r'/usr/sbin/chown root:wheel "$D"',
      r'/bin/chmod 755 "$D"',
      r'N="$D/.new"',
      r'/bin/rm -rf "$N"',
      r'/bin/mkdir "$N"',
      "trap '/bin/rm -rf \"\$N\"' EXIT",
      '/bin/cp -X ${shellQuote(coreSource)} "\$N/mihomo"',
      '/bin/cp -X ${shellQuote(helperSource)} "\$N/kago-tun"',
      '[ ${hashOf(r'"$N/mihomo"')} = ${shellQuote(coreHash)} ]',
      '[ ${hashOf(r'"$N/kago-tun"')} = ${shellQuote(helperHash)} ]',
      r'/usr/sbin/chown root:wheel "$N/mihomo"',
      r'/bin/chmod 755 "$N/mihomo"',
      r'/usr/sbin/chown root:admin "$N/kago-tun"',
      r'/bin/chmod 4750 "$N/kago-tun"',
      r'/bin/mv -f "$N/mihomo" "$D/mihomo"',
      r'/bin/mv -f "$N/kago-tun" "$D/kago-tun"',
      r'/bin/mkdir -p "$D/run"',
      r'/usr/sbin/chown root:wheel "$D/run"',
      r'/bin/chmod 700 "$D/run"',
      '/bin/rm -f ${shellQuote(legacyFile)}',
    ].join('\n');
  }

  /// Installs the wrapper and the root core (one macOS password prompt).
  /// Only members of the `admin` group may run the wrapper (mode 4750).
  /// Returns null on success, or why it failed.
  static Future<String?> authorize() async {
    final groups = await Process.run('/usr/bin/id', const <String>['-Gn']);
    if (!'${groups.stdout}'.split(RegExp(r'\s+')).contains('admin')) {
      return tr('Нужна учётная запись администратора macOS.');
    }
    if (!await executable.exists() || !await bundledHelper.exists()) {
      return tr('Не удалось скопировать ядро.');
    }
    final script = installScript(
      coreSource: executable.path,
      coreHash: await _hash(executable),
      helperSource: bundledHelper.path,
      helperHash: await _hash(bundledHelper),
      legacyFile: (await _legacyPrivilegedFile()).path,
    );
    final result = await Process.run('/usr/bin/osascript', <String>[
      '-e',
      adminScript(script,
          tr('KaGo VPN включает режим «Весь трафик через VPN». Это нужно один раз.')),
    ]);
    if (result.exitCode == 0) {
      return await authorizedHelper() == null
          ? tr('Не удалось скопировать ядро.')
          : null;
    }
    final error = '${result.stderr}'.trim();
    return error.contains('-128') ? tr('Отменено.') : error;
  }

  /// The program to run and whether it is the TUN wrapper (which takes the
  /// config on stdin). Asks for the password at most once: if the user
  /// cancels, TUN is switched off in settings and the app keeps working
  /// through the system proxy with the unprivileged bundled core.
  static Future<({File binary, bool tun})> resolve(
      void Function(String) log) async {
    await _removeLegacy();
    if (!await tunEnabled()) return (binary: executable, tun: false);
    var helper = await authorizedHelper();
    if (helper == null) {
      final error = await authorize();
      if (error == null) {
        helper = await authorizedHelper();
      } else {
        await setTunEnabled(false);
        log(tr('Режим «Весь трафик через VPN» выключен: {error}',
            <String, Object?>{'error': error}));
      }
    }
    return helper == null
        ? (binary: executable, tun: false)
        : (binary: helper, tun: true);
  }

  /// The old set-uid core in the user's folder gave root to any program of an
  /// admin user. The folder is the user's, so no root is needed to delete it.
  static Future<void> _removeLegacy() async {
    try {
      final legacy = await _legacyPrivilegedFile();
      if (await legacy.exists()) await legacy.delete();
    } catch (_) {
      // The next authorization script removes it too.
    }
  }

  /// `ps -o lstart=`: the start time, which tells a reused pid apart.
  static Future<String?> _startTime(int pid) async {
    final result =
        await Process.run('/bin/ps', <String>['-p', '$pid', '-o', 'lstart=']);
    final value = '${result.stdout}'.trim();
    return result.exitCode == 0 && value.isNotEmpty ? value : null;
  }

  static Future<void> rememberPid(int? pid) async {
    final prefs = await SharedPreferences.getInstance();
    if (pid == null) {
      await prefs.remove(_pidKey);
      return;
    }
    final started = await _startTime(pid);
    if (started != null) await prefs.setString(_pidKey, '$pid|$started');
  }

  /// A core left running by a crashed app keeps the ports and, as root, the
  /// TUN routes; stop it before starting a new one. Only the very process
  /// that was started (same pid and start time, a mihomo binary) is signalled.
  static Future<void> killStale() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.get(_pidKey);
    await prefs.remove(_pidKey);
    if (saved is! String) return;
    final separator = saved.indexOf('|');
    if (separator <= 0) return;
    final pid = int.tryParse(saved.substring(0, separator));
    if (pid == null) return;
    final started = await _startTime(pid);
    if (started == null || started != saved.substring(separator + 1)) return;
    final name =
        await Process.run('/bin/ps', <String>['-p', '$pid', '-o', 'comm=']);
    if ('${name.stdout}'.trim().endsWith('mihomo')) {
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
