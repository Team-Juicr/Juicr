import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'ad_policy.dart';
import 'app_state.dart';
import 'catalog_item.dart';
import 'diagnostic_log.dart';
import 'libvlc_hls_relay.dart';
import 'motion.dart';
import 'native_media_bridge.dart';
import 'p2p_indexer_connectors.dart';
import 'p2p_stream_bridge.dart';
import 'playback_provider.dart';
import 'source_ranking.dart';
import 'stream_api.dart';
import 'system_ui.dart';
import 'visual_style.dart';

const MethodChannel _pipChannel = MethodChannel('app.juicr.flutter/pip');
const MethodChannel _displayChannel = MethodChannel(
  'app.juicr.flutter/display',
);
const MethodChannel _castChannel = MethodChannel('app.juicr.flutter/cast');
const MethodChannel _media3PlayerChannel = MethodChannel(
  'app.juicr.flutter/media3_player',
);
const int _publicIptvMaxExpandedSources = 5;
const int _advancedP2pAvoidRiskSoftFallbackMinimum = 3;
const int _p2pSubstantialStartupBufferBytes = 6 * 1024 * 1024;
const String _liveTvUnavailableMessage =
    'Channel is offline or unavailable right now. Please try again later.';

String _safeDiagnosticError(Object error) {
  final type = error.runtimeType.toString();
  final text = error.toString().toLowerCase();
  final bucket = switch (text) {
    final value when value.contains('timeout') => 'timeout',
    final value
        when value.contains('socket') ||
            value.contains('host') ||
            value.contains('network') ||
            value.contains('connection') =>
      'network',
    final value
        when value.contains('403') ||
            value.contains('401') ||
            value.contains('unauthorized') ||
            value.contains('forbidden') =>
      'access',
    final value when value.contains('404') || value.contains('not found') =>
      'not_found',
    final value
        when value.contains('format') ||
            value.contains('parse') ||
            value.contains('codec') =>
      'format',
    final value
        when value.contains('platformexception') ||
            value.contains('exoplaybackexception') ||
            value.contains('vlc') =>
      'player',
    _ => 'unknown',
  };
  return '$type:$bucket';
}

bool _isAppSessionLibVlcUnavailableError(Object error) {
  if (error is TimeoutException) return false;
  final text = error.toString().toLowerCase();
  return text.contains('missingpluginexception') ||
      text.contains('no implementation found') ||
      text.contains('unsatisfiedlinkerror') ||
      text.contains('dlopen') ||
      text.contains('couldn\'t find "lib') ||
      text.contains('no such file') ||
      text.contains('noclassdeffounderror') ||
      text.contains('classnotfoundexception') ||
      text.contains('plugin not found');
}

String _nativeAudioCountBucket(int count) {
  if (count <= 0) return 'none';
  if (count == 1) return 'one';
  if (count <= 3) return 'few';
  return 'many';
}

String _libVlcAudioDiagnostic(VlcPlayerValue value) {
  final selected = value.activeAudioTrack >= 0 ? 'selected' : 'none';
  final muted = value.volume <= 0 ? 'muted' : 'audible';
  return 'available:${_nativeAudioCountBucket(value.audioTracksCount)},'
      'selected:$selected,volume:$muted';
}

Color _playerAccent(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

Color _playerAccentOverlay(BuildContext context, double alpha) =>
    _playerAccent(context).withValues(alpha: alpha);

BoxConstraints _playerSheetConstraints(
  BuildContext context, {
  double maxPortrait = 0.72,
  double maxLandscape = 0.78,
  double minPortrait = 0.34,
  double minLandscape = 0.58,
}) {
  final size = MediaQuery.sizeOf(context);
  final landscape = size.width > size.height;
  final maxHeight = size.height * (landscape ? maxLandscape : maxPortrait);
  final minHeight = math.min(
    size.height * (landscape ? minLandscape : minPortrait),
    maxHeight,
  );
  return BoxConstraints(minHeight: minHeight, maxHeight: maxHeight);
}

class NativePlayerPage extends StatefulWidget {
  const NativePlayerPage({
    super.key,
    required this.title,
    required this.sources,
    required this.resolveProvider,
    this.resolveSubtitles,
    this.logoUrl,
    this.progressItem,
    this.playbackKey,
    this.progressSubtitle,
    this.nextEpisodeLabel,
    this.onNextEpisode,
    this.enableProviderWarmup = true,
    this.limitToFirstQualityPass = false,
    this.liveMode = false,
  });

  final String title;
  final List<NativePlaybackRequest> sources;
  final Future<List<PlaybackSource>> Function(String providerId)
  resolveProvider;
  final Future<List<PlaybackSubtitle>> Function()? resolveSubtitles;
  final String? logoUrl;
  final CatalogItem? progressItem;
  final String? playbackKey;
  final String? progressSubtitle;
  final String? nextEpisodeLabel;
  final Future<NativePlayerNextEpisode?> Function()? onNextEpisode;
  final bool enableProviderWarmup;
  final bool limitToFirstQualityPass;
  final bool liveMode;

  static bool hasVerifiedSourceFor(String? playbackKey) {
    return _NativePlayerPageState.hasVerifiedSourceFor(playbackKey);
  }

  static String? firstVerifiedSourceKey(Iterable<String?> playbackKeys) {
    for (final key in playbackKeys) {
      if (hasVerifiedSourceFor(key)) return key;
    }
    return null;
  }

  @override
  State<NativePlayerPage> createState() => _NativePlayerPageState();
}

class NativePlaybackRequest {
  const NativePlaybackRequest({
    required this.providerId,
    this.sources = const <PlaybackSource>[],
  });

  final String providerId;
  final List<PlaybackSource> sources;
}

class NativePlayerNextEpisode {
  const NativePlayerNextEpisode({
    required this.title,
    required this.sources,
    required this.resolveProvider,
    this.resolveSubtitles,
    this.logoUrl,
    this.progressItem,
    this.playbackKey,
    this.progressSubtitle,
    this.nextEpisodeLabel,
    this.onNextEpisode,
    this.limitToFirstQualityPass = false,
  });

  final String title;
  final List<NativePlaybackRequest> sources;
  final Future<List<PlaybackSource>> Function(String providerId)
  resolveProvider;
  final Future<List<PlaybackSubtitle>> Function()? resolveSubtitles;
  final String? logoUrl;
  final CatalogItem? progressItem;
  final String? playbackKey;
  final String? progressSubtitle;
  final String? nextEpisodeLabel;
  final Future<NativePlayerNextEpisode?> Function()? onNextEpisode;
  final bool limitToFirstQualityPass;
}

enum VideoFitMode {
  fit,
  fill,
  wide,
  stretch;

  String get label {
    return switch (this) {
      VideoFitMode.fit => 'Fit',
      VideoFitMode.fill => 'Fill',
      VideoFitMode.wide => '16:9',
      VideoFitMode.stretch => 'Stretch',
    };
  }

  String get description {
    return switch (this) {
      VideoFitMode.fit => 'Show the whole video',
      VideoFitMode.fill => 'Fill screen and crop edges',
      VideoFitMode.wide => 'Force a widescreen frame',
      VideoFitMode.stretch => 'Stretch to screen',
    };
  }

  static VideoFitMode fromName(String? name) {
    return VideoFitMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => VideoFitMode.fit,
    );
  }
}

enum _NativePlaybackEngine {
  exoplayer,
  libvlc;

  String get id {
    return switch (this) {
      _NativePlaybackEngine.exoplayer => 'exoplayer',
      _NativePlaybackEngine.libvlc => 'libvlc',
    };
  }
}

class _Media3NativePlayerController {
  _Media3NativePlayerController(this.source, {required this.liveMode});

  final PlaybackSource source;
  final bool liveMode;
  final Completer<void> _viewReady = Completer<void>();
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  Timer? _pollTimer;
  int? _viewId;
  bool _disposed = false;
  bool isInitialized = false;
  bool hasError = false;
  bool isPlaying = false;
  bool isBuffering = false;
  bool isEnded = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  Size size = Size.zero;
  String errorDescription = '';
  bool firstFrameRendered = false;
  int droppedVideoFrames = 0;
  int bandwidthKbps = 0;
  String trackSummary = 'unknown';
  String audioTrackSummary = 'unknown';
  String sourceType = 'unknown';
  String mimeType = 'unknown';
  String headerCountBucket = 'none';
  String errorBucket = 'none';

  double get aspectRatio {
    if (size.width > 0 && size.height > 0) return size.width / size.height;
    return 16 / 9;
  }

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  Map<String, Object?> get creationParams {
    final settings = AppState.playerBehaviorSettings.value;
    return <String, Object?>{
      'url': source.url,
      'headers': source.headers,
      'type': source.type,
      'sourceClass': source.sourceClass.wireName,
      'liveMode': liveMode,
      'preferredAudioLanguage': settings.preferredAudioLanguage,
      'subtitleAutoSelect': settings.subtitleAutoSelect,
      'subtitleLanguage': settings.subtitleLanguage,
      'subtitles': source.subtitles
          .map(
            (subtitle) => <String, Object?>{
              'url': subtitle.url,
              'language': subtitle.language,
              'label': subtitle.label,
              'format': subtitle.format,
              'isDefault': subtitle.isDefault,
              'isForced': subtitle.isForced,
            },
          )
          .toList(),
    };
  }

  void attachView(int viewId) {
    if (_disposed) return;
    _viewId = viewId;
    if (!_viewReady.isCompleted) _viewReady.complete();
    _startPolling();
  }

  Future<void> initialize({Duration? timeout}) {
    final future = _initialize();
    return timeout == null ? future : future.timeout(timeout);
  }

  Future<void> _initialize() async {
    await _viewReady.future;
    _startPolling();
    while (!_disposed) {
      await _syncState();
      if (hasError) throw StateError(errorDescription);
      if (isInitialized) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<void> play() => _invoke('play');
  Future<void> pause() => _invoke('pause');
  Future<void> seekTo(Duration position) => _invoke('seekTo', <String, Object?>{
    'positionMs': position.inMilliseconds,
  });
  Future<void> setLooping(bool looping) =>
      _invoke('setLooping', <String, Object?>{'looping': looping});
  Future<void> setPlaybackSpeed(double speed) =>
      _invoke('setPlaybackSpeed', <String, Object?>{'speed': speed});
  Future<void> setVolume(double volume) =>
      _invoke('setVolume', <String, Object?>{'volume': volume});

  Future<void> _invoke(String method, [Map<String, Object?> args = const {}]) {
    final viewId = _viewId;
    if (viewId == null || _disposed) return Future<void>.value();
    return _media3PlayerChannel.invokeMethod<void>(method, <String, Object?>{
      'viewId': viewId,
      ...args,
    });
  }

  void _startPolling() {
    if (_pollTimer != null || _disposed) return;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      unawaited(_syncState());
    });
  }

  Future<void> _syncState() async {
    final viewId = _viewId;
    if (viewId == null || _disposed) return;
    final raw = await _media3PlayerChannel.invokeMapMethod<String, Object?>(
      'state',
      <String, Object?>{'viewId': viewId},
    );
    if (raw == null || _disposed) return;
    isInitialized = raw['initialized'] == true;
    hasError = raw['hasError'] == true;
    isPlaying = raw['playing'] == true;
    isBuffering = raw['buffering'] == true;
    isEnded = raw['ended'] == true;
    errorDescription = (raw['errorDescription'] as String?) ?? '';
    errorBucket = (raw['errorBucket'] as String?) ?? 'none';
    firstFrameRendered = raw['firstFrameRendered'] == true;
    droppedVideoFrames = (raw['droppedVideoFrames'] as num?)?.round() ?? 0;
    bandwidthKbps = (raw['bandwidthKbps'] as num?)?.round() ?? 0;
    trackSummary = (raw['trackSummary'] as String?) ?? 'unknown';
    audioTrackSummary = (raw['audioTrackSummary'] as String?) ?? 'unknown';
    sourceType = (raw['sourceType'] as String?) ?? 'unknown';
    mimeType = (raw['mimeType'] as String?) ?? 'unknown';
    headerCountBucket = (raw['headerCountBucket'] as String?) ?? 'none';
    duration = Duration(
      milliseconds: (raw['durationMs'] as num?)?.round() ?? 0,
    );
    position = Duration(
      milliseconds: (raw['positionMs'] as num?)?.round() ?? 0,
    );
    final width = (raw['width'] as num?)?.toDouble() ?? 0;
    final height = (raw['height'] as num?)?.toDouble() ?? 0;
    size = width > 0 && height > 0 ? Size(width, height) : Size.zero;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _listeners.clear();
    final viewId = _viewId;
    if (viewId != null) {
      await _media3PlayerChannel.invokeMethod<void>(
        'dispose',
        <String, Object?>{'viewId': viewId},
      );
    }
  }
}

class _NativePlaybackController {
  _NativePlaybackController._({
    required this.engine,
    this.video,
    this.vlc,
    this.media3,
    this.videoViewType,
    this.libVlcProfile,
  });

  factory _NativePlaybackController.network({
    required _NativePlaybackEngine engine,
    required PlaybackSource source,
    required bool liveMode,
    VideoViewType? exoViewType,
    _LibVlcProfile? libVlcProfile,
    bool media3NativeEnabled = true,
  }) {
    return switch (engine) {
      _NativePlaybackEngine.exoplayer => () {
        final viewType = exoViewType ?? _exoVideoViewTypeFor(source);
        if (defaultTargetPlatform == TargetPlatform.android &&
            AppState.playerBehaviorSettings.value.experimentalControlsEnabled &&
            AppState.playerBehaviorSettings.value.media3NativeExoEnabled &&
            media3NativeEnabled) {
          return _NativePlaybackController._(
            engine: engine,
            videoViewType: VideoViewType.platformView,
            media3: _Media3NativePlayerController(source, liveMode: liveMode),
          );
        }
        return _NativePlaybackController._(
          engine: engine,
          videoViewType: viewType,
          video: VideoPlayerController.networkUrl(
            Uri.parse(source.url),
            formatHint: _videoFormatHintFor(source),
            httpHeaders: source.headers,
            viewType: viewType,
          ),
        );
      }(),
      _NativePlaybackEngine.libvlc => _NativePlaybackController._(
        engine: engine,
        libVlcProfile: libVlcProfile ?? _libVlcProfiles.first,
        vlc: VlcPlayerController.network(
          source.url,
          hwAcc: (libVlcProfile ?? _libVlcProfiles.first).hwAcc,
          autoPlay: false,
          options: _vlcPlayerOptions(
            source.headers,
            libVlcProfile ?? _libVlcProfiles.first,
          ),
        ),
      ),
    };
  }

  final _NativePlaybackEngine engine;
  final VideoPlayerController? video;
  final VlcPlayerController? vlc;
  final _Media3NativePlayerController? media3;
  final VideoViewType? videoViewType;
  final _LibVlcProfile? libVlcProfile;

  bool get isInitialized =>
      video?.value.isInitialized ??
      vlc?.value.isInitialized ??
      media3?.isInitialized ??
      false;
  bool get hasError =>
      video?.value.hasError ?? vlc?.value.hasError ?? media3?.hasError ?? false;
  bool get isPlaying =>
      video?.value.isPlaying ??
      vlc?.value.isPlaying ??
      media3?.isPlaying ??
      false;
  bool get isBuffering =>
      video?.value.isBuffering ??
      vlc?.value.isBuffering ??
      media3?.isBuffering ??
      false;
  bool get isEnded =>
      video?.value.isCompleted ??
      vlc?.value.isEnded ??
      media3?.isEnded ??
      false;
  Duration get duration =>
      video?.value.duration ??
      vlc?.value.duration ??
      media3?.duration ??
      Duration.zero;
  Duration get position =>
      video?.value.position ??
      vlc?.value.position ??
      media3?.position ??
      Duration.zero;
  Size get size =>
      video?.value.size ?? vlc?.value.size ?? media3?.size ?? Size.zero;
  double get aspectRatio =>
      video?.value.aspectRatio ??
      vlc?.value.aspectRatio ??
      media3?.aspectRatio ??
      16 / 9;
  String get errorDescription =>
      video?.value.errorDescription ??
      vlc?.value.errorDescription ??
      media3?.errorDescription ??
      '';
  String get diagnosticProfile {
    final media3Controller = media3;
    if (media3Controller != null) {
      return 'media3 firstFrame=${media3Controller.firstFrameRendered} '
          'dropped=${media3Controller.droppedVideoFrames} '
          'bandwidthKbps=${media3Controller.bandwidthKbps} '
          'tracks=${media3Controller.trackSummary} '
          'audioTrack=${media3Controller.audioTrackSummary} '
          'sourceType=${media3Controller.sourceType} '
          'mime=${media3Controller.mimeType} '
          'headers=${media3Controller.headerCountBucket} '
          'errorBucket=${media3Controller.errorBucket}';
    }
    final profile = libVlcProfile;
    final vlcController = vlc;
    if (vlcController != null) {
      return 'libvlc profile=${profile?.id ?? 'unknown'} '
          'audioTrack=${_libVlcAudioDiagnostic(vlcController.value)}';
    }
    return 'video_player_wrapper audioTrack=unavailable_wrapper';
  }

  bool get requiresPlatformViewWarmup => media3 != null || vlc != null;

  void addListener(VoidCallback listener) {
    video?.addListener(listener);
    vlc?.addListener(listener);
    media3?.addListener(listener);
  }

  void removeListener(VoidCallback listener) {
    video?.removeListener(listener);
    vlc?.removeListener(listener);
    media3?.removeListener(listener);
  }

  Future<void> initialize({Duration? timeout}) {
    final videoController = video;
    if (videoController != null) {
      final future = videoController.initialize();
      return timeout == null ? future : future.timeout(timeout);
    }
    final media3Controller = media3;
    if (media3Controller != null) {
      return media3Controller.initialize(timeout: timeout);
    }
    final vlcController = vlc!;
    if (vlcController.value.isInitialized) return Future<void>.value();
    final completer = Completer<void>();
    late VoidCallback listener;
    var listenerAttached = false;
    void detachListener() {
      if (!listenerAttached) return;
      listenerAttached = false;
      vlcController.removeListener(listener);
    }

    listener = () {
      if (vlcController.value.hasError && !completer.isCompleted) {
        completer.completeError(vlcController.value.errorDescription);
      } else if (vlcController.value.isInitialized && !completer.isCompleted) {
        completer.complete();
      }
      if (completer.isCompleted) {
        detachListener();
      }
    };
    vlcController.addListener(listener);
    listenerAttached = true;
    if (timeout == null) return completer.future;
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        detachListener();
        throw TimeoutException('VLC initialize timed out', timeout);
      },
    );
  }

  Future<void> play() => video?.play() ?? vlc?.play() ?? media3!.play();
  Future<void> pause() => video?.pause() ?? vlc?.pause() ?? media3!.pause();
  Future<void> stop() => video?.pause() ?? vlc?.stop() ?? media3!.pause();
  Future<void> seekTo(Duration position) =>
      video?.seekTo(position) ??
      vlc?.seekTo(position) ??
      media3!.seekTo(position);
  Future<void> setLooping(bool looping) =>
      video?.setLooping(looping) ??
      vlc?.setLooping(looping) ??
      media3!.setLooping(looping);
  Future<void> setPlaybackSpeed(double speed) =>
      video?.setPlaybackSpeed(speed) ??
      vlc?.setPlaybackSpeed(speed) ??
      media3!.setPlaybackSpeed(speed);
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0, 1).toDouble();
    await video?.setVolume(clamped);
    await vlc?.setVolume((clamped * 100).round());
    await media3?.setVolume(clamped);
  }

  Future<void> dispose() {
    final videoController = video;
    if (videoController != null) return videoController.dispose();
    final media3Controller = media3;
    if (media3Controller != null) return media3Controller.dispose();
    final vlcController = vlc!;
    try {
      if (vlcController.viewId == null) return Future<void>.value();
    } catch (_) {
      return Future<void>.value();
    }
    return vlcController.dispose();
  }
}

VideoViewType _exoVideoViewTypeFor(PlaybackSource source) {
  return source.sourceClass == PlaybackSourceClass.p2p
      ? VideoViewType.platformView
      : VideoViewType.textureView;
}

VideoFormat? _videoFormatHintFor(PlaybackSource source) {
  final type = (source.type ?? '').trim().toLowerCase();
  if (type == 'hls') return VideoFormat.hls;
  if (type == 'dash') return VideoFormat.dash;
  return null;
}

VlcHttpOptions? _vlcHttpOptions(Map<String, String> headers) {
  if (headers.isEmpty) return null;
  final options = <String>[
    VlcHttpOptions.httpReconnect(true),
    VlcHttpOptions.httpForwardCookies(true),
  ];
  for (final entry in headers.entries) {
    final key = entry.key.trim().toLowerCase();
    final value = entry.value.trim();
    if (value.isEmpty) continue;
    if (key == 'user-agent') {
      options.add(VlcHttpOptions.httpUserAgent(value));
    } else if (key == 'referer' || key == 'referrer') {
      options.add(VlcHttpOptions.httpReferrer(value));
    }
  }
  return VlcHttpOptions(options);
}

List<String> _vlcPerMediaHttpOptions(Map<String, String> headers) {
  final options = <String>[':http-reconnect', ':http-forward-cookies'];
  for (final entry in headers.entries) {
    final key = entry.key.trim().toLowerCase();
    final name = entry.key.trim();
    final value = entry.value.trim();
    if (value.isEmpty) continue;
    if (key == 'user-agent') {
      options.add(':http-user-agent=$value');
    } else if (key == 'referer' || key == 'referrer') {
      options.add(':http-referrer=$value');
    } else if (key == 'cookie') {
      options.add(':http-cookie=$value');
    } else {
      options.add(':http-header=$name: $value');
    }
  }
  return options;
}

class _LibVlcProfile {
  const _LibVlcProfile({
    required this.id,
    required this.hwAcc,
    required this.networkCachingMs,
    this.extras = const <String>[],
  });

  final String id;
  final HwAcc hwAcc;
  final int networkCachingMs;
  final List<String> extras;
}

const List<_LibVlcProfile> _libVlcProfiles = <_LibVlcProfile>[
  _LibVlcProfile(id: 'auto_hw', hwAcc: HwAcc.auto, networkCachingMs: 1800),
  _LibVlcProfile(
    id: 'software_decode',
    hwAcc: HwAcc.disabled,
    networkCachingMs: 2500,
  ),
];

VlcPlayerOptions _vlcPlayerOptions(
  Map<String, String> headers,
  _LibVlcProfile profile,
) {
  return VlcPlayerOptions(
    advanced: VlcAdvancedOptions([
      VlcAdvancedOptions.networkCaching(profile.networkCachingMs),
    ]),
    http: _vlcHttpOptions(headers),
    extras: <String>[
      ':network-caching=${profile.networkCachingMs}',
      ..._vlcPerMediaHttpOptions(headers),
      ...profile.extras,
    ],
  );
}

class _NativePlayerPageState extends State<NativePlayerPage>
    with WidgetsBindingObserver {
  static const Duration _verifiedPlaybackSourceTtl = Duration(hours: 6);
  static const Duration _shortVodPlaceholderDurationLimit = Duration(
    seconds: 75,
  );
  static const Duration _nextEpisodeTapDebounce = Duration(seconds: 3);
  static const Duration _nextEpisodeResolverBackoff = Duration(seconds: 18);
  static bool _libvlcUnavailableForAppSession = false;

  static bool hasVerifiedSourceFor(String? playbackKey) {
    if (playbackKey == null || playbackKey.isEmpty) return false;
    return AppState.verifiedPlaybackSourcesFor(playbackKey).any((cached) {
      if (_verifiedSourceIsExpired(cached)) return false;
      return cached.confidence >= 12 &&
          _verifiedSourceHasOpenableDescriptor(cached.source) &&
          _nativeSourceClassIsPlayable(cached.source);
    });
  }

  static bool _verifiedSourceIsExpired(VerifiedPlaybackSource cached) {
    return DateTime.now().difference(cached.cachedAt) >
        _verifiedPlaybackSourceTtl;
  }

  static bool _verifiedSourceHasOpenableDescriptor(PlaybackSource source) {
    if (source.sourceClass != PlaybackSourceClass.p2p) return true;
    return P2pStreamDescriptor.fromSyntheticUrl(source.url) != null;
  }

  static int _verifiedSourceAgeMinutes(VerifiedPlaybackSource cached) {
    return DateTime.now().difference(cached.cachedAt).inMinutes;
  }

  late String _title;
  late List<NativePlaybackRequest> _requests;
  late Future<List<PlaybackSource>> Function(String providerId)
  _resolveProvider;
  Future<List<PlaybackSubtitle>> Function()? _resolveSubtitles;
  late bool _enableProviderWarmup;
  late bool _limitToFirstQualityPass;
  String? _logoUrl;
  CatalogItem? _progressItem;
  String? _playbackKey;
  String? _progressSubtitle;
  String? _nextEpisodeLabel;
  Future<NativePlayerNextEpisode?> Function()? _nextEpisodeResolver;
  final StreamApi _feedbackApi = StreamApi();

  _NativePlaybackController? _controller;
  bool _loading = true;
  bool _controlsVisible = true;
  bool _locked = false;
  String? _statusMessage;
  String? _playbackWaitMessage;
  bool _playbackWaitMessagePausedPlayback = false;
  String? _gestureLabel;
  IconData? _gestureIcon;
  double _brightnessPreview = 0.5;
  double _volumePreview = 0.5;
  bool _pipSupported = false;
  bool _androidAutoPipArmed = false;
  bool _keepScreenOn = false;
  Timer? _hideControlsTimer;
  Timer? _stallWatchdogTimer;
  Timer? _openingGuardTimer;
  Timer? _deferredResumeSeekTimer;
  Timer? _playbackCadenceTimer;
  Duration _lastWatchdogPosition = Duration.zero;
  Duration _lastCadencePosition = Duration.zero;
  Duration _lastKnownPlaybackPosition = Duration.zero;
  Duration _lastKnownPlaybackDuration = Duration.zero;
  Duration _resumeProgressAnchorPosition = Duration.zero;
  int _resumeProgressAnchorLogSecond = -1;
  DateTime? _lastCadenceSampleAt;
  int _playbackCadenceSamples = 0;
  Duration? _deferredResumeSeekPosition;
  String? _deferredResumeSeekProviderId;
  int _deferredResumeSeekAttempts = 0;
  bool _deferredResumeSeekInFlight = false;
  int _stallWatchdogTicks = 0;
  int _deadPauseTicks = 0;
  int _blackVideoWatchdogTicks = 0;
  int _bufferingWatchdogTicks = 0;
  bool _recoveringFromStall = false;
  bool _openingSource = false;
  bool _userPaused = false;
  bool _playerClosing = false;
  bool _playerPopIssued = false;
  bool _allowPop = false;
  bool _nativeProvidersExhausted = false;
  int _failureCloseGeneration = 0;
  bool _libvlcUnavailableForSession = false;
  LibVlcHlsRelay? _libVlcHlsRelay;
  bool _temporaryAutoEngineRecovery = false;
  bool _temporaryAutoProviderRecovery = false;
  bool _liveTvAutoRetryAttempted = false;
  bool _resolverTemporarilyBlocked = false;
  bool _activeSourceHasZeroClockMetadata = false;
  bool _activeSourceVerifiedForSession = false;
  String? _lastVerifiedConfidenceUrl;
  int _verifiedConfidenceMilestone = 0;
  String? _lastOpenFailureMessage;
  bool _p2pIndexerSearchAttempted = false;
  bool _p2pRuntimeUnavailableForRoute = false;
  bool _p2pBridgeBufferingForRoute = false;
  bool _libVlcContinuousTsDurationAccepted = false;
  int _libVlcContinuousTsStreamedSegments = 0;
  final Map<String, PlaybackSource> _p2pLocalStreamSourcesByKey =
      <String, PlaybackSource>{};
  final Map<String, int> _p2pLocalStreamTotalBytesByUrl = <String, int>{};
  final Set<String> _coldP2pSourceKeysForRoute = <String>{};
  final Set<String> _media3NativeFallbackUrls = <String>{};
  bool _subtitlesLoadStarted = false;
  bool _skipUnsupportedHighEfficiencyForSession = false;
  int _sameSourceRecoveryAttempts = 0;
  int _hardPlaybackErrors = 0;
  DateTime? _firstControllerErrorAt;
  String? _lastControllerErrorDescription;
  int _controllerErrorGraceLogs = 0;
  final Map<String, int> _hardRecoveryAttemptsByProvider = <String, int>{};
  final Set<String> _blackVideoRecoveredUrls = <String>{};
  final Map<String, int> _failedSourceAttempts = <String, int>{};
  final Map<String, int> _routeHlsProviderOpenTimeouts = <String, int>{};
  final Map<String, int> _routeHlsQualityOpenTimeouts = <String, int>{};
  final Map<String, int> _libVlcProfileIndexByUrl = <String, int>{};
  final Set<String> _libVlcSoftVerifiedCacheUrls = <String>{};
  final Map<String, int> _pendingLibVlcOpenSuccessStartupMsByUrl =
      <String, int>{};
  final Map<String, int> _nativeSourceClassSkipCounts = <String, int>{};
  final Map<String, int> _manualLibVlcNoProofOpensByUrl = <String, int>{};
  int _manualLibVlcOpensWithoutProof = 0;
  int _lastSavedSecond = -1;
  DateTime? _nativeWallClockStartedAt;
  DateTime? _lastIntegritySampleAt;
  Duration? _lastIntegrityPosition;
  DateTime? _lastControllerUiRebuildAt;
  String? _integrityPlaybackKey;
  int _credibleWatchMilliseconds = 0;
  int _credibleWatchSecondsAtSourceOpen = 0;
  int _seekAbuseEvents = 0;
  int _providerIndex = 0;
  int _sourceIndex = 0;
  int _enginePassIndex = 0;
  int _qualityPassIndex = 0;
  int _providerRunId = 0;
  int _openingSourceToken = 0;
  List<PlaybackSource> _activeSources = const <PlaybackSource>[];
  PlaybackSource? _activeSource;
  final Map<String, Future<List<PlaybackSource>>> _providerResolveFutures =
      <String, Future<List<PlaybackSource>>>{};
  double _playbackSpeed = 1;
  double _seekStepSeconds = 15;
  List<PlaybackSubtitle> _subtitles = const <PlaybackSubtitle>[];
  PlaybackSubtitle? _activeSubtitle;
  List<_SubtitleCue> _subtitleCues = const <_SubtitleCue>[];
  String? _subtitleText;
  double _subtitleFontSize = 16;
  double _subtitleBackgroundOpacity = 0.68;
  Color _subtitleBackgroundColor = Colors.black;
  double _subtitleBackgroundRadius = 999;
  Color _subtitleTextColor = Colors.white;
  double _subtitleDelaySeconds = 0;
  bool _subtitleDelayCustomized = false;
  double _subtitleBottomOffset = 30;
  String? _preferredQuality;
  String _qualityPreferenceMode = 'recommended';
  bool _usingGlobalOverrides = false;
  String? _preferredSubtitleId;
  VideoFitMode _fitMode = VideoFitMode.fit;
  bool _settingsExpanded = false;
  bool _settingsPausedPlayback = false;
  bool _optionSheetOpen = false;
  bool _exitConfirmationOpen = false;
  bool _resumeDialogOpen = false;
  bool _resumeDialogAcceptedAwaitingProof = false;
  bool _pictureInPictureActive = false;
  bool _systemPipHandoffActive = false;
  bool _restoringFromExternalRoute = false;
  bool _shouldRestoreOnResume = false;
  bool _restoreShouldResumePlayback = false;
  Duration _restoreResumePosition = Duration.zero;
  bool _resumePromptHandled = false;
  bool _resumePromptAccepted = false;
  bool _autoNextEpisodeStarted = false;
  bool _completionCloseStarted = false;
  bool _hasRestoredNativePreferences = false;
  bool _nextEpisodeOpening = false;
  DateTime? _lastNextEpisodeTapAt;
  DateTime? _resolverBackoffUntil;
  late final int _progressGeneration;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _resolveProvider = widget.resolveProvider;
    _resolveSubtitles = widget.resolveSubtitles;
    _enableProviderWarmup = widget.enableProviderWarmup;
    _limitToFirstQualityPass = widget.limitToFirstQualityPass;
    _logoUrl = widget.logoUrl;
    _progressItem = widget.progressItem;
    _playbackKey = widget.playbackKey;
    _requests = _requestsWithVerifiedSource(widget.sources);
    _progressSubtitle = widget.progressSubtitle;
    _nextEpisodeLabel = widget.nextEpisodeLabel;
    _nextEpisodeResolver = widget.onNextEpisode;
    WidgetsBinding.instance.addObserver(this);
    _progressGeneration = AppState.continueWatchingGeneration;
    _guardManualLibVlcAfterInterruptedSessionIfNeeded();
    _restoreNativePreferences();
    _restoreNativeSurfaceLevels();
    _enterPlayerMode();
    _pipChannel.setMethodCallHandler(_handlePipChannelCall);
    _loadPipSupport();
    unawaited(NativeMediaBridge.loadCapabilities());
    _openNextAvailableSource();
  }

  void _guardManualLibVlcAfterInterruptedSessionIfNeeded() {
    final settings = AppState.playerBehaviorSettings.value;
    if (settings.playbackEngine != 'libvlc' ||
        !_libVlcCrashGuardActiveForManualRoute) {
      return;
    }
    DiagnosticLog.add(
      'native libvlc selection guarded reason=previous_native_engine_interrupted saved=preserved effective=exoplayer',
    );
  }

  @override
  void dispose() {
    _playerClosing = true;
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _stallWatchdogTimer?.cancel();
    _openingGuardTimer?.cancel();
    _cancelDeferredResumeSeek();
    _pipChannel.setMethodCallHandler(null);
    final controller = _controller;
    if (controller != null) {
      _trackLastKnownPlaybackPosition();
      _saveNativeProgress(force: true);
    }
    _controller = null;
    controller?.removeListener(_handleControllerUpdate);
    unawaited(_stopLibVlcHlsRelay('dispose'));
    if (controller?.isInitialized == true) {
      final activeController = controller!;
      if (activeController.engine == _NativePlaybackEngine.libvlc) {
        unawaited(
          activeController
              .stop()
              .timeout(const Duration(milliseconds: 700))
              .catchError((_) {}),
        );
      } else {
        unawaited(activeController.pause().catchError((_) {}));
      }
    } else if (controller != null) {
      DiagnosticLog.add(
        'native dispose skipped pause engine=${controller.engine.id} reason=controller_not_initialized',
      );
    }
    unawaited(controller?.dispose() ?? Future<void>.value());
    unawaited(_stopP2pBridgeForPolicy('dispose'));
    unawaited(_setKeepScreenOn(false));
    unawaited(_setAndroidAutoPipOnUserLeave(false));
    final feedbackApi = _feedbackApi;
    unawaited(
      Future<void>.delayed(const Duration(seconds: 5), feedbackApi.close),
    );
    _exitPlayerMode();
    super.dispose();
  }

  List<NativePlaybackRequest> _requestsWithVerifiedSource(
    List<NativePlaybackRequest> requests, {
    String? playbackKey,
  }) {
    final key = playbackKey ?? _playbackKey;
    if (key == null || key.isEmpty) return requests;

    final cachedSources = AppState.verifiedPlaybackSourcesFor(key);
    if (cachedSources.isEmpty) return requests;
    final strictLibVlc = _effectivePlaybackEngine == 'libvlc';
    final requestProviderIds = requests
        .map((request) => request.providerId)
        .where((providerId) => providerId.isNotEmpty)
        .toSet();
    final promoted = <NativePlaybackRequest>[];
    final fallback = <NativePlaybackRequest>[];
    for (final cached in cachedSources) {
      if (requestProviderIds.isNotEmpty &&
          !requestProviderIds.contains(cached.source.providerId)) {
        DiagnosticLog.add(
          'native verified source cache skipped key=[redacted] provider=${cached.source.providerId} sourceClass=${cached.source.sourceClass.wireName} reason=provider_not_in_current_route url=[hidden]',
        );
        continue;
      }
      final request = NativePlaybackRequest(
        providerId: cached.source.providerId,
        sources: <PlaybackSource>[cached.source],
      );
      final stale = _verifiedSourceIsExpired(cached);
      final status = AppState.nativeProviderHealthFor(cached.source.providerId);
      final providerOffline = status == NativeProviderHealthStatus.failing;
      final nativeSupportedSourceClass = _nativePlaybackSupportsSourceClass(
        cached.source,
      );
      final hasOpenableDescriptor = _verifiedSourceHasOpenableDescriptor(
        cached.source,
      );
      DiagnosticLog.add(
        'native verified source cache candidate key=[redacted] provider=${cached.source.providerId} sourceClass=${cached.source.sourceClass.wireName} quality=${cached.source.quality ?? 'auto'} engine=${cached.engineId} confidence=${cached.confidence} success=${cached.successCount} failures=${cached.failureCount} stale=$stale sourceClassNative=$nativeSupportedSourceClass descriptorOpenable=$hasOpenableDescriptor providerStatus=${status.name} age=${_verifiedSourceAgeMinutes(cached)}m',
      );
      if (stale ||
          !nativeSupportedSourceClass ||
          !hasOpenableDescriptor ||
          providerOffline) {
        final reason = stale
            ? 'stale'
            : !nativeSupportedSourceClass
            ? 'source_class_not_native'
            : !hasOpenableDescriptor
            ? 'descriptor_missing'
            : 'provider_offline';
        DiagnosticLog.add(
          'native verified source cache skipped key=[redacted] provider=${cached.source.providerId} sourceClass=${cached.source.sourceClass.wireName} reason=$reason url=[hidden]',
        );
        if (!hasOpenableDescriptor) {
          AppState.recordVerifiedPlaybackSourceFailure(
            key: key,
            sourceUrl: cached.source.url,
            reason: reason,
          );
        }
        continue;
      }
      if (strictLibVlc && cached.engineId != _NativePlaybackEngine.libvlc.id) {
        _libVlcSoftVerifiedCacheUrls.add(cached.source.url);
        DiagnosticLog.add(
          'native verified source cache soft-promoted key=[redacted] provider=${cached.source.providerId} sourceClass=${cached.source.sourceClass.wireName} reason=engine_mismatch_manual_libvlc_soft_try cachedEngine=${cached.engineId} url=[hidden]',
        );
        promoted.add(request);
        continue;
      }
      final p2pWarmCache =
          cached.source.sourceClass == PlaybackSourceClass.p2p &&
          cached.successCount >= 1 &&
          cached.confidence >= 8 &&
          cached.engineId != _NativePlaybackEngine.libvlc.id;
      if (!stale &&
          nativeSupportedSourceClass &&
          !providerOffline &&
          (cached.confidence >= 12 || p2pWarmCache) &&
          cached.engineId != _NativePlaybackEngine.libvlc.id) {
        promoted.add(request);
      } else {
        fallback.add(request);
      }
    }
    if (promoted.isEmpty && fallback.isEmpty) return requests;
    return <NativePlaybackRequest>[...promoted, ...requests, ...fallback];
  }

  void _rememberVerifiedSource(
    _NativePlaybackController controller,
    Duration position,
  ) {
    final key = _playbackKey;
    final source = _activeSource;
    if (key == null || key.isEmpty || source == null || source.url.isEmpty) {
      return;
    }
    final publicIptvSource = _isPublicIptvSource(source);
    final minimumPosition = publicIptvSource
        ? const Duration(seconds: 6)
        : const Duration(seconds: 15);
    if (position < minimumPosition) return;
    if (!_nativePlaybackSupportsSourceClass(source)) return;
    if (!_verifiedSourceHasOpenableDescriptor(source)) return;
    final milestone = position >= const Duration(minutes: 2) ? 2 : 1;
    if (_lastVerifiedConfidenceUrl == source.url &&
        _verifiedConfidenceMilestone >= milestone) {
      return;
    }
    if (!controller.isInitialized ||
        controller.hasError ||
        controller.duration <= Duration.zero ||
        controller.size == Size.zero ||
        _activeSourceHasZeroClockMetadata) {
      return;
    }
    if (_sourceLooksLikeShortVodPlaceholder(source, controller)) {
      DiagnosticLog.add(
        'native verified source skipped key=[redacted] provider=${source.providerId} sourceClass=${source.sourceClass.wireName} quality=${source.quality ?? 'auto'} reason=short_vod_placeholder duration=${controller.duration.inSeconds}s engine=${controller.engine.id} url=[hidden]',
      );
      _forgetVerifiedSource(source, 'short_vod_placeholder');
      return;
    }
    final proofMinimum = _verifiedSourcePlaybackProofMinimum(
      source,
      publicIptvSource: publicIptvSource,
    );
    if (_sourceCredibleWatchSeconds < proofMinimum.inSeconds) {
      DiagnosticLog.add(
        'native verified source skipped key=[redacted] provider=${source.providerId} sourceClass=${source.sourceClass.wireName} quality=${source.quality ?? 'auto'} reason=insufficient_playback_proof sourceWatch=${_sourceCredibleWatchSeconds}s required=${proofMinimum.inSeconds}s position=${position.inSeconds}s engine=${controller.engine.id} url=[hidden]',
      );
      return;
    }

    AppState.rememberVerifiedPlaybackSource(
      key: key,
      source: source,
      engineId: controller.engine.id,
      cachedAt: DateTime.now(),
      confidenceDelta: milestone == 2 || publicIptvSource ? 18 : 10,
    );
    _activeSourceVerifiedForSession = true;
    _lastVerifiedConfidenceUrl = source.url;
    _verifiedConfidenceMilestone = milestone;
    DiagnosticLog.add(
      'native verified source cached key=[redacted] provider=${source.providerId} sourceClass=${source.sourceClass.wireName} quality=${source.quality ?? 'auto'} engine=${controller.engine.id} ttl=${_verifiedPlaybackSourceTtl.inMinutes}m url=[hidden]',
    );
    _sendPlaybackFeedback('verified', source: source, controller: controller);
  }

  void _forgetVerifiedSource(PlaybackSource source, String reason) {
    final key = _playbackKey;
    if (key == null || key.isEmpty) return;
    VerifiedPlaybackSource? cached;
    for (final entry in AppState.verifiedPlaybackSourcesFor(key)) {
      if (entry.source.url == source.url) {
        cached = entry;
        break;
      }
    }
    if (cached == null) return;

    AppState.recordVerifiedPlaybackSourceFailure(
      key: key,
      sourceUrl: source.url,
      reason: reason,
    );
    _activeSourceVerifiedForSession = false;
    DiagnosticLog.add(
      'native verified source cache penalized key=[redacted] provider=${source.providerId} sourceClass=${source.sourceClass.wireName} reason=$reason confidence=${cached.confidence} url=[hidden]',
    );
  }

  bool _isLibVlcSoftVerifiedCacheSource(
    PlaybackSource source,
    _NativePlaybackEngine? engine,
  ) {
    return engine == _NativePlaybackEngine.libvlc &&
        _libVlcSoftVerifiedCacheUrls.contains(source.url);
  }

  int get _sourceCredibleWatchSeconds {
    return math.max(
      0,
      _credibleWatchSeconds - _credibleWatchSecondsAtSourceOpen,
    );
  }

  bool _sourceHasVisualPlaybackProof(_NativePlaybackController? controller) {
    final source = _activeSource;
    if (source == null || controller == null) return false;
    if (!controller.isInitialized ||
        controller.hasError ||
        controller.duration <= Duration.zero ||
        controller.size == Size.zero ||
        _activeSourceHasZeroClockMetadata) {
      return false;
    }
    if (!_nativePlaybackSupportsSourceClass(source)) return false;
    final publicIptvSource = _isPublicIptvSource(source);
    final proofMinimum = _verifiedSourcePlaybackProofMinimum(
      source,
      publicIptvSource: publicIptvSource,
    );
    return _sourceCredibleWatchSeconds >= proofMinimum.inSeconds;
  }

  Duration _verifiedSourcePlaybackProofMinimum(
    PlaybackSource source, {
    required bool publicIptvSource,
  }) {
    if (publicIptvSource) return Duration.zero;
    if (source.sourceClass == PlaybackSourceClass.p2p) {
      return const Duration(seconds: 12);
    }
    return const Duration(seconds: 6);
  }

  void _markRuntimeSourceFailure(PlaybackSource source, String reason) {
    if (source.url.isEmpty) return;
    _pendingLibVlcOpenSuccessStartupMsByUrl.remove(source.url);
    _failedSourceAttempts[source.url] =
        (_failedSourceAttempts[source.url] ?? 0) + 1;
    final attempts = _failedSourceAttempts[source.url] ?? 0;
    if (!_isLibVlcSoftVerifiedCacheSource(source, _controller?.engine)) {
      _forgetVerifiedSource(source, reason);
    }
    DiagnosticLog.add(
      'native source runtime failed provider=${source.providerId} '
      'quality=${source.quality ?? 'auto'} attempts=$attempts reason=$reason',
    );
  }

  void _recordNativeOpenSuccess(
    PlaybackSource source,
    _NativePlaybackController controller, {
    required _NativePlaybackEngine engine,
    required int startupMs,
    required String reason,
  }) {
    AppState.recordNativeProviderSuccess(
      mediaKey: _playbackKey,
      providerId: source.providerId,
      sourceCount: _activeSources.isEmpty
          ? null
          : visiblePlaybackSourceCount(_activeSources),
    );
    _sendPlaybackFeedback(
      'open_success',
      source: source,
      controller: controller,
      engine: engine,
      startupMs: startupMs,
    );
    if (engine == _NativePlaybackEngine.libvlc) {
      _pendingLibVlcOpenSuccessStartupMsByUrl.remove(source.url);
      _manualLibVlcNoProofOpensByUrl.clear();
      _manualLibVlcOpensWithoutProof = 0;
      DiagnosticLog.add(
        'native libvlc open success accepted provider=${source.providerId} reason=$reason position=${controller.position.inSeconds}s size=${controller.size.width.toStringAsFixed(0)}x${controller.size.height.toStringAsFixed(0)}',
      );
      if (_resumeDialogAcceptedAwaitingProof && mounted) {
        _hideControlsTimer?.cancel();
        setState(() {
          _resumeDialogAcceptedAwaitingProof = false;
          _playbackWaitMessage = null;
          _playbackWaitMessagePausedPlayback = false;
          _controlsVisible = true;
        });
        _scheduleControlsHide();
      } else {
        _resumeDialogAcceptedAwaitingProof = false;
      }
    }
  }

  bool _hasLibVlcVisualPlaybackProof(_NativePlaybackController controller) {
    if (controller.engine != _NativePlaybackEngine.libvlc) return false;
    if (!controller.isInitialized || controller.hasError) return false;
    if (_hasLibVlcContinuousTsPlaybackProof(controller)) return true;
    if (controller.size == Size.zero) return false;
    if (_activeSourceHasZeroClockMetadata) return false;
    return controller.position >= const Duration(seconds: 1);
  }

  bool _hasLibVlcContinuousTsPlaybackProof(
    _NativePlaybackController controller, {
    bool allowZeroVisualMetadataProof = false,
  }) {
    if (controller.engine != _NativePlaybackEngine.libvlc) return false;
    if (!_libVlcContinuousTsActive) return false;
    if (!controller.isInitialized || controller.hasError) return false;
    if (!controller.isPlaying) return false;
    final relayPlaybackProofReady =
        _libVlcContinuousTsRelayProofReady ||
        controller.duration > Duration.zero;
    if (_activeSourceHasZeroClockMetadata && controller.size == Size.zero) {
      if (allowZeroVisualMetadataProof &&
          relayPlaybackProofReady &&
          _lastSavedSecond >= 8) {
        return true;
      }
      if (_lastSavedSecond >= 8 && _lastSavedSecond % 15 == 0) {
        DiagnosticLog.add(
          'native libvlc continuous-ts proof waiting reason=zero_visual_metadata watched=${_lastSavedSecond}s streamed=${_countDiagnosticBucket(_libVlcContinuousTsStreamedSegments)}',
        );
      }
      return false;
    }
    return _lastSavedSecond >= 8;
  }

  bool _libVlcContinuousTsPlaybackActive(
    _NativePlaybackController? controller,
  ) {
    if (controller == null) return false;
    return _hasLibVlcContinuousTsPlaybackProof(
      controller,
      allowZeroVisualMetadataProof: true,
    );
  }

  void _maybeRecordDeferredLibVlcOpenSuccess(
    _NativePlaybackController controller, {
    required String reason,
  }) {
    final source = _activeSource;
    if (source == null || source.url.isEmpty) return;
    final startupMs = _pendingLibVlcOpenSuccessStartupMsByUrl[source.url];
    if (startupMs == null) return;
    if (!_hasLibVlcVisualPlaybackProof(controller)) return;
    _recordNativeOpenSuccess(
      source,
      controller,
      engine: _NativePlaybackEngine.libvlc,
      startupMs: startupMs,
      reason: reason,
    );
  }

  void _sendPlaybackFeedback(
    String event, {
    PlaybackSource? source,
    _NativePlaybackController? controller,
    _NativePlaybackEngine? engine,
    int? startupMs,
  }) {
    if (_playerClosing && event != 'closed') {
      DiagnosticLog.add(
        'playback feedback skipped event=$event reason=player_closing',
      );
      return;
    }
    final playbackSource = source ?? _activeSource;
    if (playbackSource == null || playbackSource.providerId.trim().isEmpty) {
      return;
    }
    final activeController = controller ?? _controller;
    final position = activeController?.position ?? _lastKnownPlaybackPosition;
    final duration = activeController?.duration ?? _lastKnownPlaybackDuration;
    unawaited(
      _feedbackApi.sendPlaybackFeedback(
        providerId: playbackSource.providerId,
        event: event,
        engine: engine?.id ?? activeController?.engine.id ?? 'unknown',
        mediaType: _progressItem?.type.compatTypeValue ?? 'unknown',
        quality: playbackSource.quality ?? 'auto',
        sourceType: playbackSource.type ?? 'unknown',
        sourceClass: playbackSource.sourceClass.wireName,
        positionSeconds: position.inSeconds,
        durationSeconds: duration.inSeconds,
        startupMs: startupMs,
        sourceCount: _activeSources.isEmpty
            ? null
            : visiblePlaybackSourceCount(_activeSources),
      ),
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    DiagnosticLog.add(
      'native player reassemble; stopping controller for hot restart',
    );
    if (_pictureInPictureActive) {
      DiagnosticLog.add(
        'native player reassemble during system PiP; finishing app for hot restart',
      );
      unawaited(
        _pipChannel
            .invokeMethod<bool>('finishForHotRestart')
            .catchError((_) => false),
      );
    }
    unawaited(
      _disposeCurrentController(updateUi: false, awaitLibVlcRelease: true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pictureInPictureActive) {
        _pictureInPictureActive = false;
        _systemPipHandoffActive = false;
        if (mounted) {
          setState(() {
            _optionSheetOpen = false;
          });
        }
      }
      if (_shouldRestoreOnResume) {
        _shouldRestoreOnResume = false;
        unawaited(_restorePlaybackAfterExternalRoute());
      }
      _syncKeepScreenOn();
      return;
    }
    if (state == AppLifecycleState.inactive) {
      if (_pictureInPictureActive && state != AppLifecycleState.detached) {
        DiagnosticLog.add(
          'native player lifecycle=$state during PiP; keeping playback alive',
        );
        return;
      }
      if (_shouldAutoEnterPipForLifecycle()) {
        DiagnosticLog.add(
          'native player lifecycle=$state; entering background PiP',
        );
        unawaited(_enterPictureInPicture(showFailureMessage: false));
        return;
      }
      DiagnosticLog.add(
        'native player lifecycle=$state; waiting for paused/detached before cleanup',
      );
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_pictureInPictureActive && state != AppLifecycleState.detached) {
        DiagnosticLog.add(
          'native player lifecycle=$state during PiP; keeping playback alive',
        );
        return;
      }
      if (state != AppLifecycleState.detached &&
          _shouldAutoEnterPipForLifecycle()) {
        DiagnosticLog.add(
          'native player lifecycle=$state; entering background PiP fallback',
        );
        unawaited(_enterPictureInPicture(showFailureMessage: false));
        return;
      }
      final controller = _controller;
      final canRestoreGenericPlayback =
          !_restoringFromExternalRoute &&
          state != AppLifecycleState.detached &&
          _activeSource != null &&
          controller != null &&
          controller.isInitialized;
      if (canRestoreGenericPlayback) {
        _restoreShouldResumePlayback = !_userPaused && controller.isPlaying;
        _restoreResumePosition = controller.position;
        _shouldRestoreOnResume = true;
      }
      DiagnosticLog.add('native player lifecycle=$state; stopping playback');
      unawaited(_setKeepScreenOn(false));
      if (_restoringFromExternalRoute) {
        _shouldRestoreOnResume = true;
      }
      unawaited(
        _disposeCurrentController(updateUi: false, awaitLibVlcRelease: true),
      );
      if (_batteryDataSettings.pauseP2pWhenBackgrounded) {
        unawaited(_stopP2pBridgeForPolicy('background'));
      }
    }
  }

  Future<void> _setAndroidAutoPipOnUserLeave(bool enabled) async {
    if (!_pipSupported) {
      _androidAutoPipArmed = false;
      return;
    }
    if (_androidAutoPipArmed == enabled) return;
    try {
      await _pipChannel.invokeMethod<void>('setAutoEnterOnUserLeave', {
        'enabled': enabled,
        'playing': _controller?.isPlaying == true,
        'seekSeconds': _seekStepSeconds.round(),
        'liveMode': _isLiveTvMode,
      });
      _androidAutoPipArmed = enabled;
      DiagnosticLog.add(
        'native android auto PiP on user leave ${enabled ? 'armed' : 'disarmed'}',
      );
    } catch (error) {
      DiagnosticLog.add(
        'native android auto PiP arm failed error=${_safeDiagnosticError(error)}',
      );
    }
  }

  void _syncKeepScreenOn() {
    final shouldKeepOn =
        !_playerClosing &&
        !_pictureInPictureActive &&
        !_systemPipHandoffActive &&
        _controller?.isPlaying == true;
    unawaited(_syncAndroidAutoPipOnUserLeave());
    if (shouldKeepOn == _keepScreenOn) return;
    unawaited(_setKeepScreenOn(shouldKeepOn));
  }

  Future<void> _syncAndroidAutoPipOnUserLeave() async {
    await _setAndroidAutoPipOnUserLeave(_shouldAutoEnterPipForLifecycle());
  }

  Future<void> _setKeepScreenOn(bool enabled) async {
    if (_keepScreenOn == enabled) return;
    _keepScreenOn = enabled;
    try {
      await _displayChannel.invokeMethod<void>('setKeepScreenOn', {
        'enabled': enabled,
      });
      DiagnosticLog.add(
        'native keep screen on ${enabled ? 'enabled' : 'disabled'}',
      );
    } catch (error) {
      DiagnosticLog.add(
        'native keep screen on failed error=${_safeDiagnosticError(error)}',
      );
    }
  }

  bool _shouldAutoEnterPipForLifecycle() {
    return AppState.playerBehaviorSettings.value.pipOnBackground &&
        _playerReadyForSystemPictureInPicture();
  }

  Future<void> _enterPlayerMode() async {
    beginJuicrImmersiveSession();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitPlayerMode() async {
    await _setKeepScreenOn(false);
    await _displayChannel
        .invokeMethod<void>('resetBrightness')
        .catchError((_) {});
    endJuicrImmersiveSession();
    await restoreJuicrSystemUi(force: true);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _openNextAvailableSource() async {
    final runId = ++_providerRunId;
    final enginePasses = _enginePassesForCurrentSettings();
    DiagnosticLog.add(
      'native engine ladder configured=${AppState.playerBehaviorSettings.value.playbackEngine} '
      'effective=$_effectivePlaybackEngine passes=${enginePasses.map((engine) => engine.id).join('>')} '
      'reason=${_enginePassDecisionReason()}',
    );
    if (_requests.isEmpty) {
      DiagnosticLog.add('native page opened with no provider requests');
      _lastOpenFailureMessage =
          'Video is currently unavailable. Please try again later.';
      await _finishWithNoWorkingSource();
      return;
    }

    _nativeProvidersExhausted = false;
    _nativeSourceClassSkipCounts.clear();
    _p2pRuntimeUnavailableForRoute = false;
    _p2pBridgeBufferingForRoute = false;
    _coldP2pSourceKeysForRoute.clear();
    while (mounted &&
        runId == _providerRunId &&
        _enginePassIndex < enginePasses.length) {
      final engine = enginePasses[_enginePassIndex];
      if (engine == _NativePlaybackEngine.libvlc &&
          _libvlcUnavailableForCurrentPass) {
        DiagnosticLog.add(
          'native engine pass skipped engine=${engine.id} reason=unavailable',
        );
        _enginePassIndex += 1;
        _qualityPassIndex = 0;
        _providerIndex = 0;
        _sourceIndex = 0;
        continue;
      }
      if (_providerIndex == 0 && _sourceIndex == 0) {
        DiagnosticLog.add(
          'native engine pass start engine=${engine.id} pass=${_enginePassIndex + 1}/${enginePasses.length}',
        );
      }
      final qualityPasses = _qualityPassesForCurrentAttempt();
      if (_limitToFirstQualityPass &&
          !_qualityModeNeedsOrderedFallbackPasses &&
          _providerIndex == 0 &&
          _sourceIndex == 0 &&
          _qualityPassIndex == 0) {
        DiagnosticLog.add(
          'native cold provider scan using single quality pass reason=capped',
        );
      }
      while (mounted &&
          runId == _providerRunId &&
          _qualityPassIndex < qualityPasses.length) {
        final qualityPass = qualityPasses[_qualityPassIndex];
        var foundAnyProviderSourcesForPass = false;
        if (_providerIndex == 0 && _sourceIndex == 0) {
          DiagnosticLog.add(
            'native quality pass start label=${qualityPass.label} pass=${_qualityPassIndex + 1}/${qualityPasses.length} ${_qualityDiagnosticContext(qualityPass)}',
          );
        }
        while (mounted &&
            runId == _providerRunId &&
            _providerIndex < _requests.length) {
          final request = _requests[_providerIndex];
          var providerSources = await _expandQualitySources(request.sources);
          if (!mounted || runId != _providerRunId) return;

          if (_sourceIndex == 0 && providerSources.isEmpty) {
            final status = _resolveStatusFor(request.providerId);
            _logPlaybackStatus(status, reason: 'resolve_provider');
            setState(() {
              _loading = true;
              _statusMessage = status;
            });
            DiagnosticLog.add(
              'native page resolving provider=${request.providerId} providerIndex=$_providerIndex',
            );
            _warmNextProviderResolve();
            try {
              providerSources = await _expandQualitySources(
                await _resolveProviderSources(request.providerId),
              );
            } catch (error) {
              DiagnosticLog.add(
                'native page provider resolve failed provider=${request.providerId} error=${_safeDiagnosticError(error)}',
              );
              if (_isTemporaryResolverBlock(error)) {
                DiagnosticLog.add(
                  'native page stopping provider scan reason=playback_service_temporary_block provider=${request.providerId}',
                );
                AppState.recordNativeProviderFailure(
                  mediaKey: _playbackKey,
                  providerId: request.providerId,
                  status: NativeProviderHealthStatus.protected,
                  sourceCount: request.sources.length,
                  updateHealth: _shouldUpdateProviderHealthFromPlaybackFailure,
                );
                if (await _pauseProviderScanForResolverBlock()) {
                  return;
                }
                _resolverTemporarilyBlocked = true;
                await _finishWithNoWorkingSource();
                return;
              }
              AppState.recordNativeProviderFailure(
                mediaKey: _playbackKey,
                providerId: request.providerId,
                updateHealth: _shouldUpdateProviderHealthFromPlaybackFailure,
              );
              _providerIndex += 1;
              _sourceIndex = 0;
              continue;
            }
            if (!mounted || runId != _providerRunId) return;
          }

          if (providerSources.isEmpty) {
            DiagnosticLog.add(
              'native page provider=${request.providerId} has no sources providerIndex=$_providerIndex',
            );
            AppState.recordNativeProviderFailure(
              mediaKey: _playbackKey,
              providerId: request.providerId,
              status: NativeProviderHealthStatus.noSource,
              sourceCount: 0,
              updateHealth: _shouldUpdateProviderHealthFromPlaybackFailure,
            );
            _providerIndex += 1;
            _sourceIndex = 0;
            continue;
          }

          foundAnyProviderSourcesForPass = true;
          final sourceIndexRemapCandidate =
              _sourceIndex > 0 &&
                  _sourceIndex < _activeSources.length &&
                  _activeSources[_sourceIndex].providerId == request.providerId
              ? _activeSources[_sourceIndex]
              : null;
          providerSources = _prepareProviderSourcesForPlaybackPass(
            providerSources,
            qualityPass: qualityPass,
            engine: engine,
            enginePasses: enginePasses,
          );
          if (providerSources.isEmpty) {
            DiagnosticLog.add(
              'native page provider=${request.providerId} has no sources for qualityPass=${qualityPass.label} providerIndex=$_providerIndex ${_qualityDiagnosticContext(qualityPass)}',
            );
            _providerIndex += 1;
            _sourceIndex = 0;
            continue;
          }
          if (sourceIndexRemapCandidate != null &&
              sourceIndexRemapCandidate.providerId == request.providerId) {
            final remappedSourceIndex = providerSources.indexWhere(
              (source) => source.url == sourceIndexRemapCandidate.url,
            );
            if (remappedSourceIndex >= 0 &&
                remappedSourceIndex != _sourceIndex) {
              DiagnosticLog.add(
                'native source index remapped provider=${request.providerId} from=$_sourceIndex to=$remappedSourceIndex reason=source_index_remapped_after_ladder',
              );
              _sourceIndex = remappedSourceIndex;
            }
          }
          _activeSources = providerSources;
          if (mounted) {
            final status = _providerReadyStatusFor(
              request.providerId,
              providerSources,
            );
            _logPlaybackStatus(status, reason: 'provider_ready');
            setState(() {
              _statusMessage = status;
            });
          }
          DiagnosticLog.add(
            'native page provider ready provider=${request.providerId} providerIndex=$_providerIndex sourceCount=${providerSources.length} ${_qualityDiagnosticContext(qualityPass)}',
          );
          while (mounted &&
              runId == _providerRunId &&
              _sourceIndex < providerSources.length) {
            final source = providerSources[_sourceIndex];
            if (!_nativePlaybackSupportsSourceClass(source)) {
              _recordNativeSourceClassSkip(source);
              DiagnosticLog.add(
                'native source skipped provider=${source.providerId} sourceClass=${source.sourceClass.wireName} providerIndex=$_providerIndex sourceIndex=$_sourceIndex reason=source_class_not_native',
              );
              _sourceIndex += 1;
              continue;
            }
            if (engine == _NativePlaybackEngine.libvlc &&
                _libvlcUnavailableForCurrentPass) {
              DiagnosticLog.add(
                'native provider skipped provider=${request.providerId} engine=${engine.id} reason=unavailable',
              );
              _sourceIndex = providerSources.length;
              continue;
            }
            if (_shouldSkipSourceForSession(source, engine)) {
              DiagnosticLog.add(
                'native source skipped provider=${source.providerId} providerIndex=$_providerIndex sourceIndex=$_sourceIndex reason=session unsupported codec quality=${source.quality ?? 'auto'}',
              );
              _sourceIndex += 1;
              continue;
            }
            if (_shouldSkipP2pSourceForEngine(source, engine)) {
              DiagnosticLog.add(
                'native source skipped provider=${source.providerId} sourceClass=p2p providerIndex=$_providerIndex sourceIndex=$_sourceIndex engine=${engine.id} reason=p2p_exoplayer_high_risk_codec quality=${source.quality ?? 'auto'}',
              );
              _sourceIndex += 1;
              continue;
            }
            if (_shouldSkipColdP2pSourceForRoute(source)) {
              DiagnosticLog.add(
                'native source skipped provider=${source.providerId} sourceClass=p2p providerIndex=$_providerIndex sourceIndex=$_sourceIndex reason=route_cold_p2p_candidate quality=${source.quality ?? 'auto'}',
              );
              _sourceIndex += 1;
              continue;
            }
            if (_shouldSkipSourceAfterRouteOpenTimeouts(source, engine)) {
              _sourceIndex += 1;
              continue;
            }
            DiagnosticLog.add(
              'native source attempt provider=${source.providerId} sourceClass=${source.sourceClass.wireName} providerIndex=$_providerIndex sourceIndex=$_sourceIndex quality=${source.quality ?? 'auto'} engine=${engine.id} ${_qualityDiagnosticContext(qualityPass)} profile=${_sourceDiagnosticProfile(source)}',
            );
            final nativeReadable = await _isNativeReadableSource(
              source,
              engine: engine,
            );
            if (!mounted || runId != _providerRunId) return;
            if (!nativeReadable) {
              DiagnosticLog.add(
                'native source unreadable provider=${source.providerId} providerIndex=$_providerIndex sourceIndex=$_sourceIndex',
              );
              _forgetVerifiedSource(source, 'unreadable');
              _recordNativeProviderFailureForSource(
                source,
                sourceCount: visiblePlaybackSourceCount(providerSources),
              );
              _sourceIndex += 1;
              continue;
            }
            final status = _checkingSourceStatusFor(_sourceIndex);
            _logPlaybackStatus(status, reason: 'source_attempt');
            final opened = await _openSource(
              source,
              statusMessage: status,
              engineOverride: engine,
            );
            if (!mounted || runId != _providerRunId) return;
            if (opened) return;
            DiagnosticLog.add(
              'native source failed provider=${source.providerId} providerIndex=$_providerIndex sourceIndex=$_sourceIndex',
            );
            if (source.sourceClass == PlaybackSourceClass.p2p &&
                (_p2pRuntimeUnavailableForRoute ||
                    _p2pBridgeBufferingForRoute)) {
              DiagnosticLog.add(
                'native p2p source loop stopped provider=${source.providerId} reason=${_p2pRuntimeUnavailableForRoute ? 'runtime_unavailable' : 'local_stream_not_ready'}',
              );
              _sourceIndex = providerSources.length;
              break;
            }
            if (source.sourceClass == PlaybackSourceClass.p2p &&
                engine == _NativePlaybackEngine.exoplayer &&
                enginePasses.contains(_NativePlaybackEngine.libvlc)) {
              DiagnosticLog.add(
                'native p2p exoplayer source failed provider=${source.providerId} action=try_next_exoplayer_source',
              );
            }
            if (engine == _NativePlaybackEngine.libvlc &&
                _libvlcUnavailableForCurrentPass &&
                _effectivePlaybackEngine == 'auto') {
              final status =
                  '${_engineLabel(engine)} exhausted. Switching to Auto temporarily...';
              DiagnosticLog.add(
                'native ${engine.id} exhausted; switching to auto temporarily',
              );
              _logPlaybackStatus(status, reason: 'engine_temporary_auto');
              if (mounted) {
                setState(() {
                  _loading = true;
                  _controlsVisible = true;
                  _statusMessage = status;
                });
              }
              await Future<void>.delayed(const Duration(milliseconds: 900));
              if (!mounted || runId != _providerRunId) return;
              _enginePassIndex = 0;
              _qualityPassIndex = 0;
              _providerIndex = 0;
              _sourceIndex = 0;
              _failedSourceAttempts.clear();
              await _openNextAvailableSource();
              return;
            }
            _recordNativeProviderFailureForSource(
              source,
              sourceCount: visiblePlaybackSourceCount(providerSources),
            );
            _sourceIndex += 1;
            if (engine == _NativePlaybackEngine.libvlc &&
                _libvlcUnavailableForCurrentPass) {
              break;
            }
          }

          if (engine == _NativePlaybackEngine.libvlc &&
              _libvlcUnavailableForCurrentPass) {
            break;
          }
          DiagnosticLog.add(
            'native page provider exhausted provider=${request.providerId} providerIndex=$_providerIndex',
          );
          _providerIndex += 1;
          _sourceIndex = 0;
          if (_providerIndex < _requests.length && mounted) {
            final status = _resolveStatusFor(
              _requests[_providerIndex].providerId,
            );
            _logPlaybackStatus(status, reason: 'provider_exhausted');
            setState(() {
              _loading = true;
              _controlsVisible = true;
              _statusMessage = status;
            });
          }
        }

        if (engine == _NativePlaybackEngine.libvlc &&
            _libvlcUnavailableForCurrentPass) {
          break;
        }
        if (!foundAnyProviderSourcesForPass) {
          DiagnosticLog.add(
            'native quality pass stopping early label=${qualityPass.label} reason=no_provider_sources',
          );
          _qualityPassIndex = qualityPasses.length;
          break;
        }
        DiagnosticLog.add(
          'native quality pass exhausted label=${qualityPass.label} pass=${_qualityPassIndex + 1}/${qualityPasses.length} ${_qualityDiagnosticContext(qualityPass)}',
        );
        _qualityPassIndex += 1;
        _providerIndex = 0;
        _sourceIndex = 0;
        _failedSourceAttempts.clear();
        if (_qualityPassIndex < qualityPasses.length && mounted) {
          final status = _qualityPassStatusFor(qualityPasses);
          _logPlaybackStatus(status, reason: 'quality_exhausted');
          setState(() {
            _loading = true;
            _controlsVisible = true;
            _statusMessage = status;
          });
        }
      }

      DiagnosticLog.add(
        'native engine pass exhausted engine=${engine.id} pass=${_enginePassIndex + 1}/${enginePasses.length}',
      );
      _enginePassIndex += 1;
      _qualityPassIndex = 0;
      _providerIndex = 0;
      _sourceIndex = 0;
      _failedSourceAttempts.clear();
      _skipUnsupportedHighEfficiencyForSession = false;
      if (_enginePassIndex < enginePasses.length && mounted) {
        final status = _enginePassStatusFor(enginePasses);
        _logPlaybackStatus(status, reason: 'engine_exhausted');
        setState(() {
          _loading = true;
          _controlsVisible = true;
          _statusMessage = status;
        });
      }
    }

    if (!mounted || runId != _providerRunId) return;
    if (await _retryLiveTvOnceAfterTransientExhaustion(runId)) return;
    if (await _switchProviderToAutoTemporarilyIfNeeded(runId)) return;
    if (await _maybeSearchP2pIndexers(runId)) return;
    DiagnosticLog.add('native page exhausted all providers');
    await _finishWithNoWorkingSource();
  }

  Future<bool> _maybeSearchP2pIndexers(int runId) async {
    if (_p2pIndexerSearchAttempted) return false;
    if (_normalSourcePlaybackStillAvailableForIndexerSkip()) {
      DiagnosticLog.add(
        'native p2p indexer search skipped reason=normal_sources_available',
      );
      return false;
    }
    if (!AppState.p2pRuntimePlaybackEffective) {
      DiagnosticLog.add(
        'native p2p indexer search skipped reason=p2p_gate_closed',
      );
      return false;
    }
    if (!AppState.p2pIndexerConnectorsEnabled.value) {
      DiagnosticLog.add(
        'native p2p indexer search skipped reason=connector_switch_off',
      );
      return false;
    }
    final connectors = AppState.enabledP2pIndexerConnectors();
    if (connectors.isEmpty) {
      DiagnosticLog.add(
        'native p2p indexer search skipped reason=no_enabled_connectors',
      );
      return false;
    }

    _p2pIndexerSearchAttempted = true;
    final searchRequest = _p2pIndexerSearchRequestForCurrentItem();
    DiagnosticLog.add(
      'native p2p indexer search start reason=normal_sources_need_help connectors=${connectors.length} uri=[hidden]',
    );
    if (mounted) {
      const status = 'Checking fallback P2P sources...';
      _logPlaybackStatus(status, reason: 'p2p_indexer_search');
      setState(() {
        _loading = true;
        _controlsVisible = true;
        _statusMessage = status;
      });
    }

    final client = const P2pIndexerConnectorClient();
    final candidates = <P2pIndexerCandidate>[];
    for (final connector in connectors) {
      final results = await client.search(connector, searchRequest);
      if (!mounted || runId != _providerRunId) return true;
      candidates.addAll(
        results.where((candidate) {
          if (candidate.hasUsableP2pDescriptor) return true;
          DiagnosticLog.add(
            'native p2p indexer candidate skipped reason=missing_safe_descriptor ${candidate.redactedDiagnostic}',
          );
          return false;
        }),
      );
    }
    if (candidates.isEmpty) {
      DiagnosticLog.add(
        'native p2p indexer search empty reason=no_playable_candidates',
      );
      return false;
    }

    final sources = candidates
        .map((candidate) => candidate.toLockedPlaybackSource())
        .where(_verifiedSourceHasOpenableDescriptor)
        .toList(growable: false);
    if (sources.isEmpty) {
      DiagnosticLog.add(
        'native p2p indexer search empty reason=no_openable_descriptors',
      );
      return false;
    }

    DiagnosticLog.add(
      'native p2p indexer candidates ready count=${sources.length} sourceClass=p2p',
    );
    _requests = <NativePlaybackRequest>[
      NativePlaybackRequest(providerId: 'p2p-indexer', sources: sources),
    ];
    _providerResolveFutures.remove('p2p-indexer');
    _enginePassIndex = 0;
    _qualityPassIndex = 0;
    _providerIndex = 0;
    _sourceIndex = 0;
    _activeSources = const <PlaybackSource>[];
    _activeSource = null;
    _failedSourceAttempts.clear();
    await _openNextAvailableSource();
    return true;
  }

  bool _normalSourcePlaybackStillAvailableForIndexerSkip() {
    final enginePasses = _enginePassesForCurrentSettings();
    return _enginePassIndex < enginePasses.length &&
        _providerIndex < _requests.length;
  }

  P2pIndexerSearchRequest _p2pIndexerSearchRequestForCurrentItem() {
    final item = _progressItem;
    final mediaType =
        item?.type.compatTypeValue ?? (widget.liveMode ? 'tv' : 'movie');
    final title = (item?.name.trim().isNotEmpty ?? false) ? item!.name : _title;
    return P2pIndexerSearchRequest(
      mediaType: mediaType,
      title: title,
      year: int.tryParse(item?.year ?? ''),
    );
  }

  Future<bool> _retryLiveTvOnceAfterTransientExhaustion(int runId) async {
    if (_liveTvAutoRetryAttempted ||
        !_limitToFirstQualityPass ||
        !_requests.any((request) => request.sources.any(_isPublicIptvSource)) ||
        _resolverTemporarilyBlocked) {
      return false;
    }
    _liveTvAutoRetryAttempted = true;
    _failureCloseGeneration += 1;
    _providerIndex = 0;
    _sourceIndex = 0;
    _enginePassIndex = 0;
    _qualityPassIndex = 0;
    _failedSourceAttempts.clear();
    _lastOpenFailureMessage = null;
    const status = 'Checking another live TV route...';
    DiagnosticLog.add(
      'native live tv auto retry scheduled reason=transient_candidate_exhausted requestCount=${_requests.length}',
    );
    _logPlaybackStatus(status, reason: 'live_tv_auto_retry');
    if (mounted) {
      setState(() {
        _loading = true;
        _controlsVisible = true;
        _nativeProvidersExhausted = false;
        _statusMessage = status;
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted || runId != _providerRunId) return true;
    unawaited(_openNextAvailableSource());
    return true;
  }

  Future<bool> _switchProviderToAutoTemporarilyIfNeeded(int runId) async {
    if (_limitToFirstQualityPass) {
      DiagnosticLog.add(
        'native provider temporary auto skipped reason=resolved_only_route',
      );
      return false;
    }
    if (_temporaryAutoProviderRecovery) {
      DiagnosticLog.add(
        'native provider temporary auto skipped reason=already_recovered',
      );
      return false;
    }
    if (_requests.length != 1) {
      DiagnosticLog.add(
        'native provider temporary auto skipped reason=request_count count=${_requests.length}',
      );
      return false;
    }
    final exhaustedProviderId = _requests.single.providerId;
    if (!AppState.nativeProviderOrder.contains(exhaustedProviderId)) {
      DiagnosticLog.add(
        'native provider temporary auto skipped provider=$exhaustedProviderId reason=not_user_selectable',
      );
      return false;
    }
    final autoProviderIds = AppState.orderedNativeProviderIds(
      selected: AppState.autoNativeProviderId,
      mediaKey: _playbackKey ?? _progressItem?.id,
    ).where((providerId) => providerId != exhaustedProviderId).toList();
    if (autoProviderIds.isEmpty) {
      DiagnosticLog.add(
        'native provider temporary auto skipped provider=$exhaustedProviderId reason=no_auto_alternatives',
      );
      return false;
    }

    _temporaryAutoProviderRecovery = true;
    final status =
        '${_providerLabel(exhaustedProviderId)} exhausted. Switching to Auto temporarily...';
    DiagnosticLog.add(
      'native provider exhausted; switching to auto temporarily provider=$exhaustedProviderId',
    );
    _logPlaybackStatus(status, reason: 'provider_temporary_auto');
    if (mounted) {
      setState(() {
        _loading = true;
        _controlsVisible = true;
        _statusMessage = status;
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted || runId != _providerRunId) return true;

    _requests = [
      for (final providerId in autoProviderIds)
        NativePlaybackRequest(providerId: providerId),
    ];
    _providerResolveFutures.remove(exhaustedProviderId);
    _enginePassIndex = 0;
    _qualityPassIndex = 0;
    _providerIndex = 0;
    _sourceIndex = 0;
    _activeSources = const <PlaybackSource>[];
    _activeSource = null;
    _failedSourceAttempts.clear();
    DiagnosticLog.add(
      'native temporary auto provider order=${_requests.map((request) => _providerLabel(request.providerId)).join('>')}',
    );
    await _openNextAvailableSource();
    return true;
  }

  void _recordNativeProviderFailureForSource(
    PlaybackSource source, {
    int? sourceCount,
  }) {
    if (source.providerId == 'p2p-indexer') {
      DiagnosticLog.add(
        'native p2p indexer source failure isolated reason=no_provider_health_penalty',
      );
      return;
    }
    AppState.recordNativeProviderFailure(
      mediaKey: _playbackKey,
      providerId: source.providerId,
      sourceCount: sourceCount,
      updateHealth: _shouldUpdateProviderHealthFromPlaybackFailure,
    );
  }

  Future<List<PlaybackSource>> _resolveProviderSources(String providerId) {
    return _providerResolveFutures.putIfAbsent(providerId, () async {
      final stopwatch = Stopwatch()..start();
      final timeout = _providerResolveTimeoutFor(providerId);
      final health = AppState.nativeProviderHealthFor(providerId);
      DiagnosticLog.add(
        'native provider resolve start provider=$providerId health=${health.name} timeout=${timeout.inSeconds}s',
      );
      late final List<PlaybackSource> sources;
      try {
        sources = await _resolveProvider(providerId).timeout(timeout);
      } on TimeoutException catch (error) {
        stopwatch.stop();
        DiagnosticLog.add(
          'native provider resolve timed out provider=$providerId health=${health.name} timeout=${timeout.inSeconds}s elapsed=${stopwatch.elapsedMilliseconds}ms error=${_safeDiagnosticError(error)}',
        );
        rethrow;
      }
      stopwatch.stop();
      AppState.recordNativeProviderResolve(
        providerId: providerId,
        sourceCount: visiblePlaybackSourceCount(sources),
        elapsed: stopwatch.elapsed,
      );
      DiagnosticLog.add(
        'native provider resolve ok provider=$providerId count=${sources.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      return sources;
    });
  }

  List<_NativePlaybackEngine> _enginePassesForCurrentSettings() {
    final requested = AppState.playerBehaviorSettings.value.playbackEngine;
    final configured = _effectivePlaybackEngine;
    if (_isLiveTvMode && configured != 'libvlc') {
      DiagnosticLog.add(
        'native engine pass limited provider=live-tv engine=exoplayer reason=live-tv-route',
      );
      return const <_NativePlaybackEngine>[_NativePlaybackEngine.exoplayer];
    }
    if (_libVlcCrashGuardActiveForManualRoute && requested == 'libvlc') {
      DiagnosticLog.add(
        'native engine pass guarded engine=libvlc scope=manual reason=previous_native_engine_interrupted',
      );
      return const <_NativePlaybackEngine>[_NativePlaybackEngine.exoplayer];
    }
    if (_libvlcUnavailableForAppSession) {
      return switch (configured) {
        'libvlc' => const <_NativePlaybackEngine>[_NativePlaybackEngine.libvlc],
        'exoplayer' => const <_NativePlaybackEngine>[
          _NativePlaybackEngine.exoplayer,
        ],
        'ksplayer' => const <_NativePlaybackEngine>[
          _NativePlaybackEngine.exoplayer,
        ],
        _ => const <_NativePlaybackEngine>[_NativePlaybackEngine.exoplayer],
      };
    }
    return switch (configured) {
      'libvlc' => const <_NativePlaybackEngine>[_NativePlaybackEngine.libvlc],
      'exoplayer' => const <_NativePlaybackEngine>[
        _NativePlaybackEngine.exoplayer,
      ],
      'ksplayer' => const <_NativePlaybackEngine>[
        _NativePlaybackEngine.exoplayer,
      ],
      _ =>
        _isP2pOnlySourceRoute
            ? const <_NativePlaybackEngine>[
                _NativePlaybackEngine.libvlc,
                _NativePlaybackEngine.exoplayer,
              ]
            : const <_NativePlaybackEngine>[
                _NativePlaybackEngine.exoplayer,
                _NativePlaybackEngine.libvlc,
              ],
    };
  }

  String _enginePassDecisionReason() {
    final configured = AppState.playerBehaviorSettings.value.playbackEngine;
    if (_isLiveTvMode && configured != 'libvlc') {
      return 'live_tv_exoplayer_only';
    }
    if (_libvlcUnavailableForAppSession) {
      if (configured == 'libvlc') {
        return 'manual_libvlc_app_session_retry';
      }
      return 'libvlc_app_session_unavailable';
    }
    if (_temporaryAutoEngineRecovery) {
      return 'temporary_auto_engine_recovery';
    }
    if (_libVlcCrashGuardActiveForManualRoute && configured == 'libvlc') {
      return 'manual_libvlc_guarded_after_native_engine_interrupted';
    }
    return switch (configured) {
      'libvlc' => 'manual_libvlc',
      'exoplayer' => 'manual_exoplayer',
      'ksplayer' => 'ksplayer_android_fallback_exoplayer',
      _ =>
        _isP2pOnlySourceRoute
            ? 'auto_libvlc_then_exoplayer_p2p_only'
            : 'auto_exoplayer_then_libvlc_direct_debrid',
    };
  }

  bool get _isPublicIptvOnlyRoute {
    return _requests.isNotEmpty &&
        _requests.every(
          (request) => request.providerId.trim().toLowerCase() == 'public-iptv',
        );
  }

  bool get _isLiveTvMode {
    return widget.liveMode ||
        _progressItem?.type == MediaType.liveTv ||
        _isPublicIptvOnlyRoute;
  }

  bool get _libvlcUnavailableForCurrentPass {
    final configured = _effectivePlaybackEngine;
    if (configured == 'libvlc') return _libvlcUnavailableForSession;
    return _libvlcUnavailable;
  }

  bool get _libVlcCrashGuardActive {
    return DiagnosticLog.previousSessionExit == 'native_engine_interrupted' &&
        DiagnosticLog.previousNativeEngineActiveEngine == 'libvlc';
  }

  bool get _libVlcCrashGuardActiveForManualRoute {
    return _libVlcCrashGuardActive && !_isP2pOnlySourceRoute;
  }

  String get _effectivePlaybackEngine {
    final configured = AppState.playerBehaviorSettings.value.playbackEngine;
    if (_temporaryAutoEngineRecovery) return 'auto';
    if (_libVlcCrashGuardActiveForManualRoute && configured == 'libvlc') {
      return 'exoplayer';
    }
    return configured;
  }

  bool get _manualLibVlcConfigured {
    return AppState.playerBehaviorSettings.value.playbackEngine == 'libvlc';
  }

  bool _manualLibVlcStrictForSource(PlaybackSource source) {
    return _manualLibVlcConfigured && !_isPublicIptvSource(source);
  }

  int get _manualLibVlcRouteOpenWithoutProofLimit {
    if (_limitToFirstQualityPass) return 8;
    return 10;
  }

  int get _manualLibVlcSameSourceOpenWithoutProofLimit {
    if (_limitToFirstQualityPass) return 1;
    return 2;
  }

  bool get _isP2pOnlySourceRoute {
    var hasSource = false;
    for (final request in _requests) {
      for (final source in request.sources) {
        hasSource = true;
        if (source.sourceClass != PlaybackSourceClass.p2p) return false;
      }
    }
    return hasSource;
  }

  BatteryDataSettings get _batteryDataSettings =>
      AppState.batteryDataSettings.value;

  bool get _batterySaverPlaybackActive =>
      _batteryDataSettings.batterySaverPlayback;

  bool get _hasP2pRouteActivity {
    if (_activeSource?.sourceClass == PlaybackSourceClass.p2p) return true;
    if (_p2pLocalStreamSourcesByKey.isNotEmpty) return true;
    for (final request in _requests) {
      for (final source in request.sources) {
        if (source.sourceClass == PlaybackSourceClass.p2p) return true;
      }
    }
    return false;
  }

  Future<void> _stopP2pBridgeForPolicy(String reason) async {
    if (!_hasP2pRouteActivity) return;
    _p2pLocalStreamSourcesByKey.clear();
    _p2pLocalStreamTotalBytesByUrl.clear();
    try {
      await P2pLocalStreamBridge.instance.stopAll();
      DiagnosticLog.add('native p2p bridge stopped reason=$reason');
    } catch (error) {
      DiagnosticLog.add(
        'native p2p bridge stop skipped reason=$reason error=${_safeDiagnosticError(error)}',
      );
    }
  }

  List<_QualityPass> _qualityPassesForCurrentSettings() {
    if (_isP2pOnlySourceRoute) {
      return _p2pQualityPassesForCurrentSettings();
    }
    final target = _qualityPassTargetForCurrentSettings();
    if (target != null) {
      return <_QualityPass>[_QualityPass.target(target)];
    }
    final preferred = _preferredQuality;
    if (!_usingGlobalOverrides &&
        (preferred == null || preferred.isEmpty || preferred == 'Auto')) {
      return const <_QualityPass>[_QualityPass.autoPass];
    }
    if (_batterySaverPlaybackActive ||
        (_usingGlobalOverrides && _qualityPreferenceMode == 'dataSaver')) {
      return <_QualityPass>[
        _QualityPass.rank(240),
        _QualityPass.rank(266),
        _QualityPass.rank(336),
        _QualityPass.rank(360),
        _QualityPass.rank(452),
        _QualityPass.rank(480),
        _QualityPass.rank(534),
        _QualityPass.rank(674),
        _QualityPass.rank(720),
        _QualityPass.rank(800),
        _QualityPass.rank(1080),
        _QualityPass.rank(1440),
        _QualityPass.rank(2160),
        _QualityPass.rank(4320),
        _QualityPass.unknownPass,
      ];
    }
    if (_usingGlobalOverrides && _qualityPreferenceMode == 'recommended') {
      return const <_QualityPass>[_QualityPass.autoPass];
    }
    if (_usingGlobalOverrides && _qualityPreferenceMode == 'higher') {
      return <_QualityPass>[
        _QualityPass.highestAvailablePass,
        _QualityPass.rank(4320),
        _QualityPass.rank(2160),
        _QualityPass.rank(1440),
        _QualityPass.rank(1080),
        _QualityPass.rank(720),
        _QualityPass.rank(480),
        _QualityPass.rank(360),
        _QualityPass.unknownPass,
      ];
    }
    final hasKnown4k = _requests.any(
      (request) => request.sources.any(
        (source) => _qualityRank(_qualityLabel(source)) >= 2160,
      ),
    );
    if (!hasKnown4k) {
      return <_QualityPass>[
        _QualityPass.rank(1080),
        _QualityPass.rank(720),
        _QualityPass.rank(480),
        _QualityPass.rank(360),
        _QualityPass.unknownPass,
        _QualityPass.rank(2160),
      ];
    }
    return <_QualityPass>[
      _QualityPass.rank(2160),
      _QualityPass.rank(1080),
      _QualityPass.rank(720),
      _QualityPass.rank(480),
      _QualityPass.rank(360),
      _QualityPass.unknownPass,
    ];
  }

  List<_QualityPass> _p2pQualityPassesForCurrentSettings() {
    if (_p2pRouteHasOnlyUnknownQuality) {
      DiagnosticLog.add(
        'native p2p quality strategy mode=${_usingGlobalOverrides ? _qualityPreferenceMode : 'saved'} pass=auto-only reason=unknown_quality_only',
      );
      return const <_QualityPass>[_QualityPass.autoPass];
    }
    final target = _qualityPassTargetForCurrentSettings();
    if (target != null) {
      final preferredRank = target.rank ?? _qualityRank(target.label ?? '');
      return _dedupeQualityPasses(<_QualityPass>[
        _QualityPass.target(target),
        ..._p2pNearbyFallbackPasses(preferredRank),
      ]);
    }
    if (_batterySaverPlaybackActive ||
        (_usingGlobalOverrides && _qualityPreferenceMode == 'dataSaver')) {
      return _dedupeQualityPasses(<_QualityPass>[
        _QualityPass.rank(720),
        _QualityPass.rank(480),
        _QualityPass.rank(360),
        _QualityPass.unknownPass,
        _QualityPass.rank(1080),
        _QualityPass.rank(1440),
        _QualityPass.rank(2160),
        _QualityPass.rank(4320),
      ]);
    }
    if (_usingGlobalOverrides && _qualityPreferenceMode == 'higher') {
      return _dedupeQualityPasses(<_QualityPass>[
        _QualityPass.rank(1080),
        _QualityPass.rank(1440),
        _QualityPass.rank(2160),
        _QualityPass.rank(4320),
        _QualityPass.rank(720),
        _QualityPass.unknownPass,
        _QualityPass.rank(480),
        _QualityPass.rank(360),
      ]);
    }
    DiagnosticLog.add(
      'native p2p quality strategy mode=${_batterySaverPlaybackActive
          ? 'batterySaver'
          : _usingGlobalOverrides
          ? _qualityPreferenceMode
          : 'saved'} pass=auto-safe',
    );
    return const <_QualityPass>[_QualityPass.autoPass];
  }

  bool get _p2pRouteHasOnlyUnknownQuality {
    var hasP2pSource = false;
    for (final request in _requests) {
      for (final source in request.sources) {
        if (source.sourceClass != PlaybackSourceClass.p2p) continue;
        hasP2pSource = true;
        if (_qualityRank(_qualityLabel(source)) > 0) return false;
      }
    }
    return hasP2pSource;
  }

  List<_QualityPass> _p2pNearbyFallbackPasses(int preferredRank) {
    if (preferredRank >= 2160) {
      return <_QualityPass>[
        _QualityPass.rank(2160),
        _QualityPass.rank(1080),
        _QualityPass.rank(1440),
        _QualityPass.rank(720),
        _QualityPass.unknownPass,
        _QualityPass.rank(480),
      ];
    }
    if (preferredRank >= 1080) {
      return <_QualityPass>[
        _QualityPass.rank(1080),
        _QualityPass.rank(720),
        _QualityPass.unknownPass,
        _QualityPass.rank(1440),
        _QualityPass.rank(2160),
        _QualityPass.rank(480),
      ];
    }
    if (preferredRank >= 720) {
      return <_QualityPass>[
        _QualityPass.rank(720),
        _QualityPass.rank(480),
        _QualityPass.unknownPass,
        _QualityPass.rank(1080),
        _QualityPass.rank(360),
      ];
    }
    return <_QualityPass>[
      _QualityPass.unknownPass,
      _QualityPass.rank(720),
      _QualityPass.rank(1080),
      _QualityPass.rank(480),
      _QualityPass.rank(360),
    ];
  }

  List<_QualityPass> _dedupeQualityPasses(List<_QualityPass> passes) {
    final seen = <String>{};
    return [
      for (final pass in passes)
        if (seen.add(pass.label)) pass,
    ];
  }

  List<_QualityPass> _qualityPassesForCurrentAttempt() {
    final passes = _qualityPassesForCurrentSettings();
    if (!_limitToFirstQualityPass ||
        _qualityModeNeedsOrderedFallbackPasses ||
        passes.length <= 1) {
      return passes;
    }
    return passes.take(1).toList(growable: false);
  }

  bool get _qualityModeNeedsOrderedFallbackPasses {
    if (_isP2pOnlySourceRoute && _qualityPassTargetForCurrentSettings() != null)
      return true;
    return _usingGlobalOverrides &&
        (_qualityPreferenceMode == 'higher' ||
            _qualityPreferenceMode == 'dataSaver');
  }

  _QualityPassTarget? _qualityPassTargetForCurrentSettings() {
    if (_usingGlobalOverrides && _qualityPreferenceMode == 'higher')
      return null;
    if (_batterySaverPlaybackActive ||
        (_usingGlobalOverrides && _qualityPreferenceMode == 'dataSaver'))
      return null;
    if (_usingGlobalOverrides && _qualityPreferenceMode == 'recommended')
      return null;
    final preferred = _preferredQuality;
    if (preferred == null || preferred.isEmpty || preferred == 'Auto')
      return null;
    if (preferred == '4320P')
      return const _QualityPassTarget(label: '4320P', rank: 4320);
    final rank = _qualityRank(preferred);
    return _QualityPassTarget(label: preferred, rank: rank > 0 ? rank : null);
  }

  bool get _libvlcUnavailable {
    return _libvlcUnavailableForSession || _libvlcUnavailableForAppSession;
  }

  List<PlaybackSource> _filterSourcesForQualityPass(
    List<PlaybackSource> sources,
    _QualityPass pass,
  ) {
    if (pass.isHighestAvailable) {
      final highestRank = _highestKnownQualityRank(sources);
      if (highestRank <= 0) {
        return [
          for (final source in sources)
            if (_qualityRank(_qualityLabel(source)) <= 0) source,
        ];
      }
      return [
        for (final source in sources)
          if (_qualityRank(_qualityLabel(source)) == highestRank) source,
      ];
    }
    final target = pass.target;
    if (pass.isUnknownQuality) {
      if (_usingHigherAvailableFirst &&
          _highestKnownQualityRank(sources) <= 0) {
        return const <PlaybackSource>[];
      }
      return [
        for (final source in sources)
          if (_qualityRank(_qualityLabel(source)) <= 0) source,
      ];
    }
    if (target == null) return sources;
    if (_usingHigherAvailableFirst &&
        target.rank != null &&
        _highestKnownQualityRank(sources) == target.rank) {
      return const <PlaybackSource>[];
    }
    final exactMatches = target.label == null
        ? const <PlaybackSource>[]
        : sources
              .where((source) => _qualityLabel(source) == target.label)
              .toList();
    final rankedMatches = exactMatches.isNotEmpty || target.rank == null
        ? exactMatches
        : sources
              .where(
                (source) => _qualityRank(_qualityLabel(source)) == target.rank,
              )
              .toList();
    return rankedMatches;
  }

  bool get _usingHigherAvailableFirst {
    return _usingGlobalOverrides && _qualityPreferenceMode == 'higher';
  }

  int _highestKnownQualityRank(List<PlaybackSource> sources) {
    var highestRank = 0;
    for (final source in sources) {
      final rank = _qualityRank(_qualityLabel(source));
      if (rank > highestRank) highestRank = rank;
    }
    return highestRank;
  }

  String _qualityDiagnosticContext([_QualityPass? pass]) {
    final mode = _usingGlobalOverrides ? _qualityPreferenceMode : 'saved';
    final preferred = _preferredQuality == null || _preferredQuality!.isEmpty
        ? 'Auto'
        : _preferredQuality!;
    final passLabel = pass == null ? 'none' : pass.label;
    return 'qualityMode=$mode preferred=$preferred qualityPass=$passLabel';
  }

  Future<void> _finishWithNoWorkingSource() async {
    _pauseActivePlaybackForLoading('playback_failed');
    DiagnosticLog.add(
      'native playback failed title="$_title" engine=${AppState.playerBehaviorSettings.value.playbackEngine}',
    );
    if (!mounted) return;
    final unsupportedSourceClasses =
        !_resolverTemporarilyBlocked &&
        _lastOpenFailureMessage == null &&
        _nativeSourceClassSkipCounts.isNotEmpty;
    final skippedSourceClassSummary = _nativeSourceClassSkipSummary();
    if (unsupportedSourceClasses) {
      DiagnosticLog.add(
        'native playback failed reason=source_class_not_native sourceClasses=$skippedSourceClassSummary',
      );
    }
    final resolvedOnlyRoute = _limitToFirstQualityPass;
    final status = _resolverTemporarilyBlocked
        ? 'Playback is busy, so Juicr paused the scan to protect this session.\nPlease try again shortly.'
        : unsupportedSourceClasses
        ? 'Juicr found sources, but they are not supported by native playback yet ($skippedSourceClassSummary).\nSending you back.'
        : resolvedOnlyRoute
        ? 'Video is currently unavailable.\nSending you back.'
        : _lastOpenFailureMessage == null
        ? "Couldn't open this one. Sending you back."
        : "$_lastOpenFailureMessage\nSending you back.";
    _logPlaybackStatus(status, reason: 'playback_failed');
    setState(() {
      _loading = true;
      _controlsVisible = true;
      _nativeProvidersExhausted = true;
      _statusMessage = status;
    });
    final failureCloseGeneration = ++_failureCloseGeneration;
    await Future<void>.delayed(_failureReadDelayForRoute);
    if (!mounted ||
        _playerClosing ||
        failureCloseGeneration != _failureCloseGeneration ||
        !_nativeProvidersExhausted) {
      return;
    }
    await _close(
      _resolverTemporarilyBlocked
          ? 'native_error:playback_service_temporary_block'
          : unsupportedSourceClasses
          ? 'native_error:source_class_not_native'
          : resolvedOnlyRoute
          ? 'native_error:no_playable_source'
          : _lastOpenFailureMessage == null
          ? 'native_error'
          : 'native_error:$_lastOpenFailureMessage',
    );
  }

  Future<bool> _pauseProviderScanForResolverBlock() async {
    final controller = _controller;
    final source = _activeSource;
    if (controller == null || source == null || !controller.isInitialized) {
      return false;
    }
    DiagnosticLog.add(
      'native provider scan paused reason=playback_service_temporary_block activeProvider=${source.providerId}',
    );
    const status =
        'Playback is busy, so Juicr paused the scan to protect this session.';
    _resolverTemporarilyBlocked = true;
    _recoveringFromStall = false;
    _loading = false;
    _statusMessage = status;
    _controlsVisible = true;
    _settingsExpanded = false;
    _stallWatchdogTicks = 0;
    _deadPauseTicks = 0;
    try {
      await controller.play();
      DiagnosticLog.add(
        'native provider scan paused; resumed active controller provider=${source.providerId}',
      );
      _logPlaybackStatus(status, reason: 'resolver_protected');
    } catch (error) {
      DiagnosticLog.add(
        'native provider scan pause resume failed provider=${source.providerId} error=${_safeDiagnosticError(error)}',
      );
    }
    if (mounted) {
      setState(() {});
    }
    _startStallWatchdog();
    return true;
  }

  void _warmNextProviderResolve() {
    if (_limitToFirstQualityPass) {
      DiagnosticLog.add(
        'native provider warmup skipped reason=capped_cold_scan',
      );
      return;
    }
    if (!_enableProviderWarmup) {
      DiagnosticLog.add(
        'native provider warmup skipped reason=bootstrap_empty',
      );
      return;
    }
    final maxWarmups = _providerWarmupCount;
    if (maxWarmups <= 0) return;
    var warmed = 0;
    for (var index = _providerIndex + 1; index < _requests.length; index += 1) {
      final next = _requests[index];
      if (next.sources.isNotEmpty) continue;
      if (_providerResolveFutures.containsKey(next.providerId)) continue;
      DiagnosticLog.add(
        'native provider resolve warmup provider=${next.providerId} fromIndex=$_providerIndex',
      );
      unawaited(
        _resolveProviderSources(next.providerId).catchError((Object error) {
          DiagnosticLog.add(
            'native provider resolve warmup failed provider=${next.providerId} error=${_safeDiagnosticError(error)}',
          );
          return <PlaybackSource>[];
        }),
      );
      warmed += 1;
      if (warmed >= maxWarmups) return;
    }
  }

  Future<bool> _isNativeReadableSource(
    PlaybackSource source, {
    _NativePlaybackEngine? engine,
  }) async {
    if (!_isHlsSource(source)) {
      if (engine == _NativePlaybackEngine.libvlc) {
        return _isLibVlcRemoteReadableSource(source);
      }
      return true;
    }
    try {
      final timeout = _isPublicIptvSource(source)
          ? const Duration(seconds: 4)
          : const Duration(seconds: 3);
      final response = await http
          .get(Uri.parse(source.url), headers: source.headers)
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (_isPublicIptvSource(source)) {
          _lastOpenFailureMessage = _liveTvUnavailableMessage;
        }
        DiagnosticLog.add(
          'native hls preflight failed provider=${source.providerId} status=${response.statusCode}',
        );
        return false;
      }

      final contentType = response.headers['content-type'] ?? '';
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final publicIptvSource = _isPublicIptvSource(source);
      final looksLikeHls =
          body.trimLeft().startsWith('#EXTM3U') ||
          (!publicIptvSource && contentType.toLowerCase().contains('mpegurl'));
      if (!looksLikeHls) {
        if (publicIptvSource) {
          _lastOpenFailureMessage = _liveTvUnavailableMessage;
        }
        DiagnosticLog.add(
          'native hls preflight rejected provider=${source.providerId} contentType=$contentType',
        );
        return false;
      }
      if (publicIptvSource) {
        final rejectReason = _publicIptvManifestRejectReason(source, body);
        if (rejectReason != null) {
          _lastOpenFailureMessage = _liveTvUnavailableMessage;
          DiagnosticLog.add(
            'native hls preflight rejected provider=${source.providerId} reason=$rejectReason',
          );
          return false;
        }
        DiagnosticLog.add(
          'native hls preflight ok provider=${source.providerId} reason=live-tv-directory contentType=$contentType',
        );
      }
      if (engine == _NativePlaybackEngine.libvlc) {
        if (_manualLibVlcConfigured && source.headers.isNotEmpty) {
          DiagnosticLog.add(
            'native libvlc hls preflight ok reason=relay_candidate headers=${_headerCountBucket(source.headers.length)}',
          );
        } else if (!await _libVlcHlsForwardingCompatible(
          source,
          Uri.parse(source.url),
          body,
        )) {
          return false;
        }
      }
      return true;
    } catch (error) {
      if (_isPublicIptvSource(source)) {
        _lastOpenFailureMessage = _liveTvUnavailableMessage;
      }
      DiagnosticLog.add(
        'native hls preflight failed provider=${source.providerId} error=${_safeDiagnosticError(error)}',
      );
      return false;
    }
  }

  bool _isHlsSource(PlaybackSource source) {
    final type = (source.type ?? '').toLowerCase();
    final url = source.url.toLowerCase();
    return type == 'hls' || url.contains('.m3u8');
  }

  bool _hasLibVlcHeaderForwardingGap(Map<String, String> headers) {
    return headers.keys.any(
      (key) => !_isLibVlcForwardableHeaderName(key.trim().toLowerCase()),
    );
  }

  bool _isLibVlcForwardableHeaderName(String key) {
    return key == 'user-agent' ||
        key == 'referer' ||
        key == 'referrer' ||
        key == 'cookie';
  }

  Map<String, String> _libVlcForwardableHeaders(Map<String, String> headers) {
    final forwarded = <String, String>{};
    for (final entry in headers.entries) {
      final key = entry.key.trim();
      final normalized = key.toLowerCase();
      final value = entry.value.trim();
      if (value.isEmpty || !_isLibVlcForwardableHeaderName(normalized)) {
        continue;
      }
      if (normalized == 'referrer') {
        forwarded['Referer'] = value;
      } else {
        forwarded[key] = value;
      }
    }
    return forwarded;
  }

  String _libVlcHeaderGapBuckets(Map<String, String> headers) {
    final buckets = <String>{};
    for (final key in headers.keys.map((key) => key.trim().toLowerCase())) {
      if (_isLibVlcForwardableHeaderName(key)) continue;
      if (key == 'origin') {
        buckets.add('browser_context');
      } else if (key == 'accept' || key == 'accept-language') {
        buckets.add('negotiation');
      } else if (key == 'authorization' || key == 'x-api-key') {
        buckets.add('authorization');
      } else if (key.startsWith('x-')) {
        buckets.add('custom');
      } else {
        buckets.add('other');
      }
    }
    return buckets.isEmpty ? 'none' : buckets.join(',');
  }

  bool _isReadableLibVlcHttpStatus(int statusCode) {
    return statusCode == 200 ||
        statusCode == 206 ||
        (statusCode >= 300 && statusCode < 400);
  }

  Uri? _firstHlsChildUri(Uri baseUri, String body) {
    for (final line in _hlsManifestLines(body)) {
      if (line.startsWith('#')) continue;
      return baseUri.resolve(line);
    }
    return null;
  }

  Future<bool> _libVlcHlsForwardingCompatible(
    PlaybackSource source,
    Uri manifestUri,
    String manifestBody,
  ) async {
    if (!_hasLibVlcHeaderForwardingGap(source.headers)) return true;
    final forwardedHeaders = _libVlcForwardableHeaders(source.headers);
    final buckets = _libVlcHeaderGapBuckets(source.headers);
    final childUri = _firstHlsChildUri(manifestUri, manifestBody);
    if (childUri == null) return true;
    try {
      final childResponse = await http
          .get(childUri, headers: forwardedHeaders)
          .timeout(const Duration(seconds: 3));
      if (!_isReadableLibVlcHttpStatus(childResponse.statusCode)) {
        DiagnosticLog.add(
          'native libvlc hls preflight failed reason=header_forwarding_gap stage=child_manifest status=${childResponse.statusCode} headerBuckets=$buckets',
        );
        return false;
      }
      final contentType = childResponse.headers['content-type'] ?? '';
      final childBody = utf8.decode(
        childResponse.bodyBytes,
        allowMalformed: true,
      );
      final childLooksLikeHls =
          childBody.trimLeft().startsWith('#EXTM3U') ||
          contentType.toLowerCase().contains('mpegurl');
      if (!childLooksLikeHls) return true;
      final segmentUri = _firstHlsChildUri(childUri, childBody);
      if (segmentUri == null) return true;
      final segmentHeaders = <String, String>{...forwardedHeaders};
      segmentHeaders.putIfAbsent('Range', () => 'bytes=0-1');
      final segmentResponse = await http
          .get(segmentUri, headers: segmentHeaders)
          .timeout(const Duration(seconds: 3));
      if (!_isReadableLibVlcHttpStatus(segmentResponse.statusCode)) {
        DiagnosticLog.add(
          'native libvlc hls preflight failed reason=header_forwarding_gap stage=media_segment status=${segmentResponse.statusCode} headerBuckets=$buckets',
        );
        return false;
      }
      DiagnosticLog.add(
        'native libvlc hls preflight ok reason=limited_header_child_read headerBuckets=$buckets',
      );
      return true;
    } catch (error) {
      DiagnosticLog.add(
        'native libvlc hls preflight failed reason=header_forwarding_gap error=${_safeDiagnosticError(error)} headerBuckets=$buckets',
      );
      return false;
    }
  }

  String _routeHlsProviderTimeoutKey(
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    return '${engine.id}|${source.providerId}';
  }

  String _routeHlsQualityTimeoutKey(
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    return '${engine.id}|${source.providerId}|${_qualityLabel(source)}';
  }

  bool _shouldSkipSourceAfterRouteOpenTimeouts(
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    if (!_limitToFirstQualityPass ||
        engine != _NativePlaybackEngine.exoplayer ||
        source.sourceClass != PlaybackSourceClass.direct ||
        !_isHlsSource(source)) {
      return false;
    }

    final providerKey = _routeHlsProviderTimeoutKey(source, engine);
    final qualityKey = _routeHlsQualityTimeoutKey(source, engine);
    final providerTimeouts = _routeHlsProviderOpenTimeouts[providerKey] ?? 0;
    final qualityTimeouts = _routeHlsQualityOpenTimeouts[qualityKey] ?? 0;
    if (providerTimeouts >= 3) {
      DiagnosticLog.add(
        'native source skipped provider=${source.providerId} sourceClass=${source.sourceClass.wireName} providerIndex=$_providerIndex sourceIndex=$_sourceIndex reason=route_hls_provider_timeout_cap engine=${engine.id} timeouts=$providerTimeouts quality=${_qualityLabel(source)}',
      );
      return true;
    }
    if (qualityTimeouts >= 2) {
      DiagnosticLog.add(
        'native source skipped provider=${source.providerId} sourceClass=${source.sourceClass.wireName} providerIndex=$_providerIndex sourceIndex=$_sourceIndex reason=route_hls_quality_timeout_cap engine=${engine.id} timeouts=$qualityTimeouts quality=${_qualityLabel(source)}',
      );
      return true;
    }
    return false;
  }

  void _recordRouteHlsOpenTimeout(
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    if (!_limitToFirstQualityPass ||
        engine != _NativePlaybackEngine.exoplayer ||
        source.sourceClass != PlaybackSourceClass.direct ||
        !_isHlsSource(source)) {
      return;
    }
    final providerKey = _routeHlsProviderTimeoutKey(source, engine);
    final qualityKey = _routeHlsQualityTimeoutKey(source, engine);
    final providerTimeouts =
        (_routeHlsProviderOpenTimeouts[providerKey] ?? 0) + 1;
    final qualityTimeouts = (_routeHlsQualityOpenTimeouts[qualityKey] ?? 0) + 1;
    _routeHlsProviderOpenTimeouts[providerKey] = providerTimeouts;
    _routeHlsQualityOpenTimeouts[qualityKey] = qualityTimeouts;
    DiagnosticLog.add(
      'native route hls timeout recorded provider=${source.providerId} engine=${engine.id} quality=${_qualityLabel(source)} providerTimeouts=$providerTimeouts qualityTimeouts=$qualityTimeouts',
    );
  }

  void _resetRouteHlsTimeoutsForQualitySwitch(PlaybackSource source) {
    if (!_isHlsSource(source)) return;
    var removed = 0;
    for (final engine in _NativePlaybackEngine.values) {
      final providerKey = _routeHlsProviderTimeoutKey(source, engine);
      final qualityKey = _routeHlsQualityTimeoutKey(source, engine);
      if (_routeHlsProviderOpenTimeouts.remove(providerKey) != null) {
        removed += 1;
      }
      if (_routeHlsQualityOpenTimeouts.remove(qualityKey) != null) {
        removed += 1;
      }
    }
    DiagnosticLog.add(
      'native quality switch timeout reset provider=${source.providerId} quality=${_qualityLabel(source)} removed=$removed',
    );
  }

  Future<bool> _isLibVlcRemoteReadableSource(PlaybackSource source) async {
    if (source.sourceClass == PlaybackSourceClass.p2p) return true;
    final uri = Uri.tryParse(source.url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return true;
    }
    try {
      final headers = <String, String>{...source.headers};
      final hasRangeHeader = headers.keys.any(
        (key) => key.toLowerCase() == 'range',
      );
      if (!hasRangeHeader) headers['Range'] = 'bytes=0-1';
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 3));
      final readable =
          response.statusCode == 200 ||
          response.statusCode == 206 ||
          (response.statusCode >= 300 && response.statusCode < 400);
      if (!readable) {
        DiagnosticLog.add(
          'native libvlc preflight failed provider=${source.providerId} status=${response.statusCode}',
        );
      }
      return readable;
    } on TimeoutException catch (error) {
      DiagnosticLog.add(
        'native libvlc preflight inconclusive provider=${source.providerId} error=${_safeDiagnosticError(error)} action=allow_open',
      );
      return true;
    } catch (error) {
      DiagnosticLog.add(
        'native libvlc preflight failed provider=${source.providerId} error=${_safeDiagnosticError(error)}',
      );
      return false;
    }
  }

  String? _publicIptvManifestRejectReason(PlaybackSource source, String body) {
    final lines = _hlsManifestLines(body);
    if (lines.isEmpty || lines.first != '#EXTM3U') return 'invalid-manifest';
    final hasMediaMarkers = lines.any(
      (line) =>
          line.startsWith('#EXT-X-STREAM-INF') ||
          line.startsWith('#EXT-X-TARGETDURATION') ||
          line.startsWith('#EXT-X-MEDIA-SEQUENCE') ||
          line.startsWith('#EXTINF'),
    );
    if (!hasMediaMarkers) return 'missing-media-markers';

    final baseUri = Uri.tryParse(source.url);
    if (baseUri == null) return null;
    for (final line in lines) {
      final keyUriMatches = RegExp(
        r'URI="([^"]+)"',
        caseSensitive: false,
      ).allMatches(line);
      for (final match in keyUriMatches) {
        final child = match.group(1);
        if (_isCleartextChildUri(baseUri, child)) {
          return 'cleartext-child-uri';
        }
      }
      if (line.startsWith('#')) continue;
      if (_isCleartextChildUri(baseUri, line)) {
        return 'cleartext-child-uri';
      }
    }
    return null;
  }

  List<String> _hlsManifestLines(String body) {
    return body
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  bool _isCleartextChildUri(Uri baseUri, String? child) {
    if (child == null || child.trim().isEmpty) return false;
    return baseUri.resolve(child.trim()).scheme.toLowerCase() == 'http';
  }

  _LibVlcProfile _libVlcProfileForSource(PlaybackSource source) {
    final index = (_libVlcProfileIndexByUrl[source.url] ?? 0).clamp(
      0,
      _libVlcProfiles.length - 1,
    );
    return _libVlcProfiles[index];
  }

  bool _advanceLibVlcProfileForSource(
    PlaybackSource source, {
    required String reason,
  }) {
    final current = (_libVlcProfileIndexByUrl[source.url] ?? 0).clamp(
      0,
      _libVlcProfiles.length - 1,
    );
    final next = current + 1;
    if (next >= _libVlcProfiles.length) {
      DiagnosticLog.add(
        'native libvlc profile exhausted provider=${source.providerId} current=${_libVlcProfiles[current].id} reason=$reason',
      );
      return false;
    }
    _libVlcProfileIndexByUrl[source.url] = next;
    DiagnosticLog.add(
      'native libvlc profile advance provider=${source.providerId} from=${_libVlcProfiles[current].id} to=${_libVlcProfiles[next].id} reason=$reason',
    );
    return true;
  }

  bool _sourceLooksLikeShortVodPlaceholder(
    PlaybackSource source,
    _NativePlaybackController controller,
  ) {
    if (!_shortVodPlaceholderGuardApplies(source)) return false;
    if (!controller.isInitialized || controller.hasError) return false;
    if (controller.duration <= Duration.zero) return false;
    if (controller.duration > _shortVodPlaceholderDurationLimit) return false;
    if (controller.size == Size.zero) return false;
    return true;
  }

  bool _shortVodPlaceholderGuardApplies(PlaybackSource source) {
    if (_isLiveTvMode || _isPublicIptvSource(source)) return false;
    if (source.sourceClass != PlaybackSourceClass.debrid) return false;
    final type = _progressItem?.type;
    return type == MediaType.movie ||
        type == MediaType.series ||
        type == MediaType.animation;
  }

  Future<bool> _rejectShortVodPlaceholderSource(
    PlaybackSource source,
    _NativePlaybackController controller, {
    required _NativePlaybackEngine engine,
    required int startupMs,
  }) async {
    if (!_sourceLooksLikeShortVodPlaceholder(source, controller)) return false;
    _lastOpenFailureMessage = 'This stream is currently unavailable.';
    _forgetVerifiedSource(source, 'short_vod_placeholder');
    _failedSourceAttempts[source.url] =
        (_failedSourceAttempts[source.url] ?? 0) + 1;
    DiagnosticLog.add(
      'native short placeholder source rejected provider=${source.providerId} sourceClass=${source.sourceClass.wireName} quality=${source.quality ?? 'auto'} engine=${engine.id} duration=${controller.duration.inSeconds}s limit=${_shortVodPlaceholderDurationLimit.inSeconds}s startupMs=$startupMs action=try_next_source url=[hidden]',
    );
    _sendPlaybackFeedback(
      'short_placeholder',
      source: source,
      controller: controller,
      engine: engine,
      startupMs: startupMs,
    );
    await _disposeCurrentController(
      awaitLibVlcRelease: true,
      saveProgress: false,
    );
    _activeSource = null;
    return true;
  }

  Future<bool> _openSource(
    PlaybackSource source, {
    Duration? resumePosition,
    String? statusMessage,
    _NativePlaybackEngine? engineOverride,
  }) async {
    if (_playerClosing) return false;
    if (!_nativePlaybackSupportsSourceClass(source)) {
      _recordNativeSourceClassSkip(source);
      DiagnosticLog.add(
        'native open skipped provider=${source.providerId} sourceClass=${source.sourceClass.wireName} reason=source_class_not_native url=[hidden]',
      );
      return false;
    }
    final openStopwatch = Stopwatch()..start();
    var p2pLocalStreamReady = false;
    _stopStallWatchdog();
    _openingGuardTimer?.cancel();
    _trackLastKnownPlaybackPosition();
    _saveNativeProgress(force: true);
    await _disposeCurrentController(awaitLibVlcRelease: true);
    _nativeWallClockStartedAt = null;
    _lastSavedSecond = -1;
    _resetPlaybackIntegritySample();
    _credibleWatchSecondsAtSourceOpen = _credibleWatchSeconds;
    _activeSourceHasZeroClockMetadata = false;
    _activeSourceVerifiedForSession = false;
    _lastVerifiedConfidenceUrl = null;
    _verifiedConfidenceMilestone = 0;
    _clearControllerErrorGrace();
    final attemptedEngine = engineOverride ?? _engineForSource(source);
    final initializeTimeout = _sourceInitializeTimeout(source, attemptedEngine);
    final strictManualLibVlc =
        attemptedEngine == _NativePlaybackEngine.libvlc &&
        _manualLibVlcStrictForSource(source);
    final manualLibVlcNoProofOpensForSource =
        _manualLibVlcNoProofOpensByUrl[source.url] ?? 0;
    if (strictManualLibVlc &&
        manualLibVlcNoProofOpensForSource >=
            _manualLibVlcSameSourceOpenWithoutProofLimit) {
      _lastOpenFailureMessage = 'libVLC could not open the available source.';
      DiagnosticLog.add(
        'native libvlc source circuit opened provider=${source.providerId} reason=visual_proof_missing sourceAttempts=$manualLibVlcNoProofOpensForSource sourceLimit=$_manualLibVlcSameSourceOpenWithoutProofLimit routeAttempts=$_manualLibVlcOpensWithoutProof routeLimit=$_manualLibVlcRouteOpenWithoutProofLimit',
      );
      return false;
    }
    if (strictManualLibVlc &&
        _manualLibVlcOpensWithoutProof >=
            _manualLibVlcRouteOpenWithoutProofLimit) {
      _lastOpenFailureMessage = 'libVLC could not open the available sources.';
      _libvlcUnavailableForSession = true;
      DiagnosticLog.add(
        'native libvlc route circuit opened provider=${source.providerId} reason=visual_proof_missing attempts=$_manualLibVlcOpensWithoutProof limit=$_manualLibVlcRouteOpenWithoutProofLimit',
      );
      return false;
    }
    if (strictManualLibVlc) {
      _manualLibVlcOpensWithoutProof += 1;
      _manualLibVlcNoProofOpensByUrl[source.url] =
          manualLibVlcNoProofOpensForSource + 1;
      DiagnosticLog.add(
        'native libvlc route open attempt provider=${source.providerId} proof=missing sourceAttempt=${manualLibVlcNoProofOpensForSource + 1} sourceLimit=$_manualLibVlcSameSourceOpenWithoutProofLimit routeAttempt=$_manualLibVlcOpensWithoutProof routeLimit=$_manualLibVlcRouteOpenWithoutProofLimit',
      );
    }
    try {
      DiagnosticLog.add(
        'native open provider=${source.providerId} sourceClass=${source.sourceClass.wireName} type=${source.type ?? 'unknown'} engine=${attemptedEngine.id} profile=${_sourceDiagnosticProfile(source)} url=[hidden]',
      );
      final openingStatus = statusMessage ?? _openStatusFor(source.providerId);
      _logPlaybackStatus(openingStatus, reason: 'open_source');
      _activeSource = source;
      setState(() {
        _loading = true;
        _playbackWaitMessage = null;
        _playbackWaitMessagePausedPlayback = false;
        _nativeProvidersExhausted = false;
        if (source.subtitles.isNotEmpty && _subtitles.isEmpty) {
          _subtitles = source.subtitles;
        }
        _statusMessage = openingStatus;
      });
      DiagnosticLog.add(
        'native engine selected engine=${attemptedEngine.id} provider=${source.providerId}',
      );
      if (attemptedEngine == _NativePlaybackEngine.libvlc) {
        final profile = _libVlcProfileForSource(source);
        await DiagnosticLog.markNativeEngineActive(
          engineId: attemptedEngine.id,
          reason: 'open_source',
        );
        DiagnosticLog.add(
          'native libvlc config provider=${source.providerId} profile=${profile.id} hwAcc=${profile.hwAcc.name} networkCaching=${profile.networkCachingMs}',
        );
      }
      var startPosition = resumePosition;
      final relayResumePosition =
          startPosition ??
          _libVlcRelayPreferredResumePosition(source, attemptedEngine);
      final relayResumeAwaitingPrompt =
          startPosition == null &&
          relayResumePosition > Duration.zero &&
          !_resumePromptHandled &&
          AppState.playerBehaviorSettings.value.startBehavior == 'ask';
      if (startPosition == null &&
          relayResumePosition > Duration.zero &&
          !relayResumeAwaitingPrompt) {
        startPosition = relayResumePosition;
      }
      final controllerSource = await _controllerSourceFor(
        source,
        attemptedEngine,
        resumePosition: relayResumePosition,
      );
      p2pLocalStreamReady = source.sourceClass == PlaybackSourceClass.p2p;
      final media3NativeEnabled = !_media3NativeFallbackUrls.contains(
        source.url,
      );
      if (attemptedEngine == _NativePlaybackEngine.exoplayer &&
          !media3NativeEnabled &&
          defaultTargetPlatform == TargetPlatform.android &&
          AppState.playerBehaviorSettings.value.media3NativeExoEnabled) {
        DiagnosticLog.add(
          'native media3 surface fallback active provider=${source.providerId} reason=previous_platform_view_failure',
        );
      }
      final controller = _NativePlaybackController.network(
        engine: attemptedEngine,
        source: controllerSource,
        liveMode: widget.liveMode,
        exoViewType: _exoVideoViewTypeFor(source),
        libVlcProfile: attemptedEngine == _NativePlaybackEngine.libvlc
            ? _libVlcProfileForSource(source)
            : null,
        media3NativeEnabled: media3NativeEnabled,
      );
      _controller = controller;
      controller.addListener(_handleControllerUpdate);
      if (controller.requiresPlatformViewWarmup && mounted) {
        // Native platform-view engines initialize from their Android view; make
        // sure the view is inserted before waiting for the controller.
        setState(() {});
      }
      _openingSource = true;
      final openingToken = ++_openingSourceToken;
      _startOpeningGuard(
        source,
        openingToken,
        initializeTimeout + const Duration(seconds: 4),
      );
      if (controller.requiresPlatformViewWarmup) {
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      final controllerInitializeTimeout = _controllerInitializeTimeout(
        source,
        controllerSource,
        attemptedEngine,
        initializeTimeout,
      );
      await controller.initialize(timeout: controllerInitializeTimeout);
      _openingGuardTimer?.cancel();
      if (!mounted ||
          _playerClosing ||
          openingToken != _openingSourceToken ||
          _controller != controller) {
        _openingSource = false;
        controller.removeListener(_handleControllerUpdate);
        await controller.dispose();
        return false;
      }
      _openingSource = false;
      final decodedSize = controller.size;
      final viewType = controller.videoViewType?.name ?? 'native';
      DiagnosticLog.add(
        'native initialized provider=${source.providerId} sourceClass=${source.sourceClass.wireName} engine=${attemptedEngine.id} view=$viewType elapsed=${openStopwatch.elapsedMilliseconds}ms duration=${controller.duration.inSeconds}s size=${decodedSize.width.toStringAsFixed(0)}x${decodedSize.height.toStringAsFixed(0)} aspect=${controller.aspectRatio.toStringAsFixed(3)} fit=${_fitMode.name}',
      );
      DiagnosticLog.add(
        'native engine profile provider=${source.providerId} engine=${attemptedEngine.id} ${controller.diagnosticProfile}',
      );
      if (await _rejectShortVodPlaceholderSource(
        source,
        controller,
        engine: attemptedEngine,
        startupMs: openStopwatch.elapsedMilliseconds,
      )) {
        return false;
      }
      DiagnosticLog.viewTiming(
        surface: 'native_player',
        state: 'player_ready',
        elapsed: openStopwatch.elapsed,
        sourceClassBucket: source.sourceClass.wireName,
        mediaKind: widget.liveMode ? 'live_tv' : 'vod',
        itemCount: widget.sources.length,
      );
      final resumePromptCanOpen = _resumePromptCanOpenForController(controller);
      final libVlcRelayResumePromptDeferred =
          relayResumeAwaitingPrompt &&
          !resumePromptCanOpen &&
          attemptedEngine == _NativePlaybackEngine.libvlc &&
          _manualLibVlcConfigured &&
          source.sourceClass == PlaybackSourceClass.direct &&
          _isHlsSource(source) &&
          source.headers.isNotEmpty &&
          relayResumePosition > Duration.zero;
      if (startPosition == null && libVlcRelayResumePromptDeferred) {
        startPosition = relayResumePosition;
        DiagnosticLog.add(
          'native resume prompt deferred reason=libvlc_hls_zero_metadata provider=${source.providerId}',
        );
      }
      if (startPosition == null &&
          resumePromptCanOpen &&
          _shouldRevealPlayerBeforeResumePrompt(controller.duration)) {
        setState(() {
          _loading = false;
          _statusMessage = null;
          _playbackWaitMessage = null;
          _playbackWaitMessagePausedPlayback = false;
        });
      }
      startPosition ??= resumePromptCanOpen
          ? await _resumePositionFor(controller.duration)
          : _automaticResumePositionFor(controller.duration);
      final resolvedStartPosition = startPosition ?? Duration.zero;
      final resumePromptWasDeclined =
          _resumePromptHandled && !_resumePromptAccepted;
      final shouldReopenLibVlcRelayForStartOver =
          attemptedEngine == _NativePlaybackEngine.libvlc &&
          _manualLibVlcConfigured &&
          source.sourceClass == PlaybackSourceClass.direct &&
          _isHlsSource(source) &&
          source.headers.isNotEmpty &&
          relayResumePosition > Duration.zero &&
          resolvedStartPosition <= Duration.zero &&
          (AppState.playerBehaviorSettings.value.startBehavior == 'restart' ||
              resumePromptWasDeclined);
      if (shouldReopenLibVlcRelayForStartOver) {
        DiagnosticLog.add(
          'native libvlc hls relay start-over reopen provider=${source.providerId} reason=post_load_prompt_decline',
        );
        return _openSource(
          source,
          resumePosition: Duration.zero,
          statusMessage: openingStatus,
          engineOverride: attemptedEngine,
        );
      }
      if (resolvedStartPosition <= Duration.zero ||
          attemptedEngine != _NativePlaybackEngine.libvlc) {
        _resumeProgressAnchorPosition = Duration.zero;
        _resumeProgressAnchorLogSecond = -1;
      }
      final libVlcVisualClockUnavailable =
          attemptedEngine == _NativePlaybackEngine.libvlc &&
          controller.size == Size.zero;
      final nativeClockUnavailable =
          controller.duration <= Duration.zero && controller.size == Size.zero;
      final playbackClockUnavailable =
          nativeClockUnavailable || libVlcVisualClockUnavailable;
      _activeSourceHasZeroClockMetadata =
          attemptedEngine == _NativePlaybackEngine.libvlc &&
          playbackClockUnavailable;
      if (source.sourceClass == PlaybackSourceClass.p2p &&
          resolvedStartPosition > Duration.zero &&
          !playbackClockUnavailable) {
        await _warmP2pResumeRange(
          controllerSource,
          source,
          attemptedEngine,
          resolvedStartPosition,
          controller.duration,
        );
      }
      if (resolvedStartPosition > Duration.zero && playbackClockUnavailable) {
        if (attemptedEngine == _NativePlaybackEngine.libvlc) {
          _resumeProgressAnchorPosition = resolvedStartPosition;
          _resumeProgressAnchorLogSecond = -1;
          _lastKnownPlaybackPosition = resolvedStartPosition;
        }
        DiagnosticLog.add(
          'native resume seek deferred provider=${source.providerId} engine=${attemptedEngine.id} position=${resolvedStartPosition.inSeconds}s reason=metadata clock unavailable',
        );
        _scheduleDeferredResumeSeek(
          resolvedStartPosition,
          source.providerId,
          controller,
        );
      } else if (resolvedStartPosition > Duration.zero) {
        await _seekToResumePosition(
          resolvedStartPosition,
          source.providerId,
          controller,
        );
      }
      await controller.setLooping(false);
      await controller.setVolume(_volumePreview);
      await controller.play();
      if ((_playbackSpeed - 1).abs() >= 0.001) {
        await controller.setPlaybackSpeed(_playbackSpeed);
      }
      _nativeWallClockStartedAt = DateTime.now();
      _lastSavedSecond = -1;
      _resetPlaybackIntegritySample();
      _failedSourceAttempts.remove(source.url);
      final progressItem = _progressItem;
      final playbackKey = _playbackKey;
      if (progressItem != null &&
          playbackKey != null &&
          controller.duration.inSeconds <= 0) {
        DiagnosticLog.add(
          'native continue watching start deferred reason=metadata duration unavailable provider=${source.providerId}',
        );
      }
      if (attemptedEngine == _NativePlaybackEngine.libvlc) {
        _pendingLibVlcOpenSuccessStartupMsByUrl[source.url] =
            openStopwatch.elapsedMilliseconds;
        DiagnosticLog.add(
          'native libvlc open pending visual proof provider=${source.providerId} position=${controller.position.inSeconds}s duration=${controller.duration.inSeconds}s size=${controller.size.width.toStringAsFixed(0)}x${controller.size.height.toStringAsFixed(0)}',
        );
        _maybeRecordDeferredLibVlcOpenSuccess(
          controller,
          reason: 'open_initialized_with_visual_proof',
        );
      } else {
        _recordNativeOpenSuccess(
          source,
          controller,
          engine: attemptedEngine,
          startupMs: openStopwatch.elapsedMilliseconds,
          reason: 'open_initialized',
        );
      }
      if (_isPublicIptvSource(source)) {
        _rememberVerifiedSource(controller, const Duration(seconds: 6));
      }
      _userPaused = false;
      if (!mounted) return false;
      final keepResumeProofOverlay =
          _resumeDialogAcceptedAwaitingProof &&
          attemptedEngine == _NativePlaybackEngine.libvlc;
      setState(() {
        _loading = false;
        _statusMessage = null;
        if (!keepResumeProofOverlay) {
          _playbackWaitMessage = null;
          _playbackWaitMessagePausedPlayback = false;
        }
      });
      if (!_recoveringFromStall) {
        _sameSourceRecoveryAttempts = 0;
      }
      _ensureSubtitlesLoading();
      _startStallWatchdog();
      _scheduleControlsHide();
      return true;
    } catch (error) {
      _openingGuardTimer?.cancel();
      _openingSource = false;
      if (_playerClosing || !mounted) {
        DiagnosticLog.add(
          'native open result ignored provider=${source.providerId} reason=player_closing error=${_safeDiagnosticError(error)}',
        );
        await _disposeCurrentController(
          awaitLibVlcRelease: true,
          saveProgress: false,
        );
        return false;
      }
      final timedOut = error is TimeoutException;
      final softVerifiedLibVlcAttempt = _isLibVlcSoftVerifiedCacheSource(
        source,
        attemptedEngine,
      );
      if (timedOut) {
        DiagnosticLog.add(
          'native source open timed out provider=${source.providerId} sourceClass=${source.sourceClass.wireName} engine=${attemptedEngine.id} timeout=${initializeTimeout.inSeconds}s elapsed=${openStopwatch.elapsedMilliseconds}ms quality=${_qualityLabel(source)}',
        );
        if (!softVerifiedLibVlcAttempt) {
          _recordRouteHlsOpenTimeout(source, attemptedEngine);
        }
      }
      DiagnosticLog.add(
        'native open failed provider=${source.providerId} sourceClass=${source.sourceClass.wireName} engine=${attemptedEngine.id} timedOut=$timedOut elapsed=${openStopwatch.elapsedMilliseconds}ms profile=${_sourceDiagnosticProfile(source)} error=${_safeDiagnosticError(error)}',
      );
      if (softVerifiedLibVlcAttempt) {
        DiagnosticLog.add(
          'native verified source cache soft-failed provider=${source.providerId} engine=${attemptedEngine.id} action=continue_full_search',
        );
      } else {
        _forgetVerifiedSource(source, 'open_failed');
        _recordSourceOpenFailure(source, error);
        _failedSourceAttempts[source.url] =
            (_failedSourceAttempts[source.url] ?? 0) + 1;
        AppState.recordNativeProviderFailure(
          mediaKey: _playbackKey,
          providerId: source.providerId,
          sourceCount: _activeSources.isEmpty
              ? null
              : visiblePlaybackSourceCount(_activeSources),
          updateHealth: _shouldUpdateProviderHealthFromPlaybackFailure,
        );
        _sendPlaybackFeedback(
          'open_failed',
          source: source,
          engine: attemptedEngine,
          startupMs: openStopwatch.elapsedMilliseconds,
        );
      }
      await _disposeCurrentController(
        awaitLibVlcRelease: true,
        saveProgress: false,
      );
      _activeSource = null;
      final p2pBridgeReadinessFailure =
          source.sourceClass == PlaybackSourceClass.p2p &&
          !p2pLocalStreamReady &&
          _isP2pBridgeReadinessFailure(error);
      final deadP2pCandidate =
          error is _P2pLocalStreamNotReadyException && error.deadSwarm;
      if (attemptedEngine == _NativePlaybackEngine.libvlc &&
          mounted &&
          !_playerClosing &&
          !softVerifiedLibVlcAttempt &&
          !p2pLocalStreamReady &&
          !p2pBridgeReadinessFailure) {
        final appWideLibVlcUnavailable = _isAppSessionLibVlcUnavailableError(
          error,
        );
        final libVlcUnavailableScope = appWideLibVlcUnavailable
            ? 'app-session'
            : 'route-session';
        _libvlcUnavailableForSession = true;
        if (appWideLibVlcUnavailable) {
          _libvlcUnavailableForAppSession = true;
        }
        DiagnosticLog.add(
          'native libvlc unavailable provider=${source.providerId} scope=$libVlcUnavailableScope',
        );
        _switchPlaybackEngineToAutoAfterLibVlcFailure(source.providerId);
      }
      if (attemptedEngine == _NativePlaybackEngine.libvlc) {
        await DiagnosticLog.clearNativeEngineActive(
          engineId: attemptedEngine.id,
          reason: 'open_failed',
        );
      }
      if (source.sourceClass == PlaybackSourceClass.p2p) {
        if (deadP2pCandidate) {
          _rememberColdP2pSourceForRoute(source, 'dead_swarm');
        }
        if (_isP2pBatteryDataPolicyFailure(error)) {
          _lastOpenFailureMessage =
              'Advanced P2P is paused by Battery & data settings.';
          DiagnosticLog.add(
            'native p2p source blocked provider=${source.providerId} action=battery_data_policy',
          );
        } else if (p2pBridgeReadinessFailure) {
          if (attemptedEngine == _NativePlaybackEngine.exoplayer) {
            _lastOpenFailureMessage =
                'P2P stream is still buffering. Trying another playback path.';
            DiagnosticLog.add(
              'native p2p exoplayer bridge readiness failed provider=${source.providerId} action=try_next_safe_path',
            );
          } else if (deadP2pCandidate) {
            _lastOpenFailureMessage =
                'P2P source has not found peers yet. Trying another source.';
            DiagnosticLog.add(
              'native p2p bridge dead candidate provider=${source.providerId} engine=${attemptedEngine.id} action=try_next_p2p_source',
            );
          } else if (attemptedEngine == _NativePlaybackEngine.libvlc) {
            _lastOpenFailureMessage =
                'P2P stream is still buffering. Trying another source.';
            DiagnosticLog.add(
              'native p2p libvlc bridge readiness failed provider=${source.providerId} action=try_next_p2p_source',
            );
          } else {
            _lastOpenFailureMessage =
                'P2P stream is still buffering. Try again in a moment.';
            _p2pBridgeBufferingForRoute = true;
            DiagnosticLog.add(
              'native p2p bridge paused for route reason=local_stream_not_ready',
            );
          }
        } else {
          _lastOpenFailureMessage =
              '${_engineLabel(attemptedEngine)} could not open the local P2P stream.';
          DiagnosticLog.add(
            'native p2p local stream engine failed provider=${source.providerId} engine=${attemptedEngine.id} bridgeReady=$p2pLocalStreamReady action=allow_next_engine',
          );
        }
      } else {
        _lastOpenFailureMessage = _isPublicIptvSource(source)
            ? _liveTvUnavailableMessage
            : '${_engineLabel(attemptedEngine)} could not open the available source.';
      }
      return false;
    }
  }

  bool _isP2pBridgeReadinessFailure(Object error) {
    if (error is TimeoutException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('p2p local stream is still buffering') ||
        message.contains('p2p bridge failed') ||
        message.contains('p2p runtime') ||
        message.contains('service unavailable') ||
        message.contains('http 503');
  }

  bool _isP2pBatteryDataPolicyFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('wi-fi only') ||
        message.contains('wifi only') ||
        message.contains('low battery') ||
        message.contains('battery & data');
  }

  void _switchPlaybackEngineToAutoAfterLibVlcFailure(String providerId) {
    if (AppState.playerBehaviorSettings.value.playbackEngine != 'auto') {
      return;
    }
    _temporaryAutoEngineRecovery = true;
    DiagnosticLog.add(
      'native playback engine temporary auto reason=libvlc_unavailable provider=$providerId',
    );
  }

  Duration _sourceInitializeTimeout(
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    if (_isPublicIptvSource(source)) {
      final seconds = switch (engine) {
        _NativePlaybackEngine.libvlc => 5,
        _NativePlaybackEngine.exoplayer => 8,
      };
      DiagnosticLog.add(
        'native source open timeout budget provider=${source.providerId} sourceClass=${source.sourceClass.wireName} engine=${engine.id} quality=${_qualityLabel(source)} timeout=${seconds}s reason=live-tv-directory',
      );
      return Duration(seconds: seconds);
    }
    var seconds = switch (engine) {
      _NativePlaybackEngine.libvlc => _libVlcOpenTimeout.inSeconds,
      _NativePlaybackEngine.exoplayer => _exoPlayerOpenTimeout.inSeconds,
    };
    if (source.providerId.startsWith('addon-')) seconds += 2;
    if (source.sourceClass == PlaybackSourceClass.debrid) seconds += 2;
    if (_qualityRank(_qualityLabel(source)) >= 2160) seconds += 2;
    final style = AppState.playerBehaviorSettings.value.retryStyle;
    seconds = switch (style) {
      'fast' => (seconds - 2).clamp(5, 18).toInt(),
      'patient' => (seconds + 3).clamp(8, 24).toInt(),
      _ => seconds.clamp(6, 20).toInt(),
    };
    if (_shouldUseResolvedDirectHlsOpenBudget(source, engine)) {
      seconds = switch (style) {
        'fast' => 6,
        'patient' => math.max(seconds, 12),
        _ => seconds,
      };
      DiagnosticLog.add(
        'native source open timeout budget provider=${source.providerId} sourceClass=${source.sourceClass.wireName} engine=${engine.id} quality=${_qualityLabel(source)} timeout=${seconds}s reason=resolved-direct-hls',
      );
      return Duration(seconds: seconds);
    }
    if (source.sourceClass == PlaybackSourceClass.p2p) {
      seconds = math.max(seconds, 60);
    }
    DiagnosticLog.add(
      'native source open timeout budget provider=${source.providerId} sourceClass=${source.sourceClass.wireName} engine=${engine.id} quality=${_qualityLabel(source)} timeout=${seconds}s',
    );
    return Duration(seconds: seconds);
  }

  bool _shouldUseResolvedDirectHlsOpenBudget(
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    return _limitToFirstQualityPass &&
        engine == _NativePlaybackEngine.exoplayer &&
        source.sourceClass == PlaybackSourceClass.direct &&
        !source.providerId.startsWith('addon-') &&
        _isHlsSource(source);
  }

  Duration _controllerInitializeTimeout(
    PlaybackSource originalSource,
    PlaybackSource controllerSource,
    _NativePlaybackEngine engine,
    Duration fallback,
  ) {
    if (originalSource.sourceClass == PlaybackSourceClass.p2p &&
        controllerSource.type == 'p2p-local') {
      final seconds = switch (engine) {
        _NativePlaybackEngine.exoplayer => 16,
        _NativePlaybackEngine.libvlc => 18,
      };
      DiagnosticLog.add(
        'native p2p controller attach budget provider=${originalSource.providerId} engine=${engine.id} timeout=${seconds}s',
      );
      return Duration(seconds: seconds);
    }
    return fallback;
  }

  Future<PlaybackSource> _controllerSourceFor(
    PlaybackSource source,
    _NativePlaybackEngine engine, {
    required Duration resumePosition,
  }) async {
    if (engine == _NativePlaybackEngine.libvlc &&
        _manualLibVlcConfigured &&
        source.sourceClass == PlaybackSourceClass.direct &&
        _isHlsSource(source) &&
        source.headers.isNotEmpty) {
      await _stopLibVlcHlsRelay('new_source');
      _resetLibVlcContinuousTsProof();
      final useContinuousTsRelay = resumePosition > Duration.zero;
      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(source.url),
        headers: source.headers,
        resumePosition: resumePosition,
        continuousTsMode: useContinuousTsRelay,
        onDuration: (duration) {
          if (_playerClosing || !mounted || duration <= Duration.zero) return;
          if (_activeSource?.url != source.url) return;
          _libVlcContinuousTsDurationAccepted = true;
          setState(() {
            _lastKnownPlaybackDuration = duration;
          });
          DiagnosticLog.add(
            'native libvlc hls relay duration accepted bucket=${_durationDiagnosticBucket(duration)}',
          );
          _maybeClearLibVlcContinuousTsWaitMessage(
            reason: 'libvlc_continuous_ts_duration',
          );
        },
        onContinuousTsProgress: (streamedSegments) {
          if (_playerClosing || !mounted) return;
          if (_activeSource?.url != source.url) return;
          _libVlcContinuousTsStreamedSegments = streamedSegments;
          _maybeClearLibVlcContinuousTsWaitMessage(
            reason: 'libvlc_continuous_ts_progress',
          );
        },
        onEvent: DiagnosticLog.add,
      );
      _libVlcHlsRelay = relay;
      DiagnosticLog.add(
        'native libvlc hls relay started scope=${useContinuousTsRelay ? 'continuous_ts' : 'playlist'} headers=${_headerCountBucket(source.headers.length)}',
      );
      return source.copyWith(
        url: relay.localUri.toString(),
        type: 'ts',
        headers: const {},
      );
    }
    if (source.sourceClass != PlaybackSourceClass.p2p) return source;
    await _guardP2pBatteryDataPolicy();
    final descriptor = P2pStreamDescriptor.fromSyntheticUrl(source.url);
    if (descriptor == null) {
      throw const FormatException('P2P source descriptor is missing.');
    }
    final cacheKey = _p2pLocalStreamCacheKey(source, descriptor);
    final cachedSource = _p2pLocalStreamSourcesByKey[cacheKey];
    if (cachedSource != null) {
      DiagnosticLog.add(
        'native p2p bridge local url reused provider=${source.providerId} ${descriptor.redactedDiagnostic} url=[localhost-hidden]',
      );
      final _P2pLocalStreamReady ready;
      try {
        ready = await _waitForP2pLocalStreamReady(
          Uri.parse(cachedSource.url),
          source,
          engine,
        );
      } on _P2pLocalStreamNotReadyException catch (error) {
        _p2pLocalStreamSourcesByKey.remove(cacheKey);
        _p2pLocalStreamTotalBytesByUrl.remove(cachedSource.url);
        if (error.deadSwarm) {
          _rememberColdP2pSourceForRoute(source, 'cached_dead_swarm');
        }
        DiagnosticLog.add(
          'native p2p bridge local url cache dropped provider=${source.providerId} reason=not_ready deadSwarm=${error.deadSwarm}',
        );
        rethrow;
      } catch (error) {
        _p2pLocalStreamSourcesByKey.remove(cacheKey);
        _p2pLocalStreamTotalBytesByUrl.remove(cachedSource.url);
        DiagnosticLog.add(
          'native p2p bridge local url cache dropped provider=${source.providerId} reason=readiness_exception error=${_safeDiagnosticError(error)}',
        );
        rethrow;
      }
      if (ready.totalBytes != null) {
        _p2pLocalStreamTotalBytesByUrl[cachedSource.url] = ready.totalBytes!;
      }
      _showP2pLocalStreamReadyStatus(source);
      return cachedSource;
    }
    DiagnosticLog.add(
      'native p2p bridge open requested provider=${source.providerId} ${descriptor.redactedDiagnostic}',
    );
    final Uri localUri;
    try {
      localUri = await P2pLocalStreamBridge.instance.open(descriptor);
    } on PlatformException catch (error) {
      final detail = _safeP2pBridgeDetail(
        '${error.code} ${error.message ?? 'no-message'}',
      );
      final message = '${error.code} ${error.message ?? ''}'.toLowerCase();
      if (error.code == 'p2p_open_failed' ||
          message.contains('p2p_open_failed') ||
          message.contains('p2p runtime')) {
        _p2pRuntimeUnavailableForRoute = true;
        _lastOpenFailureMessage = 'P2P bridge failed to start.';
        DiagnosticLog.add(
          'native p2p bridge disabled for route reason=runtime_unavailable detail=$detail',
        );
      } else {
        DiagnosticLog.add(
          'native p2p bridge open failed provider=${source.providerId} detail=$detail',
        );
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _statusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playback busy. Try again soon.')),
        );
      }
      rethrow;
    } catch (error) {
      final detail = _safeP2pBridgeDetail(error.toString());
      _p2pRuntimeUnavailableForRoute = true;
      _lastOpenFailureMessage = 'P2P bridge failed to start.';
      DiagnosticLog.add(
        'native p2p bridge disabled for route reason=open_exception detail=$detail',
      );
      rethrow;
    }
    DiagnosticLog.add(
      'native p2p bridge local url ready provider=${source.providerId} url=[localhost-hidden]',
    );
    final ready = await _waitForP2pLocalStreamReady(localUri, source, engine);
    _showP2pLocalStreamReadyStatus(source);
    final preparedSource = source.copyWith(
      url: localUri.toString(),
      type: 'p2p-local',
      sourceClass: PlaybackSourceClass.direct,
      headers: const <String, String>{},
    );
    if (ready.totalBytes != null) {
      _p2pLocalStreamTotalBytesByUrl[preparedSource.url] = ready.totalBytes!;
    }
    _p2pLocalStreamSourcesByKey[cacheKey] = preparedSource;
    return preparedSource;
  }

  Future<void> _guardP2pBatteryDataPolicy() async {
    final settings = _batteryDataSettings;
    if (settings.wifiOnlyAdvancedP2p) {
      final bucket = await P2pLocalStreamBridge.instance.networkBucket();
      DiagnosticLog.add('native p2p network policy bucket=$bucket');
      if (bucket != 'wifi' && bucket != 'ethernet') {
        _p2pBridgeBufferingForRoute = true;
        _lastOpenFailureMessage =
            'Advanced P2P is paused by Battery & data settings.';
        DiagnosticLog.add(
          'native p2p bridge blocked reason=wifi_only bucket=$bucket',
        );
        throw StateError('Advanced P2P is set to Wi-Fi only.');
      }
    }
    if (!settings.stopP2pOnLowBattery) return;
    await DiagnosticLog.recordBatterySnapshot('p2p_policy_check');
    final level = DiagnosticLog.latestBatteryPercent;
    if (!DiagnosticLog.batteryEvidenceAvailable || level == null) return;
    if (DiagnosticLog.isCharging) return;
    if (level > settings.lowBatteryThresholdPercent) return;
    _p2pBridgeBufferingForRoute = true;
    _lastOpenFailureMessage =
        'Advanced P2P is paused by Battery & data settings.';
    DiagnosticLog.add(
      'native p2p bridge blocked reason=low_battery level=$level threshold=${settings.lowBatteryThresholdPercent}',
    );
    throw StateError('Advanced P2P is paused on low battery.');
  }

  String _p2pLocalStreamCacheKey(
    PlaybackSource source,
    P2pStreamDescriptor descriptor,
  ) {
    return '${source.providerId}|${descriptor.infoHash}|${descriptor.fileIdx ?? 'auto'}';
  }

  String? _p2pSourceRouteKey(PlaybackSource source) {
    final descriptor = P2pStreamDescriptor.fromSyntheticUrl(source.url);
    if (descriptor == null) return null;
    return _p2pLocalStreamCacheKey(source, descriptor);
  }

  bool _shouldSkipColdP2pSourceForRoute(PlaybackSource source) {
    if (source.sourceClass != PlaybackSourceClass.p2p) return false;
    final key = _p2pSourceRouteKey(source);
    return key != null && _coldP2pSourceKeysForRoute.contains(key);
  }

  void _rememberColdP2pSourceForRoute(PlaybackSource source, String reason) {
    final key = _p2pSourceRouteKey(source);
    if (key == null || !_coldP2pSourceKeysForRoute.add(key)) return;
    DiagnosticLog.add(
      'native p2p source marked cold for route provider=${source.providerId} reason=$reason profile=${_sourceDiagnosticProfile(source)}',
    );
  }

  Future<_P2pLocalStreamReady> _waitForP2pLocalStreamReady(
    Uri localUri,
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    return _waitForP2pLocalStreamRangeReady(
      localUri,
      source,
      engine: engine,
      rangeHeader: 'bytes=0-1',
      label: 'preflight',
    );
  }

  Future<_P2pLocalStreamReady> _waitForP2pLocalStreamRangeReady(
    Uri localUri,
    PlaybackSource source, {
    required _NativePlaybackEngine engine,
    required String rangeHeader,
    required String label,
  }) async {
    final waitLimit = label == 'resume_warm'
        ? const Duration(seconds: 5)
        : _p2pPreflightWaitLimit(source, engine);
    final stopwatch = Stopwatch()..start();
    var attempts = 0;
    var lastBufferingDetail = '';
    var abandonedDeadSwarm = false;
    while (stopwatch.elapsed < waitLimit) {
      if (!mounted || _playerClosing) {
        DiagnosticLog.add(
          'native p2p bridge $label stopped provider=${source.providerId} attempts=$attempts elapsed=${stopwatch.elapsedMilliseconds}ms reason=route_closing',
        );
        throw _P2pLocalStreamNotReadyException(deadSwarm: false);
      }
      attempts += 1;
      try {
        final response = await http
            .get(localUri, headers: <String, String>{'Range': rangeHeader})
            .timeout(const Duration(milliseconds: 900));
        if (response.statusCode == 200 || response.statusCode == 206) {
          final bufferedBytes =
              response.headers['x-juicr-p2p-buffered-bytes'] ?? 'unknown';
          final firstPieces =
              response.headers['x-juicr-p2p-first-pieces'] ?? 'unknown';
          final rangeStart =
              response.headers['x-juicr-p2p-range-start'] ?? 'unknown';
          final totalBytes = _p2pTotalBytesFromContentRange(
            response.headers['content-range'],
          );
          if (!_p2pRangeHasReadablePieces(
            label: label,
            firstPieces: firstPieces,
            rangeStart: rangeStart,
            bufferedBytes: bufferedBytes,
          )) {
            final detail =
                'status=${response.statusCode} bufferedBytes=$bufferedBytes firstPieces=$firstPieces rangeStart=$rangeStart totalBytes=${totalBytes ?? 'unknown'}';
            if (detail != lastBufferingDetail ||
                attempts == 1 ||
                attempts % 5 == 0) {
              lastBufferingDetail = detail;
              _updateP2pWarmupStatus(
                source: source,
                detail: detail,
                label: label,
              );
              DiagnosticLog.add(
                'native p2p bridge $label waiting provider=${source.providerId} attempts=$attempts elapsed=${stopwatch.elapsedMilliseconds}ms reason=pieces_not_ready detail=$detail',
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 450));
            continue;
          }
          DiagnosticLog.add(
            'native p2p bridge $label ready provider=${source.providerId} attempts=$attempts elapsed=${stopwatch.elapsedMilliseconds}ms status=${response.statusCode} bufferedBytes=$bufferedBytes firstPieces=$firstPieces rangeStart=$rangeStart totalBytes=${totalBytes ?? 'unknown'}',
          );
          return _P2pLocalStreamReady(totalBytes: totalBytes);
        }
        if (response.statusCode != 503) {
          throw StateError('P2P bridge returned HTTP ${response.statusCode}.');
        }
        final detail = _safeP2pBridgeDetail(response.body);
        if (_shouldAbandonDeadP2pPreflight(
          source: source,
          label: label,
          detail: detail,
          elapsed: stopwatch.elapsed,
          waitLimit: waitLimit,
        )) {
          DiagnosticLog.add(
            'native p2p bridge $label abandoned provider=${source.providerId} attempts=$attempts elapsed=${stopwatch.elapsedMilliseconds}ms reason=dead_swarm detail=$detail',
          );
          abandonedDeadSwarm = true;
          break;
        }
        if (_shouldAbandonWeakP2pPreflight(
          source: source,
          label: label,
          detail: detail,
          elapsed: stopwatch.elapsed,
          waitLimit: waitLimit,
        )) {
          DiagnosticLog.add(
            'native p2p bridge $label abandoned provider=${source.providerId} attempts=$attempts elapsed=${stopwatch.elapsedMilliseconds}ms reason=weak_swarm detail=$detail',
          );
          abandonedDeadSwarm = true;
          break;
        }
        if (detail != lastBufferingDetail ||
            attempts == 1 ||
            attempts % 5 == 0) {
          lastBufferingDetail = detail;
          _updateP2pWarmupStatus(source: source, detail: detail, label: label);
          DiagnosticLog.add(
            'native p2p bridge $label buffering provider=${source.providerId} attempts=$attempts elapsed=${stopwatch.elapsedMilliseconds}ms detail=$detail',
          );
        }
      } catch (error) {
        if (error is TimeoutException) {
          if (_shouldAbandonDeadP2pPreflight(
            source: source,
            label: label,
            detail: lastBufferingDetail,
            elapsed: stopwatch.elapsed,
            waitLimit: waitLimit,
          )) {
            DiagnosticLog.add(
              'native p2p bridge $label abandoned provider=${source.providerId} attempts=$attempts elapsed=${stopwatch.elapsedMilliseconds}ms reason=dead_swarm_timeout detail=$lastBufferingDetail',
            );
            abandonedDeadSwarm = true;
            break;
          }
          if (_shouldAbandonWeakP2pPreflight(
            source: source,
            label: label,
            detail: lastBufferingDetail,
            elapsed: stopwatch.elapsed,
            waitLimit: waitLimit,
          )) {
            DiagnosticLog.add(
              'native p2p bridge $label abandoned provider=${source.providerId} attempts=$attempts elapsed=${stopwatch.elapsedMilliseconds}ms reason=weak_swarm_timeout detail=$lastBufferingDetail',
            );
            abandonedDeadSwarm = true;
            break;
          }
        } else {
          DiagnosticLog.add(
            'native p2p bridge $label pending provider=${source.providerId} attempts=$attempts elapsed=${stopwatch.elapsedMilliseconds}ms error=${_safeDiagnosticError(error)}',
          );
        }
      }
      if (abandonedDeadSwarm) break;
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }
    final finalDeadSwarm = _isDeadP2pPreflightDetail(lastBufferingDetail);
    DiagnosticLog.add(
      'native p2p bridge $label not ready provider=${source.providerId} attempts=$attempts elapsed=${stopwatch.elapsedMilliseconds}ms wait=${waitLimit.inSeconds}s detail=${lastBufferingDetail.isEmpty ? 'none' : lastBufferingDetail}',
    );
    throw _P2pLocalStreamNotReadyException(
      deadSwarm: abandonedDeadSwarm || finalDeadSwarm,
    );
  }

  Duration _p2pPreflightWaitLimit(
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    if (engine != _NativePlaybackEngine.libvlc) {
      final qualityRank = _qualityRank(_qualityLabel(source));
      final noTrackers = _p2pTrackerCount(source) == 0;
      final seconds = noTrackers
          ? (qualityRank >= 2160 ? 24 : 30)
          : (qualityRank >= 2160 ? 30 : 36);
      DiagnosticLog.add(
        'native p2p bridge preflight budget provider=${source.providerId} engine=${engine.id} quality=${_qualityLabel(source)} wait=${seconds}s reason=adaptive_p2p_candidate_ladder',
      );
      return Duration(seconds: seconds);
    }
    final qualityRank = _qualityRank(_qualityLabel(source));
    final seconds = qualityRank >= 2160 ? 24 : 36;
    DiagnosticLog.add(
      'native p2p bridge preflight budget provider=${source.providerId} engine=${engine.id} quality=${_qualityLabel(source)} wait=${seconds}s reason=libvlc_candidate_ladder',
    );
    return Duration(seconds: seconds);
  }

  bool _p2pRangeHasReadablePieces({
    required String label,
    required String firstPieces,
    required String rangeStart,
    required String bufferedBytes,
  }) {
    if (label != 'preflight') return true;
    if (rangeStart != '0') return true;
    final readyPieces = _p2pReadyPieceCount(firstPieces);
    if (readyPieces == null) return false;
    final buffered = int.tryParse(bufferedBytes);
    final requiredPieces = _p2pRequiredStartupPieceCount(
      firstPieces,
      bufferedBytes,
    );
    return readyPieces >= requiredPieces &&
        (buffered == null || buffered >= 2 * 1024 * 1024);
  }

  int? _p2pReadyPieceCount(String firstPieces) {
    final value = firstPieces.split('/').first.trim();
    if (value.isEmpty || value == 'unknown') return null;
    return int.tryParse(value);
  }

  int _p2pRequiredStartupPieceCount(String firstPieces, String bufferedBytes) {
    final parts = firstPieces.split('/');
    final total = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;
    if (total == null || total <= 0) return 2;
    final readyPieces = _p2pReadyPieceCount(firstPieces) ?? 0;
    final buffered = int.tryParse(bufferedBytes) ?? 0;
    if (readyPieces >= 1 && buffered >= _p2pSubstantialStartupBufferBytes) {
      return 1;
    }
    return math.min(total, 2);
  }

  bool _shouldAbandonDeadP2pPreflight({
    required PlaybackSource source,
    required String label,
    required String detail,
    required Duration elapsed,
    required Duration waitLimit,
  }) {
    if (label != 'preflight') {
      return false;
    }
    final metadataKnown = _p2pBridgeDetailBool(detail, 'metadata') == true;
    if (metadataKnown) return false;
    final noTrackers = _p2pTrackerCount(source) == 0;
    if (noTrackers &&
        elapsed >= const Duration(seconds: 6) &&
        _isDeadP2pPreflightDetail(detail)) {
      return true;
    }
    if (noTrackers &&
        elapsed >= const Duration(seconds: 10) &&
        _isNoMetadataWeakP2pPreflightDetail(detail)) {
      return true;
    }
    final minimumWait = noTrackers ? const Duration(seconds: 14) : waitLimit;
    if (elapsed < minimumWait) return false;
    return _isDeadP2pPreflightDetail(detail);
  }

  bool _isNoMetadataWeakP2pPreflightDetail(String detail) {
    if (detail.isEmpty) return false;
    final metadataKnown = _p2pBridgeDetailBool(detail, 'metadata') == true;
    if (metadataKnown) return false;
    final peers = _p2pBridgeDetailInt(detail, 'peers') ?? 0;
    final seeds = _p2pBridgeDetailInt(detail, 'seeds') ?? 0;
    final candidates = _p2pBridgeDetailInt(detail, 'candidates') ?? 0;
    final listPeers = _p2pBridgeDetailInt(detail, 'listPeers') ?? 0;
    final progressBytes = _p2pBridgeDetailInt(detail, 'fileProgressBytes') ?? 0;
    final readyPieces = _p2pBridgeDetailInt(detail, 'firstPiecesReady') ?? 0;
    if (progressBytes > 0 || readyPieces > 0) return false;
    final tinyNoSeedCloud = peers <= 1 && seeds == 0;
    return tinyNoSeedCloud && candidates <= 32 && listPeers <= 32;
  }

  bool _isDeadP2pPreflightDetail(String detail) {
    if (detail.isEmpty) return false;
    final metadataKnown = _p2pBridgeDetailBool(detail, 'metadata') == true;
    if (metadataKnown) return false;
    final peers = _p2pBridgeDetailInt(detail, 'peers') ?? 0;
    final seeds = _p2pBridgeDetailInt(detail, 'seeds') ?? 0;
    final candidates = _p2pBridgeDetailInt(detail, 'candidates') ?? 0;
    final listPeers = _p2pBridgeDetailInt(detail, 'listPeers') ?? 0;
    return peers == 0 && seeds == 0 && candidates == 0 && listPeers == 0;
  }

  bool _shouldAbandonWeakP2pPreflight({
    required PlaybackSource source,
    required String label,
    required String detail,
    required Duration elapsed,
    required Duration waitLimit,
  }) {
    if (label != 'preflight') return false;
    if (_p2pBridgeDetailBool(detail, 'metadata') != true) return false;
    final readyPieces = _p2pBridgeDetailInt(detail, 'firstPiecesReady') ?? 0;
    if (readyPieces > 0) return false;
    final peers = _p2pBridgeDetailInt(detail, 'peers') ?? 0;
    final seeds = _p2pBridgeDetailInt(detail, 'seeds') ?? 0;
    final candidates = _p2pBridgeDetailInt(detail, 'candidates') ?? 0;
    final progressBytes = _p2pBridgeDetailInt(detail, 'fileProgressBytes') ?? 0;
    if (progressBytes > 0) return false;
    final noTrackers = _p2pTrackerCount(source) == 0;
    final hasAvailablePeerSignal = seeds > 0 || peers > 0 || candidates > 32;
    if (hasAvailablePeerSignal && elapsed < waitLimit) return false;
    final lowHealth = peers + seeds <= 4 || candidates <= 4;
    final stagnantMetadata = peers + seeds <= 4 && candidates <= 16;
    if (stagnantMetadata && elapsed >= const Duration(seconds: 16)) {
      return true;
    }
    if (elapsed < const Duration(seconds: 14)) return false;
    if (noTrackers && elapsed < const Duration(seconds: 16)) return false;
    return lowHealth;
  }

  bool? _p2pBridgeDetailBool(String detail, String key) {
    final value = _p2pBridgeDetailValue(detail, key);
    if (value == null) return null;
    if (value == 'true') return true;
    if (value == 'false') return false;
    return null;
  }

  int? _p2pBridgeDetailInt(String detail, String key) {
    return int.tryParse(_p2pBridgeDetailValue(detail, key) ?? '');
  }

  String? _p2pBridgeDetailValue(String detail, String key) {
    final match = RegExp('(?:^| )$key=([^ ]+)').firstMatch(detail);
    return match?.group(1);
  }

  Future<void> _warmP2pResumeRange(
    PlaybackSource controllerSource,
    PlaybackSource originalSource,
    _NativePlaybackEngine engine,
    Duration position,
    Duration duration,
  ) async {
    final totalBytes = _p2pLocalStreamTotalBytesByUrl[controllerSource.url];
    if (totalBytes == null || totalBytes <= 0 || duration <= Duration.zero) {
      DiagnosticLog.add(
        'native p2p resume warm skipped provider=${originalSource.providerId} reason=missing_size position=${position.inSeconds}s',
      );
      return;
    }
    final localUri = Uri.tryParse(controllerSource.url);
    if (localUri == null || localUri.host != '127.0.0.1') return;
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    final startByte = (totalBytes * ratio).round().clamp(0, totalBytes - 1);
    DiagnosticLog.add(
      'native p2p resume warm requested provider=${originalSource.providerId} position=${position.inSeconds}s startByte=$startByte',
    );
    try {
      await _waitForP2pLocalStreamRangeReady(
        localUri,
        originalSource,
        engine: engine,
        rangeHeader: 'bytes=$startByte-',
        label: 'resume_warm',
      );
    } catch (error) {
      DiagnosticLog.add(
        'native p2p resume warm skipped provider=${originalSource.providerId} position=${position.inSeconds}s reason=range_not_ready error=${_safeDiagnosticError(error)}',
      );
    }
  }

  int? _p2pTotalBytesFromContentRange(String? value) {
    if (value == null || value.isEmpty) return null;
    final total = value.split('/').last.trim();
    if (total == '*' || total.isEmpty) return null;
    return int.tryParse(total);
  }

  String _safeP2pBridgeDetail(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return 'empty';
    final lower = normalized.toLowerCase();
    if (lower.contains('stage_native_shim_loader')) {
      return 'runtime_unavailable:native_library:native_shim_loader';
    }
    if (lower.contains('stage_swig_jni_loader')) {
      return 'runtime_unavailable:native_library:swig_jni_loader';
    }
    if (lower.contains('stage_native_version_probe')) {
      return 'runtime_unavailable:native_library:native_version_probe';
    }
    if (lower.contains('stage_session_manager')) {
      return 'runtime_unavailable:native_library:session_manager';
    }
    if (lower.contains('stage_settings_pack')) {
      return 'runtime_unavailable:native_library:settings_pack';
    }
    if (lower.contains('stage_sha1_hash')) {
      return 'runtime_unavailable:native_library:sha1_hash';
    }
    if (lower.contains('stage_announce_entry')) {
      return 'runtime_unavailable:native_library:announce_entry';
    }
    if (lower.contains('stage_priority')) {
      return 'runtime_unavailable:native_library:priority';
    }
    if (lower.contains('stage_torrent_flags')) {
      return 'runtime_unavailable:native_library:torrent_flags';
    }
    if (lower.contains('stage_torrent_handle')) {
      return 'runtime_unavailable:native_library:torrent_handle';
    }
    if (lower.contains('noclass') || lower.contains('classnotfound')) {
      return 'runtime_unavailable:missing_class';
    }
    if (lower.contains('swig_module_init')) {
      return 'runtime_unavailable:native_library:swig_module_init';
    }
    if (lower.contains('jni_init')) {
      return 'runtime_unavailable:native_library:jni_init';
    }
    if (lower.contains('jni_symbol')) {
      return 'runtime_unavailable:native_library:jni_symbol';
    }
    if (lower.contains('cxx_dependency')) {
      return 'runtime_unavailable:native_library:cxx_dependency';
    }
    if (lower.contains('jlibtorrent_dependency')) {
      return 'runtime_unavailable:native_library:jlibtorrent_dependency';
    }
    if (lower.contains('page_alignment')) {
      return 'runtime_unavailable:native_library:page_alignment';
    }
    if (lower.contains('dependency_not_found')) {
      return 'runtime_unavailable:native_library:dependency_not_found';
    }
    if (lower.contains('missing_symbol')) {
      return 'runtime_unavailable:native_library:missing_symbol';
    }
    if (lower.contains('dlopen_failed')) {
      return 'runtime_unavailable:native_library:dlopen_failed';
    }
    if (lower.contains('unsatisfiedlink') ||
        lower.contains('.so') ||
        lower.contains('native library')) {
      return 'runtime_unavailable:native_library';
    }
    if (lower.contains('p2p runtime is not available')) {
      return 'runtime_unavailable:unavailable';
    }
    if (normalized.length <= 640) return normalized;
    return '${normalized.substring(0, 640)}...';
  }

  Duration get _failureReadDelay {
    final settings = AppState.playerBehaviorSettings.value;
    final seconds = settings.experimentalControlsEnabled
        ? settings.failureReadSeconds
        : const PlayerBehaviorSettings().failureReadSeconds;
    return Duration(seconds: seconds);
  }

  Duration get _failureReadDelayForRoute {
    if (_limitToFirstQualityPass) return const Duration(milliseconds: 900);
    return _failureReadDelay;
  }

  Duration get _libVlcOpenTimeout {
    final settings = AppState.playerBehaviorSettings.value;
    final seconds = settings.experimentalControlsEnabled
        ? settings.libVlcOpenTimeoutSeconds
        : const PlayerBehaviorSettings().libVlcOpenTimeoutSeconds;
    return Duration(seconds: seconds);
  }

  Duration get _exoPlayerOpenTimeout {
    final settings = AppState.playerBehaviorSettings.value;
    final seconds = settings.experimentalControlsEnabled
        ? settings.exoPlayerOpenTimeoutSeconds
        : const PlayerBehaviorSettings().exoPlayerOpenTimeoutSeconds;
    return Duration(seconds: seconds);
  }

  Duration get _providerResolveTimeout {
    final settings = AppState.playerBehaviorSettings.value;
    final seconds = settings.experimentalControlsEnabled
        ? settings.providerResolveTimeoutSeconds
        : const PlayerBehaviorSettings().providerResolveTimeoutSeconds;
    return Duration(seconds: seconds);
  }

  Duration _providerResolveTimeoutFor(String providerId) {
    final base = _providerResolveTimeout;
    final status = AppState.nativeProviderHealthFor(providerId);
    var seconds = switch (status) {
      NativeProviderHealthStatus.failing ||
      NativeProviderHealthStatus.noSource => base.inSeconds,
      NativeProviderHealthStatus.limited => base.inSeconds + 3,
      NativeProviderHealthStatus.slow => base.inSeconds + 5,
      NativeProviderHealthStatus.ready ||
      NativeProviderHealthStatus.untested ||
      NativeProviderHealthStatus.protected ||
      NativeProviderHealthStatus.checkedNoSample => base.inSeconds,
    };
    if (providerId.startsWith('addon-')) seconds += 4;
    if (_limitToFirstQualityPass && !providerId.startsWith('addon-')) {
      seconds = math.min(seconds, 6);
    }
    final minimum = _limitToFirstQualityPass && !providerId.startsWith('addon-')
        ? 4
        : base.inSeconds;
    return Duration(seconds: seconds.clamp(minimum, 30).toInt());
  }

  int get _providerWarmupCount {
    final settings = AppState.playerBehaviorSettings.value;
    return settings.experimentalControlsEnabled
        ? settings.providerWarmupCount
        : const PlayerBehaviorSettings().providerWarmupCount;
  }

  bool get _zeroClockSkipEnabled {
    final settings = AppState.playerBehaviorSettings.value;
    return settings.experimentalControlsEnabled
        ? settings.zeroClockSkipEnabled
        : const PlayerBehaviorSettings().zeroClockSkipEnabled;
  }

  bool get _progressFallbackClockEnabled {
    final settings = AppState.playerBehaviorSettings.value;
    return settings.experimentalControlsEnabled
        ? settings.progressFallbackClockEnabled
        : const PlayerBehaviorSettings().progressFallbackClockEnabled;
  }

  Duration get _resumeSeekRetryWindow {
    final settings = AppState.playerBehaviorSettings.value;
    final seconds = settings.experimentalControlsEnabled
        ? settings.resumeSeekRetrySeconds
        : const PlayerBehaviorSettings().resumeSeekRetrySeconds;
    return Duration(seconds: seconds);
  }

  Duration get _blackVideoWatchdogWindow {
    final settings = AppState.playerBehaviorSettings.value;
    final seconds = settings.experimentalControlsEnabled
        ? settings.blackVideoWatchdogSeconds
        : const PlayerBehaviorSettings().blackVideoWatchdogSeconds;
    return Duration(seconds: seconds);
  }

  Duration get _libVlcWarmupGrace {
    final settings = AppState.playerBehaviorSettings.value;
    final seconds = settings.experimentalControlsEnabled
        ? settings.libVlcWarmupSeconds
        : const PlayerBehaviorSettings().libVlcWarmupSeconds;
    return Duration(seconds: seconds);
  }

  Duration get _libVlcContinuousTsVisualGrace {
    final settings = AppState.playerBehaviorSettings.value;
    final seconds = settings.experimentalControlsEnabled
        ? settings.libVlcContinuousTsVisualGraceSeconds
        : const PlayerBehaviorSettings().libVlcContinuousTsVisualGraceSeconds;
    return Duration(seconds: seconds);
  }

  bool get _libVlcContinuousTsActive {
    return _manualLibVlcConfigured && _libVlcHlsRelay != null;
  }

  bool get _libVlcContinuousTsRelayProofReady {
    return _libVlcContinuousTsActive &&
        _libVlcContinuousTsDurationAccepted &&
        _libVlcContinuousTsStreamedSegments > 0;
  }

  bool _libVlcContinuousTsNoVisualRelayStalled(
    _NativePlaybackController controller,
    Duration? elapsed,
  ) {
    if (controller.engine != _NativePlaybackEngine.libvlc) return false;
    if (!_libVlcContinuousTsActive) return false;
    if (elapsed == null || elapsed < _libVlcWarmupGrace) return false;
    if (controller.position >= const Duration(seconds: 1)) return false;
    if (controller.size != Size.zero) return false;
    if (!_libVlcContinuousTsRelayProofReady &&
        controller.duration <= Duration.zero) {
      return false;
    }
    return AppState.playerBehaviorSettings.value.autoSwitchOnStall;
  }

  Duration get _libVlcReleaseSettle {
    final settings = AppState.playerBehaviorSettings.value;
    final milliseconds = settings.experimentalControlsEnabled
        ? settings.libVlcReleaseSettleMs
        : const PlayerBehaviorSettings().libVlcReleaseSettleMs;
    return Duration(milliseconds: milliseconds);
  }

  Duration get _stallWatchdogInterval {
    final settings = AppState.playerBehaviorSettings.value;
    final seconds = settings.experimentalControlsEnabled
        ? settings.stallWatchdogSeconds
        : const PlayerBehaviorSettings().stallWatchdogSeconds;
    return Duration(seconds: seconds);
  }

  int _bufferingRecoveryTickLimitForSource(PlaybackSource? source) {
    if (source == null) return 3;
    if (_isLiveTvMode || _isPublicIptvSource(source)) return 8;
    if (source.sourceClass == PlaybackSourceClass.p2p) return 10;
    return 3;
  }

  _NativePlaybackEngine _engineForSource(PlaybackSource source) {
    final configured = _effectivePlaybackEngine;
    if (configured == 'libvlc') return _NativePlaybackEngine.libvlc;
    if (configured == 'exoplayer') return _NativePlaybackEngine.exoplayer;
    if (configured == 'ksplayer') {
      DiagnosticLog.add(
        'native engine fallback requested=ksplayer reason=platform engine unavailable',
      );
      return _NativePlaybackEngine.exoplayer;
    }
    final type = (source.type ?? '').toLowerCase();
    final url = source.url.toLowerCase();
    if (type == 'dash' || url.contains('.mpd')) {
      return _NativePlaybackEngine.exoplayer;
    }
    if (type == 'hls' || url.contains('.m3u8')) {
      return _NativePlaybackEngine.exoplayer;
    }
    return _NativePlaybackEngine.exoplayer;
  }

  List<PlaybackSource> _prepareProviderSourcesForPlaybackPass(
    List<PlaybackSource> sources, {
    required _QualityPass qualityPass,
    required _NativePlaybackEngine engine,
    required List<_NativePlaybackEngine> enginePasses,
  }) {
    var prepared = _prioritizePreferredQuality(sources);
    prepared = _deprioritizeFailedSources(prepared);
    prepared = _filterSourcesForQualityPass(prepared, qualityPass);
    prepared = _filterRiskyP2pSourcesForQualityPass(prepared, qualityPass);
    prepared = _limitBaselineP2pSmartStartSources(prepared, qualityPass);
    if (prepared.isEmpty) return prepared;
    return _rankSourcesForEnginePass(
      prepared,
      engine,
      enginePasses,
      qualityPass: qualityPass,
    );
  }

  List<PlaybackSource> _limitBaselineP2pSmartStartSources(
    List<PlaybackSource> sources,
    _QualityPass qualityPass,
  ) {
    const _baselineP2pSmartStartCandidateLimit = 4;
    if (sources.length <= _baselineP2pSmartStartCandidateLimit) {
      return sources;
    }
    final p2pConfig = _p2pPriorityConfigFromSettings();
    if (p2pConfig.enabled) return sources;
    if (!_isP2pOnlySourceRoute) return sources;
    if (qualityPass.isHighestAvailable) return sources;
    final ranked = rankedNativePlaybackSources(
      sources,
      sourceClassAllowed: AppState.playbackSourceClassAllowedForNative,
      p2pConfig: const P2pPriorityConfig(
        enabled: true,
        mode: p2pPriorityModeSmartStart,
        resultsPerQuality: 2,
        avoidRiskyFormats: true,
      ),
    );
    final limited = ranked
        .take(_baselineP2pSmartStartCandidateLimit)
        .toList(growable: false);
    if (limited.length >= sources.length) return sources;
    DiagnosticLog.add(
      'native source filter reason=baseline_p2p_smart_start sourceClass=p2p skipped=${sources.length - limited.length} kept=${limited.length} ${_qualityDiagnosticContext(qualityPass)}',
    );
    return limited;
  }

  List<PlaybackSource> _filterRiskyP2pSourcesForQualityPass(
    List<PlaybackSource> sources,
    _QualityPass qualityPass,
  ) {
    if (sources.isEmpty) return sources;
    final p2pConfig = _p2pPriorityConfigFromSettings();
    if (!_shouldHonorAdvancedP2pRiskFilter(p2pConfig, qualityPass)) {
      return sources;
    }
    var skipped = 0;
    final filtered = <PlaybackSource>[];
    final riskFallbackCandidates = <PlaybackSource>[];
    for (final source in sources) {
      if (source.sourceClass != PlaybackSourceClass.p2p) {
        filtered.add(source);
        continue;
      }
      final riskRank = p2pPlaybackRiskRank(source, config: p2pConfig);
      if (riskRank > 0 || _looksHighEfficiencySource(source)) {
        skipped += 1;
        riskFallbackCandidates.add(source);
        continue;
      }
      filtered.add(source);
    }
    if (skipped <= 0) return sources;
    var fallbackKept = 0;
    if (filtered.length < _advancedP2pAvoidRiskSoftFallbackMinimum &&
        riskFallbackCandidates.isNotEmpty) {
      final rankedFallback = riskFallbackCandidates.toList(growable: false)
        ..sort((a, b) {
          final riskCompare = p2pPlaybackRiskRank(
            a,
            config: p2pConfig,
          ).compareTo(p2pPlaybackRiskRank(b, config: p2pConfig));
          if (riskCompare != 0) return riskCompare;
          return compareP2pSources(a, b, p2pConfig);
        });
      final needed = _advancedP2pAvoidRiskSoftFallbackMinimum - filtered.length;
      final fallback = rankedFallback.take(needed).toList(growable: false);
      fallbackKept = fallback.length;
      filtered.addAll(fallback);
    }
    DiagnosticLog.add(
      'native source filter reason=${fallbackKept > 0 ? 'advanced_p2p_avoid_risk_soft_fallback' : 'advanced_p2p_avoid_risk'} sourceClass=p2p skipped=$skipped kept=${filtered.length} fallbackKept=$fallbackKept ${_qualityDiagnosticContext(qualityPass)}',
    );
    return filtered;
  }

  bool _shouldHonorAdvancedP2pRiskFilter(
    P2pPriorityConfig p2pConfig,
    _QualityPass qualityPass,
  ) {
    if (!p2pConfig.enabled || !p2pConfig.avoidRiskyFormats) return false;
    if (_usingGlobalOverrides && _qualityPreferenceMode == 'higher') {
      return false;
    }
    if (qualityPass.isHighestAvailable) return false;
    final targetRank = qualityPass.target?.rank;
    if (targetRank != null && targetRank >= 2160) return false;
    return true;
  }

  List<PlaybackSource> _rankSourcesForEnginePass(
    List<PlaybackSource> sources,
    _NativePlaybackEngine engine,
    List<_NativePlaybackEngine> enginePasses, {
    required _QualityPass qualityPass,
  }) {
    if (sources.length < 2 ||
        !_shouldApplySourceCompatibilityLadder(
          engine,
          enginePasses,
          qualityPass,
        )) {
      return sources;
    }
    final originalIndexByUrl = <String, int>{};
    for (var index = 0; index < sources.length; index += 1) {
      originalIndexByUrl.putIfAbsent(sources[index].url, () => index);
    }
    final sorted = sources.toList(growable: false)
      ..sort((a, b) {
        final classCompare = _nativeSourceClassRank(
          a,
        ).compareTo(_nativeSourceClassRank(b));
        if (classCompare != 0) return classCompare;

        final failureCompare = (_failedSourceAttempts[a.url] ?? 0).compareTo(
          _failedSourceAttempts[b.url] ?? 0,
        );
        if (failureCompare != 0) return failureCompare;

        final compatibilityCompare = _sourceEngineCompatibilityRank(
          a,
          engine,
        ).compareTo(_sourceEngineCompatibilityRank(b, engine));
        if (compatibilityCompare != 0) return compatibilityCompare;

        return (originalIndexByUrl[a.url] ?? 0).compareTo(
          originalIndexByUrl[b.url] ?? 0,
        );
      });
    final changed = sources.asMap().entries.any(
      (entry) => sorted[entry.key].url != entry.value.url,
    );
    if (changed) {
      final reason = engine == _NativePlaybackEngine.exoplayer
          ? 'media3_compatibility_ladder'
          : 'advanced_source_avoid_risk_ladder';
      DiagnosticLog.add(
        'native source order adjusted reason=$reason engine=${engine.id} count=${sources.length} ${_qualityDiagnosticContext(qualityPass)}',
      );
    }
    _logRankedSourceOrderSnapshot(
      sorted,
      engine: engine,
      reason: changed ? 'adjusted' : 'unchanged',
      qualityPass: qualityPass,
    );
    return sorted;
  }

  void _logRankedSourceOrderSnapshot(
    List<PlaybackSource> sources, {
    required _NativePlaybackEngine engine,
    required String reason,
    required _QualityPass qualityPass,
  }) {
    if (sources.isEmpty) return;
    final entries = <String>[];
    for (var index = 0; index < sources.length && index < 6; index += 1) {
      final source = sources[index];
      entries.add(
        '#${index + 1}:${source.sourceClass.wireName}:rank=${_sourceEngineCompatibilityRank(source, engine)}:${_sourceDiagnosticProfile(source)}',
      );
    }
    final truncated = sources.length > entries.length ? ':truncated' : '';
    DiagnosticLog.add(
      'native source order snapshot reason=$reason engine=${engine.id} count=${sources.length}$truncated entries=${entries.join('|')} ${_qualityDiagnosticContext(qualityPass)}',
    );
  }

  bool _shouldApplySourceCompatibilityLadder(
    _NativePlaybackEngine engine,
    List<_NativePlaybackEngine> enginePasses,
    _QualityPass qualityPass,
  ) {
    return _shouldApplyMedia3CompatibilityLadder(engine, enginePasses) ||
        _shouldHonorAdvancedSourceRiskOrdering(qualityPass);
  }

  bool _shouldApplyMedia3CompatibilityLadder(
    _NativePlaybackEngine engine,
    List<_NativePlaybackEngine> enginePasses,
  ) {
    return engine == _NativePlaybackEngine.exoplayer;
  }

  bool _shouldHonorAdvancedSourceRiskOrdering(_QualityPass qualityPass) {
    return _shouldHonorAdvancedP2pRiskFilter(
      _p2pPriorityConfigFromSettings(),
      qualityPass,
    );
  }

  int _sourceEngineCompatibilityRank(
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    final descriptor = _sourceDiagnosticDescriptor(source);
    final container = _containerHintFor(source, descriptor);
    final video = _videoCodecHintFor(descriptor);
    final audio = _audioCodecHintFor(descriptor);
    final hdr = _hdrHintFor(descriptor);
    final strictDeviceCodec = engine == _NativePlaybackEngine.exoplayer;
    var rank = 0;
    if (container == 'hls' || container == 'dash') rank -= 3;
    if (container == 'mp4') rank -= 2;
    if (container == 'mkv') rank += strictDeviceCodec ? 4 : 2;
    if (container == 'webm' || container == 'avi') rank += 2;
    if (video == 'h264') rank -= 4;
    if (video == 'hevc') rank += strictDeviceCodec ? 5 : 3;
    if (video == 'av1' || video == 'vp9') rank += strictDeviceCodec ? 3 : 2;
    if (hdr == 'dolby-vision') {
      rank += strictDeviceCodec ? 6 : 4;
    } else if (hdr != 'sdr-or-unknown') {
      rank += 3;
    }
    if (audio == 'truehd' || audio == 'dts-hd' || audio == 'dts') {
      rank += strictDeviceCodec ? 4 : 2;
    }
    if (audio == 'eac3' || audio == 'ac3') rank += 1;
    if (_qualityRank(_qualityLabel(source)) >= 2160) rank += 3;
    return rank;
  }

  void _recordSourceOpenFailure(PlaybackSource source, Object error) {
    final message = error.toString().toLowerCase();
    final unsupportedByDevice =
        message.contains('no_exceeds_capabilities') ||
        message.contains('mediacodecvideorenderer error') ||
        message.contains('format_supported=no_exceeds_capabilities') ||
        message.contains('error_code_decoding_failed') ||
        message.contains('error_code_decoder_init_failed');
    final highEfficiencyError =
        message.contains('video/hevc') ||
        message.contains('hvc1') ||
        message.contains('x265') ||
        message.contains('hevc');
    if (!unsupportedByDevice ||
        (!highEfficiencyError && !_looksRiskyForMedia3(source))) {
      return;
    }
    if (_skipUnsupportedHighEfficiencyForSession) return;
    _skipUnsupportedHighEfficiencyForSession = true;
    DiagnosticLog.add(
      'native source capability learned provider=${source.providerId} action=skip high-efficiency sources for session',
    );
  }

  void _recordControllerRuntimeFailureHint(
    _NativePlaybackController controller, {
    required String reason,
  }) {
    if (controller.engine != _NativePlaybackEngine.exoplayer) return;
    final source = _activeSource;
    final error = controller.errorDescription;
    if (source == null || error == null || error.trim().isEmpty) return;
    DiagnosticLog.add(
      'native runtime failure hint provider=${source.providerId} engine=${controller.engine.id} reason=$reason',
    );
    _recordSourceOpenFailure(source, error);
  }

  bool _shouldSkipSourceForSession(
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    return engine == _NativePlaybackEngine.exoplayer &&
        _skipUnsupportedHighEfficiencyForSession &&
        _looksRiskyForMedia3(source);
  }

  bool _shouldSkipP2pSourceForEngine(
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    return engine == _NativePlaybackEngine.exoplayer &&
        source.sourceClass == PlaybackSourceClass.p2p &&
        p2pPlaybackRiskRank(source) >= 9 &&
        _looksHighEfficiencySource(source);
  }

  bool _nativePlaybackSupportsSourceClass(PlaybackSource source) {
    if (source.sourceClass == PlaybackSourceClass.p2p &&
        (_p2pRuntimeUnavailableForRoute || _p2pBridgeBufferingForRoute)) {
      return false;
    }
    return _nativeSourceClassIsPlayable(source);
  }

  void _recordNativeSourceClassSkip(PlaybackSource source) {
    final sourceClass = source.sourceClass.wireName;
    _nativeSourceClassSkipCounts[sourceClass] =
        (_nativeSourceClassSkipCounts[sourceClass] ?? 0) + 1;
  }

  String _nativeSourceClassSkipSummary() {
    if (_nativeSourceClassSkipCounts.isEmpty) return 'none';
    const order = <String>['external', 'p2p', 'unsupported'];
    final parts = <String>[];
    for (final sourceClass in order) {
      final count = _nativeSourceClassSkipCounts[sourceClass] ?? 0;
      if (count <= 0) continue;
      final label = switch (sourceClass) {
        'external' => 'external',
        'p2p' => 'P2P',
        _ => 'unsupported',
      };
      parts.add('$count $label');
    }
    return parts.isEmpty ? 'none' : parts.join(', ');
  }

  bool _looksHighEfficiencySource(PlaybackSource source) {
    final descriptor = _sourceDiagnosticDescriptor(source);
    if (descriptor.contains('hevc') ||
        descriptor.contains('h265') ||
        descriptor.contains('h.265') ||
        descriptor.contains('x265') ||
        descriptor.contains('hvc1') ||
        descriptor.contains('10bit') ||
        descriptor.contains('10-bit')) {
      return true;
    }
    return descriptor.contains('2160p') ||
        descriptor.contains('4k') ||
        _qualityRank(_qualityLabel(source)) >= 2160;
  }

  bool _looksRiskyForMedia3(PlaybackSource source) {
    return _looksHighEfficiencySource(source) ||
        _sourceEngineCompatibilityRank(
              source,
              _NativePlaybackEngine.exoplayer,
            ) >=
            4;
  }

  String _sourceDiagnosticProfile(PlaybackSource source) {
    final descriptor = _sourceDiagnosticDescriptor(source);
    final traits = <String>[
      'quality=${_qualityLabel(source)}',
      'container=${_containerHintFor(source, descriptor)}',
      'video=${_videoCodecHintFor(descriptor)}',
      'audio=${_audioCodecHintFor(descriptor)}',
      'hdr=${_hdrHintFor(descriptor)}',
    ];
    final language = _sourceLanguageLabel(source);
    if (language != null) traits.add('language=$language');
    if (descriptor.contains('atmos')) traits.add('spatial=atmos');
    if (descriptor.contains('dolby')) traits.add('brand=dolby');
    return traits.join(',');
  }

  String _sourceDiagnosticDescriptor(PlaybackSource source) {
    return '${source.name} ${source.url} ${source.type ?? ''} ${source.quality ?? ''}'
        .toLowerCase();
  }

  String _containerHintFor(PlaybackSource source, String descriptor) {
    final type = (source.type ?? '').toLowerCase();
    if (type == 'hls' || descriptor.contains('.m3u8')) return 'hls';
    if (type == 'dash' || descriptor.contains('.mpd')) return 'dash';
    if (descriptor.contains('.mkv') || descriptor.contains('matroska'))
      return 'mkv';
    if (descriptor.contains('.mp4')) return 'mp4';
    if (descriptor.contains('.webm')) return 'webm';
    if (descriptor.contains('.avi')) return 'avi';
    return type.isEmpty ? 'unknown' : type;
  }

  String _videoCodecHintFor(String descriptor) {
    if (descriptor.contains('av1')) return 'av1';
    if (descriptor.contains('hevc') ||
        descriptor.contains('x265') ||
        descriptor.contains('h265') ||
        descriptor.contains('h.265') ||
        descriptor.contains('hvc1')) {
      return 'hevc';
    }
    if (descriptor.contains('avc') ||
        descriptor.contains('x264') ||
        descriptor.contains('h264') ||
        descriptor.contains('h.264')) {
      return 'h264';
    }
    if (descriptor.contains('vp9')) return 'vp9';
    return 'unknown';
  }

  String _audioCodecHintFor(String descriptor) {
    if (descriptor.contains('truehd')) return 'truehd';
    if (descriptor.contains('dts-hd') || descriptor.contains('dts hd'))
      return 'dts-hd';
    if (descriptor.contains('dts')) return 'dts';
    if (descriptor.contains('ddp') ||
        descriptor.contains('eac3') ||
        descriptor.contains('e-ac3')) {
      return 'eac3';
    }
    if (descriptor.contains('dolby') || descriptor.contains('ac3'))
      return 'ac3';
    if (descriptor.contains('aac')) return 'aac';
    if (descriptor.contains('opus')) return 'opus';
    return 'unknown';
  }

  String _hdrHintFor(String descriptor) {
    if (descriptor.contains('dolby vision') ||
        descriptor.contains('dovi') ||
        descriptor.contains('dv ')) {
      return 'dolby-vision';
    }
    if (descriptor.contains('hdr10+')) return 'hdr10+';
    if (descriptor.contains('hdr10')) return 'hdr10';
    if (descriptor.contains('hdr')) return 'hdr';
    return 'sdr-or-unknown';
  }

  void _startOpeningGuard(
    PlaybackSource source,
    int openingToken,
    Duration timeout,
  ) {
    _openingGuardTimer?.cancel();
    _openingGuardTimer = Timer(timeout, () {
      if (!mounted || !_openingSource || openingToken != _openingSourceToken)
        return;
      final controller = _controller;
      if (controller?.isInitialized == true) return;
      DiagnosticLog.add(
        'native open guard timed out provider=${source.providerId} sourceIndex=$_sourceIndex',
      );
      _openingSourceToken += 1;
      _openingSource = false;
      _failedSourceAttempts[source.url] =
          (_failedSourceAttempts[source.url] ?? 0) + 1;
      AppState.recordNativeProviderFailure(
        mediaKey: _playbackKey,
        providerId: source.providerId,
        sourceCount: _activeSources.isEmpty
            ? null
            : visiblePlaybackSourceCount(_activeSources),
        updateHealth: _shouldUpdateProviderHealthFromPlaybackFailure,
      );
      unawaited(
        _disposeCurrentController(updateUi: false, awaitLibVlcRelease: true),
      );
      _activeSource = null;
      _sourceIndex += 1;
      final status = _nextSourceStatusFor();
      _pauseActivePlaybackForLoading('open_guard_timeout');
      _logPlaybackStatus(status, reason: 'open_guard_timeout');
      setState(() {
        _loading = true;
        _controlsVisible = true;
        _statusMessage = status;
      });
      unawaited(_openNextAvailableSource());
    });
  }

  void _logPlaybackStatus(
    String status, {
    required String reason,
    int? sourceIndex,
  }) {
    DiagnosticLog.add(
      'native playback status reason=$reason providerIndex=$_providerIndex sourceIndex=${sourceIndex ?? _sourceIndex} status="$status"',
    );
  }

  void _updateP2pWarmupStatus({
    required PlaybackSource source,
    required String detail,
    required String label,
  }) {
    if (label != 'preflight' ||
        source.sourceClass != PlaybackSourceClass.p2p ||
        _playerClosing ||
        !mounted) {
      return;
    }
    final status = _p2pWarmupStatusFromDetail(detail);
    if (_statusMessage == status) return;
    _logPlaybackStatus(status, reason: 'p2p_preflight_status');
    setState(() {
      _loading = true;
      _controlsVisible = true;
      _statusMessage = status;
    });
  }

  void _showP2pLocalStreamReadyStatus(PlaybackSource source) {
    if (source.sourceClass != PlaybackSourceClass.p2p ||
        _playerClosing ||
        !mounted) {
      return;
    }
    const status = 'Starting P2P source...\nBuffer is ready. Opening player.';
    _logPlaybackStatus(status, reason: 'p2p_preflight_ready');
    setState(() {
      _loading = true;
      _controlsVisible = true;
      _statusMessage = status;
    });
  }

  String _p2pWarmupStatusFromDetail(String detail) {
    final firstPieces =
        _p2pBridgeDetailInt(detail, 'firstPiecesReady') ??
        _p2pReadyPieceCount(_p2pBridgeDetailValue(detail, 'firstPieces') ?? '');
    final progressBytes =
        _p2pBridgeDetailInt(detail, 'fileProgressBytes') ??
        _p2pBridgeDetailInt(detail, 'bufferedBytes') ??
        0;
    if ((firstPieces ?? 0) > 0 || progressBytes > 0) {
      return 'Starting P2P source...\nBuffer is almost ready.';
    }
    final metadataKnown = _p2pBridgeDetailBool(detail, 'metadata') == true;
    if (metadataKnown) {
      return 'Warming P2P source...\nPeers found. Waiting for first video pieces.';
    }
    final peerSignals =
        (_p2pBridgeDetailInt(detail, 'peers') ?? 0) +
        (_p2pBridgeDetailInt(detail, 'seeds') ?? 0) +
        (_p2pBridgeDetailInt(detail, 'candidates') ?? 0) +
        (_p2pBridgeDetailInt(detail, 'listPeers') ?? 0);
    if (peerSignals > 0) {
      return 'Connecting P2P peers...\nThis can take 20-40 seconds.';
    }
    return 'Finding P2P peers...\nThis can take 20-40 seconds.';
  }

  String _resolveStatusFor(String providerId) {
    return _requests.length <= 1
        ? 'Finding a playable source...'
        : 'Finding playable sources...';
  }

  bool get _shouldUpdateProviderHealthFromPlaybackFailure {
    return _requests.length == 1;
  }

  String _providerProgressLabel(String providerId, {required String prefix}) {
    final total = _requests.length;
    if (total <= 1) {
      return '$prefix - ${_providerLabel(providerId)}';
    }
    final position = total <= 0 ? 0 : (_providerIndex + 1).clamp(1, total);
    return '$prefix $position/$total - ${_providerLabel(providerId)}';
  }

  String _qualityPassStatusFor(List<_QualityPass> passes) {
    if (passes.isEmpty || _qualityPassIndex >= passes.length) {
      return 'All quality options checked.';
    }
    final pass = passes[_qualityPassIndex];
    return 'Preparing ${_loadingStatusQualityLabel(pass.label)} sources ${_qualityPassIndex + 1}/${passes.length}...';
  }

  String _enginePassStatusFor(List<_NativePlaybackEngine> engines) {
    if (engines.isEmpty || _enginePassIndex >= engines.length) {
      return 'All playback engines checked.';
    }
    return engines.length <= 1
        ? 'Opening playback...'
        : 'Trying playback engine ${_enginePassIndex + 1}/${engines.length}...';
  }

  String _nextEngineStatusAfterUnavailable(
    List<_NativePlaybackEngine> engines,
  ) {
    for (var index = _enginePassIndex + 1; index < engines.length; index += 1) {
      final engine = engines[index];
      if (engine == _NativePlaybackEngine.libvlc &&
          _libvlcUnavailableForCurrentPass) {
        continue;
      }
      return engines.length <= 1
          ? 'Opening playback...'
          : 'Trying playback engine ${index + 1}/${engines.length}...';
    }
    return 'All playback engines checked.';
  }

  String _engineLabel(_NativePlaybackEngine engine) {
    return switch (engine) {
      _NativePlaybackEngine.exoplayer => 'Media3',
      _NativePlaybackEngine.libvlc => 'libVLC',
    };
  }

  String _openStatusFor(String providerId) {
    if (_activeSources.isNotEmpty)
      return _checkingSourceStatusFor(_sourceIndex);
    return _resolveStatusFor(providerId);
  }

  String _providerReadyStatusFor(
    String providerId,
    List<PlaybackSource> sources,
  ) {
    final sourceCount = _displaySourceEntries(sources).length;
    final publicIptvProvider = providerId.trim().toLowerCase() == 'public-iptv';
    final sourceLabel = publicIptvProvider
        ? sourceCount == 1
              ? '1 public stream candidate to check'
              : '$sourceCount public stream candidates to check'
        : sourceCount == 1
        ? '1 source'
        : '$sourceCount sources';
    final qualityPasses = _qualityPassesForCurrentAttempt();
    final qualityLabel =
        _qualityPassIndex >= 0 && _qualityPassIndex < qualityPasses.length
        ? _loadingStatusQualityLabel(qualityPasses[_qualityPassIndex].label)
        : null;
    final qualitySuffix = qualityLabel == null ? '' : ' [$qualityLabel]';
    return publicIptvProvider
        ? 'Preparing live TV $sourceLabel$qualitySuffix.'
        : sourceCount == 1
        ? 'Preparing 1 playable source$qualitySuffix.'
        : 'Preparing $sourceCount playable sources$qualitySuffix.';
  }

  String _loadingStatusQualityLabel(String quality) {
    return _displayQualityLabel(quality);
  }

  String _nextSourceStatusFor({bool skipProvider = false}) {
    if (skipProvider) {
      if (_resolverTemporarilyBlocked) {
        return 'Finding sources is taking longer than usual. Try again in a few seconds.';
      }
      final nextProviderIndex = _providerIndex + 1;
      if (nextProviderIndex < _requests.length) {
        final total = _requests.length;
        if (total <= 1) {
          return 'Trying another source...';
        }
        return 'Trying source group ${nextProviderIndex + 1}/$total...';
      }
      return _limitToFirstQualityPass
          ? 'Video is currently unavailable. Sending you back.'
          : "Couldn't open this one. Sending you back.";
    }
    final nextSourceIndex =
        _nextSourceIndexInCurrentVisibleGroup(_activeSources, _sourceIndex) ??
        _nextSourceIndexAfterCurrentVisibleGroup(
          _activeSources,
          _sourceIndex,
        ) ??
        (_sourceIndex + 1);
    return _checkingSourceStatusFor(nextSourceIndex);
  }

  String _checkingSourceStatusFor(int sourceIndex) {
    if (_activeSources.isEmpty ||
        sourceIndex < 0 ||
        sourceIndex >= _activeSources.length) {
      return _nextSourceStatusFor(skipProvider: true);
    }
    final source = _activeSources[sourceIndex];
    final quality = _qualityLabel(source);
    final livePrefix = _isPublicIptvSource(source)
        ? 'Opening live stream'
        : source.sourceClass == PlaybackSourceClass.p2p
        ? 'Opening source'
        : 'Opening source';
    final suffix = source.sourceClass == PlaybackSourceClass.p2p
        ? '\nP2P beta can take 20-40 seconds.'
        : '';
    final groups = _displaySourceEntries(_activeSources);
    final groupIndex = groups.indexWhere(
      (group) => group.variants.any((candidate) => candidate.url == source.url),
    );
    if (groupIndex < 0)
      return '$livePrefix ${sourceIndex + 1}/${_activeSources.length} [$quality]...$suffix';
    final group = groups[groupIndex];
    final mirrorIndex = group.variants.indexWhere(
      (candidate) => candidate.url == source.url,
    );
    if (group.variants.length > 1 && mirrorIndex >= 0) {
      return '$livePrefix ${groupIndex + 1}/${groups.length} - mirror ${mirrorIndex + 1}/${group.variants.length} [$quality]...$suffix';
    }
    return '$livePrefix ${groupIndex + 1}/${groups.length} [$quality]...$suffix';
  }

  String _refreshingSourceStatusFor() {
    final status = _checkingSourceStatusFor(_sourceIndex);
    if (status.startsWith('Checking ')) {
      return status.replaceFirst('Checking ', 'Refreshing ');
    }
    if (status.startsWith('Trying ')) {
      return status.replaceFirst('Trying ', 'Refreshing ');
    }
    if (status.startsWith('Opening ')) {
      return status.replaceFirst('Opening ', 'Refreshing ');
    }
    return 'Refreshing source...';
  }

  Future<void> _disposeCurrentController({
    bool updateUi = true,
    bool awaitLibVlcRelease = false,
    bool saveProgress = true,
  }) async {
    _stopStallWatchdog();
    _cancelDeferredResumeSeek();
    final controller = _controller;
    if (controller == null) return;
    if (saveProgress) {
      _trackLastKnownPlaybackPosition();
      _saveNativeProgress(force: true);
    }
    _controller = null;
    controller.removeListener(_handleControllerUpdate);
    final isLibVlc = controller.engine == _NativePlaybackEngine.libvlc;
    if (!controller.isInitialized) {
      DiagnosticLog.add(
        'native controller pause skipped engine=${controller.engine.id} reason=controller_not_initialized',
      );
    } else if (isLibVlc) {
      final stop = controller.stop().timeout(const Duration(milliseconds: 700));
      if (awaitLibVlcRelease) {
        try {
          await stop;
        } catch (error) {
          DiagnosticLog.add(
            'native libvlc controller stop skipped error=${_safeDiagnosticError(error)}',
          );
        }
      } else {
        unawaited(
          stop.catchError((error) {
            DiagnosticLog.add(
              'native libvlc controller stop skipped error=${_safeDiagnosticError(error)}',
            );
          }),
        );
      }
    } else {
      try {
        await controller.pause().timeout(const Duration(milliseconds: 700));
      } catch (_) {}
    }
    if (mounted && updateUi) {
      setState(() {});
      if (!isLibVlc) {
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    if (isLibVlc && awaitLibVlcRelease) {
      final settle = _libVlcReleaseSettle;
      final preReleaseSettle = settle <= Duration.zero
          ? const Duration(milliseconds: 180)
          : Duration(
              milliseconds: math.min(settle.inMilliseconds, 350).toInt(),
            );
      DiagnosticLog.add(
        'native libvlc pre-release settle delay=${preReleaseSettle.inMilliseconds}ms reason=stop_before_dispose',
      );
      await Future<void>.delayed(preReleaseSettle);
    }
    final releaseStopwatch = Stopwatch()..start();
    final releaseTimeout = isLibVlc && awaitLibVlcRelease
        ? const Duration(seconds: 4)
        : const Duration(seconds: 2);
    final release = controller.dispose().timeout(releaseTimeout);
    if (isLibVlc && !awaitLibVlcRelease) {
      DiagnosticLog.add('native libvlc controller release detached');
      unawaited(
        release
            .then((_) {
              unawaited(
                DiagnosticLog.clearNativeEngineActive(
                  engineId: controller.engine.id,
                  reason: 'controller_disposed_detached',
                ),
              );
              DiagnosticLog.add(
                'native controller disposed engine=${controller.engine.id} elapsed=${releaseStopwatch.elapsedMilliseconds}ms detached=true',
              );
            })
            .catchError((error) {
              DiagnosticLog.add(
                'native controller dispose timed out/failed engine=${controller.engine.id} elapsed=${releaseStopwatch.elapsedMilliseconds}ms error=${_safeDiagnosticError(error)}',
              );
            }),
      );
    } else {
      try {
        await release;
        if (isLibVlc) {
          unawaited(
            DiagnosticLog.clearNativeEngineActive(
              engineId: controller.engine.id,
              reason: 'controller_disposed',
            ),
          );
        }
        DiagnosticLog.add(
          'native controller disposed engine=${controller.engine.id} elapsed=${releaseStopwatch.elapsedMilliseconds}ms detached=false',
        );
      } catch (error) {
        DiagnosticLog.add(
          'native controller dispose timed out/failed engine=${controller.engine.id} elapsed=${releaseStopwatch.elapsedMilliseconds}ms error=${_safeDiagnosticError(error)}',
        );
      }
    }
    _activeSourceHasZeroClockMetadata = false;
    _nativeWallClockStartedAt = null;
    _lastSavedSecond = -1;
    _resetPlaybackIntegritySample();
    await _stopLibVlcHlsRelay('controller_disposed');
  }

  Future<void> _stopLibVlcHlsRelay(String reason) async {
    final relay = _libVlcHlsRelay;
    if (relay == null) return;
    _libVlcHlsRelay = null;
    _resetLibVlcContinuousTsProof();
    final summary = relay.summary;
    try {
      await relay.stop();
      DiagnosticLog.add(
        'native libvlc hls relay stopped reason=$reason $summary',
      );
    } catch (error) {
      DiagnosticLog.add(
        'native libvlc hls relay stop failed reason=$reason error=${_safeDiagnosticError(error)}',
      );
    }
  }

  void _resetLibVlcContinuousTsProof() {
    _libVlcContinuousTsDurationAccepted = false;
    _libVlcContinuousTsStreamedSegments = 0;
  }

  void _maybeClearLibVlcContinuousTsWaitMessage({required String reason}) {
    if (!_libVlcContinuousTsRelayProofReady) return;
    if (_playbackWaitMessage != 'Getting stream details...') return;
    DiagnosticLog.add(
      'native libvlc continuous-ts relay proof accepted reason=$reason streamed=${_countDiagnosticBucket(_libVlcContinuousTsStreamedSegments)} durationKnown=$_libVlcContinuousTsDurationAccepted',
    );
    _clearPlaybackWaitMessage(reason: reason);
  }

  Future<void> _loadPipSupport() async {
    try {
      final supported =
          await _pipChannel.invokeMethod<bool>('isSupported') ?? false;
      if (mounted) setState(() => _pipSupported = supported);
      if (supported) unawaited(_syncAndroidAutoPipOnUserLeave());
      DiagnosticLog.add('native system PiP supported=$supported');
    } catch (_) {
      if (mounted) setState(() => _pipSupported = false);
      DiagnosticLog.add('native system PiP support check failed');
    }
  }

  Future<dynamic> _handlePipChannelCall(MethodCall call) async {
    if (call.method == 'prepareForSystemPip') {
      _prepareForSystemPip();
      return null;
    }
    if (call.method == 'enteredSystemPip') {
      DiagnosticLog.add('native system PiP entered');
      _pictureInPictureActive = true;
      return null;
    }
    if (call.method == 'exitedSystemPip') {
      DiagnosticLog.add('native system PiP exited');
      _pictureInPictureActive = false;
      _systemPipHandoffActive = false;
      if (mounted) setState(() {});
      return null;
    }
    if (call.method != 'action') return null;
    final action = call.arguments?.toString();
    DiagnosticLog.add('native pip action=$action');
    switch (action) {
      case 'skipBack':
        if (_isLiveTvMode) break;
        await _seekBy(Duration(seconds: -_seekStepSeconds.round()));
        break;
      case 'playPause':
        _togglePlayback(ignoreOptionSheet: true);
        await _syncPipActions();
        break;
      case 'skipForward':
        if (_isLiveTvMode) break;
        await _seekBy(Duration(seconds: _seekStepSeconds.round()));
        break;
      case 'fullscreen':
        if (!mounted) return null;
        setState(() {
          _pictureInPictureActive = false;
          _optionSheetOpen = false;
          _controlsVisible = true;
        });
        break;
      case 'close':
        await _requestClose();
        break;
    }
    return null;
  }

  Future<void> _syncPipActions() async {
    if (!_pictureInPictureActive || !_pipSupported) return;
    try {
      await _pipChannel.invokeMethod<void>('updateActions', {
        'playing': _controller?.isPlaying == true,
        'seekSeconds': _seekStepSeconds.round(),
        'liveMode': _isLiveTvMode,
      });
    } catch (error) {
      DiagnosticLog.add(
        'native pip action sync failed error=${_safeDiagnosticError(error)}',
      );
    }
  }

  void _restoreNativePreferences() {
    _usingGlobalOverrides = false;
    _settingsExpanded = false;
    _settingsPausedPlayback = false;
    final item = _progressItem;
    final key = _playbackKey;
    final prefs = item == null || key == null
        ? null
        : AppState.progressFor(item, playbackKey: key)?.nativePreferences;
    if (prefs != null) {
      _hasRestoredNativePreferences = true;
      final restoredQuality = prefs.quality?.trim() ?? '';
      final normalizedQuality = _normalizeSavedQuality(restoredQuality);
      _preferredQuality =
          normalizedQuality.isEmpty || normalizedQuality.toLowerCase() == 'auto'
          ? null
          : normalizedQuality;
      _qualityPreferenceMode = _preferredQuality == null
          ? 'recommended'
          : 'advanced';
      _playbackSpeed = prefs.speed;
      _preferredSubtitleId = prefs.subtitleId;
      _subtitleDelaySeconds = prefs.subtitleDelaySeconds;
      _subtitleDelayCustomized = prefs.subtitleDelayCustomized;
      _subtitleFontSize = prefs.subtitleFontSize;
      _subtitleBackgroundOpacity = prefs.subtitleBackgroundOpacity;
      _subtitleBackgroundColor = Color(prefs.subtitleBackgroundColor);
      _subtitleBackgroundRadius = prefs.subtitleBackgroundRadius;
      _subtitleTextColor = Color(prefs.subtitleTextColor);
      _subtitleBottomOffset = prefs.subtitleBottomOffset;
      _fitMode = VideoFitMode.fromName(prefs.videoFitMode);
      DiagnosticLog.add(
        'native preferences restored key=[redacted] quality=${prefs.quality} normalized=${_preferredQuality ?? 'Auto'} speed=${prefs.speed} fit=${_fitMode.name}',
      );
    }

    if (AppState.nativePlaybackOverridesEnabled.value) {
      _usingGlobalOverrides = true;
      final overrides = AppState.nativePlaybackOverrides.value;
      _qualityPreferenceMode = overrides.qualityMode;
      _preferredQuality = overrides.qualityMode == 'advanced'
          ? _normalizeSavedQuality(overrides.advancedQuality)
          : null;
      _seekStepSeconds = overrides.seekStepSeconds;
      _playbackSpeed = overrides.speed;
      if (!_subtitleDelayCustomized) {
        _subtitleDelaySeconds = overrides.subtitleDelaySeconds;
      }
      _subtitleFontSize = overrides.subtitleFontSize;
      _subtitleBackgroundOpacity = overrides.subtitleBackgroundOpacity;
      _subtitleBackgroundColor = Color(overrides.subtitleBackgroundColor);
      _subtitleBackgroundRadius = overrides.subtitleBackgroundRadius;
      _subtitleTextColor = Color(overrides.subtitleTextColor);
      _subtitleBottomOffset = overrides.subtitleBottomOffset;
      _fitMode = VideoFitMode.fromName(overrides.videoFitMode);
      DiagnosticLog.add(
        'native overrides applied qualityMode=${overrides.qualityMode} advancedQuality=${overrides.advancedQuality} normalized=${_preferredQuality ?? 'Auto'} seek=${overrides.seekStepSeconds} fit=${_fitMode.name}',
      );
    }
    if (_batterySaverPlaybackActive && _qualityPreferenceMode != 'dataSaver') {
      _usingGlobalOverrides = true;
      _qualityPreferenceMode = 'dataSaver';
      _preferredQuality = null;
      DiagnosticLog.add(
        'native battery data policy applied playbackQuality=dataSaver',
      );
    }
  }

  void _restoreNativeSurfaceLevels() {
    _volumePreview = AppState.nativePlayerVolume.value
        .clamp(0.0, 1.0)
        .toDouble();
    _brightnessPreview = AppState.nativePlayerBrightness.value
        .clamp(0.0, 1.0)
        .toDouble();
    _displayChannel
        .invokeMethod<void>('setBrightness', {'value': _brightnessPreview})
        .catchError((_) {});
  }

  String _normalizeSavedQuality(String quality) {
    return quality.trim();
  }

  void _ensureSubtitlesLoading() {
    if (_subtitlesLoadStarted) return;
    _subtitlesLoadStarted = true;
    unawaited(_loadSubtitles());
  }

  Future<void> _loadSubtitles() async {
    final resolver = _resolveSubtitles;
    if (_playerClosing) return;
    final seededSubtitles = _subtitles;
    List<PlaybackSubtitle> resolvedSubtitles = const <PlaybackSubtitle>[];
    if (resolver != null) {
      try {
        resolvedSubtitles = await resolver();
      } catch (error) {
        DiagnosticLog.add(
          'native subtitles resolver failed error=${_safeDiagnosticError(error)}',
        );
      }
    }
    if (!mounted || _playerClosing) return;
    final subtitles = _mergePlaybackSubtitles(
      seededSubtitles,
      resolvedSubtitles,
    );
    if (subtitles.isEmpty) {
      setState(() {
        _subtitles = const <PlaybackSubtitle>[];
      });
      return;
    }
    final behavior = AppState.playerBehaviorSettings.value;
    final autoSelect = behavior.subtitleAutoSelect;
    PlaybackSubtitle? preferredSubtitle;
    if (autoSelect != 'off' &&
        (autoSelect == 'last' || _hasRestoredNativePreferences) &&
        _preferredSubtitleId != null) {
      for (final subtitle in subtitles) {
        if (subtitle.id == _preferredSubtitleId) {
          preferredSubtitle = subtitle;
          break;
        }
      }
    }
    if (preferredSubtitle == null && autoSelect == 'forced') {
      for (final subtitle in subtitles) {
        if (subtitle.isForced) {
          preferredSubtitle = subtitle;
          break;
        }
      }
    }
    if (preferredSubtitle == null && autoSelect == 'default') {
      final preferredLanguage = behavior.subtitleLanguage.toLowerCase();
      for (final subtitle in subtitles) {
        final language = subtitle.language.toLowerCase();
        if (subtitle.isDefault ||
            preferredLanguage == 'auto' ||
            (preferredLanguage == 'en' && language == 'english') ||
            (preferredLanguage == 'es' && language == 'spanish') ||
            (preferredLanguage == 'fr' && language == 'french') ||
            (preferredLanguage == 'de' && language == 'german') ||
            (preferredLanguage == 'pt' && language == 'portuguese') ||
            language == preferredLanguage ||
            language.startsWith('$preferredLanguage-')) {
          preferredSubtitle = subtitle;
          break;
        }
      }
    }
    setState(() {
      _subtitles = subtitles;
    });
    if (preferredSubtitle != null && autoSelect != 'off') {
      await _selectSubtitle(preferredSubtitle);
    }
  }

  List<PlaybackSubtitle> _mergePlaybackSubtitles(
    List<PlaybackSubtitle> seeded,
    List<PlaybackSubtitle> resolved,
  ) {
    final seen = <String>{};
    final merged = <PlaybackSubtitle>[];
    for (final subtitle in [...seeded, ...resolved]) {
      final key = subtitle.url.trim().isNotEmpty
          ? subtitle.url.trim()
          : subtitle.id;
      if (key.trim().isEmpty || !seen.add(key)) continue;
      merged.add(subtitle);
    }
    return merged;
  }

  void _handleControllerUpdate() {
    if (_playerClosing) return;
    final controller = _controller;
    if (controller != null &&
        controller.hasError &&
        !_openingSource &&
        !_recoveringFromStall) {
      if (!AppState.playerBehaviorSettings.value.autoSwitchOnStall) {
        DiagnosticLog.add(
          'native playback error detected but auto-switch on stall is disabled',
        );
        return;
      }
      if (_shouldDeferControllerErrorRecovery(controller, reason: 'listener')) {
        return;
      }
      final recoveryPosition = _effectiveRecoveryPosition(controller.position);
      DiagnosticLog.add(
        'native playback error listener provider=${_activeSource?.providerId} reportedPosition=${controller.position.inSeconds}s recoveryPosition=${recoveryPosition.inSeconds}s error=${controller.errorDescription}',
      );
      _recordControllerRuntimeFailureHint(controller, reason: 'listener');
      unawaited(
        _recoverFromPlaybackStall(
          recoveryPosition,
          skipSameSource: true,
          skipProvider: true,
        ),
      );
      return;
    }
    _clearControllerErrorGrace();
    _syncKeepScreenOn();
    _trackLastKnownPlaybackPosition();
    if (controller != null) {
      _maybeRecordDeferredLibVlcOpenSuccess(
        controller,
        reason: 'controller_update_visual_proof',
      );
    }
    _saveNativeProgress();
    if (controller != null) {
      _maybeAutoplayNextEpisode(controller);
      _maybeCloseWhenPlaybackCompleted(controller);
      _ensureControlsAutoHide(reason: 'controller_update_playing');
    }
    final subtitleChanged = _syncSubtitleText();
    if (mounted && _shouldRebuildForControllerUpdate(subtitleChanged)) {
      _lastControllerUiRebuildAt = DateTime.now();
      setState(() {});
    }
  }

  bool _shouldRebuildForControllerUpdate(bool subtitleChanged) {
    if (subtitleChanged) return true;
    final controller = _controller;
    if (controller == null || !controller.isInitialized) return true;
    final now = DateTime.now();
    final previous = _lastControllerUiRebuildAt;
    final visibleUi =
        _controlsVisible ||
        _settingsExpanded ||
        _optionSheetOpen ||
        _loading ||
        _playbackWaitMessage != null ||
        controller.isBuffering;
    final interval = visibleUi
        ? const Duration(milliseconds: 500)
        : const Duration(seconds: 2);
    return previous == null || now.difference(previous) >= interval;
  }

  void _maybeAutoplayNextEpisode(_NativePlaybackController controller) {
    if (_autoNextEpisodeStarted ||
        !AppState.playerBehaviorSettings.value.autoplayNextEpisode ||
        _nextEpisodeResolver == null ||
        !controller.isInitialized ||
        controller.duration <= Duration.zero) {
      return;
    }
    final remaining = controller.duration - controller.position;
    if (remaining > const Duration(seconds: 2)) return;
    _autoNextEpisodeStarted = true;
    DiagnosticLog.add('native autoplay next episode triggered');
    unawaited(_openNextEpisodeInPlace());
  }

  void _maybeCloseWhenPlaybackCompleted(_NativePlaybackController controller) {
    if (_completionCloseStarted ||
        _playerClosing ||
        _openingSource ||
        _recoveringFromStall ||
        _activeSourceHasZeroClockMetadata ||
        !controller.isInitialized ||
        controller.duration <= Duration.zero) {
      return;
    }
    if (_nextEpisodeResolver != null &&
        AppState.playerBehaviorSettings.value.autoplayNextEpisode &&
        _autoNextEpisodeStarted) {
      return;
    }
    final duration = controller.duration;
    final position = controller.position;
    if (position < const Duration(seconds: 3)) return;
    final remaining = duration - position;
    final nearEnd =
        remaining <= const Duration(milliseconds: 1200) &&
        position.inMilliseconds / duration.inMilliseconds >= 0.985;
    if (!controller.isEnded && !nearEnd) return;

    _completionCloseStarted = true;
    _resumePromptHandled = true;
    _resumePromptAccepted = false;
    DiagnosticLog.add(
      'native playback completed; closing player position=${position.inSeconds}s duration=${duration.inSeconds}s',
    );
    _sendPlaybackFeedback('completed');
    _saveNativeProgress(force: true, completionObserved: true);
    unawaited(_close('completed'));
  }

  void _startStallWatchdog() {
    if (_playerClosing) return;
    _stopStallWatchdog();
    _lastWatchdogPosition = _controller?.position ?? Duration.zero;
    _stallWatchdogTicks = 0;
    _blackVideoWatchdogTicks = 0;
    _bufferingWatchdogTicks = 0;
    _stallWatchdogTimer = Timer.periodic(
      _stallWatchdogInterval,
      (_) => _checkPlaybackStall(),
    );
    _startPlaybackCadenceSampler();
  }

  void _stopStallWatchdog() {
    _stallWatchdogTimer?.cancel();
    _stallWatchdogTimer = null;
    _stopPlaybackCadenceSampler();
    _stallWatchdogTicks = 0;
    _deadPauseTicks = 0;
    _blackVideoWatchdogTicks = 0;
    _bufferingWatchdogTicks = 0;
  }

  void _startPlaybackCadenceSampler() {
    _stopPlaybackCadenceSampler();
    _lastCadencePosition = _controller?.position ?? Duration.zero;
    _lastCadenceSampleAt = DateTime.now();
    _playbackCadenceSamples = 0;
    _playbackCadenceTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _samplePlaybackCadence(),
    );
  }

  void _stopPlaybackCadenceSampler() {
    _playbackCadenceTimer?.cancel();
    _playbackCadenceTimer = null;
    _lastCadenceSampleAt = null;
    _playbackCadenceSamples = 0;
  }

  void _samplePlaybackCadence() {
    final controller = _controller;
    final source = _activeSource;
    if (_playerClosing ||
        controller == null ||
        source?.sourceClass != PlaybackSourceClass.p2p ||
        !controller.isInitialized ||
        controller.hasError) {
      return;
    }
    final now = DateTime.now();
    final previousSampleAt = _lastCadenceSampleAt ?? now;
    final previousPosition = _lastCadencePosition;
    final position = controller.position;
    final wallDeltaMs = now.difference(previousSampleAt).inMilliseconds;
    final playbackDeltaMs =
        position.inMilliseconds - previousPosition.inMilliseconds;
    _lastCadenceSampleAt = now;
    _lastCadencePosition = position;
    if (wallDeltaMs <= 0) return;
    _playbackCadenceSamples += 1;
    final ratio = playbackDeltaMs / wallDeltaMs;
    final shouldLog =
        _playbackCadenceSamples <= 3 ||
        _playbackCadenceSamples % 30 == 0 ||
        ratio < 0.35 ||
        ratio > 1.80 ||
        controller.isBuffering;
    if (!shouldLog) return;
    DiagnosticLog.add(
      'native p2p cadence sample provider=${source?.providerId ?? 'unknown'} engine=${controller.engine.id} view=${controller.videoViewType?.name ?? 'native'} position=${position.inSeconds}s wallDeltaMs=$wallDeltaMs playbackDeltaMs=$playbackDeltaMs ratio=${ratio.toStringAsFixed(2)} playing=${controller.isPlaying} buffering=${controller.isBuffering}',
    );
  }

  Future<bool> _retrySourceWithExoPlayerAfterLibVlcFailure(
    PlaybackSource source,
    Duration resumePosition, {
    required String statusMessage,
    required String reason,
  }) async {
    if (!mounted || _playerClosing) return false;
    if (_manualLibVlcStrictForSource(source)) {
      DiagnosticLog.add(
        'native exoplayer retry skipped provider=${source.providerId} reason=manual_libvlc_locked originalReason=$reason',
      );
      return false;
    }
    if (!_libvlcUnavailableForSession && !_libvlcUnavailableForAppSession) {
      return false;
    }
    DiagnosticLog.add(
      'native retrying source with exoplayer provider=${source.providerId} position=${resumePosition.inSeconds}s reason=$reason',
    );
    return _openSource(
      source,
      resumePosition: resumePosition,
      statusMessage: statusMessage,
      engineOverride: _NativePlaybackEngine.exoplayer,
    );
  }

  Future<bool> _retrySourceWithLibVlcAfterExoVisualFailure(
    PlaybackSource source,
    Duration resumePosition, {
    required String statusMessage,
    required String reason,
  }) async {
    if (!mounted || _playerClosing) return false;
    if (_effectivePlaybackEngine != 'auto') {
      DiagnosticLog.add(
        'native retry with libvlc skipped provider=${source.providerId} reason=manual_engine_locked originalReason=$reason',
      );
      return false;
    }
    if (_manualLibVlcConfigured || _libvlcUnavailableForCurrentPass) {
      return false;
    }
    if (_isLiveTvMode && !_isPublicIptvSource(source)) return false;
    DiagnosticLog.add(
      'native retrying source with libvlc provider=${source.providerId} position=${resumePosition.inSeconds}s reason=$reason',
    );
    return _openSource(
      source,
      resumePosition: resumePosition,
      statusMessage: statusMessage,
      engineOverride: _NativePlaybackEngine.libvlc,
    );
  }

  void _prepareForSystemPip() {
    if (!mounted) return;
    DiagnosticLog.add('native system PiP preparing compact controls');
    setState(() {
      _pictureInPictureActive = true;
      _systemPipHandoffActive = false;
      _optionSheetOpen = false;
      _settingsExpanded = false;
      _controlsVisible = false;
      _locked = false;
    });
    unawaited(_setKeepScreenOn(false));
  }

  void _showPlaybackWaitMessage(
    String message, {
    required String reason,
    bool pausePlayback = true,
  }) {
    if (_playerClosing || _loading) return;
    final pausedForMessage = pausePlayback
        ? _pauseActivePlaybackForLoading('wait_message_$reason')
        : false;
    _playbackWaitMessagePausedPlayback =
        _playbackWaitMessagePausedPlayback || pausedForMessage;
    if (_playbackWaitMessage == message) {
      if (mounted && (_controlsVisible || _settingsExpanded)) {
        setState(() {
          _controlsVisible = false;
          _settingsExpanded = false;
        });
      }
      return;
    }
    DiagnosticLog.add(
      'native playback wait message reason=$reason provider=${_activeSource?.providerId} message="$message"',
    );
    if (mounted) {
      setState(() {
        _playbackWaitMessage = message;
        _controlsVisible = false;
        _settingsExpanded = false;
      });
    } else {
      _playbackWaitMessage = message;
      _controlsVisible = false;
      _settingsExpanded = false;
    }
  }

  void _clearPlaybackWaitMessage({required String reason}) {
    if (_playbackWaitMessage == null) return;
    final shouldResume =
        _playbackWaitMessagePausedPlayback &&
        !_playerClosing &&
        !_loading &&
        !_recoveringFromStall &&
        !_openingSource &&
        !_optionSheetOpen &&
        !_settingsExpanded &&
        !_userPaused;
    _playbackWaitMessagePausedPlayback = false;
    DiagnosticLog.add(
      'native playback wait message cleared reason=$reason provider=${_activeSource?.providerId}',
    );
    if (mounted) {
      setState(() => _playbackWaitMessage = null);
    } else {
      _playbackWaitMessage = null;
    }
    if (shouldResume) {
      unawaited(_resumePlaybackAfterWaitMessage(reason));
    }
  }

  void _checkPlaybackStall() {
    final controller = _controller;
    if (_playerClosing || !mounted) {
      _stopStallWatchdog();
      return;
    }
    if (_settingsExpanded || _optionSheetOpen) {
      _lastWatchdogPosition = controller?.position ?? Duration.zero;
      _stallWatchdogTicks = 0;
      _deadPauseTicks = 0;
      _bufferingWatchdogTicks = 0;
      _clearPlaybackWaitMessage(reason: 'player_sheet_open');
      return;
    }
    if (_loading || _recoveringFromStall || controller == null) {
      _lastWatchdogPosition = controller?.position ?? Duration.zero;
      _stallWatchdogTicks = 0;
      _deadPauseTicks = 0;
      _bufferingWatchdogTicks = 0;
      return;
    }

    final position = controller.position;
    if (_libVlcContinuousTsPlaybackActive(controller)) {
      _lastWatchdogPosition = position;
      _stallWatchdogTicks = 0;
      _deadPauseTicks = 0;
      _blackVideoWatchdogTicks = 0;
      _bufferingWatchdogTicks = 0;
      if (_lastSavedSecond == 8 || _lastSavedSecond % 30 == 0) {
        DiagnosticLog.add(
          'native libvlc continuous-ts playback protected provider=${_activeSource?.providerId} watched=${_lastSavedSecond}s position=${position.inSeconds}s duration=${controller.duration.inSeconds}s size=${controller.size.width.toInt()}x${controller.size.height.toInt()}',
        );
      }
      _clearPlaybackWaitMessage(reason: 'libvlc_continuous_ts_playing');
      return;
    }
    if (controller.hasError) {
      if (!AppState.playerBehaviorSettings.value.autoSwitchOnStall) {
        DiagnosticLog.add(
          'native playback controller error detected but auto-switch on stall is disabled',
        );
        return;
      }
      if (_shouldDeferControllerErrorRecovery(controller, reason: 'watchdog')) {
        return;
      }
      final recoveryPosition = _effectiveRecoveryPosition(position);
      DiagnosticLog.add(
        'native playback controller error provider=${_activeSource?.providerId} reportedPosition=${position.inSeconds}s recoveryPosition=${recoveryPosition.inSeconds}s error=${controller.errorDescription}',
      );
      _recordControllerRuntimeFailureHint(controller, reason: 'watchdog');
      unawaited(
        _recoverFromPlaybackStall(
          recoveryPosition,
          skipSameSource: true,
          skipProvider: true,
        ),
      );
      return;
    }

    if (!controller.isInitialized) {
      _lastWatchdogPosition = position;
      _stallWatchdogTicks = 0;
      _deadPauseTicks = 0;
      _bufferingWatchdogTicks = 0;
      return;
    }

    final nativeClockUnavailable =
        position <= Duration.zero &&
        controller.duration <= Duration.zero &&
        controller.size == Size.zero;
    if (nativeClockUnavailable) {
      final publicIptvSource =
          _activeSource != null && _isPublicIptvSource(_activeSource!);
      _stallWatchdogTicks += 1;
      _deadPauseTicks = 0;
      _bufferingWatchdogTicks = 0;
      _saveNativeProgress();
      if (_stallWatchdogTicks == 1) {
        DiagnosticLog.add(
          'native metadata clock unavailable; skipping position-only stall recovery provider=${_activeSource?.providerId} engine=${controller.engine.id}',
        );
      }
      if (_isLiveTvMode || publicIptvSource) {
        if (_stallWatchdogTicks < 6) {
          DiagnosticLog.add(
            'native live tv metadata grace provider=${_activeSource?.providerId} tick=$_stallWatchdogTicks engine=${controller.engine.id}',
          );
          _clearPlaybackWaitMessage(reason: 'live_tv_metadata_grace');
          return;
        }
        if (AppState.playerBehaviorSettings.value.autoSwitchOnStall) {
          DiagnosticLog.add(
            'native live tv metadata unresolved provider=${_activeSource?.providerId} tick=$_stallWatchdogTicks engine=${controller.engine.id} action=refresh-surface',
          );
          unawaited(
            _recoverFromBlackVideo(_effectiveRecoveryPosition(position)),
          );
          return;
        }
      }
      final libVlcZeroVisualElapsed = _nativeWallClockStartedAt == null
          ? null
          : DateTime.now().difference(_nativeWallClockStartedAt!);
      final libVlcZeroVisualMetadata =
          controller.engine == _NativePlaybackEngine.libvlc &&
          _activeSourceHasZeroClockMetadata &&
          controller.size == Size.zero;
      if (controller.engine == _NativePlaybackEngine.libvlc &&
          _libVlcContinuousTsRelayProofReady &&
          libVlcZeroVisualMetadata &&
          libVlcZeroVisualElapsed != null &&
          libVlcZeroVisualElapsed >= _libVlcWarmupGrace &&
          AppState.playerBehaviorSettings.value.autoSwitchOnStall) {
        DiagnosticLog.add(
          'native libvlc zero-visual relay proof timeout provider=${_activeSource?.providerId} elapsed=${libVlcZeroVisualElapsed.inSeconds}s duration=${controller.duration.inSeconds}s size=0x0 reason=relay_proof_no_visual action=recover',
        );
        _showPlaybackWaitMessage(
          'Recovering playback...',
          reason: 'libvlc_relay_zero_visual',
        );
        unawaited(_recoverFromPlaybackStall(position));
        return;
      }
      if (controller.engine == _NativePlaybackEngine.libvlc &&
          _libVlcContinuousTsRelayProofReady &&
          !libVlcZeroVisualMetadata) {
        _lastWatchdogPosition = position;
        _stallWatchdogTicks = 0;
        _deadPauseTicks = 0;
        _bufferingWatchdogTicks = 0;
        _maybeClearLibVlcContinuousTsWaitMessage(
          reason: 'libvlc_continuous_ts_metadata_fallback',
        );
        return;
      }
      if (controller.engine == _NativePlaybackEngine.libvlc &&
          _libVlcContinuousTsActive &&
          libVlcZeroVisualElapsed != null &&
          libVlcZeroVisualElapsed < _libVlcContinuousTsVisualGrace) {
        DiagnosticLog.add(
          'native libvlc continuous-ts visual grace elapsed=${libVlcZeroVisualElapsed.inSeconds}s position=${position.inSeconds}s duration=${controller.duration.inSeconds}s size=0x0 reason=metadata_clock',
        );
        _showPlaybackWaitMessage(
          'Getting stream details...',
          reason: 'libvlc_continuous_ts_visual_grace',
          pausePlayback: false,
        );
        return;
      }
      _showPlaybackWaitMessage(
        'Getting stream details...',
        reason: 'metadata_clock_unavailable',
        pausePlayback: false,
      );
      if (controller.engine == _NativePlaybackEngine.libvlc &&
          libVlcZeroVisualElapsed != null &&
          libVlcZeroVisualElapsed >= _libVlcWarmupGrace &&
          AppState.playerBehaviorSettings.value.autoSwitchOnStall) {
        DiagnosticLog.add(
          'native libvlc zero-visual timeout provider=${_activeSource?.providerId} elapsed=${libVlcZeroVisualElapsed.inSeconds}s duration=${controller.duration.inSeconds}s size=0x0 action=recover',
        );
        unawaited(_recoverFromPlaybackStall(position));
      }
      return;
    }

    if (controller.isBuffering) {
      _lastWatchdogPosition = position;
      _stallWatchdogTicks = 0;
      _deadPauseTicks = 0;
      _blackVideoWatchdogTicks = 0;
      _bufferingWatchdogTicks += 1;
      final source = _activeSource;
      final zeroVisualBuffering =
          source != null &&
          controller.engine == _NativePlaybackEngine.exoplayer &&
          source.sourceClass != PlaybackSourceClass.p2p &&
          !_isLiveTvMode &&
          controller.duration > Duration.zero &&
          controller.size == Size.zero &&
          _progressItem?.type != MediaType.music &&
          (position >= const Duration(seconds: 3) ||
              _lastKnownPlaybackPosition >= const Duration(seconds: 3));
      if (zeroVisualBuffering &&
          AppState.playerBehaviorSettings.value.autoSwitchOnStall) {
        DiagnosticLog.add(
          'native buffering zero visual provider=${source.providerId} engine=${controller.engine.id} tick=$_bufferingWatchdogTicks position=${position.inSeconds}s duration=${controller.duration.inSeconds}s action=visual-recovery',
        );
        _showPlaybackWaitMessage(
          'Recovering playback...',
          reason: 'buffering_zero_visual',
        );
        unawaited(_recoverFromBlackVideo(_effectiveRecoveryPosition(position)));
        return;
      }
      final recoveryTickLimit = _bufferingRecoveryTickLimitForSource(source);
      if (_bufferingWatchdogTicks >= recoveryTickLimit &&
          AppState.playerBehaviorSettings.value.autoSwitchOnStall) {
        DiagnosticLog.add(
          'native buffering watchdog provider=${source?.providerId} tick=$_bufferingWatchdogTicks limit=$recoveryTickLimit position=${position.inSeconds}s action=recover',
        );
        if (source != null) {
          _markRuntimeSourceFailure(source, 'buffering_timeout');
        }
        _showPlaybackWaitMessage(
          'Recovering playback...',
          reason: 'buffering_watchdog',
        );
        unawaited(
          _recoverFromPlaybackStall(
            _effectiveRecoveryPosition(position),
            skipSameSource: true,
            skipProvider: false,
          ),
        );
        return;
      }
      _showPlaybackWaitMessage(
        'Buffering stream...',
        reason: 'controller_buffering',
        pausePlayback: _activeSource?.sourceClass != PlaybackSourceClass.p2p,
      );
      return;
    }
    _bufferingWatchdogTicks = 0;

    final publicIptvSource =
        _activeSource != null && _isPublicIptvSource(_activeSource!);

    final libVlcWarmupElapsed = _nativeWallClockStartedAt == null
        ? null
        : DateTime.now().difference(_nativeWallClockStartedAt!);
    final libVlcStillWarmingUp =
        controller.engine == _NativePlaybackEngine.libvlc &&
        position <= Duration.zero &&
        libVlcWarmupElapsed != null &&
        libVlcWarmupElapsed < _libVlcWarmupGrace;
    final libVlcContinuousTsVisualGraceActive =
        controller.engine == _NativePlaybackEngine.libvlc &&
        _libVlcContinuousTsActive &&
        libVlcWarmupElapsed != null &&
        libVlcWarmupElapsed < _libVlcContinuousTsVisualGrace;

    final libVlcMissingVideoSurface =
        controller.engine == _NativePlaybackEngine.libvlc &&
        !libVlcContinuousTsVisualGraceActive &&
        controller.isPlaying &&
        position > Duration.zero &&
        controller.size == Size.zero;
    final exoMissingVideoSurface =
        controller.engine == _NativePlaybackEngine.exoplayer &&
        controller.isPlaying &&
        position >= const Duration(seconds: 3) &&
        controller.duration > Duration.zero &&
        controller.size == Size.zero &&
        _progressItem?.type != MediaType.music;
    if (libVlcMissingVideoSurface || exoMissingVideoSurface) {
      _blackVideoWatchdogTicks += 1;
      _stallWatchdogTicks = 0;
      _deadPauseTicks = 0;
      _bufferingWatchdogTicks = 0;
      final elapsed = _stallWatchdogInterval * _blackVideoWatchdogTicks;
      if (_blackVideoWatchdogTicks == 1) {
        DiagnosticLog.add(
          'native black video watchdog waiting provider=${_activeSource?.providerId} engine=${controller.engine.id} position=${position.inSeconds}s duration=${controller.duration.inSeconds}s size=0x0',
        );
      }
      _showPlaybackWaitMessage(
        'Refreshing video surface...',
        reason: 'black_video_watchdog',
      );
      final zeroMetadataResume =
          _activeSourceHasZeroClockMetadata &&
          (position >= const Duration(seconds: 3) ||
              _lastKnownPlaybackPosition >= const Duration(seconds: 3));
      if ((zeroMetadataResume || elapsed >= _blackVideoWatchdogWindow) &&
          AppState.playerBehaviorSettings.value.autoSwitchOnStall) {
        final recoveryPosition = _effectiveRecoveryPosition(position);
        DiagnosticLog.add(
          'native black video watchdog provider=${_activeSource?.providerId} engine=${controller.engine.id} position=${position.inSeconds}s elapsed=${elapsed.inSeconds}s action=refresh-surface zeroMetadataResume=$zeroMetadataResume',
        );
        unawaited(_recoverFromBlackVideo(recoveryPosition));
      }
      _lastWatchdogPosition = position;
      return;
    }
    _blackVideoWatchdogTicks = 0;

    if (!controller.isPlaying) {
      if (_exitConfirmationOpen) {
        _lastWatchdogPosition = position;
        _stallWatchdogTicks = 0;
        _deadPauseTicks = 0;
        _bufferingWatchdogTicks = 0;
        _clearPlaybackWaitMessage(reason: 'exit_confirmation');
        return;
      }
      if (_userPaused) {
        _lastWatchdogPosition = position;
        _stallWatchdogTicks = 0;
        _deadPauseTicks = 0;
        _bufferingWatchdogTicks = 0;
        _clearPlaybackWaitMessage(reason: 'user_paused');
        return;
      }
      if (libVlcStillWarmingUp) {
        _lastWatchdogPosition = position;
        _stallWatchdogTicks = 0;
        _deadPauseTicks = 0;
        _bufferingWatchdogTicks = 0;
        DiagnosticLog.add(
          'native libvlc warmup waiting provider=${_activeSource?.providerId} elapsed=${libVlcWarmupElapsed.inSeconds}s duration=${controller.duration.inSeconds}s position=${position.inSeconds}s',
        );
        _showPlaybackWaitMessage(
          'Warming up video engine...',
          reason: 'libvlc_warmup',
        );
        return;
      }
      if (libVlcContinuousTsVisualGraceActive) {
        _lastWatchdogPosition = position;
        _stallWatchdogTicks = 0;
        _deadPauseTicks = 0;
        _bufferingWatchdogTicks = 0;
        if (_libVlcContinuousTsNoVisualRelayStalled(
          controller,
          libVlcWarmupElapsed,
        )) {
          unawaited(
            _recoverLibVlcContinuousTsNoVisual(
              _effectiveRecoveryPosition(position),
              reason: 'libvlc_continuous_ts_inactive_no_visual',
            ),
          );
          return;
        }
        if (_libVlcContinuousTsRelayProofReady) {
          _maybeClearLibVlcContinuousTsWaitMessage(
            reason: 'libvlc_continuous_ts_inactive_relay_proof',
          );
          return;
        }
        DiagnosticLog.add(
          'native libvlc continuous-ts visual grace provider=${_activeSource?.providerId} elapsed=${libVlcWarmupElapsed.inSeconds}s position=${position.inSeconds}s duration=${controller.duration.inSeconds}s size=${controller.size.width.toInt()}x${controller.size.height.toInt()} reason=inactive',
        );
        _showPlaybackWaitMessage(
          'Getting stream details...',
          reason: 'libvlc_continuous_ts_inactive_grace',
        );
        return;
      }
      if (controller.engine == _NativePlaybackEngine.libvlc &&
          _blackVideoWatchdogTicks > 0 &&
          controller.size == Size.zero &&
          AppState.playerBehaviorSettings.value.autoSwitchOnStall) {
        final recoveryPosition = _effectiveRecoveryPosition(position);
        DiagnosticLog.add(
          'native libvlc visual surface inactive provider=${_activeSource?.providerId} position=${position.inSeconds}s action=switch-engine reason=dead-pause-after-zero-size',
        );
        unawaited(_recoverFromBlackVideo(recoveryPosition));
        return;
      }
      _deadPauseTicks += 1;
      DiagnosticLog.add(
        'native playback inactive provider=${_activeSource?.providerId} tick=$_deadPauseTicks position=${position.inSeconds}s',
      );
      if (_deadPauseTicks >= 1 &&
          AppState.playerBehaviorSettings.value.autoSwitchOnStall) {
        _showPlaybackWaitMessage(
          'Recovering playback...',
          reason: 'dead_pause_recovery',
        );
        unawaited(_recoverFromPlaybackStall(position));
      }
      return;
    }

    final moved =
        (position - _lastWatchdogPosition).abs() >
        const Duration(milliseconds: 850);
    _lastWatchdogPosition = position;
    if (moved) {
      _stallWatchdogTicks = 0;
      _deadPauseTicks = 0;
      _bufferingWatchdogTicks = 0;
      _clearPlaybackWaitMessage(reason: 'playback_progress');
      _maybeRecordDeferredLibVlcOpenSuccess(
        controller,
        reason: 'watchdog_playback_progress',
      );
      _rememberVerifiedSource(controller, position);
      return;
    }

    if (libVlcContinuousTsVisualGraceActive) {
      _stallWatchdogTicks = 0;
      _deadPauseTicks = 0;
      _bufferingWatchdogTicks = 0;
      if (_libVlcContinuousTsNoVisualRelayStalled(
        controller,
        libVlcWarmupElapsed,
      )) {
        unawaited(
          _recoverLibVlcContinuousTsNoVisual(
            _effectiveRecoveryPosition(position),
            reason: 'libvlc_continuous_ts_stall_no_visual',
          ),
        );
        return;
      }
      if (_libVlcContinuousTsRelayProofReady) {
        _maybeClearLibVlcContinuousTsWaitMessage(
          reason: 'libvlc_continuous_ts_stall_relay_proof',
        );
        return;
      }
      DiagnosticLog.add(
        'native libvlc continuous-ts visual grace provider=${_activeSource?.providerId} elapsed=${libVlcWarmupElapsed.inSeconds}s position=${position.inSeconds}s duration=${controller.duration.inSeconds}s size=${controller.size.width.toInt()}x${controller.size.height.toInt()} reason=stall_grace',
      );
      _showPlaybackWaitMessage(
        'Getting stream details...',
        reason: 'libvlc_continuous_ts_stall_grace',
        pausePlayback: false,
      );
      return;
    }

    if (publicIptvSource &&
        controller.engine == _NativePlaybackEngine.exoplayer) {
      _stallWatchdogTicks += 1;
      if (_stallWatchdogTicks < 6) {
        DiagnosticLog.add(
          'native live tv stall grace provider=${_activeSource?.providerId} tick=$_stallWatchdogTicks position=${position.inSeconds}s engine=${controller.engine.id}',
        );
        _clearPlaybackWaitMessage(reason: 'live_tv_stall_grace');
        return;
      }
    } else {
      _stallWatchdogTicks += 1;
    }

    if (libVlcStillWarmingUp) {
      DiagnosticLog.add(
        'native libvlc warmup waiting provider=${_activeSource?.providerId} elapsed=${libVlcWarmupElapsed.inSeconds}s duration=${controller.duration.inSeconds}s position=${position.inSeconds}s',
      );
      _showPlaybackWaitMessage(
        'Warming up video engine...',
        reason: 'libvlc_warmup_stall',
        pausePlayback: false,
      );
      return;
    }
    if (controller.engine == _NativePlaybackEngine.libvlc &&
        _stallWatchdogTicks < 2) {
      DiagnosticLog.add(
        'native libvlc stall grace provider=${_activeSource?.providerId} tick=$_stallWatchdogTicks position=${position.inSeconds}s',
      );
      _showPlaybackWaitMessage(
        'Checking stream...',
        reason: 'libvlc_stall_grace',
        pausePlayback: false,
      );
      return;
    }
    final p2pStallGraceTicks =
        _activeSource?.sourceClass == PlaybackSourceClass.p2p ? 3 : 1;
    if (_stallWatchdogTicks < p2pStallGraceTicks) {
      DiagnosticLog.add(
        'native p2p stall grace provider=${_activeSource?.providerId} tick=$_stallWatchdogTicks position=${position.inSeconds}s',
      );
      _showPlaybackWaitMessage(
        'Buffering stream...',
        reason: 'p2p_stall_grace',
        pausePlayback: false,
      );
      return;
    }
    if (_stallWatchdogTicks >= p2pStallGraceTicks &&
        AppState.playerBehaviorSettings.value.autoSwitchOnStall) {
      _showPlaybackWaitMessage(
        'Recovering playback...',
        reason: 'stall_recovery',
      );
      unawaited(_recoverFromPlaybackStall(position));
    }
  }

  void _trackLastKnownPlaybackPosition() {
    final controller = _controller;
    if (controller == null ||
        !controller.isInitialized ||
        controller.hasError) {
      return;
    }

    final duration = controller.duration;
    final position = _resumeAnchoredPlaybackPosition(controller);
    if (position.inSeconds < 3) return;

    if (duration.inSeconds > 0) {
      _lastKnownPlaybackDuration = duration;
    }
    if (position > _lastKnownPlaybackPosition ||
        (_lastKnownPlaybackPosition - position).abs() >
            const Duration(seconds: 10)) {
      _lastKnownPlaybackPosition = position;
    }
  }

  Duration _resumeAnchoredPlaybackPosition(
    _NativePlaybackController? controller,
  ) {
    final controllerPosition = controller?.position ?? Duration.zero;
    if (controller == null ||
        controller.engine != _NativePlaybackEngine.libvlc ||
        _resumeProgressAnchorPosition <= Duration.zero ||
        controllerPosition >=
            _resumeProgressAnchorPosition - const Duration(seconds: 10)) {
      return controllerPosition;
    }
    final anchoredPosition = _resumeProgressAnchorPosition + controllerPosition;
    if (controllerPosition <= const Duration(seconds: 10) &&
        controllerPosition.inSeconds != _resumeProgressAnchorLogSecond) {
      _resumeProgressAnchorLogSecond = controllerPosition.inSeconds;
      DiagnosticLog.add(
        'native libvlc resume-local progress anchored raw=${controllerPosition.inSeconds}s anchor=${_resumeProgressAnchorPosition.inSeconds}s effective=${anchoredPosition.inSeconds}s',
      );
    }
    return anchoredPosition;
  }

  Duration _bestKnownProgressPosition(
    _NativePlaybackController? controller,
    Duration duration,
  ) {
    final controllerPosition = _resumeAnchoredPlaybackPosition(controller);
    var position = controllerPosition > Duration.zero
        ? controllerPosition
        : _lastKnownPlaybackPosition;
    if (_lastKnownPlaybackPosition > Duration.zero &&
        (position <= Duration.zero ||
            _lastKnownPlaybackPosition > position ||
            (position - _lastKnownPlaybackPosition).abs() >
                const Duration(seconds: 10))) {
      position = _lastKnownPlaybackPosition;
    }
    if (duration > const Duration(seconds: 20) &&
        position >= duration - const Duration(seconds: 1)) {
      return duration - const Duration(seconds: 1);
    }
    return position;
  }

  Duration _bestKnownProgressDuration(_NativePlaybackController? controller) {
    final controllerDuration = controller?.duration ?? Duration.zero;
    if (controllerDuration > Duration.zero) return controllerDuration;
    if (_lastKnownPlaybackDuration > Duration.zero) {
      return _lastKnownPlaybackDuration;
    }
    final fallbackSeconds = _fallbackProgressDurationSeconds();
    if (fallbackSeconds != null && fallbackSeconds > 0) {
      return Duration(seconds: fallbackSeconds);
    }
    final item = _progressItem;
    if (item == null) return Duration.zero;
    return Duration(
      seconds: item.type.isPlayableSeries ? 10 * 60 * 60 : 45 * 60,
    );
  }

  Duration _qualitySwitchResumePosition() {
    _trackLastKnownPlaybackPosition();
    final duration = _bestKnownProgressDuration(_controller);
    final position = _bestKnownProgressPosition(_controller, duration);
    DiagnosticLog.add(
      'native quality switch resume anchor position=${position.inSeconds}s duration=${duration.inSeconds}s',
    );
    return position;
  }

  void _resetPlaybackIntegritySample() {
    _lastIntegritySampleAt = null;
    _lastIntegrityPosition = null;
  }

  void _syncPlaybackIntegrity(_NativePlaybackController controller) {
    final item = _progressItem;
    final key = _playbackKey;
    if (item == null || key == null) {
      _resetPlaybackIntegritySample();
      return;
    }
    if (_integrityPlaybackKey != key) {
      _integrityPlaybackKey = key;
      _credibleWatchMilliseconds =
          (AppState.progressFor(
                item,
                playbackKey: key,
              )?.credibleWatchedSeconds ??
              0) *
          1000;
      _seekAbuseEvents = 0;
      _resetPlaybackIntegritySample();
    }
    final duration = _bestKnownProgressDuration(controller);
    final position = _bestKnownProgressPosition(controller, duration);
    if (!controller.isInitialized ||
        controller.hasError ||
        duration <= Duration.zero ||
        position <= Duration.zero) {
      _lastIntegritySampleAt = DateTime.now();
      _lastIntegrityPosition = position;
      return;
    }

    _creditPlaybackIntegrityPosition(position, reason: 'controller');
  }

  void _creditPlaybackIntegrityPosition(
    Duration position, {
    required String reason,
  }) {
    final now = DateTime.now();
    final previousAt = _lastIntegritySampleAt;
    final previousPosition = _lastIntegrityPosition;
    if (previousAt == null || previousPosition == null) {
      _lastIntegritySampleAt = now;
      _lastIntegrityPosition = position;
      return;
    }

    final wallDeltaMs = now.difference(previousAt).inMilliseconds;
    final positionDeltaMs =
        position.inMilliseconds - previousPosition.inMilliseconds;
    if (wallDeltaMs <= 250) return;
    if (positionDeltaMs <= 250) {
      _lastIntegritySampleAt = now;
      _lastIntegrityPosition = position;
      return;
    }

    final speed = math.max(_playbackSpeed, 1.0);
    final allowedDeltaMs = (wallDeltaMs * speed * 1.45 + 1250).round();
    if (positionDeltaMs > allowedDeltaMs) {
      _lastIntegritySampleAt = now;
      _lastIntegrityPosition = position;
      if (positionDeltaMs > 5000) {
        _seekAbuseEvents += 1;
        if (_seekAbuseEvents == 1 || _seekAbuseEvents == 3) {
          DiagnosticLog.add(
            'native metrics integrity ignored jump positionDelta=${(positionDeltaMs / 1000).toStringAsFixed(1)}s wallDelta=${(wallDeltaMs / 1000).toStringAsFixed(1)}s events=$_seekAbuseEvents',
          );
        }
      }
      return;
    }

    final credibleDeltaMs = math.min(
      positionDeltaMs,
      (wallDeltaMs * speed).round(),
    );
    _lastIntegritySampleAt = now;
    _lastIntegrityPosition = position;
    final beforeSeconds = _credibleWatchSeconds;
    _credibleWatchMilliseconds += credibleDeltaMs.clamp(0, 10000).toInt();
    final afterSeconds = _credibleWatchSeconds;
    if ((beforeSeconds == 0 && afterSeconds > 0) ||
        afterSeconds ~/ 60 > beforeSeconds ~/ 60) {
      DiagnosticLog.add(
        'native metrics integrity credited activeWatch=${afterSeconds}s delta=${(credibleDeltaMs / 1000).toStringAsFixed(1)}s reason=$reason',
      );
    }
  }

  int get _credibleWatchSeconds => (_credibleWatchMilliseconds / 1000).floor();

  void _markManualSeekForIntegrity(
    Duration from,
    Duration to, {
    required String reason,
  }) {
    final forwardDelta = to - from;
    if (forwardDelta > const Duration(seconds: 2)) {
      _seekAbuseEvents += 1;
      if (_seekAbuseEvents == 1 || _seekAbuseEvents == 3) {
        DiagnosticLog.add(
          'native metrics integrity manual seek reason=$reason delta=${forwardDelta.inSeconds}s events=$_seekAbuseEvents',
        );
      }
    }
    _lastIntegritySampleAt = DateTime.now();
    _lastIntegrityPosition = to;
  }

  Duration _effectiveRecoveryPosition(Duration reportedPosition) {
    if (reportedPosition.inSeconds >= 3) return reportedPosition;
    if (_lastKnownPlaybackPosition.inSeconds >= 3)
      return _lastKnownPlaybackPosition;
    return reportedPosition;
  }

  void _clearControllerErrorGrace() {
    _firstControllerErrorAt = null;
    _lastControllerErrorDescription = null;
    _controllerErrorGraceLogs = 0;
  }

  bool _shouldDeferControllerErrorRecovery(
    _NativePlaybackController controller, {
    required String reason,
  }) {
    final now = DateTime.now();
    final position = controller.position;
    final description = controller.errorDescription;
    final hadUsefulPlayback =
        position >= const Duration(seconds: 5) ||
        _lastKnownPlaybackPosition >= const Duration(seconds: 5);
    final movedSinceWatchdog =
        (position - _lastWatchdogPosition).abs() >=
        const Duration(milliseconds: 850);
    final libVlcWarmupElapsed = _nativeWallClockStartedAt == null
        ? null
        : now.difference(_nativeWallClockStartedAt!);
    final libVlcStillGatheringMetadata =
        controller.engine == _NativePlaybackEngine.libvlc &&
        controller.isInitialized &&
        position <= Duration.zero &&
        controller.size == Size.zero &&
        libVlcWarmupElapsed != null &&
        libVlcWarmupElapsed < _libVlcWarmupGrace;

    if (libVlcStillGatheringMetadata) {
      if (_controllerErrorGraceLogs < 3) {
        DiagnosticLog.add(
          'native playback error deferred reason=$reason provider=${_activeSource?.providerId} engine=libvlc elapsed=${libVlcWarmupElapsed.inMilliseconds}ms position=${position.inSeconds}s duration=${controller.duration.inSeconds}s size=0x0 phase=warmup error=$description',
        );
        _controllerErrorGraceLogs += 1;
      }
      return true;
    }

    if (hadUsefulPlayback && controller.isPlaying && movedSinceWatchdog) {
      if (_controllerErrorGraceLogs < 2) {
        DiagnosticLog.add(
          'native playback error deferred reason=$reason provider=${_activeSource?.providerId} position=${position.inSeconds}s progress=moving error=$description',
        );
        _controllerErrorGraceLogs += 1;
      }
      _clearControllerErrorGrace();
      return true;
    }

    if (!hadUsefulPlayback) return false;

    if (_firstControllerErrorAt == null ||
        _lastControllerErrorDescription != description) {
      _firstControllerErrorAt = now;
      _lastControllerErrorDescription = description;
      _controllerErrorGraceLogs = 1;
      DiagnosticLog.add(
        'native playback error grace started reason=$reason provider=${_activeSource?.providerId} position=${position.inSeconds}s lastKnown=${_lastKnownPlaybackPosition.inSeconds}s error=$description',
      );
      return true;
    }

    final elapsed = now.difference(_firstControllerErrorAt!);
    if (elapsed < const Duration(seconds: 3)) {
      if (_controllerErrorGraceLogs < 3) {
        DiagnosticLog.add(
          'native playback error grace waiting reason=$reason provider=${_activeSource?.providerId} elapsed=${elapsed.inMilliseconds}ms position=${position.inSeconds}s error=$description',
        );
        _controllerErrorGraceLogs += 1;
      }
      return true;
    }

    return false;
  }

  Future<void> _recoverFromBlackVideo(Duration resumePosition) async {
    if (_playerClosing) return;
    if (_settingsExpanded || _optionSheetOpen) return;
    if (_recoveringFromStall) return;
    final source = _activeSource;
    if (source == null) return;
    final controller = _controller;
    if (_libVlcContinuousTsPlaybackActive(controller)) {
      DiagnosticLog.add(
        'native black video recovery skipped reason=libvlc_continuous_ts_playing provider=${source.providerId} watched=${_lastSavedSecond}s position=${controller?.position.inSeconds ?? 0}s',
      );
      return;
    }
    _recoveringFromStall = true;
    _blackVideoWatchdogTicks = 0;
    if (controller?.engine == _NativePlaybackEngine.libvlc) {
      if (_manualLibVlcStrictForSource(source)) {
        if (_advanceLibVlcProfileForSource(
          source,
          reason: 'black_video_manual_libvlc',
        )) {
          _manualLibVlcNoProofOpensByUrl.remove(source.url);
          final profile = _libVlcProfileForSource(source);
          DiagnosticLog.add(
            'native black video libvlc fallback provider=${source.providerId} action=try_libvlc_profile profile=${profile.id} reason=manual_libvlc_locked',
          );
          _sendPlaybackFeedback('black_video', source: source);
          if (mounted) {
            const status = 'Trying another libVLC profile...';
            _pauseActivePlaybackForLoading(
              'black_video_manual_libvlc_profile_retry',
            );
            _logPlaybackStatus(
              status,
              reason: 'black_video_manual_libvlc_profile_retry',
            );
            setState(() {
              _loading = true;
              _controlsVisible = true;
              _settingsExpanded = false;
              _statusMessage = status;
            });
          }
          await _disposeCurrentController(
            awaitLibVlcRelease: false,
            saveProgress: true,
          );
          if (!mounted) return;
          _activeSource = null;
          _recoveringFromStall = false;
          final recovered = await _openSource(
            source,
            resumePosition: resumePosition,
            statusMessage: 'Trying another libVLC profile...',
            engineOverride: _NativePlaybackEngine.libvlc,
          );
          if (recovered) return;
          _recoveringFromStall = true;
        } else {
          DiagnosticLog.add(
            'native black video libvlc fallback provider=${source.providerId} action=profile_ladder_exhausted position=${resumePosition.inSeconds}s reason=manual_libvlc_locked',
          );
        }
        final nextSourceIndex =
            _nextSourceIndexAfterHardFailure(_activeSources, _sourceIndex) ??
            _sourceIndex + 1;
        DiagnosticLog.add(
          'native black video libvlc fallback provider=${source.providerId} action=try_next_libvlc_source position=${resumePosition.inSeconds}s nextSourceIndex=$nextSourceIndex reason=manual_libvlc_locked',
        );
        _sendPlaybackFeedback('black_video', source: source);
        _markRuntimeSourceFailure(source, 'libvlc_black_video');
        _failedSourceAttempts[source.url] =
            (_failedSourceAttempts[source.url] ?? 0) + 1;
        _sourceIndex = nextSourceIndex;
        _sameSourceRecoveryAttempts = 0;
        if (mounted) {
          const status = 'Trying next libVLC stream...';
          _pauseActivePlaybackForLoading('black_video_libvlc_next_source');
          _logPlaybackStatus(status, reason: 'black_video_libvlc_next_source');
          setState(() {
            _loading = true;
            _controlsVisible = true;
            _settingsExpanded = false;
            _statusMessage = status;
          });
        }
        await _disposeCurrentController(
          awaitLibVlcRelease: false,
          saveProgress: true,
        );
        _activeSource = null;
        _recoveringFromStall = false;
        await _openNextAvailableSource();
        return;
      }
      DiagnosticLog.add(
        'native black video libvlc fallback provider=${source.providerId} action=switch-engine position=${resumePosition.inSeconds}s',
      );
      _sendPlaybackFeedback('black_video', source: source);
      DiagnosticLog.add(
        'native verified source cache retained provider=${source.providerId} '
        'reason=libvlc_black_video_engine_fallback url=[hidden]',
      );
      _libvlcUnavailableForSession = true;
      _switchPlaybackEngineToAutoAfterLibVlcFailure(source.providerId);
      _sourceIndex = _activeSources.indexWhere(
        (candidate) => candidate.url == source.url,
      );
      if (_sourceIndex < 0) _sourceIndex = 0;
      _sameSourceRecoveryAttempts = 0;
      if (mounted) {
        const status = 'Switching video engine...';
        _pauseActivePlaybackForLoading('black_video_engine_fallback');
        _logPlaybackStatus(status, reason: 'black_video_engine_fallback');
        setState(() {
          _loading = true;
          _controlsVisible = true;
          _settingsExpanded = false;
          _statusMessage = status;
        });
      }
      await _disposeCurrentController(
        awaitLibVlcRelease: false,
        saveProgress: true,
      );
      if (!mounted) return;
      final recovered = await _retrySourceWithExoPlayerAfterLibVlcFailure(
        source,
        resumePosition,
        statusMessage: 'Switching video engine...',
        reason: 'libvlc_visual_surface',
      );
      _recoveringFromStall = false;
      if (recovered) return;
      _recoveringFromStall = true;
      await _openNextAvailableSource();
      _recoveringFromStall = false;
      return;
    }
    if (controller?.engine == _NativePlaybackEngine.exoplayer &&
        controller?.media3 != null &&
        !_media3NativeFallbackUrls.contains(source.url)) {
      DiagnosticLog.add(
        'native media3 surface fallback provider=${source.providerId} action=retry_texture reason=black_video_platform_view position=${resumePosition.inSeconds}s',
      );
      _media3NativeFallbackUrls.add(source.url);
      _sendPlaybackFeedback('black_video', source: source);
      _markRuntimeSourceFailure(source, 'media3_platform_view_black_video');
      if (mounted) {
        const status = 'Refreshing video surface...';
        _pauseActivePlaybackForLoading('media3_native_surface_fallback');
        _logPlaybackStatus(status, reason: 'media3_native_surface_fallback');
        setState(() {
          _loading = true;
          _controlsVisible = true;
          _settingsExpanded = false;
          _statusMessage = status;
        });
      }
      await _disposeCurrentController(
        awaitLibVlcRelease: false,
        saveProgress: true,
      );
      if (!mounted) return;
      _activeSource = null;
      _recoveringFromStall = false;
      final recovered = await _openSource(
        source,
        resumePosition: resumePosition,
        statusMessage: 'Refreshing video surface...',
        engineOverride: _NativePlaybackEngine.exoplayer,
      );
      if (recovered) return;
      _recoveringFromStall = true;
    }
    final alreadyRefreshed = !_blackVideoRecoveredUrls.add(source.url);
    if (alreadyRefreshed) {
      DiagnosticLog.add(
        'native black video repeated provider=${source.providerId} action=skip-source position=${resumePosition.inSeconds}s',
      );
      _sendPlaybackFeedback('black_video', source: source);
      _forgetVerifiedSource(source, 'black_video_repeated');
      if (mounted) {
        final status = _nextSourceStatusFor(skipProvider: false);
        _pauseActivePlaybackForLoading('black_video_advance');
        _logPlaybackStatus(status, reason: 'black_video_advance');
        setState(() {
          _loading = true;
          _controlsVisible = true;
          _settingsExpanded = false;
          _statusMessage = status;
        });
      }
      final nextGroupedSourceIndex = _nextSourceIndexInCurrentVisibleGroup(
        _activeSources,
        _sourceIndex,
      );
      if (nextGroupedSourceIndex != null) {
        _sourceIndex = nextGroupedSourceIndex;
      } else {
        final nextVisibleIndex = _nextSourceIndexAfterCurrentVisibleGroup(
          _activeSources,
          _sourceIndex,
        );
        _sourceIndex = nextVisibleIndex ?? (_sourceIndex + 1);
      }
      _sameSourceRecoveryAttempts = 0;
      await _openNextAvailableSource();
      _recoveringFromStall = false;
      return;
    }

    if (controller?.engine == _NativePlaybackEngine.exoplayer) {
      if (_effectivePlaybackEngine != 'auto') {
        DiagnosticLog.add(
          'native black video exoplayer fallback provider=${source.providerId} action=try_next_exoplayer_source position=${resumePosition.inSeconds}s reason=manual_engine_locked',
        );
        _sendPlaybackFeedback('black_video', source: source);
        _markRuntimeSourceFailure(source, 'exoplayer_black_video');
        _failedSourceAttempts[source.url] =
            (_failedSourceAttempts[source.url] ?? 0) + 1;
        final nextSourceIndex =
            _nextSourceIndexAfterHardFailure(_activeSources, _sourceIndex) ??
            _sourceIndex + 1;
        _sourceIndex = nextSourceIndex;
        _sameSourceRecoveryAttempts = 0;
        if (mounted) {
          final status = _nextSourceStatusFor(skipProvider: false);
          _pauseActivePlaybackForLoading('black_video_exoplayer_next_source');
          _logPlaybackStatus(
            status,
            reason: 'black_video_exoplayer_next_source',
          );
          setState(() {
            _loading = true;
            _controlsVisible = true;
            _settingsExpanded = false;
            _statusMessage = status;
          });
        }
        await _disposeCurrentController(
          awaitLibVlcRelease: false,
          saveProgress: true,
        );
        _activeSource = null;
        _recoveringFromStall = false;
        await _openNextAvailableSource();
        return;
      }
      DiagnosticLog.add(
        'native black video exoplayer fallback provider=${source.providerId} action=switch-engine position=${resumePosition.inSeconds}s',
      );
      _sendPlaybackFeedback('black_video', source: source);
      if (mounted) {
        const status = 'Switching video engine...';
        _pauseActivePlaybackForLoading('black_video_exoplayer_libvlc');
        _logPlaybackStatus(status, reason: 'black_video_exoplayer_libvlc');
        setState(() {
          _loading = true;
          _controlsVisible = true;
          _settingsExpanded = false;
          _statusMessage = status;
        });
      }
      await _disposeCurrentController(
        awaitLibVlcRelease: false,
        saveProgress: true,
      );
      if (!mounted) return;
      final recovered = await _retrySourceWithLibVlcAfterExoVisualFailure(
        source,
        resumePosition,
        statusMessage: 'Switching video engine...',
        reason: 'exoplayer_visual_surface',
      );
      _recoveringFromStall = false;
      if (recovered) return;
      _recoveringFromStall = true;
    }

    DiagnosticLog.add(
      'native black video recovery provider=${source.providerId} action=reopen-source position=${resumePosition.inSeconds}s',
    );
    _sendPlaybackFeedback('black_video', source: source);
    if (mounted) {
      const status = 'Refreshing video surface...';
      _pauseActivePlaybackForLoading('black_video_refresh');
      _logPlaybackStatus(status, reason: 'black_video_refresh');
      setState(() {
        _loading = true;
        _controlsVisible = true;
        _settingsExpanded = false;
        _statusMessage = status;
      });
    }
    final opened = await _openSource(
      source,
      resumePosition: resumePosition,
      statusMessage: 'Refreshing video surface...',
    );
    _recoveringFromStall = false;
    if (!opened && mounted) {
      unawaited(_recoverFromPlaybackStall(resumePosition));
    }
  }

  Future<void> _recoverLibVlcContinuousTsNoVisual(
    Duration resumePosition, {
    required String reason,
  }) async {
    if (_playerClosing) return;
    if (_settingsExpanded || _optionSheetOpen) return;
    if (_recoveringFromStall) return;
    final source = _activeSource;
    if (source == null) return;
    final controller = _controller;
    final position = controller?.position ?? resumePosition;
    final duration = controller?.duration ?? Duration.zero;
    final size = controller?.size ?? Size.zero;
    _recoveringFromStall = true;
    DiagnosticLog.add(
      'native libvlc continuous-ts visual stalled provider=${source.providerId} position=${position.inSeconds}s duration=${duration.inSeconds}s size=${size.width.toInt()}x${size.height.toInt()} streamed=${_countDiagnosticBucket(_libVlcContinuousTsStreamedSegments)} reason=$reason action=recover',
    );
    _sendPlaybackFeedback('black_video', source: source);
    if (mounted) {
      const status = 'Recovering playback...';
      _pauseActivePlaybackForLoading('libvlc_continuous_ts_no_visual');
      _logPlaybackStatus(status, reason: 'libvlc_continuous_ts_no_visual');
      setState(() {
        _loading = true;
        _controlsVisible = true;
        _settingsExpanded = false;
        _statusMessage = status;
        _playbackWaitMessage = null;
        _playbackWaitMessagePausedPlayback = false;
      });
    }
    await _disposeCurrentController(
      updateUi: false,
      awaitLibVlcRelease: false,
      saveProgress: true,
    );
    if (!mounted) return;
    if (_manualLibVlcStrictForSource(source)) {
      if (_advanceLibVlcProfileForSource(
        source,
        reason: 'continuous_ts_no_visual',
      )) {
        _manualLibVlcNoProofOpensByUrl.remove(source.url);
        final profile = _libVlcProfileForSource(source);
        DiagnosticLog.add(
          'native libvlc continuous-ts visual stalled provider=${source.providerId} action=try_libvlc_profile profile=${profile.id} reason=manual_libvlc_locked',
        );
        _logPlaybackStatus(
          'Trying another libVLC profile...',
          reason: 'continuous_ts_no_visual_profile_retry',
        );
        _activeSource = null;
        _recoveringFromStall = false;
        final recovered = await _openSource(
          source,
          resumePosition: resumePosition,
          statusMessage: 'Trying another libVLC profile...',
          engineOverride: _NativePlaybackEngine.libvlc,
        );
        if (recovered) return;
        _recoveringFromStall = true;
      } else {
        DiagnosticLog.add(
          'native libvlc continuous-ts visual stalled provider=${source.providerId} action=profile_ladder_exhausted reason=manual_libvlc_locked',
        );
      }
      _markRuntimeSourceFailure(source, 'libvlc_continuous_ts_no_visual');
      _failedSourceAttempts[source.url] =
          (_failedSourceAttempts[source.url] ?? 0) + 1;
      final nextSourceIndex =
          _nextSourceIndexAfterHardFailure(_activeSources, _sourceIndex) ??
          _sourceIndex + 1;
      DiagnosticLog.add(
        'native libvlc continuous-ts visual stalled provider=${source.providerId} action=try_next_libvlc_source nextSourceIndex=$nextSourceIndex reason=manual_libvlc_locked',
      );
      _sourceIndex = nextSourceIndex;
      _sameSourceRecoveryAttempts = 0;
      _activeSource = null;
      _recoveringFromStall = false;
      await _openNextAvailableSource();
      return;
    }
    _libvlcUnavailableForSession = true;
    _switchPlaybackEngineToAutoAfterLibVlcFailure(source.providerId);
    final recovered = await _retrySourceWithExoPlayerAfterLibVlcFailure(
      source,
      resumePosition,
      statusMessage: 'Switching video engine...',
      reason: 'libvlc_continuous_ts_no_visual',
    );
    _recoveringFromStall = false;
    if (recovered) return;
    _recoveringFromStall = true;
    await _openNextAvailableSource();
    _recoveringFromStall = false;
  }

  Future<void> _recoverFromPlaybackStall(
    Duration stalledPosition, {
    bool skipSameSource = true,
    bool skipProvider = false,
  }) async {
    if (_playerClosing) return;
    if (_settingsExpanded || _optionSheetOpen) return;
    if (_recoveringFromStall) return;
    final controller = _controller;
    if (_libVlcContinuousTsPlaybackActive(controller)) {
      DiagnosticLog.add(
        'native stall recovery skipped reason=libvlc_continuous_ts_playing provider=${_activeSource?.providerId} watched=${_lastSavedSecond}s position=${controller?.position.inSeconds ?? stalledPosition.inSeconds}s',
      );
      return;
    }
    _recoveringFromStall = true;
    _showPlaybackWaitMessage(
      'Recovering playback...',
      reason: 'recover_from_stall_start',
    );
    DiagnosticLog.add(
      'native playback stalled provider=${_activeSource?.providerId} position=${stalledPosition.inSeconds}s skipSameSource=$skipSameSource skipProvider=$skipProvider',
    );
    _sendPlaybackFeedback('stall');

    final libVlcZeroMetadataStall =
        controller != null &&
        controller.engine == _NativePlaybackEngine.libvlc &&
        _activeSourceHasZeroClockMetadata;
    final sourceBeforeRecovery = _activeSource;
    if (libVlcZeroMetadataStall && _zeroClockSkipEnabled) {
      final providerId = _activeSource?.providerId;
      _lastOpenFailureMessage = 'libVLC could not open the available source.';
      DiagnosticLog.add(
        'native libvlc zero-metadata stall provider=${providerId ?? 'unknown'} position=${stalledPosition.inSeconds}s action=libvlc_zero_metadata_recovery scope=source',
      );
      _saveNativeProgress(force: true);
      final shouldAwaitRelease =
          sourceBeforeRecovery == null ||
          !_isPublicIptvSource(sourceBeforeRecovery);
      await _disposeCurrentController(
        updateUi: false,
        awaitLibVlcRelease: shouldAwaitRelease,
        saveProgress: false,
      );
      final settle = _libVlcReleaseSettle;
      if (settle > Duration.zero) {
        DiagnosticLog.add(
          'native libvlc release settle delay=${settle.inMilliseconds}ms reason=zero-clock-skip',
        );
        await Future<void>.delayed(settle);
        if (!mounted) return;
      }
      if (sourceBeforeRecovery != null) {
        if (_manualLibVlcStrictForSource(sourceBeforeRecovery)) {
          if (_advanceLibVlcProfileForSource(
            sourceBeforeRecovery,
            reason: 'zero_metadata_manual_libvlc',
          )) {
            _manualLibVlcNoProofOpensByUrl.remove(sourceBeforeRecovery.url);
            final profile = _libVlcProfileForSource(sourceBeforeRecovery);
            DiagnosticLog.add(
              'native libvlc zero-metadata stall provider=${sourceBeforeRecovery.providerId} action=try_libvlc_profile profile=${profile.id} reason=manual_libvlc_locked',
            );
            _logPlaybackStatus(
              'Trying another libVLC profile...',
              reason: 'libvlc_zero_metadata_profile_retry',
            );
            _activeSource = null;
            _recoveringFromStall = false;
            final recovered = await _openSource(
              sourceBeforeRecovery,
              resumePosition: _lastKnownPlaybackPosition > Duration.zero
                  ? _lastKnownPlaybackPosition
                  : stalledPosition,
              statusMessage: 'Trying another libVLC profile...',
              engineOverride: _NativePlaybackEngine.libvlc,
            );
            if (recovered) return;
            _recoveringFromStall = true;
          } else {
            DiagnosticLog.add(
              'native libvlc zero-metadata stall provider=${sourceBeforeRecovery.providerId} action=profile_ladder_exhausted reason=manual_libvlc_locked',
            );
          }
          _markRuntimeSourceFailure(
            sourceBeforeRecovery,
            'libvlc_zero_metadata',
          );
          _failedSourceAttempts[sourceBeforeRecovery.url] =
              (_failedSourceAttempts[sourceBeforeRecovery.url] ?? 0) + 1;
          final nextSourceIndex =
              _nextSourceIndexAfterHardFailure(_activeSources, _sourceIndex) ??
              _sourceIndex + 1;
          DiagnosticLog.add(
            'native libvlc zero-metadata stall provider=${sourceBeforeRecovery.providerId} action=try_next_libvlc_source nextSourceIndex=$nextSourceIndex reason=manual_libvlc_locked',
          );
          _sourceIndex = nextSourceIndex;
          _sameSourceRecoveryAttempts = 0;
          _activeSource = null;
          _recoveringFromStall = false;
          await _openNextAvailableSource();
          return;
        } else {
          if (_effectivePlaybackEngine == 'auto') {
            if (_advanceLibVlcProfileForSource(
              sourceBeforeRecovery,
              reason: 'zero_metadata_auto_libvlc',
            )) {
              final profile = _libVlcProfileForSource(sourceBeforeRecovery);
              DiagnosticLog.add(
                'native libvlc zero-metadata stall provider=${sourceBeforeRecovery.providerId} action=try_libvlc_profile profile=${profile.id} reason=auto_engine',
              );
              _logPlaybackStatus(
                'Trying another libVLC profile...',
                reason: 'libvlc_zero_metadata_auto_profile_retry',
              );
              _activeSource = null;
              _recoveringFromStall = false;
              final recovered = await _openSource(
                sourceBeforeRecovery,
                resumePosition: _lastKnownPlaybackPosition > Duration.zero
                    ? _lastKnownPlaybackPosition
                    : stalledPosition,
                statusMessage: 'Trying another libVLC profile...',
                engineOverride: _NativePlaybackEngine.libvlc,
              );
              if (recovered) return;
              _recoveringFromStall = true;
            } else {
              DiagnosticLog.add(
                'native libvlc zero-metadata stall provider=${sourceBeforeRecovery.providerId} action=profile_ladder_exhausted reason=auto_engine',
              );
            }
            _markRuntimeSourceFailure(
              sourceBeforeRecovery,
              'libvlc_zero_metadata',
            );
            _failedSourceAttempts[sourceBeforeRecovery.url] =
                (_failedSourceAttempts[sourceBeforeRecovery.url] ?? 0) + 1;
            final nextSourceIndex = _nextSourceIndexAfterHardFailure(
              _activeSources,
              _sourceIndex,
            );
            if (nextSourceIndex != null) {
              DiagnosticLog.add(
                'native libvlc zero-metadata stall provider=${sourceBeforeRecovery.providerId} action=try_next_libvlc_source nextSourceIndex=$nextSourceIndex reason=auto_engine',
              );
              _sourceIndex = nextSourceIndex;
              _sameSourceRecoveryAttempts = 0;
              _activeSource = null;
              _recoveringFromStall = false;
              await _openNextAvailableSource();
              return;
            }
            if (_looksRiskyForMedia3(sourceBeforeRecovery)) {
              DiagnosticLog.add(
                'native libvlc zero-metadata stall provider=${sourceBeforeRecovery.providerId} action=skip_media3_retry reason=media3_risky_source',
              );
              _sourceIndex = _activeSources.length;
              _sameSourceRecoveryAttempts = 0;
              _activeSource = null;
              _recoveringFromStall = false;
              await _openNextAvailableSource();
              return;
            }
          }
          _libvlcUnavailableForSession = true;
          _switchPlaybackEngineToAutoAfterLibVlcFailure(
            sourceBeforeRecovery.providerId,
          );
          final recovered = await _retrySourceWithExoPlayerAfterLibVlcFailure(
            sourceBeforeRecovery,
            _lastKnownPlaybackPosition > Duration.zero
                ? _lastKnownPlaybackPosition
                : stalledPosition,
            statusMessage: 'Refreshing stream...',
            reason: 'libvlc_zero_metadata',
          );
          _recoveringFromStall = false;
          if (recovered) return;
          _recoveringFromStall = true;
        }
      }
    } else if (libVlcZeroMetadataStall) {
      DiagnosticLog.add(
        'native libvlc zero-metadata stall skip disabled; trying regular recovery',
      );
    }
    if (!skipSameSource && controller != null && controller.isInitialized) {
      try {
        await controller.pause();
        final duration = controller.duration;
        final nudge = stalledPosition + const Duration(seconds: 1);
        if (duration <= Duration.zero || nudge < duration) {
          await controller.seekTo(nudge);
        }
        await controller.play();
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        final recovered =
            (controller.position - stalledPosition).abs() >
            const Duration(seconds: 2);
        if (recovered && controller.isPlaying) {
          DiagnosticLog.add('native playback stall recovered with nudge');
          _stallWatchdogTicks = 0;
          _deadPauseTicks = 0;
          _lastWatchdogPosition = controller.position;
          _recoveringFromStall = false;
          _userPaused = false;
          return;
        }
      } catch (error) {
        DiagnosticLog.add(
          'native stall nudge failed error=${_safeDiagnosticError(error)}',
        );
      }
    }

    final source = _activeSource;
    if (!skipSameSource && source != null && _sameSourceRecoveryAttempts < 1) {
      _sameSourceRecoveryAttempts += 1;
      DiagnosticLog.add('native stall reopening current source');
      if (mounted) {
        final status = _refreshingSourceStatusFor();
        _logPlaybackStatus(status, reason: 'stall_refresh_source');
        setState(() {
          _loading = true;
          _playbackWaitMessage = null;
          _playbackWaitMessagePausedPlayback = false;
          _controlsVisible = true;
          _settingsExpanded = false;
          _statusMessage = status;
        });
      }
      final opened = await _openSource(
        source,
        resumePosition: stalledPosition,
        statusMessage: _refreshingSourceStatusFor(),
      );
      _recoveringFromStall = false;
      if (opened) return;
    }

    final hadStableCurrentPlayback =
        _activeSourceVerifiedForSession ||
        (stalledPosition >= const Duration(seconds: 30) &&
            _sourceHasVisualPlaybackProof(controller));
    if (!skipProvider &&
        source != null &&
        !libVlcZeroMetadataStall &&
        stalledPosition > Duration.zero &&
        hadStableCurrentPlayback) {
      DiagnosticLog.add(
        'native stall auto-refreshing verified source provider=${source.providerId} position=${stalledPosition.inSeconds}s reason=avoid_paused_wait',
      );
      if (mounted) {
        _logPlaybackStatus(
          'Refreshing stream...',
          reason: 'stall_auto_refresh_verified',
        );
        setState(() {
          _loading = true;
          _controlsVisible = false;
          _settingsExpanded = false;
          _statusMessage = 'Refreshing stream...';
          _playbackWaitMessage = null;
          _playbackWaitMessagePausedPlayback = false;
        });
      }
      final opened = await _openSource(
        source,
        resumePosition: stalledPosition,
        statusMessage: 'Refreshing stream...',
      );
      _recoveringFromStall = false;
      if (opened) return;
      if (_manualLibVlcStrictForSource(source)) {
        _markRuntimeSourceFailure(source, 'libvlc_refresh_failed');
        _failedSourceAttempts[source.url] =
            (_failedSourceAttempts[source.url] ?? 0) + 1;
        final nextSourceIndex =
            _nextSourceIndexAfterHardFailure(_activeSources, _sourceIndex) ??
            _sourceIndex + 1;
        DiagnosticLog.add(
          'native stall auto-refresh failed provider=${source.providerId} action=try_next_libvlc_source nextSourceIndex=$nextSourceIndex reason=manual_libvlc_locked',
        );
        _sourceIndex = nextSourceIndex;
        _sameSourceRecoveryAttempts = 0;
        if (mounted) {
          const status = 'Trying next libVLC stream...';
          _logPlaybackStatus(status, reason: 'libvlc_refresh_failed_advance');
          setState(() {
            _loading = true;
            _controlsVisible = true;
            _settingsExpanded = false;
            _statusMessage = status;
            _playbackWaitMessage = null;
            _playbackWaitMessagePausedPlayback = false;
          });
        }
        await _openNextAvailableSource();
        return;
      }
      final exoOpened = await _retrySourceWithExoPlayerAfterLibVlcFailure(
        source,
        stalledPosition,
        statusMessage: 'Refreshing stream...',
        reason: 'auto_refresh_failed',
      );
      if (exoOpened) return;
      DiagnosticLog.add(
        'native stall auto-refresh failed provider=${source.providerId} action=pause-scan reason=protect_playback_service',
      );
      if (mounted) {
        const status = 'Stream refresh failed. Please try again in a moment.';
        _logPlaybackStatus(status, reason: 'stall_auto_refresh_failed');
        setState(() {
          _loading = false;
          _controlsVisible = true;
          _settingsExpanded = false;
          _statusMessage = status;
          _playbackWaitMessage = null;
          _playbackWaitMessagePausedPlayback = false;
        });
      }
      return;
    }

    if (!skipProvider &&
        source != null &&
        controller != null &&
        controller.engine == _NativePlaybackEngine.exoplayer &&
        _effectivePlaybackEngine == 'auto' &&
        _media3NativeFallbackUrls.contains(source.url)) {
      DiagnosticLog.add(
        'native stall exoplayer fallback provider=${source.providerId} action=switch-engine reason=media3_texture_stall_after_platform_view_black_video position=${stalledPosition.inSeconds}s',
      );
      if (mounted) {
        const status = 'Switching video engine...';
        _pauseActivePlaybackForLoading('stall_exoplayer_libvlc');
        _logPlaybackStatus(status, reason: 'stall_exoplayer_libvlc');
        setState(() {
          _loading = true;
          _controlsVisible = true;
          _settingsExpanded = false;
          _statusMessage = status;
          _playbackWaitMessage = null;
          _playbackWaitMessagePausedPlayback = false;
        });
      }
      final recovered = await _retrySourceWithLibVlcAfterExoVisualFailure(
        source,
        stalledPosition,
        statusMessage: 'Switching video engine...',
        reason: 'media3_texture_stall_after_platform_view_black_video',
      );
      _recoveringFromStall = false;
      if (recovered) return;
      _recoveringFromStall = true;
      DiagnosticLog.add(
        'native stall exoplayer fallback provider=${source.providerId} action=libvlc_unavailable_try_next_source reason=media3_texture_stall_after_platform_view_black_video',
      );
    }

    if (skipProvider) {
      _hardPlaybackErrors += 1;
      final failedSource = _activeSource;
      final failedProviderId = failedSource?.providerId;
      if (failedSource != null) {
        _markRuntimeSourceFailure(failedSource, 'runtime_error');
      }
      final nextHardSourceIndex = _nextSourceIndexAfterHardFailure(
        _activeSources,
        _sourceIndex,
        controller?.engine,
      );
      if (nextHardSourceIndex != null) {
        DiagnosticLog.add(
          'native hard source error trying next source before provider '
          'provider=${failedSource?.providerId} sourceIndex=$_sourceIndex '
          'nextSourceIndex=$nextHardSourceIndex hardErrors=$_hardPlaybackErrors '
          'reason=media3_codec_or_runtime_fallback',
        );
        await _disposeCurrentController(awaitLibVlcRelease: true);
        _sourceIndex = nextHardSourceIndex;
        _sameSourceRecoveryAttempts = 0;
        await _openNextAvailableSource();
        _recoveringFromStall = false;
        return;
      }
      DiagnosticLog.add(
        'native hard source error provider=${failedProviderId ?? 'unknown'} providerIndex=$_providerIndex sourceIndex=$_sourceIndex hardErrors=$_hardPlaybackErrors; skipping provider',
      );
      if (failedProviderId != null) {
        AppState.recordNativeProviderFailure(
          mediaKey: _playbackKey,
          providerId: failedProviderId,
          sourceCount: _activeSources.isEmpty
              ? null
              : visiblePlaybackSourceCount(_activeSources),
          updateHealth: _shouldUpdateProviderHealthFromPlaybackFailure,
        );
      }
      await _disposeCurrentController(awaitLibVlcRelease: true);
      final recovered = await _tryFreshProviderResolve(stalledPosition);
      if (recovered) {
        _recoveringFromStall = false;
        return;
      }
    } else {
      DiagnosticLog.add('native stall trying next source/provider');
    }
    if (mounted) {
      final status = _nextSourceStatusFor(skipProvider: skipProvider);
      _pauseActivePlaybackForLoading('stall_advance');
      _logPlaybackStatus(status, reason: 'stall_advance');
      setState(() {
        _loading = true;
        _controlsVisible = true;
        _settingsExpanded = false;
        _statusMessage = status;
      });
    }
    if (skipProvider) {
      _providerIndex += 1;
      _sourceIndex = 0;
    } else {
      if (_activeSource == null || _activeSources.isEmpty) {
        DiagnosticLog.add(
          'native stall recovery reset source index reason=no_active_source',
        );
        _sourceIndex = 0;
        _recoveringFromStall = false;
        await _openNextAvailableSource();
        return;
      }
      final nextGroupedSourceIndex = _nextSourceIndexInCurrentVisibleGroup(
        _activeSources,
        _sourceIndex,
      );
      if (nextGroupedSourceIndex != null) {
        DiagnosticLog.add(
          'native stall checking next mirror provider=${_activeSource?.providerId} sourceIndex=$_sourceIndex nextSourceIndex=$nextGroupedSourceIndex status="${_checkingSourceStatusFor(nextGroupedSourceIndex)}"',
        );
        _sourceIndex = nextGroupedSourceIndex;
      } else {
        final nextVisibleIndex = _nextSourceIndexAfterCurrentVisibleGroup(
          _activeSources,
          _sourceIndex,
        );
        if (nextVisibleIndex != null) {
          DiagnosticLog.add(
            'native stall advancing visible source provider=${_activeSource?.providerId} sourceIndex=$_sourceIndex nextSourceIndex=$nextVisibleIndex',
          );
          _sourceIndex = nextVisibleIndex;
        } else {
          _sourceIndex += 1;
        }
      }
    }
    _sameSourceRecoveryAttempts = 0;
    await _openNextAvailableSource();
    _recoveringFromStall = false;
  }

  int? _nextSourceIndexAfterHardFailure(
    List<PlaybackSource> sources,
    int sourceIndex, [
    _NativePlaybackEngine? engine,
  ]) {
    if (sources.isEmpty || sourceIndex < 0 || sourceIndex >= sources.length) {
      return null;
    }
    final nextMirror = _nextSourceIndexInCurrentVisibleGroup(
      sources,
      sourceIndex,
    );
    if (_sourceCanBeTriedAfterHardFailure(sources, nextMirror, engine)) {
      return nextMirror;
    }
    final nextVisible = _nextSourceIndexAfterCurrentVisibleGroup(
      sources,
      sourceIndex,
    );
    if (_sourceCanBeTriedAfterHardFailure(sources, nextVisible, engine)) {
      return nextVisible;
    }
    return _nextRawSourceIndexAfterHardFailure(sources, sourceIndex, engine);
  }

  bool _sourceCanBeTriedAfterHardFailure(
    List<PlaybackSource> sources,
    int? sourceIndex, [
    _NativePlaybackEngine? engine,
  ]) {
    if (sourceIndex == null ||
        sourceIndex < 0 ||
        sourceIndex >= sources.length) {
      return false;
    }
    final source = sources[sourceIndex];
    return _nativeSourceClassIsPlayable(source) &&
        (engine == null || !_shouldSkipSourceForSession(source, engine));
  }

  int? _nextRawSourceIndexAfterHardFailure(
    List<PlaybackSource> sources,
    int sourceIndex, [
    _NativePlaybackEngine? engine,
  ]) {
    for (var index = sourceIndex + 1; index < sources.length; index += 1) {
      if (!_sourceCanBeTriedAfterHardFailure(sources, index, engine)) continue;
      DiagnosticLog.add(
        'native hard source error trying raw source before provider sourceIndex=$sourceIndex nextSourceIndex=$index reason=visible_groups_exhausted',
      );
      return index;
    }
    for (var index = 0; index < sourceIndex; index += 1) {
      if (!_sourceCanBeTriedAfterHardFailure(sources, index, engine)) continue;
      DiagnosticLog.add(
        'native hard source error trying raw source before provider sourceIndex=$sourceIndex nextSourceIndex=$index reason=wrap_visible_groups_exhausted',
      );
      return index;
    }
    return null;
  }

  Future<bool> _tryFreshProviderResolve(Duration resumePosition) async {
    final providerId = _activeSource?.providerId;
    if (providerId == null || providerId.isEmpty) return false;

    final attempts = _hardRecoveryAttemptsByProvider[providerId] ?? 0;
    if (attempts >= 1) {
      DiagnosticLog.add(
        'native hard recovery skipped provider=$providerId attempts=$attempts',
      );
      return false;
    }

    _hardRecoveryAttemptsByProvider[providerId] = attempts + 1;
    DiagnosticLog.add(
      'native hard recovery re-resolve provider=$providerId position=${resumePosition.inSeconds}s',
    );
    if (mounted) {
      const status = 'Refreshing stream...';
      _logPlaybackStatus(status, reason: 'hard_recovery_refresh');
      setState(() {
        _loading = true;
        _controlsVisible = true;
        _settingsExpanded = false;
        _statusMessage = status;
      });
    }

    try {
      final freshSources = _deprioritizeFailedSources(
        _prioritizePreferredQuality(
          await _expandQualitySources(await _resolveProvider(providerId)),
        ),
      );
      DiagnosticLog.add(
        'native hard recovery resolved provider=$providerId sources=${freshSources.length}',
      );
      if (freshSources.isEmpty || !mounted) return false;

      _activeSources = freshSources;
      final playableFreshSources = _nativePlayableSources(freshSources);
      final playableFreshSource = playableFreshSources.isEmpty
          ? null
          : playableFreshSources.first;
      if (playableFreshSource == null) {
        DiagnosticLog.add(
          'native hard recovery skipped provider=$providerId reason=source_class_not_native',
        );
        return false;
      }
      _sourceIndex = freshSources.indexWhere(
        (source) => source.url == playableFreshSource.url,
      );
      if (_sourceIndex < 0) _sourceIndex = 0;
      final opened = await _openSource(
        playableFreshSource,
        resumePosition: resumePosition,
        statusMessage: 'Refreshing stream...',
      );
      DiagnosticLog.add(
        'native hard recovery reopen provider=$providerId opened=$opened',
      );
      return opened;
    } catch (error) {
      DiagnosticLog.add(
        'native hard recovery failed provider=$providerId error=${_safeDiagnosticError(error)}',
      );
      return false;
    }
  }

  List<PlaybackSource> _deprioritizeFailedSources(
    List<PlaybackSource> sources,
  ) {
    if (sources.length < 2 || _failedSourceAttempts.isEmpty) return sources;
    final sorted = sources.toList(growable: false)
      ..sort((a, b) {
        final aAttempts = _failedSourceAttempts[a.url] ?? 0;
        final bAttempts = _failedSourceAttempts[b.url] ?? 0;
        if (aAttempts != bAttempts) return aAttempts.compareTo(bAttempts);
        return 0;
      });
    return sorted;
  }

  String? _sourceIndicatorLabel() {
    if (_activeSources.isEmpty) return null;
    final progress = _displaySourceProgress(_activeSources, _sourceIndex);
    final groups = _displaySourceEntries(_activeSources);
    if (groups.isEmpty) return null;
    final activeGroupIndex = (progress.$1 - 1).clamp(0, groups.length - 1);
    final group = groups[activeGroupIndex];
    final groupedSourceCount = group.variants.length;
    final currentUrl = _activeSource?.url;
    final groupedSourceIndex = currentUrl == null
        ? 0
        : group.variants.indexWhere((source) => source.url == currentUrl);
    if (groupedSourceCount > 1 && groupedSourceIndex >= 0) {
      return 'S ${progress.$1}/${progress.$2} - M ${groupedSourceIndex + 1}/$groupedSourceCount';
    }
    if (progress.$2 > 1) {
      return 'S ${progress.$1}/${progress.$2}';
    }
    return null;
  }

  String _sourceActionLabel() {
    final groups = _displaySourceEntries(_activeSources);
    if (groups.isEmpty) return 'No sources';
    if (groups.length == 1 && groups.first.variants.length > 1) {
      return '${groups.first.variants.length} mirrors';
    }
    if (groups.length == 1) return '1 source';
    return '${groups.length} sources';
  }

  void _togglePlayback({bool ignoreOptionSheet = false}) {
    if (_locked) return;
    if (_resumeDialogOpen) return;
    if (_settingsExpanded || (_optionSheetOpen && !ignoreOptionSheet)) return;
    final controller = _controller;
    if (controller == null || !controller.isInitialized) return;
    setState(() {
      if (controller.isPlaying) {
        _userPaused = true;
        controller.pause();
      } else {
        _userPaused = false;
        controller.play();
      }
    });
    _syncKeepScreenOn();
    unawaited(_syncPipActions());
    _scheduleControlsHide();
  }

  void _toggleControls() {
    if (_resumeDialogOpen) return;
    if (!_nativeControlsReady(_controller)) {
      _hideControlsTimer?.cancel();
      if (_controlsVisible) setState(() => _controlsVisible = false);
      return;
    }
    if (_locked) {
      setState(() => _controlsVisible = true);
      _scheduleControlsHide();
      return;
    }
    final nextVisible = !_controlsVisible;
    setState(() => _controlsVisible = nextVisible);
    if (nextVisible) {
      _scheduleControlsHide();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  Future<void> _seekBy(Duration offset) async {
    if (_locked || _isLiveTvMode) return;
    final controller = _controller;
    if (controller == null || !controller.isInitialized) return;
    final duration = _bestKnownProgressDuration(controller);
    final current = _bestKnownProgressPosition(controller, duration);
    final next = current + offset;
    final clamped = next < Duration.zero
        ? Duration.zero
        : next > duration
        ? duration
        : next;
    await controller.seekTo(clamped);
    _markManualSeekForIntegrity(current, clamped, reason: 'skip_button');
    _scheduleControlsHide();
  }

  Future<void> _seekToFraction(double fraction) async {
    if (_locked || _isLiveTvMode) return;
    final controller = _controller;
    if (controller == null || !controller.isInitialized) return;
    final duration = controller.duration;
    final current = controller.position;
    final target = duration * fraction.clamp(0, 1);
    await controller.seekTo(target);
    _markManualSeekForIntegrity(current, target, reason: 'seekbar');
    _scheduleControlsHide();
  }

  void _toggleLock() {
    final shouldResumeSettingsPause =
        _settingsExpanded && _settingsPausedPlayback;
    setState(() {
      _locked = !_locked;
      _controlsVisible = true;
      if (_locked) {
        _settingsExpanded = false;
      }
    });
    if (shouldResumeSettingsPause) {
      unawaited(_resumeSettingsPauseIfNeeded());
    }
    _scheduleControlsHide();
  }

  bool _pauseActivePlaybackForLoading(String reason) {
    final controller = _controller;
    if (controller == null ||
        !controller.isInitialized ||
        !controller.isPlaying) {
      return false;
    }
    DiagnosticLog.add(
      'native playback paused for loading reason=$reason provider=${_activeSource?.providerId ?? 'unknown'}',
    );
    unawaited(
      controller
          .pause()
          .timeout(const Duration(milliseconds: 700))
          .catchError((_) {}),
    );
    return true;
  }

  Future<void> _resumePlaybackAfterWaitMessage(String reason) async {
    final controller = _controller;
    if (controller == null ||
        !controller.isInitialized ||
        _playerClosing ||
        _loading ||
        _recoveringFromStall ||
        _openingSource ||
        _optionSheetOpen ||
        _settingsExpanded ||
        _userPaused) {
      return;
    }
    try {
      await controller.play().timeout(const Duration(milliseconds: 700));
      DiagnosticLog.add(
        'native playback resumed after wait message reason=$reason provider=${_activeSource?.providerId ?? 'unknown'}',
      );
    } catch (error) {
      DiagnosticLog.add(
        'native playback resume after wait message failed reason=$reason error=${_safeDiagnosticError(error)}',
      );
    }
  }

  void _toggleSettingsPack() {
    if (_locked) return;
    if (_settingsExpanded) {
      setState(() => _settingsExpanded = false);
      unawaited(_resumeSettingsPauseIfNeeded());
      _scheduleControlsHide();
      return;
    }

    _hideControlsTimer?.cancel();
    final controller = _controller;
    final shouldPause =
        controller?.isInitialized == true && controller?.isPlaying == true;
    setState(() {
      _settingsExpanded = true;
      _settingsPausedPlayback = shouldPause;
      _controlsVisible = true;
    });
    if (shouldPause) {
      unawaited(controller!.pause());
    }
  }

  Future<void> _resumeSettingsPauseIfNeeded() async {
    if (!_settingsPausedPlayback) return;
    _settingsPausedPlayback = false;
    final controller = _controller;
    if (controller == null || !controller.isInitialized) return;
    await controller.play();
  }

  Future<void> _reloadCurrentSource() async {
    if (_locked) return;
    final source = _activeSource;
    final controller = _controller;
    if (source == null || controller == null || !controller.isInitialized) {
      return;
    }

    final position = controller.position;
    DiagnosticLog.add(
      'native manual playback reload provider=${source.providerId} position=${position.inSeconds}s',
    );
    if (_isPublicIptvSource(source)) {
      await _reopenPublicLiveSource(source, position);
      return;
    }
    final status = _refreshingSourceStatusFor();
    _logPlaybackStatus(status, reason: 'manual_reload');
    setState(() {
      _loading = true;
      _controlsVisible = true;
      _settingsExpanded = false;
      _statusMessage = status;
    });

    final opened = await _openSource(
      source,
      resumePosition: position,
      statusMessage: status,
    );
    if (!opened) {
      _sourceIndex += 1;
      await _openNextAvailableSource();
    }
  }

  Future<void> _reopenPublicLiveSource(
    PlaybackSource source,
    Duration position,
  ) async {
    const status = 'Refreshing live stream...';
    _logPlaybackStatus(status, reason: 'manual_live_reopen');
    if (mounted) {
      setState(() {
        _loading = true;
        _controlsVisible = true;
        _settingsExpanded = false;
        _settingsPausedPlayback = false;
        _statusMessage = status;
        _playbackWaitMessage = null;
        _playbackWaitMessagePausedPlayback = false;
      });
    }
    DiagnosticLog.add(
      'native manual live reopen provider=${source.providerId} position=${position.inSeconds}s',
    );
    final opened = await _openSource(source, statusMessage: status);
    if (!opened) {
      _sourceIndex += 1;
      await _openNextAvailableSource();
    }
  }

  Future<void> _enterPictureInPicture({bool showFailureMessage = true}) async {
    if (!_pipSupported) {
      if (!mounted) return;
      if (showFailureMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PiP is not supported here.')),
        );
      }
      return;
    }

    var enteredPip = false;
    _pictureInPictureActive = true;
    setState(() {
      _optionSheetOpen = false;
      _settingsExpanded = false;
      _controlsVisible = false;
      _locked = false;
    });
    await WidgetsBinding.instance.endOfFrame;

    try {
      enteredPip =
          await _pipChannel.invokeMethod<bool>('enter', {
            'playing': _controller?.isPlaying == true,
            'seekSeconds': _seekStepSeconds.round(),
            'liveMode': _isLiveTvMode,
          }) ??
          false;
      DiagnosticLog.add('native system PiP enter result=$enteredPip');
      if (!enteredPip && mounted && showFailureMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not start PiP.')));
      }
    } catch (_) {
      if (!mounted) return;
      if (showFailureMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not start PiP.')));
      }
    } finally {
      if (!enteredPip) {
        _pictureInPictureActive = false;
        _systemPipHandoffActive = false;
        if (mounted) setState(() => _optionSheetOpen = false);
      }
    }
  }

  void _handlePictureInPictureButton() {
    unawaited(_enterPictureInPicture());
  }

  bool _canEnterSystemPictureInPicture() {
    return _playerReadyForSystemPictureInPicture();
  }

  bool _playerReadyForSystemPictureInPicture() {
    final controller = _controller;
    return _pipSupported &&
        !_playerClosing &&
        !_loading &&
        !_openingSource &&
        !_recoveringFromStall &&
        !_resolverTemporarilyBlocked &&
        _playbackWaitMessage == null &&
        controller?.isInitialized == true &&
        controller?.isBuffering != true;
  }

  double _playbackProgressValue(Duration position, Duration duration) {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Future<void> _openScreencast() async {
    final wasPlaying = await _pauseForOptionSheet();
    _restoringFromExternalRoute = true;
    _restoreShouldResumePlayback = wasPlaying;
    _restoreResumePosition =
        _controller?.position ?? _lastKnownPlaybackPosition;
    var openedExternally = false;
    try {
      openedExternally =
          await _castChannel.invokeMethod<bool>('openSettings') ?? false;
      if (!openedExternally && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cast settings unavailable.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open cast settings.')),
      );
    } finally {
      if (!openedExternally) {
        await _resumeAfterOptionSheet(wasPlaying);
        _restoringFromExternalRoute = false;
        _shouldRestoreOnResume = false;
        _restoreShouldResumePlayback = false;
        _restoreResumePosition = Duration.zero;
      }
    }
  }

  Future<void> _showQualitySheet() async {
    if (_locked || _activeSources.isEmpty) return;
    final position = _qualitySwitchResumePosition();
    final wasPlaying = await _pauseForOptionSheet();
    final selected = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _QualitySheet(
          sources: _activeSources,
          activeSource: _activeSource,
          preferredQuality: _preferredQuality,
        );
      },
    );
    if (selected == null || !mounted) {
      await _resumeAfterOptionSheet(wasPlaying);
      return;
    }

    if (selected is _QualityAutoSelection) {
      final previousSource = _activeSource;
      final previousSourceIndex = _sourceIndex;
      final previousPreferredQuality = _preferredQuality;
      final previousQualityPreferenceMode = _qualityPreferenceMode;
      setState(() {
        _preferredQuality = null;
        _qualityPreferenceMode = 'recommended';
      });
      _saveNativeProgress(force: true);
      DiagnosticLog.add('native quality selected auto');
      final source = _bestAutoQualitySource(
        _nativePlayableSources(_activeSources),
      );
      if (source == null || source.url == _activeSource?.url) {
        await _resumeAfterOptionSheet(wasPlaying);
        return;
      }
      final nextIndex = _activeSources.indexWhere(
        (candidate) => candidate.url == source.url,
      );
      if (nextIndex >= 0) {
        _sourceIndex = nextIndex;
      }
      _resetRouteHlsTimeoutsForQualitySwitch(source);
      _clearOptionSheetOverlay();
      final opened = await _openSource(source, resumePosition: position);
      if (!mounted) return;
      if (opened && !wasPlaying) {
        await _controller?.pause();
      }
      if (!opened && mounted) {
        final restored = await _restorePreviousSourceAfterSelectionFailure(
          previousSource: previousSource,
          resumePosition: position,
          wasPlaying: wasPlaying,
          previousSourceIndex: previousSourceIndex,
          previousPreferredQuality: previousPreferredQuality,
          previousQualityPreferenceMode: previousQualityPreferenceMode,
          reason: 'quality_auto_selection_failed',
        );
        if (restored) return;
      }
      await _resumeAfterOptionSheet(wasPlaying);
      return;
    }

    if (selected is! PlaybackSource) {
      await _resumeAfterOptionSheet(wasPlaying);
      return;
    }

    if (selected.url == _activeSource?.url) {
      await _resumeAfterOptionSheet(wasPlaying);
      return;
    }

    final previousSource = _activeSource;
    final previousSourceIndex = _sourceIndex;
    final previousPreferredQuality = _preferredQuality;
    final previousQualityPreferenceMode = _qualityPreferenceMode;
    final nextIndex = _activeSources.indexWhere(
      (source) => source.url == selected.url,
    );
    if (nextIndex >= 0) {
      _sourceIndex = nextIndex;
    }
    _qualityPreferenceMode = 'advanced';
    _preferredQuality = _qualityLabel(selected);
    DiagnosticLog.add(
      'native quality selected provider=${selected.providerId} quality=${selected.quality ?? 'auto'}',
    );
    _resetRouteHlsTimeoutsForQualitySwitch(selected);
    _clearOptionSheetOverlay();
    final opened = await _openSource(selected, resumePosition: position);
    if (!mounted) return;
    if (opened && !wasPlaying) {
      await _controller?.pause();
    }
    if (!opened && mounted) {
      final restored = await _restorePreviousSourceAfterSelectionFailure(
        previousSource: previousSource,
        resumePosition: position,
        wasPlaying: wasPlaying,
        previousSourceIndex: previousSourceIndex,
        previousPreferredQuality: previousPreferredQuality,
        previousQualityPreferenceMode: previousQualityPreferenceMode,
        reason: 'quality_selection_failed',
      );
      if (restored) return;
      _sourceIndex += 1;
      final status = _nextSourceStatusFor();
      _logPlaybackStatus(status, reason: 'quality_selection_failed');
      setState(() {
        _loading = true;
        _controlsVisible = true;
        _statusMessage = status;
      });
      await _openNextAvailableSource();
      return;
    }
    await _resumeAfterOptionSheet(wasPlaying);
  }

  Future<void> _showSourceSheet() async {
    if (_locked || _activeSources.length < 2) return;
    final position = _qualitySwitchResumePosition();
    final wasExhausted = _nativeProvidersExhausted;
    final wasPlaying = await _pauseForOptionSheet();
    final selected = await showModalBottomSheet<PlaybackSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _SourceSheet(
          sources: _activeSources,
          activeSource: _activeSource,
        );
      },
    );
    if (selected == null || !mounted || selected.url == _activeSource?.url) {
      await _resumeAfterOptionSheet(wasPlaying);
      return;
    }

    final previousSource = _activeSource;
    final previousSourceIndex = _sourceIndex;
    final previousPreferredQuality = _preferredQuality;
    final previousQualityPreferenceMode = _qualityPreferenceMode;
    final nextIndex = _activeSources.indexWhere(
      (source) => source.url == selected.url,
    );
    if (nextIndex >= 0) {
      _sourceIndex = nextIndex;
    }
    final displayEntries = _displaySourceEntries(_activeSources);
    final selectedDisplayIndex = displayEntries.indexWhere(
      (entry) => entry.variants.any((source) => source.url == selected.url),
    );
    final selectedQuality = _qualityLabel(selected);
    _qualityPreferenceMode = selectedQuality == 'Auto'
        ? 'recommended'
        : 'advanced';
    _preferredQuality = selectedQuality == 'Auto' ? null : selectedQuality;
    DiagnosticLog.add(
      'native source selected provider=${selected.providerId} sourceIndex=$_sourceIndex visibleSourceCount=${displayEntries.length} quality=${selected.quality ?? 'auto'}',
    );
    _resetRouteHlsTimeoutsForQualitySwitch(selected);
    _clearOptionSheetOverlay();
    final opened = await _openSource(
      selected,
      resumePosition: position,
      statusMessage:
          'Opening ${_sourceDisplayLabel(selected, index: selectedDisplayIndex >= 0 ? selectedDisplayIndex : 0, total: displayEntries.length)}...',
    );
    if (opened && !wasPlaying) {
      await _controller?.pause();
    }
    if (!opened && mounted) {
      final restored = await _restorePreviousSourceAfterSelectionFailure(
        previousSource: previousSource,
        resumePosition: position,
        wasPlaying: wasPlaying,
        previousSourceIndex: previousSourceIndex,
        previousPreferredQuality: previousPreferredQuality,
        previousQualityPreferenceMode: previousQualityPreferenceMode,
        reason: 'source_selection_failed',
      );
      if (restored) return;
      _sourceIndex += 1;
      if (wasExhausted) {
        final status = _lastOpenFailureMessage == null
            ? "Couldn't open this source."
            : _lastOpenFailureMessage!;
        _logPlaybackStatus(status, reason: 'source_selection_failed_exhausted');
        setState(() {
          _loading = true;
          _controlsVisible = true;
          _nativeProvidersExhausted = true;
          _statusMessage = status;
        });
        await _resumeAfterOptionSheet(false);
        return;
      }
      final status = _nextSourceStatusFor();
      _logPlaybackStatus(status, reason: 'source_selection_failed');
      setState(() {
        _loading = true;
        _controlsVisible = true;
        _statusMessage = status;
      });
      await _openNextAvailableSource();
      return;
    }
    await _resumeAfterOptionSheet(wasPlaying);
  }

  Future<void> _showSpeedSheet() async {
    if (_locked) return;
    final wasPlaying = await _pauseForOptionSheet();
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _SpeedSheet(activeSpeed: _playbackSpeed);
      },
    );
    if (selected == null || !mounted) {
      await _resumeAfterOptionSheet(wasPlaying);
      return;
    }
    final controller = _controller;
    setState(() => _playbackSpeed = selected);
    if (controller != null && controller.isInitialized) {
      await controller.setPlaybackSpeed(selected);
    }
    _saveNativeProgress(force: true);
    DiagnosticLog.add('native speed selected ${_speedLabel(selected)}');
    await _resumeAfterOptionSheet(wasPlaying);
    _scheduleControlsHide();
  }

  Future<bool> _restorePreviousSourceAfterSelectionFailure({
    required PlaybackSource? previousSource,
    required Duration resumePosition,
    required bool wasPlaying,
    required int previousSourceIndex,
    required String? previousPreferredQuality,
    required String previousQualityPreferenceMode,
    required String reason,
  }) async {
    if (!mounted || previousSource == null || _playerClosing) return false;
    final status = "That mirror didn't work. Returning to previous source...";
    DiagnosticLog.add(
      'native source selection fallback restoring previous source reason=$reason provider=${previousSource.providerId}',
    );
    _logPlaybackStatus(status, reason: 'source_selection_restore_previous');
    setState(() {
      _loading = true;
      _controlsVisible = true;
      _statusMessage = status;
      _preferredQuality = previousPreferredQuality;
      _qualityPreferenceMode = previousQualityPreferenceMode;
    });
    final restoredIndex = _activeSources.indexWhere(
      (source) => source.url == previousSource.url,
    );
    _sourceIndex = restoredIndex >= 0 ? restoredIndex : previousSourceIndex;
    final opened = await _openSource(
      previousSource,
      resumePosition: resumePosition,
      statusMessage: status,
    );
    if (!mounted) return false;
    if (!opened) {
      DiagnosticLog.add(
        'native source selection fallback previous source failed reason=$reason provider=${previousSource.providerId}',
      );
      return false;
    }
    if (!wasPlaying) {
      await _controller?.pause();
    }
    await _resumeAfterOptionSheet(wasPlaying);
    return true;
  }

  Future<void> _showFitSheet() async {
    if (_locked) return;
    final wasPlaying = await _pauseForOptionSheet();
    final selected = await showModalBottomSheet<VideoFitMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _FitModeSheet(activeMode: _fitMode),
    );
    if (selected != null && mounted) {
      setState(() => _fitMode = selected);
      _saveNativeProgress(force: true);
      DiagnosticLog.add('native fit mode selected ${selected.name}');
    }
    await _resumeAfterOptionSheet(wasPlaying);
    _scheduleControlsHide();
  }

  Future<void> _openNextEpisodeInPlace() async {
    final resolver = _nextEpisodeResolver;
    if (resolver == null) return;
    final now = DateTime.now();
    final lastTapAt = _lastNextEpisodeTapAt;
    if (_nextEpisodeOpening ||
        (lastTapAt != null &&
            now.difference(lastTapAt) < _nextEpisodeTapDebounce)) {
      DiagnosticLog.add('native next episode ignored reason=debounce');
      return;
    }
    final backoffUntil = _resolverBackoffUntil;
    if (backoffUntil != null && now.isBefore(backoffUntil)) {
      final seconds = backoffUntil.difference(now).inSeconds.clamp(1, 99);
      DiagnosticLog.add(
        'native next episode blocked reason=temporary_resolve_backoff seconds=$seconds',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playback is busy. Try again in ${seconds}s.'),
          ),
        );
      }
      return;
    }
    _lastNextEpisodeTapAt = now;
    _nextEpisodeOpening = true;
    _hideControlsTimer?.cancel();
    _saveNativeProgress(force: true);
    final currentController = _controller;
    if (currentController?.isPlaying == true) {
      try {
        await currentController!.pause().timeout(
          const Duration(milliseconds: 700),
        );
        DiagnosticLog.add('native next episode paused current playback');
      } catch (error) {
        DiagnosticLog.add(
          'native next episode pause skipped reason=${error.runtimeType}',
        );
      }
    }
    await JuicrAdPolicy.showRewardedBeforePlayback(
      context,
      reason: 'episode_playback',
      restorePlayerLandscapeWhenDone: true,
    );
    if (!mounted) return;
    setState(() {
      _loading = true;
      _controlsVisible = true;
      _settingsExpanded = false;
      _statusMessage = 'Opening next episode...';
    });

    NativePlayerNextEpisode? next;
    try {
      next = await resolver();
    } catch (error) {
      if (_isTemporaryResolverBlock(error)) {
        _resolverBackoffUntil = DateTime.now().add(_nextEpisodeResolverBackoff);
        DiagnosticLog.add(
          'native next episode resolver backoff reason=temporary_block seconds=${_nextEpisodeResolverBackoff.inSeconds}',
        );
      }
      rethrow;
    } finally {
      _nextEpisodeOpening = false;
    }
    if (!mounted) return;
    if (next == null) {
      setState(() {
        _loading = false;
        _statusMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Next episode unavailable.')),
      );
      return;
    }

    final resolvedNext = next;
    await _disposeCurrentController(awaitLibVlcRelease: true);
    if (!mounted) return;
    setState(() {
      _title = resolvedNext.title;
      _resolveProvider = resolvedNext.resolveProvider;
      _resolveSubtitles = resolvedNext.resolveSubtitles;
      _limitToFirstQualityPass = resolvedNext.limitToFirstQualityPass;
      _logoUrl = resolvedNext.logoUrl;
      _progressItem = resolvedNext.progressItem;
      _playbackKey = resolvedNext.playbackKey;
      _requests = _requestsWithVerifiedSource(
        resolvedNext.sources,
        playbackKey: resolvedNext.playbackKey,
      );
      _progressSubtitle = resolvedNext.progressSubtitle;
      _nextEpisodeLabel = resolvedNext.nextEpisodeLabel;
      _nextEpisodeResolver = resolvedNext.onNextEpisode;
      _nextEpisodeOpening = false;
      _resolverBackoffUntil = null;
      _providerResolveFutures.clear();
      _providerIndex = 0;
      _sourceIndex = 0;
      _enginePassIndex = 0;
      _qualityPassIndex = 0;
      _libvlcUnavailableForSession = false;
      _activeSourceHasZeroClockMetadata = false;
      _activeSourceVerifiedForSession = false;
      _lastVerifiedConfidenceUrl = null;
      _verifiedConfidenceMilestone = 0;
      _skipUnsupportedHighEfficiencyForSession = false;
      _nativeSourceClassSkipCounts.clear();
      _nativeProvidersExhausted = false;
      _activeSources = const <PlaybackSource>[];
      _activeSource = null;
      _subtitles = const <PlaybackSubtitle>[];
      _subtitlesLoadStarted = false;
      _activeSubtitle = null;
      _subtitleCues = const <_SubtitleCue>[];
      _subtitleText = null;
      _preferredSubtitleId = null;
      _statusMessage = null;
      _userPaused = false;
      _pictureInPictureActive = false;
      _systemPipHandoffActive = false;
      _restoringFromExternalRoute = false;
      _shouldRestoreOnResume = false;
      _restoreShouldResumePlayback = false;
      _restoreResumePosition = Duration.zero;
      _resumePromptHandled = false;
      _resumePromptAccepted = false;
      _autoNextEpisodeStarted = false;
      _completionCloseStarted = false;
      _lastKnownPlaybackPosition = Duration.zero;
      _lastKnownPlaybackDuration = Duration.zero;
      _resumeProgressAnchorPosition = Duration.zero;
      _resumeProgressAnchorLogSecond = -1;
      _libVlcContinuousTsDurationAccepted = false;
      _libVlcContinuousTsStreamedSegments = 0;
      _nativeWallClockStartedAt = null;
      _sameSourceRecoveryAttempts = 0;
      _hardPlaybackErrors = 0;
      _hardRecoveryAttemptsByProvider.clear();
      _failedSourceAttempts.clear();
      _lastSavedSecond = -1;
      _integrityPlaybackKey = null;
      _credibleWatchMilliseconds = 0;
      _credibleWatchSecondsAtSourceOpen = 0;
      _seekAbuseEvents = 0;
      _resetPlaybackIntegritySample();
    });
    _restoreNativePreferences();
    unawaited(_openNextAvailableSource());
  }

  Future<void> _showSubtitleSheet() async {
    if (_locked) return;
    _ensureSubtitlesLoading();
    final wasPlaying = await _pauseForOptionSheet();
    final selected = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _SubtitleSheet(
          subtitles: _subtitles,
          activeSubtitle: _activeSubtitle,
          allowStyleControls: !_usingGlobalOverrides,
          fontSize: _subtitleFontSize,
          backgroundOpacity: _subtitleBackgroundOpacity,
          backgroundColor: _subtitleBackgroundColor,
          backgroundRadius: _subtitleBackgroundRadius,
          textColor: _subtitleTextColor,
          bottomOffset: _subtitleBottomOffset,
          delaySeconds: _subtitleDelaySeconds,
          defaultDelaySeconds: AppState.nativePlaybackOverridesEnabled.value
              ? AppState.nativePlaybackOverrides.value.subtitleDelaySeconds
              : 0.0,
          onDelayChanged: (value) {
            if (mounted) {
              setState(() {
                _subtitleDelaySeconds = value;
                _subtitleDelayCustomized = true;
              });
              _syncSubtitleText();
              _saveNativeProgress(force: true);
            }
          },
          onDelayResetToDefault: () {
            if (mounted) {
              final defaultDelay = AppState.nativePlaybackOverridesEnabled.value
                  ? AppState.nativePlaybackOverrides.value.subtitleDelaySeconds
                  : 0.0;
              setState(() {
                _subtitleDelayCustomized = false;
                _subtitleDelaySeconds = defaultDelay;
              });
              _syncSubtitleText();
              _saveNativeProgress(force: true);
            }
          },
          onFontSizeChanged: (value) {
            if (mounted) {
              setState(() => _subtitleFontSize = value);
              _saveNativeProgress(force: true);
            }
          },
          onBackgroundOpacityChanged: (value) {
            if (mounted) {
              setState(() => _subtitleBackgroundOpacity = value);
              _saveNativeProgress(force: true);
            }
          },
          onBackgroundColorChanged: (value) {
            if (mounted) {
              setState(() => _subtitleBackgroundColor = value);
              _saveNativeProgress(force: true);
            }
          },
          onBackgroundRadiusChanged: (value) {
            if (mounted) {
              setState(() => _subtitleBackgroundRadius = value);
              _saveNativeProgress(force: true);
            }
          },
          onTextColorChanged: (value) {
            if (mounted) {
              setState(() => _subtitleTextColor = value);
              _saveNativeProgress(force: true);
            }
          },
          onBottomOffsetChanged: (value) {
            if (mounted) {
              setState(() => _subtitleBottomOffset = value);
              _saveNativeProgress(force: true);
            }
          },
        );
      },
    );
    if (!mounted) return;
    if (selected is PlaybackSubtitle) {
      await _selectSubtitle(selected, saveAsDefault: true);
    } else if (selected is _SubtitleOffSelection) {
      await _selectSubtitle(null, saveAsDefault: true);
    }
    await _resumeAfterOptionSheet(wasPlaying);
    _scheduleControlsHide();
  }

  Future<void> _selectSubtitle(
    PlaybackSubtitle? subtitle, {
    bool saveAsDefault = false,
  }) async {
    if (subtitle == null) {
      setState(() {
        _activeSubtitle = null;
        _subtitleCues = const <_SubtitleCue>[];
        _subtitleText = null;
        _preferredSubtitleId = null;
      });
      DiagnosticLog.add('native subtitles off');
      if (saveAsDefault) {
        final behavior = AppState.playerBehaviorSettings.value;
        AppState.updatePlayerBehaviorSettings(
          behavior.copyWith(subtitleAutoSelect: 'off'),
        );
      }
      _saveNativeProgress(force: true);
      return;
    }

    try {
      DiagnosticLog.add(
        'native subtitle load label=${subtitle.label} url=[hidden]',
      );
      final response = await http
          .get(Uri.parse(subtitle.url))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Subtitle request failed: ${response.statusCode}');
      }
      final cues = _parseWebVtt(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (!mounted) return;
      setState(() {
        _activeSubtitle = subtitle;
        _subtitleCues = cues;
        _subtitleText = null;
        _preferredSubtitleId = subtitle.id;
      });
      _syncSubtitleText();
      DiagnosticLog.add(
        'native subtitle loaded label=${subtitle.label} cues=${cues.length}',
      );
      if (saveAsDefault) {
        final language = subtitle.language.trim().toLowerCase();
        final behavior = AppState.playerBehaviorSettings.value;
        AppState.updatePlayerBehaviorSettings(
          behavior.copyWith(
            subtitleAutoSelect: 'default',
            subtitleLanguage: language.isEmpty ? 'auto' : language,
          ),
        );
      }
      _saveNativeProgress(force: true);
      if (cues.isNotEmpty) {
        DiagnosticLog.add(
          'native subtitle first cue start=${_formatDuration(cues.first.start)} end=${_formatDuration(cues.first.end)} textLength=${cues.first.text.length}',
        );
      }
      if (cues.isEmpty) {
        DiagnosticLog.add('native subtitle parser produced no cues');
      }
    } catch (error) {
      DiagnosticLog.add(
        'native subtitle failed label=${subtitle.label} error=${_safeDiagnosticError(error)}',
      );
    }
  }

  Future<List<PlaybackSource>> _expandQualitySources(
    List<PlaybackSource> sources,
  ) async {
    final expanded = <PlaybackSource>[];
    for (final source in sources) {
      if (!_isHlsSource(source)) {
        expanded.add(source);
        continue;
      }

      try {
        final variants = await _hlsVariantsFor(source);
        if (variants.isNotEmpty) {
          expanded.addAll(variants);
          expanded.add(source);
          final labels = variants.map(_qualityLabel).join(',');
          DiagnosticLog.add(
            'native quality variants provider=${source.providerId} count=${variants.length} labels=$labels order=variants-first',
          );
          continue;
        }
      } catch (error) {
        DiagnosticLog.add(
          'native quality variants failed provider=${source.providerId} error=${_safeDiagnosticError(error)}',
        );
      }
      expanded.add(source);
    }

    final seen = <String>{};
    final unique = [
      for (final source in expanded)
        if (seen.add(
          '${source.providerId}|${source.quality ?? 'auto'}|${source.url}',
        ))
          source,
    ];
    if (unique.length > _publicIptvMaxExpandedSources &&
        unique.every(_isPublicIptvSource)) {
      DiagnosticLog.add(
        'native quality variants capped provider=public-iptv count=${unique.length} limit=$_publicIptvMaxExpandedSources',
      );
      return unique.take(_publicIptvMaxExpandedSources).toList();
    }
    return unique;
  }

  List<PlaybackSource> _prioritizePreferredQuality(
    List<PlaybackSource> sources,
  ) {
    final rankedSources = rankedNativePlaybackSources(
      sources,
      sourceClassAllowed: AppState.playbackSourceClassAllowedForNative,
      p2pConfig: _p2pPriorityConfigFromSettings(),
    );
    if (rankedSources.length < 2) return rankedSources;
    if (_usingGlobalOverrides && _qualityPreferenceMode == 'higher') {
      return rankedSources;
    }
    if (_usingGlobalOverrides && _qualityPreferenceMode == 'dataSaver') {
      final saver = rankedSources.toList()
        ..sort(
          (a, b) => _dataSaverQualityRank(
            _qualityLabel(a),
          ).compareTo(_dataSaverQualityRank(_qualityLabel(b))),
        );
      return saver;
    }
    if (_usingGlobalOverrides && _qualityPreferenceMode == 'recommended') {
      final targetIndex = _recommendedQualityIndex(rankedSources);
      if (targetIndex <= 0) return rankedSources;
      return _moveQualityRankToFront(
        rankedSources,
        _qualityRank(_qualityLabel(rankedSources[targetIndex])),
      );
    }
    if (_savedAutoQualityUsesRecommended) {
      final targetIndex = _recommendedQualityIndex(rankedSources);
      if (targetIndex <= 0) return rankedSources;
      return _moveQualityRankToFront(
        rankedSources,
        _qualityRank(_qualityLabel(rankedSources[targetIndex])),
      );
    }
    final preferred = _preferredQuality;
    if (preferred == null ||
        preferred.isEmpty ||
        preferred == 'Auto' ||
        rankedSources.length < 2) {
      return rankedSources;
    }
    final preferredRank = _qualityRank(preferred);
    final index = rankedSources.indexWhere(
      (source) => _qualityLabel(source) == preferred,
    );
    var fallbackIndex = -1;
    var fallbackRank = -1;
    if (preferredRank > 0) {
      for (var i = 0; i < rankedSources.length; i++) {
        final rank = _qualityRank(_qualityLabel(rankedSources[i]));
        if (rank > 0 && rank <= preferredRank && rank > fallbackRank) {
          fallbackIndex = i;
          fallbackRank = rank;
        }
      }
    }
    final targetIndex = index >= 0 ? index : fallbackIndex;
    if (targetIndex <= 0) return rankedSources;
    if (index >= 0) {
      return _moveQualityLabelToFront(rankedSources, preferred);
    }
    return _moveQualityRankToFront(rankedSources, fallbackRank);
  }

  List<PlaybackSource> _moveQualityLabelToFront(
    List<PlaybackSource> sources,
    String quality,
  ) {
    return [
      ...sources.where((source) => _qualityLabel(source) == quality),
      ...sources.where((source) => _qualityLabel(source) != quality),
    ];
  }

  List<PlaybackSource> _moveQualityRankToFront(
    List<PlaybackSource> sources,
    int rank,
  ) {
    return [
      ...sources.where((source) => _qualityRank(_qualityLabel(source)) == rank),
      ...sources.where((source) => _qualityRank(_qualityLabel(source)) != rank),
    ];
  }

  PlaybackSource? _bestAutoQualitySource(List<PlaybackSource> sources) {
    final rankedSources = rankedNativePlaybackSources(
      sources,
      sourceClassAllowed: AppState.playbackSourceClassAllowedForNative,
      p2pConfig: _p2pPriorityConfigFromSettings(),
    );
    if (rankedSources.isEmpty) return null;
    if (_usingGlobalOverrides && _qualityPreferenceMode == 'dataSaver') {
      return rankedSources.reduce(
        (a, b) =>
            _dataSaverQualityRank(_qualityLabel(a)) <=
                _dataSaverQualityRank(_qualityLabel(b))
            ? a
            : b,
      );
    }
    if (_usingGlobalOverrides && _qualityPreferenceMode == 'recommended') {
      final index = _recommendedQualityIndex(rankedSources);
      return rankedSources[index < 0 ? 0 : index];
    }
    if (_savedAutoQualityUsesRecommended) {
      final index = _recommendedQualityIndex(rankedSources);
      return rankedSources[index < 0 ? 0 : index];
    }
    return rankedSources.first;
  }

  bool get _savedAutoQualityUsesRecommended {
    final preferred = _preferredQuality;
    return !_usingGlobalOverrides &&
        !_batterySaverPlaybackActive &&
        !_isP2pOnlySourceRoute &&
        (preferred == null || preferred.isEmpty || preferred == 'Auto');
  }

  int _recommendedQualityIndex(List<PlaybackSource> rankedSources) {
    final preferredRanks = <int>[
      1080,
      720,
      800,
      674,
      534,
      480,
      452,
      360,
      336,
      266,
      240,
    ];
    for (final wanted in preferredRanks) {
      final index = rankedSources.indexWhere(
        (source) => _qualityRank(_qualityLabel(source)) == wanted,
      );
      if (index >= 0) return index;
    }
    return 0;
  }

  Future<List<PlaybackSource>> _hlsVariantsFor(PlaybackSource source) async {
    final uri = Uri.parse(source.url);
    final response = await http
        .get(uri, headers: source.headers)
        .timeout(const Duration(seconds: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const <PlaybackSource>[];
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (!body.contains('#EXT-X-STREAM-INF')) return const <PlaybackSource>[];

    final lines = _hlsManifestLines(body);
    if (_hlsManifestHasSeparateAudioRenditions(lines)) {
      DiagnosticLog.add(
        'native quality variants skipped provider=${source.providerId} reason=separate_audio_renditions',
      );
      return const <PlaybackSource>[];
    }

    final variants = <PlaybackSource>[];
    var skippedCleartextVariants = 0;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      if (index + 1 >= lines.length) continue;
      final next = lines[index + 1];
      if (next.startsWith('#')) continue;

      final resolution = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
      final bandwidth = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      final height = resolution?.group(2);
      final mbps = bandwidth == null
          ? null
          : (int.tryParse(bandwidth.group(1) ?? '') ?? 0) / 1000000;
      final label = height != null && height.isNotEmpty
          ? '${height}p'
          : mbps != null && mbps > 0
          ? '${mbps.toStringAsFixed(1)} Mbps'
          : 'Variant ${variants.length + 1}';
      final variantUri = uri.resolve(next);
      if (_isPublicIptvSource(source) && variantUri.scheme != 'https') {
        skippedCleartextVariants += 1;
        continue;
      }
      variants.add(
        PlaybackSource(
          providerId: source.providerId,
          name: source.name,
          url: variantUri.toString(),
          type: source.type,
          quality: label,
          sourceClass: source.sourceClass,
          headers: source.headers,
          subtitles: source.subtitles,
          drm: source.drm,
        ),
      );
    }
    if (_isPublicIptvSource(source) && skippedCleartextVariants > 0) {
      DiagnosticLog.add(
        'native quality variants skipped cleartext provider=${source.providerId} count=$skippedCleartextVariants',
      );
    }

    return variants;
  }

  bool _hlsManifestHasSeparateAudioRenditions(List<String> lines) {
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper.startsWith('#EXT-X-MEDIA') && upper.contains('TYPE=AUDIO')) {
        return true;
      }
      if (upper.startsWith('#EXT-X-STREAM-INF') && upper.contains('AUDIO=')) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _pauseForOptionSheet() async {
    final controller = _controller;
    if (controller == null || !controller.isInitialized) {
      if (mounted) setState(() => _optionSheetOpen = true);
      return false;
    }
    final wasPlaying = controller.isPlaying || _settingsPausedPlayback;
    if (mounted && _settingsExpanded) {
      setState(() {
        _settingsExpanded = false;
        _settingsPausedPlayback = false;
        _optionSheetOpen = true;
      });
    } else if (mounted) {
      setState(() => _optionSheetOpen = true);
    }
    if (controller.isPlaying) {
      await controller.pause();
    }
    return wasPlaying;
  }

  Future<void> _resumeAfterOptionSheet(bool shouldResume) async {
    if (mounted && _optionSheetOpen) {
      setState(() => _optionSheetOpen = false);
    }
    final controller = _controller;
    if (shouldResume && controller != null && controller.isInitialized) {
      await controller.play();
    }
    if (mounted) _scheduleControlsHide();
  }

  void _clearOptionSheetOverlay() {
    if (!mounted || !_optionSheetOpen) return;
    setState(() => _optionSheetOpen = false);
  }

  Future<void> _restorePlaybackAfterExternalRoute() async {
    if (!mounted || _playerClosing || _openingSource) return;
    if (_controller?.isInitialized == true) {
      _restoringFromExternalRoute = false;
      if (_optionSheetOpen) {
        setState(() => _optionSheetOpen = false);
      }
      _scheduleControlsHide();
      return;
    }
    final source = _activeSource;
    if (source == null) {
      _restoringFromExternalRoute = false;
      if (_optionSheetOpen) {
        setState(() => _optionSheetOpen = false);
      }
      _scheduleControlsHide();
      return;
    }

    final resumePosition = _restoreResumePosition.inSeconds >= 3
        ? _restoreResumePosition
        : _lastKnownPlaybackPosition;
    DiagnosticLog.add(
      'native restore after external route provider=${source.providerId} position=${resumePosition.inSeconds}s',
    );
    setState(() {
      _loading = true;
      _controlsVisible = true;
      _optionSheetOpen = false;
      _settingsExpanded = false;
      _statusMessage = 'Restoring playback...';
    });
    final opened = await _openSource(
      source,
      resumePosition: resumePosition,
      statusMessage: 'Restoring playback...',
    );
    if (opened && !_restoreShouldResumePlayback) {
      await _controller?.pause();
    }
    if (!opened && mounted) {
      setState(() {
        _loading = false;
        _statusMessage = null;
      });
    }
    _restoringFromExternalRoute = false;
    _restoreShouldResumePlayback = false;
    _restoreResumePosition = Duration.zero;
    _scheduleControlsHide();
  }

  bool _syncSubtitleText() {
    final controller = _controller;
    if (controller == null ||
        !controller.isInitialized ||
        _subtitleCues.isEmpty) {
      if (_subtitleText != null) {
        _subtitleText = null;
        return true;
      }
      return false;
    }

    final position =
        controller.position +
        Duration(milliseconds: (_subtitleDelaySeconds * 1000).round());
    String? nextText;
    for (final cue in _subtitleCues) {
      if (position >= cue.start && position <= cue.end) {
        nextText = cue.text;
        break;
      }
    }
    if (nextText != _subtitleText) {
      _subtitleText = nextText;
      return true;
    }
    return false;
  }

  void _handleVerticalDrag(DragUpdateDetails details, double width) {
    if (_locked) return;
    final controller = _controller;
    final keepControlsVisible = _controlsVisible;
    final isLeftSide = details.localPosition.dx < width / 2;
    final delta = -details.delta.dy / 260;
    final nextBrightness = (_brightnessPreview + delta).clamp(0, 1).toDouble();
    final nextVolume = (_volumePreview + delta).clamp(0, 1).toDouble();
    setState(() {
      if (isLeftSide) {
        _brightnessPreview = nextBrightness;
        _gestureIcon = Icons.brightness_6_rounded;
        _gestureLabel = 'Brightness ${(_brightnessPreview * 100).round()}%';
      } else {
        _volumePreview = nextVolume;
        _gestureIcon = Icons.volume_up_rounded;
        _gestureLabel = 'Volume ${(_volumePreview * 100).round()}%';
      }
      _controlsVisible = keepControlsVisible;
    });
    if (isLeftSide) {
      AppState.updateNativePlayerBrightness(nextBrightness);
      _displayChannel
          .invokeMethod<void>('setBrightness', {'value': nextBrightness})
          .catchError((_) {});
    } else {
      AppState.updateNativePlayerVolume(nextVolume);
      if (controller != null) {
        controller.setVolume(nextVolume);
      }
    }
    _scheduleControlsHide();
  }

  void _clearGestureOverlay() {
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (mounted && !_playerClosing) setState(() => _gestureLabel = null);
    });
  }

  Future<void> _close([String? result]) async {
    if (_playerClosing) {
      await _forcePopPlayerRoute(result ?? 'closed');
      return;
    }
    _playerClosing = true;
    _systemPipHandoffActive = false;
    unawaited(_setAndroidAutoPipOnUserLeave(false));
    if (mounted) setState(() => _allowPop = true);
    _hideControlsTimer?.cancel();
    _stopStallWatchdog();
    DiagnosticLog.add(
      'native close saving progress result=${result ?? 'closed'} hasController=${_controller != null}',
    );
    _sendPlaybackFeedback('closed');
    if (result != 'completed' &&
        (_controller != null ||
            (_lastKnownPlaybackDuration.inSeconds > 0 &&
                _lastKnownPlaybackPosition.inSeconds >= 3))) {
      _saveNativeProgress(force: true);
    }
    await _disposeCurrentController(
      awaitLibVlcRelease: true,
      saveProgress: false,
    );
    await _stopP2pBridgeForPolicy('route_close');
    await _forcePopPlayerRoute(result ?? 'closed');
  }

  Future<void> _forcePopPlayerRoute(String result) async {
    if (!mounted || _playerPopIssued) return;
    _playerPopIssued = true;
    if (!_allowPop && mounted) {
      setState(() => _allowPop = true);
    }
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (_optionSheetOpen && navigator.canPop()) {
      navigator.pop();
      if (mounted) setState(() => _optionSheetOpen = false);
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
    }
    if (navigator.canPop()) {
      navigator.pop(result);
    }
  }

  Future<void> _requestClose([String? result]) async {
    if (_nativeProvidersExhausted || _controller == null) {
      await _close(result);
      return;
    }
    if (_isLiveTvMode) {
      DiagnosticLog.add(
        'native exit confirmation skipped reason=live-tv-route',
      );
      await _close(result);
      return;
    }
    if (!AppState.playerBehaviorSettings.value.confirmBeforeLeaving) {
      await _close(result);
      return;
    }
    _exitConfirmationOpen = true;
    final shouldResume = await _pauseForExitConfirmation();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave playback?'),
        content: const Text(
          'Playback will stop and your progress will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    _exitConfirmationOpen = false;
    if (confirmed == true) {
      await _close(result);
    } else {
      await _resumeAfterExitConfirmation(shouldResume);
    }
  }

  Future<bool> _pauseForExitConfirmation() async {
    final controller = _controller;
    if (controller == null || !controller.isInitialized) return false;
    final wasPlaying = controller.isPlaying;
    if (!wasPlaying) return false;
    DiagnosticLog.add('native exit confirmation paused playback');
    try {
      await controller.pause().timeout(const Duration(milliseconds: 700));
    } catch (error) {
      DiagnosticLog.add(
        'native exit confirmation pause failed error=${_safeDiagnosticError(error)}',
      );
    }
    return true;
  }

  Future<void> _resumeAfterExitConfirmation(bool shouldResume) async {
    final controller = _controller;
    if (!shouldResume ||
        _playerClosing ||
        controller == null ||
        !controller.isInitialized) {
      return;
    }
    DiagnosticLog.add('native exit confirmation cancelled; resuming playback');
    try {
      _userPaused = false;
      await controller.play();
    } catch (error) {
      DiagnosticLog.add(
        'native exit confirmation resume failed error=${_safeDiagnosticError(error)}',
      );
    }
  }

  Future<Duration> _resumePositionFor(Duration duration) async {
    if (_completionCloseStarted || _playerClosing) return Duration.zero;

    final saved = _savedResumePositionFor(duration);
    if (saved <= Duration.zero) return Duration.zero;

    final startBehavior = AppState.playerBehaviorSettings.value.startBehavior;
    if (startBehavior == 'restart') return Duration.zero;
    if (startBehavior == 'resume') return saved;
    if (_resumePromptHandled) {
      return _resumePromptAccepted ? saved : Duration.zero;
    }
    _resumePromptHandled = true;
    _resumePromptAccepted = await _confirmResumePlayback(saved) ?? true;
    return _resumePromptAccepted ? saved : Duration.zero;
  }

  Duration _savedResumePositionFor(Duration duration) {
    if (_completionCloseStarted || _playerClosing) return Duration.zero;

    final item = _progressItem;
    final key = _playbackKey;
    if (item == null || key == null) return Duration.zero;

    final entry = AppState.progressFor(item, playbackKey: key);
    if (entry == null || entry.watchedSeconds <= 0) return Duration.zero;

    final saved = Duration(seconds: entry.watchedSeconds);
    if (duration.inSeconds > 0) {
      final maxResume = duration - const Duration(seconds: 20);
      if (maxResume <= Duration.zero || saved >= maxResume)
        return Duration.zero;
    }
    return saved;
  }

  Duration _automaticResumePositionFor(Duration duration) {
    final saved = _savedResumePositionFor(duration);
    if (saved <= Duration.zero) return Duration.zero;
    final startBehavior = AppState.playerBehaviorSettings.value.startBehavior;
    if (startBehavior == 'restart') return Duration.zero;
    if (startBehavior == 'resume') return saved;
    if (_resumePromptHandled) {
      return _resumePromptAccepted ? saved : Duration.zero;
    }
    return Duration.zero;
  }

  Duration _libVlcRelayPreferredResumePosition(
    PlaybackSource source,
    _NativePlaybackEngine engine,
  ) {
    if (engine != _NativePlaybackEngine.libvlc ||
        !_manualLibVlcConfigured ||
        source.sourceClass != PlaybackSourceClass.direct ||
        !_isHlsSource(source) ||
        source.headers.isEmpty) {
      return _automaticResumePositionFor(Duration.zero);
    }
    final saved = _savedResumePositionFor(Duration.zero);
    if (saved <= Duration.zero) return Duration.zero;
    final startBehavior = AppState.playerBehaviorSettings.value.startBehavior;
    if (startBehavior == 'restart') return Duration.zero;
    if (startBehavior == 'resume') return saved;
    if (_resumePromptHandled) {
      return _resumePromptAccepted ? saved : Duration.zero;
    }
    return saved;
  }

  bool _shouldRevealPlayerBeforeResumePrompt(Duration duration) {
    if (_resumePromptHandled) return false;
    if (AppState.playerBehaviorSettings.value.startBehavior != 'ask') {
      return false;
    }
    return _savedResumePositionFor(duration) > Duration.zero;
  }

  bool _resumePromptCanOpenForController(_NativePlaybackController controller) {
    if (!controller.isInitialized || controller.hasError) return false;
    if (controller.duration <= Duration.zero) return false;
    if (controller.size == Size.zero) return false;
    return true;
  }

  Duration _fallbackControlDuration() {
    final controllerDuration = _controller?.duration ?? Duration.zero;
    if (controllerDuration > Duration.zero) return controllerDuration;
    if (_lastKnownPlaybackDuration > Duration.zero) {
      return _lastKnownPlaybackDuration;
    }
    if (_libVlcContinuousTsActive) return Duration.zero;
    final item = _progressItem;
    final key = _playbackKey;
    if (item == null || key == null) return Duration.zero;
    final entry = AppState.progressFor(item, playbackKey: key);
    final seconds = entry?.durationSeconds ?? 0;
    if (seconds <= 0) return Duration.zero;
    return Duration(seconds: seconds);
  }

  int? _fallbackProgressDurationSeconds() {
    final duration = _fallbackControlDuration();
    return duration.inSeconds > 0 ? duration.inSeconds : null;
  }

  String _headerCountBucket(int count) {
    if (count <= 0) return 'none';
    if (count <= 3) return '1_to_3';
    if (count <= 6) return '4_to_6';
    return '7_plus';
  }

  String _countDiagnosticBucket(int count) {
    if (count <= 0) return 'none';
    if (count == 1) return '1';
    if (count < 5) return '2_to_4';
    if (count < 25) return '5_to_24';
    if (count < 100) return '25_to_99';
    if (count < 500) return '100_to_499';
    return '500_plus';
  }

  String _durationDiagnosticBucket(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes <= 0) return 'unknown';
    if (minutes < 30) return 'under_30m';
    if (minutes < 60) return '30_to_59m';
    if (minutes < 120) return '60_to_119m';
    if (minutes < 180) return '120_to_179m';
    return '180m_plus';
  }

  void _scheduleDeferredResumeSeek(
    Duration position,
    String providerId,
    _NativePlaybackController controller,
  ) {
    _cancelDeferredResumeSeek();
    _deferredResumeSeekPosition = position;
    _deferredResumeSeekProviderId = providerId;
    _deferredResumeSeekAttempts = 0;
    _deferredResumeSeekTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_tryDeferredResumeSeek(controller)),
    );
    unawaited(_tryDeferredResumeSeek(controller));
  }

  void _cancelDeferredResumeSeek() {
    _deferredResumeSeekTimer?.cancel();
    _deferredResumeSeekTimer = null;
    _deferredResumeSeekPosition = null;
    _deferredResumeSeekProviderId = null;
    _deferredResumeSeekAttempts = 0;
    _deferredResumeSeekInFlight = false;
  }

  Future<void> _tryDeferredResumeSeek(
    _NativePlaybackController controller,
  ) async {
    if (_deferredResumeSeekInFlight) return;
    if (_playerClosing || _controller != controller) {
      _cancelDeferredResumeSeek();
      return;
    }
    final position = _deferredResumeSeekPosition;
    final providerId = _deferredResumeSeekProviderId;
    if (position == null || providerId == null) return;

    _deferredResumeSeekAttempts += 1;
    final nativeClockUnavailable =
        controller.duration <= Duration.zero && controller.size == Size.zero;
    final canTryLibVlcMetadataLessSeek =
        controller.engine == _NativePlaybackEngine.libvlc &&
        controller.isPlaying &&
        _deferredResumeSeekAttempts >= 2;
    if (nativeClockUnavailable && !canTryLibVlcMetadataLessSeek) {
      if (_deferredResumeSeekAttempts == 8 ||
          _deferredResumeSeekAttempts == 16 ||
          _deferredResumeSeekAttempts == 24) {
        DiagnosticLog.add(
          'native resume seek waiting provider=$providerId position=${position.inSeconds}s attempts=$_deferredResumeSeekAttempts',
        );
      }
      final maxAttempts = (_resumeSeekRetryWindow.inMilliseconds / 500).ceil();
      if (_deferredResumeSeekAttempts < maxAttempts) return;
      DiagnosticLog.add(
        'native resume seek abandoned provider=$providerId position=${position.inSeconds}s reason=metadata clock unavailable',
      );
      _cancelDeferredResumeSeek();
      return;
    }
    if (nativeClockUnavailable && canTryLibVlcMetadataLessSeek) {
      DiagnosticLog.add(
        'native resume seek trying metadata-less libvlc provider=$providerId position=${position.inSeconds}s attempts=$_deferredResumeSeekAttempts',
      );
    }

    _deferredResumeSeekInFlight = true;
    try {
      await _seekToResumePosition(position, providerId, controller);
      _cancelDeferredResumeSeek();
    } finally {
      _deferredResumeSeekInFlight = false;
    }
  }

  Future<void> _seekToResumePosition(
    Duration position,
    String providerId,
    _NativePlaybackController controller,
  ) async {
    var target = position;
    final duration = controller.duration;
    if (duration > const Duration(seconds: 20) &&
        target >= duration - const Duration(seconds: 20)) {
      target = duration - const Duration(seconds: 20);
    }
    if (target <= Duration.zero) return;
    DiagnosticLog.add(
      'native seeking start provider=$providerId position=${target.inSeconds}s',
    );
    try {
      await controller.seekTo(target).timeout(const Duration(seconds: 4));
      _lastKnownPlaybackPosition = target;
      if (controller.engine == _NativePlaybackEngine.libvlc &&
          controller.duration <= Duration.zero) {
        _resumeProgressAnchorPosition = target;
        _resumeProgressAnchorLogSecond = -1;
      }
      DiagnosticLog.add(
        'native resume seek applied provider=$providerId position=${target.inSeconds}s',
      );
    } catch (error) {
      DiagnosticLog.add(
        'native seek start ignored provider=$providerId error=${_safeDiagnosticError(error)}',
      );
    }
  }

  Future<bool?> _confirmResumePlayback(Duration saved) async {
    if (!mounted) return Future<bool?>.value(true);
    final minutes = saved.inMinutes;
    final label = minutes <= 0 ? 'less than 1 minute' : '$minutes min';
    var dialogClosing = false;
    void closeResumeDialog(BuildContext dialogContext, bool resume) {
      if (dialogClosing) return;
      dialogClosing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!dialogContext.mounted) return;
        Navigator.of(dialogContext).pop(resume);
      });
    }

    _hideControlsTimer?.cancel();
    setState(() {
      _resumeDialogOpen = true;
      _resumeDialogAcceptedAwaitingProof = false;
      _controlsVisible = false;
      _settingsExpanded = false;
      _optionSheetOpen = false;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Resume playback?'),
        content: Text('Continue from $label, or start from the beginning?'),
        actions: [
          TextButton(
            onPressed: () => closeResumeDialog(context, false),
            child: const Text('Start over'),
          ),
          FilledButton(
            onPressed: () => closeResumeDialog(context, true),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
    if (!mounted) return confirmed;
    final controller = _controller;
    final waitForLibVlcProof =
        confirmed == true &&
        controller?.engine == _NativePlaybackEngine.libvlc &&
        !_hasLibVlcVisualPlaybackProof(controller!);
    setState(() {
      _resumeDialogOpen = false;
      _resumeDialogAcceptedAwaitingProof = waitForLibVlcProof;
      _controlsVisible = confirmed == true && !waitForLibVlcProof;
      _playbackWaitMessage = waitForLibVlcProof ? 'Resuming playback...' : null;
      _playbackWaitMessagePausedPlayback = false;
    });
    if (confirmed == true && !waitForLibVlcProof) {
      _scheduleControlsHide();
    }
    return confirmed;
  }

  void _saveNativeProgress({
    bool force = false,
    bool completionObserved = false,
  }) {
    final item = _progressItem;
    final key = _playbackKey;
    final controller = _controller;
    if (item == null || key == null) {
      if (force) {
        DiagnosticLog.add(
          'native progress save skipped reason=missing_progress_target itemPresent=${item != null} playbackKeyPresent=${key != null}',
        );
      }
      return;
    }

    final hasInitializedController =
        controller != null && controller.isInitialized;
    final hasLiveController = hasInitializedController && !controller.hasError;
    final duration = _bestKnownProgressDuration(controller);
    final position = _bestKnownProgressPosition(controller, duration);
    final nativeClockUnavailable =
        hasInitializedController &&
        controller.duration <= Duration.zero &&
        (controller.engine == _NativePlaybackEngine.libvlc ||
            controller.engine == _NativePlaybackEngine.exoplayer);
    final supportsFallbackClock =
        nativeClockUnavailable &&
        (controller.engine == _NativePlaybackEngine.libvlc ||
            controller.engine == _NativePlaybackEngine.exoplayer);
    if (supportsFallbackClock &&
        _resumeProgressAnchorPosition > Duration.zero) {
      if (force &&
          position.inSeconds < _resumeProgressAnchorPosition.inSeconds) {
        DiagnosticLog.add(
          'native progress save skipped reason=fallback_clock_waiting_resume_anchor engine=${controller.engine.id} anchor=${_resumeProgressAnchorPosition.inSeconds}s position=${position.inSeconds}s',
        );
      }
      if (position.inSeconds < _resumeProgressAnchorPosition.inSeconds) return;
    }
    if (supportsFallbackClock && position.inSeconds < 3) {
      if (!controller.isPlaying) {
        if (force) {
          DiagnosticLog.add(
            'native progress save skipped reason=fallback_clock_not_playing engine=${controller.engine.id}',
          );
        }
        return;
      }
      if (_loading || _playbackWaitMessage != null) {
        if (force) {
          DiagnosticLog.add(
            'native progress save skipped reason=fallback_clock_waiting engine=${controller.engine.id} loading=$_loading waitMessage=${_playbackWaitMessage != null}',
          );
        }
        return;
      }
      if (!_progressFallbackClockEnabled) {
        if (force) {
          DiagnosticLog.add(
            'native progress save skipped reason=fallback_clock_disabled engine=${controller.engine.id}',
          );
        }
        return;
      }
      final startedAt = _nativeWallClockStartedAt;
      if (startedAt == null) {
        if (force) {
          DiagnosticLog.add(
            'native progress save skipped reason=missing_wall_clock engine=${controller.engine.id}',
          );
        }
        return;
      }
      final wallClockSeconds = DateTime.now().difference(startedAt).inSeconds;
      final watchedSeconds = wallClockSeconds;
      if (watchedSeconds < 3 && !force) return;
      final deltaSeconds = _lastSavedSecond < 0
          ? watchedSeconds
          : watchedSeconds - _lastSavedSecond;
      if (deltaSeconds <= 0) {
        if (force) {
          DiagnosticLog.add(
            'native progress save skipped reason=no_fallback_delta engine=${controller.engine.id} watched=${watchedSeconds}s last=$_lastSavedSecond',
          );
        }
        return;
      }
      if (!force && deltaSeconds < _nativeProgressSaveIntervalSeconds) return;
      _lastSavedSecond = watchedSeconds;
      final nativePreferences = _currentNativePreferences();
      DiagnosticLog.add(
        'native progress saved with fallback clock engine=${controller.engine.id} watched=${watchedSeconds}s wall=${wallClockSeconds}s delta=${deltaSeconds}s',
      );
      AppState.recordPlaybackProgress(
        item: item,
        playbackKey: key,
        title: _title,
        subtitle: _progressSubtitle,
        durationSeconds: duration.inSeconds > 0
            ? duration.inSeconds
            : _fallbackProgressDurationSeconds(),
        watchedSeconds: deltaSeconds,
        completionObserved: completionObserved,
        trustedCompletionObserved: false,
        generation: _progressGeneration,
        nativePreferences: nativePreferences,
      );
      _rememberVerifiedSource(controller, Duration(seconds: watchedSeconds));
      return;
    }
    if (duration.inSeconds <= 0 || position.inSeconds < 3) {
      if (force) {
        _saveNativePreferencesOnly(reason: 'progress_clock_unavailable');
        DiagnosticLog.add(
          'native progress save skipped reason=invalid_clock duration=${duration.inSeconds}s position=${position.inSeconds}s initialized=$hasInitializedController live=$hasLiveController',
        );
      }
      return;
    }
    _creditPlaybackIntegrityPosition(position, reason: 'progress_save');
    if (!force &&
        (position.inSeconds - _lastSavedSecond).abs() <
            _nativeProgressSaveIntervalSeconds) {
      return;
    }
    _creditPlaybackIntegrityPosition(position, reason: 'progress_save');
    _lastSavedSecond = position.inSeconds;
    final nativePreferences = _currentNativePreferences();
    final endedCompletion = completionObserved && controller?.isEnded == true;
    final trustedCompletionObserved = completionObserved;
    final credibleCompletionObserved =
        completionObserved &&
        (trustedCompletionObserved ||
            _hasCredibleCompletionForNativeEnd(
              durationSeconds: duration.inSeconds,
              positionSeconds: position.inSeconds,
              ended: endedCompletion,
            ));
    final effectivePosition = completionObserved && credibleCompletionObserved
        ? duration
        : position;
    final savedPosition = _resumeSafeProgressPosition(
      effectivePosition,
      duration,
      completionObserved: credibleCompletionObserved,
    );
    if (completionObserved) {
      DiagnosticLog.add(
        'native completion trust observed trustedCompletion=$trustedCompletionObserved credibleCompletion=$credibleCompletionObserved credibleWatched=${_credibleWatchSeconds}s position=${position.inSeconds}s duration=${duration.inSeconds}s',
      );
    }
    if (savedPosition != effectivePosition) {
      DiagnosticLog.add(
        'native progress near-end capped for resume position=${effectivePosition.inSeconds}s saved=${savedPosition.inSeconds}s duration=${duration.inSeconds}s reason=incomplete_near_end completionObserved=$completionObserved trustedCompletion=$trustedCompletionObserved credibleCompletion=$credibleCompletionObserved credibleWatched=${_credibleWatchSeconds}s',
      );
    }
    DiagnosticLog.add(
      'native progress saved with player clock engine=${controller?.engine.id ?? 'cached'} watched=${savedPosition.inSeconds}s duration=${duration.inSeconds}s force=$force',
    );
    if (controller != null) {
      _rememberVerifiedSource(controller, position);
    }

    AppState.setPlaybackProgress(
      item: item,
      playbackKey: key,
      title: _title,
      subtitle: _progressSubtitle,
      durationSeconds: duration.inSeconds,
      watchedSeconds: savedPosition.inSeconds,
      credibleWatchedSeconds: _credibleWatchSeconds,
      completionObserved: completionObserved,
      trustedCompletionObserved: trustedCompletionObserved,
      generation: _progressGeneration,
      nativePreferences: nativePreferences,
    );
  }

  bool _hasCredibleCompletionForNativeEnd({
    required int durationSeconds,
    required int positionSeconds,
    required bool ended,
  }) {
    if (AppState.hasCredibleCompletionEvidence(
      durationSeconds: durationSeconds,
      credibleWatchedSeconds: _credibleWatchSeconds,
    )) {
      return true;
    }
    if (!ended || durationSeconds <= 0) return false;
    final nearEnd = positionSeconds / durationSeconds >= 0.95;
    if (!nearEnd) return false;
    return _credibleWatchSeconds >= 60;
  }

  Duration _resumeSafeProgressPosition(
    Duration position,
    Duration duration, {
    required bool completionObserved,
  }) {
    if (completionObserved ||
        duration <= Duration.zero ||
        position < const Duration(seconds: 3)) {
      return position;
    }
    final progress = position.inMilliseconds / duration.inMilliseconds;
    if (progress < 0.95) return position;

    final percentCapMs = (duration.inMilliseconds * 0.92).round();
    final tailCapMs =
        duration.inMilliseconds - const Duration(minutes: 3).inMilliseconds;
    final preferredCapMs = tailCapMs > 0
        ? math.min(percentCapMs, tailCapMs)
        : percentCapMs;
    final capMs = math.max(
      const Duration(seconds: 3).inMilliseconds,
      preferredCapMs,
    );
    if (position.inMilliseconds <= capMs) return position;
    return Duration(milliseconds: capMs);
  }

  NativePlayerPreferences _currentNativePreferences() {
    return NativePlayerPreferences(
      quality: _preferredQuality ?? 'Auto',
      speed: _playbackSpeed,
      subtitleId: _activeSubtitle?.id,
      subtitleDelaySeconds: _subtitleDelaySeconds,
      subtitleDelayCustomized: _subtitleDelayCustomized,
      subtitleFontSize: _subtitleFontSize,
      subtitleBackgroundOpacity: _subtitleBackgroundOpacity,
      subtitleBackgroundColor: _subtitleBackgroundColor.value,
      subtitleBackgroundRadius: _subtitleBackgroundRadius,
      subtitleTextColor: _subtitleTextColor.value,
      subtitleBottomOffset: _subtitleBottomOffset,
      videoFitMode: _fitMode.name,
    );
  }

  void _saveNativePreferencesOnly({required String reason}) {
    final item = _progressItem;
    final key = _playbackKey;
    if (item == null || key == null) {
      DiagnosticLog.add(
        'native preferences save skipped reason=missing_progress_target trigger=$reason itemPresent=${item != null} playbackKeyPresent=${key != null}',
      );
      return;
    }
    AppState.updateNativePlayerPreferences(
      item: item,
      playbackKey: key,
      title: _title,
      subtitle: _progressSubtitle,
      generation: _progressGeneration,
      nativePreferences: _currentNativePreferences(),
    );
    DiagnosticLog.add('native preferences saved reason=$reason key=[redacted]');
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    if (!_controlsVisible ||
        _resumeDialogOpen ||
        _pictureInPictureActive ||
        !_nativeControlsReady(_controller) ||
        _settingsExpanded) {
      return;
    }
    final timeout =
        AppState.playerBehaviorSettings.value.controlsTimeoutSeconds;
    _hideControlsTimer = Timer(Duration(seconds: timeout), () {
      if (!mounted) return;
      setState(() {
        _controlsVisible = false;
        _settingsExpanded = false;
      });
    });
  }

  void _ensureControlsAutoHide({required String reason}) {
    if (!_controlsVisible || _hideControlsTimer?.isActive == true) return;
    if (_settingsExpanded ||
        _optionSheetOpen ||
        _resumeDialogOpen ||
        _loading ||
        _playbackWaitMessage != null) {
      return;
    }
    final controller = _controller;
    if (controller == null ||
        !controller.isInitialized ||
        !controller.isPlaying ||
        !_nativeControlsReady(controller)) {
      return;
    }
    DiagnosticLog.add(
      'native controls auto-hide scheduled reason=$reason engine=${controller.engine.id}',
    );
    _scheduleControlsHide();
  }

  int get _nativeProgressSaveIntervalSeconds {
    final source = _activeSource;
    if (source?.sourceClass == PlaybackSourceClass.p2p) return 15;
    return 5;
  }

  bool _nativeControlsReady(_NativePlaybackController? controller) {
    if (controller == null ||
        !controller.isInitialized ||
        controller.hasError ||
        _loading ||
        _openingSource ||
        _recoveringFromStall ||
        _resolverTemporarilyBlocked ||
        _playbackWaitMessage != null ||
        _activeSource == null) {
      return false;
    }
    if (controller.engine == _NativePlaybackEngine.libvlc) {
      return true;
    }
    if (_activeSourceHasZeroClockMetadata) {
      return false;
    }
    final hasUsableClock = controller.duration > Duration.zero;
    final hasVideoSurface = controller.size != Size.zero;
    return hasUsableClock && hasVideoSurface;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller?.isInitialized == true;
    final nativeControlsReady = _nativeControlsReady(controller);
    final controlsSuppressed = _resumeDialogOpen;
    final controlsDimmed =
        !controlsSuppressed &&
        (_settingsExpanded || (_optionSheetOpen && !_loading));
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, __) {
        if (didPop) {
          _exitPlayerMode();
          return;
        }
        unawaited(
          _nativeProvidersExhausted || controller == null
              ? _close('closed')
              : _requestClose(),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compactPlayer =
                _pictureInPictureActive ||
                constraints.maxWidth <= 360 ||
                constraints.maxHeight <= 240;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _settingsExpanded || _loading || controlsSuppressed
                  ? null
                  : _toggleControls,
              onVerticalDragUpdate:
                  _settingsExpanded ||
                      _loading ||
                      compactPlayer ||
                      controlsSuppressed
                  ? null
                  : (details) =>
                        _handleVerticalDrag(details, constraints.maxWidth),
              onVerticalDragEnd:
                  _settingsExpanded || _loading || controlsSuppressed
                  ? null
                  : (_) => _clearGestureOverlay(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  if (controller != null &&
                      (initialized ||
                          controller.requiresPlatformViewWarmup ||
                          controller.engine == _NativePlaybackEngine.libvlc))
                    _VideoSurface(controller: controller, fitMode: _fitMode),
                  if (_loading && !initialized)
                    _NativePlayerLoading(
                      title: _title,
                      logoUrl: _logoUrl,
                      backgroundUrl: _progressItem?.background,
                      backdropStyle: AppState
                          .playerBehaviorSettings
                          .value
                          .loadingBackdropStyle,
                      message: _statusMessage,
                      onBack: () {
                        unawaited(
                          _nativeProvidersExhausted || controller == null
                              ? _close('closed')
                              : _requestClose(),
                        );
                      },
                      onRetry: _nativeProvidersExhausted
                          ? () {
                              _failureCloseGeneration += 1;
                              _providerIndex = 0;
                              _sourceIndex = 0;
                              _enginePassIndex = 0;
                              _qualityPassIndex = 0;
                              _libvlcUnavailableForSession = false;
                              _liveTvAutoRetryAttempted = false;
                              _skipUnsupportedHighEfficiencyForSession = false;
                              _nativeSourceClassSkipCounts.clear();
                              _providerResolveFutures.clear();
                              _failedSourceAttempts.clear();
                              _blackVideoRecoveredUrls.clear();
                              final status = _enginePassStatusFor(
                                _enginePassesForCurrentSettings(),
                              );
                              _logPlaybackStatus(
                                status,
                                reason: 'retry_sources',
                              );
                              setState(() {
                                _loading = true;
                                _controlsVisible = true;
                                _nativeProvidersExhausted = false;
                                _statusMessage = status;
                              });
                              unawaited(_openNextAvailableSource());
                            }
                          : null,
                      onChooseSource:
                          _nativeProvidersExhausted && _activeSources.length > 1
                          ? () => unawaited(_showSourceSheet())
                          : null,
                    ),
                  if (_loading && initialized)
                    _NativeRefreshOverlay(
                      message: _statusMessage ?? 'Refreshing...',
                      onBack: () => unawaited(_requestClose()),
                    ),
                  if (!_loading && _playbackWaitMessage != null)
                    _NativePlaybackStatusOverlay(label: _playbackWaitMessage!),
                  if (!nativeControlsReady &&
                      !_loading &&
                      !controlsSuppressed &&
                      !_pictureInPictureActive)
                    SafeArea(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _PlayerRoundButton(
                            icon: Icons.arrow_back_rounded,
                            semanticLabel: 'Close player',
                            onPressed: () => unawaited(_requestClose()),
                          ),
                        ),
                      ),
                    ),
                  if (_subtitleText != null && !_loading)
                    _SubtitleOverlay(
                      text: _subtitleText!,
                      fontSize: _subtitleFontSize,
                      backgroundOpacity: _subtitleBackgroundOpacity,
                      backgroundColor: _subtitleBackgroundColor,
                      backgroundRadius: _subtitleBackgroundRadius,
                      textColor: _subtitleTextColor,
                      bottomOffset:
                          (_pictureInPictureActive || _systemPipHandoffActive)
                          ? 8
                          : _subtitleBottomOffset,
                      compactMode: compactPlayer,
                    ),
                  if (controlsDimmed)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _settingsExpanded && !_loading
                            ? _toggleSettingsPack
                            : null,
                        child: AnimatedOpacity(
                          opacity: controlsDimmed ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: IgnorePointer(
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.52),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!_loading &&
                      _playbackWaitMessage == null &&
                      !controlsSuppressed &&
                      nativeControlsReady &&
                      !_pictureInPictureActive)
                    _AnimatedPlayerControls(
                      visible: _controlsVisible && nativeControlsReady,
                      child: _NativePlayerControls(
                        title: _title,
                        nextEpisodeLabel: _nextEpisodeLabel,
                        controller: controller,
                        fallbackDuration: _fallbackControlDuration(),
                        fallbackPosition: _bestKnownProgressPosition(
                          controller,
                          _fallbackControlDuration(),
                        ),
                        locked: _locked,
                        liveMode: _isLiveTvMode,
                        buffering:
                            initialized &&
                            controller!.isBuffering &&
                            !_recoveringFromStall,
                        onBack: () {
                          unawaited(_requestClose());
                        },
                        onNextEpisode: _nextEpisodeLabel == null
                            ? null
                            : () {
                                DiagnosticLog.add(
                                  'native next episode pressed label="$_nextEpisodeLabel"',
                                );
                                unawaited(_openNextEpisodeInPlace());
                              },
                        onPlayPause: _togglePlayback,
                        seekStepSeconds: _seekStepSeconds.round(),
                        onSeekBackward: () => _seekBy(
                          Duration(seconds: -_seekStepSeconds.round()),
                        ),
                        onSeekForward: () => _seekBy(
                          Duration(seconds: _seekStepSeconds.round()),
                        ),
                        onSeekToFraction: _seekToFraction,
                        onToggleLock: _toggleLock,
                        onEnterPip: _handlePictureInPictureButton,
                        onOpenCast: _openScreencast,
                        pipSupported: _canEnterSystemPictureInPicture(),
                        sourceSelectionAvailable: _activeSources.length > 1,
                        onSourcePressed: _showSourceSheet,
                        sourceActionLabel: _sourceActionLabel(),
                        sourceIndicator: _sourceIndicatorLabel(),
                        qualityLabel: _qualityControlLabel(
                          _usingGlobalOverrides,
                          _qualityPreferenceMode,
                          _preferredQuality,
                        ),
                        onQualityPressed: _showQualitySheet,
                        speedLabel: _speedLabel(_playbackSpeed),
                        onSpeedPressed: _showSpeedSheet,
                        fitMode: _fitMode,
                        onFitPressed: _showFitSheet,
                        onReloadPressed: _reloadCurrentSource,
                        settingsExpanded: _settingsExpanded,
                        limitedSettingsMode: _usingGlobalOverrides,
                        onToggleSettings: _toggleSettingsPack,
                        subtitlesAvailable: _subtitles.isNotEmpty,
                        subtitlesEnabled: _activeSubtitle != null,
                        onSubtitlePressed: _showSubtitleSheet,
                        compactMode: compactPlayer,
                        pictureInPictureActive: _pictureInPictureActive,
                      ),
                    ),
                  if (_gestureLabel != null)
                    _GestureOverlay(icon: _gestureIcon, label: _gestureLabel!),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _speedLabel(double value) {
  if ((value - 1).abs() < 0.001) return '1x';
  return '${value.toStringAsFixed(value % 1 == 0 ? 0 : 2).replaceAll(RegExp(r'0$'), '').replaceAll(RegExp(r'\.$'), '')}x';
}

String _speedMenuLabel(String label) {
  return label == '1x' ? '1x (Normal)' : label;
}

String _subtitleDelayLabel(double seconds) {
  if (seconds.abs() < 0.01) return '0s';
  final sign = seconds > 0 ? '+' : '';
  final value = seconds % 1 == 0
      ? seconds.toStringAsFixed(0)
      : seconds.toStringAsFixed(1);
  return '$sign${value}s';
}

String _subtitlePositionLabel(double bottomOffset) {
  if (bottomOffset <= 34) return 'Low';
  if (bottomOffset >= 72) return 'High';
  return 'Mid';
}

String _fitModeLabel(VideoFitMode mode) {
  return switch (mode) {
    VideoFitMode.fit => 'Fit',
    VideoFitMode.fill => 'Fill',
    VideoFitMode.wide => 'Wide',
    VideoFitMode.stretch => 'Stretch',
  };
}

String _qualityLabel(PlaybackSource? source) {
  return _displayQualityLabel(playbackQualityLabel(source));
}

String _displayQualityLabel(String quality) {
  final trimmed = quality.trim();
  if (trimmed.isEmpty) return 'Auto';
  final lower = trimmed.toLowerCase();
  if (lower == 'auto' || lower == 'unknown') return 'Auto';
  return trimmed.replaceAllMapped(
    RegExp(r'(\d+)\s*p\b', caseSensitive: false),
    (match) => '${match.group(1)}P',
  );
}

String _qualityControlLabel(
  bool usingGlobalOverrides,
  String qualityPreferenceMode,
  String? preferredQuality,
) {
  if (!usingGlobalOverrides) {
    return preferredQuality ?? 'Auto';
  }
  return switch (qualityPreferenceMode) {
    'higher' => 'Higher quality',
    'dataSaver' => 'Data saver',
    'advanced' => preferredQuality ?? 'Auto',
    _ => 'Recommended',
  };
}

int _qualityRank(String label) {
  return playbackQualityRank(label);
}

int _dataSaverQualityRank(String label) {
  final rank = _qualityRank(label);
  return rank > 0 ? rank : 9999;
}

P2pPriorityConfig _p2pPriorityConfigFromSettings() {
  final behavior = AppState.playerBehaviorSettings.value;
  return P2pPriorityConfig(
    enabled: behavior.p2pSourcePrioritiesEnabled,
    mode: behavior.p2pPriorityMode,
    resultsPerQuality: behavior.p2pResultsPerQuality,
    preferredAudioLanguageMode: behavior.p2pPreferredAudioLanguageMode,
    avoidRiskyFormats: behavior.p2pAvoidRiskyFormats,
    sizeLimitMb: behavior.p2pSizeLimitMb,
  );
}

int _nativeSourceClassRank(PlaybackSource source) {
  return switch (source.sourceClass) {
    PlaybackSourceClass.direct => 0,
    PlaybackSourceClass.debrid => 0,
    PlaybackSourceClass.p2p => 1,
    PlaybackSourceClass.external =>
      AppState.playbackSourceClassAllowedForNative(source.sourceClass) ? 2 : 3,
    PlaybackSourceClass.unsupported => 3,
  };
}

class _P2pLocalStreamReady {
  const _P2pLocalStreamReady({this.totalBytes});

  final int? totalBytes;
}

class _P2pLocalStreamNotReadyException implements Exception {
  const _P2pLocalStreamNotReadyException({required this.deadSwarm});

  final bool deadSwarm;

  @override
  String toString() => deadSwarm
      ? 'P2P local stream is still buffering: no peers yet.'
      : 'P2P local stream is still buffering.';
}

int _p2pTrackerCount(PlaybackSource source) {
  return P2pStreamDescriptor.fromSyntheticUrl(source.url)?.trackers.length ?? 0;
}

List<_DisplaySourceEntry> _displaySourceEntries(List<PlaybackSource> sources) {
  return groupVisiblePlaybackSources(sources)
      .map(
        (group) => _DisplaySourceEntry(
          primary: group.primary,
          variants: group.variants,
        ),
      )
      .toList(growable: false);
}

(int, int) _displaySourceProgress(
  List<PlaybackSource> sources,
  int sourceIndex,
) {
  return visiblePlaybackSourceProgress(sources, sourceIndex);
}

int? _nextSourceIndexInCurrentVisibleGroup(
  List<PlaybackSource> sources,
  int sourceIndex,
) {
  if (sources.isEmpty || sourceIndex < 0 || sourceIndex >= sources.length)
    return null;
  final currentUrl = sources[sourceIndex].url;
  if (currentUrl.isEmpty) return null;
  final groups = groupVisiblePlaybackSources(sources);
  final visibleIndex = groups.indexWhere(
    (group) => group.variants.any((source) => source.url == currentUrl),
  );
  if (visibleIndex < 0) return null;
  final variants = groups[visibleIndex].variants;
  final variantIndex = variants.indexWhere(
    (source) => source.url == currentUrl,
  );
  if (variantIndex < 0 || variantIndex + 1 >= variants.length) return null;
  for (final source in variants.skip(variantIndex + 1)) {
    if (!_nativeSourceClassIsPlayable(source)) continue;
    final nextSourceIndex = sources.indexWhere(
      (candidate) => candidate.url == source.url,
    );
    if (nextSourceIndex >= 0) return nextSourceIndex;
  }
  return null;
}

int? _nextSourceIndexAfterCurrentVisibleGroup(
  List<PlaybackSource> sources,
  int sourceIndex,
) {
  if (sources.isEmpty || sourceIndex < 0 || sourceIndex >= sources.length)
    return null;
  final currentUrl = sources[sourceIndex].url;
  if (currentUrl.isEmpty) return null;
  final groups = groupVisiblePlaybackSources(sources);
  final visibleIndex = groups.indexWhere(
    (group) => group.variants.any((source) => source.url == currentUrl),
  );
  if (visibleIndex < 0 || visibleIndex + 1 >= groups.length) return null;
  for (final group in groups.skip(visibleIndex + 1)) {
    final playableSource = _nativePlayableSourceForEntry(
      _DisplaySourceEntry(primary: group.primary, variants: group.variants),
    );
    if (playableSource == null) continue;
    final nextSourceIndex = sources.indexWhere(
      (source) => source.url == playableSource.url,
    );
    if (nextSourceIndex >= 0) return nextSourceIndex;
  }
  return null;
}

String _sourceDisplayLabel(
  PlaybackSource source, {
  required int index,
  required int total,
}) {
  final quality = _qualityLabel(source);
  final parts = <String>['Source ${index + 1}'];
  if (total > 1) parts[0] = 'Source ${index + 1}/$total';
  if (quality != 'Auto') parts.add(quality);
  final sourceClassLabel = _sourceClassDisplayLabel(source);
  if (sourceClassLabel != null) parts.add(sourceClassLabel);
  return parts.join(' - ');
}

String? _sourceClassDisplayLabel(PlaybackSource source) {
  return switch (source.sourceClass) {
    PlaybackSourceClass.direct => null,
    PlaybackSourceClass.debrid => 'Cached',
    PlaybackSourceClass.external => 'External',
    PlaybackSourceClass.p2p => 'P2P',
    PlaybackSourceClass.unsupported => 'Unsupported',
  };
}

bool _nativeSourceClassIsPlayable(PlaybackSource source) {
  return AppState.playbackSourceClassAllowedForNative(source.sourceClass);
}

PlaybackSource? _nativePlayableSourceForEntry(_DisplaySourceEntry entry) {
  for (final source in entry.variants) {
    if (_nativeSourceClassIsPlayable(source)) return source;
  }
  return null;
}

List<PlaybackSource> _nativePlayableSources(List<PlaybackSource> sources) {
  return sources.where(_nativeSourceClassIsPlayable).toList(growable: false);
}

String _sourceClassDisabledReason(PlaybackSource source) {
  final behavior = AppState.playerBehaviorSettings.value;
  return switch (source.sourceClass) {
    PlaybackSourceClass.external =>
      'External source - native playback cannot open this yet.',
    PlaybackSourceClass.p2p =>
      !P2pLocalStreamBridge.instance.isAvailable
          ? 'P2P source - Advanced P2P support is not installed yet.'
          : !behavior.p2pPlaybackConsentAccepted
          ? 'P2P source - review advanced consent before playback.'
          : !behavior.p2pPlaybackEnabled
          ? 'P2P source - advanced playback is off.'
          : 'P2P source - waiting for approved runtime proof.',
    PlaybackSourceClass.unsupported =>
      'Unsupported source type for this build.',
    PlaybackSourceClass.direct ||
    PlaybackSourceClass.debrid => 'Native playback supported.',
  };
}

String? _sourceLanguageLabel(PlaybackSource source) {
  return playbackSourceLanguageLabel(source);
}

String _providerLabel(String? providerId) {
  final normalized = (providerId ?? '').trim().toLowerCase();
  if (normalized.startsWith('addon-')) return 'stream add-on';
  return switch (normalized) {
    'public-iptv' => 'Live TV',
    'vidlink' => 'Alpha',
    'vidsrc' => 'Beta',
    'icefy' => 'Delta',
    'vidnest' => 'Epsilon',
    'primesrc' => 'Zeta',
    'xpass' => 'Zeta',
    'cineby' => 'Eta',
    'moviesapi' => 'Eta',
    'vidking' => 'Nu',
    'popr' => 'Theta',
    'cinesu' => 'Rho',
    'vidapi' => 'Sigma',
    'videasy' => 'Tau',
    'vidfun' => 'Upsilon',
    'flixhq' => 'Phi',
    'rgshows' => 'Iota',
    'vixsrc' => 'Kappa',
    'vidrock' => 'Lambda',
    'vidzee' => 'Mu',
    'flixer' => 'Xi',
    '7xstream' => 'Omicron',
    'meowtv' => 'Pi',
    '' => 'provider',
    _ => 'provider',
  };
}

bool _isPublicIptvSource(PlaybackSource source) {
  return source.providerId.trim().toLowerCase() == 'public-iptv';
}

class _AnimatedPlayerControls extends StatelessWidget {
  const _AnimatedPlayerControls({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curve = visible ? Curves.easeOutCubic : Curves.easeInCubic;
    final duration = Duration(milliseconds: visible ? 140 : 210);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        curve: curve,
        child: child,
      ),
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({required this.controller, required this.fitMode});

  final _NativePlaybackController controller;
  final VideoFitMode fitMode;

  @override
  Widget build(BuildContext context) {
    final size = controller.size;
    final width = size.width > 0 ? size.width : 16.0;
    final height = size.height > 0 ? size.height : 9.0;
    final displayAspectRatio = _displayAspectRatioFor(controller);
    final player = _NativePlaybackSurface(
      controller: controller,
      aspectRatio: displayAspectRatio,
    );

    return switch (fitMode) {
      VideoFitMode.fit => Center(
        child: AspectRatio(aspectRatio: displayAspectRatio, child: player),
      ),
      VideoFitMode.fill => SizedBox.expand(
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(width: width, height: height, child: player),
          ),
        ),
      ),
      VideoFitMode.wide => Center(
        child: ClipRect(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(width: width, height: height, child: player),
            ),
          ),
        ),
      ),
      VideoFitMode.stretch => SizedBox.expand(child: player),
    };
  }
}

double _displayAspectRatioFor(_NativePlaybackController controller) {
  final size = controller.size;
  if (size.width > 0 && size.height > 0) {
    return size.width / size.height;
  }
  final raw = controller.aspectRatio;
  if (raw.isFinite && raw > 1.05) return raw;
  return 16 / 9;
}

class _NativePlaybackSurface extends StatelessWidget {
  const _NativePlaybackSurface({
    required this.controller,
    required this.aspectRatio,
  });

  final _NativePlaybackController controller;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final video = controller.video;
    if (video != null) return VideoPlayer(video);
    final media3 = controller.media3;
    if (media3 != null) {
      return IgnorePointer(
        child: AndroidView(
          viewType: 'app.juicr.flutter/media3_player',
          creationParams: media3.creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: media3.attachView,
        ),
      );
    }
    final vlc = controller.vlc;
    if (vlc != null) {
      return VlcPlayer(
        controller: vlc,
        aspectRatio: aspectRatio,
        placeholder: const ColoredBox(color: Colors.black),
        virtualDisplay: true,
      );
    }
    return const SizedBox.shrink();
  }
}

class _CompactNativePlayerControls extends StatelessWidget {
  const _CompactNativePlayerControls({
    required this.initialized,
    required this.playing,
    required this.liveMode,
    required this.position,
    required this.duration,
    required this.progress,
    required this.seekStepSeconds,
    required this.onBack,
    required this.onFullscreen,
    required this.onPlayPause,
    required this.onSeekBackward,
    required this.onSeekForward,
    required this.onSeekToFraction,
    required this.pictureInPictureActive,
  });

  final bool initialized;
  final bool playing;
  final bool liveMode;
  final Duration position;
  final Duration duration;
  final double progress;
  final int seekStepSeconds;
  final VoidCallback onBack;
  final VoidCallback onFullscreen;
  final VoidCallback onPlayPause;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final ValueChanged<double> onSeekToFraction;
  final bool pictureInPictureActive;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final shortest = math.min(width, height);
        final chromeButtonSize = (shortest * 0.17).clamp(24.0, 34.0);
        final sideButtonSize = (shortest * 0.22).clamp(32.0, 44.0);
        final playButtonSize = (shortest * 0.29).clamp(42.0, 58.0);
        final iconSize = (sideButtonSize * 0.52).clamp(17.0, 23.0);
        final playIconSize = (playButtonSize * 0.65).clamp(27.0, 38.0);
        final progressInset = (width * 0.035).clamp(10.0, 16.0);
        final progressTrackHeight = (height * 0.018).clamp(2.4, 4.0);
        final progressThumbRadius = (height * 0.032).clamp(4.5, 6.8);
        final timeFontSize = (shortest * 0.055).clamp(9.0, 12.0);
        final cornerButtonInsetX = (width * 0.038).clamp(12.0, 17.0);
        final cornerButtonInsetY = (height * 0.052).clamp(8.0, 12.0);
        final transportY = height * 0.48;
        final seekBarHeight = progressThumbRadius * 2 + 4 + timeFontSize + 3;
        final progressTop = math.min(
          height * 0.84 - 12,
          height - seekBarHeight - 8,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            const _ControlGradient(alignment: Alignment.topCenter),
            const _ControlGradient(alignment: Alignment.bottomCenter),
            Positioned(
              left: cornerButtonInsetX,
              top: cornerButtonInsetY,
              child: _MiniPipButton(
                icon: Icons.close_rounded,
                onPressed: onBack,
                semanticLabel: 'Close',
                size: chromeButtonSize,
                iconSize: (chromeButtonSize * 0.60).clamp(15.0, 20.0),
                surfaceAlpha: 0.26,
                borderAlpha: 0.10,
              ),
            ),
            Positioned(
              right: cornerButtonInsetX,
              top: cornerButtonInsetY,
              child: _MiniPipButton(
                icon: pictureInPictureActive
                    ? Icons.fullscreen_rounded
                    : Icons.picture_in_picture_alt_rounded,
                onPressed: onFullscreen,
                semanticLabel: pictureInPictureActive
                    ? 'Fullscreen'
                    : 'Picture in picture',
                size: chromeButtonSize,
                iconSize: (chromeButtonSize * 0.60).clamp(15.0, 20.0),
                surfaceAlpha: 0.26,
                borderAlpha: 0.10,
              ),
            ),
            if (!liveMode)
              Positioned(
                left: width * 0.18 - sideButtonSize / 2,
                top: transportY - sideButtonSize / 2,
                child: _MiniPipButton(
                  icon: Icons.replay_10_rounded,
                  onPressed: onSeekBackward,
                  semanticLabel: 'Back $seekStepSeconds seconds',
                  size: sideButtonSize,
                  iconSize: iconSize,
                  surfaceAlpha: 0.18,
                  borderAlpha: 0.08,
                ),
              ),
            Positioned(
              left: width * 0.50 - playButtonSize / 2,
              top: transportY - playButtonSize / 2,
              child: _MiniPipButton(
                icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onPressed: initialized ? onPlayPause : null,
                semanticLabel: playing ? 'Pause' : 'Play',
                emphasized: true,
                size: playButtonSize,
                iconSize: playIconSize,
                surfaceAlpha: 0.30,
                borderAlpha: 0,
              ),
            ),
            if (!liveMode)
              Positioned(
                left: width * 0.82 - sideButtonSize / 2,
                top: transportY - sideButtonSize / 2,
                child: _MiniPipButton(
                  icon: Icons.forward_10_rounded,
                  onPressed: onSeekForward,
                  semanticLabel: 'Forward $seekStepSeconds seconds',
                  size: sideButtonSize,
                  iconSize: iconSize,
                  surfaceAlpha: 0.18,
                  borderAlpha: 0.08,
                ),
              ),
            if (!liveMode)
              Positioned(
                left: progressInset,
                right: progressInset,
                top: progressTop,
                child: _MiniPipSeekBar(
                  progress: progress,
                  initialized: initialized,
                  onSeekToFraction: onSeekToFraction,
                  currentText: _formatDuration(position),
                  durationText: _formatDuration(duration),
                  fontSize: timeFontSize,
                  trackHeight: progressTrackHeight,
                  thumbRadius: progressThumbRadius,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MiniPipSeekBar extends StatelessWidget {
  const _MiniPipSeekBar({
    required this.progress,
    required this.initialized,
    required this.onSeekToFraction,
    required this.currentText,
    required this.durationText,
    required this.fontSize,
    required this.trackHeight,
    required this.thumbRadius,
  });

  final double progress;
  final bool initialized;
  final ValueChanged<double> onSeekToFraction;
  final String currentText;
  final String durationText;
  final double fontSize;
  final double trackHeight;
  final double thumbRadius;

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = progress.clamp(0.0, 1.0).toDouble();
    final trackTop = thumbRadius;
    final labelTop = thumbRadius * 2 + 4;
    final height = labelTop + fontSize + 3;

    void seekFromLocal(Offset localPosition, BoxConstraints constraints) {
      if (!initialized || constraints.maxWidth <= 0) {
        return;
      }
      onSeekToFraction((localPosition.dx / constraints.maxWidth).clamp(0, 1));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final thumbLeft = (trackWidth * effectiveProgress) - thumbRadius;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              seekFromLocal(details.localPosition, constraints),
          onHorizontalDragUpdate: (details) =>
              seekFromLocal(details.localPosition, constraints),
          child: SizedBox(
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: trackTop,
                  child: Container(
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(trackHeight),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  width: trackWidth * effectiveProgress,
                  top: trackTop,
                  child: Container(
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: _playerAccent(context),
                      borderRadius: BorderRadius.circular(trackHeight),
                    ),
                  ),
                ),
                Positioned(
                  left: thumbLeft.clamp(-thumbRadius, trackWidth - thumbRadius),
                  top: trackTop + trackHeight / 2 - thumbRadius,
                  child: Container(
                    width: thumbRadius * 2,
                    height: thumbRadius * 2,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: labelTop,
                  child: _MiniPipTimeText(
                    text: currentText,
                    fontSize: fontSize,
                  ),
                ),
                Positioned(
                  right: 0,
                  top: labelTop,
                  child: _MiniPipTimeText(
                    text: durationText,
                    fontSize: fontSize,
                    alignRight: true,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniPipTimeText extends StatelessWidget {
  const _MiniPipTimeText({
    required this.text,
    required this.fontSize,
    this.alignRight = false,
  });

  final String text;
  final double fontSize;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        color: Colors.white70,
        fontWeight: FontWeight.w900,
        fontSize: fontSize,
      ),
    );
  }
}

class _MiniPipButton extends StatelessWidget {
  const _MiniPipButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.emphasized = false,
    this.size,
    this.iconSize,
    this.surfaceAlpha,
    this.borderAlpha,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final bool emphasized;
  final double? size;
  final double? iconSize;
  final double? surfaceAlpha;
  final double? borderAlpha;

  @override
  Widget build(BuildContext context) {
    final effectiveSize = size ?? (emphasized ? 34.0 : 28.0);
    final effectiveIconSize = iconSize ?? (emphasized ? 23.0 : 17.0);
    final effectiveSurfaceAlpha = surfaceAlpha ?? (emphasized ? 0.22 : 0.08);
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: Colors.black.withValues(alpha: effectiveSurfaceAlpha),
        shape: const CircleBorder(),
        shadowColor: Colors.black.withValues(alpha: emphasized ? 0.36 : 0.24),
        elevation: emphasized ? 6 : 3,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(
                    alpha: emphasized ? 0.05 : 0.025,
                  ),
                  blurRadius: 2,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: SizedBox.square(
              dimension: effectiveSize,
              child: Icon(
                icon,
                size: effectiveIconSize,
                color: onPressed == null ? Colors.white38 : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NativePlayerControls extends StatelessWidget {
  const _NativePlayerControls({
    required this.title,
    required this.nextEpisodeLabel,
    required this.controller,
    required this.fallbackDuration,
    required this.fallbackPosition,
    required this.locked,
    required this.liveMode,
    required this.buffering,
    required this.onBack,
    required this.onNextEpisode,
    required this.onPlayPause,
    required this.seekStepSeconds,
    required this.onSeekBackward,
    required this.onSeekForward,
    required this.onSeekToFraction,
    required this.onToggleLock,
    required this.onEnterPip,
    required this.onOpenCast,
    required this.pipSupported,
    required this.sourceSelectionAvailable,
    required this.onSourcePressed,
    required this.sourceActionLabel,
    required this.sourceIndicator,
    required this.qualityLabel,
    required this.onQualityPressed,
    required this.speedLabel,
    required this.onSpeedPressed,
    required this.fitMode,
    required this.onFitPressed,
    required this.onReloadPressed,
    required this.settingsExpanded,
    required this.limitedSettingsMode,
    required this.onToggleSettings,
    required this.subtitlesAvailable,
    required this.subtitlesEnabled,
    required this.onSubtitlePressed,
    required this.compactMode,
    required this.pictureInPictureActive,
  });

  final String title;
  final String? nextEpisodeLabel;
  final _NativePlaybackController? controller;
  final Duration fallbackDuration;
  final Duration fallbackPosition;
  final bool locked;
  final bool liveMode;
  final bool buffering;
  final VoidCallback onBack;
  final VoidCallback? onNextEpisode;
  final VoidCallback onPlayPause;
  final int seekStepSeconds;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final ValueChanged<double> onSeekToFraction;
  final VoidCallback onToggleLock;
  final VoidCallback onEnterPip;
  final VoidCallback onOpenCast;
  final bool pipSupported;
  final bool sourceSelectionAvailable;
  final VoidCallback onSourcePressed;
  final String sourceActionLabel;
  final String? sourceIndicator;
  final String qualityLabel;
  final VoidCallback onQualityPressed;
  final String speedLabel;
  final VoidCallback onSpeedPressed;
  final VideoFitMode fitMode;
  final VoidCallback onFitPressed;
  final VoidCallback onReloadPressed;
  final bool settingsExpanded;
  final bool limitedSettingsMode;
  final VoidCallback onToggleSettings;
  final bool subtitlesAvailable;
  final bool subtitlesEnabled;
  final VoidCallback onSubtitlePressed;
  final bool compactMode;
  final bool pictureInPictureActive;

  @override
  Widget build(BuildContext context) {
    final initialized = controller?.isInitialized == true;
    final playing = controller?.isPlaying == true;
    final controllerPosition = initialized
        ? controller!.position
        : Duration.zero;
    final position = fallbackPosition > controllerPosition
        ? fallbackPosition
        : controllerPosition;
    final controllerDuration = initialized
        ? controller!.duration
        : Duration.zero;
    final duration = controllerDuration > Duration.zero
        ? controllerDuration
        : fallbackDuration;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : position.inMilliseconds / duration.inMilliseconds;
    final padding = MediaQuery.paddingOf(context);

    if (compactMode) {
      return _CompactNativePlayerControls(
        initialized: initialized,
        playing: playing,
        liveMode: liveMode,
        position: position,
        duration: duration,
        progress: progress.clamp(0, 1).toDouble(),
        seekStepSeconds: seekStepSeconds,
        onBack: onBack,
        onFullscreen: onEnterPip,
        onPlayPause: onPlayPause,
        onSeekBackward: onSeekBackward,
        onSeekForward: onSeekForward,
        onSeekToFraction: onSeekToFraction,
        pictureInPictureActive: pictureInPictureActive,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const _ControlGradient(alignment: Alignment.topCenter),
        const _ControlGradient(alignment: Alignment.bottomCenter),
        Positioned(
          top: padding.top + 8,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!locked)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: padding.left + 12),
                      child: _PlayerRoundButton(
                        icon: Icons.arrow_back_rounded,
                        semanticLabel: 'Close player',
                        onPressed: onBack,
                      ),
                    ),
                  ),
                if (!locked)
                  LayoutBuilder(
                    builder: (context, headerConstraints) {
                      final titleMaxWidth = math.max(
                        96.0,
                        math.min(
                          headerConstraints.maxWidth * 0.48,
                          headerConstraints.maxWidth - 180,
                        ),
                      );
                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: titleMaxWidth),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.72,
                                            ),
                                            blurRadius: 8,
                                          ),
                                          Shadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.36,
                                            ),
                                            blurRadius: 2,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                ),
                              ),
                              if (buffering) ...[
                                const SizedBox(width: 10),
                                const _InlineBufferingBadge(),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                if (!locked &&
                    nextEpisodeLabel != null &&
                    onNextEpisode != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: padding.right + 12),
                      child: _NextEpisodeButton(
                        label: nextEpisodeLabel!,
                        onPressed: onNextEpisode!,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!locked)
          Positioned.fill(
            child: Stack(
              children: [
                if (!liveMode)
                  Align(
                    alignment: const Alignment(-0.50, 0),
                    child: _SeekButton(
                      forward: false,
                      seconds: seekStepSeconds,
                      onPressed: onSeekBackward,
                    ),
                  ),
                Align(
                  alignment: Alignment.center,
                  child: _MainPlayButton(
                    playing: playing,
                    enabled: initialized,
                    onPressed: onPlayPause,
                  ),
                ),
                if (!liveMode)
                  Align(
                    alignment: const Alignment(0.50, 0),
                    child: _SeekButton(
                      forward: true,
                      seconds: seekStepSeconds,
                      onPressed: onSeekForward,
                    ),
                  ),
              ],
            ),
          ),
        if (initialized && !locked)
          Positioned(
            right: padding.right + 150,
            bottom: padding.bottom + 102,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 230),
              reverseDuration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(animation),
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.96,
                        end: 1,
                      ).animate(animation),
                      alignment: Alignment.bottomRight,
                      child: child,
                    ),
                  ),
                );
              },
              child: settingsExpanded
                  ? _SettingsActionMenu(
                      key: const ValueKey('settings-expanded'),
                      limitedMode: limitedSettingsMode,
                      liveMode: liveMode,
                      qualityLabel: qualityLabel,
                      onQualityPressed: onQualityPressed,
                      speedLabel: speedLabel,
                      onSpeedPressed: onSpeedPressed,
                      fitMode: fitMode,
                      onFitPressed: onFitPressed,
                      onReloadPressed: onReloadPressed,
                      subtitlesAvailable: subtitlesAvailable,
                      subtitlesEnabled: subtitlesEnabled,
                      onSubtitlePressed: onSubtitlePressed,
                    )
                  : const SizedBox(
                      key: ValueKey('settings-collapsed'),
                      width: 0,
                      height: 0,
                    ),
            ),
          ),
        if (initialized)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!locked)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 2, bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _SourceActionButton(
                                onPressed: onSourcePressed,
                                enabled: sourceSelectionAvailable,
                                label: sourceActionLabel,
                                detailLabel: sourceIndicator,
                              ),
                              const SizedBox(width: 8),
                              _SettingsControlPack(
                                expanded: settingsExpanded,
                                onToggleSettings: onToggleSettings,
                              ),
                              const SizedBox(width: 8),
                              _PlayerRoundButton(
                                icon: Icons.cast_rounded,
                                semanticLabel: 'Cast',
                                onPressed: onOpenCast,
                                size: 44,
                              ),
                              const SizedBox(width: 8),
                              _PlayerRoundButton(
                                icon: Icons.picture_in_picture_alt_rounded,
                                semanticLabel: 'Picture in picture',
                                onPressed: onEnterPip,
                                enabled: pipSupported,
                                size: 44,
                              ),
                              const SizedBox(width: 8),
                              _PlayerRoundButton(
                                icon: Icons.lock_open_rounded,
                                semanticLabel: 'Lock controls',
                                onPressed: onToggleLock,
                                size: 44,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 2, bottom: 4),
                          child: _PlayerRoundButton(
                            icon: Icons.lock_rounded,
                            semanticLabel: 'Unlock controls',
                            onPressed: onToggleLock,
                            size: 44,
                          ),
                        ),
                      ),
                    if (!locked && !liveMode)
                      Row(
                        children: [
                          Text(
                            _formatDuration(position),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 15,
                                ),
                                activeTrackColor: _playerAccent(context),
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                overlayColor: _playerAccentOverlay(
                                  context,
                                  0.20,
                                ),
                              ),
                              child: Slider(
                                value: progress.clamp(0, 1).toDouble(),
                                onChanged: initialized
                                    ? onSeekToFraction
                                    : null,
                              ),
                            ),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _QualityButton extends StatelessWidget {
  const _QualityButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(58, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _SourceActionButton extends StatelessWidget {
  const _SourceActionButton({
    required this.onPressed,
    required this.enabled,
    required this.label,
    required this.detailLabel,
  });

  final VoidCallback onPressed;
  final bool enabled;
  final String label;
  final String? detailLabel;

  @override
  Widget build(BuildContext context) {
    final activeColor = _playerAccent(context);
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 116, minHeight: 44),
        child: Material(
          color: enabled
              ? activeColor.withValues(alpha: 0.82)
              : Colors.black.withValues(alpha: 0.42),
          shape: const StadiumBorder(),
          shadowColor: Colors.black.withValues(alpha: 0.34),
          elevation: enabled ? 5 : 2,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.dns_rounded,
                      size: 21,
                      color: enabled ? Colors.white : Colors.white38,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: enabled ? Colors.white : Colors.white38,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                          if (detailLabel != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              detailLabel!,
                              softWrap: true,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: enabled
                                    ? Colors.white70
                                    : Colors.white30,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NextEpisodeButton extends StatelessWidget {
  const _NextEpisodeButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.skip_next_rounded, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        shape: const StadiumBorder(),
      ),
    );
  }
}

class _SettingsControlPack extends StatelessWidget {
  const _SettingsControlPack({
    required this.expanded,
    required this.onToggleSettings,
  });

  final bool expanded;
  final VoidCallback onToggleSettings;

  @override
  Widget build(BuildContext context) {
    return _PlayerRoundButton(
      icon: Icons.settings_rounded,
      semanticLabel: expanded
          ? 'Close player settings'
          : 'Open player settings',
      onPressed: onToggleSettings,
      active: expanded,
      size: 44,
    );
  }
}

class _SettingsActionMenu extends StatelessWidget {
  const _SettingsActionMenu({
    super.key,
    required this.limitedMode,
    required this.liveMode,
    required this.qualityLabel,
    required this.onQualityPressed,
    required this.speedLabel,
    required this.onSpeedPressed,
    required this.fitMode,
    required this.onFitPressed,
    required this.onReloadPressed,
    required this.subtitlesAvailable,
    required this.subtitlesEnabled,
    required this.onSubtitlePressed,
  });

  final bool limitedMode;
  final bool liveMode;
  final String qualityLabel;
  final VoidCallback onQualityPressed;
  final String speedLabel;
  final VoidCallback onSpeedPressed;
  final VideoFitMode fitMode;
  final VoidCallback onFitPressed;
  final VoidCallback onReloadPressed;
  final bool subtitlesAvailable;
  final bool subtitlesEnabled;
  final VoidCallback onSubtitlePressed;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      _SettingsActionButton(
        icon: Icons.closed_caption_rounded,
        label: 'Subtitle',
        onPressed: onSubtitlePressed,
        enabled: subtitlesAvailable,
        active: subtitlesEnabled,
      ),
      if (!limitedMode) ...[
        _SettingsActionButton(
          icon: Icons.high_quality_rounded,
          label: 'Quality: $qualityLabel',
          onPressed: onQualityPressed,
        ),
        _SettingsActionButton(
          icon: Icons.speed_rounded,
          label: 'Speed: ${_speedMenuLabel(speedLabel)}',
          onPressed: onSpeedPressed,
        ),
        _SettingsActionButton(
          icon: Icons.aspect_ratio_rounded,
          label: 'Video Size: ${_fitModeLabel(fitMode)}',
          onPressed: onFitPressed,
          active: fitMode != VideoFitMode.fit,
        ),
      ],
      _SettingsActionButton(
        icon: Icons.refresh_rounded,
        label: liveMode ? 'Refresh Live Stream' : 'Refresh Stream',
        onPressed: onReloadPressed,
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var index = 0; index < actions.length; index++)
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: Duration(milliseconds: 180 + index * 34),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 8),
                      child: child,
                    ),
                  );
                },
                child: actions[index],
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsActionButton extends StatelessWidget {
  const _SettingsActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? Colors.white : Colors.white38;
    final accent = active
        ? _playerAccent(context)
        : Colors.white.withValues(alpha: 0.08);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: TextButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 21),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          disabledForegroundColor: Colors.white38,
          backgroundColor: active
              ? _playerAccentOverlay(context, 0.35)
              : Colors.white.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          minimumSize: const Size(210, 44),
          alignment: Alignment.centerLeft,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }
}

class _QualitySheet extends StatelessWidget {
  const _QualitySheet({
    required this.sources,
    required this.activeSource,
    required this.preferredQuality,
  });

  final List<PlaybackSource> sources;
  final PlaybackSource? activeSource;
  final String? preferredQuality;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedQuality = preferredQuality ?? 'Auto';
    final hasAutoSource = sources.any(
      (source) => _qualityLabel(source) == 'Auto',
    );
    final rankedSources = rankedNativePlaybackSources(
      sources,
      sourceClassAllowed: AppState.playbackSourceClassAllowedForNative,
      p2pConfig: _p2pPriorityConfigFromSettings(),
    );
    final qualitySourceByLabel = <String, PlaybackSource>{};
    for (final source in rankedSources) {
      final label = _qualityLabel(source);
      if (label == 'Auto') continue;
      final existing = qualitySourceByLabel[label];
      if (existing == null ||
          (!_nativeSourceClassIsPlayable(existing) &&
              _nativeSourceClassIsPlayable(source))) {
        qualitySourceByLabel[label] = source;
      }
    }
    final qualitySources = qualitySourceByLabel.entries.toList()
      ..sort((a, b) => _qualityRank(b.key).compareTo(_qualityRank(a.key)));
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: _playerSheetConstraints(context),
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: JuicrVisual.bottomSheetFloatingBorderRadius,
              boxShadow: JuicrVisual.softShadow(
                colorScheme,
                alpha: 0.16,
                blur: 24,
                y: 10,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Quality',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _QualityAutoOption(selected: selectedQuality == 'Auto'),
                  if (qualitySources.isEmpty && !hasAutoSource) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 10),
                      child: Text(
                        'No quality variants available for this source.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ] else ...[
                    for (final entry in qualitySources)
                      _QualityOption(
                        source: entry.value,
                        selected: selectedQuality == entry.key,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QualityAutoSelection {
  const _QualityAutoSelection();
}

class _QualityAutoOption extends StatelessWidget {
  const _QualityAutoOption({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return JuicrSheetOptionTile(
      padding: const EdgeInsets.only(top: 8),
      label: 'Auto',
      selected: selected,
      onTap: () => Navigator.of(context).pop(const _QualityAutoSelection()),
    );
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.sources, required this.activeSource});

  final List<PlaybackSource> sources;
  final PlaybackSource? activeSource;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayEntries = _displaySourceEntries(sources);
    final activeEntryIndex = displayEntries.indexWhere(
      (entry) =>
          entry.variants.any((source) => source.url == activeSource?.url),
    );
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: _playerSheetConstraints(
            context,
            maxPortrait: 0.76,
            maxLandscape: 0.82,
          ),
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: JuicrVisual.bottomSheetFloatingBorderRadius,
              boxShadow: JuicrVisual.softShadow(
                colorScheme,
                alpha: 0.16,
                blur: 24,
                y: 10,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sources',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pick a quality or mirror if the current one buffers or fails.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var index = 0; index < displayEntries.length; index++)
                    _SourceOption(
                      entry: displayEntries[index],
                      index: index,
                      total: displayEntries.length,
                      selected: index == activeEntryIndex,
                      activeSource: activeSource,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedSheet extends StatelessWidget {
  const _SpeedSheet({required this.activeSpeed});

  final double activeSpeed;

  static const List<double> _speeds = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: _playerSheetConstraints(context),
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: JuicrVisual.bottomSheetFloatingBorderRadius,
              boxShadow: JuicrVisual.softShadow(
                colorScheme,
                alpha: 0.16,
                blur: 24,
                y: 10,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Playback speed',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final speed in _speeds)
                    _SpeedOption(
                      speed: speed,
                      selected: (speed - activeSpeed).abs() < 0.001,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QualityOption extends StatelessWidget {
  const _QualityOption({required this.source, required this.selected});

  final PlaybackSource source;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final label = _qualityLabel(source);
    final enabled = _nativeSourceClassIsPlayable(source);
    return JuicrSheetOptionTile(
      padding: const EdgeInsets.only(top: 8),
      label: label,
      subtitle: enabled ? null : _sourceClassDisabledReason(source),
      selected: selected,
      enabled: enabled,
      onTap: enabled ? () => Navigator.of(context).pop(source) : null,
    );
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.entry,
    required this.index,
    required this.total,
    required this.selected,
    required this.activeSource,
  });

  final _DisplaySourceEntry entry;
  final int index;
  final int total;
  final bool selected;
  final PlaybackSource? activeSource;

  @override
  Widget build(BuildContext context) {
    final source = entry.primary;
    final playableSource = _nativePlayableSourceForEntry(entry);
    final enabled = playableSource != null;
    final language = _sourceLanguageLabel(source);
    final languageLabel = language ?? 'Not tagged';
    final mirrorCount = entry.variants.length;
    final groupedSourcesLabel = mirrorCount > 1
        ? ' - $mirrorCount mirrors'
        : '';
    final unsupportedReason = enabled ? '' : _sourceClassDisabledReason(source);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        JuicrSheetOptionTile(
          padding: const EdgeInsets.only(top: 8),
          label: _sourceDisplayLabel(source, index: index, total: total),
          subtitle: enabled
              ? mirrorCount > 1
                    ? 'Audio: $languageLabel - $mirrorCount mirrors available below'
                    : 'Audio: $languageLabel$groupedSourcesLabel'
              : unsupportedReason,
          selected: selected && mirrorCount <= 1,
          enabled: enabled,
          onTap: enabled
              ? () => Navigator.of(context).pop(playableSource)
              : null,
        ),
        if (mirrorCount > 1)
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (
                  var mirrorIndex = 0;
                  mirrorIndex < entry.variants.length;
                  mirrorIndex++
                )
                  _MirrorOption(
                    source: entry.variants[mirrorIndex],
                    index: mirrorIndex,
                    total: entry.variants.length,
                    selected:
                        activeSource?.url == entry.variants[mirrorIndex].url,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MirrorOption extends StatelessWidget {
  const _MirrorOption({
    required this.source,
    required this.index,
    required this.total,
    required this.selected,
  });

  final PlaybackSource source;
  final int index;
  final int total;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = _nativeSourceClassIsPlayable(source);
    final language = _sourceLanguageLabel(source);
    final parts = <String>[_qualityLabel(source)];
    parts.add('Audio: ${language ?? 'Not tagged'}');
    final sourceClassLabel = _sourceClassDisplayLabel(source);
    if (sourceClassLabel != null) parts.add(sourceClassLabel);
    return JuicrSheetOptionTile(
      padding: const EdgeInsets.only(top: 6),
      label: 'Mirror ${index + 1}/$total',
      subtitle: enabled
          ? parts.join(' - ')
          : _sourceClassDisabledReason(source),
      selected: selected,
      enabled: enabled,
      onTap: enabled ? () => Navigator.of(context).pop(source) : null,
    );
  }
}

class _DisplaySourceEntry {
  const _DisplaySourceEntry({required this.primary, required this.variants});

  final PlaybackSource primary;
  final List<PlaybackSource> variants;
}

class _QualityPass {
  const _QualityPass({
    required this.target,
    required this.isHighestAvailable,
    required this.isUnknownQuality,
    required this.label,
  });

  factory _QualityPass.target(_QualityPassTarget target) {
    return _QualityPass(
      target: target,
      isHighestAvailable: false,
      isUnknownQuality: false,
      label: target.label ?? '${target.rank ?? 'preferred'}p',
    );
  }

  factory _QualityPass.rank(int rank) {
    return _QualityPass(
      target: _QualityPassTarget(rank: rank),
      isHighestAvailable: false,
      isUnknownQuality: false,
      label: '${rank}p',
    );
  }

  static const _QualityPass highestAvailablePass = _QualityPass(
    target: null,
    isHighestAvailable: true,
    isUnknownQuality: false,
    label: 'highest available',
  );

  static const _QualityPass autoPass = _QualityPass(
    target: null,
    isHighestAvailable: false,
    isUnknownQuality: false,
    label: 'auto',
  );

  static const _QualityPass unknownPass = _QualityPass(
    target: null,
    isHighestAvailable: false,
    isUnknownQuality: true,
    label: 'unknown',
  );

  final _QualityPassTarget? target;
  final bool isHighestAvailable;
  final bool isUnknownQuality;
  final String label;
}

class _QualityPassTarget {
  const _QualityPassTarget({this.label, this.rank});

  final String? label;
  final int? rank;
}

class _SpeedOption extends StatelessWidget {
  const _SpeedOption({required this.speed, required this.selected});

  final double speed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return JuicrSheetOptionTile(
      padding: const EdgeInsets.only(top: 8),
      label: speed == 1 ? '1x (Normal)' : _speedLabel(speed),
      selected: selected,
      onTap: () => Navigator.of(context).pop(speed),
    );
  }
}

class _FitModeSheet extends StatelessWidget {
  const _FitModeSheet({required this.activeMode});

  final VideoFitMode activeMode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: _playerSheetConstraints(context),
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: JuicrVisual.bottomSheetFloatingBorderRadius,
              boxShadow: JuicrVisual.softShadow(
                colorScheme,
                alpha: 0.16,
                blur: 24,
                y: 10,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Video size',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final mode in VideoFitMode.values)
                    _FitModeOption(mode: mode, selected: mode == activeMode),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FitModeOption extends StatelessWidget {
  const _FitModeOption({required this.mode, required this.selected});

  final VideoFitMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return JuicrSheetOptionTile(
      padding: const EdgeInsets.only(top: 8),
      icon: Icons.aspect_ratio_rounded,
      label: mode.label,
      subtitle: mode.description,
      selected: selected,
      onTap: () => Navigator.of(context).pop(mode),
    );
  }
}

class _SubtitleOffSelection {
  const _SubtitleOffSelection();
}

class _SubtitleSheet extends StatefulWidget {
  const _SubtitleSheet({
    required this.subtitles,
    required this.activeSubtitle,
    required this.allowStyleControls,
    required this.fontSize,
    required this.backgroundOpacity,
    required this.backgroundColor,
    required this.backgroundRadius,
    required this.textColor,
    required this.bottomOffset,
    required this.delaySeconds,
    required this.defaultDelaySeconds,
    required this.onDelayChanged,
    required this.onDelayResetToDefault,
    required this.onFontSizeChanged,
    required this.onBackgroundOpacityChanged,
    required this.onBackgroundColorChanged,
    required this.onBackgroundRadiusChanged,
    required this.onTextColorChanged,
    required this.onBottomOffsetChanged,
  });

  final List<PlaybackSubtitle> subtitles;
  final PlaybackSubtitle? activeSubtitle;
  final bool allowStyleControls;
  final double fontSize;
  final double backgroundOpacity;
  final Color backgroundColor;
  final double backgroundRadius;
  final Color textColor;
  final double bottomOffset;
  final double delaySeconds;
  final double defaultDelaySeconds;
  final ValueChanged<double> onDelayChanged;
  final VoidCallback onDelayResetToDefault;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<double> onBackgroundOpacityChanged;
  final ValueChanged<Color> onBackgroundColorChanged;
  final ValueChanged<double> onBackgroundRadiusChanged;
  final ValueChanged<Color> onTextColorChanged;
  final ValueChanged<double> onBottomOffsetChanged;

  @override
  State<_SubtitleSheet> createState() => _SubtitleSheetState();
}

class _SubtitleSheetState extends State<_SubtitleSheet> {
  late double _fontSize;
  late double _backgroundOpacity;
  late Color _backgroundColor;
  late double _backgroundRadius;
  late Color _textColor;
  late double _bottomOffset;
  late double _delaySeconds;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.fontSize;
    _backgroundOpacity = widget.backgroundOpacity;
    _backgroundColor = widget.backgroundColor;
    _backgroundRadius = widget.backgroundRadius;
    _textColor = widget.textColor;
    _bottomOffset = widget.bottomOffset;
    _delaySeconds = widget.delaySeconds;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: _playerSheetConstraints(
            context,
            maxPortrait: 0.78,
            maxLandscape: 0.84,
          ),
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: JuicrVisual.bottomSheetFloatingBorderRadius,
              boxShadow: JuicrVisual.softShadow(
                colorScheme,
                alpha: 0.16,
                blur: 24,
                y: 10,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Subtitles',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Subtitle sync',
                        child: ExcludeSemantics(
                          child: IconButton(
                            tooltip: 'Subtitle sync',
                            onPressed: _showDelaySheet,
                            icon: const Icon(Icons.tune_rounded),
                            color: colorScheme.onSurface,
                            style: IconButton.styleFrom(
                              backgroundColor: colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ),
                      if (widget.allowStyleControls) ...[
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          label: 'Subtitle settings',
                          child: ExcludeSemantics(
                            child: IconButton(
                              tooltip: 'Subtitle settings',
                              onPressed: _showStyleSheet,
                              icon: const Icon(Icons.settings_rounded),
                              color: colorScheme.onSurface,
                              style: IconButton.styleFrom(
                                backgroundColor: colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  _SubtitleOption(
                    label: 'Off',
                    selected: widget.activeSubtitle == null,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(const _SubtitleOffSelection()),
                  ),
                  for (final subtitle in widget.subtitles)
                    _SubtitleOption(
                      label: subtitle.label,
                      selected: subtitle.id == widget.activeSubtitle?.id,
                      onTap: () => Navigator.of(context).pop(subtitle),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDelaySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: JuicrVisual.bottomSheetFloatingBorderRadius,
                boxShadow: JuicrVisual.softShadow(
                  colorScheme,
                  alpha: 0.16,
                  blur: 24,
                  y: 10,
                ),
              ),
              child: StatefulBuilder(
                builder: (context, setSheetState) {
                  final label = _subtitleDelayLabel(_delaySeconds);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: colorScheme.onSurface.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Subtitle sync',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                            ),
                          ),
                          Text(
                            label,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: _delaySeconds,
                        min: -10,
                        max: 10,
                        divisions: 40,
                        label: label,
                        onChanged: (value) {
                          final rounded = (value * 2).round() / 2;
                          setState(() => _delaySeconds = rounded);
                          setSheetState(() {});
                          widget.onDelayChanged(rounded);
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '-10s',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(
                                () =>
                                    _delaySeconds = widget.defaultDelaySeconds,
                              );
                              setSheetState(() {});
                              widget.onDelayResetToDefault();
                            },
                            child: const Text('Use default'),
                          ),
                          Text(
                            '+10s',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showStyleSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: JuicrVisual.bottomSheetFloatingBorderRadius,
                boxShadow: JuicrVisual.softShadow(
                  colorScheme,
                  alpha: 0.16,
                  blur: 24,
                  y: 10,
                ),
              ),
              child: StatefulBuilder(
                builder: (context, setSheetState) {
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.28,
                            ),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Subtitle settings',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _SubtitlePreview(
                          text: 'Subtitle preview\nTwo-line cues stay stacked.',
                          fontSize: _fontSize,
                          backgroundOpacity: _backgroundOpacity,
                          backgroundColor: _backgroundColor,
                          backgroundRadius: _backgroundRadius,
                          textColor: _textColor,
                        ),
                        const SizedBox(height: 10),
                        _SubtitleSlider(
                          label: 'Text size',
                          value: _fontSize,
                          min: 13,
                          max: 24,
                          divisions: 11,
                          valueLabel: '${_fontSize.round()}',
                          onChanged: (value) {
                            setState(() => _fontSize = value);
                            setSheetState(() {});
                            widget.onFontSizeChanged(value);
                          },
                        ),
                        const SizedBox(height: 6),
                        _SubtitleSlider(
                          label: 'Position',
                          value: _bottomOffset,
                          min: 18,
                          max: 96,
                          divisions: 26,
                          valueLabel: _subtitlePositionLabel(_bottomOffset),
                          onChanged: (value) {
                            final rounded = value.roundToDouble();
                            setState(() => _bottomOffset = rounded);
                            setSheetState(() {});
                            widget.onBottomOffsetChanged(rounded);
                          },
                        ),
                        const SizedBox(height: 6),
                        _SubtitleSlider(
                          label: 'Roundness',
                          value: _backgroundRadius >= 999
                              ? 32
                              : _backgroundRadius,
                          min: 0,
                          max: 32,
                          divisions: 8,
                          valueLabel: _backgroundRadius >= 999
                              ? 'Full'
                              : _backgroundRadius.round().toString(),
                          onChanged: (value) {
                            final radius = value >= 32 ? 999.0 : value;
                            setState(() => _backgroundRadius = radius);
                            setSheetState(() {});
                            widget.onBackgroundRadiusChanged(radius);
                          },
                        ),
                        const SizedBox(height: 6),
                        _SubtitleColorPicker(
                          title: 'Background',
                          selectedColor: _backgroundOpacity <= 0
                              ? Colors.transparent
                              : _backgroundColor,
                          colors: const [
                            Colors.transparent,
                            Colors.black,
                            Color(0xFF2B2933),
                            Color(0xFF281B54),
                          ],
                          onSelected: (color) {
                            final opacity = color == Colors.transparent
                                ? 0.0
                                : color.opacity < 1
                                ? color.opacity
                                : 0.74;
                            setState(() {
                              _backgroundColor = color == Colors.transparent
                                  ? Colors.black
                                  : color.withAlpha(255);
                              _backgroundOpacity = opacity;
                            });
                            setSheetState(() {});
                            widget.onBackgroundColorChanged(_backgroundColor);
                            widget.onBackgroundOpacityChanged(opacity);
                          },
                        ),
                        const SizedBox(height: 8),
                        _SubtitleColorPicker(
                          title: 'Text color',
                          selectedColor: _textColor,
                          colors: const [
                            Colors.white,
                            Color(0xFFFFF2A6),
                            Color(0xFF9EE7FF),
                            Color(0xFF111111),
                          ],
                          onSelected: (color) {
                            setState(() => _textColor = color);
                            setSheetState(() {});
                            widget.onTextColorChanged(color);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SubtitleColorPicker extends StatelessWidget {
  const _SubtitleColorPicker({
    required this.title,
    required this.selectedColor,
    required this.colors,
    required this.onSelected,
  });

  final String title;
  final Color selectedColor;
  final List<Color> colors;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            title,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in colors)
                _SubtitleColorDot(
                  color: color,
                  selected: color.value == selectedColor.value,
                  semanticLabel: '$title preset color',
                  onTap: () => onSelected(color),
                ),
              _SubtitleCustomColorDot(
                selectedColor: selectedColor,
                selected: !colors.any(
                  (color) => color.value == selectedColor.value,
                ),
                semanticLabel: 'Custom $title color',
                onTap: () async {
                  final selected = await showDialog<Color>(
                    context: context,
                    builder: (context) => _SubtitleColorDialog(
                      title: title,
                      initialColor: selectedColor,
                    ),
                  );
                  if (selected != null) onSelected(selected);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubtitlePreview extends StatelessWidget {
  const _SubtitlePreview({
    required this.text,
    required this.fontSize,
    required this.backgroundOpacity,
    required this.backgroundColor,
    required this.backgroundRadius,
    required this.textColor,
  });

  final String text;
  final double fontSize;
  final double backgroundOpacity;
  final Color backgroundColor;
  final double backgroundRadius;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor.withValues(alpha: backgroundOpacity),
          borderRadius: BorderRadius.circular(backgroundRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtitleSlider extends StatelessWidget {
  const _SubtitleSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _SubtitleColorDot extends StatelessWidget {
  const _SubtitleColorDot({
    required this.color,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 30,
            height: 30,
            decoration: JuicrVisual.elevatedCircleDecoration(
              colorScheme,
              color: color,
              shadowAlpha: selected ? 0.18 : 0.08,
              glowAlpha: selected ? 0.16 : 0.04,
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtitleCustomColorDot extends StatelessWidget {
  const _SubtitleCustomColorDot({
    required this.selectedColor,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final Color selectedColor;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(
                    alpha: selected ? 0.14 : 0.07,
                  ),
                  blurRadius: selected ? 12 : 8,
                  offset: Offset(0, selected ? 5 : 3),
                ),
              ],
            ),
            child: Center(
              child: _SubtitleRgbCustomColorMark(
                previewColor: selected ? selectedColor : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtitleRgbCustomColorMark extends StatelessWidget {
  const _SubtitleRgbCustomColorMark({this.previewColor});

  final Color? previewColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 19,
      height: 19,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFFFF4D8D),
            Color(0xFFFFD166),
            Color(0xFF32D583),
            Color(0xFF38BDF8),
            Color(0xFF8B5CF6),
            Color(0xFFFF4D8D),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 12.5,
          height: 12.5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: previewColor ?? Colors.white.withValues(alpha: 0.36),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.86),
              width: 1.15,
            ),
          ),
          child: previewColor == null
              ? const Icon(
                  Icons.palette_outlined,
                  size: 7.8,
                  color: Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

class _SubtitleColorDialog extends StatefulWidget {
  const _SubtitleColorDialog({required this.title, required this.initialColor});

  final String title;
  final Color initialColor;

  @override
  State<_SubtitleColorDialog> createState() => _SubtitleColorDialogState();
}

class _SubtitleColorDialogState extends State<_SubtitleColorDialog> {
  late HSVColor _hsv;
  late double _opacity;
  late final TextEditingController _hexController;

  static const List<double> _saturationStops = [1, 0.82, 0.64, 0.46, 0.28, 0.1];
  static const List<double> _valueStops = [0.95, 0.78, 0.62, 0.46, 0.3];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialColor == Colors.transparent
        ? Colors.white
        : widget.initialColor;
    _hsv = HSVColor.fromColor(initial.withAlpha(255));
    _opacity = 1.0;
    _hexController = TextEditingController(text: _hexFor(_color));
  }

  Color get _color => _hsv.toColor().withValues(alpha: 1.0);

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor value, {double? opacity}) {
    setState(() {
      _hsv = value;
      if (opacity != null) _opacity = 1.0;
      _hexController.text = _hexFor(_color);
    });
  }

  void _applyHex(String value) {
    final parsed = _colorFromHex(value);
    if (parsed == null) return;
    setState(() {
      _hsv = HSVColor.fromColor(parsed.withAlpha(255));
      _opacity = 1.0;
      _hexController.text = _hexFor(_color);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 86,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(14),
                boxShadow: JuicrVisual.softShadow(
                  colorScheme,
                  alpha: 0.1,
                  blur: 14,
                  y: 5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Slider(
              value: _hsv.hue,
              min: 0,
              max: 360,
              divisions: 72,
              label: '${_hsv.hue.round()}',
              onChanged: (value) => _setHsv(_hsv.withHue(value)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final saturation in _saturationStops)
                  for (final value in _valueStops)
                    _SubtitleDialogSwatch(
                      color: _hsv
                          .withSaturation(saturation)
                          .withValue(value)
                          .toColor(),
                      selected: _closeColor(
                        _hsv
                            .withSaturation(saturation)
                            .withValue(value)
                            .toColor(),
                        _hsv.toColor(),
                      ),
                      onTap: () => _setHsv(
                        _hsv.withSaturation(saturation).withValue(value),
                      ),
                    ),
                for (final color in const [
                  Colors.white,
                  Color(0xFFDDDDDD),
                  Color(0xFF999999),
                  Color(0xFF555555),
                  Colors.black,
                ])
                  _SubtitleDialogSwatch(
                    color: color,
                    selected: _closeColor(color, _hsv.toColor()),
                    onTap: () => _setHsv(HSVColor.fromColor(color)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hexController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Hex (RRGGBB)',
                prefixText: '#',
              ),
              onSubmitted: _applyHex,
              onEditingComplete: () => _applyHex(_hexController.text),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  bool _closeColor(Color a, Color b) {
    return (a.red - b.red).abs() < 4 &&
        (a.green - b.green).abs() < 4 &&
        (a.blue - b.blue).abs() < 4;
  }

  String _hexFor(Color color) {
    return (color.value & 0x00FFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
  }

  Color? _colorFromHex(String value) {
    final cleaned = value.replaceAll('#', '').trim();
    if (!RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(cleaned)) {
      return null;
    }
    final hex = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
    final parsed = Color(int.parse(hex, radix: 16));
    return Color(0xFF000000 | (parsed.value & 0x00FFFFFF));
  }
}

class _SubtitleDialogSwatch extends StatelessWidget {
  const _SubtitleDialogSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Choose subtitle custom color swatch',
      child: ExcludeSemantics(
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 26,
            height: 26,
            decoration: JuicrVisual.elevatedCircleDecoration(
              colorScheme,
              color: color,
              shadowAlpha: selected ? 0.18 : 0.08,
              glowAlpha: selected ? 0.16 : 0.04,
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtitleOption extends StatelessWidget {
  const _SubtitleOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return JuicrSheetOptionTile(
      padding: const EdgeInsets.only(top: 8),
      label: label,
      selected: selected,
      onTap: onTap,
    );
  }
}

class _SubtitleOverlay extends StatelessWidget {
  const _SubtitleOverlay({
    required this.text,
    required this.fontSize,
    required this.backgroundOpacity,
    required this.backgroundColor,
    required this.backgroundRadius,
    required this.textColor,
    required this.bottomOffset,
    required this.compactMode,
  });

  final String text;
  final double fontSize;
  final double backgroundOpacity;
  final Color backgroundColor;
  final double backgroundRadius;
  final Color textColor;
  final double bottomOffset;
  final bool compactMode;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compactFontSize = math.min(
      fontSize,
      (size.shortestSide * 0.055).clamp(8.0, 12.0).toDouble(),
    );
    final effectiveFontSize = compactMode ? compactFontSize : fontSize;
    final horizontalPadding = compactMode ? 10.0 : 42.0;
    final verticalPadding = compactMode ? 4.0 : 8.0;
    final textHorizontalPadding = compactMode ? 8.0 : 16.0;
    final effectiveBottomOffset = compactMode
        ? math.min(bottomOffset, 42).toDouble()
        : bottomOffset;
    final availableTextWidth = math.max(
      24.0,
      size.width - (horizontalPadding * 2),
    );
    final maxWidth = compactMode ? availableTextWidth : 640.0;
    final overlay = Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          effectiveBottomOffset,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor.withValues(alpha: backgroundOpacity),
              borderRadius: BorderRadius.circular(backgroundRadius),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: textHorizontalPadding,
                vertical: verticalPadding,
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                softWrap: true,
                maxLines: compactMode ? 2 : null,
                overflow: compactMode ? TextOverflow.ellipsis : null,
                style: TextStyle(
                  color: textColor,
                  fontSize: effectiveFontSize,
                  fontWeight: FontWeight.w800,
                  height: compactMode ? 1.08 : 1.25,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return compactMode ? overlay : SafeArea(child: overlay);
  }
}

class _NativePlayerLoading extends StatefulWidget {
  const _NativePlayerLoading({
    required this.title,
    required this.onBack,
    this.logoUrl,
    this.backgroundUrl,
    this.backdropStyle = 'scan',
    this.message,
    this.onUseWebPlayer,
    this.onRetry,
    this.onChooseSource,
  });

  final String title;
  final VoidCallback onBack;
  final String? logoUrl;
  final String? backgroundUrl;
  final String backdropStyle;
  final String? message;
  final VoidCallback? onUseWebPlayer;
  final VoidCallback? onRetry;
  final VoidCallback? onChooseSource;

  @override
  State<_NativePlayerLoading> createState() => _NativePlayerLoadingState();
}

class _NativePlayerLoadingState extends State<_NativePlayerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = widget.title.trim().isEmpty ? 'Loading player' : widget.title;
    final message = widget.message?.trim();
    final hasMessage = message != null && message.isNotEmpty;
    final hasActions = widget.onRetry != null || widget.onChooseSource != null;
    final actionCount =
        (widget.onRetry != null ? 1 : 0) +
        (widget.onChooseSource != null ? 1 : 0);
    final contentKey = '${message ?? 'no-message'}|$hasActions|$actionCount';
    final maxMessageWidth = (MediaQuery.sizeOf(context).width - 48).clamp(
      240.0,
      680.0,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(color: Colors.black)),
        _LoadingBackdrop(
          controller: _controller,
          style: widget.backdropStyle,
          backgroundUrl: widget.backgroundUrl,
          logoUrl: widget.logoUrl,
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _PlayerRoundButton(
                icon: Icons.arrow_back_rounded,
                semanticLabel: 'Close player',
                onPressed: widget.onBack,
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 42),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSlide(
                  offset: hasMessage ? const Offset(0, -0.055) : Offset.zero,
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedScale(
                    scale: hasMessage ? 0.965 : 1,
                    duration: const Duration(milliseconds: 620),
                    curve: Curves.easeInOutCubic,
                    child: _LoadingTitleWheel(
                      controller: _controller,
                      title: title,
                      logoUrl: widget.logoUrl,
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 720),
                  reverseDuration: const Duration(milliseconds: 420),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInOutCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.16),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: hasMessage || hasActions
                      ? Padding(
                          key: ValueKey<String>(contentKey),
                          padding: const EdgeInsets.only(top: 16),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: maxMessageWidth,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (hasMessage)
                                  _AnimatedLoadingText(
                                    label: message!,
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.labelLarge?.copyWith(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w800,
                                      height: 1.32,
                                    ),
                                  ),
                                if (hasActions)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: hasMessage ? 14 : 0,
                                    ),
                                    child: actionCount == 1
                                        ? Center(
                                            child: widget.onChooseSource != null
                                                ? _LoadingActionChip(
                                                    icon: Icons.dns_rounded,
                                                    label: 'Sources',
                                                    onPressed:
                                                        widget.onChooseSource!,
                                                  )
                                                : _LoadingActionChip(
                                                    icon: Icons.refresh_rounded,
                                                    label: 'Retry',
                                                    onPressed: widget.onRetry!,
                                                  ),
                                          )
                                        : Wrap(
                                            alignment: WrapAlignment.center,
                                            runAlignment: WrapAlignment.center,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: [
                                              if (widget.onChooseSource != null)
                                                _LoadingActionChip(
                                                  icon: Icons.dns_rounded,
                                                  label: 'Sources',
                                                  onPressed:
                                                      widget.onChooseSource!,
                                                ),
                                              if (widget.onRetry != null)
                                                _LoadingActionChip(
                                                  icon: Icons.refresh_rounded,
                                                  label: 'Retry',
                                                  onPressed: widget.onRetry!,
                                                ),
                                            ],
                                          ),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey<String>('no-loading-content'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingBackdrop extends StatelessWidget {
  const _LoadingBackdrop({
    required this.controller,
    required this.style,
    this.backgroundUrl,
    this.logoUrl,
  });

  final Animation<double> controller;
  final String style;
  final String? backgroundUrl;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return switch (style) {
      'none' => const SizedBox.shrink(),
      'artworkBlur' => _LoadingArtworkBlur(
        backgroundUrl: backgroundUrl,
        logoUrl: logoUrl,
      ),
      _ => _LoadingScanBackground(controller: controller),
    };
  }
}

class _LoadingArtworkBlur extends StatelessWidget {
  const _LoadingArtworkBlur({this.backgroundUrl, this.logoUrl});

  final String? backgroundUrl;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final imageUrl = _loadingArtworkUrl(backgroundUrl, logoUrl);
    if (imageUrl == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Transform.scale(
              scale: 1.04,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.48),
                  Colors.black.withValues(alpha: 0.68),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String? _loadingArtworkUrl(String? backgroundUrl, String? logoUrl) {
  final background = backgroundUrl?.trim();
  if (background != null &&
      (background.startsWith('https://') || background.startsWith('http://'))) {
    return background;
  }
  final logo = logoUrl?.trim();
  if (logo != null &&
      (logo.startsWith('https://') || logo.startsWith('http://'))) {
    return logo;
  }
  return null;
}

class _LoadingScanBackground extends StatelessWidget {
  const _LoadingScanBackground({required this.controller});

  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    final accent = _playerAccent(context);
    if (juicrMotionDisabled(context)) {
      return IgnorePointer(
        child: CustomPaint(
          painter: _LoadingScanPainter(
            progress: 0.5,
            accent: accent,
            staticMode: true,
          ),
        ),
      );
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _LoadingScanPainter(
              progress: controller.value,
              accent: accent,
            ),
          );
        },
      ),
    );
  }
}

class _LoadingScanPainter extends CustomPainter {
  const _LoadingScanPainter({
    required this.progress,
    required this.accent,
    this.staticMode = false,
  });

  final double progress;
  final Color accent;
  final bool staticMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width * 0.5, size.height * 0.47);
    final shortest = math.min(size.width, size.height);
    final outerRadius = math
        .min(size.width * 0.30, shortest * 0.46)
        .clamp(128.0, 320.0)
        .toDouble();
    final innerRadius = outerRadius * 0.125;
    final scanRotation = staticMode ? -0.16 : progress * math.pi * 2;
    final softAccent = Color.lerp(accent, Colors.white, 0.18) ?? accent;

    final discRect = Rect.fromCircle(center: center, radius: outerRadius);
    final discPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.018),
          Colors.black.withValues(alpha: 0.24),
          accent.withValues(alpha: staticMode ? 0.030 : 0.045),
          Colors.black.withValues(alpha: 0.36),
          Colors.transparent,
        ],
        stops: const [0, 0.24, 0.58, 0.78, 1],
      ).createShader(discRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(center, outerRadius, discPaint);

    final grooveBase = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65;
    for (var i = 0; i < 16; i += 1) {
      final ringRadius = outerRadius * (0.18 + i * 0.047);
      if (ringRadius >= outerRadius * 0.96) break;
      final wave = math.sin((progress * math.pi * 2) + i * 0.7);
      grooveBase.color = Colors.white.withValues(
        alpha: staticMode ? 0.018 : 0.022 + (wave + 1) * 0.004,
      );
      canvas.drawCircle(center, ringRadius, grooveBase);
    }

    final shadowGroove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.black.withValues(alpha: 0.18);
    for (var i = 0; i < 7; i += 1) {
      canvas.drawCircle(center, outerRadius * (0.28 + i * 0.085), shadowGroove);
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(scanRotation);
    final sweepRect = Rect.fromCircle(center: Offset.zero, radius: outerRadius);
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          accent.withValues(alpha: staticMode ? 0.035 : 0.085),
          softAccent.withValues(alpha: staticMode ? 0.05 : 0.12),
          accent.withValues(alpha: staticMode ? 0.00 : 0.018),
          Colors.transparent,
        ],
        stops: const [0.00, 0.035, 0.055, 0.09, 0.16],
      ).createShader(sweepRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(Offset.zero, outerRadius * 0.94, sweepPaint);
    canvas.restore();

    final centerPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              accent.withValues(alpha: staticMode ? 0.12 : 0.20),
              Colors.black.withValues(alpha: 0.44),
              Colors.transparent,
            ],
            stops: const [0, 0.46, 1],
          ).createShader(
            Rect.fromCircle(center: center, radius: innerRadius * 2.8),
          );
    canvas.drawCircle(center, innerRadius * 2.8, centerPaint);
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()..color = Colors.black.withValues(alpha: 0.48),
    );
  }

  @override
  bool shouldRepaint(covariant _LoadingScanPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.staticMode != staticMode;
  }
}

class _LoadingActionChip extends StatelessWidget {
  const _LoadingActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      shape: const StadiumBorder(),
      shadowColor: Colors.black.withValues(alpha: 0.28),
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedLoadingText extends StatefulWidget {
  const _AnimatedLoadingText({
    required this.label,
    required this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String label;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<_AnimatedLoadingText> createState() => _AnimatedLoadingTextState();
}

class _AnimatedLoadingTextState extends State<_AnimatedLoadingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _hasAnimatedDots => widget.label.contains('...');

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (_hasAnimatedDots) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedLoadingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasAnimatedDots && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_hasAnimatedDots && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _animatedLabel() {
    if (!_hasAnimatedDots) return widget.label;
    final markerIndex = widget.label.indexOf('...');
    if (markerIndex < 0) return widget.label;
    final prefix = widget.label.substring(0, markerIndex);
    final suffix = widget.label.substring(markerIndex + 3);
    final startsWithDot = prefix.endsWith('.');
    final phaseCount = startsWithDot ? 3 : 4;
    final phase = (_controller.value * phaseCount).floor().clamp(
      0,
      phaseCount - 1,
    );
    final dotCount = startsWithDot ? phase + 1 : phase;
    final dots = '.' * dotCount;
    return '$prefix$dots$suffix';
  }

  @override
  Widget build(BuildContext context) {
    Widget text(String label) {
      return Text(
        label,
        textAlign: widget.textAlign,
        softWrap: true,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        style: widget.style,
      );
    }

    if (!_hasAnimatedDots) return text(widget.label);
    return Semantics(
      label: widget.label.replaceAll('\n', ' '),
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => text(_animatedLabel()),
        ),
      ),
    );
  }
}

class _NativeRefreshOverlay extends StatelessWidget {
  const _NativeRefreshOverlay({
    required this.message,
    required this.onBack,
    this.onUseWebPlayer,
  });

  final String message;
  final VoidCallback onBack;
  final VoidCallback? onUseWebPlayer;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.72,
              colors: [
                Colors.black.withValues(alpha: 0.16),
                Colors.black.withValues(alpha: 0.62),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _PlayerRoundButton(
                icon: Icons.arrow_back_rounded,
                semanticLabel: 'Close player',
                onPressed: onBack,
              ),
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_NativePlaybackStatusOverlay(label: message)],
          ),
        ),
      ],
    );
  }
}

class _NativePlaybackStatusOverlay extends StatelessWidget {
  const _NativePlaybackStatusOverlay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xB8000000),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: _playerAccentOverlay(context, 0.06),
                blurRadius: 8,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(width: 10),
                _AnimatedLoadingText(
                  label: label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineBufferingBadge extends StatelessWidget {
  const _InlineBufferingBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Buffering',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingTitleWheel extends StatelessWidget {
  const _LoadingTitleWheel({
    required this.controller,
    required this.title,
    this.logoUrl,
  });

  final Animation<double> controller;
  final String title;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style =
        textTheme.displayMedium?.copyWith(
          color: Colors.white,
          fontSize: 68,
          fontWeight: FontWeight.w900,
          height: 0.82,
          letterSpacing: -1.6,
        ) ??
        const TextStyle(
          color: Colors.white,
          fontSize: 68,
          fontWeight: FontWeight.w900,
          height: 0.82,
          letterSpacing: -1.6,
        );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = controller.value;
        final pulse = 0.985 + (math.sin(progress * math.pi * 2) + 1) * 0.006;
        final shimmerStart = -1.2 + progress * 2.4;

        final logo = logoUrl?.trim();
        return Transform.scale(
          scale: pulse,
          child: logo != null && logo.isNotEmpty
              ? ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 380,
                    maxHeight: 160,
                  ),
                  child: Image.network(
                    logo,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _LoadingFallbackTitle(
                      title: title,
                      style: style,
                      shimmerStart: shimmerStart,
                    ),
                  ),
                )
              : _LoadingFallbackTitle(
                  title: title,
                  style: style,
                  shimmerStart: shimmerStart,
                ),
        );
      },
    );
  }
}

class _LoadingFallbackTitle extends StatelessWidget {
  const _LoadingFallbackTitle({
    required this.title,
    required this.style,
    required this.shimmerStart,
  });

  final String title;
  final TextStyle style;
  final double shimmerStart;

  @override
  Widget build(BuildContext context) {
    final accent = _playerAccent(context);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment(shimmerStart, -0.4),
          end: Alignment(shimmerStart + 0.9, 0.4),
          colors: [
            const Color(0x99FFFFFF),
            Colors.white,
            accent,
            Colors.white,
            const Color(0x99FFFFFF),
          ],
          stops: const [0, 0.36, 0.5, 0.64, 1],
        ).createShader(bounds);
      },
      child: Text(
        title.toUpperCase(),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _MainPlayButton extends StatelessWidget {
  const _MainPlayButton({
    required this.playing,
    required this.enabled,
    required this.onPressed,
  });

  final bool playing;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = _playerAccent(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: playing ? 'Pause playback' : 'Play playback',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: IconButton(
            tooltip: playing ? 'Pause playback' : 'Play playback',
            onPressed: enabled ? onPressed : null,
            iconSize: 50,
            color: Colors.white,
            disabledColor: Colors.white38,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(76),
              shape: const CircleBorder(),
            ),
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
        ),
      ),
    );
  }
}

class _SeekButton extends StatefulWidget {
  const _SeekButton({
    required this.forward,
    required this.seconds,
    required this.onPressed,
  });

  final bool forward;
  final int seconds;
  final VoidCallback onPressed;

  @override
  State<_SeekButton> createState() => _SeekButtonState();
}

class _SeekButtonState extends State<_SeekButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;
  late final Animation<double> _turns;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    final direction = widget.forward ? 1.0 : -1.0;
    _turns = CurvedAnimation(
      parent: _spinController,
      curve: Curves.easeOutCubic,
    ).drive(Tween<double>(begin: 0, end: direction));
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _handlePressed() {
    if (!juicrMotionDisabled(context)) {
      _spinController.forward(from: 0);
    }
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.forward
        ? 'Skip forward ${widget.seconds} seconds'
        : 'Skip back ${widget.seconds} seconds';
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 76,
          child: IconButton(
            tooltip: label,
            onPressed: _handlePressed,
            iconSize: 42,
            color: Colors.white,
            style: IconButton.styleFrom(
              backgroundColor: Colors.black45,
              shape: const CircleBorder(),
            ),
            icon: Stack(
              alignment: Alignment.center,
              children: [
                RotationTransition(
                  turns: _turns,
                  child: Icon(
                    widget.forward
                        ? Icons.rotate_right_rounded
                        : Icons.rotate_left_rounded,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    top: 2,
                    left: widget.forward ? 2 : 0,
                    right: widget.forward ? 0 : 2,
                  ),
                  child: Text(
                    '${widget.seconds}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerRoundButton extends StatelessWidget {
  const _PlayerRoundButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 44,
    this.enabled = true,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;
  final double size;
  final bool enabled;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Material(
            color: active ? _playerAccent(context) : Colors.black54,
            elevation: active ? 3 : 1,
            shadowColor: Colors.black.withValues(alpha: 0.42),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onPressed : null,
              child: Center(
                child: Icon(
                  icon,
                  size: size <= 36 ? 19 : 24,
                  color: enabled ? Colors.white : Colors.white38,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GestureOverlay extends StatelessWidget {
  const _GestureOverlay({required this.icon, required this.label});

  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, 0.42),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xB8000000),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.tune_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _SubtitleCue {
  const _SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;
}

List<_SubtitleCue> _parseWebVtt(String input) {
  final normalized = input
      .replaceAll('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  final directCues = _parseSubtitleBlocks(normalized.split('\n\n'));
  if (directCues.isNotEmpty) return directCues;

  final compactBlocks =
      RegExp(
            r'((?:\d+\s*\n)?\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->\s*\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}[\s\S]*?)(?=\n\s*\d+\s*\n\s*\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->|\z)',
          )
          .allMatches(normalized)
          .map((match) => match.group(1) ?? '')
          .where((block) => block.trim().isNotEmpty)
          .toList();
  return _parseSubtitleBlocks(compactBlocks);
}

List<_SubtitleCue> _parseSubtitleBlocks(List<String> blocks) {
  final cues = <_SubtitleCue>[];

  for (final block in blocks) {
    final lines = block
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.isNotEmpty &&
              !line.startsWith('WEBVTT') &&
              !line.startsWith('NOTE'),
        )
        .toList();
    if (lines.isEmpty) continue;

    final timingIndex = lines.indexWhere((line) => line.contains('-->'));
    if (timingIndex < 0) continue;

    final parts = lines[timingIndex].split('-->');
    if (parts.length < 2) continue;

    final start = _parseSubtitleTime(parts[0]);
    final end = _parseSubtitleTime(parts[1].trim().split(RegExp(r'\s+')).first);
    if (start == null || end == null || end <= start) continue;

    final text = lines
        .skip(timingIndex + 1)
        .join('\n')
        .replaceAll(RegExp(r'\{\\[^}]+\}'), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
    if (text.isEmpty) continue;

    cues.add(_SubtitleCue(start: start, end: end, text: text));
  }

  return cues;
}

Duration? _parseSubtitleTime(String raw) {
  final clean = raw.trim().replaceAll(',', '.');
  final parts = clean.split(':');
  if (parts.length < 2 || parts.length > 3) return null;

  final secondsPart = parts.last.split('.');
  final seconds = int.tryParse(secondsPart.first);
  final millis = secondsPart.length > 1
      ? int.tryParse(secondsPart[1].padRight(3, '0').substring(0, 3)) ?? 0
      : 0;
  final minutes = int.tryParse(parts[parts.length - 2]);
  final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
  if (seconds == null || minutes == null || hours == null) return null;

  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}

bool _isTemporaryResolverBlock(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('rate limit') ||
      text.contains('temporarily blocked') ||
      text.contains('taking longer than usual') ||
      text.contains('too many requests');
}

class _ControlGradient extends StatelessWidget {
  const _ControlGradient({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final isTop = alignment == Alignment.topCenter;

    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.30),
                Colors.black.withValues(alpha: 0.06),
                Colors.transparent,
              ],
              stops: const [0, 0.46, 1],
            ),
          ),
        ),
      ),
    );
  }
}
