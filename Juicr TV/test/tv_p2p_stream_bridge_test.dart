import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_p2p_stream_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.juicr.flutter/p2p_bridge');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('native capability must answer true before TV enables P2P', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'isAvailable';
    });

    const bridge = MethodChannelTvP2pLocalStreamBridge(channel: channel);

    expect(await bridge.isAvailable(), isTrue);
    expect(calls.map((call) => call.method), <String>['isAvailable']);
  });

  test('runtime capability resolves true only from a positive native probe',
      () async {
    expect(
      await resolveTvP2pRuntimeCapability(
        bridge: _CapabilityP2pBridge(Future<bool>.value(true)),
      ),
      isTrue,
    );
    expect(
      await resolveTvP2pRuntimeCapability(
        bridge: _CapabilityP2pBridge(Future<bool>.value(false)),
      ),
      isFalse,
    );
  });

  test('runtime capability fails closed when the native probe throws',
      () async {
    expect(
      await resolveTvP2pRuntimeCapability(
        bridge: _CapabilityP2pBridge(Future<bool>.error(StateError('boom'))),
      ),
      isFalse,
    );
  });

  test('runtime capability fails closed when the native probe does not settle',
      () async {
    expect(
      await resolveTvP2pRuntimeCapability(
        bridge: _CapabilityP2pBridge(Completer<bool>().future),
        timeout: const Duration(milliseconds: 5),
      ),
      isFalse,
    );
  });

  test('P2P execution requires runtime, consent, and an enabled add-on',
      () {
    TvP2pRuntimeCapability.configure(false);
    expect(
      tvP2pPlaybackEffective(
        savedEnabled: true,
        hasConsent: true,
        hasEnabledAddOns: true,
      ),
      isFalse,
    );

    TvP2pRuntimeCapability.configure(true);
    expect(
      tvP2pPlaybackEffective(
        savedEnabled: true,
        hasConsent: true,
        hasEnabledAddOns: true,
      ),
      isTrue,
    );
    expect(
      tvP2pPlaybackEffective(
        savedEnabled: true,
        hasConsent: false,
        hasEnabledAddOns: true,
      ),
      isFalse,
    );
    expect(
      tvP2pPlaybackEffective(
        savedEnabled: true,
        hasConsent: true,
        hasEnabledAddOns: false,
      ),
      isFalse,
    );
    TvP2pRuntimeCapability.configure(false);
  });

  test('saved P2P preference survives a temporarily unavailable runtime', () {
    TvP2pRuntimeCapability.configure(false);

    expect(
      tvP2pSavedPreferenceEnabled(
        savedEnabled: true,
        hasConsent: true,
        hasEnabledAddOns: true,
      ),
      isTrue,
    );
    expect(
      tvP2pSavedPreferenceEnabled(
        savedEnabled: true,
        hasConsent: false,
        hasEnabledAddOns: true,
      ),
      isFalse,
    );
  });

  test('P2P candidate budget leaves native proof time inside the route window', () {
    expect(
      tvP2pCandidateStartupBudget(
        libVlc: false,
        qualityLabel: '1080P',
        trackerCount: 1,
      ),
      const Duration(seconds: 80),
    );
    expect(
      tvP2pCandidateStartupBudget(
        libVlc: false,
        qualityLabel: '2160P',
        trackerCount: 1,
      ),
      const Duration(seconds: 80),
    );
    expect(
      tvP2pCandidateStartupBudget(
        libVlc: false,
        qualityLabel: '1080P',
        trackerCount: 0,
      ),
      const Duration(seconds: 80),
    );
    expect(
      tvP2pCandidateStartupBudget(
        libVlc: true,
        qualityLabel: '2160P',
        trackerCount: 1,
      ),
      const Duration(seconds: 80),
    );
    expect(
      tvP2pCandidateStartupBudget(
        libVlc: true,
        qualityLabel: '720P',
        trackerCount: 0,
      ),
      const Duration(seconds: 80),
    );
    expect(tvP2pRouteStartupBudget(), const Duration(seconds: 90));
  });

  test('P2P route identity survives refreshed tracker and label changes', () {
    const original = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
      fileIdx: 2,
      trackers: <String>['https://tracker-one.invalid/announce'],
      displayName: 'Original label',
    );
    const refreshed = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
      fileIdx: 2,
      trackers: <String>['https://tracker-two.invalid/announce'],
      displayName: 'Refreshed label',
    );
    const siblingFile = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
      fileIdx: 3,
    );

    expect(tvP2pRouteIdentityKey(original), tvP2pRouteIdentityKey(refreshed));
    expect(
      tvP2pRouteIdentityKey(original),
      isNot(tvP2pRouteIdentityKey(siblingFile)),
    );
  });

  test('cold P2P discovery stages abandon early while pieces keep warming', () {
    expect(
      tvP2pReadinessAbandonAfter(
        stage: 'metadata_peers_missing',
        trackerCount: 0,
      ),
      const Duration(seconds: 10),
    );
    expect(
      tvP2pReadinessAbandonAfter(
        stage: 'metadata_discovery_inactive',
        trackerCount: 0,
      ),
      const Duration(seconds: 6),
    );
    expect(
      tvP2pReadinessAbandonAfter(stage: 'peers', trackerCount: 0),
      const Duration(seconds: 16),
    );
    expect(
      tvP2pReadinessAbandonAfter(stage: 'pieces', trackerCount: 0),
      isNull,
    );
  });

  test('cold P2P startup rolls back before the full candidate timeout',
      () async {
    final pending = Completer<Uri>();
    final events = <String>[];

    await expectLater(
      tvAwaitP2pStartupWithRollback(
        startup: pending.future,
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 5),
        readinessStage: () async => 'metadata_peers_missing',
        abandonAfterForStage: (_) => Duration.zero,
        rollback: () async => events.add('rollback'),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          contains('stage=metadata_peers_missing'),
        ),
      ),
    );

    expect(events, <String>['rollback']);
    expect(pending.isCompleted, isFalse);
  });

  test('timed-out P2P startup rolls back before its open future settles',
      () async {
    final pending = Completer<Uri>();
    final events = <String>[];

    await expectLater(
      tvAwaitP2pStartupWithRollback(
        startup: pending.future,
        timeout: const Duration(milliseconds: 5),
        rollback: () async => events.add('rollback'),
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(events, <String>['rollback']);
    expect(pending.isCompleted, isFalse);
  });

  test('timed-out P2P startup captures a neutral readiness stage before rollback',
      () async {
    final pending = Completer<Uri>();
    final events = <String>[];

    await expectLater(
      tvAwaitP2pStartupWithRollback(
        startup: pending.future,
        timeout: const Duration(milliseconds: 5),
        readinessStage: () async {
          events.add('stage');
          return 'metadata';
        },
        rollback: () async => events.add('rollback'),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          contains('stage=metadata'),
        ),
      ),
    );

    expect(events, isNotEmpty);
    expect(events.last, 'rollback');
    expect(events.where((event) => event == 'rollback'), hasLength(1));
    expect(events.take(events.length - 1), everyElement('stage'));
    expect(pending.isCompleted, isFalse);
  });

  test('timed-out P2P startup bounds uncooperative rollback', () async {
    final pendingStartup = Completer<Uri>();
    final pendingRollback = Completer<void>();

    await expectLater(
      tvAwaitP2pStartupWithRollback(
        startup: pendingStartup.future,
        timeout: const Duration(milliseconds: 5),
        rollbackTimeout: const Duration(milliseconds: 5),
        rollback: () => pendingRollback.future,
      ).timeout(const Duration(milliseconds: 100)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('timed-out P2P startup preserves a fixed metadata discovery stage',
      () async {
    final pending = Completer<Uri>();

    await expectLater(
      tvAwaitP2pStartupWithRollback(
        startup: pending.future,
        timeout: const Duration(milliseconds: 5),
        readinessStage: () async => 'metadata_trackers_missing',
        rollback: () async {},
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          contains('stage=metadata_trackers_missing'),
        ),
      ),
    );
  });

  test('P2P lifecycle gate settles transport before one resume restart',
      () async {
    final gate = TvP2pLifecycleGate();
    final events = <String>[];

    await gate.suspend(
      hasActiveTransport: true,
      pausePlayback: () async => events.add('pause'),
      closeTransport: () async => events.add('close'),
    );

    expect(events, <String>['pause', 'close']);
    expect(gate.needsResume, isTrue);

    await gate.resume(reopenPlayback: () async => events.add('reopen'));
    await gate.resume(reopenPlayback: () async => events.add('duplicate'));

    expect(events, <String>['pause', 'close', 'reopen']);
    expect(gate.needsResume, isFalse);
  });

  test('open accepts only verified loopback media owned by its generation',
      () async {
    final calls = <MethodCall>[];
    var readinessChecks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'open') {
        return 'http://127.0.0.1:43210/stream/opaque';
      }
      if (call.method == 'isReady') {
        readinessChecks += 1;
        return readinessChecks >= 2;
      }
      return null;
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(
      channel: channel,
      readinessPollInterval: Duration(milliseconds: 1),
    );
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
      fileIdx: 2,
      trackers: <String>['https://tracker.invalid/announce'],
    );

    final uri = await bridge.open(descriptor, generation: 7);

    expect(uri.toString(), 'http://127.0.0.1:43210/stream/opaque');
    expect(calls.map((call) => call.method), <String>['open', 'isReady', 'isReady']);
    final arguments = Map<Object?, Object?>.from(
      calls.first.arguments as Map<Object?, Object?>,
    );
    expect(arguments['generation'], 7);
    expect(arguments['fileIdx'], 2);
  });

  test('open rejects a non-loopback native response', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'https://media.invalid/private';
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(channel: channel);

    await expectLater(
      bridge.open(
        const TvP2pStreamDescriptor(
          infoHash: '0123456789abcdef0123456789abcdef01234567',
        ),
        generation: 3,
      ),
      throwsStateError,
    );
    expect(
      calls.map((call) => call.method),
      <String>['open', 'stopGeneration'],
    );
  });

  test('open fails closed when local media never becomes readable', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'open') {
        return 'http://127.0.0.1:43210/stream/opaque';
      }
      if (call.method == 'isReady') return false;
      return null;
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(
      channel: channel,
      readinessTimeout: Duration(milliseconds: 5),
      readinessPollInterval: Duration(milliseconds: 1),
    );

    await expectLater(
      bridge.open(
        const TvP2pStreamDescriptor(
          infoHash: '0123456789abcdef0123456789abcdef01234567',
        ),
        generation: 4,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls.last.method, 'stopGeneration');
    expect(
      calls.last.arguments,
      <String, Object>{'generation': 4},
    );
  });

  test('hung readiness probe cannot outlive the bridge deadline', () async {
    final calls = <MethodCall>[];
    final pendingReady = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'open') {
        return 'http://127.0.0.1:43210/stream/opaque';
      }
      if (call.method == 'isReady') return pendingReady.future;
      return null;
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(
      channel: channel,
      readinessTimeout: Duration(milliseconds: 5),
      readinessPollInterval: Duration(milliseconds: 1),
    );

    await expectLater(
      bridge
          .open(
            const TvP2pStreamDescriptor(
              infoHash: '0123456789abcdef0123456789abcdef01234567',
            ),
            generation: 40,
          )
          .timeout(const Duration(milliseconds: 100)),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls.last.method, 'stopGeneration');
  });

  test('generation cancellation stops stale readiness polling', () async {
    final calls = <MethodCall>[];
    final firstPoll = Completer<void>();
    final pendingReady = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'open') {
        return 'http://127.0.0.1:43210/stream/opaque';
      }
      if (call.method == 'isReady') {
        if (!firstPoll.isCompleted) firstPoll.complete();
        return pendingReady.future;
      }
      return null;
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(
      channel: channel,
      readinessTimeout: Duration(seconds: 1),
      readinessPollInterval: Duration(milliseconds: 20),
    );
    final opening = bridge.open(
      const TvP2pStreamDescriptor(
        infoHash: '0123456789abcdef0123456789abcdef01234567',
      ),
      generation: 41,
    );

    await firstPoll.future;
    await bridge.stopGeneration(41);
    await expectLater(
      opening.timeout(const Duration(milliseconds: 100)),
      throwsA(anything),
    );
    final pollCount = calls.where((call) => call.method == 'isReady').length;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls.where((call) => call.method == 'isReady'), hasLength(pollCount));
  });

  test('generation cancellation during poll delay dispatches no stale probe',
      () async {
    final calls = <MethodCall>[];
    final firstPoll = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'open') {
        return 'http://127.0.0.1:43210/stream/opaque';
      }
      if (call.method == 'isReady') {
        if (!firstPoll.isCompleted) firstPoll.complete();
        return false;
      }
      return null;
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(
      channel: channel,
      readinessTimeout: Duration(seconds: 1),
      readinessPollInterval: Duration(milliseconds: 50),
    );
    final opening = bridge.open(
      const TvP2pStreamDescriptor(
        infoHash: '0123456789abcdef0123456789abcdef01234567',
      ),
      generation: 42,
    );

    await firstPoll.future;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final pollCount = calls.where((call) => call.method == 'isReady').length;
    await bridge.stopGeneration(42);
    await expectLater(
      opening.timeout(const Duration(milliseconds: 100)),
      throwsA(anything),
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(calls.where((call) => call.method == 'isReady'), hasLength(pollCount));
  });

  test('readiness stage accepts only fixed native buckets', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'readinessStatus') {
        return <String, Object>{'stage': 'pieces', 'private': 'blocked'};
      }
      return null;
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(channel: channel);

    expect(await bridge.readinessStage(9), 'pieces');
    expect(await bridge.readinessStage(0), 'unknown');
    expect(calls.single.method, 'readinessStatus');
    expect(calls.single.arguments, <String, Object>{'generation': 9});
  });

  test('readiness stage preserves neutral handle and file boundaries', () async {
    var stage = 'handle';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readinessStatus') {
        return <String, Object>{'stage': stage};
      }
      return null;
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(channel: channel);

    expect(await bridge.readinessStage(10), 'handle');
    stage = 'file';
    expect(await bridge.readinessStage(10), 'file');
  });

  test('readiness stage preserves only fixed metadata discovery buckets', () async {
    var discovery = 'trackers_missing';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readinessStatus') {
        return <String, Object>{
          'stage': 'metadata',
          'discovery': discovery,
          'private': 'blocked',
        };
      }
      return null;
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(channel: channel);

    expect(await bridge.readinessStage(11), 'metadata_trackers_missing');
    discovery = 'private-network-state';
    expect(await bridge.readinessStage(11), 'metadata');
  });

  test('open cleans its generation when readiness probing fails', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'open') {
        return 'http://127.0.0.1:43210/stream/opaque';
      }
      if (call.method == 'isReady') {
        throw PlatformException(code: 'readiness_failed');
      }
      return null;
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(channel: channel);

    await expectLater(
      bridge.open(
        const TvP2pStreamDescriptor(
          infoHash: '0123456789abcdef0123456789abcdef01234567',
        ),
        generation: 5,
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(
      calls.map((call) => call.method),
      <String>['open', 'isReady', 'stopGeneration'],
    );
  });

  test('generation-scoped stop cannot become an unowned global stop',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(channel: channel);

    await bridge.stopThrough(11);

    expect(calls.single.method, 'stopAll');
    expect(calls.single.arguments, <String, Object>{'generation': 11});
  });

  test('failed replacement discards only its exact generation', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    const bridge = MethodChannelTvP2pLocalStreamBridge(channel: channel);

    await bridge.stopGeneration(13);

    expect(calls.single.method, 'stopGeneration');
    expect(calls.single.arguments, <String, Object>{'generation': 13});
  });

  test('P2P owner commits replacement only after startup proof', () async {
    final bridge = _RecordingP2pBridge();
    final owner = TvP2pPlaybackOwner(bridge: bridge);
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
    );

    final prepared = await owner.prepare(descriptor, generation: 21);
    expect(prepared.host, '127.0.0.1');
    expect(bridge.stoppedThrough, isEmpty);

    await owner.commit(21);

    expect(bridge.stoppedThrough, <int>[20]);
    expect(owner.activeGeneration, 21);
  });

  test('P2P owner rolls back failed replacement without stopping active owner',
      () async {
    final bridge = _RecordingP2pBridge();
    final owner = TvP2pPlaybackOwner(bridge: bridge);
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
    );
    await owner.prepare(descriptor, generation: 30);
    await owner.commit(30);
    bridge.stoppedThrough.clear();

    await owner.prepare(descriptor, generation: 31);
    await owner.rollback(31);

    expect(bridge.stoppedExactly, <int>[31]);
    expect(bridge.stoppedThrough, isEmpty);
    expect(owner.activeGeneration, 30);
  });

  test('delayed older rollback cannot stop newer committed attempt', () async {
    final bridge = _RecordingP2pBridge();
    final owner = TvP2pPlaybackOwner(bridge: bridge);
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
    );

    await owner.prepare(descriptor, generation: 40);
    await owner.prepare(descriptor, generation: 41);
    await owner.commit(41);
    await owner.rollback(40);

    expect(owner.activeGeneration, 41);
    expect(bridge.stoppedExactly, <int>[40]);
    expect(bridge.stoppedThrough, <int>[40]);
  });

  test('delayed older commit cannot replace newer committed attempt', () async {
    final bridge = _ControlledP2pBridge();
    final owner = TvP2pPlaybackOwner(bridge: bridge);
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
    );

    await owner.prepare(descriptor, generation: 40);
    await owner.prepare(descriptor, generation: 41);
    final olderCommit = owner.commit(40);
    final newerCommit = owner.commit(41);

    bridge.completeStopThrough(40);
    await newerCommit;
    expect(owner.activeGeneration, 41);

    bridge.completeStopThrough(39);
    await olderCommit;

    expect(owner.activeGeneration, 41);
    expect(bridge.stoppedExactly, <int>[40]);
  });

  test('delayed commit cannot resurrect a generation closed by newer cleanup',
      () async {
    final bridge = _ControlledP2pBridge();
    final owner = TvP2pPlaybackOwner(bridge: bridge);
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
    );

    await owner.prepare(descriptor, generation: 40);
    final delayedCommit = owner.commit(40);
    final newerClose = owner.closeThrough(40);

    bridge.completeStopThrough(40);
    await newerClose;
    expect(owner.activeGeneration, isNull);

    bridge.completeStopThrough(39);
    await delayedCommit;

    expect(owner.activeGeneration, isNull);
    expect(bridge.stoppedExactly, <int>[40]);
  });

  test('exact rollback prevents an in-flight commit from reclaiming ownership',
      () async {
    final bridge = _ControlledP2pBridge();
    final owner = TvP2pPlaybackOwner(bridge: bridge);
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
    );

    await owner.prepare(descriptor, generation: 50);
    final delayedCommit = owner.commit(50);
    await owner.rollback(50);
    bridge.completeStopThrough(49);
    await delayedCommit;

    expect(owner.activeGeneration, isNull);
    expect(bridge.stoppedExactly, <int>[50, 50]);
  });

  test('exact rollback prevents an in-flight prepare from becoming owned',
      () async {
    final bridge = _ControlledOpenP2pBridge();
    final owner = TvP2pPlaybackOwner(bridge: bridge);
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
    );

    final delayedPrepare = owner.prepare(descriptor, generation: 60);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.opened, <int>[60]);
    await owner.rollback(60);
    bridge.completeOpen(60);

    await expectLater(delayedPrepare, throwsStateError);
    expect(owner.activeGeneration, isNull);
    expect(bridge.stoppedExactly, <int>[60, 60]);
  });

  test('rollback quarantines preparation before native cleanup settles',
      () async {
    final bridge = _ControlledOpenAndStopP2pBridge();
    final owner = TvP2pPlaybackOwner(bridge: bridge);
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
    );

    final delayedPrepare = owner.prepare(descriptor, generation: 70);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.opened, <int>[70]);
    final rollback = owner.rollback(70);
    bridge.completeOpen(70);

    final prepareExpectation = expectLater(delayedPrepare, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    bridge.completeStopGeneration(70);
    await prepareExpectation;
    await rollback;

    expect(owner.activeGeneration, isNull);
    expect(bridge.stoppedExactly, <int>[70, 70]);
  });

  test('close quarantines commit before native cleanup settles', () async {
    final bridge = _ControlledP2pBridge();
    final owner = TvP2pPlaybackOwner(bridge: bridge);
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
    );

    await owner.prepare(descriptor, generation: 80);
    final delayedCommit = owner.commit(80);
    final close = owner.closeThrough(80);

    bridge.completeStopThrough(79);
    await delayedCommit;
    expect(owner.activeGeneration, isNull);

    bridge.completeStopThrough(80);
    await close;
  });

  test('finalization during capability probe never starts native playback',
      () async {
    final bridge = _ControlledCapabilityP2pBridge();
    final owner = TvP2pPlaybackOwner(bridge: bridge);
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
    );

    final delayedPrepare = owner.prepare(descriptor, generation: 90);
    await Future<void>.delayed(Duration.zero);
    await owner.rollback(90);
    bridge.completeCapability(true);

    await expectLater(delayedPrepare, throwsStateError);
    expect(bridge.opened, isEmpty);
  });

  test('rollback watermark rejects stale generations without clearing active',
      () async {
    final bridge = _RecordingP2pBridge();
    final owner = TvP2pPlaybackOwner(bridge: bridge);
    const descriptor = TvP2pStreamDescriptor(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
    );

    await owner.prepare(descriptor, generation: 100);
    await owner.commit(100);
    await owner.rollback(110);

    expect(owner.activeGeneration, 100);
    await expectLater(
      owner.prepare(descriptor, generation: 109),
      throwsStateError,
    );
    await owner.prepare(descriptor, generation: 111);
  });
}

