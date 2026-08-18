import 'dart:async';

import 'package:flutter/services.dart';

class TvP2pStreamDescriptor {
  const TvP2pStreamDescriptor({
    required this.infoHash,
    this.fileIdx,
    this.trackers = const <String>[],
    this.displayName,
    this.quality,
  });

  factory TvP2pStreamDescriptor.fromAddonStream(
    Map<String, dynamic> stream,
  ) {
    return TvP2pStreamDescriptor(
      infoHash: _normalizeInfoHash((stream['infoHash'] ?? '').toString()) ?? '',
      fileIdx: int.tryParse((stream['fileIdx'] ?? '').toString()),
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
  int get trackerCount => trackers.length;

  Map<String, Object?> toNativeArguments({required int generation}) {
    if (!isUsable || generation <= 0) {
      throw ArgumentError('P2P playback descriptor is not usable.');
    }
    return <String, Object?>{
      'infoHash': infoHash,
      'fileIdx': fileIdx,
      'trackers': trackers,
      'displayName': displayName,
      'quality': quality,
      'generation': generation,
    };
  }

  @override
  String toString() {
    return 'TvP2pStreamDescriptor(fileIdx=${fileIdx ?? 'auto'}, '
        'trackers=$trackerCount, label=${displayName == null ? 'absent' : 'present'})';
  }
}

String tvP2pRouteIdentityKey(TvP2pStreamDescriptor descriptor) {
  final hash = descriptor.infoHash.trim().toLowerCase();
  return 'p2p:$hash:${descriptor.fileIdx ?? 'auto'}';
}

abstract class TvP2pLocalStreamBridge {
  const TvP2pLocalStreamBridge();

  Future<bool> isAvailable();

  Future<Map<String, Object?>> availabilityStatus() async =>
      const <String, Object?>{
        'available': false,
        'stage': 'unknown',
        'bucket': 'unavailable',
      };

  Future<Uri> open(
    TvP2pStreamDescriptor descriptor, {
    required int generation,
  });

  Future<String> networkBucket();

  Future<String> readinessStage(int generation) async => 'unknown';

  Future<void> stopThrough(int generation);

  Future<void> stopGeneration(int generation);
}

Future<bool> resolveTvP2pRuntimeCapability({
  TvP2pLocalStreamBridge bridge =
      const MethodChannelTvP2pLocalStreamBridge(),
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    return await bridge.isAvailable().timeout(timeout);
  } catch (_) {
    return false;
  }
}

class TvP2pRuntimeCapability {
  TvP2pRuntimeCapability._();

  static bool _available = false;

  static bool get available => _available;

  static void configure(bool available) {
    _available = available;
  }
}

bool tvP2pPlaybackEffective({
  required bool savedEnabled,
  required bool hasConsent,
  required bool hasEnabledAddOns,
}) {
  return TvP2pRuntimeCapability.available &&
      savedEnabled &&
      hasConsent &&
      hasEnabledAddOns;
}

bool tvP2pSavedPreferenceEnabled({
  required bool savedEnabled,
  required bool hasConsent,
  required bool hasEnabledAddOns,
}) {
  return savedEnabled && hasConsent && hasEnabledAddOns;
}

Duration tvP2pCandidateStartupBudget({
  required bool libVlc,
  required String qualityLabel,
  required int trackerCount,
}) {
  // Dead discovery stages still rotate early through
  // tvP2pReadinessAbandonAfter. A viable warm candidate may spend most of a
  // minute acquiring pieces, so reserve the remaining route window for native
  // startup proof instead of expiring immediately after handoff.
  return const Duration(seconds: 80);
}

Duration tvP2pRouteStartupBudget() => const Duration(seconds: 90);

Duration? tvP2pReadinessAbandonAfter({
  required String stage,
  required int trackerCount,
}) {
  final normalized = stage.trim().toLowerCase();
  final noTrackers = trackerCount <= 0;
  return switch (normalized) {
    'failed' => Duration.zero,
    'metadata_trackers_missing' || 'metadata_discovery_inactive' =>
      const Duration(seconds: 6),
    'metadata_discovery_waiting' when noTrackers =>
      const Duration(seconds: 6),
    'metadata_peers_missing' when noTrackers =>
      const Duration(seconds: 10),
    'metadata_metadata_waiting' when noTrackers =>
      const Duration(seconds: 14),
    'peers' => Duration(seconds: noTrackers ? 16 : 14),
    _ => null,
  };
}

Future<T> tvAwaitP2pStartupWithRollback<T>({
  required Future<T> startup,
  required Duration timeout,
  required Future<void> Function() rollback,
  Future<String> Function()? readinessStage,
  Duration? Function(String stage)? abandonAfterForStage,
  Duration pollInterval = const Duration(seconds: 1),
  Duration readinessProbeTimeout = const Duration(seconds: 1),
  Duration rollbackTimeout = const Duration(seconds: 2),
}) async {
  final settled = startup.then<_TvP2pStartupSettlement<T>>(
    (value) => _TvP2pStartupSettlement<T>.value(value),
    onError: (Object error, StackTrace stackTrace) =>
        _TvP2pStartupSettlement<T>.error(error, stackTrace),
  );
  final stopwatch = Stopwatch()..start();
  var stage = 'unknown';
  var readinessSampled = false;

  Future<void> settleRollback() async {
    final settlement = Future<void>.sync(rollback).catchError((_) {});
    await settlement.timeout(rollbackTimeout, onTimeout: () {});
  }

  Future<String> sampleReadiness(Duration remaining) async {
    final probe = readinessStage;
    if (probe == null || remaining <= Duration.zero) return 'unknown';
    final timeout = remaining < readinessProbeTimeout
        ? remaining
        : readinessProbeTimeout;
    try {
      return _safeReadinessStage(
        await probe().timeout(timeout, onTimeout: () => 'unknown'),
      );
    } catch (_) {
      return 'unknown';
    }
  }

  while (stopwatch.elapsed < timeout) {
    stage = await sampleReadiness(timeout - stopwatch.elapsed);
    readinessSampled = true;
    final abandonAfter = abandonAfterForStage?.call(stage);
    if (abandonAfter != null && stopwatch.elapsed >= abandonAfter) {
      await settleRollback();
      throw TimeoutException(
        'P2P playback startup timed out (stage=$stage).',
      );
    }
    final remaining = timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) break;
    final wait = remaining < pollInterval ? remaining : pollInterval;
    final outcome = await Future.any<Object?>(<Future<Object?>>[
      settled,
      Future<void>.delayed(wait),
    ]);
    if (outcome is _TvP2pStartupSettlement<T>) {
      if (outcome.error != null) {
        Error.throwWithStackTrace(outcome.error!, outcome.stackTrace!);
      }
      return outcome.value as T;
    }
  }

  if (!readinessSampled) {
    stage = await sampleReadiness(timeout - stopwatch.elapsed);
  }
  await settleRollback();
  throw TimeoutException('P2P playback startup timed out (stage=$stage).');
}

class _TvP2pStartupSettlement<T> {
  const _TvP2pStartupSettlement.value(this.value)
      : error = null,
        stackTrace = null;

