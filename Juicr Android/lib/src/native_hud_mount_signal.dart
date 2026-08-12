import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

enum NativeHudTransportSlot { leftSkip, centerPlayPause, rightSkip }

class NativeHudTransportMountOwner {
  NativeHudTransportMountOwner(this.generation);

  final int generation;
  final GlobalKey activePlayerBoundsKey = GlobalKey();
  final GlobalKey leftSkipKey = GlobalKey();
  final GlobalKey centerPlayPauseKey = GlobalKey();
  final GlobalKey rightSkipKey = GlobalKey();
  final Set<NativeHudTransportSlot> _completedAnimations =
      <NativeHudTransportSlot>{};

  void markAnimationCompleted(NativeHudTransportSlot slot) {
    _completedAnimations.add(slot);
  }

  void resetAnimationCompletion() {
    _completedAnimations.clear();
  }

  bool get animationCompleted =>
      _completedAnimations.length == NativeHudTransportSlot.values.length;
}

bool nativeHudTransportRenderObjectReady({
  required GlobalKey activePlayerBoundsKey,
  required GlobalKey controlKey,
}) {
  final activeBounds = activePlayerBoundsKey.currentContext?.findRenderObject();
  final control = controlKey.currentContext?.findRenderObject();
  if (activeBounds is! RenderBox ||
      control is! RenderBox ||
      !activeBounds.attached ||
      !control.attached ||
      !activeBounds.hasSize ||
      !control.hasSize ||
      activeBounds.size.isEmpty ||
      control.size.isEmpty ||
      control.paintBounds.isEmpty) {
    return false;
  }
  final controlRect = MatrixUtils.transformRect(
    control.getTransformTo(activeBounds),
    Offset.zero & control.size,
  );
  final activeRect = Offset.zero & activeBounds.size;
  return !controlRect.isEmpty &&
      activeRect.contains(controlRect.topLeft) &&
      activeRect.contains(controlRect.bottomRight);
}

class NativeHudMountSignalEvent {
  const NativeHudMountSignalEvent({
    required this.generation,
    required this.mounted,
  });

  final int generation;
  final bool mounted;

  String get diagnostic => mounted
      ? 'native hud transport mounted generation=$generation mounted=true'
      : 'native hud transport invalidated generation=$generation mounted=false';
}

class NativeHudMountSignalGate {
  static const int _maximumGeneration = 0x7fffffff;

  int? _visibleGeneration;
  int? _mountedGeneration;
  bool _disposed = false;

  NativeHudMountSignalEvent? beginVisibleGeneration(int generation) {
    if (_disposed || generation < 0 || generation > _maximumGeneration) {
      return null;
    }
    if (_visibleGeneration == generation) return null;
    final invalidated = _invalidateMountedGeneration();
    _visibleGeneration = generation;
    return invalidated;
  }

  NativeHudMountSignalEvent? completePostFrame({
    required int generation,
    required bool visible,
    required bool animationCompleted,
    required bool leftSkipMounted,
    required bool centerControlMounted,
    required bool rightSkipMounted,
    required bool playerVerified,
    required bool loading,
  }) {
    if (_disposed ||
        _visibleGeneration != generation ||
        _mountedGeneration == generation ||
        !visible ||
        !animationCompleted ||
        !leftSkipMounted ||
        !centerControlMounted ||
        !rightSkipMounted ||
        !playerVerified ||
        loading) {
      return null;
    }
    _mountedGeneration = generation;
    return NativeHudMountSignalEvent(generation: generation, mounted: true);
  }

  NativeHudMountSignalEvent? hide(int generation) {
    if (_disposed || _visibleGeneration != generation) return null;
    _visibleGeneration = null;
    return _invalidateMountedGeneration();
  }

  NativeHudMountSignalEvent? dispose() {
    if (_disposed) return null;
    final invalidated = _invalidateMountedGeneration();
    _visibleGeneration = null;
    _disposed = true;
    return invalidated;
  }

  NativeHudMountSignalEvent? _invalidateMountedGeneration() {
    final generation = _mountedGeneration;
    if (generation == null) return null;
    _mountedGeneration = null;
    return NativeHudMountSignalEvent(generation: generation, mounted: false);
  }
}
