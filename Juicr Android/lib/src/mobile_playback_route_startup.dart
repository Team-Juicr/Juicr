import 'dart:async';

import 'playback_request_transport.dart';

class MobilePlaybackRouteStartupExpired implements Exception {
  const MobilePlaybackRouteStartupExpired();
}

String? mobileLibVlcOpeningStaleReason({
  required bool playerClosing,
  required bool mounted,
  required bool routeOwnerCurrent,
  required bool routeOwnerAvailable,
  required bool transactionOwnerPresent,
  required bool transactionOwnerAvailable,
  required bool openingTokenCurrent,
  required bool coordinatorCurrent,
}) {
  if (playerClosing) return 'player_closing';
  if (!mounted) return 'unmounted';
  if (transactionOwnerPresent) {
    if (!transactionOwnerAvailable) return 'transaction_owner_unavailable';
  } else {
    if (!routeOwnerCurrent) return 'route_owner_replaced';
    if (!routeOwnerAvailable) return 'route_owner_unavailable';
  }
  if (!openingTokenCurrent) return 'opening_token_replaced';
  if (!coordinatorCurrent) return 'coordinator_replaced';
  return null;
}

/// Makes terminal settlement synchronously reject late controller callbacks.
class MobilePlaybackTerminalCallbackGate {
  int _generation = 0;
  bool _terminal = false;

  int beginOpening() {
    _terminal = false;
    return ++_generation;
  }

  void invalidateTerminal() {
    _terminal = true;
    ++_generation;
  }

  bool permits(int callbackGeneration) =>
      !_terminal && callbackGeneration == _generation;

  int get generation => _generation;
}

class _RouteStartupSettlementTracker {
  final Set<Future<void>> _active = <Future<void>>{};

  int get count => _active.length;

  void track(Future<void> settlement) {
    _active.add(settlement);
    unawaited(settlement.whenComplete(() => _active.remove(settlement)));
  }

  List<Future<void>> snapshot() => List<Future<void>>.of(_active);

  void detach(Iterable<Future<void>> settlements) {
    _active.removeAll(settlements);
  }

  void dispose() => _active.clear();
}

class MobilePlaybackRouteStartupOwner {
  MobilePlaybackRouteStartupOwner({
    required this.generation,
    required DateTime startedAt,
    Duration Function()? elapsed,
    void Function()? onWorkCancelled,
    Duration wallBudget = const Duration(seconds: 60),
    Duration settlementReserve = const Duration(milliseconds: 1500),
    Duration childSettlementBudget = const Duration(milliseconds: 500),
  })  : assert(settlementReserve < wallBudget),
        _wallBudget = wallBudget,
        _workBudget = wallBudget - settlementReserve,
        _childSettlementBudget = childSettlementBudget,
        _onWorkCancelled = onWorkCancelled,
        deadline = startedAt.add(wallBudget),
        workCutoff = startedAt.add(wallBudget - settlementReserve) {
    final wallAge = DateTime.now().difference(startedAt);
    final initialAge = wallAge.isNegative ? Duration.zero : wallAge;
    _stopwatch.start();
    _elapsed = elapsed ?? () => initialAge + _stopwatch.elapsed;
    final delay = remainingWorkBudget;
    if (delay <= Duration.zero) {
      _expire();
    } else {
      _cutoffTimer = Timer(delay, _expire);
    }
  }

  final int generation;
  final DateTime deadline;
  final DateTime workCutoff;
  final Duration _wallBudget;
  final Duration _workBudget;
  final Duration _childSettlementBudget;
  final Stopwatch _stopwatch = Stopwatch();
  late final Duration Function() _elapsed;
  final void Function()? _onWorkCancelled;
  final PlaybackRequestCancellation cancellation =
      PlaybackRequestCancellation();
  final Completer<void> _cancelled = Completer<void>();
  final _RouteStartupSettlementTracker _settlements =
      _RouteStartupSettlementTracker();

  Timer? _cutoffTimer;
  bool _expired = false;
  bool _disposed = false;
  bool _cancelNotified = false;
  bool _completedSuccessfully = false;

  bool get isExpired =>
      !_completedSuccessfully && (_expired || _elapsed() >= _workBudget);
  bool get isCancelled => cancellation.isCancelled;
  bool get isCompletedSuccessfully => _completedSuccessfully;
  Future<void> get whenCancelled => _cancelled.future;
  int get activeSettlementCount => _settlements.count;

  bool ownsAttempt(int attemptGeneration) =>
      !_disposed && !isCancelled && generation == attemptGeneration;

  Duration get remainingWorkBudget {
    final remaining = _workBudget - _elapsed();
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration get remainingWallBudget {
    final remaining = _wallBudget - _elapsed();
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void throwIfUnavailable() {
    if (_disposed || isExpired || isCancelled) {
      _expire();
      throw const MobilePlaybackRouteStartupExpired();
    }
  }

  Future<T> runWork<T>(
    Future<T> Function(PlaybackRequestCancellation cancellation) operation,
  ) async {
    throwIfUnavailable();
    final future = operation(cancellation);
    final settlement = future.then<void>((_) {}, onError: (_) {});
    _settlements.track(settlement);
    final result = await Future.any<T>(<Future<T>>[
      future,
      whenCancelled.then<T>(
        (_) => throw const MobilePlaybackRouteStartupExpired(),
      ),
    ]);
    throwIfUnavailable();
    return result;
  }

  bool canChargeOptionalDelay(Duration delay) {
    if (_completedSuccessfully) return true;
    if (_disposed || isExpired || isCancelled) return false;
    return delay <= remainingWorkBudget;
  }

  Future<void> cancelAndSettle() async {
    _cancelWork();
    final settlements = _settlements.snapshot();
    if (settlements.isEmpty) return;
    final remaining = remainingWallBudget;
    if (remaining > Duration.zero) {
      final waitBudget = remaining < _childSettlementBudget
          ? remaining
          : _childSettlementBudget;
      await Future.wait(settlements).timeout(
        waitBudget,
        onTimeout: () => const <void>[],
      );
    }
    _settlements.detach(settlements);
  }

  void completeSuccessfully() {
    _completedSuccessfully = true;
    _cutoffTimer?.cancel();
    _cutoffTimer = null;
  }

  void expireNow() {
    if (_completedSuccessfully || _disposed) return;
    _expire();
  }

  void _expire() {
    _expired = true;
    _cancelWork();
  }

  void _cancelWork() {
    _cutoffTimer?.cancel();
    _cutoffTimer = null;
    if (!cancellation.isCancelled) cancellation.cancel();
    if (!_cancelled.isCompleted) _cancelled.complete();
    if (!_cancelNotified) {
      _cancelNotified = true;
      _onWorkCancelled?.call();
    }
  }

  void dispose() {
    _disposed = true;
    _stopwatch.stop();
    _cancelWork();
    _settlements.dispose();
  }
}

Future<void> restoreRetainedPlaybackAfterRouteFailure({
  required void Function() publishRestoredUi,
  Future<void> Function()? resumePlayback,
  void Function(Object error)? onResumeError,
}) async {
  publishRestoredUi();
  if (resumePlayback == null) return;
  try {
    await resumePlayback();
  } catch (error) {
    onResumeError?.call(error);
  }
}