  const _TvP2pStartupSettlement.error(this.error, this.stackTrace)
      : value = null;

  final T? value;
  final Object? error;
  final StackTrace? stackTrace;
}

class TvP2pLifecycleGate {
  Future<void>? _suspendSettlement;
  bool _needsResume = false;

  bool get needsResume => _needsResume;

  Future<void> suspend({
    required bool hasActiveTransport,
    required Future<void> Function() pausePlayback,
    required Future<void> Function() closeTransport,
  }) async {
    if (!hasActiveTransport || _needsResume) return;
    _needsResume = true;
    final settlement = () async {
      await pausePlayback();
      await closeTransport();
    }();
    _suspendSettlement = settlement;
    try {
      await settlement;
    } finally {
      if (identical(_suspendSettlement, settlement)) {
        _suspendSettlement = null;
      }
    }
  }

  Future<void> resume({
    required Future<void> Function() reopenPlayback,
  }) async {
    final settlement = _suspendSettlement;
    if (settlement != null) await settlement;
    if (!_needsResume) return;
    _needsResume = false;
    try {
      await reopenPlayback();
    } catch (_) {
      _needsResume = true;
      rethrow;
    }
  }
}

class MethodChannelTvP2pLocalStreamBridge extends TvP2pLocalStreamBridge {
  const MethodChannelTvP2pLocalStreamBridge({
    this.channel = const MethodChannel('app.juicr.flutter/p2p_bridge'),
    this.readinessTimeout = const Duration(seconds: 60),
    this.readinessPollInterval = const Duration(seconds: 1),
  });

  final MethodChannel channel;
  final Duration readinessTimeout;
  final Duration readinessPollInterval;
  static final Map<MethodChannel, Map<int, Completer<void>>>
      _generationCancellations =
      <MethodChannel, Map<int, Completer<void>>>{};

  Map<int, Completer<void>> get _cancellations =>
      _generationCancellations.putIfAbsent(
        channel,
        () => <int, Completer<void>>{},
      );

