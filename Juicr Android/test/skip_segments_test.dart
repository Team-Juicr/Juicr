import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juicr/src/skip_segments.dart';

void main() {
  test('uses Juicr skip segment endpoint by default', () {
    expect(
      defaultPlaybackSkipSegmentEndpoint().toString(),
      'https://api.juicr.app/skip-segments',
    );
  });

  test('loads intro recap and outro segments from a neutral payload', () async {
    final client = PlaybackSkipSegmentClient(
      client: MockClient((request) async {
        expect(request.url.queryParameters['tmdb_id'], '76479');
        expect(request.url.queryParameters['imdb_id'], 'tt0944947');
        expect(request.url.queryParameters['season'], '1');
        expect(request.url.queryParameters['episode'], '2');
        expect(request.url.queryParameters['duration_ms'], '3588000');
        return http.Response(
          jsonEncode({
            'segments': [
              {'type': 'intro', 'start_sec': 0, 'end_sec': 27},
              {'kind': 'recap', 'start': '00:00:05', 'end': '00:00:45'},
              {'segment_type': 'outro', 'start_time': 3480, 'end_time': 3588},
            ],
          }),
          200,
        );
      }),
      endpoint: Uri.parse('https://example.test/segments'),
    );

    final segments = await client.lookup(
      tmdbId: 76479,
      imdbId: 'tt0944947',
      season: 1,
      episode: 2,
      duration: const Duration(minutes: 59, seconds: 48),
    );

    expect(segments.map((segment) => segment.label), [
      'Skip intro',
      'Skip recap',
      'Skip outro',
    ]);
    expect(segments[1].start, const Duration(seconds: 5));
    expect(segments[1].end, const Duration(seconds: 45));
    expect(segments.first.end, const Duration(seconds: 27));
  });

  test(
    'does not request remote segments without episode identifiers',
    () async {
      final client = PlaybackSkipSegmentClient(
        client: MockClient((request) async {
          fail('segment lookup should not run without complete identifiers');
        }),
        endpoint: Uri.parse('https://example.test/segments'),
      );

      final segments = await client.lookup(
        tmdbId: 76479,
        imdbId: 'tt0944947',
        season: null,
        episode: 2,
        duration: const Duration(minutes: 59),
      );

      expect(segments, isEmpty);
    },
  );

  test('can request remote segments with tmdb identity only', () async {
    final client = PlaybackSkipSegmentClient(
      client: MockClient((request) async {
        expect(request.url.queryParameters['tmdb_id'], '76479');
        expect(request.url.queryParameters['imdb_id'], isNull);
        return http.Response(
          jsonEncode({
            'segments': [
              {'type': 'intro', 'start_sec': 0, 'end_sec': 27},
            ],
          }),
          200,
        );
      }),
      endpoint: Uri.parse('https://example.test/segments'),
    );

    final segments = await client.lookup(
      tmdbId: 76479,
      imdbId: null,
      season: 1,
      episode: 1,
      duration: null,
    );

    expect(segments.single.label, 'Skip intro');
    expect(segments.single.end, const Duration(seconds: 27));
  });

  test('selects the active skip segment for intro recap and outro windows', () {
    final segments = parsePlaybackSkipSegments([
      {'type': 'intro', 'start': 0, 'end': 90},
      {'type': 'recap', 'start': 120, 'end': 165},
      {'type': 'outro', 'start': 3500, 'end': 3540},
      {'type': 'preview', 'start': 3550, 'end': 3580},
    ]);
    const duration = Duration(hours: 1);

    expect(
      activePlaybackSkipSegment(
        segments,
        const Duration(seconds: 20),
        duration,
      )?.label,
      'Skip intro',
    );
    expect(
      activePlaybackSkipSegment(
        segments,
        const Duration(seconds: 130),
        duration,
      )?.label,
      'Skip recap',
    );
    expect(
      activePlaybackSkipSegment(
        segments,
        const Duration(seconds: 3510),
        duration,
      )?.label,
      'Skip outro',
    );
    expect(
      activePlaybackSkipSegment(
        segments,
        const Duration(seconds: 3555),
        duration,
      )?.label,
      'Skip preview',
    );
    expect(
      activePlaybackSkipSegment(
        segments,
        const Duration(seconds: 200),
        duration,
      ),
      isNull,
    );
  });

  test('uses fixed skip fallback only for short local opening windows', () {
    expect(allowFixedSkipSegmentFallback(season: 1, episode: 1), isFalse);
    expect(allowFixedSkipSegmentFallback(season: null, episode: null), isTrue);
    expect(defaultFixedIntroSkipTarget(), const Duration(seconds: 30));
  });
}
