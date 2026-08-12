import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;
  late String routeStartupSource;
  late String modelsSource;
  late String hlsRelaySource;
  late String relayTransportSource;
  late String flutterVlcPlayerWidgetSource;
  late String flutterVlcPlayerAndroidSource;
  late String flutterVlcPlayerBuilderSource;
  late String flutterVlcPlayerFactorySource;
  late String vlcSurfaceViewSource;
  late String media3PlayerViewSource;
  late String detailsSource;
  late String nativePlayerState;
  late String adapter;
  late String handleControllerChanged;
  late String dispose;
  late String pageDispose;
  late String closeCoordinatorSession;
  late String openSource;
  late String openLibVlcSourceWithCoordinator;
  late String confirmResumePlayback;
  late String handleMobileLibVlcCoordinatorRecovered;
  late String handleMobileLibVlcCoordinatorFailure;
  late String bestKnownProgressPosition;
  late String subtitlePlaybackPosition;
  late String seekBy;
  late String seekControllerToPlaybackPosition;
  late String reopenMobileLibVlcAt;
  late String adoptMobileLibVlcTransport;
  late String resetLibVlcContinuousTsProof;
  late String libVlcContinuousTsLocalSeekPosition;
  late String switchMobileLibVlcSelection;
  late String saveNativeProgress;
  late String showQualitySheet;
  late String showSourceSheet;
  late String build;

  setUpAll(() {
    source = File('lib/src/native_player_page.dart').readAsStringSync();
    routeStartupSource =
        File('lib/src/mobile_playback_route_startup.dart').readAsStringSync();
    modelsSource = File('lib/src/mobile_libvlc_models.dart').readAsStringSync();
    hlsRelaySource = File('lib/src/libvlc_hls_relay.dart').readAsStringSync();
    relayTransportSource =
        File('lib/src/mobile_libvlc_relay_transport.dart').readAsStringSync();
    flutterVlcPlayerWidgetSource = File(
      'local_plugins/flutter_vlc_player/lib/src/flutter_vlc_player.dart',
    ).readAsStringSync();
    flutterVlcPlayerAndroidSource = File(
      'local_plugins/flutter_vlc_player/android/src/main/java/'
      'software/solid/fluttervlcplayer/FlutterVlcPlayer.java',
    ).readAsStringSync();
    flutterVlcPlayerBuilderSource = File(
      'local_plugins/flutter_vlc_player/android/src/main/java/'
      'software/solid/fluttervlcplayer/FlutterVlcPlayerBuilder.java',
    ).readAsStringSync();
    flutterVlcPlayerFactorySource = File(
      'local_plugins/flutter_vlc_player/android/src/main/java/'
      'software/solid/fluttervlcplayer/FlutterVlcPlayerFactory.java',
    ).readAsStringSync();
    vlcSurfaceViewSource = File(
      'local_plugins/flutter_vlc_player/android/src/main/java/'
      'software/solid/fluttervlcplayer/VLCTextureView.java',
    ).readAsStringSync();
    media3PlayerViewSource = File(
      'android/app/src/main/kotlin/app/juicr/flutter/'
      'JuicrMedia3PlayerView.kt',
    ).readAsStringSync();
    detailsSource = File('lib/src/details_page.dart').readAsStringSync();
    nativePlayerState = _classBody(source, '_NativePlayerPageState');
    adapter = _classBody(source, '_MobileLibVlcDriverAdapter');
    handleControllerChanged = _methodBody(adapter, '_handleControllerChanged');
    dispose = _methodBody(adapter, 'dispose');
    pageDispose = _methodBody(nativePlayerState, 'dispose');
    closeCoordinatorSession = _methodBody(
      nativePlayerState,
      '_closeMobileLibVlcCoordinatorSession',
    );
    openSource = _methodBody(nativePlayerState, '_openSource');
    openLibVlcSourceWithCoordinator = _methodBody(
      nativePlayerState,
      '_openLibVlcSourceWithCoordinator',
    );
    confirmResumePlayback = _methodBody(
      nativePlayerState,
      '_confirmResumePlayback',
    );
    handleMobileLibVlcCoordinatorRecovered = _methodBody(
      nativePlayerState,
      '_handleMobileLibVlcCoordinatorRecovered',
    );
    handleMobileLibVlcCoordinatorFailure = _methodBody(
      nativePlayerState,
      '_handleMobileLibVlcCoordinatorFailure',
    );
    bestKnownProgressPosition = _methodBody(
      nativePlayerState,
      '_bestKnownProgressPosition',
    );
    subtitlePlaybackPosition = _methodBody(
      nativePlayerState,
      '_subtitlePlaybackPosition',
    );
    seekBy = _methodBody(nativePlayerState, '_seekBy');
    seekControllerToPlaybackPosition = _methodBody(
      nativePlayerState,
      '_seekControllerToPlaybackPosition',
    );
    reopenMobileLibVlcAt = _methodBody(
      nativePlayerState,
      '_reopenMobileLibVlcAt',
    );
    adoptMobileLibVlcTransport = _methodBody(
      nativePlayerState,
      '_adoptMobileLibVlcTransport',
    );
    resetLibVlcContinuousTsProof = _methodBody(
      nativePlayerState,
      '_resetLibVlcContinuousTsProof',
    );
    libVlcContinuousTsLocalSeekPosition = _methodBody(
      nativePlayerState,
      '_libVlcContinuousTsLocalSeekPosition',
    );
    switchMobileLibVlcSelection = _methodBody(
      nativePlayerState,
      '_switchMobileLibVlcSelection',
    );
    saveNativeProgress = _methodBody(
      nativePlayerState,
      '_saveNativeProgress',
    );
    showQualitySheet = _methodBody(
      nativePlayerState,
      '_showQualitySheet',
    );
    showSourceSheet = _methodBody(nativePlayerState, '_showSourceSheet');
    build = _methodBody(nativePlayerState, 'build');
  });

  test('auth-rejected startup publishes truthful fresh-source state', () {
    expect(
      source,
      contains('_showMobileLibVlcFindingAnotherSourceStatus()'),
    );
    expect(
      nativePlayerState,
      contains("const status = 'Finding another playable stream...'"),
    );
  });

  test(
    'Media3 resume keeps a lower HLS rendition after higher access failures',
    () {
      expect(
        source,
        contains('_routeHlsProviderAccessFailures[providerKey] ?? 0'),
      );
      expect(source, contains('providerAccessFailures >= 2'));
      expect(
        source,
        contains('reason=higher_renditions_unreadable'),
      );
      expect(
        source.indexOf('providerAccessFailures >= 2'),
        lessThan(source.indexOf('remainingProviders < 2')),
      );
    },
  );

  test('fresh libVLC session preserves launch rejection ownership', () {
    expect(
      source,
      isNot(contains('_resetLibVlcCircuitsForFreshSources')),
    );
    expect(
      source,
      contains('rejectedTransportSessions: _libVlcLaunchRejectionCircuit'),
    );
    expect(
      source,
      contains('.rejectedSessionsFor(_libVlcLaunchGeneration)'),
    );
    expect(
      source,
      contains('rejectedRenditionHeightsByScope.remove('),
    );
    expect(
      source,
      contains('_mobileLibVlcRenditionScope(candidate, freshSource)'),
    );
  });

  test('native player imports the libVLC lifecycle modules', () {
    expect(source, contains("import 'mobile_libvlc_coordinator.dart';"));
    expect(source, contains("import 'mobile_libvlc_models.dart';"));
    expect(source, contains("import 'mobile_libvlc_relay_transport.dart';"));
  });

  test('explicit libVLC transport ordering covers every playback entry path',
      () {
    final initState = _methodBody(nativePlayerState, 'initState');
    final openLibVlcSourceWithCoordinator = _methodBody(
      nativePlayerState,
      '_openLibVlcSourceWithCoordinator',
    );
    final tryFreshRouteResolve = _methodBody(
      nativePlayerState,
      '_tryFreshRouteResolve',
    );
    final openNextEpisodeInPlace = _methodBody(
      nativePlayerState,
      '_openNextEpisodeInPlace',
    );
    final normalizedNativePlayerState = _normalizeCode(nativePlayerState);

    for (final entryPath in <String>[
      initState,
      openLibVlcSourceWithCoordinator,
      tryFreshRouteResolve,
      openNextEpisodeInPlace,
    ]) {
      expect(
        entryPath,
        contains('mobilePrioritizeExplicitLibVlcRequestsByTransport('),
      );
      expect(entryPath, contains('explicitLibVlc: _manualLibVlcConfigured'));
    }
    expect(
      normalizedNativePlayerState,
      contains(
        'prepared = mobilePrioritizeExplicitLibVlcSourcesByTransport( '
        'prepared,',
      ),
    );
    expect(
      normalizedNativePlayerState,
      contains(
        'explicitLibVlc: engine == _NativePlaybackEngine.libvlc && '
        '_manualLibVlcConfigured',
      ),
    );
  });

  test('verified libVLC MP4 uses the bounded early fallback partition', () {
    final normalizedNativePlayerState = _normalizeCode(nativePlayerState);

    expect(
      normalizedNativePlayerState,
      contains(
        'final libVlcVerifiedMp4EarlyFallback = '
        'mobileVerifiedLibVlcMp4CanUseEarlyFallback(',
      ),
    );
    expect(
      normalizedNativePlayerState,
      contains(
        'if (libVlcVerifiedMp4EarlyFallback) { '
        'DiagnosticLog.add(',
      ),
    );
    expect(
      normalizedNativePlayerState,
      contains('reason=libvlc_verified_mp4_after_fresh_sample'),
    );
    expect(
      normalizedNativePlayerState,
      contains('earlyFallback.add(request); continue;'),
    );
  });

  test('active relay transport scopes configured headers to the upstream host',
      () {
    expect(
      relayTransportSource,
      contains('limitHeadersToUpstreamOrigin: true'),
    );
  });

  test('continuous-TS coordinator startup receives the relay-safe budget', () {
    final timeoutBody = _methodBody(
      nativePlayerState,
      '_sourceInitializeTimeout',
    );
    expect(
      timeoutBody,
      contains('_canUseLibVlcHlsRelaySource(source, engine)'),
    );
    expect(timeoutBody, contains('reason=libvlc_continuous_ts_relay'));
    expect(timeoutBody, contains('Duration(seconds: 40)'));
  });

  test('direct libVLC VOD startup keeps the TV lifecycle budget', () {
    final timeoutBody = _methodBody(
      nativePlayerState,
      '_sourceInitializeTimeout',
    );
    expect(
      timeoutBody,
      contains('engine == _NativePlaybackEngine.libvlc'),
    );
    expect(
      timeoutBody,
      contains('!_isHlsSource(source)'),
    );
    expect(
      timeoutBody,
      contains('seconds = math.max(seconds, 24);'),
    );
    expect(
      timeoutBody,
      contains('reason=libvlc_tv_parity_direct_vod'),
    );
  });

  test('driver adapter is libVLC-only and publishes before initialization', () {
    expect(
      source,
      contains(
        'class _MobileLibVlcDriverAdapter implements MobileLibVlcDriver',
      ),
    );
    expect(adapter, contains('engine: _NativePlaybackEngine.libvlc'));
    expect(adapter, contains('onControllerReady(_controller);'));
    expect(
      adapter.indexOf('onControllerReady(_controller);'),
      lessThan(adapter.indexOf('Future<void> initialize()')),
    );

    expect(adapter, isNot(contains('_NativePlaybackEngine.exoplayer')));
    expect(adapter, isNot(contains('_Media3NativePlayerController')));
    expect(adapter, isNot(contains('VideoPlayerController')));
    expect(adapter, isNot(contains('media3')));
  });

  test('driver uses one TV-style libVLC option profile', () {
    expect(
      source,
      contains(
        'const _LibVlcProfile _mobileLibVlcDriverProfile = _LibVlcProfile(',
      ),
    );
    expect(adapter, contains('libVlcProfile: _mobileLibVlcDriverProfile'));
    expect(adapter, contains('libVlcContinuousTsMode: false'));
  });

  test('relay drivers own timeline translation for seeks and lead telemetry',
      () {
    final normalizedOpen = _normalizeCode(openLibVlcSourceWithCoordinator);
    expect(
      modelsSource,
      contains('final class MobileLibVlcSessionTimeline'),
    );
    expect(adapter, contains('required MobileLibVlcSessionTimeline? timeline'));
    expect(adapter, contains('_timeline?.recordDriverPosition('));
    expect(
      adapter,
      contains(
        'final driverPosition = '
        '_timeline?.localSeekPosition(position) ?? position;',
      ),
    );
    expect(
      normalizedOpen,
      contains(
        'final sessionTimelines = '
        '<String, MobileLibVlcSessionTimeline>{};',
      ),
    );
    expect(
      normalizedOpen,
      contains('timeline: usesRelay ? sessionTimeline : null'),
    );
    expect(
      normalizedOpen,
      contains(
        'currentPlaybackPosition: () => '
        'sessionTimeline.absolutePlaybackPosition',
      ),
    );
    expect(
      normalizedOpen,
      contains('sessionTimeline.recordTimelineOffset(offset);'),
    );
  });

  test('decoded-frame probe is opt-in and observes libVLC pixels', () {
    expect(
      source.replaceAll('\r\n', '\n'),
      contains(
        "bool.fromEnvironment(\n"
        "  'JUICR_LIBVLC_FRAME_PROBE',\n"
        "  defaultValue: false,\n"
        ')',
      ),
    );
    expect(adapter, contains('_probeDecodedFrame(controller)'));
    expect(adapter, contains('vlcController.takeSnapshot()'));
    expect(adapter, contains("? 'baseline'"));
    expect(adapter, contains("? 'unchanged'"));
    expect(adapter, contains(": 'changed'"));
    expect(adapter, contains('state=\$state'));
    expect(adapter, contains('state=empty'));
    expect(
      adapter,
      contains('if (!_libVlcDecodedFrameProbeEnabled || _disposed) return;'),
    );
  });

  test('snapshot visual evidence requires advancing initialized geometry', () {
    const proofFlagDeclaration =
        'bool _hasObservedAdvancingVisualFrame = false;';
    const proofAssignment = '_hasObservedAdvancingVisualFrame = true;';
    final normalizedAdapter = _normalizeCode(adapter);
    final proofFlagOccurrences = RegExp(
      r'\b_hasObservedAdvancingVisualFrame\b',
    ).allMatches(adapter).toList();
    final declarationRoles = RegExp(
      r'\bbool\s+(_hasObservedAdvancingVisualFrame)\s*=\s*false\s*;',
    ).allMatches(adapter).toList();
    final guardedAssignmentRoles = RegExp(
      r'\b(_hasObservedAdvancingVisualFrame)\s*=\s*true\s*;',
    ).allMatches(adapter).toList();
    final snapshotReadRoles = RegExp(
      r'\bhasUsableVideoFrame\s*:\s*'
      r'(_hasObservedAdvancingVisualFrame)\s*,',
    ).allMatches(adapter).toList();
    expect(declarationRoles, hasLength(1));
    expect(guardedAssignmentRoles, hasLength(1));
    expect(snapshotReadRoles, hasLength(1));
    final intendedRoleOffsets = <int>[
      _identifierOffset(declarationRoles.single),
      _identifierOffset(guardedAssignmentRoles.single),
      _identifierOffset(snapshotReadRoles.single),
    ]..sort();
    expect(
      proofFlagOccurrences.map((match) => match.start).toList(),
      intendedRoleOffsets,
    );
    expect(_occurrences(normalizedAdapter, proofFlagDeclaration), 1);
    expect(_occurrences(adapter, proofAssignment), 1);

    final geometryExpression = _initializerExpression(
      handleControllerChanged,
      'hasInitializedVideoGeometry',
    );
    expect(
      _normalizeCode(geometryExpression),
      'controller.isInitialized && controller.size.width > 0 && '
      'controller.size.height > 0',
    );

    final proofCondition = _guardConditionForStatement(
      handleControllerChanged,
      proofAssignment,
    );
    expect(
      _normalizeCode(proofCondition),
      'controller.isPlaying && hasInitializedVideoGeometry && '
      'controller.position > _lastObservedPosition',
    );
    expect(
      _normalizeCode(
        _guardBodyForStatement(
          handleControllerChanged,
          proofAssignment,
        ),
      ),
      proofAssignment,
    );

    final normalizedHandler = _normalizeCode(handleControllerChanged);
    expect(normalizedHandler, isNot(contains('||')));
    for (final forbiddenNegation in const [
      '!controller.isPlaying',
      'controller.isPlaying == false',
      '!hasInitializedVideoGeometry',
      'hasInitializedVideoGeometry == false',
      '!(controller.position > _lastObservedPosition)',
      'controller.position <= _lastObservedPosition',
    ]) {
      expect(normalizedHandler, isNot(contains(forbiddenNegation)));
    }
    expect(
      _normalizeCode(
        _namedArgumentExpression(
          handleControllerChanged,
          'hasUsableVideoFrame',
        ),
      ),
      '_hasObservedAdvancingVisualFrame',
    );
  });

  test('driver delegates the existing playback settings', () {
    expect(adapter, contains('await _controller.setVolume(_volume);'));
    expect(
      adapter,
      contains('await _controller.setPlaybackSpeed(_playbackSpeed);'),
    );
    expect(
      adapter,
      contains(
        'await _controller.setVideoSizeMode('
        '_nativeVideoSizeModeFor(_fitMode));',
      ),
    );
  });

  test('driver disposal is guarded and performs each cleanup once', () {
    const guard = 'if (_disposed) return;';
    const markDisposed = '_disposed = true;';
    const removeListener =
        '_controller.removeListener(_handleControllerChanged);';
    const disposeController = 'await _controller.dispose();';
    const closeSnapshots = 'await _snapshots.close();';
    const expectedDispose = 'if (_disposed) return; '
        '_disposed = true; '
        '_controller.removeListener(_handleControllerChanged); '
        'try { await _controller.dispose(); } '
        'finally { await _snapshots.close(); }';
    final normalizedDispose = _normalizeCode(dispose);

    expect(normalizedDispose, expectedDispose);
    expect(_occurrences(normalizedDispose, guard), 1);
    expect(_occurrences(normalizedDispose, markDisposed), 1);
    expect(_occurrences(normalizedDispose, removeListener), 1);
    expect(_occurrences(normalizedDispose, disposeController), 1);
    expect(_occurrences(normalizedDispose, closeSnapshots), 1);
  });

  test('page owns one coordinator and delegates libVLC once at the split', () {
    expect(
      adapter,
      isNot(contains('_retrySourceWithExoPlayerAfterLibVlcFailure')),
    );
    expect(
      RegExp(r'\bMobileLibVlcCoordinator\s*\(').allMatches(source),
      hasLength(1),
    );
    expect(
      _occurrences(
        openSource,
        'return _openLibVlcSourceWithCoordinator(',
      ),
      1,
    );

    final engineSplit = openSource.indexOf(
      'if (attemptedEngine == _NativePlaybackEngine.libvlc)',
    );
    final delegation = openSource.indexOf(
      'return _openLibVlcSourceWithCoordinator(',
    );
    final legacyControllerSource = openSource.indexOf(
      'await _controllerSourceFor(',
    );
    expect(engineSplit, greaterThanOrEqualTo(0));
    expect(delegation, greaterThan(engineSplit));
    expect(legacyControllerSource, greaterThan(delegation));
  });

  test('coordinator helper owns only libVLC driver and relay factories', () {
    expect(openLibVlcSourceWithCoordinator, isNotEmpty);
    expect(
      openLibVlcSourceWithCoordinator,
      contains('MobileLibVlcCoordinator('),
    );
    expect(openLibVlcSourceWithCoordinator, contains('driverFactory:'));
    expect(openLibVlcSourceWithCoordinator, contains('transportFactory:'));
    expect(
      openLibVlcSourceWithCoordinator,
      contains('_MobileLibVlcDriverAdapter('),
    );
    expect(
      openLibVlcSourceWithCoordinator,
      contains('MobileLibVlcRelayTransport.start('),
    );
    expect(
      openLibVlcSourceWithCoordinator,
      isNot(contains('_Media3NativePlayerController')),
    );
    expect(
      openLibVlcSourceWithCoordinator,
      isNot(contains('VideoPlayerController')),
    );
    expect(
      openLibVlcSourceWithCoordinator,
      isNot(contains('_NativePlaybackEngine.exoplayer')),
    );
    expect(
      openLibVlcSourceWithCoordinator,
      isNot(contains('_retrySourceWithExoPlayerAfterLibVlcFailure')),
    );
    expect(
      openLibVlcSourceWithCoordinator,
      isNot(contains('_lastOpenFailureMessage = error.message')),
    );
    expect(
      openLibVlcSourceWithCoordinator,
      isNot(contains('attemptedCandidateIds')),
    );

    final transportFactory =
        openLibVlcSourceWithCoordinator.indexOf('transportFactory:');
    final clearRelaySnapshot = openLibVlcSourceWithCoordinator.indexOf(
      '_mobileLibVlcRelayActive = false;',
      transportFactory,
    );
    final nullableTransportGuard = openLibVlcSourceWithCoordinator.indexOf(
      'if (source == null) {',
      transportFactory,
    );
    expect(clearRelaySnapshot, greaterThan(transportFactory));
    expect(nullableTransportGuard, greaterThan(clearRelaySnapshot));
  });

  test('coordinator honors the bounded direct-HLS diagnostic switch', () {
    final normalizedHelper = _normalizeCode(
      openLibVlcSourceWithCoordinator,
    );
    expect(
      normalizedHelper,
      contains(
        'requiresTransport: !widget.liveMode && '
        '_isHlsSource(candidateSource) && '
        '_libVlcContinuousTsRelayEnabled',
      ),
    );
    expect(
      normalizedHelper,
      contains(
        'if (!candidate.requiresTransport) {',
      ),
    );
  });

  test('libVLC startup emits fixed candidate-to-native handoff stages', () {
    for (final stage in const <String>[
      'candidate_selected',
      'preflight_succeeded',
      'relay_transport_start',
      'native_driver_handoff',
      'coordinator_open_start',
    ]) {
      expect(
        nativePlayerState,
        contains("_recordLibVlcStartupStage('$stage');"),
      );
    }
  });

  test('libVLC open captures route-owner attempt ownership before callbacks',
      () {
    final openStart =
        source.indexOf('Future<bool> _openLibVlcSourceWithCoordinator(');
    final openEnd = source.indexOf('Future<bool> _openSource(', openStart);
    final open = source.substring(openStart, openEnd);
    final normalizedOpen = _normalizeCode(open);
    final generationStart = source.indexOf(
      'void _beginLibVlcLaunchGeneration({required String reason})',
    );
    final generationEnd = source.indexOf(
        'Future<bool> _tryFreshProviderResolve(', generationStart);
    final generation = source.substring(generationStart, generationEnd);

    expect(generation, contains('_openingSourceToken += 1;'));
    expect(generation.indexOf('_openingSourceToken += 1;'),
        lessThan(generation.indexOf('_routeStartupOwner.dispose();')));
    expect(
        open, contains('final openingRouteStartupOwner = _routeStartupOwner;'));
    expect(open, contains('final openingRouteStartupGeneration ='));
    expect(open, contains('mobileLibVlcOpeningStaleReason('));
    expect(open,
        contains('identical(_routeStartupOwner, openingRouteStartupOwner)'));
    expect(open, contains('openingRouteStartupOwner.ownsAttempt('));
    expect(open, contains('_libVlcSeekOwner ?? _libVlcSourceSwitchOwner'));
    expect(open, contains('openingBudgetOwner.remainingWorkBudget'));
    expect(
        _occurrences(open, 'if (openingIsStale()) {'), greaterThanOrEqualTo(5));
    expect(normalizedOpen,
        contains('await controller.pause(); if (openingIsStale())'));
    expect(normalizedOpen,
        contains('await controller.play(); if (openingIsStale())'));
    expect(open, contains('await DiagnosticLog.markNativeEngineActive('));
  });

  test('libVLC source switch retains the coordinator factory owner', () {
    final start = source.indexOf('Future<bool?> _switchMobileLibVlcSelection(');
    final end = source.indexOf('Future<void> _showQualitySheet(', start);
    final method = source.substring(start, end);
    expect(
        method,
        isNot(contains(
            "_beginLibVlcLaunchGeneration(reason: 'explicit_source_choice')")));
    expect(method, contains('await coordinator.switchSource('));
  });

  test('libVLC transactional reopen reports its exact pre-factory rejection',
      () {
    final openStart = source.indexOf(
      'Future<bool> _openLibVlcSourceWithCoordinator(',
    );
    final openEnd = source.indexOf('Future<bool> _openSource(', openStart);
    final open = source.substring(openStart, openEnd);

    expect(open, contains('reason=opening_stale'));
    expect(open, contains('reason=transport_not_required'));
    expect(open, contains('reason=source_mapping_missing'));
    expect(open, contains('reason=relay_capability_unavailable'));
    for (final reason in const <String>[
      'player_closing',
      'unmounted',
      'route_owner_replaced',
      'route_owner_unavailable',
      'transaction_owner_unavailable',
      'opening_token_replaced',
      'coordinator_replaced',
    ]) {
      expect(routeStartupSource, contains("return '$reason';"));
    }
    expect(open, contains('openingStaleReason()'));
    expect(open, contains('staleBucket='));
    expect(reopenMobileLibVlcAt, contains('_beginLibVlcSeekGeneration()'));
    expect(
      reopenMobileLibVlcAt,
      contains('seekRouteOwner.runWork<MobileLibVlcOpenResult>('),
    );
  });

  test('libVLC source switch owns a fresh post-startup route budget', () {
    final method = _methodBody(
      nativePlayerState,
      '_switchMobileLibVlcSelection',
    );

    expect(method, contains('final switchRouteOwner ='));
    expect(method, contains('_beginLibVlcSourceSwitchGeneration('));
    expect(
      method,
      contains('switchRouteOwner.remainingWorkBudget'),
    );
    expect(method, contains('switchRouteOwner.whenCancelled'));
  });

  test('route terminal invalidates non-libVLC opening before settlement', () {
    final method = _methodBody(
      nativePlayerState,
      '_finishWithNoWorkingSource',
    );

    expect(method, contains('_invalidateOpeningSourceAttempt('));
    expect(
      method.indexOf('_invalidateOpeningSourceAttempt('),
      lessThan(method.indexOf('await _routeStartupOwner.cancelAndSettle();')),
    );
  });

  test('terminal expiry synchronously quarantines a late non-libVLC controller',
      () {
    final invalidator = _methodBody(
      nativePlayerState,
      '_invalidateOpeningSourceAttempt',
    );
    final open = _methodBody(nativePlayerState, '_openSource');
    final normalizedOpen = _normalizeCode(open);

    expect(
        invalidator, contains('_detachControllerUpdateListener(controller);'));
    expect(invalidator, contains('_controller = null;'));
    expect(invalidator, contains('unawaited(controller.dispose());'));
    expect(
      normalizedOpen,
      contains('await _disposeCurrentController( awaitLibVlcRelease: true,'),
    );
    expect(
      normalizedOpen,
      contains(
        'if (_playerClosing || !mounted || openingToken != _openingSourceToken)',
      ),
    );
  });

  test(
      'non-libVLC controller creation rechecks terminal ownership after source await',
      () {
    final open = _normalizeCode(_methodBody(nativePlayerState, '_openSource'));
    expect(
      open,
      contains(
        'final controllerSource = await _controllerSourceFor( source, attemptedEngine, resumePosition: relayResumePosition, ); if (_playerClosing || !mounted || openingToken != _openingSourceToken) { _openingSource = false; return false; } final libVlcContinuousTsMode',
      ),
    );
  });

  test(
      'terminal expiry quarantines late controller callbacks before publication',
      () {
    final terminal = _methodBody(
      nativePlayerState,
      '_finishWithNoWorkingSource',
    );
    final listener = _methodBody(
      nativePlayerState,
      '_attachControllerUpdateListener',
    );
    final handler = _methodBody(nativePlayerState, '_handleControllerUpdate');

    expect(terminal, contains('_terminalOpeningCallbackQuarantined = true;'));
    expect(listener,
        contains('_terminalCallbackGate.permits(callbackGeneration)'));
    expect(handler, contains('if (_playerClosing ||'));
    expect(handler, contains('_terminalOpeningCallbackQuarantined ||'));
  });

  test('libVLC HLS defaults to the TV-style sequential TS relay', () {
    final normalizedSource = _normalizeCode(source);
    final continuousTsHandler = _normalizeCode(
      _methodBody(hlsRelaySource, '_handleContinuousTsRequest'),
    );
    final relayEligibility = _normalizeCode(
      _methodBody(nativePlayerState, '_canUseLibVlcHlsRelaySource'),
    );

    expect(
      normalizedSource,
      contains(
        "const bool _libVlcContinuousTsRelayEnabled = "
        "bool.fromEnvironment( 'JUICR_LIBVLC_CONTINUOUS_TS', "
        'defaultValue: true, );',
      ),
    );
    expect(
      relayEligibility,
      contains('if (!_libVlcContinuousTsRelayEnabled) return false;'),
    );
    expect(
      relayEligibility,
      contains(
          'mobileFirstPartyOpaqueMediaCapability(Uri.tryParse(source.url))'),
    );
    expect(continuousTsHandler, contains('final segmentQueue = List<Uri>.of('));
    expect(
      continuousTsHandler,
      contains('await _readTvSequentialSegment('),
    );
    expect(continuousTsHandler, contains('await _pipeMediaResponse('));
    expect(
      continuousTsHandler,
      contains('final failureLimit = streamedSegments == 0 ? 6 : 12;'),
    );
    expect(hlsRelaySource, contains("context: 'fresh_transport'"));
    expect(hlsRelaySource, contains('useFreshTransport: true'));
    expect(
      hlsRelaySource,
      contains('forceFreshCacheBypass: plan.useFreshTransport'),
    );
    expect(
      continuousTsHandler,
      isNot(contains('_readContinuousTsSegment(')),
    );
    expect(continuousTsHandler, isNot(contains('ensureStartupLead')));
    expect(continuousTsHandler, isNot(contains('pendingSegments')));
    expect(continuousTsHandler, isNot(contains('playlist refresh')));
  });

  test('ordered candidates preserve source request context and identity', () {
    final normalizedHelper = _normalizeCode(
      openLibVlcSourceWithCoordinator,
    );
    expect(
      _occurrences(
        openLibVlcSourceWithCoordinator,
        'MobileLibVlcSourceCandidate(',
      ),
      2,
    );
    for (final preservedField in const [
      'headers: candidateSource.headers',
      'providerId: candidateSource.providerId',
      'mirrorGroup: candidateSource.mirrorGroupId',
      'qualityLabel: _qualityLabel(candidateSource)',
      'audioLanguage: candidateSource.language',
    ]) {
      expect(normalizedHelper, contains(preservedField));
    }
    for (final preservedField in const [
      'headers: freshSource.headers',
      'providerId: freshSource.providerId',
      'mirrorGroup: freshSource.mirrorGroupId',
      'qualityLabel: _qualityLabel(freshSource)',
      'audioLanguage: freshSource.language',
    ]) {
      expect(normalizedHelper, contains(preservedField));
    }
    expect(
      openLibVlcSourceWithCoordinator,
      contains('candidateSources[candidate]'),
    );
  });

  test('candidate mapping retains every source for later manual selection', () {
    final normalized = _normalizeCode(openLibVlcSourceWithCoordinator);
    expect(normalized, contains('final allCandidateEntries ='));
    expect(
      normalized,
      contains(
        'final candidateSources = '
        'Map<MobileLibVlcSourceCandidate, PlaybackSource>.fromEntries(',
      ),
    );
    expect(normalized, contains('allCandidateEntries, );'));
    expect(
      normalized,
      contains('allCandidateEntries .skip(requestedIndex)'),
    );
  });

  test('controller is published before coordinator initialization', () {
    final publishController =
        openLibVlcSourceWithCoordinator.indexOf('_controller = controller;');
    final attachPageListener = openLibVlcSourceWithCoordinator.indexOf(
      '_attachControllerUpdateListener(controller);',
    );
    final attachPlatformView = openLibVlcSourceWithCoordinator.indexOf(
      'setState(() {});',
      attachPageListener,
    );
    final awaitOpen = openLibVlcSourceWithCoordinator.indexOf(
      'final result = await coordinator.open(',
    );

    expect(publishController, greaterThanOrEqualTo(0));
    expect(attachPageListener, greaterThan(publishController));
    expect(attachPlatformView, greaterThan(attachPageListener));
    expect(awaitOpen, greaterThan(attachPlatformView));

    final normalizedHelper = _normalizeCode(
      openLibVlcSourceWithCoordinator,
    );
    expect(
      normalizedHelper,
      contains(
        'if (identical(_controller, publishedController)) { '
        '_controller = null; '
        'final controllerToDetach = publishedController; '
        'if (controllerToDetach != null) { '
        '_detachControllerUpdateListener(controllerToDetach);',
      ),
    );
    expect(
      normalizedHelper.indexOf(
        '_detachControllerUpdateListener(controllerToDetach);',
      ),
      lessThan(normalizedHelper.indexOf('await driver.dispose();')),
    );
  });

  test('temporary libVLC seek controller mounts above the retained surface',
      () {
    final normalized = _normalizeCode(openLibVlcSourceWithCoordinator);
    expect(
      normalized,
      contains(
        'final publishControllerImmediately = '
        'coordinator.currentDriver == null;',
      ),
    );
    expect(
      normalized,
      contains('if (!publishControllerImmediately) {'),
    );
    expect(
      nativePlayerState,
      contains('final Map<int, _NativePlaybackController>'),
    );
    expect(
      normalized,
      contains(
        '_stagedMobileLibVlcControllers[driverGeneration] = controller;',
      ),
    );
    expect(
      normalized,
      contains('volume: publishControllerImmediately ? _volumePreview : 0'),
    );
    final normalizedBuild = _normalizeCode(build);
    final stagedSurface = normalizedBuild.indexOf(
      'for (final surfaceController in mountedLibVlcControllers)',
    );
    final nonLibVlcSurface = normalizedBuild.indexOf(
      'controller.engine != _NativePlaybackEngine.libvlc',
    );
    expect(stagedSurface, greaterThanOrEqualTo(0));
    expect(nonLibVlcSurface, greaterThan(stagedSurface));
    expect(normalizedBuild, contains('_VideoSurface('));
    expect(normalizedBuild, contains('Opacity('));
    expect(
      normalizedBuild,
      contains('if (controller != null && '
          'controller.engine == _NativePlaybackEngine.libvlc && '
          '!stagedControllers.contains(controller)) controller'),
    );
    expect(
      normalizedBuild.indexOf(
        'if (controller != null && '
        'controller.engine == _NativePlaybackEngine.libvlc',
      ),
      lessThan(normalizedBuild.indexOf('...stagedControllers')),
    );
    expect(normalizedBuild, contains(': 0.01'));
    expect(normalizedBuild, contains('ExcludeSemantics('));
    expect(normalizedBuild, contains('IgnorePointer('));
  });

  test('failed or stale candidate removes only its seek generation', () {
    final normalizedOpen = _normalizeCode(openLibVlcSourceWithCoordinator);
    final normalizedReopen = _normalizeCode(reopenMobileLibVlcAt);
    expect(
      normalizedOpen,
      contains(
        '_removeStagedMobileLibVlcController( driverGeneration, '
        'driver.controller, );',
      ),
    );
    expect(
      normalizedReopen,
      contains(
        '_removeStagedMobileLibVlcController( seekGeneration, );',
      ),
    );
    expect(
      normalizedReopen,
      isNot(contains('_stagedMobileLibVlcControllers.clear()')),
    );
  });

  test('proved candidate publishes before coordinator disposes the old owner',
      () {
    final normalized = _normalizeCode(reopenMobileLibVlcAt);
    final promotionHook = normalized.indexOf('onBeforePreviousDispose:');
    final publishCandidate =
        normalized.indexOf('_controller = reopenedController;');
    final awaitCompletion =
        normalized.indexOf('final result = await reopening;');
    expect(promotionHook, greaterThanOrEqualTo(0));
    expect(publishCandidate, greaterThan(promotionHook));
    expect(awaitCompletion, greaterThan(publishCandidate));
    expect(
      normalized.substring(promotionHook, awaitCompletion),
      contains('_removeStagedMobileLibVlcController('),
    );
  });

  test('same-source seek proof is decoded-video and persistence transactional',
      () {
    final normalizedReopen = _normalizeCode(reopenMobileLibVlcAt);
    final normalizedSave = _normalizeCode(saveNativeProgress);
    expect(
      normalizedReopen,
      contains('if (!result.driver.hasVisualProof)'),
    );
    expect(
      normalizedReopen,
      contains('surfaceGeneration='),
    );
    expect(
      normalizedReopen,
      contains('seekSettlementGeneration='),
    );
    expect(
      normalizedSave,
      contains('native progress save deferred reason=seek_candidate_unproved'),
    );
    expect(
      normalizedReopen.indexOf('_mobileLibVlcSeekPreparing = false;'),
      lessThan(normalizedReopen.indexOf('_saveNativeProgress(force: true);')),
    );
  });

  test('ended foreground uses a truthful nonblack seek presentation', () {
    final normalizedReopen = _normalizeCode(reopenMobileLibVlcAt);
    final normalizedBuild = _normalizeCode(build);
    expect(
      nativePlayerState,
      contains('_mobileLibVlcSeekNeedsVisibleFallback'),
    );
    expect(normalizedReopen, contains('controller.isEnded'));
    expect(
      normalizedBuild,
      contains('if (_mobileLibVlcSeekNeedsVisibleFallback)'),
    );
    expect(normalizedBuild, contains('_NativeSeekPreparationSurface('));
  });

  test('rapid seek generations mount only the current candidate surface', () {
    final normalizedBuild = _normalizeCode(build);
    expect(
      normalizedBuild,
      contains('entry.key == _mobileLibVlcCoordinator?.generation'),
    );
    expect(
      normalizedBuild,
      contains('!identical(entry.value, controller)'),
    );
    expect(
      normalizedBuild,
      contains('.map((entry) => entry.value)'),
    );
    expect(
      normalizedBuild,
      contains('.toList(growable: false)'),
    );
  });

  test('seek candidate owns the single visible surface until promotion', () {
    final normalizedBuild = _normalizeCode(build);
    final stagedSurface = normalizedBuild.indexOf(
      'for (final surfaceController in mountedLibVlcControllers)',
    );
    final nonLibVlcSurface = normalizedBuild.indexOf(
      'controller.engine != _NativePlaybackEngine.libvlc',
    );
    expect(stagedSurface, greaterThanOrEqualTo(0));
    expect(nonLibVlcSurface, greaterThan(stagedSurface));
    expect(normalizedBuild, contains('Opacity('));
    expect(normalizedBuild, contains(': 0.01'));
    expect(normalizedBuild, contains('final visibleLibVlcController ='));
    expect(
      normalizedBuild,
      contains('_mobileLibVlcSeekPreparing && stagedControllers.isNotEmpty'),
    );
    expect(
      normalizedBuild,
      contains('identical( surfaceController, visibleLibVlcController, ) '
          '? 1 : 0.01'),
    );
    expect(
      normalizedBuild.substring(stagedSurface, nonLibVlcSurface),
      isNot(contains('_controller =')),
    );
  });

  test('libVLC surfaces keep stable platform composition across generations',
      () {
    final normalizedBuild = _normalizeCode(build);
    final normalizedSurface = _normalizeCode(
      _classBody(source, '_NativePlaybackSurface'),
    );
    expect(
      normalizedBuild,
      isNot(contains('surfaceForeground:')),
    );
    expect(
      normalizedBuild,
      isNot(contains('setLibVlcSurfaceForeground(')),
    );
    expect(normalizedSurface, isNot(contains('surfaceForeground')));
    expect(
      flutterVlcPlayerWidgetSource,
      isNot(contains('surfaceForeground')),
    );
    expect(
      flutterVlcPlayerFactorySource,
      isNot(contains('surfaceForeground')),
    );
  });

  test('native libVLC ownership uses SurfaceView without TextureView fallback',
      () {
    expect(vlcSurfaceViewSource, contains('import android.view.SurfaceView;'));
    expect(
      vlcSurfaceViewSource,
      isNot(contains('import android.view.TextureView;')),
    );
    expect(vlcSurfaceViewSource, isNot(contains('new TextureView(')));
    expect(
      vlcSurfaceViewSource,
      isNot(contains('void setSurfaceForeground(boolean foreground)')),
    );
    expect(
      vlcSurfaceViewSource,
      isNot(contains('videoSurfaceView.setZOrderMediaOverlay(foreground);')),
    );
    expect(vlcSurfaceViewSource, isNot(contains('setZOrderOnTop(true)')));
    expect(
      flutterVlcPlayerAndroidSource,
      isNot(contains('void setSurfaceForeground(boolean foreground)')),
    );
    expect(
      flutterVlcPlayerBuilderSource,
      isNot(contains('flutter_video_plugin/surfaceOwnership')),
    );
  });

  test('proved seek promotion publishes without dynamic SurfaceView ownership',
      () {
    final normalized = _normalizeCode(reopenMobileLibVlcAt);
    final normalizedSource = _normalizeCode(source);
    expect(
      normalizedSource,
      isNot(contains('onCandidateInitialized: (generation) =>')),
    );
    expect(
      normalizedSource,
      isNot(contains('_claimStagedMobileLibVlcSurfaceForProof(')),
    );
    expect(
      normalizedSource,
      isNot(contains('onCandidateRollback: (generation) =>')),
    );
    expect(
      normalizedSource,
      isNot(contains('_restoreRetainedMobileLibVlcSurfaceAfterRollback(')),
    );
    final publish = normalized.indexOf('_controller = reopenedController;');
    expect(publish, greaterThanOrEqualTo(0));
    expect(normalized, isNot(contains('setLibVlcSurfaceForeground(')));
  });

  test('staged libVLC candidate uses the same stable surface composition', () {
    final normalizedSource = _normalizeCode(source);
    expect(
      normalizedSource,
      isNot(contains('surfaceForeground:')),
    );
  });

  test('explicit seek owns generation before staging or visible preparation',
      () {
    final normalized = _normalizeCode(reopenMobileLibVlcAt);
    final settleRecovery = normalized.indexOf(
      'await coordinator.cancelRuntimeRecoveryForExplicitAction(',
    );
    final ownershipCallback = normalized.indexOf('onGenerationOwned:');
    final markPreparing = normalized.indexOf(
      '_mobileLibVlcSeekPreparing = true;',
    );
    final reopen = normalized.indexOf('coordinator.reopenCurrentSourceAt(');
    expect(settleRecovery, greaterThanOrEqualTo(0));
    expect(reopen, greaterThan(settleRecovery));
    expect(ownershipCallback, greaterThan(reopen));
    expect(markPreparing, greaterThan(ownershipCallback));
    expect(
      normalized.substring(ownershipCallback, markPreparing),
      contains('_removeStaleMobileLibVlcSeekSurfaces('),
    );

    final promotionCallback = normalized.indexOf('onBeforePreviousDispose:');
    expect(promotionCallback, greaterThan(markPreparing));
    final generationOwned = normalized.substring(
      ownershipCallback,
      promotionCallback,
    );
    expect(
      generationOwned,
      contains('_mobileLibVlcSeekNeedsVisibleFallback = false;'),
      reason: 'seek staging must not require the full-screen fallback surface',
    );
    expect(
      generationOwned,
      isNot(contains('_mobileLibVlcSeekNeedsVisibleFallback = true;')),
    );
    expect(
      generationOwned,
      isNot(contains('setLibVlcSurfaceForeground(')),
      reason: 'seek staging must not mutate attached SurfaceView Z ordering',
    );

    final promotion = normalized.substring(promotionCallback);
    final publish = promotion.indexOf('_controller = reopenedController;');
    expect(publish, greaterThanOrEqualTo(0));
    expect(promotion, isNot(contains('setLibVlcSurfaceForeground(')));
  });

  test(
      'continuous TS persistence reapplies the absolute floor after near-end cap',
      () {
    final normalized = _normalizeCode(saveNativeProgress);
    final genericCap = normalized.indexOf('_resumeSafeProgressPosition(');
    final absoluteFloor = normalized.indexOf(
      'preserveMobileLibVlcAbsoluteProgressFloor(',
    );
    expect(genericCap, greaterThanOrEqualTo(0));
    expect(absoluteFloor, greaterThan(genericCap));
    expect(
      normalized.substring(genericCap, absoluteFloor),
      contains('savedPosition'),
    );
    expect(
        subtitlePlaybackPosition, contains('_resumeAnchoredPlaybackPosition'));
  });

  test('seek preparation keeps the active video visible under a status overlay',
      () {
    final normalizedBuild = _normalizeCode(build);
    expect(
      normalizedBuild,
      contains('if (_mobileLibVlcSeekPreparing && initialized) '
          '_NativePlaybackStatusOverlay('),
    );
    expect(
      normalizedBuild,
      isNot(contains(
        'if (_mobileLibVlcSeekPreparing && initialized) '
        '_NativeRefreshOverlay(',
      )),
    );
    expect(
      _normalizeCode(reopenMobileLibVlcAt),
      isNot(contains('setLibVlcSurfaceForeground(')),
    );
  });

  test('candidate proof uses one visible keyed libVLC surface slot', () {
    final normalizedBuild = _normalizeCode(build);
    expect(
      normalizedBuild,
      contains('final mountedLibVlcControllers ='),
    );
    expect(
      normalizedBuild,
      contains(
        'for (final surfaceController in mountedLibVlcControllers)',
      ),
    );
    expect(
      normalizedBuild,
      contains(
        'key: ValueKey<int>(identityHashCode(surfaceController))',
      ),
    );
    expect(
      normalizedBuild,
      contains(
        'opacity: identical( surfaceController, visibleLibVlcController, ) '
        '? 1 : 0.01',
      ),
    );
    expect(
      normalizedBuild,
      isNot(contains('for (final stagedController in stagedControllers)')),
    );
  });

  test('same-source seek preparation keeps rapid seek controls mounted', () {
    final normalized = _normalizeCode(source);
    expect(
      source,
      contains('bool _mobileLibVlcSeekPreparing = false;'),
    );
    expect(
      source,
      contains('final seekControlsReady = !_loading || '
          '_mobileLibVlcSeekPreparing;'),
    );
    expect(
      normalized,
      contains(
        'final nativeControlsReady = _nativeControlsReady( controller, '
        'allowSeekPreparation: _mobileLibVlcSeekPreparing, );',
      ),
    );
    expect(
      normalized,
      contains(
        'bool _nativeControlsReady( _NativePlaybackController? controller, { '
        'bool allowSeekPreparation = false, })',
      ),
    );
    expect(
      normalized,
      contains('(_loading && !allowSeekPreparation)'),
    );
    expect(
      normalized,
      contains('_openingSource || _recoveringFromStall ||'),
    );
    expect(
      source,
      contains('if (_loading && initialized && '
          '!_mobileLibVlcSeekPreparing)'),
    );
    expect(
      normalized,
      contains('if (seekControlsReady && _playbackWaitMessage == null'),
    );
    expect(
      source,
      contains('_mobileLibVlcSeekPreparing = true;'),
    );
    expect(
      source,
      contains('_mobileLibVlcSeekPreparing = false;'),
    );
  });

  test('explicit series Continue intent survives a global restart default', () {
    final normalizedNative = _normalizeCode(source);
    final normalizedDetails = _normalizeCode(detailsSource);
    expect(source, contains('this.preferSavedResume = false,'));
    expect(source, contains('final bool preferSavedResume;'));
    expect(
      source,
      contains(
        '_preferSavedResumeOnInitialOpen = widget.preferSavedResume;',
      ),
    );
    expect(
      normalizedNative,
      contains('if (_preferSavedResumeOnInitialOpen) return saved;'),
    );
    expect(
      normalizedNative,
      contains('!_preferSavedResumeOnInitialOpen && startBehavior == \'ask\''),
    );
    expect(
      normalizedNative,
      contains('_preferSavedResumeOnInitialOpen = false;'),
    );
    expect(
      normalizedDetails,
      contains('preferSavedResume: entry != null,'),
    );
    expect(
      RegExp(r'preferSavedResume: preferSavedResume,')
          .allMatches(detailsSource)
          .length,
      greaterThanOrEqualTo(3),
    );
  });

  test('direct MP4 pre-opens from the shared saved progress anchor', () {
    final preOpenResume = _methodBody(
      nativePlayerState,
      '_preOpenPreferredResumePosition',
    );
    final knownMp4Source = _methodBody(
      source,
      'mobileIsKnownDirectMp4Source',
    );
    final normalized = _normalizeCode(preOpenResume);

    expect(
      knownMp4Source,
      contains('source.sourceClass == PlaybackSourceClass.debrid'),
    );
    expect(
      normalized,
      contains(
        'final directMp4 = mobileIsKnownDirectMp4Source(source);',
      ),
    );
    expect(
      normalized,
      contains(
        'directMp4 && (engine == _NativePlaybackEngine.exoplayer || '
        'engine == _NativePlaybackEngine.libvlc)',
      ),
    );
    expect(
      normalized.indexOf('if (!supportsPreOpenResume)'),
      lessThan(normalized.indexOf('if (_preferSavedResumeOnInitialOpen)')),
    );
    expect(
      openLibVlcSourceWithCoordinator,
      contains('anchor: coordinatorAnchor'),
    );
    expect(
      saveNativeProgress,
      contains('reason=resume_seek_pending_progress_guard'),
    );
  });

  test('P2P proves startup before applying the shared saved progress anchor',
      () {
    final preOpenResume = _methodBody(
      nativePlayerState,
      '_preOpenPreferredResumePosition',
    );
    final normalized = _normalizeCode(preOpenResume);

    expect(
      normalized,
      isNot(contains('PlaybackSourceClass.p2p')),
    );
    expect(
      openSource,
      contains(
        'await controller.initialize(timeout: controllerInitializeTimeout);',
      ),
    );
    expect(
      openSource.indexOf('await _resumePositionFor(controller.duration)'),
      greaterThan(
        openSource.indexOf(
          'await controller.initialize(timeout: controllerInitializeTimeout);',
        ),
      ),
    );
    expect(
      openSource,
      contains(
          'initialPosition: attemptedEngine == _NativePlaybackEngine.exoplayer'),
    );
    final delayMedia3Resume = _methodBody(
      nativePlayerState,
      '_shouldDelayMedia3ResumeSeekUntilVisualProof',
    );
    expect(
      delayMedia3Resume,
      contains('source.sourceClass == PlaybackSourceClass.p2p'),
    );
    final playIndex = openSource.indexOf('await controller.play();');
    final media3P2pRestoreIndex = openSource.indexOf(
      '_restoreMedia3P2pResumeAfterProof(',
      playIndex,
    );
    expect(
      playIndex,
      lessThan(media3P2pRestoreIndex),
    );
    final media3P2pRestore = _methodBody(
      nativePlayerState,
      '_restoreMedia3P2pResumeAfterProof',
    );
    final startupProof = media3P2pRestore.indexOf(
      'await _waitForSourceSwitchStartupProof(',
    );
    final warmRange = media3P2pRestore.indexOf(
      'await _warmP2pResumeRange(',
    );
    final resumeSeek = media3P2pRestore.indexOf(
      'await _seekToResumePosition(',
    );
    final resumeProof = media3P2pRestore.indexOf(
      'await _waitForDeferredResumeSeekProof(',
    );
    expect(startupProof, greaterThanOrEqualTo(0));
    expect(warmRange, greaterThan(startupProof));
    expect(resumeSeek, greaterThan(warmRange));
    expect(resumeProof, greaterThan(resumeSeek));
    expect(
      media3P2pRestore,
      contains('action=preserve_resume_anchor'),
    );
  });

  test('libVLC P2P coordinator proves zero startup before resume seek', () {
    final normalized = _normalizeCode(openLibVlcSourceWithCoordinator);
    final coordinatorOpen = normalized.indexOf(
      'final result = await coordinator.open(',
    );
    final resumeResolution = normalized.indexOf(
      'await _resumePositionFor(controller.duration)',
      coordinatorOpen,
    );
    final resumeSeek = resumeResolution < 0
        ? -1
        : normalized.indexOf(
            'await _seekToResumePosition(',
            resumeResolution,
          );
    final deferredRestore = resumeResolution < 0
        ? -1
        : normalized.indexOf(
            '_restoreP2pResumeAfterProof(',
            resumeResolution,
          );
    final resumeProof = resumeSeek < 0
        ? -1
        : normalized.indexOf(
            'await _waitForDeferredResumeSeekProof(',
            resumeSeek,
          );

    expect(
      normalized,
      contains(
        'final deferP2pResumeUntilProof = '
        'source.sourceClass == PlaybackSourceClass.p2p && '
        'resumePosition == null;',
      ),
    );
    expect(
      normalized,
      contains(
        'final coordinatorAnchor = deferP2pResumeUntilProof '
        '? Duration.zero',
      ),
    );
    expect(coordinatorOpen, greaterThanOrEqualTo(0));
    expect(resumeResolution, greaterThan(coordinatorOpen));
    expect(deferredRestore, greaterThan(resumeResolution));
    expect(resumeSeek, -1);
    expect(resumeProof, -1);
    final restoreBody = _methodBody(
      nativePlayerState,
      '_restoreP2pResumeAfterProof',
    );
    expect(restoreBody, contains('await _warmP2pResumeRange('));
    expect(restoreBody, contains('await _seekToResumePosition('));
    expect(restoreBody, contains('await _waitForDeferredResumeSeekProof('));
    expect(restoreBody, contains('action=preserve_resume_anchor'));
  });

  test('proved libVLC source is mounted before the resume prompt', () {
    final coordinatorOpen = openLibVlcSourceWithCoordinator.indexOf(
      'final result = await coordinator.open(',
    );
    final publishSource = openLibVlcSourceWithCoordinator.indexOf(
      '_activeSource = provedSource;',
    );
    final resumePrompt = openLibVlcSourceWithCoordinator.indexOf(
      'final shouldPromptForResume =',
    );

    expect(coordinatorOpen, greaterThanOrEqualTo(0));
    expect(publishSource, greaterThan(coordinatorOpen));
    expect(resumePrompt, greaterThan(publishSource));
  });

  test('shared resume anchor floors ordinary cross-engine progress saves', () {
    final proposedSave = saveNativeProgress.indexOf(
      'var savedPosition = _resumeSafeProgressPosition(',
    );
    final preserveAnchor = saveNativeProgress.indexOf(
      'savedPosition = preserveMobileLibVlcAnchor(',
    );
    final persistProgress = saveNativeProgress.indexOf(
      'AppState.setPlaybackProgress(',
    );

    expect(proposedSave, greaterThanOrEqualTo(0));
    expect(preserveAnchor, greaterThan(proposedSave));
    expect(persistProgress, greaterThan(preserveAnchor));
    expect(
      saveNativeProgress.substring(preserveAnchor, persistProgress),
      contains('current: _resumeProgressAnchorPosition'),
    );
    expect(
      saveNativeProgress.substring(preserveAnchor, persistProgress),
      contains('explicitSeek: false'),
    );
  });

  test('libVLC coordinator installs the shared anchor before startup callbacks',
      () {
    final anchorGuard = openLibVlcSourceWithCoordinator.indexOf(
      'if (protectedResumeAnchor > Duration.zero || explicitStartOver)',
    );
    final installAnchor = openLibVlcSourceWithCoordinator.indexOf(
      '_resumeProgressAnchorPosition = preserveMobileLibVlcAnchor(',
      anchorGuard,
    );
    final coordinatorOpen = openLibVlcSourceWithCoordinator.indexOf(
      'final result = await coordinator.open(',
    );

    expect(anchorGuard, greaterThanOrEqualTo(0));
    expect(installAnchor, greaterThan(anchorGuard));
    expect(coordinatorOpen, greaterThan(installAnchor));
  });

  test('decoder keyframe preroll cannot release the shared resume floor', () {
    final resumeAnchoredPosition = _methodBody(
      nativePlayerState,
      '_resumeAnchoredPlaybackPosition',
    );
    final normalized = _normalizeCode(resumeAnchoredPosition);

    expect(
      normalized,
      contains(
        'if (controllerPosition >= _resumeProgressAnchorPosition) { '
        '_resumeProgressAnchorPosition = Duration.zero;',
      ),
    );
    expect(
      normalized,
      contains(
        'if (controllerPosition >= _resumeProgressAnchorPosition - '
        'const Duration(seconds: 10)) { return _resumeProgressAnchorPosition;',
      ),
    );
  });

  test('same-source seek transport adoption preserves settlement generation',
      () {
    expect(
      _normalizeCode(resetLibVlcContinuousTsProof),
      contains(
        'if (!preserveSeekSettlement) { '
        '_libVlcSeekSettlementBarrier.clear();',
      ),
    );
    expect(
      _normalizeCode(adoptMobileLibVlcTransport),
      contains(
        '_resetLibVlcContinuousTsProof( '
        'preserveSeekSettlement: preserveSeekSettlement, );',
      ),
    );
    expect(
      _normalizeCode(reopenMobileLibVlcAt),
      contains('preserveSeekSettlement: true'),
    );
  });

  test('temporary relay callbacks are staged until switch proof', () {
    final normalized = _normalizeCode(openLibVlcSourceWithCoordinator);
    expect(
      normalized,
      contains(
        'final stagedTransportMetadata = preparingSwitch '
        '? _StagedMobileLibVlcTransportMetadata() '
        ': null;',
      ),
    );
    expect(
      normalized,
      contains(
        '_stagedMobileLibVlcTransportMetadata[stagedTransportKey] = '
        'stagedTransportMetadata;',
      ),
    );
    expect(
      switchMobileLibVlcSelection,
      contains('_applyStagedMobileLibVlcTransportMetadata('),
    );
  });

  test(
      'rejected HLS renditions downshift within the current libVLC source session',
      () {
    final normalized = _normalizeCode(openLibVlcSourceWithCoordinator);

    expect(
      normalized,
      contains(
        'final rejectedRenditionHeightsByScope = <String, Set<int>>{};',
      ),
    );
    expect(
      normalized,
      contains(
        'final renditionScope = '
        '_mobileLibVlcRenditionScope(candidate, source);',
      ),
    );
    expect(
      normalized,
      contains(
        'excludedHeights: rejectedRenditionHeightsByScope[renditionScope] '
        '?? const <int>{},',
      ),
    );
    expect(
      normalized,
      contains(
        'rejectedRenditionHeightsByScope '
        '.putIfAbsent(renditionScope, () => <int>{}) '
        '.add(failedHeight);',
      ),
    );
    expect(
      nativePlayerState,
      contains('String _mobileLibVlcRenditionScope('),
    );
  });

  test('proved result publishes source and ready state before subtitles', () {
    final awaitOpen = openLibVlcSourceWithCoordinator.indexOf(
      'final result = await coordinator.open(',
    );
    final publishActiveSource = openLibVlcSourceWithCoordinator.indexOf(
      '_activeSource = provedSource;',
    );
    final clearLoading = openLibVlcSourceWithCoordinator.indexOf(
      '_loading = false;',
    );
    final startWatchdog =
        openLibVlcSourceWithCoordinator.indexOf('_startStallWatchdog();');
    final startSubtitles =
        openLibVlcSourceWithCoordinator.indexOf('_ensureSubtitlesLoading();');

    expect(awaitOpen, greaterThanOrEqualTo(0));
    expect(publishActiveSource, greaterThan(awaitOpen));
    expect(clearLoading, greaterThan(awaitOpen));
    expect(startWatchdog, greaterThan(clearLoading));
    expect(startSubtitles, greaterThan(clearLoading));
  });

  test('proved libVLC startup hands runtime health to the coordinator', () {
    final normalizedOpen = openLibVlcSourceWithCoordinator.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final awaitOpen = openLibVlcSourceWithCoordinator.indexOf(
      'final result = await coordinator.open(',
    );
    final startMonitoring = openLibVlcSourceWithCoordinator.indexOf(
      'coordinator.startHealthMonitoring(',
    );

    expect(awaitOpen, greaterThanOrEqualTo(0));
    expect(startMonitoring, greaterThan(awaitOpen));
    expect(
      normalizedOpen,
      contains(
        'onRecovered: (result) => '
        '_handleMobileLibVlcCoordinatorRecovered(coordinator, result)',
      ),
    );
    expect(
      normalizedOpen,
      contains(
        'onTerminalFailure: (failure) => '
        '_handleMobileLibVlcCoordinatorFailure(coordinator, failure)',
      ),
    );
  });

  test(
      'libVLC recovery resolves fresh sessions instead of replaying startup candidates',
      () {
    final normalizedOpen = _normalizeCode(openLibVlcSourceWithCoordinator);

    expect(
      normalizedOpen,
      isNot(contains('freshResolver: () async => candidates')),
    );
    expect(normalizedOpen, contains('currentRefresher:'));
    expect(
      normalizedOpen,
      contains('_runCancelableProviderWork<List<PlaybackSource>>('),
    );
    expect(
      normalizedOpen,
      contains('_resolveRecoveryProvider(providerId, cancellation)'),
    );
    expect(
      normalizedOpen,
      isNot(contains('_resolveRecoveryProvider(providerId).timeout(')),
    );
    expect(normalizedOpen, contains('_resolveFreshRequests'));
    expect(
      normalizedOpen,
      contains('_mobileLibVlcCandidateSources?[candidate] = freshSource'),
    );
  });

  test(
      'fresh libVLC recovery source joins the visible source pool only after proof',
      () {
    expect(
      handleMobileLibVlcCoordinatorRecovered,
      contains('_activeSources = <PlaybackSource>['),
    );
    expect(
      handleMobileLibVlcCoordinatorRecovered.indexOf(
        '_activeSources = <PlaybackSource>[',
      ),
      greaterThan(
        handleMobileLibVlcCoordinatorRecovered.indexOf(
          'final recoveredSource =',
        ),
      ),
    );
    expect(
      handleMobileLibVlcCoordinatorRecovered,
      contains('_sourceIndex = recoveredIndex;'),
    );
  });

  test('runtime recovery publishes only the current proved libVLC owner', () {
    final normalized = _normalizeCode(handleMobileLibVlcCoordinatorRecovered);
    for (final guard in const [
      '!identical(_mobileLibVlcCoordinator, coordinator)',
      'result.generation != coordinator.generation',
      'coordinator.currentCandidate?.attemptIdentity != '
          'result.candidate.attemptIdentity',
      'driver is! _MobileLibVlcDriverAdapter',
    ]) {
      expect(normalized, contains(guard));
    }
    expect(normalized, contains('_controller = recoveredController;'));
    expect(normalized, contains('_activeSource = recoveredSource;'));
    expect(
      normalized,
      contains('_applyStagedMobileLibVlcTransportMetadata('),
    );
    expect(normalized, contains('await _adoptMobileLibVlcTransport('));
    expect(normalized, contains('_rememberCrediblePlaybackAnchor('));
    expect(normalized, contains('_saveNativeProgress(force: true);'));
  });

  test('terminal libVLC monitor failure never crosses into Media3', () {
    expect(handleMobileLibVlcCoordinatorFailure, isNotEmpty);
    expect(
      handleMobileLibVlcCoordinatorFailure,
      contains('identical(_mobileLibVlcCoordinator, coordinator)'),
    );
    expect(
      handleMobileLibVlcCoordinatorFailure,
      isNot(contains('_retrySourceWithExoPlayerAfterLibVlcFailure')),
    );
    expect(
      handleMobileLibVlcCoordinatorFailure,
      isNot(contains('_openNextAvailableSource')),
    );
    expect(
      handleMobileLibVlcCoordinatorFailure.toLowerCase(),
      isNot(contains('media3')),
    );
  });

  test('resume prompt remains after proof with coordinated start-over', () {
    final awaitOpen = openLibVlcSourceWithCoordinator.indexOf(
      'final result = await coordinator.open(',
    );
    final resumePrompt = openLibVlcSourceWithCoordinator.indexOf(
      'await _resumePositionFor(controller.duration)',
    );
    expect(resumePrompt, greaterThan(awaitOpen));
    expect(
      _normalizeCode(openLibVlcSourceWithCoordinator),
      contains(
        'return _openLibVlcSourceWithCoordinator( provedSource, '
        'resumePosition: Duration.zero,',
      ),
    );
  });

  test('resume prompt actions close without waiting for another frame', () {
    final normalized = _normalizeCode(confirmResumePlayback);
    expect(
      normalized,
      contains('Navigator.of(dialogContext).pop(resume);'),
    );
    expect(
      normalized,
      isNot(contains('WidgetsBinding.instance.addPostFrameCallback')),
    );
  });

  test('coordinator receives the preserved opening anchor', () {
    final normalizedHelper = _normalizeCode(
      openLibVlcSourceWithCoordinator,
    );
    expect(
      normalizedHelper,
      contains(
        'final requestedCoordinatorAnchor = resumePosition ?? '
        '_preOpenPreferredResumePosition(',
      ),
    );
    expect(
      normalizedHelper,
      contains(
        'final coordinatorAnchor = deferP2pResumeUntilProof '
        '? Duration.zero '
        ': explicitStartOver '
        '? Duration.zero '
        ': preserveMobileLibVlcAnchor(',
      ),
    );
    expect(
      normalizedHelper,
      contains('current: _currentPlaybackResumeAnchor()'),
    );
    expect(
      _namedArgumentExpression(
        openLibVlcSourceWithCoordinator,
        'anchor',
      ),
      'coordinatorAnchor',
    );
    expect(
      openLibVlcSourceWithCoordinator,
      isNot(contains('anchor: Duration.zero')),
    );
  });

  test('failed HLS opening returns its absolute anchor to page recovery', () {
    final normalizedHelper = _normalizeCode(
      openLibVlcSourceWithCoordinator,
    );
    final ownershipGate = normalizedHelper.indexOf(
      'if (!stillOwnsOpen) return false;',
    );
    final terminalFailure = normalizedHelper.indexOf(
      'if (error is MobileLibVlcTerminalFailure) {',
    );
    final anchorRestore = normalizedHelper.indexOf(
      '_resumeProgressAnchorPosition = preserveMobileLibVlcAnchor(',
      terminalFailure,
    );
    final failedOpenLog = normalizedHelper.indexOf(
      "'native libvlc coordinator open failed '",
      terminalFailure,
    );

    expect(ownershipGate, greaterThanOrEqualTo(0));
    expect(terminalFailure, greaterThan(ownershipGate));
    expect(anchorRestore, greaterThan(terminalFailure));
    expect(anchorRestore, lessThan(failedOpenLog));
    expect(
      normalizedHelper.substring(anchorRestore, failedOpenLog),
      contains('current: _resumeProgressAnchorPosition'),
    );
    expect(
      normalizedHelper.substring(anchorRestore, failedOpenLog),
      contains('candidate: error.anchor'),
    );
    expect(
      normalizedHelper.substring(anchorRestore, failedOpenLog),
      contains('explicitSeek: explicitStartOver'),
    );
  });

  test('continuous TS progress and subtitles share the absolute clock', () {
    expect(
      saveNativeProgress,
      contains('_bestKnownProgressPosition(controller, duration)'),
    );
    expect(
      subtitlePlaybackPosition,
      contains('_resumeAnchoredPlaybackPosition(controller)'),
    );
  });

  test('continuous TS recovery arms its credible floor before opening', () {
    final normalizedHelper = _normalizeCode(
      openLibVlcSourceWithCoordinator,
    );
    final floorAssignment = normalizedHelper.indexOf(
      '_resumeProgressAnchorPosition = preserveMobileLibVlcAnchor(',
    );
    final coordinatorOpen = normalizedHelper.indexOf(
      'final result = await coordinator.open(',
    );

    expect(floorAssignment, greaterThanOrEqualTo(0));
    expect(coordinatorOpen, greaterThan(floorAssignment));
    expect(
      normalizedHelper.substring(floorAssignment, coordinatorOpen),
      contains('candidate: protectedResumeAnchor'),
    );
    expect(
      normalizedHelper.substring(floorAssignment, coordinatorOpen),
      contains('explicitSeek: explicitStartOver'),
    );
  });

  test('page publishes only the proven relay generation timeline', () {
    final absolutePosition = _methodBody(
      nativePlayerState,
      '_libVlcContinuousTsAbsolutePosition',
    );
    final normalizedOpen = _normalizeCode(openLibVlcSourceWithCoordinator);
    final normalizedRecovery =
        _normalizeCode(handleMobileLibVlcCoordinatorRecovered);
    final normalizedSeek = _normalizeCode(reopenMobileLibVlcAt);
    final normalizedSwitch = _normalizeCode(switchMobileLibVlcSelection);

    expect(
      nativePlayerState,
      contains(
        'MobileLibVlcSessionTimeline? _activeMobileLibVlcSessionTimeline;',
      ),
    );
    expect(adapter, contains('MobileLibVlcSessionTimeline? get timeline'));
    expect(
      absolutePosition,
      contains('_activeMobileLibVlcSessionTimeline'),
    );
    expect(
      normalizedOpen,
      contains(
        '_activeMobileLibVlcSessionTimeline = '
        'usesRelay ? sessionTimeline : null;',
      ),
    );
    expect(
      normalizedRecovery,
      contains('_activeMobileLibVlcSessionTimeline = driver.timeline;'),
    );
    expect(
      normalizedSeek,
      contains(
        '_activeMobileLibVlcSessionTimeline = reopenedDriver.timeline;',
      ),
    );
    expect(
      normalizedSwitch,
      contains(
        '_activeMobileLibVlcSessionTimeline = switchedDriver.timeline;',
      ),
    );
  });

  test('stale relay generations cannot publish a progress floor', () {
    final normalizedRecovery =
        _normalizeCode(handleMobileLibVlcCoordinatorRecovered);
    final normalizedSeek = _normalizeCode(reopenMobileLibVlcAt);
    final normalizedSwitch = _normalizeCode(switchMobileLibVlcSelection);

    expect(
      normalizedRecovery.indexOf(
        'result.generation != coordinator.generation',
      ),
      lessThan(
        normalizedRecovery.indexOf(
          '_activeMobileLibVlcSessionTimeline = driver.timeline;',
        ),
      ),
    );
    expect(
      normalizedSeek.indexOf('result.generation != coordinator.generation'),
      lessThan(
        normalizedSeek.indexOf(
          '_activeMobileLibVlcSessionTimeline = reopenedDriver.timeline;',
        ),
      ),
    );
    expect(
      normalizedSwitch.indexOf('result.generation != coordinator.generation'),
      lessThan(
        normalizedSwitch.indexOf(
          '_activeMobileLibVlcSessionTimeline = switchedDriver.timeline;',
        ),
      ),
    );
  });

  test('UI persistence and subtitles share the active clamped relay domain',
      () {
    final absolutePosition = _methodBody(
      nativePlayerState,
      '_libVlcContinuousTsAbsolutePosition',
    );

    expect(
      absolutePosition,
      contains('_activeMobileLibVlcSessionTimeline'),
    );
    expect(
      bestKnownProgressPosition,
      contains('_resumeAnchoredPlaybackPosition(controller)'),
    );
    expect(
      saveNativeProgress,
      contains('_bestKnownProgressPosition(controller, duration)'),
    );
    expect(
      subtitlePlaybackPosition,
      contains('_resumeAnchoredPlaybackPosition(controller)'),
    );
  });

  test('direct MP4 bypasses the relay progress timeline', () {
    final absolutePosition = _methodBody(
      nativePlayerState,
      '_libVlcContinuousTsAbsolutePosition',
    );
    final activeTimeline = absolutePosition.indexOf(
      '_activeMobileLibVlcSessionTimeline',
    );
    final continuousTsGuard = absolutePosition.indexOf(
      '!_libVlcContinuousTsActive',
    );

    expect(continuousTsGuard, greaterThanOrEqualTo(0));
    expect(activeTimeline, greaterThan(continuousTsGuard));
  });

  test('page closes its coordinator-owned libVLC session', () {
    expect(
      _occurrences(
        nativePlayerState,
        'MobileLibVlcCoordinator? _mobileLibVlcCoordinator;',
      ),
      1,
    );
    expect(
      pageDispose,
      contains("_closeMobileLibVlcCoordinatorSession('dispose')"),
    );
    expect(
      closeCoordinatorSession,
      contains('await coordinator.close()'),
    );
    expect(
      _normalizeCode(pageDispose),
      contains(
        'final coordinatorSessionActive = '
        '_mobileLibVlcCoordinator != null;',
      ),
    );
    expect(
      _normalizeCode(pageDispose),
      contains(
        'if (coordinatorSessionActive) { '
        'unawaited(_closeMobileLibVlcCoordinatorSession(\'dispose\'));',
      ),
    );
  });

  test('source sheet delegates only libVLC selections to coordinator switch',
      () {
    final normalized = _normalizeCode(showSourceSheet);
    expect(
      normalized,
      contains(
        'if (_controller?.engine == _NativePlaybackEngine.libvlc) {',
      ),
    );
    expect(
      normalized,
      contains('await _switchMobileLibVlcSelection('),
    );
    expect(
      normalized,
      contains('selected: selected'),
    );
    expect(
      normalized,
      contains('position: position'),
    );
    expect(
      normalized,
      contains('wasPlaying: wasPlaying'),
    );
  });

  test('Media3 source switching retains the existing openSource route', () {
    final libVlcBranch = showSourceSheet.indexOf(
      'if (_controller?.engine == _NativePlaybackEngine.libvlc)',
    );
    final media3Open = showSourceSheet.indexOf(
      'final opened = await _openSource(',
    );

    expect(libVlcBranch, greaterThanOrEqualTo(0));
    expect(media3Open, greaterThan(libVlcBranch));
    expect(
      _normalizeCode(showSourceSheet.substring(media3Open)),
      contains('final opened = await _openSource( selected,'),
    );
  });

  test(
      'manual source and quality switches sample the live anchor after selection',
      () {
    final sourceModal = showSourceSheet.indexOf(
      'final selected = await showModalBottomSheet<PlaybackSource>(',
    );
    final sourceAnchor = showSourceSheet.indexOf(
      'final position = _qualitySwitchResumePosition();',
    );
    final qualityModal = showQualitySheet.indexOf(
      'final selected = await showModalBottomSheet<Object>(',
    );
    final qualityAnchor = showQualitySheet.indexOf(
      'final position = _qualitySwitchResumePosition();',
    );

    expect(sourceModal, greaterThanOrEqualTo(0));
    expect(sourceAnchor, greaterThan(sourceModal));
    expect(qualityModal, greaterThanOrEqualTo(0));
    expect(qualityAnchor, greaterThan(qualityModal));
  });

  test('Media3 manual replacements arm rollback before candidate startup', () {
    final sourceBranch = showSourceSheet.indexOf(
      'if (_controller?.engine == _NativePlaybackEngine.libvlc)',
    );
    final sourceArm = showSourceSheet.indexOf(
      '_armSourceSelectionRollback(',
      sourceBranch,
    );
    final sourceOpen = showSourceSheet.indexOf(
      'final opened = await _openSource(',
      sourceBranch,
    );

    expect(sourceArm, greaterThan(sourceBranch));
    expect(sourceArm, lessThan(sourceOpen));

    final qualityLibVlcSwitch = showQualitySheet.lastIndexOf(
      'final libVlcHandled = await _switchMobileLibVlcSelection(',
    );
    final qualityArm = showQualitySheet.indexOf(
      '_armSourceSelectionRollback(',
      qualityLibVlcSwitch,
    );
    final qualityOpen = showQualitySheet.indexOf(
      'final opened = await _openSource(',
      qualityLibVlcSwitch,
    );

    expect(qualityArm, greaterThan(qualityLibVlcSwitch));
    expect(qualityArm, lessThan(qualityOpen));
    expect(
      _occurrences(
        showQualitySheet,
        '_restorePendingSourceSelectionRollback(',
      ),
      2,
    );
    expect(
      _occurrences(
        showSourceSheet,
        '_restorePendingSourceSelectionRollback(',
      ),
      1,
    );
    expect(
      showQualitySheet,
      isNot(contains('_restorePreviousSourceAfterSelectionFailure(')),
    );
    expect(
      showSourceSheet,
      isNot(contains('_restorePreviousSourceAfterSelectionFailure(')),
    );
  });

  test('libVLC switch failure cannot enter page fallback ladders', () {
    expect(switchMobileLibVlcSelection, isNotEmpty);
    expect(
      switchMobileLibVlcSelection,
      isNot(contains('_openNextAvailableSource')),
    );
    expect(
      switchMobileLibVlcSelection,
      isNot(contains('_restorePreviousSourceAfterSelectionFailure')),
    );
    expect(switchMobileLibVlcSelection, isNot(contains('_openSource(')));
    expect(
      switchMobileLibVlcSelection.toLowerCase(),
      isNot(contains('media3')),
    );
  });

  test('quality sheet uses the same proved libVLC switch transaction', () {
    final normalized = _normalizeCode(showQualitySheet);
    expect(
      _occurrences(showQualitySheet, 'await _switchMobileLibVlcSelection('),
      2,
    );
    expect(normalized, contains('selectedQuality: \'Auto\''));
    expect(
      normalized,
      contains('selectedQuality: _qualityLabel(selected)'),
    );
  });

  test('libVLC switch verifies coordinator generation before page publication',
      () {
    final awaitSwitch = switchMobileLibVlcSelection.indexOf(
      'await coordinator.switchSource(',
    );
    final verifyGeneration = switchMobileLibVlcSelection.indexOf(
      'result.generation != coordinator.generation',
    );
    final verifyCandidate = switchMobileLibVlcSelection.indexOf(
      'coordinator.currentCandidate?.attemptIdentity !=',
    );
    final publishController = switchMobileLibVlcSelection.indexOf(
      '_controller = switchedController;',
    );

    expect(awaitSwitch, greaterThanOrEqualTo(0));
    expect(verifyGeneration, greaterThan(awaitSwitch));
    expect(verifyCandidate, greaterThan(awaitSwitch));
    expect(publishController, greaterThan(verifyGeneration));
    expect(publishController, greaterThan(verifyCandidate));
  });

  test('direct seekable libVLC keeps the in-place coordinator seek path', () {
    expect(
      seekControllerToPlaybackPosition,
      contains('await coordinator.seekTo(target);'),
    );
    expect(
      _normalizeCode(seekControllerToPlaybackPosition),
      isNot(contains('driverPosition: localTarget')),
    );
  });

  test('non-seekable continuous TS uses the proven single-controller reopen',
      () {
    final seekStart = source.indexOf(
      'Future<bool> _seekControllerToPlaybackPosition(',
    );
    final seekEnd = source.indexOf(
      '\n  Duration? _libVlcContinuousTsLocalSeekPosition(',
      seekStart,
    );
    final seekFlow = source.substring(seekStart, seekEnd);
    final normalizedCoordinatorOpen =
        _normalizeCode(openLibVlcSourceWithCoordinator);
    expect(
      source,
      contains('transportSeekable: false'),
    );
    expect(
      seekFlow,
      contains('final seekRouteOwner = _beginLibVlcSeekGeneration();'),
    );
    expect(
      seekFlow,
      contains('seekRouteOwner.runWork<bool>('),
    );
    expect(
      seekFlow,
      contains('_openSource('),
    );
    expect(
      seekFlow,
      contains('libVlcManualSeekReopen: true'),
    );
    expect(
      seekFlow,
      isNot(contains('await _reopenMobileLibVlcAt(')),
    );
    expect(
      normalizedCoordinatorOpen,
      contains(
        'final openingBudgetOwner = '
        '_libVlcSeekOwner ?? openingRouteStartupOwner;',
      ),
    );
    expect(
      normalizedCoordinatorOpen,
      contains('routeStartupDeadline: openingBudgetOwner.deadline'),
    );
    expect(
      normalizedCoordinatorOpen,
      contains(
        'routeStartupRemainingBudget: () => '
        'openingBudgetOwner.remainingWorkBudget',
      ),
    );
  });

  test('rapid same-source relay seeks stage metadata by seek generation', () {
    final normalizedOpen = _normalizeCode(openLibVlcSourceWithCoordinator);
    final normalizedState = _normalizeCode(nativePlayerState);
    expect(normalizedState, contains('MobileLibVlcSourceCandidate, int'));
    expect(
      normalizedState,
      contains('_StagedMobileLibVlcTransportMetadata>'),
    );
    expect(
      normalizedOpen,
      contains(
        'final stagedTransportKey = '
        '(candidate, coordinator.generation);',
      ),
    );
    expect(
      _normalizeCode(reopenMobileLibVlcAt),
      contains(
        '_applyStagedMobileLibVlcTransportMetadata( result.candidate, '
        'result.generation,',
      ),
    );
  });

  test('continuous TS backward seeks settle before stale progress is saved',
      () {
    expect(
      nativePlayerState,
      contains('MobileLibVlcSeekSettlementBarrier()'),
    );
    expect(
      bestKnownProgressPosition,
      contains('_libVlcSeekSettlementBarrier.acceptedPosition('),
    );
    final ordinaryFallback = bestKnownProgressPosition
        .lastIndexOf('position = _lastKnownPlaybackPosition;');
    final settlementConstraint = bestKnownProgressPosition.indexOf(
      '_libVlcSeekSettlementBarrier.constrainComputedPosition(',
    );
    expect(ordinaryFallback, greaterThanOrEqualTo(0));
    expect(settlementConstraint, greaterThan(ordinaryFallback));
    expect(seekBy, contains('_libVlcSeekSettlementBarrier.nextSeekBase'));
    final beginBarrier = seekBy.indexOf('_libVlcSeekSettlementBarrier.begin(');
    final updateAnchor = seekBy.indexOf('_markManualSeekForIntegrity(');
    final applySeek = seekBy.indexOf(
      'await _seekControllerToPlaybackPosition(',
    );
    expect(beginBarrier, greaterThanOrEqualTo(0));
    expect(updateAnchor, greaterThan(beginBarrier));
    expect(applySeek, greaterThan(updateAnchor));
  });

  test('libVLC controller and source publish only after awaited switch proof',
      () {
    final awaitSwitch = switchMobileLibVlcSelection.indexOf(
      'await coordinator.switchSource(',
    );
    final publishController = switchMobileLibVlcSelection.indexOf(
      '_controller = switchedController;',
    );
    final publishSource =
        switchMobileLibVlcSelection.indexOf('_activeSource = selected;');
    final publishIndex =
        switchMobileLibVlcSelection.indexOf('_sourceIndex = nextIndex;');

    expect(awaitSwitch, greaterThanOrEqualTo(0));
    expect(publishController, greaterThan(awaitSwitch));
    expect(publishSource, greaterThan(awaitSwitch));
    expect(publishIndex, greaterThan(awaitSwitch));
  });

  test('libVLC switch anchor is qualitySwitchResumePosition and never zeroed',
      () {
    expect(
      showSourceSheet,
      contains('final position = _qualitySwitchResumePosition();'),
    );
    expect(switchMobileLibVlcSelection, contains('anchor: position'));
    expect(
      switchMobileLibVlcSelection,
      isNot(contains('anchor: Duration.zero')),
    );
    expect(
      switchMobileLibVlcSelection,
      isNot(contains('resumePositionOverride: Duration.zero')),
    );
  });

  test('unproved libVLC switch clocks cannot overwrite saved progress', () {
    expect(
      nativePlayerState,
      contains('bool _manualLibVlcSelectionProofPending = false;'),
    );
    expect(
      nativePlayerState,
      contains(
        'Duration _manualLibVlcSelectionProgressAnchor = Duration.zero;',
      ),
    );
    expect(
      nativePlayerState,
      contains(
        'bool _manualLibVlcSelectionRetainedClockRecoveryPending = false;',
      ),
    );

    final beginProof = switchMobileLibVlcSelection.indexOf(
      '_manualLibVlcSelectionProofPending = true;',
    );
    final captureAnchor = switchMobileLibVlcSelection.indexOf(
      '_manualLibVlcSelectionProgressAnchor = position;',
    );
    final awaitSwitch = switchMobileLibVlcSelection.indexOf(
      'await coordinator.switchSource(',
    );
    final accepted = switchMobileLibVlcSelection.indexOf(
      '_manualLibVlcSelectionProofPending = false;',
      awaitSwitch,
    );
    final acceptedSave = switchMobileLibVlcSelection.indexOf(
      '_saveNativeProgress(force: true);',
      accepted,
    );

    expect(beginProof, greaterThanOrEqualTo(0));
    expect(captureAnchor, greaterThanOrEqualTo(0));
    expect(beginProof, lessThan(awaitSwitch));
    expect(captureAnchor, lessThan(awaitSwitch));
    expect(accepted, greaterThan(awaitSwitch));
    expect(acceptedSave, greaterThan(accepted));
    expect(
      switchMobileLibVlcSelection,
      contains("reason: 'libvlc_selection_rejected_anchor_restored'"),
    );
    expect(
      switchMobileLibVlcSelection,
      contains(
        '_manualLibVlcSelectionRetainedClockRecoveryPending = true;',
      ),
    );
    expect(
      saveNativeProgress,
      contains(
        'if (_manualLibVlcSelectionProofPending)',
      ),
    );
    expect(
      saveNativeProgress,
      contains(
        'reason=libvlc_candidate_switch_unproved',
      ),
    );
    expect(
      saveNativeProgress,
      contains(
        'if (_manualLibVlcSelectionRetainedClockRecoveryPending)',
      ),
    );
    expect(
      saveNativeProgress,
      contains(
        'reason=libvlc_retained_session_clock_unproved',
      ),
    );
    expect(
      saveNativeProgress,
      contains(
        'reason=libvlc_retained_session_clock_recovered',
      ),
    );
  });

  test('source-sheet widget markers remain unchanged', () {
    for (final marker in const [
      'showModalBottomSheet<PlaybackSource>',
      'backgroundColor: Colors.transparent',
      '_SourceSheet(',
      'sources: _activeSources',
      'activeSource: _activeSource',
      '_displaySourceEntries(_activeSources)',
      '_qualityLabel(selected)',
    ]) {
      expect(showSourceSheet, contains(marker));
    }
  });

  test('source controls expose transport without guessing unknown streams', () {
    final sourceActionLabel = _methodBody(
      nativePlayerState,
      '_sourceActionLabel',
    );
    final sourceOption = _classBody(source, '_SourceOption');
    final mirrorOption = _classBody(source, '_MirrorOption');

    for (final marker in const [
      'String _sourceTransportDisplayLabel(',
      'String _sourceTransportGroupDisplayLabel(',
      "return 'MP4';",
      "return 'HLS';",
      "return 'Stream';",
      "return 'Mixed formats';",
    ]) {
      expect(source, contains(marker));
    }
    expect(
      sourceActionLabel,
      contains('_sourceTransportDisplayLabel(_activeSource)'),
    );
    expect(
      sourceOption,
      contains('_sourceTransportGroupDisplayLabel(entry.variants)'),
    );
    expect(
      mirrorOption,
      contains('_sourceTransportDisplayLabel(source)'),
    );
  });

  test('existing Media3 construction markers remain present once', () {
    expect(
      _occurrences(source, 'media3: _Media3NativePlayerController('),
      1,
    );
    expect(
      _occurrences(source, 'video: VideoPlayerController.networkUrl('),
      1,
    );
    expect(
      _occurrences(source, 'if (_shouldUseNativeMedia3SurfaceForSource('),
      1,
    );
  });

  test('Media3 retains one bounded VOD skip window behind playback', () {
    expect(
      media3PlayerViewSource,
      contains('private const val VOD_BACK_BUFFER_MS = 45_000'),
    );
    expect(
      media3PlayerViewSource,
      contains(
        '.setBackBuffer(if (liveMode) 0 else VOD_BACK_BUFFER_MS, true)',
      ),
    );
  });

  test('libVLC coordinator prepares P2P candidates through the local bridge',
      () {
    final source = File('lib/src/native_player_page.dart').readAsStringSync();
    final page = _classBody(source, '_NativePlayerPageState');
    final openMethod = _methodBody(page, '_openLibVlcSourceWithCoordinator');
    final compactOpenMethod = _normalizeCode(openMethod);

    expect(openMethod, isNotEmpty);
    expect(
      compactOpenMethod,
      contains(
        'await _controllerSourceFor( originalSource, '
        '_NativePlaybackEngine.libvlc,',
      ),
    );
    expect(
      compactOpenMethod,
      contains('originalSource.sourceClass == PlaybackSourceClass.p2p'),
    );
    expect(
      compactOpenMethod,
      contains('driverSource = preparedP2pSource'),
    );
  });

  test(
      'Media3 avoids the emulator goldfish AVC decoder without changing devices',
      () {
    expect(
      media3PlayerViewSource,
      contains('private fun media3CodecSelectorForDevice()'),
    );
    expect(
      media3PlayerViewSource,
      contains('MediaCodecSelector.PREFER_SOFTWARE'),
    );
    expect(
      media3PlayerViewSource,
      contains('if (!isAndroidEmulator()) return MediaCodecSelector.DEFAULT'),
    );
    expect(
      media3PlayerViewSource,
      isNot(contains('fingerprint.startsWith("generic")')),
      reason: 'A generic build fingerprint alone is not emulator proof.',
    );
    expect(media3PlayerViewSource, contains('hardware.contains("ranchu")'));
    expect(media3PlayerViewSource, contains('hardware.contains("goldfish")'));
    expect(media3PlayerViewSource, contains('model.contains("sdk_gphone")'));
    expect(
      media3PlayerViewSource,
      contains('if (mimeType != MimeTypes.VIDEO_H264)'),
    );
    expect(
      media3PlayerViewSource,
      contains('.setMediaCodecSelector(media3CodecSelectorForDevice())'),
    );
  });

  test('next episode cancellation restores retained playback UI', () {
    final source = File('lib/src/native_player_page.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _openNextEpisodeInPlace()');
    final end = source.indexOf('\n  Future<', start + 20);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);
    final catchStart = method.indexOf('} catch (error) {');
    final finallyStart = method.indexOf('} finally {', catchStart);
    expect(catchStart, greaterThanOrEqualTo(0));
    expect(finallyStart, greaterThan(catchStart));
    final failureBranch = method.substring(catchStart, finallyStart);

    expect(
        failureBranch, contains('_routeStartupOwner.completeSuccessfully()'));
    expect(failureBranch, contains('_loading = false'));
    expect(failureBranch, contains('_statusMessage = null'));
    expect(failureBranch, isNot(contains('rethrow;')));
  });

  test('next episode null result restores UI before retained playback', () {
    final page = File('lib/src/native_player_page.dart').readAsStringSync();
    final start = page.indexOf('if (next == null) {');
    final end = page.indexOf('\n    final resolvedNext = next;', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final nullBranch = page.substring(start, end);

    expect(
      nullBranch,
      contains('restoreRetainedPlaybackAfterRouteFailure('),
    );
    expect(
      nullBranch.indexOf('publishRestoredUi:'),
      lessThan(nullBranch.indexOf('resumePlayback:')),
    );
  });
}