class _ControlledCapabilityP2pBridge extends _RecordingP2pBridge {
  final Completer<bool> _capability = Completer<bool>();

  @override
  Future<bool> isAvailable() => _capability.future;

  void completeCapability(bool value) {
    _capability.complete(value);
  }
}

class _ControlledOpenAndStopP2pBridge extends _ControlledOpenP2pBridge {
  final Map<int, Completer<void>> _stopCompleters =
      <int, Completer<void>>{};

  @override
  Future<void> stopGeneration(int generation) {
    stoppedExactly.add(generation);
    return (_stopCompleters[generation] ??= Completer<void>()).future;
  }

  void completeStopGeneration(int generation) {
    _stopCompleters[generation]!.complete();
  }
}

class _ControlledOpenP2pBridge extends _RecordingP2pBridge {
  final Map<int, Completer<Uri>> _openCompleters = <int, Completer<Uri>>{};

  @override
  Future<Uri> open(
    TvP2pStreamDescriptor descriptor, {
    required int generation,
  }) {
    opened.add(generation);
    return (_openCompleters[generation] ??= Completer<Uri>()).future;
  }

  void completeOpen(int generation) {
    _openCompleters[generation]!.complete(
      Uri.parse('http://127.0.0.1:43210/stream/g$generation'),
    );
  }
}

