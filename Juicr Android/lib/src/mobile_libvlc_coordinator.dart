import 'dart:async';

import 'mobile_libvlc_models.dart';

abstract interface class MobileLibVlcDriver {
  MobileLibVlcDriverSnapshot get snapshot;
  Stream<MobileLibVlcDriverSnapshot> get snapshots;
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> dispose();
}

abstract interface class MobileLibVlcTransport {
  Uri get playbackUri;
  MobileLibVlcTransportSnapshot get snapshot;
  Stream<MobileLibVlcTransportSnapshot> get snapshots;
  Future<void> stop();
}

typedef MobileLibVlcDriverFactory = Future<MobileLibVlcDriver> Function(
  MobileLibVlcSourceCandidate candidate,
  Uri playbackUri,
);
typedef MobileLibVlcTransportFactory = Future<MobileLibVlcTransport?> Function(
  MobileLibVlcSourceCandidate candidate,
  Duration anchor,
);
typedef MobileLibVlcFreshResolver = Future<List<MobileLibVlcSourceCandidate>>
    Function();
typedef MobileLibVlcCurrentRefresher = Future<MobileLibVlcSourceCandidate?>
    Function(
  MobileLibVlcSourceCandidate candidate,
);
typedef MobileLibVlcCandidateLifecycle = Future<void> Function(int generation);

MobileLibVlcHealthStatus classifyMobileLibVlcHealth({
  required MobileLibVlcHealthSample previous,
  required MobileLibVlcHealthSample current,
  Duration hardStallAfter = const Duration(seconds: 10),
}) {
  if (current.driver.hasError) {
    return MobileLibVlcHealthStatus.failed;
  }
  if (current.driver.isEnded) {
    if (current.transport.terminalFailure != null) {
      return MobileLibVlcHealthStatus.failed;
    }
    return MobileLibVlcHealthStatus.ended;
  }
  final driverAdvance = current.driver.position - previous.driver.position;
  final driverAdvanced = driverAdvance >= const Duration(milliseconds: 250);
  final observedFor = current.observedAt.difference(previous.observedAt);
  if (driverAdvanced &&
      (current.driver.hasVisualProof ||
          (current.transport.hasMediaProof &&
              !observedFor.isNegative &&
              observedFor >= hardStallAfter))) {
    return MobileLibVlcHealthStatus.healthy;
  }
  if (current.transport.terminalFailure != null) {
    return MobileLibVlcHealthStatus.failed;
  }
  if (driverAdvanced && !current.driver.hasVisualProof) {
    if (!observedFor.isNegative && observedFor >= hardStallAfter) {
      return MobileLibVlcHealthStatus.stalled;
    }
    return MobileLibVlcHealthStatus.buffering;
  }
  final transportAdvanced =
      current.transport.totalMediaBytes > previous.transport.totalMediaBytes ||
          current.transport.completedMediaSegments >
              previous.transport.completedMediaSegments ||
          current.transport.estimatedBufferedPosition >
              previous.transport.estimatedBufferedPosition;
  if (transportAdvanced) {
    return MobileLibVlcHealthStatus.buffering;
  }
  final lastTransportActivityAt = current.transport.lastTransportActivityAt;
  if (lastTransportActivityAt != null) {
    final transportIdleFor =
        current.observedAt.difference(lastTransportActivityAt);
    if (!transportIdleFor.isNegative && transportIdleFor < hardStallAfter) {
      return MobileLibVlcHealthStatus.buffering;
    }
  }
  final elapsed = current.observedAt.difference(previous.observedAt);
  if (current.driver.isBuffering && elapsed < hardStallAfter) {
    return MobileLibVlcHealthStatus.buffering;
  }
  if (elapsed >= hardStallAfter) {
    return MobileLibVlcHealthStatus.stalled;
  }
  return MobileLibVlcHealthStatus.buffering;
}

final class MobileLibVlcCoordinator {
  static const Duration _terminalOwnerCleanupBudget = Duration(
    milliseconds: 500,
  );
  MobileLibVlcCoordinator({
    required MobileLibVlcDriverFactory driverFactory,
    required MobileLibVlcTransportFactory transportFactory,
    required MobileLibVlcFreshResolver freshResolver,
    MobileLibVlcCurrentRefresher? currentRefresher,
    this.startupTimeout = const Duration(seconds: 14),
    this.startupBudget = const Duration(seconds: 60),
    this.freshRecoveryReserve = const Duration(seconds: 30),
    this.freshResolverTimeout = const Duration(seconds: 6),
  })  : _driverFactory = driverFactory,
        _transportFactory = transportFactory,
        _freshResolver = freshResolver,
        _currentRefresher = currentRefresher;

  final MobileLibVlcDriverFactory _driverFactory;
  final MobileLibVlcTransportFactory _transportFactory;
  final MobileLibVlcFreshResolver _freshResolver;
  final MobileLibVlcCurrentRefresher? _currentRefresher;
  final Duration startupTimeout;
  final Duration startupBudget;
  final Duration freshRecoveryReserve;
  final Duration freshResolverTimeout;
  final StreamController<MobileLibVlcState> _states =
      StreamController<MobileLibVlcState>.broadcast(sync: true);

  MobileLibVlcState _state = MobileLibVlcState.idle;
  MobileLibVlcDriver? _driver;
  MobileLibVlcTransport? _transport;
  MobileLibVlcSourceCandidate? _currentCandidate;
  List<MobileLibVlcSourceCandidate> _knownCandidates = const [];
  Duration _anchor = Duration.zero;
  Future<MobileLibVlcOpenResult>? _recoveryFuture;
  Completer<MobileLibVlcDriverSnapshot>? _pendingProof;
  Timer? _healthTimer;
  MobileLibVlcHealthSample? _healthBaseline;
  Duration _healthHardStallAfter = const Duration(seconds: 10);
  void Function(MobileLibVlcOpenResult result)? _onHealthRecovered;
  void Function(MobileLibVlcTerminalFailure failure)? _onHealthFailure;
  bool _healthIsLive = false;
  bool _healthCheckInFlight = false;
  int _healthGeneration = -1;
  int _generation = 0;
  bool _closed = false;

  MobileLibVlcState get state => _state;
  Stream<MobileLibVlcState> get states => _states.stream;
  int get generation => _generation;
  MobileLibVlcDriver? get currentDriver => _driver;
  MobileLibVlcTransport? get currentTransport => _transport;
  MobileLibVlcSourceCandidate? get currentCandidate => _currentCandidate;

  void startHealthMonitoring({
    Duration interval = const Duration(seconds: 2),
    Duration hardStallAfter = const Duration(seconds: 10),
    bool isLive = false,
    void Function(MobileLibVlcOpenResult result)? onRecovered,
    void Function(MobileLibVlcTerminalFailure failure)? onTerminalFailure,
  }) {
    if (_closed) {
      return;
    }
    _healthTimer?.cancel();
    _healthHardStallAfter = hardStallAfter;
    _healthIsLive = isLive;
    _onHealthRecovered = onRecovered;
    _onHealthFailure = onTerminalFailure;
    _healthBaseline = _currentHealthSample();
    _healthGeneration = _generation;
    _healthTimer = Timer.periodic(interval, (_) {
      unawaited(_checkRuntimeHealth());
    });
  }