String _classBody(String source, String className) {
  final declaration = source.indexOf('class $className');
  if (declaration < 0) return '';
  final openingBrace = source.indexOf('{', declaration);
  if (openingBrace < 0) return '';
  return _balancedBody(source, openingBrace, '{', '}');
}

String _methodBody(String classBody, String methodName) {
  final declaration = RegExp(
    '^\\s*(?:Future<[^\\n]+>|void|bool|String|int|double|Duration|Widget)\\s+'
    '${RegExp.escape(methodName)}\\s*\\(',
    multiLine: true,
  ).firstMatch(classBody);
  if (declaration == null) return '';
  final openingParenthesis = classBody.indexOf('(', declaration.start);
  final closingParenthesis = _closingDelimiterIndex(
    classBody,
    openingParenthesis,
    '(',
    ')',
  );
  if (closingParenthesis < 0) return '';
  final openingBrace = classBody.indexOf('{', closingParenthesis);
  if (openingBrace < 0) return '';
  return _balancedBody(classBody, openingBrace, '{', '}');
}

String _balancedBody(
  String source,
  int openingIndex,
  String opening,
  String closing,
) {
  final closingIndex = _closingDelimiterIndex(
    source,
    openingIndex,
    opening,
    closing,
  );
  if (closingIndex < 0) return '';
  return source.substring(openingIndex + 1, closingIndex);
}

