import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/mihomo_release_api.dart';
import 'package:kago_vpn/core/network/mihomo_windows_core_updater.dart';

void main() {
  group('Mihomo release selection', () {
    // The upstream ZIP contains one executable named mihomo-windows-amd64-compatible.exe.
    const compatibleName = 'mihomo-windows-amd64-compatible-v1.19.32.zip';
    const optimizedName = 'mihomo-windows-amd64-v3-v1.19.32.zip';

    MihomoReleaseAsset asset(String name) => MihomoReleaseAsset(
          name: name,
          url: Uri.https('github.com',
              '/MetaCubeX/mihomo/releases/download/v1.19.32/$name'),
          size: 1024,
          digest: 'sha256:${List<String>.filled(64, 'a').join()}',
        );

    test('prefers portable compatible asset over CPU-optimized variants', () {
      final release = MihomoReleaseInfo(
        version: 'v1.19.32',
        assets: <MihomoReleaseAsset>[
          asset(optimizedName),
          asset('mihomo-windows-amd64-v1-go125-v1.19.32.zip'),
          asset(compatibleName),
        ],
      );

      expect(MihomoReleaseApi.selectWindowsAmd64Asset(release)?.name,
          compatibleName);
    });

    test('falls back only to exact baseline v1 asset', () {
      final release = MihomoReleaseInfo(
        version: 'v1.19.32',
        assets: <MihomoReleaseAsset>[
          asset('mihomo-windows-amd64-v2-v1.19.32.zip'),
          asset('mihomo-windows-amd64-v1-v1.19.32.zip'),
        ],
      );

      expect(MihomoReleaseApi.selectWindowsAmd64Asset(release)?.name,
          'mihomo-windows-amd64-v1-v1.19.32.zip');
    });

    test('refuses unsupported optimized-only release', () {
      final release = MihomoReleaseInfo(
          version: 'v1.19.32',
          assets: <MihomoReleaseAsset>[asset(optimizedName)]);

      expect(MihomoReleaseApi.selectWindowsAmd64Asset(release), isNull);
    });
  });

  group('Mihomo integrity/version helpers', () {
    test('compares stable semantic versions numerically', () {
      expect(MihomoReleaseApi.compareStableVersions('v1.10.0', 'v1.9.99'),
          greaterThan(0));
      expect(MihomoReleaseApi.compareStableVersions('v2.0.0', 'v1.99.99'),
          greaterThan(0));
      expect(MihomoReleaseApi.compareStableVersions('v1.19.32', '1.19.32'), 0);
      expect(() => MihomoReleaseApi.compareStableVersions('latest', 'v1.0.0'),
          throwsFormatException);
    });

    test('compares full hashes without early exit for same-length values', () {
      expect(
          MihomoWindowsCoreUpdater.constantTimeEquals('ab12', 'ab12'), isTrue);
      expect(
          MihomoWindowsCoreUpdater.constantTimeEquals('ab12', 'ab13'), isFalse);
      expect(MihomoWindowsCoreUpdater.constantTimeEquals('abc', 'ab'), isFalse);
    });
  });
}
