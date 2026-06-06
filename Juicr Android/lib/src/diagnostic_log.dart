import 'dart:convert';
import 'dart:async';
import 'dart:ui' show ViewPadding;

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';

class DiagnosticLog {
  DiagnosticLog._();

  static const int _maxEntries = 260;
  static const int _maxUploadReportBytes = 56 * 1024;
  static const String _entriesKey = 'diagnostic_log_entries';
  static const String _sessionStateKey = 'diagnostic_session_state';
  static const String _lastSessionIdKey = 'diagnostic_session_id';
  static const String _installMarkerKey = 'diagnostic_install_marker';
  static const String _lastPromptedCrashSessionKey =
      'diagnostic_last_prompted_crash_session';
  static const String _nativeEngineActiveKey =
      'diagnostic_native_engine_active';
  static const MethodChannel _diagnosticChannel = MethodChannel(
    'app.juicr.flutter/diagnostics',
  );
  static final List<String> _entries = <String>[];
  static final Map<String, DateTime> _timers = <String, DateTime>{};
  static final Map<String, int> _counters = <String, int>{};
  static Timer? _persistEntriesTimer;
  static SharedPreferences? _prefs;
  static String _sessionId = '';
  static String _previousSessionId = '';
  static String _previousSessionExit = 'clean';
  static String _previousNativeEngineActiveEngine = '';
  static String _previousAndroidExitReason = 'unavailable';
  static String _previousAndroidExitDescription = '';
  static String _currentInstallMarker = 'unknown';
  static bool _previousInstallChanged = false;
  static bool _previousSessionCrashed = false;
  static DateTime? _batterySessionStartedAt;
  static DateTime? _batteryLastSampledAt;
  static int? _batteryInitialPercent;
  static int? _batteryLastPercent;
  static String _batteryLastStatus = 'unavailable';
  static String _batteryLastPlugged = 'unavailable';
  static int? _batteryLastTemperatureTenthsC;
  static int? _batteryLastVoltageMv;
  static bool _batteryAvailable = false;
  static final ValueNotifier<int> sessionRevision = ValueNotifier<int>(0);

  static void add(String message) {
    final now = DateTime.now().toIso8601String();
    final sanitized = _sanitizeForStorage(message);
    _entries.add('[$now] $sanitized');
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    final category = _eventCategory(message);
    _counters[category] = (_counters[category] ?? 0) + 1;
    _mirrorToAndroidLogcat(sanitized);
    _persistEntries();
  }

  static Future<void> initPersistentSession({SharedPreferences? prefs}) async {
    final preInitEntries = List<String>.from(_entries);
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _entries
      ..clear()
      ..addAll(_prefs?.getStringList(_entriesKey) ?? const <String>[]);
    if (preInitEntries.isNotEmpty) {
      _entries.addAll(preInitEntries);
      if (_entries.length > _maxEntries) {
        _entries.removeRange(0, _entries.length - _maxEntries);
      }
    }
    _rebuildCounters();
    final previousState = _prefs?.getString(_sessionStateKey);
    final previousId = _prefs?.getString(_lastSessionIdKey);
    final promptedId = _prefs?.getString(_lastPromptedCrashSessionKey);
    final previousInstallMarker = _prefs?.getString(_installMarkerKey);
    final previousNativeEngineActive = _prefs?.getString(
      _nativeEngineActiveKey,
    );
    _previousSessionId = previousId ?? '';
    final previousWasRunning =
        previousState == 'running' &&
        previousId != null &&
        previousId.isNotEmpty;
    _currentInstallMarker = previousInstallMarker ?? 'unknown';
    _previousInstallChanged = false;
    _previousAndroidExitReason = previousWasRunning ? 'pending' : 'not_needed';
    _previousAndroidExitDescription = '';
    _previousSessionExit = previousWasRunning ? 'pending' : 'clean';
    _previousSessionCrashed = false;
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    unawaited(_prefs?.setString(_sessionStateKey, 'running'));
    unawaited(_prefs?.setString(_lastSessionIdKey, _sessionId));
    add('diagnostic session started id=$_sessionId');
    unawaited(recordBatterySnapshot('session_start'));
    unawaited(
      _finishPersistentSessionBoot(
        previousWasRunning: previousWasRunning,
        previousId: previousId,
        promptedId: promptedId,
        previousInstallMarker: previousInstallMarker,
        previousNativeEngineActive: previousNativeEngineActive,
      ),
    );
  }

  static Future<void> _finishPersistentSessionBoot({
    required bool previousWasRunning,
    required String? previousId,
    required String? promptedId,
    required String? previousInstallMarker,
    required String? previousNativeEngineActive,
  }) async {
    final nativeEngineInterrupted =
        previousNativeEngineActive != null &&
        previousNativeEngineActive.trim().isNotEmpty;
    _previousNativeEngineActiveEngine = nativeEngineInterrupted
        ? _engineFromNativeActiveMarker(previousNativeEngineActive)
        : '';
    if (previousWasRunning) {
      _currentInstallMarker = await _loadInstallMarker();
      _previousInstallChanged =
          previousInstallMarker != null &&
          _currentInstallMarker != 'unknown' &&
          previousInstallMarker != _currentInstallMarker;
      final androidExit = await _loadLatestAndroidExitInfo();
      _previousAndroidExitReason = (androidExit['reason'] ?? 'unavailable')
          .toString();
      _previousAndroidExitDescription = (androidExit['description'] ?? '')
          .toString();
      _previousSessionExit = _classifyPreviousSessionExit(previousWasRunning);
      if (nativeEngineInterrupted &&
          _previousSessionExit != 'app_native_crash') {
        _previousSessionExit = 'native_engine_interrupted';
      }
      _previousSessionCrashed =
          _shouldPromptForPreviousExit(_previousSessionExit) &&
          previousId != promptedId;
      if (_currentInstallMarker != 'unknown') {
        await _prefs?.setString(_installMarkerKey, _currentInstallMarker);
      }
      add(
        'previous session ended unexpectedly previousSession=$previousId '
        'classification=$_previousSessionExit '
        'androidExit=$_previousAndroidExitReason '
        'installChanged=$_previousInstallChanged '
        'nativeEngineActive=${nativeEngineInterrupted ? _previousNativeEngineActiveEngine : 'none'}',
      );
    } else {
      _previousSessionExit = nativeEngineInterrupted
          ? 'native_engine_interrupted'
          : 'clean';
      _previousSessionCrashed =
          nativeEngineInterrupted && previousId != promptedId;
      _previousAndroidExitReason = 'not_needed';
      _previousAndroidExitDescription = '';
      await _refreshInstallMarkerAfterBoot(previousInstallMarker);
      if (nativeEngineInterrupted) {
        add(
          'previous native engine session ended unexpectedly marker=present classification=$_previousSessionExit',
        );
      }
    }
    if (nativeEngineInterrupted) {
      await _prefs?.remove(_nativeEngineActiveKey);
    }
    sessionRevision.value += 1;
  }

  static Future<void> _refreshInstallMarkerAfterBoot(
    String? previousInstallMarker,
  ) async {
    final marker = await _loadInstallMarker();
    if (marker == 'unknown') return;
    _currentInstallMarker = marker;
    await _prefs?.setString(_installMarkerKey, marker);
    final changed =
        previousInstallMarker != null && previousInstallMarker != marker;
    if (changed) {
      add('diagnostic install marker refreshed after boot changed=true');
    }
  }

