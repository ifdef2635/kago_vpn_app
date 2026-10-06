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
import '../l10n/l10n.dart';

class MihomoCoreInstall {
  const MihomoCoreInstall(
      {required this.version,
      required this.executable,
      required this.updated,
      this.note});

  final String version;
  final File executable;
  final bool updated;

  /// Why the update check failed while the installed core was kept
  /// (for example `HTTP 403`); null when the check succeeded or was not due.
  final String? note;

  MihomoCoreInstall withNote(String reason) => MihomoCoreInstall(
      version: version, executable: executable, updated: updated, note: reason);
}

/// Mihomo is not installed yet and GitHub could not be reached, so there is
/// nothing to fall back to. [toString] is user-facing Russian text, so existing
/// `'$error'` call sites show it without exposing a raw DioException.
class MihomoCoreNetworkException implements Exception {
  const MihomoCoreNetworkException(this.reason, {this.cause});

  /// Short technical reason, e.g. `HTTP 403` or the OS socket error text.
  final String reason;
  final Object? cause;

  String get message => tr(
      'Не удалось связаться с GitHub ({reason}), а встроенное ядро Mihomo ещё не установлено. Проверьте интернет и доступ к github.com: загрузка повторится при следующем подключении.',
      <String, Object?>{'reason': reason});

  @override
  String toString() => message;
}

/// Direct-download fallback used when api.github.com cannot be reached and no
/// core is installed yet (so there is no version to keep). Newer releases are
/// still picked up through the GitHub API once it is reachable.
abstract final class MihomoPinnedCore {
  static const version = 'v1.19.32';
  static const assetName = 'mihomo-windows-amd64-compatible-$version.zip';

  /// SHA-256 of the pinned ZIP (`certutil -hashfile <zip> SHA256`), compiled
  /// in so the fallback download does not trust the release page alone.
  static String? get sha256Hex =>
      '974a4d7ad69aed27aa2e8f91d61113573c14dadb14562c63e58effabf59816f0';

  static final Uri url = Uri.https(
      'github.com', '/MetaCubeX/mihomo/releases/download/$version/$assetName');

  /// Public asset list of the release on github.com (not the API), which is
  /// usually reachable together with the download itself.
  static final Uri assetsPageUrl = Uri.https(
      'github.com', '/MetaCubeX/mihomo/releases/expanded_assets/$version');

  /// Finds this asset's `sha256:<hex>` in the release page HTML. The match must
  /// start at this asset's own download link and may not cross into the next
  /// asset, so a neighbour's digest is never picked up. Returns lowercase hex.
  static String? digestFromReleasePage(String page) {
    final match = RegExp(
      'releases/download/${RegExp.escape(version)}/${RegExp.escape(assetName)}'
      r'(?:(?!/releases/download/)[\s\S]){0,1200}?sha256:([0-9a-fA-F]{64})',
    ).firstMatch(page);
    return match?.group(1)?.toLowerCase();
  }

