import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'app_state.dart';
import 'app_shell.dart';
import 'diagnostic_log.dart';
import 'first_run_welcome_page.dart';
import 'notification_orchestrator.dart';
import 'release_changelog_view.dart';
import 'release_updates.dart';
import 'stream_api.dart';
import 'system_ui.dart';
import 'visual_style.dart';

const _juicrGreen = Color(0xFF1DB954);
const _juicrBrightGreen = Color(0xFF1ED760);
const _juicrDarkBase = Color(0xFF131218);
const _juicrDarkSurface = Color(0xFF17161C);
const _juicrDarkCard = Color(0xFF1C1D20);
const _juicrDarkCardLow = Color(0xFF17191A);
const _juicrDarkCardHigh = Color(0xFF232429);
const _juicrDarkBorder = Color(0xFF34343B);
const _juicrLightSurface = Color(0xFFF5F7F2);
const _juicrLightText = Color(0xFF121212);

class StreamCatalogApp extends StatefulWidget {
  const StreamCatalogApp({super.key});

  @override
  State<StreamCatalogApp> createState() => _StreamCatalogAppState();
}

class _StreamCatalogAppState extends State<StreamCatalogApp>
    with WidgetsBindingObserver {
  final StreamApi _api = StreamApi();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final NotificationOrchestrator _notificationOrchestrator =
      NotificationOrchestrator(api: _api, navigatorKey: _navigatorKey);
  bool _crashPromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DiagnosticLog.sessionRevision.addListener(_handleDiagnosticSessionChanged);
    AppState.notificationSettingsRevision.addListener(
      _handleNotificationSettingsChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowCrashPrompt();
      unawaited(_refreshProviderHealthAfterStartup());
      unawaited(_checkNotificationsAfterStartup());
      unawaited(_maybeCheckReleaseOnLaunch());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DiagnosticLog.sessionRevision.removeListener(
      _handleDiagnosticSessionChanged,
    );
    AppState.notificationSettingsRevision.removeListener(
      _handleNotificationSettingsChanged,
    );
    _api.close();
    super.dispose();
  }

  void _handleDiagnosticSessionChanged() {
    unawaited(_maybeShowCrashPrompt());
  }

  void _handleNotificationSettingsChanged() {
    unawaited(_notificationOrchestrator.check(reason: 'settings_changed'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    DiagnosticLog.add('app lifecycle state=${state.name}');
    if (state == AppLifecycleState.resumed) {
      scheduleJuicrSystemUiRestore();
      DiagnosticLog.markSessionRunning('resumed');
      unawaited(AppState.syncSignedInLibrary(replaceWithRemoteSnapshot: true));
      unawaited(_notificationOrchestrator.check(reason: 'resumed'));
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      DiagnosticLog.markSessionClean(state.name);
    }
  }

  Future<void> _maybeShowCrashPrompt() async {
    if (!mounted || _crashPromptShown || !DiagnosticLog.shouldShowCrashPrompt) {
      return;
    }
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeShowCrashPrompt(),
      );
      return;
    }
    _crashPromptShown = true;
    DiagnosticLog.add(
      'crash recovery prompt shown '
      'previousSession=${DiagnosticLog.previousSessionId} '
      'classification=${DiagnosticLog.previousSessionExit}',
    );
    final send = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Whoops, that wasn't supposed to happen"),
        content: const Text(
          'Juicr closed unexpectedly last time. You can send a private diagnostic ticket to help us fix it.\n\n'
          'The report is redacted before sending and avoids private account, source, playback, and tracking details.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Don't send"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send report'),
          ),
        ],
      ),
    );
    if (send == true) {
      await _sendCrashReport();
    } else {
      DiagnosticLog.add('crash recovery prompt dismissed');
      await DiagnosticLog.dismissCrashPrompt();
    }
  }

  Future<void> _refreshProviderHealthAfterStartup() async {
    await Future<void>.delayed(const Duration(milliseconds: 8500));
    if (!mounted || !AppState.defaultProvidersEnabled.value) return;
    final quietRemaining = AppState.interactionQuietRemaining();
    if (quietRemaining > Duration.zero) {
      await Future<void>.delayed(quietRemaining);
      if (!mounted || !AppState.defaultProvidersEnabled.value) return;
    }
    await _api.refreshNativeProviderServerHealth();
  }

  Future<void> _checkNotificationsAfterStartup() async {
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    await _notificationOrchestrator.check(reason: 'startup');
  }

  Future<void> _maybeCheckReleaseOnLaunch() async {
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    if (!mounted || !AppState.releaseCheckOnLaunchEnabled.value) return;
    try {
      final installInfo = await DiagnosticLog.installInfo();
      final versionName = (installInfo['versionName'] ?? '').toString().trim();
      final channel = releaseChannelForVersion(versionName);
      final release = await ReleaseUpdatesClient().latestForChannel(channel);
      if (!mounted ||
          release.fromFallback ||
          !AppState.releaseMessageOnLaunchEnabled.value) {
        return;
      }
      final installed = _normalizeReleaseVersion(versionName);
      final latest = _normalizeReleaseVersion(release.displayVersion);
      if (installed.isEmpty || latest.isEmpty || installed == latest) return;
      final context = _navigatorKey.currentContext;
      if (context == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            channel == ReleaseUpdateChannel.nightly
                ? 'A newer nightly is available: ${release.displayVersion}.'
                : 'A newer release is available: ${release.displayVersion}.',
          ),
          action: SnackBarAction(
            label: 'Changelog',
            onPressed: () => _showLaunchReleaseChangelog(release),
          ),
        ),
      );
    } catch (error) {
      DiagnosticLog.add('release launch check skipped reason=$error');
    }
  }

  String _normalizeReleaseVersion(String value) {
    var text = value.trim().toLowerCase();
    if (text.startsWith('v')) text = text.substring(1);
    final plusIndex = text.indexOf('+');
    if (plusIndex >= 0) text = text.substring(0, plusIndex);
    return text.trim();
  }

  Future<void> _showLaunchReleaseChangelog(ReleaseUpdateInfo release) async {
    final dialogContext = _navigatorKey.currentContext;
    if (!mounted || dialogContext == null) return;
    final body = release.body.trim().isEmpty
        ? fallbackChangelog(release.channel)
        : release.body.trim();
    await showDialog<void>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text(
          release.channel == ReleaseUpdateChannel.nightly
              ? 'Nightly changelog'
              : 'Release changelog',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(child: ReleaseChangelogView(body: body)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendCrashReport() async {
    await DiagnosticLog.refreshBatteryEvidenceForReport('crash_report');
    final report = DiagnosticLog.uploadReport();
    try {
      DiagnosticLog.add('crash recovery report submitted');
      final ticketId = await _api.sendDiagnosticReport(report);
      DiagnosticLog.add('crash recovery ticket created id=$ticketId');
      await DiagnosticLog.dismissCrashPrompt();
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: ticketId));
      await showDialog<void>(
        context: _navigatorKey.currentContext ?? context,
        builder: (context) => AlertDialog(
          title: const Text('Crash report sent'),
          content: Text(
            'Your ticket number is $ticketId.\n\n'
            'It was copied to your clipboard so you can reference it later.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: ticketId));
                Navigator.of(context).pop();
              },
              child: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      DiagnosticLog.add('crash recovery report failed error=$error');
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: report));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report copied. Upload unavailable.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState.themeMode,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AppState.pureBlackTheme,
          builder: (context, pureBlack, __) {
            return ValueListenableBuilder<String>(
              valueListenable: AppState.accentThemeId,
              builder: (context, _, ___) {
                return ValueListenableBuilder<Color>(
                  valueListenable: AppState.customAccentColor,
                  builder: (context, ____, _____) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: AppState.useDeviceAccent,
                      builder: (context, useDeviceAccent, ______) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: AppState.compactLayout,
                          builder: (context, compactLayout, _______) {
                            return ValueListenableBuilder<bool>(
                              valueListenable: AppState.reduceMotion,
                              builder: (context, reduceMotion, ________) {
                                return ValueListenableBuilder<String>(
                                  valueListenable: AppState.textSize,
                                  builder: (context, __, _________) {
                                    return ValueListenableBuilder<String>(
                                      valueListenable:
                                          AppState.statusMessageStyle,
                                      builder: (context, statusMessageStyle, __________) {
                                        return ValueListenableBuilder<String>(
                                          valueListenable:
                                              AppState.systemBarStyle,
                                          builder: (context, systemBarStyle, ___________) {
                                            Widget buildApp(
                                              ColorScheme? lightDynamicScheme,
                                              ColorScheme? darkDynamicScheme,
                                            ) {
                                              final dynamicAvailable =
                                                  useDeviceAccent &&
                                                  lightDynamicScheme != null &&
                                                  darkDynamicScheme != null;
                                              final accent = dynamicAvailable
                                                  ? lightDynamicScheme.primary
                                                  : AppState
                                                        .effectiveAccentColor;
                                              final darkBase = pureBlack
                                                  ? Colors.black
                                                  : _juicrDarkBase;
                                              final lightBase =
                                                  _juicrLightSurface;
                                              final visualDensity =
                                                  compactLayout
                                                  ? VisualDensity.compact
                                                  : VisualDensity.standard;
                                              return MaterialApp(
                                                navigatorKey: _navigatorKey,
                                                debugShowCheckedModeBanner:
                                                    false,
                                                title: 'Juicr',
                                                themeMode: themeMode,
                                                themeAnimationDuration:
                                                    Duration.zero,
                                                themeAnimationCurve:
                                                    Curves.linear,
                                                theme: _lightTheme(
                                                  accent: accent,
                                                  dynamicScheme:
                                                      dynamicAvailable
                                                      ? lightDynamicScheme
                                                      : null,
                                                  visualDensity: visualDensity,
                                                  reduceMotion: reduceMotion,
                                                  statusMessageStyle:
                                                      statusMessageStyle,
                                                ),
                                                darkTheme: _darkTheme(
                                                  accent: dynamicAvailable
                                                      ? darkDynamicScheme
                                                            .primary
                                                      : accent,
                                                  dynamicScheme:
                                                      dynamicAvailable
                                                      ? darkDynamicScheme
                                                      : null,
                                                  pureBlack: pureBlack,
                                                  visualDensity: visualDensity,
                                                  reduceMotion: reduceMotion,
                                                  statusMessageStyle:
                                                      statusMessageStyle,
                                                ),
                                                builder: (context, child) {
                                                  final isDark =
                                                      Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark;
                                                  final content = MediaQuery(
                                                    data: MediaQuery.of(context)
                                                        .copyWith(
                                                          textScaler:
                                                              TextScaler.linear(
                                                                AppState
                                                                    .textScaleFactor,
                                                              ),
                                                        ),
                                                    child:
                                                        child ??
                                                        const SizedBox.shrink(),
                                                  );
                                                  return AnnotatedRegion<
                                                    SystemUiOverlayStyle
                                                  >(
                                                    value: _systemOverlayStyle(
                                                      isDark: isDark,
                                                      style: systemBarStyle,
                                                      darkBase: darkBase,
                                                      lightBase: lightBase,
                                                    ),
                                                    child: content,
                                                  );
                                                },
                                                home: ValueListenableBuilder<bool>(
                                                  valueListenable:
                                                      AppState.preferencesReady,
                                                  builder: (context, ready, _) {
                                                    if (!ready) {
                                                      return const JuicrBootSplash();
                                                    }
                                                    return ValueListenableBuilder<
                                                      bool
                                                    >(
                                                      valueListenable: AppState
                                                          .firstRunWelcomeSeen,
                                                      builder: (context, seen, _) {
                                                        return seen
                                                            ? const AppShell()
                                                            : const FirstRunWelcomePage();
                                                      },
                                                    );
                                                  },
                                                ),
                                              );
                                            }

                                            if (!useDeviceAccent) {
                                              return buildApp(null, null);
                                            }
                                            return DynamicColorBuilder(
                                              builder: buildApp,
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class JuicrBootSplash extends StatelessWidget {
  const JuicrBootSplash({super.key, this.onPresented});

  final VoidCallback? onPresented;

  @override
  Widget build(BuildContext context) {
    final onPresented = this.onPresented;
    if (onPresented != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onPresented());
    }
    final theme = Theme.of(context);
    final background = theme.scaffoldBackgroundColor;
    final splashSize = (MediaQuery.sizeOf(context).shortestSide * 0.42).clamp(
      168.0,
      220.0,
    );
    return Scaffold(
      backgroundColor: background,
      body: Center(
        child: Image.asset(
          'assets/splash/juicr_splash.gif',
          width: splashSize,
          height: splashSize,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

SystemUiOverlayStyle _systemOverlayStyle({
  required bool isDark,
  required String style,
  required Color darkBase,
  required Color lightBase,
}) {
  final background = switch (style) {
    'black' => Colors.black,
    'transparent' => Colors.transparent,
    _ => isDark ? darkBase : lightBase,
  };
  final icons = isDark || style == 'black' ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: style == 'transparent' ? Colors.transparent : background,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: icons == Brightness.light
        ? Brightness.dark
        : Brightness.light,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );
}

SnackBarBehavior _snackBarBehavior(String style) {
  return style == 'bottom' ? SnackBarBehavior.fixed : SnackBarBehavior.floating;
}

EdgeInsets _snackBarInsetPadding(String style) {
  return switch (style) {
    'quiet' => const EdgeInsets.fromLTRB(28, 0, 28, 34),
    'bottom' => EdgeInsets.zero,
    _ => const EdgeInsets.fromLTRB(16, 0, 16, 24),
  };
}

Color _brightAccent(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withSaturation((hsl.saturation + 0.12).clamp(0.0, 1.0))
      .withLightness((hsl.lightness + 0.12).clamp(0.48, 0.72))
      .toColor();
}

Color _lightPrimaryAccent(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withSaturation((hsl.saturation + 0.04).clamp(0.0, 1.0))
      .withLightness((hsl.lightness - 0.12).clamp(0.28, 0.48))
      .toColor();
}

Color _accentTintedLightSurface(Color accent, double alpha) {
  return Color.alphaBlend(accent.withValues(alpha: alpha), _juicrLightSurface);
}

Color _accentTintedLightBorder(Color accent) {
  return Color.alphaBlend(
    accent.withValues(alpha: 0.22),
    const Color(0xFFDCE0EA),
  );
}

ThemeData _darkTheme({
  required Color accent,
  ColorScheme? dynamicScheme,
  required bool pureBlack,
  required VisualDensity visualDensity,
  required bool reduceMotion,
  required String statusMessageStyle,
}) {
  final brightAccent = _brightAccent(accent);
  final darkBase = pureBlack ? Colors.black : _juicrDarkBase;
  final darkSurface = pureBlack ? Colors.black : _juicrDarkSurface;
  final darkCard = pureBlack ? const Color(0xFF070707) : _juicrDarkCard;
  final darkCardLow = pureBlack ? const Color(0xFF050505) : _juicrDarkCardLow;
  final darkCardHigh = pureBlack ? const Color(0xFF101010) : _juicrDarkCardHigh;
  final darkBorder = pureBlack ? const Color(0xFF272727) : _juicrDarkBorder;
  final seededScheme =
      dynamicScheme ??
      ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: accent,
        primary: accent,
        secondary: brightAccent,
        surface: darkSurface,
      ).copyWith(
        surfaceContainerLowest: darkBase,
        surfaceContainerLow: darkCardLow,
        surfaceContainer: darkCard,
        surfaceContainerHigh: darkCardHigh,
        surfaceContainerHighest: darkCardHigh,
        outlineVariant: darkBorder,
        surfaceTint: Colors.transparent,
      );
  final colorScheme = seededScheme.copyWith(
    primary: accent,
    secondary: dynamicScheme?.secondary ?? brightAccent,
    surface: darkSurface,
    surfaceContainerLowest: darkBase,
    surfaceContainerLow: darkCardLow,
    surfaceContainer: darkCard,
    surfaceContainerHigh: darkCardHigh,
    surfaceContainerHighest: darkCardHigh,
    outline: darkBorder,
    outlineVariant: darkBorder.withValues(alpha: 0.72),
    surfaceTint: Colors.transparent,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    visualDensity: visualDensity,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    pageTransitionsTheme: _pageTransitionsTheme(reduceMotion),
    colorScheme: colorScheme,
    scaffoldBackgroundColor: darkBase,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ),
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w900,
      ),
    ),
    cardTheme: _cardTheme(colorScheme),
    bottomSheetTheme: _bottomSheetTheme(colorScheme, darkBase),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _elevatedButtonStyle(colorScheme),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _filledButtonStyle(colorScheme),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _outlinedButtonStyle(colorScheme),
    ),
    textButtonTheme: TextButtonThemeData(style: _textButtonStyle(colorScheme)),
    iconButtonTheme: IconButtonThemeData(style: _iconButtonStyle(colorScheme)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return brightAccent;
        }
        return colorScheme.onSurface.withValues(alpha: 0.72);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accent.withValues(alpha: 0.58);
        }
        return colorScheme.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accent.withValues(alpha: 0.7);
        }
        return colorScheme.outlineVariant.withValues(alpha: 0.8);
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(JuicrVisual.softRadius),
        borderSide: BorderSide(color: darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(JuicrVisual.softRadius),
        borderSide: BorderSide(color: darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(JuicrVisual.softRadius),
        borderSide: BorderSide(color: brightAccent, width: 1.4),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: darkBase,
      indicatorColor: Colors.transparent,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? brightAccent : Colors.white54,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? brightAccent : Colors.white54,
          size: 27,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: _snackBarBehavior(statusMessageStyle),
      insetPadding: _snackBarInsetPadding(statusMessageStyle),
      backgroundColor: darkCard,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

ThemeData _lightTheme({
  required Color accent,
  ColorScheme? dynamicScheme,
  required VisualDensity visualDensity,
  required bool reduceMotion,
  required String statusMessageStyle,
}) {
  final lightPrimary = _lightPrimaryAccent(accent);
  final lightCard = _accentTintedLightSurface(accent, 0.1);
  final lightCardHigh = _accentTintedLightSurface(accent, 0.16);
  final lightBorder = _accentTintedLightBorder(accent);
  final seededScheme =
      dynamicScheme ??
      ColorScheme.fromSeed(
        brightness: Brightness.light,
        seedColor: accent,
        primary: lightPrimary,
        secondary: accent,
        surface: _juicrLightSurface,
      ).copyWith(
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: _juicrLightSurface,
        surfaceContainer: lightCard,
        surfaceContainerHigh: lightCardHigh,
        surfaceContainerHighest: lightCardHigh,
        outlineVariant: lightBorder,
        surfaceTint: Colors.transparent,
      );
  final colorScheme = seededScheme.copyWith(
    primary: dynamicScheme?.primary ?? lightPrimary,
    secondary: dynamicScheme?.secondary ?? accent,
    surface: _juicrLightSurface,
    surfaceContainerLowest: _juicrLightSurface,
    surfaceContainerLow: Colors.white,
    surfaceContainer: lightCard,
    surfaceContainerHigh: lightCardHigh,
    surfaceContainerHighest: lightCardHigh,
    outline: lightBorder,
    outlineVariant: lightBorder,
    surfaceTint: Colors.transparent,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    visualDensity: visualDensity,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    pageTransitionsTheme: _pageTransitionsTheme(reduceMotion),
    colorScheme: colorScheme,
    scaffoldBackgroundColor: _juicrLightSurface,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ),
      titleTextStyle: TextStyle(
        color: _juicrLightText,
        fontSize: 22,
        fontWeight: FontWeight.w900,
      ),
    ),
    cardTheme: _cardTheme(colorScheme),
    bottomSheetTheme: _bottomSheetTheme(colorScheme, _juicrLightSurface),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _elevatedButtonStyle(colorScheme),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _filledButtonStyle(colorScheme),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _outlinedButtonStyle(colorScheme),
    ),
    textButtonTheme: TextButtonThemeData(style: _textButtonStyle(colorScheme)),
    iconButtonTheme: IconButtonThemeData(style: _iconButtonStyle(colorScheme)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(JuicrVisual.softRadius),
        borderSide: const BorderSide(color: Color(0xFFDCE0EA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(JuicrVisual.softRadius),
        borderSide: const BorderSide(color: Color(0xFFDCE0EA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(JuicrVisual.softRadius),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: Colors.white,
      indicatorColor: Colors.transparent,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? lightPrimary : Colors.black54,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? lightPrimary : Colors.black54,
          size: 27,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: _snackBarBehavior(statusMessageStyle),
      insetPadding: _snackBarInsetPadding(statusMessageStyle),
      backgroundColor: Colors.white,
      contentTextStyle: const TextStyle(
        color: _juicrLightText,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

PageTransitionsTheme _pageTransitionsTheme(bool reduceMotion) {
  if (!reduceMotion) return const PageTransitionsTheme();
  return const PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: _NoPageTransitionsBuilder(),
      TargetPlatform.iOS: _NoPageTransitionsBuilder(),
      TargetPlatform.macOS: _NoPageTransitionsBuilder(),
      TargetPlatform.windows: _NoPageTransitionsBuilder(),
      TargetPlatform.linux: _NoPageTransitionsBuilder(),
    },
  );
}

class _NoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

CardThemeData _cardTheme(ColorScheme colorScheme) {
  return CardThemeData(
    color: JuicrVisual.flatCardColor(colorScheme),
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(JuicrVisual.cardRadius),
      side: BorderSide(
        color: JuicrVisual.flatCardBorder(colorScheme),
        width: JuicrVisual.cardStrokeWidth,
      ),
    ),
  );
}

BottomSheetThemeData _bottomSheetTheme(
  ColorScheme colorScheme,
  Color backgroundColor,
) {
  return BottomSheetThemeData(
    backgroundColor: backgroundColor,
    surfaceTintColor: Colors.transparent,
    shape: JuicrVisual.bottomSheetShape,
    clipBehavior: Clip.antiAlias,
    dragHandleColor: colorScheme.onSurface.withValues(alpha: 0.62),
  );
}

ButtonStyle _filledButtonStyle(ColorScheme colorScheme) {
  return FilledButton.styleFrom(
    minimumSize: const Size(64, 40),
    padding: JuicrVisual.buttonPadding,
    shape: const StadiumBorder(),
    textStyle: JuicrVisual.buttonTextStyle,
  ).copyWith(
    animationDuration: JuicrVisual.snapDuration,
    overlayColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.pressed)
          ? colorScheme.onPrimary.withValues(alpha: 0.12)
          : null,
    ),
  );
}

ButtonStyle _elevatedButtonStyle(ColorScheme colorScheme) {
  return ElevatedButton.styleFrom(
    minimumSize: const Size(64, 40),
    padding: JuicrVisual.buttonPadding,
    backgroundColor: colorScheme.surfaceContainerLow,
    foregroundColor: colorScheme.primary,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.black.withValues(
      alpha: colorScheme.brightness == Brightness.dark ? 0.36 : 0.16,
    ),
    shape: const StadiumBorder(),
    textStyle: JuicrVisual.buttonTextStyle,
  ).copyWith(
    animationDuration: JuicrVisual.snapDuration,
    elevation: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return 0;
      if (states.contains(WidgetState.pressed)) return 0;
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return 3;
      }
      return 1;
    }),
  );
}

ButtonStyle _outlinedButtonStyle(ColorScheme colorScheme) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(64, 40),
    padding: JuicrVisual.buttonPadding,
    backgroundColor: colorScheme.surfaceContainerLow,
    foregroundColor: colorScheme.primary,
    shape: const StadiumBorder(),
    side: BorderSide.none,
    textStyle: JuicrVisual.buttonTextStyle,
  ).copyWith(
    animationDuration: JuicrVisual.snapDuration,
    overlayColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.pressed)
          ? colorScheme.primary.withValues(alpha: 0.12)
          : null,
    ),
  );
}

ButtonStyle _textButtonStyle(ColorScheme colorScheme) {
  return TextButton.styleFrom(
    minimumSize: const Size(48, 40),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    foregroundColor: colorScheme.primary,
    shape: const StadiumBorder(),
    textStyle: JuicrVisual.buttonTextStyle,
  ).copyWith(
    animationDuration: JuicrVisual.snapDuration,
    overlayColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.pressed)
          ? colorScheme.primary.withValues(alpha: 0.12)
          : null,
    ),
  );
}

ButtonStyle _iconButtonStyle(ColorScheme colorScheme) {
  return IconButton.styleFrom(
    minimumSize: const Size.square(40),
    shape: const CircleBorder(),
    foregroundColor: colorScheme.onSurfaceVariant,
  ).copyWith(
    animationDuration: JuicrVisual.snapDuration,
    overlayColor: WidgetStateProperty.all(Colors.transparent),
  );
}