  static bool get previousSessionCrashed => _previousSessionCrashed;

  static bool get shouldShowCrashPrompt => _previousSessionCrashed;

  static String get previousSessionId => _previousSessionId;

  static String get previousSessionExit => _previousSessionExit;
  static String get previousNativeEngineActiveEngine =>
      _previousNativeEngineActiveEngine;

  static String _engineFromNativeActiveMarker(String? marker) {
    final raw = marker?.trim() ?? '';
    if (raw.isEmpty) return 'unknown';
    final engine = raw.split('|').first.trim();
    if (engine.isEmpty) return 'unknown';
    return _sanitizeViewTimingToken(engine);
  }

  static String get sessionId => _sessionId;

  static String get previousAndroidExitReason => _previousAndroidExitReason;

  static bool get previousInstallChanged => _previousInstallChanged;

  static String get appVersionLabel {
    final parts = _currentInstallMarker.split('|');
    if (parts.length < 3) return 'flutter-native unknown';
    final versionName = parts[1].isEmpty ? 'unknown' : parts[1];
    final versionCode = parts[2].isEmpty ? 'unknown' : parts[2];
    return 'flutter-native $versionName+$versionCode';
  }

  static bool get batteryEvidenceAvailable => _batteryAvailable;

  static int? get latestBatteryPercent => _batteryLastPercent;

  static String get latestBatteryStatus => _batteryLastStatus;

  static bool get isCharging =>
      _batteryLastStatus == 'charging' ||
      _batteryLastPlugged == 'ac' ||
      _batteryLastPlugged == 'usb' ||
      _batteryLastPlugged == 'wireless';

  static Future<void> markSessionClean(String reason) async {
    add('diagnostic session clean reason=$reason id=$_sessionId');
    await _prefs?.setString(_sessionStateKey, 'clean');
  }

  static Future<void> markSessionRunning(String reason) async {
    add('diagnostic session running reason=$reason id=$_sessionId');
    await _prefs?.setString(_sessionStateKey, 'running');
    unawaited(recordBatterySnapshot(reason));
  }

  static Future<void> recordBatterySnapshot(String reason) async {
    try {
      final raw = await _diagnosticChannel.invokeMapMethod<String, Object?>(
        'batterySnapshot',
      );
      if (raw == null || raw.isEmpty) {
        _batteryAvailable = false;
        add('battery evidence unavailable reason=$reason status=empty');
        return;
      }
      final available = raw['available'] == true;
      final percent = _intFromObject(raw['levelPercent']);
      final status = _safeBatteryToken(raw['status']);
      final plugged = _safeBatteryToken(raw['plugged']);
      final temperature = _intFromObject(raw['temperatureTenthsC']);
      final voltage = _intFromObject(raw['voltageMv']);
      final now = DateTime.now();
      _batteryAvailable = available && percent != null && percent >= 0;
      _batterySessionStartedAt ??= now;
      _batteryLastSampledAt = now;
      if (_batteryAvailable && _batteryInitialPercent == null) {
        _batteryInitialPercent = percent;
      }
      if (_batteryAvailable) _batteryLastPercent = percent;
      _batteryLastStatus = status;
      _batteryLastPlugged = plugged;
      _batteryLastTemperatureTenthsC = temperature == null || temperature < 0
          ? null
          : temperature;
      _batteryLastVoltageMv = voltage == null || voltage < 0 ? null : voltage;
      add(
        'battery evidence sample reason=${_sanitizeViewTimingToken(reason)} '
        'available=$_batteryAvailable level=${_batteryLastPercent ?? 'unknown'} '
        'delta=${_batteryDeltaLabel()} status=$_batteryLastStatus '
        'plugged=$_batteryLastPlugged elapsed=${_batteryElapsedLabel()}',
      );
    } catch (error) {
      _batteryAvailable = false;
      add('battery evidence unavailable reason=$reason error=$error');
    }
  }

  static Future<void> refreshBatteryEvidenceForReport(String reason) {
    return Future.wait<void>([recordBatterySnapshot(reason)]).then((_) {});
  }

  static Future<void> markNativeEngineActive({
    required String engineId,
    required String reason,
  }) async {
    final safeEngine = _sanitizeViewTimingToken(engineId);
    final safeReason = _sanitizeViewTimingToken(reason);
    add(
      'diagnostic native engine active engine=$safeEngine reason=$safeReason',
    );
    await _prefs?.setString(
      _nativeEngineActiveKey,
      '$safeEngine|$_sessionId|${DateTime.now().toIso8601String()}',
    );
  }

  static Future<void> clearNativeEngineActive({
    required String engineId,
    required String reason,
  }) async {
    final safeEngine = _sanitizeViewTimingToken(engineId);
    final safeReason = _sanitizeViewTimingToken(reason);
    add('diagnostic native engine clear engine=$safeEngine reason=$safeReason');
    await _prefs?.remove(_nativeEngineActiveKey);
  }

  static Future<void> dismissCrashPrompt() async {
    if (_previousSessionId.isNotEmpty) {
      await _prefs?.setString(_lastPromptedCrashSessionKey, _previousSessionId);
    }
    _previousSessionCrashed = false;
  }

  static String _classifyPreviousSessionExit(bool previousWasRunning) {
    if (!previousWasRunning) return 'clean';
    if (_previousInstallChanged) return 'android_app_update_or_reinstall';
    switch (_previousAndroidExitReason) {
      case 'crash':
        return 'app_crash';
      case 'crash_native':
        return 'app_native_crash';
      case 'anr':
        return 'app_anr';
      case 'low_memory':
        return 'android_low_memory_kill';
      case 'user_requested':
      case 'user_stopped':
        return 'android_user_or_system_stop';
      case 'dependency_died':
        return 'android_dependency_died';
      case 'permission_change':
        return 'android_permission_change';
      case 'signaled':
        return 'process_signaled';
      case 'exit_self':
        return 'app_exit_self';
      case 'initialization_failure':
        return 'app_initialization_failure';
      case 'excessive_resource_usage':
        return 'android_excessive_resource_usage';
      case 'other':
        return 'android_other';
    }
    return 'app_or_system_unknown';
  }

  static bool _shouldPromptForPreviousExit(String exit) {
    return switch (exit) {
      'clean' => false,
      'android_app_update_or_reinstall' => false,
      'android_low_memory_kill' => false,
      'android_user_or_system_stop' => false,
      'android_permission_change' => false,
      'app_exit_self' => false,
      _ => true,
    };
  }

  static Future<String> _loadInstallMarker() async {
    try {
      final raw = await _diagnosticChannel.invokeMapMethod<String, Object?>(
        'installInfo',
      );
      if (raw == null || raw.isEmpty) return 'unknown';
      final packageName = (raw['packageName'] ?? '').toString();
      final versionName = (raw['versionName'] ?? '').toString();
      final versionCode = (raw['versionCode'] ?? '').toString();
      final firstInstallTime = (raw['firstInstallTime'] ?? '').toString();
      final lastUpdateTime = (raw['lastUpdateTime'] ?? '').toString();
      return <String>[
        packageName,
        versionName,
        versionCode,
        firstInstallTime,
        lastUpdateTime,
      ].join('|');
    } catch (error) {
      add('diagnostic install info unavailable error=$error');
      return 'unknown';
    }
  }

