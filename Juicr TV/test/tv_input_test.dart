import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_input.dart';

void main() {
  test('maps common TV remote keys into safe action buckets', () {
    const mapper = TvRemoteInputMapper();

    expect(mapper.bucketForKey(LogicalKeyboardKey.arrowUp), TvRemoteActionBucket.dpadUp);
    expect(mapper.bucketForKey(LogicalKeyboardKey.select), TvRemoteActionBucket.select);
    expect(mapper.bucketForKey(LogicalKeyboardKey.mediaPlayPause), TvRemoteActionBucket.mediaPlayPause);
    expect(mapper.bucketForKey(LogicalKeyboardKey.mediaFastForward), TvRemoteActionBucket.seekNext);
    expect(mapper.bucketForKey(LogicalKeyboardKey.mediaRewind), TvRemoteActionBucket.seekPrevious);
    expect(mapper.bucketForKey(LogicalKeyboardKey.goBack), TvRemoteActionBucket.back);
    expect(mapper.bucketForKey(LogicalKeyboardKey.browserBack), TvRemoteActionBucket.back);
    expect(mapper.bucketForKey(LogicalKeyboardKey.navigateOut), TvRemoteActionBucket.back);
    expect(mapper.bucketForKey(LogicalKeyboardKey.gameButtonB), TvRemoteActionBucket.back);
  });

  test('debug snapshots expose only remote-safe labels and state', () {
    const snapshot = TvRemoteDebugSnapshot(
      lastKeyBucket: TvRemoteActionBucket.mediaPlayPause,
      currentSurfaceName: 'playback',
      currentFocusLabel: 'tv-playback-play',
      controlsVisible: true,
      controlsLocked: false,
    );

    expect(snapshot.toDebugMap(), {
      'last_key_bucket': 'media_play_pause',
      'current_surface_name': 'playback',
      'current_focus_label': 'tv-playback-play',
      'controls_visible': true,
      'controls_locked': false,
    });
  });

  test('playback action resolver keeps media keys and menu keys deterministic', () {
    const resolver = TvPlaybackRemoteActionResolver();

    expect(resolver.commandFor(TvRemoteActionBucket.mediaPlayPause), TvPlaybackRemoteCommand.togglePlay);
    expect(resolver.commandFor(TvRemoteActionBucket.mediaPlay), TvPlaybackRemoteCommand.play);
    expect(resolver.commandFor(TvRemoteActionBucket.mediaPause), TvPlaybackRemoteCommand.pause);
    expect(resolver.commandFor(TvRemoteActionBucket.seekNext), TvPlaybackRemoteCommand.seekForward);
    expect(resolver.commandFor(TvRemoteActionBucket.seekPrevious), TvPlaybackRemoteCommand.seekBack);
    expect(resolver.commandFor(TvRemoteActionBucket.captions), TvPlaybackRemoteCommand.openSettings);
    expect(resolver.commandFor(TvRemoteActionBucket.settings), TvPlaybackRemoteCommand.openSettings);
    expect(resolver.commandFor(TvRemoteActionBucket.info), TvPlaybackRemoteCommand.openSettings);
    expect(resolver.commandFor(TvRemoteActionBucket.menu), TvPlaybackRemoteCommand.openSources);
  });

  test('native media commands execute without depending on HUD focus', () {
    for (final command in <TvPlaybackRemoteCommand>[
      TvPlaybackRemoteCommand.togglePlay,
      TvPlaybackRemoteCommand.play,
      TvPlaybackRemoteCommand.pause,
      TvPlaybackRemoteCommand.stop,
      TvPlaybackRemoteCommand.seekBack,
      TvPlaybackRemoteCommand.seekForward,
    ]) {
      expect(tvNativePlaybackCommandExecutesImmediately(command), isTrue);
    }
    expect(
      tvNativePlaybackCommandExecutesImmediately(
        TvPlaybackRemoteCommand.showControls,
      ),
      isFalse,
    );
    expect(
      tvNativePlaybackCommandExecutesImmediately(
        TvPlaybackRemoteCommand.openSources,
      ),
      isFalse,
    );
  });

  test('remote skip commands use the shared fifteen-second interval', () {
    expect(
      tvPlaybackSkipOffsetForCommand(TvPlaybackRemoteCommand.seekBack),
      const Duration(seconds: -15),
    );
    expect(
      tvPlaybackSkipOffsetForCommand(TvPlaybackRemoteCommand.seekForward),
      const Duration(seconds: 15),
    );
    expect(
      tvPlaybackSkipOffsetForCommand(TvPlaybackRemoteCommand.togglePlay),
      isNull,
    );
  });

  test('native directional capture is limited to an initialized hidden HUD', () {
    const policy = TvHiddenHudRemoteCapturePolicy();

    expect(
      policy.shouldCapture(
        initialized: true,
        controlsVisible: false,
        switchingSource: false,
        dialogOpen: false,
      ),
      isTrue,
    );
    expect(
      policy.shouldCapture(
        initialized: true,
        controlsVisible: true,
        switchingSource: false,
        dialogOpen: false,
      ),
      isFalse,
    );
    expect(
      policy.shouldCapture(
        initialized: true,
        controlsVisible: false,
        switchingSource: false,
        dialogOpen: true,
      ),
      isFalse,
    );
    expect(
      policy.shouldCapture(
        initialized: false,
        controlsVisible: false,
        switchingSource: false,
        dialogOpen: false,
      ),
      isFalse,
    );
    expect(
      policy.shouldCapture(
        initialized: true,
        controlsVisible: false,
        switchingSource: true,
        dialogOpen: false,
      ),
      isFalse,
    );
  });

  test('final playback dialog close refreshes hidden HUD capture ownership', () {
    expect(
      tvPlaybackDialogCloseNeedsHiddenHudRefresh(remainingDialogDepth: 0),
      isTrue,
    );
    expect(
      tvPlaybackDialogCloseNeedsHiddenHudRefresh(remainingDialogDepth: 1),
      isFalse,
    );
  });

  test('nested source selection waits out the child-close suppression window', () {
    final childClosedAt = DateTime(2026, 8, 16, 9);

    expect(
      tvPlaybackNestedDialogParentCloseDelay(
        childClosedAt: childClosedAt,
        now: childClosedAt.add(const Duration(milliseconds: 100)),
      ),
      const Duration(milliseconds: 320),
    );
    expect(
      tvPlaybackNestedDialogParentCloseDelay(
        childClosedAt: childClosedAt,
        now: childClosedAt.add(const Duration(milliseconds: 500)),
      ),
      Duration.zero,
    );
  });

  test('locked hidden HUD always reveals onto Unlock', () {
    const policy = TvPlaybackRevealFocusPolicy();

    for (final bucket in <TvRemoteActionBucket>[
      TvRemoteActionBucket.dpadUp,
      TvRemoteActionBucket.dpadDown,
      TvRemoteActionBucket.dpadLeft,
      TvRemoteActionBucket.dpadRight,
      TvRemoteActionBucket.select,
    ]) {
      expect(
        policy.targetFor(bucket: bucket, controlsLocked: true),
        TvPlaybackRevealFocusTarget.lock,
        reason: bucket.name,
      );
    }
  });

  test('native Select unlocks only the focused Unlock control', () {
    expect(
      tvNativeLockedRemoteShouldUnlock(
        bucket: TvRemoteActionBucket.select,
        unlockFocused: true,
        isRepeat: false,
      ),
      isTrue,
    );
    expect(
      tvNativeLockedRemoteShouldUnlock(
        bucket: TvRemoteActionBucket.select,
        unlockFocused: false,
        isRepeat: false,
      ),
      isFalse,
    );
    expect(
      tvNativeLockedRemoteShouldUnlock(
        bucket: TvRemoteActionBucket.select,
        unlockFocused: true,
        isRepeat: true,
      ),
      isFalse,
    );
  });

  test('playback dialog owns directional and select keys', () {
    const ownership = TvPlaybackDialogKeyOwnership();

    expect(
      ownership.shouldPassThrough(TvPlaybackRemoteCommand.showControls),
      isTrue,
    );
    expect(
      ownership.shouldPassThrough(TvPlaybackRemoteCommand.openSources),
      isTrue,
    );
    expect(ownership.shouldPassThrough(null), isTrue);
    expect(
      ownership.shouldPassThrough(TvPlaybackRemoteCommand.close),
      isFalse,
    );
  });
}
