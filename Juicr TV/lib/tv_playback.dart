part of 'main.dart';

const MethodChannel _tvMedia3PlayerChannel = MethodChannel(
  'app.juicr.flutter/media3_player',
);

enum _TvPlaybackEngine { media3, textureExoplayer, libvlc }

class _TvPlaybackValue {
  const _TvPlaybackValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isEnded = false,
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.size = Size.zero,
    this.aspectRatio = 16 / 9,
    this.errorDescription = '',
  });

  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool isEnded;
  final Duration duration;
  final Duration position;
  final Size size;
  final double aspectRatio;
  final String errorDescription;

  static const empty = _TvPlaybackValue();
}

class _TvRelayStartupProof extends ChangeNotifier {
  var _streamedSegments = 0;
  var _streamedBytes = 0;
  var _duration = Duration.zero;

  int get streamedSegments => _streamedSegments;
  int get streamedBytes => _streamedBytes;
  Duration get duration => _duration;
  bool get hasMediaProof => _streamedBytes >= 512 * 1024;

  void updateDuration(Duration duration) {
    if (duration <= Duration.zero || duration == _duration) return;
    _duration = duration;
    notifyListeners();
  }

  void updateProgress(int streamedSegments) {
    if (streamedSegments <= _streamedSegments) return;
    _streamedSegments = streamedSegments;
    notifyListeners();
  }

  void updateBytes(int streamedBytes) {
    if (streamedBytes <= _streamedBytes) return;
    _streamedBytes = streamedBytes;
    notifyListeners();
  }
}

class _TvMedia3PlaybackController {
  _TvMedia3PlaybackController(this.session, {required this.subtitles});

  final _PlaybackSession session;
  final List<_TvSubtitle> subtitles;
  final Completer<void> _viewReady = Completer<void>();
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  Timer? _pollTimer;
  int? _viewId;
  bool _disposed = false;
  _TvPlaybackValue value = _TvPlaybackValue.empty;
  bool firstFrameRendered = false;
  String errorBucket = 'none';

  Map<String, Object?> get creationParams => <String, Object?>{
    'url': session.tvMediaUrl,
    'headers': session.httpHeaders,
    'type': session.sourceType,
    'sourceClass': 'direct',
    'liveMode': false,
    'subtitles': subtitles
        .map(
          (subtitle) => <String, Object?>{
            'url': subtitle.url,
            'language': subtitle.language,
            'label': subtitle.label,
            'format': subtitle.format,
          },
        )
        .toList(),
  };

  void attachView(int viewId) {
    if (_disposed) return;
    _viewId = viewId;
    if (!_viewReady.isCompleted) _viewReady.complete();
    _startPolling();
  }

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  Future<void> initialize({
    Duration timeout = const Duration(seconds: 22),
  }) async {
    await _viewReady.future.timeout(timeout);
    _startPolling();
    final deadline = DateTime.now().add(timeout);
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      await _syncState();
      if (value.errorDescription.isNotEmpty) {
        throw StateError(value.errorDescription);
      }
      if (value.isInitialized) return;
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
    throw TimeoutException('Media3 initialize timed out', timeout);
  }

  Future<void> play() => _invoke('play');
  Future<void> pause() => _invoke('pause');
  Future<void> seekTo(Duration position) => _invoke('seekTo', <String, Object?>{
    'positionMs': position.inMilliseconds,
  });
  Future<void> setPlaybackSpeed(double speed) =>
      _invoke('setPlaybackSpeed', <String, Object?>{'speed': speed});

