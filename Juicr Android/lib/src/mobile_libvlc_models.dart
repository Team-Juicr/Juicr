import 'dart:convert';
import 'dart:collection';

bool mobileFirstPartyOpaqueMediaCapability(Uri? uri) {
  if (uri == null ||
      uri.scheme != 'https' ||
      !const <String>{'asia.juicr.app', 'us.juicr.app'}.contains(uri.host) ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  return RegExp(
    r'^/playback/media/[a-f0-9]{64}/\d{1,5}(?:\.(?:m3u8|m4s|mp4|ts|aac|vtt|key|bin))?$',
    caseSensitive: false,
  ).hasMatch(uri.path);
}

enum MobileLibVlcState {
  idle,
  resolving,
  prebuffering,
  opening,
  proving,
  playing,
  buffering,
  recovering,
  failed,
  closed,
}

enum MobileLibVlcFailureKind {
  cancelled,
  startupTimeout,
  driverError,
  transportFailure,
  frozenVideo,
  sourceExhausted,
}

enum MobileLibVlcTransportFailureClass {
  transient,
  authSessionUnreadable,
}

enum MobileLibVlcOpenReason {
  initial,
  resume,
  recovery,
  sourceSwitch,
  explicitStartOver,
  episodeTransition,
}

enum MobileLibVlcHealthStatus {
  healthy,
  buffering,
  stalled,
  ended,
  failed,
}

bool deferMobileLibVlcHlsMediaProofToRelay({
  required bool continuousTsRelayCandidate,
}) {
  return continuousTsRelayCandidate;
}

bool hasEstablishedMobileLibVlcHlsLead({
  required bool startupLeadReady,
  required int emittedSegments,
  required int stagedStartupSegments,
}) {
  if (!startupLeadReady) return false;
  return emittedSegments > 0 && stagedStartupSegments == 0;
}

final class MobileLibVlcLaunchRejectionCircuit {
  int _generation = 0;
  Set<String> _rejectedTransportSessions = <String>{};
  bool _disposed = false;

  int beginLaunch() {
    if (_disposed) {
      throw StateError('The libVLC launch circuit is disposed.');
    }
    _generation += 1;
    _rejectedTransportSessions = <String>{};
    return _generation;
  }

  Set<String> rejectedSessionsFor(int generation) {
    if (_disposed || generation != _generation) return <String>{};
    return _rejectedTransportSessions;
  }

  void dispose() {
    _disposed = true;
    _generation += 1;
    _rejectedTransportSessions = <String>{};
  }
}

final class MobileLibVlcSourceCandidate {
  MobileLibVlcSourceCandidate({
    required this.id,
    required this.mirrorGroup,
    required this.qualityLabel,
    required this.uri,
    Map<String, String> headers = const {},
    this.providerId = '',
    this.audioLanguage = '',
    this.requiresTransport = false,
  }) : headers = UnmodifiableMapView(Map<String, String>.from(headers));

  final String id;
  final String mirrorGroup;
  final String qualityLabel;
  final Uri uri;
  final Map<String, String> headers;
  final String providerId;
  final String audioLanguage;
  final bool requiresTransport;

  String get attemptIdentity {
    final context = headers.entries.toList()
      ..sort((left, right) {
        final keyOrder =
            left.key.toLowerCase().compareTo(right.key.toLowerCase());
        return keyOrder != 0 ? keyOrder : left.value.compareTo(right.value);
      });
    final fingerprintInput = <String>[
      uri.toString(),
      for (final entry in context)
        '${entry.key.toLowerCase().trim()}:${entry.value.trim()}',
    ].join('\n');
    return [
      id.trim(),
      mirrorGroup.trim().toLowerCase(),
      qualityLabel.trim().toLowerCase(),
      _stableFingerprint(fingerprintInput),
    ].join('|');
  }

  String get transportSessionIdentity {
    final context = headers.entries.toList()
      ..sort((left, right) {
        final keyOrder =
            left.key.toLowerCase().compareTo(right.key.toLowerCase());
        return keyOrder != 0 ? keyOrder : left.value.compareTo(right.value);
      });
    final authority = <String>[
      uri.scheme.toLowerCase(),
      uri.userInfo,
      uri.host.toLowerCase(),
      if (uri.hasPort) uri.port.toString(),
    ].join('|');
    final fingerprintInput = <String>[
      providerId.trim().toLowerCase(),
      mirrorGroup.trim().toLowerCase(),
      authority,
      uri.query,
      for (final entry in context)
        '${entry.key.toLowerCase().trim()}:${entry.value.trim()}',
    ].join('\n');
    return 'hls-session:${_stableFingerprint(fingerprintInput)}';
  }
}

final class MobileLibVlcDriverSnapshot {
  const MobileLibVlcDriverSnapshot({
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isBuffering,
    required this.hasError,
    required this.videoWidth,
    required this.videoHeight,
    this.isInitialized = false,
    this.isEnded = false,
    this.hasUsableVideoFrame = false,
    this.errorMessage,
  });

  const MobileLibVlcDriverSnapshot.idle()
      : position = Duration.zero,
        duration = Duration.zero,
        isPlaying = false,
        isBuffering = false,
        hasError = false,
        videoWidth = 0,
        videoHeight = 0,
        isInitialized = false,
        isEnded = false,
        hasUsableVideoFrame = false,
        errorMessage = null;

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isBuffering;
  final bool hasError;
  final double videoWidth;
  final double videoHeight;
  final bool isInitialized;
  final bool isEnded;
  final bool hasUsableVideoFrame;
  final String? errorMessage;

  bool get hasVideoGeometry => videoWidth > 0 && videoHeight > 0;
  bool get hasVisualProof =>
      isInitialized && hasVideoGeometry && hasUsableVideoFrame;
}

final class MobileLibVlcTransportSnapshot {
  const MobileLibVlcTransportSnapshot({
    required this.totalMediaBytes,
    required this.completedMediaSegments,
    required this.estimatedBufferedPosition,
    this.timelineOffset = Duration.zero,
    this.lastByteAdvanceAt,
    this.lastTransportActivityAt,
    this.terminalFailure,
    this.terminalFailureClass,
  });

  const MobileLibVlcTransportSnapshot.idle()
      : totalMediaBytes = 0,
        completedMediaSegments = 0,
        estimatedBufferedPosition = Duration.zero,
        timelineOffset = Duration.zero,
        lastByteAdvanceAt = null,
        lastTransportActivityAt = null,
        terminalFailure = null,
        terminalFailureClass = null;

  final int totalMediaBytes;
  final int completedMediaSegments;
  final Duration estimatedBufferedPosition;
  final Duration timelineOffset;
  final DateTime? lastByteAdvanceAt;
  final DateTime? lastTransportActivityAt;
  final MobileLibVlcFailureKind? terminalFailure;
  final MobileLibVlcTransportFailureClass? terminalFailureClass;

  bool get hasMediaProof => totalMediaBytes > 0 || completedMediaSegments > 0;
}

final class MobileLibVlcHealthSample {
  const MobileLibVlcHealthSample({
    required this.observedAt,
    required this.driver,
    required this.transport,
    required this.anchor,
  });

  final DateTime observedAt;
  final MobileLibVlcDriverSnapshot driver;
  final MobileLibVlcTransportSnapshot transport;
  final Duration anchor;
}

final class MobileLibVlcOpenResult {
  const MobileLibVlcOpenResult({
    required this.candidate,
    required this.driver,
    required this.anchor,
    required this.generation,
  });

  final MobileLibVlcSourceCandidate candidate;
  final MobileLibVlcDriverSnapshot driver;
  final Duration anchor;
  final int generation;
}

final class MobileLibVlcTerminalFailure {
  MobileLibVlcTerminalFailure({
    required this.kind,
    required this.message,
    required this.anchor,
    Iterable<String> attemptedCandidateIds = const [],
    this.transportFailureClass,
    this.transportMediaProved = false,
  }) : attemptedCandidateIds = List<String>.unmodifiable(attemptedCandidateIds);

  final MobileLibVlcFailureKind kind;
  final String message;
  final Duration anchor;
  final List<String> attemptedCandidateIds;
  final MobileLibVlcTransportFailureClass? transportFailureClass;
  final bool transportMediaProved;
}

Duration preserveMobileLibVlcAnchor({
  required Duration current,
  required Duration candidate,
  required bool explicitSeek,
}) {
  final safeCurrent = current.isNegative ? Duration.zero : current;
  final safeCandidate = candidate.isNegative ? Duration.zero : candidate;
  if (explicitSeek) {
    return safeCandidate;
  }
  return safeCandidate > safeCurrent ? safeCandidate : safeCurrent;
}

Duration preserveMobileLibVlcAbsoluteProgressFloor({
  required Duration proposedPosition,
  required Duration authoritativeAnchor,
  required Duration relayLocalDuration,
  required bool continuousTsAbsoluteTimeline,
  Duration? canonicalContentDuration,
  bool canonicalDurationIsAbsolute = false,
}) {
  final safeProposed =
      proposedPosition.isNegative ? Duration.zero : proposedPosition;
  if (!continuousTsAbsoluteTimeline) return safeProposed;

  var safeAnchor =
      authoritativeAnchor.isNegative ? Duration.zero : authoritativeAnchor;
  final canonicalDuration = canonicalContentDuration;
  if (canonicalDurationIsAbsolute &&
      canonicalDuration != null &&
      canonicalDuration > Duration.zero &&
      safeAnchor > canonicalDuration) {
    safeAnchor = canonicalDuration;
  }
  // relayLocalDuration is intentionally not a clamp for an absolute anchor.
  return safeProposed >= safeAnchor ? safeProposed : safeAnchor;
}

final class MobileLibVlcSeekSettlementBarrier {
  static const Duration _convergenceTolerance = Duration(seconds: 2);
  static const Duration _convergenceProofWindow = Duration(milliseconds: 250);
  static const Duration settlementDecisionWindow = Duration(seconds: 5);

  Duration _target = Duration.zero;
  DateTime? _startedAt;
  DateTime? _convergenceStartedAt;
  bool _settledOnLastAcceptance = false;
  int _generation = 0;

  bool get isSettling => _startedAt != null;
  Duration get nextSeekBase => _target;
  int get generation => _generation;

  int begin({
    required Duration from,
    required Duration target,
    required DateTime observedAt,
  }) {
    final safeFrom = from.isNegative ? Duration.zero : from;
    final safeTarget = target.isNegative ? Duration.zero : target;
    _generation += 1;
    _target = safeTarget;
    _startedAt = safeTarget < safeFrom ? observedAt : null;
    _convergenceStartedAt = null;
    _settledOnLastAcceptance = false;
    return _generation;
  }

  Duration acceptedPosition({
    required Duration nativePosition,
    required DateTime observedAt,
  }) {
    final safeNative =
        nativePosition.isNegative ? Duration.zero : nativePosition;
    _settledOnLastAcceptance = false;
    if (!isSettling) return safeNative;
    final minimumConvergedPosition = _target > _convergenceTolerance
        ? _target - _convergenceTolerance
        : Duration.zero;
    final converged = safeNative >= minimumConvergedPosition &&
        safeNative <= _target + _convergenceTolerance;
    if (converged) {
      final convergenceStartedAt = _convergenceStartedAt;
      if (convergenceStartedAt == null) {
        _convergenceStartedAt = observedAt;
      } else if (observedAt.difference(convergenceStartedAt) >=
          _convergenceProofWindow) {
        _startedAt = null;
        _convergenceStartedAt = null;
        _settledOnLastAcceptance = true;
        return safeNative;
      }
      return _target;
    }
    _convergenceStartedAt = null;
    return _target;
  }

  Duration constrainComputedPosition({
    required Duration computedPosition,
    required Duration acceptedNativePosition,
  }) {
    final safeComputed =
        computedPosition.isNegative ? Duration.zero : computedPosition;
    if (isSettling) return _target;
    if (_settledOnLastAcceptance) {
      _settledOnLastAcceptance = false;
      return acceptedNativePosition.isNegative
          ? Duration.zero
          : acceptedNativePosition;
    }
    return safeComputed;
  }

  bool decisionOverdue(DateTime observedAt) {
    final startedAt = _startedAt;
    return startedAt != null &&
        observedAt.difference(startedAt) >= settlementDecisionWindow;
  }

  bool isCurrentGeneration(int generation) => generation == _generation;

  void clear() {
    _target = Duration.zero;
    _startedAt = null;
    _convergenceStartedAt = null;
    _settledOnLastAcceptance = false;
    _generation += 1;
  }
}

Duration mobileLibVlcRelayLocalPosition({
  required Duration absolutePosition,
  required Duration timelineOffset,
}) {
  final safeAbsolute =
      absolutePosition.isNegative ? Duration.zero : absolutePosition;
  final safeOffset = timelineOffset.isNegative ? Duration.zero : timelineOffset;
  if (safeAbsolute <= safeOffset) return Duration.zero;
  return safeAbsolute - safeOffset;
}

bool shouldReopenMobileLibVlcRelayForSeek({
  required bool continuousTsActive,
  required Duration target,
  required Duration timelineOffset,
  required Duration bufferedPosition,
  bool transportSeekable = true,
  Duration frontierSafetyMargin = const Duration(seconds: 2),
}) {
  if (!continuousTsActive) return false;
  if (!transportSeekable) return true;
  final safeTarget = target.isNegative ? Duration.zero : target;
  final safeOffset = timelineOffset.isNegative ? Duration.zero : timelineOffset;
  final safeBuffered =
      bufferedPosition.isNegative ? Duration.zero : bufferedPosition;
  final safeMargin =
      frontierSafetyMargin.isNegative ? Duration.zero : frontierSafetyMargin;
  final earliestSeek =
      safeOffset > safeMargin ? safeOffset - safeMargin : Duration.zero;
  final latestSeek =
      safeBuffered > safeMargin ? safeBuffered - safeMargin : Duration.zero;
  return safeTarget < earliestSeek || safeTarget > latestSeek;
}

Duration mobileLibVlcRelayAbsolutePosition({
  required Duration localPosition,
  required Duration timelineOffset,
}) {
  final safeLocal = localPosition.isNegative ? Duration.zero : localPosition;
  final safeOffset = timelineOffset.isNegative ? Duration.zero : timelineOffset;
  return safeOffset + safeLocal;
}

final class MobileLibVlcSessionTimeline {
  MobileLibVlcSessionTimeline({required Duration anchor})
      : _fallbackAnchor = anchor.isNegative ? Duration.zero : anchor;

  Duration _fallbackAnchor;
  Duration _timelineOffset = Duration.zero;
  Duration? _absoluteDriverPosition;

  Duration get absolutePlaybackPosition {
    return _absoluteDriverPosition ?? _fallbackAnchor;
  }

  void recordTimelineOffset(Duration offset) {
    _timelineOffset = offset.isNegative ? Duration.zero : offset;
  }

  void recordDriverPosition(
    Duration position, {
    required bool isInitialized,
  }) {
    if (!isInitialized) return;
    final safePosition = position.isNegative ? Duration.zero : position;
    final absolutePosition = mobileLibVlcRelayAbsolutePosition(
      localPosition: safePosition,
      timelineOffset: _timelineOffset,
    );
    if (absolutePosition < _fallbackAnchor) return;
    final previousPosition = _absoluteDriverPosition;
    if (previousPosition != null && absolutePosition < previousPosition) return;
    _absoluteDriverPosition = absolutePosition;
  }

  Duration localSeekPosition(Duration absolutePosition) {
    _fallbackAnchor =
        absolutePosition.isNegative ? Duration.zero : absolutePosition;
    _absoluteDriverPosition = null;
    return mobileLibVlcRelayLocalPosition(
      absolutePosition: absolutePosition,
      timelineOffset: _timelineOffset,
    );
  }
}

String _stableFingerprint(String value) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
