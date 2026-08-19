import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juicr/src/release_updates.dart';
import 'package:juicr/src/release_update_assets.dart';

void main() {
  group('release APK assets', () {
    const tag = 'v1.2.3';
    final githubAssets = <GithubReleaseAsset>[
      GithubReleaseAsset(
        name: 'juicr-android-$tag-arm64-v8a.apk',
        size: 120,
        downloadUri: Uri.parse(
          'https://github.com/Team-Juicr/Juicr/releases/download/$tag/juicr-android-$tag-arm64-v8a.apk',
        ),
      ),
      GithubReleaseAsset(
        name: 'juicr-android-$tag-universal.apk',
        size: 220,
        downloadUri: Uri.parse(
          'https://github.com/Team-Juicr/Juicr/releases/download/$tag/juicr-android-$tag-universal.apk',
        ),
      ),
      GithubReleaseAsset(
        name: 'juicr-tv-$tag-arm64-v8a.apk',
        size: 320,
        downloadUri: Uri.parse(
          'https://github.com/Team-Juicr/Juicr/releases/download/$tag/juicr-tv-$tag-arm64-v8a.apk',
        ),
      ),
    ];

    Map<String, Object?> manifest({
      String manifestTag = tag,
      List<Map<String, Object?>>? assets,
    }) {
      return {
        'schemaVersion': 1,
        'tag': manifestTag,
        'assets': assets ??
            [
              {
                'name': 'juicr-android-$tag-arm64-v8a.apk',
                'size': 120,
                'sha256': 'a' * 64,
              },
              {
                'name': 'juicr-android-$tag-universal.apk',
                'size': 220,
                'sha256': 'b' * 64,
              },
              {
                'name': 'juicr-tv-$tag-arm64-v8a.apk',
                'size': 320,
                'sha256': 'c' * 64,
              },
            ],
      };
    }

    test('parses exact checksum-bound assets and selects Mobile ABI', () {
      final parsed = parseReleaseApkAssets(
        releaseTag: tag,
        githubAssets: githubAssets,
        manifestJson: manifest(),
      );

      final selected = selectReleaseApkAsset(
        assets: parsed,
        lane: ReleaseAppLane.android,
        supportedAbis: const ['arm64-v8a', 'armeabi-v7a'],
      );

      expect(selected, isNotNull);
      expect(selected!.abi, 'arm64-v8a');
      expect(selected.sha256, 'a' * 64);
      expect(selected.name, startsWith('juicr-android-'));
    });

    test('uses universal only when no supported lane ABI exists', () {
      final parsed = parseReleaseApkAssets(
        releaseTag: tag,
        githubAssets: githubAssets,
        manifestJson: manifest(),
      );

      final selected = selectReleaseApkAsset(
        assets: parsed,
        lane: ReleaseAppLane.android,
        supportedAbis: const ['x86_64'],
      );

      expect(selected?.abi, 'universal');
    });

    test('never selects a TV asset for Mobile', () {
      final parsed = parseReleaseApkAssets(
        releaseTag: tag,
        githubAssets: githubAssets,
        manifestJson: manifest(),
      );

      final selected = selectReleaseApkAsset(
        assets: parsed.where((asset) => asset.lane == ReleaseAppLane.tv),
        lane: ReleaseAppLane.android,
        supportedAbis: const ['arm64-v8a'],
      );

      expect(selected, isNull);
    });

    test('rejects unknown manifest fields and tag mismatch', () {
      expect(
        () => parseReleaseApkAssets(
          releaseTag: tag,
          githubAssets: githubAssets,
          manifestJson: {...manifest(), 'unexpected': true},
        ),
        throwsFormatException,
      );
      expect(
        () => parseReleaseApkAssets(
          releaseTag: tag,
          githubAssets: githubAssets,
          manifestJson: manifest(manifestTag: 'v9.9.9'),
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate, malformed hash, and size mismatch', () {
      final valid =
          (manifest()['assets']! as List).cast<Map<String, Object?>>();
      expect(
        () => parseReleaseApkAssets(
          releaseTag: tag,
          githubAssets: githubAssets,
          manifestJson: manifest(assets: [valid.first, valid.first]),
        ),
        throwsFormatException,
      );
      expect(
        () => parseReleaseApkAssets(
          releaseTag: tag,
          githubAssets: githubAssets,
          manifestJson: manifest(
            assets: [
              {...valid.first, 'sha256': 'ABC'},
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => parseReleaseApkAssets(
          releaseTag: tag,
          githubAssets: githubAssets,
          manifestJson: manifest(
            assets: [
              {...valid.first, 'size': 121},
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects hostile and query-bearing asset URLs', () {
      final hostile = [
        GithubReleaseAsset(
          name: githubAssets.first.name,
          size: githubAssets.first.size,
          downloadUri: Uri.parse('https://example.com/update.apk'),
        ),
      ];
      final firstManifest = {
        'schemaVersion': 1,
        'tag': tag,
        'assets': [
          {
            'name': githubAssets.first.name,
            'size': githubAssets.first.size,
            'sha256': 'a' * 64,
          },
        ],
      };

      expect(
        () => parseReleaseApkAssets(
          releaseTag: tag,
          githubAssets: hostile,
          manifestJson: firstManifest,
        ),
        throwsFormatException,
      );
    });
  });

  group('release update versions', () {
    test('treats a higher nightly sequence as newer', () {
      expect(
        isReleaseUpdateAvailable(
          installedVersion: '1.0.2-nightly.20260612.1',
          latestVersion: '1.0.2-nightly.20260612.5',
        ),
        isTrue,
      );
      expect(
        isReleaseUpdateAvailable(
          installedVersion: '1.0.2-nightly.20260612.5',
          latestVersion: '1.0.2-nightly.20260612.1',
        ),
        isFalse,
      );
    });

    test('treats a newer nightly date as newer', () {
      expect(
        isReleaseUpdateAvailable(
          installedVersion: '1.0.2-nightly.20260611.1',
          latestVersion: '1.0.2-nightly.20260612.1',
        ),
        isTrue,
      );
      expect(
        isReleaseUpdateAvailable(
          installedVersion: '1.0.2-nightly.20260612.5',
          latestVersion: '1.0.2-nightly.20260611.1',
        ),
        isFalse,
      );
    });

    test('treats a stable release as newer than its prerelease', () {
      expect(
        isReleaseUpdateAvailable(
          installedVersion: '1.0.2-nightly.20260612.5',
          latestVersion: '1.0.2',
        ),
        isTrue,
      );
    });
  });

  group('ReleaseUpdatesClient', () {
    test('hydrates only checksum-bound APK assets from the chosen release',
        () async {
      const tag = 'v1.2.3';
      final manifestUri = Uri.parse(
        'https://github.com/Team-Juicr/Juicr/releases/download/$tag/juicr-$tag-checksums.json',
      );
      final client = ReleaseUpdatesClient(
        client: MockClient((request) async {
          if (request.url == manifestUri) {
            return http.Response(
              jsonEncode({
                'schemaVersion': 1,
                'tag': tag,
                'assets': [
                  {
                    'name': 'juicr-android-$tag-arm64-v8a.apk',
                    'size': 120,
                    'sha256': 'a' * 64,
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode([
              {
                'draft': false,
                'prerelease': false,
                'tag_name': tag,
                'name': 'Juicr $tag',
                'body': 'Stable release',
                'published_at': '2026-06-12T10:00:00Z',
                'html_url':
                    'https://github.com/Team-Juicr/Juicr/releases/tag/$tag',
                'assets': [
                  {
                    'name': 'juicr-android-$tag-arm64-v8a.apk',
                    'size': 120,
                    'browser_download_url':
                        'https://github.com/Team-Juicr/Juicr/releases/download/$tag/juicr-android-$tag-arm64-v8a.apk',
                  },
                  {
                    'name': 'juicr-$tag-checksums.json',
                    'size': 200,
                    'browser_download_url': manifestUri.toString(),
                  },
                ],
              },
            ]),
            200,
          );
        }),
      );

      final release =
          await client.latestForChannel(ReleaseUpdateChannel.stable);

      expect(release.fromFallback, isFalse);
      expect(release.apkAssets, hasLength(1));
      expect(release.apkAssets.single.sha256, 'a' * 64);
    });

    test('keeps release notes but exposes no APK when manifest is invalid',
        () async {
      const tag = 'v1.2.3';
      final client = ReleaseUpdatesClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('.json')) {
            return http.Response(
                '{"schemaVersion":1,"tag":"wrong","assets":[]}', 200);
          }
          return http.Response(
            jsonEncode([
              {
                'draft': false,
                'prerelease': false,
                'tag_name': tag,
                'name': 'Juicr $tag',
                'body': 'Still readable',
                'published_at': '2026-06-12T10:00:00Z',
                'html_url':
                    'https://github.com/Team-Juicr/Juicr/releases/tag/$tag',
                'assets': [
                  {
                    'name': 'juicr-android-$tag-universal.apk',
                    'size': 120,
                    'browser_download_url':
                        'https://github.com/Team-Juicr/Juicr/releases/download/$tag/juicr-android-$tag-universal.apk',
                  },
                  {
                    'name': 'juicr-$tag-checksums.json',
                    'size': 20,
                    'browser_download_url':
                        'https://github.com/Team-Juicr/Juicr/releases/download/$tag/juicr-$tag-checksums.json',
                  },
                ],
              },
            ]),
            200,
          );
        }),
      );

      final release =
          await client.latestForChannel(ReleaseUpdateChannel.stable);

      expect(release.fromFallback, isFalse);
      expect(release.body, 'Still readable');
      expect(release.apkAssets, isEmpty);
    });

    test(
      'selects the highest matching nightly instead of the first response',
      () async {
        final client = ReleaseUpdatesClient(
          client: MockClient((request) async {
            return http.Response(
              jsonEncode([
                {
                  'draft': false,
                  'prerelease': true,
                  'tag_name': 'v1.0.2-nightly.20260612.1',
                  'name': 'Juicr 1.0.2-nightly.20260612.1 Nightly',
                  'body': 'Older nightly',
                  'published_at': '2026-06-12T08:00:00Z',
                  'html_url':
                      'https://github.com/Team-Juicr/Juicr/releases/tag/v1.0.2-nightly.20260612.1',
                },
                {
                  'draft': false,
                  'prerelease': true,
                  'tag_name': 'v1.0.2-nightly.20260612.5',
                  'name': 'Juicr 1.0.2-nightly.20260612.5 Nightly',
                  'body': 'Newer nightly',
                  'published_at': '2026-06-12T10:00:00Z',
                  'html_url':
                      'https://github.com/Team-Juicr/Juicr/releases/tag/v1.0.2-nightly.20260612.5',
                },
              ]),
              200,
            );
          }),
        );

        final release = await client.latestForChannel(
          ReleaseUpdateChannel.nightly,
        );

        expect(release.displayVersion, '1.0.2-nightly.20260612.5');
        expect(release.body, 'Newer nightly');
        expect(
          releaseDownloadUri(release).toString(),
          'https://github.com/Team-Juicr/Juicr/releases/tag/v1.0.2-nightly.20260612.5',
        );
      },
    );

    test('uses the releases page when a release URL is missing', () {
      final release = fallbackReleaseInfo(ReleaseUpdateChannel.stable);

      expect(releaseDownloadUri(release), juicrReleasesUri);
    });

    test('falls back when release URL is not the Juicr GitHub release page',
        () async {
      final client = ReleaseUpdatesClient(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode([
              {
                'draft': false,
                'prerelease': false,
                'tag_name': 'v1.0.2',
                'name': 'Juicr v1.0.2',
                'body': 'Stable release',
                'published_at': '2026-06-12T10:00:00Z',
                'html_url': 'https://example.com/download.apk',
              },
            ]),
            200,
          );
        }),
      );

      final release =
          await client.latestForChannel(ReleaseUpdateChannel.stable);

      expect(release.displayVersion, '1.0.2');
      expect(releaseDownloadUri(release), juicrReleasesUri);
    });
  });
}