  Future<void> _invoke(String method, [Map<String, Object?> args = const {}]) {
    final viewId = _viewId;
    if (viewId == null || _disposed) return Future<void>.value();
    return _tvMedia3PlayerChannel.invokeMethod<void>(method, <String, Object?>{
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
    final raw = await _tvMedia3PlayerChannel.invokeMapMethod<String, Object?>(
      'state',
      <String, Object?>{'viewId': viewId},
    );
    if (raw == null || _disposed) return;
    final hasError = raw['hasError'] == true;
    final width = (raw['width'] as num?)?.toDouble() ?? 0;
    final height = (raw['height'] as num?)?.toDouble() ?? 0;
    final size = width > 0 && height > 0 ? Size(width, height) : Size.zero;
    firstFrameRendered = raw['firstFrameRendered'] == true;
    errorBucket = (raw['errorBucket'] as String?) ?? 'none';
    value = _TvPlaybackValue(
      isInitialized: raw['initialized'] == true,
      isPlaying: raw['playing'] == true,
      isBuffering: raw['buffering'] == true,
      isEnded: raw['ended'] == true,
      duration: Duration(
        milliseconds: (raw['durationMs'] as num?)?.round() ?? 0,
      ),
      position: Duration(
        milliseconds: (raw['positionMs'] as num?)?.round() ?? 0,
      ),
      size: size,
      aspectRatio: size.width > 0 && size.height > 0
          ? size.width / size.height
          : 16 / 9,
      errorDescription: hasError
          ? ((raw['errorDescription'] as String?) ?? 'media3_error')
          : '',
    );
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _pollTimer?.cancel();
    _listeners.clear();
    final viewId = _viewId;
    if (viewId != null) {
      await _tvMedia3PlayerChannel.invokeMethod<void>(
        'dispose',
        <String, Object?>{'viewId': viewId},
      );
    }
  }
}

class _TvNativePlaybackController extends ChangeNotifier {
  _TvNativePlaybackController.media3(
    _PlaybackSession session, {
    required List<_TvSubtitle> subtitles,
    LibVlcHlsRelay? relay,
  }) : engine = _TvPlaybackEngine.media3,
       _video = null,
       _media3 = _TvMedia3PlaybackController(session, subtitles: subtitles),
       _vlc = null,
       _relay = relay,
       _relayProof = null {
    _media3!.addListener(notifyListeners);
  }

  _TvNativePlaybackController.textureExoplayer(
    _PlaybackSession session, {
    LibVlcHlsRelay? relay,
  }) : engine = _TvPlaybackEngine.textureExoplayer,
       _video = VideoPlayerController.networkUrl(
         Uri.parse(session.tvMediaUrl),
         formatHint: session.videoFormatHint,
         httpHeaders: session.httpHeaders,
         viewType: VideoViewType.textureView,
       ),
       _media3 = null,
       _vlc = null,
       _relay = relay,
       _relayProof = null {
    _video!.addListener(notifyListeners);
  }

  _TvNativePlaybackController.libvlc(
    _PlaybackSession session, {
    LibVlcHlsRelay? relay,
    _TvRelayStartupProof? relayProof,
  }) : engine = _TvPlaybackEngine.libvlc,
       _video = null,
       _media3 = null,
       _relay = relay,
       _relayProof = relayProof,
       _vlc = VlcPlayerController.network(
         session.tvMediaUrl,
         hwAcc: HwAcc.auto,
         autoInitialize: false,
         autoPlay: false,
         options: _tvVlcPlayerOptions(session.httpHeaders),
       ) {
    _vlc!.addListener(notifyListeners);
    _relayProof?.addListener(notifyListeners);
  }

  final _TvPlaybackEngine engine;
  final VideoPlayerController? _video;
  final _TvMedia3PlaybackController? _media3;
  final VlcPlayerController? _vlc;
  final LibVlcHlsRelay? _relay;
  final _TvRelayStartupProof? _relayProof;
  bool get hasStartupProof {
    final video = _video;
    if (video != null) {
      final current = value;
      return current.isInitialized &&
          current.isPlaying &&
          current.position >= const Duration(seconds: 1);
    }
    final media3 = _media3;
    if (media3 != null) {
      final current = media3.value;
      return media3.firstFrameRendered &&
          current.isInitialized &&
          current.isPlaying &&
          current.position >= const Duration(seconds: 1);
    }
    final current = value;
    return current.isInitialized &&
        (current.duration > Duration.zero ||
            current.size.width > 0 && current.size.height > 0 ||
            current.position >= const Duration(seconds: 1));
  }

  _TvPlaybackValue get value {
    final video = _video;
    if (video != null) {
      final raw = video.value;
      return _TvPlaybackValue(
        isInitialized: raw.isInitialized,
        isPlaying: raw.isPlaying,
        isBuffering: raw.isBuffering,
        isEnded: raw.isCompleted,
        duration: raw.duration,
        position: raw.position,
        size: raw.size,
        aspectRatio: raw.aspectRatio <= 0 ? 16 / 9 : raw.aspectRatio,
        errorDescription: raw.hasError ? raw.errorDescription ?? '' : '',
      );
    }
    final media3 = _media3;
    if (media3 != null) return media3.value;
    final raw = _vlc!.value;
    return _TvPlaybackValue(
      isInitialized: raw.isInitialized,
      isPlaying: raw.isPlaying,
      isBuffering: raw.isBuffering,
      isEnded: raw.isEnded,
      duration: raw.duration,
      position: raw.position,
      size: raw.size,
      aspectRatio: raw.aspectRatio <= 0 ? 16 / 9 : raw.aspectRatio,
      errorDescription: raw.hasError ? raw.errorDescription : '',
    );
  }

  Future<void> initialize({
    Duration timeout = const Duration(seconds: 22),
  }) async {
    final video = _video;
    if (video != null) return video.initialize().timeout(timeout);
    final media3 = _media3;
    if (media3 != null) return media3.initialize(timeout: timeout);
    final vlc = _vlc!;
    if (vlc.value.isInitialized) return Future<void>.value();
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_vlcViewAttached(vlc)) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!_vlcViewAttached(vlc)) {
      throw TimeoutException('libVLC view attach timed out', timeout);
    }
    final completer = Completer<void>();
    late VoidCallback listener;
    var listenerAttached = false;
    void detachListener() {
      if (!listenerAttached) return;
      listenerAttached = false;
      vlc.removeListener(listener);
    }

    listener = () {
      final value = vlc.value;
      if (value.hasError && !completer.isCompleted) {
        completer.completeError(value.errorDescription);
      } else if (value.isInitialized && !completer.isCompleted) {
        completer.complete();
      }
      if (completer.isCompleted) detachListener();
    };
    vlc.addListener(listener);
    listenerAttached = true;
    await vlc.initialize().catchError((Object error) {
      final message = error.toString().toLowerCase();
      if (message.contains('already initialized')) return;
      if (!completer.isCompleted) completer.completeError(error);
    });
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      detachListener();
      throw TimeoutException('libVLC initialize timed out', timeout);
    }
    return completer.future.timeout(
      remaining,
      onTimeout: () {
        detachListener();
        throw TimeoutException('libVLC initialize timed out', timeout);
      },
    );
  }

  Future<void> play() => _video?.play() ?? _media3?.play() ?? _vlc!.play();
  Future<void> pause() => _video?.pause() ?? _media3?.pause() ?? _vlc!.pause();
  Future<void> seekTo(Duration position) =>
      _video?.seekTo(position) ??
      _media3?.seekTo(position) ??
      _vlc!.seekTo(position);
  Future<void> setPlaybackSpeed(double speed) =>
      _video?.setPlaybackSpeed(speed) ??
      _media3?.setPlaybackSpeed(speed) ??
      _vlc!.setPlaybackSpeed(speed);

  bool _vlcViewAttached(VlcPlayerController vlc) {
    try {
      final dynamic controller = vlc;
      return controller.viewId is int;
    } catch (_) {
      return false;
    }
  }

  Widget surface({required double aspectRatio}) {
    final video = _video;
    if (video != null) {
      return IgnorePointer(child: VideoPlayer(video));
    }
    final media3 = _media3;
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
    return VlcPlayer(
      controller: _vlc!,
      aspectRatio: aspectRatio,
      placeholder: const ColoredBox(color: Colors.black),
      virtualDisplay: true,
    );
  }

  @override
  Future<void> dispose() async {
    _video?.removeListener(notifyListeners);
    _media3?.removeListener(notifyListeners);
    _vlc?.removeListener(notifyListeners);
    _relayProof?.removeListener(notifyListeners);
    await _video?.dispose();
    await _media3?.dispose();
    await _vlc?.dispose();
    await _relay?.stop();
    super.dispose();
  }
}

VlcPlayerOptions _tvVlcPlayerOptions(Map<String, String> headers) {
  final extras = <String>[
    ':network-caching=1800',
    ':http-reconnect',
    ':http-forward-cookies',
  ];
  final http = <String>[
    VlcHttpOptions.httpReconnect(true),
    VlcHttpOptions.httpForwardCookies(true),
  ];
  for (final entry in headers.entries) {
    final key = entry.key.trim().toLowerCase();
    final value = entry.value.trim();
    if (value.isEmpty) continue;
    if (key == 'user-agent') {
      http.add(VlcHttpOptions.httpUserAgent(value));
      extras.add(':http-user-agent=$value');
    } else if (key == 'referer' || key == 'referrer') {
      http.add(VlcHttpOptions.httpReferrer(value));
      extras.add(':http-referrer=$value');
    } else if (key == 'cookie') {
      extras.add(':http-cookie=$value');
    } else {
      extras.add(':http-header=${entry.key.trim()}: $value');
    }
  }
  return VlcPlayerOptions(
    advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(1800)]),
    http: VlcHttpOptions(http),
    extras: extras,
  );
}

class _TvPlaybackPage extends StatefulWidget {
  const _TvPlaybackPage({
    required this.item,
    required this.sessions,
    required this.initialSessionIndex,
    required this.initialSeason,
    required this.initialEpisode,
    required this.initialResumePosition,
    required this.settings,
    required this.subtitles,
    required this.initialSubtitleIndex,
  });

  final _TvItem item;
  final List<_PlaybackSession> sessions;
  final int initialSessionIndex;
  final int initialSeason;
  final int initialEpisode;
  final Duration initialResumePosition;
  final _TvSettingsState settings;
  final List<_TvSubtitle> subtitles;
  final int initialSubtitleIndex;

  @override
  State<_TvPlaybackPage> createState() => _TvPlaybackPageState();
}

class _TvPlaybackPageState extends State<_TvPlaybackPage> {
  static const Duration _seekStep = Duration(seconds: 15);
  static const Duration _fastSeekStep = Duration(seconds: 30);
  static const Duration _controlsAutoHideDelay = Duration(seconds: 4);

  final FocusNode _playbackFocusNode = FocusNode(debugLabel: 'tv-playback');
  final FocusNode _backFocusNode = FocusNode(debugLabel: 'tv-playback-back');
  final FocusNode _nextEpisodeFocusNode = FocusNode(
    debugLabel: 'tv-playback-next-episode',
  );
  final FocusNode _skipBackFocusNode = FocusNode(
    debugLabel: 'tv-playback-skip-back',
  );
  final FocusNode _playFocusNode = FocusNode(debugLabel: 'tv-playback-play');
  final FocusNode _skipForwardFocusNode = FocusNode(
    debugLabel: 'tv-playback-skip-forward',
  );
  final FocusNode _sourcesFocusNode = FocusNode(
    debugLabel: 'tv-playback-sources',
  );
  final FocusNode _settingsFocusNode = FocusNode(
    debugLabel: 'tv-playback-settings',
  );
  final FocusNode _lockFocusNode = FocusNode(debugLabel: 'tv-playback-lock');
  final FocusNode _progressFocusNode = FocusNode(
    debugLabel: 'tv-playback-progress',
  );
  final _api = _TvApi();
  _TvNativePlaybackController? _controller;
  late List<_PlaybackSession> _sessions;
  Timer? _hideControlsTimer;
  Timer? _feedbackTimer;
  bool _controlsVisible = true;
  bool _locked = false;
  bool _switchingSource = false;
  bool _closingPlayback = false;
  late bool _autoplayNextEpisode = widget.settings.nextEpisode;
  late bool _captionsEnabled;
  bool _autoNextQueued = false;
  double _playbackSpeed = 1.0;
  String _videoSize = 'Fit';
  int _season = 1;
  int _episode = 1;
  late int _sessionIndex;
  late int _subtitleIndex;
  _TvPlaybackFeedback? _feedback;
  TvRemoteDebugSnapshot _remoteDebugSnapshot = const TvRemoteDebugSnapshot(
    currentSurfaceName: 'playback',
  );

