import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juicr/src/release_updates.dart';

void main() {
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
                },
                {
                  'draft': false,
                  'prerelease': true,
                  'tag_name': 'v1.0.2-nightly.20260612.5',
                  'name': 'Juicr 1.0.2-nightly.20260612.5 Nightly',
                  'body': 'Newer nightly',
                  'published_at': '2026-06-12T10:00:00Z',
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
      },
    );
  });
}
