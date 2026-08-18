import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/main.dart';

void main() {
  test('ordinary engine progress cannot lower the active resume floor', () {
    expect(
      tvPlaybackProgressFloor(
        current: const Duration(seconds: 142),
        incoming: const Duration(seconds: 1),
      ),
      const Duration(seconds: 142),
    );
    expect(
      tvPlaybackProgressFloor(
        current: const Duration(seconds: 142),
        incoming: const Duration(seconds: 150),
      ),
      const Duration(seconds: 150),
    );
  });

  test('seek uses the advancing position when reported duration is stale', () {
    expect(
      tvPlaybackSeekTarget(
        before: const Duration(seconds: 6927),
        offset: const Duration(seconds: -15),
        duration: const Duration(seconds: 6833),
      ),
      const Duration(seconds: 6912),
    );
    expect(
      tvPlaybackSeekTarget(
        before: const Duration(seconds: 6821),
        offset: const Duration(seconds: 15),
        duration: const Duration(seconds: 6833),
      ),
      const Duration(seconds: 6833),
    );
  });

  test('known-duration Media3 seek does not reapply a startup display offset', () {
    expect(
      tvPlaybackPositionWithDisplayOffset(
        rawPosition: const Duration(seconds: 182),
        reportedDuration: const Duration(seconds: 6833),
        displayTimelineOffset: const Duration(seconds: 208),
      ),
      const Duration(seconds: 182),
    );
    expect(
      tvPlaybackPositionWithDisplayOffset(
        rawPosition: const Duration(seconds: 4),
        reportedDuration: Duration.zero,
        displayTimelineOffset: const Duration(seconds: 208),
      ),
      const Duration(seconds: 212),
    );
  });

  test('libVLC continuous-TS always owns an absolute relay timeline', () {
    expect(
      tvPlaybackAbsolutePosition(
        rawPosition: const Duration(seconds: 4),
        reportedDuration: const Duration(seconds: 6833),
        libVlcContinuousTsActive: true,
        libVlcTimelineOffset: const Duration(seconds: 170),
        displayTimelineOffset: const Duration(seconds: 170),
      ),
      const Duration(seconds: 174),
    );
    expect(
      tvPlaybackAbsolutePosition(
        rawPosition: const Duration(seconds: 4),
        reportedDuration: const Duration(seconds: 6833),
        libVlcContinuousTsActive: false,
        libVlcTimelineOffset: Duration.zero,
        displayTimelineOffset: const Duration(seconds: 170),
      ),
      const Duration(seconds: 4),
    );
  });

  test('startup reapplies an ignored resume seek only after playback proof', () {
    expect(
      tvPlaybackStartupNeedsPostProofResume(
        target: const Duration(seconds: 132),
        current: Duration.zero,
        relayAlreadyAtResume: false,
      ),
      isTrue,
    );
    expect(
      tvPlaybackStartupNeedsPostProofResume(
        target: const Duration(seconds: 132),
        current: const Duration(seconds: 130),
        relayAlreadyAtResume: false,
      ),
      isFalse,
    );
    expect(
      tvPlaybackStartupNeedsPostProofResume(
        target: const Duration(seconds: 132),
        current: Duration.zero,
        relayAlreadyAtResume: true,
      ),
      isFalse,
    );
  });

  test('completed progress restarts explicitly while unfinished progress resumes', () async {
    const completedPosition = Duration(seconds: 6833);
    const duration = Duration(seconds: 6833);
    const unfinishedPosition = Duration(seconds: 51);
    var clears = 0;

    expect(
      tvPlaybackProgressIsComplete(
        position: completedPosition,
        duration: duration,
      ),
      isTrue,
    );
    expect(
      tvPlaybackProgressCanResume(
        position: unfinishedPosition,
        duration: duration,
        enabled: true,
      ),
      isTrue,
    );
    expect(
      tvPlaybackProgressCanResume(
        position: completedPosition,
        duration: duration,
        enabled: true,
      ),
      isFalse,
    );
    expect(
      await tvResetCompletedProgressBeforeReplay(
        position: completedPosition,
        duration: duration,
        clear: () async => clears += 1,
      ),
      isTrue,
    );
    expect(clears, 1);
    expect(
      await tvResetCompletedProgressBeforeReplay(
        position: unfinishedPosition,
        duration: duration,
        clear: () async => clears += 1,
      ),
      isFalse,
    );
    expect(clears, 1);
  });

  test('explicit start over invokes the owned progress reset', () async {
    final resets = <String>[];

    await tvResetProgressForExplicitStartOver(
      season: 2,
      episode: 9,
      reset: (season, episode) async => resets.add('$season:$episode'),
    );

    expect(resets, <String>['2:9']);
  });

  test('initial libVLC continuous-TS resume reopens at the saved anchor', () {
    expect(
      tvLibVlcContinuousTsSeekRequiresReopen(
        continuousTsActive: true,
        timelineOffset: Duration.zero,
        target: const Duration(seconds: 93),
        reason: 'resume_prompt',
      ),
      isTrue,
    );
  });

  test('ordinary local continuous-TS seek keeps the active controller', () {
    expect(
      tvLibVlcContinuousTsSeekRequiresReopen(
        continuousTsActive: true,
        timelineOffset: Duration.zero,
        target: const Duration(seconds: 15),
        reason: 'remote_seek',
      ),
      isFalse,
    );
  });

  test('initial libVLC resume releases the obsolete controller before reopen',
      () async {
    final events = <String>[];

    final released = await tvReleaseControllerForLibVlcResumeReopen(
      shouldRelease: true,
      stop: () async => events.add('stop'),
      detach: () => events.add('detach'),
      settle: () async => events.add('settle'),
      dispose: () async => events.add('dispose'),
    );

    expect(released, isTrue);
    expect(events, <String>['stop', 'detach', 'settle', 'dispose']);
  });

  test('ordinary seek does not release the active controller', () async {
    final events = <String>[];

    final released = await tvReleaseControllerForLibVlcResumeReopen(
      shouldRelease: false,
      stop: () async => events.add('stop'),
      detach: () => events.add('detach'),
      settle: () async => events.add('settle'),
      dispose: () async => events.add('dispose'),
    );

    expect(released, isFalse);
    expect(events, isEmpty);
  });

  test('resume after seek plays the current replacement controller', () async {
    final played = <String>[];

    final resumed = await tvResumeCurrentControllerAfterSeek<String>(
      currentController: 'replacement',
      play: (controller) async => played.add(controller),
    );

    expect(resumed, isTrue);
    expect(played, <String>['replacement']);
  });

  test('resume after seek settles when replacement is unavailable', () async {
    final resumed = await tvResumeCurrentControllerAfterSeek<String>(
      currentController: null,
      play: (_) async => fail('must not play a missing controller'),
    );

    expect(resumed, isFalse);
  });

  test('paused seek reasserts pause on the current controller', () async {
    final paused = <String>[];

    final restored = await tvPauseCurrentControllerAfterSeek<String>(
      currentController: 'replacement',
      pause: (controller) async => paused.add(controller),
    );

    expect(restored, isTrue);
    expect(paused, <String>['replacement']);
  });

  test('paused seek settles when replacement is unavailable', () async {
    final restored = await tvPauseCurrentControllerAfterSeek<String>(
      currentController: null,
      pause: (_) async => fail('must not pause a missing controller'),
    );

    expect(restored, isFalse);
  });

  test('resume prompt reopen does not preserve the dialog-induced pause', () {
    expect(
      tvShouldPauseReplacementAfterLibVlcReopen(
        wasPlaying: false,
        reason: 'resume_prompt',
      ),
      isFalse,
    );
    expect(
      tvShouldPauseReplacementAfterLibVlcReopen(
        wasPlaying: false,
        reason: 'remote_seek',
      ),
      isTrue,
    );
    expect(
      tvShouldPauseReplacementAfterLibVlcReopen(
        wasPlaying: true,
        reason: 'remote_seek',
      ),
      isFalse,
    );
  });
}