  static Future<Map<String, Object?>> _loadLatestAndroidExitInfo() async {
    try {
      final raw = await _diagnosticChannel.invokeListMethod<Object?>(
        'processExitInfo',
      );
      if (raw == null || raw.isEmpty) return const <String, Object?>{};
      final entries = raw.whereType<Map<Object?, Object?>>().toList()
        ..sort((a, b) {
          final aTimestamp =
              int.tryParse((a['timestamp'] ?? '').toString()) ?? 0;
          final bTimestamp =
              int.tryParse((b['timestamp'] ?? '').toString()) ?? 0;
          return bTimestamp.compareTo(aTimestamp);
        });
      if (entries.isEmpty) return const <String, Object?>{};
      return entries.first.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
    } catch (error) {
      add('diagnostic android exit info unavailable error=$error');
      return const <String, Object?>{};
    }
  }

  static Future<Map<String, Object?>> installInfo() async {
    try {
      final raw = await _diagnosticChannel.invokeMapMethod<String, Object?>(
        'installInfo',
      );
      return raw ?? const <String, Object?>{};
    } catch (error) {
      add('diagnostic install info read failed error=$error');
      return const <String, Object?>{};
    }
  }

  static void breadcrumb(
    String area,
    String action, [
    Map<String, Object?> data = const {},
  ]) {
    final fields = data.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    add(
      'BREADCRUMB area=$area action=$action${fields.isEmpty ? '' : ' $fields'}',
    );
  }

  static void performance(String area, String action, Duration elapsed) {
    add('PERF area=$area action=$action elapsedMs=${elapsed.inMilliseconds}');
  }

  static void viewTiming({
    required String surface,
    required String state,
    Duration? elapsed,
    String? sourceClassBucket,
    String? mediaKind,
    String? cacheStateBucket,
    String? refreshActionBucket,
    int? itemCount,
    bool redacted = true,
  }) {
    final fields = <String>[
      'surface=${_sanitizeViewTimingToken(surface)}',
      'viewTimingState=${_sanitizeViewTimingToken(state)}',
      if (sourceClassBucket != null && sourceClassBucket.trim().isNotEmpty)
        'sourceClassBucket=${_sanitizeViewTimingToken(sourceClassBucket)}',
      if (mediaKind != null && mediaKind.trim().isNotEmpty)
        'mediaKind=${_sanitizeViewTimingToken(mediaKind)}',
      if (elapsed != null) 'elapsedBucket=${_elapsedBucket(elapsed)}',
      if (elapsed != null) 'firstPaintBucket=${_elapsedBucket(elapsed)}',
      if (state == 'skeleton_visible')
        'skeletonVisibleBucket=${_elapsedBucket(elapsed ?? Duration.zero)}',
      if (state == 'interaction_ready')
        'interactionReadyBucket=${_elapsedBucket(elapsed ?? Duration.zero)}',
      if (state == 'trailer_ready')
        'trailerReadyBucket=${_elapsedBucket(elapsed ?? Duration.zero)}',
      if (state == 'player_ready')
        'playerReadyBucket=${_elapsedBucket(elapsed ?? Duration.zero)}',
      if (cacheStateBucket != null && cacheStateBucket.trim().isNotEmpty)
        'cacheStateBucket=${_sanitizeViewTimingToken(cacheStateBucket)}',
      if (refreshActionBucket != null && refreshActionBucket.trim().isNotEmpty)
        'refreshActionBucket=${_sanitizeViewTimingToken(refreshActionBucket)}',
      if (itemCount != null) 'itemCountBucket=${_itemCountBucket(itemCount)}',
      'evidenceVersion=view_timing_v1',
      'redacted=$redacted',
    ];
    add('VIEWTIMING ${fields.join(' ')}');
  }

  static String _sanitizeForStorage(String value) {
    return value
        .replaceAll(RegExp(r'https?:\/\/[^\s,)]+'), '[url]')
        .replaceAll(RegExp(r'uri=\[url\]'), 'uri=[hidden]')
        .replaceAll(RegExp(r'url=\[url\]'), 'url=[hidden]');
  }

  static void _mirrorToAndroidLogcat(String value) {
    final safe = _sanitizeSensitiveReportTokens(value);
    if (!_isPlaybackLogcatCandidate(safe)) return;
    unawaited(
      _diagnosticChannel
          .invokeMethod<void>('logcat', {'message': safe})
          .catchError((_) {}),
    );
  }

  static bool _isPlaybackLogcatCandidate(String value) {
    final lower = value.toLowerCase();
    return lower.contains('details playback') ||
        lower.contains('details resolve') ||
        lower.contains('native ') ||
        lower.contains('addon streams') ||
        lower.contains('remote resolve') ||
        lower.contains('playback feedback') ||
        lower.contains('p2p stream');
  }

  static void clear() {
    _entries.clear();
    _timers.clear();
    _counters.clear();
    _persistEntries();
  }

  static void start(String key, String message) {
    _timers[key] = DateTime.now();
    add('$message started key=$key');
  }

  static void end(String key, String message) {
    final startedAt = _timers.remove(key);
    final elapsed = startedAt == null
        ? 'unknown'
        : '${DateTime.now().difference(startedAt).inMilliseconds}ms';
    add('$message finished key=$key elapsed=$elapsed');
  }

