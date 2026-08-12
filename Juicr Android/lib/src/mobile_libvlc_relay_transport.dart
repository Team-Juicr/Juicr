import 'dart:async';

import 'libvlc_hls_relay.dart';
import 'mobile_libvlc_coordinator.dart';
import 'mobile_libvlc_models.dart';

typedef MobileLibVlcNow = DateTime Function();

final class MobileLibVlcTransportSnapshotController {
  MobileLibVlcTransportSnapshotController({
    MobileLibVlcNow? now,
  }) : _now = now ?? DateTime.now;

  final MobileLibVlcNow _now;
  final StreamController<MobileLibVlcTransportSnapshot> _snapshots =
      StreamController<MobileLibVlcTransportSnapshot>.broadcast(sync: true);

  MobileLibVlcTransportSnapshot _snapshot =
      const MobileLibVlcTransportSnapshot.idle();
  bool _closed = false;

  MobileLibVlcTransportSnapshot get snapshot => _snapshot;
  Stream<MobileLibVlcTransportSnapshot> get snapshots => _snapshots.stream;

  void recordTransportActivity() {
    if (_closed) {
      return;
    }
    _publish(
      lastTransportActivityAt: _now(),
    );
  }

  void recordTotalMediaBytes(int totalMediaBytes) {
    if (_closed || totalMediaBytes <= _snapshot.totalMediaBytes) {
      return;
    }
    final observedAt = _now();
    _publish(
      totalMediaBytes: totalMediaBytes,
      lastByteAdvanceAt: observedAt,
      lastTransportActivityAt: observedAt,
    );
  }

  void recordCompletedMediaSegments(int completedMediaSegments) {
    if (_closed ||
        completedMediaSegments <= _snapshot.completedMediaSegments) {
      return;
    }
    _publish(
      completedMediaSegments: completedMediaSegments,
      lastTransportActivityAt: _now(),
    );
  }

  void recordBufferedPosition(Duration estimatedBufferedPosition) {
    if (_closed ||
        estimatedBufferedPosition <= _snapshot.estimatedBufferedPosition) {
      return;
    }
    _publish(
      estimatedBufferedPosition: estimatedBufferedPosition,
      lastTransportActivityAt: _now(),
    );
  }

  void recordTimelineOffset(Duration timelineOffset) {
    if (_closed || timelineOffset == _snapshot.timelineOffset) {
      return;
    }
    _publish(
      timelineOffset: timelineOffset,
      lastTransportActivityAt: _now(),
    );
  }

  void recordTerminalFailure(
    MobileLibVlcFailureKind failure, {
    MobileLibVlcTransportFailureClass failureClass =
        MobileLibVlcTransportFailureClass.transient,
  }) {
    if (_closed || _snapshot.terminalFailure != null) {
      return;
    }
    _publish(
      terminalFailure: failure,
      terminalFailureClass: failureClass,
    );
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _snapshots.close();
  }

  void _publish({
    int? totalMediaBytes,
    int? completedMediaSegments,
    Duration? estimatedBufferedPosition,
    Duration? timelineOffset,
    DateTime? lastByteAdvanceAt,
    DateTime? lastTransportActivityAt,
    MobileLibVlcFailureKind? terminalFailure,
    MobileLibVlcTransportFailureClass? terminalFailureClass,
  }) {
    if (_closed) {
      return;
    }
    _snapshot = MobileLibVlcTransportSnapshot(
      totalMediaBytes: totalMediaBytes ?? _snapshot.totalMediaBytes,
      completedMediaSegments:
          completedMediaSegments ?? _snapshot.completedMediaSegments,
      estimatedBufferedPosition:
          estimatedBufferedPosition ?? _snapshot.estimatedBufferedPosition,
      timelineOffset: timelineOffset ?? _snapshot.timelineOffset,
      lastByteAdvanceAt: lastByteAdvanceAt ?? _snapshot.lastByteAdvanceAt,
      lastTransportActivityAt:
          lastTransportActivityAt ?? _snapshot.lastTransportActivityAt,
      terminalFailure: terminalFailure ?? _snapshot.terminalFailure,
      terminalFailureClass:
          terminalFailureClass ?? _snapshot.terminalFailureClass,
    );
    _snapshots.add(_snapshot);
  }
}

final class MobileLibVlcRelayTransport implements MobileLibVlcTransport {
  MobileLibVlcRelayTransport._({
    required LibVlcHlsRelay relay,
    required MobileLibVlcTransportSnapshotController snapshots,
  })  : _relay = relay,
        _snapshotController = snapshots;

  static Future<MobileLibVlcRelayTransport> start({
    required MobileLibVlcSourceCandidate candidate,
    required Duration anchor,
    required Duration Function() currentPlaybackPosition,
    int targetHeight = 720,
    Set<int> excludedHeights = const <int>{},
    void Function(Duration duration)? onDuration,
    void Function(int selectedHeight)? onRenditionSelected,
    void Function(int failedHeight)? onRenditionFailure,
    void Function(Duration offset)? onTimelineOffset,
    required void Function(String message) onEvent,
  }) async {
    final snapshots = MobileLibVlcTransportSnapshotController();
    final relay = await LibVlcHlsRelay.start(
      upstreamUri: candidate.uri,
      headers: candidate.headers,
      limitHeadersToUpstreamOrigin: true,
      resumePosition: anchor,
      continuousTsMode: true,
      continuousTsTargetHeight: targetHeight,
      continuousTsExcludedHeights: excludedHeights,
      currentPlaybackPosition: currentPlaybackPosition,
      onDuration: onDuration,
      onContinuousTsProgress: snapshots.recordCompletedMediaSegments,
      onContinuousTsBytes: snapshots.recordTotalMediaBytes,
      onContinuousTsTransportActivity: snapshots.recordTransportActivity,
      onContinuousTsStartupLeadReady: snapshots.recordTransportActivity,
      onContinuousTsBufferedPosition: snapshots.recordBufferedPosition,
      onContinuousTsRenditionSelected: onRenditionSelected,
      onContinuousTsRenditionFailure: onRenditionFailure,
      onTimelineOffset: (offset) {
        snapshots.recordTimelineOffset(offset);
        onTimelineOffset?.call(offset);
      },
      onContinuousTsUpstreamError: (_, lastStatusBucket) {
        snapshots.recordTerminalFailure(
          MobileLibVlcFailureKind.transportFailure,
          failureClass: lastStatusBucket == 'auth'
              ? MobileLibVlcTransportFailureClass.authSessionUnreadable
              : MobileLibVlcTransportFailureClass.transient,
        );
      },
      onEvent: onEvent,
    );
    return MobileLibVlcRelayTransport._(
      relay: relay,
      snapshots: snapshots,
    );
  }

  final LibVlcHlsRelay _relay;
  final MobileLibVlcTransportSnapshotController _snapshotController;
  bool _stopped = false;

  @override
  Uri get playbackUri => _relay.localUri;

  @override
  MobileLibVlcTransportSnapshot get snapshot =>
      _snapshotController.snapshot;

  @override
  Stream<MobileLibVlcTransportSnapshot> get snapshots =>
      _snapshotController.snapshots;

  @override
  Future<void> stop() async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    try {
      await _relay.stop();
    } finally {
      await _snapshotController.close();
    }
  }
}
