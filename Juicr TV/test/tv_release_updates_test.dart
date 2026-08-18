import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_release_update_assets.dart';

void main() {
  group('TV release APK assets', () {
    const tag = 'v1.2.3';
    final githubAssets = <TvGithubReleaseAsset>[
      TvGithubReleaseAsset(
        name: 'juicr-tv-$tag-x86_64.apk',
        size: 120,
        downloadUri: Uri.parse(
          'https://github.com/Team-Juicr/Juicr/releases/download/$tag/juicr-tv-$tag-x86_64.apk',
        ),
      ),
      TvGithubReleaseAsset(
        name: 'juicr-tv-$tag-universal.apk',
        size: 220,
        downloadUri: Uri.parse(
          'https://github.com/Team-Juicr/Juicr/releases/download/$tag/juicr-tv-$tag-universal.apk',
        ),
      ),
      TvGithubReleaseAsset(
        name: 'juicr-android-$tag-x86_64.apk',
        size: 320,
        downloadUri: Uri.parse(
          'https://github.com/Team-Juicr/Juicr/releases/download/$tag/juicr-android-$tag-x86_64.apk',
        ),
      ),
    ];

    Map<String, Object?> manifest({
      String manifestTag = tag,
      List<Map<String, Object?>>? assets,
    }) =>
        {
          'schemaVersion': 1,
          'tag': manifestTag,
          'assets': assets ??
              [
                {
                  'name': 'juicr-tv-$tag-x86_64.apk',
                  'size': 120,
                  'sha256': 'a' * 64,
                },
                {
                  'name': 'juicr-tv-$tag-universal.apk',
                  'size': 220,
                  'sha256': 'b' * 64,
                },
                {
                  'name': 'juicr-android-$tag-x86_64.apk',
                  'size': 320,
                  'sha256': 'c' * 64,
                },
              ],
        };

    test('selects TV ABI and never crosses to Mobile', () {
      final parsed = parseTvReleaseApkAssets(
        releaseTag: tag,
        githubAssets: githubAssets,
        manifestJson: manifest(),
      );

      final selected = selectTvReleaseApkAsset(
        assets: parsed,
        lane: TvReleaseAppLane.tv,
        supportedAbis: const ['x86_64'],
      );

      expect(selected?.abi, 'x86_64');
      expect(selected?.name, startsWith('juicr-tv-'));
      expect(
        selectTvReleaseApkAsset(
          assets: parsed.where(
            (asset) => asset.lane == TvReleaseAppLane.android,
          ),
          lane: TvReleaseAppLane.tv,
          supportedAbis: const ['x86_64'],
        ),
        isNull,
      );
    });

    test('uses TV universal fallback', () {
      final parsed = parseTvReleaseApkAssets(
        releaseTag: tag,
        githubAssets: githubAssets,
        manifestJson: manifest(),
      );
      expect(
        selectTvReleaseApkAsset(
          assets: parsed,
          lane: TvReleaseAppLane.tv,
          supportedAbis: const ['arm64-v8a'],
        )?.abi,
        'universal',
      );
    });

    test('rejects unknown fields, tag mismatch, and duplicate entries', () {
      expect(
        () => parseTvReleaseApkAssets(
          releaseTag: tag,
          githubAssets: githubAssets,
          manifestJson: {...manifest(), 'unknown': 1},
        ),
        throwsFormatException,
      );
      expect(
        () => parseTvReleaseApkAssets(
          releaseTag: tag,
          githubAssets: githubAssets,
          manifestJson: manifest(manifestTag: 'v9.9.9'),
        ),
        throwsFormatException,
      );
      final first = (manifest()['assets']! as List).first as Map<String, Object?>;
      expect(
        () => parseTvReleaseApkAssets(
          releaseTag: tag,
          githubAssets: githubAssets,
          manifestJson: manifest(assets: [first, first]),
        ),
        throwsFormatException,
      );
    });

    test('rejects malformed hash, mismatched size, and hostile URL', () {
      final first = (manifest()['assets']! as List).first as Map<String, Object?>;
      expect(
        () => parseTvReleaseApkAssets(
          releaseTag: tag,
          githubAssets: githubAssets,
          manifestJson: manifest(
            assets: [
              {...first, 'sha256': 'ABC'},
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => parseTvReleaseApkAssets(
          releaseTag: tag,
          githubAssets: githubAssets,
          manifestJson: manifest(
            assets: [
              {...first, 'size': 121},
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => parseTvReleaseApkAssets(
          releaseTag: tag,
          githubAssets: [
            TvGithubReleaseAsset(
              name: githubAssets.first.name,
              size: githubAssets.first.size,
              downloadUri: Uri.parse('https://example.com/update.apk'),
            ),
          ],
          manifestJson: manifest(assets: [first]),
        ),
        throwsFormatException,
      );
    });
  });
}
