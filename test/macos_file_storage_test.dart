import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/storage/secure_storage.dart';

/// The login keychain of older versions; counts reads (each one is a
/// password prompt on macOS after an update).
class _Keychain extends FlutterSecureStorage {
  _Keychain(this.items);
  final Map<String, String> items;
  final reads = <String>[];

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads.add(key);
    return items[key];
  }
}

void main() {
  late Directory root;
  late Directory folder;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kago_secure');
    folder = Directory('${root.path}${Platform.pathSeparator}secure');
  });
  tearDown(() => root.delete(recursive: true));

  MacosFileStorage storage(_Keychain keychain) =>
      MacosFileStorage(directory: () async => folder, legacy: keychain);

  test('keychain items are moved once, the secret is not', () async {
    final keychain = _Keychain(<String, String>{
      'kago.device.hwid.v1': 'ABCDEF',
      'kago.profiles.v1': '[]',
      'mihomo.secret': 'old',
    });
    final first = storage(keychain);
    final reads = await Future.wait(<Future<String?>>[
      first.read(key: 'kago.device.hwid.v1'),
      first.read(key: 'kago.device.hwid.v1'),
      first.read(key: 'kago.profiles.v1'),
      first.read(key: 'kago.account.cookies.v1'),
      first.read(key: 'mihomo.secret'),
    ]);
    expect(reads, <String?>['ABCDEF', 'ABCDEF', '[]', null, null]);
    expect(keychain.reads, <String>[
      'kago.device.hwid.v1',
      'kago.profiles.v1',
      'kago.account.cookies.v1',
    ]);

    // A new start reads the file only.
    final again = _Keychain(keychain.items);
    final second = storage(again);
    expect(await second.read(key: 'kago.device.hwid.v1'), 'ABCDEF');
    expect(await second.read(key: 'kago.account.cookies.v1'), isNull);
    expect(again.reads, isEmpty);
  });

  test('writes and deletes persist, a deleted key is not brought back',
      () async {
    final keychain = _Keychain(<String, String>{'kago.profiles.v1': '[1]'});
    final first = storage(keychain);
    await first.write(key: 'mihomo.secret', value: 's');
    await first.delete(key: 'kago.profiles.v1');
    final second = storage(_Keychain(keychain.items));
    expect(await second.read(key: 'mihomo.secret'), 's');
    expect(await second.read(key: 'kago.profiles.v1'), isNull);
    expect(keychain.reads, isEmpty);

    final saved = jsonDecode(
        await File('${folder.path}${Platform.pathSeparator}secrets.json')
            .readAsString()) as Map<String, dynamic>;
    expect(saved['values'], <String, String>{'mihomo.secret': 's'});
  });

  test('the folder is readable only by the user', () async {
    await storage(_Keychain(<String, String>{}))
        .write(key: 'mihomo.secret', value: 's');
    final mode = (await folder.stat()).mode & 0x1FF;
    expect(mode, 0x1C0); // 0700
  }, skip: Platform.isWindows);
}
