import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import 'mihomo_windows_core_updater.dart';
import 'mihomo_windows_system_proxy.dart';

/// Mihomo shipped inside the macOS app bundle (`Contents/Resources/mihomo`, a
/// universal arm64 + x86_64 binary added by the CI build and signed with the
/// app). It is updated together with the app, like the Android core.
abstract final class MihomoMacosCore {
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
}

/// Reversible macOS system proxy (System Settings → Network → Proxies) for
/// every enabled network service, set with `networksetup` as Clash Verge
/// does. Apps that honour the system proxy go through Mihomo on
/// 127.0.0.1:7890; it is not a full-device TUN.
class MihomoMacosSystemProxy {
  static const _networksetup = '/usr/sbin/networksetup';
  static const _host = '127.0.0.1';
  static const _port = '7890';
  static const _ownedKey = 'mihomo.macos.proxy.services.v1';
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

  Future<void> enable() async {
    _requireMacos();
    await restoreIfOwned();
    final preferences = await SharedPreferences.getInstance();
    final bypass = bypassFor(
        bypassRussian:
            preferences.getBool(MihomoWindowsSystemProxy.bypassRussianKey) ??
                false);
    final owned = <String>[];
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
    }
    await preferences.setStringList(_ownedKey, owned);
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

  /// Turns the proxies off on the services KaGo turned them on (also after a
  /// crash, at the next start).
  Future<void> restoreIfOwned() async {
    if (!Platform.isMacOS) return;
    final preferences = await SharedPreferences.getInstance();
    final owned = preferences.getStringList(_ownedKey);
    if (owned == null) return;
    for (final service in owned) {
      await _run(<String>['-setwebproxystate', service, 'off']);
      await _run(<String>['-setsecurewebproxystate', service, 'off']);
      await _run(<String>['-setsocksfirewallproxystate', service, 'off']);
    }
    await preferences.remove(_ownedKey);
  }

  void _requireMacos() {
    if (!Platform.isMacOS) {
      throw UnsupportedError(
          tr('Системный прокси macOS доступен только в macOS.'));
    }
  }
}