  @override
  void initState() {
    super.initState();
    _sessions = widget.sessions;
    _sessionIndex = widget.initialSessionIndex
        .clamp(0, _sessions.length - 1)
        .toInt();
    _season = widget.initialSeason;
    _episode = widget.initialEpisode;
    _subtitleIndex = widget.initialSubtitleIndex;
    _captionsEnabled =
        widget.settings.subtitles &&
        widget.settings.builtInSubtitles &&
        _subtitleIndex >= 0 &&
        _subtitleIndex < widget.subtitles.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showControls();
      _playFocusNode.requestFocus();
      unawaited(_openSession(_sessionIndex, feedbackLabel: 'Ready'));
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _feedbackTimer?.cancel();
    _playbackFocusNode.dispose();
    _backFocusNode.dispose();
    _nextEpisodeFocusNode.dispose();
    _skipBackFocusNode.dispose();
    _playFocusNode.dispose();
    _skipForwardFocusNode.dispose();
    _sourcesFocusNode.dispose();
    _settingsFocusNode.dispose();
    _lockFocusNode.dispose();
    _progressFocusNode.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    _showControls();
    if (mounted) setState(() {});
  }

  Future<void> _playOnly() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.play();
    _showControls();
    if (mounted) setState(() {});
  }

  Future<void> _pauseOnly() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.pause();
    _showControls();
    if (mounted) setState(() {});
  }

  Future<void> _seekBy(Duration offset) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    final target = value.position + offset;
    final duration = value.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && target > duration
        ? duration
        : target;
    await controller.seekTo(clamped);
    _showControls();
    if (mounted) setState(() {});
  }

  Future<void> _skipBy(Duration offset, {required int direction}) async {
    await _seekBy(offset);
  }

  Future<void> _fastSeekBy(Duration offset, {required int direction}) async {
    await _seekBy(offset);
    _showFeedback(
      direction < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
      '',
      seeking: true,
    );
  }

  void _showControls() {
    _hideControlsTimer?.cancel();
    setState(() => _controlsVisible = true);
    _hideControlsTimer = Timer(_controlsAutoHideDelay, () {
      if (!mounted || _locked) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _showFeedback(
    IconData icon,
    String label, {
    bool seeking = false,
    int skipDirection = 0,
  }) {
    _feedbackTimer?.cancel();
    setState(
      () => _feedback = _TvPlaybackFeedback(
        icon,
        label,
        seeking: seeking,
        skipDirection: skipDirection,
      ),
    );
    _feedbackTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      setState(() => _feedback = null);
    });
  }

  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      _controlsVisible = true;
    });
    _showFeedback(
      _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
      _locked ? 'Locked' : 'Unlocked',
    );
    if (!_locked) _showControls();
  }

  void _showPlayerToast(String message) {
    _showControls();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  _TvPlaybackProgress _currentProgress() {
    final value = _controller?.value ?? _TvPlaybackValue.empty;
    if (!value.isInitialized) {
      return const _TvPlaybackProgress(
        position: Duration.zero,
        duration: Duration.zero,
      );
    }
    return _TvPlaybackProgress(
      position: value.position,
      duration: value.duration,
    );
  }

  Future<void> _closePlayback() async {
    if (_closingPlayback) return;
    _closingPlayback = true;
    final progress = _currentProgress();
    final controller = _controller;
    if (controller != null) {
      setState(() => _controller = null);
      await controller.dispose();
    }
    if (!mounted) return;
    Navigator.of(context).pop(progress);
  }

  void _updateRemoteDebug(TvRemoteActionBucket? bucket) {
    final focusLabel = FocusManager.instance.primaryFocus?.debugLabel;
    _remoteDebugSnapshot = _remoteDebugSnapshot.copyWith(
      lastKeyBucket: bucket,
      currentSurfaceName: 'playback',
      currentFocusLabel: focusLabel == null || focusLabel.trim().isEmpty
          ? 'none'
          : focusLabel,
      controlsVisible: _controlsVisible,
      controlsLocked: _locked,
    );
  }

  List<_TvPlaybackEngine> _engineLadderFor(_PlaybackSession session) {
    if (_isNativeHlsSession(session)) {
      return const <_TvPlaybackEngine>[
        _TvPlaybackEngine.textureExoplayer,
        _TvPlaybackEngine.media3,
        _TvPlaybackEngine.libvlc,
      ];
    }
    return const <_TvPlaybackEngine>[
      _TvPlaybackEngine.media3,
      _TvPlaybackEngine.textureExoplayer,
      _TvPlaybackEngine.libvlc,
    ];
  }

  Future<_TvNativePlaybackController> _prepareNativeController(
    _PlaybackSession session,
    _TvPlaybackEngine engine,
  ) async {
    var controllerSession = session;
    LibVlcHlsRelay? relay;
    _TvRelayStartupProof? relayProof;
    final shouldRelay = _shouldRelaySession(session, engine);
    if (engine == _TvPlaybackEngine.libvlc) {
      debugPrint(
        'Juicr TV libVLC relay decision shouldRelay=$shouldRelay '
        'sourceType=${_safePlaybackTypeBucket(session.sourceType)} '
        'url=${_safePlaybackUrlBucket(session.tvMediaUrl)}',
      );
    }
    if (shouldRelay) {
      relayProof = _TvRelayStartupProof();
      final continuousTsMode = session.tvMediaUrl.toLowerCase().contains(
        '/web/playback/session/',
      );
      relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(session.tvMediaUrl),
        headers: session.httpHeaders,
        resumePosition: Duration.zero,
        continuousTsMode: continuousTsMode,
        onDuration: relayProof.updateDuration,
        onContinuousTsProgress: relayProof.updateProgress,
        onContinuousTsBytes: relayProof.updateBytes,
        onEvent: (message) => debugPrint('Juicr TV $message'),
      );
      controllerSession = session.copyWith(
        mediaUrl: relay.localUri.toString(),
        sourceType: continuousTsMode ? 'ts' : 'hls',
        httpHeaders: const <String, String>{},
      );
      debugPrint('Juicr TV native HLS relay started engine=${engine.name}');
    }
    final controller = switch (engine) {
      _TvPlaybackEngine.media3 => _TvNativePlaybackController.media3(
        controllerSession,
        subtitles: _captionsEnabled ? widget.subtitles : const <_TvSubtitle>[],
        relay: relay,
      ),
      _TvPlaybackEngine.textureExoplayer =>
        _TvNativePlaybackController.textureExoplayer(
          controllerSession,
          relay: relay,
        ),
      _TvPlaybackEngine.libvlc => _TvNativePlaybackController.libvlc(
        controllerSession,
        relay: relay,
        relayProof: relayProof,
      ),
    };
    setState(() => _controller = controller);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await controller.initialize().timeout(const Duration(seconds: 24));
      await controller.setPlaybackSpeed(_playbackSpeed);
      final shouldResumeInitialEpisode =
          _season == widget.initialSeason && _episode == widget.initialEpisode;
      if (shouldResumeInitialEpisode &&
          widget.initialResumePosition > Duration.zero &&
          widget.initialResumePosition < controller.value.duration) {
        await controller.seekTo(widget.initialResumePosition);
      }
      await controller.play();
      await _verifyStartupProof(controller, engine);
      debugPrint('Juicr TV native playback ready engine=${engine.name}');
      return controller;
    } catch (error) {
      debugPrint(
        'Juicr TV native playback candidate failed '
        'engine=${engine.name} bucket=${_playbackInitBucket(error)} '
        'errorType=${error.runtimeType} detail=${_safeTvPlaybackError(error)}',
      );
      if (identical(_controller, controller)) {
        setState(() => _controller = null);
      }
      if (relay != null && _controller != controller) {
        await relay.stop();
      }
      await controller.dispose();
      rethrow;
    }
  }

  bool _shouldRelaySession(_PlaybackSession session, _TvPlaybackEngine engine) {
    if (_isNativeHlsSession(session)) return true;
    return engine == _TvPlaybackEngine.libvlc &&
        session.tvMediaUrl.toLowerCase().contains('/web/playback/session/');
  }

  bool _isNativeHlsSession(_PlaybackSession session) {
    final type = session.sourceType.toLowerCase();
    final url = session.tvMediaUrl.toLowerCase();
    return type.contains('hls') ||
        type.contains('m3u8') ||
        type.contains('mpegurl') ||
        url.contains('.m3u8');
  }

  String _safePlaybackTypeBucket(String sourceType) {
    final type = sourceType.toLowerCase();
    if (type.contains('mpegurl') || type.contains('m3u8')) return 'hls';
    if (type.contains('dash') || type.contains('mpd')) return 'dash';
    if (type.contains('mp4') || type.contains('video')) return 'file';
    return type.isEmpty ? 'unknown' : 'other';
  }

  String _safePlaybackUrlBucket(String url) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('/web/playback/session/')) return 'web-session';
    if (lowerUrl.contains('.m3u8')) return 'hls-path';
    if (lowerUrl.contains('.mpd')) return 'dash-path';
    if (lowerUrl.contains('.mp4')) return 'file-path';
    return url.startsWith('https://') ? 'https' : 'other';
  }

  String _safeTvPlaybackError(Object error) {
    return error
        .toString()
        .replaceAll(RegExp(r'https?://[^\s"]+'), '[hidden-url]')
        .replaceAll(RegExp(r'127\.0\.0\.1[^\s"]*'), '[localhost-hidden]')
        .replaceAll(RegExp(r'localhost[^\s"]*'), '[localhost-hidden]');
  }

  Future<_TvNativePlaybackController> _prepareWithLadder(
    _PlaybackSession session,
  ) async {
    Object? lastError;
    var currentSession = session;
    final engineLadder = _engineLadderFor(session);
    for (var index = 0; index < engineLadder.length; index += 1) {
      final engine = engineLadder[index];
      try {
        return await _prepareNativeController(currentSession, engine);
      } catch (error) {
        lastError = error;
        if (index < engineLadder.length - 1) {
          final refreshed = await _freshPlaybackSessionForCurrentEpisode();
          if (refreshed != null) {
            currentSession = refreshed;
            if (_sessionIndex >= 0 && _sessionIndex < _sessions.length) {
              _sessions[_sessionIndex] = refreshed;
            }
            debugPrint(
              'Juicr TV native playback refreshed session '
              'after engine=${engine.name}',
            );
          }
        }
      }
    }
    throw _PlaybackUnavailableException(
      _playbackInitBucket(lastError ?? 'media_init'),
    );
  }

  Future<_PlaybackSession?> _freshPlaybackSessionForCurrentEpisode() async {
    try {
      final sessions = await _api
          .playbackSessions(widget.item, season: _season, episode: _episode)
          .timeout(const Duration(seconds: 45));
      return sessions.isEmpty ? null : sessions.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _verifyStartupProof(
    _TvNativePlaybackController controller,
    _TvPlaybackEngine engine,
  ) async {
    final timeout = engine == _TvPlaybackEngine.libvlc
        ? const Duration(seconds: 22)
        : const Duration(seconds: 6);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (controller.value.errorDescription.isNotEmpty) {
        throw StateError(controller.value.errorDescription);
      }
      if (controller.hasStartupProof) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('${engine.name}_startup');
  }

  Future<void> _openSession(int index, {required String feedbackLabel}) async {
    if (index < 0 || index >= _sessions.length || _switchingSource) return;
    setState(() {
      _switchingSource = true;
      _controlsVisible = true;
    });
    final oldController = _controller;
    try {
      var selectedIndex = index;
      _TvNativePlaybackController? preparedController;
      Object? lastError;
      for (
        var candidateIndex = index;
        candidateIndex < _sessions.length;
        candidateIndex += 1
      ) {
        try {
          preparedController = await _prepareWithLadder(
            _sessions[candidateIndex],
          );
          selectedIndex = candidateIndex;
          break;
        } catch (error) {
          lastError = error;
          debugPrint(
            'Juicr TV source candidate failed '
            'index=${candidateIndex + 1} errorType=${error.runtimeType} '
            'detail=${_safeTvPlaybackError(error)}',
          );
        }
      }
      if (preparedController == null) {
        throw lastError ?? const _TvApiException('playback_unavailable');
      }
      if (!mounted) {
        await _controller?.dispose();
        return;
      }
      if (oldController != null && !identical(oldController, _controller)) {
        await oldController.dispose();
      }
      setState(() {
        _sessionIndex = selectedIndex;
        _switchingSource = false;
        _autoNextQueued = false;
        _controlsVisible = true;
      });
      _playFocusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _switchingSource = false;
        _controller = oldController;
      });
      _showPlayerToast(_friendlyPlaybackError(error));
    }
  }

  Future<void> _switchToSource(int index) async {
    if (index == _sessionIndex ||
        index < 0 ||
        index >= _sessions.length ||
        _switchingSource) {
      return;
    }
    Navigator.of(context).pop();
    await _openSession(index, feedbackLabel: 'Source ${index + 1}');
  }

  Future<void> _openNextEpisode() async {
    final seriesLike =
        widget.item.type == 'series' || widget.item.type == 'animation';
    if (!seriesLike || _switchingSource) {
      _showPlayerToast('Next episode is available for series and animation.');
      return;
    }
    setState(() {
      _switchingSource = true;
      _controlsVisible = true;
    });
    final nextEpisode = _episode + 1;
    final oldController = _controller;
    try {
      final sessions = await _api
          .playbackSessions(widget.item, season: _season, episode: nextEpisode)
          .timeout(const Duration(seconds: 75));
      final controller = await _prepareWithLadder(sessions.first);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      if (oldController != null && !identical(oldController, controller)) {
        await oldController.dispose();
      }
      _episode = nextEpisode;
      setState(() {
        _sessions = sessions;
        _sessionIndex = 0;
        _switchingSource = false;
        _autoNextQueued = false;
        _controlsVisible = true;
      });
      _playFocusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _switchingSource = false;
        _controller = oldController;
      });
      _showPlayerToast(_friendlyPlaybackError(error));
    }
  }

  void _maybeAutoNextEpisode(_TvPlaybackValue value) {
    final seriesLike =
        widget.item.type == 'series' || widget.item.type == 'animation';
    if (!_autoplayNextEpisode ||
        !seriesLike ||
        _autoNextQueued ||
        _switchingSource ||
        !value.isInitialized ||
        value.duration <= Duration.zero) {
      return;
    }
    final remaining = value.duration - value.position;
    if (remaining > const Duration(seconds: 6)) return;
    _autoNextQueued = true;
    unawaited(_openNextEpisode());
  }

  String _sessionLabel(_PlaybackSession session, int index) {
    final type = session.sourceType.trim().toLowerCase();
    final quality = switch (type) {
      'hls' || 'm3u8' => 'Adaptive',
      'dash' || 'mpd' => 'Adaptive',
      'mp4' || 'video' => 'Direct',
      _ => 'TV ready',
    };
    return 'Source ${index + 1} - $quality';
  }

  Future<void> _showSourcesPanel() async {
    _showControls();
    if (_sessions.length < 2) {
      _showPlayerToast('Only one TV source is ready for this title.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 560,
            constraints: const BoxConstraints(maxHeight: 560),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xEE15151E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0x24FFFFFF)),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  child: _TvCircleIconButton(
                    icon: Icons.close_rounded,
                    size: 48,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 62),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sources',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Choose another TV-ready playback option.',
                        style: TextStyle(
                          color: Color(0xFFAAA6BD),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (
                                var index = 0;
                                index < _sessions.length;
                                index++
                              )
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _TvTextButton(
                                    icon: index == _sessionIndex
                                        ? Icons.check_circle_rounded
                                        : Icons.video_library_rounded,
                                    label: index == _sessionIndex
                                        ? '${_sessionLabel(_sessions[index], index)} active'
                                        : _sessionLabel(
                                            _sessions[index],
                                            index,
                                          ),
                                    autofocus: index == _sessionIndex,
                                    enabled: !_switchingSource,
                                    animateIcon:
                                        _switchingSource &&
                                        index != _sessionIndex,
                                    onPressed: () =>
                                        unawaited(_switchToSource(index)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    _showControls();
    _sourcesFocusNode.requestFocus();
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.setPlaybackSpeed(speed);
    setState(() {
      _playbackSpeed = speed;
      _controlsVisible = true;
    });
    _showFeedback(Icons.speed_rounded, '${speed.toStringAsFixed(2)}x');
  }

  Future<void> _restartPlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.seekTo(Duration.zero);
    await controller.play();
    _showControls();
    _showFeedback(Icons.refresh_rounded, 'Restarted');
  }

  Future<void> _showSubtitlePicker(VoidCallback refreshSettingsDialog) async {
    final captionsAvailable =
        widget.subtitles.isNotEmpty &&
        widget.settings.subtitles &&
        widget.settings.builtInSubtitles;
    final selectedLabel =
        _captionsEnabled &&
            _subtitleIndex >= 0 &&
            _subtitleIndex < widget.subtitles.length
        ? widget.subtitles[_subtitleIndex].label
        : 'Off';
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _TvPlaybackChoiceDialog(
        title: 'Subtitle',
        selected: selectedLabel,
        choices: [
          const _TvPlaybackChoice('Off', Icons.closed_caption_off_rounded),
          if (captionsAvailable)
            for (final subtitle in widget.subtitles)
              _TvPlaybackChoice(subtitle.label, Icons.closed_caption_rounded),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final subtitleIndex = widget.subtitles.indexWhere(
      (subtitle) => subtitle.label == selected,
    );
    setState(() {
      _subtitleIndex = subtitleIndex;
      _captionsEnabled = subtitleIndex >= 0;
      _controlsVisible = true;
    });
    if (_controller?.engine == _TvPlaybackEngine.media3) {
      await _openSession(
        _sessionIndex,
        feedbackLabel: _captionsEnabled ? 'Subtitles on' : 'Subtitles off',
      );
    }
    refreshSettingsDialog();
    _showFeedback(
      Icons.closed_caption_rounded,
      _captionsEnabled ? 'Subtitles on' : 'Subtitles off',
    );
  }

  Future<void> _showVideoSizePicker(VoidCallback refreshSettingsDialog) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _TvPlaybackChoiceDialog(
        title: 'Video size',
        selected: _videoSize,
        choices: const [
          _TvPlaybackChoice('Fit', Icons.fit_screen_rounded),
          _TvPlaybackChoice('Fill', Icons.fullscreen_rounded),
          _TvPlaybackChoice('16:9', Icons.aspect_ratio_rounded),
          _TvPlaybackChoice('Stretch', Icons.open_in_full_rounded),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _videoSize = selected;
      _controlsVisible = true;
    });
    refreshSettingsDialog();
    _showFeedback(Icons.aspect_ratio_rounded, selected);
  }

  Widget _videoSurface(_TvPlaybackValue value) {
    final controller = _controller;
    if (controller == null) return const _TvPlaybackLoadingState();
    Widget withLoading(Widget child) {
      if (value.isInitialized) return child;
      return Stack(
        fit: StackFit.expand,
        children: [
          child,
          const ColoredBox(
            color: Colors.black,
            child: Center(child: _TvPlaybackLoadingState()),
          ),
        ],
      );
    }

    return SizedBox.expand(
      child: withLoading(
        controller.surface(
          aspectRatio: value.aspectRatio <= 0 ? 16 / 9 : value.aspectRatio,
        ),
      ),
    );
  }

  Future<void> _showSettingsPanel() async {
    _showControls();
    final seriesLike =
        widget.item.type == 'series' || widget.item.type == 'animation';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: 760,
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: const Color(0xEE15151E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x24FFFFFF)),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _TvCircleIconButton(
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            seriesLike
                                ? 'S$_season E$_episode - Source ${_sessionIndex + 1}/${_sessions.length}'
                                : 'Source ${_sessionIndex + 1}/${_sessions.length}',
                            style: const TextStyle(
                              color: Color(0xFFAAA6BD),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Column(
                            children: [
                              for (final speed in const [0.75, 1.0, 1.25, 1.5])
                                _TvPlaybackSettingsRow(
                                  icon: speed == _playbackSpeed
                                      ? Icons.check_circle_rounded
                                      : Icons.speed_rounded,
                                  title:
                                      'Speed ${speed.toStringAsFixed(speed == 1.0 ? 0 : 2)}x',
                                  value: speed == _playbackSpeed
                                      ? 'Active'
                                      : '',
                                  selected: speed == _playbackSpeed,
                                  onPressed: () {
                                    unawaited(_setPlaybackSpeed(speed));
                                    setDialogState(() {});
                                  },
                                ),
                              _TvPlaybackSettingsRow(
                                icon: Icons.refresh_rounded,
                                title: 'Restart',
                                value: 'Start from beginning',
                                onPressed: () => unawaited(_restartPlayback()),
                              ),
                              _TvPlaybackSettingsRow(
                                icon: _captionsEnabled
                                    ? Icons.closed_caption_rounded
                                    : Icons.closed_caption_off_rounded,
                                title: 'Subtitle',
                                value:
                                    _captionsEnabled &&
                                        _subtitleIndex >= 0 &&
                                        _subtitleIndex < widget.subtitles.length
                                    ? widget.subtitles[_subtitleIndex].label
                                    : widget.subtitles.isEmpty
                                    ? 'Unavailable'
                                    : 'Off',
                                onPressed: () => unawaited(
                                  _showSubtitlePicker(
                                    () => setDialogState(() {}),
                                  ),
                                ),
                              ),
                              _TvPlaybackSettingsRow(
                                icon: Icons.aspect_ratio_rounded,
                                title: 'Video size',
                                value: _videoSize,
                                onPressed: () => unawaited(
                                  _showVideoSizePicker(
                                    () => setDialogState(() {}),
                                  ),
                                ),
                              ),
                              if (seriesLike)
                                _TvPlaybackSettingsRow(
                                  icon: _autoplayNextEpisode
                                      ? Icons.playlist_play_rounded
                                      : Icons.playlist_remove_rounded,
                                  title: 'Next episode',
                                  value: _autoplayNextEpisode ? 'On' : 'Off',
                                  onPressed: () {
                                    setState(() {
                                      _autoplayNextEpisode =
                                          !_autoplayNextEpisode;
                                      _controlsVisible = true;
                                    });
                                    setDialogState(() {});
                                    _showFeedback(
                                      Icons.playlist_play_rounded,
                                      _autoplayNextEpisode
                                          ? 'Auto next on'
                                          : 'Auto next off',
                                    );
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted) return;
    _showControls();
    _settingsFocusNode.requestFocus();
  }

  KeyEventResult _focusPlaybackControl(TraversalDirection direction) {
    _showControls();
    final focused = FocusManager.instance.primaryFocus;
    if (direction == TraversalDirection.up) {
      if (focused == _progressFocusNode) {
        _sourcesFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (focused == _sourcesFocusNode ||
          focused == _settingsFocusNode ||
          focused == _lockFocusNode) {
        _playFocusNode.requestFocus();
      } else if (focused == _skipBackFocusNode ||
          focused == _skipForwardFocusNode) {
        _backFocusNode.requestFocus();
      } else if (focused == _nextEpisodeFocusNode) {
        _nextEpisodeFocusNode.requestFocus();
      } else {
        _backFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (direction == TraversalDirection.down) {
      if (focused == _backFocusNode) {
        _playFocusNode.requestFocus();
      } else if (focused == _nextEpisodeFocusNode) {
        _playFocusNode.requestFocus();
      } else if (focused == _playFocusNode ||
          focused == _skipBackFocusNode ||
          focused == _skipForwardFocusNode) {
        _sourcesFocusNode.requestFocus();
      } else if (focused == _sourcesFocusNode ||
          focused == _settingsFocusNode ||
          focused == _lockFocusNode) {
        _progressFocusNode.requestFocus();
      } else {
        _sourcesFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handlePlaybackKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final bucket = tvRemoteInputMapper.bucketForEvent(event);
    _updateRemoteDebug(bucket);
    if (bucket == null) return KeyEventResult.ignored;
    final command = tvPlaybackRemoteActionResolver.commandFor(bucket);
    if (_locked &&
        bucket != TvRemoteActionBucket.select &&
        command != TvPlaybackRemoteCommand.close) {
      return KeyEventResult.handled;
    }
    switch (command) {
      case TvPlaybackRemoteCommand.togglePlay:
        unawaited(_togglePlay());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.play:
        unawaited(_playOnly());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.pause:
        unawaited(_pauseOnly());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.stop:
      case TvPlaybackRemoteCommand.close:
        unawaited(_closePlayback());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.seekForward:
        unawaited(_fastSeekBy(_fastSeekStep, direction: 1));
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.seekBack:
        unawaited(
          _fastSeekBy(
            Duration(seconds: -_fastSeekStep.inSeconds),
            direction: -1,
          ),
        );
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.openSources:
        unawaited(_showSourcesPanel());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.openSettings:
        unawaited(_showSettingsPanel());
        return KeyEventResult.handled;
      case TvPlaybackRemoteCommand.showControls:
        break;
      case null:
        return KeyEventResult.ignored;
    }
    if (bucket == TvRemoteActionBucket.dpadUp) {
      return _focusPlaybackControl(TraversalDirection.up);
    }
    if (bucket == TvRemoteActionBucket.dpadDown) {
      return _focusPlaybackControl(TraversalDirection.down);
    }
    if (bucket == TvRemoteActionBucket.dpadRight) {
      return KeyEventResult.ignored;
    }
    if (bucket == TvRemoteActionBucket.dpadLeft) {
      return KeyEventResult.ignored;
    }
    if (bucket == TvRemoteActionBucket.select) {
      _showControls();
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
            TraversalDirection.up,
          ),
          SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
            TraversalDirection.down,
          ),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                unawaited(_closePlayback());
                return null;
              },
            ),
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                unawaited(_togglePlay());
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _playbackFocusNode,
            autofocus: true,
            onKeyEvent: (_, event) => _handlePlaybackKey(event),
            child: AnimatedBuilder(
              animation: _controller ?? Listenable.merge(const <Listenable>[]),
              builder: (context, _) {
                final value = _controller?.value ?? _TvPlaybackValue.empty;
                final initialized = value.isInitialized;
                final feedback = _feedback;
                _maybeAutoNextEpisode(value);
                return Stack(
                  children: [
                    Center(child: _videoSurface(value)),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          duration: _tvDuration(180),
                          opacity: _controlsVisible ? 1 : 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.72),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.74),
                                ],
                                stops: const [0, 0.36, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_switchingSource)
                      const Positioned.fill(
                        child: Center(child: _TvPlaybackLoadingState()),
                      ),
                    if (_controlsVisible &&
                        !_locked &&
                        feedback?.seeking != true &&
                        !_switchingSource)
                      _TvPlaybackCenterControls(
                        initialized: initialized,
                        playing: value.isPlaying,
                        skipBackFocusNode: _skipBackFocusNode,
                        playFocusNode: _playFocusNode,
                        skipForwardFocusNode: _skipForwardFocusNode,
                        onTogglePlay: _togglePlay,
                        onSeekBack: () => _skipBy(
                          const Duration(seconds: -15),
                          direction: -1,
                        ),
                        onSeekForward: () => _skipBy(_seekStep, direction: 1),
                      ),
                    if (feedback != null)
                      _TvPlaybackFeedbackOverlay(feedback: feedback),
                    SafeArea(
                      child: AnimatedOpacity(
                        duration: _tvDuration(180),
                        opacity: _controlsVisible ? 1 : 0,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 24, 28, 26),
                          child: Column(
                            children: [
                              _TvPlaybackTopBar(
                                title: widget.item.title,
                                showNextEpisode:
                                    (widget.item.type == 'series' ||
                                    widget.item.type == 'animation'),
                                nextEpisodeLabel: 'Next episode',
                                backFocusNode: _backFocusNode,
                                nextEpisodeFocusNode: _nextEpisodeFocusNode,
                                onBack: () => unawaited(_closePlayback()),
                                onNextEpisode: _openNextEpisode,
                                onFocusMainControls: () =>
                                    _playFocusNode.requestFocus(),
                              ),
                              const Spacer(),
                              _TvPlaybackActionRow(
                                locked: _locked,
                                sourcesFocusNode: _sourcesFocusNode,
                                settingsFocusNode: _settingsFocusNode,
                                lockFocusNode: _lockFocusNode,
                                onLockPressed: _toggleLock,
                                onSourcesPressed: _showSourcesPanel,
                                onSettingsPressed: _showSettingsPanel,
                                showAdvancedControls:
                                    widget.settings.advancedControls,
                              ),
                              const SizedBox(height: 14),
                              _TvPlaybackTransportHud(
                                initialized: initialized,
                                position: value.position,
                                duration: value.duration,
                                focusNode: _progressFocusNode,
                                onSeekBack: () => _fastSeekBy(
                                  Duration(seconds: -_fastSeekStep.inSeconds),
                                  direction: -1,
                                ),
                                onSeekForward: () =>
                                    _fastSeekBy(_fastSeekStep, direction: 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TvPlaybackSettingsRow extends StatelessWidget {
  const _TvPlaybackSettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onPressed,
    this.selected = false,
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onPressed;
  final bool selected;
  final FocusNode? focusNode;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _TvFocusable(
        autoReveal: true,
        focusNode: focusNode,
        onPressed: onPressed,
        onArrowUp: onArrowUp,
        onArrowDown: onArrowDown,
        builder: (focused) {
          return AnimatedContainer(
            duration: _tvDuration(130),
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: selected ? _tvAccentColor : const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: focused
                    ? selected
                          ? Colors.white
                          : _tvFocusBorder
                    : const Color(0x22FFFFFF),
                width: focused ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? Colors.black : _tvAccentColor,
                  size: 25,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (value.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0x22000000)
                          : const Color(0x24FFFFFF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? const Color(0x22000000)
                            : const Color(0x22FFFFFF),
                      ),
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TvPlaybackChoice {
  const _TvPlaybackChoice(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _TvPlaybackChoiceDialog extends StatefulWidget {
  const _TvPlaybackChoiceDialog({
    required this.title,
    required this.selected,
    required this.choices,
  });

  final String title;
  final String selected;
  final List<_TvPlaybackChoice> choices;

  @override
  State<_TvPlaybackChoiceDialog> createState() =>
      _TvPlaybackChoiceDialogState();
}

class _TvPlaybackChoiceDialogState extends State<_TvPlaybackChoiceDialog> {
  final List<FocusNode> _choiceFocusNodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncChoiceFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusChoice(_selectedIndex);
    });
  }

  @override
  void dispose() {
    for (final node in _choiceFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  int get _selectedIndex {
    final index = widget.choices.indexWhere(
      (choice) => choice.label == widget.selected,
    );
    return index < 0 ? 0 : index;
  }

  void _syncChoiceFocusNodes() {
    while (_choiceFocusNodes.length > widget.choices.length) {
      _choiceFocusNodes.removeLast().dispose();
    }
    while (_choiceFocusNodes.length < widget.choices.length) {
      final index = _choiceFocusNodes.length;
      _choiceFocusNodes.add(FocusNode(debugLabel: 'tv-playback-choice-$index'));
    }
  }

  void _focusChoice(int index) {
    if (index < 0 || index >= _choiceFocusNodes.length) return;
    final node = _choiceFocusNodes[index];
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(140),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncChoiceFocusNodes();
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: const Color(0xF215151E),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0x24FFFFFF)),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              child: _TvCircleIconButton(
                icon: Icons.close_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 22),
                  for (var index = 0; index < widget.choices.length; index++)
                    _TvPlaybackSettingsRow(
                      icon: widget.choices[index].label == widget.selected
                          ? Icons.check_circle_rounded
                          : widget.choices[index].icon,
                      title: widget.choices[index].label,
                      value: widget.choices[index].label == widget.selected
                          ? 'Active'
                          : '',
                      selected: widget.choices[index].label == widget.selected,
                      focusNode: _choiceFocusNodes[index],
                      onArrowUp: index == 0
                          ? () => _focusChoice(index)
                          : () => _focusChoice(index - 1),
                      onArrowDown: index == widget.choices.length - 1
                          ? () => _focusChoice(index)
                          : () => _focusChoice(index + 1),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(widget.choices[index].label),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvPlaybackTopBar extends StatelessWidget {
  const _TvPlaybackTopBar({
    required this.title,
    required this.showNextEpisode,
    required this.nextEpisodeLabel,
    required this.backFocusNode,
    required this.nextEpisodeFocusNode,
    required this.onBack,
    required this.onNextEpisode,
    required this.onFocusMainControls,
  });

  final String title;
  final bool showNextEpisode;
  final String nextEpisodeLabel;
  final FocusNode backFocusNode;
  final FocusNode nextEpisodeFocusNode;
  final VoidCallback onBack;
  final VoidCallback onNextEpisode;
  final VoidCallback onFocusMainControls;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TvTextButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back',
          focusNode: backFocusNode,
          onPressed: onBack,
          onArrowRight: showNextEpisode
              ? () => nextEpisodeFocusNode.requestFocus()
              : null,
          onArrowDown: onFocusMainControls,
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        SizedBox(
          width: 170,
          child: showNextEpisode
              ? Align(
                  alignment: Alignment.centerRight,
                  child: _TvTextButton(
                    icon: Icons.skip_next_rounded,
                    label: nextEpisodeLabel,
                    focusNode: nextEpisodeFocusNode,
                    onPressed: onNextEpisode,
                    onArrowLeft: () => backFocusNode.requestFocus(),
                    onArrowDown: onFocusMainControls,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _TvPlaybackActionRow extends StatelessWidget {
  const _TvPlaybackActionRow({
    required this.locked,
    required this.sourcesFocusNode,
    required this.settingsFocusNode,
    required this.lockFocusNode,
    required this.onLockPressed,
    required this.onSourcesPressed,
    required this.onSettingsPressed,
    required this.showAdvancedControls,
  });

  final bool locked;
  final FocusNode sourcesFocusNode;
  final FocusNode settingsFocusNode;
  final FocusNode lockFocusNode;
  final VoidCallback onLockPressed;
  final VoidCallback onSourcesPressed;
  final VoidCallback onSettingsPressed;
  final bool showAdvancedControls;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _TvPlaybackPillButton(
          icon: Icons.video_library_rounded,
          label: 'Sources',
          focusNode: sourcesFocusNode,
          onPressed: locked ? null : onSourcesPressed,
        ),
        const SizedBox(width: 12),
        _TvPlaybackPillButton(
          icon: Icons.settings_rounded,
          label: 'Settings',
          focusNode: settingsFocusNode,
          onPressed: locked ? null : onSettingsPressed,
        ),
        if (showAdvancedControls) ...[
          const SizedBox(width: 12),
          _TvPlaybackPillButton(
            icon: locked ? Icons.lock_rounded : Icons.lock_open_rounded,
            label: locked ? 'Unlock' : 'Lock',
            focusNode: lockFocusNode,
            onPressed: onLockPressed,
          ),
        ],
      ],
    );
  }
}

class _TvPlaybackPillButton extends StatelessWidget {
  const _TvPlaybackPillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      enabled: onPressed != null,
      focusNode: focusNode,
      onPressed: onPressed ?? () {},
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(140),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: focused ? _tvAccentColor : const Color(0xAA111217),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused ? _tvFocusBorder : const Color(0x22FFFFFF),
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: focused ? Colors.black : const Color(0xFFE8E4F5),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: focused ? Colors.black : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvPlaybackFeedbackOverlay extends StatelessWidget {
  const _TvPlaybackFeedbackOverlay({required this.feedback});

  final _TvPlaybackFeedback feedback;

  @override
  Widget build(BuildContext context) {
    if (feedback.skipDirection != 0) {
      return Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: _TvSkipPulse(
              direction: feedback.skipDirection,
              label: feedback.label,
            ),
          ),
        ),
      );
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedSwitcher(
            duration: _tvDuration(140),
            child: _TvSeekPulse(
              key: ValueKey('${feedback.label}:${feedback.seeking}'),
              icon: feedback.icon,
              seeking: feedback.seeking,
            ),
          ),
        ),
      ),
    );
  }
}

class _TvSeekPulse extends StatelessWidget {
  const _TvSeekPulse({super.key, required this.icon, required this.seeking});

  final IconData icon;
  final bool seeking;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        color: seeking ? const Color(0xB6111217) : _tvAccentColor,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x77000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: seeking ? Colors.white : Colors.black,
        size: seeking ? 36 : 44,
      ),
    );
  }
}

class _TvSkipPulse extends StatefulWidget {
  const _TvSkipPulse({required this.direction, required this.label});

  final int direction;
  final String label;

  @override
  State<_TvSkipPulse> createState() => _TvSkipPulseState();
}

class _TvSkipPulseState extends State<_TvSkipPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _tvDuration(520),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reverse = widget.direction < 0;
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.88, end: 1.08).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
        ),
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            color: const Color(0xB6111217),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x33FFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x77000000),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              RotationTransition(
                turns:
                    Tween<double>(
                      begin: reverse ? 0.0 : 0.0,
                      end: reverse ? -1.0 : 1.0,
                    ).animate(
                      CurvedAnimation(
                        parent: _controller,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: Transform.scale(
                  scaleX: reverse ? 1 : -1,
                  child: const Icon(
                    Icons.replay_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvPlaybackFeedback {
  const _TvPlaybackFeedback(
    this.icon,
    this.label, {
    required this.seeking,
    required this.skipDirection,
  });

  final IconData icon;
  final String label;
  final bool seeking;
  final int skipDirection;
}

class _TvPlaybackCenterControls extends StatelessWidget {
  const _TvPlaybackCenterControls({
    required this.initialized,
    required this.playing,
    required this.skipBackFocusNode,
    required this.playFocusNode,
    required this.skipForwardFocusNode,
    required this.onTogglePlay,
    required this.onSeekBack,
    required this.onSeekForward,
  });

  final bool initialized;
  final bool playing;
  final FocusNode skipBackFocusNode;
  final FocusNode playFocusNode;
  final FocusNode skipForwardFocusNode;
  final Future<void> Function() onTogglePlay;
  final Future<void> Function() onSeekBack;
  final Future<void> Function() onSeekForward;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(120, 92, 120, 118),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _TvPlaybackSkipButton(
                  direction: -1,
                  label: 'Back 15 seconds',
                  size: 72,
                  focusNode: skipBackFocusNode,
                  onPressed: initialized ? () => unawaited(onSeekBack()) : null,
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: _TvPlaybackRoundButton(
                  icon: playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  label: playing ? 'Pause' : 'Play',
                  size: 96,
                  accent: true,
                  focusNode: playFocusNode,
                  autofocus: true,
                  onPressed: initialized
                      ? () => unawaited(onTogglePlay())
                      : null,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _TvPlaybackSkipButton(
                  direction: 1,
                  label: 'Forward 15 seconds',
                  size: 72,
                  focusNode: skipForwardFocusNode,
                  onPressed: initialized
                      ? () => unawaited(onSeekForward())
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvPlaybackLoadingState extends StatelessWidget {
  const _TvPlaybackLoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: _tvAccentColor),
        const SizedBox(height: 18),
        const Text(
          'Preparing playback...',
          style: TextStyle(
            color: Color(0xFFDAD8E8),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _TvPlaybackTransportHud extends StatelessWidget {
  const _TvPlaybackTransportHud({
    required this.initialized,
    required this.position,
    required this.duration,
    required this.focusNode,
    required this.onSeekBack,
    required this.onSeekForward,
  });

  final bool initialized;
  final Duration position;
  final Duration duration;
  final FocusNode focusNode;
  final Future<void> Function() onSeekBack;
  final Future<void> Function() onSeekForward;

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble();
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            _formatDuration(position),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TvPlaybackProgressScrubber(
            focusNode: focusNode,
            initialized: initialized,
            progress: progress,
            onSeekBack: onSeekBack,
            onSeekForward: onSeekForward,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(
            _formatDuration(duration),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _TvPlaybackProgressScrubber extends StatefulWidget {
  const _TvPlaybackProgressScrubber({
    required this.focusNode,
    required this.initialized,
    required this.progress,
    required this.onSeekBack,
    required this.onSeekForward,
  });

  final FocusNode focusNode;
  final bool initialized;
  final double progress;
  final Future<void> Function() onSeekBack;
  final Future<void> Function() onSeekForward;

  @override
  State<_TvPlaybackProgressScrubber> createState() =>
      _TvPlaybackProgressScrubberState();
}

class _TvPlaybackProgressScrubberState
    extends State<_TvPlaybackProgressScrubber> {
  static const Duration _holdSeekDelay = Duration(milliseconds: 260);
  static const Duration _holdSeekInterval = Duration(milliseconds: 240);

  Timer? _holdSeekDelayTimer;
  Timer? _holdSeekTimer;
  bool _focused = false;
  int _holdDirection = 0;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_syncFocus);
  }

  @override
  void didUpdateWidget(covariant _TvPlaybackProgressScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    oldWidget.focusNode.removeListener(_syncFocus);
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_syncFocus);
  }

  @override
  void dispose() {
    _stopHoldSeek();
    widget.focusNode.removeListener(_syncFocus);
    super.dispose();
  }

  void _syncFocus() {
    if (!mounted) return;
    if (!widget.focusNode.hasFocus) _stopHoldSeek();
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  void _startHoldSeek(int direction) {
    if (_holdDirection == direction &&
        (_holdSeekDelayTimer != null || _holdSeekTimer != null)) {
      return;
    }
    _stopHoldSeek();
    _holdDirection = direction;
    _holdSeekDelayTimer = Timer(_holdSeekDelay, () {
      _holdSeekDelayTimer = null;
      unawaited(direction < 0 ? widget.onSeekBack() : widget.onSeekForward());
      _holdSeekTimer = Timer.periodic(_holdSeekInterval, (_) {
        unawaited(direction < 0 ? widget.onSeekBack() : widget.onSeekForward());
      });
    });
  }

  void _stopHoldSeek() {
    _holdDirection = 0;
    _holdSeekDelayTimer?.cancel();
    _holdSeekDelayTimer = null;
    _holdSeekTimer?.cancel();
    _holdSeekTimer = null;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!widget.initialized) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _stopHoldSeek();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (event is KeyRepeatEvent) unawaited(widget.onSeekBack());
      _startHoldSeek(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (event is KeyRepeatEvent) unawaited(widget.onSeekForward());
      _startHoldSeek(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: widget.initialized,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: widget.initialized ? widget.focusNode.requestFocus : null,
        child: AnimatedContainer(
          duration: _tvDuration(130),
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _focused ? _tvFocusBorder : Colors.transparent,
              width: _focused ? 2 : 0,
            ),
          ),
          child: SizedBox(
            height: _focused ? 18 : 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(color: Color(0x44FFFFFF)),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: widget.initialized ? widget.progress : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: _tvAccentColor),
                    ),
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

class _TvPlaybackRoundButton extends StatelessWidget {
  const _TvPlaybackRoundButton({
    required this.icon,
    required this.label,
    required this.size,
    required this.onPressed,
    this.accent = false,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final double size;
  final VoidCallback? onPressed;
  final bool accent;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      enabled: onPressed != null,
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed ?? () {},
      builder: (focused) {
        final active = accent || focused;
        return AnimatedScale(
          scale: focused ? 1.08 : 1,
          duration: _tvDuration(130),
          child: Semantics(
            button: true,
            label: label,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? _tvAccentColor : const Color(0xAA111217),
                border: Border.all(
                  color: focused ? Colors.white : const Color(0x22FFFFFF),
                  width: focused ? 3 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: active ? Colors.black : Colors.white,
                size: accent ? 48 : 36,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TvPlaybackSkipButton extends StatefulWidget {
  const _TvPlaybackSkipButton({
    required this.direction,
    required this.label,
    required this.size,
    required this.focusNode,
    required this.onPressed,
  });

  final int direction;
  final String label;
  final double size;
  final FocusNode focusNode;
  final VoidCallback? onPressed;

  @override
  State<_TvPlaybackSkipButton> createState() => _TvPlaybackSkipButtonState();
}

class _TvPlaybackSkipButtonState extends State<_TvPlaybackSkipButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _tvDuration(440),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _press() {
    if (widget.onPressed == null) return;
    _controller
      ..reset()
      ..forward();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final reverse = widget.direction < 0;
    return _TvFocusable(
      enabled: widget.onPressed != null,
      focusNode: widget.focusNode,
      onPressed: _press,
      builder: (focused) {
        final active = focused;
        return AnimatedScale(
          scale: focused ? 1.08 : 1,
          duration: _tvDuration(130),
          child: Semantics(
            button: true,
            label: widget.label,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? _tvAccentColor : const Color(0xAA111217),
                border: Border.all(
                  color: focused ? _tvFocusBorder : const Color(0x22FFFFFF),
                  width: focused ? 3 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RotationTransition(
                    turns: Tween<double>(begin: 0, end: reverse ? -1 : 1)
                        .animate(
                          CurvedAnimation(
                            parent: _controller,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: Transform.scale(
                      scaleX: reverse ? 1 : -1,
                      child: Icon(
                        Icons.replay_rounded,
                        color: active ? Colors.black : Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '15',
                      style: TextStyle(
                        color: active ? Colors.black : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