int _closingDelimiterIndex(
  String source,
  int openingIndex,
  String opening,
  String closing,
) {
  var depth = 0;
  for (var index = openingIndex; index < source.length; index += 1) {
    final character = source[index];
    if (character == opening) {
      depth += 1;
    } else if (character == closing) {
      depth -= 1;
      if (depth == 0) {
        return index;
      }
    }
  }
  return -1;
}

String _initializerExpression(String methodBody, String variableName) {
  final declaration = RegExp(
    '\\b(?:final|var)\\s+${RegExp.escape(variableName)}\\s*=',
  ).firstMatch(methodBody);
  if (declaration == null) return '';
  final expressionStart = declaration.end;
  final expressionEnd = methodBody.indexOf(';', expressionStart);
  if (expressionEnd < 0) return '';
  return methodBody.substring(expressionStart, expressionEnd).trim();
}

String _guardConditionForStatement(String methodBody, String statement) {
  final statementIndex = methodBody.indexOf(statement);
  if (statementIndex < 0) return '';

  var searchOffset = 0;
  String condition = '';
  while (true) {
    final candidate = methodBody.indexOf('if (', searchOffset);
    if (candidate < 0 || candidate >= statementIndex) break;
    final openingParenthesis = methodBody.indexOf('(', candidate);
    final conditionBody = _balancedBody(
      methodBody,
      openingParenthesis,
      '(',
      ')',
    );
    final closingParenthesis = openingParenthesis + conditionBody.length + 1;
    final openingBrace = methodBody.indexOf('{', closingParenthesis);
    if (openingBrace >= 0) {
      final guardedBody = _balancedBody(methodBody, openingBrace, '{', '}');
      final guardedEnd = openingBrace + guardedBody.length + 1;
      if (statementIndex > openingBrace && statementIndex < guardedEnd) {
        condition = conditionBody.trim();
      }
    }
    searchOffset = candidate + 3;
  }
  return condition;
}