  void stopHealthMonitoring() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _healthBaseline = null;
    _healthGeneration = -1;
    _healthCheckInFlight = false;
  }

  Future<MobileLibVlcOpenResult> open({
    required List<MobileLibVlcSourceCandidate> candidates,
    required Duration anchor,
    required MobileLibVlcOpenReason reason,
    bool isLive = false,
    Set<String>? rejectedTransportSessions,
    DateTime? routeStartupDeadline,
    Duration Function()? routeStartupRemainingBudget,
  }) async {
    if (_closed) {
      throw MobileLibVlcTerminalFailure(
        kind: MobileLibVlcFailureKind.cancelled,
        message: 'The libVLC playback session is closed.',
        anchor: anchor,
      );
    }
    if (candidates.isEmpty) {
      _publish(MobileLibVlcState.failed, _generation);
      throw MobileLibVlcTerminalFailure(
        kind: MobileLibVlcFailureKind.sourceExhausted,
        message: 'No libVLC source candidates are available.',
        anchor: anchor,
      );
    }

    final generation = ++_generation;
    _knownCandidates = List<MobileLibVlcSourceCandidate>.unmodifiable(
      candidates,
    );
    _anchor = preserveMobileLibVlcAnchor(
      current: Duration.zero,
      candidate: anchor,
      explicitSeek: reason == MobileLibVlcOpenReason.explicitStartOver ||
          reason == MobileLibVlcOpenReason.episodeTransition,
    );

    _publish(MobileLibVlcState.resolving, generation);
    final attempted = <String>[];
    final launchRejectedTransportSessions =
        rejectedTransportSessions ?? <String>{};
    final launchNativeStartupRejectedSessions = <String>{};
    final attemptedIdentities = <String>{};
    MobileLibVlcTerminalFailure? lastFailure;
    final startupDeadline =
        routeStartupDeadline ?? DateTime.now().add(startupBudget);
    final result = await _tryCandidates(
      candidates: candidates,
      attemptedIdentities: attemptedIdentities,
      attemptedForDiagnostics: attempted,
      generation: generation,
      reason: reason,
      isLive: isLive,
      rejectedTransportSessions: launchRejectedTransportSessions,
      nativeStartupRejectedSessions: launchNativeStartupRejectedSessions,
      startupDeadline: startupDeadline,
      remainingStartupBudget: routeStartupRemainingBudget,
      reserveFreshRecovery: true,
      stopAfterFirstFailure: true,
      onFailure: (failure) => lastFailure = failure,
    );
    if (result != null) {
      return result;
    }
    final localRecoveryResult = await _tryCandidates(
      candidates: candidates,
      attemptedIdentities: attemptedIdentities,
      attemptedForDiagnostics: attempted,
      generation: generation,
      reason: MobileLibVlcOpenReason.recovery,
      isLive: isLive,
      rejectedTransportSessions: launchRejectedTransportSessions,
      nativeStartupRejectedSessions: launchNativeStartupRejectedSessions,
      startupDeadline: startupDeadline,
      remainingStartupBudget: routeStartupRemainingBudget,
      reserveFreshRecovery: false,
      onFailure: (failure) => lastFailure = failure,
    );
    if (localRecoveryResult != null) {
      return localRecoveryResult;
    }
    if (attempted.isNotEmpty || launchRejectedTransportSessions.isNotEmpty) {
      _publish(MobileLibVlcState.resolving, generation);
      final remaining = _remainingStartupBudget(
        startupDeadline,
        routeStartupRemainingBudget,
      );
      if (remaining > Duration.zero) {
        List<MobileLibVlcSourceCandidate> freshCandidates;
        try {
          final resolverBudget = _freshResolverBudget(remaining);
          if (resolverBudget <= Duration.zero) {
            throw TimeoutException('No fresh resolver budget remains.');
          }
          freshCandidates = await _freshResolver().timeout(resolverBudget);
          _throwIfStale(generation, _anchor);
        } on TimeoutException {
          lastFailure = _startupBudgetFailure(_anchor);
          freshCandidates = const <MobileLibVlcSourceCandidate>[];
        }
        final freshResult = await _tryCandidates(
          candidates: freshCandidates,
          attemptedIdentities: attemptedIdentities,
          attemptedForDiagnostics: attempted,
          generation: generation,
          reason: MobileLibVlcOpenReason.recovery,
          isLive: isLive,
          rejectedTransportSessions: launchRejectedTransportSessions,
          nativeStartupRejectedSessions: launchNativeStartupRejectedSessions,
          startupDeadline: startupDeadline,
          remainingStartupBudget: routeStartupRemainingBudget,
          reserveFreshRecovery: false,
          onFailure: (failure) => lastFailure = failure,
        );
        if (freshResult != null) {
          _knownCandidates = List<MobileLibVlcSourceCandidate>.unmodifiable(
            <MobileLibVlcSourceCandidate>[
              ..._knownCandidates,
              ...freshCandidates,
            ],
          );
          return freshResult;
        }
      } else {
        lastFailure = _startupBudgetFailure(_anchor);
      }
    }
    _publish(MobileLibVlcState.failed, generation);
    final failure = lastFailure;
    if (failure != null) {
      throw MobileLibVlcTerminalFailure(
        kind: failure.kind,
        message: failure.message,
        anchor: _anchor,
        attemptedCandidateIds: attempted,
        transportFailureClass: failure.transportFailureClass,
        transportMediaProved: failure.transportMediaProved,
      );
    }
    throw MobileLibVlcTerminalFailure(
      kind: MobileLibVlcFailureKind.sourceExhausted,
      message: 'libVLC could not prove any available source.',
      anchor: _anchor,
      attemptedCandidateIds: attempted,
    );
  }

  Future<MobileLibVlcOpenResult> _openCandidate({
    required MobileLibVlcSourceCandidate candidate,
    required int generation,
    required MobileLibVlcOpenReason reason,
    required bool isLive,
    required DateTime startupDeadline,
    Duration Function()? remainingStartupBudget,
  }) async {
    _publish(MobileLibVlcState.prebuffering, generation);
    final transportFuture = _transportFactory(candidate, _anchor);
    final transport = await _awaitTransportWithinBudget(
      transportFuture,
      startupDeadline: startupDeadline,
      remainingStartupBudget: remainingStartupBudget,
    );
    if (_isStale(generation)) {
      await transport?.stop();
      throw _cancelledFailure(_anchor);
    }
    if (candidate.requiresTransport && transport == null) {
      throw MobileLibVlcTerminalFailure(
        kind: MobileLibVlcFailureKind.transportFailure,
        message: 'The selected libVLC source requires a safe transport.',
        anchor: _anchor,
        attemptedCandidateIds: [candidate.attemptIdentity],
      );
    }
    _transport = transport;

    try {
      _publish(MobileLibVlcState.opening, generation);
      final driver = await _awaitRouteOwnedDriver(
        _driverFactory(
          candidate,
          transport?.playbackUri ?? candidate.uri,
        ),
        anchor: _anchor,
        remainingBudget: () => _remainingStartupBudget(
          startupDeadline,
          remainingStartupBudget,
        ),
      );
      if (_isStale(generation)) {
        await driver.dispose();
        throw _cancelledFailure(_anchor);
      }
      _driver = driver;

      await driver.initialize().timeout(
            _remainingStartupBudget(startupDeadline, remainingStartupBudget),
          );
      _throwIfStale(generation, _anchor);
      if (_anchor > Duration.zero) {
        await driver.seekTo(_anchor);
        _throwIfStale(generation, _anchor);
      }
      _publish(MobileLibVlcState.proving, generation);
      final proofTimeout = _shorterDuration(
        isLive ? const Duration(seconds: 12) : startupTimeout,
        _remainingStartupBudget(startupDeadline, remainingStartupBudget),
      );
      final proof = _waitForStartupProof(
        driver: driver,
        transport: transport,
        generation: generation,
        anchor: _anchor,
        timeout: proofTimeout,
      );
      await driver.play();
      if (_anchor > Duration.zero) {
        await driver.seekTo(_anchor);
        _throwIfStale(generation, _anchor);
      }
      final snapshot = await proof;
      _throwIfStale(generation, _anchor);
      _publish(MobileLibVlcState.playing, generation);
      _currentCandidate = candidate;
      _anchor = preserveMobileLibVlcAnchor(
        current: _anchor,
        candidate: _logicalPosition(snapshot, transport),
        explicitSeek: false,
      );
      return MobileLibVlcOpenResult(
        candidate: candidate,
        driver: snapshot,
        anchor: _anchor,
        generation: generation,
      );
    } on MobileLibVlcTerminalFailure catch (failure) {
      final transportMediaProved = failure.transportMediaProved ||
          (transport?.snapshot.hasMediaProof ?? false);
      await _disposeOwned(bounded: remainingStartupBudget != null);
      if (failure.kind == MobileLibVlcFailureKind.cancelled) {
        rethrow;
      }
      throw MobileLibVlcTerminalFailure(
        kind: failure.kind,
        message: failure.message,
        anchor: failure.anchor,
        attemptedCandidateIds: failure.attemptedCandidateIds,
        transportFailureClass: failure.transportFailureClass,
        transportMediaProved: transportMediaProved,
      );
    } on TimeoutException {
      final transportMediaProved = transport?.snapshot.hasMediaProof ?? false;
      await _disposeOwned(bounded: remainingStartupBudget != null);
      final failure = _startupBudgetFailure(_anchor);
      throw MobileLibVlcTerminalFailure(
        kind: failure.kind,
        message: failure.message,
        anchor: failure.anchor,
        attemptedCandidateIds: failure.attemptedCandidateIds,
        transportMediaProved: transportMediaProved,
      );
    } catch (error) {
      await _disposeOwned(bounded: remainingStartupBudget != null);
      if (generation != _generation || _closed) {
        throw _cancelledFailure(_anchor);
      }
      throw MobileLibVlcTerminalFailure(
        kind: MobileLibVlcFailureKind.driverError,
        message: 'libVLC failed to open the selected source: $error',
        anchor: _anchor,
        attemptedCandidateIds: [candidate.attemptIdentity],
      );
    }
  }

  Future<MobileLibVlcOpenResult?> _tryCandidates({
    required Iterable<MobileLibVlcSourceCandidate> candidates,
    required Set<String> attemptedIdentities,
    required List<String> attemptedForDiagnostics,
    required int generation,
    required MobileLibVlcOpenReason reason,
    required bool isLive,
    required Set<String> rejectedTransportSessions,
    required Set<String> nativeStartupRejectedSessions,
    required DateTime startupDeadline,
    Duration Function()? remainingStartupBudget,
    required bool reserveFreshRecovery,
    bool stopAfterFirstFailure = false,
    void Function(MobileLibVlcTerminalFailure failure)? onFailure,
  }) async {
    for (final candidate in candidates) {
      if (rejectedTransportSessions.contains(
            candidate.transportSessionIdentity,
          ) ||
          nativeStartupRejectedSessions.contains(
            candidate.transportSessionIdentity,
          )) {
        continue;
      }
      final remaining = _remainingStartupBudget(
        startupDeadline,
        remainingStartupBudget,
      );
      final attemptBudget =
          reserveFreshRecovery ? remaining - freshRecoveryReserve : remaining;
      if (attemptBudget <= Duration.zero) {
        onFailure?.call(_startupBudgetFailure(_anchor));
        break;
      }
      final identity = candidate.attemptIdentity;
      if (!attemptedIdentities.add(identity)) {
        continue;
      }
      attemptedForDiagnostics.add(identity);
      try {
        final attemptStopwatch = Stopwatch()..start();
        return await _openCandidate(
          candidate: candidate,
          generation: generation,
          reason: reason,
          isLive: isLive,
          startupDeadline: DateTime.now().add(attemptBudget),
          remainingStartupBudget: () =>
              attemptBudget - attemptStopwatch.elapsed,
        );
      } on MobileLibVlcTerminalFailure catch (failure) {
        if (failure.kind == MobileLibVlcFailureKind.cancelled) {
          rethrow;
        }
        if (failure.transportFailureClass ==
            MobileLibVlcTransportFailureClass.authSessionUnreadable) {
          rejectedTransportSessions.add(candidate.transportSessionIdentity);
        }
        if (failure.kind == MobileLibVlcFailureKind.startupTimeout &&
            failure.transportMediaProved) {
          nativeStartupRejectedSessions.add(
            candidate.transportSessionIdentity,
          );
        }
        onFailure?.call(failure);
        _publish(MobileLibVlcState.recovering, generation);
        if (stopAfterFirstFailure) break;
      }
    }
    return null;
  }

  Future<MobileLibVlcOpenResult> recover({
    required MobileLibVlcFailureKind failure,
    required Duration observedPosition,
    bool isLive = false,
  }) {
    _anchor = preserveMobileLibVlcAnchor(
      current: _anchor,
      candidate: observedPosition,
      explicitSeek: false,
    );
    final active = _recoveryFuture;
    if (active != null) {
      return active;
    }
    late final Future<MobileLibVlcOpenResult> operation;
    operation = _recoverInternal(failure: failure, isLive: isLive).whenComplete(
      () {
        if (identical(_recoveryFuture, operation)) {
          _recoveryFuture = null;
        }
      },
    );
    _recoveryFuture = operation;
    return operation;
  }

  Future<MobileLibVlcOpenResult> reopenCurrentSourceAt({
    required Duration anchor,
    required bool wasPlaying,
    bool isLive = false,
    Future<void> Function(int generation)? onGenerationOwned,
    MobileLibVlcCandidateLifecycle? onCandidateInitialized,
    MobileLibVlcCandidateLifecycle? onCandidateRollback,
    Future<void> Function(MobileLibVlcOpenResult result)?
        onBeforePreviousDispose,
  }) async {
    final requestedAnchor = anchor.isNegative ? Duration.zero : anchor;
    await cancelRuntimeRecoveryForExplicitAction(anchor: requestedAnchor);
    final previousDriver = _driver;
    final previousTransport = _transport;
    final candidate = _currentCandidate;
    final rollbackAnchor = _anchor;
    if (_closed || previousDriver == null || candidate == null) {
      throw MobileLibVlcTerminalFailure(
        kind: _closed
            ? MobileLibVlcFailureKind.cancelled
            : MobileLibVlcFailureKind.driverError,
        message: _closed
            ? 'The libVLC playback session is closed.'
            : 'No proved libVLC session is available to seek.',
        anchor: rollbackAnchor,
      );
    }

    final generation = ++_generation;
    final pendingProof = _pendingProof;
    if (pendingProof != null && !pendingProof.isCompleted) {
      pendingProof.completeError(_cancelledFailure(requestedAnchor));
    }
    await onGenerationOwned?.call(generation);
    _throwIfStale(generation, requestedAnchor);

    MobileLibVlcTransport? temporaryTransport;
    MobileLibVlcDriver? temporaryDriver;
    var temporaryPromoted = false;
    var previousPaused = false;
    var candidateInitialized = false;
    try {
      await previousDriver.pause();
      previousPaused = true;
      _throwIfStale(generation, requestedAnchor);

      _publish(MobileLibVlcState.prebuffering, generation);
      temporaryTransport = await _transportFactory(candidate, requestedAnchor);
      _throwIfStale(generation, requestedAnchor);
      if (candidate.requiresTransport && temporaryTransport == null) {
        throw MobileLibVlcTerminalFailure(
          kind: MobileLibVlcFailureKind.transportFailure,
          message: 'The selected libVLC source requires a safe transport.',
          anchor: requestedAnchor,
          attemptedCandidateIds: <String>[candidate.attemptIdentity],
        );
      }

      _publish(MobileLibVlcState.opening, generation);
      temporaryDriver = await _driverFactory(
        candidate,
        temporaryTransport?.playbackUri ?? candidate.uri,
      );
      _throwIfStale(generation, requestedAnchor);
      await temporaryDriver.initialize();
      _throwIfStale(generation, requestedAnchor);
      candidateInitialized = true;
      await onCandidateInitialized?.call(generation);
      _throwIfStale(generation, requestedAnchor);

      _publish(MobileLibVlcState.proving, generation);
      final proof = _waitForStartupProof(
        driver: temporaryDriver,
        transport: temporaryTransport,
        generation: generation,
        anchor: requestedAnchor,
        timeout: isLive ? const Duration(seconds: 12) : startupTimeout,
        requireDecodedVideoProof: true,
      );
      await temporaryDriver.play();
      final snapshot = await proof;
      _throwIfStale(generation, requestedAnchor);
      if (!wasPlaying) {
        await temporaryDriver.pause();
        _throwIfStale(generation, requestedAnchor);
      }

      _driver = temporaryDriver;
      _transport = temporaryTransport;
      _anchor = preserveMobileLibVlcAnchor(
        current: requestedAnchor,
        candidate: _logicalPosition(snapshot, temporaryTransport),
        explicitSeek: false,
      );
      final result = MobileLibVlcOpenResult(
        candidate: candidate,
        driver: snapshot,
        anchor: _anchor,
        generation: generation,
      );
      await onBeforePreviousDispose?.call(result);
      _throwIfStale(generation, requestedAnchor);
      temporaryPromoted = true;
      await _disposeOwners(
        previousDriver,
        previousTransport,
        suppressErrors: true,
      );
      _throwIfStale(generation, requestedAnchor);
      _publish(MobileLibVlcState.playing, generation);
      return result;
    } catch (error) {
      if (!temporaryPromoted) {
        if (candidateInitialized) {
          await onCandidateRollback?.call(generation);
        }
        await _disposeOwners(temporaryDriver, temporaryTransport);
      }
      if (_isStale(generation)) {
        throw _cancelledFailure(requestedAnchor);
      }
      _driver = previousDriver;
      _transport = previousTransport;
      _anchor = rollbackAnchor;
      if (previousPaused && wasPlaying) {
        await previousDriver.play();
      }
      _publish(MobileLibVlcState.playing, generation);
      if (error is MobileLibVlcTerminalFailure) {
        throw MobileLibVlcTerminalFailure(
          kind: error.kind,
          message: error.message,
          anchor: rollbackAnchor,
          attemptedCandidateIds: error.attemptedCandidateIds,
        );
      }
      throw MobileLibVlcTerminalFailure(
        kind: MobileLibVlcFailureKind.driverError,
        message: 'libVLC could not prove the requested seek position.',
        anchor: rollbackAnchor,
        attemptedCandidateIds: <String>[candidate.attemptIdentity],
      );
    }
  }

  Future<void> cancelRuntimeRecoveryForExplicitAction({
    required Duration anchor,
  }) async {
    final activeRecovery = _recoveryFuture;
    if (activeRecovery == null) return;
    final safeAnchor = anchor.isNegative ? Duration.zero : anchor;
    _generation += 1;
    final pendingProof = _pendingProof;
    if (pendingProof != null && !pendingProof.isCompleted) {
      pendingProof.completeError(_cancelledFailure(safeAnchor));
    }
    try {
      await activeRecovery;
    } on MobileLibVlcTerminalFailure catch (failure) {
      if (failure.kind != MobileLibVlcFailureKind.cancelled) rethrow;
    }
    if (_closed) throw _cancelledFailure(safeAnchor);
  }

  Future<MobileLibVlcOpenResult> switchSource({
    required MobileLibVlcSourceCandidate candidate,
    required Duration anchor,
    required bool wasPlaying,
    bool isLive = false,
    Duration Function()? routeStartupRemainingBudget,
    Future<void>? routeStartupCancellation,
    MobileLibVlcCandidateLifecycle? onCandidateInitialized,
    MobileLibVlcCandidateLifecycle? onCandidateRollback,
  }) async {
    final previousDriver = _driver;
    final previousTransport = _transport;
    final previousCandidate = _currentCandidate;
    if (_closed || previousDriver == null || previousCandidate == null) {
      throw MobileLibVlcTerminalFailure(
        kind: _closed
            ? MobileLibVlcFailureKind.cancelled
            : MobileLibVlcFailureKind.driverError,
        message: _closed
            ? 'The libVLC playback session is closed.'
            : 'No proved libVLC session is available to switch.',
        anchor: anchor,
      );
    }

    final preservedAnchor = preserveMobileLibVlcAnchor(
      current: _anchor,
      candidate: anchor,
      explicitSeek: false,
    );
    _anchor = preservedAnchor;
    final generation = ++_generation;
    final pendingProof = _pendingProof;
    if (pendingProof != null && !pendingProof.isCompleted) {
      pendingProof.completeError(_cancelledFailure(preservedAnchor));
    }

    MobileLibVlcTransport? temporaryTransport;
    MobileLibVlcDriver? temporaryDriver;
    var temporaryPromoted = false;
    var candidateInitialized = false;
    try {
      await _awaitRouteOwnedStep<void>(
        previousDriver.pause(),
        anchor: preservedAnchor,
        remainingBudget: routeStartupRemainingBudget,
        cancellation: routeStartupCancellation,
      );
      _throwIfStale(generation, preservedAnchor);

      _publish(MobileLibVlcState.prebuffering, generation);
      temporaryTransport = await _awaitRouteOwnedTransport(
        _transportFactory(candidate, preservedAnchor),
        anchor: preservedAnchor,
        remainingBudget: routeStartupRemainingBudget,
        cancellation: routeStartupCancellation,
      );
      _throwIfStale(generation, preservedAnchor);

      _publish(MobileLibVlcState.opening, generation);
      temporaryDriver = await _awaitRouteOwnedDriver(
        _driverFactory(
          candidate,
          temporaryTransport?.playbackUri ?? candidate.uri,
        ),
        anchor: preservedAnchor,
        remainingBudget: routeStartupRemainingBudget,
        cancellation: routeStartupCancellation,
      );
      _throwIfStale(generation, preservedAnchor);
      await _awaitRouteOwnedStep<void>(
        temporaryDriver.initialize(),
        anchor: preservedAnchor,
        remainingBudget: routeStartupRemainingBudget,
        cancellation: routeStartupCancellation,
      );
      _throwIfStale(generation, preservedAnchor);
      candidateInitialized = true;
      await _awaitRouteOwnedStep<void>(
        onCandidateInitialized?.call(generation) ?? Future<void>.value(),
        anchor: preservedAnchor,
        remainingBudget: routeStartupRemainingBudget,
        cancellation: routeStartupCancellation,
      );
      _throwIfStale(generation, preservedAnchor);
      if (preservedAnchor > Duration.zero) {
        await _awaitRouteOwnedStep<void>(
          temporaryDriver.seekTo(preservedAnchor),
          anchor: preservedAnchor,
          remainingBudget: routeStartupRemainingBudget,
          cancellation: routeStartupCancellation,
        );
        _throwIfStale(generation, preservedAnchor);
      }

      _publish(MobileLibVlcState.proving, generation);
      final proof = _waitForStartupProof(
        driver: temporaryDriver,
        transport: temporaryTransport,
        generation: generation,
        anchor: preservedAnchor,
        timeout: isLive ? const Duration(seconds: 12) : startupTimeout,
      );
      await _awaitRouteOwnedStep<void>(
        temporaryDriver.play(),
        anchor: preservedAnchor,
        remainingBudget: routeStartupRemainingBudget,
        cancellation: routeStartupCancellation,
      );
      if (preservedAnchor > Duration.zero) {
        await _awaitRouteOwnedStep<void>(
          temporaryDriver.seekTo(preservedAnchor),
          anchor: preservedAnchor,
          remainingBudget: routeStartupRemainingBudget,
          cancellation: routeStartupCancellation,
        );
        _throwIfStale(generation, preservedAnchor);
      }
      final snapshot = await _awaitRouteOwnedStep<MobileLibVlcDriverSnapshot>(
        proof,
        anchor: preservedAnchor,
        remainingBudget: routeStartupRemainingBudget,
        cancellation: routeStartupCancellation,
      );
      _throwIfStale(generation, preservedAnchor);
      if (!wasPlaying) {
        await _awaitRouteOwnedStep<void>(
          temporaryDriver.pause(),
          anchor: preservedAnchor,
          remainingBudget: routeStartupRemainingBudget,
          cancellation: routeStartupCancellation,
        );
        _throwIfStale(generation, preservedAnchor);
      }

      _driver = temporaryDriver;
      _transport = temporaryTransport;
      _currentCandidate = candidate;
      _anchor = preserveMobileLibVlcAnchor(
        current: preservedAnchor,
        candidate: _logicalPosition(snapshot, temporaryTransport),
        explicitSeek: false,
      );
      _knownCandidates = List<MobileLibVlcSourceCandidate>.unmodifiable(
        <MobileLibVlcSourceCandidate>[
          candidate,
          ..._knownCandidates.where(
            (known) => known.attemptIdentity != candidate.attemptIdentity,
          ),
        ],
      );
      temporaryPromoted = true;
      await _disposeOwners(
        previousDriver,
        previousTransport,
        suppressErrors: true,
      );
      _throwIfStale(generation, preservedAnchor);
      _publish(MobileLibVlcState.playing, generation);
      return MobileLibVlcOpenResult(
        candidate: candidate,
        driver: snapshot,
        anchor: _anchor,
        generation: generation,
      );
    } catch (error) {
      if (!temporaryPromoted) {
        if (candidateInitialized) {
          await onCandidateRollback?.call(generation);
        }
        await _disposeOwners(
          temporaryDriver,
          temporaryTransport,
          bounded: routeStartupRemainingBudget != null,
        );
      }
      if (_isStale(generation)) {
        throw _cancelledFailure(preservedAnchor);
      }

      _driver = previousDriver;
      _transport = previousTransport;
      _currentCandidate = previousCandidate;
      _anchor = preservedAnchor;
      final previousPosition = _logicalPosition(
        previousDriver.snapshot,
        previousTransport,
      );
      final rollbackDrift = (previousPosition - preservedAnchor).abs();
      final rollback = () async {
        _throwIfStale(generation, preservedAnchor);
        if (preservedAnchor > Duration.zero &&
            (previousPosition <= Duration.zero ||
                rollbackDrift > const Duration(seconds: 5))) {
          await previousDriver.seekTo(preservedAnchor);
          _throwIfStale(generation, preservedAnchor);
        }
        if (wasPlaying) {
          await previousDriver.play();
        } else {
          await previousDriver.pause();
        }
        _throwIfStale(generation, preservedAnchor);
      }();
      if (routeStartupRemainingBudget == null) {
        await rollback;
      } else {
        await rollback.timeout(
          _terminalOwnerCleanupBudget,
          onTimeout: () {},
        );
      }
      _throwIfStale(generation, preservedAnchor);
      _publish(MobileLibVlcState.playing, generation);
      if (error is MobileLibVlcTerminalFailure) {
        rethrow;
      }
      throw MobileLibVlcTerminalFailure(
        kind: MobileLibVlcFailureKind.driverError,
        message: 'libVLC could not prove the selected source.',
        anchor: preservedAnchor,
        attemptedCandidateIds: <String>[candidate.attemptIdentity],
      );
    }
  }

  Future<MobileLibVlcOpenResult> _recoverInternal({
    required MobileLibVlcFailureKind failure,
    required bool isLive,
  }) async {
    if (_closed) {
      throw _cancelledFailure(_anchor);
    }
    final generation = ++_generation;
    final current = _currentCandidate;
    final previousDriver = _driver;
    final previousTransport = _transport;
    final attemptedIdentities = <String>{};
    final attemptedForDiagnostics = <String>[];
    _publish(MobileLibVlcState.recovering, generation);

    final firstStage = <MobileLibVlcSourceCandidate>[];
    if (current != null) {
      final refreshed = await _currentRefresher?.call(current);
      _throwIfStale(generation, _anchor);
      firstStage.add(refreshed ?? current);
      firstStage.addAll(
        _knownCandidates.where(
          (candidate) => candidate.attemptIdentity != current.attemptIdentity,
        ),
      );
    } else {
      firstStage.addAll(_knownCandidates);
    }
    var result = await _tryRecoveryCandidates(
      candidates: firstStage,
      attemptedIdentities: attemptedIdentities,
      attemptedForDiagnostics: attemptedForDiagnostics,
      generation: generation,
      isLive: isLive,
      previousDriver: previousDriver,
      previousTransport: previousTransport,
    );
    if (result != null) {
      return result;
    }

    _publish(MobileLibVlcState.resolving, generation);
    final freshCandidates = await _freshResolver();
    _throwIfStale(generation, _anchor);
    result = await _tryRecoveryCandidates(
      candidates: freshCandidates,
      attemptedIdentities: attemptedIdentities,
      attemptedForDiagnostics: attemptedForDiagnostics,
      generation: generation,
      isLive: isLive,
      previousDriver: previousDriver,
      previousTransport: previousTransport,
    );
    if (result != null) {
      _knownCandidates = List<MobileLibVlcSourceCandidate>.unmodifiable(
        [..._knownCandidates, ...freshCandidates],
      );
      return result;
    }

    await _disposeOwned();
    _throwIfStale(generation, _anchor);
    _publish(MobileLibVlcState.failed, generation);
    throw MobileLibVlcTerminalFailure(
      kind: MobileLibVlcFailureKind.sourceExhausted,
      message: 'libVLC exhausted its bounded recovery ladder after '
          '${failure.name}.',
      anchor: _anchor,
      attemptedCandidateIds: attemptedForDiagnostics,
    );
  }

  Future<MobileLibVlcOpenResult?> _tryRecoveryCandidates({
    required Iterable<MobileLibVlcSourceCandidate> candidates,
    required Set<String> attemptedIdentities,
    required List<String> attemptedForDiagnostics,
    required int generation,
    required bool isLive,
    required MobileLibVlcDriver? previousDriver,
    required MobileLibVlcTransport? previousTransport,
  }) async {
    for (final candidate in candidates) {
      final identity = candidate.attemptIdentity;
      if (!attemptedIdentities.add(identity)) continue;
      attemptedForDiagnostics.add(identity);
      try {
        return await _openRecoveryCandidate(
          candidate: candidate,
          generation: generation,
          isLive: isLive,
          previousDriver: previousDriver,
          previousTransport: previousTransport,
        );
      } on MobileLibVlcTerminalFailure catch (failure) {
        if (failure.kind == MobileLibVlcFailureKind.cancelled) rethrow;
        _publish(MobileLibVlcState.recovering, generation);
      }
    }
    return null;
  }

  Future<MobileLibVlcOpenResult> _openRecoveryCandidate({
    required MobileLibVlcSourceCandidate candidate,
    required int generation,
    required bool isLive,
    required MobileLibVlcDriver? previousDriver,
    required MobileLibVlcTransport? previousTransport,
  }) async {
    MobileLibVlcTransport? temporaryTransport;
    MobileLibVlcDriver? temporaryDriver;
    var promoted = false;
    try {
      _publish(MobileLibVlcState.prebuffering, generation);
      temporaryTransport = await _transportFactory(candidate, _anchor);
      _throwIfStale(generation, _anchor);
      if (candidate.requiresTransport && temporaryTransport == null) {
        throw MobileLibVlcTerminalFailure(
          kind: MobileLibVlcFailureKind.transportFailure,
          message: 'The selected libVLC source requires a safe transport.',
          anchor: _anchor,
          attemptedCandidateIds: <String>[candidate.attemptIdentity],
        );
      }

      _publish(MobileLibVlcState.opening, generation);
      temporaryDriver = await _driverFactory(
        candidate,
        temporaryTransport?.playbackUri ?? candidate.uri,
      );
      _throwIfStale(generation, _anchor);
      await temporaryDriver.initialize();
      _throwIfStale(generation, _anchor);
      if (_anchor > Duration.zero) {
        await temporaryDriver.seekTo(_anchor);
        _throwIfStale(generation, _anchor);
      }

      _publish(MobileLibVlcState.proving, generation);
      final proof = _waitForStartupProof(
        driver: temporaryDriver,
        transport: temporaryTransport,
        generation: generation,
        anchor: _anchor,
        timeout: isLive ? const Duration(seconds: 12) : startupTimeout,
      );
      await temporaryDriver.play();
      if (_anchor > Duration.zero) {
        await temporaryDriver.seekTo(_anchor);
        _throwIfStale(generation, _anchor);
      }
      final snapshot = await proof;
      _throwIfStale(generation, _anchor);

      _driver = temporaryDriver;
      _transport = temporaryTransport;
      _currentCandidate = candidate;
      _anchor = preserveMobileLibVlcAnchor(
        current: _anchor,
        candidate: _logicalPosition(snapshot, temporaryTransport),
        explicitSeek: false,
      );
      promoted = true;
      await _disposeOwners(
        previousDriver,
        previousTransport,
        suppressErrors: true,
      );
      _throwIfStale(generation, _anchor);
      _publish(MobileLibVlcState.playing, generation);
      return MobileLibVlcOpenResult(
        candidate: candidate,
        driver: snapshot,
        anchor: _anchor,
        generation: generation,
      );
    } catch (error) {
      if (!promoted) {
        await _disposeOwners(temporaryDriver, temporaryTransport);
      }
      if (_isStale(generation)) throw _cancelledFailure(_anchor);
      if (error is MobileLibVlcTerminalFailure) rethrow;
      throw MobileLibVlcTerminalFailure(
        kind: MobileLibVlcFailureKind.driverError,
        message: 'libVLC failed to recover the selected source.',
        anchor: _anchor,
        attemptedCandidateIds: <String>[candidate.attemptIdentity],
      );
    }
  }

  Future<void> seekTo(Duration position) async {
    final driver = _driver;
    if (driver == null || _closed) {
      return;
    }
    final target = position.isNegative ? Duration.zero : position;
    _anchor = target;
    await driver.seekTo(target);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    stopHealthMonitoring();
    _closed = true;
    _generation += 1;
    final pendingProof = _pendingProof;
    if (pendingProof != null && !pendingProof.isCompleted) {
      pendingProof.completeError(_cancelledFailure(_anchor));
    }
    await _disposeOwned();
    _state = MobileLibVlcState.closed;
    if (!_states.isClosed) {
      _states.add(MobileLibVlcState.closed);
    }
  }

  MobileLibVlcHealthSample? _currentHealthSample() {
    final driver = _driver;
    if (driver == null) {
      return null;
    }
    return MobileLibVlcHealthSample(
      observedAt: DateTime.now(),
      driver: driver.snapshot,
      transport:
          _transport?.snapshot ?? const MobileLibVlcTransportSnapshot.idle(),
      anchor: _anchor,
    );
  }

  Future<void> _checkRuntimeHealth() async {
    if (_closed || _healthCheckInFlight) {
      return;
    }
    final current = _currentHealthSample();
    if (current == null ||
        (_state != MobileLibVlcState.playing &&
            _state != MobileLibVlcState.buffering)) {
      _healthBaseline = current;
      _healthGeneration = _generation;
      return;
    }
    final previous = _healthBaseline;
    if (previous == null || _healthGeneration != _generation) {
      _healthBaseline = current;
      _healthGeneration = _generation;
      return;
    }

    final status = classifyMobileLibVlcHealth(
      previous: previous,
      current: current,
      hardStallAfter: _healthHardStallAfter,
    );
    if (status == MobileLibVlcHealthStatus.healthy) {
      _anchor = preserveMobileLibVlcAnchor(
        current: _anchor,
        candidate: _logicalPosition(current.driver, _transport),
        explicitSeek: false,
      );
      _healthBaseline = current;
      _publish(MobileLibVlcState.playing, _generation);
      return;
    }
    if (status == MobileLibVlcHealthStatus.buffering) {
      final transportAdvanced = current.transport.totalMediaBytes >
              previous.transport.totalMediaBytes ||
          current.transport.completedMediaSegments >
              previous.transport.completedMediaSegments ||
          current.transport.estimatedBufferedPosition >
              previous.transport.estimatedBufferedPosition;
      final driverAdvanced =
          current.driver.position - previous.driver.position >=
              const Duration(milliseconds: 250);
      if (transportAdvanced && !driverAdvanced) {
        _healthBaseline = current;
      }
      _publish(MobileLibVlcState.buffering, _generation);
      return;
    }
    if (status == MobileLibVlcHealthStatus.ended) {
      stopHealthMonitoring();
      return;
    }

    _healthCheckInFlight = true;
    try {
      final result = await recover(
        failure: status == MobileLibVlcHealthStatus.failed
            ? MobileLibVlcFailureKind.transportFailure
            : MobileLibVlcFailureKind.frozenVideo,
        observedPosition: _logicalPosition(current.driver, _transport),
        isLive: _healthIsLive,
      );
      _healthBaseline = _currentHealthSample();
      _healthGeneration = _generation;
      _onHealthRecovered?.call(result);
    } on MobileLibVlcTerminalFailure catch (failure) {
      if (failure.kind != MobileLibVlcFailureKind.cancelled) {
        _onHealthFailure?.call(failure);
      }
    } finally {
      _healthCheckInFlight = false;
    }
  }

  Duration _logicalPosition(
    MobileLibVlcDriverSnapshot driver,
    MobileLibVlcTransport? transport,
  ) {
    final timelineOffset = transport?.snapshot.timelineOffset ?? Duration.zero;
    if (timelineOffset <= Duration.zero) {
      return driver.position;
    }
    return mobileLibVlcRelayAbsolutePosition(
      localPosition: driver.position,
      timelineOffset: timelineOffset,
    );
  }

  Future<MobileLibVlcDriverSnapshot> _waitForStartupProof({
    required MobileLibVlcDriver driver,
    required MobileLibVlcTransport? transport,
    required int generation,
    required Duration anchor,
    required Duration timeout,
    bool requireDecodedVideoProof = false,
  }) async {
    final completer = Completer<MobileLibVlcDriverSnapshot>();
    _pendingProof = completer;
    final baseline = driver.snapshot.position;
    var lastObservedPosition = baseline;
    var advancingRunStart = baseline;
    var advancingSamples = 0;
    StreamSubscription<MobileLibVlcDriverSnapshot>? driverSubscription;
    StreamSubscription<MobileLibVlcTransportSnapshot>? transportSubscription;
    Timer? timer;
    late void Function(MobileLibVlcDriverSnapshot snapshot) inspect;

    void inspectTransport(MobileLibVlcTransportSnapshot snapshot) {
      if (completer.isCompleted || generation != _generation || _closed) {
        return;
      }
      final failure = snapshot.terminalFailure;
      if (failure != null) {
        completer.completeError(
          MobileLibVlcTerminalFailure(
            kind: failure,
            message: 'The libVLC transport failed before startup proof.',
            anchor: anchor,
            transportFailureClass: snapshot.terminalFailureClass,
          ),
        );
        return;
      }
      inspect(driver.snapshot);
    }

    inspect = (MobileLibVlcDriverSnapshot snapshot) {
      if (completer.isCompleted || generation != _generation || _closed) {
        return;
      }
      if (snapshot.hasError) {
        completer.completeError(
          MobileLibVlcTerminalFailure(
            kind: MobileLibVlcFailureKind.driverError,
            message: snapshot.errorMessage ?? 'libVLC reported an error.',
            anchor: anchor,
          ),
        );
        return;
      }
      final observedDelta = snapshot.position - lastObservedPosition;
      if (observedDelta <= const Duration(seconds: -1)) {
        advancingSamples = 0;
        advancingRunStart = snapshot.position;
      } else if (observedDelta >= const Duration(milliseconds: 100)) {
        if (advancingSamples == 0) {
          advancingRunStart = lastObservedPosition;
        }
        advancingSamples += 1;
      }
      lastObservedPosition = snapshot.position;
      final sustainedAdvance = advancingSamples >= 2 &&
          snapshot.position - advancingRunStart >=
              const Duration(milliseconds: 500);
      final hasVisualOrTransportProof = requireDecodedVideoProof
          ? snapshot.hasVisualProof
          : snapshot.hasVisualProof ||
              (snapshot.isInitialized &&
                  (transport?.snapshot.hasMediaProof ?? false));
      final anchorFloor = anchor > const Duration(seconds: 5)
          ? anchor - const Duration(seconds: 5)
          : Duration.zero;
      final transportSnapshot = transport?.snapshot;
      final timelineOffset = transportSnapshot?.timelineOffset ?? Duration.zero;
      final absolutePosition = timelineOffset > Duration.zero
          ? timelineOffset + snapshot.position
          : snapshot.position;
      final transportCoversAnchor = transportSnapshot != null &&
          timelineOffset > Duration.zero &&
          transportSnapshot.hasMediaProof &&
          transportSnapshot.estimatedBufferedPosition >= anchorFloor;
      final isAtRequestedAnchor =
          absolutePosition >= anchorFloor || transportCoversAnchor;
      if (snapshot.isPlaying &&
          sustainedAdvance &&
          hasVisualOrTransportProof &&
          isAtRequestedAnchor) {
        completer.complete(snapshot);
      }
    };

    driverSubscription = driver.snapshots.listen(
      inspect,
      onError: completer.completeError,
    );
    if (transport != null) {
      transportSubscription = transport.snapshots.listen(
        inspectTransport,
        onError: (Object error, StackTrace stackTrace) {
          if (completer.isCompleted) return;
          completer.completeError(
            MobileLibVlcTerminalFailure(
              kind: MobileLibVlcFailureKind.transportFailure,
              message: 'The libVLC transport stream failed during startup.',
              anchor: anchor,
            ),
            stackTrace,
          );
        },
      );
      inspectTransport(transport.snapshot);
    }
    inspect(driver.snapshot);
    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          MobileLibVlcTerminalFailure(
            kind: MobileLibVlcFailureKind.startupTimeout,
            message: 'libVLC video did not prove an advancing clock.',
            anchor: anchor,
          ),
        );
      }
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await driverSubscription.cancel();
      await transportSubscription?.cancel();
      if (identical(_pendingProof, completer)) {
        _pendingProof = null;
      }
    }
  }

  void _publish(MobileLibVlcState value, int generation) {
    if (_closed || generation != _generation || _states.isClosed) {
      return;
    }
    _state = value;
    _states.add(value);
  }

  void _throwIfStale(int generation, Duration anchor) {
    if (_isStale(generation)) {
      throw _cancelledFailure(anchor);
    }
  }

  bool _isStale(int generation) => _closed || generation != _generation;

  MobileLibVlcTerminalFailure _cancelledFailure(Duration anchor) {
    return MobileLibVlcTerminalFailure(
      kind: MobileLibVlcFailureKind.cancelled,
      message: 'The libVLC playback attempt was cancelled.',
      anchor: anchor,
    );
  }

  Duration _remainingStartupBudget(
    DateTime deadline, [
    Duration Function()? remainingBudget,
  ]) {
    final remaining =
        remainingBudget?.call() ?? deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw _startupBudgetFailure(_anchor);
    }
    return remaining;
  }

  Duration _freshResolverBudget(Duration remaining) {
    final effectiveRecoveryReserve = _shorterDuration(
      freshRecoveryReserve,
      startupBudget,
    );
    final proportionalResolverBudget = Duration(
      microseconds: effectiveRecoveryReserve.inMicroseconds ~/ 5,
    );
    final effectiveResolverBudget = _shorterDuration(
      freshResolverTimeout,
      proportionalResolverBudget,
    );
    final recoveryCandidateReserve =
        effectiveRecoveryReserve - effectiveResolverBudget;
    final available = remaining - recoveryCandidateReserve;
    if (available <= Duration.zero) {
      return Duration.zero;
    }
    return _shorterDuration(available, effectiveResolverBudget);
  }

  Duration _shorterDuration(Duration left, Duration right) {
    return left <= right ? left : right;
  }

  MobileLibVlcTerminalFailure _startupBudgetFailure(Duration anchor) {
    return MobileLibVlcTerminalFailure(
      kind: MobileLibVlcFailureKind.startupTimeout,
      message: 'libVLC exhausted its bounded startup recovery budget.',
      anchor: anchor,
    );
  }

  Future<MobileLibVlcTransport?> _awaitTransportWithinBudget(
    Future<MobileLibVlcTransport?> transportFuture, {
    required DateTime startupDeadline,
    Duration Function()? remainingStartupBudget,
  }) async {
    try {
      return await transportFuture.timeout(
        _remainingStartupBudget(startupDeadline, remainingStartupBudget),
      );
    } on TimeoutException {
      unawaited(
        transportFuture.then((lateTransport) async {
          await lateTransport?.stop();
        }).catchError((Object _) {}),
      );
      throw _startupBudgetFailure(_anchor);
    }
  }

  Future<T> _awaitRouteOwnedStep<T>(
    Future<T> operation, {
    required Duration anchor,
    Duration Function()? remainingBudget,
    Future<void>? cancellation,
  }) {
    if (remainingBudget == null && cancellation == null) return operation;
    final remaining = remainingBudget?.call() ?? startupTimeout;
    if (remaining <= Duration.zero) {
      return Future<T>.error(_startupBudgetFailure(anchor));
    }
    final bounded = operation.timeout(
      remaining,
      onTimeout: () => throw _startupBudgetFailure(anchor),
    );
    if (cancellation == null) return bounded;
    return Future.any<T>(<Future<T>>[
      bounded,
      cancellation.then<T>((_) => throw _cancelledFailure(anchor)),
    ]);
  }

  Future<MobileLibVlcTransport?> _awaitRouteOwnedTransport(
    Future<MobileLibVlcTransport?> operation, {
    required Duration anchor,
    Duration Function()? remainingBudget,
    Future<void>? cancellation,
  }) async {
    try {
      return await _awaitRouteOwnedStep<MobileLibVlcTransport?>(
        operation,
        anchor: anchor,
        remainingBudget: remainingBudget,
        cancellation: cancellation,
      );
    } catch (_) {
      unawaited(
        operation.then((transport) async {
          await transport?.stop();
        }).catchError((Object _) {}),
      );
      rethrow;
    }
  }

  Future<MobileLibVlcDriver> _awaitRouteOwnedDriver(
    Future<MobileLibVlcDriver> operation, {
    required Duration anchor,
    Duration Function()? remainingBudget,
    Future<void>? cancellation,
  }) async {
    try {
      return await _awaitRouteOwnedStep<MobileLibVlcDriver>(
        operation,
        anchor: anchor,
        remainingBudget: remainingBudget,
        cancellation: cancellation,
      );
    } catch (_) {
      unawaited(
        operation.then((driver) async {
          await driver.dispose();
        }).catchError((Object _) {}),
      );
      rethrow;
    }
  }

  Future<void> _disposeOwned({bool bounded = false}) async {
    final driver = _driver;
    final transport = _transport;
    _driver = null;
    _transport = null;
    await _disposeOwners(driver, transport, bounded: bounded);
  }

  Future<void> _disposeOwners(
      MobileLibVlcDriver? driver, MobileLibVlcTransport? transport,
      {bool bounded = false, bool suppressErrors = false}) async {
    final disposal = _disposeOwnersUnbounded(driver, transport);
    try {
      if (!bounded) {
        await disposal;
        return;
      }
      await disposal.timeout(
        _terminalOwnerCleanupBudget,
        onTimeout: () {},
      );
    } catch (_) {
      if (!suppressErrors) rethrow;
    }
  }

  Future<void> _disposeOwnersUnbounded(
    MobileLibVlcDriver? driver,
    MobileLibVlcTransport? transport,
  ) async {
    Object? driverError;
    try {
      if (driver != null) {
        await driver.dispose();
      }
    } catch (error) {
      driverError = error;
    } finally {
      if (transport != null) {
        await transport.stop();
      }
    }
    if (driverError != null) {
      throw driverError;
    }
  }
}
