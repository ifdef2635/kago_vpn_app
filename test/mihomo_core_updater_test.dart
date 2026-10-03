import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/mihomo_release_api.dart';
import 'package:kago_vpn/core/network/mihomo_windows_core_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reproduces the field error: api.github.com refuses the connection
/// (Windows errno 1225).
class _RefusedAdapter implements HttpClientAdapter {
  final List<Uri> requested = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requested.add(options.uri);
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: const SocketException(
        'The connection errored',
        osError: OSError(
            'Удаленный компьютер отклонил это сетевое подключение', 1225),
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

/// GitHub answers, but with a payload that is not a Mihomo release.
class _BadPayloadAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString('{}', 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

MihomoWindowsCoreUpdater _updater(HttpClientAdapter adapter, Directory root) =>
    MihomoWindowsCoreUpdater(
      isWindows: true,
      installRoot: root,
      dio: Dio()..httpClientAdapter = adapter,
      releases: MihomoReleaseApi(dio: Dio()..httpClientAdapter = adapter),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('kago_core_updater_test');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('GitHub unreachable', () {
    test(
        'no core installed: tries the pinned direct URL, then a clear Russian error',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final adapter = _RefusedAdapter();
      final logs = <String>[];

      await expectLater(
        _updater(adapter, Directory('${temp.path}${Platform.pathSeparator}core'))
            .ensureInstalled(forceCheck: true, onLog: logs.add),
        throwsA(
          isA<MihomoCoreNetworkException>()
              .having((e) => e.message, 'message', contains('GitHub'))
              .having((e) => e.toString(), 'toString',
                  isNot(contains('DioException'))),
        ),
      );
      expect(logs.any((line) => line.contains('GitHub API недоступен')), isTrue);
      expect(logs.any((line) => line.contains('закреплённая версия')), isTrue);
      expect(adapter.requested, contains(MihomoPinnedCore.url));
    });

    test('pinned URL points at the official v1.19.32 compatible ZIP', () {
      expect(
        MihomoPinnedCore.url.toString(),
        'https://github.com/MetaCubeX/mihomo/releases/download/v1.19.32/mihomo-windows-amd64-compatible-v1.19.32.zip',
      );
    });

    test('stale saved path (file deleted) is treated as not installed',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mihomo.builtin.version': 'v1.19.32',
        'mihomo.builtin.path': '${temp.path}${Platform.pathSeparator}gone.exe',
      });
      final logs = <String>[];

      await expectLater(
        _updater(_RefusedAdapter(),
                Directory('${temp.path}${Platform.pathSeparator}core'))
            .ensureInstalled(onLog: logs.add),
        throwsA(isA<MihomoCoreNetworkException>()),
      );
      expect(logs.any((line) => line.contains('будет установлено заново')),
          isTrue);
    });

    test('installed core is kept when the update check fails', () async {
      final exe = File('${temp.path}${Platform.pathSeparator}mihomo.exe')
        ..writeAsBytesSync(<int>[1]);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mihomo.builtin.version': 'v1.19.32',
        'mihomo.builtin.path': exe.path,
      });

      final install = await _updater(_RefusedAdapter(),
              Directory('${temp.path}${Platform.pathSeparator}core'))
          .ensureInstalled(forceCheck: true);

      expect(install.version, 'v1.19.32');
      expect(install.executable.path, exe.path);
      expect(install.updated, isFalse);
    });

    test('non-network errors are not disguised as connectivity problems',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await expectLater(
        _updater(_BadPayloadAdapter(),
                Directory('${temp.path}${Platform.pathSeparator}core'))
            .ensureInstalled(forceCheck: true),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('integrity check', () {
    test('a modified mihomo.exe is treated as not installed', () async {
      final exe = File('${temp.path}${Platform.pathSeparator}mihomo.exe')
        ..writeAsBytesSync(<int>[1, 2, 3]);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mihomo.builtin.version': 'v1.19.32',
        'mihomo.builtin.path': exe.path,
        'mihomo.builtin.sha256': sha256.convert(<int>[1, 2, 3]).toString(),
      });
      final updater = _updater(_RefusedAdapter(), temp);

      expect(await updater.installed(), isNotNull);

      exe.writeAsBytesSync(<int>[9, 9, 9, 9]);
      // Different size, so the cached "verified" marker no longer applies.
      expect(await updater.installed(), isNull);
    });

    test('an install from an older build is recorded on first use', () async {
      final exe = File('${temp.path}${Platform.pathSeparator}mihomo.exe')
        ..writeAsBytesSync(<int>[4, 5, 6]);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mihomo.builtin.version': 'v1.19.30',
        'mihomo.builtin.path': exe.path,
      });

      expect(await _updater(_RefusedAdapter(), temp).installed(), isNotNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mihomo.builtin.sha256'),
          sha256.convert(<int>[4, 5, 6]).toString());
    });
  });

  group('old version cleanup', () {
    test('keeps only the active version and drops stale staging folders',
        () async {
      final root = Directory('${temp.path}${Platform.pathSeparator}core')
        ..createSync();
      Directory dir(String name) =>
          Directory('${root.path}${Platform.pathSeparator}$name')
            ..createSync();
      final keepDir = dir('v1.19.32-bbbbbbbbbbbb');
      final keepExe = File('${keepDir.path}${Platform.pathSeparator}mihomo.exe')
        ..writeAsBytesSync(<int>[1]);
      final old = dir('v1.19.30-aaaaaaaaaaaa');
      File('${old.path}${Platform.pathSeparator}mihomo.exe')
          .writeAsBytesSync(<int>[2]);
      final staging = dir('.staging-123');
      File('${staging.path}${Platform.pathSeparator}mihomo.exe')
          .writeAsBytesSync(<int>[3]);
      final logs = <String>[];

      await _updater(_RefusedAdapter(), root).cleanupOldVersions(
        MihomoCoreInstall(
            version: 'v1.19.32', executable: keepExe, updated: false),
        onLog: logs.add,
      );

      expect(keepDir.existsSync(), isTrue);
      expect(keepExe.existsSync(), isTrue);
      expect(old.existsSync(), isFalse);
      expect(staging.existsSync(), isFalse);
      expect(logs.where((line) => line.contains('Удалена старая версия')),
          hasLength(2));
    });

    test('does nothing when the active core lives outside the install root',
        () async {
      final root = Directory('${temp.path}${Platform.pathSeparator}core')
        ..createSync();
      final other = Directory('${root.path}${Platform.pathSeparator}v1')
        ..createSync();
      final external = File('${temp.path}${Platform.pathSeparator}other.exe')
        ..writeAsBytesSync(<int>[1]);

      await _updater(_RefusedAdapter(), root).cleanupOldVersions(
        MihomoCoreInstall(
            version: 'v1.19.32', executable: external, updated: false),
      );

      expect(other.existsSync(), isTrue);
    });
  });

  group('pinned release digest', () {
    const name = MihomoPinnedCore.assetName;
    const hex =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    const neighbour =
        'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

    test('is read from GitHub HTML next to the asset link', () {
      final page = '''
<li><a href="/MetaCubeX/mihomo/releases/download/v1.19.32/mihomo-windows-amd64-v1-v1.19.32.zip"><span>mihomo-windows-amd64-v1-v1.19.32.zip</span></a>
<span class="text-mono">sha256:$neighbour</span></li>
<li><a href="/MetaCubeX/mihomo/releases/download/v1.19.32/$name"><span>$name</span></a>
<span class="text-mono">sha256:${hex.toUpperCase()}</span></li>
''';

      expect(MihomoPinnedCore.digestFromReleasePage(page), hex);
    });

    test('works with the markdown-style listing too', () {
      const page =
          '[$name](https://github.com/MetaCubeX/mihomo/releases/download/v1.19.32/$name)\n  sha256:$hex  \n 21.3 MB';

      expect(MihomoPinnedCore.digestFromReleasePage(page), hex);
    });

    test('never takes the digest of the next asset', () {
      final page = '''
<a href="/MetaCubeX/mihomo/releases/download/v1.19.32/$name">$name</a>
<a href="/MetaCubeX/mihomo/releases/download/v1.19.32/other.zip">other.zip</a>
<span>sha256:$neighbour</span>
''';

      expect(MihomoPinnedCore.digestFromReleasePage(page), isNull);
    });

    test('release() carries the digest into the asset for verification', () {
      final asset = MihomoPinnedCore.release(hex).assets.single;

      expect(asset.digest, 'sha256:$hex');
      expect(MihomoPinnedCore.release().assets.single.digest, '');
    });
  });
}
