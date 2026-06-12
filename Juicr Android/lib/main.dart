import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/app_integrity.dart';
import 'src/account_library_sync_service.dart';
import 'src/app_state.dart';
import 'src/ad_policy.dart';
import 'src/diagnostic_log.dart';
import 'src/runtime_app_policy_service.dart';
import 'src/system_ui.dart';

final Stopwatch _startupStopwatch = Stopwatch()..start();
bool _startupFirstFrameLogged = false;

Future<void> main() async {
  await (runZonedGuarded<Future<void>>(() async {
        DiagnosticLog.add('startup main entered elapsedMs=0');
        WidgetsFlutterBinding.ensureInitialized();
        DiagnosticLog.add(
          'startup binding ready elapsedMs=${_startupStopwatch.elapsedMilliseconds}',
        );
        FlutterError.onError = (details) {
          DiagnosticLog.flutterError(details);
          FlutterError.presentError(details);
        };
        ui.PlatformDispatcher.instance.onError = (error, stack) {
          DiagnosticLog.asyncError(error, stack);
          return true;
        };
        ErrorWidget.builder = (details) {
          DiagnosticLog.flutterError(details);
          return _AppErrorFallback(message: details.exceptionAsString());
        };

        unawaited(restoreJuicrSystemUi());
        runApp(const _BootstrapApp());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_startupFirstFrameLogged) return;
          _startupFirstFrameLogged = true;
          DiagnosticLog.add(
            'startup first flutter frame elapsedMs=${_startupStopwatch.elapsedMilliseconds}',
          );
          DiagnosticLog.viewTiming(
            surface: 'startup',
            state: 'first_frame',
            elapsed: _startupStopwatch.elapsed,
            cacheStateBucket: 'local_boot',
            mediaKind: 'shell',
          );
        });
        DiagnosticLog.add(
          'startup runApp submitted elapsedMs=${_startupStopwatch.elapsedMilliseconds}',
        );
      }, DiagnosticLog.asyncError) ??
      Future<void>.value());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  static const String _splashAssetPath = 'assets/splash/juicr_splash.gif';
  static const Duration _splashLoopGuard = Duration(milliseconds: 80);
  static const Duration _splashFallbackDuration = Duration(milliseconds: 1800);
  static const Duration _splashMaxDuration = Duration(milliseconds: 6000);

  bool _bootComplete = false;
  bool _minimumSplashComplete = false;
  bool _splashHoldStarted = false;
  bool _splashReleaseLogged = false;

  @override
  void initState() {
    super.initState();
    DiagnosticLog.add(
      'startup flutter splash shown mode=asset_duration '
      'loopGuardMs=${_splashLoopGuard.inMilliseconds} '
      'fallbackMs=${_splashFallbackDuration.inMilliseconds}',
    );
    unawaited(_boot());
  }

  void _handleSplashPresented() {
    if (_splashHoldStarted) return;
    _splashHoldStarted = true;
    DiagnosticLog.add(
      'startup flutter splash presented elapsedMs=${_startupStopwatch.elapsedMilliseconds}',
    );
    unawaited(_holdMinimumSplash());
  }

  Future<void> _holdMinimumSplash() async {
    final elapsed = Stopwatch()..start();
    final targetDuration = await _resolveSplashHoldDuration();
    final remaining = targetDuration - elapsed.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (!mounted) return;
    DiagnosticLog.add(
      'startup flutter splash minimum '
      'durationMs=${targetDuration.inMilliseconds} '
      'elapsedMs=${_startupStopwatch.elapsedMilliseconds}',
    );
    setState(() {
      _minimumSplashComplete = true;
    });
    _releaseSplashIfReady();
  }

  Future<Duration> _resolveSplashHoldDuration() async {
    try {
      final data = await rootBundle.load(_splashAssetPath);
      final animationDuration = _readGifAnimationDuration(data);
      if (animationDuration <= Duration.zero) return _splashFallbackDuration;
      final target = animationDuration - _splashLoopGuard;
      if (target <= Duration.zero) return _splashFallbackDuration;
      if (target > _splashMaxDuration) return _splashMaxDuration;
      return target;
    } catch (error) {
      DiagnosticLog.add(
        'startup flutter splash duration fallback error=${error.runtimeType}',
      );
      return _splashFallbackDuration;
    }
  }

  Duration _readGifAnimationDuration(ByteData data) {
    var centiseconds = 0;
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    for (var index = 0; index + 7 < bytes.length; index += 1) {
      final isGraphicControlExtension =
          bytes[index] == 0x21 &&
          bytes[index + 1] == 0xF9 &&
          bytes[index + 2] == 0x04;
      if (!isGraphicControlExtension) continue;
      final delay = (bytes[index + 4] | (bytes[index + 5] << 8)).toInt();
      centiseconds += delay;
    }
    return Duration(milliseconds: centiseconds * 10);
  }

  Future<void> _boot() async {
    try {
      final bootStopwatch = Stopwatch()..start();
      DiagnosticLog.add(
        'startup bootstrap boot started elapsedMs=${_startupStopwatch.elapsedMilliseconds}',
      );
      final prefsStopwatch = Stopwatch()..start();
      final prefs = await SharedPreferences.getInstance();
      final prefsMs = prefsStopwatch.elapsedMilliseconds;
      final appStateStopwatch = Stopwatch()..start();
      await AppState.init(prefs: prefs);
      AccountLibrarySyncService.install();
      unawaited(RuntimeAppPolicyService.refresh());
      unawaited(AppState.syncSignedInLibrary(replaceWithRemoteSnapshot: true));
      final appStateMs = appStateStopwatch.elapsedMilliseconds;
      final diagnosticsStopwatch = Stopwatch()..start();
      await DiagnosticLog.initPersistentSession(prefs: prefs);
      final diagnosticsMs = diagnosticsStopwatch.elapsedMilliseconds;
      DiagnosticLog.add(
        'startup boot timings prefsMs=$prefsMs appStateMs=$appStateMs diagnosticsMs=$diagnosticsMs totalMs=${bootStopwatch.elapsedMilliseconds} sinceMainMs=${_startupStopwatch.elapsedMilliseconds}',
      );
      DiagnosticLog.add(
        'app boot complete elapsed=${bootStopwatch.elapsedMilliseconds}ms',
      );
      if (mounted) {
        setState(() {
          _bootComplete = true;
        });
        _releaseSplashIfReady();
      }
      unawaited(_runDeferredStartupWork());
    } catch (error, stack) {
      DiagnosticLog.asyncError(error, stack);
      if (mounted) {
        setState(() {
          _bootComplete = true;
        });
        _releaseSplashIfReady();
      }
    }
  }

  void _releaseSplashIfReady() {
    if (!_bootComplete || !_minimumSplashComplete) {
      return;
    }
    if (_splashReleaseLogged) return;
    setState(() {
      _splashReleaseLogged = true;
    });
    DiagnosticLog.add(
      'startup flutter splash released elapsedMs=${_startupStopwatch.elapsedMilliseconds}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_splashReleaseLogged) return const StreamCatalogApp();
    return _buildSplashApp();
  }

  Widget _buildSplashApp() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState.themeMode,
      builder: (context, themeMode, _) {
        final effectiveThemeMode = _bootComplete ? themeMode : ThemeMode.dark;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: effectiveThemeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF5F7F2),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF131218),
          ),
          home: JuicrBootSplash(onPresented: _handleSplashPresented),
        );
      },
    );
  }
}

