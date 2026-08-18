part of 'main.dart';

const MethodChannel _tvMedia3PlayerChannel = MethodChannel(
  'app.juicr.flutter/media3_player',
);
const String _tvLibVlcPigeonChannelPrefix =
    'dev.flutter.pigeon.flutter_vlc_player_platform_interface.VlcPlayerApi.';

const Duration tvPlaybackSkipInterval = tvRemotePlaybackSkipInterval;

class TvPlaybackTimelineOwnership {
  const TvPlaybackTimelineOwnership({
    required this.continuousTsActive,
    required this.timelineOffset,
    required this.displayOffset,
  });

  final bool continuousTsActive;
  final Duration timelineOffset;
  final Duration displayOffset;
}

TvPlaybackTimelineOwnership tvPlaybackTimelineAfterReplacement({
  required TvPlaybackTimelineOwnership retained,
  required TvPlaybackTimelineOwnership staged,
  required bool promoted,
}) {
  return promoted ? staged : retained;
}

TvPlaybackTimelineOwnership tvPlaybackTimelineForClose({
  required TvPlaybackTimelineOwnership? retainedDuringReplacement,
  required TvPlaybackTimelineOwnership current,
}) {
  return retainedDuringReplacement ?? current;
}

class TvPlaybackTimelineTransaction {
  TvPlaybackTimelineOwnership? _retained;

  bool get active => _retained != null;

  void begin(TvPlaybackTimelineOwnership retained) {
    _retained = retained;
  }

  TvPlaybackTimelineOwnership settle({
    required TvPlaybackTimelineOwnership current,
    required bool promoted,
  }) {
    final retained = _retained;
    _retained = null;
    if (retained == null) return current;
    return tvPlaybackTimelineAfterReplacement(
      retained: retained,
      staged: current,
      promoted: promoted,
    );
  }

  T snapshotForClose<T>({
    required TvPlaybackTimelineOwnership current,
    required void Function(TvPlaybackTimelineOwnership ownership) apply,
    required T Function() snapshot,
  }) {
    apply(settle(current: current, promoted: false));
    return snapshot();
  }
}
const Duration tvPlaybackReplacementOpenBudget = Duration(seconds: 45);
const int tvPlaybackReplacementCandidateLimit = 1;
const Key tvActivePlaybackSurfaceKey =
    ValueKey<String>('tv-active-playback-surface');
const Key tvStagedPlaybackSurfaceKey =
    ValueKey<String>('tv-staged-playback-surface');

Widget tvPlaybackSurfaceWithIdentity({
  required GlobalKey identity,
  required Widget child,
}) {
  return KeyedSubtree(key: identity, child: child);
}

class TvPlaybackSurfaceSlots extends StatelessWidget {
  const TvPlaybackSurfaceSlots({
    super.key,
    required this.activeSurface,
    this.stagedSurface,
  });

  final Widget activeSurface;
  final Widget? stagedSurface;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (stagedSurface != null)
          Positioned.fill(
            key: tvStagedPlaybackSurfaceKey,
            child: stagedSurface!,
          ),
        Positioned.fill(
          key: tvActivePlaybackSurfaceKey,
          child: activeSurface,
        ),
      ],
    );
  }
}

enum TvPlaybackTransportAction {
  pause('pause'),
  resume('resume'),
  seekBack('seek_back'),
  seekForward('seek_forward');

  const TvPlaybackTransportAction(this.bucket);

  final String bucket;
}

String tvPlaybackTransportOutcomeLine({
  required TvPlaybackTransportAction action,
  required String engine,
  required Duration beforePosition,
  required Duration afterPosition,
  required bool beforePlaying,
  required bool afterPlaying,
}) {
  return 'Juicr TV playback transport outcome '
      'action=${action.bucket} engine=$engine '
      'before=${beforePosition.inSeconds}s after=${afterPosition.inSeconds}s '
      'beforePlaying=$beforePlaying afterPlaying=$afterPlaying';
}

Future<T> tvSettlePlaybackTransportState<T>({
  required T Function() read,
  required bool Function(T value) isSettled,
  Duration timeout = const Duration(seconds: 3),
  Duration interval = const Duration(milliseconds: 80),
}) async {
  final deadline = DateTime.now().add(timeout);
  var current = read();
  while (!isSettled(current) && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(interval);
    current = read();
  }
  return current;
}

Duration tvPlaybackTransportSettleTimeout({
  required TvPlaybackTransportAction action,
  required String engine,
}) {
  if (engine == 'libvlc' &&
      (action == TvPlaybackTransportAction.seekBack ||
          action == TvPlaybackTransportAction.seekForward)) {
    return const Duration(seconds: 20);
  }
  if (action == TvPlaybackTransportAction.resume && engine == 'media3') {
    return const Duration(seconds: 10);
  }
  return const Duration(seconds: 3);
}

Duration tvPlaybackProgressFloor({
  required Duration current,
  required Duration incoming,
}) {
  return incoming > current ? incoming : current;
}

bool tvPlaybackProgressIsComplete({
  required Duration position,
  required Duration duration,
}) {
  if (duration <= Duration.zero) return false;
  final remaining = duration - position;
  return position >= const Duration(minutes: 3) &&
      (position.inMilliseconds / duration.inMilliseconds) >= 0.92 &&
      remaining <= const Duration(minutes: 5);
}

bool tvPlaybackProgressCanResume({
  required Duration position,
  required Duration duration,
  required bool enabled,
}) {
  if (!enabled || position <= Duration.zero) return false;
  if (tvPlaybackProgressIsComplete(position: position, duration: duration)) {
    return false;
  }
  if (duration <= Duration.zero) return true;
  return duration - position > const Duration(minutes: 2);
}

Future<bool> tvResetCompletedProgressBeforeReplay({
  required Duration? position,
  required Duration? duration,
  required Future<void> Function() clear,
}) async {
  if (position == null ||
      duration == null ||
      !tvPlaybackProgressIsComplete(position: position, duration: duration)) {
    return false;
  }
  await clear();
  return true;
}

bool tvPlaybackStartupNeedsPostProofResume({
  required Duration target,
  required Duration current,
  required bool relayAlreadyAtResume,
}) {
  if (relayAlreadyAtResume || target <= Duration.zero) return false;
  return (current - target).abs() > const Duration(seconds: 3);
}

Duration tvPlaybackSeekTarget({
  required Duration before,
  required Duration offset,
  required Duration duration,
}) {
  final target = before + offset;
  if (target < Duration.zero) return Duration.zero;
  if (duration <= Duration.zero || before > duration) return target;
  return target > duration ? duration : target;
}

Duration tvPlaybackPositionWithDisplayOffset({
  required Duration rawPosition,
  required Duration reportedDuration,
  required Duration displayTimelineOffset,
}) {
  if (displayTimelineOffset <= Duration.zero ||
      rawPosition <= Duration.zero ||
      reportedDuration > Duration.zero) {
    return rawPosition;
  }
  if (rawPosition >= displayTimelineOffset - const Duration(seconds: 2)) {
    return rawPosition;
  }
  return displayTimelineOffset + rawPosition;
}

Duration tvPlaybackAbsolutePosition({
  required Duration rawPosition,
  required Duration reportedDuration,
  required bool libVlcContinuousTsActive,
  required Duration libVlcTimelineOffset,
  required Duration displayTimelineOffset,
}) {
  if (libVlcContinuousTsActive && libVlcTimelineOffset > Duration.zero) {
    return libVlcTimelineOffset + rawPosition;
  }
  return tvPlaybackPositionWithDisplayOffset(
    rawPosition: rawPosition,
    reportedDuration: reportedDuration,
    displayTimelineOffset: displayTimelineOffset,
  );
}

Future<void> tvResetProgressForExplicitStartOver({
  required int season,
  required int episode,
  required Future<void> Function(int season, int episode) reset,
}) {
  return reset(season, episode);
}

String tvPlaybackOpenReasonBucket(String value) {
  if (value.startsWith('Source ')) return 'source';
  return switch (value) {
    'Ready' => 'initial',
    'Resume playback' => 'lifecycle_resume',
    'Recovered' => 'recovery',
    'Seeking' => 'seek',
    'Previous source' => 'rollback',
    'Refreshed' => 'refresh',
    _ => 'other',
  };
}

String? tvPlaybackReplacementEngineName({
  required String feedbackLabel,
  required String? retainedEngine,
}) {
  if (!feedbackLabel.startsWith('Source ')) return null;
  final normalized = retainedEngine?.trim().toLowerCase();
  if (normalized == 'media3' || normalized == 'libvlc') return normalized;
  return null;
}

bool tvP2pPlaybackShouldSuspendForLifecycle(AppLifecycleState state) {
  return state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;
}

bool tvFailedReplacementRequiresSessionReopen({
  required String engine,
  required bool retainedInitialized,
  required String errorDescription,
  required bool retainedMounted,
}) {
  if (retainedMounted && retainedInitialized && errorDescription.isEmpty) {
    return false;
  }
  return engine == 'media3' ||
      engine == 'libvlc' ||
      !retainedInitialized ||
      errorDescription.isNotEmpty;
}

bool tvPlaybackReplacementRequiresPreRelease({
  required String retainedEngine,
  required String replacementEngine,
  required bool hasRetainedController,
}) {
  return false;
}

bool tvLibVlcContinuousTsSeekRequiresReopen({
  required bool continuousTsActive,
  required Duration timelineOffset,
  required Duration target,
  required String reason,
}) {
  return continuousTsActive &&
      timelineOffset == Duration.zero &&
      target > Duration.zero &&
      reason == 'resume_prompt';
}

Future<bool> tvReleaseControllerForLibVlcResumeReopen({
  required bool shouldRelease,
  required Future<void> Function() stop,
  required void Function() detach,
  required Future<void> Function() settle,
  required Future<void> Function() dispose,
}) async {
  if (!shouldRelease) return false;
  await stop();
  detach();
  await settle();
  await dispose();
  return true;
}

Future<bool> tvResumeCurrentControllerAfterSeek<T>({
  required T? currentController,
  required Future<void> Function(T controller) play,
}) async {
  if (currentController == null) return false;
  await play(currentController);
  return true;
}

Future<bool> tvPauseCurrentControllerAfterSeek<T>({
  required T? currentController,
  required Future<void> Function(T controller) pause,
}) async {
  if (currentController == null) return false;
  await pause(currentController);
  return true;
}

bool tvShouldPauseReplacementAfterLibVlcReopen({
  required bool wasPlaying,
  required String reason,
}) {
  return !wasPlaying && reason != 'resume_prompt';
}

Future<bool> tvRestorePlaybackAfterFailedReplacement({
  required bool wasPlaying,
  required Future<void> Function() resume,
}) async {
  if (!wasPlaying) return false;
  try {
    await resume();
    return true;
  } catch (_) {
    return false;
  }
}

Future<int> tvDisposePlaybackResources(
  Iterable<Future<void> Function()> releases, {
  void Function(Object issue)? onCleanupIssue,
}) async {
  var failureCount = 0;
  for (final release in releases) {
    try {
      await release();
    } catch (issue) {
      failureCount += 1;
      try {
        onCleanupIssue?.call(issue);
      } catch (_) {}
    }
  }
  return failureCount;
}

bool tvPlaybackAsyncResultIsCurrent({
  required bool mounted,
  required int capturedGeneration,
  required int currentGeneration,
  int? capturedSeason,
  int? currentSeason,
  int? capturedEpisode,
  int? currentEpisode,
}) {
  if (!mounted || capturedGeneration != currentGeneration) return false;
  if (capturedSeason != null && capturedSeason != currentSeason) return false;
  if (capturedEpisode != null && capturedEpisode != currentEpisode) {
    return false;
  }
  return true;
}

bool tvPreparedPlaybackCanPublish({
  required bool mounted,
  required int capturedGeneration,
  required int currentGeneration,
  required int capturedAttempt,
  required int currentAttempt,
  required bool controllerIsOwned,
}) {
  return mounted &&
      capturedGeneration == currentGeneration &&
      capturedAttempt == currentAttempt &&
      controllerIsOwned;
}

bool tvPromotePreparedPlaybackController<T>({
  required bool mounted,
  required int capturedGeneration,
  required int currentGeneration,
  required int capturedAttempt,
  required int currentAttempt,
  required T preparedController,
  required T? currentController,
  required T? stagedController,
  required void Function(T? controller) replaceCurrent,
  required void Function(T? controller) replaceStaged,
}) {
  final controllerIsOwned = identical(currentController, preparedController) ||
      identical(stagedController, preparedController);
  if (!tvPreparedPlaybackCanPublish(
    mounted: mounted,
    capturedGeneration: capturedGeneration,
    currentGeneration: currentGeneration,
    capturedAttempt: capturedAttempt,
    currentAttempt: currentAttempt,
    controllerIsOwned: controllerIsOwned,
  )) {
    return false;
  }
  if (identical(stagedController, preparedController)) {
    replaceStaged(null);
    replaceCurrent(preparedController);
  }
  return true;
}

bool tvFailedStartupCanRestoreTimeline({
  required bool attemptIsCurrent,
  required bool controllerIsStaged,
}) {
  return attemptIsCurrent && controllerIsStaged;
}

bool tvSubtitleLookupResultIsCurrent({
  required bool mounted,
  required int capturedSeason,
  required int currentSeason,
  required int capturedEpisode,
  required int currentEpisode,
}) {
  return mounted &&
      capturedSeason == currentSeason &&
      capturedEpisode == currentEpisode;
}

bool tvMedia3HasStartupProof({
  required bool initialized,
  required bool playing,
  required bool firstFrameRendered,
  required Duration position,
  required Duration duration,
  required Size size,
}) {
  if (!initialized || !playing) return false;
  return firstFrameRendered || position >= const Duration(milliseconds: 500);
}

Duration tvPlaybackStartupProofTimeout({
  required bool libVlc,
  required bool livePlayback,
}) {
  if (!libVlc) return const Duration(seconds: 10);
  return livePlayback
      ? const Duration(seconds: 12)
      : const Duration(seconds: 24);
}

bool tvLibVlcRelayHasStartupProof({
  required bool initialized,
  required bool playing,
  required Duration position,
  required int streamedSegments,
  required int streamedBytes,
}) {
  if (!initialized || !playing) return false;
  if (streamedBytes >= 512 * 1024) return true;
  return streamedSegments > 0 &&
      streamedBytes >= 64 * 1024 &&
      position >= const Duration(seconds: 1);
}

bool tvPlaybackReplacementHasPromotionProof({
  required bool initialized,
  required bool playing,
  required bool buffering,
  required bool hasSelectedAudioTrack,
  required Size size,
  required Duration startPosition,
  required Duration currentPosition,
}) {
  if (!initialized || !playing || buffering || !hasSelectedAudioTrack) {
    return false;
  }
  if (size.width <= 0 || size.height <= 0) return false;
  return currentPosition - startPosition >= const Duration(milliseconds: 500);
}

bool tvMedia3HasSelectedAudioTrack(String summary) {
  return RegExp(r'(?:^|,)selected:(?!none\b|0\b)[^,]+').hasMatch(summary);
}

bool tvLibVlcHasSelectedAudioTrack({
  required int trackCount,
  required int trackId,
}) {
  return trackCount > 0 && trackId >= 0;
}

bool tvLibVlcHasSelectedAudioProof({
  required int trackCount,
  required int trackId,
  required int? confirmedTrackId,
}) {
  return tvLibVlcHasSelectedAudioTrack(
        trackCount: trackCount,
        trackId: trackId,
      ) ||
      (confirmedTrackId != null && confirmedTrackId >= 0);
}

int? tvPreferredLibVlcAudioTrack({
  required Map<int, String> tracks,
  required int activeTrack,
}) {
  if (activeTrack >= 0 && tracks.containsKey(activeTrack)) return activeTrack;
  final playable = tracks.keys.where((track) => track >= 0).toList()..sort();
  return playable.isEmpty ? null : playable.first;
}

Object? _tvDecodeLibVlcPigeonReply(Object? reply) {
  if (reply is! List<Object?> || reply.isEmpty) {
    throw StateError('libvlc_audio_reply_invalid');
  }
  if (reply.length != 1) {
    throw StateError('libvlc_audio_reply_error');
  }
  return reply.first;
}

int tvDecodeLibVlcPigeonIntReply(Object? reply) {
  final value = _tvDecodeLibVlcPigeonReply(reply);
  if (value is! num) throw StateError('libvlc_audio_reply_invalid');
  return value.toInt();
}

Map<int, String> tvDecodeLibVlcPigeonTracksReply(Object? reply) {
  final value = _tvDecodeLibVlcPigeonReply(reply);
  if (value is! Map<Object?, Object?>) {
    throw StateError('libvlc_audio_reply_invalid');
  }
  final tracks = <int, String>{};
  for (final entry in value.entries) {
    if (entry.key is! num || entry.value is! String) {
      throw StateError('libvlc_audio_reply_invalid');
    }
    tracks[(entry.key as num).toInt()] = entry.value! as String;
  }
  return tracks;
}

Future<Object?> _tvCallLibVlcPigeon(
  String method,
  List<Object?> arguments,
) async {
  final channel = BasicMessageChannel<Object?>(
    '$_tvLibVlcPigeonChannelPrefix$method',
    const StandardMessageCodec(),
  );
  return channel.send(arguments);
}

bool tvPlaybackCadenceShouldReport({
  required int lastReportedSecond,
  required int positionSecond,
}) {
  if (positionSecond <= 0 || positionSecond <= lastReportedSecond) return false;
  return lastReportedSecond < 0 || positionSecond - lastReportedSecond >= 5;
}

bool tvPlaybackProgressCanPublish({
  required bool controllerIsCurrent,
  required bool switchingSource,
}) =>
    controllerIsCurrent && !switchingSource;

bool tvPlaybackCanPublishResumePrompt({
  required bool initialized,
  required bool playing,
}) {
  return initialized && !playing;
}

bool tvPlaybackResumePauseShouldRetry({
  required bool initialized,
  required bool playing,
  required int attempt,
}) {
  return initialized && playing && attempt < 5;
}

Future<bool> tvSettleControllerPauseForResume({
  required Future<void> Function() pause,
  required bool Function() isCurrent,
  required bool Function() isInitialized,
  required bool Function() isPlaying,
  int maxAttempts = 5,
  Duration attemptTimeout = const Duration(seconds: 1),
  Duration pollInterval = const Duration(milliseconds: 50),
  void Function(int attempt)? onRetry,
}) async {
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    if (!isCurrent()) return false;
    final deadline = DateTime.now().add(attemptTimeout);
    try {
      await pause().timeout(attemptTimeout);
    } catch (_) {
      // The caller still owns the controller; retry only within this budget.
    }
    while (isCurrent() &&
        isInitialized() &&
        isPlaying() &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
    }
    if (!isCurrent()) return false;
    if (isInitialized() && !isPlaying()) return true;
    if (attempt < maxAttempts) onRetry?.call(attempt);
  }
  return false;
}

Future<bool> tvSettleControllerPlay({
  required Future<void> Function() play,
  required bool Function() isCurrent,
  required bool Function() isInitialized,
  required bool Function() isPlaying,
  int maxAttempts = 5,
  Duration attemptTimeout = const Duration(seconds: 1),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    if (!isCurrent() || !isInitialized()) return false;
    if (isPlaying()) return true;
    try {
      await play().timeout(attemptTimeout);
    } catch (_) {
      // Retry only while this exact initialized controller remains current.
    }
    final deadline = DateTime.now().add(attemptTimeout);
    while (isCurrent() &&
        isInitialized() &&
        !isPlaying() &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
    }
    if (!isCurrent() || !isInitialized()) return false;
    if (isPlaying()) return true;
  }
  return false;
}

bool tvDetachFailedStartupController<T>({
  required T? Function() currentController,
  required T failedController,
  required void Function() detach,
}) {
  if (!identical(currentController(), failedController)) return false;
  detach();
  return true;
}

Future<void> tvRollbackPreparedP2pOnCanceledStartup({
  required bool p2pPrepared,
  required Future<void> Function() rollback,
}) async {
  if (p2pPrepared) await rollback();
}

Future<bool> tvFinalizePreparedPlaybackOwnership({
  required Future<void> Function() finalizeOwnership,
  required bool Function() isCurrent,
  required Future<void> Function() disposePreparedController,
  Future<void> Function()? rollbackPreparedOwnership,
}) async {
  await finalizeOwnership();
  if (isCurrent()) return true;
  await disposePreparedController();
  await rollbackPreparedOwnership?.call();
  return false;
}

int tvP2pOwnershipGenerationForStartupAttempt(int startupAttempt) {
  if (startupAttempt <= 0) {
    throw ArgumentError.value(startupAttempt, 'startupAttempt');
  }
  return startupAttempt;
}

List<int> tvFreshFallbackCandidateIndexes({
  required List<String> mergedKeys,
  required List<String> freshKeys,
  List<String> cachedKeys = const <String>[],
}) {
  final cached = cachedKeys.where((key) => key.isNotEmpty).toSet();
  final freshOnly =
      freshKeys.where((key) => key.isNotEmpty && !cached.contains(key)).toSet();
  if (freshOnly.isEmpty) return const <int>[];
  return <int>[
    for (var index = 0; index < mergedKeys.length; index++)
      if (freshOnly.contains(mergedKeys[index])) index,
  ];
}

List<T> tvExcludeRejectedPlaybackSessions<T>({
  required Iterable<T> sessions,
  required Set<String> rejectedKeys,
  required String Function(T session) keyOf,
}) {
  if (rejectedKeys.isEmpty) return sessions.toList(growable: false);
  return <T>[
    for (final session in sessions)
      if (!rejectedKeys.contains(keyOf(session))) session,
  ];
}

class TvMedia3StatePollGate {
  int _generation = 0;
  bool _inFlight = false;
  bool _disposed = false;

  int? begin() {
    if (_disposed || _inFlight) return null;
    _inFlight = true;
    return ++_generation;
  }

  bool accept(int generation) {
    if (!_disposed && _inFlight && generation == _generation) {
      _inFlight = false;
      return true;
    }
    return false;
  }

  void dispose() {
    _disposed = true;
    _inFlight = false;
    _generation += 1;
  }
}

const MethodChannel _tvRemoteKeyChannel = MethodChannel(
  'app.juicr.flutter/tv_remote_keys',
);

enum _TvPlaybackEngine { media3, libvlc }

class _TvPlaybackCanceledException implements Exception {
  const _TvPlaybackCanceledException();

  @override
  String toString() => 'playback_canceled';
}

class _TvPlaybackValue {
  const _TvPlaybackValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isEnded = false,
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.size = Size.zero,
    this.aspectRatio = 16 / 9,
    this.errorDescription = '',
    this.audioSinkErrorCount = 0,
    this.hasSelectedAudioTrack = false,
  });

  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool isEnded;
  final Duration duration;
  final Duration position;
  final Size size;
  final double aspectRatio;
  final String errorDescription;
  final int audioSinkErrorCount;
  final bool hasSelectedAudioTrack;

  static const empty = _TvPlaybackValue();
}

enum _TvPlaybackSkipSegmentKind {
  intro,
  recap,
  outro,
  preview;

  String get label {
    return switch (this) {
      _TvPlaybackSkipSegmentKind.intro => 'Skip intro',
      _TvPlaybackSkipSegmentKind.recap => 'Skip recap',
      _TvPlaybackSkipSegmentKind.outro => 'Skip outro',
      _TvPlaybackSkipSegmentKind.preview => 'Skip preview',
    };
  }

  static _TvPlaybackSkipSegmentKind? fromValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'intro' || 'opening' => _TvPlaybackSkipSegmentKind.intro,
      'recap' || 'previously' => _TvPlaybackSkipSegmentKind.recap,
      'outro' || 'credits' || 'ending' => _TvPlaybackSkipSegmentKind.outro,
      'preview' || 'next' => _TvPlaybackSkipSegmentKind.preview,
      _ => null,
    };
  }
}

class _TvPlaybackSkipSegmentTiming {
  const _TvPlaybackSkipSegmentTiming({
    required this.kind,
    required this.start,
    required this.end,
  });

  final _TvPlaybackSkipSegmentKind kind;
  final Duration start;
  final Duration end;

  String get label => kind.label;

  bool activeAt(Duration position, Duration duration) {
    if (duration <= Duration.zero || end <= start) return false;
    final clampedEnd = _tvSkipTargetWithinDuration(end, duration);
    if (clampedEnd <= position + const Duration(seconds: 2)) return false;
    return position >= start && position < end;
  }

  Duration targetFor(Duration duration) =>
      _tvSkipTargetWithinDuration(end, duration);
}

class _TvPlaybackSkipSegmentClient {
  const _TvPlaybackSkipSegmentClient();

  static const _timeout = Duration(seconds: 4);

  Future<List<_TvPlaybackSkipSegmentTiming>> lookup({
    required int? tmdbId,
    required String? imdbId,
    required int? season,
    required int? episode,
    Duration? duration,
  }) async {
    final cleanTmdbId = tmdbId != null && tmdbId > 0 ? tmdbId : null;
    final cleanImdbId = _tvCleanImdbId(imdbId);
    if ((cleanTmdbId == null && cleanImdbId == null) ||
        season == null ||
        season <= 0 ||
        episode == null ||
        episode <= 0) {
      return const <_TvPlaybackSkipSegmentTiming>[];
    }
    final endpoint = Uri.parse(_apiBase).resolve('/skip-segments');
    final parameters = <String, String>{
      if (cleanTmdbId != null) 'tmdb_id': cleanTmdbId.toString(),
      if (cleanImdbId != null) 'imdb_id': cleanImdbId,
      'season': season.toString(),
      'episode': episode.toString(),
      if (duration != null && duration > Duration.zero)
        'duration_ms': duration.inMilliseconds.toString(),
    };
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(endpoint.replace(queryParameters: parameters))
          .timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const <_TvPlaybackSkipSegmentTiming>[];
      }
      final body = await utf8.decoder.bind(response).join().timeout(_timeout);
      return _parseTvPlaybackSkipSegments(jsonDecode(body));
    } finally {
      client.close(force: true);
    }
  }
}

class _TvPlaybackFeedbackClient {
  const _TvPlaybackFeedbackClient();

  static const _timeout = Duration(seconds: 4);

  Future<void> send({
    required String providerId,
    required String event,
    required String engine,
    required String mediaType,
    required String quality,
    required String sourceType,
    required String sourceClass,
    required int positionSeconds,
    required int durationSeconds,
    required int sourceCount,
    int? startupMs,
  }) async {
    final cleanProviderId = providerId.trim();
    final cleanEvent = event.trim();
    if (cleanProviderId.isEmpty || cleanEvent.isEmpty) return;

    final body = <String, Object?>{
      'providerId': cleanProviderId,
      'event': cleanEvent,
      if (engine.trim().isNotEmpty) 'engine': engine.trim(),
      if (mediaType.trim().isNotEmpty) 'mediaType': mediaType.trim(),
      if (quality.trim().isNotEmpty) 'quality': quality.trim(),
      if (sourceType.trim().isNotEmpty) 'sourceType': sourceType.trim(),
      if (sourceClass.trim().isNotEmpty) 'sourceClass': sourceClass.trim(),
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'sourceCount': sourceCount,
      if (startupMs != null && startupMs >= 0) 'startupMs': startupMs,
    };
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client
          .postUrl(Uri.parse(_apiBase).resolve('/ops/playback-feedback'))
          .timeout(_timeout);
      for (final entry in _TvApi.juicrClientHeaders.entries) {
        request.headers.set(entry.key, entry.value);
      }
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(_timeout);
      await response.drain<void>().timeout(_timeout);
    } catch (error) {
      debugPrint(
        'Juicr TV playback feedback skipped '
        'event=$cleanEvent bucket=${_apiErrorBucket(error)}',
      );
    } finally {
      client.close(force: true);
    }
  }
}

_TvPlaybackSkipSegmentTiming? _activeTvPlaybackSkipSegment(
  List<_TvPlaybackSkipSegmentTiming> segments,
  Duration position,
  Duration duration,
) {
  for (final segment in segments) {
    if (segment.activeAt(position, duration)) return segment;
  }
  return null;
}

List<_TvPlaybackSkipSegmentTiming> _parseTvPlaybackSkipSegments(
  Object? payload,
) {
  final entries = <_TvPlaybackSkipSegmentTiming>[];
  for (final raw in _tvSkipSegmentCandidates(payload)) {
    final segment = _parseTvPlaybackSkipSegment(raw);
    if (segment != null) entries.add(segment);
  }
  entries.sort((left, right) {
    final startCompare = left.start.compareTo(right.start);
    if (startCompare != 0) return startCompare;
    return left.end.compareTo(right.end);
  });
  return entries;
}

Iterable<Map<String, Object?>> _tvSkipSegmentCandidates(Object? payload) sync* {
  if (payload is List) {
    for (final entry in payload) {
      if (entry is Map) yield Map<String, Object?>.from(entry);
    }
    return;
  }
  if (payload is! Map) return;
  final map = Map<String, Object?>.from(payload);
  final nested =
      map['segments'] ?? map['data'] ?? map['items'] ?? map['results'];
  if (nested is List) {
    yield* _tvSkipSegmentCandidates(nested);
    return;
  }
  var yieldedNamedSegment = false;
  for (final kind in _TvPlaybackSkipSegmentKind.values) {
    final value = map[kind.name];
    if (value is Map) {
      yieldedNamedSegment = true;
      yield {
        ...Map<String, Object?>.from(value),
        'type': value['type'] ?? kind.name,
      };
    }
  }
  if (yieldedNamedSegment) return;
  if (_tvReadSkipDuration(map, const ['start', 'start_sec', 'start_time']) !=
          null &&
      _tvReadSkipDuration(map, const ['end', 'end_sec', 'end_time']) != null) {
    yield map;
  }
}

_TvPlaybackSkipSegmentTiming? _parseTvPlaybackSkipSegment(
  Map<String, Object?> raw,
) {
  final kind = _TvPlaybackSkipSegmentKind.fromValue(
        raw['type'] ?? raw['kind'] ?? raw['segment_type'],
      ) ??
      _TvPlaybackSkipSegmentKind.intro;
  final start = _tvReadSkipDuration(raw, const [
    'start',
    'start_sec',
    'start_time',
    'startSeconds',
    'startTime',
  ]);
  final end = _tvReadSkipDuration(raw, const [
    'end',
    'end_sec',
    'end_time',
    'endSeconds',
    'endTime',
  ]);
  if (start == null || end == null) return null;
  if (end <= start + const Duration(seconds: 2)) return null;
  return _TvPlaybackSkipSegmentTiming(
    kind: kind,
    start: start < Duration.zero ? Duration.zero : start,
    end: end,
  );
}

Duration? _tvReadSkipDuration(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final duration = _tvParseSkipDuration(map[key]);
    if (duration != null) return duration;
  }
  return null;
}

Duration? _tvParseSkipDuration(Object? value) {
  if (value is num) {
    return Duration(milliseconds: (value * 1000).round());
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final numeric = num.tryParse(trimmed);
    if (numeric != null) {
      return Duration(milliseconds: (numeric * 1000).round());
    }
    final parts = trimmed.split(':');
    if (parts.length == 2 || parts.length == 3) {
      final values = parts.map((part) => num.tryParse(part)).toList();
      if (values.any((part) => part == null)) return null;
      final seconds = parts.length == 2
          ? (values[0]! * 60) + values[1]!
          : (values[0]! * 3600) + (values[1]! * 60) + values[2]!;
      return Duration(milliseconds: (seconds * 1000).round());
    }
  }
  return null;
}

Duration _tvSkipTargetWithinDuration(Duration target, Duration duration) {
  if (duration <= Duration.zero) return target;
  final latestTarget = duration - const Duration(seconds: 2);
  if (latestTarget <= Duration.zero) return target;
  return target > latestTarget ? latestTarget : target;
}

String? _tvCleanImdbId(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return RegExp(r'^tt\d+$').hasMatch(trimmed) ? trimmed : null;
}

class _TvRelayStartupProof extends ChangeNotifier {
  var _streamedSegments = 0;
  var _streamedBytes = 0;
  var _duration = Duration.zero;

  int get streamedSegments => _streamedSegments;
  int get streamedBytes => _streamedBytes;
  Duration get duration => _duration;
  bool get hasMediaProof => _streamedBytes >= 512 * 1024;

  void updateDuration(Duration duration) {
    if (duration <= Duration.zero || duration == _duration) return;
    _duration = duration;
    notifyListeners();
  }

  void updateProgress(int streamedSegments) {
    if (streamedSegments <= _streamedSegments) return;
    _streamedSegments = streamedSegments;
    notifyListeners();
  }

  void updateBytes(int streamedBytes) {
    if (streamedBytes <= _streamedBytes) return;
    _streamedBytes = streamedBytes;
    notifyListeners();
  }
}

class _TvMedia3PlaybackController {
  _TvMedia3PlaybackController(
    this.session, {
    required this.subtitles,
    required this.liveMode,
  });

  final _PlaybackSession session;
  final List<_TvSubtitle> subtitles;
  final bool liveMode;
  final Completer<void> _viewReady = Completer<void>();
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  Timer? _pollTimer;
  final TvMedia3StatePollGate _pollGate = TvMedia3StatePollGate();
  int? _viewId;
  bool _disposed = false;
  _TvPlaybackValue value = _TvPlaybackValue.empty;
  bool firstFrameRendered = false;
  String errorBucket = 'none';

  Map<String, Object?> get creationParams => <String, Object?>{
        'url': session.tvMediaUrl,
        'headers': session.httpHeaders,
        'type': session.sourceType,
        'sourceClass':
            session.sourceClass.isEmpty ? 'direct' : session.sourceClass,
        'liveMode': liveMode,
        'subtitleAutoSelect': subtitles.isEmpty ? 'off' : 'selected',
        'subtitleLanguage': subtitles.isEmpty ? '' : subtitles.first.language,
        'subtitles': subtitles
            .map(
              (subtitle) => <String, Object?>{
                'url': subtitle.url,
                'language': subtitle.language,
                'label': subtitle.label,
                'format': subtitle.format,
                'selected': true,
              },
            )
            .toList(),
      };

  void attachView(int viewId) {
    if (_disposed) return;
    _viewId = viewId;
    if (!_viewReady.isCompleted) _viewReady.complete();
    _startPolling();
  }

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  Future<void> initialize({
    Duration timeout = const Duration(seconds: 22),
  }) async {
    await _viewReady.future.timeout(timeout);
    _startPolling();
    final deadline = DateTime.now().add(timeout);
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      await _syncState();
      if (value.errorDescription.isNotEmpty) {
        throw StateError(value.errorDescription);
      }
      if (value.isInitialized) return;
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
    throw TimeoutException('Media3 initialize timed out', timeout);
  }

  Future<void> play() => _invoke('play');
  Future<void> pause() => _invoke('pause');
  Future<void> seekTo(Duration position) => _invoke('seekTo', <String, Object?>{
        'positionMs': position.inMilliseconds,
      });
  Future<void> setPlaybackSpeed(double speed) =>
      _invoke('setPlaybackSpeed', <String, Object?>{'speed': speed});
  Future<void> setVideoSizeMode(String mode) =>
      _invoke('setVideoSizeMode', <String, Object?>{'mode': mode});

  Future<void> _invoke(String method, [Map<String, Object?> args = const {}]) {
    final viewId = _viewId;
    if (viewId == null || _disposed) return Future<void>.value();
    return _tvMedia3PlayerChannel.invokeMethod<void>(method, <String, Object?>{
      'viewId': viewId,
      ...args,
    });
  }

  void _startPolling() {
    if (_pollTimer != null || _disposed) return;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      unawaited(_syncState());
    });
  }

  Future<void> _syncState() async {
    final viewId = _viewId;
    if (viewId == null || _disposed) return;
    final pollGeneration = _pollGate.begin();
    if (pollGeneration == null) return;
    late final Map<String, Object?>? raw;
    try {
      raw = await _tvMedia3PlayerChannel.invokeMapMethod<String, Object?>(
        'state',
        <String, Object?>{'viewId': viewId},
      );
    } catch (error) {
      if (!_pollGate.accept(pollGeneration) || _disposed) return;
      value = _TvPlaybackValue(
        isInitialized: value.isInitialized,
        isPlaying: false,
        isBuffering: false,
        isEnded: false,
        duration: value.duration,
        position: value.position,
        size: value.size,
        aspectRatio: value.aspectRatio,
        errorDescription: 'media3_view_detached',
        audioSinkErrorCount: value.audioSinkErrorCount,
        hasSelectedAudioTrack: value.hasSelectedAudioTrack,
      );
      errorBucket = 'detached';
      debugPrint(
        'Juicr TV Media3 state sync failed '
        'viewId=$viewId errorType=${error.runtimeType}',
      );
      for (final listener in List<VoidCallback>.of(_listeners)) {
        listener();
      }
      return;
    }
    if (!_pollGate.accept(pollGeneration) || raw == null || _disposed) return;
    final hasError = raw['hasError'] == true;
    final width = (raw['width'] as num?)?.toDouble() ?? 0;
    final height = (raw['height'] as num?)?.toDouble() ?? 0;
    final size = width > 0 && height > 0 ? Size(width, height) : Size.zero;
    firstFrameRendered = raw['firstFrameRendered'] == true;
    errorBucket = (raw['errorBucket'] as String?) ?? 'none';
    final audioSinkErrorCount =
        (raw['audioSinkErrorCount'] as num?)?.round() ?? 0;
    final audioTrackSummary = (raw['audioTrackSummary'] as String?) ?? '';
    value = _TvPlaybackValue(
      isInitialized: raw['initialized'] == true,
      isPlaying: raw['playing'] == true,
      isBuffering: raw['buffering'] == true,
      isEnded: raw['ended'] == true,
      duration: Duration(
        milliseconds: (raw['durationMs'] as num?)?.round() ?? 0,
      ),
      position: Duration(
        milliseconds: (raw['positionMs'] as num?)?.round() ?? 0,
      ),
      size: size,
      aspectRatio:
          size.width > 0 && size.height > 0 ? size.width / size.height : 16 / 9,
      errorDescription: hasError
          ? ((raw['errorDescription'] as String?) ?? 'media3_error')
          : '',
      audioSinkErrorCount: audioSinkErrorCount,
      hasSelectedAudioTrack: tvMedia3HasSelectedAudioTrack(audioTrackSummary),
    );
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _pollGate.dispose();
    _pollTimer?.cancel();
    _listeners.clear();
    final viewId = _viewId;
    if (viewId != null) {
      await _tvMedia3PlayerChannel.invokeMethod<void>(
        'dispose',
        <String, Object?>{'viewId': viewId},
      );
    }
  }
}