  static void screen(BuildContext context, String name) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      add('screen $name view metrics unavailable');
      return;
    }
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    add(
      'screen $name size=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)} '
      'orientation=${size.width > size.height ? 'landscape' : 'portrait'} '
      'dpr=${view.devicePixelRatio.toStringAsFixed(2)} '
      'padding=${_viewPadding(view.padding, view.devicePixelRatio)} '
      'viewInsets=${_viewPadding(view.viewInsets, view.devicePixelRatio)}',
    );
  }

  static void flutterError(FlutterErrorDetails details) {
    final exception = details.exceptionAsString();
    final library = details.library ?? 'unknown library';
    final context = details.context?.toDescription() ?? 'no context';
    add('FLUTTER ERROR library=$library context=$context exception=$exception');
    final stack = details.stack;
    if (stack != null) {
      add('FLUTTER STACK ${_trimStack(stack)}');
    }
  }

  static void asyncError(Object error, StackTrace stack) {
    add('ASYNC ERROR exception=$error');
    add('ASYNC STACK ${_trimStack(stack)}');
  }

  static String report() {
    final errors = _entries
        .where(_isErrorLike)
        .map(_sanitizeForReport)
        .toList();
    final performance = _entries
        .where(_isPerformanceLike)
        .map(_sanitizeForReport)
        .toList();
    final lines = <String>[
      'Juicr diagnostic report',
      '------------------------',
      '',
      '[Report]',
      'Generated: ${DateTime.now().toIso8601String()}',
      'Mode: Native only',
      'App version: $appVersionLabel',
      'Session id: $_sessionId',
      'Previous session crashed: $_previousSessionCrashed',
      'Previous session exit: $_previousSessionExit',
      'Previous Android exit reason: $_previousAndroidExitReason',
      if (_previousAndroidExitDescription.isNotEmpty)
        'Previous Android exit detail: $_previousAndroidExitDescription',
      'Previous app install changed: $_previousInstallChanged',
      '',
      '[App State]',
      'Theme: ${AppState.themeMode.value.name}',
      'Shell tab: ${AppState.shellTab.value}',
      'Native provider: ${_providerLabel(AppState.selectedNativeProviderId)}',
      'Continue watching entries: ${AppState.continueWatching.value.length}',
      'Saved library entries: ${AppState.library.value.length}',
      'Search history entries: ${AppState.searchHistory.value.length}',
      'User add-ons: ${AppState.userAddons.value.length}',
      'Default catalog: ${AppState.defaultCatalogEnabled.value}',
      'Default providers: ${AppState.defaultProvidersEnabled.value}',
      'Default subtitles: ${AppState.defaultSubtitlesEnabled.value}',
      'Default trailers: ${AppState.defaultTrailersEnabled.value}',
      'Banner ads enabled: ${AppState.bannerAdsEnabled.value}',
      'Interstitial ads enabled: ${AppState.interstitialAdsEnabled.value}',
      'Rewarded ads enabled: ${AppState.rewardedVideoAdsEnabled.value}',
      'Notifications enabled: ${AppState.notificationsEnabled.value}',
      'Notification personalization retired: true',
      'Notification dialogs enabled: ${AppState.notificationDialogsEnabled.value}',
      'Notification interstitials enabled: ${AppState.notificationInterstitialsEnabled.value}',
      '',
      '[Root Cause Packet]',
      ..._rootCausePacketLines(),
      '',
      '[Playback Attempt Timeline]',
      ..._playbackAttemptTimelineLines(),
      '',
      '[Protection/Cooldown State]',
      ..._protectionCooldownLines(),
      '',
      '[Route Close Cleanup]',
      ..._routeCloseCleanupLines(),
      '',
      '[Battery Evidence]',
      ..._batteryEvidenceLines(),
      '',
      '[P2P Bridge Readiness]',
      AppState.exportP2pBridgeReadiness(),
      '',
      '[P2P Indexer Connectors]',
      const JsonEncoder.withIndent(
        '  ',
      ).convert(AppState.p2pIndexerConnectorsDiagnosticSummary()),
      '',
      '[P2P Priority Source Settings]',
      const JsonEncoder.withIndent(
        '  ',
      ).convert(AppState.p2pSourcePrioritiesDiagnosticSummary()),
      '',
      '[P2P Runtime Decision Packet]',
      AppState.exportP2pRuntimeDecisionPacket(),
      '',
      '[P2P Runtime Approval Packet]',
      AppState.exportP2pRuntimeApprovalPacket(),
      '',
      '[P2P Ready-To-Test Gate Attestation Matrix]',
      AppState.exportP2pReadyToTestGateAttestationMatrix(),
      '',
      '[Add-on Route Evidence]',
      if (AppState.addonRouteAttemptHistory.value.isEmpty)
        'No add-on route-attempt evidence recorded yet.'
      else
        AppState.exportAddonRouteAttemptHistory(),
      '',
      '[Event Counts]',
      if (_counters.isEmpty) 'No event counters recorded yet.',
      ..._counters.entries
          .toList()
          .where((entry) => entry.value > 0)
          .map((entry) => '${entry.key}: ${entry.value}'),
      '',
      '[Likely Issues]',
      if (errors.isEmpty) 'No error-like events recorded yet.',
      ...errors.take(40),
      '',
      '[Performance]',
      if (performance.isEmpty) 'No performance timing events recorded yet.',
      ...performance.take(40),
      '',
      '[View Timing]',
      ..._viewTimingLines(),
      '',
      '[Recent Events]',
      if (_entries.isEmpty) 'No diagnostic events recorded yet.',
      ..._entries.map(_sanitizeForReport),
    ];
    return lines.join('\n');
  }

  static String uploadReport() {
    final fullReport = report();
    if (utf8.encode(fullReport).length <= _maxUploadReportBytes) {
      return fullReport;
    }

    final errors = _entries
        .where(_isErrorLike)
        .map(_sanitizeForReport)
        .toList();
    final performance = _entries
        .where(_isPerformanceLike)
        .map(_sanitizeForReport)
        .toList();
    final recentEvents = _entries
        .map(_sanitizeForReport)
        .toList()
        .reversed
        .take(90)
        .toList()
        .reversed
        .toList();
    final baseLines = <String>[
      'Juicr diagnostic report',
      '------------------------',
      '',
      '[Report]',
      'Generated: ${DateTime.now().toIso8601String()}',
      'Mode: Native only',
      'App version: $appVersionLabel',
      'Session id: $_sessionId',
      'Upload mode: compact redacted report',
      'Full local report bytes: ${utf8.encode(fullReport).length}',
      'Previous session crashed: $_previousSessionCrashed',
      'Previous session exit: $_previousSessionExit',
      'Previous Android exit reason: $_previousAndroidExitReason',
      'Previous app install changed: $_previousInstallChanged',
      '',
      '[App State]',
      'Theme: ${AppState.themeMode.value.name}',
      'Shell tab: ${AppState.shellTab.value}',
      'Native provider: ${_providerLabel(AppState.selectedNativeProviderId)}',
      'Continue watching entries: ${AppState.continueWatching.value.length}',
      'Saved library entries: ${AppState.library.value.length}',
      'Search history entries: ${AppState.searchHistory.value.length}',
      'User add-ons: ${AppState.userAddons.value.length}',
      'Default catalog: ${AppState.defaultCatalogEnabled.value}',
      'Default providers: ${AppState.defaultProvidersEnabled.value}',
      '',
      '[Root Cause Packet]',
      ..._rootCausePacketLines(),
      '',
      '[Playback Attempt Timeline]',
      ..._playbackAttemptTimelineLines(),
      '',
      '[Protection/Cooldown State]',
      ..._protectionCooldownLines(),
      '',
      '[Route Close Cleanup]',
      ..._routeCloseCleanupLines(),
      '',
      '[Battery Evidence]',
      ..._batteryEvidenceLines(),
      '',
      '[P2P Bridge Readiness]',
      AppState.exportP2pBridgeReadiness(),
      '',
      '[P2P Indexer Connectors]',
      const JsonEncoder.withIndent(
        '  ',
      ).convert(AppState.p2pIndexerConnectorsDiagnosticSummary()),
      '',
      '[P2P Priority Source Settings]',
      const JsonEncoder.withIndent(
        '  ',
      ).convert(AppState.p2pSourcePrioritiesDiagnosticSummary()),
      '',
      '[P2P Runtime Decision Packet]',
      AppState.exportP2pRuntimeDecisionPacket(),
      '',
      '[Add-on Route Evidence]',
      if (AppState.addonRouteAttemptHistory.value.isEmpty)
        'No add-on route-attempt evidence recorded yet.'
      else
        AppState.exportCompactAddonRouteAttemptHistory(),
      '',
      '[Event Counts]',
      if (_counters.isEmpty) 'No event counters recorded yet.',
      ..._counters.entries
          .toList()
          .where((entry) => entry.value > 0)
          .map((entry) => '${entry.key}: ${entry.value}'),
      '',
      '[Likely Issues]',
      if (errors.isEmpty) 'No error-like events recorded yet.',
      ...errors.take(24),
      '',
      '[Performance]',
      if (performance.isEmpty) 'No performance timing events recorded yet.',
      ...performance.take(24),
      '',
      '[View Timing]',
      ..._viewTimingLines().take(24),
      '',
      '[Recent Events]',
      if (_entries.isEmpty) 'No diagnostic events recorded yet.',
    ];
    String buildCompact() => <String>[...baseLines, ...recentEvents].join('\n');

    var compact = buildCompact();
    while (utf8.encode(compact).length > _maxUploadReportBytes &&
        recentEvents.length > 20) {
      recentEvents.removeAt(0);
      compact = buildCompact();
    }
    final encoded = utf8.encode(compact);
    if (encoded.length > _maxUploadReportBytes) {
      const note = '\n[Report truncated to stay within upload limit.]';
      final limit = _maxUploadReportBytes - utf8.encode(note).length;
      return '${utf8.decode(encoded.take(limit).toList(), allowMalformed: true)}$note';
    }
    return compact;
  }

  static List<String> _rootCausePacketLines() {
    final sanitizedEntries = _entries.map(_sanitizeForReport).toList();
    final attemptCount = sanitizedEntries
        .where((entry) => entry.contains('details playback launch start'))
        .length;
    final issueCount = sanitizedEntries.where(_isErrorLike).length;
    final rateLimitCount = _countMatches(
      sanitizedEntries,
      RegExp(r'Rate limit exceeded|Request temporarily blocked'),
    );
    final localBackoffCount = _countMatches(
      sanitizedEntries,
      RegExp(
        r'details playback (?:service|resolver) backoff armed|cooling this title',
      ),
    );
    final temporaryBlockCount = _countMatches(
      sanitizedEntries,
      RegExp(
        r'details playback (?:service|resolver) temporary block observed',
      ),
    );
    final routeCloseNoiseCount = _countMatches(
      sanitizedEntries,
      RegExp(
        r'playback feedback skipped event=.*reason=player_closing|native open result ignored .*reason=player_closing',
      ),
    );
    final lateOpenAfterCloseCount = _countMatches(
      sanitizedEntries,
      RegExp(r'native open failed|native source open timed out'),
    );
    final rootCause = _rootCauseLabel(
      rateLimitCount: rateLimitCount,
      localBackoffCount: localBackoffCount,
      temporaryBlockCount: temporaryBlockCount,
      routeCloseNoiseCount: routeCloseNoiseCount,
      lateOpenAfterCloseCount: lateOpenAfterCloseCount,
      issueCount: issueCount,
    );
    return <String>[
      'Schema: juicr.diagnostic.root_cause.v1',
      'Patch fingerprint: diagnostic-root-cause-packet-v7-active-watch-saved-delta',
      'Install marker state: ${_installMarkerSummary()}',
      'Playback attempts recorded: $attemptCount',
      'Issue-like events recorded: $issueCount',
      'Most likely area: $rootCause',
      'Privacy posture: counts, safe labels, timings, and redacted route evidence only.',
    ];
  }

  static List<String> _playbackAttemptTimelineLines() {
    final attempts = <_PlaybackAttemptSummary>[];
    _PlaybackAttemptSummary? current;
    for (final entry in _entries.map(_sanitizeForReport)) {
      final start = RegExp(
        r'details playback launch start type=([^\s]+) id=([^\s]+).*verifiedCache=([^\s]+)',
      ).firstMatch(entry);
      if (start != null) {
        if (current != null) attempts.add(current);
        current = _PlaybackAttemptSummary(
          startedAt: _timestampForEntry(entry),
          type: start.group(1) ?? 'unknown',
          id: _safeMediaId(start.group(2) ?? 'unknown'),
          verifiedCache: start.group(3) ?? 'unknown',
        );
        continue;
      }
      current?._observe(entry);
    }
    if (current != null) attempts.add(current);
    if (attempts.isEmpty) {
      return const <String>['No playback attempts recorded yet.'];
    }
    return attempts.reversed.take(8).toList().reversed.map((attempt) {
      return attempt.toReportLine();
    }).toList();
  }

  static List<String> _protectionCooldownLines() {
    final entries = _entries.map(_sanitizeForReport).toList();
    final localBackoffCount = _countMatches(
      entries,
      RegExp(
        r'details playback (?:service|resolver) backoff armed|cooling this title',
      ),
    );
    final temporaryBlockCount = _countMatches(
      entries,
      RegExp(
        r'details playback (?:service|resolver) temporary block observed',
      ),
    );
    final resolverRateLimitCount = _countMatches(
      entries,
      RegExp(r'Rate limit exceeded|Request temporarily blocked'),
    );
    final resolverBusyCount = _countMatches(
      entries,
      RegExp(r'Playback service is busy|Resolver is busy|playback_service_temporary_block|resolver_temporary_block'),
    );
    return <String>[
      'App title cooldown: ${localBackoffCount == 0 ? 'not recorded' : 'old cooldown seen ($localBackoffCount)'}',
      'Temporary playback-service pauses observed: $temporaryBlockCount',
      'Playback-service rate-limit responses: $resolverRateLimitCount',
      'Playback-service busy scan pauses: $resolverBusyCount',
      'Interpretation: app cooldown, service cooldown, and edge/rate-limit signals are separated for root-cause triage.',
    ];
  }

  static List<String> _routeCloseCleanupLines() {
    final entries = _entries.map(_sanitizeForReport).toList();
    final routeClosedCount = _countMatches(
      entries,
      RegExp(
        r'native route finished result=closed|native route completed result=closed',
      ),
    );
    final feedbackSkippedCount = _countMatches(
      entries,
      RegExp(r'playback feedback skipped event=.*reason=player_closing'),
    );
    final lateOpenIgnoredCount = _countMatches(
      entries,
      RegExp(r'native open result ignored .*reason=player_closing'),
    );
    final closedClientFeedbackCount = _countMatches(
      entries,
      RegExp(r'Client is already closed'),
    );
    return <String>[
      'Closed native routes: $routeClosedCount',
      'Late feedback skipped after close: $feedbackSkippedCount',
      'Late source-open results ignored after close: $lateOpenIgnoredCount',
      'Closed HTTP client feedback errors: $closedClientFeedbackCount',
      'Interpretation: close cleanup should prevent old source-open results from becoming provider/cache penalties or noisy feedback.',
    ];
  }

  static List<String> _batteryEvidenceLines() {
    if (!_batteryAvailable ||
        _batteryInitialPercent == null ||
        _batteryLastPercent == null ||
        _batterySessionStartedAt == null ||
        _batteryLastSampledAt == null) {
      return const <String>[
        'Battery snapshot: unavailable',
        'Interpretation: device battery evidence was not available from Android for this session.',
      ];
    }
    return <String>[
      'Schema: juicr.diagnostic.battery_evidence.v1',
      'Session elapsed: ${_batteryElapsedLabel()}',
      'Initial battery: $_batteryInitialPercent%',
      'Latest battery: $_batteryLastPercent%',
      'Battery delta: ${_batteryDeltaLabel()}',
      'Charging state: $_batteryLastStatus',
      'Plugged: $_batteryLastPlugged',
      if (_batteryLastTemperatureTenthsC != null)
        'Temperature bucket: ${_batteryTemperatureBucket(_batteryLastTemperatureTenthsC!)}',
      if (_batteryLastVoltageMv != null)
        'Voltage bucket: ${_batteryVoltageBucket(_batteryLastVoltageMv!)}',
      'Interpretation: passive snapshots only; compare with screen brightness, signal quality, playback engine, source type, and session duration.',
    ];
  }

  static String _batteryElapsedLabel() {
    final startedAt = _batterySessionStartedAt;
    final sampledAt = _batteryLastSampledAt;
    if (startedAt == null || sampledAt == null) return 'unknown';
    final elapsed = sampledAt.difference(startedAt);
    if (elapsed.inMinutes >= 60) {
      final hours = elapsed.inHours;
      final minutes = elapsed.inMinutes.remainder(60);
      return '${hours}h ${minutes}m';
    }
    if (elapsed.inMinutes > 0) return '${elapsed.inMinutes}m';
    return '${elapsed.inSeconds}s';
  }

  static String _batteryDeltaLabel() {
    final initial = _batteryInitialPercent;
    final latest = _batteryLastPercent;
    if (initial == null || latest == null) return 'unknown';
    final delta = latest - initial;
    if (delta == 0) return '0%';
    return '${delta > 0 ? '+' : ''}$delta%';
  }

  static String _batteryTemperatureBucket(int tenthsC) {
    final celsius = tenthsC / 10.0;
    if (celsius < 30) return 'cool';
    if (celsius < 38) return 'normal';
    if (celsius < 43) return 'warm';
    return 'hot';
  }

  static String _batteryVoltageBucket(int mv) {
    if (mv <= 0) return 'unknown';
    if (mv < 3600) return 'low';
    if (mv < 3900) return 'normal';
    if (mv < 4300) return 'high';
    return 'charging-high';
  }

  static int _countMatches(Iterable<String> entries, RegExp pattern) {
    var count = 0;
    for (final entry in entries) {
      if (pattern.hasMatch(entry)) count += 1;
    }
    return count;
  }

  static String _rootCauseLabel({
    required int rateLimitCount,
    required int localBackoffCount,
    required int temporaryBlockCount,
    required int routeCloseNoiseCount,
    required int lateOpenAfterCloseCount,
    required int issueCount,
  }) {
    if (localBackoffCount > 0) return 'old app-side playback cooldown';
    if (rateLimitCount > 0) return 'playback service protection pacing';
    if (temporaryBlockCount > 0) {
      return 'temporary playback service protection signal';
    }
    if (routeCloseNoiseCount > 0) return 'route-close cleanup guarded';
    if (lateOpenAfterCloseCount > 0) return 'native source open/readability';
    if (issueCount > 0) return 'general app or provider issue';
    return 'no obvious issue in retained diagnostics';
  }

  static String _installMarkerSummary() {
    final parts = _currentInstallMarker.split('|');
    if (parts.length < 3) {
      return 'unknown install marker; changed=$_previousInstallChanged';
    }
    final packageName = parts[0].isEmpty ? 'unknown' : parts[0];
    final versionName = parts[1].isEmpty ? 'unknown' : parts[1];
    final versionCode = parts[2].isEmpty ? 'unknown' : parts[2];
    return 'package=$packageName version=$versionName code=$versionCode changed=$_previousInstallChanged';
  }

  static String _timestampForEntry(String entry) {
    final match = RegExp(r'^\[([^\]]+)\]').firstMatch(entry);
    if (match == null) return 'unknown-time';
    return match.group(1) ?? 'unknown-time';
  }

  static String _safeMediaId(String value) {
    if (value.length <= 16) return value;
    return '${value.substring(0, 12)}...';
  }

  static List<String> _localCatalogSummaryLines() {
    final summary = AppState.exportLocalCatalogSummary();
    final kindCounts = summary['kindCounts'];
    final kindLine = kindCounts is Map
        ? kindCounts.entries
              .map((entry) => '${entry.key}:${entry.value}')
              .join(', ')
        : '';
    return <String>[
      'Catalogs: ${summary['catalogCount']}',
      'Items: ${summary['itemCount']}',
      'Kinds: ${kindLine.isEmpty ? 'none' : kindLine}',
      'Tagged items: ${summary['taggedItemCount']}',
      'Items with runtime metadata: ${summary['runtimeItemCount']}',
      'Items with release-year metadata: ${summary['releaseYearItemCount']}',
      'Picked asset ref count: ${summary['pickedAssetRefCount']}',
      'Picked assets needing relink: ${summary['relinkNeededPickedAssetCount']}',
      'Picked asset refs: ${summary['hasPickedAssetRefs']}',
      'Media refs: ${summary['hasMediaRefs']}',
      'Path-like fields: ${summary['hasPathLikeFields']}',
      'Storage permission mode: ${summary['storagePermissionMode']}',
      'File access mode: ${summary['fileAccessMode']}',
      'Diagnostics redaction: ${summary['diagnosticsRedaction']}',
    ];
  }

  static List<String> _viewTimingLines() {
    final packets = _entries
        .map(_sanitizeForReport)
        .where((entry) => entry.contains('VIEWTIMING '))
        .toList();
    if (packets.isEmpty) {
      return const <String>['No view timing packets recorded yet.'];
    }
    return packets.take(24).toList();
  }

  static void _persistEntries() {
    final prefs = _prefs;
    if (prefs == null) return;
    if (_persistEntriesTimer?.isActive == true) return;
    _persistEntriesTimer = Timer(const Duration(milliseconds: 400), () {
      final currentPrefs = _prefs;
      if (currentPrefs == null) return;
      currentPrefs.setStringList(_entriesKey, List<String>.from(_entries));
    });
  }

  static void _rebuildCounters() {
    _counters.clear();
    for (final entry in _entries) {
      final category = _eventCategory(entry);
      _counters[category] = (_counters[category] ?? 0) + 1;
    }
  }

  static bool _isErrorLike(String value) {
    return RegExp(
      r'error|failed|timeout|exception|crash|stall|no sources|blocked|denied',
      caseSensitive: false,
    ).hasMatch(value);
  }

  static bool _isPerformanceLike(String value) {
    return RegExp(
      r'\bPERF\b|\bVIEWTIMING\b|elapsed=|elapsedMs=|durationMs=',
      caseSensitive: false,
    ).hasMatch(value);
  }

  static String _sanitizeViewTimingToken(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
  }

  static String _safeBatteryToken(Object? value) {
    final raw = (value ?? 'unknown').toString().trim();
    if (raw.isEmpty) return 'unknown';
    return _sanitizeViewTimingToken(raw);
  }

  static int? _intFromObject(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString());
  }

  static String _elapsedBucket(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    if (ms < 250) return 'under_250ms';
    if (ms < 600) return '250_to_599ms';
    if (ms < 1200) return '600_to_1199ms';
    if (ms < 2500) return '1200_to_2499ms';
    if (ms < 5000) return '2500_to_4999ms';
    if (ms < 8000) return '5000_to_7999ms';
    return '8000ms_plus';
  }

  static String _itemCountBucket(int count) {
    if (count <= 0) return '0';
    if (count <= 4) return '1_to_4';
    if (count <= 12) return '5_to_12';
    if (count <= 24) return '13_to_24';
    if (count <= 48) return '25_to_48';
    return '49_plus';
  }

  static String _eventCategory(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('flutter error') || lower.contains('async error'))
      return 'crash';
    if (_isErrorLike(value)) return 'issue';
    if (_isPerformanceLike(value)) return 'performance';
    if (lower.contains('screen ')) return 'screen';
    if (lower.contains('settings')) return 'settings';
    if (lower.contains('addon')) return 'addon';
    if (lower.contains('route') || lower.contains('resolve')) return 'playback';
    return 'general';
  }

  static String _sanitizeForReport(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'https?:\/\/[^\s,)]+'), '[url]')
        .replaceAll(
          RegExp(r"Failed host lookup: '[^']+'"),
          'Failed host lookup: [host]',
        )
        .replaceAll(RegExp(r'uri=\[url\]'), 'uri=[hidden]')
        .replaceAll(RegExp(r'url=\[url\]'), 'url=[hidden]');
    return _sanitizeSensitiveReportTokens(_sanitizeProviderIds(sanitized));
  }

  static String _sanitizeSensitiveReportTokens(String value) {
    var sanitized = value
        .replaceAll(
          RegExp(r'\bmagnet:[^\s]+', caseSensitive: false),
          'magnet:[hidden]',
        )
        .replaceAll(
          RegExp(r'\binfoHash=[^\s]+', caseSensitive: false),
          'infoHash=[redacted]',
        )
        .replaceAll(
          RegExp(r'\bhash=[0-9a-f]{20,}\b', caseSensitive: false),
          'hash=[redacted]',
        )
        .replaceAll(
          RegExp(r'\btrackers=[^\s]+', caseSensitive: false),
          'trackers=[redacted]',
        )
        .replaceAll(
          RegExp(r'\bpeer[A-Za-z]*=[^\s]+', caseSensitive: false),
          'peer=[redacted]',
        )
        .replaceAll(
          RegExp(r'\bheaders?=[^\s]+', caseSensitive: false),
          'headers=[redacted]',
        )
        .replaceAll(
          RegExp(r'\btoken=[^\s]+', caseSensitive: false),
          'token=[redacted]',
        )
        .replaceAll(
          RegExp(r'\bapiKey=[^\s]+', caseSensitive: false),
          'apiKey=[redacted]',
        )
        .replaceAll(
          RegExp(r'\baccount=[^\s]+', caseSensitive: false),
          'account=[redacted]',
        )
        .replaceAll(
          RegExp(r'\bcookie=[^\s]+', caseSensitive: false),
          'cookie=[redacted]',
        )
        .replaceAll(RegExp(r'\bprovider=[^\s]+'), 'provider=[redacted]')
        .replaceAll(
          RegExp(r'\bremoteProvider=[^\s]+'),
          'remoteProvider=[redacted]',
        )
        .replaceAll(
          RegExp(
            r'\baddon=.*?(?=\s(?:catalogs=|catalog=|type=|sort=|genre=|search=|reason=|id=|uri=|resource=|error=|label=|infoHash=|fileIdx=|trackers=|p2pLocked=|quality=|episodes=)|$)',
          ),
          'addon=[redacted]',
        )
        .replaceAll(
          RegExp(r'\bactiveAddons=[^\n]+'),
          'activeAddons=[redacted_addons]',
        )
        .replaceAll(
          RegExp(r'\bcatalogs=[^\s]+'),
          'catalogs=[redacted_catalogs]',
        )
        .replaceAll(RegExp(r'\bcatalog=[^\s]+'), 'catalog=[redacted_catalog]')
        .replaceAll(RegExp(r'\bkey=(builtin|addon):[^\s]+'), 'key=[redacted]')
        .replaceAll(RegExp(r'\bfirst=([^\n]+)'), 'first=[redacted_media_list]')
        .replaceAll(RegExp(r'\btitleLength=\d+'), 'titleLength=[redacted]')
        .replaceAll(
          RegExp(r'\bid=tt\d+', caseSensitive: false),
          'id=[redacted_media]',
        )
        .replaceAll(
          RegExp(r'\bid=\d{4,}', caseSensitive: false),
          'id=[redacted_media]',
        )
        .replaceAll(
          RegExp(r'\bmovie tt\d+', caseSensitive: false),
          'movie [redacted_media]',
        )
        .replaceAll(
          RegExp(r'\bmovie \d{4,}', caseSensitive: false),
          'movie [redacted_media]',
        )
        .replaceAll(
          RegExp(r'\bseries tt\d+', caseSensitive: false),
          'series [redacted_media]',
        )
        .replaceAll(
          RegExp(r'\banimation tt\d+', caseSensitive: false),
          'animation [redacted_media]',
        )
        .replaceAll(RegExp(r'\bproviderIndex=\d+'), 'providerIndex=[redacted]')
        .replaceAll(RegExp(r'\bsourceIndex=\d+'), 'sourceIndex=[redacted]')
        .replaceAll(RegExp(r'\bsourceCount=\d+'), 'sourceCount=[count]')
        .replaceAll(
          RegExp(r'\bprovider ready provider=[^\s]+'),
          'provider ready provider=[redacted]',
        )
        .replaceAll(
          RegExp(r'\bnative request order=[^\n]+'),
          'native request order=[redacted_provider_order]',
        )
        .replaceAll(
          RegExp(r'\bnative cold provider scan [^\n]+'),
          'native cold provider scan [redacted_provider_order]',
        )
        .replaceAll(
          RegExp(r'\bnative page resolving provider=[^\s]+'),
          'native page resolving provider=[redacted]',
        )
        .replaceAll(
          RegExp(r'\bnative provider resolve start provider=[^\s]+'),
          'native provider resolve start provider=[redacted]',
        )
        .replaceAll(
          RegExp(
            r'\bhosted [a-z]+ [a-z]+ (start|ok) provider=[^\s]+',
            caseSensitive: false,
          ),
          'hosted playback lookup [redacted_route]',
        )
        .replaceAll(
          RegExp(r'\bhosted playback lookup (start|ok) provider=[^\s]+'),
          'hosted playback lookup [redacted_route]',
        )
        .replaceAll(
          RegExp(
            r'\b(?:provider|playback) health sample .*?\b(id|type|sources|embeds|sourceClasses)=[^\n]+',
          ),
          'playback health sample [redacted_summary]',
        )
        .replaceAll(
          RegExp(r'\bprovider lookup (start|ok) provider=[^\s]+'),
          'provider lookup [redacted_route]',
        )
        .replaceAll(
          'details playback resolver temporary block observed',
          'details playback service temporary block observed',
        )
        .replaceAll(
          'details playback resolver backoff armed',
          'details playback service backoff armed',
        )
        .replaceAll(
          'resolver_temporary_block',
          'playback_service_temporary_block',
        )
        .replaceAll(
          'resolver_protected',
          'playback_service_protected',
        )
        .replaceAll(
          'protect_resolver',
          'protect_playback_service',
        )
        .replaceAll(
          RegExp(r'\bnative quality variants provider=[^\s]+'),
          'native quality variants provider=[redacted]',
        );
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'label="[^"]*"'),
      (_) => 'label="[redacted_label]"',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'text="[^"]*"'),
      (_) => 'text="[redacted_text]"',
    );
    return sanitized;
  }

  static String _providerLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'Unknown';
    }
    const labels = <String, String>{
      'vidlink': 'Alpha',
      'alpha': 'Alpha',
      'vidsrc': 'Beta',
      'beta': 'Beta',
      'icefy': 'Delta',
      'delta': 'Delta',
      'vidnest': 'Epsilon',
      'epsilon': 'Epsilon',
      'primesrc': 'Zeta',
      'xpass': 'Zeta',
      'zeta': 'Zeta',
      'cineby': 'Eta',
      'moviesapi': 'Eta',
      'vidking': 'Nu',
      'eta': 'Eta',
      'nu': 'Nu',
      'popr': 'Theta',
      'theta': 'Theta',
      'cinesu': 'Rho',
      'rho': 'Rho',
      'vidapi': 'Sigma',
      'sigma': 'Sigma',
      'videasy': 'Tau',
      'tau': 'Tau',
      'vidfun': 'Upsilon',
      'upsilon': 'Upsilon',
      'flixhq': 'Phi',
      'phi': 'Phi',
      'rgshows': 'Iota',
      'iota': 'Iota',
      'vixsrc': 'Kappa',
      'kappa': 'Kappa',
      'vidrock': 'Lambda',
      'lambda': 'Lambda',
      'vidzee': 'Mu',
      'mu': 'Mu',
      'flixer': 'Xi',
      'xi': 'Xi',
      '7xstream': 'Omicron',
      'omicron': 'Omicron',
      'meowtv': 'Pi',
      'pi': 'Pi',
    };
    return labels[normalized] ?? value;
  }

  static String _sanitizeProviderIds(String value) {
    return value
        .replaceAll(RegExp(r'\bvidlink\b', caseSensitive: false), 'Alpha')
        .replaceAll(RegExp(r'\bvidsrc\b', caseSensitive: false), 'Beta')
        .replaceAll(RegExp(r'\bfmovies4u\b', caseSensitive: false), 'Provider')
        .replaceAll(RegExp(r'\bhydrahd\b', caseSensitive: false), 'Provider')
        .replaceAll(RegExp(r'\bicefy\b', caseSensitive: false), 'Delta')
        .replaceAll(RegExp(r'\bvidnest\b', caseSensitive: false), 'Epsilon')
        .replaceAll(RegExp(r'\bprimesrc\b', caseSensitive: false), 'Zeta')
        .replaceAll(RegExp(r'\bxpass\b', caseSensitive: false), 'Zeta')
        .replaceAll(RegExp(r'\bcineby\b', caseSensitive: false), 'Eta')
        .replaceAll(RegExp(r'\bmoviesapi\b', caseSensitive: false), 'Eta')
        .replaceAll(RegExp(r'\bvidking\b', caseSensitive: false), 'Nu')
        .replaceAll(RegExp(r'\bpopr\b', caseSensitive: false), 'Theta')
        .replaceAll(RegExp(r'\bcinesu\b', caseSensitive: false), 'Rho')
        .replaceAll(RegExp(r'\brho\b', caseSensitive: false), 'Rho')
        .replaceAll(RegExp(r'\bvidapi\b', caseSensitive: false), 'Sigma')
        .replaceAll(RegExp(r'\bsigma\b', caseSensitive: false), 'Sigma')
        .replaceAll(RegExp(r'\bvideasy\b', caseSensitive: false), 'Tau')
        .replaceAll(RegExp(r'\btau\b', caseSensitive: false), 'Tau')
        .replaceAll(RegExp(r'\bvidfun\b', caseSensitive: false), 'Upsilon')
        .replaceAll(RegExp(r'\bupsilon\b', caseSensitive: false), 'Upsilon')
        .replaceAll(RegExp(r'\bflixhq\b', caseSensitive: false), 'Phi')
        .replaceAll(RegExp(r'\bphi\b', caseSensitive: false), 'Phi')
        .replaceAll(RegExp(r'\brgshows\b', caseSensitive: false), 'Iota')
        .replaceAll(RegExp(r'\bvixsrc\b', caseSensitive: false), 'Kappa')
        .replaceAll(RegExp(r'\bvidrock\b', caseSensitive: false), 'Lambda')
        .replaceAll(RegExp(r'\bvidzee\b', caseSensitive: false), 'Mu')
        .replaceAll(RegExp(r'\bflixer\b', caseSensitive: false), 'Xi')
        .replaceAll(RegExp(r'\b7xstream\b', caseSensitive: false), 'Omicron')
        .replaceAll(RegExp(r'\bmeowtv\b', caseSensitive: false), 'Pi')
        .replaceAll(RegExp(r'\bpi\b', caseSensitive: false), 'Pi');
  }

  static String _viewPadding(ViewPadding value, double devicePixelRatio) {
    final left = value.left / devicePixelRatio;
    final top = value.top / devicePixelRatio;
    final right = value.right / devicePixelRatio;
    final bottom = value.bottom / devicePixelRatio;
    return '(${left.toStringAsFixed(1)},${top.toStringAsFixed(1)},'
        '${right.toStringAsFixed(1)},${bottom.toStringAsFixed(1)})';
  }

  static String _trimStack(StackTrace stack) {
    return stack
        .toString()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(12)
        .join(' | ');
  }
}

