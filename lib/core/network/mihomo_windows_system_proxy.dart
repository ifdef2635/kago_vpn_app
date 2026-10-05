import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32_registry/win32_registry.dart';
import '../l10n/l10n.dart';

/// Reversible per-user Windows Internet Settings proxy integration.
///
/// This routes applications that honor the Windows system proxy; it does not
/// claim to replace a Wintun-based full-device TUN.
class MihomoWindowsSystemProxy {
  static const registryPath =
      r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const proxyServer =
      'http=127.0.0.1:7890;https=127.0.0.1:7890;socks=127.0.0.1:7890';
  static const proxyBypass = 'localhost;127.0.0.1;[::1]';
  static const _backupKey = 'mihomo.windows.proxy.backup.v1';
  static const _ownedProxyKey = 'mihomo.windows.proxy.owned.v1';

  Future<void> enable() async {
    _requireWindows();
    await restoreIfOwned();

    final preferences = await SharedPreferences.getInstance();
    final snapshot = _readSnapshot();
    await preferences.setString(_backupKey, jsonEncode(snapshot));
    await preferences.setString(_ownedProxyKey, proxyServer);

    final key = _openRegistryKey();
    try {
      key.createValue(const RegistryValue.int32('ProxyEnable', 1));
      key.createValue(const RegistryValue.string('ProxyServer', proxyServer));
      key.createValue(const RegistryValue.string('ProxyOverride', proxyBypass));
      // A static proxy should not be shadowed by a subscription/PAC URL.
      key.createValue(const RegistryValue.string('AutoConfigURL', ''));
    } finally {
      key.close();
    }
    _refreshWinInet();
  }

  Future<void> restoreIfOwned() async {
    if (!Platform.isWindows) return;
    final preferences = await SharedPreferences.getInstance();
    final backupJson = preferences.getString(_backupKey);
    if (backupJson == null) return;

    final ownedProxy = preferences.getString(_ownedProxyKey);
    final current = _readSnapshot();
    final stillOwned = current['ProxyEnable'] == 1 &&
        current['ProxyServer'] == ownedProxy &&
        ownedProxy == proxyServer;
    if (stillOwned) {
      final decoded = jsonDecode(backupJson);
      if (decoded is Map<String, dynamic>) {
        _restoreSnapshot(decoded);
        _refreshWinInet();
      }
    }
    await preferences.remove(_backupKey);
    await preferences.remove(_ownedProxyKey);
  }

  Map<String, Object?> _readSnapshot() {
    final key = _openRegistryKey();
    try {
      return <String, Object?>{
        'ProxyEnable': key.getIntValue('ProxyEnable'),
        'ProxyServer': key.getStringValue('ProxyServer'),
        'ProxyOverride': key.getStringValue('ProxyOverride'),
        'AutoConfigURL': key.getStringValue('AutoConfigURL'),
      };
    } finally {
      key.close();
    }
  }

  void _restoreSnapshot(Map<String, dynamic> snapshot) {
    final key = _openRegistryKey();
    try {
      _restoreInt(key, 'ProxyEnable', snapshot['ProxyEnable']);
      _restoreString(key, 'ProxyServer', snapshot['ProxyServer']);
      _restoreString(key, 'ProxyOverride', snapshot['ProxyOverride']);
      _restoreString(key, 'AutoConfigURL', snapshot['AutoConfigURL']);
    } finally {
      key.close();
    }
  }

  void _restoreInt(RegistryKey key, String name, Object? value) {
    if (value is int) {
      key.createValue(RegistryValue.int32(name, value));
    } else {
      _deleteIfPresent(key, name);
    }
  }

  void _restoreString(RegistryKey key, String name, Object? value) {
    if (value is String) {
      key.createValue(RegistryValue.string(name, value));
    } else {
      _deleteIfPresent(key, name);
    }
  }

  void _deleteIfPresent(RegistryKey key, String name) {
    if (key.getValue(name) != null) {
      key.deleteValue(name);
    }
  }

  RegistryKey _openRegistryKey() => Registry.openPath(
        RegistryHive.currentUser,
        path: registryPath,
        desiredAccessRights: AccessRights.allAccess,
      );

  void _refreshWinInet() {
    final wininet = DynamicLibrary.open('wininet.dll');
    final setOption = wininet.lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)>('InternetSetOptionW');
    const settingsChanged = 39;
    const refresh = 37;
    if (setOption(0, settingsChanged, nullptr, 0) == 0 ||
        setOption(0, refresh, nullptr, 0) == 0) {
      throw StateError(
          tr('Не удалось обновить настройки системного прокси Windows.'));
    }
  }

  void _requireWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError(tr('Системный прокси доступен только в Windows.'));
    }
  }
}
