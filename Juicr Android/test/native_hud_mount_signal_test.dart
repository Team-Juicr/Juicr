import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:juicr/src/native_hud_mount_signal.dart';

void main() {
  group('NativeHudMountSignalGate', () {
    test('does not emit while loading hidden or player unverified', () {
      final gate = NativeHudMountSignalGate();
      gate.beginVisibleGeneration(4);

      expect(
        gate.completePostFrame(
          generation: 4,
          visible: true,
          animationCompleted: true,
          leftSkipMounted: true,
          centerControlMounted: true,
          rightSkipMounted: true,
          playerVerified: true,
          loading: true,
        ),
        isNull,
      );
      expect(
        gate.completePostFrame(
          generation: 4,
          visible: false,
          animationCompleted: true,
          leftSkipMounted: true,
          centerControlMounted: true,
          rightSkipMounted: true,
          playerVerified: true,
          loading: false,
        ),
        isNull,
      );
      expect(
        gate.completePostFrame(
          generation: 4,
          visible: true,
          animationCompleted: true,
          leftSkipMounted: true,
          centerControlMounted: true,
          rightSkipMounted: true,
          playerVerified: false,
          loading: false,
        ),
        isNull,
      );
    });

    test('does not emit before every transport control is mounted', () {
      final gate = NativeHudMountSignalGate()..beginVisibleGeneration(7);

      expect(
        gate.completePostFrame(
          generation: 7,
          visible: true,
          animationCompleted: true,
          leftSkipMounted: false,
          centerControlMounted: true,
          rightSkipMounted: false,
          playerVerified: true,
          loading: false,
        ),
        isNull,
      );
    });

    test('does not emit while only the center control is painted', () {
      final gate = NativeHudMountSignalGate()..beginVisibleGeneration(71);

      expect(
        gate.completePostFrame(
          generation: 71,
          visible: true,
          animationCompleted: true,
          leftSkipMounted: false,
          centerControlMounted: true,
          rightSkipMounted: false,
          playerVerified: true,
          loading: false,
        ),
        isNull,
      );
    });

    test('does not emit before the staged transport animation completes', () {
      final gate = NativeHudMountSignalGate()..beginVisibleGeneration(72);

      expect(
        gate.completePostFrame(
          generation: 72,
          visible: true,
          animationCompleted: false,
          leftSkipMounted: true,
          centerControlMounted: true,
          rightSkipMounted: true,
          playerVerified: true,
          loading: false,
        ),
        isNull,
      );
    });

    test('emits exactly once after verified current-generation mount', () {
      final gate = NativeHudMountSignalGate()..beginVisibleGeneration(8);

      final event = gate.completePostFrame(
        generation: 8,
        visible: true,
        animationCompleted: true,
        leftSkipMounted: true,
        centerControlMounted: true,
        rightSkipMounted: true,
        playerVerified: true,
        loading: false,
      );

      expect(event?.diagnostic,
          'native hud transport mounted generation=8 mounted=true');
      expect(
        gate.completePostFrame(
          generation: 8,
          visible: true,
          animationCompleted: true,
          leftSkipMounted: true,
          centerControlMounted: true,
          rightSkipMounted: true,
          playerVerified: true,
          loading: false,
        ),
        isNull,
      );
    });

    test('stale generation cannot emit after a newer reveal', () {
      final gate = NativeHudMountSignalGate()
        ..beginVisibleGeneration(9)
        ..beginVisibleGeneration(10);

      expect(
        gate.completePostFrame(
          generation: 9,
          visible: true,
          animationCompleted: true,
          leftSkipMounted: true,
          centerControlMounted: true,
          rightSkipMounted: true,
          playerVerified: true,
          loading: false,
        ),
        isNull,
      );
    });

    test('new generation invalidates a previously mounted generation', () {
      final gate = NativeHudMountSignalGate()..beginVisibleGeneration(11);
      gate.completePostFrame(
        generation: 11,
        visible: true,
        animationCompleted: true,
        leftSkipMounted: true,
        centerControlMounted: true,
        rightSkipMounted: true,
        playerVerified: true,
        loading: false,
      );

      final event = gate.beginVisibleGeneration(12);

      expect(event?.diagnostic,
          'native hud transport invalidated generation=11 mounted=false');
    });

    test('hide invalidates once and blocks the old generation', () {
      final gate = NativeHudMountSignalGate()..beginVisibleGeneration(13);
      gate.completePostFrame(
        generation: 13,
        visible: true,
        animationCompleted: true,
        leftSkipMounted: true,
        centerControlMounted: true,
        rightSkipMounted: true,
        playerVerified: true,
        loading: false,
      );

      expect(
        gate.hide(13)?.diagnostic,
        'native hud transport invalidated generation=13 mounted=false',
      );
      expect(gate.hide(13), isNull);
      expect(
        gate.completePostFrame(
          generation: 13,
          visible: true,
          animationCompleted: true,
          leftSkipMounted: true,
          centerControlMounted: true,
          rightSkipMounted: true,
          playerVerified: true,
          loading: false,
        ),
        isNull,
      );
    });

    test('dispose invalidates once and rejects all later callbacks', () {
      final gate = NativeHudMountSignalGate()..beginVisibleGeneration(14);
      gate.completePostFrame(
        generation: 14,
        visible: true,
        animationCompleted: true,
        leftSkipMounted: true,
        centerControlMounted: true,
        rightSkipMounted: true,
        playerVerified: true,
        loading: false,
      );

      expect(
        gate.dispose()?.diagnostic,
        'native hud transport invalidated generation=14 mounted=false',
      );
      expect(gate.dispose(), isNull);
      gate.beginVisibleGeneration(15);
      expect(
        gate.completePostFrame(
          generation: 15,
          visible: true,
          animationCompleted: true,
          leftSkipMounted: true,
          centerControlMounted: true,
          rightSkipMounted: true,
          playerVerified: true,
          loading: false,
        ),
        isNull,
      );
    });
  });

  group('nativeHudTransportRenderObjectReady', () {
    testWidgets('accepts attached nonzero controls inside active player bounds',
        (tester) async {
      final owner = NativeHudTransportMountOwner(21);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              key: owner.activePlayerBoundsKey,
              width: 300,
              height: 180,
              child: Stack(
                children: [
                  Positioned(
                    left: 55,
                    top: 65,
                    child: SizedBox.square(
                      key: owner.leftSkipKey,
                      dimension: 50,
                    ),
                  ),
                  Positioned(
                    left: 120,
                    top: 55,
                    child: SizedBox.square(
                      key: owner.centerPlayPauseKey,
                      dimension: 70,
                    ),
                  ),
                  Positioned(
                    left: 195,
                    top: 65,
                    child: SizedBox.square(
                      key: owner.rightSkipKey,
                      dimension: 50,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(
        nativeHudTransportRenderObjectReady(
          activePlayerBoundsKey: owner.activePlayerBoundsKey,
          controlKey: owner.leftSkipKey,
        ),
        isTrue,
      );
      expect(
        nativeHudTransportRenderObjectReady(
          activePlayerBoundsKey: owner.activePlayerBoundsKey,
          controlKey: owner.centerPlayPauseKey,
        ),
        isTrue,
      );
      expect(
        nativeHudTransportRenderObjectReady(
          activePlayerBoundsKey: owner.activePlayerBoundsKey,
          controlKey: owner.rightSkipKey,
        ),
        isTrue,
      );
    });

    testWidgets('rejects zero-size detached or out-of-bounds controls',
        (tester) async {
      final owner = NativeHudTransportMountOwner(22);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              key: owner.activePlayerBoundsKey,
              width: 300,
              height: 180,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 55,
                    top: 65,
                    child: SizedBox(
                      key: owner.leftSkipKey,
                      width: 0,
                      height: 0,
                    ),
                  ),
                  Positioned(
                    left: 290,
                    top: 65,
                    child: SizedBox.square(
                      key: owner.rightSkipKey,
                      dimension: 50,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(
        nativeHudTransportRenderObjectReady(
          activePlayerBoundsKey: owner.activePlayerBoundsKey,
          controlKey: owner.leftSkipKey,
        ),
        isFalse,
      );
      expect(
        nativeHudTransportRenderObjectReady(
          activePlayerBoundsKey: owner.activePlayerBoundsKey,
          controlKey: owner.centerPlayPauseKey,
        ),
        isFalse,
      );
      expect(
        nativeHudTransportRenderObjectReady(
          activePlayerBoundsKey: owner.activePlayerBoundsKey,
          controlKey: owner.rightSkipKey,
        ),
        isFalse,
      );
    });
  });
}
