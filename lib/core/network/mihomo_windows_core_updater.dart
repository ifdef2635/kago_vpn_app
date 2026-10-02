import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mihomo_release_api.dart';

class MihomoCoreInstall {
  const MihomoCoreInstall(
      {required this.version, required this.executable, required this.updated});

  final String version;
  final File executable;
  final bool updated;
}

/// Mihomo is not installed yet and GitHub could not be reached, so there is
/// nothing to fall back to. [toString] is user-facing Russian text, so existing
/// `'$error'` call sites show it without exposing a raw DioException.
class MihomoCoreNetworkException implements Exception {
  const MihomoCoreNetworkException(this.reason, {this.cause});

  /// Short technical reason, e.g. `HTTP 403` or the OS socket error text.
  final String reason;
  final Object? cause;

  String get message =>
      'Не удалось связаться с GitHub ($reason), а встроенное ядро Mihomo ещё не установлено. '
      'Проверьте интернет и доступ к github.com: загрузка повторится при следующем подключении.';

  @override
  String toString() => message;
}

/// Direct-download fallback used when api.github.com cannot be reached and no
/// core is installed yet (so there is no version to keep). Newer releases are
/// still picked up through the GitHub API once it is reachable.
abstract final class MihomoPinnedCore {
  static const version = 'v1.19.32';
  static const assetName = 'mihomo-windows-amd64-compatible-$version.zip';

  /// SHA-256 of the pinned ZIP, 64 hex characters. When null the download is
  /// accepted on HTTPS origin, ZIP structure and `mihomo -v` alone; set it to
  /// enforce the digest (`certutil -hashfile <zip> SHA256`).
  static String? get sha256Hex => null;

  static final Uri url = Uri.https('github.com',
      '/MetaCubeX/mihomo/releases/download/$version/$assetName');

  static MihomoReleaseInfo release() {
    final hex = sha256Hex;
    return MihomoReleaseInfo(
      version: version,
      assets: <MihomoReleaseAsset>[
        MihomoReleaseAsset(
            name: assetName,
            url: url,
            size: 0,
            digest: hex == null ? '' : 'sha256:${hex.toLowerCase()}'),
      ],
    );
  }
}