  Future<T> _awaitGeneration<T>(
    Future<T> operation,
    Completer<void> cancellation,
    DateTime deadline,
  ) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return Future<T>.error(
        TimeoutException('P2P local playback deadline expired.'),
      );
    }
    return Future.any<T>(<Future<T>>[
      operation,
      cancellation.future.then<T>(
        (_) => throw StateError('P2P playback generation was cancelled.'),
      ),
    ]).timeout(remaining);
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await channel.invokeMethod<bool>('isAvailable') == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Map<String, Object?>> availabilityStatus() async {
    try {
      final value = await channel.invokeMapMethod<String, Object?>(
        'availabilityStatus',
      );
      const stages = <String>{
        'ready', 'native_shim_loader', 'swig_jni_loader',
        'native_version_probe', 'session_manager', 'settings_pack',
        'sha1_hash', 'announce_entry', 'priority', 'torrent_flags',
        'torrent_handle', 'unknown',
      };
      const buckets = <String>{
        'available', 'native_library', 'missing_class', 'permission',
        'unavailable',
      };
      final stage = value?['stage']?.toString() ?? 'unknown';
      final bucket = value?['bucket']?.toString() ?? 'unavailable';
      return <String, Object?>{
        'available': value?['available'] == true,
        'stage': stages.contains(stage) ? stage : 'unknown',
        'bucket': buckets.contains(bucket) ? bucket : 'unavailable',
      };
    } on PlatformException {
      return super.availabilityStatus();
    } on MissingPluginException {
      return super.availabilityStatus();
    }
  }

  @override
  Future<Uri> open(
    TvP2pStreamDescriptor descriptor, {
    required int generation,
  }) async {
    final deadline = DateTime.now().add(readinessTimeout);
    final cancellation = Completer<void>();
    _cancellations[generation] = cancellation;
    try {
      final localUrl = await _awaitGeneration<String?>(
        channel.invokeMethod<String>(
            'open',
            descriptor.toNativeArguments(generation: generation),
          ),
        cancellation,
        deadline,
      );
      final uri = Uri.tryParse(localUrl ?? '');
      if (uri == null ||
          uri.scheme != 'http' ||
          uri.host != '127.0.0.1' ||
          !uri.hasPort ||
          uri.port <= 0 ||
          uri.port > 65535 ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment) {
        throw StateError('P2P bridge did not return a local playback URL.');
      }
      while (DateTime.now().isBefore(deadline)) {
        final ready = await _awaitGeneration<bool?>(
          channel.invokeMethod<bool>(
              'isReady',
              <String, Object>{'generation': generation},
            ),
          cancellation,
          deadline,
        );
        if (ready == true) return uri;
        final delayRemaining = deadline.difference(DateTime.now());
        if (delayRemaining <= Duration.zero) break;
        await _awaitGeneration<void>(
          Future<void>.delayed(
            delayRemaining < readinessPollInterval
                ? delayRemaining
                : readinessPollInterval,
          ),
          cancellation,
          deadline,
        );
      }
      throw TimeoutException('P2P local playback did not become readable.');
    } catch (error, stackTrace) {
      try {
        await channel
            .invokeMethod<void>(
              'stopGeneration',
              <String, Object>{'generation': generation},
            )
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // Preserve the original open/readiness failure.
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _cancellations.remove(generation);
      if (_cancellations.isEmpty) {
        _generationCancellations.remove(channel);
      }
    }
  }

  @override
  Future<String> networkBucket() async {
    try {
      return _safeNetworkBucket(
        await channel.invokeMethod<String>('networkBucket'),
      );
    } on PlatformException {
      return 'unavailable';
    } on MissingPluginException {
      return 'unavailable';
    }
  }

  @override
  Future<String> readinessStage(int generation) async {
    if (generation <= 0) return 'unknown';
    try {
      final status = await channel
          .invokeMapMethod<String, Object?>(
            'readinessStatus',
            <String, Object>{'generation': generation},
          )
          .timeout(const Duration(seconds: 1));
      final stage = _safeReadinessStage(status?['stage']);
      if (stage != 'metadata') return stage;
      final discovery = _safeMetadataDiscoveryStage(status?['discovery']);
      return discovery == null ? stage : '${stage}_$discovery';
    } on PlatformException {
      return 'unknown';
    } on MissingPluginException {
      return 'unknown';
    }
  }

  @override
  Future<void> stopThrough(int generation) async {
    if (generation <= 0) return;
    for (final entry in _cancellations.entries.toList()) {
      if (entry.key <= generation && !entry.value.isCompleted) {
        entry.value.complete();
      }
    }
    await channel
        .invokeMethod<void>('stopAll', <String, Object>{
          'generation': generation,
        })
        .timeout(const Duration(seconds: 2));
  }

  @override
  Future<void> stopGeneration(int generation) async {
    if (generation <= 0) return;
    final cancellation = _cancellations[generation];
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    await channel
        .invokeMethod<void>('stopGeneration', <String, Object>{
          'generation': generation,
        })
        .timeout(const Duration(seconds: 2));
  }
}

class TvP2pPlaybackOwner {
  TvP2pPlaybackOwner({required this.bridge});