Future<void> _runDeferredStartupWork() async {
  await Future<void>.delayed(const Duration(milliseconds: 6500));
  await _waitForInteractionQuiet();
  unawaited(AppIntegrityService.instance.observeBoot());
  await Future<void>.delayed(const Duration(milliseconds: 3500));
  await _waitForInteractionQuiet();
  unawaited(JuicrAdPolicy.initialize());
}

Future<void> _waitForInteractionQuiet() async {
  final quietRemaining = AppState.interactionQuietRemaining();
  if (quietRemaining > Duration.zero) {
    await Future<void>.delayed(quietRemaining);
  }
}

class _AppErrorFallback extends StatelessWidget {
  const _AppErrorFallback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final summary = _safeErrorSummary(message);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF0E1013),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF171A1F),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF1F8D5A)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 28,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Colors.white,
                    decoration: TextDecoration.none,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.construction_rounded,
                            color: Color(0xFF55D98A),
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Juicr hit a snag',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'This screen failed to draw, but Juicr saved the diagnostic trail locally.',
                        style: TextStyle(
                          color: Color(0xFFD5D8DF),
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Open Settings > About & diagnostics > Copy diagnostic report, then send it here so we can fix the exact path.',
                        style: TextStyle(
                          color: Color(0xFFD5D8DF),
                          decoration: TextDecoration.none,
                        ),
                      ),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101318),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF2A3038)),
                          ),
                          child: Text(
                            'Technical clue: $summary',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB6BBC7),
                              decoration: TextDecoration.none,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _safeErrorSummary(String value) {
    final firstLine = value
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return '';
    return firstLine
        .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '[link]')
        .replaceAll(RegExp(r'[A-Za-z0-9_-]{32,}'), '[redacted]')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
