import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/app_state.dart';
import 'package:juicr/src/catalog_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy series duration sentinel is not exposed as ten hours', () {
    final entry = ContinueWatchingEntry.fromJson(<String, dynamic>{
      'key': 'tv:76479:1:1',
      'item': <String, dynamic>{
        'type': 'series',
        'id': 'tv:76479',
        'name': 'The Boys',
      },
      'title': 'The Boys S1 E1',
      'subtitle': 'S1 E1',
      'watchedSeconds': 8,
      'credibleWatchedSeconds': 0,
      'durationSeconds': 10 * 60 * 60,
      'progress': 0.02,
      'updatedAt': '2026-08-01T00:00:00.000Z',
    });

    expect(entry.durationSeconds, 45 * 60);
    expect(entry.remainingTimeLabel, isNot('10 hours'));
  });

  test('unknown series duration uses a bounded episode fallback', () {
    const item = CatalogItem(
      type: MediaType.series,
      id: 'tv:duration-fallback',
      name: 'Series control',
    );

    AppState.recordPlaybackProgress(
      item: item,
      playbackKey: 'tv:duration-fallback:1:1',
      title: 'Series control S1 E1',
      watchedSeconds: 8,
    );

    final entry = AppState.progressFor(
      item,
      playbackKey: 'tv:duration-fallback:1:1',
    );
    expect(entry, isNotNull);
    expect(entry!.durationSeconds, 45 * 60);
  });

  test('pre-playback preference save does not fabricate progress', () {
    const item = CatalogItem(
      type: MediaType.series,
      id: 'tv:preferences-only',
      name: 'Preferences control',
    );

    AppState.updateNativePlayerPreferences(
      item: item,
      playbackKey: 'tv:preferences-only:1:1',
      title: 'Preferences control S1 E1',
      nativePreferences: const NativePlayerPreferences(quality: '720P'),
    );

    expect(
      AppState.progressFor(
        item,
        playbackKey: 'tv:preferences-only:1:1',
      ),
      isNull,
    );
  });
}
