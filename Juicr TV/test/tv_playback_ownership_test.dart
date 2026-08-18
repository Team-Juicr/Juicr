import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:juicr_tv/main.dart';

void main() {
  test('libVLC direct MP4 disables hardware direct rendering', () {
    expect(
      tvLibVlcHardwareAcceleration(
        sourceType: 'mp4',
        mediaUrl: 'https://first-party.invalid/media/file.mp4',
      ),
      HwAcc.decoding,
    );
    expect(
      tvLibVlcHardwareAcceleration(
        sourceType: 'hls',
        mediaUrl: 'https://first-party.invalid/media/master.m3u8',
      ),
      HwAcc.auto,
    );
  });

  test('transport diagnostics expose only fixed playback state buckets', () {
    expect(
      tvPlaybackTransportOutcomeLine(
        action: TvPlaybackTransportAction.pause,
        engine: 'media3',
        beforePosition: const Duration(seconds: 42),
        afterPosition: const Duration(seconds: 42),
        beforePlaying: true,
        afterPlaying: false,
      ),
      'Juicr TV playback transport outcome action=pause engine=media3 '
      'before=42s after=42s beforePlaying=true afterPlaying=false',
    );
    expect(
      tvPlaybackTransportOutcomeLine(
        action: TvPlaybackTransportAction.seekBack,
        engine: 'libvlc',
        beforePosition: const Duration(seconds: 42),
        afterPosition: const Duration(seconds: 27),
        beforePlaying: true,
        afterPlaying: true,
      ),
      'Juicr TV playback transport outcome action=seek_back engine=libvlc '
      'before=42s after=27s beforePlaying=true afterPlaying=true',
    );
  });

  test('transport diagnostics wait for the controller state to settle',
      () async {
    var reads = 0;
    final settled = await tvSettlePlaybackTransportState<int>(
      read: () => ++reads,
      isSettled: (value) => value >= 3,
      timeout: const Duration(milliseconds: 50),
      interval: Duration.zero,
    );

    expect(settled, 3);
    expect(reads, 3);
  });

  test('Media3 resume settlement allows bounded post-seek rebuffering', () {
    expect(
      tvPlaybackTransportSettleTimeout(
        action: TvPlaybackTransportAction.resume,
        engine: 'media3',
      ),
      const Duration(seconds: 10),
    );
    expect(
      tvPlaybackTransportSettleTimeout(
        action: TvPlaybackTransportAction.pause,
        engine: 'media3',
      ),
      const Duration(seconds: 3),
    );
    expect(
      tvPlaybackTransportSettleTimeout(
        action: TvPlaybackTransportAction.seekForward,
        engine: 'libvlc',
      ),
      const Duration(seconds: 20),
    );
    expect(
      tvPlaybackTransportSettleTimeout(
        action: TvPlaybackTransportAction.seekBack,
        engine: 'media3',
      ),
      const Duration(seconds: 3),
    );
  });

  test('playback open diagnostics expose only fixed reason buckets', () {
    expect(tvPlaybackOpenReasonBucket('Ready'), 'initial');
    expect(tvPlaybackOpenReasonBucket('Seeking'), 'seek');
    expect(tvPlaybackOpenReasonBucket('Recovered'), 'recovery');
    expect(tvPlaybackOpenReasonBucket('Source 2'), 'source');
    expect(tvPlaybackOpenReasonBucket('Previous source'), 'rollback');
    expect(tvPlaybackOpenReasonBucket('Refreshed'), 'refresh');
    expect(tvPlaybackOpenReasonBucket('private value'), 'other');
  });

  test('manual source replacement retains the active engine', () {
    expect(
      tvPlaybackReplacementEngineName(
        feedbackLabel: 'Source 2',
        retainedEngine: 'libvlc',
      ),
      'libvlc',
    );
    expect(
      tvPlaybackReplacementEngineName(
        feedbackLabel: 'Recovered',
        retainedEngine: 'libvlc',
      ),
      isNull,
    );
    expect(
      tvPlaybackReplacementEngineName(
        feedbackLabel: 'Source 2',
        retainedEngine: null,
      ),
      isNull,
    );
  });

  test('async playback continuation requires current generation and identity',
      () {
    expect(
      tvPlaybackAsyncResultIsCurrent(
        mounted: true,
        capturedGeneration: 4,
        currentGeneration: 4,
        capturedSeason: 2,
        currentSeason: 2,
        capturedEpisode: 9,
        currentEpisode: 9,
      ),
      isTrue,
    );
    expect(
      tvPlaybackAsyncResultIsCurrent(
        mounted: true,
        capturedGeneration: 4,
        currentGeneration: 5,
      ),
      isFalse,
    );
    expect(
      tvPlaybackAsyncResultIsCurrent(
        mounted: true,
        capturedGeneration: 4,
        currentGeneration: 4,
        capturedSeason: 2,
        currentSeason: 2,
        capturedEpisode: 9,
        currentEpisode: 10,
      ),
      isFalse,
    );
    expect(
      tvPlaybackAsyncResultIsCurrent(
        mounted: false,
        capturedGeneration: 4,
        currentGeneration: 4,
      ),
      isFalse,
    );
  });

  test('prepared playback publication requires exact attempt and owned controller',
      () {
    expect(
      tvPreparedPlaybackCanPublish(
        mounted: true,
        capturedGeneration: 8,
        currentGeneration: 8,
        capturedAttempt: 13,
        currentAttempt: 13,
        controllerIsOwned: true,
      ),
      isTrue,
    );
    expect(
      tvPreparedPlaybackCanPublish(
        mounted: true,
        capturedGeneration: 8,
        currentGeneration: 8,
        capturedAttempt: 12,
        currentAttempt: 13,
        controllerIsOwned: true,
      ),
      isFalse,
    );
    expect(
      tvPreparedPlaybackCanPublish(
        mounted: true,
        capturedGeneration: 8,
        currentGeneration: 8,
        capturedAttempt: 13,
        currentAttempt: 13,
        controllerIsOwned: false,
      ),
      isFalse,
    );
  });

  test('subtitle lookup survives same-identity playback startup only', () {
    expect(
      tvSubtitleLookupResultIsCurrent(
        mounted: true,
        capturedSeason: 2,
        currentSeason: 2,
        capturedEpisode: 9,
        currentEpisode: 9,
      ),
      isTrue,
    );
    expect(
      tvSubtitleLookupResultIsCurrent(
        mounted: true,
        capturedSeason: 2,
        currentSeason: 2,
        capturedEpisode: 9,
        currentEpisode: 10,
      ),
      isFalse,
    );
    expect(
      tvSubtitleLookupResultIsCurrent(
        mounted: false,
        capturedSeason: 2,
        currentSeason: 2,
        capturedEpisode: 9,
        currentEpisode: 9,
      ),
      isFalse,
    );
  });

  test('Media3 startup proof rejects metadata-only black MP4 state', () {
    expect(
      tvMedia3HasStartupProof(
        initialized: true,
        playing: true,
        firstFrameRendered: false,
        position: Duration.zero,
        duration: const Duration(minutes: 90),
        size: const Size(1920, 1080),
      ),
      isFalse,
    );
    expect(
      tvMedia3HasStartupProof(
        initialized: true,
        playing: true,
        firstFrameRendered: true,
        position: Duration.zero,
        duration: const Duration(minutes: 90),
        size: const Size(1920, 1080),
      ),
      isTrue,
    );
    expect(
      tvMedia3HasStartupProof(
        initialized: true,
        playing: true,
        firstFrameRendered: false,
        position: const Duration(milliseconds: 500),
        duration: const Duration(minutes: 90),
        size: Size.zero,
      ),
      isTrue,
    );
  });

  test('native startup proof keeps engine-specific bounded attach windows', () {
    expect(
      tvPlaybackStartupProofTimeout(libVlc: true, livePlayback: false),
      const Duration(seconds: 24),
    );
    expect(
      tvPlaybackStartupProofTimeout(libVlc: false, livePlayback: false),
      const Duration(seconds: 10),
    );
  });

  test('libVLC relay accepts bounded small segments only after advancement',
      () {
    expect(
      tvLibVlcRelayHasStartupProof(
        initialized: true,
        playing: true,
        position: const Duration(seconds: 1),
        streamedSegments: 1,
        streamedBytes: 64 * 1024,
      ),
      isTrue,
    );
    expect(
      tvLibVlcRelayHasStartupProof(
        initialized: true,
        playing: true,
        position: Duration.zero,
        streamedSegments: 1,
        streamedBytes: 64 * 1024,
      ),
      isFalse,
    );
    expect(
      tvLibVlcRelayHasStartupProof(
        initialized: true,
        playing: true,
        position: const Duration(seconds: 1),
        streamedSegments: 1,
        streamedBytes: 63 * 1024,
      ),
      isFalse,
    );
  });

  test('Media3 state poll gate allows only one request and rejects late state',
      () {
    final gate = TvMedia3StatePollGate();
    final first = gate.begin();

    expect(first, isNotNull);
    expect(gate.begin(), isNull);
    expect(gate.accept(first!), isTrue);

    final second = gate.begin();
    expect(second, isNotNull);
    gate.dispose();
    expect(gate.accept(second!), isFalse);
    expect(gate.begin(), isNull);
  });

  test('playback audio proof accepts only a selected audio track', () {
    expect(
      tvMedia3HasSelectedAudioTrack(
        'available:1,selected:1,unsupported:0,codec:aac',
      ),
      isTrue,
    );
    expect(
      tvMedia3HasSelectedAudioTrack('available:1,selected:none'),
      isFalse,
    );
    expect(tvMedia3HasSelectedAudioTrack('unknown'), isFalse);
    expect(tvLibVlcHasSelectedAudioTrack(trackCount: 2, trackId: 1), isTrue);
    expect(tvLibVlcHasSelectedAudioTrack(trackCount: 2, trackId: -1), isFalse);
    expect(tvLibVlcHasSelectedAudioTrack(trackCount: 0, trackId: 1), isFalse);
    expect(
      tvLibVlcHasSelectedAudioProof(
        trackCount: 0,
        trackId: -1,
        confirmedTrackId: 2,
      ),
      isTrue,
    );
    expect(
      tvLibVlcHasSelectedAudioProof(
        trackCount: 2,
        trackId: -1,
        confirmedTrackId: null,
      ),
      isFalse,
    );
  });

  test('replacement promotion requires advancing nonblank playback with audio',
      () {
    expect(
      tvPlaybackReplacementHasPromotionProof(
        initialized: true,
        playing: true,
        buffering: false,
        hasSelectedAudioTrack: true,
        size: const Size(1280, 720),
        startPosition: const Duration(seconds: 12),
        currentPosition: const Duration(seconds: 13),
      ),
      isTrue,
    );
    expect(
      tvPlaybackReplacementHasPromotionProof(
        initialized: true,
        playing: true,
        buffering: false,
        hasSelectedAudioTrack: false,
        size: const Size(1280, 720),
        startPosition: const Duration(seconds: 12),
        currentPosition: const Duration(seconds: 13),
      ),
      isFalse,
    );
    expect(
      tvPlaybackReplacementHasPromotionProof(
        initialized: true,
        playing: true,
        buffering: false,
        hasSelectedAudioTrack: true,
        size: Size.zero,
        startPosition: const Duration(seconds: 12),
        currentPosition: const Duration(seconds: 13),
      ),
      isFalse,
    );
    expect(
      tvPlaybackReplacementHasPromotionProof(
        initialized: true,
        playing: true,
        buffering: false,
        hasSelectedAudioTrack: true,
        size: const Size(1280, 720),
        startPosition: const Duration(seconds: 12),
        currentPosition: const Duration(milliseconds: 12499),
      ),
      isFalse,
    );
    expect(
      tvPlaybackReplacementHasPromotionProof(
        initialized: true,
        playing: true,
        buffering: true,
        hasSelectedAudioTrack: true,
        size: const Size(1280, 720),
        startPosition: const Duration(seconds: 12),
        currentPosition: const Duration(seconds: 13),
      ),
      isFalse,
    );
  });

  test(
      'libVLC startup selects the first playable audio track when none is active',
      () {
    expect(
      tvPreferredLibVlcAudioTrack(
        tracks: const <int, String>{-1: 'Disable', 2: 'English', 5: 'Spanish'},
        activeTrack: -1,
      ),
      2,
    );
    expect(
      tvPreferredLibVlcAudioTrack(
        tracks: const <int, String>{-1: 'Disable', 2: 'English'},
        activeTrack: 2,
      ),
      2,
    );
    expect(
      tvPreferredLibVlcAudioTrack(
        tracks: const <int, String>{-1: 'Disable'},
        activeTrack: -1,
      ),
      isNull,
    );
  });

  test('TV libVLC bridge decodes primitive Pigeon audio replies fail closed',
      () {
    expect(tvDecodeLibVlcPigeonIntReply(<Object?>[2]), 2);
    expect(
      tvDecodeLibVlcPigeonTracksReply(<Object?>[
        <Object?, Object?>{-1: 'Disable', 3: 'English'},
      ]),
      const <int, String>{-1: 'Disable', 3: 'English'},
    );
    expect(
      () => tvDecodeLibVlcPigeonIntReply(<Object?>['invalid']),
      throwsA(isA<StateError>()),
    );
    expect(
      () => tvDecodeLibVlcPigeonTracksReply(<Object?>[3]),
      throwsA(isA<StateError>()),
    );
  });

  test('cadence evidence is rate limited to advancing five-second buckets', () {
    expect(
      tvPlaybackCadenceShouldReport(lastReportedSecond: -1, positionSecond: 2),
      isTrue,
    );
    expect(
      tvPlaybackCadenceShouldReport(lastReportedSecond: 2, positionSecond: 6),
      isFalse,
    );
    expect(
      tvPlaybackCadenceShouldReport(lastReportedSecond: 2, positionSecond: 7),
      isTrue,
    );
    expect(
      tvPlaybackCadenceShouldReport(lastReportedSecond: 7, positionSecond: 7),
      isFalse,
    );
  });

  test('uncommitted source replacement cannot publish progress', () {
    expect(
      tvPlaybackProgressCanPublish(
        controllerIsCurrent: true,
        switchingSource: false,
      ),
      isTrue,
    );
    expect(
      tvPlaybackProgressCanPublish(
        controllerIsCurrent: true,
        switchingSource: true,
      ),
      isFalse,
    );
    expect(
      tvPlaybackProgressCanPublish(
        controllerIsCurrent: false,
        switchingSource: false,
      ),
      isFalse,
    );
  });

  test('playback authority changes invalidate verified source cache', () {
    final original = tvPlaybackAuthorityFingerprint(
      builtInPlayback: true,
      enabledAddOns: const <String>['addon-b', 'addon-a'],
    );
    final reordered = tvPlaybackAuthorityFingerprint(
      builtInPlayback: true,
      enabledAddOns: const <String>['addon-a', 'addon-b'],
    );
    final disabled = tvPlaybackAuthorityFingerprint(
      builtInPlayback: true,
      enabledAddOns: const <String>['addon-a'],
    );

    expect(original, reordered);
    expect(tvPlaybackAuthorityChanged(original, reordered), isFalse);
    expect(tvPlaybackAuthorityChanged(original, disabled), isTrue);
    expect(
      tvPlaybackAuthorityChanged(
        original,
        tvPlaybackAuthorityFingerprint(
          builtInPlayback: false,
          enabledAddOns: const <String>['addon-a', 'addon-b'],
        ),
      ),
      isTrue,
    );
  });

  test('TV skip buttons use the advertised fifteen-second interval', () {
    expect(tvPlaybackSkipInterval, const Duration(seconds: 15));
  });

  test('resume prompt is published only after initialized playback is paused',
      () {
    expect(
      tvPlaybackCanPublishResumePrompt(initialized: true, playing: false),
      isTrue,
    );
    expect(
      tvPlaybackCanPublishResumePrompt(initialized: true, playing: true),
      isFalse,
    );
    expect(
      tvPlaybackCanPublishResumePrompt(initialized: false, playing: false),
      isFalse,
    );
  });

  test('resume pause settlement retries stay bounded while playback is active',
      () {
    expect(
      tvPlaybackResumePauseShouldRetry(
        initialized: true,
        playing: true,
        attempt: 1,
      ),
      isTrue,
    );
    expect(
      tvPlaybackResumePauseShouldRetry(
        initialized: true,
        playing: true,
        attempt: 5,
      ),
      isFalse,
    );
    expect(
      tvPlaybackResumePauseShouldRetry(
        initialized: true,
        playing: false,
        attempt: 1,
      ),
      isFalse,
    );
  });

  test(
      'resume pause settlement bounds a platform pause call that never returns',
      () async {
    var calls = 0;
    final result = await tvSettleControllerPauseForResume(
      pause: () {
        calls++;
        return Completer<void>().future;
      },
      isCurrent: () => true,
      isInitialized: () => true,
      isPlaying: () => true,
      maxAttempts: 2,
      attemptTimeout: const Duration(milliseconds: 10),
      pollInterval: const Duration(milliseconds: 1),
    ).timeout(const Duration(milliseconds: 200));

    expect(result, isFalse);
    expect(calls, 2);
  });

  test('user resume retries the current initialized controller until it plays',
      () async {
    var calls = 0;
    var playing = false;

    final result = await tvSettleControllerPlay(
      play: () async {
        calls++;
        if (calls == 2) playing = true;
      },
      isCurrent: () => true,
      isInitialized: () => true,
      isPlaying: () => playing,
      maxAttempts: 3,
      attemptTimeout: const Duration(milliseconds: 10),
      pollInterval: const Duration(milliseconds: 1),
    );

    expect(result, isTrue);
    expect(calls, 2);
  });

  test('VOD playback identity converges built-in and add-on TMDB items', () {
    expect(
      tvCanonicalPlaybackItemKey(
        type: 'movie',
        id: 'tmdb:424783',
        tmdbId: 424783,
      ),
      tvCanonicalPlaybackItemKey(
        type: 'movie',
        id: 'addon-item-opaque',
        tmdbId: 424783,
      ),
    );
    expect(
      tvCanonicalPlaybackItemKey(
        type: 'live',
        id: 'channel-a',
        tmdbId: null,
      ),
      isNot(
        tvCanonicalPlaybackItemKey(
          type: 'live',
          id: 'channel-b',
          tmdbId: null,
        ),
      ),
    );
  });

  test(
      'failed startup detaches only its exact published controller after timeout',
      () {
    final failedController = Object();
    Object? publishedController = failedController;
    expect(
      tvDetachFailedStartupController(
        currentController: () => publishedController,
        failedController: failedController,
        detach: () => publishedController = null,
      ),
      isTrue,
    );
    expect(publishedController, isNull);

    final replacementController = Object();
    publishedController = replacementController;
    expect(
      tvDetachFailedStartupController(
        currentController: () => publishedController,
        failedController: failedController,
        detach: () => publishedController = null,
      ),
      isFalse,
    );
    expect(publishedController, same(replacementController));
  });

  test('cancelled prepared P2P startup rolls back its owned generation',
      () async {
    var rollbacks = 0;
    await tvRollbackPreparedP2pOnCanceledStartup(
      p2pPrepared: true,
      rollback: () async => rollbacks += 1,
    );
    expect(rollbacks, 1);
  });

  test('P2P ownership generation is unique per startup attempt', () {
    expect(tvP2pOwnershipGenerationForStartupAttempt(40), 40);
    expect(tvP2pOwnershipGenerationForStartupAttempt(41), 41);
    expect(
      tvP2pOwnershipGenerationForStartupAttempt(40),
      isNot(tvP2pOwnershipGenerationForStartupAttempt(41)),
    );
  });

  test('P2P playback suspends only when the app leaves the foreground', () {
    expect(
      tvP2pPlaybackShouldSuspendForLifecycle(AppLifecycleState.resumed),
      isFalse,
    );
    expect(
      tvP2pPlaybackShouldSuspendForLifecycle(AppLifecycleState.inactive),
      isFalse,
    );
    expect(
      tvP2pPlaybackShouldSuspendForLifecycle(AppLifecycleState.hidden),
      isTrue,
    );
    expect(
      tvP2pPlaybackShouldSuspendForLifecycle(AppLifecycleState.paused),
      isTrue,
    );
    expect(
      tvP2pPlaybackShouldSuspendForLifecycle(AppLifecycleState.detached),
      isTrue,
    );
  });

  test('fresh fallback retries the prepended fresh sessions, not cached tails',
      () {
    expect(
      tvFreshFallbackCandidateIndexes(
        mergedKeys: const <String>[
          'fresh-a',
          'fresh-b',
          'cached-a',
          'cached-b',
        ],
        freshKeys: const <String>['fresh-a', 'fresh-b'],
      ),
      const <int>[0, 1],
    );
    expect(
      tvFreshFallbackCandidateIndexes(
        mergedKeys: const <String>['fresh-a', 'cached-a', 'cached-b'],
        freshKeys: const <String>['fresh-a', 'cached-a'],
        cachedKeys: const <String>['cached-a', 'cached-b'],
      ),
      const <int>[0],
    );
  });

  test('fresh fallback excludes route-rejected sessions before batch limiting',
      () {
    final sessions = <String>[
      'failed-a',
      'failed-b',
      'failed-c',
      'fresh-d',
      'fresh-e',
      'fresh-f',
    ];

    expect(
      tvExcludeRejectedPlaybackSessions<String>(
        sessions: sessions,
        rejectedKeys: const <String>{
          'failed-a',
          'failed-b',
          'failed-c',
        },
        keyOf: (session) => session,
      ).take(3),
      const <String>['fresh-d', 'fresh-e', 'fresh-f'],
    );
  });

  test('ownership finalization quarantines cancellation during its await',
      () async {
    final finalization = Completer<void>();
    var current = true;
    var disposals = 0;
    var rollbacks = 0;

    final result = tvFinalizePreparedPlaybackOwnership(
      finalizeOwnership: () => finalization.future,
      isCurrent: () => current,
      disposePreparedController: () async => disposals += 1,
      rollbackPreparedOwnership: () async => rollbacks += 1,
    );
    current = false;
    finalization.complete();

    expect(await result, isFalse);
    expect(disposals, 1);
    expect(rollbacks, 1);
  });
}
