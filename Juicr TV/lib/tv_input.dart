import 'package:flutter/services.dart';

enum TvRemoteActionBucket {
  dpadUp,
  dpadDown,
  dpadLeft,
  dpadRight,
  select,
  back,
  mediaPlayPause,
  mediaPlay,
  mediaPause,
  mediaStop,
  seekNext,
  seekPrevious,
  search,
  menu,
  info,
  captions,
  settings,
  pageUp,
  pageDown,
  channelUp,
  channelDown,
}

extension TvRemoteActionBucketDebug on TvRemoteActionBucket {
  String get debugLabel {
    switch (this) {
      case TvRemoteActionBucket.dpadUp:
        return 'dpad_up';
      case TvRemoteActionBucket.dpadDown:
        return 'dpad_down';
      case TvRemoteActionBucket.dpadLeft:
        return 'dpad_left';
      case TvRemoteActionBucket.dpadRight:
        return 'dpad_right';
      case TvRemoteActionBucket.select:
        return 'select';
      case TvRemoteActionBucket.back:
        return 'back';
      case TvRemoteActionBucket.mediaPlayPause:
        return 'media_play_pause';
      case TvRemoteActionBucket.mediaPlay:
        return 'media_play';
      case TvRemoteActionBucket.mediaPause:
        return 'media_pause';
      case TvRemoteActionBucket.mediaStop:
        return 'media_stop';
      case TvRemoteActionBucket.seekNext:
        return 'seek_next';
      case TvRemoteActionBucket.seekPrevious:
        return 'seek_previous';
      case TvRemoteActionBucket.search:
        return 'search';
      case TvRemoteActionBucket.menu:
        return 'menu';
      case TvRemoteActionBucket.info:
        return 'info';
      case TvRemoteActionBucket.captions:
        return 'captions';
      case TvRemoteActionBucket.settings:
        return 'settings';
      case TvRemoteActionBucket.pageUp:
        return 'page_up';
      case TvRemoteActionBucket.pageDown:
        return 'page_down';
      case TvRemoteActionBucket.channelUp:
        return 'channel_up';
      case TvRemoteActionBucket.channelDown:
        return 'channel_down';
    }
  }
}

class TvRemoteInputMapper {
  const TvRemoteInputMapper();

  TvRemoteActionBucket? bucketForEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return null;
    }
    return bucketForKey(event.logicalKey);
  }

  TvRemoteActionBucket? bucketForKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) {
      return TvRemoteActionBucket.dpadUp;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return TvRemoteActionBucket.dpadDown;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return TvRemoteActionBucket.dpadLeft;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return TvRemoteActionBucket.dpadRight;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      return TvRemoteActionBucket.select;
    }
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.navigateOut ||
        key == LogicalKeyboardKey.gameButtonB) {
      return TvRemoteActionBucket.back;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      return TvRemoteActionBucket.mediaPlayPause;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      return TvRemoteActionBucket.mediaPlay;
    }
    if (key == LogicalKeyboardKey.mediaPause) {
      return TvRemoteActionBucket.mediaPause;
    }
    if (key == LogicalKeyboardKey.mediaStop) {
      return TvRemoteActionBucket.mediaStop;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext ||
        key == LogicalKeyboardKey.mediaSkipForward ||
        key == LogicalKeyboardKey.mediaStepForward ||
        key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.navigateNext) {
      return TvRemoteActionBucket.seekNext;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious ||
        key == LogicalKeyboardKey.mediaSkipBackward ||
        key == LogicalKeyboardKey.mediaStepBackward ||
        key == LogicalKeyboardKey.mediaRewind ||
        key == LogicalKeyboardKey.navigatePrevious) {
      return TvRemoteActionBucket.seekPrevious;
    }
    if (key == LogicalKeyboardKey.browserSearch ||
        key == LogicalKeyboardKey.find) {
      return TvRemoteActionBucket.search;
    }
    if (key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.mediaTopMenu ||
        key == LogicalKeyboardKey.tvContentsMenu ||
        key == LogicalKeyboardKey.gameButtonStart) {
      return TvRemoteActionBucket.menu;
    }
    if (key == LogicalKeyboardKey.info) {
      return TvRemoteActionBucket.info;
    }
    if (key == LogicalKeyboardKey.closedCaptionToggle) {
      return TvRemoteActionBucket.captions;
    }
    if (key == LogicalKeyboardKey.settings) {
      return TvRemoteActionBucket.settings;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      return TvRemoteActionBucket.pageUp;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      return TvRemoteActionBucket.pageDown;
    }
    if (key == LogicalKeyboardKey.channelUp) {
      return TvRemoteActionBucket.channelUp;
    }
    if (key == LogicalKeyboardKey.channelDown) {
      return TvRemoteActionBucket.channelDown;
    }
    return null;
  }
}

