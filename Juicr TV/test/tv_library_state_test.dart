import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_library_state.dart';

void main() {
  test('exports a mobile-compatible account library snapshot', () {
    const state = TvLibraryState(
      likedKeys: {'movie:movie-1'},
      recentItems: [
        TvRecentItemSnapshot(
          key: 'movie:movie-1',
          itemId: 'movie-1',
          itemType: 'movie',
          title: 'Movie One',
          year: '2026',
          updatedAtMillis: 1000,
        ),
        TvRecentItemSnapshot(
          key: 'series:series-1',
          itemId: 'series-1',
          itemType: 'series',
          title: 'Series One',
          year: '2026',
          updatedAtMillis: 1001,
        ),
      ],
      progress: {
        'movie:movie-1:1:1': TvPlaybackProgress(
          key: 'movie:movie-1:1:1',
          positionMillis: 10 * 60 * 1000,
          durationMillis: 40 * 60 * 1000,
          updatedAtMillis: 2000,
        ),
        'series:series-1:1:1': TvPlaybackProgress(
          key: 'series:series-1:1:1',
          positionMillis: 20 * 60 * 1000,
          durationMillis: 40 * 60 * 1000,
          updatedAtMillis: 3000,
        ),
      },
      completedKeys: {'series:series-1:1:1'},
    );

    final snapshot = state.toMobileLibraryBackup();

    expect(snapshot['schema'], 'juicr.library.backup.v1');
    expect(snapshot['lists'], isEmpty);
    expect(snapshot['saved'], hasLength(1));
    expect(snapshot['continueWatching'], hasLength(1));
    expect(snapshot['completedWatching'], hasLength(1));

    final saved = (snapshot['saved'] as List).single as Map<String, Object?>;
    expect(saved['id'], 'movie-1');
    expect(saved['type'], 'movie');
    expect(saved['name'], 'Movie One');

    final progress =
        (snapshot['continueWatching'] as List).single as Map<String, Object?>;
    expect(progress['key'], 'movie:movie-1:1:1');
    expect(progress['watchedSeconds'], 600);
    expect(progress['credibleWatchedSeconds'], 600);
    expect(progress['durationSeconds'], 2400);
    expect(progress['progress'], closeTo(0.25, 0.001));

    final completed =
        (snapshot['completedWatching'] as List).single as Map<String, Object?>;
    expect(completed['key'], 'series:series-1:1:1');
    expect(completed['credibleWatchedSeconds'], 1200);
    expect(completed['durationSeconds'], 2400);
    expect(state.activeWatchSeconds, 1800);
  });

  test('merges a mobile-compatible account library snapshot into TV state', () {
    final state = const TvLibraryState().mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': [
        {
          'id': 'movie-2',
          'type': 'movie',
          'name': 'Movie Two',
          'year': '2025',
        },
      ],
      'continueWatching': [
        {
          'key': 'movie:movie-2:1:1',
          'item': {
            'id': 'movie-2',
            'type': 'movie',
            'name': 'Movie Two',
            'year': '2025',
          },
          'watchedSeconds': 300,
          'durationSeconds': 1800,
          'updatedAt': DateTime.fromMillisecondsSinceEpoch(4000).toIso8601String(),
        },
      ],
      'completedWatching': [
        {
          'key': 'series:series-2:1:1',
          'item': {
            'id': 'series-2',
            'type': 'series',
            'name': 'Series Two',
            'year': '2026',
          },
          'watchedSeconds': 1800,
          'durationSeconds': 1800,
          'completedAt': DateTime.fromMillisecondsSinceEpoch(5000).toIso8601String(),
        },
      ],
    });

    expect(state.likedKeys, contains('movie:movie-2'));
    expect(state.recentItems.map((item) => item.key), contains('movie:movie-2'));
    expect(state.progress['movie:movie-2:1:1']?.positionMillis, 300000);
    expect(state.completedKeys, contains('series:series-2:1:1'));
    expect(state.progress['series:series-2:1:1']?.durationMillis, 1800000);
  });
}
