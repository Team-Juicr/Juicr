import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/main.dart';
import 'package:juicr_tv/tv_playback_candidate_order.dart';

void main() {
  test('Back during replacement snapshots the retained absolute timeline', () {
    const retained = TvPlaybackTimelineOwnership(
      continuousTsActive: true,
      timelineOffset: Duration(seconds: 996),
      displayOffset: Duration.zero,
    );
    const staged = TvPlaybackTimelineOwnership(
      continuousTsActive: false,
      timelineOffset: Duration.zero,
      displayOffset: Duration(seconds: 4),
    );

    expect(
      tvPlaybackTimelineForClose(
        retainedDuringReplacement: retained,
        current: staged,
      ),
      retained,
    );
    expect(
      tvPlaybackTimelineForClose(
        retainedDuringReplacement: null,
        current: staged,
      ),
      staged,
    );
  });

  test('replacement timeline transaction owns close, rollback, and promotion',
      () {
    const retained = TvPlaybackTimelineOwnership(
      continuousTsActive: true,
      timelineOffset: Duration(seconds: 996),
      displayOffset: Duration.zero,
    );
    const staged = TvPlaybackTimelineOwnership(
      continuousTsActive: false,
      timelineOffset: Duration.zero,
      displayOffset: Duration(seconds: 4),
    );
    final transaction = TvPlaybackTimelineTransaction();
    final events = <String>[];

    transaction.begin(retained);
    final closeResult = transaction.snapshotForClose<String>(
      current: staged,
      apply: (ownership) => events.add('apply:${ownership.timelineOffset.inSeconds}'),
      snapshot: () {
        events.add('snapshot');
        return 'closed';
      },
    );
    expect(closeResult, 'closed');
    expect(events, <String>['apply:996', 'snapshot']);
    expect(transaction.active, isFalse);

    transaction.begin(retained);
    expect(transaction.settle(current: staged, promoted: false), retained);
    expect(transaction.active, isFalse);

    transaction.begin(retained);
    expect(transaction.settle(current: staged, promoted: true), staged);
    expect(transaction.active, isFalse);
  });

  test('failed replacement restores retained continuous-TS timeline ownership',
      () {
    const retained = TvPlaybackTimelineOwnership(
      continuousTsActive: true,
      timelineOffset: Duration(seconds: 996),
      displayOffset: Duration.zero,
    );
    const staged = TvPlaybackTimelineOwnership(
      continuousTsActive: false,
      timelineOffset: Duration.zero,
      displayOffset: Duration(seconds: 4),
    );

    expect(
      tvPlaybackTimelineAfterReplacement(
        retained: retained,
        staged: staged,
        promoted: false,
      ),
      retained,
    );
    expect(
      tvPlaybackTimelineAfterReplacement(
        retained: retained,
        staged: staged,
        promoted: true,
      ),
      staged,
    );
  });

  test('next episode promotes only its exact owned staged controller', () {
    Object? active = Object();
    final staged = Object();
    Object? stagedSlot = staged;

    expect(
      tvPromotePreparedPlaybackController<Object>(
        mounted: true,
        capturedGeneration: 4,
        currentGeneration: 4,
        capturedAttempt: 9,
        currentAttempt: 9,
        preparedController: staged,
        currentController: active,
        stagedController: stagedSlot,
        replaceCurrent: (controller) => active = controller,
        replaceStaged: (controller) => stagedSlot = controller,
      ),
      isTrue,
    );
    expect(active, same(staged));
    expect(stagedSlot, isNull);

    final stale = Object();
    stagedSlot = stale;
    expect(
      tvPromotePreparedPlaybackController<Object>(
        mounted: true,
        capturedGeneration: 4,
        currentGeneration: 4,
        capturedAttempt: 8,
        currentAttempt: 9,
        preparedController: stale,
        currentController: active,
        stagedController: stagedSlot,
        replaceCurrent: (controller) => active = controller,
        replaceStaged: (controller) => stagedSlot = controller,
      ),
      isFalse,
    );
    expect(active, same(staged));
    expect(stagedSlot, same(stale));
  });

  test('stale failed attempt cannot restore retained timeline ownership', () {
    expect(
      tvFailedStartupCanRestoreTimeline(
        attemptIsCurrent: true,
        controllerIsStaged: true,
      ),
      isTrue,
    );
    expect(
      tvFailedStartupCanRestoreTimeline(
        attemptIsCurrent: false,
        controllerIsStaged: true,
      ),
      isFalse,
    );
    expect(
      tvFailedStartupCanRestoreTimeline(
        attemptIsCurrent: true,
        controllerIsStaged: false,
      ),
      isFalse,
    );
  });

  test('source replacement has one bounded terminal budget', () {
    expect(tvPlaybackReplacementOpenBudget, const Duration(seconds: 45));
    expect(tvPlaybackReplacementCandidateLimit, 1);
  });

  test('source replacement retains the active controller until target proof', () {
    expect(
      tvPlaybackReplacementRequiresPreRelease(
        retainedEngine: 'libvlc',
        replacementEngine: 'libvlc',
        hasRetainedController: true,
      ),
      isFalse,
    );
    expect(
      tvPlaybackReplacementRequiresPreRelease(
        retainedEngine: 'media3',
        replacementEngine: 'libvlc',
        hasRetainedController: true,
      ),
      isFalse,
    );
    expect(
      tvPlaybackReplacementRequiresPreRelease(
        retainedEngine: 'libvlc',
        replacementEngine: 'libvlc',
        hasRetainedController: false,
      ),
      isFalse,
    );
    expect(
      tvPlaybackReplacementRequiresPreRelease(
        retainedEngine: 'libvlc',
        replacementEngine: 'media3',
        hasRetainedController: true,
      ),
      isFalse,
    );
  });

  test('failed replacement reuses a healthy retained controller in place', () {
    expect(
      tvFailedReplacementRequiresSessionReopen(
        engine: 'media3',
        retainedInitialized: true,
        errorDescription: '',
        retainedMounted: true,
      ),
      isFalse,
    );
    expect(
      tvFailedReplacementRequiresSessionReopen(
        engine: 'libvlc',
        retainedInitialized: true,
        errorDescription: '',
        retainedMounted: true,
      ),
      isFalse,
    );
    expect(
      tvFailedReplacementRequiresSessionReopen(
        engine: 'libvlc',
        retainedInitialized: false,
        errorDescription: '',
        retainedMounted: true,
      ),
      isTrue,
    );
    expect(
      tvFailedReplacementRequiresSessionReopen(
        engine: 'media3',
        retainedInitialized: true,
        errorDescription: '',
        retainedMounted: false,
      ),
      isTrue,
    );
  });

  test(
      'failed replacement resumes the retained controller only when it was playing',
      () async {
    var resumeCount = 0;

    expect(
      await tvRestorePlaybackAfterFailedReplacement(
        wasPlaying: true,
        resume: () async => resumeCount += 1,
      ),
      isTrue,
    );
    expect(
      await tvRestorePlaybackAfterFailedReplacement(
        wasPlaying: false,
        resume: () async => resumeCount += 1,
      ),
      isFalse,
    );

    expect(resumeCount, 1);
  });

  test('failed replacement resume failure settles without escaping', () async {
    final restored = await tvRestorePlaybackAfterFailedReplacement(
      wasPlaying: true,
      resume: () async => throw StateError('resume failed'),
    );

    expect(restored, isFalse);
  });

  test('post-promotion cleanup drains every resource without rollback', () async {
    final events = <String>[];

    final failureCount = await tvDisposePlaybackResources(
      <Future<void> Function()>[
        () async {
          events.add('video');
          throw StateError('video cleanup failed');
        },
        () async => events.add('media3'),
        () async => events.add('libvlc'),
        () async => events.add('relay'),
      ],
    );

    expect(failureCount, 1);
    expect(events, <String>['video', 'media3', 'libvlc', 'relay']);
  });

  test('viable retained-controller rollback rebases its merged inventory index',
      () {
    final rebasedIndex = tvPlaybackCandidateIndexForIdentity(
      identities: const ['fresh-a', 'fresh-b', 'retained-source'],
      identity: 'retained-source',
    );

    expect(rebasedIndex, 2);
  });

  testWidgets('staging a source preserves the mounted active surface',
      (tester) async {
    final activeKey = GlobalKey();

    Widget build({required bool staged}) => Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 1280,
            height: 720,
            child: TvPlaybackSurfaceSlots(
              activeSurface: SizedBox(key: activeKey),
              stagedSurface: staged ? const ColoredBox(color: Colors.black) : null,
            ),
          ),
        );

    await tester.pumpWidget(build(staged: false));
    final activeContext = activeKey.currentContext;
    expect(activeContext, isNotNull);

    await tester.pumpWidget(build(staged: true));

    expect(activeKey.currentContext, same(activeContext));
    expect(find.byKey(tvActivePlaybackSurfaceKey), findsOneWidget);
    expect(find.byKey(tvStagedPlaybackSurfaceKey), findsOneWidget);
  });

  testWidgets('promoting a staged source preserves its mounted surface state',
      (tester) async {
    final targetIdentity = GlobalKey();

    Widget targetSurface() => tvPlaybackSurfaceWithIdentity(
          identity: targetIdentity,
          child: const SizedBox(),
        );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TvPlaybackSurfaceSlots(
          activeSurface: const SizedBox(),
          stagedSurface: targetSurface(),
        ),
      ),
    );
    final stagedContext = targetIdentity.currentContext;
    expect(stagedContext, isNotNull);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TvPlaybackSurfaceSlots(activeSurface: targetSurface()),
      ),
    );

    expect(targetIdentity.currentContext, same(stagedContext));
    expect(find.byKey(tvStagedPlaybackSurfaceKey), findsNothing);
    expect(find.byKey(tvActivePlaybackSurfaceKey), findsOneWidget);
  });
}
