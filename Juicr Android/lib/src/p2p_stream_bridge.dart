import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class P2pStreamDescriptor {
  const P2pStreamDescriptor({
    required this.infoHash,
    this.fileIdx,
    this.trackers = const <String>[],
    this.displayName,
    this.quality,
  });

  factory P2pStreamDescriptor.fromAddonStream(Map<String, dynamic> stream) {
    final infoHash =
        _normalizeInfoHash((stream['infoHash'] ?? '').toString()) ?? '';
    final fileIdx = int.tryParse((stream['fileIdx'] ?? '').toString());
    return P2pStreamDescriptor(
      infoHash: infoHash,
      fileIdx: fileIdx,
      trackers: _trackerList(stream['sources']),
      displayName: _optionalText(stream['name'] ?? stream['title']),
      quality: _optionalText(stream['quality']),
    );
  }

  final String infoHash;
  final int? fileIdx;
  final List<String> trackers;
  final String? displayName;
  final String? quality;

  bool get isUsable => _normalizeInfoHash(infoHash) != null;

  String get syntheticUrl {
    final normalizedInfoHash = _normalizeInfoHash(infoHash) ?? infoHash;
    final uri = Uri(
      scheme: 'juicr-p2p',
      host: 'stream',
      queryParameters: <String, String>{
        'ih': normalizedInfoHash,
        if (fileIdx != null) 'fileIdx': fileIdx.toString(),
        if (displayName != null && displayName!.trim().isNotEmpty)
          'name': displayName!.trim(),
        if (quality != null && quality!.trim().isNotEmpty)
          'quality': quality!.trim(),
      },
    );
    final trackerQuery = trackers
        .map((tracker) => 'tr=${Uri.encodeQueryComponent(tracker)}')
        .join('&');
    return trackerQuery.isEmpty ? uri.toString() : '$uri&$trackerQuery';
  }

  static P2pStreamDescriptor? fromSyntheticUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'juicr-p2p') return null;
    final infoHash = _normalizeInfoHash(uri.queryParameters['ih'] ?? '');
    if (infoHash == null) return null;
    return P2pStreamDescriptor(
      infoHash: infoHash,
      fileIdx: int.tryParse(uri.queryParameters['fileIdx'] ?? ''),
      trackers: uri.queryParametersAll['tr'] ?? const <String>[],
      displayName: _optionalText(uri.queryParameters['name']),
      quality: _optionalText(uri.queryParameters['quality']),
    );
  }

  String get redactedDiagnostic {
    return 'infoHash=[hidden] fileIdx=${fileIdx ?? 'auto'} trackers=${trackers.length}';
  }

  String get lockedOperatorSummary {
    return [
      'p2pLocked=true',
      'fileIdx=${fileIdx ?? 'auto'}',
      'trackers=${trackers.length}',
      'quality=${_safeDescriptorLabel(quality)}',
      'label=${displayName == null ? 'absent' : 'present'}',
    ].join(' ');
  }
}

String? _normalizeInfoHash(String value) {
  var cleaned = value.trim();
  final btihIndex = cleaned.toLowerCase().indexOf('btih:');
  if (btihIndex >= 0) {
    cleaned = cleaned.substring(btihIndex + 'btih:'.length);
  }
  cleaned = cleaned.split(RegExp(r'[&?#\s]')).first.trim().toLowerCase();
  cleaned = cleaned.replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (RegExp(r'[a-f0-9]{40}').hasMatch(cleaned) && cleaned.length == 40) {
    return cleaned;
  }
  if (RegExp(r'[a-z2-7]{32}').hasMatch(cleaned) && cleaned.length == 32) {
    return _base32InfoHashToHex(cleaned);
  }
  return null;
}

String? _base32InfoHashToHex(String value) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
  final bytes = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final codeUnit in value.toLowerCase().codeUnits) {
    final index = alphabet.indexOf(String.fromCharCode(codeUnit));
    if (index < 0) return null;
    buffer = (buffer << 5) | index;
    bits += 5;
    while (bits >= 8) {
      bits -= 8;
      bytes.add((buffer >> bits) & 0xff);
      buffer = bits == 0 ? 0 : buffer & ((1 << bits) - 1);
    }
  }
  if (bytes.length != 20) return null;
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class P2pBridgeApprovalRequirement {
  const P2pBridgeApprovalRequirement({
    required this.id,
    required this.label,
    required this.status,
  });

  final String id;
  final String label;
  final String status;

  Map<String, Object> toJson() {
    return <String, Object>{'id': id, 'label': label, 'status': status};
  }
}

class P2pBridgeApprovalChecklist {
  const P2pBridgeApprovalChecklist({required this.requirements});