class _ControlledP2pBridge extends _RecordingP2pBridge {
  final Map<int, Completer<void>> _stopThroughCompleters =
      <int, Completer<void>>{};

  @override
  Future<void> stopThrough(int generation) {
    stoppedThrough.add(generation);
    return (_stopThroughCompleters[generation] ??= Completer<void>()).future;
  }

  void completeStopThrough(int generation) {
    _stopThroughCompleters[generation]!.complete();
  }
}

class _RecordingP2pBridge extends TvP2pLocalStreamBridge {
  final List<int> opened = <int>[];
  final List<int> stoppedThrough = <int>[];
  final List<int> stoppedExactly = <int>[];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String> networkBucket() async => 'ethernet';

  @override
  Future<Uri> open(
    TvP2pStreamDescriptor descriptor, {
    required int generation,
  }) async {
    opened.add(generation);
    return Uri.parse('http://127.0.0.1:43210/stream/g$generation');
  }

  @override
  Future<void> stopGeneration(int generation) async {
    stoppedExactly.add(generation);
  }

  @override
  Future<void> stopThrough(int generation) async {
    stoppedThrough.add(generation);
  }
}

class _CapabilityP2pBridge extends TvP2pLocalStreamBridge {
  const _CapabilityP2pBridge(this.result);

  final Future<bool> result;

  @override
  Future<bool> isAvailable() => result;

  @override
  Future<String> networkBucket() async => 'unavailable';

  @override
  Future<Uri> open(
    TvP2pStreamDescriptor descriptor, {
    required int generation,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> stopGeneration(int generation) async {}

  @override
  Future<void> stopThrough(int generation) async {}
}
