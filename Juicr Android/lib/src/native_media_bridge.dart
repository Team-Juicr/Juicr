import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'diagnostic_log.dart';

class NativeMediaCapabilities {
  const NativeMediaCapabilities({
    required this.schema,
    required this.sdk,
    required this.device,
    required this.media3Available,
    required this.media3UiAvailable,
    required this.legacyExoPlayerAvailable,
    required this.surfaceControlAvailable,
    required this.pictureInPictureAvailable,
    required this.decoderSummary,
  });

  factory NativeMediaCapabilities.fromMap(Map<Object?, Object?> raw) {
    final decoderItems =
        (raw['decoders'] as List<Object?>?) ?? const <Object?>[];
    final decoders = decoderItems
        .whereType<Map<Object?, Object?>>()
        .map((entry) {
          final mime = (entry['mime'] ?? '').toString();
          final count = _intValue(entry['count']);
          final hardwareCount = _intValue(entry['hardwareCount']);
          final secureCount = _intValue(entry['secureCount']);
          return '$mime:$count/$hardwareCount/$secureCount';
        })
        .where((entry) => entry.isNotEmpty)
        .join(',');
    return NativeMediaCapabilities(
      schema: (raw['schema'] ?? '').toString(),
      sdk: _intValue(raw['sdk']),
      device: (raw['device'] ?? '').toString(),
      media3Available: raw['media3Available'] == true,
      media3UiAvailable: raw['media3UiAvailable'] == true,
      legacyExoPlayerAvailable: raw['legacyExoPlayerAvailable'] == true,
      surfaceControlAvailable: raw['surfaceControlAvailable'] == true,
      pictureInPictureAvailable: raw['pictureInPictureAvailable'] == true,
      decoderSummary: decoders,
    );
  }

  final String schema;
  final int sdk;
  final String device;
  final bool media3Available;
  final bool media3UiAvailable;
  final bool legacyExoPlayerAvailable;
  final bool surfaceControlAvailable;
  final bool pictureInPictureAvailable;
  final String decoderSummary;

  String get diagnosticSummary {
    return 'schema=$schema sdk=$sdk media3=$media3Available '
        'media3Ui=$media3UiAvailable legacyExo=$legacyExoPlayerAvailable '
        'surfaceControl=$surfaceControlAvailable pip=$pictureInPictureAvailable '
        'decoders=$decoderSummary';
  }
}

class NativeMediaBridge {
  const NativeMediaBridge._();

  static const MethodChannel _channel = MethodChannel(
    'app.juicr.flutter/native_media',
  );

  static Future<NativeMediaCapabilities?> loadCapabilities() async {
    if (kIsWeb) return null;
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'capabilities',
      );
      if (raw == null) return null;
      final capabilities = NativeMediaCapabilities.fromMap(raw);
      DiagnosticLog.add(
        'native media capabilities ${capabilities.diagnosticSummary}',
      );
      return capabilities;
    } catch (error) {
      DiagnosticLog.add('native media capabilities unavailable error=$error');
      return null;
    }
  }
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse((value ?? '').toString()) ?? 0;
}