class MihomoWindowsCoreUpdater {
  /// [isWindows] and [installRoot] exist so tests can exercise the update flow
  /// on any host OS without touching the real %APPDATA%.
  MihomoWindowsCoreUpdater(
      {Dio? dio,
      MihomoReleaseApi? releases,
      bool? isWindows,
      Directory? installRoot})
      : _isWindows = isWindows ?? Platform.isWindows,
        _installRootOverride = installRoot,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 3),
              sendTimeout: const Duration(seconds: 15),
              headers: const <String, String>{
                'User-Agent': 'KaGo-VPN-Core-Updater'
              },
            )),
        _releases = releases ?? MihomoReleaseApi(dio: dio);

  static const _versionKey = 'mihomo.builtin.version';
  static const _pathKey = 'mihomo.builtin.path';
  static const _checkedAtKey = 'mihomo.builtin.checkedAt';
  static const _checkInterval = Duration(hours: 12);
  static const _maxArchiveBytes = 100 * 1024 * 1024;
  static const _maxExecutableBytes = 250 * 1024 * 1024;

  final bool _isWindows;
  final Directory? _installRootOverride;
  final Dio _dio;
  final MihomoReleaseApi _releases;
  Future<MihomoCoreInstall>? _operation;

  Future<MihomoCoreInstall> ensureInstalled(
      {bool forceCheck = false, ValueChanged<String>? onLog}) {
    final running = _operation;
    if (running != null) return running;
    final operation = _ensureInstalled(forceCheck: forceCheck, onLog: onLog);
    _operation = operation;
    return operation.whenComplete(() {
      _operation = null;
    });
  }

  Future<MihomoCoreInstall?> installed() async {
    final preferences = await SharedPreferences.getInstance();
    final path = preferences.getString(_pathKey);
    final version = preferences.getString(_versionKey);
    if (path == null || version == null || !await File(path).exists()) {
      return null;
    }
    return MihomoCoreInstall(
        version: version, executable: File(path), updated: false);
  }

  /// `%APPDATA%\KaGo\core` (created on demand). Falls back to the app support
  /// directory only if APPDATA is not set.
  Future<Directory> _installRoot() async {
    final override = _installRootOverride;
    if (override != null) return override;
    final appData = Platform.environment['APPDATA'];
    final base = appData != null && appData.isNotEmpty
        ? appData
        : (await getApplicationSupportDirectory()).path;
    return Directory(
        '$base${Platform.pathSeparator}KaGo${Platform.pathSeparator}core');
  }

  Future<MihomoCoreInstall> _ensureInstalled(
      {required bool forceCheck, ValueChanged<String>? onLog}) async {
    if (!_isWindows) {
      throw UnsupportedError(
          'Встроенное автоматическое ядро пока поддерживает Windows x64.');
    }
    final preferences = await SharedPreferences.getInstance();
    final current = await installed();
    if (current == null && preferences.getString(_pathKey) != null) {
      onLog?.call(
          'Сохранённый mihomo.exe не найден на диске; ядро будет установлено заново.');
    }
    final checkedText = preferences.getString(_checkedAtKey);
    final checkedAt =
        checkedText == null ? null : DateTime.tryParse(checkedText)?.toUtc();
    final checkDue = forceCheck ||
        current == null ||
        checkedAt == null ||
        DateTime.now().toUtc().difference(checkedAt) >= _checkInterval;
    if (!checkDue) return current;

    MihomoReleaseInfo release;
    try {
      onLog?.call('Проверка обновлений Mihomo…');
      release = await _releases.latestStable();
    } catch (error, stackTrace) {
      if (current != null) {
        onLog?.call(
            'GitHub недоступен; используется Mihomo ${current.version}: $error');
        return current;
      }
      onLog?.call(
          'GitHub API недоступен, встроенное ядро не установлено: $error');
      if (_explainNetworkFailure(error) is! MihomoCoreNetworkException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      onLog?.call(
          'Загружается закреплённая версия ${MihomoPinnedCore.version} напрямую с github.com.');
      release = MihomoPinnedCore.release();
    }

    final latest = release.version;
    if (current != null &&
        MihomoReleaseApi.compareStableVersions(latest, current.version) <= 0) {
      await preferences.setString(
          _checkedAtKey, DateTime.now().toUtc().toIso8601String());
      onLog?.call('Mihomo ${current.version} уже установлен.');
      return current;
    }
    final asset = MihomoReleaseApi.selectWindowsAmd64Asset(release);
    if (asset == null) {
      if (current != null) {
        await preferences.setString(
            _checkedAtKey, DateTime.now().toUtc().toIso8601String());
        onLog?.call(
            'Для $latest не найден поддерживаемый asset; оставлено Mihomo ${current.version}.');
        return current;
      }
      throw StateError(
          'В релизе $latest нет поддерживаемой Windows x64 сборки Mihomo.');
    }
    if (asset.size > _maxArchiveBytes) {
      throw StateError('Размер Mihomo ZIP превышает безопасный лимит.');
    }

    final root = await _installRoot();
    final staging = Directory(
        '${root.path}${Platform.pathSeparator}.staging-${DateTime.now().microsecondsSinceEpoch}');
    await staging.create(recursive: true);
    try {
      var lastLoggedStep = -1;
      final download = await _dio.get<List<int>>(
        asset.url.toString(),
        options:
            Options(responseType: ResponseType.bytes, followRedirects: true),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final step = received * 10 ~/ total;
          if (step == lastLoggedStep) return;
          lastLoggedStep = step;
          onLog?.call('Загрузка Mihomo: ${step * 10}%');
        },
      );
      final archiveBytes = download.data;
      if (archiveBytes == null ||
          archiveBytes.isEmpty ||
          archiveBytes.length > _maxArchiveBytes ||
          (asset.size > 0 && archiveBytes.length != asset.size)) {
        throw const FormatException(
            'Загруженный Mihomo ZIP имеет неверный размер.');
      }
      final digest = sha256.convert(archiveBytes).toString();
      if (asset.digest.isEmpty) {
        onLog?.call(
            'Для закреплённой версии нет эталонного SHA-256: проверены источник github.com по HTTPS, структура ZIP и запуск mihomo -v.');
      } else if (!constantTimeEquals(
          digest, asset.digest.substring('sha256:'.length))) {
        throw const FormatException(
            'SHA-256 Mihomo ZIP не совпал с GitHub release digest.');
      }

      final archive = ZipDecoder().decodeBytes(archiveBytes);
      final executables = archive.files
          .where((entry) =>
              entry.isFile &&
              _basename(entry.name).toLowerCase().endsWith('.exe'))
          .toList();
      if (executables.length != 1) {
        throw const FormatException(
            'В Mihomo ZIP должен быть ровно один Windows executable.');
      }
      final entry = executables.single;
      if (entry.size < 1 || entry.size > _maxExecutableBytes) {
        throw const FormatException('Небезопасный размер mihomo.exe в ZIP.');
      }
      final executableBytes = entry.readBytes();
      if (executableBytes == null || executableBytes.length != entry.size) {
        throw const FormatException('mihomo.exe распакован неполностью.');
      }

      final stagedBinary =
          File('${staging.path}${Platform.pathSeparator}mihomo.exe');
      await stagedBinary.writeAsBytes(executableBytes, flush: true);
      await _probe(stagedBinary, latest);

      final versionFolder = Directory(
          '${root.path}${Platform.pathSeparator}$latest-${digest.substring(0, 12)}');
      await versionFolder.create(recursive: true);
      final installedBinary =
          File('${versionFolder.path}${Platform.pathSeparator}mihomo.exe');
      if (await installedBinary.exists()) {
        await _probe(installedBinary, latest);
      } else {
        await stagedBinary.rename(installedBinary.path);
      }
      await preferences.setString(_versionKey, latest);
      await preferences.setString(_pathKey, installedBinary.path);
      await preferences.setString(
          _checkedAtKey, DateTime.now().toUtc().toIso8601String());
      onLog?.call('Mihomo $latest установлен и проверен.');
      return MihomoCoreInstall(
          version: latest, executable: installedBinary, updated: true);
    } catch (error, stackTrace) {
      if (current != null) {
        await preferences.setString(
            _checkedAtKey, DateTime.now().toUtc().toIso8601String());
        onLog?.call(
            'Обновление Mihomo не завершилось; оставлено ${current.version}: $error');
        return current;
      }
      Error.throwWithStackTrace(_explainNetworkFailure(error), stackTrace);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// Network failures become [MihomoCoreNetworkException]; integrity and format
  /// errors (digest mismatch, bad ZIP, ...) are returned unchanged so they are
  /// never disguised as connectivity problems.
  static Object _explainNetworkFailure(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final inner = error.error;
      final String reason;
      if (status != null) {
        reason = 'HTTP $status';
      } else if (inner is SocketException) {
        final os = inner.osError?.message.trim();
        reason = os == null || os.isEmpty ? inner.message : os;
      } else {
        reason = error.type.name;
      }
      return MihomoCoreNetworkException(reason, cause: error);
    }
    if (error is SocketException || error is TimeoutException) {
      return MihomoCoreNetworkException(error.runtimeType.toString(),
          cause: error);
    }
    return error;
  }

  Future<void> _probe(File executable, String expectedVersion) async {
    final process = await Process.start(executable.path, const <String>['-v'],
        runInShell: false);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(const Duration(seconds: 12),
        onTimeout: () {
      process.kill();
      return -1;
    });
    final output = '${await stdout}\n${await stderr}';
    final printableVersion = expectedVersion.startsWith('v')
        ? expectedVersion.substring(1)
        : expectedVersion;
    if (exitCode != 0 || !output.contains(printableVersion)) {
      throw FormatException(
          'Проверка mihomo.exe не прошла для $expectedVersion (код $exitCode).');
    }
  }

  static String _basename(String path) =>
      path.replaceAll('\\', '/').split('/').last;

  @visibleForTesting
  static bool constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}