  factory P2pBridgeApprovalChecklist.lockedBaseline() {
    return const P2pBridgeApprovalChecklist(
      requirements: <P2pBridgeApprovalRequirement>[
        P2pBridgeApprovalRequirement(
          id: 'architectureApproval',
          label: 'Chosen bridge path, rejected alternatives, rollback plan',
          status: 'missing',
        ),
        P2pBridgeApprovalRequirement(
          id: 'dependencyReview',
          label: 'Exact package/library, license, size, maintenance review',
          status: 'missing',
        ),
        P2pBridgeApprovalRequirement(
          id: 'permissionReview',
          label: 'Android permission diff and Play policy review',
          status: 'missing',
        ),
        P2pBridgeApprovalRequirement(
          id: 'privacyReview',
          label: 'IP, bandwidth, battery, storage, redaction review',
          status: 'missing',
        ),
        P2pBridgeApprovalRequirement(
          id: 'resourceBudget',
          label: 'Bandwidth, battery, thermal, storage, session limits',
          status: 'missing',
        ),
        P2pBridgeApprovalRequirement(
          id: 'sessionLifecycle',
          label: 'Start, pause, stop, cleanup, foreground/background rules',
          status: 'missing',
        ),
        P2pBridgeApprovalRequirement(
          id: 'killSwitchReview',
          label: 'Force-disable switch, trigger sources, disabled UX',
          status: 'missing',
        ),
        P2pBridgeApprovalRequirement(
          id: 'rollbackDrill',
        label: 'Rollback drill, cache cleanup, direct/account restoration',
          status: 'missing',
        ),
        P2pBridgeApprovalRequirement(
          id: 'releaseExclusion',
          label:
              'No non-Beta/default release path until controlled proof exists',
          status: 'missing',
        ),
        P2pBridgeApprovalRequirement(
          id: 'consentProof',
          label: 'Heavy consent, disable path, visible P2P labels',
          status: 'ready',
        ),
        P2pBridgeApprovalRequirement(
          id: 'realDeviceProof',
          label: 'Movie, series, animation/animation diagnostics',
          status: 'missing',
        ),
      ],
    );
  }

  final List<P2pBridgeApprovalRequirement> requirements;

  bool get canEnableBridge {
    return requirements.every((requirement) => requirement.status == 'ready');
  }

  List<P2pBridgeApprovalRequirement> get missingRequirements {
    return requirements
        .where((requirement) => requirement.status != 'ready')
        .toList(growable: false);
  }

  P2pBridgeApprovalRequirement? get nextMissingRequirement {
    return missingRequirements.isEmpty ? null : missingRequirements.first;
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'canEnableBridge': canEnableBridge,
      'missingRequirementCount': missingRequirements.length,
      if (nextMissingRequirement != null)
        'nextMissingRequirement': nextMissingRequirement!.toJson(),
      'requirements': requirements
          .map((requirement) => requirement.toJson())
          .toList(growable: false),
    };
  }
}

class P2pRuntimeCapabilityState {
  const P2pRuntimeCapabilityState({
    required this.id,
    required this.label,
    required this.available,
    required this.approved,
    required this.selected,
    required this.effective,
    required this.lockedReason,
  });

  final String id;
  final String label;
  final bool available;
  final bool approved;
  final bool selected;
  final bool effective;
  final String lockedReason;

  static List<P2pRuntimeCapabilityState> lockedBaseline({
    bool localBridgeAvailable = false,
  }) {
    return <P2pRuntimeCapabilityState>[
      const P2pRuntimeCapabilityState(
        id: 'directDebridFirst',
        label: 'Direct/account-backed first',
        available: true,
        approved: true,
        selected: true,
        effective: true,
        lockedReason: 'Recommended fallback stays active.',
      ),
      P2pRuntimeCapabilityState(
        id: 'externalHandoff',
        label: 'External handoff',
        available: false,
        approved: false,
        selected: false,
        effective: false,
        lockedReason: 'External route proof is missing.',
      ),
      P2pRuntimeCapabilityState(
        id: 'localBridge',
        label: 'Local bridge',
        available: localBridgeAvailable,
        approved: false,
        selected: localBridgeAvailable,
        effective: false,
        lockedReason: localBridgeAvailable
            ? 'Installed for controlled Beta playback; source health still needs live buffering proof.'
            : 'Local bridge is not installed in this build.',
      ),
      P2pRuntimeCapabilityState(
        id: 'nativeP2pEngine',
        label: 'Native P2P engine',
        available: localBridgeAvailable,
        approved: false,
        selected: localBridgeAvailable,
        effective: false,
        lockedReason: localBridgeAvailable
            ? 'Beta runtime dependency is present; heavy consent and real-device proof still apply.'
            : 'Native engine proof is missing.',
      ),
      const P2pRuntimeCapabilityState(
        id: 'wifiOnly',
        label: 'Wi-Fi only',
        available: true,
        approved: false,
        selected: true,
        effective: true,
        lockedReason: 'Enforced by Battery & data with bucketed network state.',
      ),
      const P2pRuntimeCapabilityState(
        id: 'batteryLimits',
        label: 'Battery limits',
        available: true,
        approved: false,
        selected: true,
        effective: true,
        lockedReason:
            'Enforced by Battery & data with Android battery evidence.',
      ),
      const P2pRuntimeCapabilityState(
        id: 'advancedDiagnostics',
        label: 'Advanced diagnostics',
        available: false,
        approved: false,
        selected: false,
        effective: false,
        lockedReason: 'Redacted diagnostics proof is missing.',
      ),
    ];
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'id': id,
      'label': label,
      'available': available,
      'approved': approved,
      'selected': selected,
      'effective': effective,
      'lockedReason': lockedReason,
    };
  }
}

