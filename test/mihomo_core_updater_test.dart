import 'dart:io';
import 'dart:typed_data';

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
      expect(logs.any((line) => line.contains('не найден на диске')), isTrue);
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
}