const tvRemoteInputMapper = TvRemoteInputMapper();

enum TvPlaybackRemoteCommand {
  togglePlay,
  play,
  pause,
  stop,
  seekForward,
  seekBack,
  openSources,
  openSettings,
  close,
  showControls,
}

class TvPlaybackRemoteActionResolver {
  const TvPlaybackRemoteActionResolver();

  TvPlaybackRemoteCommand? commandFor(TvRemoteActionBucket bucket) {
    return switch (bucket) {
      TvRemoteActionBucket.mediaPlayPause => TvPlaybackRemoteCommand.togglePlay,
      TvRemoteActionBucket.mediaPlay => TvPlaybackRemoteCommand.play,
      TvRemoteActionBucket.mediaPause => TvPlaybackRemoteCommand.pause,
      TvRemoteActionBucket.mediaStop => TvPlaybackRemoteCommand.stop,
      TvRemoteActionBucket.seekNext ||
      TvRemoteActionBucket.pageDown ||
      TvRemoteActionBucket.channelDown =>
        TvPlaybackRemoteCommand.seekForward,
      TvRemoteActionBucket.seekPrevious ||
      TvRemoteActionBucket.pageUp ||
      TvRemoteActionBucket.channelUp =>
        TvPlaybackRemoteCommand.seekBack,
      TvRemoteActionBucket.menu => TvPlaybackRemoteCommand.openSources,
      TvRemoteActionBucket.info ||
      TvRemoteActionBucket.captions ||
      TvRemoteActionBucket.settings =>
        TvPlaybackRemoteCommand.openSettings,
      TvRemoteActionBucket.back => TvPlaybackRemoteCommand.close,
      TvRemoteActionBucket.select ||
      TvRemoteActionBucket.dpadUp ||
      TvRemoteActionBucket.dpadDown ||
      TvRemoteActionBucket.dpadLeft ||
      TvRemoteActionBucket.dpadRight =>
        TvPlaybackRemoteCommand.showControls,
      TvRemoteActionBucket.search => null,
    };
  }
}

const tvPlaybackRemoteActionResolver = TvPlaybackRemoteActionResolver();

class TvRemoteDebugSnapshot {
  const TvRemoteDebugSnapshot({
    this.lastKeyBucket,
    this.currentSurfaceName = 'none',
    this.currentFocusLabel = 'none',
    this.controlsVisible = false,
    this.controlsLocked = false,
  });

  final TvRemoteActionBucket? lastKeyBucket;
  final String currentSurfaceName;
  final String currentFocusLabel;
  final bool controlsVisible;
  final bool controlsLocked;

  String get lastKeyLabel => lastKeyBucket?.debugLabel ?? 'none';

  TvRemoteDebugSnapshot copyWith({
    TvRemoteActionBucket? lastKeyBucket,
    bool clearLastKeyBucket = false,
    String? currentSurfaceName,
    String? currentFocusLabel,
    bool? controlsVisible,
    bool? controlsLocked,
  }) {
    return TvRemoteDebugSnapshot(
      lastKeyBucket: clearLastKeyBucket
          ? null
          : lastKeyBucket ?? this.lastKeyBucket,
      currentSurfaceName: currentSurfaceName ?? this.currentSurfaceName,
      currentFocusLabel: currentFocusLabel ?? this.currentFocusLabel,
      controlsVisible: controlsVisible ?? this.controlsVisible,
      controlsLocked: controlsLocked ?? this.controlsLocked,
    );
  }

  Map<String, Object> toDebugMap() {
    return <String, Object>{
      'last_key_bucket': lastKeyLabel,
      'current_surface_name': currentSurfaceName,
      'current_focus_label': currentFocusLabel,
      'controls_visible': controlsVisible,
      'controls_locked': controlsLocked,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TvRemoteDebugSnapshot &&
            other.lastKeyBucket == lastKeyBucket &&
            other.currentSurfaceName == currentSurfaceName &&
            other.currentFocusLabel == currentFocusLabel &&
            other.controlsVisible == controlsVisible &&
            other.controlsLocked == controlsLocked;
  }

  @override
  int get hashCode {
    return Object.hash(
      lastKeyBucket,
      currentSurfaceName,
      currentFocusLabel,
      controlsVisible,
      controlsLocked,
    );
  }

  @override
  String toString() {
    return 'TvRemoteDebugSnapshot(${toDebugMap()})';
  }
}
