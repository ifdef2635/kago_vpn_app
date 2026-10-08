import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Secure storage shared by the app (session cookies, profiles, controller
/// secret, device id).
///
/// macOS: a file in the user's own folder ([MacosFileStorage]), not the
/// keychain. The .dmg is signed ad hoc, so every update has a new code
/// signature; the login keychain then asked for the password once per item
/// (5–7 times) after each update, and the data-protection keychain needs an
/// Apple Developer team (-34018 without it).
final FlutterSecureStorage kagoSecureStorage =
    Platform.isMacOS ? MacosFileStorage() : const FlutterSecureStorage();

/// Keys brought over from the macOS login keychain of versions before 2.0.4
/// (one last password prompt per item that exists). The controller secret is
/// left out: a new one is made without asking.
const macosLegacyKeys = <String>{
  'kago.device.hwid.v1',
  'kago.profiles.v1',
  'kago.account.cookies.v1',
};

/// Key–value secrets in `secure/secrets.json` of the app's support folder,
/// with the folder readable only by the user (mode 700), like the profiles
/// of other desktop VPN clients and the DPAPI file of the Windows build
/// (which any program of the same user can read too). Operations run one at
/// a time, so a key is migrated from the keychain at most once.
class MacosFileStorage extends FlutterSecureStorage {
  MacosFileStorage(
      {Future<Directory> Function()? directory,
      FlutterSecureStorage? legacy,
      Set<String> legacyKeys = macosLegacyKeys})
      : _directory = directory ?? _defaultDirectory,
        _legacy = legacy ??
            const FlutterSecureStorage(
                mOptions: MacOsOptions(useDataProtectionKeyChain: false)),
        _legacyKeys = legacyKeys,
        super();

  final Future<Directory> Function() _directory;
  final FlutterSecureStorage _legacy;
  final Set<String> _legacyKeys;

  Map<String, String>? _values;
  Set<String> _migrated = <String>{};
  Future<void> _queue = Future<void>.value();

  static Future<Directory> _defaultDirectory() async => Directory(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}secure');

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<File> _file() async {
    final directory = await _directory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    if (!Platform.isWindows) {
      // Before anything is written into it.
      try {
        await Process.run('/bin/chmod', <String>['700', directory.path]);
      } on ProcessException {
        // Left as created; the parent is the user's own folder.
      }
    }
    return File('${directory.path}${Platform.pathSeparator}secrets.json');
  }

  Future<Map<String, String>> _load() async {
    final cached = _values;
    if (cached != null) return cached;
    final values = <String, String>{};
    try {
      final Object? decoded = jsonDecode(await (await _file()).readAsString());
      if (decoded is Map<String, dynamic>) {
        final stored = decoded['values'];
        if (stored is Map<String, dynamic>) {
          for (final MapEntry(:key, :value) in stored.entries) {
            if (value is String) values[key] = value;
          }
        }
        final migrated = decoded['migrated'];
        if (migrated is List) _migrated = migrated.whereType<String>().toSet();
      }
    } on FileSystemException {
      // No file yet.
    } on FormatException {
      // A damaged file is replaced at the next write.
    }
    return _values = values;
  }

  Future<void> _save() async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
        jsonEncode(<String, Object>{
          'values': _values ?? const <String, String>{},
          'migrated': _migrated.toList()..sort(),
        }),
        flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      _locked(() async {
        final values = await _load();
        final value = values[key];
        if (value != null || _migrated.contains(key)) return value;
        if (!_legacyKeys.contains(key)) return null;
        String? legacy;
        try {
          legacy = await _legacy.read(key: key);
        } catch (_) {
          // Denied or unreadable: asked again at the next start.
          return null;
        }
        if (legacy != null) values[key] = legacy;
        _migrated.add(key);
        await _save();
        return legacy;
      });

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      _locked(() async {
        final values = await _load();
        if (value == null) {
          values.remove(key);
        } else {
          values[key] = value;
        }
        _migrated.add(key);
        await _save();
      });

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      write(key: key, value: null);

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      await read(key: key) != null;

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      _locked(() async => Map<String, String>.of(await _load()));

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      _locked(() async {
        (await _load()).clear();
        _migrated.addAll(_legacyKeys);
        await _save();
      });
}