abstract class P2pLocalStreamBridge {
  const P2pLocalStreamBridge();

  static const P2pLocalStreamBridge instance =
      MethodChannelP2pLocalStreamBridge();

  bool get isAvailable;

  String get unavailableReason;

  Future<Uri> open(P2pStreamDescriptor descriptor);

  Future<String> networkBucket();

  Future<void> stopAll();
}

class MethodChannelP2pLocalStreamBridge extends P2pLocalStreamBridge {
  const MethodChannelP2pLocalStreamBridge();

  static const MethodChannel _channel = MethodChannel(
    'app.juicr.flutter/p2p_bridge',
  );

  @override
  bool get isAvailable => defaultTargetPlatform == TargetPlatform.android;

  @override
  String get unavailableReason =>
      'Advanced P2P playback support is only available in Android builds that include the Beta runtime.';

  @override
  Future<Uri> open(P2pStreamDescriptor descriptor) async {
    if (!descriptor.isUsable) {
      throw ArgumentError('Missing P2P info hash.');
    }
    final localUrl = await _channel.invokeMethod<String>('open', {
      'infoHash': descriptor.infoHash,
      'fileIdx': descriptor.fileIdx,
      'trackers': descriptor.trackers,
      'displayName': descriptor.displayName,
      'quality': descriptor.quality,
    });
    final uri = Uri.tryParse(localUrl ?? '');
    if (uri == null || uri.host != '127.0.0.1') {
      throw StateError('P2P bridge did not return a local playback URL.');
    }
    return uri;
  }

  @override
  Future<String> networkBucket() async {
    final bucket = await _channel.invokeMethod<String>('networkBucket');
    return _safeNetworkBucket(bucket);
  }

  @override
  Future<void> stopAll() async {
    await _channel.invokeMethod<void>('stopAll');
  }
}

class DisabledP2pLocalStreamBridge extends P2pLocalStreamBridge {
  const DisabledP2pLocalStreamBridge();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason =>
      'Advanced P2P playback support is not installed in this build.';

  @override
  Future<Uri> open(P2pStreamDescriptor descriptor) {
    throw UnsupportedError(unavailableReason);
  }

  @override
  Future<String> networkBucket() async => 'unavailable';

  @override
  Future<void> stopAll() async {}
}

String _safeNetworkBucket(String? value) {
  return switch ((value ?? '').trim().toLowerCase()) {
    'wifi' => 'wifi',
    'cellular' => 'cellular',
    'ethernet' => 'ethernet',
    'vpn' => 'vpn',
    'offline' => 'offline',
    'other' => 'other',
    _ => 'unavailable',
  };
}

List<String> _trackerList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => _normalizeTracker(item.toString()))
      .whereType<String>()
      .toSet()
      .toList(growable: false);
}

String? _normalizeTracker(String value) {
  var tracker = value.trim();
  if (tracker.isEmpty) return null;
  for (final prefix in const <String>['tracker:', 'announce:']) {
    if (tracker.toLowerCase().startsWith(prefix)) {
      tracker = tracker.substring(prefix.length).trim();
    }
  }
  final lower = tracker.toLowerCase();
  if (lower.startsWith('udp://') ||
      lower.startsWith('http://') ||
      lower.startsWith('https://')) {
    return tracker;
  }
  return null;
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String _safeDescriptorLabel(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'unknown';
  final safe = text.replaceAll(RegExp(r'[^A-Za-z0-9_.+-]'), '');
  if (safe.isEmpty) return 'unknown';
  return safe.length <= 18 ? safe : '${safe.substring(0, 18)}...';
}