String _guardBodyForStatement(String methodBody, String statement) {
  final statementIndex = methodBody.indexOf(statement);
  if (statementIndex < 0) return '';

  var searchOffset = 0;
  String body = '';
  while (true) {
    final candidate = methodBody.indexOf('if (', searchOffset);
    if (candidate < 0 || candidate >= statementIndex) break;
    final openingParenthesis = methodBody.indexOf('(', candidate);
    final closingParenthesis = _closingDelimiterIndex(
      methodBody,
      openingParenthesis,
      '(',
      ')',
    );
    if (closingParenthesis < 0) break;
    final openingBrace = methodBody.indexOf('{', closingParenthesis);
    if (openingBrace >= 0) {
      final guardedBody = _balancedBody(methodBody, openingBrace, '{', '}');
      final guardedEnd = openingBrace + guardedBody.length + 1;
      if (statementIndex > openingBrace && statementIndex < guardedEnd) {
        body = guardedBody.trim();
      }
    }
    searchOffset = candidate + 3;
  }
  return body;
}

String _namedArgumentExpression(String methodBody, String argumentName) {
  final argument = RegExp(
    '\\b${RegExp.escape(argumentName)}\\s*:',
  ).firstMatch(methodBody);
  if (argument == null) return '';
  final expressionEnd = methodBody.indexOf(',', argument.end);
  if (expressionEnd < 0) return '';
  return methodBody.substring(argument.end, expressionEnd).trim();
}

String _normalizeCode(String source) {
  return source.replaceAll(RegExp(r'\s+'), ' ').trim();
}

int _occurrences(String source, String needle) {
  var count = 0;
  var offset = 0;
  while (true) {
    final index = source.indexOf(needle, offset);
    if (index < 0) return count;
    count += 1;
    offset = index + needle.length;
  }
}

int _identifierOffset(RegExpMatch role) {
  const identifier = '_hasObservedAdvancingVisualFrame';
  return role.start + role.group(0)!.indexOf(identifier);
}