class _TvNativePlaybackController extends ChangeNotifier {
  _TvNativePlaybackController.media3(
    _PlaybackSession session, {
    required List<_TvSubtitle> subtitles,
    required bool liveMode,
    LibVlcHlsRelay? relay,
  })  : engine = _TvPlaybackEngine.media3,
        _video = null,
        _media3 = _TvMedia3PlaybackController(
          session,
          subtitles: subtitles,
          liveMode: liveMode,
        ),
        _vlc = null,
        _relay = relay,
        _relayProof = null {
    _media3!.addListener(notifyListeners);
  }

  _TvNativePlaybackController.libvlc(
    _PlaybackSession session, {
    LibVlcHlsRelay? relay,
    _TvRelayStartupProof? relayProof,
  })  : engine = _TvPlaybackEngine.libvlc,
        _video = null,
        _media3 = null,
        _relay = relay,
        _relayProof = relayProof,
        _vlc = VlcPlayerController.network(
          session.tvMediaUrl,
          hwAcc: tvLibVlcHardwareAcceleration(
            sourceType: session.sourceType,
            mediaUrl: session.tvMediaUrl,
          ),
          autoInitialize: false,
          autoPlay: false,
          options: _tvVlcPlayerOptions(session.httpHeaders),
        ) {
    _vlc!.addListener(notifyListeners);
    _relayProof?.addListener(notifyListeners);
  }

  final _TvPlaybackEngine engine;
  final VideoPlayerController? _video;
  final _TvMedia3PlaybackController? _media3;
  final VlcPlayerController? _vlc;
  final LibVlcHlsRelay? _relay;
  final _TvRelayStartupProof? _relayProof;
  final GlobalKey _surfaceIdentity = GlobalKey();
  int? _confirmedLibVlcAudioTrackId;
  bool _disposed = false;
  bool get hasStartupProof {
    final video = _video;
    if (video != null) {
      final current = value;
      return current.isInitialized &&
          current.isPlaying &&
          current.position >= const Duration(seconds: 1);
    }
    final media3 = _media3;
    if (media3 != null) {
      final current = media3.value;
      if (!current.isInitialized || current.errorDescription.isNotEmpty) {
        return false;
      }
      return tvMedia3HasStartupProof(
        initialized: current.isInitialized,
        playing: current.isPlaying,
        firstFrameRendered: media3.firstFrameRendered,
        position: current.position,
        duration: current.duration,
        size: current.size,
      );
    }
    final current = value;
    final relayProof = _relayProof;
    if (relayProof != null) {
      return tvLibVlcRelayHasStartupProof(
        initialized: current.isInitialized,
        playing: current.isPlaying,
        position: current.position,
        streamedSegments: relayProof.streamedSegments,
        streamedBytes: relayProof.streamedBytes,
      );
    }
    return current.isInitialized &&
        current.isPlaying &&
        (current.duration > Duration.zero ||
            current.size.width > 0 && current.size.height > 0 ||
            current.position >= const Duration(seconds: 1));
  }

  _TvPlaybackValue get value {
    final video = _video;
    if (video != null) {
      final raw = video.value;
      return _TvPlaybackValue(
        isInitialized: raw.isInitialized,
        isPlaying: raw.isPlaying,
        isBuffering: raw.isBuffering,
        isEnded: raw.isCompleted,
        duration: raw.duration,
        position: raw.position,
        size: raw.size,
        aspectRatio: raw.aspectRatio <= 0 ? 16 / 9 : raw.aspectRatio,
        errorDescription: raw.hasError ? raw.errorDescription ?? '' : '',
        audioSinkErrorCount: 0,
        hasSelectedAudioTrack: raw.isInitialized,
      );
    }
    final media3 = _media3;
    if (media3 != null) return media3.value;
    final raw = _vlc!.value;
    final relayDuration = _relayProof?.duration ?? Duration.zero;
    return _TvPlaybackValue(
      isInitialized: raw.isInitialized,
      isPlaying: raw.isPlaying,
      isBuffering: raw.isBuffering,
      isEnded: raw.isEnded,
      duration: raw.duration > Duration.zero ? raw.duration : relayDuration,
      position: raw.position,
      size: raw.size,
      aspectRatio: raw.aspectRatio <= 0 ? 16 / 9 : raw.aspectRatio,
      errorDescription: raw.hasError ? raw.errorDescription : '',
      audioSinkErrorCount: 0,
      hasSelectedAudioTrack: tvLibVlcHasSelectedAudioProof(
        trackCount: raw.audioTracksCount,
        trackId: raw.activeAudioTrack,
        confirmedTrackId: _confirmedLibVlcAudioTrackId,
      ),
    );
  }

