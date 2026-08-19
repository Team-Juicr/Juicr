import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/p2p_stream_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.juicr.flutter/p2p_bridge.test');
  const descriptor = P2pStreamDescriptor(
    infoHash: '0123456789abcdef0123456789abcdef01234567',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('generation cancellation settles a pending readiness probe', () async {
    final calls = <MethodCall>[];
    final firstProbe = Completer<void>();
    final pendingReadiness = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'open') {
        return 'http://127.0.0.1:43210/stream/opaque';
      }
      if (call.method == 'isReady') {
        if (!firstProbe.isCompleted) firstProbe.complete();
        return pendingReadiness.future;
      }
      return null;
    });
    const bridge = MethodChannelP2pLocalStreamBridge(
      channel: channel,
      readinessTimeout: Duration(seconds: 1),
      readinessPollInterval: Duration(milliseconds: 20),
    );

    final opening = bridge.open(descriptor, generation: 41);
    await firstProbe.future;
    await bridge.stopGeneration(41);

    await expectLater(
      opening.timeout(const Duration(milliseconds: 100)),
      throwsStateError,
    );
    final probeCount = calls.where((call) => call.method == 'isReady').length;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
        calls.where((call) => call.method == 'isReady'), hasLength(probeCount));
    expect(calls.last.method, 'stopGeneration');
    expect(calls.last.arguments, <String, Object>{'generation': 41});
  });

  test('P2P replacement promotes only its prepared generation', () async {
    final bridge = _RecordingP2pBridge();
    final owner = P2pPlaybackOwner(bridge: bridge);

    final localUri = await owner.prepare(descriptor, generation: 21);

    expect(localUri.toString(), 'http://127.0.0.1:43210/stream/g21');
    expect(owner.activeGeneration, isNull);
    expect(bridge.stoppedThrough, isEmpty);

    await owner.commit(21);

    expect(owner.activeGeneration, 21);
    expect(bridge.stoppedThrough, <int>[20]);
  });

  test('failed replacement stops only its generation', () async {
    final bridge = _RecordingP2pBridge();
    final owner = P2pPlaybackOwner(bridge: bridge);

    await owner.prepare(descriptor, generation: 30);
    await owner.commit(30);
    bridge.stoppedThrough.clear();

    await owner.prepare(descriptor, generation: 31);
    await owner.rollback(31);

    expect(owner.activeGeneration, 30);
    expect(bridge.stoppedExactly, <int>[31]);
    expect(bridge.stoppedThrough, isEmpty);
  });

  test('successful replacement with direct media retires active P2P', () async {
    final bridge = _RecordingP2pBridge();
    final owner = P2pPlaybackOwner(bridge: bridge);

    await owner.prepare(descriptor, generation: 30);
    await owner.commit(30);
    bridge.stoppedThrough.clear();

    await owner.closeActive();

    expect(owner.activeGeneration, isNull);
    expect(bridge.stoppedExactly, <int>[30]);
  });

  test('late older preparation cannot publish after route cleanup', () async {
    final bridge = _ControlledOpenP2pBridge();
    final owner = P2pPlaybackOwner(bridge: bridge);

    final delayedPrepare = owner.prepare(descriptor, generation: 40);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.opened, <int>[40]);

    await owner.closeThrough(40);
    bridge.completeOpen(40);

    await expectLater(delayedPrepare, throwsStateError);
    expect(owner.activeGeneration, isNull);
    expect(bridge.stoppedExactly, <int>[40]);
    expect(bridge.stoppedThrough, <int>[40]);
  });
}

class _RecordingP2pBridge extends P2pLocalStreamBridge {
  final List<int> opened = <int>[];
  final List<int> stoppedThrough = <int>[];
  final List<int> stoppedExactly = <int>[];

  @override
  bool get isAvailable => true;

  @override
  String get unavailableReason => '';

  @override
  Future<String> networkBucket() async => 'ethernet';

  @override
  Future<Uri> open(
    P2pStreamDescriptor descriptor, {
    int? generation,
  }) async {
    if (generation == null) throw StateError('generation required');
    opened.add(generation);
    return Uri.parse('http://127.0.0.1:43210/stream/g$generation');
  }

  @override
  Future<void> stopGeneration(int generation) async {
    stoppedExactly.add(generation);
  }

  @override
  Future<void> stopAll() async {}

  @override
  Future<void> stopThrough(int generation) async {
    stoppedThrough.add(generation);
  }
}

class _ControlledOpenP2pBridge extends _RecordingP2pBridge {
  final Map<int, Completer<Uri>> _openCompleters = <int, Completer<Uri>>{};

  @override
  Future<Uri> open(
    P2pStreamDescriptor descriptor, {
    int? generation,
  }) {
    if (generation == null) throw StateError('generation required');
    opened.add(generation);
    return (_openCompleters[generation] ??= Completer<Uri>()).future;
  }

  void completeOpen(int generation) {
    _openCompleters[generation]!.complete(
      Uri.parse('http://127.0.0.1:43210/stream/g$generation'),
    );
  }
}
