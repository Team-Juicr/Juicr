import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'android/app/src/main/kotlin/app/juicr/flutter/JuicrMedia3PlayerView.kt',
  ).readAsStringSync();

  test('Media3 avoids goldfish AVC only for adaptive emulator playback', () {
    expect(
      source,
      contains('private fun media3CodecSelectorForDevice(sourceType: String)'),
    );
    expect(source, contains('MediaCodecSelector.PREFER_SOFTWARE'));
    expect(
      source,
      contains('if (!isAndroidEmulator()) return MediaCodecSelector.DEFAULT'),
    );
    expect(
      source,
      contains(
        'if (sourceType != "hls" && sourceType != "ts") return MediaCodecSelector.DEFAULT',
      ),
      reason: 'Direct MP4 must retain the normal decoder order.',
    );
    expect(source, contains('hardware.contains("ranchu")'));
    expect(source, contains('hardware.contains("goldfish")'));
    expect(source, contains('model.contains("sdk_gphone")'));
    expect(source, contains('if (mimeType != MimeTypes.VIDEO_H264)'));
    expect(
      source,
      contains('.setMediaCodecSelector(media3CodecSelectorForDevice(sourceType))'),
    );
    expect(
      source,
      isNot(contains('fingerprint.startsWith("generic")')),
      reason: 'A generic build fingerprint alone is not emulator proof.',
    );
  });
}