  Future<void> initialize({
    Duration timeout = const Duration(seconds: 22),
  }) async {
    final video = _video;
    if (video != null) return video.initialize().timeout(timeout);
    final media3 = _media3;
    if (media3 != null) return media3.initialize(timeout: timeout);
    final vlc = _vlc!;
    if (vlc.value.isInitialized) return Future<void>.value();
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_vlcViewAttached(vlc)) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!_vlcViewAttached(vlc)) {
      throw TimeoutException('libVLC view attach timed out', timeout);
    }
    final completer = Completer<void>();
    late VoidCallback listener;
    var listenerAttached = false;
    void detachListener() {
      if (!listenerAttached) return;
      listenerAttached = false;
      vlc.removeListener(listener);
    }

    listener = () {
      final value = vlc.value;
      if (value.hasError && !completer.isCompleted) {
        completer.completeError(value.errorDescription);
      } else if (value.isInitialized && !completer.isCompleted) {
        completer.complete();
      }
      if (completer.isCompleted) detachListener();
    };
    vlc.addListener(listener);
    listenerAttached = true;
    await vlc.initialize().catchError((Object error) {
      final message = error.toString().toLowerCase();
      if (message.contains('already initialized')) return;
      if (!completer.isCompleted) completer.completeError(error);
    });
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      detachListener();
      throw TimeoutException('libVLC initialize timed out', timeout);
    }
    return completer.future.timeout(
      remaining,
      onTimeout: () {
        detachListener();
        throw TimeoutException('libVLC initialize timed out', timeout);
      },
    );
  }

  Future<void> play() => _video?.play() ?? _media3?.play() ?? _vlc!.play();
  Future<void> pause() => _video?.pause() ?? _media3?.pause() ?? _vlc!.pause();
  Future<void> stop() => _vlc?.stop() ?? pause();
  Future<void> seekTo(Duration position) =>
      _video?.seekTo(position) ??
      _media3?.seekTo(position) ??
      _vlc!.seekTo(position);
  Future<void> setPlaybackSpeed(double speed) =>
      _video?.setPlaybackSpeed(speed) ??
      _media3?.setPlaybackSpeed(speed) ??
      _vlc!.setPlaybackSpeed(speed);
  Future<void> setVideoSizeMode(String mode) =>
      _media3?.setVideoSizeMode(mode) ?? Future<void>.value();

  Future<void> ensureSelectedAudioTrack({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final vlc = _vlc;
    if (vlc == null) return;
    final dynamic rawController = vlc;
    final Object? rawViewId = rawController.viewId;
    if (rawViewId is! int) {
      throw StateError('libvlc_audio_view_unavailable');
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final trackCount = tvDecodeLibVlcPigeonIntReply(
        await _tvCallLibVlcPigeon('getAudioTracksCount', <Object?>[rawViewId]),
      );
      final tracks = tvDecodeLibVlcPigeonTracksReply(
        await _tvCallLibVlcPigeon('getAudioTracks', <Object?>[rawViewId]),
      );
      var activeTrack = tvDecodeLibVlcPigeonIntReply(
        await _tvCallLibVlcPigeon('getAudioTrack', <Object?>[rawViewId]),
      );
      final preferred = tvPreferredLibVlcAudioTrack(
        tracks: tracks,
        activeTrack: activeTrack,
      );
      if (preferred != null) {
        if (preferred != activeTrack) {
          await _tvCallLibVlcPigeon(
            'setAudioTrack',
            <Object?>[rawViewId, preferred],
          );
          await Future<void>.delayed(const Duration(milliseconds: 120));
          activeTrack = tvDecodeLibVlcPigeonIntReply(
            await _tvCallLibVlcPigeon('getAudioTrack', <Object?>[rawViewId]),
          );
        }
        vlc.value = vlc.value.copyWith(
          audioTracksCount: trackCount,
          activeAudioTrack: activeTrack,
        );
        if (tvLibVlcHasSelectedAudioTrack(
          trackCount: vlc.value.audioTracksCount,
          trackId: vlc.value.activeAudioTrack,
        )) {
          _confirmedLibVlcAudioTrackId = activeTrack;
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw StateError('libvlc_audio_track_unavailable');
  }

  bool _vlcViewAttached(VlcPlayerController vlc) {
    try {
      final dynamic controller = vlc;
      return controller.viewId is int;
    } catch (_) {
      return false;
    }
  }

  Future<void> _disposeVlcSafely() async {
    final vlc = _vlc;
    if (vlc == null) return;
    if (!_vlcViewAttached(vlc)) {
      debugPrint(
        'Juicr TV libVLC dispose skipped before view attach '
        'reason=unattached_view',
      );
      return;
    }
    try {
      await vlc.dispose();
    } catch (error) {
      if (!error.runtimeType.toString().contains('LateInitializationError')) {
        rethrow;
      }
      debugPrint(
        'Juicr TV libVLC dispose ignored before view attach '
        'errorType=${error.runtimeType}',
      );
    }
  }

  Widget surface({required double aspectRatio}) {
    final video = _video;
    if (video != null) {
      return tvPlaybackSurfaceWithIdentity(
        identity: _surfaceIdentity,
        child: IgnorePointer(child: VideoPlayer(video)),
      );
    }
    final media3 = _media3;
    if (media3 != null) {
      return tvPlaybackSurfaceWithIdentity(
        identity: _surfaceIdentity,
        child: IgnorePointer(
          child: AndroidView(
            key: ValueKey<int>(identityHashCode(media3)),
            viewType: 'app.juicr.flutter/media3_player',
            creationParams: media3.creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: media3.attachView,
          ),
        ),
      );
    }
    return tvPlaybackSurfaceWithIdentity(
      identity: _surfaceIdentity,
      child: IgnorePointer(
        child: VlcPlayer(
          controller: _vlc!,
          aspectRatio: aspectRatio,
          placeholder: const ColoredBox(color: Colors.black),
          virtualDisplay: true,
        ),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _video?.removeListener(notifyListeners);
    _media3?.removeListener(notifyListeners);
    _vlc?.removeListener(notifyListeners);
    _relayProof?.removeListener(notifyListeners);
    await tvDisposePlaybackResources(
      <Future<void> Function()>[
        () async {
          await _video?.dispose();
        },
        () async {
          await _media3?.dispose();
        },
        _disposeVlcSafely,
        () async {
          await _relay?.stop();
        },
      ],
      onCleanupIssue: (issue) => debugPrint(
        'Juicr TV playback cleanup incomplete issueType=${issue.runtimeType}',
      ),
    );
    super.dispose();
  }
}

HwAcc tvLibVlcHardwareAcceleration({
  required String sourceType,
  required String mediaUrl,
}) {
  final normalizedType = sourceType.trim().toLowerCase();
  final normalizedPath = Uri.tryParse(mediaUrl)?.path.toLowerCase() ?? '';
  final directMp4 = normalizedType == 'mp4' ||
      normalizedType == 'file' ||
      normalizedPath.endsWith('.mp4');
  return directMp4 ? HwAcc.decoding : HwAcc.auto;
}

VlcPlayerOptions _tvVlcPlayerOptions(Map<String, String> headers) {
  final extras = <String>[
    ':network-caching=1800',
    ':http-reconnect',
    ':http-forward-cookies',
  ];
  final http = <String>[
    VlcHttpOptions.httpReconnect(true),
    VlcHttpOptions.httpForwardCookies(true),
  ];
  for (final entry in headers.entries) {
    final key = entry.key.trim().toLowerCase();
    final value = entry.value.trim();
    if (value.isEmpty) continue;
    if (key == 'user-agent') {
      http.add(VlcHttpOptions.httpUserAgent(value));
      extras.add(':http-user-agent=$value');
    } else if (key == 'referer' || key == 'referrer') {
      http.add(VlcHttpOptions.httpReferrer(value));
      extras.add(':http-referrer=$value');
    } else if (key == 'cookie') {
      extras.add(':http-cookie=$value');
    } else {
      extras.add(':http-header=${entry.key.trim()}: $value');
    }
  }
  return VlcPlayerOptions(
    advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(1800)]),
    http: VlcHttpOptions(http),
    extras: extras,
  );
}

/// Test-only observation hook for episode-dialog ownership races.
@visibleForTesting
class TvPlaybackPageLifecycleHarness {
  TvPlaybackPageLifecycleHarness({
    this.skipInitialPlayback = false,
    this.prepareEpisode,
  });

  final bool skipInitialPlayback;
  final Future<bool> Function(int season, int episode)? prepareEpisode;
  Future<bool> Function(int season)? openSeasonEpisodes;
  Future<void> Function()? openEpisodesPanel;
  int episodePromotions = 0;
  int activeSeason = 1;
  int activeEpisode = 1;

  void recordEpisodePromotion({required int season, required int episode}) {
    episodePromotions += 1;
    activeSeason = season;
    activeEpisode = episode;
  }
}

@visibleForTesting
Widget buildTvPlaybackEpisodeTestPage({
  required TvPlaybackPageLifecycleHarness lifecycleHarness,
}) {
  return _TvPlaybackPage(
    item: const _TvItem(
      id: 'series-test',
      type: 'series',
      title: 'Series test',
      color: Colors.black,
      episodes: <_TvEpisode>[
        _TvEpisode(
          season: 1,
          episode: 1,
          title: 'First',
          description: 'First episode',
        ),
        _TvEpisode(
          season: 1,
          episode: 2,
          title: 'Second',
          description:
              'Second episode with enough detail to overflow the available row width and prove focused horizontal reading.',
        ),
      ],
    ),
    sessions: const <_PlaybackSession>[
      _PlaybackSession(
        mediaUrl: 'https://example.invalid/video.m3u8',
        sourceType: 'hls',
        httpHeaders: <String, String>{},
        quality: '720P',
      ),
    ],
    initialSessionIndex: 0,
    initialSeason: 1,
    initialEpisode: 1,
    initialResumePosition: Duration.zero,
    settings: const _TvSettingsState(builtInPlayback: true),
    subtitles: const <_TvSubtitle>[],
    initialSubtitleIndex: -1,
    lifecycleHarness: lifecycleHarness,
  );
}

class _TvPlaybackPage extends StatefulWidget {
  const _TvPlaybackPage({
    required this.item,
    required this.sessions,
    required this.initialSessionIndex,
    required this.initialSeason,
    required this.initialEpisode,
    required this.initialResumePosition,
    this.initialResumeProgress,
    required this.settings,
    required this.subtitles,
    required this.initialSubtitleIndex,
    this.subtitleId,
    this.subtitleLanguage = 'auto',
    this.onSubtitlePreferenceChanged,
    this.onSubtitleDelayChanged,
    this.resolveSubtitles,
    this.resolveFreshSessions,
    this.onProgress,
    this.onProgressReset,
    this.onVerifiedSession,
    this.onRejectedSession,
    this.lifecycleHarness,
  });

  final _TvItem item;
  final List<_PlaybackSession> sessions;
  final int initialSessionIndex;
  final int initialSeason;
  final int initialEpisode;
  final Duration initialResumePosition;
  final _TvPlaybackProgress? initialResumeProgress;
  final _TvSettingsState settings;
  final List<_TvSubtitle> subtitles;
  final int initialSubtitleIndex;
  final String? subtitleId;
  final String subtitleLanguage;
  final Future<void> Function(String? subtitleId, String subtitleLanguage)?
      onSubtitlePreferenceChanged;
  final Future<void> Function(int subtitleDelayMillis)? onSubtitleDelayChanged;
  final Future<List<_TvSubtitle>> Function(int season, int episode)?
      resolveSubtitles;
  final Future<List<_PlaybackSession>> Function(Set<String> rejectedKeys)?
      resolveFreshSessions;
  final void Function(int season, int episode, _TvPlaybackProgress progress)?
      onProgress;
  final Future<void> Function(int season, int episode)? onProgressReset;
  final void Function(_PlaybackSession session, String engineId)?
      onVerifiedSession;
  final void Function(_PlaybackSession session)? onRejectedSession;
  @visibleForTesting
  final TvPlaybackPageLifecycleHarness? lifecycleHarness;

  @override
  State<_TvPlaybackPage> createState() => _TvPlaybackPageState();
}

const String _tvVideoSizeFit = 'fit';
const String _tvVideoSizeFill = 'fill';
const String _tvVideoSizeWide = 'wide';
const String _tvVideoSizeStretch = 'stretch';

String _normalizeTvVideoSizeMode(String mode) {
  return switch (mode.trim().toLowerCase()) {
    'fill' => _tvVideoSizeFill,
    '16:9' || 'wide' => _tvVideoSizeWide,
    'stretch' => _tvVideoSizeStretch,
    _ => _tvVideoSizeFit,
  };
}

String _nativeTvVideoSizeModeFor(String mode) {
  return switch (_normalizeTvVideoSizeMode(mode)) {
    _tvVideoSizeWide => '16:9',
    _tvVideoSizeFill => _tvVideoSizeFill,
    _tvVideoSizeStretch => _tvVideoSizeStretch,
    _ => _tvVideoSizeFit,
  };
}

String _tvVideoSizeLabel(String mode) {
  return switch (_normalizeTvVideoSizeMode(mode)) {
    _tvVideoSizeFill => 'Fill',
    _tvVideoSizeWide => '16:9',
    _tvVideoSizeStretch => 'Stretch',
    _ => 'Fit',
  };
}

class _TvPlaybackPageState extends State<_TvPlaybackPage>
    with WidgetsBindingObserver {
  static const Duration _seekStep = tvPlaybackSkipInterval;
  static const Duration _fastSeekStep = Duration(seconds: 1);
  static const Duration _controlsAutoHideDelay = Duration(seconds: 11);

  final FocusNode _playbackFocusNode = FocusNode(debugLabel: 'tv-playback');
  final FocusNode _backFocusNode = FocusNode(debugLabel: 'tv-playback-back');
  final FocusNode _nextEpisodeFocusNode = FocusNode(
    debugLabel: 'tv-playback-next-episode',
  );
  final FocusNode _skipBackFocusNode = FocusNode(
    debugLabel: 'tv-playback-skip-back',
  );
  final FocusNode _playFocusNode = FocusNode(debugLabel: 'tv-playback-play');
  final FocusNode _skipForwardFocusNode = FocusNode(
    debugLabel: 'tv-playback-skip-forward',
  );
  final FocusNode _episodesFocusNode = FocusNode(
    debugLabel: 'tv-playback-episodes',
  );
  final FocusNode _sourcesFocusNode = FocusNode(
    debugLabel: 'tv-playback-sources',
  );
  final FocusNode _settingsFocusNode = FocusNode(
    debugLabel: 'tv-playback-settings',
  );
  final FocusNode _skipSegmentFocusNode = FocusNode(
    debugLabel: 'tv-playback-skip-segment',
  );
  final FocusNode _lockFocusNode = FocusNode(debugLabel: 'tv-playback-lock');
  final FocusNode _progressFocusNode = FocusNode(
    debugLabel: 'tv-playback-progress',
  );
  final _api = _TvApi();
  final _TvPlaybackSkipSegmentClient _skipSegmentClient =
      const _TvPlaybackSkipSegmentClient();
  final _TvPlaybackFeedbackClient _feedbackClient =
      const _TvPlaybackFeedbackClient();
  final TvP2pPlaybackOwner _p2pPlaybackOwner = TvP2pPlaybackOwner(
    bridge: const MethodChannelTvP2pLocalStreamBridge(),
  );
  final TvP2pLifecycleGate _p2pLifecycleGate = TvP2pLifecycleGate();
  _TvNativePlaybackController? _controller;
  _TvNativePlaybackController? _stagedController;
  late List<_PlaybackSession> _sessions;
  final Set<String> _rejectedSessionKeysForRoute = <String>{};
  Timer? _hideControlsTimer;
  Timer? _feedbackTimer;
  Timer? _holdSeekDelayTimer;
  Timer? _holdSeekTimer;
  bool _controlsVisible = false;
  bool _locked = false;
  bool _switchingSource = false;
  bool _closingPlayback = false;
  bool _recoveringRuntimePlayback = false;
  bool _handlingPlaybackFallbackKey = false;
  bool _playbackDialogCloseInFlight = false;
  bool? _nativeHiddenHudCaptureActive;
  int _playbackDialogDepth = 0;
  NavigatorState? _activePlaybackDialogNavigator;
  DateTime _suppressPlaybackBackUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPlaybackDialogClosedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _loadingStatus = 'Preparing playback sources...';
  int _playbackGeneration = 0;
  int _startupAttemptGeneration = 0;
  late final bool _autoplayNextEpisode = widget.settings.nextEpisode;
  late bool _captionsEnabled;
  bool _autoNextQueued = false;
  int _holdSeekDirection = 0;
  double _playbackSpeed = 1.0;
  String _videoSize = _tvVideoSizeFit;
  int _season = 1;
  int _episode = 1;
  late int _sessionIndex;
  late int _subtitleIndex;
  late int _subtitleDelayMillis;
  int _subtitleLoadGeneration = 0;
  int _skipSegmentLoadGeneration = 0;
  bool _subtitlesLoading = false;
  bool _subtitlesLoaded = false;
  Future<void>? _subtitleLookupFuture;
  late List<_TvSubtitle> _subtitles;
  List<_TvSubtitleCue> _subtitleCues = const <_TvSubtitleCue>[];
  List<_TvPlaybackSkipSegmentTiming> _skipSegments =
      const <_TvPlaybackSkipSegmentTiming>[];
  Duration _skipSegmentLookupDuration = Duration.zero;
  double _lastDecodedAspectRatio = 16 / 9;
  late Duration _initialResumePosition;
  bool _initialResumePromptResolved = false;
  bool _initializedHudRevealed = false;
  bool _resumePromptVisible = false;
  int _lastProgressCallbackSecond = -1;
  int _lastProgressCallbackDurationSecond = -1;
  Duration _lastKnownPlaybackPosition = Duration.zero;
  Duration _lastKnownPlaybackDuration = Duration.zero;
  Duration _p2pLifecycleResumePosition = Duration.zero;
  bool _libVlcContinuousTsActive = false;
  Duration _libVlcContinuousTsTimelineOffset = Duration.zero;
  Duration _playbackDisplayTimelineOffset = Duration.zero;
  final TvPlaybackTimelineTransaction _timelineTransaction =
      TvPlaybackTimelineTransaction();
  String? _lastVerifiedSessionUrl;
  int _verifiedSessionMilestone = 0;
  Duration _verifiedSessionProofStartPosition = Duration.zero;
  DateTime? _verifiedSessionProofStartedAt;
  DateTime? _runtimeErrorFirstSeenAt;
  String? _runtimeErrorFirstDescription;
  Duration _runtimeErrorFirstPosition = Duration.zero;
  Timer? _runtimeErrorRecoveryTimer;
  DateTime? _runtimeErrorRecoverySuppressedUntil;
  Timer? _playbackCadenceTimer;
  DateTime? _lastCadenceSampleAt;
  Duration _lastCadencePosition = Duration.zero;
  Duration _lastCrediblePlaybackPosition = Duration.zero;
  Duration _credibleWatchedDuration = Duration.zero;
  int _playbackCadenceConsecutiveJumpEvents = 0;
  int _playbackCadenceHealthySamples = 0;
  bool _playbackCadenceClockUnstable = false;
  bool _recoveringFromPlaybackCadence = false;
  DateTime? _lastPlaybackCadenceDriftLogAt;
  int _lastPlaybackCadenceEvidenceSecond = -1;
  FocusNode? _lastPlaybackFocusNode;
  _TvPlaybackFeedback? _feedback;
  TvRemoteDebugSnapshot _remoteDebugSnapshot = const TvRemoteDebugSnapshot(
    currentSurfaceName: 'playback',
  );

  bool get _isLiveTvPlayback => _normalizeType(widget.item.type) == 'live';

  bool get _hasPlaybackDialogOpen => _playbackDialogDepth > 0;

  @override
  void initState() {
    super.initState();
    _sessions = widget.sessions;
    WidgetsBinding.instance.addObserver(this);
    _sessionIndex = _sessions.isEmpty
        ? 0
        : widget.initialSessionIndex.clamp(0, _sessions.length - 1).toInt();
    _season = widget.initialSeason;
    _episode = widget.initialEpisode;
    _credibleWatchedDuration =
        widget.initialResumeProgress?.credibleWatched ?? Duration.zero;
    _subtitles = widget.subtitles.toList(growable: false);
    _subtitleIndex = widget.initialSubtitleIndex;
    final preferredSubtitleId = widget.subtitleId?.trim();
    if (preferredSubtitleId != null && preferredSubtitleId.isNotEmpty) {
      _subtitleIndex = _subtitles.indexWhere(
        (subtitle) => subtitle.id == preferredSubtitleId,
      );
    }
    final canUseSubtitles = widget.settings.hasSubtitleSource;
    if (_subtitleIndex < 0 &&
        _subtitles.isNotEmpty &&
        !_isLiveTvPlayback &&
        widget.settings.subtitles &&
        canUseSubtitles) {
      _subtitleIndex = 0;
    }
    _subtitleDelayMillis =
        widget.settings.subtitleDelayMillis.clamp(-20000, 20000).toInt();
    _initialResumePosition = widget.initialResumePosition;
    _captionsEnabled = !_isLiveTvPlayback &&
        widget.settings.subtitles &&
        canUseSubtitles &&
        _subtitleIndex >= 0 &&
        _subtitleIndex < _subtitles.length;
    widget.lifecycleHarness?.openSeasonEpisodes =
        (season) async => await _showSeasonEpisodes(season) != null;
    widget.lifecycleHarness?.openEpisodesPanel = _showEpisodesPanel;
    _tvRemoteKeyChannel.setMethodCallHandler(_handleNativeRemoteKeyCall);
    HardwareKeyboard.instance.addHandler(_handlePlaybackFallbackKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _backFocusNode.requestFocus();
      if (widget.lifecycleHarness?.skipInitialPlayback == true) return;
      if (_sessions.isEmpty) {
        _closePlaybackUnavailable('Playback is unavailable right now.');
        return;
      }
      if (_subtitles.isNotEmpty) {
        unawaited(_loadSelectedSubtitleCues());
      }
      unawaited(_loadPlaybackSubtitles());
      unawaited(_startInitialPlayback());
    });
    for (final node in _playbackControlFocusNodes) {
      node.addListener(_syncLastPlaybackFocusNode);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (tvP2pPlaybackShouldSuspendForLifecycle(state)) {
      unawaited(_suspendP2pForLifecycle());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeP2pAfterLifecycle());
    }
  }

  Future<void> _suspendP2pForLifecycle() async {
    final closingGeneration = _startupAttemptGeneration;
    final controller = _controller;
    _p2pLifecycleResumePosition = _currentProgress().position;
    try {
      await _p2pLifecycleGate.suspend(
        hasActiveTransport: _p2pPlaybackOwner.hasActiveTransport,
        pausePlayback: () async {
          if (controller != null && controller.value.isPlaying) {
            await controller.pause();
          }
        },
        closeTransport: () => _p2pPlaybackOwner.closeThrough(closingGeneration),
      );
    } catch (_) {
      debugPrint('Juicr TV P2P lifecycle suspension did not settle cleanly');
    }
  }

  Future<void> _resumeP2pAfterLifecycle() async {
    if (!mounted || _closingPlayback || _switchingSource) return;
    await _p2pLifecycleGate.resume(
      reopenPlayback: () => _openSession(
        _sessionIndex,
        feedbackLabel: 'Resume playback',
        maxCandidateCount: 1,
        maxOpenDuration: const Duration(seconds: 45),
        resumePosition: _p2pLifecycleResumePosition,
        restoreOldOnFailure: false,
        allowFreshFallback: false,
      ),
    );
  }

  @override
  void dispose() {
    debugPrint('Juicr TV playback page dispose');
    widget.lifecycleHarness?.openSeasonEpisodes = null;
    widget.lifecycleHarness?.openEpisodesPanel = null;
    WidgetsBinding.instance.removeObserver(this);
    _playbackGeneration++;
    if (widget.lifecycleHarness?.skipInitialPlayback != true) {
      unawaited(_p2pPlaybackOwner.closeThrough(_startupAttemptGeneration));
    }
    _hideControlsTimer?.cancel();
    _feedbackTimer?.cancel();
    _runtimeErrorRecoveryTimer?.cancel();
    _stopPlaybackCadenceTimer();
    _stopHoldSeek();
    for (final node in _playbackControlFocusNodes) {
      node.removeListener(_syncLastPlaybackFocusNode);
    }
    _tvRemoteKeyChannel.setMethodCallHandler(null);
    _nativeHiddenHudCaptureActive = false;
    unawaited(
      _tvRemoteKeyChannel.invokeMethod<void>(
        'setHiddenHudCapture',
        const <String, Object?>{'active': false},
      ),
    );
    HardwareKeyboard.instance.removeHandler(_handlePlaybackFallbackKey);
    _playbackFocusNode.dispose();
    _backFocusNode.dispose();
    _nextEpisodeFocusNode.dispose();
    _skipBackFocusNode.dispose();
    _playFocusNode.dispose();
    _skipForwardFocusNode.dispose();
    _episodesFocusNode.dispose();
    _sourcesFocusNode.dispose();
    _settingsFocusNode.dispose();
    _skipSegmentFocusNode.dispose();
    _lockFocusNode.dispose();
    _progressFocusNode.dispose();
    _controller?.removeListener(_handlePlaybackProgressTick);
    _controller?.dispose();
    _stagedController?.dispose();
    super.dispose();
  }

  List<FocusNode> get _playbackControlFocusNodes => [
        _backFocusNode,
        _nextEpisodeFocusNode,
        _skipBackFocusNode,
        _playFocusNode,
        _skipForwardFocusNode,
        _skipSegmentFocusNode,
        _episodesFocusNode,
        _sourcesFocusNode,
        _settingsFocusNode,
        _lockFocusNode,
        _progressFocusNode,
      ];

  void _syncLastPlaybackFocusNode() {
    for (final node in _playbackControlFocusNodes) {
      if (node.hasFocus) {
        _lastPlaybackFocusNode = node;
        return;
      }
    }
  }

  bool _handlePlaybackFallbackKey(KeyEvent event) {
    if (_handlingPlaybackFallbackKey || !mounted || _switchingSource) {
      return false;
    }
    if (event is KeyUpEvent) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final bucket = tvRemoteInputMapper.bucketForEvent(event);
    if (bucket == null) return false;
    final command = tvPlaybackRemoteActionResolver.commandFor(bucket);
    if (_hasPlaybackDialogOpen) {
      if (command == TvPlaybackRemoteCommand.close) {
        unawaited(_closeTopPlaybackDialog('fallback-key-close'));
        return true;
      }
      return !tvPlaybackDialogKeyOwnership.shouldPassThrough(command);
    }
    if (command == TvPlaybackRemoteCommand.close) return false;

    final primaryFocus = FocusManager.instance.primaryFocus;
    final playbackHasFocus = primaryFocus == _playbackFocusNode ||
        _playbackControlFocusNodes.any((node) => node.hasFocus);
    if (_controlsVisible && playbackHasFocus) return false;

    _handlingPlaybackFallbackKey = true;
    try {
      if (_locked || !_controlsVisible) {
        _showControls(focusPrimary: true);
        return true;
      }
      _playbackFocusNode.requestFocus();
      return false;
    } finally {
      _handlingPlaybackFallbackKey = false;
    }
  }

  Future<void> _handleNativeRemoteKeyCall(MethodCall call) async {
    if (call.method != 'key' || !mounted) return;
    final args = call.arguments;
    if (args is! Map) return;
    final keyCode = args['keyCode'];
    final action = args['action'];
    final repeatCount = args['repeatCount'];
    if (keyCode is! int || action is! int) return;
    if (action == 1) return;
    final bucket = _nativeRemoteBucketForKeyCode(keyCode);
    if (bucket == null) return;
    final isRepeat = repeatCount is int && repeatCount > 0;
    _handleNativeRemoteBucket(bucket, isRepeat: isRepeat);
  }

  TvRemoteActionBucket? _nativeRemoteBucketForKeyCode(int keyCode) {
    return switch (keyCode) {
      19 => TvRemoteActionBucket.dpadUp,
      20 => TvRemoteActionBucket.dpadDown,
      21 => TvRemoteActionBucket.dpadLeft,
      22 => TvRemoteActionBucket.dpadRight,
      23 || 66 || 160 || 62 => TvRemoteActionBucket.select,
      4 || 111 => TvRemoteActionBucket.back,
      85 => TvRemoteActionBucket.mediaPlayPause,
      126 => TvRemoteActionBucket.mediaPlay,
      127 => TvRemoteActionBucket.mediaPause,
      86 => TvRemoteActionBucket.mediaStop,
      90 => TvRemoteActionBucket.seekNext,
      89 => TvRemoteActionBucket.seekPrevious,
      84 => TvRemoteActionBucket.search,
      82 => TvRemoteActionBucket.menu,
      165 => TvRemoteActionBucket.info,
      175 => TvRemoteActionBucket.captions,
      176 => TvRemoteActionBucket.settings,
      92 => TvRemoteActionBucket.pageUp,
      93 => TvRemoteActionBucket.pageDown,
      166 => TvRemoteActionBucket.channelUp,
      167 => TvRemoteActionBucket.channelDown,
      _ => null,
    };
  }

  void _handleNativeRemoteBucket(
    TvRemoteActionBucket bucket, {
    required bool isRepeat,
  }) {
    if (_switchingSource) return;
    final command = tvPlaybackRemoteActionResolver.commandFor(bucket);
    if (_hasPlaybackDialogOpen) {
      if (command == TvPlaybackRemoteCommand.close) {
        unawaited(_closeTopPlaybackDialog('native-close'));
      } else {
        debugPrint(
          'Juicr TV native remote ignored while playback dialog open '
          'bucket=$bucket depth=$_playbackDialogDepth',
        );
      }
      return;
    }
    if (command == TvPlaybackRemoteCommand.close) {
      if (_shouldSuppressPlaybackBack()) return;
      unawaited(_closePlayback());
      return;
    }
    if (command == TvPlaybackRemoteCommand.openSettings) {
      _showControls();
      _requestHudFocusAfterBuild(_settingsFocusNode);
      unawaited(_showSettingsPanel());
      return;
    }
    if (command == TvPlaybackRemoteCommand.openSources) {
      _showControls();
      _requestHudFocusAfterBuild(_sourcesFocusNode);
      unawaited(_showSourcesPanel());
      return;
    }
    if (_locked) {
      _showControls();
      if (tvNativeLockedRemoteShouldUnlock(
        bucket: bucket,
        unlockFocused: FocusManager.instance.primaryFocus == _lockFocusNode,
        isRepeat: isRepeat,
      )) {
        _toggleLock();
      } else {
        _requestHudFocusAfterBuild(_lockFocusNode);
      }
      return;
    }
    if (command != null &&
        tvNativePlaybackCommandExecutesImmediately(command)) {
      _showControlsForRemoteBucket(bucket);
      if (isRepeat) return;
      switch (command) {
        case TvPlaybackRemoteCommand.togglePlay:
          unawaited(_togglePlay());
        case TvPlaybackRemoteCommand.play:
          unawaited(_playOnly());
        case TvPlaybackRemoteCommand.pause:
          unawaited(_pauseOnly());
        case TvPlaybackRemoteCommand.stop:
          unawaited(_closePlayback());
        case TvPlaybackRemoteCommand.seekForward:
          if (!_isLiveTvPlayback) {
            unawaited(
              _skipBy(
                tvPlaybackSkipOffsetForCommand(command)!,
                direction: 1,
              ),
            );
          }
        case TvPlaybackRemoteCommand.seekBack:
          if (!_isLiveTvPlayback) {
            unawaited(
              _skipBy(
                tvPlaybackSkipOffsetForCommand(
                  TvPlaybackRemoteCommand.seekBack,
                )!,
                direction: -1,
              ),
            );
          }
        case TvPlaybackRemoteCommand.openSources ||
              TvPlaybackRemoteCommand.openSettings ||
              TvPlaybackRemoteCommand.showControls ||
              TvPlaybackRemoteCommand.close:
          break;
      }
      return;
    }
    final playbackHasFocus =
        FocusManager.instance.primaryFocus == _playbackFocusNode ||
            _playbackControlFocusNodes.any((node) => node.hasFocus);
    if (_controlsVisible) _refreshControlsAutoHideTimer();
    if (_controlsVisible && playbackHasFocus) return;

    if (!_controlsVisible || _locked) {
      _showControlsForRemoteBucket(bucket);
      return;
    }
    _playbackFocusNode.requestFocus();
    if (isRepeat) return;
    if (bucket == TvRemoteActionBucket.select) {
      _activateFocusedPlaybackControl();
    }
  }

  bool _isPlaybackGenerationActive(int generation) {
    return mounted && generation == _playbackGeneration;
  }

  bool _isPlaybackStartupAttemptActive(int generation, int startupAttempt) {
    return _isPlaybackGenerationActive(generation) &&
        startupAttempt == _startupAttemptGeneration;
  }

  void _updatePlaybackLoadingStatus(String status) {
    if (!mounted || _loadingStatus == status) return;
    setState(() => _loadingStatus = status);
  }

  String _sourceLoadingStatus(int index) {
    final total = _sessions.length;
    if (total <= 1) return 'Preparing playback source...';
    return 'Preparing source ${index + 1}/$total...';
  }

  String _engineLoadingStatus(int index, int total) {
    if (total <= 1) return 'Opening playback...';
    return 'Trying playback engine ${index + 1}/$total...';
  }

  void _suppressPlaybackBackBriefly() {
    _suppressPlaybackBackUntil = DateTime.now().add(
      const Duration(seconds: 2),
    );
  }

  bool _shouldSuppressPlaybackBack() {
    if (DateTime.now().isAfter(_suppressPlaybackBackUntil)) return false;
    _showControls();
    return true;
  }

  bool _shouldSuppressPlaybackBackAfterDialog() {
    final elapsed = DateTime.now().difference(_lastPlaybackDialogClosedAt);
    if (elapsed >= Duration.zero &&
        elapsed < const Duration(milliseconds: 900)) {
      _suppressPlaybackBackBriefly();
      _showControls();
      debugPrint(
        'Juicr TV playback route back suppressed after dialog close '
        'elapsedMs=${elapsed.inMilliseconds}',
      );
      return true;
    }
    return false;
  }

  bool _beginPlaybackDialogClose(String source) {
    if (!_hasPlaybackDialogOpen || !mounted) return false;
    if (_playbackDialogCloseInFlight) {
      debugPrint(
        'Juicr TV playback dialog close ignored source=$source '
        'depth=$_playbackDialogDepth inFlight=1',
      );
      _suppressPlaybackBackBriefly();
      return false;
    }
    _playbackDialogCloseInFlight = true;
    _suppressPlaybackBackBriefly();
    debugPrint(
      'Juicr TV playback dialog close requested source=$source '
      'depth=$_playbackDialogDepth',
    );
    return true;
  }

  void _popPlaybackDialog<T>(
    NavigatorState navigator,
    String source, [
    T? result,
  ]) {
    if (!_beginPlaybackDialogClose(source)) return;
    navigator.pop<T>(result);
  }

  NavigatorState _playbackDialogNavigator(BuildContext dialogContext) {
    return _activePlaybackDialogNavigator ?? Navigator.of(dialogContext);
  }

  Future<void> _closeTopPlaybackDialog(String source) async {
    if (!_beginPlaybackDialogClose(source)) return;
    final navigator = _activePlaybackDialogNavigator ?? Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      _playbackDialogCloseInFlight = false;
    }
  }

  bool _shouldIgnoreNestedPlaybackDialogPop(String source) {
    final elapsed = DateTime.now().difference(_lastPlaybackDialogClosedAt);
    final ignore = _hasPlaybackDialogOpen &&
        elapsed >= Duration.zero &&
        elapsed < const Duration(milliseconds: 420);
    if (ignore) {
      debugPrint(
        'Juicr TV nested playback dialog pop ignored source=$source depth=$_playbackDialogDepth',
      );
    }
    return ignore;
  }

  Future<T?> _showPlaybackDialog<T>({
    required WidgetBuilder builder,
    bool? requestFocus,
  }) async {
    if (_nativeHiddenHudCaptureActive == true) {
      _nativeHiddenHudCaptureActive = false;
      unawaited(
        _tvRemoteKeyChannel.invokeMethod<void>(
          'setHiddenHudCapture',
          const <String, Object?>{'active': false},
        ),
      );
    }
    _playbackDialogDepth += 1;
    debugPrint('Juicr TV playback dialog open depth=$_playbackDialogDepth');
    try {
      return await _showTvDialog<T>(
        context: context,
        builder: (dialogContext) {
          _activePlaybackDialogNavigator = Navigator.of(dialogContext);
          return Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
              SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
              SingleActivator(LogicalKeyboardKey.browserBack): DismissIntent(),
              SingleActivator(LogicalKeyboardKey.navigateOut): DismissIntent(),
              SingleActivator(LogicalKeyboardKey.gameButtonB): DismissIntent(),
            },
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    _popPlaybackDialog(
                      _playbackDialogNavigator(dialogContext),
                      'dialog-dismiss',
                    );
                    return null;
                  },
                ),
              },
              child: builder(dialogContext),
            ),
          );
        },
        requestFocus: requestFocus ?? true,
        useRootNavigator: false,
      );
    } finally {
      _lastPlaybackDialogClosedAt = DateTime.now();
      _playbackDialogDepth = (_playbackDialogDepth - 1).clamp(0, 999).toInt();
      _playbackDialogCloseInFlight = false;
      if (_playbackDialogDepth == 0) {
        _activePlaybackDialogNavigator = null;
      }
      debugPrint('Juicr TV playback dialog close depth=$_playbackDialogDepth');
      _suppressPlaybackBackBriefly();
      if (tvPlaybackDialogCloseNeedsHiddenHudRefresh(
        remainingDialogDepth: _playbackDialogDepth,
      )) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncNativeHiddenHudCapture(
            initialized: _controller?.value.isInitialized ?? false,
          );
        });
      }
    }
  }

  Future<void> _settlePlaybackDialogFocusBeforeDispose(
    Iterable<FocusNode> nodes, {
    FocusNode? restoreFocusNode,
  }) async {
    for (final node in nodes) {
      if (node.hasFocus) {
        node.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
      }
    }
    if (mounted &&
        restoreFocusNode != null &&
        restoreFocusNode.canRequestFocus) {
      restoreFocusNode.requestFocus();
    }
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _startInitialPlayback() async {
    if (_sessions.isEmpty) {
      _closePlaybackUnavailable('Playback is unavailable right now.');
      return;
    }
    debugPrint(
      'Juicr TV initial playback session '
      'index=${_sessionIndex + 1}/${_sessions.length} '
      '${_safePlaybackSessionFingerprint(_sessions[_sessionIndex])}',
    );
    _lastKnownPlaybackPosition = Duration.zero;
    _lastKnownPlaybackDuration =
        widget.initialResumeProgress?.duration ?? Duration.zero;
    _playbackDisplayTimelineOffset = Duration.zero;
    final progress = widget.initialResumeProgress;
    debugPrint(
      'Juicr TV initial resume input '
      'present=${progress != null} position=${progress?.position.inSeconds ?? 0}s',
    );
    if (progress != null && progress.position > Duration.zero) {
      _initialResumePosition = Duration.zero;
      await _openSession(
        _sessionIndex,
        feedbackLabel: 'Ready',
        maxCandidateCount: 4,
        maxOpenDuration: _sessions.any(
          (session) => session.p2pDescriptor != null,
        )
            ? tvP2pRouteStartupBudget()
            : const Duration(seconds: 60),
      );
      if (!mounted || _controller == null) return;
      await _resolveInitialResumeChoiceAfterReady(progress);
      return;
    }
    _initialResumePosition = widget.initialResumePosition;
    await _openSession(
      _sessionIndex,
      feedbackLabel: 'Ready',
      maxCandidateCount: 4,
      maxOpenDuration: _sessions.any(
        (session) => session.p2pDescriptor != null,
      )
          ? tvP2pRouteStartupBudget()
          : const Duration(seconds: 60),
    );
  }

  Future<void> _resolveInitialResumeChoiceAfterReady(
    _TvPlaybackProgress progress,
  ) async {
    if (_initialResumePromptResolved) return;
    _initialResumePromptResolved = true;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final pauseSettled = await tvSettleControllerPauseForResume(
      pause: controller.pause,
      isCurrent: () => mounted && identical(_controller, controller),
      isInitialized: () => controller.value.isInitialized,
      isPlaying: () => controller.value.isPlaying,
      onRetry: (attempt) {
        debugPrint(
          'Juicr TV resume prompt pause retry attempt=$attempt '
          'engine=${controller.engine.name}',
        );
      },
    );
    if (!mounted || !identical(_controller, controller)) return;
    final pausedValue = controller.value;
    if (!pauseSettled ||
        !tvPlaybackCanPublishResumePrompt(
          initialized: pausedValue.isInitialized,
          playing: pausedValue.isPlaying,
        )) {
      debugPrint(
        'Juicr TV resume prompt unavailable reason=pause_not_settled '
        'engine=${controller.engine.name}',
      );
      await _closePlayback();
      return;
    }
    _hideControlsTimer?.cancel();
    setState(() {
      _resumePromptVisible = true;
      _controlsVisible = false;
      _feedback = null;
    });
    final continuePlayback = await _showPlaybackDialog<bool>(
      builder: (context) => _TvResumePlaybackDialog(progress: progress),
      requestFocus: true,
    );
    if (!mounted) return;
    setState(() => _resumePromptVisible = false);
    if (continuePlayback == null) {
      await _closePlayback();
      return;
    }
    if (continuePlayback &&
        _canSeekToResumePosition(
          progress.position,
          progress.duration > Duration.zero
              ? progress.duration
              : controller.value.duration,
        )) {
      debugPrint(
        'Juicr TV resume prompt accepted '
        'position=${progress.position.inSeconds}s '
        'duration=${(progress.duration > Duration.zero ? progress.duration : controller.value.duration).inSeconds}s',
      );
      await _seekControllerToPlaybackPosition(
        controller,
        progress.position,
        reason: 'resume_prompt',
      );
      final resumedController = _controller;
      if (!mounted || resumedController == null) return;
      _lastKnownPlaybackPosition = progress.position;
      _resetPlaybackCadenceState(crediblePosition: progress.position);
      final resumeDuration =
          _absolutePlaybackDuration(resumedController, resumedController.value);
      if (resumeDuration > Duration.zero) {
        _lastKnownPlaybackDuration = resumeDuration;
      }
    } else if (!continuePlayback) {
      debugPrint('Juicr TV resume prompt declined action=start_over');
      final resetProgress = widget.onProgressReset;
      if (resetProgress != null) {
        await tvResetProgressForExplicitStartOver(
          season: _season,
          episode: _episode,
          reset: resetProgress,
        );
      }
      if (!mounted || !identical(_controller, controller)) return;
      await _seekControllerToPlaybackPosition(
        controller,
        Duration.zero,
        reason: 'resume_prompt_start_over',
      );
      _lastKnownPlaybackPosition = Duration.zero;
      _playbackDisplayTimelineOffset = Duration.zero;
      _libVlcContinuousTsTimelineOffset = Duration.zero;
      _resetPlaybackCadenceState(crediblePosition: Duration.zero);
    }
    if (!mounted) return;
    await tvResumeCurrentControllerAfterSeek<_TvNativePlaybackController>(
      currentController: _controller,
      play: (currentController) => currentController.play(),
    );
    _showControls(focusPrimary: true);
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final beforeValue = controller.value;
    final beforePosition = _absolutePlaybackPosition(controller, beforeValue);
    final action = beforeValue.isPlaying
        ? TvPlaybackTransportAction.pause
        : TvPlaybackTransportAction.resume;
    if (beforeValue.isPlaying) {
      await controller.pause();
    } else {
      await tvSettleControllerPlay(
        play: controller.play,
        isCurrent: () => mounted && identical(_controller, controller),
        isInitialized: () => controller.value.isInitialized,
        isPlaying: () => controller.value.isPlaying,
      );
    }
    final afterController = _controller;
    if (identical(afterController, controller)) {
      final afterValue = await tvSettlePlaybackTransportState<_TvPlaybackValue>(
        read: () => controller.value,
        isSettled: (value) => action == TvPlaybackTransportAction.pause
            ? !value.isPlaying
            : value.isPlaying,
        timeout: tvPlaybackTransportSettleTimeout(
          action: action,
          engine: controller.engine.name,
        ),
      );
      debugPrint(
        tvPlaybackTransportOutcomeLine(
          action: action,
          engine: controller.engine.name,
          beforePosition: beforePosition,
          afterPosition: _absolutePlaybackPosition(controller, afterValue),
          beforePlaying: beforeValue.isPlaying,
          afterPlaying: afterValue.isPlaying,
        ),
      );
    }
    _showControls();
    if (mounted) setState(() {});
  }

  Future<void> _playOnly() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.play();
    _showControls();
    if (mounted) setState(() {});
  }

  Future<void> _pauseOnly() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.pause();
    _showControls();
    if (mounted) setState(() {});
  }

  void _replaceController(_TvNativePlaybackController? controller) {
    final previous = _controller;
    if (identical(previous, controller)) return;
    debugPrint(
      'Juicr TV playback controller replace '
      'from=${previous?.engine.name ?? 'none'} to=${controller?.engine.name ?? 'none'}',
    );
    previous?.removeListener(_handlePlaybackProgressTick);
    _controller = controller;
    _lastProgressCallbackSecond = -1;
    _lastProgressCallbackDurationSecond = -1;
    _verifiedSessionProofStartPosition = Duration.zero;
    _verifiedSessionProofStartedAt = null;
    _resetPlaybackCadenceState(
      crediblePosition:
          controller == null ? Duration.zero : _lastKnownPlaybackPosition,
    );
    if (controller == null) {
      _stopPlaybackCadenceTimer();
    } else {
      _startPlaybackCadenceTimer();
    }
    if (controller?.engine != _TvPlaybackEngine.libvlc) {
      _libVlcContinuousTsActive = false;
      _libVlcContinuousTsTimelineOffset = Duration.zero;
    }
    _resetRuntimePlaybackErrorDebounce();
    controller?.addListener(_handlePlaybackProgressTick);
  }

  void _replaceStagedController(_TvNativePlaybackController? controller) {
    final previous = _stagedController;
    if (identical(previous, controller)) return;
    debugPrint(
      'Juicr TV staged playback controller replace '
      'from=${previous?.engine.name ?? 'none'} '
      'to=${controller?.engine.name ?? 'none'}',
    );
    _stagedController = controller;
  }

  void _resetRuntimePlaybackErrorDebounce() {
    _runtimeErrorRecoveryTimer?.cancel();
    _runtimeErrorRecoveryTimer = null;
    _runtimeErrorFirstSeenAt = null;
    _runtimeErrorFirstDescription = null;
    _runtimeErrorFirstPosition = Duration.zero;
  }

  bool _canSeekToResumePosition(Duration position, Duration duration) {
    if (position <= Duration.zero) return false;
    if (duration <= Duration.zero) return true;
    final latestResume = duration - const Duration(seconds: 20);
    if (latestResume <= Duration.zero) return false;
    return position < latestResume;
  }

  void _maybeReportVerifiedSession(
    _TvNativePlaybackController controller,
    _TvPlaybackValue value,
  ) {
    final callback = widget.onVerifiedSession;
    if (_sessionIndex < 0 ||
        _sessionIndex >= _sessions.length ||
        !value.isInitialized ||
        !value.isPlaying ||
        value.errorDescription.isNotEmpty ||
        value.size == Size.zero ||
        value.audioSinkErrorCount > 0 ||
        !_hasSanePlaybackGeometry(value) ||
        _playbackCadenceClockUnstable) {
      return;
    }
    final session = _sessions[_sessionIndex];
    if (session.mediaUrl.startsWith('http://127.0.0.1') ||
        session.mediaUrl.startsWith('http://localhost')) {
      return;
    }
    final proofPosition = _isLiveTvPlayback
        ? const Duration(seconds: 6)
        : const Duration(seconds: 15);
    final requiredWatched = _isLiveTvPlayback
        ? const Duration(seconds: 6)
        : const Duration(seconds: 10);
    final proofStartedAt = _verifiedSessionProofStartedAt;
    final jumpedBackward = value.position < _verifiedSessionProofStartPosition;
    final jumpedForward = value.position - _verifiedSessionProofStartPosition >
        const Duration(seconds: 30);
    if (proofStartedAt == null || jumpedBackward || jumpedForward) {
      _verifiedSessionProofStartedAt = DateTime.now();
      _verifiedSessionProofStartPosition = value.position;
      return;
    }
    if (value.position < proofPosition) return;
    if (value.position - _verifiedSessionProofStartPosition < requiredWatched) {
      return;
    }
    if (!_isLiveTvPlayback && value.duration <= Duration.zero) return;
    final milestone = value.position >= const Duration(minutes: 2) ? 2 : 1;
    if (_lastVerifiedSessionUrl == session.mediaUrl &&
        _verifiedSessionMilestone >= milestone) {
      return;
    }
    _lastVerifiedSessionUrl = session.mediaUrl;
    _verifiedSessionMilestone = milestone;
    unawaited(
      _sendPlaybackFeedback(
        event: 'verified',
        session: session,
        controller: controller,
        value: value,
      ),
    );
    callback?.call(session, controller.engine.name);
  }

  void _reportRejectedSession(_PlaybackSession session) {
    _rejectedSessionKeysForRoute.add(
      _playbackSessionRouteRejectionKey(session),
    );
    widget.onRejectedSession?.call(session);
    unawaited(
      _sendPlaybackFeedback(
        event: 'open_failed',
        session: session,
        startupMs: 0,
      ),
    );
  }

  Future<void> _sendPlaybackFeedback({
    required String event,
    required _PlaybackSession session,
    _TvNativePlaybackController? controller,
    _TvPlaybackValue? value,
    int? startupMs,
  }) async {
    final feedbackValue = value ?? controller?.value;
    final progress = _currentProgress();
    await _feedbackClient.send(
      providerId: session.providerId,
      event: event,
      engine: controller?.engine.name ?? '',
      mediaType: _feedbackMediaType(),
      quality: session.quality,
      sourceType: session.sourceType,
      sourceClass: session.sourceClass,
      positionSeconds: (controller != null && feedbackValue != null
              ? _stablePlaybackPosition(
                  _absolutePlaybackPosition(controller, feedbackValue),
                )
              : progress.position)
          .inSeconds,
      durationSeconds: (controller != null && feedbackValue != null
              ? _absolutePlaybackDuration(controller, feedbackValue)
              : progress.duration)
          .inSeconds,
      sourceCount: _sessions.length,
      startupMs: startupMs,
    );
  }

  String _feedbackMediaType() {
    final type = _normalizeType(widget.item.type);
    return switch (type) {
      'series' => 'series',
      'animation' => 'animation',
      'live' || 'live_tv' || 'livetv' || 'channel' => 'live_tv',
      _ => 'movie',
    };
  }

  void _handlePlaybackProgressTick() {
    final controller = _controller;
    if (controller == null || _closingPlayback) return;
    final value = controller.value;
    if (value.errorDescription.isNotEmpty) {
      _handleRuntimePlaybackErrorObserved(controller, value);
      return;
    }
    _runtimeErrorFirstSeenAt = null;
    _runtimeErrorFirstDescription = null;
    _runtimeErrorFirstPosition = Duration.zero;
    _runtimeErrorRecoveryTimer?.cancel();
    _runtimeErrorRecoveryTimer = null;
    if (!value.isInitialized) return;
    final rawPosition = _absolutePlaybackPosition(controller, value);
    final stablePosition = _stablePlaybackPosition(rawPosition);
    if (stablePosition > Duration.zero) {
      _lastKnownPlaybackPosition = stablePosition;
    }
    final absoluteDuration = _absolutePlaybackDuration(controller, value);
    if (absoluteDuration > Duration.zero) {
      _lastKnownPlaybackDuration = absoluteDuration;
    }
    _maybeReportVerifiedSession(controller, value);
    if (_shouldRecoverFromNativeClockSignal(controller, value)) {
      _handleNativeClockSignalObserved(controller, value);
    }
    if (value.duration > Duration.zero) {
      _maybeLoadSkipSegments(value.duration);
    }
    if (!tvPlaybackProgressCanPublish(
      controllerIsCurrent: identical(controller, _controller),
      switchingSource: _switchingSource,
    )) {
      return;
    }
    final callback = widget.onProgress;
    if (callback == null) return;
    if (!value.isPlaying && !value.isEnded) return;
    if (stablePosition <= Duration.zero) return;

    final positionSecond = stablePosition.inSeconds;
    final durationSecond = absoluteDuration.inSeconds;
    final progressChangedEnough = _lastProgressCallbackSecond < 0 ||
        positionSecond - _lastProgressCallbackSecond >= 5 ||
        value.isEnded;
    final durationChanged = durationSecond > 0 &&
        durationSecond != _lastProgressCallbackDurationSecond;
    if (!progressChangedEnough && !durationChanged) return;

    _lastProgressCallbackSecond = positionSecond;
    _lastProgressCallbackDurationSecond = durationSecond;
    callback(
      _season,
      _episode,
      _TvPlaybackProgress(
        position: stablePosition,
        duration: absoluteDuration,
        credibleWatched: _credibleWatchedDuration,
      ),
    );
  }

  void _startPlaybackCadenceTimer() {
    _playbackCadenceTimer?.cancel();
    _playbackCadenceTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _samplePlaybackCadence(),
    );
  }

  void _stopPlaybackCadenceTimer() {
    _playbackCadenceTimer?.cancel();
    _playbackCadenceTimer = null;
    _lastCadenceSampleAt = null;
    _lastCadencePosition = Duration.zero;
  }

  void _resetPlaybackCadenceState({Duration? crediblePosition}) {
    _lastCadenceSampleAt = null;
    _lastCadencePosition = Duration.zero;
    _lastCrediblePlaybackPosition = crediblePosition ?? Duration.zero;
    _playbackCadenceConsecutiveJumpEvents = 0;
    _playbackCadenceHealthySamples = 0;
    _playbackCadenceClockUnstable = false;
    _lastPlaybackCadenceDriftLogAt = null;
    _lastPlaybackCadenceEvidenceSecond = -1;
  }

  Duration _stablePlaybackPosition(Duration observedPosition) {
    if (_playbackCadenceClockUnstable &&
        _lastCrediblePlaybackPosition > Duration.zero) {
      return _lastCrediblePlaybackPosition;
    }
    return observedPosition;
  }

  bool _hasSanePlaybackGeometry(_TvPlaybackValue value) {
    if (value.size == Size.zero) return false;
    final aspect = value.aspectRatio;
    if (!aspect.isFinite || aspect <= 0.4 || aspect >= 3.2) return false;
    if (value.size.width <= 0 || value.size.height <= 0) return false;
    return true;
  }

  Duration? _expectedRuntimeDuration() {
    final runtime = widget.item.runtime?.trim();
    if (runtime == null || runtime.isEmpty) return null;
    final clock = _parseTvSubtitleTime(runtime);
    if (clock != null) return clock;
    final lower = runtime.toLowerCase();
    final hours = RegExp(r'(\d+)\s*h').firstMatch(lower);
    final minutes = RegExp(r'(\d+)\s*m').firstMatch(lower);
    final hourValue = hours == null ? 0 : int.tryParse(hours.group(1)!) ?? 0;
    final minuteValue =
        minutes == null ? 0 : int.tryParse(minutes.group(1)!) ?? 0;
    if (hourValue > 0 || minuteValue > 0) {
      return Duration(hours: hourValue, minutes: minuteValue);
    }
    final bareMinutes = RegExp(r'\b(\d{2,3})\b').firstMatch(runtime);
    final parsedMinutes =
        bareMinutes == null ? null : int.tryParse(bareMinutes.group(1)!);
    if (parsedMinutes != null && parsedMinutes > 0) {
      return Duration(minutes: parsedMinutes);
    }
    return null;
  }

  bool _shouldRejectShortVodPlaceholder(_TvPlaybackValue value) {
    if (_isLiveTvPlayback || value.duration <= Duration.zero) return false;
    final type = widget.item.type.trim().toLowerCase();
    final isLongForm = type == 'movie' ||
        type == 'series' ||
        type == 'animation' ||
        type == 'anime';
    if (!isLongForm) return false;
    final expected = _expectedRuntimeDuration();
    if (expected != null && expected >= const Duration(minutes: 20)) {
      return value.duration < expected * 0.55;
    }
    return value.duration < const Duration(minutes: 12);
  }

  bool _shouldRecoverFromNativeClockSignal(
    _TvNativePlaybackController controller,
    _TvPlaybackValue value,
  ) {
    if (controller.engine != _TvPlaybackEngine.media3) return false;
    if (value.audioSinkErrorCount <= 0) return false;
    if (!value.isInitialized || !value.isPlaying || value.isBuffering) {
      return false;
    }
    return true;
  }

  void _handleNativeClockSignalObserved(
    _TvNativePlaybackController controller,
    _TvPlaybackValue value,
  ) {
    if (_recoveringFromPlaybackCadence ||
        _recoveringRuntimePlayback ||
        _switchingSource ||
        _closingPlayback) {
      return;
    }
    final anchor = _stablePlaybackPosition(
      _absolutePlaybackPosition(controller, value),
    );
    debugPrint(
      'Juicr TV playback native clock drift observed '
      'engine=${controller.engine.name} '
      'audioSinkErrors=${value.audioSinkErrorCount} '
      'position=${anchor.inSeconds}s '
      'action=try_next_source',
    );
    _playbackCadenceClockUnstable = true;
    if (_lastCrediblePlaybackPosition <= Duration.zero &&
        anchor > Duration.zero) {
      _lastCrediblePlaybackPosition = anchor;
    }
    unawaited(
      _recoverFromPlaybackCadenceDrift(
        controller,
        _lastCrediblePlaybackPosition > Duration.zero
            ? _lastCrediblePlaybackPosition
            : anchor,
        observedPosition: anchor,
      ),
    );
  }

  void _samplePlaybackCadence() {
    final controller = _controller;
    if (controller == null ||
        _closingPlayback ||
        _switchingSource ||
        _hasPlaybackDialogOpen ||
        _recoveringRuntimePlayback ||
        _recoveringFromPlaybackCadence) {
      return;
    }
    final value = controller.value;
    if (!value.isInitialized ||
        !value.isPlaying ||
        value.isBuffering ||
        value.isEnded ||
        value.errorDescription.isNotEmpty) {
      return;
    }
    final now = DateTime.now();
    final position = _absolutePlaybackPosition(controller, value);
    if (position <= Duration.zero) return;
    final lastSampleAt = _lastCadenceSampleAt;
    if (lastSampleAt == null || _lastCadencePosition <= Duration.zero) {
      _lastCadenceSampleAt = now;
      _lastCadencePosition = position;
      _lastCrediblePlaybackPosition = position;
      return;
    }
    final wallDeltaMs = now.difference(lastSampleAt).inMilliseconds;
    if (wallDeltaMs <= 0) return;
    final playbackDeltaMs =
        position.inMilliseconds - _lastCadencePosition.inMilliseconds;
    final maxForwardMs = wallDeltaMs * 4 + 2200;
    final jumpedBackward = playbackDeltaMs < -2200;
    final jumpedForward = playbackDeltaMs > maxForwardMs;
    if (jumpedBackward || jumpedForward) {
      _playbackCadenceConsecutiveJumpEvents += 1;
      _playbackCadenceHealthySamples = 0;
      _playbackCadenceClockUnstable = true;
      final heldPosition = _lastCrediblePlaybackPosition > Duration.zero
          ? _lastCrediblePlaybackPosition
          : _lastCadencePosition;
      final shouldLog = _lastPlaybackCadenceDriftLogAt == null ||
          now.difference(_lastPlaybackCadenceDriftLogAt!) >
              const Duration(seconds: 4);
      if (shouldLog) {
        _lastPlaybackCadenceDriftLogAt = now;
        debugPrint(
          'Juicr TV playback cadence drift observed '
          'engine=${controller.engine.name} '
          'observed=${position.inSeconds}s '
          'held=${heldPosition.inSeconds}s '
          'wallDeltaMs=$wallDeltaMs playbackDeltaMs=$playbackDeltaMs '
          'consecutive=$_playbackCadenceConsecutiveJumpEvents '
          'action=hold_progress_clock',
        );
      }
      if (_playbackCadenceConsecutiveJumpEvents >= 2) {
        unawaited(
          _recoverFromPlaybackCadenceDrift(
            controller,
            heldPosition,
            observedPosition: position,
          ),
        );
      }
      _lastCadenceSampleAt = now;
      _lastCadencePosition = heldPosition;
      return;
    }
    _lastCadenceSampleAt = now;
    _lastCadencePosition = position;
    _lastCrediblePlaybackPosition = position;
    final credibleDeltaMs = playbackDeltaMs.clamp(0, wallDeltaMs + 1000);
    _credibleWatchedDuration += Duration(milliseconds: credibleDeltaMs);
    _playbackCadenceConsecutiveJumpEvents = 0;
    _playbackCadenceHealthySamples += 1;
    final positionSecond = position.inSeconds;
    if (tvPlaybackCadenceShouldReport(
      lastReportedSecond: _lastPlaybackCadenceEvidenceSecond,
      positionSecond: positionSecond,
    )) {
      _lastPlaybackCadenceEvidenceSecond = positionSecond;
      debugPrint(
        'Juicr TV playback cadence sample '
        'engine=${controller.engine.name} position=${positionSecond}s '
        'audio=${value.hasSelectedAudioTrack ? 'active' : 'missing'}',
      );
    }
    if (_playbackCadenceClockUnstable && _playbackCadenceHealthySamples >= 8) {
      debugPrint(
        'Juicr TV playback cadence recovered '
        'engine=${controller.engine.name} position=${position.inSeconds}s',
      );
      _playbackCadenceClockUnstable = false;
      _lastPlaybackCadenceDriftLogAt = null;
    }
  }

  Future<void> _recoverFromPlaybackCadenceDrift(
    _TvNativePlaybackController controller,
    Duration anchorPosition, {
    required Duration observedPosition,
  }) async {
    if (_recoveringFromPlaybackCadence ||
        _recoveringRuntimePlayback ||
        _switchingSource ||
        _closingPlayback ||
        !mounted ||
        !identical(_controller, controller) ||
        _sessions.isEmpty) {
      return;
    }
    _recoveringFromPlaybackCadence = true;
    final resumePosition = anchorPosition > const Duration(seconds: 3)
        ? anchorPosition
        : _runtimeRecoveryResumePosition(controller, controller.value);
    final nextIndex = _sessions.length <= 1
        ? _sessionIndex
        : (_sessionIndex + 1) % _sessions.length;
    debugPrint(
      'Juicr TV playback cadence recovery queued '
      'engine=${controller.engine.name} '
      'observed=${observedPosition.inSeconds}s '
      'anchor=${resumePosition.inSeconds}s '
      'action=try_next_source',
    );
    if (_sessionIndex >= 0 && _sessionIndex < _sessions.length) {
      unawaited(
        _sendPlaybackFeedback(
          event: 'cadence_drift',
          session: _sessions[_sessionIndex],
          controller: controller,
          value: controller.value,
        ),
      );
      _reportRejectedSession(_sessions[_sessionIndex]);
    }
    try {
      await _openSession(
        nextIndex,
        feedbackLabel: 'Recovered',
        maxCandidateCount: _sessions.length <= 1 ? 1 : _sessions.length - 1,
        maxOpenDuration: const Duration(seconds: 60),
        resumePosition: resumePosition,
        restoreOldOnFailure: true,
      );
    } finally {
      _recoveringFromPlaybackCadence = false;
      _resetPlaybackCadenceState(crediblePosition: resumePosition);
    }
  }

  Future<void> _seekBy(Duration offset) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    final shouldPlay = value.isPlaying;
    final beforePosition = _absolutePlaybackPosition(controller, value);
    final duration = _absolutePlaybackDuration(controller, value);
    final clamped = tvPlaybackSeekTarget(
      before: beforePosition,
      offset: offset,
      duration: duration,
    );
    final transportAction = offset.isNegative
        ? TvPlaybackTransportAction.seekBack
        : TvPlaybackTransportAction.seekForward;
    final seekApplied = await _seekControllerToPlaybackPosition(
      controller,
      clamped,
      reason: 'remote_seek',
    );
    _lastKnownPlaybackPosition = clamped;
    if (duration > Duration.zero) _lastKnownPlaybackDuration = duration;
    if (seekApplied) {
      _resetPlaybackCadenceState(crediblePosition: clamped);
      await _resumePlaybackAfterSeek(controller, shouldPlay: shouldPlay);
    } else if (!shouldPlay) {
      await _controller?.pause();
    }
    final afterController = _controller;
    final afterValue = afterController == null
        ? null
        : await tvSettlePlaybackTransportState<_TvPlaybackValue>(
            read: () => afterController.value,
            isSettled: (value) {
              final observed =
                  _absolutePlaybackPosition(afterController, value);
              return (observed - clamped).abs() <= const Duration(seconds: 3);
            },
            timeout: tvPlaybackTransportSettleTimeout(
              action: transportAction,
              engine: afterController.engine.name,
            ),
          );
    if (afterController != null && afterValue != null) {
      debugPrint(
        tvPlaybackTransportOutcomeLine(
          action: transportAction,
          engine: afterController.engine.name,
          beforePosition: beforePosition,
          afterPosition: _absolutePlaybackPosition(afterController, afterValue),
          beforePlaying: shouldPlay,
          afterPlaying: afterValue.isPlaying,
        ),
      );
    }
    _showControls();
    if (mounted) setState(() {});
  }

  Future<bool> _seekControllerToPlaybackPosition(
    _TvNativePlaybackController controller,
    Duration target, {
    required String reason,
  }) async {
    final requiresRelayReopen = controller.engine == _TvPlaybackEngine.libvlc &&
        tvLibVlcContinuousTsSeekRequiresReopen(
          continuousTsActive: _libVlcContinuousTsActive,
          timelineOffset: _libVlcContinuousTsTimelineOffset,
          target: target,
          reason: reason,
        );
    final localTarget = requiresRelayReopen
        ? null
        : _libVlcContinuousTsLocalSeekPosition(controller, target);
    if (localTarget != null) {
      if (localTarget != target) {
        debugPrint(
          'Juicr TV libVLC continuous-ts seek translated '
          'target=${target.inSeconds}s local=${localTarget.inSeconds}s '
          'offset=${_libVlcContinuousTsTimelineOffset.inSeconds}s '
          'reason=$reason',
        );
      }
      await controller.seekTo(localTarget);
      return true;
    }
    if (controller.engine != _TvPlaybackEngine.libvlc ||
        _sessionIndex < 0 ||
        _sessionIndex >= _sessions.length ||
        _switchingSource ||
        _closingPlayback ||
        !mounted ||
        !identical(_controller, controller)) {
      await controller.seekTo(target);
      return true;
    }
    final wasPlaying = controller.value.isPlaying;
    await tvReleaseControllerForLibVlcResumeReopen(
      shouldRelease:
          requiresRelayReopen && mounted && identical(_controller, controller),
      stop: () async {
        try {
          await controller.stop().timeout(const Duration(milliseconds: 700));
        } catch (_) {}
      },
      detach: () {
        if (!mounted || !identical(_controller, controller)) return;
        setState(() => _replaceController(null));
      },
      settle: () async {
        if (mounted) {
          await WidgetsBinding.instance.endOfFrame.timeout(
            const Duration(seconds: 1),
            onTimeout: () {},
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 180));
      },
      dispose: () => controller.dispose().timeout(const Duration(seconds: 4)),
    );
    debugPrint(
      'Juicr TV libVLC continuous-ts seek reopen '
      'target=${target.inSeconds}s '
      'offset=${_libVlcContinuousTsTimelineOffset.inSeconds}s '
      'reason=$reason',
    );
    await _openSession(
      _sessionIndex,
      feedbackLabel: 'Seeking',
      resumePosition: target,
      restoreOldOnFailure: true,
    );
    if (tvShouldPauseReplacementAfterLibVlcReopen(
      wasPlaying: wasPlaying,
      reason: reason,
    )) {
      await _controller?.pause();
    }
    if (mounted) {
      setState(() {
        _controlsVisible = true;
        _loadingStatus = 'Playing';
      });
    }
    return false;
  }

  Duration? _libVlcContinuousTsLocalSeekPosition(
    _TvNativePlaybackController controller,
    Duration target,
  ) {
    if (controller.engine != _TvPlaybackEngine.libvlc ||
        !_libVlcContinuousTsActive) {
      return target;
    }
    final offset = _libVlcContinuousTsTimelineOffset;
    if (offset == Duration.zero) return target;
    if (target < offset - const Duration(seconds: 2)) return null;
    final localTarget = target - offset;
    return localTarget <= Duration.zero ? Duration.zero : localTarget;
  }

  Future<void> _recoverFromRuntimePlaybackError(
    _TvNativePlaybackController controller,
    _TvPlaybackValue value,
  ) async {
    if (_recoveringRuntimePlayback ||
        _switchingSource ||
        _closingPlayback ||
        !mounted ||
        !identical(_controller, controller)) {
      return;
    }
    _recoveringRuntimePlayback = true;
    final resumePosition = _runtimeRecoveryResumePosition(controller, value);
    final nextIndex = _sessions.length <= 1
        ? _sessionIndex
        : (_sessionIndex + 1) % _sessions.length;
    debugPrint(
      'Juicr TV runtime playback error '
      'engine=${controller.engine.name} '
      'position=${resumePosition.inSeconds}s '
      'action=try_next_source '
      'error=${_safeTvPlaybackError(value.errorDescription)}',
    );
    if (_sessionIndex >= 0 && _sessionIndex < _sessions.length) {
      unawaited(
        _sendPlaybackFeedback(
          event: 'runtime_error',
          session: _sessions[_sessionIndex],
          controller: controller,
          value: value,
        ),
      );
      _reportRejectedSession(_sessions[_sessionIndex]);
    }
    try {
      await _openSession(
        nextIndex,
        feedbackLabel: 'Recovered',
        maxCandidateCount: _sessions.length <= 1 ? 1 : _sessions.length - 1,
        maxOpenDuration: const Duration(seconds: 60),
        resumePosition: resumePosition,
        restoreOldOnFailure: true,
      );
    } finally {
      _runtimeErrorRecoverySuppressedUntil = DateTime.now().add(
        const Duration(seconds: 12),
      );
      _resetRuntimePlaybackErrorDebounce();
      _recoveringRuntimePlayback = false;
    }
  }

  Duration _runtimeRecoveryResumePosition(
    _TvNativePlaybackController controller,
    _TvPlaybackValue value,
  ) {
    final position = _absolutePlaybackPosition(controller, value);
    if (_playbackCadenceClockUnstable &&
        _lastCrediblePlaybackPosition > const Duration(seconds: 3)) {
      return _lastCrediblePlaybackPosition;
    }
    if (position > const Duration(seconds: 3)) return position;
    if (_lastKnownPlaybackPosition > const Duration(seconds: 3)) {
      return _lastKnownPlaybackPosition;
    }
    return Duration.zero;
  }

  Future<void> _resumePlaybackAfterSeek(
    _TvNativePlaybackController controller, {
    required bool shouldPlay,
  }) async {
    if (!mounted || !identical(_controller, controller)) return;
    if (!controller.value.isInitialized || controller.value.isEnded) return;
    if (!shouldPlay) {
      try {
        await tvPauseCurrentControllerAfterSeek<_TvNativePlaybackController>(
          currentController: controller,
          pause: (currentController) => currentController.pause(),
        );
      } catch (error) {
        debugPrint(
          'Juicr TV playback seek pause skipped '
          'engine=${controller.engine.name} '
          'errorType=${error.runtimeType}',
        );
      }
      return;
    }
    unawaited(
      () async {
        for (final delay in const <Duration>[
          Duration.zero,
          Duration(milliseconds: 280),
          Duration(milliseconds: 650),
          Duration(milliseconds: 1100),
          Duration(milliseconds: 1700),
        ]) {
          if (delay > Duration.zero) {
            await Future<void>.delayed(delay);
          }
          if (!mounted || !identical(_controller, controller)) return;
          final value = controller.value;
          if (!value.isInitialized || value.isEnded) return;
          if (!value.isPlaying) {
            debugPrint(
              'Juicr TV playback seek resume reassert '
              'engine=${controller.engine.name} '
              'position=${value.position.inSeconds}s',
            );
          }
          try {
            await controller.play();
          } catch (error) {
            debugPrint(
              'Juicr TV playback seek resume skipped '
              'engine=${controller.engine.name} '
              'errorType=${error.runtimeType}',
            );
          }
        }
      }(),
    );
  }

  void _handleRuntimePlaybackErrorObserved(
    _TvNativePlaybackController controller,
    _TvPlaybackValue value,
  ) {
    final now = DateTime.now();
    final suppressedUntil = _runtimeErrorRecoverySuppressedUntil;
    if (suppressedUntil != null && now.isBefore(suppressedUntil)) {
      debugPrint(
        'Juicr TV runtime playback error suppressed after recovery '
        'engine=${controller.engine.name} '
        'position=${value.position.inSeconds}s',
      );
      return;
    }
    _runtimeErrorRecoverySuppressedUntil = null;
    final description = _safeTvPlaybackError(value.errorDescription);
    final firstSeen = _runtimeErrorFirstSeenAt;
    final firstDescription = _runtimeErrorFirstDescription;
    if (firstSeen == null || firstDescription != description) {
      _runtimeErrorFirstSeenAt = now;
      _runtimeErrorFirstDescription = description;
      _runtimeErrorFirstPosition = value.position;
      _runtimeErrorRecoveryTimer?.cancel();
      _runtimeErrorRecoveryTimer = Timer(
        const Duration(milliseconds: 1300),
        () {
          if (!mounted || !identical(_controller, controller)) return;
          final latest = controller.value;
          if (latest.errorDescription.isEmpty) {
            _resetRuntimePlaybackErrorDebounce();
            return;
          }
          _handleRuntimePlaybackErrorObserved(controller, latest);
        },
      );
      debugPrint(
        'Juicr TV runtime playback error observed '
        'engine=${controller.engine.name} '
        'position=${value.position.inSeconds}s '
        'playing=${value.isPlaying} buffering=${value.isBuffering} '
        'action=debounce error=$description',
      );
      return;
    }
    final elapsed = now.difference(firstSeen);
    final advanced = value.position - _runtimeErrorFirstPosition >
        const Duration(milliseconds: 750);
    if (advanced) {
      debugPrint(
        'Juicr TV runtime playback error cleared by progress '
        'engine=${controller.engine.name} '
        'position=${value.position.inSeconds}s',
      );
      _resetRuntimePlaybackErrorDebounce();
      return;
    }
    if (value.isPlaying || value.isBuffering) {
      debugPrint(
        'Juicr TV runtime playback error held as transient '
        'engine=${controller.engine.name} '
        'position=${value.position.inSeconds}s '
        'playing=${value.isPlaying} buffering=${value.isBuffering}',
      );
      return;
    }
    if (elapsed < const Duration(milliseconds: 4500)) return;
    unawaited(_recoverFromRuntimePlaybackError(controller, value));
  }

  Future<void> _skipBy(Duration offset, {required int direction}) async {
    await _seekBy(offset);
  }

  Future<void> _fastSeekBy(Duration offset, {required int direction}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await _seekBy(offset);
    _showFeedback(
      direction < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
      '',
      seeking: true,
    );
  }

  void _prepareForOptionDialog() {
    _showControls();
    _hideControlsTimer?.cancel();
  }

  bool get _seriesLike =>
      widget.item.type == 'series' || widget.item.type == 'animation';

  bool get _hasNextEpisodeMetadata {
    final next = _nextEpisodeMetadata();
    if (next == null) return false;
    final title = next.title.trim();
    final description = next.description.trim();
    final defaultTitle = 'Episode ${next.episode}';
    final defaultDescription = 'Episode ${next.episode}';
    return (next.thumbnail ?? '').trim().isNotEmpty ||
        (title.isNotEmpty && title != defaultTitle) ||
        (description.isNotEmpty && description != defaultDescription);
  }

  _TvEpisode? _nextEpisodeMetadata() {
    if (!_seriesLike) return null;
    final nextEpisode = _episode + 1;
    for (final episode in widget.item.episodes) {
      if (episode.season == _season && episode.episode == nextEpisode) {
        return episode;
      }
    }
    return null;
  }

  _TvPlayerSkipSegment? _activeSkipSegment(_TvPlaybackValue value) {
    if (_locked || !value.isInitialized || !_skipSegmentsSupported) return null;
    final duration = value.duration;
    final position = value.position;
    final remoteSegment = _activeTvPlaybackSkipSegment(
      _skipSegments,
      position,
      duration,
    );
    if (remoteSegment != null) {
      return _TvPlayerSkipSegment(
        label: remoteSegment.label,
        target: remoteSegment.targetFor(duration),
      );
    }
    if (_hasEpisodeSkipSegmentIdentity) return null;
    if (duration.inMinutes < 15) return null;
    final totalSeconds = duration.inSeconds;
    if (position.inSeconds <= 80) {
      final target = const Duration(seconds: 30);
      final capped = target < Duration(seconds: totalSeconds - 30)
          ? target
          : Duration(seconds: totalSeconds - 30);
      if (capped > position + const Duration(seconds: 5)) {
        return _TvPlayerSkipSegment(label: 'Skip intro', target: capped);
      }
    }
    final remaining = totalSeconds - position.inSeconds;
    if (remaining <= 105 && remaining > 8) {
      return _TvPlayerSkipSegment(
        label: 'Skip outro',
        target: Duration(seconds: math.max(0, totalSeconds - 2)),
      );
    }
    return null;
  }

  Future<void> _skipToSegment(_TvPlayerSkipSegment segment) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _locked) {
      return;
    }
    await controller.seekTo(segment.target);
    await _resumePlaybackAfterSeek(controller, shouldPlay: true);
    _showControls();
  }

  void _startHoldSeek(int direction) {
    if (_holdSeekDirection == direction &&
        (_holdSeekDelayTimer != null || _holdSeekTimer != null)) {
      return;
    }
    _stopHoldSeek();
    _holdSeekDirection = direction;
    _holdSeekDelayTimer = Timer(const Duration(milliseconds: 260), () {
      _holdSeekDelayTimer = null;
      unawaited(
        direction < 0
            ? _fastSeekBy(
                Duration(seconds: -_fastSeekStep.inSeconds),
                direction: -1,
              )
            : _fastSeekBy(_fastSeekStep, direction: 1),
      );
      _holdSeekTimer = Timer.periodic(const Duration(milliseconds: 240), (_) {
        unawaited(
          direction < 0
              ? _fastSeekBy(
                  Duration(seconds: -_fastSeekStep.inSeconds),
                  direction: -1,
                )
              : _fastSeekBy(_fastSeekStep, direction: 1),
        );
      });
    });
  }

  void _stopHoldSeek() {
    _holdSeekDirection = 0;
    _holdSeekDelayTimer?.cancel();
    _holdSeekDelayTimer = null;
    _holdSeekTimer?.cancel();
    _holdSeekTimer = null;
  }

  void _showControls({bool focusPrimary = false}) {
    _hideControlsTimer?.cancel();
    setState(() => _controlsVisible = true);
    _scheduleControlsAutoHide();
    if (focusPrimary) _requestPrimaryHudFocusAfterBuild();
  }

  void _refreshControlsAutoHideTimer() {
    if (!_controlsVisible) return;
    _hideControlsTimer?.cancel();
    _scheduleControlsAutoHide();
  }

  void _scheduleControlsAutoHide() {
    _hideControlsTimer = Timer(_controlsAutoHideDelay, () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
      _playbackFocusNode.requestFocus();
    });
  }

  FocusNode _bottomEntryPlaybackFocusNode() {
    final value = _controller?.value ?? _TvPlaybackValue.empty;
    final skipSegmentFocusable = !_locked && _activeSkipSegment(value) != null;
    if (skipSegmentFocusable) return _skipSegmentFocusNode;
    if (_locked) return _lockFocusNode;
    return _seriesLike && widget.item.episodes.isNotEmpty
        ? _episodesFocusNode
        : _sourcesFocusNode;
  }

  FocusNode _preferredRevealFocusNode(TvRemoteActionBucket bucket) {
    if (tvPlaybackRevealFocusPolicy.targetFor(
          bucket: bucket,
          controlsLocked: _locked,
        ) ==
        TvPlaybackRevealFocusTarget.lock) {
      return _lockFocusNode;
    }
    return switch (bucket) {
      TvRemoteActionBucket.dpadUp => _backFocusNode,
      TvRemoteActionBucket.dpadDown => _bottomEntryPlaybackFocusNode(),
      TvRemoteActionBucket.dpadLeft =>
        _isLiveTvPlayback ? _playFocusNode : _skipBackFocusNode,
      TvRemoteActionBucket.dpadRight =>
        _isLiveTvPlayback ? _lockFocusNode : _skipForwardFocusNode,
      TvRemoteActionBucket.settings ||
      TvRemoteActionBucket.captions =>
        _settingsFocusNode,
      TvRemoteActionBucket.menu ||
      TvRemoteActionBucket.info =>
        _sourcesFocusNode,
      _ => _locked ? _lockFocusNode : _playFocusNode,
    };
  }

  void _showControlsForRemoteBucket(TvRemoteActionBucket bucket) {
    _showControls();
    _requestHudFocusAfterBuild(_preferredRevealFocusNode(bucket));
  }

  void _syncNativeHiddenHudCapture({required bool initialized}) {
    final shouldCapture = tvHiddenHudRemoteCapturePolicy.shouldCapture(
      initialized: initialized,
      controlsVisible: _controlsVisible,
      switchingSource: _switchingSource,
      dialogOpen: _hasPlaybackDialogOpen,
    );
    if (_nativeHiddenHudCaptureActive == shouldCapture) return;
    _nativeHiddenHudCaptureActive = shouldCapture;
    unawaited(
      _tvRemoteKeyChannel.invokeMethod<void>(
        'setHiddenHudCapture',
        <String, Object?>{'active': shouldCapture},
      ),
    );
  }

  void _requestPrimaryHudFocusAfterBuild([int attempt = 0]) {
    final target = _locked ? _lockFocusNode : _playFocusNode;
    _requestHudFocusAfterBuild(target, attempt);
  }

  FocusNode _fallbackHudFocusNodeFor(FocusNode target) {
    if (_locked) return _lockFocusNode;
    if (target == _skipSegmentFocusNode ||
        target == _skipForwardFocusNode ||
        target == _skipBackFocusNode) {
      return _sourcesFocusNode;
    }
    return _playFocusNode;
  }

  void _requestHudFocusAfterBuild(FocusNode target, [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_controlsVisible ||
          _switchingSource ||
          _resumePromptVisible) {
        return;
      }
      if (target.context != null && target.canRequestFocus) {
        target.requestFocus();
        return;
      }
      if (attempt < 4) {
        _requestHudFocusAfterBuild(target, attempt + 1);
        return;
      }
      final fallback = _fallbackHudFocusNodeFor(target);
      if (fallback.context != null && fallback.canRequestFocus) {
        fallback.requestFocus();
      } else if (_playbackFocusNode.canRequestFocus) {
        _playbackFocusNode.requestFocus();
      }
    });
  }

  void _revealControlsAfterInitialization(bool initialized) {
    if (_resumePromptVisible) return;
    if (!initialized) {
      _initializedHudRevealed = false;
      return;
    }
    if (_initializedHudRevealed) return;
    _initializedHudRevealed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _switchingSource || _resumePromptVisible) return;
      _showControls(focusPrimary: true);
    });
  }

  void _showFeedback(
    IconData icon,
    String label, {
    bool seeking = false,
    int skipDirection = 0,
  }) {
    _feedbackTimer?.cancel();
    setState(
      () => _feedback = _TvPlaybackFeedback(
        icon,
        label,
        seeking: seeking,
        skipDirection: skipDirection,
      ),
    );
    _feedbackTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      setState(() => _feedback = null);
    });
  }

  void _toggleLock() {
    final nextLocked = !_locked;
    _hideControlsTimer?.cancel();
    _feedbackTimer?.cancel();
    setState(() {
      _locked = nextLocked;
      _controlsVisible = !nextLocked;
      _feedback = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_locked) {
        _playbackFocusNode.requestFocus();
      } else {
        _showControls(focusPrimary: true);
      }
    });
  }

  void _showPlayerToast(String message) {
    _showControls();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  _TvPlaybackProgress _currentProgress() {
    final controller = _controller;
    final value = controller?.value ?? _TvPlaybackValue.empty;
    if (!value.isInitialized) {
      return _TvPlaybackProgress(
        position: _lastKnownPlaybackPosition,
        duration: _lastKnownPlaybackDuration,
        credibleWatched: _credibleWatchedDuration,
      );
    }
    return _TvPlaybackProgress(
      position: _stablePlaybackPosition(
                _absolutePlaybackPosition(controller!, value),
              ) >
              Duration.zero
          ? _stablePlaybackPosition(
              _absolutePlaybackPosition(controller, value))
          : _lastKnownPlaybackPosition,
      duration: _absolutePlaybackDuration(controller, value) > Duration.zero
          ? _absolutePlaybackDuration(controller, value)
          : _lastKnownPlaybackDuration,
      credibleWatched: _credibleWatchedDuration,
    );
  }

  Duration _absolutePlaybackPosition(
    _TvNativePlaybackController controller,
    _TvPlaybackValue value,
  ) {
    return tvPlaybackAbsolutePosition(
      rawPosition: value.position,
      reportedDuration: value.duration,
      libVlcContinuousTsActive: controller.engine == _TvPlaybackEngine.libvlc &&
          _libVlcContinuousTsActive,
      libVlcTimelineOffset: _libVlcContinuousTsTimelineOffset,
      displayTimelineOffset: _playbackDisplayTimelineOffset,
    );
  }

  Duration _absolutePlaybackDuration(
    _TvNativePlaybackController controller,
    _TvPlaybackValue value,
  ) {
    if (value.duration > Duration.zero) return value.duration;
    return _lastKnownPlaybackDuration;
  }

  TvPlaybackTimelineOwnership get _playbackTimelineOwnership =>
      TvPlaybackTimelineOwnership(
        continuousTsActive: _libVlcContinuousTsActive,
        timelineOffset: _libVlcContinuousTsTimelineOffset,
        displayOffset: _playbackDisplayTimelineOffset,
      );

  void _applyPlaybackTimelineOwnership(
    TvPlaybackTimelineOwnership ownership,
  ) {
    _libVlcContinuousTsActive = ownership.continuousTsActive;
    _libVlcContinuousTsTimelineOffset = ownership.timelineOffset;
    _playbackDisplayTimelineOffset = ownership.displayOffset;
  }

  Future<void> _closePlayback() async {
    if (_closingPlayback) return;
    debugPrint(
      'Juicr TV close playback requested '
      'dialogDepth=$_playbackDialogDepth switching=$_switchingSource',
    );
    _closingPlayback = true;
    final p2pClosingGeneration = _startupAttemptGeneration;
    _playbackGeneration++;
    _subtitleLoadGeneration++;
    final progress = _timelineTransaction.snapshotForClose<_TvPlaybackProgress>(
      current: _playbackTimelineOwnership,
      apply: _applyPlaybackTimelineOwnership,
      snapshot: _currentProgress,
    );
    final controller = _controller;
    final stagedController = _stagedController;
    if (_sessionIndex >= 0 && _sessionIndex < _sessions.length) {
      unawaited(
        _sendPlaybackFeedback(
          event: 'closed',
          session: _sessions[_sessionIndex],
          controller: controller,
          value: controller?.value ??
              _TvPlaybackValue(
                position: progress.position,
                duration: progress.duration,
              ),
        ),
      );
    }
    if (controller != null) {
      setState(() {
        _replaceStagedController(null);
        _replaceController(null);
      });
      await controller.dispose();
    } else if (stagedController != null) {
      setState(() => _replaceStagedController(null));
    }
    if (stagedController != null && !identical(stagedController, controller)) {
      await stagedController.dispose();
    }
    await _p2pPlaybackOwner
        .closeThrough(p2pClosingGeneration)
        .timeout(const Duration(seconds: 2), onTimeout: () {});
    if (!mounted) return;
    Navigator.of(context).pop(
      _TvPlaybackResult(
        season: _season,
        episode: _episode,
        progress: progress,
      ),
    );
  }

  void _closePlaybackUnavailable(String message) {
    if (_closingPlayback) return;
    _closingPlayback = true;
    unawaited(_settleUnavailablePlaybackAndClose(message));
  }

  Future<void> _settleUnavailablePlaybackAndClose(String message) async {
    final p2pClosingGeneration = _startupAttemptGeneration;
    _playbackGeneration++;
    final stagedController = _stagedController;
    if (stagedController != null) {
      if (mounted) {
        setState(() => _replaceStagedController(null));
      } else {
        _replaceStagedController(null);
      }
      await stagedController.dispose();
    }
    try {
      await _p2pPlaybackOwner
          .closeThrough(p2pClosingGeneration)
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    } catch (_) {
      // The playback route still closes truthfully if native cleanup fails.
    }
    if (!mounted) return;
    Navigator.of(context).pop(_TvPlaybackUnavailable(message));
  }

  void _updateRemoteDebug(TvRemoteActionBucket? bucket) {
    final focusLabel = FocusManager.instance.primaryFocus?.debugLabel;
    _remoteDebugSnapshot = _remoteDebugSnapshot.copyWith(
      lastKeyBucket: bucket,
      currentSurfaceName: 'playback',
      currentFocusLabel:
          focusLabel == null || focusLabel.trim().isEmpty ? 'none' : focusLabel,
      controlsVisible: _controlsVisible,
      controlsLocked: _locked,
    );
  }

  List<_TvPlaybackEngine> _engineLadderFor(_PlaybackSession session) {
    final mode = widget.settings.playbackEngine;
    if (mode == 'Compatibility') {
      return const <_TvPlaybackEngine>[
        _TvPlaybackEngine.libvlc,
        _TvPlaybackEngine.media3,
      ];
    }
    if (_isNativeHlsSession(session)) {
      if (mode == 'Native') {
        return const <_TvPlaybackEngine>[
          _TvPlaybackEngine.media3,
        ];
      }
      return const <_TvPlaybackEngine>[
        _TvPlaybackEngine.media3,
        _TvPlaybackEngine.libvlc,
      ];
    }
    if (mode == 'Native') {
      return const <_TvPlaybackEngine>[
        _TvPlaybackEngine.media3,
      ];
    }
    return const <_TvPlaybackEngine>[
      _TvPlaybackEngine.media3,
      _TvPlaybackEngine.libvlc,
    ];
  }

  Future<_TvNativePlaybackController> _prepareNativeController(
    _PlaybackSession session,
    _TvPlaybackEngine engine,
    int generation,
    int startupAttempt,
    Duration resumePosition,
  ) async {
    final startedAt = DateTime.now();
    var controllerSession = session;
    LibVlcHlsRelay? relay;
    _TvRelayStartupProof? relayProof;
    var continuousTsMode = false;
    final shouldRelay = _shouldRelaySession(session, engine);
    _updatePlaybackLoadingStatus('Preparing playback source...');
    if (shouldRelay) {
      debugPrint(
        'Juicr TV native relay decision engine=${engine.name} shouldRelay=$shouldRelay '
        'sourceType=${_safePlaybackTypeBucket(session.sourceType)} '
        'url=${_safePlaybackUrlBucket(session.tvMediaUrl)}',
      );
    }
    if (shouldRelay) {
      relayProof = _TvRelayStartupProof();
      final canUseLibVlcContinuousTs = engine == _TvPlaybackEngine.libvlc &&
          (session.tvMediaUrl
                  .toLowerCase()
                  .contains('/web/playback/session/') ||
              (_isNativeHlsSession(session) && session.httpHeaders.isNotEmpty));
      continuousTsMode = canUseLibVlcContinuousTs;
      relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(session.tvMediaUrl),
        headers: session.httpHeaders,
        limitHeadersToUpstreamOrigin: continuousTsMode,
        resumePosition: resumePosition,
        continuousTsMode: continuousTsMode,
        onDuration: relayProof.updateDuration,
        onContinuousTsProgress: relayProof.updateProgress,
        onContinuousTsBytes: relayProof.updateBytes,
        onEvent: (message) => debugPrint('Juicr TV $message'),
      );
      controllerSession = session.copyWith(
        mediaUrl: relay.localUri.toString(),
        sourceType: continuousTsMode ? 'ts' : 'hls',
        httpHeaders: const <String, String>{},
      );
      debugPrint(
        'Juicr TV native HLS relay started engine=${engine.name} '
        'scope=${continuousTsMode ? 'continuous_ts' : 'playlist'} '
        'resume=${resumePosition.inSeconds}s',
      );
    }
    final controller = switch (engine) {
      _TvPlaybackEngine.media3 => _TvNativePlaybackController.media3(
          controllerSession,
          subtitles: _selectedSubtitlesForPlayback(),
          liveMode: _isLiveTvPlayback,
          relay: relay,
        ),
      _TvPlaybackEngine.libvlc => _TvNativePlaybackController.libvlc(
          controllerSession,
          relay: relay,
          relayProof: relayProof,
        ),
    };
    if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
      await relay?.stop();
      await controller.dispose();
      throw const _TvPlaybackCanceledException();
    }
    _updatePlaybackLoadingStatus('Opening playback...');
    final stageForReplacement = _controller?.value.isInitialized == true;
    final retainedTimelineOwnership = _playbackTimelineOwnership;
    setState(() {
      if (stageForReplacement) {
        _replaceStagedController(controller);
      } else {
        _replaceController(controller);
      }
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
        throw const _TvPlaybackCanceledException();
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
        throw const _TvPlaybackCanceledException();
      }
      await controller.initialize().timeout(const Duration(seconds: 24));
      if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
        throw const _TvPlaybackCanceledException();
      }
      await controller.setVideoSizeMode(_nativeTvVideoSizeModeFor(_videoSize));
      _libVlcContinuousTsActive =
          engine == _TvPlaybackEngine.libvlc && continuousTsMode;
      _libVlcContinuousTsTimelineOffset =
          _libVlcContinuousTsActive ? resumePosition : Duration.zero;
      debugPrint(
        'Juicr TV playback timeline ownership '
        'engine=${engine.name} continuous=$_libVlcContinuousTsActive '
        'offset=${_libVlcContinuousTsTimelineOffset.inSeconds}s '
        'resume=${resumePosition.inSeconds}s',
      );
      _updatePlaybackLoadingStatus('Starting playback...');
      if (!_isLiveTvPlayback) {
        await controller.setPlaybackSpeed(_playbackSpeed);
      }
      final hasExplicitResumePosition = resumePosition > Duration.zero;
      final targetResumePosition =
          hasExplicitResumePosition ? resumePosition : _initialResumePosition;
      final shouldResumeInitialEpisode =
          _season == widget.initialSeason && _episode == widget.initialEpisode;
      final resumeSeekEligible = !_isLiveTvPlayback &&
          (hasExplicitResumePosition || shouldResumeInitialEpisode);
      final relayAlreadyAtResume = engine == _TvPlaybackEngine.libvlc &&
          continuousTsMode &&
          resumePosition > Duration.zero &&
          targetResumePosition == resumePosition;
      if (resumeSeekEligible &&
          _canSeekToResumePosition(
            targetResumePosition,
            controller.value.duration,
          )) {
        debugPrint(
          'Juicr TV native initial resume seek '
          'position=${targetResumePosition.inSeconds}s '
          'duration=${controller.value.duration.inSeconds}s',
        );
        if (!relayAlreadyAtResume) {
          await controller.seekTo(targetResumePosition);
        }
        final rawAfterResumeSeek = controller.value;
        _playbackDisplayTimelineOffset =
            rawAfterResumeSeek.duration <= Duration.zero &&
                    rawAfterResumeSeek.position <
                        targetResumePosition - const Duration(seconds: 2)
                ? targetResumePosition
                : Duration.zero;
        _lastKnownPlaybackPosition = targetResumePosition;
        _resetPlaybackCadenceState(crediblePosition: targetResumePosition);
        if (controller.value.duration > Duration.zero) {
          _lastKnownPlaybackDuration = controller.value.duration;
        }
      }
      if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
        throw const _TvPlaybackCanceledException();
      }
      final replacementProofStartPosition = controller.value.position;
      await controller.play();
      _updatePlaybackLoadingStatus('Confirming playback...');
      await _verifyStartupProof(controller, engine, generation, startupAttempt);
      await controller.ensureSelectedAudioTrack();
      if (stageForReplacement) {
        await _verifyReplacementPromotionProof(
          controller,
          generation,
          startupAttempt,
          replacementProofStartPosition,
        );
      }
      if (resumeSeekEligible &&
          _canSeekToResumePosition(
            targetResumePosition,
            controller.value.duration,
          ) &&
          tvPlaybackStartupNeedsPostProofResume(
            target: targetResumePosition,
            current: controller.value.position,
            relayAlreadyAtResume: relayAlreadyAtResume,
          )) {
        debugPrint(
          'Juicr TV native post-proof resume seek '
          'engine=${engine.name} target=present',
        );
        await controller.seekTo(targetResumePosition);
        final settledValue =
            await tvSettlePlaybackTransportState<_TvPlaybackValue>(
          read: () => controller.value,
          isSettled: (value) =>
              (value.position - targetResumePosition).abs() <=
              const Duration(seconds: 3),
          timeout: const Duration(seconds: 8),
        );
        if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
          throw const _TvPlaybackCanceledException();
        }
        if ((settledValue.position - targetResumePosition).abs() >
            const Duration(seconds: 3)) {
          throw StateError('resume_seek_unsettled');
        }
        _playbackDisplayTimelineOffset = Duration.zero;
        _lastKnownPlaybackPosition = targetResumePosition;
        if (settledValue.duration > Duration.zero) {
          _lastKnownPlaybackDuration = settledValue.duration;
        }
        _resetPlaybackCadenceState(crediblePosition: targetResumePosition);
      }
      await _ensureAutoplayAfterStartup(controller, generation, startupAttempt);
      if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
        throw const _TvPlaybackCanceledException();
      }
      final readyValue = controller.value;
      if (_shouldRejectShortVodPlaceholder(readyValue)) {
        debugPrint(
          'Juicr TV short VOD placeholder rejected '
          'engine=${engine.name} duration=${readyValue.duration.inSeconds}s '
          'expected=${_expectedRuntimeDuration()?.inSeconds ?? 0}s '
          '${_safePlaybackSessionFingerprint(session)}',
        );
        throw StateError('short_vod_placeholder');
      }
      debugPrint(
        'Juicr TV native playback ready engine=${engine.name} '
        'size=${readyValue.size.width.toStringAsFixed(0)}x'
        '${readyValue.size.height.toStringAsFixed(0)} '
        'aspect=${readyValue.aspectRatio.toStringAsFixed(3)} '
        'duration=${readyValue.duration.inSeconds}s '
        'position=${readyValue.position.inSeconds}s '
        '${_safePlaybackSessionFingerprint(session)}',
      );
      unawaited(
        _sendPlaybackFeedback(
          event: 'open_success',
          session: session,
          controller: controller,
          value: controller.value,
          startupMs: DateTime.now().difference(startedAt).inMilliseconds,
        ),
      );
      return controller;
    } catch (error) {
      final startupAttemptStillActive =
          _isPlaybackStartupAttemptActive(generation, startupAttempt);
      final controllerIsStaged = identical(_stagedController, controller);
      if (stageForReplacement &&
          tvFailedStartupCanRestoreTimeline(
            attemptIsCurrent: startupAttemptStillActive,
            controllerIsStaged: controllerIsStaged,
          )) {
        _applyPlaybackTimelineOwnership(
          tvPlaybackTimelineAfterReplacement(
            retained: retainedTimelineOwnership,
            staged: _playbackTimelineOwnership,
            promoted: false,
          ),
        );
      }
      if (error is! _TvPlaybackCanceledException && startupAttemptStillActive) {
        debugPrint(
          'Juicr TV native playback candidate failed '
          'engine=${engine.name} bucket=${_playbackInitBucket(error)} '
          'errorType=${error.runtimeType} detail=${_safeTvPlaybackError(error)}',
        );
      }
      if (identical(_controller, controller) || controllerIsStaged) {
        void detach() {
          if (controllerIsStaged) {
            _replaceStagedController(null);
          } else {
            _replaceController(null);
          }
        }

        if (mounted) {
          setState(() => tvDetachFailedStartupController(
                currentController: () =>
                    controllerIsStaged ? _stagedController : _controller,
                failedController: controller,
                detach: detach,
              ));
        } else {
          tvDetachFailedStartupController(
            currentController: () =>
                controllerIsStaged ? _stagedController : _controller,
            failedController: controller,
            detach: detach,
          );
        }
      }
      if (relay != null &&
          !identical(_controller, controller) &&
          !identical(_stagedController, controller)) {
        await relay.stop();
      }
      await controller.dispose();
      rethrow;
    }
  }

  bool _shouldRelaySession(_PlaybackSession session, _TvPlaybackEngine engine) {
    final url = session.tvMediaUrl.toLowerCase();
    if (url.contains('/web/playback/session/')) {
      return engine == _TvPlaybackEngine.libvlc;
    }
    if (!_isNativeHlsSession(session)) return false;
    if (engine == _TvPlaybackEngine.libvlc) {
      return session.httpHeaders.isNotEmpty;
    }
    return false;
  }

  bool _isNativeHlsSession(_PlaybackSession session) {
    final type = session.sourceType.toLowerCase();
    final url = session.tvMediaUrl.toLowerCase();
    return type.contains('hls') ||
        type.contains('m3u8') ||
        type.contains('mpegurl') ||
        url.contains('.m3u8');
  }

  String _safePlaybackTypeBucket(String sourceType) {
    final type = sourceType.toLowerCase();
    if (type.contains('mpegurl') || type.contains('m3u8')) return 'hls';
    if (type.contains('dash') || type.contains('mpd')) return 'dash';
    if (type.contains('mp4') || type.contains('video')) return 'file';
    return type.isEmpty ? 'unknown' : 'other';
  }

  String _safePlaybackUrlBucket(String url) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('/web/playback/session/')) return 'web-session';
    if (lowerUrl.contains('.m3u8')) return 'hls-path';
    if (lowerUrl.contains('.mpd')) return 'dash-path';
    if (lowerUrl.contains('.mp4')) return 'file-path';
    return url.startsWith('https://') ? 'https' : 'other';
  }

  String _safePlaybackSessionFingerprint(_PlaybackSession session) {
    final quality = _qualityLabelForSession(session);
    final type = _safePlaybackTypeBucket(session.sourceType);
    final url = _safePlaybackUrlBucket(session.tvMediaUrl);
    final sourceClass = session.sourceClass.trim().isEmpty
        ? 'none'
        : _safePlaybackTypeBucket(session.sourceClass);
    final headers = session.httpHeaders.length;
    final captions = session.subtitles.length;
    final providerBucket = session.providerId.trim().isEmpty ? 'none' : 'set';
    final format = session.videoFormatHint?.name ?? 'auto';
    return 'quality=$quality type=$type url=$url class=$sourceClass '
        'headers=$headers captions=$captions provider=$providerBucket '
        'format=$format';
  }

  String _safeTvPlaybackError(Object error) {
    return error
        .toString()
        .replaceAll(
          RegExp(
            r'(authorization|cookie|token|api(?:-|_| )?key|x-api-key)\s*[:=]\s*[^,\s]+',
            caseSensitive: false,
          ),
          r'$1=[hidden]',
        )
        .replaceAll(
          RegExp(r'bearer\s+[A-Za-z0-9._~+/=\-]+', caseSensitive: false),
          'bearer [hidden]',
        )
        .replaceAll(RegExp(r'https?://[^\s"]+'), '[hidden-url]')
        .replaceAll(RegExp(r'127\.0\.0\.1[^\s"]*'), '[localhost-hidden]')
        .replaceAll(RegExp(r'localhost[^\s"]*'), '[localhost-hidden]');
  }

  bool _isHardSourceUnavailableError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('error_code_io_bad_http_status') ||
        text.contains('invalidresponsecodeexception') ||
        text.contains('response code: 403') ||
        text.contains('response code: 404') ||
        text.contains('response code: 410') ||
        text.contains('status=not_found') ||
        text.contains('not_found') ||
        text.contains('http connection failure');
  }

  Future<_TvNativePlaybackController> _prepareWithLadder(
    _PlaybackSession session,
    int generation,
    int startupAttempt,
    int sessionIndex,
    Duration resumePosition, {
    _TvPlaybackEngine? requiredEngine,
  }) async {
    Object? lastError;
    var currentSession = session;
    var p2pPrepared = false;
    final p2pDescriptor = session.p2pDescriptor;
    final p2pGeneration = p2pDescriptor == null
        ? null
        : tvP2pOwnershipGenerationForStartupAttempt(startupAttempt);
    if (p2pDescriptor != null) {
      try {
        _updatePlaybackLoadingStatus('Preparing advanced playback...');
        final localUri = await _p2pPlaybackOwner.prepare(
          p2pDescriptor,
          generation: p2pGeneration!,
        );
        p2pPrepared = true;
        if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
          await _p2pPlaybackOwner.rollback(p2pGeneration);
          throw const _TvPlaybackCanceledException();
        }
        currentSession = session.copyWith(
          mediaUrl: localUri.toString(),
          sourceType: 'p2p-local',
          httpHeaders: const <String, String>{},
        );
        debugPrint(
          'Juicr TV advanced playback local handoff ready '
          'engineScope=both generation=current',
        );
      } catch (error) {
        if (error is _TvPlaybackCanceledException) rethrow;
        if (p2pPrepared) {
          await _p2pPlaybackOwner.rollback(p2pGeneration!);
        }
        throw _PlaybackUnavailableException(_playbackInitBucket(error));
      }
    }
    final engineLadder = requiredEngine == null
        ? _engineLadderFor(currentSession)
        : <_TvPlaybackEngine>[requiredEngine];
    for (var index = 0; index < engineLadder.length; index += 1) {
      final engine = engineLadder[index];
      try {
        if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
          throw const _TvPlaybackCanceledException();
        }
        _updatePlaybackLoadingStatus(
          _engineLoadingStatus(index, engineLadder.length),
        );
        final preparedController = await _prepareNativeController(
          currentSession,
          engine,
          generation,
          startupAttempt,
          resumePosition,
        );
        if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
          await preparedController.dispose();
          throw const _TvPlaybackCanceledException();
        }
        final ownershipIsCurrent = await tvFinalizePreparedPlaybackOwnership(
          finalizeOwnership: p2pPrepared
              ? () => _p2pPlaybackOwner.commit(p2pGeneration!)
              : () => _p2pPlaybackOwner.closeThrough(startupAttempt - 1),
          isCurrent: () =>
              _isPlaybackStartupAttemptActive(generation, startupAttempt),
          disposePreparedController: preparedController.dispose,
          rollbackPreparedOwnership: p2pPrepared
              ? () => _p2pPlaybackOwner.rollback(p2pGeneration!)
              : null,
        );
        if (!ownershipIsCurrent) {
          p2pPrepared = false;
          throw const _TvPlaybackCanceledException();
        }
        return preparedController;
      } catch (error) {
        if (error is _TvPlaybackCanceledException) {
          await tvRollbackPreparedP2pOnCanceledStartup(
            p2pPrepared: p2pPrepared,
            rollback: () => _p2pPlaybackOwner.rollback(p2pGeneration!),
          );
          rethrow;
        }
        lastError = error;
        if (_isHardSourceUnavailableError(error)) {
          debugPrint(
            'Juicr TV source unavailable hard stop '
            'engine=${engine.name} bucket=${_playbackInitBucket(error)} '
            'action=try_next_source',
          );
          break;
        }
        if (index < engineLadder.length - 1) {
          _updatePlaybackLoadingStatus('Trying another playback engine...');
        }
      }
    }
    if (p2pPrepared) {
      await _p2pPlaybackOwner.rollback(p2pGeneration!);
    }
    throw _PlaybackUnavailableException(
      _playbackInitBucket(lastError ?? 'media_init'),
    );
  }

  Future<void> _verifyStartupProof(
    _TvNativePlaybackController controller,
    _TvPlaybackEngine engine,
    int generation,
    int startupAttempt,
  ) async {
    final timeout = tvPlaybackStartupProofTimeout(
      libVlc: engine == _TvPlaybackEngine.libvlc,
      livePlayback: _isLiveTvPlayback,
    );
    final deadline = DateTime.now().add(timeout);
    _TvPlaybackValue lastValue = _TvPlaybackValue.empty;
    while (DateTime.now().isBefore(deadline)) {
      if (!_isPlaybackGenerationActive(generation)) {
        throw const _TvPlaybackCanceledException();
      }
      lastValue = controller.value;
      if (lastValue.errorDescription.isNotEmpty) {
        throw StateError(lastValue.errorDescription);
      }
      if (controller.hasStartupProof) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    debugPrint(
      'Juicr TV startup proof timed out engine=${engine.name} '
      'initialized=${lastValue.isInitialized} playing=${lastValue.isPlaying} '
      'buffering=${lastValue.isBuffering} duration=${lastValue.duration.inSeconds}s '
      'position=${lastValue.position.inSeconds}s '
      'size=${lastValue.size.width.toStringAsFixed(0)}x${lastValue.size.height.toStringAsFixed(0)}',
    );
    throw StateError('${engine.name}_startup');
  }

  Future<void> _verifyReplacementPromotionProof(
    _TvNativePlaybackController controller,
    int generation,
    int startupAttempt,
    Duration startPosition,
  ) async {
    const timeout = Duration(seconds: 8);
    final deadline = DateTime.now().add(timeout);
    _TvPlaybackValue lastValue = controller.value;
    while (DateTime.now().isBefore(deadline)) {
      if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
        throw const _TvPlaybackCanceledException();
      }
      lastValue = controller.value;
      if (lastValue.errorDescription.isNotEmpty) {
        throw StateError(lastValue.errorDescription);
      }
      if (tvPlaybackReplacementHasPromotionProof(
        initialized: lastValue.isInitialized,
        playing: lastValue.isPlaying,
        buffering: lastValue.isBuffering,
        hasSelectedAudioTrack: lastValue.hasSelectedAudioTrack,
        size: lastValue.size,
        startPosition: startPosition,
        currentPosition: lastValue.position,
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    debugPrint(
      'Juicr TV replacement proof timed out '
      'engine=${controller.engine.name} '
      'initialized=${lastValue.isInitialized} playing=${lastValue.isPlaying} '
      'buffering=${lastValue.isBuffering} '
      'audio=${lastValue.hasSelectedAudioTrack ? 'active' : 'missing'} '
      'position=${lastValue.position.inSeconds}s '
      'size=${lastValue.size.width.toStringAsFixed(0)}x'
      '${lastValue.size.height.toStringAsFixed(0)}',
    );
    throw StateError('${controller.engine.name}_replacement_proof');
  }

  Future<void> _ensureAutoplayAfterStartup(
    _TvNativePlaybackController controller,
    int generation,
    int startupAttempt,
  ) async {
    for (var attempt = 0; attempt < 3; attempt += 1) {
      if (!_isPlaybackStartupAttemptActive(generation, startupAttempt)) {
        throw const _TvPlaybackCanceledException();
      }
      final value = controller.value;
      if (!value.isInitialized || value.isPlaying || value.isEnded) return;
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }
    final value = controller.value;
    if (!value.isPlaying && !value.isEnded) {
      debugPrint(
        'Juicr TV autoplay reassertion left controller paused '
        'engine=${controller.engine.name} '
        'initialized=${value.isInitialized} '
        'buffering=${value.isBuffering} '
        'position=${value.position.inSeconds}s',
      );
    }
  }

  Future<void> _openSession(
    int index, {
    required String feedbackLabel,
    List<int>? candidateIndexes,
    int? maxCandidateCount,
    Duration? maxOpenDuration,
    Duration resumePosition = Duration.zero,
    bool restoreOldOnFailure = true,
    bool allowFreshFallback = true,
    _PlaybackSession? retainedSessionOverride,
  }) async {
    if (_sessions.isEmpty) {
      _closePlaybackUnavailable('Playback is unavailable right now.');
      return;
    }
    if (index < 0 || index >= _sessions.length || _switchingSource) return;
    debugPrint(
      'Juicr TV playback open requested '
      'reason=${tvPlaybackOpenReasonBucket(feedbackLabel)} '
      'resume=${resumePosition > Duration.zero ? 'present' : 'zero'} '
      'replacement=${_controller == null ? 'no' : 'yes'}',
    );
    final generation = ++_playbackGeneration;
    _startupAttemptGeneration += 1;
    setState(() {
      _switchingSource = true;
      _controlsVisible = false;
      _loadingStatus = _sourceLoadingStatus(index);
    });
    _backFocusNode.requestFocus();
    final oldController = _controller;
    final retainedTimelineOwnership = _playbackTimelineOwnership;
    if (oldController != null) {
      _timelineTransaction.begin(retainedTimelineOwnership);
    }
    final previousSessionIndex = _sessionIndex;
    final previousSession = retainedSessionOverride ??
        (previousSessionIndex >= 0 && previousSessionIndex < _sessions.length
            ? _sessions[previousSessionIndex]
            : null);
    final previousSessionIdentity = previousSession == null
        ? ''
        : _playbackSessionMergeKey(previousSession);
    int? retainedSessionIndexForRollback() {
      var retainedIndex = tvPlaybackCandidateIndexForIdentity(
        identities:
            _sessions.map(_playbackSessionMergeKey).toList(growable: false),
        identity: previousSessionIdentity,
      );
      if (retainedIndex != null || previousSession == null || !mounted) {
        return retainedIndex;
      }
      final restoredInventory = _mergedFallbackSessions(
        _sessions,
        <_PlaybackSession>[previousSession],
      );
      setState(() => _sessions = restoredInventory);
      retainedIndex = tvPlaybackCandidateIndexForIdentity(
        identities: restoredInventory
            .map(_playbackSessionMergeKey)
            .toList(growable: false),
        identity: previousSessionIdentity,
      );
      return retainedIndex;
    }
    final oldControllerWasPlaying = oldController?.value.isPlaying ?? false;
    final replacementEngineName = tvPlaybackReplacementEngineName(
      feedbackLabel: feedbackLabel,
      retainedEngine: oldController?.engine.name,
    );
    final replacementEngine = switch (replacementEngineName) {
      'media3' => _TvPlaybackEngine.media3,
      'libvlc' => _TvPlaybackEngine.libvlc,
      _ => null,
    };
    final replacementFirstEngine =
        replacementEngine ?? _engineLadderFor(_sessions[index]).first;
    final oldControllerPreReleased = tvPlaybackReplacementRequiresPreRelease(
      retainedEngine: oldController?.engine.name ?? '',
      replacementEngine: replacementFirstEngine.name,
      hasRetainedController: oldController != null,
    );
    if (oldController != null) {
      if (oldControllerPreReleased) {
        await tvReleaseControllerForLibVlcResumeReopen(
          shouldRelease: mounted && identical(_controller, oldController),
          stop: () async {
            try {
              await oldController.stop().timeout(
                    const Duration(milliseconds: 700),
                  );
            } catch (_) {}
          },
          detach: () {
            if (!mounted || !identical(_controller, oldController)) return;
            setState(() => _replaceController(null));
          },
          settle: () async {
            if (mounted) {
              await WidgetsBinding.instance.endOfFrame.timeout(
                const Duration(seconds: 1),
                onTimeout: () {},
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 180));
          },
          dispose: () =>
              oldController.dispose().timeout(const Duration(seconds: 4)),
        );
      } else {
        unawaited(oldController.pause());
      }
    }
    try {
      var selectedIndex = index;
      _TvNativePlaybackController? preparedController;
      int? preparedStartupAttempt;
      Object? lastError;
      final openDeadline =
          maxOpenDuration == null ? null : DateTime.now().add(maxOpenDuration);
      var candidateAttemptsRemaining = tvPlaybackCandidateAttemptBudget(
        requestedMaxCount: maxCandidateCount,
      );
      Future<void> tryCandidates(List<int> candidateIndexes) async {
        for (final candidateIndex in candidateIndexes) {
          if (candidateAttemptsRemaining <= 0) break;
          candidateAttemptsRemaining -= 1;
          final candidateSession = _sessions[candidateIndex];
          final candidateP2p = candidateSession.p2pDescriptor;
          final candidateFirstEngine =
              replacementEngine ?? _engineLadderFor(candidateSession).first;
          var attemptTimeout = candidateP2p != null
              ? tvP2pCandidateStartupBudget(
                  libVlc: candidateFirstEngine == _TvPlaybackEngine.libvlc,
                  qualityLabel: _qualityLabelForSession(candidateSession),
                  trackerCount: candidateP2p.trackerCount,
                )
              : const Duration(seconds: 34);
          if (openDeadline != null) {
            final remaining = openDeadline.difference(DateTime.now());
            if (remaining <= Duration.zero) {
              lastError = TimeoutException('playback_open_budget_exceeded');
              break;
            }
            if (remaining < attemptTimeout) attemptTimeout = remaining;
          }
          _updatePlaybackLoadingStatus(_sourceLoadingStatus(candidateIndex));
          debugPrint(
            'Juicr TV source candidate opening '
            'index=${candidateIndex + 1}/${_sessions.length} '
            '${_safePlaybackSessionFingerprint(_sessions[candidateIndex])}',
          );
          try {
            final startupAttempt = ++_startupAttemptGeneration;
            final startupAttemptFuture = _prepareWithLadder(
              _sessions[candidateIndex],
              generation,
              startupAttempt,
              candidateIndex,
              resumePosition,
              requiredEngine: replacementEngine,
            );
            if (candidateP2p != null) {
              preparedController = await tvAwaitP2pStartupWithRollback(
                startup: startupAttemptFuture,
                timeout: attemptTimeout,
                abandonAfterForStage: (stage) =>
                    tvP2pReadinessAbandonAfter(
                  stage: stage,
                  trackerCount: candidateP2p.trackerCount,
                ),
                readinessStage: () => _p2pPlaybackOwner.readinessStage(
                  tvP2pOwnershipGenerationForStartupAttempt(startupAttempt),
                ),
                rollback: () async {
                  _startupAttemptGeneration += 1;
                  await _p2pPlaybackOwner.rollback(
                    tvP2pOwnershipGenerationForStartupAttempt(startupAttempt),
                  );
                },
              );
            } else {
              preparedController = await startupAttemptFuture.timeout(
                attemptTimeout,
                onTimeout: () {
                  // Timed-out startup futures may still finish later; invalidate
                  // them so stale startup attempts cannot replace live playback.
                  _startupAttemptGeneration += 1;
                  throw TimeoutException('playback_startup_attempt_timed_out');
                },
              );
            }
            if (!_isPlaybackGenerationActive(generation)) {
              await preparedController?.dispose();
              return;
            }
            preparedStartupAttempt = startupAttempt;
            selectedIndex = candidateIndex;
            break;
          } catch (error) {
            if (error is _TvPlaybackCanceledException) rethrow;
            lastError = error;
            _reportRejectedSession(_sessions[candidateIndex]);
            debugPrint(
              'Juicr TV source candidate failed '
              'index=${candidateIndex + 1} errorType=${error.runtimeType} '
              'detail=${_safeTvPlaybackError(error)}',
            );
          }
        }
      }

      final candidates = candidateIndexes ?? _candidateSessionOrder(index);
      final limitedCandidates = tvBoundedPlaybackCandidateOrder(
        candidates,
        maxCount: candidateAttemptsRemaining,
        includeP2pFallback: widget.settings.p2pPlaybackActive,
        isP2p: (candidateIndex) =>
            _sessions[candidateIndex].p2pDescriptor != null,
      );
      await tryCandidates(limitedCandidates);
      if (preparedController == null && allowFreshFallback) {
        final cachedSessionKeys =
            _sessions.map(_playbackSessionMergeKey).toList(growable: false);
        final freshSessions = await _loadFreshFallbackSessions(generation);
        if (freshSessions.isNotEmpty &&
            _isPlaybackGenerationActive(generation)) {
          final merged = _mergedFallbackSessions(
            _sessions,
            oldController != null && previousSession != null
                ? <_PlaybackSession>[previousSession, ...freshSessions]
                : freshSessions,
          );
          final mergedKeys = merged
              .map(_playbackSessionMergeKey)
              .toList(growable: false);
          if (tvPlaybackCandidateInventoryChanged(
            previousIdentities: cachedSessionKeys,
            nextIdentities: mergedKeys,
          )) {
            setState(() => _sessions = merged);
            final freshIndexes = tvFreshFallbackCandidateIndexes(
              mergedKeys: mergedKeys,
              freshKeys: freshSessions
                  .map(_playbackSessionMergeKey)
                  .toList(growable: false),
              cachedKeys: cachedSessionKeys,
            );
            debugPrint(
              'Juicr TV fresh playback fallback plan '
              'received=${freshSessions.length} '
              'retained=${merged.length} '
              'attempts=${freshIndexes.length}',
            );
            if (freshIndexes.isNotEmpty) {
              await tryCandidates(freshIndexes);
            }
          }
        }
      }
      if (preparedController == null) {
        throw lastError ?? const _TvApiException('playback_unavailable');
      }
      final preparedAttempt = preparedStartupAttempt;
      final preparedControllerIsOwned =
          identical(_controller, preparedController) ||
              identical(_stagedController, preparedController);
      if (preparedAttempt == null ||
          !tvPreparedPlaybackCanPublish(
            mounted: mounted,
            capturedGeneration: generation,
            currentGeneration: _playbackGeneration,
            capturedAttempt: preparedAttempt,
            currentAttempt: _startupAttemptGeneration,
            controllerIsOwned: preparedControllerIsOwned,
          )) {
        await preparedController?.dispose();
        _applyPlaybackTimelineOwnership(
          _timelineTransaction.settle(
            current: _playbackTimelineOwnership,
            promoted: false,
          ),
        );
        return;
      }
      final preparedWasStaged =
          identical(_stagedController, preparedController);
      setState(() {
        if (_timelineTransaction.active) {
          _applyPlaybackTimelineOwnership(
            _timelineTransaction.settle(
              current: _playbackTimelineOwnership,
              promoted: true,
            ),
          );
        }
        if (preparedWasStaged) {
          _replaceStagedController(null);
          _replaceController(preparedController);
        }
        _sessionIndex = selectedIndex;
        _switchingSource = false;
        _autoNextQueued = false;
        _controlsVisible = false;
      });
      if (oldController != null &&
          !identical(oldController, preparedController)) {
        await tvDisposePlaybackResources(
          <Future<void> Function()>[
            () => WidgetsBinding.instance.endOfFrame.timeout(
                  const Duration(seconds: 1),
                  onTimeout: () {},
                ),
            oldController.dispose,
          ],
          onCleanupIssue: (issue) => debugPrint(
            'Juicr TV retained playback cleanup incomplete '
            'issueType=${issue.runtimeType}',
          ),
        );
      }
    } catch (error) {
      _applyPlaybackTimelineOwnership(
        _timelineTransaction.settle(
          current: _playbackTimelineOwnership,
          promoted: false,
        ),
      );
      if (error is _TvPlaybackCanceledException ||
          !_isPlaybackGenerationActive(generation)) {
        return;
      }
      final abandonedController = _stagedController;
      if (abandonedController != null) {
        setState(() => _replaceStagedController(null));
        unawaited(abandonedController.dispose());
      }
      final message = _friendlyPlaybackError(error);
      if (oldController == null || !restoreOldOnFailure) {
        _closePlaybackUnavailable(message);
        return;
      }
      final retainedValue = oldController.value;
      if (oldControllerPreReleased ||
          tvFailedReplacementRequiresSessionReopen(
            engine: oldController.engine.name,
            retainedInitialized: retainedValue.isInitialized,
            errorDescription: retainedValue.errorDescription,
            retainedMounted: identical(_controller, oldController),
          )) {
        setState(() {
          _switchingSource = false;
          _replaceController(null);
        });
        if (!oldControllerPreReleased) {
          await oldController.dispose();
        }
        debugPrint(
          'Juicr TV source rollback reopening retained session '
          'engine=${oldController.engine.name}',
        );
        final rollbackIndex = retainedSessionIndexForRollback();
        if (rollbackIndex == null) {
          _closePlaybackUnavailable('Playback is unavailable right now.');
          return;
        }
        await _openSession(
          rollbackIndex,
          feedbackLabel: 'Previous source',
          maxCandidateCount: 1,
          maxOpenDuration: const Duration(seconds: 20),
          resumePosition: resumePosition,
          restoreOldOnFailure: false,
          allowFreshFallback: false,
        );
        final restoredController = _controller;
        if (!oldControllerWasPlaying &&
            mounted &&
            restoredController != null &&
            restoredController.value.isInitialized &&
            restoredController.value.isPlaying) {
          await restoredController.pause();
        }
        if (mounted && restoredController?.value.isInitialized == true) {
          _showPlayerToast(message);
        }
        return;
      }
      final retainedIndex = retainedSessionIndexForRollback();
      if (retainedIndex == null) {
        _closePlaybackUnavailable('Playback is unavailable right now.');
        return;
      }
      setState(() {
        _switchingSource = false;
        _replaceController(oldController);
        _sessionIndex = retainedIndex;
      });
      final resumed = await tvRestorePlaybackAfterFailedReplacement(
        wasPlaying: oldControllerWasPlaying,
        resume: oldController.play,
      );
      debugPrint(
        'Juicr TV source rollback settled '
        'resumeRequested=$oldControllerWasPlaying resumed=$resumed',
      );
      _showPlayerToast(message);
    }
  }

  List<int> _candidateSessionOrder(int requestedIndex) {
    if (_sessions.isEmpty) return const <int>[];
    final start = requestedIndex.clamp(0, _sessions.length - 1).toInt();
    return [
      for (var offset = 0; offset < _sessions.length; offset += 1)
        (start + offset) % _sessions.length,
    ];
  }

  Future<void> _switchToSource(
    int index, {
    List<int>? candidateIndexes,
  }) async {
    if (index == _sessionIndex ||
        index < 0 ||
        index >= _sessions.length ||
        _switchingSource) {
      return;
    }
    final progress = _currentProgress();
    debugPrint(
      'Juicr TV source replacement anchor '
      'position=${progress.position.inSeconds}s '
      'timelineOffset=${_libVlcContinuousTsTimelineOffset.inSeconds}s '
      'displayOffset=${_playbackDisplayTimelineOffset.inSeconds}s',
    );
    final previousValue = _controller?.value ?? _TvPlaybackValue.empty;
    final wasPaused =
        previousValue.isInitialized && previousValue.isPlaying != true;
    await _openSession(
      index,
      feedbackLabel: 'Source ${index + 1}',
      candidateIndexes: candidateIndexes,
      maxCandidateCount:
          candidateIndexes?.length ?? tvPlaybackReplacementCandidateLimit,
      maxOpenDuration: tvPlaybackReplacementOpenBudget,
      resumePosition: progress.position,
      allowFreshFallback: false,
    );
    final nextController = _controller;
    if (wasPaused &&
        mounted &&
        nextController != null &&
        nextController.value.isInitialized &&
        nextController.value.isPlaying) {
      await nextController.pause();
    }
  }

  Future<void> _openNextEpisode() async {
    final target = _nextEpisodeMetadata();
    if (target == null || !_hasNextEpisodeMetadata || _switchingSource) {
      _showPlayerToast('Next episode metadata is not ready.');
      return;
    }
    await _openEpisode(target);
  }

  Future<bool> _openEpisode(_TvEpisode target) async {
    if (_switchingSource) return false;
    if (target.season == _season && target.episode == _episode) return true;
    final generation = ++_playbackGeneration;
    _startupAttemptGeneration += 1;
    final oldController = _controller;
    final oldControllerWasPlaying = oldController?.value.isPlaying == true;
    final retainedTimelineOwnership = _playbackTimelineOwnership;
    if (oldController?.value.isInitialized == true) {
      _timelineTransaction.begin(retainedTimelineOwnership);
    }
    try {
      if (!mounted || !_isPlaybackGenerationActive(generation)) {
        if (_timelineTransaction.active) {
          _applyPlaybackTimelineOwnership(
            _timelineTransaction.settle(
              current: _playbackTimelineOwnership,
              promoted: false,
            ),
          );
        }
        return false;
      }
      setState(() {
        _switchingSource = true;
        _controlsVisible = false;
        _loadingStatus = 'Preparing episode ${target.episode}...';
      });
      _backFocusNode.requestFocus();
      final prepareEpisode = widget.lifecycleHarness?.prepareEpisode;
      if (prepareEpisode != null) {
        final prepared = await prepareEpisode(target.season, target.episode);
        if (!prepared || !_isPlaybackGenerationActive(generation)) {
          return false;
        }
        setState(() {
          _season = target.season;
          _episode = target.episode;
          _switchingSource = false;
          _controlsVisible = false;
        });
        widget.lifecycleHarness?.recordEpisodePromotion(
          season: target.season,
          episode: target.episode,
        );
        return true;
      }
      final sessions = await _api
          .playbackSessions(
            widget.item,
            settings: widget.settings,
            season: target.season,
            episode: target.episode,
          )
          .timeout(const Duration(seconds: 75));
      if (!_isPlaybackGenerationActive(generation)) {
        throw const _TvPlaybackCanceledException();
      }
      _TvNativePlaybackController? controller;
      int? preparedStartupAttempt;
      Object? lastError;
      var selectedIndex = 0;
      var candidateAttemptsRemaining = tvPlaybackCandidateAttemptBudget();
      for (var candidateIndex = 0;
          candidateIndex < sessions.length && candidateAttemptsRemaining > 0;
          candidateIndex += 1) {
        candidateAttemptsRemaining -= 1;
        _updatePlaybackLoadingStatus(
          sessions.length <= 1
              ? 'Preparing episode ${target.episode}...'
              : 'Preparing episode ${target.episode} source ${candidateIndex + 1}/${sessions.length}...',
        );
        try {
          final startupAttempt = ++_startupAttemptGeneration;
          final startupAttemptFuture = _prepareWithLadder(
            sessions[candidateIndex],
            generation,
            startupAttempt,
            candidateIndex,
            Duration.zero,
          );
          if (sessions[candidateIndex].p2pDescriptor != null) {
            final candidateSession = sessions[candidateIndex];
            final candidateP2p = candidateSession.p2pDescriptor!;
            final candidateFirstEngine =
                _engineLadderFor(candidateSession).first;
            controller = await tvAwaitP2pStartupWithRollback(
              startup: startupAttemptFuture,
              timeout: tvP2pCandidateStartupBudget(
                libVlc: candidateFirstEngine == _TvPlaybackEngine.libvlc,
                qualityLabel: _qualityLabelForSession(candidateSession),
                trackerCount: candidateP2p.trackerCount,
              ),
              abandonAfterForStage: (stage) =>
                  tvP2pReadinessAbandonAfter(
                stage: stage,
                trackerCount: candidateP2p.trackerCount,
              ),
              readinessStage: () => _p2pPlaybackOwner.readinessStage(
                tvP2pOwnershipGenerationForStartupAttempt(startupAttempt),
              ),
              rollback: () async {
                _startupAttemptGeneration += 1;
                await _p2pPlaybackOwner.rollback(
                  tvP2pOwnershipGenerationForStartupAttempt(startupAttempt),
                );
              },
            );
          } else {
            controller = await startupAttemptFuture.timeout(
              const Duration(seconds: 34),
              onTimeout: () {
                // Timed-out startup futures may still finish later; invalidate
                // them so stale startup attempts cannot replace live playback.
                _startupAttemptGeneration += 1;
                throw TimeoutException('playback_startup_attempt_timed_out');
              },
            );
          }
          preparedStartupAttempt = startupAttempt;
          selectedIndex = candidateIndex;
          break;
        } catch (error) {
          if (error is _TvPlaybackCanceledException) rethrow;
          lastError = error;
          debugPrint(
            'Juicr TV next episode source candidate failed '
            'index=${candidateIndex + 1} errorType=${error.runtimeType} '
            'detail=${_safeTvPlaybackError(error)}',
          );
        }
      }
      final preparedController = controller;
      if (preparedController == null) {
        throw lastError ?? const _TvApiException('playback_unavailable');
      }
      final preparedAttempt = preparedStartupAttempt;
      var promoted = false;
      if (preparedAttempt != null &&
          mounted &&
          _isPlaybackGenerationActive(generation)) {
        setState(() {
          promoted = tvPromotePreparedPlaybackController(
            mounted: mounted,
            capturedGeneration: generation,
            currentGeneration: _playbackGeneration,
            capturedAttempt: preparedAttempt,
            currentAttempt: _startupAttemptGeneration,
            preparedController: preparedController,
            currentController: _controller,
            stagedController: _stagedController,
            replaceCurrent: _replaceController,
            replaceStaged: _replaceStagedController,
          );
          if (promoted && _timelineTransaction.active) {
            _applyPlaybackTimelineOwnership(
              _timelineTransaction.settle(
                current: _playbackTimelineOwnership,
                promoted: true,
              ),
            );
          }
        });
      }
      if (!promoted) {
        if (_timelineTransaction.active) {
          _applyPlaybackTimelineOwnership(
            _timelineTransaction.settle(
              current: _playbackTimelineOwnership,
              promoted: false,
            ),
          );
        }
        await preparedController.dispose();
        return false;
      }
      _season = target.season;
      _episode = target.episode;
      _credibleWatchedDuration = Duration.zero;
      _resetSubtitlesForEpisodeTransition(sessions);
      setState(() {
        _resetSkipSegmentsForCurrentEpisode();
        _sessions = sessions;
        _sessionIndex = selectedIndex;
        _switchingSource = false;
        _autoNextQueued = false;
        _controlsVisible = false;
      });
      if (oldController != null &&
          !identical(oldController, preparedController)) {
        await oldController.dispose();
      }
      return true;
    } catch (error) {
      if (_timelineTransaction.active) {
        _applyPlaybackTimelineOwnership(
          _timelineTransaction.settle(
            current: _playbackTimelineOwnership,
            promoted: false,
          ),
        );
      }
      if (error is _TvPlaybackCanceledException ||
          !_isPlaybackGenerationActive(generation)) {
        return false;
      }
      setState(() {
        _switchingSource = false;
        _replaceController(oldController);
      });
      if (oldController != null) {
        await tvRestorePlaybackAfterFailedReplacement(
          wasPlaying: oldControllerWasPlaying,
          resume: oldController.play,
        );
      }
      _showPlayerToast(_friendlyPlaybackError(error));
      return false;
    }
  }

  void _resetSubtitlesForEpisodeTransition(
    List<_PlaybackSession> sessions,
  ) {
    _subtitleLoadGeneration += 1;
    _subtitleLookupFuture = null;
    _subtitlesLoading = false;
    _subtitlesLoaded = false;
    _subtitleCues = const <_TvSubtitleCue>[];
    _subtitles = _subtitlesFromPlaybackSessions(sessions);
    _subtitleIndex = -1;
    _captionsEnabled = widget.settings.subtitles;
    if (_subtitles.isNotEmpty || widget.settings.hasSubtitleSource) {
      unawaited(_loadPlaybackSubtitles());
    }
  }

  List<_TvSubtitle> _subtitlesFromPlaybackSessions(
    List<_PlaybackSession> sessions,
  ) {
    final seen = <String>{};
    final subtitles = <_TvSubtitle>[];
    for (final session in sessions) {
      for (final subtitle in session.subtitles) {
        final key = subtitle.id.trim().isNotEmpty
            ? subtitle.id.trim()
            : '${subtitle.url}|${subtitle.language}|${subtitle.label}';
        if (subtitle.url.isEmpty || !seen.add(key)) continue;
        subtitles.add(subtitle);
      }
    }
    return subtitles.toList(growable: false);
  }

  void _maybeAutoNextEpisode(_TvPlaybackValue value) {
    if (!_autoplayNextEpisode ||
        !_hasNextEpisodeMetadata ||
        _autoNextQueued ||
        _switchingSource ||
        !value.isInitialized ||
        value.duration <= Duration.zero) {
      return;
    }
    final remaining = value.duration - value.position;
    if (remaining > const Duration(seconds: 6)) return;
    _autoNextQueued = true;
    unawaited(_openNextEpisode());
  }

  List<_TvSubtitle> _selectedSubtitlesForPlayback() {
    if (!_captionsEnabled ||
        _subtitleIndex < 0 ||
        _subtitleIndex >= _subtitles.length) {
      return const <_TvSubtitle>[];
    }
    return <_TvSubtitle>[_subtitles[_subtitleIndex]];
  }

  Future<List<_PlaybackSession>> _loadFreshFallbackSessions(
    int generation,
  ) async {
    final resolver = widget.resolveFreshSessions;
    if (resolver == null || !_isPlaybackGenerationActive(generation)) {
      return const <_PlaybackSession>[];
    }
    _updatePlaybackLoadingStatus('Refreshing playback sources...');
    try {
      final sessions = await resolver(
        Set<String>.unmodifiable(_rejectedSessionKeysForRoute),
      ).timeout(const Duration(seconds: 45));
      if (!_isPlaybackGenerationActive(generation)) {
        return const <_PlaybackSession>[];
      }
      final usable = sessions
          .where((session) => session.mediaUrl.trim().isNotEmpty)
          .toList(growable: false);
      debugPrint(
        'Juicr TV fresh playback fallback loaded count=${usable.length} '
        'first=${usable.isEmpty ? 'none' : _safePlaybackSessionFingerprint(usable.first)}',
      );
      return usable;
    } catch (error) {
      debugPrint(
        'Juicr TV fresh playback fallback failed '
        'errorType=${error.runtimeType} detail=${_safeTvPlaybackError(error)}',
      );
      return const <_PlaybackSession>[];
    }
  }

  List<_PlaybackSession> _mergedFallbackSessions(
    List<_PlaybackSession> cached,
    List<_PlaybackSession> fresh,
  ) {
    return tvBoundedRetainedCandidateMerge(
      fresh: fresh.where((session) => session.mediaUrl.trim().isNotEmpty).toList(
            growable: false,
          ),
      cached: cached.where((session) => session.mediaUrl.trim().isNotEmpty).toList(
            growable: false,
          ),
      identityOf: _playbackSessionMergeKey,
      isAddOn: (session) =>
          tvPlaybackCandidateFamilyFromWire(session.sourceFamily) ==
          TvPlaybackCandidateFamily.addOn,
      isFallback: (session) =>
          tvPlaybackCandidateFamilyFromWire(session.sourceFamily) ==
          TvPlaybackCandidateFamily.fallback,
    );
  }

  String _playbackSessionMergeKey(_PlaybackSession session) =>
      tvPlaybackCandidateIdentityIsSafe(session.candidateId)
          ? session.candidateId
          : '';

  String _playbackSessionRouteRejectionKey(_PlaybackSession session) {
    final candidateId = _playbackSessionMergeKey(session);
    if (candidateId.isNotEmpty) return candidateId;
    final p2p = session.p2pDescriptor;
    return p2p == null ? '' : tvP2pRouteIdentityKey(p2p);
  }

  Future<_PlaybackSession?> _freshPlaybackSessionForCurrentEpisode({
    required int sessionIndex,
    required int generation,
  }) async {
    if (sessionIndex < 0 || sessionIndex >= _sessions.length) {
      return null;
    }
    final freshSessions = await _loadFreshFallbackSessions(generation);
    if (freshSessions.isEmpty || !_isPlaybackGenerationActive(generation)) {
      return null;
    }
    final current = _sessions[sessionIndex];
    final refreshed = freshSessions.firstWhere(
      (session) =>
          current.providerId.trim().isNotEmpty &&
          session.providerId.trim().toLowerCase() ==
              current.providerId.trim().toLowerCase(),
      orElse: () => freshSessions.first,
    );
    if (refreshed.mediaUrl.trim().isEmpty) return null;
    debugPrint(
      'Juicr TV refreshed current playback session '
      'index=${sessionIndex + 1}/${_sessions.length} '
      'before=${_safePlaybackSessionFingerprint(current)} '
      'after=${_safePlaybackSessionFingerprint(refreshed)}',
    );
    if (mounted && _isPlaybackGenerationActive(generation)) {
      final merged = _mergedFallbackSessions(
        _sessions,
        <_PlaybackSession>[refreshed, ...freshSessions],
      );
      setState(() => _sessions = merged);
    }
    return refreshed;
  }

  _TvSubtitle? _selectedSubtitle() {
    if (!_captionsEnabled ||
        _subtitleIndex < 0 ||
        _subtitleIndex >= _subtitles.length) {
      return null;
    }
    return _subtitles[_subtitleIndex];
  }

  Future<void> _loadPlaybackSubtitles({bool activateFirst = true}) async {
    final canUseSubtitles = widget.settings.hasSubtitleSource;
    if (_isLiveTvPlayback || _subtitlesLoaded || !canUseSubtitles) {
      debugPrint(
        'Juicr TV subtitle load skipped '
        'live=$_isLiveTvPlayback loaded=$_subtitlesLoaded '
        'loading=$_subtitlesLoading enabled=${widget.settings.subtitles} '
        'source=$canUseSubtitles seed=${_subtitles.length}',
      );
      return;
    }
    if (_subtitlesLoading) {
      debugPrint(
        'Juicr TV subtitle load joined pending seed=${_subtitles.length}',
      );
      final pending = _subtitleLookupFuture;
      if (pending != null) await pending;
      return;
    }
    final resolver = widget.resolveSubtitles;
    if (resolver == null) {
      debugPrint('Juicr TV subtitle load skipped resolver=missing');
      return;
    }
    debugPrint(
      'Juicr TV subtitle load start '
      'seed=${_subtitles.length} index=$_subtitleIndex',
    );
    final season = _season;
    final episode = _episode;
    final lookupFuture = () async {
      _subtitlesLoading = true;
      try {
        final resolved = await resolver(
          _season,
          _episode,
        ).timeout(const Duration(seconds: 16));
        if (!tvSubtitleLookupResultIsCurrent(
          mounted: mounted,
          capturedSeason: season,
          currentSeason: _season,
          capturedEpisode: episode,
          currentEpisode: _episode,
        )) {
          return;
        }
        final subtitles = _mergePlaybackSubtitles(_subtitles, resolved);
        debugPrint(
          'Juicr TV subtitle load result '
          'seed=${_subtitles.length} resolved=${resolved.length} '
          'merged=${subtitles.length}',
        );
        setState(() {
          _subtitles = subtitles;
          _subtitlesLoaded = subtitles.isNotEmpty;
          final preferredSubtitleId = widget.subtitleId?.trim();
          final preferredIndex =
              preferredSubtitleId == null || preferredSubtitleId.isEmpty
                  ? -1
                  : subtitles.indexWhere(
                      (subtitle) => subtitle.id == preferredSubtitleId,
                    );
          if (preferredIndex >= 0) {
            _subtitleIndex = preferredIndex;
            _captionsEnabled = true;
          } else if (activateFirst &&
              _subtitleIndex < 0 &&
              subtitles.isNotEmpty) {
            _subtitleIndex = 0;
            _captionsEnabled = true;
          } else if (_subtitleIndex >= subtitles.length) {
            _subtitleIndex = subtitles.isEmpty ? -1 : 0;
            _captionsEnabled = subtitles.isNotEmpty;
          }
        });
        if (_captionsEnabled && _subtitles.isNotEmpty) {
          await _loadSelectedSubtitleCues();
        }
      } catch (error) {
        debugPrint(
          'Juicr TV subtitle lookup skipped '
          'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
        );
        if (tvSubtitleLookupResultIsCurrent(
          mounted: mounted,
          capturedSeason: season,
          currentSeason: _season,
          capturedEpisode: episode,
          currentEpisode: _episode,
        )) {
          setState(() {
            _subtitlesLoaded = _subtitles.isNotEmpty;
          });
        }
      } finally {
        if (tvSubtitleLookupResultIsCurrent(
          mounted: mounted,
          capturedSeason: season,
          currentSeason: _season,
          capturedEpisode: episode,
          currentEpisode: _episode,
        )) {
          _subtitlesLoading = false;
          _subtitleLookupFuture = null;
        }
      }
    }();
    _subtitleLookupFuture = lookupFuture;
    await lookupFuture;
  }

  List<_TvSubtitle> _mergePlaybackSubtitles(
    List<_TvSubtitle> seeded,
    List<_TvSubtitle> resolved,
  ) {
    final seen = <String>{};
    final merged = <_TvSubtitle>[];
    for (final subtitle in [...seeded, ...resolved]) {
      final key = subtitle.id.trim().isNotEmpty
          ? subtitle.id.trim()
          : '${subtitle.url}|${subtitle.language}|${subtitle.label}';
      if (!seen.add(key)) continue;
      merged.add(subtitle);
    }
    return merged;
  }

  Future<void> _loadSelectedSubtitleCues({bool allowFallback = true}) async {
    final generation = ++_subtitleLoadGeneration;
    final subtitle = _selectedSubtitle();
    if (subtitle == null) {
      if (mounted) setState(() => _subtitleCues = const <_TvSubtitleCue>[]);
      return;
    }
    var loaded = (cues: const <_TvSubtitleCue>[], failed: false);
    var loadedIndex = _subtitleIndex;
    final indexes = allowFallback
        ? <int>[
            _subtitleIndex,
            for (var index = 0; index < _subtitles.length; index++)
              if (index != _subtitleIndex) index,
          ]
        : <int>[_subtitleIndex];
    for (final index in indexes) {
      final candidate = await _loadSubtitleCueCandidate(
        _subtitles[index],
      );
      loaded = candidate;
      if (candidate.cues.isEmpty) continue;
      loadedIndex = index;
      break;
    }
    if (!mounted || generation != _subtitleLoadGeneration) return;
    setState(() {
      _subtitleCues = loaded.cues;
      if (allowFallback && loaded.cues.isNotEmpty) {
        _subtitleIndex = loadedIndex;
      }
    });
    if (loaded.cues.isEmpty) {
      _showPlayerToast(
        loaded.failed
            ? 'Subtitle could not be loaded.'
            : 'Subtitle could not be read on this TV.',
      );
    }
  }

  Future<({List<_TvSubtitleCue> cues, bool failed})> _loadSubtitleCueCandidate(
    _TvSubtitle subtitle,
  ) async {
    try {
      final text = await _api.subtitleText(subtitle);
      final cues = _parseTvSubtitleCues(text);
      debugPrint(
        'Juicr TV subtitle parse '
        'format=${subtitle.format.trim().isEmpty ? 'unknown' : subtitle.format.trim().toLowerCase()} '
        'language=${subtitle.language.trim().isEmpty ? 'unknown' : 'present'} '
        'content=${_tvSubtitleContentBucket(text)} '
        'chars=${text.length} cues=${cues.length}',
      );
      return (cues: cues, failed: false);
    } catch (error) {
      debugPrint(
        'Juicr TV subtitle candidate skipped '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return (cues: const <_TvSubtitleCue>[], failed: true);
    }
  }

  String? _activeSubtitleText(_TvPlaybackValue value) {
    if (!_captionsEnabled ||
        _subtitleCues.isEmpty ||
        !value.isInitialized ||
        value.position <= Duration.zero) {
      return null;
    }
    final position =
        value.position + Duration(milliseconds: _subtitleDelayMillis);
    for (final cue in _subtitleCues) {
      if (position >= cue.start && position <= cue.end) return cue.text;
    }
    return null;
  }

  String _qualityLabelForSession(_PlaybackSession session) {
    return tvPlaybackDisplayQuality(session.quality);
  }

  List<String> _availableQualityLabels() {
    return tvPlaybackAvailableQualityLabels([
      for (final session in _sessions) session.quality,
    ]);
  }

  List<_TvPlaybackSourceGroup> _sourceGroups() {
    return [
      for (final group in groupTvPlaybackSources([
        for (var index = 0; index < _sessions.length; index++)
          TvPlaybackSourceGroupEntry(
            sessionIndex: index,
            quality: _qualityLabelForSession(_sessions[index]),
            mirrorGroupId: _sessions[index].mirrorGroupId,
            mirrorRank: _sessions[index].mirrorRank,
            sourcePoolVersion: _sessions[index].sourcePoolVersion,
          ),
      ]))
        _TvPlaybackSourceGroup(
          quality: group.quality,
          sessionIndexes: group.sessionIndexes,
        ),
    ];
  }

  Future<void> _showSourcesPanel() async {
    if (_locked) return;
    _showControls();
    if (_sessions.length < 2) {
      _showPlayerToast('Only one TV source is ready for this title.');
      return;
    }
    _prepareForOptionDialog();
    final allGroups = _sourceGroups();
    final groups = allGroups.any((group) => group.quality != 'Auto')
        ? allGroups.where((group) => group.quality != 'Auto').toList()
        : allGroups;
    int? pendingSourceIndex;
    var sourceParentDialogOpen = false;
    final sourceFocusNodes = [
      for (var index = 0; index < groups.length; index++)
        FocusNode(debugLabel: 'tv-playback-source-group-$index'),
    ];
    final sourceDialogFocusNode = FocusNode(
      debugLabel: 'tv-playback-sources-dialog',
    );
    var lastSourceFocusIndex = groups.indexWhere(
      (group) => group.contains(_sessionIndex),
    );
    if (lastSourceFocusIndex < 0) lastSourceFocusIndex = 0;
    var sourceFocusRestoreQueued = false;

    void focusSource(int index) {
      if (index < 0 || index >= sourceFocusNodes.length) return;
      lastSourceFocusIndex = index;
      sourceFocusNodes[index].requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = sourceFocusNodes[index].context;
        if (!mounted || context == null || !context.mounted) return;
        Scrollable.ensureVisible(
          context,
          duration: _tvDuration(140),
          curve: Curves.easeOutCubic,
          alignment: 0.42,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      });
    }

    void restoreSourceFocus([int attempt = 0]) {
      if (sourceFocusRestoreQueued && attempt == 0) return;
      if (attempt == 0) sourceFocusRestoreQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (attempt == 0) sourceFocusRestoreQueued = false;
        if (!mounted) return;
        final focusInsideSources = sourceFocusNodes.any(
          (node) => node.hasFocus,
        );
        if (focusInsideSources) return;
        focusSource(lastSourceFocusIndex);
        if (attempt < 8) restoreSourceFocus(attempt + 1);
      });
    }

    bool isTvBackKey(LogicalKeyboardKey key) {
      return key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.browserBack;
    }

    KeyEventResult handleSourceDialogKey(LogicalKeyboardKey key) {
      if (isTvBackKey(key)) {
        final navigator =
            _activePlaybackDialogNavigator ?? Navigator.of(context);
        _popPlaybackDialog(navigator, 'sources-key');
        return KeyEventResult.handled;
      }
      final focusedIndex = sourceFocusNodes.indexWhere((node) => node.hasFocus);
      final currentIndex = focusedIndex >= 0
          ? focusedIndex
          : lastSourceFocusIndex.clamp(0, sourceFocusNodes.length - 1).toInt();
      if (key == LogicalKeyboardKey.arrowUp) {
        focusSource(currentIndex <= 0 ? 0 : currentIndex - 1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        focusSource(
          currentIndex >= sourceFocusNodes.length - 1
              ? sourceFocusNodes.length - 1
              : currentIndex + 1,
        );
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        focusSource(currentIndex);
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) &&
          focusedIndex < 0) {
        focusSource(currentIndex);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    Future<T?> runSourceChild<T>(
      int index,
      Future<T?> Function() action,
      StateSetter setDialogState,
    ) async {
      try {
        return await action();
      } finally {
        _suppressPlaybackBackBriefly();
        if (mounted && sourceParentDialogOpen) {
          setDialogState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && sourceParentDialogOpen) focusSource(index);
          });
        }
      }
    }

    try {
      sourceParentDialogOpen = true;
      await _showPlaybackDialog<void>(
        builder: (dialogContext) {
          final dialogNavigator = _playbackDialogNavigator(dialogContext);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              restoreSourceFocus();
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (didPop) return;
                  if (_shouldIgnoreNestedPlaybackDialogPop('sources-parent')) {
                    return;
                  }
                  // Guarded replacement for dialogNavigator.pop();
                  _popPlaybackDialog(dialogNavigator, 'sources-parent');
                },
                child: Focus(
                  focusNode: sourceDialogFocusNode,
                  canRequestFocus: false,
                  skipTraversal: true,
                  descendantsAreFocusable: true,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    return handleSourceDialogKey(event.logicalKey);
                  },
                  child: Dialog(
                    backgroundColor: Colors.transparent,
                    child: Container(
                      width: 284,
                      constraints: const BoxConstraints(maxHeight: 560),
                      padding: const EdgeInsets.all(_tvSpacing),
                      decoration: BoxDecoration(
                        color: const Color(0xEE202124),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0x24FFFFFF)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: _tvSpacing),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sources',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: _tvSpacing),
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var index = 0;
                                        index < groups.length;
                                        index++)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: _TvSourceGroupButton(
                                          focusNode: sourceFocusNodes[index],
                                          icon: groups[index]
                                                  .contains(_sessionIndex)
                                              ? Icons.check_circle_rounded
                                              : Icons.video_library_rounded,
                                          title: groups[index].label,
                                          subtitle: groups[index]
                                                  .contains(_sessionIndex)
                                              ? 'Current quality'
                                              : 'Open mirrors',
                                          selected: groups[index]
                                              .contains(_sessionIndex),
                                          autofocus:
                                              index == lastSourceFocusIndex,
                                          enabled: !_switchingSource,
                                          animateIcon: _switchingSource &&
                                              !groups[index]
                                                  .contains(_sessionIndex),
                                          minHeight: 44,
                                          horizontalPadding: 14,
                                          verticalPadding: 10,
                                          iconSize: 20,
                                          fontSize: 14,
                                          onArrowUp: index == 0
                                              ? () => focusSource(index)
                                              : () => focusSource(index - 1),
                                          onArrowDown: index ==
                                                  groups.length - 1
                                              ? () => focusSource(index)
                                              : () => focusSource(index + 1),
                                          onArrowLeft: () => focusSource(index),
                                          onArrowRight: () =>
                                              focusSource(index),
                                          onPressed: () {
                                            if (groups[index]
                                                    .sessionIndexes
                                                    .length >
                                                1) {
                                              unawaited(
                                                runSourceChild<int?>(
                                                  index,
                                                  () => _showSourceMirrorPicker(
                                                    groups[index],
                                                  ),
                                                  setDialogState,
                                                ).then((mirrorIndex) async {
                                                  if (mirrorIndex == null) {
                                                    return;
                                                  }
                                                  final closeDelay =
                                                      tvPlaybackNestedDialogParentCloseDelay(
                                                    childClosedAt:
                                                        _lastPlaybackDialogClosedAt,
                                                    now: DateTime.now(),
                                                  );
                                                  if (closeDelay >
                                                      Duration.zero) {
                                                    await Future<void>.delayed(
                                                      closeDelay,
                                                    );
                                                  }
                                                  pendingSourceIndex =
                                                      mirrorIndex;
                                                  if (!mounted ||
                                                      !sourceParentDialogOpen) {
                                                    return;
                                                  }
                                                  if (dialogNavigator
                                                      .canPop()) {
                                                    _popPlaybackDialog(
                                                      dialogNavigator,
                                                      'sources-mirror-select',
                                                    );
                                                  }
                                                }),
                                              );
                                              return;
                                            }
                                            pendingSourceIndex = groups[index]
                                                .sessionIndexes
                                                .first;
                                            _popPlaybackDialog(
                                              dialogNavigator,
                                              'sources-select',
                                            );
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      sourceParentDialogOpen = false;
      await _settlePlaybackDialogFocusBeforeDispose(
        [sourceDialogFocusNode, ...sourceFocusNodes],
        restoreFocusNode: _sourcesFocusNode,
      );
      sourceDialogFocusNode.dispose();
      for (final node in sourceFocusNodes) {
        node.dispose();
      }
    }
    if (!mounted) return;
    if (pendingSourceIndex != null) {
      await _switchToSource(pendingSourceIndex!);
    }
    _showControls();
    _sourcesFocusNode.requestFocus();
  }

  Future<int?> _showSourceMirrorPicker(_TvPlaybackSourceGroup group) async {
    final selected = await _showPlaybackDialog<String>(
      builder: (context) => _TvPlaybackChoiceDialog(
        title: '${group.quality} mirrors',
        selected: _sessionIndex.toString(),
        onBack: (dialogContext) => _popPlaybackDialog(
          _playbackDialogNavigator(dialogContext),
          'source-mirror-choice',
        ),
        choices: [
          for (var mirror = 0; mirror < group.sessionIndexes.length; mirror++)
            _TvPlaybackChoice(
              'Mirror ${mirror + 1}/${group.sessionIndexes.length}',
              Icons.video_library_rounded,
              value: group.sessionIndexes[mirror].toString(),
              subtitle: _sourceMirrorSubtitle(group.sessionIndexes[mirror]),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return null;
    final index = int.tryParse(selected);
    if (index == null) return null;
    return index;
  }

  String _sourceMirrorSubtitle(int sessionIndex) {
    if (sessionIndex < 0 || sessionIndex >= _sessions.length) {
      return 'Audio: Not tagged';
    }
    final session = _sessions[sessionIndex];
    final parts = <String>[
      'Audio: Not tagged',
      _qualityLabelForSession(session),
    ];
    final type =
        _sourceTypeDisplayLabel(session.sourceType, session.tvMediaUrl);
    if (type.isNotEmpty) parts.add(type);
    final sourceClass = _sourceClassDisplayLabel(session.sourceClass);
    if (sourceClass.isNotEmpty) parts.add(sourceClass);
    return parts.join(' - ');
  }

  String _sourceTypeDisplayLabel(String sourceType, String mediaUrl) {
    final type = sourceType.trim().toLowerCase();
    final url = mediaUrl.toLowerCase();
    if (type.contains('mpegurl') ||
        type.contains('m3u8') ||
        type.contains('hls') ||
        url.contains('.m3u8')) {
      return 'HLS';
    }
    if (type.contains('dash') || type.contains('mpd') || url.contains('.mpd')) {
      return 'DASH';
    }
    if (type.contains('mp4') ||
        type.contains('video') ||
        url.contains('.mp4')) {
      return 'Direct video';
    }
    return type.isEmpty ? '' : type.toUpperCase();
  }

  String _sourceClassDisplayLabel(String sourceClass) {
    final value = sourceClass.trim().toLowerCase();
    if (value.isEmpty) return '';
    if (value == 'direct') return 'Direct';
    if (value == 'debrid') return 'Account';
    if (value == 'p2p') return 'P2P';
    return value.toUpperCase();
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.setPlaybackSpeed(speed);
    setState(() {
      _playbackSpeed = speed;
      _controlsVisible = true;
    });
    _showFeedback(Icons.speed_rounded, '${speed.toStringAsFixed(2)}x');
  }

  Future<void> _refreshStream() async {
    final resumePosition = _currentProgress().position;
    debugPrint(
      'Juicr TV refresh stream requested '
      'source=settings position=${resumePosition.inSeconds}s',
    );
    final generation = ++_playbackGeneration;
    final sessionIndex = _sessionIndex;
    if (sessionIndex < 0 || sessionIndex >= _sessions.length) return;
    final retainedSession = _sessions[sessionIndex];
    final retainedIdentity = _playbackSessionMergeKey(retainedSession);
    final refreshed = await _freshPlaybackSessionForCurrentEpisode(
      sessionIndex: sessionIndex,
      generation: generation,
    );
    if (!tvPlaybackAsyncResultIsCurrent(
      mounted: mounted,
      capturedGeneration: generation,
      currentGeneration: _playbackGeneration,
    )) {
      return;
    }
    final targetIdentity = refreshed == null
        ? retainedIdentity
        : _playbackSessionMergeKey(refreshed);
    final rebasedIndex = tvPlaybackCandidateIndexForIdentity(
      identities:
          _sessions.map(_playbackSessionMergeKey).toList(growable: false),
      identity: targetIdentity,
    );
    if (rebasedIndex == null) {
      _closePlaybackUnavailable('Playback is unavailable right now.');
      return;
    }
    await _openSession(
      rebasedIndex,
      feedbackLabel: 'Refreshed',
      resumePosition: resumePosition,
      retainedSessionOverride: retainedSession,
    );
  }

  List<_TvEpisode> _episodesForSeason(int season) {
    final slots = tvPlaybackEpisodesForSeason(
      [
        for (final episode in widget.item.episodes)
          TvPlaybackEpisodeSlot(
            season: episode.season,
            episode: episode.episode,
          ),
      ],
      season,
    );
    return [
      for (final slot in slots)
        widget.item.episodes.firstWhere(
          (episode) =>
              episode.season == slot.season &&
              episode.episode == slot.episode,
        ),
    ];
  }

  Future<_TvEpisode?> _showSeasonEpisodes(int season) async {
    final episodes = _episodesForSeason(season);
    if (episodes.isEmpty) return null;
    final selectedValue = '$season:${_season == season ? _episode : -1}';
    final selected = await _showPlaybackDialog<String>(
        builder: (context) => _TvPlaybackChoiceDialog(
        title: 'Season $season episodes',
        selected: selectedValue,
        onBack: (dialogContext) => _popPlaybackDialog<String>(
            _playbackDialogNavigator(dialogContext),
            'episodes-child-back',
          ),
        onChoice: (value, dialogContext) async {
          await Future<void>.delayed(_tvDuration(120));
          if (!mounted || !dialogContext.mounted) return;
          _popPlaybackDialog<String>(
            _playbackDialogNavigator(dialogContext),
            'episodes-child-select',
            value,
          );
        },
        choices: [
          for (final episode in episodes)
            _TvPlaybackChoice(
              'E${episode.episode} - ${episode.title}',
              Icons.play_circle_outline_rounded,
              value: '$season:${episode.episode}',
              subtitle: episode.description,
              imageUrl: episode.thumbnail,
              pendingIcon: Icons.hourglass_top_rounded,
              marqueeSubtitleOnFocus: true,
            ),
        ],
        ),
      );
    if (selected == null) return null;
    return episodes.firstWhere(
      (episode) => '$season:${episode.episode}' == selected,
    );
  }

  Future<void> _showEpisodesPanel() async {
    if (_locked || !_seriesLike || widget.item.episodes.isEmpty) return;
    _prepareForOptionDialog();
    final seasons = tvPlaybackSeasons([
      for (final episode in widget.item.episodes)
        TvPlaybackEpisodeSlot(
          season: episode.season,
          episode: episode.episode,
        ),
    ]);
    if (seasons.isEmpty) {
      _showPlayerToast('Episodes are unavailable right now.');
      return;
    }
    var parentOpen = true;
    _TvEpisode? selectedEpisode;
    try {
      selectedEpisode = await _showPlaybackDialog<_TvEpisode>(
        builder: (context) => _TvPlaybackChoiceDialog(
          title: 'Choose season',
          selected: _season.toString(),
          onBack: (dialogContext) => _popPlaybackDialog(
            _playbackDialogNavigator(dialogContext),
            'episodes-parent-back',
          ),
          onChoice: (value, dialogContext) async {
            final season = int.tryParse(value);
            if (season == null) return;
            final target = await _showSeasonEpisodes(season);
            _suppressPlaybackBackBriefly();
            if (target == null ||
                !mounted ||
                !parentOpen ||
                !dialogContext.mounted) {
              return;
            }
            await WidgetsBinding.instance.endOfFrame;
            if (mounted && parentOpen && dialogContext.mounted) {
              _popPlaybackDialog<_TvEpisode>(
                _playbackDialogNavigator(dialogContext),
                'episodes-parent-select',
                target,
              );
            }
          },
          choices: [
            for (final season in seasons)
              _TvPlaybackChoice(
                'Season $season',
                Icons.video_library_rounded,
                value: season.toString(),
                subtitle: '${_episodesForSeason(season).length} episodes',
              ),
          ],
        ),
      );
    } finally {
      parentOpen = false;
    }
    if (!mounted) return;
    if (selectedEpisode != null) {
      await _openEpisode(selectedEpisode);
      return;
    }
    _showControls();
    _episodesFocusNode.requestFocus();
  }

  Future<void> _showQualityPicker(VoidCallback refreshSettingsDialog) async {
    final qualityLabels = _availableQualityLabels();
    final sessionQualityLabels = [
      for (final session in _sessions) _qualityLabelForSession(session),
    ];
    final hasAutomaticCandidate = sessionQualityLabels.contains('Auto');
    if (qualityLabels.isEmpty && !hasAutomaticCandidate) {
      _showPlayerToast('No quality variants are ready for this title.');
      return;
    }
    final currentQuality = _qualityLabelForSession(_sessions[_sessionIndex]);
    final selected = await _showPlaybackDialog<String>(
      builder: (context) => _TvPlaybackChoiceDialog(
        title: 'Quality',
        selected: currentQuality,
        onBack: (dialogContext) => _popPlaybackDialog(
          _playbackDialogNavigator(dialogContext),
          'quality-choice',
        ),
        choices: [
          if (hasAutomaticCandidate)
            const _TvPlaybackChoice('Auto', Icons.auto_awesome_rounded),
          for (final label in qualityLabels)
            _TvPlaybackChoice(label, Icons.high_quality_rounded),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final qualityCandidateIndexes = tvPlaybackQualityCandidateOrder(
      qualities: sessionQualityLabels,
      currentIndex: _sessionIndex,
      selected: selected,
    );
    if (qualityCandidateIndexes.isEmpty) {
      _showPlayerToast('$selected is unavailable right now.');
      return;
    }
    final nextIndex = qualityCandidateIndexes.first;
    if (nextIndex != _sessionIndex) {
      await _switchToSource(
        nextIndex,
        candidateIndexes: qualityCandidateIndexes,
      );
    }
    refreshSettingsDialog();
  }

  Future<void> _showSpeedPicker(VoidCallback refreshSettingsDialog) async {
    final selected = await _showPlaybackDialog<String>(
      builder: (context) => _TvPlaybackChoiceDialog(
        title: 'Speed',
        selected: _speedLabel(_playbackSpeed),
        onBack: (dialogContext) => _popPlaybackDialog(
          _playbackDialogNavigator(dialogContext),
          'speed-choice',
        ),
        choices: const [
          _TvPlaybackChoice('0.75x', Icons.speed_rounded),
          _TvPlaybackChoice('1x', Icons.speed_rounded),
          _TvPlaybackChoice('1.25x', Icons.speed_rounded),
          _TvPlaybackChoice('1.50x', Icons.speed_rounded),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final speed = switch (selected) {
      '0.75x' => 0.75,
      '1.25x' => 1.25,
      '1.50x' => 1.5,
      _ => 1.0,
    };
    await _setPlaybackSpeed(speed);
    refreshSettingsDialog();
  }

  String _speedLabel(double speed) {
    if ((speed - 1).abs() < 0.001) return '1x';
    return '${speed.toStringAsFixed(2)}x';
  }

  String _subtitleDelayLabel(int millis) {
    if (millis == 0) return '0s';
    final seconds = millis.abs() / 1000;
    final text = seconds % 1 == 0
        ? seconds.toStringAsFixed(0)
        : seconds.toStringAsFixed(1);
    return '${millis > 0 ? '+' : '-'}${text}s';
  }

  List<_TvPlaybackChoice> _subtitleDelayChoices() {
    return [
      for (var millis = -20000; millis <= 20000; millis += 500)
        _TvPlaybackChoice(
          _subtitleDelayLabel(millis),
          Icons.more_time_rounded,
          value: millis.toString(),
        ),
    ];
  }

  Future<void> _showSubtitleTrackPicker(
    VoidCallback refreshSettingsDialog,
  ) async {
    debugPrint(
      'Juicr TV subtitle picker open '
      'loaded=$_subtitlesLoaded loading=$_subtitlesLoading '
      'seed=${_subtitles.length}',
    );
    await _loadPlaybackSubtitles(activateFirst: false);
    _suppressPlaybackBackBriefly();
    final canUseSubtitles = widget.settings.hasSubtitleSource;
    final captionsAvailable = _subtitles.isNotEmpty && canUseSubtitles;
    final groups = _groupTvSubtitles(_subtitles);
    final selectedGroupKey = _captionsEnabled &&
            _subtitleIndex >= 0 &&
            _subtitleIndex < _subtitles.length
        ? _tvSubtitleProviderKey(_subtitles[_subtitleIndex])
        : 'off';
    final selectedGroup = await _showPlaybackDialog<String>(
      builder: (context) => _TvPlaybackChoiceDialog(
        title: 'Subtitle',
        selected: selectedGroupKey,
        onBack: (dialogContext) => _popPlaybackDialog(
          _playbackDialogNavigator(dialogContext),
          'subtitle-choice',
        ),
        choices: [
          const _TvPlaybackChoice(
            'Off',
            Icons.closed_caption_off_rounded,
            value: 'off',
          ),
          if (captionsAvailable)
            for (final group in groups)
              _TvPlaybackChoice(
                '${group.title} (${group.subtitles.length} available)',
                Icons.closed_caption_rounded,
                value: group.providerKey,
              ),
        ],
      ),
    );
    if (selectedGroup == null || !mounted) return;
    var selected = selectedGroup;
    if (selectedGroup != 'off') {
      final group = groups.firstWhere(
        (candidate) => candidate.providerKey == selectedGroup,
      );
      final childSelection = await _showSubtitleGroupPicker(group);
      if (childSelection == null || !mounted) return;
      selected = childSelection;
    }
    var subtitleIndex = -1;
    if (selected != 'off') {
      for (var index = 0; index < _subtitles.length; index++) {
        if (_subtitleChoiceKey(index, _subtitles[index]) == selected) {
          subtitleIndex = index;
          break;
        }
      }
    }
    final wasCaptionsEnabled = _captionsEnabled;
    final previousSubtitleIndex = _subtitleIndex;
    final nextCaptionsEnabled = subtitleIndex >= 0;
    if (wasCaptionsEnabled == nextCaptionsEnabled &&
        previousSubtitleIndex == subtitleIndex) {
      final activeSubtitle = _selectedSubtitle();
      final activeLanguage =
          activeSubtitle?.language.trim().toLowerCase() ?? '';
      await widget.onSubtitlePreferenceChanged?.call(
        activeSubtitle?.id,
        activeLanguage.isEmpty ? widget.subtitleLanguage : activeLanguage,
      );
      debugPrint(
        'Juicr TV subtitle picker unchanged '
        'available=${_subtitles.length} selected=$subtitleIndex',
      );
      refreshSettingsDialog();
      return;
    }
    setState(() {
      _subtitleIndex = subtitleIndex;
      _captionsEnabled = nextCaptionsEnabled;
      _controlsVisible = true;
    });
    await _loadSelectedSubtitleCues(allowFallback: false);
    final activeSubtitle = _selectedSubtitle();
    final activeLanguage = activeSubtitle?.language.trim().toLowerCase() ?? '';
    await widget.onSubtitlePreferenceChanged?.call(
      activeSubtitle?.id,
      activeLanguage.isEmpty ? widget.subtitleLanguage : activeLanguage,
    );
    debugPrint(
      'Juicr TV subtitle picker changed '
      'enabled=$_captionsEnabled selected=$_subtitleIndex '
      'available=${_subtitles.length} action=cues_only',
    );
    refreshSettingsDialog();
    _showFeedback(
      Icons.closed_caption_rounded,
      _captionsEnabled ? 'Subtitles on' : 'Subtitles off',
    );
  }

  Future<String?> _showSubtitleGroupPicker(_TvSubtitleGroup group) {
    final selectedKey = _captionsEnabled &&
            _subtitleIndex >= 0 &&
            _subtitleIndex < _subtitles.length
        ? _subtitleChoiceKey(_subtitleIndex, _subtitles[_subtitleIndex])
        : '';
    return _showPlaybackDialog<String>(
      builder: (context) => _TvPlaybackChoiceDialog(
        title: group.title,
        selected: selectedKey,
        onBack: (dialogContext) => _popPlaybackDialog(
          _playbackDialogNavigator(dialogContext),
          'subtitle-group-choice',
        ),
        choices: [
          for (final subtitle in group.subtitles)
            _TvPlaybackChoice(
              subtitle.label,
              Icons.closed_caption_rounded,
              value: _subtitleChoiceKey(
                _subtitles.indexOf(subtitle),
                subtitle,
              ),
            ),
        ],
      ),
    );
  }

  bool get _skipSegmentsSupported => !_isLiveTvPlayback;

  bool get _hasEpisodeSkipSegmentIdentity =>
      (widget.item.type == 'series' || widget.item.type == 'animation') &&
      _season > 0 &&
      _episode > 0;

  int? get _skipSegmentLookupSeason =>
      _hasEpisodeSkipSegmentIdentity ? _season : null;

  int? get _skipSegmentLookupEpisode =>
      _hasEpisodeSkipSegmentIdentity ? _episode : null;

  String? get _skipSegmentImdbId => _tvCleanImdbId(widget.item.id);

  int? get _skipSegmentTmdbId => widget.item.tmdbId;

  void _maybeLoadSkipSegments(Duration duration) {
    if (!_skipSegmentsSupported ||
        duration <= Duration.zero ||
        _skipSegmentLookupDuration > Duration.zero) {
      return;
    }
    if ((_skipSegmentTmdbId == null && _skipSegmentImdbId == null) ||
        _skipSegmentLookupSeason == null ||
        _skipSegmentLookupEpisode == null) {
      return;
    }
    _skipSegmentLookupDuration = duration;
    unawaited(_loadSkipSegments(duration));
  }

  Future<void> _loadSkipSegments(Duration duration) async {
    final generation = ++_skipSegmentLoadGeneration;
    if (!_skipSegmentsSupported) {
      if (mounted) {
        setState(() {
          _skipSegments = const <_TvPlaybackSkipSegmentTiming>[];
          _skipSegmentLookupDuration = Duration.zero;
        });
      }
      return;
    }
    try {
      final segments = await _skipSegmentClient.lookup(
        tmdbId: _skipSegmentTmdbId,
        imdbId: _skipSegmentImdbId,
        season: _skipSegmentLookupSeason,
        episode: _skipSegmentLookupEpisode,
        duration: duration,
      );
      if (!mounted || generation != _skipSegmentLoadGeneration) return;
      setState(() => _skipSegments = segments);
      _skipSegmentLookupDuration = duration;
    } catch (_) {
      if (!mounted || generation != _skipSegmentLoadGeneration) return;
      _skipSegmentLookupDuration = Duration.zero;
      setState(() => _skipSegments = const <_TvPlaybackSkipSegmentTiming>[]);
    }
  }

  void _resetSkipSegmentsForCurrentEpisode() {
    _skipSegmentLoadGeneration += 1;
    _skipSegments = const <_TvPlaybackSkipSegmentTiming>[];
    _skipSegmentLookupDuration = Duration.zero;
  }

  Future<void> _showSubtitleDelayPicker(
    VoidCallback refreshSettingsDialog,
  ) async {
    final selected = await _showPlaybackDialog<String>(
      builder: (context) => _TvPlaybackChoiceDialog(
        title: 'Subtitle delay',
        selected: _subtitleDelayMillis.toString(),
        onBack: (dialogContext) => _popPlaybackDialog(
          _playbackDialogNavigator(dialogContext),
          'subtitle-delay-choice',
        ),
        choices: _subtitleDelayChoices(),
      ),
    );
    if (selected == null || !mounted) return;
    final millis = int.tryParse(selected);
    if (millis == null) return;
    setState(() {
      _subtitleDelayMillis = millis.clamp(-20000, 20000).toInt();
      _controlsVisible = true;
    });
    await widget.onSubtitleDelayChanged?.call(_subtitleDelayMillis);
    refreshSettingsDialog();
    _showFeedback(
      Icons.more_time_rounded,
      'Subtitle delay ${_subtitleDelayLabel(_subtitleDelayMillis)}',
    );
  }

  Future<void> _showSubtitlePicker(VoidCallback refreshSettingsDialog) async {
    final subtitleFocusNodes = [
      FocusNode(debugLabel: 'tv-playback-subtitle-track'),
      FocusNode(debugLabel: 'tv-playback-subtitle-delay'),
    ];
    final subtitleDialogFocusNode = FocusNode(
      debugLabel: 'tv-playback-subtitle-dialog',
    );
    var lastSubtitleFocusIndex = 0;

    void focusSubtitleRow(int index) {
      if (index < 0 || index >= subtitleFocusNodes.length) return;
      lastSubtitleFocusIndex = index;
      subtitleFocusNodes[index].requestFocus();
    }

    void restoreSubtitleFocus() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final focusInsideSubtitle = subtitleFocusNodes.any(
          (node) => node.hasFocus,
        );
        if (!focusInsideSubtitle) {
          focusSubtitleRow(lastSubtitleFocusIndex);
        }
      });
    }

    Future<void> runSubtitleChild(
      int index,
      Future<void> Function() action,
      StateSetter setDialogState,
    ) async {
      try {
        await action();
      } finally {
        _suppressPlaybackBackBriefly();
        if (mounted) {
          setDialogState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) focusSubtitleRow(index);
          });
        }
      }
    }

    try {
      await _showPlaybackDialog<void>(
        builder: (dialogContext) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_shouldIgnoreNestedPlaybackDialogPop('subtitle-parent')) {
                return;
              }
              _popPlaybackDialog(
                _playbackDialogNavigator(dialogContext),
                'subtitle-parent',
              );
            },
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                restoreSubtitleFocus();
                final subtitleValue = _captionsEnabled &&
                        _subtitleIndex >= 0 &&
                        _subtitleIndex < _subtitles.length
                    ? _subtitles[_subtitleIndex].label
                    : _subtitles.isEmpty
                        ? (_subtitlesLoading ? 'Loading' : 'Unavailable')
                        : 'Off';
                return Focus(
                  focusNode: subtitleDialogFocusNode,
                  autofocus: true,
                  descendantsAreFocusable: true,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    final key = event.logicalKey;
                    final focusedIndex = subtitleFocusNodes.indexWhere(
                      (node) => node.hasFocus,
                    );
                    if (focusedIndex >= 0) return KeyEventResult.ignored;
                    if (key == LogicalKeyboardKey.arrowUp) {
                      focusSubtitleRow(
                        lastSubtitleFocusIndex <= 0
                            ? 0
                            : lastSubtitleFocusIndex - 1,
                      );
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.arrowDown) {
                      focusSubtitleRow(
                        lastSubtitleFocusIndex >= subtitleFocusNodes.length - 1
                            ? subtitleFocusNodes.length - 1
                            : lastSubtitleFocusIndex + 1,
                      );
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.select ||
                        key == LogicalKeyboardKey.enter ||
                        key == LogicalKeyboardKey.space) {
                      focusSubtitleRow(lastSubtitleFocusIndex);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Dialog(
                    backgroundColor: Colors.transparent,
                    child: Container(
                      width: 560,
                      constraints: const BoxConstraints(maxHeight: 420),
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xEE202124),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0x24FFFFFF)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: _tvSpacing),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Subtitle',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: _tvSpacing),
                            const Text(
                              'Choose captions and sync timing.',
                              style: TextStyle(
                                color: Color(0xFFAAA6BD),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: _tvSpacing),
                            _TvPlaybackSettingsRow(
                              icon: _captionsEnabled
                                  ? Icons.closed_caption_rounded
                                  : Icons.closed_caption_off_rounded,
                              title: 'Track',
                              value: subtitleValue,
                              autofocus: true,
                              focusNode: subtitleFocusNodes[0],
                              onArrowUp: () => focusSubtitleRow(0),
                              onArrowDown: () => focusSubtitleRow(1),
                              onPressed: () => unawaited(
                                runSubtitleChild(
                                  0,
                                  () => _showSubtitleTrackPicker(
                                    () => setDialogState(() {}),
                                  ),
                                  setDialogState,
                                ),
                              ),
                            ),
                            _TvPlaybackSettingsRow(
                              icon: Icons.more_time_rounded,
                              title: 'Delay',
                              value: _subtitleDelayLabel(_subtitleDelayMillis),
                              focusNode: subtitleFocusNodes[1],
                              onArrowUp: () => focusSubtitleRow(0),
                              onArrowDown: () => focusSubtitleRow(1),
                              onPressed: () => unawaited(
                                runSubtitleChild(
                                  1,
                                  () => _showSubtitleDelayPicker(
                                    () => setDialogState(() {}),
                                  ),
                                  setDialogState,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    } finally {
      await _settlePlaybackDialogFocusBeforeDispose(
        [subtitleDialogFocusNode, ...subtitleFocusNodes],
        restoreFocusNode: _settingsFocusNode,
      );
      subtitleDialogFocusNode.dispose();
      for (final node in subtitleFocusNodes) {
        node.dispose();
      }
    }
    if (mounted) refreshSettingsDialog();
  }

  String _subtitleChoiceKey(int index, _TvSubtitle subtitle) {
    final id = subtitle.id.trim();
    final identity = id.isNotEmpty
        ? id
        : [
            subtitle.language.trim().toLowerCase(),
            subtitle.label.trim().toLowerCase(),
            subtitle.format.trim().toLowerCase(),
          ].join('|');
    return [index, identity].join('|');
  }

  Future<void> _showVideoSizePicker(VoidCallback refreshSettingsDialog) async {
    final selected = await _showPlaybackDialog<String>(
      builder: (context) => _TvPlaybackChoiceDialog(
        title: 'Video size',
        selected: _videoSize,
        onBack: (dialogContext) => _popPlaybackDialog(
          _playbackDialogNavigator(dialogContext),
          'video-size-choice',
        ),
        choices: const [
          _TvPlaybackChoice(
            'Fit',
            Icons.fit_screen_rounded,
            value: _tvVideoSizeFit,
          ),
          _TvPlaybackChoice(
            'Fill',
            Icons.fullscreen_rounded,
            value: _tvVideoSizeFill,
          ),
          _TvPlaybackChoice(
            '16:9',
            Icons.aspect_ratio_rounded,
            value: _tvVideoSizeWide,
          ),
          _TvPlaybackChoice(
            'Stretch',
            Icons.open_in_full_rounded,
            value: _tvVideoSizeStretch,
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final previous = _videoSize;
    final normalized = _normalizeTvVideoSizeMode(selected);
    setState(() {
      _videoSize = normalized;
      _controlsVisible = true;
    });
    await _controller?.setVideoSizeMode(_nativeTvVideoSizeModeFor(normalized));
    debugPrint(
      'Juicr TV video size changed '
      'from=${_tvVideoSizeLabel(previous)} '
      'to=${_tvVideoSizeLabel(normalized)} action=layout_and_native',
    );
    refreshSettingsDialog();
  }

  double _stableDecodedAspectRatio(
    _TvPlaybackValue value,
    _TvPlaybackEngine engine,
  ) {
    final width = value.size.width;
    final height = value.size.height;
    if (width > 0 && height > 0) {
      final sizeAspectRatio = width / height;
      if (sizeAspectRatio.isFinite &&
          sizeAspectRatio > _minimumTrustedAspectRatio(engine) &&
          sizeAspectRatio <= 3.2) {
        _lastDecodedAspectRatio = sizeAspectRatio;
        return _lastDecodedAspectRatio;
      }
    }
    final candidate = value.aspectRatio;
    if (candidate.isFinite &&
        candidate > _minimumTrustedAspectRatio(engine) &&
        candidate <= 3.2) {
      _lastDecodedAspectRatio = candidate;
    }
    return _lastDecodedAspectRatio;
  }

  double _minimumTrustedAspectRatio(_TvPlaybackEngine engine) {
    return 1.05;
  }

  Widget _videoSurfaceForController(
    _TvNativePlaybackController? controller,
    _TvPlaybackValue value, {
    bool updateStableAspectRatio = true,
  }) {
    if (controller == null) {
      return const ColoredBox(color: Colors.black);
    }
    final decodedAspectRatio = updateStableAspectRatio
        ? _stableDecodedAspectRatio(value, controller.engine)
        : 16 / 9;
    Widget surface(double aspectRatio) =>
        controller.surface(aspectRatio: aspectRatio);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }
        final mode = _normalizeTvVideoSizeMode(_videoSize);
        if (mode == _tvVideoSizeStretch) {
          return SizedBox.expand(child: surface(16 / 9));
        }
        final aspectRatio =
            mode == _tvVideoSizeWide ? 16 / 9 : decodedAspectRatio;
        final viewportRatio = width / height;
        if (mode == _tvVideoSizeFill) {
          final coverWidth =
              viewportRatio > aspectRatio ? width : height * aspectRatio;
          final coverHeight =
              viewportRatio > aspectRatio ? width / aspectRatio : height;
          return ClipRect(
            child: Center(
              child: SizedBox(
                width: coverWidth,
                height: coverHeight,
                child: surface(aspectRatio),
              ),
            ),
          );
        }
        var fitHeight = height;
        if (mode == _tvVideoSizeFit && aspectRatio < 1.70) {
          fitHeight = height * 0.86;
        }
        final fittedWidth =
            viewportRatio > aspectRatio ? fitHeight * aspectRatio : width;
        final fittedHeight =
            viewportRatio > aspectRatio ? fitHeight : width / aspectRatio;
        return Center(
          child: SizedBox(
            width: fittedWidth,
            height: fittedHeight,
            child: surface(aspectRatio),
          ),
        );
      },
    );
  }

  Future<void> _showSettingsPanel() async {
    if (_locked) return;
    _showControls();
    _hideControlsTimer?.cancel();
    final seriesLike =
        widget.item.type == 'series' || widget.item.type == 'animation';
    final livePlayback = _isLiveTvPlayback;
    final settingsRowCount = livePlayback ? 3 : 5;
    final settingsFocusNodes = [
      for (var index = 0; index < settingsRowCount; index++)
        FocusNode(debugLabel: 'tv-playback-settings-row-$index'),
    ];
    final settingsDialogFocusNode = FocusNode(
      debugLabel: 'tv-playback-settings-dialog',
    );
    var lastSettingsFocusIndex = 0;
    var settingsFocusRestoreQueued = false;
    void focusSettingsRow(int index, {int attempt = 0}) {
      if (index < 0 || index >= settingsFocusNodes.length) return;
      lastSettingsFocusIndex = index;
      final node = settingsFocusNodes[index];
      if (node.context == null || !node.canRequestFocus) {
        if (attempt < 8) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) focusSettingsRow(index, attempt: attempt + 1);
          });
        }
        return;
      }
      node.requestFocus();
      if (!node.hasFocus && attempt < 8) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) focusSettingsRow(index, attempt: attempt + 1);
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = node.context;
        if (!mounted || context == null) return;
        Scrollable.ensureVisible(
          context,
          duration: _tvDuration(140),
          curve: Curves.easeOutCubic,
          alignment: 0.42,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      });
    }

    void restoreSettingsFocus([int attempt = 0]) {
      if (settingsFocusRestoreQueued && attempt == 0) return;
      if (attempt == 0) settingsFocusRestoreQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (attempt == 0) settingsFocusRestoreQueued = false;
        if (!mounted) return;
        final focusInsideSettings = settingsFocusNodes.any(
          (node) => node.hasFocus,
        );
        if (focusInsideSettings) return;
        focusSettingsRow(lastSettingsFocusIndex, attempt: attempt);
        if (attempt < 8) restoreSettingsFocus(attempt + 1);
      });
    }

    Future<void> runSettingsChild(
      int index,
      Future<void> Function() action,
      StateSetter setDialogState,
    ) async {
      try {
        await action();
      } finally {
        _suppressPlaybackBackBriefly();
        if (mounted) {
          setDialogState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) focusSettingsRow(index);
          });
        }
      }
    }

    try {
      await _showPlaybackDialog<void>(
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              restoreSettingsFocus();
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (didPop) return;
                  if (_shouldIgnoreNestedPlaybackDialogPop('settings-parent')) {
                    return;
                  }
                  _popPlaybackDialog(
                    _playbackDialogNavigator(dialogContext),
                    'settings-parent',
                  );
                },
                child: Focus(
                  focusNode: settingsDialogFocusNode,
                  autofocus: true,
                  descendantsAreFocusable: true,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    final key = event.logicalKey;
                    final focusedIndex = settingsFocusNodes.indexWhere(
                      (node) => node.hasFocus,
                    );
                    if (focusedIndex >= 0) return KeyEventResult.ignored;
                    if (key == LogicalKeyboardKey.arrowUp) {
                      focusSettingsRow(
                        lastSettingsFocusIndex <= 0
                            ? 0
                            : lastSettingsFocusIndex - 1,
                      );
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.arrowDown) {
                      focusSettingsRow(
                        lastSettingsFocusIndex >= settingsFocusNodes.length - 1
                            ? settingsFocusNodes.length - 1
                            : lastSettingsFocusIndex + 1,
                      );
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.select ||
                        key == LogicalKeyboardKey.enter ||
                        key == LogicalKeyboardKey.space) {
                      focusSettingsRow(lastSettingsFocusIndex);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Dialog(
                    backgroundColor: Colors.transparent,
                    child: Container(
                      width: 620,
                      constraints: const BoxConstraints(maxHeight: 560),
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xEE202124),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0x24FFFFFF)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: _tvSpacing),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Settings',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: _tvSpacing),
                            Text(
                              seriesLike
                                  ? 'S$_season E$_episode - Source ${_sessionIndex + 1}/${_sessions.length}'
                                  : 'Source ${_sessionIndex + 1}/${_sessions.length}',
                              style: const TextStyle(
                                color: Color(0xFFAAA6BD),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: _tvSpacing),
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    if (!livePlayback)
                                      _TvPlaybackSettingsRow(
                                        icon: _captionsEnabled
                                            ? Icons.closed_caption_rounded
                                            : Icons.closed_caption_off_rounded,
                                        title: 'Subtitle',
                                        value: _captionsEnabled &&
                                                _subtitleIndex >= 0 &&
                                                _subtitleIndex <
                                                    _subtitles.length
                                            ? _subtitles[_subtitleIndex].label
                                            : _subtitles.isEmpty
                                                ? (_subtitlesLoading
                                                    ? 'Loading'
                                                    : 'Unavailable')
                                                : 'Off',
                                        focusNode: settingsFocusNodes[0],
                                        autofocus: true,
                                        onArrowUp: () => focusSettingsRow(0),
                                        onArrowDown: () => focusSettingsRow(1),
                                        onPressed: () => unawaited(
                                          runSettingsChild(
                                            0,
                                            () => _showSubtitlePicker(() {}),
                                            setDialogState,
                                          ),
                                        ),
                                      ),
                                    _TvPlaybackSettingsRow(
                                      icon: Icons.high_quality_rounded,
                                      title: 'Quality',
                                      value: _qualityLabelForSession(
                                        _sessions[_sessionIndex],
                                      ),
                                      focusNode: settingsFocusNodes[
                                          livePlayback ? 0 : 1],
                                      autofocus: livePlayback,
                                      onArrowUp: () => focusSettingsRow(
                                        livePlayback ? 0 : 0,
                                      ),
                                      onArrowDown: () => focusSettingsRow(
                                        livePlayback ? 1 : 2,
                                      ),
                                      onPressed: () => unawaited(
                                        runSettingsChild(
                                          livePlayback ? 0 : 1,
                                          () => _showQualityPicker(() {}),
                                          setDialogState,
                                        ),
                                      ),
                                    ),
                                    if (!livePlayback)
                                      _TvPlaybackSettingsRow(
                                        icon: Icons.speed_rounded,
                                        title: 'Speed',
                                        value: _speedLabel(_playbackSpeed),
                                        focusNode: settingsFocusNodes[2],
                                        onArrowUp: () => focusSettingsRow(1),
                                        onArrowDown: () => focusSettingsRow(3),
                                        onPressed: () => unawaited(
                                          runSettingsChild(
                                            2,
                                            () => _showSpeedPicker(() {}),
                                            setDialogState,
                                          ),
                                        ),
                                      ),
                                    _TvPlaybackSettingsRow(
                                      icon: Icons.aspect_ratio_rounded,
                                      title: 'Video size',
                                      value: _tvVideoSizeLabel(_videoSize),
                                      focusNode: settingsFocusNodes[
                                          livePlayback ? 1 : 3],
                                      onArrowUp: () => focusSettingsRow(
                                        livePlayback ? 0 : 2,
                                      ),
                                      onArrowDown: () => focusSettingsRow(
                                        livePlayback ? 2 : 4,
                                      ),
                                      onPressed: () => unawaited(
                                        runSettingsChild(
                                          livePlayback ? 1 : 3,
                                          () => _showVideoSizePicker(() {}),
                                          setDialogState,
                                        ),
                                      ),
                                    ),
                                    _TvPlaybackSettingsRow(
                                      icon: Icons.refresh_rounded,
                                      title: livePlayback
                                          ? 'Refresh live stream'
                                          : 'Refresh stream',
                                      value: 'Reload',
                                      focusNode: settingsFocusNodes[
                                          livePlayback ? 2 : 4],
                                      onArrowUp: () => focusSettingsRow(
                                        livePlayback ? 1 : 3,
                                      ),
                                      onArrowDown: () => focusSettingsRow(
                                        livePlayback ? 2 : 4,
                                      ),
                                      onPressed: () {
                                        _popPlaybackDialog(
                                          _playbackDialogNavigator(
                                              dialogContext),
                                          'settings-refresh',
                                        );
                                        unawaited(_refreshStream());
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      await _settlePlaybackDialogFocusBeforeDispose(
        [settingsDialogFocusNode, ...settingsFocusNodes],
        restoreFocusNode: _settingsFocusNode,
      );
      settingsDialogFocusNode.dispose();
      for (final node in settingsFocusNodes) {
        node.dispose();
      }
    }
    if (!mounted) return;
    _showControls();
    _settingsFocusNode.requestFocus();
  }

  KeyEventResult _focusPlaybackControl(TraversalDirection direction) {
    _showControls();
    final focused = FocusManager.instance.primaryFocus;
    final controllerValue = _controller?.value ?? _TvPlaybackValue.empty;
    final skipSegmentFocusable =
        !_locked && _activeSkipSegment(controllerValue) != null;
    final bottomEntryFocusNode = skipSegmentFocusable
        ? _skipSegmentFocusNode
        : _locked
            ? _lockFocusNode
            : _seriesLike && widget.item.episodes.isNotEmpty
                ? _episodesFocusNode
                : _sourcesFocusNode;
    if (direction == TraversalDirection.up) {
      if (focused == _progressFocusNode) {
        bottomEntryFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (focused == _episodesFocusNode ||
          focused == _sourcesFocusNode ||
          focused == _settingsFocusNode ||
          focused == _skipSegmentFocusNode ||
          focused == _lockFocusNode) {
        _playFocusNode.requestFocus();
      } else if (focused == _skipBackFocusNode ||
          focused == _skipForwardFocusNode) {
        _backFocusNode.requestFocus();
      } else if (focused == _nextEpisodeFocusNode) {
        _nextEpisodeFocusNode.requestFocus();
      } else {
        _backFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (direction == TraversalDirection.down) {
      if (focused == _backFocusNode) {
        _playFocusNode.requestFocus();
      } else if (focused == _nextEpisodeFocusNode) {
        _playFocusNode.requestFocus();
      } else if (focused == _playFocusNode ||
          focused == _skipBackFocusNode ||
          focused == _skipForwardFocusNode) {
        bottomEntryFocusNode.requestFocus();
      } else if (focused == _episodesFocusNode ||
          focused == _sourcesFocusNode ||
          focused == _settingsFocusNode ||
          focused == _skipSegmentFocusNode ||
          focused == _lockFocusNode) {
        if (_locked || _isLiveTvPlayback) {
          _lockFocusNode.requestFocus();
        } else {
          _progressFocusNode.requestFocus();
        }
      } else {
        bottomEntryFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _focusPlaybackControlHorizontal(int direction) {
    _showControls();
    final focused = FocusManager.instance.primaryFocus;
    final controllerValue = _controller?.value ?? _TvPlaybackValue.empty;
    final skipSegmentFocusable =
        !_locked && _activeSkipSegment(controllerValue) != null;
    if (direction > 0) {
      if (focused == _skipBackFocusNode) {
        _playFocusNode.requestFocus();
      } else if (focused == _playFocusNode || focused == _playbackFocusNode) {
        if (!_isLiveTvPlayback) {
          _skipForwardFocusNode.requestFocus();
        } else {
          _sourcesFocusNode.requestFocus();
        }
      } else if (focused == _skipForwardFocusNode) {
        (_seriesLike && widget.item.episodes.isNotEmpty
                ? _episodesFocusNode
                : _sourcesFocusNode)
            .requestFocus();
      } else if (focused == _skipSegmentFocusNode) {
        (_seriesLike && widget.item.episodes.isNotEmpty
                ? _episodesFocusNode
                : _sourcesFocusNode)
            .requestFocus();
      } else if (focused == _episodesFocusNode) {
        _sourcesFocusNode.requestFocus();
      } else if (focused == _sourcesFocusNode) {
        _settingsFocusNode.requestFocus();
      } else if (focused == _settingsFocusNode) {
        _lockFocusNode.requestFocus();
      } else {
        _settingsFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (focused == _lockFocusNode) {
      _settingsFocusNode.requestFocus();
    } else if (focused == _settingsFocusNode) {
      _sourcesFocusNode.requestFocus();
    } else if (focused == _sourcesFocusNode) {
      if (_seriesLike && widget.item.episodes.isNotEmpty) {
        _episodesFocusNode.requestFocus();
      } else if (skipSegmentFocusable) {
        _skipSegmentFocusNode.requestFocus();
      } else {
        _lockFocusNode.requestFocus();
      }
    } else if (focused == _skipSegmentFocusNode) {
      _playFocusNode.requestFocus();
    } else if (focused == _episodesFocusNode) {
      if (skipSegmentFocusable) {
        _skipSegmentFocusNode.requestFocus();
      } else {
        _lockFocusNode.requestFocus();
      }
    } else if (focused == _skipForwardFocusNode) {
      _playFocusNode.requestFocus();
    } else if (focused == _playFocusNode || focused == _playbackFocusNode) {
      if (!_isLiveTvPlayback) {
        _skipBackFocusNode.requestFocus();
      } else {
        _sourcesFocusNode.requestFocus();
      }
    } else if (focused == _skipBackFocusNode) {
      _skipBackFocusNode.requestFocus();
    } else {
      _sourcesFocusNode.requestFocus();
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _activateFocusedPlaybackControl() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final focused = primaryFocus == _playbackFocusNode
        ? _lastPlaybackFocusNode ?? primaryFocus
        : primaryFocus;
    if (focused == _backFocusNode) {
      unawaited(_closePlayback());
      return KeyEventResult.handled;
    }
    if (focused == _playFocusNode || focused == _playbackFocusNode) {
      unawaited(_togglePlay());
      return KeyEventResult.handled;
    }
    if (focused == _skipBackFocusNode) {
      if (!_isLiveTvPlayback) {
        unawaited(
          _skipBy(
            Duration(seconds: -tvPlaybackSkipInterval.inSeconds),
            direction: -1,
          ),
        );
      }
      return KeyEventResult.handled;
    }
    if (focused == _skipForwardFocusNode) {
      if (!_isLiveTvPlayback) {
        unawaited(_skipBy(tvPlaybackSkipInterval, direction: 1));
      }
      return KeyEventResult.handled;
    }
    if (focused == _skipSegmentFocusNode) {
      final segment = _activeSkipSegment(
        _controller?.value ?? _TvPlaybackValue.empty,
      );
      if (segment != null) {
        unawaited(_skipToSegment(segment));
      }
      return KeyEventResult.handled;
    }
    if (focused == _sourcesFocusNode) {
      unawaited(_showSourcesPanel());
      return KeyEventResult.handled;
    }
    if (focused == _episodesFocusNode) {
      unawaited(_showEpisodesPanel());
      return KeyEventResult.handled;
    }
    if (focused == _settingsFocusNode) {
      unawaited(_showSettingsPanel());
      return KeyEventResult.handled;
    }
    if (focused == _lockFocusNode) {
      _toggleLock();
      return KeyEventResult.handled;
    }
    if (focused == _nextEpisodeFocusNode) {
      unawaited(_openNextEpisode());
      return KeyEventResult.handled;
    }
    if (focused == _progressFocusNode) {
      unawaited(_togglePlay());
      return KeyEventResult.handled;
    }
    _playFocusNode.requestFocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _handlePlaybackKey(KeyEvent event) {
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        final wasHoldingSeek = _holdSeekDirection != 0;
        _stopHoldSeek();
        return wasHoldingSeek ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final bucket = tvRemoteInputMapper.bucketForEvent(event);
    _updateRemoteDebug(bucket);
    if (bucket == null) return KeyEventResult.ignored;
    final command = tvPlaybackRemoteActionResolver.commandFor(bucket);
    if (_hasPlaybackDialogOpen) {
      if (command == TvPlaybackRemoteCommand.close) {
        unawaited(_closeTopPlaybackDialog('key-close'));
      }
      return KeyEventResult.handled;
    }
    if (_controlsVisible && command != TvPlaybackRemoteCommand.close) {
      _refreshControlsAutoHideTimer();
    }
    if (!_controlsVisible && command != TvPlaybackRemoteCommand.close) {
      if (command == TvPlaybackRemoteCommand.openSettings) {
        _showControls();
        _requestHudFocusAfterBuild(_settingsFocusNode);
        unawaited(_showSettingsPanel());
      } else if (command == TvPlaybackRemoteCommand.openSources) {
        _showControls();
        _requestHudFocusAfterBuild(_sourcesFocusNode);
        unawaited(_showSourcesPanel());
      } else {
        _showControlsForRemoteBucket(bucket);
      }
      return KeyEventResult.handled;
    }
    if (_locked && command != TvPlaybackRemoteCommand.close) {
      _showControls();
      if (bucket == TvRemoteActionBucket.select &&
          FocusManager.instance.primaryFocus == _lockFocusNode) {
        _toggleLock();
      } else {
        _requestHudFocusAfterBuild(_lockFocusNode);
      }
      return KeyEventResult.handled;
    }
    switch (command) {
      case TvPlaybackRemoteCommand.togglePlay:
        unawaited(_togglePlay());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.play:
        unawaited(_playOnly());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.pause:
        unawaited(_pauseOnly());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.stop:
      case TvPlaybackRemoteCommand.close:
        if (_shouldSuppressPlaybackBack() ||
            _shouldSuppressPlaybackBackAfterDialog()) {
          return KeyEventResult.handled;
        }
        unawaited(_closePlayback());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.seekForward:
        if (bucket == TvRemoteActionBucket.dpadRight) break;
        if (_isLiveTvPlayback) return KeyEventResult.handled;
        unawaited(
          _skipBy(
            tvPlaybackSkipOffsetForCommand(
              TvPlaybackRemoteCommand.seekForward,
            )!,
            direction: 1,
          ),
        );
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.seekBack:
        if (bucket == TvRemoteActionBucket.dpadLeft) break;
        if (_isLiveTvPlayback) return KeyEventResult.handled;
        unawaited(
          _skipBy(
            tvPlaybackSkipOffsetForCommand(TvPlaybackRemoteCommand.seekBack)!,
            direction: -1,
          ),
        );
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.openSources:
        unawaited(_showSourcesPanel());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.openSettings:
        unawaited(_showSettingsPanel());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.showControls:
        break;
      case null:
        return KeyEventResult.ignored;
    }
    if (bucket == TvRemoteActionBucket.dpadUp) {
      return _focusPlaybackControl(TraversalDirection.up);
    }
    if (bucket == TvRemoteActionBucket.dpadDown) {
      return _focusPlaybackControl(TraversalDirection.down);
    }
    if (bucket == TvRemoteActionBucket.dpadRight) {
      if (FocusManager.instance.primaryFocus != _progressFocusNode) {
        return _focusPlaybackControlHorizontal(1);
      }
      if (_isLiveTvPlayback) return KeyEventResult.handled;
      if (event is KeyDownEvent) {
        unawaited(_fastSeekBy(_fastSeekStep, direction: 1));
      }
      _startHoldSeek(1);
      return KeyEventResult.handled;
    }
    if (bucket == TvRemoteActionBucket.dpadLeft) {
      if (FocusManager.instance.primaryFocus != _progressFocusNode) {
        return _focusPlaybackControlHorizontal(-1);
      }
      if (_isLiveTvPlayback) return KeyEventResult.handled;
      if (event is KeyDownEvent) {
        unawaited(
          _fastSeekBy(
            Duration(seconds: -_fastSeekStep.inSeconds),
            direction: -1,
          ),
        );
      }
      _startHoldSeek(-1);
      return KeyEventResult.handled;
    }
    if (bucket == TvRemoteActionBucket.select) {
      _showControls();
      return _activateFocusedPlaybackControl();
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_hasPlaybackDialogOpen) {
          unawaited(_closeTopPlaybackDialog('route-pop'));
          return;
        }
        if (_shouldSuppressPlaybackBack() ||
            _shouldSuppressPlaybackBackAfterDialog()) {
          return;
        }
        unawaited(_closePlayback());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
          },
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  if (_hasPlaybackDialogOpen) {
                    unawaited(_closeTopPlaybackDialog('dismiss-intent'));
                    return null;
                  }
                  if (_shouldSuppressPlaybackBack() ||
                      _shouldSuppressPlaybackBackAfterDialog()) {
                    return null;
                  }
                  unawaited(_closePlayback());
                  return null;
                },
              ),
            },
            child: Focus(
              focusNode: _playbackFocusNode,
              autofocus: true,
              onKeyEvent: (_, event) => _handlePlaybackKey(event),
              child: AnimatedBuilder(
                animation:
                    _controller ?? Listenable.merge(const <Listenable>[]),
                builder: (context, _) {
                  final value = _controller?.value ?? _TvPlaybackValue.empty;
                  final initialized = value.isInitialized;
                  _syncNativeHiddenHudCapture(initialized: initialized);
                  final controllerMounted = _controller != null;
                  final loadingOnly = !controllerMounted;
                  final showPlaybackLoading = !initialized || _switchingSource;
                  final displayProgress = _currentProgress();
                  final fullHudVisible =
                      initialized && _controlsVisible && !_switchingSource;
                  final feedback = _feedback;
                  final livePlayback = _isLiveTvPlayback;
                  final feedbackIcon = feedback == null
                      ? null
                      : feedback.skipDirection < 0
                          ? Icons.replay_rounded
                          : feedback.skipDirection > 0
                              ? Icons.forward_rounded
                              : feedback.icon;
                  final skipSegment =
                      livePlayback ? null : _activeSkipSegment(value);
                  final subtitleText =
                      livePlayback ? null : _activeSubtitleText(value);
                  final centerHudVisible =
                      fullHudVisible && !_switchingSource && !loadingOnly;
                  final centerControlsVisible = centerHudVisible && !_locked;
                  final centerUnlockVisible = centerHudVisible && _locked;
                  final showBufferingIndicator = initialized &&
                      value.isPlaying &&
                      value.isBuffering &&
                      !_switchingSource &&
                      feedback == null &&
                      !centerControlsVisible &&
                      !centerUnlockVisible;
                  _revealControlsAfterInitialization(
                    initialized && !_switchingSource,
                  );
                  _maybeAutoNextEpisode(value);
                  void focusPrimaryControls() {
                    if (_locked) {
                      _lockFocusNode.requestFocus();
                    } else {
                      _playFocusNode.requestFocus();
                    }
                  }

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: TvPlaybackSurfaceSlots(
                          stagedSurface: _stagedController == null
                              ? null
                              : Center(
                                  child: _videoSurfaceForController(
                                    _stagedController,
                                    _stagedController!.value,
                                    updateStableAspectRatio: false,
                                  ),
                                ),
                          activeSurface: Center(child: _videoSurface(value)),
                        ),
                      ),
                      if (showPlaybackLoading)
                        Positioned.fill(
                          child: ColoredBox(
                            color: controllerMounted
                                ? Colors.black.withValues(alpha: 0.70)
                                : Colors.black,
                            child: Center(
                              child: _TvPlaybackLoadingState(
                                item: widget.item,
                                status: _loadingStatus,
                              ),
                            ),
                          ),
                        ),
                      if (!loadingOnly)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: _tvDuration(180),
                              opacity: fullHudVisible ? 1 : 0,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.72),
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.74),
                                    ],
                                    stops: const [0, 0.36, 1],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (!loadingOnly && subtitleText != null)
                        _TvSubtitleOverlay(
                          text: subtitleText,
                          settings: widget.settings,
                          controlsVisible: fullHudVisible,
                        ),
                      if (showBufferingIndicator)
                        const _TvPlaybackBufferingIndicator(),
                      if (centerControlsVisible)
                        _TvPlaybackCenterControls(
                          initialized: initialized,
                          playing: value.isPlaying,
                          feedbackIcon:
                              feedback?.seeking == true ? feedbackIcon : null,
                          showNextEpisode: _hasNextEpisodeMetadata,
                          skipSegmentAvailable: skipSegment != null,
                          skipBackFocusNode: _skipBackFocusNode,
                          playFocusNode: _playFocusNode,
                          skipForwardFocusNode: _skipForwardFocusNode,
                          nextEpisodeFocusNode: _nextEpisodeFocusNode,
                          backFocusNode: _backFocusNode,
                          skipSegmentFocusNode: _skipSegmentFocusNode,
                          sourcesFocusNode: _sourcesFocusNode,
                          showSeekControls: !livePlayback,
                          onTogglePlay: _togglePlay,
                          onSeekBack: () => _skipBy(
                            const Duration(seconds: -15),
                            direction: -1,
                          ),
                          onSeekForward: () => _skipBy(_seekStep, direction: 1),
                        ),
                      if (centerUnlockVisible)
                        Positioned.fill(
                          child: SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                120,
                                92,
                                120,
                                118,
                              ),
                              child: Center(
                                child: _TvPlaybackRoundButton(
                                  icon: Icons.lock_open_rounded,
                                  label: 'Unlock',
                                  size: 96,
                                  accent: true,
                                  focusNode: _lockFocusNode,
                                  onPressed: _toggleLock,
                                  onArrowUp: () =>
                                      _backFocusNode.requestFocus(),
                                  onArrowDown: () =>
                                      _lockFocusNode.requestFocus(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (feedback != null &&
                          (!fullHudVisible || _locked || !feedback.seeking))
                        _TvPlaybackFeedbackOverlay(feedback: feedback),
                      if (showPlaybackLoading)
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(28, 24, 28, 26),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: _TvTextButton(
                                icon: Icons.arrow_back_rounded,
                                label: 'Back',
                                focusNode: _backFocusNode,
                                onPressed: () => unawaited(_closePlayback()),
                              ),
                            ),
                          ),
                        ),
                      if (!loadingOnly && _controlsVisible)
                        SafeArea(
                          child: FocusScope(
                            canRequestFocus: fullHudVisible,
                            descendantsAreFocusable: fullHudVisible,
                            child: AnimatedOpacity(
                              duration: _tvDuration(180),
                              opacity: fullHudVisible ? 1 : 0,
                              alwaysIncludeSemantics: fullHudVisible,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  28,
                                  24,
                                  28,
                                  26,
                                ),
                                child: Column(
                                  children: [
                                    _TvPlaybackTopBar(
                                      title: widget.item.title,
                                      episodeLabel: _seriesLike &&
                                              _season > 0 &&
                                              _episode > 0
                                          ? 'S$_season E$_episode'
                                          : null,
                                      accentColor: _tvAccentColor,
                                      showNextEpisode: _hasNextEpisodeMetadata,
                                      nextEpisodeLabel: 'Next episode',
                                      backFocusNode: _backFocusNode,
                                      nextEpisodeFocusNode:
                                          _nextEpisodeFocusNode,
                                      onBack: () => unawaited(_closePlayback()),
                                      onNextEpisode: _openNextEpisode,
                                      onFocusMainControls: focusPrimaryControls,
                                      onFocusBack: () =>
                                          _backFocusNode.requestFocus(),
                                    ),
                                    const Spacer(),
                                    if (!_locked)
                                      _TvPlaybackActionRow(
                                        locked: _locked,
                                        showEpisodes: _seriesLike &&
                                            widget.item.episodes.isNotEmpty,
                                        skipSegment: skipSegment,
                                        skipSegmentFocusNode:
                                            _skipSegmentFocusNode,
                                        episodesFocusNode: _episodesFocusNode,
                                        sourcesFocusNode: _sourcesFocusNode,
                                        settingsFocusNode: _settingsFocusNode,
                                        lockFocusNode: _lockFocusNode,
                                        onLockPressed: _toggleLock,
                                        onEpisodesPressed: _showEpisodesPanel,
                                        onSourcesPressed: _showSourcesPanel,
                                        onSettingsPressed: _showSettingsPanel,
                                        onFocusMainControls:
                                            focusPrimaryControls,
                                        onFocusProgress: () => livePlayback
                                            ? _lockFocusNode.requestFocus()
                                            : _progressFocusNode.requestFocus(),
                                        onSkipSegmentPressed: skipSegment ==
                                                null
                                            ? null
                                            : () => unawaited(
                                                  _skipToSegment(skipSegment),
                                                ),
                                      ),
                                    if (!_locked && !livePlayback) ...[
                                      const SizedBox(height: _tvSpacing),
                                      _TvPlaybackTransportHud(
                                        initialized: initialized,
                                        position: displayProgress.position,
                                        duration: displayProgress.duration,
                                        focusNode: _progressFocusNode,
                                        onSeekBack: () => _fastSeekBy(
                                          Duration(
                                            seconds: -_fastSeekStep.inSeconds,
                                          ),
                                          direction: -1,
                                        ),
                                        onSeekForward: () => _fastSeekBy(
                                          _fastSeekStep,
                                          direction: 1,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoSurface(_TvPlaybackValue value) =>
      _videoSurfaceForController(_controller, value);
}

class _TvPlaybackSettingsRow extends StatelessWidget {
  const _TvPlaybackSettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onPressed,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onPressed;
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _TvFocusable(
        autoReveal: true,
        autofocus: autofocus,
        focusNode: focusNode,
        onPressed: onPressed,
        onArrowLeft: onArrowLeft,
        onArrowRight: onArrowRight,
        onArrowUp: onArrowUp,
        onArrowDown: onArrowDown,
        builder: (focused) {
          return AnimatedContainer(
            duration: _tvDuration(130),
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? _tvAccentColor : const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: focused
                    ? selected
                        ? Colors.white
                        : _tvFocusBorder
                    : const Color(0x22FFFFFF),
                width: focused ? 2 : 1,
              ),
            ),
            child: ClipRect(
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? Colors.black : _tvAccentColor,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (value.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 112),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0x22000000)
                              : const Color(0x24FFFFFF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? const Color(0x22000000)
                                : const Color(0x22FFFFFF),
                          ),
                        ),
                        child: Text(
                          value,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selected ? Colors.black : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TvPlaybackChoice {
  const _TvPlaybackChoice(
    this.label,
    this.icon, {
    String? value,
    this.subtitle = '',
    this.imageUrl,
    this.pendingIcon,
    this.marqueeSubtitleOnFocus = false,
  }) : value = value ?? label;

  final String label;
  final IconData icon;
  final String value;
  final String subtitle;
  final String? imageUrl;
  final IconData? pendingIcon;
  final bool marqueeSubtitleOnFocus;
}

class _TvPlaybackChoiceDialog extends StatefulWidget {
  const _TvPlaybackChoiceDialog({
    required this.title,
    required this.selected,
    required this.choices,
    this.onBack,
    this.onChoice,
  });

  final String title;
  final String selected;
  final List<_TvPlaybackChoice> choices;
  final ValueChanged<BuildContext>? onBack;
  final Future<void> Function(String value, BuildContext context)? onChoice;

  @override
  State<_TvPlaybackChoiceDialog> createState() =>
      _TvPlaybackChoiceDialogState();
}

class _TvPlaybackChoiceDialogState extends State<_TvPlaybackChoiceDialog> {
  final List<FocusNode> _choiceFocusNodes = <FocusNode>[];
  final FocusNode _dialogFocusNode = FocusNode(
    debugLabel: 'tv-playback-choice-dialog',
  );
  String? _pendingValue;

  Future<void> _activateChoice(int index) async {
    if (_pendingValue != null ||
        index < 0 ||
        index >= widget.choices.length) {
      return;
    }
    final value = widget.choices[index].value;
    final onChoice = widget.onChoice;
    if (onChoice == null) {
      Navigator.of(context).pop(value);
      return;
    }
    setState(() => _pendingValue = value);
    try {
      await onChoice(value, context);
    } finally {
      if (mounted) setState(() => _pendingValue = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _syncChoiceFocusNodes();
    _restoreChoiceFocus();
  }

  @override
  void didUpdateWidget(covariant _TvPlaybackChoiceDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        oldWidget.choices.length != widget.choices.length) {
      _syncChoiceFocusNodes();
      _restoreChoiceFocus();
    }
  }

  @override
  void dispose() {
    _dialogFocusNode.dispose();
    for (final node in _choiceFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  int get _selectedIndex {
    final index = widget.choices.indexWhere(
      (choice) => choice.value == widget.selected,
    );
    return index < 0 ? 0 : index;
  }

  void _syncChoiceFocusNodes() {
    while (_choiceFocusNodes.length > widget.choices.length) {
      _choiceFocusNodes.removeLast().dispose();
    }
    while (_choiceFocusNodes.length < widget.choices.length) {
      final index = _choiceFocusNodes.length;
      _choiceFocusNodes.add(FocusNode(debugLabel: 'tv-playback-choice-$index'));
    }
  }

  void _focusChoice(int index) {
    if (index < 0 || index >= _choiceFocusNodes.length) return;
    final node = _choiceFocusNodes[index];
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(140),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  void _restoreChoiceFocus([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _choiceFocusNodes.isEmpty) return;
      final focusInsideChoices = _choiceFocusNodes.any((node) => node.hasFocus);
      if (!focusInsideChoices) {
        _focusChoice(_selectedIndex);
      }
      if (attempt >= 5) return;
      Future<void>.delayed(
        const Duration(milliseconds: 80),
        () => _restoreChoiceFocus(attempt + 1),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncChoiceFocusNodes();
    return Focus(
      focusNode: _dialogFocusNode,
      autofocus: true,
      descendantsAreFocusable: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.browserBack) {
          final onBack = widget.onBack;
          if (onBack != null) {
            onBack(context);
          } else {
            Navigator.of(context).pop();
          }
          return KeyEventResult.handled;
        }
        final focusedIndex = _choiceFocusNodes.indexWhere(
          (focusNode) => focusNode.hasFocus,
        );
        if (widget.choices.isEmpty) return KeyEventResult.ignored;
        final currentIndex = focusedIndex < 0 ? _selectedIndex : focusedIndex;
        if (key == LogicalKeyboardKey.arrowUp) {
          _focusChoice(currentIndex <= 0 ? 0 : currentIndex - 1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _focusChoice(
            currentIndex >= widget.choices.length - 1
                ? widget.choices.length - 1
                : currentIndex + 1,
          );
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) {
          _focusChoice(currentIndex);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) {
          unawaited(_activateChoice(currentIndex));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (focused) {
        if (focused) _restoreChoiceFocus();
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 500),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xF2202124),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0x24FFFFFF)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: _tvSpacing),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: _tvSpacing),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var index = 0;
                            index < widget.choices.length;
                            index++)
                          widget.choices[index].subtitle.trim().isNotEmpty
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _TvSourceGroupButton(
                                    icon: widget.choices[index].value ==
                                            widget.selected
                                        ? Icons.check_circle_rounded
                                        : widget.choices[index].icon,
                                    title: widget.choices[index].label,
                                    subtitle: widget.choices[index].subtitle,
                                    imageUrl:
                                        widget.choices[index].imageUrl,
                                    pendingIcon:
                                        widget.choices[index].pendingIcon,
                                    marqueeSubtitleOnFocus: widget
                                        .choices[index]
                                        .marqueeSubtitleOnFocus,
                                    marqueeKey: widget.choices[index]
                                            .marqueeSubtitleOnFocus
                                        ? ValueKey<String>(
                                            'tv-playback-choice-marquee-${widget.choices[index].value}',
                                          )
                                        : null,
                                    selected: widget.choices[index].value ==
                                        widget.selected,
                                    focusNode: _choiceFocusNodes[index],
                                     autofocus: index == _selectedIndex,
                                    enabled: _pendingValue == null,
                                    animateIcon: _pendingValue ==
                                        widget.choices[index].value,
                                    onArrowUp: index == 0
                                        ? () => _focusChoice(index)
                                        : () => _focusChoice(index - 1),
                                    onArrowDown:
                                        index == widget.choices.length - 1
                                            ? () => _focusChoice(index)
                                            : () => _focusChoice(index + 1),
                                    onArrowLeft: () => _focusChoice(index),
                                    onArrowRight: () => _focusChoice(index),
                                    onPressed: () =>
                                        unawaited(_activateChoice(index)),
                                  ),
                                )
                              : _TvPlaybackSettingsRow(
                                  icon: widget.choices[index].value ==
                                          widget.selected
                                      ? Icons.check_circle_rounded
                                      : widget.choices[index].icon,
                                  title: widget.choices[index].label,
                                  value: widget.choices[index].value ==
                                          widget.selected
                                      ? 'Active'
                                      : '',
                                  selected: widget.choices[index].value ==
                                      widget.selected,
                                  focusNode: _choiceFocusNodes[index],
                                  onArrowUp: index == 0
                                      ? () => _focusChoice(index)
                                      : () => _focusChoice(index - 1),
                                  onArrowDown:
                                      index == widget.choices.length - 1
                                          ? () => _focusChoice(index)
                                          : () => _focusChoice(index + 1),
                                  onArrowLeft: () => _focusChoice(index),
                                  onArrowRight: () => _focusChoice(index),
                                  onPressed: () =>
                                      unawaited(_activateChoice(index)),
                                ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvSubtitleGroup {
  const _TvSubtitleGroup({
    required this.title,
    required this.providerKey,
    required this.subtitles,
  });

  final String title;
  final String providerKey;
  final List<_TvSubtitle> subtitles;
}

List<_TvSubtitleGroup> _groupTvSubtitles(List<_TvSubtitle> subtitles) {
  final primary = <_TvSubtitle>[];
  final fallback = <_TvSubtitle>[];
  for (final subtitle in subtitles) {
    if (_tvSubtitleProviderKey(subtitle) == 'juicr-subtitle-1') {
      primary.add(subtitle);
    } else {
      fallback.add(subtitle);
    }
  }
  return <_TvSubtitleGroup>[
    if (primary.isNotEmpty)
      _TvSubtitleGroup(
        title: 'Subtitle 1',
        providerKey: 'juicr-subtitle-1',
        subtitles: primary,
      ),
    if (fallback.isNotEmpty)
      _TvSubtitleGroup(
        title: 'Subtitle 2',
        providerKey: 'juicr-subtitle-2',
        subtitles: fallback,
      ),
  ];
}

String _tvSubtitleProviderKey(_TvSubtitle subtitle) {
  final provider = subtitle.provider.trim().toLowerCase();
  if (provider == 'juicr-subtitle-1' ||
      provider == 'subtitle-1' ||
      provider == 'subsense' ||
      provider == 'subsense.js') {
    return 'juicr-subtitle-1';
  }
  if (provider == 'juicr-subtitle-2' ||
      provider == 'subtitle-2' ||
      provider == 'juicr-fallback' ||
      provider == 'juicr-fallback.js' ||
      provider == 'fallback') {
    return 'juicr-subtitle-2';
  }
  final id = subtitle.id.trim().toLowerCase();
  if (id.startsWith('juicr-subtitle-1-') || id.startsWith('subsense-')) {
    return 'juicr-subtitle-1';
  }
  return 'juicr-subtitle-2';
}

class _TvSubtitleCue {
  const _TvSubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;
}

List<_TvSubtitleCue> _parseTvSubtitleCues(String input) {
  final normalized = input
      .replaceAll('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  final directCues = _parseTvSubtitleBlocks(normalized.split('\n\n'));
  if (directCues.isNotEmpty) return directCues;

  final compactBlocks = RegExp(
    r'((?:\d+\s*\n)?\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->\s*\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}[\s\S]*?)(?=\n\s*\d+\s*\n\s*\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->|\z)',
  )
      .allMatches(normalized)
      .map((match) => match.group(1) ?? '')
      .where((block) => block.trim().isNotEmpty)
      .toList();
  return _parseTvSubtitleBlocks(compactBlocks);
}

String _tvSubtitleContentBucket(String input) {
  final sample = input.trimLeft();
  final lower = sample.toLowerCase();
  if (sample.isEmpty) return 'empty';
  if (sample.startsWith('PK')) return 'zip';
  if (lower.startsWith('<!doctype') || lower.startsWith('<html')) {
    return 'html';
  }
  if (lower.startsWith('{') || lower.startsWith('[')) return 'json';
  if (lower.startsWith('webvtt')) return 'webvtt';
  if (lower.startsWith('[script info]') || lower.contains('[events]')) {
    return 'ass';
  }
  if (sample.contains('-->')) return 'timed-text';
  return 'plain';
}

List<_TvSubtitleCue> _parseTvSubtitleBlocks(List<String> blocks) {
  final cues = <_TvSubtitleCue>[];
  for (final block in blocks) {
    final lines = block
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.isNotEmpty &&
              !line.startsWith('WEBVTT') &&
              !line.startsWith('NOTE'),
        )
        .toList();
    if (lines.isEmpty) continue;
    final timingIndex = lines.indexWhere((line) => line.contains('-->'));
    if (timingIndex < 0) continue;
    final parts = lines[timingIndex].split('-->');
    if (parts.length < 2) continue;
    final start = _parseTvSubtitleTime(parts[0]);
    final end = _parseTvSubtitleTime(
      parts[1].trim().split(RegExp(r'\s+')).first,
    );
    if (start == null || end == null || end <= start) continue;
    final text = lines
        .skip(timingIndex + 1)
        .join('\n')
        .replaceAll(RegExp(r'\{\\[^}]+\}'), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
    if (text.isEmpty) continue;
    cues.add(_TvSubtitleCue(start: start, end: end, text: text));
  }
  return cues;
}

Duration? _parseTvSubtitleTime(String raw) {
  final clean = raw.trim().replaceAll(',', '.');
  final parts = clean.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final secondsPart = parts.last.split('.');
  final seconds = int.tryParse(secondsPart.first);
  final millis = secondsPart.length > 1
      ? int.tryParse(secondsPart[1].padRight(3, '0').substring(0, 3)) ?? 0
      : 0;
  final minutes = int.tryParse(parts[parts.length - 2]);
  final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
  if (seconds == null || minutes == null || hours == null) return null;
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}

class _TvSubtitleOverlay extends StatelessWidget {
  const _TvSubtitleOverlay({
    required this.text,
    required this.settings,
    required this.controlsVisible,
  });

  final String text;
  final _TvSettingsState settings;
  final bool controlsVisible;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final fontSize = switch (settings.subtitleTextSize) {
      'Small' => 18.0,
      'Large' => 27.0,
      'Maximum' => 34.0,
      _ => 22.0,
    };
    final textColor = switch (settings.subtitleTextColor) {
      'Yellow' => const Color(0xFFFFF176),
      'Cyan' => const Color(0xFF80DEEA),
      'Green' => _tvAccentColor,
      _ => Colors.white,
    };
    final backgroundOpacity = switch (settings.subtitleBackground) {
      'Off' => 0.0,
      'Solid' => 0.88,
      _ => 0.62,
    };
    final bottomOffset = controlsVisible ? 118.0 : 54.0;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(48, 0, 48, bottomOffset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(860.0, size.width - 96),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: backgroundOpacity),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  softWrap: true,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    height: 1.22,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvNowPlayingTitleReveal extends StatefulWidget {
  const _TvNowPlayingTitleReveal({
    required this.title,
    required this.episodeLabel,
    required this.accentColor,
  });

  final String title;
  final String? episodeLabel;
  final Color accentColor;

  @override
  State<_TvNowPlayingTitleReveal> createState() =>
      _TvNowPlayingTitleRevealState();
}

class _TvNowPlayingTitleRevealState extends State<_TvNowPlayingTitleReveal> {
  Timer? _titleTimer;
  bool _labelVisible = false;
  bool _titleVisible = false;

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(covariant _TvNowPlayingTitleReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.episodeLabel != widget.episodeLabel) {
      _reveal();
    }
  }

  @override
  void dispose() {
    _titleTimer?.cancel();
    super.dispose();
  }

  void _reveal() {
    _titleTimer?.cancel();
    _labelVisible = true;
    _titleVisible = false;
    _titleTimer = Timer(const Duration(milliseconds: 130), () {
      if (!mounted) return;
      setState(() => _titleVisible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title.trim().isEmpty ? 'Now playing' : widget.title;
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TvNowPlayingRevealLine(
            visible: _labelVisible,
            offset: -0.12,
            child: Text(
              'NOW PLAYING',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.accentColor,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                height: 1,
                shadows: const [
                  Shadow(color: Colors.black, blurRadius: 12),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          _TvNowPlayingRevealLine(
            visible: _titleVisible,
            offset: 0.12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                      shadows: [
                        Shadow(color: Colors.black, blurRadius: 12),
                      ],
                    ),
                  ),
                ),
                if (widget.episodeLabel != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    widget.episodeLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 12),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TvNowPlayingRevealLine extends StatelessWidget {
  const _TvNowPlayingRevealLine({
    required this.visible,
    required this.offset,
    required this.child,
  });

  final bool visible;
  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: _tvDuration(180),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : Offset(0, offset),
        duration: _tvDuration(220),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

class _TvPlaybackTopBar extends StatelessWidget {
  const _TvPlaybackTopBar({
    required this.title,
    required this.episodeLabel,
    required this.accentColor,
    required this.showNextEpisode,
    required this.nextEpisodeLabel,
    required this.backFocusNode,
    required this.nextEpisodeFocusNode,
    required this.onBack,
    required this.onNextEpisode,
    required this.onFocusMainControls,
    required this.onFocusBack,
  });

  final String title;
  final String? episodeLabel;
  final Color accentColor;
  final bool showNextEpisode;
  final String nextEpisodeLabel;
  final FocusNode backFocusNode;
  final FocusNode nextEpisodeFocusNode;
  final VoidCallback onBack;
  final VoidCallback onNextEpisode;
  final VoidCallback onFocusMainControls;
  final VoidCallback onFocusBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _TvTextButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              focusNode: backFocusNode,
              onPressed: onBack,
              onArrowRight: showNextEpisode
                  ? () => nextEpisodeFocusNode.requestFocus()
                  : null,
              onArrowDown: onFocusMainControls,
            ),
          ),
          Positioned.fill(
            left: 190,
            right: 190,
            child: Center(
              child: _TvNowPlayingTitleReveal(
                title: title,
                episodeLabel: episodeLabel,
                accentColor: accentColor,
              ),
            ),
          ),
          if (showNextEpisode)
            Align(
              alignment: Alignment.centerRight,
              child: _TvTextButton(
                icon: Icons.skip_next_rounded,
                label: nextEpisodeLabel,
                focusNode: nextEpisodeFocusNode,
                onPressed: onNextEpisode,
                onArrowLeft: () => backFocusNode.requestFocus(),
                onArrowUp: onFocusBack,
                onArrowDown: onFocusMainControls,
              ),
            ),
        ],
      ),
    );
  }
}

class _TvPlaybackActionRow extends StatelessWidget {
  const _TvPlaybackActionRow({
    required this.locked,
    required this.showEpisodes,
    required this.skipSegment,
    required this.skipSegmentFocusNode,
    required this.episodesFocusNode,
    required this.sourcesFocusNode,
    required this.settingsFocusNode,
    required this.lockFocusNode,
    required this.onLockPressed,
    required this.onEpisodesPressed,
    required this.onSourcesPressed,
    required this.onSettingsPressed,
    required this.onFocusMainControls,
    required this.onFocusProgress,
    required this.onSkipSegmentPressed,
  });

  final bool locked;
  final bool showEpisodes;
  final _TvPlayerSkipSegment? skipSegment;
  final FocusNode skipSegmentFocusNode;
  final FocusNode episodesFocusNode;
  final FocusNode sourcesFocusNode;
  final FocusNode settingsFocusNode;
  final FocusNode lockFocusNode;
  final VoidCallback onLockPressed;
  final VoidCallback onEpisodesPressed;
  final VoidCallback onSourcesPressed;
  final VoidCallback onSettingsPressed;
  final VoidCallback onFocusMainControls;
  final VoidCallback onFocusProgress;
  final VoidCallback? onSkipSegmentPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (!locked && skipSegment != null && onSkipSegmentPressed != null)
          _TvPlaybackPillButton(
            icon: Icons.skip_next_rounded,
            label: skipSegment!.label,
            focusNode: skipSegmentFocusNode,
            onPressed: onSkipSegmentPressed,
            onArrowRight: () => (showEpisodes
                    ? episodesFocusNode
                    : sourcesFocusNode)
                .requestFocus(),
            onArrowUp: onFocusMainControls,
            onArrowDown: () => sourcesFocusNode.requestFocus(),
          ),
        const Spacer(),
        if (!locked) ...[
          if (showEpisodes) ...[
            _TvPlaybackPillButton(
              icon: Icons.video_collection_rounded,
              label: 'Episodes',
              focusNode: episodesFocusNode,
              onPressed: onEpisodesPressed,
              onArrowLeft: skipSegment != null && onSkipSegmentPressed != null
                  ? () => skipSegmentFocusNode.requestFocus()
                  : () => lockFocusNode.requestFocus(),
              onArrowRight: () => sourcesFocusNode.requestFocus(),
              onArrowUp: skipSegment != null && onSkipSegmentPressed != null
                  ? () => skipSegmentFocusNode.requestFocus()
                  : onFocusMainControls,
              onArrowDown: onFocusProgress,
            ),
            const SizedBox(width: _tvSpacing),
          ],
          _TvPlaybackPillButton(
            icon: Icons.video_library_rounded,
            label: 'Sources',
            focusNode: sourcesFocusNode,
            onPressed: onSourcesPressed,
            onArrowLeft: showEpisodes
                ? () => episodesFocusNode.requestFocus()
                : skipSegment != null && onSkipSegmentPressed != null
                    ? () => skipSegmentFocusNode.requestFocus()
                    : () => lockFocusNode.requestFocus(),
            onArrowRight: () => settingsFocusNode.requestFocus(),
            onArrowUp: skipSegment != null && onSkipSegmentPressed != null
                ? () => skipSegmentFocusNode.requestFocus()
                : onFocusMainControls,
            onArrowDown: onFocusProgress,
          ),
          const SizedBox(width: _tvSpacing),
          _TvPlaybackPillButton(
            icon: Icons.settings_rounded,
            label: 'Settings',
            focusNode: settingsFocusNode,
            onPressed: onSettingsPressed,
            onArrowLeft: () => sourcesFocusNode.requestFocus(),
            onArrowRight: () => lockFocusNode.requestFocus(),
            onArrowUp: skipSegment != null && onSkipSegmentPressed != null
                ? () => skipSegmentFocusNode.requestFocus()
                : onFocusMainControls,
            onArrowDown: onFocusProgress,
          ),
          const SizedBox(width: _tvSpacing),
        ],
        _TvPlaybackPillButton(
          icon: locked ? Icons.lock_rounded : Icons.lock_open_rounded,
          label: locked ? 'Unlock' : 'Lock',
          focusNode: lockFocusNode,
          onPressed: onLockPressed,
          onArrowLeft: locked
              ? onFocusMainControls
              : () => settingsFocusNode.requestFocus(),
          onArrowUp:
              !locked && skipSegment != null && onSkipSegmentPressed != null
                  ? () => skipSegmentFocusNode.requestFocus()
                  : onFocusMainControls,
          onArrowDown: onFocusProgress,
        ),
      ],
    );
  }
}

class _TvPlayerSkipSegment {
  const _TvPlayerSkipSegment({required this.label, required this.target});

  final String label;
  final Duration target;
}

class _TvPlaybackSourceGroup {
  const _TvPlaybackSourceGroup({
    required this.quality,
    required this.sessionIndexes,
  });

  final String quality;
  final List<int> sessionIndexes;

  bool contains(int sessionIndex) => sessionIndexes.contains(sessionIndex);

  String get label {
    final mirrorCount = sessionIndexes.length;
    final mirrorLabel = mirrorCount == 1 ? 'mirror' : 'mirrors';
    return '$quality - $mirrorCount $mirrorLabel';
  }
}

class _TvFocusedHorizontalMarquee extends StatefulWidget {
  const _TvFocusedHorizontalMarquee({
    required this.text,
    required this.active,
    required this.style,
    this.scrollKey,
  });

  final String text;
  final bool active;
  final TextStyle style;
  final Key? scrollKey;

  @override
  State<_TvFocusedHorizontalMarquee> createState() =>
      _TvFocusedHorizontalMarqueeState();
}

class _TvFocusedHorizontalMarqueeState
    extends State<_TvFocusedHorizontalMarquee> {
  final ScrollController _controller = ScrollController();
  Timer? _startTimer;
  int _animationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _TvFocusedHorizontalMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active || oldWidget.text != widget.text) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _animationGeneration += 1;
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    final generation = ++_animationGeneration;
    _startTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _animationGeneration) return;
      if (!widget.active) {
        if (_controller.hasClients) _controller.jumpTo(0);
        return;
      }
      _startTimer = Timer(_tvDuration(320), () {
        if (!mounted ||
            !widget.active ||
            generation != _animationGeneration) {
          return;
        }
        unawaited(_runMarquee(generation));
      });
    });
  }

  Future<void> _runMarquee(int generation) async {
    if (!mounted ||
        !widget.active ||
        generation != _animationGeneration ||
        !_controller.hasClients) {
      return;
    }
    final extent = _controller.position.maxScrollExtent;
    if (extent <= 0) return;
    final travelMillis = (extent * 24).round().clamp(900, 4200);
    await _controller.animateTo(
      extent,
      duration: _tvDuration(travelMillis),
      curve: Curves.linear,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SingleChildScrollView(
        key: widget.scrollKey,
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        ),
      ),
    );
  }
}

class _TvSourceGroupButton extends StatelessWidget {
  const _TvSourceGroupButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.selected = false,
    this.autofocus = false,
    this.enabled = true,
    this.animateIcon = false,
    this.imageUrl,
    this.pendingIcon,
    this.marqueeSubtitleOnFocus = false,
    this.marqueeKey,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
    this.minHeight = 58,
    this.horizontalPadding = 14,
    this.verticalPadding = 10,
    this.iconSize = 20,
    this.fontSize = 15,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;
  final bool selected;
  final bool autofocus;
  final bool enabled;
  final bool animateIcon;
  final String? imageUrl;
  final IconData? pendingIcon;
  final bool marqueeSubtitleOnFocus;
  final Key? marqueeKey;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final double minHeight;
  final double horizontalPadding;
  final double verticalPadding;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
      enabled: enabled,
      focusNode: focusNode,
      onPressed: onPressed,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) {
        final active = focused && enabled;
        final selectedOrActive = selected || active;
        final foreground = selectedOrActive ? Colors.black : Colors.white;
        final secondary = selectedOrActive
            ? const Color(0xDD000000)
            : const Color(0xFFB8B3C8);
        return AnimatedContainer(
          duration: _tvDuration(130),
          constraints: BoxConstraints(minHeight: minHeight),
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            color: selectedOrActive ? _tvAccentColor : const Color(0x24FFFFFF),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: active
                  ? _tvSolidFocusBorder
                  : selected
                      ? const Color(0xAAFFFFFF)
                      : const Color(0x22FFFFFF),
              width: active ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (animateIcon)
                _LoopingIcon(icon: pendingIcon ?? icon, color: foreground)
              else if ((imageUrl ?? '').trim().isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 76,
                    height: 44,
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        icon,
                        color: foreground,
                        size: iconSize,
                      ),
                    ),
                  ),
                )
              else
                Icon(icon, color: foreground, size: iconSize),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      if (marqueeSubtitleOnFocus)
                        _TvFocusedHorizontalMarquee(
                          scrollKey: marqueeKey,
                          text: subtitle,
                          active: active,
                          style: TextStyle(
                            color: secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        )
                      else
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvPlaybackPillButton extends StatelessWidget {
  const _TvPlaybackPillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      enabled: onPressed != null,
      focusNode: focusNode,
      onPressed: onPressed ?? () {},
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(140),
          padding: const EdgeInsets.symmetric(
            horizontal: _tvSpacing,
            vertical: _tvSpacing,
          ),
          decoration: BoxDecoration(
            color: focused ? _tvAccentColor : const Color(0xAA111217),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused ? _tvFocusBorder : const Color(0x22FFFFFF),
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: focused ? Colors.black : const Color(0xFFE8E4F5),
                size: 22,
              ),
              const SizedBox(width: _tvSpacing),
              Text(
                label,
                style: TextStyle(
                  color: focused ? Colors.black : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvPlaybackFeedbackOverlay extends StatelessWidget {
  const _TvPlaybackFeedbackOverlay({required this.feedback});

  final _TvPlaybackFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final icon = feedback.skipDirection < 0
        ? Icons.replay_rounded
        : feedback.skipDirection > 0
            ? Icons.forward_rounded
            : feedback.icon;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: _TvPlaybackPulseButton(icon: icon),
        ),
      ),
    );
  }
}

class _TvPlaybackPulseButton extends StatelessWidget {
  const _TvPlaybackPulseButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: _tvAccentColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x77000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.black, size: 46),
    );
  }
}

class _TvPlaybackBufferingIndicator extends StatelessWidget {
  const _TvPlaybackBufferingIndicator();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            width: 74,
            height: 74,
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.54),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x40FFFFFF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: _tvAccentColor,
              backgroundColor: const Color(0x33FFFFFF),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvPlaybackFeedback {
  const _TvPlaybackFeedback(
    this.icon,
    this.label, {
    required this.seeking,
    required this.skipDirection,
  });

  final IconData icon;
  final String label;
  final bool seeking;
  final int skipDirection;
}

class _TvPlaybackCenterControls extends StatelessWidget {
  const _TvPlaybackCenterControls({
    required this.initialized,
    required this.playing,
    this.feedbackIcon,
    required this.showNextEpisode,
    required this.skipSegmentAvailable,
    required this.showSeekControls,
    required this.skipBackFocusNode,
    required this.playFocusNode,
    required this.skipForwardFocusNode,
    required this.nextEpisodeFocusNode,
    required this.backFocusNode,
    required this.skipSegmentFocusNode,
    required this.sourcesFocusNode,
    required this.onTogglePlay,
    required this.onSeekBack,
    required this.onSeekForward,
  });

  final bool initialized;
  final bool playing;
  final IconData? feedbackIcon;
  final bool showNextEpisode;
  final bool skipSegmentAvailable;
  final bool showSeekControls;
  final FocusNode skipBackFocusNode;
  final FocusNode playFocusNode;
  final FocusNode skipForwardFocusNode;
  final FocusNode nextEpisodeFocusNode;
  final FocusNode backFocusNode;
  final FocusNode skipSegmentFocusNode;
  final FocusNode sourcesFocusNode;
  final Future<void> Function() onTogglePlay;
  final Future<void> Function() onSeekBack;
  final Future<void> Function() onSeekForward;

  void _focusAbove() {
    if (showNextEpisode) {
      nextEpisodeFocusNode.requestFocus();
    } else {
      backFocusNode.requestFocus();
    }
  }

  void _focusBelow() {
    if (skipSegmentAvailable) {
      skipSegmentFocusNode.requestFocus();
    } else {
      sourcesFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(120, 92, 120, 118),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: showSeekControls
                    ? _TvPlaybackSkipButton(
                        direction: -1,
                        label: 'Back 15 seconds',
                        size: 72,
                        focusNode: skipBackFocusNode,
                        onPressed:
                            initialized ? () => unawaited(onSeekBack()) : null,
                        onArrowRight: () => playFocusNode.requestFocus(),
                        onArrowUp: _focusAbove,
                        onArrowDown: _focusBelow,
                      )
                    : const SizedBox.shrink(),
              ),
              Align(
                alignment: Alignment.center,
                child: _TvPlaybackRoundButton(
                  icon: feedbackIcon ??
                      (playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                  label: playing ? 'Pause' : 'Play',
                  size: 96,
                  accent: true,
                  focusNode: playFocusNode,
                  onPressed:
                      initialized ? () => unawaited(onTogglePlay()) : null,
                  onArrowLeft: showSeekControls
                      ? () => skipBackFocusNode.requestFocus()
                      : null,
                  onArrowRight: showSeekControls
                      ? () => skipForwardFocusNode.requestFocus()
                      : () => sourcesFocusNode.requestFocus(),
                  onArrowUp: _focusAbove,
                  onArrowDown: _focusBelow,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: showSeekControls
                    ? _TvPlaybackSkipButton(
                        direction: 1,
                        label: 'Forward 15 seconds',
                        size: 72,
                        focusNode: skipForwardFocusNode,
                        onPressed: initialized
                            ? () => unawaited(onSeekForward())
                            : null,
                        onArrowLeft: () => playFocusNode.requestFocus(),
                        onArrowUp: _focusAbove,
                        onArrowDown: _focusBelow,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvPlaybackLoadingState extends StatefulWidget {
  const _TvPlaybackLoadingState({required this.item, required this.status});

  final _TvItem item;
  final String status;

  @override
  State<_TvPlaybackLoadingState> createState() =>
      _TvPlaybackLoadingStateState();
}

class _TvPlaybackLoadingStateState extends State<_TvPlaybackLoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _tvDuration(1250),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = (widget.item.logo ?? '').trim();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final eased = Curves.easeInOut.transform(_controller.value);
        return Opacity(
          opacity: 0.72 + eased * 0.28,
          child: child,
        );
      },
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 420,
              child: logo.isNotEmpty
                  ? Image.network(
                      logo,
                      height: 150,
                      fit: BoxFit.contain,
                      cacheWidth: 840,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox(
                          height: 150,
                          child: Center(
                            child: _TvShimmerBox(
                              width: 320,
                              height: 72,
                              radius: 14,
                              alpha: 0.42,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) =>
                          _TvPlaybackLoadingTitle(title: widget.item.title),
                    )
                  : _TvPlaybackLoadingTitle(title: widget.item.title),
            ),
            const SizedBox(height: 18),
            _TvAnimatedLoadingText(
              label: widget.status,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFC9C3DA),
                fontSize: 16,
                height: 1.25,
                fontWeight: FontWeight.w800,
                shadows: [
                  Shadow(
                    color: Color(0xAA000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvAnimatedLoadingText extends StatefulWidget {
  const _TvAnimatedLoadingText({
    required this.label,
    required this.style,
    this.textAlign,
  });

  final String label;
  final TextStyle style;
  final TextAlign? textAlign;

  @override
  State<_TvAnimatedLoadingText> createState() => _TvAnimatedLoadingTextState();
}

class _TvAnimatedLoadingTextState extends State<_TvAnimatedLoadingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _tvDuration(1200),
  );

  bool get _hasAnimatedDots => widget.label.contains('...');

  @override
  void initState() {
    super.initState();
    if (_hasAnimatedDots) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _TvAnimatedLoadingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasAnimatedDots && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_hasAnimatedDots && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _animatedLabel() {
    if (!_hasAnimatedDots) return widget.label;
    final markerIndex = widget.label.indexOf('...');
    if (markerIndex < 0) return widget.label;
    final prefix = widget.label.substring(0, markerIndex);
    final suffix = widget.label.substring(markerIndex + 3);
    final startsWithDot = prefix.endsWith('.');
    final phaseCount = startsWithDot ? 3 : 4;
    final phase = (_controller.value * phaseCount).floor().clamp(
          0,
          phaseCount - 1,
        );
    final dotCount = startsWithDot ? phase + 1 : phase;
    return '$prefix${List.filled(dotCount, '.').join()}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    Widget text(String label) {
      return Text(
        label,
        textAlign: widget.textAlign,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    }

    if (!_hasAnimatedDots) return text(widget.label);
    return Semantics(
      label: widget.label.replaceAll('\n', ' '),
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => text(_animatedLabel()),
        ),
      ),
    );
  }
}

class _TvPlaybackLoadingTitle extends StatelessWidget {
  const _TvPlaybackLoadingTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 34,
        height: 1.05,
        fontWeight: FontWeight.w900,
        shadows: [
          Shadow(
            color: Color(0xAA000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
    );
  }
}

class _TvPlaybackTransportHud extends StatelessWidget {
  const _TvPlaybackTransportHud({
    required this.initialized,
    required this.position,
    required this.duration,
    required this.focusNode,
    required this.onSeekBack,
    required this.onSeekForward,
  });

  final bool initialized;
  final Duration position;
  final Duration duration;
  final FocusNode focusNode;
  final Future<void> Function() onSeekBack;
  final Future<void> Function() onSeekForward;

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            _formatDuration(position),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: _tvSpacing),
        Expanded(
          child: _TvPlaybackProgressScrubber(
            focusNode: focusNode,
            initialized: initialized,
            progress: progress,
            onSeekBack: onSeekBack,
            onSeekForward: onSeekForward,
          ),
        ),
        const SizedBox(width: _tvSpacing),
        SizedBox(
          width: 64,
          child: Text(
            _formatDuration(duration),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _TvPlaybackProgressScrubber extends StatefulWidget {
  const _TvPlaybackProgressScrubber({
    required this.focusNode,
    required this.initialized,
    required this.progress,
    required this.onSeekBack,
    required this.onSeekForward,
  });

  final FocusNode focusNode;
  final bool initialized;
  final double progress;
  final Future<void> Function() onSeekBack;
  final Future<void> Function() onSeekForward;

  @override
  State<_TvPlaybackProgressScrubber> createState() =>
      _TvPlaybackProgressScrubberState();
}

class _TvPlaybackProgressScrubberState
    extends State<_TvPlaybackProgressScrubber> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_syncFocus);
  }

  @override
  void didUpdateWidget(covariant _TvPlaybackProgressScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    oldWidget.focusNode.removeListener(_syncFocus);
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_syncFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_syncFocus);
    super.dispose();
  }

  void _syncFocus() {
    if (!mounted) return;
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: widget.initialized,
      child: GestureDetector(
        onTap: widget.initialized ? widget.focusNode.requestFocus : null,
        child: AnimatedContainer(
          duration: _tvDuration(130),
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _focused ? _tvFocusBorder : Colors.transparent,
              width: _focused ? 2 : 0,
            ),
          ),
          child: SizedBox(
            height: _focused ? 18 : 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(color: Color(0x44FFFFFF)),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: widget.initialized ? widget.progress : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: _tvAccentColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvPlaybackRoundButton extends StatelessWidget {
  const _TvPlaybackRoundButton({
    required this.icon,
    required this.label,
    required this.size,
    required this.onPressed,
    this.accent = false,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
  });

  final IconData icon;
  final String label;
  final double size;
  final VoidCallback? onPressed;
  final bool accent;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      enabled: onPressed != null,
      focusNode: focusNode,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      onPressed: onPressed ?? () {},
      builder: (focused) {
        final active = accent || focused;
        return AnimatedScale(
          scale: focused ? 1.08 : 1,
          duration: _tvDuration(130),
          child: Semantics(
            button: true,
            label: label,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? _tvAccentColor : const Color(0xAA111217),
                border: Border.all(
                  color: focused ? Colors.white : const Color(0x22FFFFFF),
                  width: focused ? 3 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: active ? Colors.black : Colors.white,
                size: accent ? 48 : 36,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TvPlaybackSkipButton extends StatefulWidget {
  const _TvPlaybackSkipButton({
    required this.direction,
    required this.label,
    required this.size,
    required this.focusNode,
    required this.onPressed,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
  });

  final int direction;
  final String label;
  final double size;
  final FocusNode focusNode;
  final VoidCallback? onPressed;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  State<_TvPlaybackSkipButton> createState() => _TvPlaybackSkipButtonState();
}

class _TvPlaybackSkipButtonState extends State<_TvPlaybackSkipButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _tvDuration(440),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _press() {
    if (widget.onPressed == null) return;
    _controller
      ..reset()
      ..forward();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final reverse = widget.direction < 0;
    return _TvFocusable(
      enabled: widget.onPressed != null,
      focusNode: widget.focusNode,
      onArrowLeft: widget.onArrowLeft,
      onArrowRight: widget.onArrowRight,
      onArrowUp: widget.onArrowUp,
      onArrowDown: widget.onArrowDown,
      onPressed: _press,
      builder: (focused) {
        final active = focused;
        return AnimatedScale(
          scale: focused ? 1.08 : 1,
          duration: _tvDuration(130),
          child: Semantics(
            button: true,
            label: widget.label,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? _tvAccentColor : const Color(0xAA111217),
                border: Border.all(
                  color: focused ? _tvFocusBorder : const Color(0x22FFFFFF),
                  width: focused ? 3 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RotationTransition(
                    turns:
                        Tween<double>(begin: 0, end: reverse ? -1 : 1).animate(
                      CurvedAnimation(
                        parent: _controller,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: Transform.scale(
                      scaleX: reverse ? 1 : -1,
                      child: Icon(
                        Icons.replay_rounded,
                        color: active ? Colors.black : Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '15',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: active ? Colors.black : Colors.white,
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
