import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/mobile_libvlc_models.dart';

void main() {
  group('first-party opaque media capability', () {
    test('accepts only canonical regional media URLs', () {
      final digest = 'a' * 64;
      expect(
        mobileFirstPartyOpaqueMediaCapability(
          Uri.parse('https://asia.juicr.app/playback/media/$digest/0.m3u8'),
        ),
        isTrue,
      );
      expect(
        mobileFirstPartyOpaqueMediaCapability(
          Uri.parse('https://us.juicr.app/playback/media/$digest/12.ts'),
        ),
        isTrue,
      );
      for (final invalid in <String>[
        'https://api.juicr.app/playback/media/$digest/0.m3u8',
        'https://asia.juicr.app/playback/media/$digest/0.m3u8?token=private',
        'https://asia.juicr.app:444/playback/media/$digest/0.m3u8',
        'https://user@asia.juicr.app/playback/media/$digest/0.m3u8',
        'http://asia.juicr.app/playback/media/$digest/0.m3u8',
        'https://asia.juicr.app/not-media/$digest/0.m3u8',
      ]) {
        expect(
          mobileFirstPartyOpaqueMediaCapability(Uri.parse(invalid)),
          isFalse,
          reason: invalid,
        );
      }
    });
  });

  group('MobileLibVlcState', () {
    test('defines the complete bounded lifecycle', () {
      expect(
        MobileLibVlcState.values,
        const [
          MobileLibVlcState.idle,
          MobileLibVlcState.resolving,
          MobileLibVlcState.prebuffering,
          MobileLibVlcState.opening,
          MobileLibVlcState.proving,
          MobileLibVlcState.playing,
          MobileLibVlcState.buffering,
          MobileLibVlcState.recovering,
          MobileLibVlcState.failed,
          MobileLibVlcState.closed,
        ],
      );
    });
  });

  group('anonymous HLS transport session identity', () {
    MobileLibVlcSourceCandidate candidate({
      required String id,
      required String quality,
      required String path,
      String query = 'session=expired',
      String mirror = 'mirror-a',
    }) {
      return MobileLibVlcSourceCandidate(
        id: id,
        mirrorGroup: mirror,
        qualityLabel: quality,
        uri: Uri.parse('https://media.invalid/$path?$query'),
        headers: const <String, String>{
          'Referer': 'https://app.invalid/watch',
          'User-Agent': 'Juicr-Test',
        },
        providerId: 'anonymous-provider',
        requiresTransport: true,
      );
    }

    test('deduplicates renditions sharing one opaque session context', () {
      final fullHd = candidate(
        id: 'source-1080',
        quality: '1080P',
        path: 'renditions/1080.m3u8',
      );
      final hd = candidate(
        id: 'source-720',
        quality: '720P',
        path: 'renditions/720.m3u8',
      );
      final adaptive = candidate(
        id: 'source-auto',
        quality: 'Auto',
        path: 'master.m3u8',
      );

      expect(fullHd.transportSessionIdentity, hd.transportSessionIdentity);
      expect(hd.transportSessionIdentity, adaptive.transportSessionIdentity);
      expect(fullHd.attemptIdentity, isNot(hd.attemptIdentity));
    });

    test('fresh query session and distinct mirror remain independently eligible',
        () {
      final expired = candidate(
        id: 'expired',
        quality: '1080P',
        path: 'renditions/1080.m3u8',
      );
      final refreshed = candidate(
        id: 'fresh',
        quality: '1080P',
        path: 'renditions/1080.m3u8',
        query: 'session=fresh',
      );
      final distinctMirror = candidate(
        id: 'mirror-b',
        quality: '1080P',
        path: 'renditions/1080.m3u8',
        mirror: 'mirror-b',
      );

      expect(expired.transportSessionIdentity,
          isNot(refreshed.transportSessionIdentity));
      expect(expired.transportSessionIdentity,
          isNot(distinctMirror.transportSessionIdentity));
    });

    test('opaque identity never contains request context or source labels', () {
      final source = candidate(
        id: 'private-source-id',
        quality: '1080P',
        path: 'private/manifest.m3u8',
      );
      final identity = source.transportSessionIdentity;

      expect(identity, isNot(contains('media.invalid')));
      expect(identity, isNot(contains('session=expired')));
      expect(identity, isNot(contains('app.invalid')));
      expect(identity, isNot(contains('Juicr-Test')));
      expect(identity, isNot(contains('anonymous-provider')));
      expect(identity, isNot(contains('private-source-id')));
    });
  });

  group('preserveMobileLibVlcAnchor', () {
    test('recovery cannot move a credible anchor backward', () {
      expect(
        preserveMobileLibVlcAnchor(
          current: const Duration(minutes: 30),
          candidate: Duration.zero,
          explicitSeek: false,
        ),
        const Duration(minutes: 30),
      );
    });

    test('recovery advances to a newer credible anchor', () {
      expect(
        preserveMobileLibVlcAnchor(
          current: const Duration(minutes: 30),
          candidate: const Duration(minutes: 31),
          explicitSeek: false,
        ),
        const Duration(minutes: 31),
      );
    });

    test('explicit backward seek may move the anchor backward', () {
      expect(
        preserveMobileLibVlcAnchor(
          current: const Duration(minutes: 30),
          candidate: const Duration(minutes: 2),
          explicitSeek: true,
        ),
        const Duration(minutes: 2),
      );
    });

    test('negative candidates are clamped to zero', () {
      expect(
        preserveMobileLibVlcAnchor(
          current: Duration.zero,
          candidate: const Duration(seconds: -1),
          explicitSeek: true,
        ),
        Duration.zero,
      );
    });
  });

  group('continuous-TS absolute seek persistence', () {
    test('relay-local near-EOF window cannot lower the requested anchor', () {
      const preSeek = Duration(seconds: 2543);
      const requested = Duration(seconds: 2528);
      const relayWindowDuration = Duration(seconds: 24);
      const genericNearEndResumeCap = Duration(seconds: 2341);

      expect(preSeek - const Duration(seconds: 15), requested);
      expect(
        preserveMobileLibVlcAbsoluteProgressFloor(
          proposedPosition: genericNearEndResumeCap,
          authoritativeAnchor: requested,
          relayLocalDuration: relayWindowDuration,
          continuousTsAbsoluteTimeline: true,
        ),
        requested,
      );
    });

    test('direct MP4 persistence keeps its existing proposed position', () {
      expect(
        preserveMobileLibVlcAbsoluteProgressFloor(
          proposedPosition: const Duration(seconds: 2341),
          authoritativeAnchor: const Duration(seconds: 2528),
          relayLocalDuration: const Duration(seconds: 24),
          continuousTsAbsoluteTimeline: false,
        ),
        const Duration(seconds: 2341),
      );
    });
  });

  group('MobileLibVlcSeekSettlementBarrier', () {
    test('quarantines stale native samples across rapid backward seeks', () {
      final barrier = MobileLibVlcSeekSettlementBarrier();
      final startedAt = DateTime(2026, 8, 3, 7, 30);

      barrier.begin(
        from: const Duration(seconds: 638),
        target: const Duration(seconds: 623),
        observedAt: startedAt,
      );
      expect(
        barrier.acceptedPosition(
          nativePosition: const Duration(seconds: 641),
          observedAt: startedAt.add(const Duration(milliseconds: 200)),
        ),
        const Duration(seconds: 623),
      );
      expect(barrier.nextSeekBase, const Duration(seconds: 623));

      barrier.begin(
        from: barrier.nextSeekBase,
        target: const Duration(seconds: 608),
        observedAt: startedAt.add(const Duration(milliseconds: 400)),
      );
      expect(
        barrier.acceptedPosition(
          nativePosition: const Duration(seconds: 643),
          observedAt: startedAt.add(const Duration(milliseconds: 500)),
        ),
        const Duration(seconds: 608),
      );

      barrier.begin(
        from: barrier.nextSeekBase,
        target: const Duration(seconds: 593),
        observedAt: startedAt.add(const Duration(milliseconds: 800)),
      );
      expect(barrier.nextSeekBase, const Duration(seconds: 593));
      expect(barrier.isSettling, isTrue);
      expect(
        barrier.decisionOverdue(
          startedAt.add(const Duration(seconds: 6)),
        ),
        isTrue,
      );
      expect(
        barrier.acceptedPosition(
          nativePosition: const Duration(seconds: 646),
          observedAt: startedAt.add(const Duration(seconds: 6)),
        ),
        const Duration(seconds: 593),
      );
    });

    test('accepts natural forward progress after native convergence', () {
      final barrier = MobileLibVlcSeekSettlementBarrier();
      final startedAt = DateTime(2026, 8, 3, 7, 31);
      barrier.begin(
        from: const Duration(seconds: 638),
        target: const Duration(seconds: 623),
        observedAt: startedAt,
      );

      expect(
        barrier.acceptedPosition(
          nativePosition: const Duration(seconds: 624),
          observedAt: startedAt.add(const Duration(milliseconds: 700)),
        ),
        const Duration(seconds: 623),
      );
      expect(barrier.isSettling, isTrue);
      expect(
        barrier.acceptedPosition(
          nativePosition: const Duration(seconds: 641),
          observedAt: startedAt.add(const Duration(milliseconds: 800)),
        ),
        const Duration(seconds: 623),
      );
      expect(
        barrier.constrainComputedPosition(
          computedPosition: const Duration(seconds: 641),
          acceptedNativePosition: const Duration(seconds: 623),
        ),
        const Duration(seconds: 623),
      );
      expect(barrier.isSettling, isTrue);
      expect(
        barrier.acceptedPosition(
          nativePosition: const Duration(seconds: 624),
          observedAt: startedAt.add(const Duration(milliseconds: 900)),
        ),
        const Duration(seconds: 623),
      );
      expect(
        barrier.constrainComputedPosition(
          computedPosition: const Duration(seconds: 641),
          acceptedNativePosition: barrier.acceptedPosition(
            nativePosition: const Duration(seconds: 625),
            observedAt: startedAt.add(const Duration(milliseconds: 1200)),
          ),
        ),
        const Duration(seconds: 625),
      );
      expect(
        barrier.acceptedPosition(
          nativePosition: const Duration(seconds: 626),
          observedAt: startedAt.add(const Duration(milliseconds: 1400)),
        ),
        const Duration(seconds: 626),
      );
      expect(barrier.isSettling, isFalse);
      expect(
        barrier.acceptedPosition(
          nativePosition: const Duration(seconds: 629),
          observedAt: startedAt.add(const Duration(seconds: 5)),
        ),
        const Duration(seconds: 629),
      );
    });

    test('does not constrain forward seeks', () {
      final barrier = MobileLibVlcSeekSettlementBarrier();
      final startedAt = DateTime(2026, 8, 3, 7, 32);
      barrier.begin(
        from: const Duration(seconds: 532),
        target: const Duration(seconds: 594),
        observedAt: startedAt,
      );

      expect(barrier.isSettling, isFalse);
      expect(
        barrier.acceptedPosition(
          nativePosition: const Duration(seconds: 595),
          observedAt: startedAt.add(const Duration(milliseconds: 300)),
        ),
        const Duration(seconds: 595),
      );
    });
  });

  group('mobile libVLC HLS startup proof ownership', () {
    test('continuous TS relay owns media proof after manifest validation', () {
      expect(
        deferMobileLibVlcHlsMediaProofToRelay(
          continuousTsRelayCandidate: true,
        ),
        isTrue,
      );
    });

    test('non-relay HLS keeps native source validation ownership', () {
      expect(
        deferMobileLibVlcHlsMediaProofToRelay(
          continuousTsRelayCandidate: false,
        ),
        isFalse,
      );
    });

    test('partial startup lead is not established playback', () {
      expect(
        hasEstablishedMobileLibVlcHlsLead(
          startupLeadReady: false,
          emittedSegments: 0,
          stagedStartupSegments: 4,
        ),
        isFalse,
      );
    });

    test('reported lead with emitted media is established playback', () {
      expect(
        hasEstablishedMobileLibVlcHlsLead(
          startupLeadReady: true,
          emittedSegments: 4,
          stagedStartupSegments: 0,
        ),
        isTrue,
      );
    });
  });

  group('mobile libVLC relay timeline translation', () {
    test('keeps a seekable relay seek inside the buffered frontier immediate',
        () {
      expect(
        shouldReopenMobileLibVlcRelayForSeek(
          continuousTsActive: true,
          target: const Duration(minutes: 2),
          timelineOffset: Duration.zero,
          bufferedPosition: const Duration(minutes: 3),
          transportSeekable: true,
        ),
        isFalse,
      );
    });

    test('reopens a non-seekable relay for every explicit seek', () {
      expect(
        shouldReopenMobileLibVlcRelayForSeek(
          continuousTsActive: true,
          target: const Duration(minutes: 2),
          timelineOffset: Duration.zero,
          bufferedPosition: const Duration(minutes: 3),
          transportSeekable: false,
        ),
        isTrue,
      );
    });

    test('reopens a zero-offset relay when seek exceeds its frontier', () {
      expect(
        shouldReopenMobileLibVlcRelayForSeek(
          continuousTsActive: true,
          target: const Duration(minutes: 8),
          timelineOffset: Duration.zero,
          bufferedPosition: const Duration(minutes: 3),
        ),
        isTrue,
      );
    });

    test('reopens when seek targets media before the relay window', () {
      expect(
        shouldReopenMobileLibVlcRelayForSeek(
          continuousTsActive: true,
          target: const Duration(minutes: 10),
          timelineOffset: const Duration(minutes: 20),
          bufferedPosition: const Duration(minutes: 23),
        ),
        isTrue,
      );
    });

    test('maps a global resume anchor to the relay-local driver clock', () {
      expect(
        mobileLibVlcRelayLocalPosition(
          absolutePosition: const Duration(hours: 1, minutes: 35, seconds: 43),
          timelineOffset: const Duration(hours: 1, minutes: 34, seconds: 40),
        ),
        const Duration(minutes: 1, seconds: 3),
      );
    });

    test('maps the relay-local driver clock back to the global timeline', () {
      expect(
        mobileLibVlcRelayAbsolutePosition(
          localPosition: const Duration(minutes: 1, seconds: 3),
          timelineOffset: const Duration(hours: 1, minutes: 34, seconds: 40),
        ),
        const Duration(hours: 1, minutes: 35, seconds: 43),
      );
    });

    test('clamps a global anchor before the relay window to local zero', () {
      expect(
        mobileLibVlcRelayLocalPosition(
          absolutePosition: const Duration(minutes: 20),
          timelineOffset: const Duration(minutes: 30),
        ),
        Duration.zero,
      );
    });

    test(
        'keeps lead telemetry at the anchor until the driver clock is credible',
        () {
      final timeline = MobileLibVlcSessionTimeline(
        anchor: const Duration(hours: 1, minutes: 35, seconds: 43),
      );
      timeline.recordTimelineOffset(
        const Duration(hours: 1, minutes: 34, seconds: 40),
      );
      timeline.recordDriverPosition(
        Duration.zero,
        isInitialized: true,
      );

      expect(
        timeline.absolutePlaybackPosition,
        const Duration(hours: 1, minutes: 35, seconds: 43),
      );

      expect(
        timeline.localSeekPosition(
          const Duration(hours: 1, minutes: 35, seconds: 43),
        ),
        const Duration(minutes: 1, seconds: 3),
      );
      timeline.recordDriverPosition(
        const Duration(minutes: 1, seconds: 3),
        isInitialized: true,
      );

      expect(
        timeline.absolutePlaybackPosition,
        const Duration(hours: 1, minutes: 35, seconds: 43),
      );
    });

    test('translates recovered local callbacks without losing the anchor', () {
      const anchor = Duration(minutes: 29, seconds: 19);
      final timeline = MobileLibVlcSessionTimeline(anchor: anchor);

      timeline.recordDriverPosition(Duration.zero, isInitialized: true);
      expect(timeline.absolutePlaybackPosition, anchor);

      timeline.recordTimelineOffset(anchor);
      for (final localSeconds in const [0, 2, 7]) {
        timeline.recordDriverPosition(
          Duration(seconds: localSeconds),
          isInitialized: true,
        );
        expect(
          timeline.absolutePlaybackPosition,
          anchor + Duration(seconds: localSeconds),
        );
      }
    });

    test('holds decoder preroll below the credible recovery anchor', () {
      const anchor = Duration(minutes: 13, seconds: 27);
      final timeline = MobileLibVlcSessionTimeline(anchor: anchor);

      timeline.recordTimelineOffset(
        const Duration(minutes: 13, seconds: 15),
      );
      for (final localSeconds in const [0, 2, 7]) {
        timeline.recordDriverPosition(
          Duration(seconds: localSeconds),
          isInitialized: true,
        );
        expect(timeline.absolutePlaybackPosition, anchor);
      }

      timeline.recordDriverPosition(
        const Duration(seconds: 12),
        isInitialized: true,
      );
      expect(timeline.absolutePlaybackPosition, anchor);

      timeline.recordDriverPosition(
        const Duration(seconds: 14),
        isInitialized: true,
      );
      expect(
        timeline.absolutePlaybackPosition,
        const Duration(minutes: 13, seconds: 29),
      );
    });

    test('provisional equality cannot release the floor before recalibration',
        () {
      const floor = Duration(minutes: 17, seconds: 55);
      final timeline = MobileLibVlcSessionTimeline(anchor: floor);

      timeline.recordTimelineOffset(floor);
      timeline.recordDriverPosition(Duration.zero, isInitialized: true);
      expect(timeline.absolutePlaybackPosition, floor);

      timeline.recordTimelineOffset(
        const Duration(minutes: 17, seconds: 40),
      );
      for (final localSeconds in const [0, 3, 8, 13]) {
        timeline.recordDriverPosition(
          Duration(seconds: localSeconds),
          isInitialized: true,
        );
        expect(timeline.absolutePlaybackPosition, floor);
      }

      timeline.recordDriverPosition(
        const Duration(seconds: 18),
        isInitialized: true,
      );
      expect(
        timeline.absolutePlaybackPosition,
        const Duration(minutes: 17, seconds: 58),
      );
    });

    test('recovery timeline inherits the highest credible watched floor', () {
      final active = MobileLibVlcSessionTimeline(
        anchor: const Duration(minutes: 17, seconds: 55),
      );
      active.recordTimelineOffset(
        const Duration(minutes: 17, seconds: 40),
      );
      active.recordDriverPosition(
        const Duration(seconds: 20),
        isInitialized: true,
      );
      expect(
        active.absolutePlaybackPosition,
        const Duration(minutes: 18),
      );

      final recovered = MobileLibVlcSessionTimeline(
        anchor: active.absolutePlaybackPosition,
      );
      recovered.recordTimelineOffset(
        const Duration(minutes: 17, seconds: 45),
      );
      recovered.recordDriverPosition(Duration.zero, isInitialized: true);
      expect(
        recovered.absolutePlaybackPosition,
        const Duration(minutes: 18),
      );
    });

    test('explicit seek replaces the floor and Start over alone permits zero',
        () {
      final timeline = MobileLibVlcSessionTimeline(
        anchor: const Duration(minutes: 18),
      );

      expect(
        timeline.localSeekPosition(const Duration(minutes: 12)),
        const Duration(minutes: 12),
      );
      timeline.recordTimelineOffset(
        const Duration(minutes: 11, seconds: 45),
      );
      timeline.recordDriverPosition(Duration.zero, isInitialized: true);
      expect(timeline.absolutePlaybackPosition, const Duration(minutes: 12));

      expect(timeline.localSeekPosition(Duration.zero), Duration.zero);
      timeline.recordTimelineOffset(Duration.zero);
      timeline.recordDriverPosition(Duration.zero, isInitialized: true);
      expect(timeline.absolutePlaybackPosition, Duration.zero);
    });

    test('stale timeline samples cannot mutate the active generation floor',
        () {
      final stale = MobileLibVlcSessionTimeline(
        anchor: const Duration(minutes: 17, seconds: 55),
      );
      final active = MobileLibVlcSessionTimeline(
        anchor: const Duration(minutes: 12),
      );

      stale.recordTimelineOffset(const Duration(minutes: 17));
      active.recordTimelineOffset(
        const Duration(minutes: 11, seconds: 45),
      );
      active.recordDriverPosition(Duration.zero, isInitialized: true);
      stale.recordDriverPosition(
        const Duration(minutes: 4),
        isInitialized: true,
      );

      expect(active.absolutePlaybackPosition, const Duration(minutes: 12));
    });
  });

  test('source candidate carries stable attempt identity inputs', () {
    final candidate = MobileLibVlcSourceCandidate(
      id: 'source-1',
      mirrorGroup: '1080p',
      qualityLabel: '1080P',
      uri: Uri.parse('https://example.invalid/master.m3u8'),
      headers: {'Referer': 'https://example.invalid/'},
    );

    expect(candidate.id, 'source-1');
    expect(candidate.mirrorGroup, '1080p');
    expect(candidate.qualityLabel, '1080P');
    expect(candidate.uri.scheme, 'https');
    expect(candidate.headers['Referer'], 'https://example.invalid/');
    expect(candidate.attemptIdentity, isNot(contains('example.invalid')));
    expect(candidate.attemptIdentity, isNot(contains('Referer')));
  });

  test('launch rejection circuit is monotonic and generation scoped', () {
    final circuit = MobileLibVlcLaunchRejectionCircuit();
    final firstGeneration = circuit.beginLaunch();
    final firstSessions = circuit.rejectedSessionsFor(firstGeneration);
    firstSessions.add('hls-session:first');

    expect(
      circuit.rejectedSessionsFor(firstGeneration),
      contains('hls-session:first'),
    );

    final secondGeneration = circuit.beginLaunch();
    expect(circuit.rejectedSessionsFor(secondGeneration), isEmpty);
    firstSessions.add('hls-session:stale');
    expect(
      circuit.rejectedSessionsFor(secondGeneration),
      isNot(contains('hls-session:stale')),
    );

    circuit.dispose();
    expect(circuit.rejectedSessionsFor(secondGeneration), isEmpty);
  });

  test('refreshed request context creates a new redacted attempt identity', () {
    final first = MobileLibVlcSourceCandidate(
      id: 'source-1',
      mirrorGroup: '1080p',
      qualityLabel: '1080P',
      uri: Uri.parse('https://example.invalid/master.m3u8'),
      headers: const {'Authorization': 'Bearer first'},
    );
    final refreshed = MobileLibVlcSourceCandidate(
      id: 'source-1',
      mirrorGroup: '1080p',
      qualityLabel: '1080P',
      uri: Uri.parse('https://example.invalid/master.m3u8'),
      headers: const {'Authorization': 'Bearer second'},
    );

    expect(refreshed.attemptIdentity, isNot(first.attemptIdentity));
    expect(refreshed.attemptIdentity, isNot(contains('Bearer')));
  });

  test('snapshots expose proof and health inputs without player dependencies',
      () {
    const driver = MobileLibVlcDriverSnapshot(
      position: Duration(seconds: 5),
      duration: Duration(minutes: 90),
      isPlaying: true,
      isBuffering: false,
      hasError: false,
      videoWidth: 1920,
      videoHeight: 1080,
      isInitialized: true,
      hasUsableVideoFrame: true,
    );
    const transport = MobileLibVlcTransportSnapshot(
      totalMediaBytes: 1024,
      completedMediaSegments: 3,
      estimatedBufferedPosition: Duration(seconds: 18),
    );

    expect(driver.hasVideoGeometry, isTrue);
    expect(driver.hasVisualProof, isTrue);
    expect(transport.hasMediaProof, isTrue);
  });

  test('ended playback is represented separately from a frozen clock', () {
    const driver = MobileLibVlcDriverSnapshot(
      position: Duration(minutes: 90),
      duration: Duration(minutes: 90),
      isPlaying: false,
      isBuffering: false,
      hasError: false,
      videoWidth: 1920,
      videoHeight: 1080,
      isInitialized: true,
      isEnded: true,
      hasUsableVideoFrame: true,
    );

    expect(driver.isEnded, isTrue);
    expect(driver.hasVisualProof, isTrue);
  });
}
