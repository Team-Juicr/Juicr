import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/mobile_playback_episode_selection.dart';
import 'package:juicr/src/native_player_page.dart';

void main() {
  const episodes = <MobilePlaybackEpisodeSlot>[
    MobilePlaybackEpisodeSlot(season: 2, episode: 2),
    MobilePlaybackEpisodeSlot(season: 1, episode: 3),
    MobilePlaybackEpisodeSlot(season: 2, episode: 1),
    MobilePlaybackEpisodeSlot(season: 1, episode: 1),
    MobilePlaybackEpisodeSlot(season: 1, episode: 1),
  ];

  test('seasons are unique and ordered', () {
    expect(mobilePlaybackSeasons(episodes), <int>[1, 2]);
  });

  test('episodes are unique and ordered inside the selected season', () {
    expect(
      mobilePlaybackEpisodesForSeason(episodes, 1),
      const <MobilePlaybackEpisodeSlot>[
        MobilePlaybackEpisodeSlot(season: 1, episode: 1),
        MobilePlaybackEpisodeSlot(season: 1, episode: 3),
      ],
    );
  });

  test('child Back returns to season selection', () {
    expect(
      mobileEpisodePickerStageAfterChildResult(hasSelection: false),
      MobileEpisodePickerStage.seasons,
    );
    expect(
      mobileEpisodePickerStageAfterChildResult(hasSelection: true),
      MobileEpisodePickerStage.done,
    );
  });

  testWidgets('real player route owns fresh work after original route expiry',
      (tester) async {
    final harness = NativePlayerPageLifecycleHarness(
      skipInitialOpen: true,
      skipPlaybackInterstitials: true,
    );
    var resolverCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: NativePlayerPage(
          title: 'Current episode',
          sources: const <NativePlaybackRequest>[],
          resolveProvider: (_, __) async => const [],
          startupStartedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          lifecycleHarness: harness,
          onNextEpisode: (_) async {
            resolverCalls += 1;
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    expect(harness.openNextEpisode, isNotNull);
    await harness.openNextEpisode!.call();
    await tester.pump();

    expect(resolverCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(harness.openNextEpisode, isNull);
  });
}
