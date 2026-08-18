import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_library_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ordinary progress updates cannot lower a saved resume anchor', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final store = await TvLibraryStateStore.load();
    const key = 'movie:tmdb:24428:1:1';

    await store.updateProgress(
      key: key,
      positionMillis: 142000,
      credibleWatchedMillis: 30000,
      durationMillis: 8575000,
    );
    await store.updateProgress(
      key: key,
      positionMillis: 1000,
      credibleWatchedMillis: 45000,
    );

    final progress = store.progressFor(key);
    expect(progress?.positionMillis, 142000);
    expect(progress?.credibleWatchedMillis, 45000);
    expect(progress?.durationMillis, 8575000);
  });

  test('exports a mobile-compatible account library snapshot', () {
    const state = TvLibraryState(
      likedKeys: {'movie:movie-1'},
      libraryLists: [
        TvLibraryList(
          id: 'list-1',
          name: 'Weekend',
          itemKeys: ['movie:movie-1', 'series:series-1'],
          createdAtMillis: 900,
          updatedAtMillis: 1200,
        ),
      ],
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
    expect(snapshot['lists'], hasLength(1));
    expect(snapshot['saved'], hasLength(1));
    expect(snapshot['continueWatching'], hasLength(1));
    expect(snapshot['completedWatching'], hasLength(1));

    final list = (snapshot['lists'] as List).single as Map<String, Object?>;
    expect(list['id'], 'list-1');
    expect(list['name'], 'Weekend');
    expect(list['itemIds'], ['movie:movie-1', 'series:series-1']);

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
      'lists': [
        {
          'id': 'list-2',
          'name': 'Watch with family',
          'itemIds': ['movie:movie-2', 'series:series-2'],
          'createdAt': DateTime.fromMillisecondsSinceEpoch(3500).toIso8601String(),
          'updatedAt': DateTime.fromMillisecondsSinceEpoch(5500).toIso8601String(),
        },
      ],
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
    expect(state.libraryLists, hasLength(1));
    expect(state.libraryLists.single.name, 'Watch with family');
    expect(state.libraryLists.single.itemKeys, ['movie:movie-2', 'series:series-2']);
    expect(state.recentItems.map((item) => item.key), contains('movie:movie-2'));
    expect(state.progress['movie:movie-2:1:1']?.positionMillis, 300000);
    expect(state.completedKeys, contains('series:series-2:1:1'));
    expect(state.progress['series:series-2:1:1']?.durationMillis, 1800000);
  });

  test('normalizes TV library lists and preserves recent updates first', () {
    const state = TvLibraryState(
      libraryLists: [
        TvLibraryList(
          id: 'list-a',
          name: '  My   List  ',
          itemKeys: ['movie:one', 'movie:one', 'series:two'],
          createdAtMillis: 1,
          updatedAtMillis: 10,
        ),
        TvLibraryList(
          id: 'list-b',
          name: '',
          itemKeys: ['movie:three'],
          createdAtMillis: 2,
          updatedAtMillis: 30,
        ),
      ],
    );

    final normalized = state.normalized();

    expect(normalized.libraryLists.map((list) => list.id), ['list-b', 'list-a']);
    expect(normalized.libraryLists.first.name, 'Untitled list');
    expect(normalized.libraryLists.last.name, 'My List');
    expect(normalized.libraryLists.last.itemKeys, ['movie:one', 'series:two']);
  });

  test('keeps credible watch time separate from resume position', () {
    const state = TvLibraryState(
      recentItems: [
        TvRecentItemSnapshot(
          key: 'movie:movie-1',
          itemId: 'movie-1',
          itemType: 'movie',
          title: 'Movie One',
          updatedAtMillis: 1000,
        ),
      ],
      progress: {
        'movie:movie-1:1:1': TvPlaybackProgress(
          key: 'movie:movie-1:1:1',
          positionMillis: 30 * 60 * 1000,
          credibleWatchedMillis: 5 * 60 * 1000,
          durationMillis: 40 * 60 * 1000,
          updatedAtMillis: 2000,
        ),
      },
    );

    final snapshot = state.toMobileLibraryBackup();
    final progress =
        (snapshot['continueWatching'] as List).single as Map<String, Object?>;

    expect(progress['watchedSeconds'], 1800);
    expect(progress['credibleWatchedSeconds'], 300);
    expect(state.activeWatchSeconds, 300);
    expect(
      TvLibraryState.fromEncodedJson(state.toEncodedJson())
          .progress['movie:movie-1:1:1']
          ?.credibleWatchedMillis,
      300000,
    );
  });

  test('merges remote snapshot into existing unsynced local state', () {
    const local = TvLibraryState(
      likedKeys: {'movie:local'},
      recentItems: [
        TvRecentItemSnapshot(
          key: 'movie:local',
          itemId: 'local',
          itemType: 'movie',
          title: 'Local Movie',
          updatedAtMillis: 1000,
        ),
      ],
    );

    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': [
        {'id': 'remote', 'type': 'movie', 'name': 'Remote Movie'},
      ],
      'lists': const <Object?>[],
      'continueWatching': const <Object?>[],
      'completedWatching': const <Object?>[],
    });

    expect(merged.likedKeys, containsAll({'movie:local', 'movie:remote'}));
    expect(
      merged.recentItems.map((item) => item.key),
      containsAll({'movie:local', 'movie:remote'}),
    );
  });

  test('remote progress cannot lower a preserved local resume anchor', () {
    const local = TvLibraryState(
      recentItems: [
        TvRecentItemSnapshot(
          key: 'movie:bumblebee',
          itemId: 'bumblebee',
          itemType: 'movie',
          title: 'Bumblebee',
          updatedAtMillis: 5000,
        ),
      ],
      progress: {
        'movie:bumblebee:1:1': TvPlaybackProgress(
          key: 'movie:bumblebee:1:1',
          positionMillis: 2296 * 1000,
          credibleWatchedMillis: 900 * 1000,
          durationMillis: 6833 * 1000,
          updatedAtMillis: 5000,
        ),
      },
      completedKeys: {'movie:bumblebee:1:1'},
    );

    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': const <Object?>[],
      'continueWatching': [
        {
          'key': 'movie:bumblebee:1:1',
          'item': {
            'id': 'bumblebee',
            'type': 'movie',
            'name': 'Bumblebee',
          },
          'watchedSeconds': 0,
          'credibleWatchedSeconds': 0,
          'durationSeconds': 6833,
          'updatedAt': DateTime.fromMillisecondsSinceEpoch(6000).toIso8601String(),
        },
      ],
      'completedWatching': const <Object?>[],
    });

    expect(
      merged.progress['movie:bumblebee:1:1']?.positionMillis,
      2296 * 1000,
    );
    expect(
      merged.progress['movie:bumblebee:1:1']?.credibleWatchedMillis,
      900 * 1000,
    );
    expect(merged.completedKeys, contains('movie:bumblebee:1:1'));
  });

  test('remote opaque progress migrates to the exact canonical TMDB key', () {
    final merged = const TvLibraryState().mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': const <Object?>[],
      'continueWatching': [
        {
          'key': 'movie:add-on-bumblebee:1:1',
          'item': {
            'id': 'add-on-bumblebee',
            'type': 'movie',
            'name': 'Bumblebee',
            'tmdbId': 424783,
          },
          'watchedSeconds': 321,
          'credibleWatchedSeconds': 120,
          'durationSeconds': 6833,
          'updatedAt': DateTime.fromMillisecondsSinceEpoch(6000).toIso8601String(),
        },
      ],
      'completedWatching': const <Object?>[],
    });

    expect(merged.progress, contains('movie:tmdb:424783:1:1'));
    expect(merged.progress, isNot(contains('movie:add-on-bumblebee:1:1')));
    expect(merged.recentItems.single.key, 'movie:tmdb:424783');
  });

  test('equal remote position cannot lower metadata or clear completion', () {
    const key = 'movie:tmdb:424783:1:1';
    const local = TvLibraryState(
      progress: {
        key: TvPlaybackProgress(
          key: key,
          positionMillis: 500000,
          credibleWatchedMillis: 300000,
          durationMillis: 6833000,
          updatedAtMillis: 5000,
        ),
      },
      completedKeys: {key},
    );

    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': const <Object?>[],
      'continueWatching': [
        {
          'key': 'movie:opaque-bumblebee:1:1',
          'item': {
            'id': 'opaque-bumblebee',
            'type': 'movie',
            'name': 'Bumblebee',
            'tmdbId': 424783,
          },
          'watchedSeconds': 500,
          'credibleWatchedSeconds': 10,
          'durationSeconds': 6000,
          'updatedAt': DateTime.fromMillisecondsSinceEpoch(6000).toIso8601String(),
        },
      ],
      'completedWatching': const <Object?>[],
    });

    expect(merged.progress[key]?.credibleWatchedMillis, 300000);
    expect(merged.progress[key]?.durationMillis, 6833000);
    expect(merged.completedKeys, contains(key));
  });

  test('series and animation imports retain typed canonical episode identity', () {
    final merged = const TvLibraryState().mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': const <Object?>[],
      'continueWatching': [
        {
          'key': 'series:opaque-series:2:9',
          'item': {
            'id': 'opaque-series',
            'type': 'series',
            'name': 'The 100',
            'tmdbId': 48866,
          },
          'watchedSeconds': 100,
          'durationSeconds': 2500,
        },
        {
          'key': 'animation:opaque-animation:1:1',
          'item': {
            'id': 'opaque-animation',
            'type': 'animation',
            'name': 'Animation Control',
            'tmdbId': 9001,
          },
          'watchedSeconds': 200,
          'durationSeconds': 1500,
        },
      ],
      'completedWatching': const <Object?>[],
    });

    expect(merged.progress, contains('series:tmdb:48866:2:9'));
    expect(merged.progress, contains('animation:tmdb:9001:1:1'));
  });

  test('normalization atomically migrates legacy library aliases', () {
    const legacyKey = 'movie:legacy-bumblebee';
    const canonicalKey = 'movie:tmdb:424783';
    final normalized = const TvLibraryState(
      likedKeys: {legacyKey},
      libraryLists: [
        TvLibraryList(
          id: 'saved-list',
          name: 'Saved',
          itemKeys: [legacyKey],
          createdAtMillis: 1,
          updatedAtMillis: 1,
        ),
      ],
      recentItems: [
        TvRecentItemSnapshot(
          key: legacyKey,
          itemId: 'legacy-bumblebee',
          itemType: 'movie',
          title: 'Bumblebee',
          tmdbId: 424783,
          updatedAtMillis: 1,
        ),
      ],
      progress: {
        '$legacyKey:1:1': TvPlaybackProgress(
          key: '$legacyKey:1:1',
          positionMillis: 200000,
          durationMillis: 6833000,
          updatedAtMillis: 1,
        ),
      },
      completedKeys: {'$legacyKey:1:1'},
    ).normalized();

    expect(normalized.likedKeys, {canonicalKey});
    expect(normalized.libraryLists.single.itemKeys, [canonicalKey]);
    expect(normalized.recentItems.single.key, canonicalKey);
    expect(normalized.progress, contains('$canonicalKey:1:1'));
    expect(normalized.completedKeys, {'$canonicalKey:1:1'});
  });

  test('TV export import round trip preserves canonical TMDB identity', () {
    const key = 'movie:tmdb:424783';
    const state = TvLibraryState(
      likedKeys: {key},
      recentItems: [
        TvRecentItemSnapshot(
          key: key,
          itemId: 'legacy-bumblebee',
          itemType: 'movie',
          title: 'Bumblebee',
          tmdbId: 424783,
          imdbId: 'tt4701182',
          updatedAtMillis: 1,
        ),
      ],
      progress: {
        '$key:1:1': TvPlaybackProgress(
          key: '$key:1:1',
          positionMillis: 300000,
          durationMillis: 6833000,
          updatedAtMillis: 1,
        ),
      },
    );

    final backup = state.toMobileLibraryBackup();
    final restored = const TvLibraryState().mergeMobileLibraryBackup(backup);

    expect(restored.likedKeys, contains(key));
    expect(restored.recentItems.single.tmdbId, 424783);
    expect(restored.recentItems.single.imdbId, 'tt4701182');
    expect(restored.progress, contains('$key:1:1'));
  });

  test('live TV import remains keyed by its exact channel identity', () {
    final merged = const TvLibraryState().mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': [
        {
          'id': 'channel-a',
          'type': 'liveTv',
          'name': 'Channel A',
          'tmdbId': 424783,
        },
      ],
      'lists': const <Object?>[],
      'continueWatching': const <Object?>[],
      'completedWatching': const <Object?>[],
    });

    expect(merged.likedKeys, contains('live:channel-a'));
    expect(merged.likedKeys, isNot(contains('live:tmdb:424783')));
  });

  test('legacy live TV aliases never contribute active watch time', () {
    const state = TvLibraryState(
      recentItems: [
        TvRecentItemSnapshot(
          key: 'liveTv:channel-a',
          itemId: 'channel-a',
          itemType: 'liveTv',
          title: 'Channel A',
          updatedAtMillis: 1000,
        ),
      ],
      progress: {
        'liveTv:channel-a:1:1': TvPlaybackProgress(
          key: 'liveTv:channel-a:1:1',
          positionMillis: 10 * 60 * 1000,
          credibleWatchedMillis: 10 * 60 * 1000,
          durationMillis: 30 * 60 * 1000,
          updatedAtMillis: 2000,
        ),
      },
    );

    expect(state.normalized().recentItems.single.key, 'live:channel-a');
    expect(state.activeWatchSeconds, 0);
  });

  test('orphaned live TV progress never contributes active watch time', () {
    for (final key in const [
      'live:channel-a:1:1',
      'liveTv:channel-a:1:1',
    ]) {
      final state = TvLibraryState(
        progress: {
          key: TvPlaybackProgress(
            key: key,
            positionMillis: 10 * 60 * 1000,
            credibleWatchedMillis: 10 * 60 * 1000,
            durationMillis: 30 * 60 * 1000,
            updatedAtMillis: 2000,
          ),
        },
      );

      expect(state.activeWatchSeconds, 0, reason: key);
    }
  });

  test('equal completed import can advance completion without lowering metadata', () {
    const key = 'movie:tmdb:424783:1:1';
    const local = TvLibraryState(
      progress: {
        key: TvPlaybackProgress(
          key: key,
          positionMillis: 500000,
          credibleWatchedMillis: 300000,
          durationMillis: 6833000,
          updatedAtMillis: 5000,
        ),
      },
    );
    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': const <Object?>[],
      'continueWatching': const <Object?>[],
      'completedWatching': [
        {
          'key': 'movie:opaque:1:1',
          'item': {
            'id': 'opaque',
            'type': 'movie',
            'name': 'Bumblebee',
            'tmdbId': 424783,
          },
          'watchedSeconds': 500,
          'credibleWatchedSeconds': 10,
          'durationSeconds': 6000,
          'completedAt': DateTime.fromMillisecondsSinceEpoch(6000).toIso8601String(),
        },
      ],
    });

    expect(merged.completedKeys, contains(key));
    expect(merged.progress[key]?.credibleWatchedMillis, 300000);
    expect(merged.progress[key]?.durationMillis, 6833000);
  });

  test('higher remote position preserves larger credible time and duration', () {
    const key = 'movie:tmdb:424783:1:1';
    const local = TvLibraryState(
      progress: {
        key: TvPlaybackProgress(
          key: key,
          positionMillis: 500000,
          credibleWatchedMillis: 400000,
          durationMillis: 6833000,
          updatedAtMillis: 5000,
        ),
      },
    );
    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': const <Object?>[],
      'continueWatching': [
        {
          'key': 'movie:opaque:1:1',
          'item': {
            'id': 'opaque',
            'type': 'movie',
            'name': 'Bumblebee',
            'tmdbId': 424783,
          },
          'watchedSeconds': 600,
          'credibleWatchedSeconds': 100,
          'durationSeconds': 6000,
        },
      ],
      'completedWatching': const <Object?>[],
    });

    expect(merged.progress[key]?.positionMillis, 600000);
    expect(merged.progress[key]?.credibleWatchedMillis, 400000);
    expect(merged.progress[key]?.durationMillis, 6833000);
  });

  test('completion merges independently from resume position', () {
    const key = 'movie:tmdb:424783:1:1';
    const completedLocal = TvLibraryState(
      progress: {
        key: TvPlaybackProgress(
          key: key,
          positionMillis: 500000,
          durationMillis: 6833000,
          updatedAtMillis: 1,
        ),
      },
      completedKeys: {key},
    );
    final continued = completedLocal.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': const <Object?>[],
      'continueWatching': [
        {
          'key': 'movie:opaque:1:1',
          'item': {
            'id': 'opaque',
            'type': 'movie',
            'name': 'Bumblebee',
            'tmdbId': 424783,
          },
          'watchedSeconds': 600,
          'durationSeconds': 6833,
        },
      ],
      'completedWatching': const <Object?>[],
    });
    expect(continued.completedKeys, contains(key));

    const unfinishedLocal = TvLibraryState(
      progress: {
        key: TvPlaybackProgress(
          key: key,
          positionMillis: 700000,
          durationMillis: 6833000,
          updatedAtMillis: 1,
        ),
      },
    );
    final completed = unfinishedLocal.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': const <Object?>[],
      'continueWatching': const <Object?>[],
      'completedWatching': [
        {
          'key': 'movie:opaque:1:1',
          'item': {
            'id': 'opaque',
            'type': 'movie',
            'name': 'Bumblebee',
            'tmdbId': 424783,
          },
          'watchedSeconds': 600,
          'durationSeconds': 6833,
        },
      ],
    });
    expect(completed.completedKeys, contains(key));
    expect(completed.progress[key]?.positionMillis, 700000);
  });

  test('canonical snapshot collision preserves identity metadata', () {
    final normalized = const TvLibraryState(
      recentItems: [
        TvRecentItemSnapshot(
          key: 'movie:legacy',
          itemId: 'legacy',
          itemType: 'movie',
          title: 'Older title',
          tmdbId: 424783,
          imdbId: 'tt4701182',
          updatedAtMillis: 1,
        ),
        TvRecentItemSnapshot(
          key: 'movie:tmdb:424783',
          itemId: 'newer',
          itemType: 'movie',
          title: 'Bumblebee',
          tmdbId: 424783,
          updatedAtMillis: 2,
        ),
      ],
    ).normalized();

    expect(normalized.recentItems.single.title, 'Bumblebee');
    expect(normalized.recentItems.single.imdbId, 'tt4701182');
  });

  test('same canonical account import merges snapshot identity and freshness', () {
    const key = 'movie:tmdb:424783';
    const local = TvLibraryState(
      recentItems: [
        TvRecentItemSnapshot(
          key: key,
          itemId: 'local-bumblebee',
          itemType: 'movie',
          title: 'Current Bumblebee',
          tmdbId: 424783,
          imdbId: 'tt4701182',
          updatedAtMillis: 5000,
        ),
      ],
    );
    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': [
        {
          'id': 'remote-bumblebee',
          'type': 'movie',
          'name': 'Older Bumblebee',
          'tmdbId': 424783,
          'updatedAtMillis': 1000,
        },
      ],
      'lists': const <Object?>[],
      'continueWatching': const <Object?>[],
      'completedWatching': const <Object?>[],
    });

    expect(merged.recentItems.single.title, 'Current Bumblebee');
    expect(merged.recentItems.single.imdbId, 'tt4701182');
  });

  test('timestamp-less progress cannot replace fresher local snapshot metadata',
      () {
    const key = 'movie:tmdb:424783';
    const progressKey = '$key:1:1';
    const local = TvLibraryState(
      recentItems: [
        TvRecentItemSnapshot(
          key: key,
          itemId: 'local-bumblebee',
          itemType: 'movie',
          title: 'Bumblebee',
          tmdbId: 424783,
          imdbId: 'tt4701182',
          updatedAtMillis: 5000,
        ),
      ],
      progress: {
        progressKey: TvPlaybackProgress(
          key: progressKey,
          positionMillis: 120000,
          durationMillis: 6833000,
          updatedAtMillis: 5000,
        ),
      },
    );

    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': const <Object?>[],
      'continueWatching': [
        {
          'key': 'movie:stale-bumblebee:1:1',
          'item': {
            'id': 'stale-bumblebee',
            'type': 'movie',
            'name': 'Old Bumblebee Copy',
            'tmdbId': 424783,
          },
          'watchedSeconds': 240,
          'durationSeconds': 6833,
        },
      ],
      'completedWatching': const <Object?>[],
    });

    expect(merged.progress[progressKey]?.positionMillis, 240000);
    expect(merged.recentItems.single.title, 'Bumblebee');
    expect(merged.recentItems.single.imdbId, 'tt4701182');
    expect(merged.recentItems.single.updatedAtMillis, 5000);
  });

  test('calendar-invalid progress timestamp cannot become authoritative', () {
    const key = 'movie:tmdb:424783';
    const local = TvLibraryState(
      recentItems: [
        TvRecentItemSnapshot(
          key: key,
          itemId: 'local-bumblebee',
          itemType: 'movie',
          title: 'Bumblebee',
          tmdbId: 424783,
          imdbId: 'tt4701182',
          updatedAtMillis: 5000,
        ),
      ],
    );

    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': const <Object?>[],
      'continueWatching': [
        {
          'key': 'movie:stale-bumblebee:1:1',
          'item': {
            'id': 'stale-bumblebee',
            'type': 'movie',
            'name': 'Malformed Date Copy',
            'tmdbId': 424783,
          },
          'watchedSeconds': 240,
          'durationSeconds': 6833,
          'updatedAt': '2026-02-31T12:00:00.000',
        },
      ],
      'completedWatching': const <Object?>[],
    });

    expect(merged.recentItems.single.title, 'Bumblebee');
    expect(merged.recentItems.single.imdbId, 'tt4701182');
    expect(merged.recentItems.single.updatedAtMillis, 5000);
  });

  test('calendar-invalid saved timestamp cannot replace fresher metadata', () {
    const key = 'movie:tmdb:424783';
    const local = TvLibraryState(
      recentItems: [
        TvRecentItemSnapshot(
          key: key,
          itemId: 'local-bumblebee',
          itemType: 'movie',
          title: 'Bumblebee',
          tmdbId: 424783,
          imdbId: 'tt4701182',
          updatedAtMillis: 5000,
        ),
      ],
    );

    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': [
        {
          'id': 'stale-bumblebee',
          'type': 'movie',
          'name': 'Malformed Saved Copy',
          'tmdbId': 424783,
          'updatedAt': '2026-02-31T12:00:00.000',
        },
      ],
      'lists': const <Object?>[],
      'continueWatching': const <Object?>[],
      'completedWatching': const <Object?>[],
    });

    expect(merged.recentItems.single.title, 'Bumblebee');
    expect(merged.recentItems.single.imdbId, 'tt4701182');
    expect(merged.recentItems.single.updatedAtMillis, 5000);
  });

  test('invalid list time and offset cannot replace a fresher local list', () {
    const local = TvLibraryState(
      likedKeys: {'movie:tmdb:424783'},
      libraryLists: [
        TvLibraryList(
          id: 'list-1',
          name: 'Current list',
          itemKeys: ['movie:tmdb:424783'],
          createdAtMillis: 1000,
          updatedAtMillis: 5000,
        ),
      ],
    );

    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': [
        {
          'id': 'list-1',
          'name': 'Malformed remote list',
          'itemIds': ['movie:tmdb:999'],
          'createdAt': '2026-01-01T25:00:00.000',
          'updatedAt': '2026-01-01T12:00:00.000+25:00',
        },
      ],
      'continueWatching': const <Object?>[],
      'completedWatching': const <Object?>[],
    });

    expect(merged.libraryLists.single.name, 'Current list');
    expect(merged.libraryLists.single.itemKeys, ['movie:tmdb:424783']);
    expect(merged.libraryLists.single.updatedAtMillis, 5000);
    expect(merged.likedKeys, {'movie:tmdb:424783'});
  });

  test('invalid first-seen list cannot add saved membership', () {
    const local = TvLibraryState(
      likedKeys: {'movie:tmdb:424783'},
    );

    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': [
        {
          'id': 'unknown-list',
          'name': 'Malformed remote list',
          'itemIds': ['movie:tmdb:999'],
          'createdAt': 'not-a-time',
          'updatedAt': '2026-02-31T12:00:00.000',
        },
      ],
      'continueWatching': const <Object?>[],
      'completedWatching': const <Object?>[],
    });

    expect(merged.libraryLists, isEmpty);
    expect(merged.likedKeys, {'movie:tmdb:424783'});
  });

  test('malformed list membership cannot replace or create lists', () {
    const local = TvLibraryState(
      likedKeys: {'movie:tmdb:424783'},
      libraryLists: [
        TvLibraryList(
          id: 'list-1',
          name: 'Current list',
          itemKeys: ['movie:tmdb:424783'],
          createdAtMillis: 1000,
          updatedAtMillis: 5000,
        ),
      ],
    );

    final merged = local.mergeMobileLibraryBackup({
      'schema': 'juicr.library.backup.v1',
      'saved': const <Object?>[],
      'lists': [
        {
          'id': 'list-1',
          'name': 'Wrong collection type',
          'itemIds': 'movie:tmdb:999',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-02T00:00:00.000Z',
        },
        {
          'id': 'list-2',
          'name': 'Wrong member type',
          'itemIds': [123],
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-02T00:00:00.000Z',
        },
        {
          'id': 'list-3',
          'name': 'Blank member',
          'itemIds': ['movie:tmdb:424783', '   '],
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-02T00:00:00.000Z',
        },
      ],
      'continueWatching': const <Object?>[],
      'completedWatching': const <Object?>[],
    });

    expect(merged.libraryLists, hasLength(1));
    expect(merged.libraryLists.single.name, 'Current list');
    expect(merged.libraryLists.single.itemKeys, ['movie:tmdb:424783']);
    expect(merged.likedKeys, {'movie:tmdb:424783'});
  });

  test('persisted malformed list membership is rejected', () {
    final state = TvLibraryState.fromJson({
      'version': 1,
      'likedKeys': const <String>[],
      'libraryLists': [
        {
          'id': 'list-1',
          'name': 'Malformed persisted list',
          'itemKeys': ['movie:tmdb:424783', '   '],
          'createdAtMillis': 1000,
          'updatedAtMillis': 2000,
        },
      ],
      'completedKeys': const <String>[],
      'recentItems': const <Object?>[],
      'progress': const <Object?>[],
    });

    expect(state.libraryLists, isEmpty);
  });
}
