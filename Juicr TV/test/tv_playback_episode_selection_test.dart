import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/main.dart';
import 'package:juicr_tv/tv_playback_episode_selection.dart';

void main() {
  const episodes = <TvPlaybackEpisodeSlot>[
    TvPlaybackEpisodeSlot(season: 2, episode: 2),
    TvPlaybackEpisodeSlot(season: 1, episode: 3),
    TvPlaybackEpisodeSlot(season: 2, episode: 1),
    TvPlaybackEpisodeSlot(season: 1, episode: 1),
    TvPlaybackEpisodeSlot(season: 1, episode: 1),
  ];

  test('season picker is unique and sorted', () {
    expect(tvPlaybackSeasons(episodes), const <int>[1, 2]);
  });

  test('season picker prefers the active season when available', () {
    expect(
      tvPlaybackInitialSeasonIndex(
        seasons: const <int>[1, 2, 3],
        activeSeason: 2,
      ),
      1,
    );
    expect(
      tvPlaybackInitialSeasonIndex(
        seasons: const <int>[1, 2, 3],
        activeSeason: 9,
      ),
      0,
    );
  });

  test('episode picker is sorted and deduplicated within one season', () {
    expect(
      tvPlaybackEpisodesForSeason(episodes, 1),
      const <TvPlaybackEpisodeSlot>[
        TvPlaybackEpisodeSlot(season: 1, episode: 1),
        TvPlaybackEpisodeSlot(season: 1, episode: 3),
      ],
    );
  });

  test('episode picker prefers the exact active episode', () {
    const seasonEpisodes = <TvPlaybackEpisodeSlot>[
      TvPlaybackEpisodeSlot(season: 2, episode: 1),
      TvPlaybackEpisodeSlot(season: 2, episode: 2),
    ];
    expect(
      tvPlaybackInitialEpisodeIndex(
        episodes: seasonEpisodes,
        activeSeason: 2,
        activeEpisode: 2,
      ),
      1,
    );
    expect(
      tvPlaybackInitialEpisodeIndex(
        episodes: seasonEpisodes,
        activeSeason: 1,
        activeEpisode: 2,
      ),
      0,
    );
  });

  test('dialog Back invalidates a pending episode attempt', () {
    final gate = TvPlaybackEpisodeAttemptGate();
    final attempt = gate.begin();

    expect(gate.owns(attempt), isTrue);

    gate.cancel(attempt);

    expect(gate.owns(attempt), isFalse);
    expect(gate.owns(gate.begin()), isTrue);
  });

  test('dialog Back rejects a late successful episode operation', () async {
    final gate = TvPlaybackEpisodeAttemptGate();
    final attempt = gate.begin();
    final target = Completer<bool>();
    final result = gate.runOwned<bool>(attempt, () => target.future);

    gate.cancel(attempt);
    target.complete(true);

    expect(await result, isNull);
  });

  testWidgets(
      'episode selection closes both dialogs before title-wheel preparation',
      (tester) async {
    final preparation = Completer<bool>();
    var preparationCalls = 0;
    final harness = TvPlaybackPageLifecycleHarness(
      skipInitialPlayback: true,
      prepareEpisode: (season, episode) {
        preparationCalls += 1;
        expect((season, episode), (1, 2));
        return preparation.future;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: buildTvPlaybackEpisodeTestPage(lifecycleHarness: harness),
      ),
    );
    await tester.pump();

    expect(harness.openEpisodesPanel, isNotNull);
    unawaited(harness.openEpisodesPanel!.call());
    await tester.pump();
    expect(find.text('Choose season'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Season 1 episodes'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(preparationCalls, 0);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);

    for (var attempt = 0; attempt < 12 && preparationCalls == 0; attempt++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(preparationCalls, 1);
    await tester.pump();
    expect(find.text('Season 1 episodes').hitTestable(), findsNothing);
    expect(find.text('Choose season').hitTestable(), findsNothing);
    expect(find.textContaining('Preparing episode 2'), findsOneWidget);

    expect(preparation.isCompleted, isFalse);
    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets(
      'focused episode detail scrolls horizontally and resets after blur',
      (tester) async {
    final harness = TvPlaybackPageLifecycleHarness(skipInitialPlayback: true);

    await tester.pumpWidget(
      MaterialApp(
        home: buildTvPlaybackEpisodeTestPage(lifecycleHarness: harness),
      ),
    );
    await tester.pump();

    final dialogResult = harness.openSeasonEpisodes!.call(1);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final marquee = find.byKey(
      const ValueKey<String>('tv-playback-choice-marquee-1:2'),
    );
    expect(marquee, findsOneWidget);
    final scrollable = tester.widget<SingleChildScrollView>(marquee);
    expect(scrollable.controller!.offset, 0);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(scrollable.controller!.offset, greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(scrollable.controller!.offset, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    expect(await dialogResult, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
