import 'package:dio/dio.dart';
import '../l10n/l10n.dart';

class MihomoReleaseAsset {
  const MihomoReleaseAsset(
      {required this.name,
      required this.url,
      required this.size,
      required this.digest});

  final String name;
  final Uri url;
  final int size;
  final String digest;
}

class MihomoReleaseInfo {
  const MihomoReleaseInfo({required this.version, required this.assets});

  final String version;
  final List<MihomoReleaseAsset> assets;
}

class MihomoReleaseApi {
  MihomoReleaseApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              headers: const <String, String>{
                'Accept': 'application/vnd.github+json',
                'X-GitHub-Api-Version': '2022-11-28',
                'User-Agent': 'KaGo-VPN-Core-Updater',
              },
            ));

  static final Uri latestReleaseUri =
      Uri.https('api.github.com', '/repos/MetaCubeX/mihomo/releases/latest');
  final Dio _dio;

  Future<MihomoReleaseInfo> latestStable() async {
    final response = await _dio.get<Object?>(latestReleaseUri.toString());
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw FormatException(
          tr('GitHub вернул неверные данные о релизе Mihomo.'));
    }
    final rawVersion = data['tag_name'];
    if (rawVersion is! String ||
        !RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(rawVersion)) {
      throw FormatException(tr('Тег Mihomo не похож на стабильную версию.'));
    }
    final rawReleaseUrl = data['html_url'];
    final releaseUrl =
        Uri.tryParse(rawReleaseUrl is String ? rawReleaseUrl : '');
    if (releaseUrl == null ||
        releaseUrl.scheme != 'https' ||
        releaseUrl.host != 'github.com' ||
        releaseUrl.path != '/MetaCubeX/mihomo/releases/tag/$rawVersion') {
      throw FormatException(tr('Непроверенный URL релиза Mihomo.'));
    }
    final rawAssets = data['assets'];
    if (rawAssets is! List<dynamic>) {
      throw FormatException(tr('В релизе Mihomo отсутствует список assets.'));
    }
    final assets = <MihomoReleaseAsset>[];
    for (final raw in rawAssets) {
      if (raw is! Map<String, dynamic>) continue;
      final rawName = raw['name'];
      final rawUrl = raw['browser_download_url'];
      final url = Uri.tryParse(rawUrl is String ? rawUrl : '');
      final digest = raw['digest'];
      final size = raw['size'];
      if (rawName is! String ||
          url == null ||
          url.scheme != 'https' ||
          url.host != 'github.com' ||
          !url.path
              .startsWith('/MetaCubeX/mihomo/releases/download/$rawVersion/') ||
          digest is! String ||
          !RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest) ||
          size is! num ||
          size < 1) {
        continue;
      }
      assets.add(MihomoReleaseAsset(
          name: rawName,
          url: url,
          size: size.toInt(),
          digest: digest.toLowerCase()));
    }
    return MihomoReleaseInfo(
        version: rawVersion,
        assets: List<MihomoReleaseAsset>.unmodifiable(assets));
  }

  static MihomoReleaseAsset? selectWindowsAmd64Asset(
      MihomoReleaseInfo release) {
    // Prefer the portable CPU-baseline build, never GOAMD64 v2/v3-specific assets.
    final preferredNames = <String>[
      'mihomo-windows-amd64-compatible-${release.version}.zip',
      'mihomo-windows-amd64-v1-${release.version}.zip',
      'mihomo-windows-amd64-${release.version}.zip',
    ];
    for (final name in preferredNames) {
      for (final asset in release.assets) {
        if (asset.name == name) return asset;
      }
    }
    return null;
  }

  static int compareStableVersions(String left, String right) {
    final pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');
    final leftMatch = pattern.firstMatch(left);
    final rightMatch = pattern.firstMatch(right);
    if (leftMatch == null || rightMatch == null) {
      throw FormatException(tr('Неверный формат версии Mihomo.'));
    }
    for (var index = 1; index <= 3; index++) {
      final comparison = int.parse(leftMatch.group(index)!)
          .compareTo(int.parse(rightMatch.group(index)!));
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}
