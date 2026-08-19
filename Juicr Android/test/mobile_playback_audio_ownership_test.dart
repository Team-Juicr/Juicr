import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/mobile_playback_audio_ownership.dart';

void main() {
  test('staged replacement stays silent until active playback retires',
      () async {
    final events = <String>[];

    expect(
      mobileReplacementTargetVolume(
        requestedVolume: 0.72,
        staged: true,
      ),
      0,
    );

    final transferred = await mobileTransferReplacementAudioOwnership(
      silenceActive: () async => events.add('active-silent'),
      activateTarget: () async => events.add('target-audible'),
      promoteTarget: () async {
        events.add('target-promoted');
        return true;
      },
      silenceTarget: () async => events.add('target-silent'),
      cleanupActive: () async => events.add('active-cleaned'),
    );

    expect(transferred, isTrue);
    expect(
      events,
      <String>[
        'active-silent',
        'target-audible',
        'target-promoted',
        'active-cleaned',
      ],
    );
  });

  test('stalled cleanup cannot leave a proven replacement muted', () async {
    final events = <String>[];
    final cleanup = Completer<void>();

    final transferred = await mobileTransferReplacementAudioOwnership(
      silenceActive: () async => events.add('active-silent'),
      activateTarget: () async => events.add('target-audible'),
      promoteTarget: () async {
        events.add('target-promoted');
        return true;
      },
      silenceTarget: () async => events.add('target-silent'),
      cleanupActive: () => cleanup.future,
      cleanupTimeout: const Duration(milliseconds: 1),
    );

    expect(transferred, isTrue);
    expect(
      events,
      <String>['active-silent', 'target-audible', 'target-promoted'],
    );
  });

  test('target stays muted when active audio cannot be silenced', () async {
    final events = <String>[];

    final transferred = await mobileTransferReplacementAudioOwnership(
      silenceActive: () async => throw StateError('still audible'),
      activateTarget: () async => events.add('target-audible'),
      promoteTarget: () async {
        events.add('target-promoted');
        return true;
      },
      silenceTarget: () async => events.add('target-silent'),
      cleanupActive: () async => events.add('active-cleaned'),
    );

    expect(transferred, isFalse);
    expect(events, isEmpty);
  });

  test('failed promotion leaves cleanup and target activation untouched',
      () async {
    final events = <String>[];

    final transferred = await mobileTransferReplacementAudioOwnership(
      silenceActive: () async => events.add('active-silent'),
      activateTarget: () async => events.add('target-audible'),
      promoteTarget: () async {
        events.add('target-rejected');
        return false;
      },
      silenceTarget: () async => events.add('target-silent'),
      cleanupActive: () async => events.add('active-cleaned'),
    );

    expect(transferred, isFalse);
    expect(
      events,
      <String>[
        'active-silent',
        'target-audible',
        'target-rejected',
        'target-silent',
      ],
    );
  });

  test('failed target activation leaves promotion and cleanup untouched',
      () async {
    final events = <String>[];

    final transferred = await mobileTransferReplacementAudioOwnership(
      silenceActive: () async => events.add('active-silent'),
      activateTarget: () async => throw StateError('volume unavailable'),
      promoteTarget: () async {
        events.add('target-promoted');
        return true;
      },
      silenceTarget: () async => events.add('target-silent'),
      cleanupActive: () async => events.add('active-cleaned'),
    );

    expect(transferred, isFalse);
    expect(events, <String>['active-silent']);
  });

  test('ordinary startup keeps the requested target volume', () {
    expect(
      mobileReplacementTargetVolume(
        requestedVolume: 0.72,
        staged: false,
      ),
      0.72,
    );
  });

  test('libVLC audio proof requires a playable selected track', () {
    expect(
      mobileLibVlcHasSelectedAudioTrack(trackCount: 2, trackId: 1),
      isTrue,
    );
    expect(
      mobileLibVlcHasSelectedAudioTrack(trackCount: 2, trackId: -1),
      isFalse,
    );
    expect(
      mobileLibVlcHasSelectedAudioTrack(trackCount: 0, trackId: 1),
      isFalse,
    );
  });

  test('libVLC audio repair retains valid selection or picks first playable',
      () {
    const tracks = <int, String>{-1: 'Disable', 4: 'English', 7: 'Spanish'};
    expect(
      mobilePreferredLibVlcAudioTrack(tracks: tracks, activeTrack: 7),
      7,
    );
    expect(
      mobilePreferredLibVlcAudioTrack(tracks: tracks, activeTrack: -1),
      4,
    );
    expect(
      mobilePreferredLibVlcAudioTrack(
        tracks: const <int, String>{-1: 'Disable'},
        activeTrack: -1,
      ),
      isNull,
    );
  });

  test('libVLC pigeon replies fail closed', () {
    expect(mobileDecodeLibVlcPigeonIntReply(<Object?>[3]), 3);
    expect(
      mobileDecodeLibVlcPigeonTracksReply(<Object?>[
        <Object?, Object?>{1: 'English'},
      ]),
      <int, String>{1: 'English'},
    );
    expect(
      () => mobileDecodeLibVlcPigeonIntReply(<Object?>[]),
      throwsStateError,
    );
    expect(
      () => mobileDecodeLibVlcPigeonTracksReply(<Object?>[
        <Object?, Object?>{'bad': 'English'},
      ]),
      throwsStateError,
    );
  });
}
