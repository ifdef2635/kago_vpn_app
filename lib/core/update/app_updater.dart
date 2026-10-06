import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../device/device_identity.dart';
import '../l10n/l10n.dart';
import 'release_signature.dart';

/// A newer KaGo VPN release on GitHub for this platform.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.assetName,
    required this.assetUrl,
    required this.sumsUrl,
    this.notes = '',
  });

  final String version;
  final String assetName;
  final String assetUrl;
  final String sumsUrl;
  final String notes;
}

/// How the downloaded update was handed over.
enum UpdateInstallResult {
  /// The installer runs; on desktop the app is about to quit.
  started,

  /// Android: "Install unknown apps" must be allowed for KaGo VPN first.
  needsPermission,

  /// The app could not replace itself (macOS outside a writable folder): the
  /// .dmg is opened for a manual drag-and-drop install.
  openedManually,
}

/// In-app updates from the latest GitHub release, on every platform:
/// Android — the APK goes to the system installer (same signing key, so it
/// installs over the current version); Windows — the Inno Setup installer runs
/// silently and restarts the app; macOS — the app bundle is replaced from the
/// .dmg after the app quits, and the new version starts.
///
/// Every file is checked against `SHA256SUMS.txt` of the same release, and
/// that list must carry a valid signature (`SHA256SUMS.txt.sig`) by the
/// release key built into the app (release_signature.dart): a release
/// published without that key is not installed.
class AppUpdater {
  AppUpdater({this.proxyPort});

  static const repo = 'ifdef2635/kago_vpn_app';
  static const _apiLatest =
      'https://api.github.com/repos/$repo/releases/latest';
  static const _webLatest = 'https://github.com/$repo/releases/latest';
  static const _channel = MethodChannel('net.usekago.app/service');

  /// Desktop: send requests through the running core (`127.0.0.1:port`).
  final int? proxyPort;

  static bool get supported =>
      Platform.isAndroid || Platform.isWindows || Platform.isMacOS;

  /// The signed list of all files of a release and its signature.
  static const signedSums = 'SHA256SUMS.txt';
  static const signedSumsSignature = 'SHA256SUMS.txt.sig';

  /// `KaGoVPN-Android-1.0.4.apk`, `KaGoVPN-Windows-x64-Setup-1.0.4.exe`,
  /// `KaGoVPN-macOS-1.0.4.dmg` (release.yml).
  static ({String asset, String sums})? assetsFor(String os, String version) =>
      switch (os) {
        'android' => (asset: 'KaGoVPN-Android-$version.apk', sums: signedSums),
        'windows' => (
            asset: 'KaGoVPN-Windows-x64-Setup-$version.exe',
            sums: signedSums
          ),
        'macos' => (asset: 'KaGoVPN-macOS-$version.dmg', sums: signedSums),
        _ => null,
      };

