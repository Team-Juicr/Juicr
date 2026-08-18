import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_addon_playback.dart';

void main() {
  test('parses direct and account-backed add-on media without exposing embeds', () {
    final candidates = parseTvAddonPlaybackCandidates(
      <Object?>[
        <String, Object?>{
          'name': 'Account stream',
          'title': '1080p',
          'url': 'https://media.invalid/playback?id=opaque',
          'type': 'video/mp4',
          'behaviorHints': <String, Object?>{
            'proxyHeaders': <String, Object?>{
              'request': <String, Object?>{'Referer': 'https://app.invalid/'},
            },
          },
        },
        <String, Object?>{
          'name': 'Direct stream',
          'url': 'https://media.invalid/master.m3u8',
        },
        <String, Object?>{
          'name': 'External page',
          'externalUrl': 'https://site.invalid/watch/123',
        },
      ],
      sourceId: 'addon-a',
    );

    expect(candidates, hasLength(2));
    expect(candidates.first.sourceType, 'mp4');
    expect(candidates.first.sourceClass, 'debrid');
    expect(candidates.first.quality, '1080P');
    expect(candidates.first.headers, <String, String>{
      'Referer': 'https://app.invalid/',
    });
    expect(candidates.last.sourceType, 'hls');
    expect(candidates.last.sourceClass, 'direct');
  });

  test('accepts progressive MP4 aliases for opaque signed URLs', () {
    for (final alias in <String>['mp4', 'video', 'video/mp4', 'application/mp4']) {
      final candidates = parseTvAddonPlaybackCandidates(
        <Object?>[
          <String, Object?>{
            'url': 'https://media.invalid/opaque?signature=value',
            'type': alias,
          },
        ],
        sourceId: 'addon-a',
      );
      expect(candidates.single.sourceType, 'mp4', reason: alias);
    }
  });

  test('derives a private codec compatibility rank from add-on metadata', () {
    final candidates = parseTvAddonPlaybackCandidates(
      <Object?>[
        <String, Object?>{
          'name': 'Movie 1080p H.264 AAC',
          'url': 'https://media.invalid/avc',
          'type': 'video/mp4',
        },
        <String, Object?>{
          'name': 'Movie 1080p HEVC 10bit Dolby Vision',
          'url': 'https://media.invalid/hevc',
          'type': 'video/mp4',
        },
      ],
      sourceId: 'addon-a',
    );

    expect(candidates, hasLength(2));
    expect(candidates.first.compatibilityRisk, 0);
    expect(candidates.last.compatibilityRisk, greaterThanOrEqualTo(7));
  });

  test('keeps descriptor-only P2P private for the TV runtime bridge', () {
    final streams = <Object?>[
      <String, Object?>{
        'name': 'Torrent',
        'infoHash': '0123456789abcdef0123456789abcdef01234567',
        'fileIdx': 0,
        'sources': <String>[
          'tracker:https://tracker.invalid/announce',
        ],
      },
      <String, Object?>{
        'url': 'magnet:?xt=urn:btih:0123456789abcdef',
      },
    ];

    expect(
      parseTvAddonPlaybackCandidates(streams, sourceId: 'addon-a'),
      isEmpty,
    );

    final candidates = parseTvAddonPlaybackCandidates(
      streams,
      sourceId: 'addon-a',
      allowP2p: true,
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.mediaUrl, 'juicr-p2p://pending/1');
    expect(candidates.single.sourceType, 'p2p');
    expect(candidates.single.sourceClass, 'p2p');
    expect(candidates.single.p2pDescriptor, isNotNull);
    expect(candidates.single.p2pDescriptor!.fileIdx, 0);
    expect(candidates.single.p2pDescriptor!.trackerCount, 1);
    expect(candidates.single.toString(), isNot(contains('0123456789abcdef')));
  });

  test('builds movie and exact episode add-on request IDs', () {
    expect(
      tvAddonPlaybackRequestIds(
        id: 'tmdb:424783',
        tmdbId: 424783,
        imdbId: 'tt4701182',
      ),
      <String>['tt4701182', 'tmdb:424783', '424783'],
    );
    expect(
      tvAddonPlaybackRequestIds(
        id: 'tmdb:48866',
        tmdbId: 48866,
        imdbId: 'tt2661044',
        season: 2,
        episode: 9,
      ),
      <String>['tt2661044:2:9', 'tmdb:48866:2:9', '48866:2:9'],
    );
  });
}
