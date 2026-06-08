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
}
