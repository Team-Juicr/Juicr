part of 'main.dart';

class _TvPlaybackPage extends StatefulWidget {
  const _TvPlaybackPage({
    required this.item,
    required this.controller,
    required this.sessions,
    required this.initialSessionIndex,
    required this.initialSeason,
    required this.initialEpisode,
    required this.settings,
    required this.subtitles,
    required this.initialSubtitleIndex,
  });

  final _TvItem item;
  final VideoPlayerController controller;
  final List<_PlaybackSession> sessions;
  final int initialSessionIndex;
  final int initialSeason;
  final int initialEpisode;
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
  final FocusNode _skipBackFocusNode = FocusNode(debugLabel: 'tv-playback-skip-back');
  final FocusNode _playFocusNode = FocusNode(debugLabel: 'tv-playback-play');
  final FocusNode _skipForwardFocusNode = FocusNode(debugLabel: 'tv-playback-skip-forward');
  final FocusNode _sourcesFocusNode = FocusNode(debugLabel: 'tv-playback-sources');
  final FocusNode _settingsFocusNode = FocusNode(debugLabel: 'tv-playback-settings');
  final FocusNode _lockFocusNode = FocusNode(debugLabel: 'tv-playback-lock');
  final FocusNode _progressFocusNode = FocusNode(debugLabel: 'tv-playback-progress');
  final _api = _TvApi();
  late VideoPlayerController _controller;
  late List<_PlaybackSession> _sessions;
  Timer? _hideControlsTimer;
  Timer? _feedbackTimer;
  bool _controlsVisible = true;
  bool _locked = false;
  bool _switchingSource = false;
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

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _sessions = widget.sessions;
    _sessionIndex = widget.initialSessionIndex.clamp(0, _sessions.length - 1).toInt();
    _season = widget.initialSeason;
    _episode = widget.initialEpisode;
    _subtitleIndex = widget.initialSubtitleIndex;
    _captionsEnabled = widget.settings.subtitles &&
        widget.settings.builtInSubtitles &&
        _subtitleIndex >= 0 &&
        _subtitleIndex < widget.subtitles.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showControls();
      _playFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _feedbackTimer?.cancel();
    _playbackFocusNode.dispose();
    _backFocusNode.dispose();
    _skipBackFocusNode.dispose();
    _playFocusNode.dispose();
    _skipForwardFocusNode.dispose();
    _sourcesFocusNode.dispose();
    _settingsFocusNode.dispose();
    _lockFocusNode.dispose();
    _progressFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
    _showControls();
    if (mounted) setState(() {});
  }

  Future<void> _seekBy(Duration offset) async {
    if (!_controller.value.isInitialized) return;
    final value = _controller.value;
    final target = value.position + offset;
    final duration = value.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && target > duration
            ? duration
            : target;
    await _controller.seekTo(clamped);
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
    _showFeedback(_locked ? Icons.lock_rounded : Icons.lock_open_rounded, _locked ? 'Locked' : 'Unlocked');
    if (!_locked) _showControls();
  }

  void _showPlayerToast(String message) {
    _showControls();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  _TvPlaybackProgress _currentProgress() {
    final value = _controller.value;
    if (!value.isInitialized) {
      return const _TvPlaybackProgress(position: Duration.zero, duration: Duration.zero);
    }
    return _TvPlaybackProgress(position: value.position, duration: value.duration);
  }

  void _closePlayback() {
    Navigator.of(context).pop(_currentProgress());
  }

  Future<VideoPlayerController> _prepareController(_PlaybackSession session) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(session.tvMediaUrl),
      formatHint: session.videoFormatHint,
      httpHeaders: session.httpHeaders,
      closedCaptionFile: _activeSubtitleFile(),
    );
    await controller.initialize().timeout(const Duration(seconds: 22));
    await controller.setPlaybackSpeed(_playbackSpeed);
    await controller.play();
    return controller;
  }

  Future<void> _replaceController({
    required VideoPlayerController controller,
    required List<_PlaybackSession> sessions,
    required int sessionIndex,
    required String feedbackLabel,
  }) async {
    final oldController = _controller;
    setState(() {
      _controller = controller;
      _sessions = sessions;
      _sessionIndex = sessionIndex;
      _switchingSource = false;
      _autoNextQueued = false;
      _controlsVisible = true;
    });
    await oldController.dispose();
    _showFeedback(Icons.check_rounded, feedbackLabel);
    _playFocusNode.requestFocus();
  }

  Future<void> _switchToSource(int index) async {
    if (index == _sessionIndex || index < 0 || index >= _sessions.length || _switchingSource) {
      return;
    }
    Navigator.of(context).pop();
    setState(() {
      _switchingSource = true;
      _controlsVisible = true;
    });
    try {
      final controller = await _prepareController(_sessions[index]);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _replaceController(
        controller: controller,
        sessions: _sessions,
        sessionIndex: index,
        feedbackLabel: 'Source ${index + 1}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _switchingSource = false);
      _showPlayerToast('That TV source was not ready. Try another source.');
    }
  }

  Future<void> _openNextEpisode() async {
    final seriesLike = widget.item.type == 'series' || widget.item.type == 'animation';
    if (!seriesLike || _switchingSource) {
      _showPlayerToast('Next episode is available for series and animation.');
      return;
    }
    setState(() {
      _switchingSource = true;
      _controlsVisible = true;
    });
    final nextEpisode = _episode + 1;
    try {
      final sessions = await _api
          .playbackSessions(
            widget.item,
            season: _season,
            episode: nextEpisode,
            allowWebFallback: widget.settings.playbackEngine != 'Native',
          )
          .timeout(const Duration(seconds: 75));
      VideoPlayerController? readyController;
      var readyIndex = 0;
      Object? lastError;
      for (var index = 0; index < sessions.length; index++) {
        try {
          readyController = await _prepareController(sessions[index]);
          readyIndex = index;
          break;
        } catch (error) {
          lastError = error;
        }
      }
      final controller = readyController;
      if (controller == null) {
        throw _PlaybackUnavailableException(
          _playbackInitBucket(lastError ?? 'media_init'),
        );
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _episode = nextEpisode;
      await _replaceController(
        controller: controller,
        sessions: sessions,
        sessionIndex: readyIndex,
        feedbackLabel: 'S$_season E$_episode',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _switchingSource = false);
      _showPlayerToast(_friendlyPlaybackError(error));
    }
  }

  void _maybeAutoNextEpisode(VideoPlayerValue value) {
    final seriesLike = widget.item.type == 'series' || widget.item.type == 'animation';
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
                              for (var index = 0; index < _sessions.length; index++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _TvTextButton(
                                    icon: index == _sessionIndex
                                        ? Icons.check_circle_rounded
                                        : Icons.video_library_rounded,
                                    label: index == _sessionIndex
                                        ? '${_sessionLabel(_sessions[index], index)} active'
                                        : _sessionLabel(_sessions[index], index),
                                    autofocus: index == _sessionIndex,
                                    enabled: !_switchingSource,
                                    animateIcon: _switchingSource && index != _sessionIndex,
                                    onPressed: () => unawaited(_switchToSource(index)),
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
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    if (!_controller.value.isInitialized) return;
    await _controller.setPlaybackSpeed(speed);
    setState(() {
      _playbackSpeed = speed;
      _controlsVisible = true;
    });
    _showFeedback(Icons.speed_rounded, '${speed.toStringAsFixed(2)}x');
  }

  Future<void> _restartPlayback() async {
    if (!_controller.value.isInitialized) return;
    await _controller.seekTo(Duration.zero);
    await _controller.play();
    _showControls();
    _showFeedback(Icons.refresh_rounded, 'Restarted');
  }

  Future<void> _showSubtitlePicker(VoidCallback refreshSettingsDialog) async {
    final captionsAvailable = widget.subtitles.isNotEmpty &&
        widget.settings.subtitles &&
        widget.settings.builtInSubtitles;
    final selectedLabel = _captionsEnabled && _subtitleIndex >= 0 && _subtitleIndex < widget.subtitles.length
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
    final subtitleIndex = widget.subtitles.indexWhere((subtitle) => subtitle.label == selected);
    setState(() {
      _subtitleIndex = subtitleIndex;
      _captionsEnabled = subtitleIndex >= 0;
      _controlsVisible = true;
    });
    await _controller.setClosedCaptionFile(_activeSubtitleFile());
    refreshSettingsDialog();
    _showFeedback(Icons.closed_caption_rounded, _captionsEnabled ? 'Subtitles on' : 'Subtitles off');
  }

  Future<ClosedCaptionFile>? _activeSubtitleFile() {
    if (!_captionsEnabled || _subtitleIndex < 0 || _subtitleIndex >= widget.subtitles.length) {
      return null;
    }
    final subtitle = widget.subtitles[_subtitleIndex];
    return _api.subtitleText(subtitle).then((text) {
      return subtitle.format.toLowerCase().contains('srt')
          ? SubRipCaptionFile(text)
          : WebVTTCaptionFile(text);
    });
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

  Widget _videoSurface(VideoPlayerValue value) {
    if (!value.isInitialized) return const _TvPlaybackLoadingState();
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
        final videoAspect = value.aspectRatio <= 0 ? 16 / 9 : value.aspectRatio;
        final effectiveAspect = _videoSize == '16:9' ? 16 / 9 : videoAspect;
        Widget withCaptions(Widget child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (_captionsEnabled)
                Positioned(
                  left: 72,
                  right: 72,
                  bottom: _controlsVisible ? 116 : 42,
                  child: ClosedCaption(
                    text: value.caption.text,
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      shadows: [
                        Shadow(color: Colors.black, blurRadius: 8),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }
        if (_videoSize == 'Stretch') {
          return SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: screenSize.width,
                height: screenSize.height,
                child: withCaptions(VideoPlayer(_controller)),
              ),
            ),
          );
        }
        final fit = _videoSize == 'Fill' ? BoxFit.cover : BoxFit.contain;
        return SizedBox.expand(
          child: FittedBox(
            fit: fit,
            child: SizedBox(
              width: effectiveAspect,
              height: 1,
              child: AspectRatio(
                aspectRatio: effectiveAspect,
                child: withCaptions(VideoPlayer(_controller)),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSettingsPanel() async {
    _showControls();
    final seriesLike = widget.item.type == 'series' || widget.item.type == 'animation';
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
                      padding: const EdgeInsets.only(top: 8, right: 56),
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
                                  title: 'Speed ${speed.toStringAsFixed(speed == 1.0 ? 0 : 2)}x',
                                  value: speed == _playbackSpeed ? 'Active' : '',
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
                                value: _captionsEnabled && _subtitleIndex >= 0 && _subtitleIndex < widget.subtitles.length
                                    ? widget.subtitles[_subtitleIndex].label
                                    : widget.subtitles.isEmpty
                                        ? 'Unavailable'
                                        : 'Off',
                                onPressed: () => unawaited(
                                  _showSubtitlePicker(() => setDialogState(() {})),
                                ),
                              ),
                              _TvPlaybackSettingsRow(
                                icon: Icons.aspect_ratio_rounded,
                                title: 'Video size',
                                value: _videoSize,
                                onPressed: () => unawaited(
                                  _showVideoSizePicker(() => setDialogState(() {})),
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
                                      _autoplayNextEpisode = !_autoplayNextEpisode;
                                      _controlsVisible = true;
                                    });
                                    setDialogState(() {});
                                    _showFeedback(
                                      Icons.playlist_play_rounded,
                                      _autoplayNextEpisode ? 'Auto next on' : 'Auto next off',
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
  }

  KeyEventResult _focusPlaybackControl(TraversalDirection direction) {
    _showControls();
    final focused = FocusManager.instance.primaryFocus;
    if (direction == TraversalDirection.up) {
      if (focused == _progressFocusNode) {
        _sourcesFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (focused == _sourcesFocusNode || focused == _settingsFocusNode || focused == _lockFocusNode) {
        _playFocusNode.requestFocus();
      } else if (focused == _skipBackFocusNode || focused == _skipForwardFocusNode) {
        _backFocusNode.requestFocus();
      } else {
        _backFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (direction == TraversalDirection.down) {
      if (focused == _backFocusNode) {
        _playFocusNode.requestFocus();
      } else if (focused == _playFocusNode || focused == _skipBackFocusNode || focused == _skipForwardFocusNode) {
        _sourcesFocusNode.requestFocus();
      } else if (focused == _sourcesFocusNode || focused == _settingsFocusNode || focused == _lockFocusNode) {
        _progressFocusNode.requestFocus();
      } else {
        _sourcesFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handlePlaybackKey(KeyEvent event) {
    final key = event.logicalKey;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_locked && key != LogicalKeyboardKey.select && key != LogicalKeyboardKey.enter) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return _focusPlaybackControl(TraversalDirection.up);
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return _focusPlaybackControl(TraversalDirection.down);
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
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
          SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
          SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                _closePlayback();
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
              animation: _controller,
              builder: (context, _) {
                final value = _controller.value;
                final initialized = value.isInitialized;
                final feedback = _feedback;
                _maybeAutoNextEpisode(value);
                return Stack(
                  children: [
                    Center(
                      child: _videoSurface(value),
                    ),
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
                    if (_controlsVisible && !_locked && feedback?.seeking != true && !_switchingSource)
                              _TvPlaybackCenterControls(
                                initialized: initialized,
                                playing: value.isPlaying,
                                skipBackFocusNode: _skipBackFocusNode,
                                playFocusNode: _playFocusNode,
                                skipForwardFocusNode: _skipForwardFocusNode,
                                onTogglePlay: _togglePlay,
                                onSeekBack: () => _skipBy(const Duration(seconds: -15), direction: -1),
                                onSeekForward: () => _skipBy(_seekStep, direction: 1),
                      ),
                    if (feedback != null) _TvPlaybackFeedbackOverlay(feedback: feedback),
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
                                showNextEpisode: widget.settings.nextEpisode &&
                                    (widget.item.type == 'series' || widget.item.type == 'animation'),
                                nextEpisodeLabel: 'Next episode',
                                backFocusNode: _backFocusNode,
                                onBack: _closePlayback,
                                onNextEpisode: _openNextEpisode,
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
                                showAdvancedControls: widget.settings.advancedControls,
                              ),
                              const SizedBox(height: 14),
                              _TvPlaybackTransportHud(
                                initialized: initialized,
                                position: value.position,
                                duration: value.duration,
                                focusNode: _progressFocusNode,
                                onSeekBack: () => _fastSeekBy(Duration(seconds: -_fastSeekStep.inSeconds), direction: -1),
                                onSeekForward: () => _fastSeekBy(_fastSeekStep, direction: 1),
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
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _TvFocusable(
        onPressed: onPressed,
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
                Icon(icon, color: selected ? Colors.black : _tvAccentColor, size: 25),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0x22000000) : const Color(0x24FFFFFF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected ? const Color(0x22000000) : const Color(0x22FFFFFF),
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

class _TvPlaybackChoiceDialog extends StatelessWidget {
  const _TvPlaybackChoiceDialog({
    required this.title,
    required this.selected,
    required this.choices,
  });

  final String title;
  final String selected;
  final List<_TvPlaybackChoice> choices;

  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.only(top: 8, right: 58),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 22),
                  for (final choice in choices)
                    _TvPlaybackSettingsRow(
                      icon: choice.label == selected ? Icons.check_circle_rounded : choice.icon,
                      title: choice.label,
                      value: choice.label == selected ? 'Active' : '',
                      selected: choice.label == selected,
                      onPressed: () => Navigator.of(context).pop(choice.label),
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
    required this.onBack,
    required this.onNextEpisode,
  });

  final String title;
  final bool showNextEpisode;
  final String nextEpisodeLabel;
  final FocusNode backFocusNode;
  final VoidCallback onBack;
  final VoidCallback onNextEpisode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TvTextButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back',
          focusNode: backFocusNode,
          onPressed: onBack,
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
                    onPressed: onNextEpisode,
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
  const _TvSeekPulse({
    super.key,
    required this.icon,
    required this.seeking,
  });

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
  const _TvSkipPulse({
    required this.direction,
    required this.label,
  });

  final int direction;
  final String label;

  @override
  State<_TvSkipPulse> createState() => _TvSkipPulseState();
}

class _TvSkipPulseState extends State<_TvSkipPulse> with SingleTickerProviderStateMixin {
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
                turns: Tween<double>(
                  begin: reverse ? 0.0 : 0.0,
                  end: reverse ? -1.0 : 1.0,
                ).animate(
                  CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
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
                  icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  label: playing ? 'Pause' : 'Play',
                  size: 96,
                  accent: true,
                  focusNode: playFocusNode,
                  autofocus: true,
                  onPressed: initialized ? () => unawaited(onTogglePlay()) : null,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _TvPlaybackSkipButton(
                  direction: 1,
                  label: 'Forward 15 seconds',
                  size: 72,
                  focusNode: skipForwardFocusNode,
                  onPressed: initialized ? () => unawaited(onSeekForward()) : null,
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
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            _formatDuration(position),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
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
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
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
  State<_TvPlaybackProgressScrubber> createState() => _TvPlaybackProgressScrubberState();
}

class _TvPlaybackProgressScrubberState extends State<_TvPlaybackProgressScrubber> {
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
    if (_holdDirection == direction && (_holdSeekDelayTimer != null || _holdSeekTimer != null)) return;
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
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _stopHoldSeek();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
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

class _TvPlaybackSkipButtonState extends State<_TvPlaybackSkipButton> with SingleTickerProviderStateMixin {
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
                    turns: Tween<double>(begin: 0, end: reverse ? -1 : 1).animate(
                      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
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