  /// "v1.0.4" / "1.0.4" -> [1, 0, 4]; null if it is not a plain version.
  static List<int>? parseVersion(String text) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(text.trim());
    if (match == null) return null;
    return <int>[for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  static bool isNewer(String latest, String current) {
    final a = parseVersion(latest);
    final b = parseVersion(current);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  /// Release notes (Markdown from RELEASE_STATUS.md) as plain text for the
  /// dialog: no emphasis or code marks, bullets as "•".
  static String plainNotes(String markdown) => markdown
      .replaceAll('\r', '')
      .replaceAll('**', '')
      .replaceAll('`', '')
      .replaceAllMapped(RegExp(r'^(\s*)- ', multiLine: true),
          (match) => '${match.group(1)}• ')
      .trim();

  /// The hash for [name] in a `sha256sum`/`shasum` listing
  /// (`<hex>  <name>` or `<hex> *<name>`).
  static String? hashFor(String sums, String name) {
    for (final line in const LineSplitter().convert(sums)) {
      final match =
          RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(line.trim());
      if (match != null && match.group(2)!.trim() == name) {
        return match.group(1)!.toLowerCase();
      }
    }
    return null;
  }

  Dio _dio({bool followRedirects = true}) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: followRedirects,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
      headers: <String, String>{
        'User-Agent': 'KaGoVPN/$kagoAppVersion',
        'Accept': 'application/vnd.github+json',
      },
    ));
    final port = proxyPort;
    if (port != null) {
      dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
        return client;
      });
    }
    return dio;
  }

  /// The latest release tag and notes: the GitHub API, or — when the API is
  /// unreachable or rate-limited — the redirect of github.com/…/releases/latest.
  Future<({String tag, String notes})> _latest() async {
    try {
      final response = await _dio().get<Map<String, dynamic>>(_apiLatest);
      final data = response.data;
      final tag = data?['tag_name'];
      if (tag is String) {
        final body = data?['body'];
        return (tag: tag, notes: body is String ? plainNotes(body) : '');
      }
    } catch (_) {
      // Fall back to the web redirect below.
    }
    final response = await _dio(followRedirects: false).get<String>(_webLatest,
        options: Options(responseType: ResponseType.plain));
    final location = response.headers.value('location') ?? '';
    final tag = Uri.tryParse(location)?.pathSegments.lastOrNull ?? '';
    if (parseVersion(tag) == null) {
      throw StateError(tr('Не удалось узнать последнюю версию.'));
    }
    return (tag: tag, notes: '');
  }

  /// A release newer than this app, or null.
  Future<AppRelease?> check() async {
    if (!supported) return null;
    final latest = await _latest();
    final version = latest.tag.replaceFirst('v', '');
    if (!isNewer(version, kagoAppVersion)) return null;
    final os = Platform.operatingSystem;
    final names = assetsFor(os, version);
    if (names == null) return null;
    final base = 'https://github.com/$repo/releases/download/${latest.tag}';
    return AppRelease(
      version: version,
      assetName: names.asset,
      assetUrl: '$base/${names.asset}',
      sumsUrl: '$base/${names.sums}',
      notes: latest.notes,
    );
  }

  /// Downloads the update into the temporary folder and checks its SHA-256.
  Future<File> download(AppRelease release,
      {void Function(int received, int total)? onProgress,
      CancelToken? cancelToken}) async {
    final dio = _dio();
    Future<List<int>> bytes(String url) async {
      final response = await dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes),
          cancelToken: cancelToken);
      return response.data ?? const <int>[];
    }

    final sums = await bytes(release.sumsUrl);
    final signature = await bytes('${release.sumsUrl}.sig');
    if (!verifyRsaSha256(sums, signature)) {
      throw StateError(tr(
          'Подпись обновления не прошла проверку. Обновление не установлено.'));
    }
    final expected =
        hashFor(utf8.decode(sums, allowMalformed: true), release.assetName);
    if (expected == null) {
      throw StateError(tr('В релизе нет контрольной суммы обновления.'));
    }
    final dir = Directory('${(await getTemporaryDirectory()).path}'
        '${Platform.pathSeparator}updates');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file =
        File('${dir.path}${Platform.pathSeparator}${release.assetName}');
    await dio.download(release.assetUrl, file.path,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(receiveTimeout: const Duration(minutes: 2)));
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual != expected) {
      await file.delete();
      throw StateError(tr(
          'Файл обновления повреждён (контрольная сумма не совпала). Попробуйте ещё раз.'));
    }
    return file;
  }

  /// Hands the file to the platform installer. On Windows and macOS the
  /// caller must then stop the core and quit the app.
  Future<UpdateInstallResult> install(File file) async {
    if (Platform.isAndroid) {
      final result = await _channel
          .invokeMethod<String>('installUpdate', {'path': file.path});
      return result == 'permission'
          ? UpdateInstallResult.needsPermission
          : UpdateInstallResult.started;
    }
    if (Platform.isWindows) {
      // Inno Setup: progress window only, closes the old app if it still
      // runs, and starts KaGo VPN again when done (kago_vpn.iss).
      await Process.start(
          file.path,
          const <String>[
            '/SILENT',
            '/SUPPRESSMSGBOXES',
            '/NORESTART',
            '/CLOSEAPPLICATIONS',
          ],
          mode: ProcessStartMode.detached);
      return UpdateInstallResult.started;
    }
    if (Platform.isMacOS) return _installMacos(file);
    throw UnsupportedError(tr('Обновление не поддерживается на этой системе.'));
  }

  /// `…/KaGo VPN.app` of the running app.
  static Directory get macosBundle =>
      File(Platform.resolvedExecutable).parent.parent.parent;

  /// Replaces the bundle once this process exits: mount the .dmg, copy the
  /// new app next to the old one, swap, start it. A bundle in a folder the
  /// user cannot write (a mounted .dmg, App Translocation) is updated by hand.
  Future<UpdateInstallResult> _installMacos(File dmg) async {
    final bundle = macosBundle;
    if (!bundle.path.endsWith('.app') || !await _writable(bundle.parent)) {
      await Process.run('/usr/bin/open', <String>[dmg.path]);
      return UpdateInstallResult.openedManually;
    }
    final script = File('${dmg.parent.path}/install.sh');
    await script.writeAsString(macosInstallScript);
    await Process.start(
        '/bin/bash', <String>[script.path, '$pid', dmg.path, bundle.path],
        mode: ProcessStartMode.detached);
    return UpdateInstallResult.started;
  }

  static Future<bool> _writable(Directory directory) async {
    try {
      final probe = File('${directory.path}/.kago-update-probe');
      await probe.writeAsString('');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Arguments: app pid, path to the .dmg, path to `KaGo VPN.app`.
  /// If anything fails before the swap, the old app stays and is reopened.
  static const macosInstallScript = r'''#!/bin/bash
APP_PID="$1"; DMG="$2"; TARGET="$3"
for _ in $(seq 1 300); do kill -0 "$APP_PID" 2>/dev/null || break; sleep 0.2; done
MNT="$(mktemp -d /tmp/kago-update.XXXXXX)"
STAGE="$TARGET.update"
if hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MNT" "$DMG" >/dev/null; then
  SRC="$(find "$MNT" -maxdepth 1 -name '*.app' -print -quit)"
  rm -rf "$STAGE"
  if [ -n "$SRC" ] && ditto "$SRC" "$STAGE"; then
    rm -rf "$TARGET.old"
    if mv "$TARGET" "$TARGET.old"; then
      if mv "$STAGE" "$TARGET"; then rm -rf "$TARGET.old"; else mv "$TARGET.old" "$TARGET"; fi
    fi
  fi
  rm -rf "$STAGE"
  hdiutil detach "$MNT" -quiet || hdiutil detach "$MNT" -force -quiet
fi
rmdir "$MNT" 2>/dev/null
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
rm -f "$DMG"
open "$TARGET"
''';
}