  /// [pageDigest] is used only when no digest is compiled in via [sha256Hex].
  static MihomoReleaseInfo release([String? pageDigest]) {
    final hex = sha256Hex ?? pageDigest;
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
  static const _exeDigestKey = 'mihomo.builtin.sha256';
  static const _checkInterval = Duration(hours: 12);
  static const _maxArchiveBytes = 100 * 1024 * 1024;
  static const _maxExecutableBytes = 250 * 1024 * 1024;

  final bool _isWindows;
  final Directory? _installRootOverride;
  final Dio _dio;
  final MihomoReleaseApi _releases;
  Future<MihomoCoreInstall>? _operation;
  String? _verifiedFileKey;

  Future<MihomoCoreInstall> ensureInstalled(
      {bool forceCheck = false, ValueChanged<String>? onLog}) {
    final running = _operation;
    if (running != null) return running;
    final operation = _ensureInstalled(forceCheck: forceCheck, onLog: onLog)
        .then((install) async {
      await cleanupOldVersions(install, onLog: onLog);
      return install;
    });
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
    final file = File(path);
    if (!await _isIntact(file, preferences)) return null;
    return MihomoCoreInstall(
        version: version, executable: file, updated: false);
  }

  /// The SHA-256 of mihomo.exe is recorded when it is installed and re-checked
  /// before use, so a corrupted, truncated or modified binary is replaced
  /// instead of being launched. Installs from older builds have no record yet;
  /// their current file is recorded on first use. The (path, size, mtime) of the
  /// last good check is cached, so the 30 MB file is not re-hashed every call.
  Future<bool> _isIntact(File file, SharedPreferences preferences) async {
    final stat = await file.stat();
    final key =
        '${file.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    if (_verifiedFileKey == key) return true;
    final actual = await _fileDigest(file);
    final expected = preferences.getString(_exeDigestKey);
    if (expected == null) {
      await preferences.setString(_exeDigestKey, actual);
    } else if (!constantTimeEquals(actual, expected)) {
      return false;
    }
    _verifiedFileKey = key;
    return true;
  }

  Future<String> _fileDigest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  /// Deletes every other version folder (and leftover `.staging-*` folders of
  /// interrupted downloads) from the install root, keeping only [keep]. A
  /// version that is still running cannot be deleted on Windows; it is skipped
  /// and removed on a later run. Never throws.
  Future<void> cleanupOldVersions(MihomoCoreInstall keep,
      {ValueChanged<String>? onLog}) async {
    try {
      final root = await _installRoot();
      if (!await root.exists()) return;
      final keepDir = keep.executable.parent.path;
      // Only clean when the kept core lives inside the root; otherwise the
      // folders here are not "old versions" of it.
      if (!_samePath(keepDir, root.path) && !_isUnder(keepDir, root.path)) {
        return;
      }
      for (final entity in await root.list(followLinks: false).toList()) {
        if (entity is! Directory) continue;
        if (_samePath(entity.path, keepDir)) continue;
        try {
          await entity.delete(recursive: true);
          onLog?.call(tr('Удалена старая версия ядра: {v}',
              <String, Object?>{'v': _basename(entity.path)}));
        } on FileSystemException catch (error) {
          onLog?.call(tr(
              'Не удалось удалить {v} (возможно, оно запущено): {message}',
              <String, Object?>{
                'v': _basename(entity.path),
                'message': error.message
              }));
        }
      }
    } catch (error) {
      onLog?.call(tr('Очистка старых версий ядра не удалась: {error}',
          <String, Object?>{'error': error}));
    }
  }

  static String _normalized(String path) =>
      path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();

  static bool _samePath(String left, String right) =>
      _normalized(left) == _normalized(right);

  static bool _isUnder(String child, String parent) =>
      _normalized(child).startsWith('${_normalized(parent)}/');

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
          tr('Встроенное автоматическое ядро пока поддерживает Windows x64.'));
    }
    final preferences = await SharedPreferences.getInstance();
    final current = await installed();
    if (current == null && preferences.getString(_pathKey) != null) {
      onLog?.call(tr(
          'Сохранённый mihomo.exe отсутствует или не прошёл проверку SHA-256; ядро будет установлено заново.'));
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
      onLog?.call(tr('Проверка обновлений Mihomo…'));
      release = await _releases.latestStable();
    } catch (error, stackTrace) {
      if (current != null) {
        onLog?.call(tr(
            'GitHub недоступен; используется Mihomo {version}: {error}',
            <String, Object?>{'version': current.version, 'error': error}));
        return current.withNote(_failureReason(error));
      }
      onLog?.call(tr(
          'GitHub API недоступен, встроенное ядро не установлено: {error}',
          <String, Object?>{'error': error}));
      if (_explainNetworkFailure(error) is! MihomoCoreNetworkException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      onLog?.call(tr(
          'Загружается закреплённая версия {version} напрямую с github.com.',
          <String, Object?>{'version': MihomoPinnedCore.version}));
      release = MihomoPinnedCore.release(await _pinnedDigestFromPage(onLog));
    }

    final latest = release.version;
    if (current != null &&
        MihomoReleaseApi.compareStableVersions(latest, current.version) <= 0) {
      await preferences.setString(
          _checkedAtKey, DateTime.now().toUtc().toIso8601String());
      onLog?.call(tr('Mihomo {version} уже установлен.',
          <String, Object?>{'version': current.version}));
      return current;
    }
    final asset = MihomoReleaseApi.selectWindowsAmd64Asset(release);
    if (asset == null) {
      if (current != null) {
        await preferences.setString(
            _checkedAtKey, DateTime.now().toUtc().toIso8601String());
        onLog?.call(tr(
            'Для {latest} не найден поддерживаемый asset; оставлено Mihomo {version}.',
            <String, Object?>{'latest': latest, 'version': current.version}));
        return current;
      }
      throw StateError(tr(
          'В релизе {latest} нет поддерживаемой Windows x64 сборки Mihomo.',
          <String, Object?>{'latest': latest}));
    }
    if (asset.size > _maxArchiveBytes) {
      throw StateError(tr('Размер Mihomo ZIP превышает безопасный лимит.'));
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
          onLog?.call(
              tr('Загрузка Mihomo: {v}%', <String, Object?>{'v': step * 10}));
        },
      );
      final archiveBytes = download.data;
      if (archiveBytes == null ||
          archiveBytes.isEmpty ||
          archiveBytes.length > _maxArchiveBytes ||
          (asset.size > 0 && archiveBytes.length != asset.size)) {
        throw FormatException(
            tr('Загруженный Mihomo ZIP имеет неверный размер.'));
      }
      final digest = sha256.convert(archiveBytes).toString();
      // No reference hash, no install: the ZIP's mihomo.exe would be run.
      if (asset.digest.isEmpty) {
        throw FormatException(tr(
            'Для Mihomo нет эталонного SHA-256 — ядро не установлено. Попробуйте позже.'));
      } else if (!constantTimeEquals(
          digest, asset.digest.substring('sha256:'.length))) {
        throw FormatException(
            tr('SHA-256 Mihomo ZIP не совпал с GitHub release digest.'));
      }

      final archive = ZipDecoder().decodeBytes(archiveBytes);
      final executables = archive.files
          .where((entry) =>
              entry.isFile &&
              _basename(entry.name).toLowerCase().endsWith('.exe'))
          .toList();
      if (executables.length != 1) {
        throw FormatException(
            tr('В Mihomo ZIP должен быть ровно один Windows executable.'));
      }
      final entry = executables.single;
      if (entry.size < 1 || entry.size > _maxExecutableBytes) {
        throw FormatException(tr('Небезопасный размер mihomo.exe в ZIP.'));
      }
      final executableBytes = entry.readBytes();
      if (executableBytes == null || executableBytes.length != entry.size) {
        throw FormatException(tr('mihomo.exe распакован неполностью.'));
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
      final executableDigest = sha256.convert(executableBytes).toString();
      if (await installedBinary.exists() &&
          constantTimeEquals(
              await _fileDigest(installedBinary), executableDigest)) {
        await _probe(installedBinary, latest);
      } else {
        if (await installedBinary.exists()) await installedBinary.delete();
        await stagedBinary.rename(installedBinary.path);
      }
      await preferences.setString(_exeDigestKey, executableDigest);
      _verifiedFileKey = null;
      await preferences.setString(_versionKey, latest);
      await preferences.setString(_pathKey, installedBinary.path);
      await preferences.setString(
          _checkedAtKey, DateTime.now().toUtc().toIso8601String());
      onLog?.call(tr('Mihomo {latest} установлен и проверен.',
          <String, Object?>{'latest': latest}));
      return MihomoCoreInstall(
          version: latest, executable: installedBinary, updated: true);
    } catch (error, stackTrace) {
      if (current != null) {
        await preferences.setString(
            _checkedAtKey, DateTime.now().toUtc().toIso8601String());
        onLog?.call(tr(
            'Обновление Mihomo не завершилось; оставлено {version}: {error}',
            <String, Object?>{'version': current.version, 'error': error}));
        return current.withNote(_failureReason(error));
      }
      Error.throwWithStackTrace(_explainNetworkFailure(error), stackTrace);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// Best effort: reads the pinned asset's SHA-256 from the release page on
  /// github.com so the fallback download can be verified like the API one.
  Future<String?> _pinnedDigestFromPage(ValueChanged<String>? onLog) async {
    if (MihomoPinnedCore.sha256Hex != null) return null;
    try {
      final response = await _dio.get<String>(
        MihomoPinnedCore.assetsPageUrl.toString(),
        options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 20),
            headers: const <String, String>{'Accept': 'text/html'}),
      );
      final digest =
          MihomoPinnedCore.digestFromReleasePage(response.data ?? '');
      onLog?.call(digest == null
          ? tr('На странице релиза не найден SHA-256 для {assetName}.',
              <String, Object?>{'assetName': MihomoPinnedCore.assetName})
          : tr('SHA-256 для {assetName} получен со страницы релиза.',
              <String, Object?>{'assetName': MihomoPinnedCore.assetName}));
      return digest;
    } catch (error) {
      onLog?.call(tr('Не удалось получить SHA-256 со страницы релиза: {error}',
          <String, Object?>{'error': error}));
      return null;
    }
  }

  static String _failureReason(Object error) {
    final explained = _explainNetworkFailure(error);
    return explained is MihomoCoreNetworkException
        ? explained.reason
        : error.toString();
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
      throw FormatException(tr(
          'Проверка mihomo.exe не прошла для {expectedVersion} (код {exitCode}).',
          <String, Object?>{
            'expectedVersion': expectedVersion,
            'exitCode': exitCode
          }));
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