class _PlaybackAttemptSummary {
  _PlaybackAttemptSummary({
    required this.startedAt,
    required this.type,
    required this.id,
    required this.verifiedCache,
  });

  final String startedAt;
  final String type;
  final String id;
  final String verifiedCache;
  String result = 'incomplete';
  String provider = 'unknown';
  String engine = 'unknown';
  String protection = 'none';
  String sourceOpen = 'not reached';
  String elapsed = 'unknown';

  void _observe(String entry) {
    final providerMatch = RegExp(r'provider=([^\s]+)').firstMatch(entry);
    if (providerMatch != null) {
      provider = '[redacted]';
    }
    final engineMatch = RegExp(r'engine=([^\s]+)').firstMatch(entry);
    if (engineMatch != null) {
      engine = engineMatch.group(1) ?? engine;
    }
    final elapsedMatch = RegExp(r'elapsed=([^\s]+)').firstMatch(entry);
    if (elapsedMatch != null) {
      elapsed = elapsedMatch.group(1) ?? elapsed;
    }
    if (entry.contains('native source attempt')) {
      sourceOpen = 'attempted';
    }
    if (entry.contains('native initialized') &&
        entry.contains('engine=libvlc')) {
      result = 'controller-initialized';
      sourceOpen = sourceOpen == 'not reached' ? 'attempted' : sourceOpen;
    } else if (entry.contains('native initialized')) {
      result = 'initialized';
      sourceOpen = 'opened';
    } else if (entry.contains('native libvlc open pending visual proof')) {
      result = 'waiting-first-frame';
      sourceOpen = 'pending-first-frame';
    } else if (entry.contains('native libvlc open success accepted')) {
      result = 'initialized';
      sourceOpen = 'opened';
    } else if (entry.contains('native source runtime failed')) {
      result = 'source-runtime-failed';
      sourceOpen = 'failed';
    } else if (entry.contains('details playback launch ok')) {
      result = result == 'initialized' ? result : 'route-opened';
    } else if (entry.contains('details playback launch failed')) {
      result = 'launch-failed';
    } else if (entry.contains('native playback failed')) {
      result = 'native-failed';
    } else if (entry.contains('native open result ignored') &&
        entry.contains('reason=player_closing')) {
      result = 'closed-before-open-finished';
      sourceOpen = 'ignored-after-close';
    } else if (entry.contains('native open failed') ||
        entry.contains('native source open timed out')) {
      result = 'source-open-failed';
      sourceOpen = 'failed';
    }
    if (entry.contains('Rate limit exceeded') ||
        entry.contains('Request temporarily blocked')) {
      protection = 'rate-limit';
    } else if (entry.contains('playback_service_temporary_block') ||
        entry.contains('resolver_temporary_block') ||
        entry.contains('details playback service temporary block observed') ||
        entry.contains('details playback resolver temporary block observed')) {
      protection = 'temporary-block';
    } else if (entry.contains('details playback service backoff armed') ||
        entry.contains('details playback resolver backoff armed') ||
        entry.contains('cooling this title')) {
      protection = 'old-app-cooldown';
    }
  }

  String toReportLine() {
    return '$startedAt type=$type id=$id result=$result provider=$provider '
        'engine=$engine verifiedCache=$verifiedCache sourceOpen=$sourceOpen '
        'protection=$protection elapsed=$elapsed';
  }
}