  final TvP2pLocalStreamBridge bridge;
  int? _activeGeneration;
  int _closedThroughGeneration = 0;
  int _finalizedThroughGeneration = 0;
  final Set<int> _preparedGenerations = <int>{};

  int? get activeGeneration => _activeGeneration;
  bool get hasActiveTransport => _activeGeneration != null;

  Future<String> readinessStage(int generation) =>
      bridge.readinessStage(generation);

  bool _isFinalized(int generation) =>
      generation <= _finalizedThroughGeneration;

  Future<Uri> prepare(
    TvP2pStreamDescriptor descriptor, {
    required int generation,
  }) async {
    if (generation <= 0) {
      throw ArgumentError('P2P playback generation must be positive.');
    }
    if (_isFinalized(generation)) {
      throw StateError('P2P playback generation is already closed.');
    }
    if (!await bridge.isAvailable()) {
      throw StateError('Advanced playback is unavailable.');
    }
    if (_isFinalized(generation)) {
      throw StateError('P2P playback generation closed during preparation.');
    }
    final uri = await bridge.open(descriptor, generation: generation);
    if (_isFinalized(generation)) {
      await bridge.stopGeneration(generation);
      throw StateError('P2P playback generation closed during preparation.');
    }
    _preparedGenerations.add(generation);
    return uri;
  }

  Future<void> commit(int generation) async {
    if (!_preparedGenerations.remove(generation)) {
      throw StateError('P2P playback generation was not prepared.');
    }
    await bridge.stopThrough(generation - 1);
    final activeGeneration = _activeGeneration;
    if (_isFinalized(generation) ||
        (activeGeneration != null && activeGeneration > generation)) {
      await bridge.stopGeneration(generation);
      return;
    }
    _activeGeneration = generation;
  }

  Future<void> rollback(int generation) async {
    _preparedGenerations.remove(generation);
    if (generation > _finalizedThroughGeneration) {
      _finalizedThroughGeneration = generation;
    }
    if (_activeGeneration == generation) {
      _activeGeneration = null;
    }
    await bridge.stopGeneration(generation);
  }

  Future<void> closeThrough(int generation) async {
    _preparedGenerations.removeWhere((value) => value <= generation);
    if (generation > _closedThroughGeneration) {
      _closedThroughGeneration = generation;
    }
    if (generation > _finalizedThroughGeneration) {
      _finalizedThroughGeneration = generation;
    }
    if ((_activeGeneration ?? 0) <= generation) {
      _activeGeneration = null;
    }
    await bridge.stopThrough(generation);
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
  if (RegExp(r'^[a-f0-9]{40}$').hasMatch(cleaned)) return cleaned;
  if (RegExp(r'^[a-z2-7]{32}$').hasMatch(cleaned)) {
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

List<String> _trackerList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => _normalizeTracker(item.toString()))
      .whereType<String>()
      .toSet()
      .take(32)
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
  final uri = Uri.tryParse(tracker);
  if (uri == null || uri.host.isEmpty) return null;
  return switch (uri.scheme.toLowerCase()) {
    'http' || 'https' || 'udp' => tracker,
    _ => null,
  };
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
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

String _safeReadinessStage(Object? value) {
  return switch ((value ?? '').toString().trim().toLowerCase()) {
    'starting' => 'starting',
    'handle' => 'handle',
    'metadata' => 'metadata',
    'metadata_trackers_missing' => 'metadata_trackers_missing',
    'metadata_discovery_inactive' => 'metadata_discovery_inactive',
    'metadata_discovery_waiting' => 'metadata_discovery_waiting',
    'metadata_peers_missing' => 'metadata_peers_missing',
    'metadata_metadata_waiting' => 'metadata_metadata_waiting',
    'metadata_metadata_ready' => 'metadata_metadata_ready',
    'file' => 'file',
    'peers' => 'peers',
    'pieces' => 'pieces',
    'ready' => 'ready',
    'failed' => 'failed',
    _ => 'unknown',
  };
}

String? _safeMetadataDiscoveryStage(Object? value) {
  return switch ((value ?? '').toString().trim().toLowerCase()) {
    'trackers_missing' => 'trackers_missing',
    'discovery_inactive' => 'discovery_inactive',
    'discovery_waiting' => 'discovery_waiting',
    'peers_missing' => 'peers_missing',
    'metadata_waiting' => 'metadata_waiting',
    'metadata_ready' => 'metadata_ready',
    _ => null,
  };
}
