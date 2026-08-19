double mobileReplacementTargetVolume({
  required double requestedVolume,
  required bool staged,
}) {
  return staged ? 0 : requestedVolume.clamp(0, 1).toDouble();
}

Future<bool> mobileTransferReplacementAudioOwnership({
  required Future<void> Function() silenceActive,
  required Future<void> Function() activateTarget,
  required Future<bool> Function() promoteTarget,
  required Future<void> Function() silenceTarget,
  required Future<void> Function() cleanupActive,
  Duration cleanupTimeout = const Duration(milliseconds: 700),
}) async {
  try {
    await silenceActive();
  } catch (_) {
    return false;
  }
  try {
    await activateTarget();
  } catch (_) {
    return false;
  }
  if (!await promoteTarget()) {
    try {
      await silenceTarget();
    } catch (_) {}
    return false;
  }
  try {
    await cleanupActive().timeout(cleanupTimeout);
  } catch (_) {}
  return true;
}

bool mobileLibVlcHasSelectedAudioTrack({
  required int trackCount,
  required int trackId,
}) {
  return trackCount > 0 && trackId >= 0;
}

int? mobilePreferredLibVlcAudioTrack({
  required Map<int, String> tracks,
  required int activeTrack,
}) {
  if (activeTrack >= 0 && tracks.containsKey(activeTrack)) return activeTrack;
  final playable = tracks.keys.where((track) => track >= 0).toList()..sort();
  return playable.isEmpty ? null : playable.first;
}

Object? _mobileDecodeLibVlcPigeonReply(Object? reply) {
  if (reply is! List<Object?> || reply.isEmpty) {
    throw StateError('libvlc_audio_reply_invalid');
  }
  if (reply.length != 1) {
    throw StateError('libvlc_audio_reply_error');
  }
  return reply.first;
}

int mobileDecodeLibVlcPigeonIntReply(Object? reply) {
  final value = _mobileDecodeLibVlcPigeonReply(reply);
  if (value is! num) throw StateError('libvlc_audio_reply_invalid');
  return value.toInt();
}

Map<int, String> mobileDecodeLibVlcPigeonTracksReply(Object? reply) {
  final value = _mobileDecodeLibVlcPigeonReply(reply);
  if (value is! Map<Object?, Object?>) {
    throw StateError('libvlc_audio_reply_invalid');
  }
  final tracks = <int, String>{};
  for (final entry in value.entries) {
    if (entry.key is! num || entry.value is! String) {
      throw StateError('libvlc_audio_reply_invalid');
    }
    tracks[(entry.key as num).toInt()] = entry.value! as String;
  }
  return tracks;
}
