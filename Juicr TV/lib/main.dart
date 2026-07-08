import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'libvlc_hls_relay.dart';
import 'tv_account_state.dart';
import 'tv_input.dart';
import 'tv_library_state.dart';
import 'tv_playback_request.dart';

part 'tv_shell_widgets.dart';
part 'tv_surfaces.dart';
part 'tv_playback.dart';
part 'tv_shared_widgets.dart';
part 'tv_release_updates.dart';
part 'tv_data.dart';

const _apiBase = 'https://api.juicr.app';
const _tvSettingsPrefsKey = 'juicr_tv_settings_v1';
const _tvCatalogWarmSnapshotPrefsKey = 'juicr_tv_catalog_warm_snapshot_v1';
const _tvVerifiedPlaybackSessionsPrefsKey =
    'juicr_tv_verified_playback_sessions_v2';
const _tvAppVersion = '1.0.1';
const _tvAppBuildNumber = '2';
const _tvAppPackageName = 'app.juicr.flutter';
const _juicrGreen = Color(0xFF20D66B);
const double _tvSpacing = 12;
const double _tvNavigationRailWidth = 94;
const double _tvNavItemGap = 4;
const double _tvPosterGridGap = 6;
const double _tvHomeRailGap = 8;
Color _tvAccentColor = _juicrGreen;
double _tvTextScale = 1.0;
bool _tvMotionEnabled = true;
_TvThemePalette _tvTheme = _TvThemePalette.dark;

Color get _tvFocusBorder => _tvAccentColor;
Color get _tvSolidFocusBorder => Colors.white;

class _TvThemePalette {
  const _TvThemePalette({
    required this.background,
    required this.backdropGradient,
    required this.railGradient,
    required this.railBorder,
    required this.card,
    required this.cardAlt,
    required this.dialog,
    required this.row,
    required this.rowBorder,
    required this.text,
    required this.muted,
    required this.valuePill,
    required this.valuePillBorder,
  });

  final Color background;
  final List<Color> backdropGradient;
  final List<Color> railGradient;
  final Color railBorder;
  final Color card;
  final Color cardAlt;
  final Color dialog;
  final Color row;
  final Color rowBorder;
  final Color text;
  final Color muted;
  final Color valuePill;
  final Color valuePillBorder;

  static const dark = _TvThemePalette(
    background: Color(0xFF000000),
    backdropGradient: [Color(0xFF000000), Color(0xFF000000), Color(0xFF000000)],
    railGradient: [Color(0x1AFFFFFF), Color(0x1131313C), Color(0x1AFFFFFF)],
    railBorder: Color(0x18FFFFFF),
    card: Color(0x1AFFFFFF),
    cardAlt: Color(0x18FFFFFF),
    dialog: Color(0xF2202124),
    row: Color(0x1FFFFFFF),
    rowBorder: Color(0x22FFFFFF),
    text: Colors.white,
    muted: Color(0xFFAAA6BD),
    valuePill: Color(0x1FFFFFFF),
    valuePillBorder: Color(0x22FFFFFF),
  );

  static const amoled = _TvThemePalette(
    background: Color(0xFF000000),
    backdropGradient: [Color(0xFF000000), Color(0xFF000000), Color(0xFF000000)],
    railGradient: [Color(0xFF050505), Color(0xFF000000), Color(0xFF050505)],
    railBorder: Color(0x26FFFFFF),
    card: Color(0xFF090A0D),
    cardAlt: Color(0xFF101115),
    dialog: Color(0xFF101115),
    row: Color(0xFF17181D),
    rowBorder: Color(0x29FFFFFF),
    text: Colors.white,
    muted: Color(0xFFC0BBD0),
    valuePill: Color(0xFF202126),
    valuePillBorder: Color(0x29FFFFFF),
  );

  static const light = _TvThemePalette(
    background: Color(0xFFE1DDD2),
    backdropGradient: [Color(0xFFD5D1C7), Color(0xFFE1DDD2), Color(0xFFCFD8D1)],
    railGradient: [Color(0xE6D7D3C8), Color(0xD9CAC5BA), Color(0xE6D7D3C8)],
    railBorder: Color(0x26000000),
    card: Color(0xF2ECE8DE),
    cardAlt: Color(0xFFE0DACE),
    dialog: Color(0xF7E8E4DA),
    row: Color(0xFFD8D2C6),
    rowBorder: Color(0x33000000),
    text: Color(0xFF151515),
    muted: Color(0xFF56515C),
    valuePill: Color(0xFFD8D2C6),
    valuePillBorder: Color(0x30000000),
  );
}

_TvThemePalette _themeForSetting(String theme) {
  return switch (theme) {
    'Light' => _TvThemePalette.light,
    'Amoled Black' => _TvThemePalette.amoled,
    _ => _TvThemePalette.dark,
  };
}

Color _accentForSetting(String accent) {
  return switch (accent) {
    'Purple' => const Color(0xFF9B6DFF),
    'Ocean' => const Color(0xFF00A8CC),
    'Amber' => const Color(0xFFFFB703),
    _ => _juicrGreen,
  };
}

Color _accentForSettings(_TvSettingsState settings) {
  if (settings.accent == 'Custom') return Color(settings.customAccentColor);
  return _accentForSetting(settings.accent);
}

double _textScaleForSetting(String size) {
  return switch (size) {
    'Smaller' => 0.92,
    'Large' => 1.08,
    'Larger' => 1.14,
    'Maximum' => 1.20,
    _ => 1.0,
  };
}

Duration _tvDuration(int milliseconds) {
  return _tvMotionEnabled
      ? Duration(milliseconds: milliseconds)
      : Duration.zero;
}

void _applyTvSettingsGlobals(_TvSettingsState settings) {
  _tvAccentColor = _accentForSettings(settings);
  _tvTextScale = _textScaleForSetting(settings.textSize);
  _tvMotionEnabled = settings.motion;
  _tvTheme = _themeForSetting(settings.theme);
}

enum _TvLibraryFilter {
  continueWatching(
    'Continue watching',
    'Unfinished titles',
    Icons.history_rounded,
  ),
  lists('Lists', 'Custom watchlists', Icons.bookmarks_outlined),
  movies('Movies', 'Liked movies', Icons.movie_rounded),
  series('Series', 'Liked series', Icons.tv_rounded),
  animation('Animations', 'Liked animations', Icons.auto_awesome_rounded),
  liveTv('Live TV', 'Liked live channels', Icons.live_tv_rounded),
  metrics('Metrics', 'Watching signals', Icons.insights_rounded),
  ranking('Ranking', 'Watch time leaderboard', Icons.emoji_events_outlined);

  const _TvLibraryFilter(this.label, this.subtitle, this.icon);

  final String label;
  final String subtitle;
  final IconData icon;
}

enum _TvAccountSyncState { guest, idle, syncing, synced, needsAttention }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 480;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  _installTvKeyboardErrorFilter();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const JuicrTvApp());
}

Future<T?> _showTvDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) async {
  final previousFocus = FocusManager.instance.primaryFocus;
  final result = await showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior:
        traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
    requestFocus: requestFocus ?? true,
    animationStyle: animationStyle,
  );
  _restoreTvFocusAfterRoutePop(previousFocus);
  return result;
}

void _restoreTvFocusAfterRoutePop(FocusNode? previousFocus) {
  if (previousFocus == null) return;
  void restore([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = previousFocus.context;
      if (!previousFocus.canRequestFocus ||
          context == null ||
          !context.mounted) {
        if (attempt < 5) {
          Future<void>.delayed(
            const Duration(milliseconds: 24),
            () => restore(attempt + 1),
          );
        }
        return;
      }
      previousFocus.requestFocus();
      try {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          alignment: 0.35,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      } on FlutterError {
        // Focus restoration is still useful even when the node is outside a
        // scrollable, or when the scrollable is settling after a route pop.
      }
      final primaryFocus = FocusManager.instance.primaryFocus;
      if ((primaryFocus == null || primaryFocus.context == null) &&
          attempt < 5) {
        Future<void>.delayed(
          const Duration(milliseconds: 24),
          () => restore(attempt + 1),
        );
      }
    });
  }

  restore();
}

void _installTvKeyboardErrorFilter() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_isStaleTvKeyUpAssertion(details)) return;
    if (_isBenignTvPlatformStreamCancel(details)) return;
    if (previousOnError != null) {
      previousOnError(details);
      return;
    }
    FlutterError.presentError(details);
  };
}

bool _isStaleTvKeyUpAssertion(FlutterErrorDetails details) {
  if (details.library != 'services library') return false;
  final exception = details.exceptionAsString();
  return exception.contains('A KeyUpEvent is dispatched') &&
      exception.contains('_pressedKeys.containsKey(event.physicalKey)');
}

bool _isBenignTvPlatformStreamCancel(FlutterErrorDetails details) {
  if (details.library != 'services library') return false;
  final exception = details.exceptionAsString();
  return exception.contains('MissingPluginException') &&
      exception.contains('No implementation found for method cancel') &&
      (exception.contains('flutter_video_plugin/getVideoEvents_') ||
          exception.contains('flutter_video_plugin/getRendererEvents_'));
}

class JuicrTvApp extends StatelessWidget {
  const JuicrTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Juicr TV',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF20D66B),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          width: 720,
          backgroundColor: const Color(0xFF191A23),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0x22FFFFFF)),
          ),
          insetPadding: const EdgeInsets.only(
            left: _tvNavigationRailWidth,
            bottom: _tvSpacing,
          ),
        ),
        useMaterial3: true,
      ),
      home: const TvHomePage(),
    );
  }
}

class _TvHydratedHomeSignals {
  const _TvHydratedHomeSignals({
    this.topSignal = const <_TvItem>[],
    this.todaySignal = const <_TvItem>[],
    this.juicrTopSignal = const <_TvItem>[],
  });

  final List<_TvItem> topSignal;
  final List<_TvItem> todaySignal;
  final List<_TvItem> juicrTopSignal;
}

class _TvCatalogLaneRequest {
  const _TvCatalogLaneRequest({
    required this.kind,
    required this.sort,
    required this.type,
    required this.catalogSort,
    this.fallbackType,
    this.pages = 3,
  });

  final _TvDiscoveryKind kind;
  final _TvDiscoverySort sort;
  final String type;
  final String catalogSort;
  final String? fallbackType;
  final int pages;
}

class TvHomePage extends StatefulWidget {
  const TvHomePage({super.key});

  @override
  State<TvHomePage> createState() => _TvHomePageState();
}

class _TvHomePageState extends State<TvHomePage> with WidgetsBindingObserver {
  final GlobalKey<_TvNavigationRailState> _navigationRailKey =
      GlobalKey<_TvNavigationRailState>();
  final GlobalKey _homeHeroKey = GlobalKey(debugLabel: 'tv-home-hero');
  final FocusNode _homeHeroWatchFocusNode = FocusNode(
    debugLabel: 'tv-home-hero-watch',
  );
  late final List<FocusNode> _pageEntryFocusNodes = List.generate(
    _tabItems.length,
    (index) => FocusNode(debugLabel: 'tv-page-entry-${_tabItems[index].label}'),
  );
  late final List<FocusNode> _pageContentFocusNodes = List.generate(
    _tabItems.length,
    (index) =>
        FocusNode(debugLabel: 'tv-page-content-${_tabItems[index].label}'),
  );
  late final List<FocusNode?> _lastPageFocusNodes = List<FocusNode?>.filled(
    _tabItems.length,
    null,
  );
  late final List<String?> _lastPageFocusItemKeys = List<String?>.filled(
    _tabItems.length,
    null,
  );
  late final List<String?> _pendingPageFocusItemKeys = List<String?>.filled(
    _tabItems.length,
    null,
  );
  final _api = _TvApi();
  final _items = <_TvItem>[];
  final _movies = <_TvItem>[];
  final _series = <_TvItem>[];
  final _animation = <_TvItem>[];
  final _liveTv = <_TvItem>[];
  final _discoveryLaneItems = <String, List<_TvItem>>{};
  final _discoveryLanePages = <String, int>{};
  final _discoveryLaneLoading = <String>{};
  final _discoveryLaneExhausted = <String>{};
  final _upcomingPicks = <_TvItem>[];
  List<_TvItem> _heroEditorialItems = const <_TvItem>[];
  List<_TvItem> _topSignalRemoteItems = const <_TvItem>[];
  List<_TvItem> _todaySignalRemoteItems = const <_TvItem>[];
  List<_TvItem> _juicrTopSignalRemoteItems = const <_TvItem>[];
  final _homeArtworkByKey = <String, _TvItem>{};
  final _homeArtworkHydrationKeys = <String>{};
  final _homeArtworkHydrationAttempts = <String, int>{};
  bool _homeArtworkHydrating = false;
  Future<void>? _catalogLoadFuture;
  DateTime? _catalogLoadedAt;
  final _recentItems = <_TvItem>[];
  final _likedItemKeys = <String>{};
  final _watchedProgress = <String, _TvPlaybackProgress>{};
  final _verifiedPlaybackSessions =
      <String, List<_TvVerifiedPlaybackSession>>{};
  final _accountStore = const TvAccountStateStore();
  TvLibraryStateStore? _libraryStore;
  TvAccountSession? _accountSession;
  TvAccountProfile? _accountProfile;
  String _accountLibraryRevision = '';
  int? _accountActiveWatchSeconds;
  _TvAccountSyncState _accountSyncState = _TvAccountSyncState.guest;
  Timer? _accountLibraryPushTimer;
  _TvHomeEditorialEdition? _homeEditorial;
  int _selectedTab = 0;
  bool _loading = true;
  String? _error;
  _TvItem? _selectedItem;
  _TvRail? _expandedRail;
  bool _searchOpen = false;
  int _homeHeroIndex = 0;
  int _homeHeroCarouselPauseDepth = 0;
  final GlobalKey<_TvSearchOverlayState> _searchOverlayKey =
      GlobalKey<_TvSearchOverlayState>();
  String? _preparingPlaybackKey;
  int _playRequestGeneration = 0;
  DateTime? _lastBackDispatchAt;
  DateTime? _lastExitBackPressAt;
  _TvDiscoveryKind _discoveryKind = _TvDiscoveryKind.movie;
  _TvDiscoverySort _discoverySort = _TvDiscoverySort.popular;
  String _discoveryGenre = 'All genres';
  _TvLibraryFilter _libraryFilter = _TvLibraryFilter.continueWatching;
  _TvSettingsState _tvSettings = const _TvSettingsState();
  String _lastFocusTraceLabel = 'none';

  static const _tabItems = <_TvNavItem>[
    _TvNavItem('Home', Icons.home_rounded),
    _TvNavItem('Discovery', Icons.explore_rounded),
    _TvNavItem('Library', Icons.favorite_rounded),
    _TvNavItem('Settings', Icons.settings_rounded),
  ];

  static const _navItems = <_TvNavItem>[
    _TvNavItem('Search', Icons.search_rounded),
    _TvNavItem('Home', Icons.home_rounded),
    _TvNavItem('Discovery', Icons.explore_rounded),
    _TvNavItem('Library', Icons.favorite_rounded),
    _TvNavItem('Settings', Icons.settings_rounded),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_tracePrimaryFocus);
    unawaited(_restoreTvLibraryState());
    unawaited(_restoreTvAccountState());
    unawaited(_restoreVerifiedPlaybackSessions());
    unawaited(_restoreTvSettings());
    _restoreStartupFocusAfterFrame();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_tracePrimaryFocus);
    _homeHeroWatchFocusNode.dispose();
    for (final node in _pageEntryFocusNodes) {
      node.unfocus();
      node.dispose();
    }
    for (final node in _pageContentFocusNodes) {
      node.unfocus();
      node.dispose();
    }
    _accountLibraryPushTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resyncTvKeyboardAfterResume());
    }
  }

  Future<void> _resyncTvKeyboardAfterResume() async {
    try {
      await HardwareKeyboard.instance.syncKeyboardState();
    } catch (_) {
      // Some Android TV surfaces may not answer the keyboard state query while
      // the window is settling after resume. Focus restoration is still useful.
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_primaryFocusNeedsRestore) return;
      if (_searchOpen) {
        _searchOverlayKey.currentState?.restoreFocus();
        return;
      }
      if (_selectedItem == null) {
        _enterSelectedTabContent();
      }
    });
  }

  void _tracePrimaryFocus() {
    if (!kDebugMode) return;
    final label = FocusManager.instance.primaryFocus?.debugLabel;
    final safeLabel = label == null || label.trim().isEmpty ? 'none' : label;
    if (safeLabel == _lastFocusTraceLabel) return;
    _lastFocusTraceLabel = safeLabel;
    debugPrint(
      'Juicr TV focus trace label=$safeLabel tab=${_tabItems[_selectedTab].label}',
    );
    if (safeLabel == 'none') {
      _restorePrimaryFocusIfStillMissing();
    }
  }

  void _restorePrimaryFocusIfStillMissing([int attempt = 0]) {
    Future<void>.delayed(Duration(milliseconds: 80 + attempt * 45), () {
      if (!mounted || !_primaryFocusNeedsRestore) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (_searchOpen) {
        _searchOverlayKey.currentState?.restoreFocus();
      } else if (_selectedItem == null) {
        if (attempt >= 4 && _selectedTab == 0) {
          _lastPageFocusNodes[0] = null;
          _lastPageFocusItemKeys[0] = null;
        }
        if (attempt >= 6) {
          _navigationRailKey.currentState?.focusSelected();
        } else if (attempt >= 2) {
          _focusPageEntry();
        } else {
          _enterSelectedTabContent();
        }
      }
      if (!_primaryFocusNeedsRestore || attempt >= 6) return;
      _restorePrimaryFocusIfStillMissing(attempt + 1);
    });
  }

  void _focusNavigationAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigationRailKey.currentState?.focusSelected();
    });
  }

  void _restoreStartupFocusAfterFrame([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_primaryFocusNeedsRestore) return;
      if (_searchOpen) {
        _searchOverlayKey.currentState?.restoreFocus();
      } else if (_selectedItem == null) {
        _enterSelectedTabContent();
      }
      if (attempt >= 8) {
        if (_primaryFocusNeedsRestore) {
          _navigationRailKey.currentState?.focusSelected();
        }
        return;
      }
      Future<void>.delayed(
        Duration(milliseconds: 90 + attempt * 45),
        () => _restoreStartupFocusAfterFrame(attempt + 1),
      );
    });
  }

  bool get _primaryFocusNeedsRestore {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null ||
        primaryFocus == FocusManager.instance.rootScope ||
        primaryFocus.context == null) {
      return true;
    }
    final label = primaryFocus.debugLabel?.trim() ?? '';
    return label.isEmpty ||
        label == 'none' ||
        label.startsWith('_ModalScopeState');
  }

  bool get _hasCatalogSnapshot =>
      _items.isNotEmpty ||
      _discoveryLaneItems.values.any((lane) => lane.isNotEmpty);

  bool get _hasFreshCatalogSnapshot {
    final loadedAt = _catalogLoadedAt;
    if (!_hasCatalogSnapshot || loadedAt == null) return false;
    return DateTime.now().difference(loadedAt) < const Duration(minutes: 20);
  }

  Map<String, dynamic> _catalogWarmItemJson(_TvItem item) {
    return {
      'id': item.id,
      'type': item.type,
      'title': item.title,
      if ((item.poster ?? '').trim().isNotEmpty) 'poster': item.poster,
      if ((item.background ?? '').trim().isNotEmpty)
        'background': item.background,
      if ((item.logo ?? '').trim().isNotEmpty) 'logo': item.logo,
      if ((item.year ?? '').trim().isNotEmpty) 'year': item.year,
      if (item.tmdbId != null) 'tmdbId': item.tmdbId,
      if (item.genres.isNotEmpty) 'genres': item.genres,
      if ((item.description ?? '').trim().isNotEmpty)
        'description': item.description,
      if ((item.imdbRating ?? '').trim().isNotEmpty)
        'imdbRating': item.imdbRating,
      if ((item.releaseDate ?? '').trim().isNotEmpty)
        'releaseDate': item.releaseDate,
      if (item.isUpcoming) 'isUpcoming': true,
      if ((item.runtime ?? '').trim().isNotEmpty) 'runtime': item.runtime,
    };
  }

  _TvItem? _catalogWarmItemFromJson(Object? value) {
    if (value is! Map) return null;
    try {
      final json = Map<String, dynamic>.from(value);
      final fallbackType = (json['type'] ?? 'movie').toString();
      final item = _TvItem.fromJson(json, fallbackType: fallbackType);
      if (item.id.trim().isEmpty || item.title.trim().isEmpty) return null;
      if (!_hasTvDiscoveryArtwork(item)) return null;
      return item;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _catalogWarmItemsJson(
    Iterable<_TvItem> items, {
    int limit = 80,
  }) {
    return items.take(limit).map(_catalogWarmItemJson).toList(growable: false);
  }

  List<_TvItem> _catalogWarmItemsFromJson(Object? value) {
    if (value is! List) return const <_TvItem>[];
    return value.map(_catalogWarmItemFromJson).nonNulls.toList(growable: false);
  }

  Map<String, List<_TvItem>> _catalogWarmLanesFromJson(Object? value) {
    if (value is! Map) return const <String, List<_TvItem>>{};
    final lanes = <String, List<_TvItem>>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final items = _catalogWarmItemsFromJson(entry.value);
      if (items.isNotEmpty) lanes[key] = items;
    }
    return lanes;
  }

  Future<bool> _restoreCatalogWarmSnapshot(SharedPreferences prefs) async {
    try {
      final encoded = prefs.getString(_tvCatalogWarmSnapshotPrefsKey);
      if (encoded == null || encoded.trim().isEmpty) return false;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return false;
      final snapshot = Map<String, dynamic>.from(decoded);
      final items = _catalogWarmItemsFromJson(snapshot['items']);
      final lanes = _catalogWarmLanesFromJson(snapshot['lanes']);
      if (items.isEmpty && lanes.values.every((lane) => lane.isEmpty)) {
        return false;
      }
      final loadedAtMs = int.tryParse(
        (snapshot['loadedAtMs'] ?? '').toString(),
      );
      final loadedAt = loadedAtMs == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(loadedAtMs);
      final editorial = snapshot['editorial'] is Map
          ? _TvHomeEditorialEdition.fromJson(
              Map<String, dynamic>.from(snapshot['editorial'] as Map),
            )
          : null;
      final heroItems = _catalogWarmItemsFromJson(snapshot['hero']);
      final topSignalItems = _catalogWarmItemsFromJson(snapshot['topSignal']);
      final todaySignalItems = _catalogWarmItemsFromJson(
        snapshot['todaySignal'],
      );
      final juicrTopSignalItems = _catalogWarmItemsFromJson(
        snapshot['juicrTopSignal'],
      );
      final upcomingPicks = lanes[_tvDiscoveryLaneKey(
            _TvDiscoveryKind.movie,
            _TvDiscoverySort.upcoming,
          )] ??
          const <_TvItem>[];
      if (!mounted) return false;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _movies
          ..clear()
          ..addAll(items.where((item) => item.type == 'movie'));
        _series
          ..clear()
          ..addAll(items.where((item) => item.type == 'series'));
        _animation
          ..clear()
          ..addAll(items.where(_isAnimationOrAnimationItem));
        _liveTv
          ..clear()
          ..addAll(
            items.where(
              (item) =>
                  _matchesDiscoveryLaneKind(item, _TvDiscoveryKind.liveTv),
            ),
          );
        _discoveryLaneItems
          ..clear()
          ..addAll(lanes);
        _discoveryLanePages
          ..clear()
          ..addAll({for (final key in lanes.keys) key: 1});
        _discoveryLaneLoading.clear();
        _discoveryLaneExhausted.clear();
        _upcomingPicks
          ..clear()
          ..addAll(upcomingPicks);
        _heroEditorialItems = heroItems;
        _topSignalRemoteItems = topSignalItems;
        _todaySignalRemoteItems = todaySignalItems;
        _juicrTopSignalRemoteItems = juicrTopSignalItems;
        _homeEditorial = editorial?.hasUsableRails == true ? editorial : null;
        final homeSnapshotItems = <_TvItem>[
          ...heroItems,
          ...topSignalItems,
          ...todaySignalItems,
          ...juicrTopSignalItems,
        ];
        _homeArtworkByKey.clear();
        _homeArtworkByKey.addAll(_homeArtworkMap(homeSnapshotItems));
        _homeArtworkHydrationKeys.clear();
        _homeArtworkHydrationKeys.addAll(
          homeSnapshotItems
              .where((item) => (item.logo ?? '').trim().isNotEmpty)
              .expand(_homeArtworkKeys),
        );
        _homeArtworkHydrationAttempts.clear();
        _catalogLoadedAt = loadedAt;
        _loading = false;
        _error = null;
        _reconcileRecentItemsWithCatalog();
      });
      debugPrint(
        'Juicr TV catalog warm snapshot restored '
        'items=${items.length} lanes=${lanes.length}',
      );
      return true;
    } catch (error) {
      debugPrint(
        'Juicr TV catalog warm snapshot skipped '
        'bucket=catalog_snapshot_restore errorType=${error.runtimeType}',
      );
      return false;
    }
  }

  Future<void> _saveCatalogWarmSnapshot() async {
    final hasSnapshotPayload = _items.isNotEmpty ||
        _discoveryLaneItems.values.any((lane) => lane.isNotEmpty) ||
        _heroEditorialItems.isNotEmpty ||
        _topSignalRemoteItems.isNotEmpty ||
        _todaySignalRemoteItems.isNotEmpty ||
        _juicrTopSignalRemoteItems.isNotEmpty;
    if (!hasSnapshotPayload) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lanes = <String, List<Map<String, dynamic>>>{
        for (final entry in _discoveryLaneItems.entries)
          if (entry.value.isNotEmpty)
            entry.key: _catalogWarmItemsJson(entry.value, limit: 48),
      };
      final snapshot = {
        'version': 1,
        'loadedAtMs':
            (_catalogLoadedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'items': _catalogWarmItemsJson(_items, limit: 360),
        'hero': _catalogWarmItemsJson(_heroEditorialItems, limit: 12),
        if (_homeEditorial != null) 'editorial': _homeEditorial!.toJson(),
        'topSignal': _catalogWarmItemsJson(_topSignalRemoteItems, limit: 24),
        'todaySignal': _catalogWarmItemsJson(
          _todaySignalRemoteItems,
          limit: 24,
        ),
        'juicrTopSignal': _catalogWarmItemsJson(
          _juicrTopSignalRemoteItems,
          limit: 12,
        ),
        'lanes': lanes,
      };
      await prefs.setString(
        _tvCatalogWarmSnapshotPrefsKey,
        jsonEncode(snapshot),
      );
    } catch (error) {
      debugPrint(
        'Juicr TV catalog warm snapshot save skipped '
        'bucket=catalog_snapshot_save errorType=${error.runtimeType}',
      );
    }
  }

  Future<void> _loadCatalog({bool force = false}) async {
    if (!_tvSettings.hasCatalogSource) {
      _clearCatalogForDisabledSource();
      return;
    }
    if (!force && _hasFreshCatalogSnapshot) return;
    final existingLoad = _catalogLoadFuture;
    if (existingLoad != null) {
      await existingLoad;
      return;
    }
    final future = _loadCatalogInner(force: force);
    _catalogLoadFuture = future;
    try {
      await future;
    } finally {
      if (identical(_catalogLoadFuture, future)) {
        _catalogLoadFuture = null;
      }
    }
  }

  Future<void> _loadCatalogInner({required bool force}) async {
    setState(() {
      _loading = !_hasCatalogSnapshot;
      _error = null;
    });
    try {
      final catalogRequests = <_TvCatalogLaneRequest>[
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.movie,
          sort: _TvDiscoverySort.popular,
          type: 'movie',
          catalogSort: _TvDiscoverySort.popular.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.movie,
          sort: _TvDiscoverySort.nowPlaying,
          type: 'movie',
          catalogSort: _TvDiscoverySort.nowPlaying.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.movie,
          sort: _TvDiscoverySort.topRated,
          type: 'movie',
          catalogSort: _TvDiscoverySort.topRated.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.movie,
          sort: _TvDiscoverySort.featured,
          type: 'movie',
          catalogSort: _TvDiscoverySort.featured.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.movie,
          sort: _TvDiscoverySort.upcoming,
          type: 'movie',
          catalogSort: _TvDiscoverySort.upcoming.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.series,
          sort: _TvDiscoverySort.popular,
          type: 'series',
          catalogSort: _TvDiscoverySort.popular.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.series,
          sort: _TvDiscoverySort.airingToday,
          type: 'series',
          catalogSort: _TvDiscoverySort.airingToday.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.series,
          sort: _TvDiscoverySort.onTv,
          type: 'series',
          catalogSort: _TvDiscoverySort.onTv.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.series,
          sort: _TvDiscoverySort.topRated,
          type: 'series',
          catalogSort: _TvDiscoverySort.topRated.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.series,
          sort: _TvDiscoverySort.featured,
          type: 'series',
          catalogSort: _TvDiscoverySort.featured.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.animation,
          sort: _TvDiscoverySort.popular,
          type: 'animation',
          fallbackType: 'movie',
          catalogSort: _TvDiscoverySort.popular.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.animation,
          sort: _TvDiscoverySort.onTv,
          type: 'animation',
          fallbackType: 'series',
          catalogSort: _TvDiscoverySort.onTv.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.popular,
          type: 'live_tv',
          catalogSort: _TvDiscoverySort.popular.catalogSortId,
          pages: 2,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.newest,
          type: 'live_tv',
          catalogSort: _TvDiscoverySort.newest.catalogSortId,
          pages: 2,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.featured,
          type: 'live_tv',
          catalogSort: _TvDiscoverySort.featured.catalogSortId,
          pages: 2,
        ),
        const _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.popular,
          type: 'livetv',
          catalogSort: 'top',
          pages: 1,
        ),
        const _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.popular,
          type: 'channel',
          catalogSort: 'top',
          pages: 1,
        ),
        const _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.popular,
          type: 'channels',
          catalogSort: 'top',
          pages: 1,
        ),
      ];
      var catalogFetchHadError = false;
      void markCatalogFetchError() => catalogFetchHadError = true;

      final results = await Future.wait<Object?>([
        for (final request in catalogRequests)
          _safeCatalog(
            type: request.type,
            fallbackType: request.fallbackType,
            sort: request.catalogSort,
            pages: request.pages,
            onError: markCatalogFetchError,
          ),
        _safeHomeEditorial(),
      ]).timeout(const Duration(seconds: 35));
      final editorialResult = results[catalogRequests.length];
      final editorial =
          editorialResult is _TvHomeEditorialEdition ? editorialResult : null;
      final merged = <String, _TvItem>{};
      final discoveryLaneMaps = <String, Map<String, _TvItem>>{};
      final discoveryLanePages = <String, int>{};
      for (var index = 0; index < catalogRequests.length; index++) {
        final list = results[index];
        if (list is! List<_TvItem>) continue;
        final request = catalogRequests[index];
        final laneKey = _tvDiscoveryLaneKey(request.kind, request.sort);
        discoveryLanePages[laneKey] = math.max(
          discoveryLanePages[laneKey] ?? 0,
          request.pages,
        );
        final laneMap = discoveryLaneMaps.putIfAbsent(
          laneKey,
          () => <String, _TvItem>{},
        );
        for (final item in list) {
          final normalized = _normalizeCatalogLane(item);
          if (!_matchesDiscoveryLaneKind(normalized, request.kind)) continue;
          final itemKey = '${normalized.type}:${normalized.id}';
          laneMap[itemKey] = normalized;
          merged[itemKey] = normalized;
        }
      }
      final discoveryLanes = {
        for (final entry in discoveryLaneMaps.entries)
          entry.key: entry.value.values.toList(growable: false),
      };
      final all = merged.values.toList();
      final upcomingPicks = discoveryLanes[_tvDiscoveryLaneKey(
            _TvDiscoveryKind.movie,
            _TvDiscoverySort.upcoming,
          )]
              ?.where((item) => item.type == 'movie')
              .toList(growable: false) ??
          const <_TvItem>[];
      final hasLoadedCatalog = all.isNotEmpty ||
          discoveryLanes.values.any((lane) => lane.isNotEmpty);
      if (!hasLoadedCatalog && _hasCatalogSnapshot) {
        debugPrint(
          'Juicr TV catalog refresh retained snapshot '
          'bucket=empty_refresh hadNetworkError=$catalogFetchHadError',
        );
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = null;
          _discoveryLaneLoading.clear();
        });
        return;
      }
      if (!hasLoadedCatalog) {
        debugPrint(
          'Juicr TV catalog hydrate stopped '
          'bucket=empty_initial hadNetworkError=$catalogFetchHadError',
        );
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Catalog is unavailable right now. Try again shortly.';
          _discoveryLaneLoading.clear();
          _discoveryLaneExhausted.clear();
        });
        _focusNavigationAfterFrame();
        return;
      }
      final previousEditorial = _homeEditorial;
      final previousEditionKey = previousEditorial == null
          ? ''
          : '${previousEditorial.editionId}|${previousEditorial.editionDate}';
      final nextEditionKey = editorial == null
          ? ''
          : '${editorial.editionId}|${editorial.editionDate}';
      final preserveHomeSignals =
          previousEditionKey.isNotEmpty && previousEditionKey == nextEditionKey;
      final heroEditorial = editorial?.hero;
      var curatedHeroItems = const <_TvItem>[];
      if (heroEditorial != null && _hasHomeEditorialScope(heroEditorial)) {
        try {
          final heroItems = await _loadCuratedHeroItems(
            heroEditorial,
            seedItems: all,
          );
          curatedHeroItems = heroItems;
        } catch (error) {
          debugPrint(
            'Juicr TV hero editorial hydrate skipped '
            'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(all);
        _movies
          ..clear()
          ..addAll(all.where((item) => item.type == 'movie'));
        _series
          ..clear()
          ..addAll(all.where((item) => item.type == 'series'));
        _animation
          ..clear()
          ..addAll(all.where(_isAnimationOrAnimationItem));
        _liveTv
          ..clear()
          ..addAll(
            all.where(
              (item) =>
                  _matchesDiscoveryLaneKind(item, _TvDiscoveryKind.liveTv),
            ),
          );
        _discoveryLaneItems
          ..clear()
          ..addAll(discoveryLanes);
        _discoveryLanePages
          ..clear()
          ..addAll(discoveryLanePages);
        _discoveryLaneLoading.clear();
        _discoveryLaneExhausted.clear();
        _upcomingPicks
          ..clear()
          ..addAll(upcomingPicks);
        _heroEditorialItems = curatedHeroItems;
        if (!preserveHomeSignals) {
          _topSignalRemoteItems = const <_TvItem>[];
          _todaySignalRemoteItems = const <_TvItem>[];
          _juicrTopSignalRemoteItems = const <_TvItem>[];
        }
        _homeArtworkByKey.clear();
        _homeArtworkByKey.addAll(_homeArtworkMap(curatedHeroItems));
        _homeArtworkHydrationKeys.clear();
        _homeArtworkHydrationKeys.addAll(
          curatedHeroItems
              .where((item) => (item.logo ?? '').trim().isNotEmpty)
              .expand(_homeArtworkKeys),
        );
        _homeArtworkHydrationAttempts.clear();
        _homeEditorial = editorial;
        _catalogLoadedAt = DateTime.now();
        _loading = false;
        _reconcileRecentItemsWithCatalog();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedItem != null || _searchOpen) return;
        _focusSelectedTabFirstItem();
      });
      unawaited(_saveCatalogWarmSnapshot());
      unawaited(_refreshHomeSignalRails(editorial, seedItems: all));
      unawaited(_refreshHomeRailArtwork());
    } catch (error) {
      if (!mounted) return;
      if (_hasCatalogSnapshot) {
        debugPrint(
          'Juicr TV catalog refresh retained snapshot '
          'bucket=refresh_exception errorType=${error.runtimeType}',
        );
        setState(() {
          _loading = false;
          _error = null;
          _discoveryLaneLoading.clear();
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Catalog is unavailable right now. Try again shortly.';
      });
    }
  }

  Future<List<_TvItem>> _safeCatalog({
    required String type,
    required String sort,
    String? fallbackType,
    int pages = 1,
    void Function()? onError,
  }) async {
    final merged = <String, _TvItem>{};
    final safePages = pages.clamp(1, 4).toInt();
    for (var page = 1; page <= safePages; page += 1) {
      try {
        final items = await _catalogPageWithRetry(
          type: type,
          fallbackType: fallbackType,
          sort: sort,
          page: page,
        );
        if (items.isEmpty) break;
        for (final item in items) {
          merged['${item.type}:${item.id}'] = item;
        }
      } catch (error) {
        onError?.call();
        debugPrint(
          'Juicr TV catalog page skipped '
          'lane=$type page=$page bucket=${_apiErrorBucket(error)} '
          'errorType=${error.runtimeType}',
        );
        break;
      }
    }
    return merged.values.toList(growable: false);
  }

  Future<List<_TvItem>> _catalogPageWithRetry({
    required String type,
    required String sort,
    required int page,
    String? fallbackType,
    String? genre,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        return await _api
            .catalog(
              type: type,
              fallbackType: fallbackType,
              sort: sort,
              page: page,
              genre: genre ?? '',
            )
            .timeout(const Duration(seconds: 8));
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 260));
        }
      }
    }
    Error.throwWithStackTrace(lastError!, StackTrace.current);
  }

  Future<_TvHomeEditorialEdition?> _safeHomeEditorial() async {
    try {
      return await _api.homeEditorial().timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint(
        'Juicr TV home editorial skipped '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return null;
    }
  }

  void _clearCatalogForDisabledSource() {
    if (!mounted) return;
    if (!_hasCatalogSnapshot &&
        !_loading &&
        _error == null &&
        _homeEditorial == null &&
        _heroEditorialItems.isEmpty &&
        _topSignalRemoteItems.isEmpty &&
        _todaySignalRemoteItems.isEmpty &&
        _juicrTopSignalRemoteItems.isEmpty &&
        _upcomingPicks.isEmpty) {
      return;
    }
    setState(() {
      _loading = false;
      _error = null;
      _items.clear();
      _movies.clear();
      _series.clear();
      _animation.clear();
      _liveTv.clear();
      _discoveryLaneItems.clear();
      _discoveryLanePages.clear();
      _discoveryLaneLoading.clear();
      _discoveryLaneExhausted.clear();
      _upcomingPicks.clear();
      _heroEditorialItems = const <_TvItem>[];
      _topSignalRemoteItems = const <_TvItem>[];
      _todaySignalRemoteItems = const <_TvItem>[];
      _juicrTopSignalRemoteItems = const <_TvItem>[];
      _homeArtworkByKey.clear();
      _homeArtworkHydrationKeys.clear();
      _homeArtworkHydrationAttempts.clear();
      _homeEditorial = null;
      _catalogLoadedAt = null;
    });
  }

  Future<void> _loadMoreDiscoveryLane() async {
    final laneKey = _tvDiscoveryLaneKey(
      _discoveryKind,
      _discoverySort,
      genre: _discoveryGenre,
    );
    if (_discoveryLaneLoading.contains(laneKey) ||
        _discoveryLaneExhausted.contains(laneKey)) {
      return;
    }
    final type = switch (_discoveryKind) {
      _TvDiscoveryKind.movie => 'movie',
      _TvDiscoveryKind.series => 'series',
      _TvDiscoveryKind.animation => 'animation',
      _TvDiscoveryKind.liveTv => 'live_tv',
    };
    final fallbackType = _fallbackTypeForDiscovery(
      _discoveryKind,
      _discoverySort,
    );
    var nextPage = (_discoveryLanePages[laneKey] ?? 0) + 1;
    setState(() => _discoveryLaneLoading.add(laneKey));
    try {
      final existing = <String, _TvItem>{
        for (final item in _discoveryLaneItems[laneKey] ?? const <_TvItem>[])
          '${item.type}:${item.id}': item,
      };
      var exhausted = false;
      var addedCount = 0;
      final items = await _loadMoreDiscoveryCatalogPage(
        type: type,
        fallbackType: fallbackType,
        sort: _discoverySort.catalogSortId,
        page: nextPage,
        genre: _discoveryGenre,
      );
      if (items.isEmpty) {
        exhausted = true;
      }
      for (final item in items) {
        final normalized = _normalizeCatalogLane(item);
        if (!_matchesDiscoveryLaneKind(normalized, _discoveryKind)) continue;
        final itemKey = '${normalized.type}:${normalized.id}';
        if (existing.containsKey(itemKey)) continue;
        existing[itemKey] = normalized;
        addedCount += 1;
      }
      if (addedCount == 0) exhausted = true;
      if (!mounted) return;
      setState(() {
        _discoveryLanePages[laneKey] = math.max(
          _discoveryLanePages[laneKey] ?? 0,
          nextPage,
        );
        if (exhausted) _discoveryLaneExhausted.add(laneKey);
        _discoveryLaneItems[laneKey] = existing.values.toList(growable: false);
      });
    } catch (error) {
      debugPrint(
        'Juicr TV discovery load more skipped '
        'lane=$laneKey page=$nextPage bucket=${_apiErrorBucket(error)} '
        'errorType=${error.runtimeType}',
      );
      if (mounted) {
        setState(() {
          _discoveryLaneItems.putIfAbsent(laneKey, () => const <_TvItem>[]);
          _discoveryLaneExhausted.add(laneKey);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _discoveryLaneLoading.remove(laneKey));
      } else {
        _discoveryLaneLoading.remove(laneKey);
      }
    }
  }

  Future<List<_TvItem>> _loadMoreDiscoveryCatalogPage({
    required String type,
    required String sort,
    required int page,
    required String genre,
    String? fallbackType,
  }) async {
    if (_discoveryKind != _TvDiscoveryKind.liveTv) {
      return _catalogPageWithRetry(
        type: type,
        fallbackType: fallbackType,
        sort: sort,
        page: page,
        genre: genre,
      );
    }

    const liveCatalogAliases = ['live_tv', 'livetv', 'channel', 'channels'];
    final merged = <String, _TvItem>{};
    final results = await Future.wait<List<_TvItem>>(
      liveCatalogAliases.map((alias) async {
        try {
          return await _catalogPageWithRetry(
            type: alias,
            fallbackType: alias == 'live_tv' ? 'live' : null,
            sort: sort,
            page: page,
            genre: genre,
          );
        } catch (error) {
          debugPrint(
            'Juicr TV discovery load more skipped '
            'lane=$alias page=$page bucket=${_apiErrorBucket(error)} '
            'errorType=${error.runtimeType}',
          );
          return const <_TvItem>[];
        }
      }),
    );
    for (final list in results) {
      for (final item in list) {
        merged['${item.type}:${item.id}'] = item;
      }
    }
    return merged.values.toList(growable: false);
  }

  Future<_TvHydratedHomeSignals> _hydrateHomeSignalRails(
    _TvHomeEditorialEdition? editorial, {
    required List<_TvItem> seedItems,
  }) async {
    if (editorial == null) return const _TvHydratedHomeSignals();
    final today = await _hydrateHomeSignalRail(
      editorial.todaySignal,
      seedItems: seedItems,
      limit: 20,
    );
    final top = await _hydrateHomeSignalRail(
      editorial.topSignal,
      seedItems: [...seedItems, ...today],
      limit: 20,
    );
    final juicrTop = await _hydrateHomeSignalRail(
      editorial.juicrTopSignal,
      seedItems: [...seedItems, ...today, ...top],
      limit: 10,
    );
    return _TvHydratedHomeSignals(
      topSignal: top,
      todaySignal: today,
      juicrTopSignal: juicrTop,
    );
  }

  Future<void> _refreshHomeSignalRails(
    _TvHomeEditorialEdition? editorial, {
    required List<_TvItem> seedItems,
  }) async {
    if (editorial == null) return;
    final editionKey = '${editorial.editionId}|${editorial.editionDate}';
    final hydrated = await _hydrateHomeSignalRails(
      editorial,
      seedItems: seedItems,
    );
    if (!mounted) return;
    final current = _homeEditorial;
    final currentKey =
        current == null ? '' : '${current.editionId}|${current.editionDate}';
    if (currentKey != editionKey) return;
    final hasTopSignal = hydrated.topSignal.isNotEmpty;
    final hasTodaySignal = hydrated.todaySignal.isNotEmpty;
    final hasJuicrTopSignal = hydrated.juicrTopSignal.isNotEmpty;
    if (!hasTopSignal && !hasTodaySignal && !hasJuicrTopSignal) {
      debugPrint(
        'Juicr TV home signal retained previous rails '
        'bucket=empty_signal_refresh',
      );
      return;
    }
    setState(() {
      if (hasTopSignal) _topSignalRemoteItems = hydrated.topSignal;
      if (hasTodaySignal) _todaySignalRemoteItems = hydrated.todaySignal;
      if (hasJuicrTopSignal) {
        _juicrTopSignalRemoteItems = hydrated.juicrTopSignal;
      }
    });
    unawaited(_refreshHomeRailArtwork());
    unawaited(_saveCatalogWarmSnapshot());
  }

  Future<void> _refreshHomeRailArtwork() async {
    if (!mounted || _loading || _homeArtworkHydrating) return;
    const batchLimit = 4;
    const maxAttempts = 2;
    final candidates = <_TvItem>[
      ..._items,
      ..._movies,
      ..._series,
      ..._animation,
      ..._liveTv,
      ..._upcomingPicks,
      ..._recentItems,
      ..._homeHeroItems,
      for (final rail in _rails) ...rail.items,
    ];
    final candidatesByKey = <String, _TvItem>{};
    final seen = <String>{};
    for (final item in candidates) {
      final key = _homeUsedKey(item);
      if (!seen.add(key)) continue;
      if (_homeArtworkHydrationKeys.contains(key) ||
          _hasCompleteTvArtwork(_applyHomeArtwork(item))) {
        continue;
      }
      if (_hasCompleteTvArtwork(item)) continue;
      if (item.tmdbId == null && item.id.trim().isEmpty) continue;
      final attempts = _homeArtworkHydrationAttempts[key] ?? 0;
      if (attempts >= maxAttempts) continue;
      candidatesByKey[key] = item;
    }
    final pendingEntries = candidatesByKey.entries.toList(growable: false)
      ..sort((left, right) {
        final attemptDelta = (_homeArtworkHydrationAttempts[left.key] ?? 0)
            .compareTo(_homeArtworkHydrationAttempts[right.key] ?? 0);
        if (attemptDelta != 0) return attemptDelta;
        return left.key.compareTo(right.key);
      });
    final pending = Map<String, _TvItem>.fromEntries(
      pendingEntries.take(batchLimit),
    );
    for (final key in pending.keys) {
      _homeArtworkHydrationAttempts[key] =
          (_homeArtworkHydrationAttempts[key] ?? 0) + 1;
    }
    if (pending.isEmpty) return;
    final shouldContinue = pendingEntries.length > batchLimit;
    _homeArtworkHydrating = true;
    final byKey = <String, _TvItem>{};
    try {
      final hydrated = <MapEntry<String, _TvItem>>[];
      for (final entry in pending.entries) {
        hydrated.add(
          MapEntry(
            entry.key,
            await _hydrateHeroArtworkItem(entry.value),
          ),
        );
        if (!mounted) return;
      }
      if (!mounted) return;
      for (final entry in hydrated) {
        final item = entry.value;
        final hasArtwork = _hasPrimaryTvArtwork(item) ||
            (item.logo ?? '').trim().isNotEmpty ||
            (item.description ?? '').trim().isNotEmpty;
        if (hasArtwork) {
          byKey[entry.key] = item;
          for (final key in _homeArtworkKeys(item)) {
            byKey[key] = item;
          }
          final requested = pending[entry.key];
          if (requested != null) {
            for (final key in _homeArtworkKeys(requested)) {
              byKey[key] = item;
            }
          }
        }
        if (_hasCompleteTvArtwork(_applyHomeArtwork(item))) {
          _homeArtworkHydrationKeys.addAll({
            entry.key,
            ..._homeArtworkKeys(item),
            if (pending[entry.key] != null)
              ..._homeArtworkKeys(pending[entry.key]!),
          });
        }
      }
    } finally {
      _homeArtworkHydrating = false;
    }
    if (byKey.isNotEmpty) {
      setState(() {
        _homeArtworkByKey.addAll(byKey);
        _mergeArtworkInto(_items, byKey);
        _mergeArtworkInto(_movies, byKey);
        _mergeArtworkInto(_series, byKey);
        _mergeArtworkInto(_animation, byKey);
        _mergeArtworkInto(_liveTv, byKey);
        _mergeArtworkInto(_upcomingPicks, byKey);
        _mergeArtworkInto(_recentItems, byKey);
        _topSignalRemoteItems = _mergedArtworkList(
          _topSignalRemoteItems,
          byKey,
        );
        _todaySignalRemoteItems = _mergedArtworkList(
          _todaySignalRemoteItems,
          byKey,
        );
        _juicrTopSignalRemoteItems = _mergedArtworkList(
          _juicrTopSignalRemoteItems,
          byKey,
        );
        _heroEditorialItems = _mergedArtworkList(_heroEditorialItems, byKey);
      });
    }
    if (shouldContinue && mounted) {
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 120),
        ).then((_) => _refreshHomeRailArtwork()),
      );
    }
  }

  void _mergeArtworkInto(List<_TvItem> items, Map<String, _TvItem> hydrated) {
    for (var index = 0; index < items.length; index++) {
      final other = _homeArtworkFor(items[index], hydrated);
      if (other != null) items[index] = items[index].merge(other);
    }
  }

  List<_TvItem> _mergedArtworkList(
    List<_TvItem> items,
    Map<String, _TvItem> hydrated,
  ) {
    return [
      for (final item in items)
        item.merge(_homeArtworkFor(item, hydrated) ?? item),
    ];
  }

  _TvItem? _homeArtworkFor(_TvItem item, Map<String, _TvItem> hydrated) {
    for (final key in _homeArtworkKeys(item)) {
      final other = hydrated[key];
      if (other != null) return other;
    }
    return null;
  }

  _TvItem _applyHomeArtwork(_TvItem item) {
    return item.merge(_homeArtworkFor(item, _homeArtworkByKey) ?? item);
  }

  Map<String, _TvItem> _homeArtworkMap(Iterable<_TvItem> items) {
    final byKey = <String, _TvItem>{};
    for (final item in items) {
      final hasArtwork = _hasPrimaryTvArtwork(item) ||
          (item.logo ?? '').trim().isNotEmpty ||
          (item.description ?? '').trim().isNotEmpty;
      if (!hasArtwork) continue;
      for (final key in _homeArtworkKeys(item)) {
        byKey[key] = item;
      }
    }
    return byKey;
  }

  Future<List<_TvItem>> _hydrateHomeSignalRail(
    _TvHomeEditorialRail editorial, {
    required List<_TvItem> seedItems,
    required int limit,
  }) async {
    if (editorial.items.isEmpty) return const <_TvItem>[];
    final ranked = <_TvItem>[];
    final seen = <String>{};
    final seedPool = _availableHomeItems(seedItems).toList();
    for (final signal in editorial.items.take(limit)) {
      try {
        var match = _findHomeSignalSeedMatch(seedPool, signal);
        match ??= await _findHomeSignalRemoteMatch(signal);
        if (match == null || match.poster == null) continue;
        final normalized = _normalizeCatalogLane(match);
        final key = _homeUsedKey(normalized);
        if (seen.add(key)) ranked.add(normalized);
      } catch (error) {
        debugPrint(
          'Juicr TV home signal item skipped '
          'bucket=home_signal_hydrate errorType=${error.runtimeType}',
        );
      }
    }
    debugPrint(
      'Juicr TV home signal hydrated '
      'rail=${editorial.id.ifEmpty(editorial.title)} requested=${editorial.items.length} matched=${ranked.length}',
    );
    return ranked;
  }

  _TvItem? _findHomeSignalSeedMatch(
    List<_TvItem> items,
    _TvHomeEditorialTrendItem signal,
  ) {
    for (final item in items) {
      if (_itemMatchesHomeSignal(item, signal)) return item;
    }
    return null;
  }

  Future<_TvItem?> _findHomeSignalRemoteMatch(
    _TvHomeEditorialTrendItem signal,
  ) async {
    final types = _homeSignalTypes(signal);
    for (final type in types) {
      _TvItem? match;
      if (signal.tmdbId != null) {
        final metaSeed = _TvItem(
          id: 'tmdb:${signal.tmdbId}',
          type: type,
          title: signal.title,
          color: _colorFromText(signal.title),
          year: signal.year,
          tmdbId: signal.tmdbId,
        );
        try {
          final meta =
              await _api.meta(metaSeed).timeout(const Duration(seconds: 5));
          if (_itemMatchesHomeSignal(meta, signal)) match = meta;
        } catch (_) {
          // Fall through to catalog search.
        }
      }
      if (match != null && match.poster != null) return match;
      final searchMatch = await _findHomeSignalCatalogMatch(signal, type);
      if (searchMatch != null) {
        return match == null ? searchMatch : match.merge(searchMatch);
      }
      if (match != null) return match;
    }
    return null;
  }

  Future<_TvItem?> _findHomeSignalCatalogMatch(
    _TvHomeEditorialTrendItem signal,
    String type,
  ) async {
    final result = await _api
        .catalog(
          type: type,
          sort: 'top',
          search: signal.title,
          deepSearch: true,
          preferDefaultCatalog: true,
        )
        .timeout(const Duration(seconds: 7));
    for (final item in result) {
      final normalized = _normalizeCatalogLane(item);
      if (_itemMatchesHomeSignal(normalized, signal) &&
          normalized.poster != null) {
        return normalized;
      }
    }
    for (final item in result) {
      final normalized = _normalizeCatalogLane(item);
      if (_itemMatchesHomeSignal(normalized, signal)) return normalized;
    }
    return null;
  }

  List<String> _homeSignalTypes(_TvHomeEditorialTrendItem signal) {
    if (signal.type == 'movie' ||
        signal.type == 'series' ||
        signal.type == 'animation') {
      return [signal.type == 'animation' ? 'series' : signal.type];
    }
    return const ['movie', 'series'];
  }

  bool _itemMatchesHomeSignal(_TvItem item, _TvHomeEditorialTrendItem signal) {
    final signalType = signal.type == 'animation' ? 'series' : signal.type;
    final itemType = item.type == 'animation' ? 'series' : item.type;
    if (signalType.isNotEmpty && itemType != signalType) return false;
    if (signal.tmdbId != null && item.tmdbId == signal.tmdbId) return true;
    final itemTitle = _normalizeHomeText(item.title);
    final signalTitle = _normalizeHomeText(signal.title);
    if (itemTitle.isEmpty || signalTitle.isEmpty || itemTitle != signalTitle) {
      return false;
    }
    final signalYear = signal.year?.trim() ?? '';
    if (signalYear.isEmpty) return true;
    final itemYear = item.year?.trim() ?? '';
    return itemYear.isEmpty || itemYear.startsWith(signalYear);
  }

  _TvItem _normalizeCatalogLane(_TvItem item) {
    if (_isExplicitLiveTvType(item.type)) return item.withType('live');
    if (item.type == 'series' && _hasAnimationSignal(item)) {
      return item.withType('animation');
    }
    return item;
  }

  bool _hasTvDiscoveryArtwork(_TvItem item) {
    if (_isExplicitLiveTvType(item.type)) {
      return item.poster != null ||
          item.background != null ||
          item.logo != null;
    }
    return item.poster != null || item.background != null;
  }

  bool _hasPrimaryTvArtwork(_TvItem item) {
    return (item.poster ?? '').trim().isNotEmpty ||
        (item.background ?? '').trim().isNotEmpty;
  }

  bool _hasCompleteTvArtwork(_TvItem item) {
    return (item.poster ?? '').trim().isNotEmpty &&
        (item.background ?? '').trim().isNotEmpty &&
        (item.logo ?? '').trim().isNotEmpty &&
        (item.description ?? '').trim().isNotEmpty;
  }

  bool _matchesDiscoveryLaneKind(_TvItem item, _TvDiscoveryKind kind) {
    final type = item.type.trim().toLowerCase();
    return switch (kind) {
      _TvDiscoveryKind.movie => type == 'movie',
      _TvDiscoveryKind.series => type == 'series',
      _TvDiscoveryKind.animation =>
        type == 'animation' || _isAnimationOrAnimationItem(item),
      _TvDiscoveryKind.liveTv => _isExplicitLiveTvType(type),
    };
  }

  bool _isExplicitLiveTvType(String type) {
    final normalized = type.trim().toLowerCase().replaceAll('-', '_');
    return normalized == 'live' ||
        normalized == 'live_tv' ||
        normalized == 'livetv' ||
        normalized == 'channel' ||
        normalized == 'channels';
  }

  String? _fallbackTypeForDiscovery(
    _TvDiscoveryKind kind,
    _TvDiscoverySort sort,
  ) {
    if (kind == _TvDiscoveryKind.animation) {
      return sort == _TvDiscoverySort.onTv ? 'series' : 'movie';
    }
    if (kind == _TvDiscoveryKind.liveTv) return 'live';
    return null;
  }

  bool _isAnimationOrAnimationItem(_TvItem item) {
    if (item.type == 'animation') {
      return _hasAnimationSignal(item);
    }
    return _hasAnimationSignal(item);
  }

  bool _hasAnimationSignal(_TvItem item) {
    final haystack = [
      item.title,
      item.description ?? '',
      ...item.genres,
    ].join(' ').toLowerCase();
    const signals = [
      'animation',
      'animation',
      'animated',
      'manga',
      'japanese animation',
    ];
    return signals.any(haystack.contains);
  }

  bool _isLiveTvItem(_TvItem item) {
    if (item.type == 'live' ||
        item.type == 'live_tv' ||
        item.type == 'livetv' ||
        item.type == 'channel') {
      return true;
    }
    final haystack = [
      item.title,
      item.description ?? '',
      ...item.genres,
    ].join(' ').toLowerCase();
    const signals = [
      'live tv',
      'live channel',
      'channel',
      'news',
      'sports',
      'tv channel',
    ];
    return signals.any(haystack.contains);
  }

  Future<void> _restoreTvSettings() async {
    var restored = const _TvSettingsState();
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_tvSettingsPrefsKey);
      if (encoded != null && encoded.trim().isNotEmpty) {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          restored = _TvSettingsState.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      }
    } catch (error) {
      debugPrint(
        'Juicr TV settings restore skipped '
        'bucket=settings_restore errorType=${error.runtimeType}',
      );
    }
    if (!mounted) return;
    setState(() => _tvSettings = restored);
    if (_tvSettings.hasCatalogSource && prefs != null) {
      await _restoreCatalogWarmSnapshot(prefs);
    }
    unawaited(_loadCatalog(force: true));
  }

  Future<void> _persistTvSettings(_TvSettingsState settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tvSettingsPrefsKey, jsonEncode(settings.toJson()));
    } catch (error) {
      debugPrint(
        'Juicr TV settings save skipped '
        'bucket=settings_save errorType=${error.runtimeType}',
      );
    }
  }

  Future<void> _restoreVerifiedPlaybackSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_tvVerifiedPlaybackSessionsPrefsKey);
      if (encoded == null || encoded.trim().isEmpty) return;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return;
      final restored = <String, List<_TvVerifiedPlaybackSession>>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty || entry.value is! List) continue;
        final sessions = <_TvVerifiedPlaybackSession>[
          for (final raw in (entry.value as List).whereType<Map>())
            _TvVerifiedPlaybackSession.fromJson(
              Map<String, dynamic>.from(raw),
            ),
        ].where(_verifiedPlaybackSessionUsable).toList(growable: false);
        if (sessions.isNotEmpty) restored[key] = _rankVerifiedSessions(sessions);
      }
      if (!mounted) return;
      setState(() {
        _verifiedPlaybackSessions
          ..clear()
          ..addAll(restored);
      });
      debugPrint(
        'Juicr TV verified playback cache restored keys=${restored.length}',
      );
    } catch (error) {
      debugPrint(
        'Juicr TV verified playback cache restore skipped '
        'bucket=verified_playback_restore errorType=${error.runtimeType}',
      );
    }
  }

  Future<void> _persistVerifiedPlaybackSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _verifiedPlaybackSessions.map(
          (key, value) => MapEntry(
            key,
            _rankVerifiedSessions(value)
                .take(3)
                .map((entry) => entry.toJson())
                .toList(growable: false),
          ),
        ),
      );
      await prefs.setString(_tvVerifiedPlaybackSessionsPrefsKey, encoded);
    } catch (error) {
      debugPrint(
        'Juicr TV verified playback cache save skipped '
        'bucket=verified_playback_save errorType=${error.runtimeType}',
      );
    }
  }

  Future<void> _restoreTvLibraryState() async {
    try {
      final store = await TvLibraryStateStore.load();
      if (!mounted) return;
      setState(() {
        _libraryStore = store;
        _applyLibraryState(store.state);
      });
    } catch (error) {
      debugPrint(
        'Juicr TV library restore skipped '
        'bucket=library_restore errorType=${error.runtimeType}',
      );
    }
  }

  Future<void> _restoreTvAccountState() async {
    try {
      final restored = await _accountStore.restore();
      var session = restored.session;
      var profile = restored.profile;
      if (session != null) {
        profile = await _api
                .refreshAuthSession(session.token)
                .timeout(const Duration(seconds: 9)) ??
            profile;
      }
      if (!mounted) return;
      setState(() {
        _accountSession = session;
        _accountProfile = profile;
        _accountSyncState = session?.isValid == true
            ? _TvAccountSyncState.idle
            : _TvAccountSyncState.guest;
      });
      if (session?.isValid == true) {
        unawaited(_syncAccountLibrary(fetchRemote: true));
      }
    } catch (error) {
      debugPrint(
        'Juicr TV account restore skipped '
        'bucket=account_restore errorType=${error.runtimeType}',
      );
    }
  }

  void _applyLibraryState(TvLibraryState state) {
    final restoredRecent = state.recentItems
        .map(_itemFromRecentSnapshot)
        .whereType<_TvItem>()
        .toList();
    final restoredProgress = <String, _TvPlaybackProgress>{};
    for (final entry in state.progress.entries) {
      restoredProgress[entry.key] = _TvPlaybackProgress(
        position: Duration(milliseconds: entry.value.positionMillis),
        duration: Duration(milliseconds: entry.value.durationMillis ?? 0),
      );
    }
    _likedItemKeys
      ..clear()
      ..addAll(state.likedKeys);
    _recentItems
      ..clear()
      ..addAll(restoredRecent);
    _watchedProgress
      ..clear()
      ..addAll(restoredProgress);
    _reconcileRecentItemsWithCatalog();
  }

  Future<bool> _syncAccountLibrary({required bool fetchRemote}) async {
    final session = _accountSession;
    final store = _libraryStore;
    if (session?.isValid != true || store == null) {
      if (mounted) {
        setState(() => _accountSyncState = _TvAccountSyncState.guest);
      }
      return false;
    }
    if (mounted) {
      setState(() => _accountSyncState = _TvAccountSyncState.syncing);
    }
    try {
      await _api.syncAccountWatchMetrics(
        token: session!.token,
        activeWatchSeconds: store.state.activeWatchSeconds,
      );
      final accountWatchSeconds = await _api.fetchAccountActiveWatchSeconds(
        session.token,
      );
      if (fetchRemote) {
        final remote = await _api.fetchAccountLibrarySnapshot(session.token);
        final remoteSnapshot = remote?.snapshot;
        if (remoteSnapshot != null && remoteSnapshot.isNotEmpty) {
          _accountLibraryRevision = remote!.revision;
          final accountState = const TvLibraryState().mergeMobileLibraryBackup(
            remoteSnapshot,
          );
          await store.save(accountState);
          if (mounted) {
            setState(() {
              _accountActiveWatchSeconds = accountWatchSeconds;
              _applyLibraryState(store.state);
            });
          }
          if (mounted) {
            setState(() => _accountSyncState = _TvAccountSyncState.synced);
          }
          return true;
        }
      }
      final push = await _api.pushAccountLibrarySnapshot(
        token: session.token,
        snapshot: store.state.toMobileLibraryBackup(),
        baseRevision: _accountLibraryRevision,
      );
      if (push.conflict && push.snapshot != null) {
        final merged = store.state.mergeMobileLibraryBackup(push.snapshot!);
        await store.save(merged);
        _accountLibraryRevision = push.revision;
        if (mounted) {
          setState(() => _applyLibraryState(store.state));
        }
        final retry = await _api.pushAccountLibrarySnapshot(
          token: session.token,
          snapshot: store.state.toMobileLibraryBackup(),
          baseRevision: _accountLibraryRevision,
        );
        if (retry.ok) _accountLibraryRevision = retry.revision;
      } else if (push.ok) {
        _accountLibraryRevision = push.revision;
      }
      if (mounted) {
        setState(() {
          _accountActiveWatchSeconds = accountWatchSeconds;
          _accountSyncState = _TvAccountSyncState.synced;
        });
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _accountSyncState = _TvAccountSyncState.needsAttention);
      }
      debugPrint(
        'Juicr TV account library sync skipped '
        'bucket=account_library_sync errorType=${error.runtimeType}',
      );
      return false;
    }
  }

  void _scheduleAccountLibraryPush() {
    final session = _accountSession;
    if (session?.isValid != true) return;
    _accountLibraryPushTimer?.cancel();
    _accountLibraryPushTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_syncAccountLibrary(fetchRemote: false));
    });
  }

  bool get _accountSignedIn => _accountSession?.isValid == true;

  String get _accountLabel {
    final profile = _accountProfile;
    if (!_accountSignedIn || profile == null) return 'Guest';
    if (profile.username.trim().isNotEmpty) return profile.username.trim();
    return _redactedEmailLabel(profile.email);
  }

  String _redactedEmailLabel(String email) {
    final parts = email.trim().split('@');
    if (parts.length != 2 || parts.first.isEmpty || parts.last.isEmpty) {
      return 'Signed in';
    }
    final name = parts.first;
    final visible = name.length <= 2 ? name : name.substring(0, 2);
    return '$visible***@${parts.last}';
  }

  Future<void> _openAccountSignIn() async {
    final credentials = await _showTvDialog<_TvAccountSignInResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _TvAccountSignInDialog(api: _api),
    );
    if (!mounted || credentials == null) return;
    try {
      await _accountStore.save(
        session: credentials.session,
        profile: credentials.profile,
      );
      setState(() {
        _accountSession = credentials.session;
        _accountProfile = credentials.profile;
        _accountSyncState = _TvAccountSyncState.idle;
      });
      await _syncAccountLibrary(fetchRemote: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Signed in to Juicr.')));
    } catch (error) {
      debugPrint(
        'Juicr TV sign-in save skipped '
        'bucket=account_sign_in_save errorType=${error.runtimeType}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Sign-in could not finish on this TV.')),
        );
    }
  }

  Future<void> _openAccountLibrary() async {
    if (!_accountSignedIn) {
      await _openAccountSignIn();
      if (!mounted || !_accountSignedIn) return;
    }
    await _openAccountManager();
  }

  Future<void> _openAccountManager() async {
    final profile = _accountProfile;
    if (profile == null || !_accountSignedIn) return;
    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) => _TvAccountLibraryDialog(
        profile: profile,
        accountLabel: _accountLabel,
        accountSyncLabel: _accountSyncLabel,
        recentCount: _recentLibraryCount,
        savedCount: _savedLibraryCount,
        completedCount: _completedLibraryCount,
        savedMovieCount: _savedMovieLibraryCount,
        savedSeriesCount: _savedSeriesLibraryCount,
        savedAnimationCount: _savedAnimationLibraryCount,
        savedLiveTvCount: _savedLiveTvLibraryCount,
        activeWatchLabel: _activeWatchLabel,
        onSync: _syncAccountNow,
        onSaveProfile: _saveAccountProfile,
        onClearContinue: _clearAccountContinueWatching,
        onClearSaved: _clearAccountSavedTitles,
        onClearMovies: _clearAccountSavedMovies,
        onClearSeries: _clearAccountSavedSeries,
        onClearAnimation: _clearAccountSavedAnimation,
        onClearLiveTv: _clearAccountSavedLiveTv,
        onClearLists: _clearAccountLibraryLists,
        onClearCompleted: _clearAccountCompletedHistory,
        onSignOut: _signOutAccount,
        onDeleteAccount: _deleteAccountAndLocalLibrary,
      ),
    );
  }

  Future<TvAccountProfile> _saveAccountProfile({
    required String username,
    required String emoji,
    required bool leaderboardOptIn,
  }) async {
    final session = _accountSession;
    if (session?.isValid != true) {
      throw const _TvApiException('auth_required');
    }
    final profile = await _api.updateAccountProfile(
      token: session!.token,
      username: username,
      emoji: emoji,
      leaderboardOptIn: leaderboardOptIn,
    );
    await _accountStore.save(session: session, profile: profile);
    if (mounted) {
      setState(() => _accountProfile = profile);
    }
    return profile;
  }

  Future<void> _saveAccountLibraryState(TvLibraryState state) async {
    final store = _libraryStore;
    if (store == null) return;
    await store.save(state);
    if (!mounted) return;
    setState(() => _applyLibraryState(store.state));
    _scheduleAccountLibraryPush();
  }

  Future<void> _clearAccountContinueWatching() async {
    final store = _libraryStore;
    if (store == null) return;
    await _saveAccountLibraryState(
      store.state.copyWith(
        recentItems: const <TvRecentItemSnapshot>[],
        progress: const <String, TvPlaybackProgress>{},
      ),
    );
  }

  Future<void> _clearAccountSavedTitles() async {
    final store = _libraryStore;
    if (store == null) return;
    await _saveAccountLibraryState(
      store.state.copyWith(likedKeys: const <String>{}),
    );
  }

  Future<void> _clearAccountSavedMovies() {
    return _clearAccountSavedWhere(
      (item) => item.type.trim().toLowerCase() == 'movie',
      fallbackTypes: const {'movie'},
    );
  }

  Future<void> _clearAccountSavedSeries() {
    return _clearAccountSavedWhere(
      (item) => item.type.trim().toLowerCase() == 'series',
      fallbackTypes: const {'series'},
    );
  }

  Future<void> _clearAccountSavedAnimation() {
    return _clearAccountSavedWhere(
      _isAnimationOrAnimationItem,
      fallbackTypes: const {'animation'},
    );
  }

  Future<void> _clearAccountSavedLiveTv() {
    return _clearAccountSavedWhere(
      _isLiveTvItem,
      fallbackTypes: const {'live', 'live_tv', 'livetv', 'channel', 'tv'},
    );
  }

  Future<void> _clearAccountSavedWhere(
    bool Function(_TvItem item) matches, {
    required Set<String> fallbackTypes,
  }) async {
    final store = _libraryStore;
    if (store == null) return;
    final itemByKey = <String, _TvItem>{};
    for (final item in [
      ..._items,
      ..._movies,
      ..._series,
      ..._animation,
      ..._liveTv,
      ..._recentItems,
    ]) {
      itemByKey.putIfAbsent(_itemKey(item), () => item);
    }
    final nextLiked = <String>{
      for (final key in store.state.likedKeys)
        if (!_savedLibraryKeyMatches(
          key,
          itemByKey[key],
          matches,
          fallbackTypes,
        ))
          key,
    };
    await _saveAccountLibraryState(store.state.copyWith(likedKeys: nextLiked));
  }

  bool _savedLibraryKeyMatches(
    String key,
    _TvItem? item,
    bool Function(_TvItem item) matches,
    Set<String> fallbackTypes,
  ) {
    if (item != null) return matches(item);
    final type = key.split(':').first.trim().toLowerCase();
    return fallbackTypes.contains(type);
  }

  Future<void> _clearAccountLibraryLists() async {
    final store = _libraryStore;
    if (store == null) return;
    await _saveAccountLibraryState(
      store.state.copyWith(libraryLists: const <TvLibraryList>[]),
    );
  }

  Future<void> _clearAccountCompletedHistory() async {
    final store = _libraryStore;
    if (store == null) return;
    await _saveAccountLibraryState(
      store.state.copyWith(completedKeys: const <String>{}),
    );
  }

  Future<void> _deleteAccountAndLocalLibrary() async {
    final token = _accountSession?.token ?? '';
    await _api.deleteAccount(token);
    await _libraryStore?.clear();
    await _accountStore.clear();
    _accountLibraryPushTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _accountSession = null;
      _accountProfile = null;
      _accountLibraryRevision = '';
      _accountActiveWatchSeconds = null;
      _accountSyncState = _TvAccountSyncState.guest;
      _applyLibraryState(const TvLibraryState());
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Account deleted.')));
  }

  Future<void> _signOutAccount() async {
    final token = _accountSession?.token ?? '';
    try {
      if (token.trim().isNotEmpty) {
        await _api.signOutAuthSession(token);
      }
    } catch (error) {
      debugPrint(
        'Juicr TV remote sign-out skipped '
        'bucket=account_sign_out errorType=${error.runtimeType}',
      );
    }
    await _accountStore.clear();
    _accountLibraryPushTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _accountSession = null;
      _accountProfile = null;
      _accountLibraryRevision = '';
      _accountActiveWatchSeconds = null;
      _accountSyncState = _TvAccountSyncState.guest;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Signed out.')));
  }

  Future<void> _syncAccountNow() async {
    final synced = await _syncAccountLibrary(fetchRemote: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _accountSignedIn
                ? synced
                    ? 'Library sync updated.'
                    : 'Library sync needs attention.'
                : 'Sign in to sync your library.',
          ),
        ),
      );
  }

  String get _accountSyncLabel {
    return switch (_accountSyncState) {
      _TvAccountSyncState.guest => 'Guest',
      _TvAccountSyncState.idle => 'Ready',
      _TvAccountSyncState.syncing => 'Syncing',
      _TvAccountSyncState.synced => 'Synced',
      _TvAccountSyncState.needsAttention => 'Needs attention',
    };
  }

  int get _savedLibraryCount => _likedItemKeys.length;

  int get _savedMovieLibraryCount => _likedItems
      .where((item) => item.type.trim().toLowerCase() == 'movie')
      .length;

  int get _savedSeriesLibraryCount => _likedItems
      .where((item) => item.type.trim().toLowerCase() == 'series')
      .length;

  int get _savedAnimationLibraryCount =>
      _likedItems.where(_isAnimationOrAnimationItem).length;

  int get _savedLiveTvLibraryCount => _likedItems.where(_isLiveTvItem).length;

  int get _recentLibraryCount => _continueItems.length;

  List<_TvItem> get _continueItems {
    final candidates = <String, _TvItem>{};
    for (final item in [
      ..._recentItems,
      ..._items,
      ..._movies,
      ..._series,
      ..._animation,
    ]) {
      candidates.putIfAbsent(_itemKey(item), () => item);
    }
    return [
      for (final item in _recentItems)
        if (_hasUnfinishedPlaybackProgress(item)) item,
      for (final item in candidates.values)
        if (!_recentItems.any((recent) => _itemKey(recent) == _itemKey(item)) &&
            _hasUnfinishedPlaybackProgress(item))
          item,
    ];
  }

  bool _hasUnfinishedPlaybackProgress(_TvItem item) {
    if (_isLiveTvItem(item)) return false;
    final itemKey = _itemKey(item);
    final legacyItemKey = item.id.trim();
    for (final entry in _watchedProgress.entries) {
      final progressKey = entry.key;
      final matchesCurrentKey =
          progressKey == itemKey || progressKey.startsWith('$itemKey:');
      final matchesLegacyKey = legacyItemKey.isNotEmpty &&
          (progressKey == legacyItemKey ||
              progressKey.startsWith('$legacyItemKey:'));
      if (!matchesCurrentKey && !matchesLegacyKey) {
        continue;
      }
      final progress = entry.value;
      if (progress.position > Duration.zero && !_isPlaybackComplete(progress)) {
        return true;
      }
    }
    return false;
  }

  int get _completedLibraryCount =>
      _libraryStore?.state.completedKeys.length ?? 0;

  int get _activeWatchSeconds {
    if (_accountSignedIn && _accountActiveWatchSeconds != null) {
      return _accountActiveWatchSeconds!;
    }
    return _libraryStore?.state.activeWatchSeconds ?? 0;
  }

  String get _activeWatchLabel {
    final seconds = _activeWatchSeconds;
    if (seconds <= 0) return '0m';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
  }

  List<_TvRail> get _rails {
    final editorial = _homeEditorial;
    final rails = <_TvRail>[];
    final usedKeys = <String>{
      for (final item in _homeHeroItems.take(8)) _homeUsedKey(item),
    };

    void addRail({
      required _TvHomeEditorialRail editorial,
      required List<_TvItem> primary,
      int limit = 20,
      bool preservePrimaryRank = false,
      bool showRank = true,
      bool posterCards = false,
    }) {
      final items = _backfilledHomeRailItems(
        primary,
        fallbackPool: const <_TvItem>[],
        usedKeys: usedKeys,
        limit: limit,
        preservePrimaryRank: preservePrimaryRank,
      );
      if (items.isEmpty) return;
      rails.add(
        _TvRail(
          editorial.title,
          editorial.subtitle,
          items,
          showRank: showRank,
          posterCards: posterCards,
        ),
      );
      usedKeys.addAll(items.map(_homeUsedKey));
    }

    final todayEditorial = editorial?.todaySignal;
    if (_hasHomeEditorialScope(todayEditorial)) {
      final todayRemoteItems = _remoteHomeSignalItems(
        _todaySignalRemoteItems,
        todayEditorial!,
      );
      addRail(
        editorial: todayEditorial,
        primary: todayRemoteItems.isNotEmpty
            ? todayRemoteItems
            : _itemsForEditorial(todayEditorial),
        limit: 20,
        preservePrimaryRank: todayRemoteItems.isNotEmpty,
      );
    }

    final weekEditorial = editorial?.topSignal;
    if (_hasHomeEditorialScope(weekEditorial)) {
      final weekRemoteItems = _remoteHomeSignalItems(
        _topSignalRemoteItems,
        weekEditorial!,
      );
      addRail(
        editorial: weekEditorial,
        primary: weekRemoteItems.isNotEmpty
            ? weekRemoteItems
            : _itemsForEditorial(weekEditorial),
        limit: 20,
        preservePrimaryRank: weekRemoteItems.isNotEmpty,
      );
    }

    final topTenEditorial = editorial?.juicrTopSignal;
    if (_hasHomeEditorialScope(topTenEditorial)) {
      final topTenRemoteItems = _remoteHomeSignalItems(
        _juicrTopSignalRemoteItems,
        topTenEditorial!,
      );
      addRail(
        editorial: topTenEditorial,
        primary: topTenRemoteItems.isNotEmpty
            ? topTenRemoteItems
            : _itemsForEditorial(topTenEditorial),
        limit: 10,
        preservePrimaryRank: topTenRemoteItems.isNotEmpty,
      );
    }

    final rawUpcomingEditorial = _hasHomeEditorialScope(editorial?.upcoming)
        ? editorial!.upcoming
        : const _TvHomeEditorialRail(
            id: 'upcomingEditorial',
            title: 'Upcoming This Year',
            subtitle: '',
          );
    final upcomingEditorial = _TvHomeEditorialRail(
      id: rawUpcomingEditorial.id,
      title: 'Upcoming This Year',
      subtitle: '',
      kind: rawUpcomingEditorial.kind,
      types: rawUpcomingEditorial.types,
      genres: rawUpcomingEditorial.genres,
      sort: rawUpcomingEditorial.sort,
      perType: rawUpcomingEditorial.perType,
      requireGenreMatch: rawUpcomingEditorial.requireGenreMatch,
      intent: rawUpcomingEditorial.intent,
      curationKind: rawUpcomingEditorial.curationKind,
      releaseWindow: rawUpcomingEditorial.releaseWindow,
      theme: rawUpcomingEditorial.theme,
      seasonalWindow: rawUpcomingEditorial.seasonalWindow,
      query: rawUpcomingEditorial.query,
      items: rawUpcomingEditorial.items,
    );
    final upcomingLaneItems = _discoveryLaneItems[_tvDiscoveryLaneKey(
          _TvDiscoveryKind.movie,
          _TvDiscoverySort.upcoming,
        )] ??
        const <_TvItem>[];
    final upcomingPrimary = upcomingLaneItems.isNotEmpty
        ? upcomingLaneItems
        : (_upcomingPicks.isNotEmpty
            ? _upcomingPicks
            : _itemsForEditorial(upcomingEditorial));
    if (upcomingPrimary.isNotEmpty) {
      addRail(
        editorial: upcomingEditorial,
        primary: upcomingPrimary,
        limit: 20,
        showRank: false,
        posterCards: true,
      );
    }

    addRail(
      editorial: const _TvHomeEditorialRail(
        id: 'savedForLater',
        title: 'Saved For Later',
        subtitle: 'Titles you marked to revisit.',
      ),
      primary: _likedItems,
      limit: 12,
      showRank: false,
    );

    return rails;
  }

  List<_TvItem> get _homeHeroItems {
    if (_heroEditorialItems.isNotEmpty) {
      return [
        for (final item in _heroEditorialItems.take(8)) _applyHomeArtwork(item),
      ];
    }
    final editorial = _homeEditorial;
    if (editorial != null && _hasHomeEditorialScope(editorial.hero)) {
      final curated = _itemsForEditorial(editorial.hero);
      if (curated.isNotEmpty) {
        return [
          for (final item in curated.take(8)) _applyHomeArtwork(item),
        ];
      }
    }
    return const <_TvItem>[];
  }

  _TvHomeEditorialRail get _homeHeroEditorial {
    return _homeEditorial?.hero ??
        const _TvHomeEditorialRail(id: 'hero', title: '', subtitle: '');
  }

  Future<List<_TvItem>> _loadCuratedHeroItems(
    _TvHomeEditorialRail editorial, {
    required List<_TvItem> seedItems,
  }) async {
    const heroLimit = 12;
    const heroCandidateLimit = 36;
    const heroArtworkCandidateLimit = 16;
    if (!_hasHeroEditorialScope(editorial)) {
      final hydrated = await _hydrateHeroArtworkItems(
        _itemsForEditorial(
          editorial,
          seedItems,
        ).take(heroArtworkCandidateLimit),
        limit: heroLimit,
      );
      return hydrated;
    }
    final ranked = await _hydrateHomeSignalRail(
      editorial,
      seedItems: seedItems,
      limit: heroCandidateLimit,
    );
    if (ranked.isNotEmpty) {
      final hydratedRanked = await _hydrateHeroArtworkItems(
        ranked.take(heroArtworkCandidateLimit),
        limit: heroLimit,
      );
      if (_hasLogoArtwork(hydratedRanked)) return hydratedRanked;
    }
    final types = editorial.types.isEmpty
        ? const ['movie', 'series', 'animation']
        : editorial.types;
    final genre =
        editorial.genres.isEmpty ? 'All genres' : editorial.genres.first;
    final perType = editorial.perType.clamp(1, 12).toInt();
    final buckets = await Future.wait<List<_TvItem>>([
      for (final type in types)
        _loadCuratedHeroBucket(
          type: type,
          editorial: editorial,
          genre: genre,
          limit: perType * 3,
        ),
    ]);
    final interleaved = _interleaveHeroBuckets(
      buckets,
    ).take(heroCandidateLimit).toList();
    if (interleaved.isNotEmpty) {
      return _hydrateHeroArtworkItems(
        interleaved.take(heroArtworkCandidateLimit),
        limit: heroLimit,
      );
    }
    final editorialFallback = _itemsForEditorial(editorial, seedItems);
    return _hydrateHeroArtworkItems(
      editorialFallback.take(heroArtworkCandidateLimit),
      limit: heroLimit,
    );
  }

  Future<List<_TvItem>> _hydrateHeroArtworkItems(
    Iterable<_TvItem> sourceItems, {
    int limit = 12,
  }) async {
    final items = sourceItems.toList(growable: false);
    if (items.isEmpty) return const <_TvItem>[];
    final hydrated = await Future.wait([
      for (final item in items) _hydrateHeroArtworkItem(item),
    ]);
    final withLogo = hydrated
        .where((item) => (item.logo ?? '').trim().isNotEmpty)
        .toList(growable: false);
    if (withLogo.isEmpty) return hydrated.take(limit).toList(growable: false);
    final withoutLogo = hydrated
        .where((item) => (item.logo ?? '').trim().isEmpty)
        .toList(growable: false);
    return [...withLogo, ...withoutLogo].take(limit).toList(growable: false);
  }

  bool _hasLogoArtwork(Iterable<_TvItem> items) {
    return items.any((item) => (item.logo ?? '').trim().isNotEmpty);
  }

  Future<_TvItem> _hydrateHeroArtworkItem(_TvItem item) async {
    if ((item.poster ?? '').trim().isNotEmpty &&
        (item.logo ?? '').trim().isNotEmpty &&
        (item.background ?? '').trim().isNotEmpty &&
        (item.description ?? '').trim().isNotEmpty) {
      return item;
    }
    try {
      final metaSeed = item.tmdbId == null
          ? item
          : _TvItem(
              id: 'tmdb:${item.tmdbId}',
              type: item.type,
              title: item.title,
              color: item.color,
              poster: item.poster,
              background: item.background,
              logo: item.logo,
              year: item.year,
              tmdbId: item.tmdbId,
              genres: item.genres,
              description: item.description,
              imdbRating: item.imdbRating,
              releaseDate: item.releaseDate,
              isUpcoming: item.isUpcoming,
              runtime: item.runtime,
            );
      final meta =
          await _api.meta(metaSeed).timeout(const Duration(seconds: 8));
      return item.merge(meta);
    } catch (error) {
      debugPrint(
        'Juicr TV hero artwork hydrate skipped '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return item;
    }
  }

  bool _hasHeroEditorialScope(_TvHomeEditorialRail editorial) {
    return editorial.title.isNotEmpty &&
        (editorial.genres.isNotEmpty ||
            editorial.query.isNotEmpty ||
            editorial.items.isNotEmpty ||
            _isInTheatersEditorial(editorial));
  }

  bool _hasHomeEditorialScope(_TvHomeEditorialRail? editorial) {
    if (editorial == null) return false;
    return editorial.title.trim().isNotEmpty ||
        editorial.subtitle.trim().isNotEmpty ||
        editorial.items.isNotEmpty ||
        editorial.query.trim().isNotEmpty ||
        editorial.genres.isNotEmpty;
  }

  Future<List<_TvItem>> _loadCuratedHeroBucket({
    required String type,
    required _TvHomeEditorialRail editorial,
    required String genre,
    required int limit,
  }) async {
    final gathered = <_TvItem>[];
    final seen = <String>{};
    for (final sort in _curatedHeroSortFallbacks(editorial.sort)) {
      for (var page = 1; page <= 3; page += 1) {
        try {
          final items = await _api
              .catalog(
                type: type,
                sort: sort,
                page: page,
                genre: genre,
                search: editorial.query,
                deepSearch: editorial.query.isNotEmpty,
                preferDefaultCatalog: true,
              )
              .timeout(const Duration(seconds: 8));
          if (items.isEmpty) break;
          for (final item in items.map(_normalizeCatalogLane)) {
            if (item.poster == null || _isLiveTvItem(item)) continue;
            if (!_homeItemMatchesEditorialIntent(item, editorial)) continue;
            if (seen.add(_homeUsedKey(item))) gathered.add(item);
          }
          final matches = _bestEditorialMatches(
            gathered,
            editorial,
            limit,
            allowUnknownGenre: true,
          );
          if (matches.length >= limit) return matches;
        } catch (error) {
          debugPrint(
            'Juicr TV hero editorial bucket skipped '
            'type=$type page=$page bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
          );
          break;
        }
      }
    }
    return _bestEditorialMatches(
      gathered,
      editorial,
      limit,
      allowUnknownGenre: true,
    );
  }

  List<String> _curatedHeroSortFallbacks(String preferred) {
    final normalized =
        preferred.trim().isEmpty ? 'imdbRating' : preferred.trim();
    return [
      normalized,
      for (final sort in const ['imdbRating', 'top', 'year'])
        if (sort.toLowerCase() != normalized.toLowerCase()) sort,
    ];
  }

  List<_TvItem> _interleaveHeroBuckets(List<List<_TvItem>> buckets) {
    final result = <_TvItem>[];
    final seen = <String>{};
    final maxLength = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.length),
    );
    for (var index = 0; index < maxLength; index += 1) {
      for (final bucket in buckets) {
        if (index >= bucket.length) continue;
        final item = bucket[index];
        if (seen.add(_homeUsedKey(item))) result.add(item);
      }
    }
    return result;
  }

  bool _homeItemMatchesEditorialIntent(
    _TvItem item,
    _TvHomeEditorialRail editorial,
  ) {
    if (_isInTheatersEditorial(editorial)) {
      return item.type == 'movie' &&
          _yearInt(item.year) >= DateTime.now().year - 1;
    }
    if (!_homeItemMatchesEditorialQuery(item, editorial.query)) return false;
    if (!_requiresCurrentReleaseWindow(editorial)) return true;
    final year = _yearInt(item.year);
    return year > 0 && year == DateTime.now().year;
  }

  bool _homeItemMatchesEditorialQuery(_TvItem item, String query) {
    final cleaned = _normalizeHomeText(query);
    if (cleaned.isEmpty) return true;
    final haystack = _normalizeHomeText(
      [item.title, item.id, item.year ?? '', ...item.genres].join(' '),
    );
    final tokens =
        cleaned.split(RegExp(r'[\s:_-]+')).where((token) => token.length >= 3);
    if (tokens.isEmpty) return haystack.contains(cleaned);
    return tokens.every(haystack.contains);
  }

  List<_TvItem> _bestEditorialMatches(
    List<_TvItem> items,
    _TvHomeEditorialRail editorial,
    int limit, {
    bool allowUnknownGenre = false,
  }) {
    final scoped = [
      for (final item in items)
        if (_homeItemMatchesEditorialIntent(item, editorial)) item,
    ];
    final genreMatches = scoped.where((item) {
      if (_itemMatchesAnyEditorialGenre(item, editorial.genres)) {
        return true;
      }
      return allowUnknownGenre && item.genres.isEmpty;
    }).toList(growable: false);
    final ranked = (editorial.genres.isEmpty ? scoped : genreMatches)
      ..sort(
        (left, right) =>
            _homeSignalScore(right).compareTo(_homeSignalScore(left)),
      );
    if (ranked.length >= limit || editorial.requireGenreMatch) {
      return _dedupeHomeItems(ranked).take(limit).toList(growable: false);
    }
    final matched = {for (final item in ranked) _homeUsedKey(item)};
    final fallback = [
      for (final item in scoped)
        if (!matched.contains(_homeUsedKey(item))) item,
    ]..sort(
        (left, right) =>
            _homeSignalScore(right).compareTo(_homeSignalScore(left)),
      );
    return _dedupeHomeItems([
      ...ranked,
      ...fallback,
    ]).take(limit).toList(growable: false);
  }

  bool _itemMatchesAnyEditorialGenre(_TvItem item, List<String> genres) {
    if (genres.isEmpty) return true;
    final itemGenres = item.genres.map((genre) => genre.toLowerCase()).toList();
    return genres.any((target) {
      final normalizedTarget = target.toLowerCase();
      return itemGenres.any(
        (genre) =>
            genre == normalizedTarget ||
            genre.contains(normalizedTarget) ||
            normalizedTarget.contains(genre),
      );
    });
  }

  bool _isInTheatersEditorial(_TvHomeEditorialRail editorial) {
    final title = editorial.title.trim().toLowerCase();
    final intent = editorial.intent.trim().toLowerCase();
    final window = editorial.releaseWindow.trim().toLowerCase();
    return title == 'in theaters' ||
        intent == 'theatrical_trailers' ||
        window == 'now_playing';
  }

  List<_TvItem> _remoteHomeSignalItems(
    List<_TvItem> items,
    _TvHomeEditorialRail editorial,
  ) {
    if (items.isEmpty || editorial.items.isEmpty) return const <_TvItem>[];
    final remaining = _availableHomeItems(items).toList();
    final ranked = <_TvItem>[];
    final seen = <String>{};
    for (final signal in editorial.items) {
      final index = remaining.indexWhere(
        (item) => _itemMatchesHomeSignal(item, signal),
      );
      if (index < 0) continue;
      final match = remaining.removeAt(index);
      if (seen.add(_homeUsedKey(match))) ranked.add(match);
    }
    return ranked;
  }

  String _homeUsedKey(_TvItem item) {
    final tmdbId = item.tmdbId;
    if (tmdbId != null) return '${item.type}:tmdb:$tmdbId';
    return '${item.type}:${_normalizeHomeText(item.title)}:${item.year ?? ''}';
  }

  Set<String> _homeArtworkKeys(_TvItem item) {
    final keys = <String>{_homeUsedKey(item)};
    final normalizedTitle = _normalizeHomeText(item.title);
    if (normalizedTitle.isNotEmpty) {
      keys.add('${item.type}:$normalizedTitle:${item.year ?? ''}');
    }
    final tmdbId = item.tmdbId;
    if (tmdbId != null) keys.add('${item.type}:tmdb:$tmdbId');
    final rawId = item.id.trim();
    if (rawId.isNotEmpty) keys.add('${item.type}:id:$rawId');
    return keys;
  }

  List<_TvItem> _availableHomeItems(Iterable<_TvItem> items) {
    final result = <_TvItem>[];
    for (final item in items) {
      final decorated = _applyHomeArtwork(item);
      if (decorated.poster != null && !_isLiveTvItem(decorated)) {
        result.add(decorated);
      }
    }
    return result;
  }

  List<_TvItem> _dedupeHomeItems(Iterable<_TvItem> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (seen.add(_homeUsedKey(item))) item,
    ];
  }

  List<_TvItem> _backfilledHomeRailItems(
    List<_TvItem> primary, {
    required List<_TvItem> fallbackPool,
    required Set<String> usedKeys,
    required int limit,
    bool preservePrimaryRank = false,
  }) {
    final seen = <String>{};
    final result = <_TvItem>[];
    void addItems(Iterable<_TvItem> items, {required bool allowUsed}) {
      for (final item in _availableHomeItems(items)) {
        if (result.length >= limit) break;
        final key = _homeUsedKey(item);
        if ((!allowUsed && usedKeys.contains(key)) || !seen.add(key)) {
          continue;
        }
        result.add(item);
      }
    }

    addItems(primary, allowUsed: preservePrimaryRank);
    if (result.length < limit) addItems(fallbackPool, allowUsed: false);
    return result;
  }

  double _homeSignalScore(_TvItem item) {
    var score = _ratingDouble(item.imdbRating) * 10;
    final year = _yearInt(item.year);
    final currentYear = DateTime.now().year;
    if (year > 0) {
      score += math.max(0, 8 - (currentYear - year).abs()).toDouble();
    }
    if (_isItemLiked(item)) score += 14;
    if (_recentItems.any((recent) => _itemKey(recent) == _itemKey(item))) {
      score += 10;
    }
    return score;
  }

  String _normalizeHomeText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  List<_TvItem> _itemsForEditorial(
    _TvHomeEditorialRail editorial, [
    List<_TvItem>? sourceItems,
  ]) {
    var candidates = _availableHomeItems(sourceItems ?? _items);
    final ranked = _rankedItemsForEditorial(editorial, candidates);
    if (ranked.isNotEmpty) return ranked;
    if (editorial.types.isNotEmpty) {
      final types = editorial.types.toSet();
      candidates =
          candidates.where((item) => types.contains(item.type)).toList();
    }
    if (editorial.query.isNotEmpty) {
      final query = _normalizeHomeText(editorial.query);
      candidates = candidates.where((item) {
        final haystack = _normalizeHomeText(
          [item.title, item.id, item.year ?? '', ...item.genres].join(' '),
        );
        return query.isEmpty || haystack.contains(query);
      }).toList();
    }
    if (editorial.genres.isNotEmpty) {
      final genres =
          editorial.genres.map((genre) => genre.toLowerCase()).toSet();
      final genreMatches = candidates.where((item) {
        return item.genres.any((genre) => genres.contains(genre.toLowerCase()));
      }).toList();
      if (genreMatches.isNotEmpty || editorial.requireGenreMatch) {
        candidates = genreMatches;
      }
    }
    if (_requiresCurrentReleaseWindow(editorial)) {
      final currentYear = DateTime.now().year;
      final current = candidates
          .where((item) => _yearInt(item.year) >= currentYear - 1)
          .toList();
      if (current.isNotEmpty || editorial.requireGenreMatch) {
        candidates = current;
      }
    }
    if (editorial.sort == 'year') {
      candidates.sort((a, b) => (_yearInt(b.year)).compareTo(_yearInt(a.year)));
    } else if (editorial.sort.toLowerCase().contains('imdb')) {
      candidates.sort(
        (a, b) => (_ratingDouble(
          b.imdbRating,
        )).compareTo(_ratingDouble(a.imdbRating)),
      );
    }
    return _stableDailyShuffle(candidates, seed: editorial.title.hashCode);
  }

  List<_TvItem> _rankedItemsForEditorial(
    _TvHomeEditorialRail editorial,
    List<_TvItem> candidates,
  ) {
    if (editorial.items.isEmpty || candidates.isEmpty) return const <_TvItem>[];
    final byTmdb = <String, _TvItem>{};
    final byTitle = <String, _TvItem>{};
    for (final item in candidates) {
      if (item.tmdbId != null) {
        byTmdb['${item.type}:${item.tmdbId}'] = item;
      }
      final normalizedTitle = _normalizeHomeText(item.title);
      byTitle['${item.type}:$normalizedTitle:${item.year ?? ''}'] = item;
      byTitle.putIfAbsent('${item.type}:$normalizedTitle:', () => item);
    }
    final ranked = <_TvItem>[];
    final seen = <String>{};
    for (final item in editorial.items) {
      final normalizedTitle = _normalizeHomeText(item.title);
      final match = item.tmdbId == null
          ? byTitle['${item.type}:$normalizedTitle:${item.year ?? ''}'] ??
              byTitle['${item.type}:$normalizedTitle:']
          : byTmdb['${item.type}:${item.tmdbId}'];
      if (match != null && seen.add(_itemKey(match))) {
        ranked.add(match);
      }
    }
    return ranked;
  }

  bool _requiresCurrentReleaseWindow(_TvHomeEditorialRail editorial) {
    final intent = editorial.intent.toLowerCase();
    final window = editorial.releaseWindow.toLowerCase();
    return intent.contains('current') || window.contains('current_year');
  }

  List<_TvItem> _stableDailyShuffle(List<_TvItem> items, {required int seed}) {
    final copy = [...items];
    final random = math.Random(_editorialBucket(offset: seed.abs() % 997));
    copy.shuffle(random);
    return copy;
  }

  int _editorialBucket({int offset = 0}) {
    final now = DateTime.now();
    final days = now.difference(DateTime(2024)).inDays;
    return days + offset;
  }

  void _selectTab(int index, {bool resetLibraryFilter = false}) {
    _cancelPreparingPlayback();
    setState(() {
      _selectedTab = index;
      _selectedItem = null;
      _expandedRail = null;
      _searchOpen = false;
      if (index == 0) {
        _lastPageFocusNodes[0] = _homeHeroWatchFocusNode;
        _lastPageFocusItemKeys[0] = null;
        _pendingPageFocusItemKeys[0] = null;
      }
      if (resetLibraryFilter) {
        _libraryFilter = _TvLibraryFilter.continueWatching;
      }
    });
    if (index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedTab != 1) return;
        _ensureSelectedDiscoveryLaneLoaded();
      });
    }
  }

  void _restoreHomeHero() {
    _revealHomeHeroAfterFrame(requestHeroFocus: true);
  }

  void _revealHomeHeroAfterFrame({
    required bool requestHeroFocus,
    bool focusNavigationAfterReveal = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (requestHeroFocus) {
        _homeHeroWatchFocusNode.requestFocus();
      }
      final heroContext = _homeHeroKey.currentContext;
      if (heroContext != null && heroContext.mounted) {
        try {
          Scrollable.ensureVisible(
            heroContext,
            duration: _tvDuration(180),
            curve: Curves.easeOutCubic,
            alignment: 0,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
        } on FlutterError {
          // Home can rebuild while catalog rails hydrate; focus is enough.
        }
      }
      if (focusNavigationAfterReveal) {
        _navigationRailKey.currentState?.focusSelected();
      }
    });
  }

  void _selectNavigationItem(int index) {
    if (_navItems[index].label == 'Search') {
      _cancelPreparingPlayback();
      setState(() {
        _selectedItem = null;
        _expandedRail = null;
        _searchOpen = true;
      });
      return;
    }
    final tabIndex = _tabIndexForNavIndex(index);
    if (tabIndex != null) {
      final selectingLibrary = _tabItems[tabIndex].label == 'Library';
      if (tabIndex == _selectedTab) {
        if (selectingLibrary &&
            _libraryFilter != _TvLibraryFilter.continueWatching) {
          setState(() {
            _expandedRail = null;
            _selectedItem = null;
            _searchOpen = false;
            _libraryFilter = _TvLibraryFilter.continueWatching;
          });
        }
        _enterSelectedTabContent();
        return;
      }
      _selectTab(tabIndex, resetLibraryFilter: selectingLibrary);
      _enterSelectedTabContentAfterNavigation();
    }
  }

  void _moveRightFromNavigation(int index) {
    if (_navItems[index].label == 'Search') {
      _cancelPreparingPlayback();
      setState(() {
        _selectedItem = null;
        _expandedRail = null;
        _searchOpen = true;
      });
      return;
    }
    final tabIndex = _tabIndexForNavIndex(index);
    if (tabIndex == null) return;
    if (tabIndex != _selectedTab) {
      _selectTab(tabIndex);
    }
    _enterSelectedTabContentAfterNavigation();
  }

  void _enterSelectedTabContentAfterNavigation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _enterSelectedTabContent();
      Future<void>.delayed(const Duration(milliseconds: 70), () {
        final navigationState = _navigationRailKey.currentState;
        if (!mounted || navigationState == null || !navigationState.hasFocus) {
          return;
        }
        _enterSelectedTabContent();
      });
    });
  }

  int _navIndexForTab(int tabIndex) {
    final label = _tabItems[tabIndex].label;
    return _navItems.indexWhere((item) => item.label == label);
  }

  int? _tabIndexForNavIndex(int navIndex) {
    final label = _navItems[navIndex].label;
    final tabIndex = _tabItems.indexWhere((item) => item.label == label);
    return tabIndex == -1 ? null : tabIndex;
  }

  void _pauseHomeHeroCarousel() {
    setState(() => _homeHeroCarouselPauseDepth += 1);
  }

  void _resumeHomeHeroCarousel() {
    if (_homeHeroCarouselPauseDepth <= 0) return;
    setState(() => _homeHeroCarouselPauseDepth -= 1);
  }

  Future<void> _openItem(_TvItem item) async {
    final openedFromHomeHero =
        _selectedTab == 0 && !_searchOpen && _homeHeroWatchFocusNode.hasFocus;
    final pauseHomeHeroCarousel = _selectedTab == 0 && !_searchOpen;
    final previousFocus = FocusManager.instance.primaryFocus;
    final openedItemKey = _itemKey(item);
    if (pauseHomeHeroCarousel) {
      _pauseHomeHeroCarousel();
    }
    _rememberItem(item);
    final openedFromSearch = _searchOpen;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _TvDetailsPage(
            item: item,
            settings: _tvSettings,
            liked: _isItemLiked(item),
            libraryLists: _libraryStore?.state.libraryLists ?? const [],
            onCancelPreparing: _cancelPreparingPlayback,
            onPlay: (detailsItem) =>
                _play(detailsItem, returnToDetailsOnClose: false),
            onPlayEpisode: (detailsItem, season, episode) => _play(
              detailsItem,
              season: season,
              episode: episode,
              returnToDetailsOnClose: false,
            ),
            onOpenItem: _openItem,
            onToggleSaved: _toggleLike,
            onCreateList: _createLibraryListForItem,
            onToggleList: _toggleItemInLibraryList,
            isItemSaved: _isItemLiked,
            isItemInList: _isItemInLibraryList,
            progressForPlayback: _watchedProgressForPlayback,
          ),
        ),
      );
    } finally {
      if (mounted && pauseHomeHeroCarousel) {
        _resumeHomeHeroCarousel();
      }
    }
    if (!mounted) return;
    final homeRouteIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!homeRouteIsCurrent) {
      _restoreTvFocusAfterRoutePop(previousFocus);
      return;
    }
    if (openedFromSearch && _searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_searchOpen) return;
        _searchOverlayKey.currentState?.restoreFocus(openedItemKey);
      });
      return;
    }
    if (openedFromHomeHero) {
      _lastPageFocusNodes[0] = _homeHeroWatchFocusNode;
      _restoreHomeHero();
      return;
    }
    _queuePageItemFocus(openedItemKey);
    _focusRememberedPageNode();
  }

  void _rememberItem(_TvItem item) {
    _rememberRecentItem(item);
    if (_tvSettings.keepHistory) {
      unawaited(
        _libraryStore?.addRecentItem(
              key: _itemKey(item),
              itemId: item.id,
              snapshot: _itemSnapshot(item),
            ) ??
            Future<void>.value(),
      );
      _scheduleAccountLibraryPush();
    }
  }

  void _rememberContinueItem(_TvItem item) {
    _rememberRecentItem(item);
    unawaited(
      _libraryStore?.addRecentItem(
            key: _itemKey(item),
            itemId: item.id,
            snapshot: _itemSnapshot(item),
          ) ??
          Future<void>.value(),
    );
  }

  void _rememberRecentItem(_TvItem item) {
    _recentItems.removeWhere(
      (candidate) => candidate.type == item.type && candidate.id == item.id,
    );
    _recentItems.insert(0, item);
    if (_recentItems.length > 24) {
      _recentItems.removeRange(24, _recentItems.length);
    }
  }

  void _cancelPreparingPlayback() {
    _playRequestGeneration++;
    if (_preparingPlaybackKey == null) return;
    if (mounted) {
      setState(() => _preparingPlaybackKey = null);
    } else {
      _preparingPlaybackKey = null;
    }
  }

  String _itemKey(_TvItem item) => '${item.type}:${item.id}';

  _TvItem? _itemFromRecentSnapshot(TvRecentItemSnapshot snapshot) {
    final itemType = snapshot.itemType ?? snapshot.key.split(':').first;
    final itemId = snapshot.itemId ?? snapshot.key.split(':').skip(1).join(':');
    final title = snapshot.title;
    if (itemId.trim().isEmpty || title == null || title.trim().isEmpty) {
      return null;
    }
    return _TvItem(
      id: itemId,
      type: _normalizeType(itemType),
      title: title,
      color: _colorFromText(itemId),
      year: snapshot.year,
      poster: snapshot.poster,
      background: snapshot.background,
      logo: snapshot.logo,
      tmdbId: snapshot.tmdbId,
      imdbId: snapshot.imdbId,
    );
  }

  Map<String, Object?> _itemSnapshot(_TvItem item) {
    return <String, Object?>{
      'id': item.id,
      'type': item.type,
      'title': item.title,
      if (item.year != null) 'year': item.year,
      if ((item.poster ?? '').trim().isNotEmpty) 'poster': item.poster,
      if ((item.background ?? '').trim().isNotEmpty)
        'background': item.background,
      if ((item.logo ?? '').trim().isNotEmpty) 'logo': item.logo,
      if (item.tmdbId != null) 'tmdbId': item.tmdbId,
      if ((item.imdbId ?? '').trim().isNotEmpty) 'imdbId': item.imdbId,
    };
  }

  void _reconcileRecentItemsWithCatalog() {
    if (_recentItems.isEmpty || _items.isEmpty) return;
    final catalogByKey = {for (final item in _items) _itemKey(item): item};
    for (var index = 0; index < _recentItems.length; index++) {
      final catalogItem = catalogByKey[_itemKey(_recentItems[index])];
      if (catalogItem != null) {
        _recentItems[index] = _recentItems[index].merge(catalogItem);
      }
    }
  }

  bool _isItemLiked(_TvItem item) => _likedItemKeys.contains(_itemKey(item));

  List<_TvItem> get _likedItems {
    final candidates = <String, _TvItem>{};
    for (final item in [
      ..._items,
      ..._movies,
      ..._series,
      ..._animation,
      ..._recentItems,
    ]) {
      candidates[_itemKey(item)] = item;
    }
    final snapshotsByKey = {
      for (final snapshot
          in _libraryStore?.state.recentItems ?? const <TvRecentItemSnapshot>[])
        snapshot.key: snapshot,
    };
    return [
      for (final key in _likedItemKeys)
        if (candidates[key] != null)
          candidates[key]!
        else if (snapshotsByKey[key] != null &&
            _itemFromRecentSnapshot(snapshotsByKey[key]!) != null)
          _itemFromRecentSnapshot(snapshotsByKey[key]!)!,
    ];
  }

  void _toggleLike(_TvItem item) {
    var liked = false;
    setState(() {
      final key = _itemKey(item);
      liked = _likedItemKeys.add(key);
      if (!liked) {
        _likedItemKeys.remove(key);
      }
    });
    unawaited(
      _libraryStore?.setLiked(_itemKey(item), liked) ?? Future<void>.value(),
    );
    if (liked) {
      _rememberContinueItem(item);
    }
    _scheduleAccountLibraryPush();
  }

  Future<TvLibraryList?> _createLibraryListForItem(
    _TvItem item,
    String name,
  ) async {
    final store = _libraryStore;
    if (store == null) return null;
    final list = await store.createLibraryList(
      name,
      initialItemKey: _itemKey(item),
    );
    if (!mounted) return list;
    setState(() => _likedItemKeys.add(_itemKey(item)));
    _rememberContinueItem(item);
    _scheduleAccountLibraryPush();
    return list;
  }

  Future<bool> _toggleItemInLibraryList(
    _TvItem item,
    TvLibraryList list,
  ) async {
    final store = _libraryStore;
    if (store == null) return false;
    final selected = await store.toggleItemInLibraryList(
      list.id,
      _itemKey(item),
    );
    if (!mounted) return selected;
    setState(() => _likedItemKeys.add(_itemKey(item)));
    _rememberContinueItem(item);
    _scheduleAccountLibraryPush();
    return selected;
  }

  bool _isItemInLibraryList(_TvItem item, TvLibraryList list) {
    return list.itemKeys.contains(_itemKey(item));
  }

  void _updateTvSettings(_TvSettingsState next) {
    final shouldRefreshCatalog =
        _tvSettings.builtInCatalog != next.builtInCatalog ||
            _tvSettings.builtInLiveTv != next.builtInLiveTv;
    setState(() {
      _tvSettings = next;
      if (!next.keepHistory) {
        _recentItems.clear();
        unawaited(
          _libraryStore?.save(
                _libraryStore!.state.copyWith(recentItems: const []),
              ) ??
              Future<void>.value(),
        );
      }
    });
    unawaited(_persistTvSettings(next));
    if (shouldRefreshCatalog) {
      unawaited(_loadCatalog(force: true));
    }
  }

  void _ensureSelectedDiscoveryLaneLoaded() {
    if (!_tvSettings.hasCatalogSource) return;
    final laneKey = _tvDiscoveryLaneKey(
      _discoveryKind,
      _discoverySort,
      genre: _discoveryGenre,
    );
    if ((_discoveryLaneItems[laneKey] ?? const <_TvItem>[]).isNotEmpty) return;
    if (_discoveryLaneLoading.contains(laneKey) ||
        _discoveryLaneExhausted.contains(laneKey)) {
      return;
    }
    unawaited(_loadMoreDiscoveryLane());
  }

  void _closeOverlay({bool focusNavigation = false}) {
    _cancelPreparingPlayback();
    final wasSearchOpen = _searchOpen;
    setState(() {
      _selectedItem = null;
      _searchOpen = false;
      if (wasSearchOpen && _selectedTab == 0) {
        _lastPageFocusNodes[0] = _homeHeroWatchFocusNode;
        _lastPageFocusItemKeys[0] = null;
        _pendingPageFocusItemKeys[0] = null;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (wasSearchOpen && _selectedTab == 0) {
        if (focusNavigation) {
          _revealHomeHeroAfterFrame(
            requestHeroFocus: false,
            focusNavigationAfterReveal: true,
          );
        } else {
          _restoreHomeHero();
        }
        return;
      }
      if (focusNavigation) {
        _navigationRailKey.currentState?.focusSelected();
      } else if (_focusRememberedPageNode()) {
        return;
      } else {
        _focusPageEntry();
      }
    });
  }

  void _handleBackPressed() {
    final now = DateTime.now();
    final duplicateBack = _lastBackDispatchAt != null &&
        now.difference(_lastBackDispatchAt!) <
            const Duration(milliseconds: 180);
    if (duplicateBack) return;
    _lastBackDispatchAt = now;
    if (_searchOpen) {
      _closeOverlay(focusNavigation: true);
      return;
    }
    if (_selectedItem != null) {
      _closeOverlay();
      return;
    }
    if (_expandedRail != null) {
      setState(() => _expandedRail = null);
      return;
    }
    final navigationHasFocus =
        _navigationRailKey.currentState?.hasFocus == true;
    if (!navigationHasFocus) {
      _lastExitBackPressAt = null;
      _navigationRailKey.currentState?.focusSelected();
      return;
    }
    if (_selectedTab != 0) {
      _lastExitBackPressAt = null;
      _cancelPreparingPlayback();
      setState(() {
        _selectedTab = 0;
        _expandedRail = null;
        _selectedItem = null;
        _searchOpen = false;
      });
      _lastPageFocusNodes[0] = _homeHeroWatchFocusNode;
      _restoreHomeHero();
      return;
    }
    final shouldExit = _lastExitBackPressAt != null &&
        now.difference(_lastExitBackPressAt!) < const Duration(seconds: 2);
    if (shouldExit) {
      SystemNavigator.pop();
      return;
    }
    _lastExitBackPressAt = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Press Back again to exit Juicr TV.')),
      );
  }

  Future<void> _openDiscoveryMenu() async {
    var changed = false;
    await _showTvDialog<void>(
      context: context,
      builder: (context) => _TvDiscoveryMenuDialog(
        kind: _discoveryKind,
        sort: _discoverySort,
        genre: _discoveryGenre,
        genres: _availableDiscoveryGenres,
        onChanged: (selection) {
          if (!mounted) return;
          setState(() {
            changed = true;
            _discoveryKind = selection.kind;
            _discoverySort = selection.sort;
            _discoveryGenre = selection.genre;
          });
        },
      ),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (changed) {
        _rememberPageFocus(_pageEntryFocusNodes[_selectedTab]);
        _ensureSelectedDiscoveryLaneLoaded();
        _focusPageEntry();
        return;
      }
      if (_focusRememberedPageNode()) return;
      _focusPageEntry();
    });
  }

  List<String> get _availableDiscoveryGenres {
    final genres = <String, String>{};
    final candidates = <String, _TvItem>{
      for (final item in _items) '${item.type}:${item.id}': item,
      for (final entry in _discoveryLaneItems.entries)
        for (final item in entry.value) '${item.type}:${item.id}': item,
    }.values;
    for (final item in candidates) {
      if (!_matchesDiscoveryLaneKind(item, _discoveryKind)) continue;
      for (final rawGenre in item.genres) {
        final genre = rawGenre.trim();
        if (genre.isEmpty) continue;
        final key = genre.toLowerCase();
        genres.putIfAbsent(key, () => _formatDiscoveryGenreLabel(genre));
      }
    }
    final sorted = genres.values.toList()
      ..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
    return sorted;
  }

  String _formatDiscoveryGenreLabel(String genre) {
    return genre
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) {
      if (part.length <= 2 && part == part.toUpperCase()) return part;
      return part[0].toUpperCase() + part.substring(1).toLowerCase();
    }).join(' ');
  }

  Future<void> _openLibraryMenu() async {
    await _showTvDialog<void>(
      context: context,
      builder: (context) => _TvLibraryMenuDialog(
        filter: _libraryFilter,
        onChanged: (selection) {
          if (!mounted) return;
          setState(() => _libraryFilter = selection);
        },
      ),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusRememberedPageNode()) return;
      _focusPageEntry();
    });
  }

  Future<void> _openItemLibraryMenu(_TvItem item) async {
    final saved = _isItemLiked(item);
    final action = await _showTvDialog<_TvLibraryAction>(
      context: context,
      builder: (_) => _TvLibraryActionDialog(saved: saved),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _TvLibraryAction.toggleSaved:
        _toggleLike(item);
      case _TvLibraryAction.addToList:
        await _openItemListPicker(item);
    }
  }

  Future<void> _openItemListPicker(_TvItem item) async {
    final result = await _showTvDialog<Object>(
      context: context,
      builder: (_) => _TvListPickerDialog(
        item: item,
        lists: _libraryStore?.state.libraryLists ?? const [],
        isItemInList: _isItemInLibraryList,
      ),
    );
    if (!mounted || result == null) return;
    if (result is TvLibraryList) {
      final selected = await _toggleItemInLibraryList(item, result);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              selected
                  ? 'Added to ${result.name}'
                  : 'Removed from ${result.name}',
            ),
          ),
        );
    } else if (result is String) {
      final list = await _createLibraryListForItem(item, result);
      if (!mounted || list == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Added to ${list.name}')));
    }
  }

  void _focusPageEntry() {
    if (!mounted) return;
    if (_selectedTab == 0) {
      void focusHero() {
        if (!mounted) return;
        final watchContext = _homeHeroWatchFocusNode.context;
        if (watchContext == null) {
          _pageEntryFocusNodes[0].requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_pageEntryFocusNodes[0].hasFocus) return;
            final firstRailContext = _pageEntryFocusNodes[0].context;
            if (firstRailContext == null || !firstRailContext.mounted) return;
            try {
              Scrollable.ensureVisible(
                firstRailContext,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: 0.36,
                alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              );
            } on FlutterError {
              // The first rail can be replaced during catalog hydration.
            }
          });
          return;
        }
        _rememberPageFocus(_homeHeroWatchFocusNode);
        _homeHeroWatchFocusNode.requestFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_homeHeroWatchFocusNode.hasFocus) return;
          final heroContext = _homeHeroKey.currentContext;
          if (heroContext == null || !heroContext.mounted) return;
          try {
            Scrollable.ensureVisible(
              heroContext,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: 0,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            );
          } on FlutterError {
            // The hero can be replaced during catalog hydration.
          }
        });
      }

      focusHero();
      WidgetsBinding.instance.addPostFrameCallback((_) => focusHero());
      for (final delay in const <int>[120, 280, 520, 900]) {
        Future<void>.delayed(
          Duration(milliseconds: delay),
          () {
            if (!mounted || !_primaryFocusNeedsRestore) return;
            focusHero();
          },
        );
      }
      return;
    }
    final index =
        _selectedTab.clamp(0, _pageEntryFocusNodes.length - 1).toInt();
    final node = _pageEntryFocusNodes[index];
    if (node.context != null) {
      node.requestFocus();
      return;
    }
    void retryFocus([int attempt = 0]) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (node.context != null) {
          node.requestFocus();
          return;
        }
        if (attempt >= 6) return;
        Future<void>.delayed(
          Duration(milliseconds: 70 + attempt * 35),
          () => retryFocus(attempt + 1),
        );
      });
    }

    retryFocus();
  }

  void _focusPageContent() {
    if (!mounted) return;
    final index =
        _selectedTab.clamp(0, _pageContentFocusNodes.length - 1).toInt();
    final node = _pageContentFocusNodes[index];
    if (node.context != null) {
      _rememberPageFocus(node);
      node.requestFocus();
      return;
    }
    void retryFocus([int attempt = 0]) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (node.context != null) {
          _rememberPageFocus(node);
          node.requestFocus();
          return;
        }
        if (attempt >= 6) return;
        Future<void>.delayed(
          Duration(milliseconds: 70 + attempt * 35),
          () => retryFocus(attempt + 1),
        );
      });
    }

    retryFocus();
  }

  void _rememberPageFocus(FocusNode node, {_TvItem? item}) {
    if (!mounted ||
        _selectedTab < 0 ||
        _selectedTab >= _lastPageFocusNodes.length) {
      return;
    }
    _lastPageFocusNodes[_selectedTab] = node;
    if (item != null) {
      _lastPageFocusItemKeys[_selectedTab] = _itemKey(item);
    }
  }

  void _rememberPageItemFocus(FocusNode node, _TvItem item) {
    _rememberPageFocus(node, item: item);
  }

  void _queueRememberedPageItemFocus() {
    if (!mounted ||
        _selectedTab < 0 ||
        _selectedTab >= _pendingPageFocusItemKeys.length) {
      return;
    }
    _queuePageItemFocus(_lastPageFocusItemKeys[_selectedTab]);
  }

  void _queuePageItemFocus(String? itemKey) {
    if (itemKey == null ||
        itemKey.trim().isEmpty ||
        _selectedTab < 0 ||
        _selectedTab >= _pendingPageFocusItemKeys.length) {
      return;
    }
    setState(() => _pendingPageFocusItemKeys[_selectedTab] = itemKey);
  }

  void _consumePageItemFocus(String itemKey) {
    if (!mounted ||
        _selectedTab < 0 ||
        _selectedTab >= _pendingPageFocusItemKeys.length) {
      return;
    }
    if (_pendingPageFocusItemKeys[_selectedTab] != itemKey) return;
    setState(() => _pendingPageFocusItemKeys[_selectedTab] = null);
  }

  bool _focusRememberedPageNode({double alignment = 0.38}) {
    if (!mounted ||
        _selectedTab < 0 ||
        _selectedTab >= _lastPageFocusNodes.length) {
      return false;
    }
    final node = _lastPageFocusNodes[_selectedTab];
    final context = node?.context;
    if (node == null ||
        context == null ||
        !context.mounted ||
        !node.canRequestFocus) {
      _lastPageFocusNodes[_selectedTab] = null;
      _queueRememberedPageItemFocus();
      return false;
    }
    node.requestFocus();
    try {
      final alignmentPolicy = _selectedTab == 0
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.explicit;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: alignment,
        alignmentPolicy: alignmentPolicy,
      );
    } on FlutterError {
      _lastPageFocusNodes[_selectedTab] = null;
      _queueRememberedPageItemFocus();
      return false;
    }
    return true;
  }

  void _enterSelectedTabContent() {
    if (_selectedTab != 0) {
      _focusSelectedTabFirstItem();
      return;
    }
    if (_lastPageFocusNodes[0] == _homeHeroWatchFocusNode) {
      _restoreHomeHero();
      return;
    }
    if (_focusRememberedPageNode()) return;
    _focusSelectedTabFirstItem();
  }

  void _focusSelectedTabFirstItem() {
    if (_selectedTab == 0) {
      _focusPageEntry();
      return;
    }
    if (_selectedTab == 1 || _selectedTab == 2 || _selectedTab == 3) {
      if (_selectedTab == 3) {
        _focusPageEntry();
        return;
      }
      _focusPageContent();
      return;
    }
    _focusPageContent();
  }

  List<_PlaybackSession> _orderedPlaybackSessions(
    List<_PlaybackSession> sessions,
  ) {
    final ordered = [
      for (final session in sessions)
        if (_tvSettings.p2pPlaybackEnabled || !_isP2pPlaybackSession(session))
          session,
    ];
    int rank(_PlaybackSession session) {
      final type = session.sourceType.toLowerCase();
      final p2p = _isP2pPlaybackSession(session);
      if (p2p && !_tvSettings.p2pSourcePrioritiesEnabled) return 20;
      if (p2p) return 10 + _p2pPlaybackSessionRank(session);
      final adaptive = type.contains('hls') ||
          type.contains('m3u8') ||
          type.contains('dash') ||
          type.contains('mpd');
      final direct = type.contains('mp4') || type.contains('video');
      return switch (_tvSettings.preferredQuality) {
        'Best available' => adaptive
            ? 0
            : direct
                ? 1
                : 2,
        'Data saver' => direct
            ? 0
            : adaptive
                ? 1
                : 2,
        _ => adaptive
            ? 0
            : direct
                ? 1
                : 2,
      };
    }

    ordered.sort((left, right) => rank(left).compareTo(rank(right)));
    if (!_tvSettings.p2pPlaybackEnabled ||
        !_tvSettings.p2pSourcePrioritiesEnabled) {
      return ordered;
    }
    final p2pQualityCounts = <String, int>{};
    return [
      for (final session in ordered)
        if (!_isP2pPlaybackSession(session) ||
            (p2pQualityCounts.update(
                  _playbackQualityBucket(session.sourceType.toLowerCase()),
                  (count) => count + 1,
                  ifAbsent: () => 1,
                ) <=
                _tvSettings.p2pResultsPerQuality))
          session,
    ];
  }

  bool _isP2pPlaybackSession(_PlaybackSession session) {
    final type = session.sourceType.toLowerCase();
    final url = session.mediaUrl.toLowerCase();
    return type.contains('p2p') ||
        type.contains('torrent') ||
        type.contains('magnet') ||
        url.startsWith('magnet:') ||
        url.contains('btih:');
  }

  int _p2pPlaybackSessionRank(_PlaybackSession session) {
    final type = session.sourceType.toLowerCase();
    final risky = _tvSettings.p2pAvoidRiskyFormats &&
        (type.contains('cam') ||
            type.contains('ts') ||
            type.contains('telecine') ||
            type.contains('telesync') ||
            type.contains('scr'));
    final riskyPenalty = risky ? 8 : 0;
    final qualityRank = _playbackQualityRank(type);
    return switch (_tvSettings.p2pPriorityMode) {
      kTvP2pPriorityQualityFirst => qualityRank + riskyPenalty,
      kTvP2pPriorityAvailabilityFirst => riskyPenalty,
      kTvP2pPrioritySmallerFasterFiles =>
        _playbackSizeRank(type) + riskyPenalty,
      kTvP2pPriorityBalanced =>
        ((qualityRank + _playbackSizeRank(type)) ~/ 2) + riskyPenalty,
      _ => riskyPenalty + math.min(qualityRank, _playbackSizeRank(type)),
    };
  }

  int _playbackQualityRank(String type) {
    if (type.contains('2160') || type.contains('4k') || type.contains('uhd')) {
      return 0;
    }
    if (type.contains('1080')) return 1;
    if (type.contains('720')) return 2;
    if (type.contains('480')) return 3;
    return 4;
  }

  String _playbackQualityBucket(String type) {
    if (type.contains('2160') || type.contains('4k') || type.contains('uhd')) {
      return '2160';
    }
    if (type.contains('1080')) return '1080';
    if (type.contains('720')) return '720';
    if (type.contains('480')) return '480';
    return 'auto';
  }

  int _playbackSizeRank(String type) {
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*(gb|mb)').firstMatch(type);
    if (match == null) return 2;
    final amount = double.tryParse(match.group(1) ?? '') ?? 0;
    final unit = match.group(2) ?? 'mb';
    final sizeMb = unit == 'gb' ? amount * 1024 : amount;
    final limit = _tvSettings.p2pSizeLimitMb;
    if (limit > 0 && sizeMb > limit) return 10;
    if (sizeMb <= 1400) return 0;
    if (sizeMb <= 4096) return 1;
    if (sizeMb <= 8192) return 2;
    return 3;
  }

  String _playbackProgressKey(_TvItem item, int season, int episode) {
    return '${item.type}:${item.id}:$season:$episode';
  }

  String _verifiedPlaybackSessionKey(_TvItem item, int season, int episode) {
    final type = _normalizeType(item.type);
    final id = item.id.trim().isNotEmpty
        ? item.id.trim()
        : (item.tmdbId?.toString() ?? item.title.trim());
    if (type == 'live') return 'live:$id';
    return '$type:$id:$season:$episode';
  }

  bool _verifiedPlaybackSessionUsable(_TvVerifiedPlaybackSession entry) {
    if (entry.session.mediaUrl.trim().isEmpty) return false;
    if (entry.session.mediaUrl.startsWith('http://127.0.0.1') ||
        entry.session.mediaUrl.startsWith('http://localhost')) {
      return false;
    }
    if (DateTime.now().difference(entry.cachedAt) > const Duration(hours: 6)) {
      return false;
    }
    if (entry.confidence < 8) return false;
    if (_isP2pPlaybackSession(entry.session) && !_tvSettings.p2pPlaybackEnabled) {
      return false;
    }
    return true;
  }

  List<_TvVerifiedPlaybackSession> _rankVerifiedSessions(
    Iterable<_TvVerifiedPlaybackSession> entries,
  ) {
    final ranked = entries.where(_verifiedPlaybackSessionUsable).toList()
      ..sort((left, right) {
        final confidence = right.confidence.compareTo(left.confidence);
        if (confidence != 0) return confidence;
        final success = right.successCount.compareTo(left.successCount);
        if (success != 0) return success;
        return right.cachedAt.compareTo(left.cachedAt);
      });
    return ranked.take(3).toList(growable: false);
  }

  List<_PlaybackSession> _verifiedPlaybackSessionsFor(String key) {
    final entries = _rankVerifiedSessions(
      _verifiedPlaybackSessions[key] ?? const <_TvVerifiedPlaybackSession>[],
    );
    return entries.map((entry) => entry.session).toList(growable: false);
  }

  void _rememberVerifiedPlaybackSession(
    String key,
    _PlaybackSession session,
    String engineId,
  ) {
    if (key.trim().isEmpty ||
        session.mediaUrl.trim().isEmpty ||
        session.mediaUrl.startsWith('http://127.0.0.1') ||
        session.mediaUrl.startsWith('http://localhost')) {
      return;
    }
    final current = List<_TvVerifiedPlaybackSession>.from(
      _verifiedPlaybackSessions[key] ?? const <_TvVerifiedPlaybackSession>[],
    );
    final index = current.indexWhere(
      (entry) => entry.session.mediaUrl == session.mediaUrl,
    );
    if (index >= 0) {
      final previous = current[index];
      current[index] = previous.copyWith(
        session: session,
        engineId: engineId,
        cachedAt: DateTime.now(),
        confidence: (previous.confidence + 10).clamp(0, 100),
        successCount: previous.successCount + 1,
        failureCount: previous.failureCount,
      );
    } else {
      current.add(
        _TvVerifiedPlaybackSession(
          session: session,
          engineId: engineId,
          cachedAt: DateTime.now(),
          confidence: 12,
        ),
      );
    }
    setState(() {
      _verifiedPlaybackSessions[key] = _rankVerifiedSessions(current);
    });
    unawaited(_persistVerifiedPlaybackSessions());
    debugPrint('Juicr TV verified playback cache stored key=[redacted]');
  }

  void _forgetVerifiedPlaybackSessions(String key) {
    if (!_verifiedPlaybackSessions.containsKey(key)) return;
    setState(() => _verifiedPlaybackSessions.remove(key));
    unawaited(_persistVerifiedPlaybackSessions());
    debugPrint('Juicr TV verified playback cache cleared key=[redacted]');
  }

  void _forgetRejectedVerifiedPlaybackSession(
    String key,
    _PlaybackSession session,
  ) {
    final current =
        _verifiedPlaybackSessions[key] ?? const <_TvVerifiedPlaybackSession>[];
    final rejectedUrl = session.mediaUrl.trim();
    if (current.isEmpty || rejectedUrl.isEmpty) return;
    final filtered = current
        .where((entry) => entry.session.mediaUrl.trim() != rejectedUrl)
        .toList(growable: false);
    if (filtered.length == current.length) return;
    setState(() {
      if (filtered.isEmpty) {
        _verifiedPlaybackSessions.remove(key);
      } else {
        _verifiedPlaybackSessions[key] = filtered;
      }
    });
    unawaited(_persistVerifiedPlaybackSessions());
    debugPrint('Juicr TV verified playback cache rejected key=[redacted]');
  }

  bool _shouldOfferResume(_TvPlaybackProgress progress) {
    if (!_tvSettings.resumePrompt) return false;
    if (progress.position <= Duration.zero) return false;
    if (progress.duration <= Duration.zero) return true;
    return progress.duration - progress.position > const Duration(minutes: 2);
  }

  _TvPlaybackProgress? _resumeProgressFor(
    _TvItem item,
    int season,
    int episode,
  ) {
    final progress = _watchedProgressForPlayback(item, season, episode);
    if (progress == null || !_shouldOfferResume(progress)) return null;
    return progress;
  }

  _TvPlaybackProgress? _watchedProgressForPlayback(
    _TvItem item,
    int season,
    int episode,
  ) {
    final exactKey = _playbackProgressKey(item, season, episode);
    final itemKey = _itemKey(item);
    final legacyItemKey = item.id.trim();
    final candidates = <String>[
      exactKey,
      if (legacyItemKey.isNotEmpty) '$legacyItemKey:$season:$episode',
      if (season == 1 && episode == 1) itemKey,
      if (season == 1 && episode == 1 && legacyItemKey.isNotEmpty)
        legacyItemKey,
    ];
    _TvPlaybackProgress? best;
    for (final key in candidates) {
      final progress = _watchedProgress[key];
      if (progress == null) continue;
      if (best == null ||
          progress.position > best.position ||
          (progress.position == best.position &&
              progress.duration > best.duration)) {
        best = progress;
      }
    }
    return best;
  }

  ({int season, int episode, _TvPlaybackProgress progress})?
      _latestWatchedProgressForItem(_TvItem item) {
    final itemKey = _itemKey(item);
    final legacyItemKey = item.id.trim();
    ({int season, int episode})? parseKey(String key) {
      if (key == itemKey ||
          (legacyItemKey.isNotEmpty && key == legacyItemKey)) {
        return (season: 1, episode: 1);
      }
      final prefixes = <String>[
        '$itemKey:',
        if (legacyItemKey.isNotEmpty) '$legacyItemKey:',
      ];
      for (final prefix in prefixes) {
        if (!key.startsWith(prefix)) continue;
        final parts = key.substring(prefix.length).split(':');
        if (parts.length != 2) continue;
        final season = int.tryParse(parts[0]);
        final episode = int.tryParse(parts[1]);
        if (season == null || episode == null) continue;
        if (season <= 0 || episode <= 0) continue;
        return (season: season, episode: episode);
      }
      return null;
    }

    ({int season, int episode, _TvPlaybackProgress progress})? best;
    for (final entry in _watchedProgress.entries) {
      final parsed = parseKey(entry.key);
      if (parsed == null) continue;
      final progress = entry.value;
      if (progress.position <= Duration.zero) continue;
      if (!_shouldOfferResume(progress)) continue;
      if (best == null ||
          parsed.season > best.season ||
          (parsed.season == best.season && parsed.episode > best.episode) ||
          (parsed.season == best.season &&
              parsed.episode == best.episode &&
              progress.position > best.progress.position)) {
        best = (
          season: parsed.season,
          episode: parsed.episode,
          progress: progress,
        );
      }
    }
    return best;
  }

  ({int season, int episode, _TvPlaybackProgress? progress})
      _resolvePlaybackTarget(_TvItem item, int season, int episode) {
    final exactProgress = _resumeProgressFor(item, season, episode);
    if (exactProgress != null || season != 1 || episode != 1) {
      return (season: season, episode: episode, progress: exactProgress);
    }
    final latestProgress = _latestWatchedProgressForItem(item);
    if (latestProgress != null) {
      return (
        season: latestProgress.season,
        episode: latestProgress.episode,
        progress: latestProgress.progress,
      );
    }
    return (season: season, episode: episode, progress: null);
  }

  Future<void> _play(
    _TvItem item, {
    int season = 1,
    int episode = 1,
    bool returnToDetailsOnClose = true,
  }) async {
    if (!_tvSettings.hasPlaybackSource) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Enable playback in Settings before starting titles.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      return;
    }
    final target = _resolvePlaybackTarget(item, season, episode);
    final targetSeason = target.season;
    final targetEpisode = target.episode;
    final playbackKey = _playbackProgressKey(item, targetSeason, targetEpisode);
    final verifiedCacheKey =
        _verifiedPlaybackSessionKey(item, targetSeason, targetEpisode);
    if (_preparingPlaybackKey != null) return;
    if (!mounted) return;
    final requestGeneration = ++_playRequestGeneration;
    setState(() => _preparingPlaybackKey = playbackKey);
    debugPrint(
      'Juicr TV playback requested hasSource=${_tvSettings.hasPlaybackSource}',
    );
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press Back to cancel while Juicr prepares playback.'),
          duration: Duration(seconds: 4),
        ),
      );
    try {
      final resumeProgress = target.progress;
      if (!mounted) return;
      final cachedSessions = _verifiedPlaybackSessionsFor(verifiedCacheKey);
      final usedVerifiedPlaybackCache = cachedSessions.isNotEmpty;
      if (usedVerifiedPlaybackCache) {
        debugPrint(
          'Juicr TV playback using verified source cache '
          'key=[redacted] count=${cachedSessions.length}',
        );
      }
      Future<List<_PlaybackSession>> fetchFreshPlaybackSessions(
        String reason,
      ) async {
        try {
          final sessions = await _api
              .playbackSessions(
                item,
                season: targetSeason,
                episode: targetEpisode,
              )
              .timeout(const Duration(seconds: 45));
          final ordered = _orderedPlaybackSessions(sessions);
          debugPrint(
            'Juicr TV fresh playback $reason ready '
            'count=${ordered.length}',
          );
          return ordered;
        } catch (error) {
          debugPrint(
            'Juicr TV fresh playback $reason failed '
            'errorType=${error.runtimeType}',
          );
          return const <_PlaybackSession>[];
        }
      }

      Future<List<_PlaybackSession>>? freshFallbackFuture;
      List<_PlaybackSession> freshSessions = const <_PlaybackSession>[];
      if (usedVerifiedPlaybackCache) {
        debugPrint(
          'Juicr TV fresh playback source refresh warming '
          'while using verified cache',
        );
        freshFallbackFuture = fetchFreshPlaybackSessions('source refresh');
      } else {
        freshSessions = await fetchFreshPlaybackSessions('initial lookup');
      }
      final sessions = usedVerifiedPlaybackCache
          ? _orderedPlaybackSessions(cachedSessions)
          : _orderedPlaybackSessions(freshSessions);
      if (!mounted || requestGeneration != _playRequestGeneration) return;
      final seededSubtitles = _subtitlesFromPlaybackSessions(sessions);
      debugPrint(
        'Juicr TV subtitle seed count=${seededSubtitles.length} '
        'sessions=${sessions.length}',
      );
      final previousFocus = FocusManager.instance.primaryFocus;
      final result = await Navigator.of(context).push<Object?>(
        MaterialPageRoute<Object?>(
          builder: (_) => _TvPlaybackPage(
            item: item,
            sessions: sessions,
            initialSessionIndex: 0,
            initialSeason: targetSeason,
            initialEpisode: targetEpisode,
            initialResumePosition: Duration.zero,
            initialResumeProgress: resumeProgress,
            settings: _tvSettings,
            subtitles: seededSubtitles,
            initialSubtitleIndex: -1,
            resolveSubtitles: () => _subtitlesForPlayback(
              item,
              season: targetSeason,
              episode: targetEpisode,
            ),
            resolveFreshSessions: usedVerifiedPlaybackCache
                ? () async {
                    debugPrint(
                      'Juicr TV fresh playback fallback requested '
                      'cacheKey=[redacted]',
                    );
                    final warmed =
                        await (freshFallbackFuture ??
                            Future<List<_PlaybackSession>>.value(
                              const <_PlaybackSession>[],
                            ));
                    if (warmed.isNotEmpty) return warmed;
                    debugPrint(
                      'Juicr TV fresh playback retry requested '
                      'after cache rejection',
                    );
                    return fetchFreshPlaybackSessions(
                      'retry after cache rejection',
                    );
                  }
                : null,
            onProgress: (season, episode, progress) {
              final progressKey = _playbackProgressKey(item, season, episode);
              _savePlaybackProgressForItem(
                item,
                progressKey,
                progress,
                markHistory: true,
              );
            },
            onVerifiedSession: (session, engineId) {
              _rememberVerifiedPlaybackSession(
                verifiedCacheKey,
                session,
                engineId,
              );
            },
            onRejectedSession: (session) {
              _forgetRejectedVerifiedPlaybackSession(
                verifiedCacheKey,
                session,
              );
            },
          ),
        ),
      );
      if (!mounted || requestGeneration != _playRequestGeneration) return;
      if (!returnToDetailsOnClose) {
        _restoreTvFocusAfterRoutePop(previousFocus);
      }
      if (result is _TvPlaybackUnavailable) {
        if (usedVerifiedPlaybackCache) {
          _forgetVerifiedPlaybackSessions(verifiedCacheKey);
        }
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(result.message),
              duration: const Duration(seconds: 3),
            ),
          );
        if (returnToDetailsOnClose) {
          if (mounted && _preparingPlaybackKey == playbackKey) {
            setState(() => _preparingPlaybackKey = null);
          }
          await _openItem(item);
        }
        return;
      }
      final progress = result is _TvPlaybackProgress ? result : null;
      if (progress != null) {
        _savePlaybackProgressForItem(item, playbackKey, progress);
      }
      if (_tvSettings.keepHistory) _rememberItem(item);
      if (returnToDetailsOnClose) {
        if (mounted && _preparingPlaybackKey == playbackKey) {
          setState(() => _preparingPlaybackKey = null);
        }
        await _openItem(item);
      }
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_friendlyPlaybackError(error)),
            duration: const Duration(seconds: 3),
          ),
        );
      if (returnToDetailsOnClose) {
        if (mounted && _preparingPlaybackKey == playbackKey) {
          setState(() => _preparingPlaybackKey = null);
        }
        await _openItem(item);
      }
    } finally {
      if (mounted && _preparingPlaybackKey == playbackKey) {
        setState(() => _preparingPlaybackKey = null);
      }
    }
  }

  void _savePlaybackProgressForItem(
    _TvItem item,
    String playbackKey,
    _TvPlaybackProgress progress, {
    bool markHistory = false,
  }) {
    if (progress.position <= Duration.zero) return;
    final normalizedProgress = progress.duration > Duration.zero
        ? progress
        : _TvPlaybackProgress(
            position: progress.position,
            duration: Duration.zero,
          );
    _watchedProgress[playbackKey] = normalizedProgress;
    unawaited(
      _libraryStore?.updateProgress(
            key: playbackKey,
            positionMillis: normalizedProgress.position.inMilliseconds,
            durationMillis: normalizedProgress.duration > Duration.zero
                ? normalizedProgress.duration.inMilliseconds
                : null,
          ) ??
          Future<void>.value(),
    );
    if (_isPlaybackComplete(normalizedProgress)) {
      unawaited(
        _libraryStore?.markCompleted(playbackKey) ?? Future<void>.value(),
      );
    }
    _rememberContinueItem(item);
    if (markHistory && _tvSettings.keepHistory) _rememberItem(item);
    _scheduleAccountLibraryPush();
    if (mounted) setState(() {});
  }

  bool _isPlaybackComplete(_TvPlaybackProgress progress) {
    if (progress.duration <= Duration.zero) return false;
    final remaining = progress.duration - progress.position;
    return progress.position >= const Duration(minutes: 3) &&
        (progress.position.inMilliseconds / progress.duration.inMilliseconds) >=
            0.92 &&
        remaining <= const Duration(minutes: 5);
  }

  Future<List<_TvSubtitle>> _subtitlesForPlayback(
    _TvItem item, {
    required int season,
    required int episode,
  }) async {
    final canUseHostedSubtitles = _tvSettings.hasBuiltInSubtitleSource;
    final canUseAddOnSubtitles = _tvSettings.hasAddOnSubtitleSource;
    if (!canUseHostedSubtitles && !canUseAddOnSubtitles) {
      debugPrint(
        'Juicr TV subtitle lookup skipped gate=source '
        'enabled=${_tvSettings.subtitles}',
      );
      return const <_TvSubtitle>[];
    }
    try {
      var lookupItem = item;
      final needsSubtitleIdentityHydration =
          _tvImdbIdForHostedLookup(lookupItem) == null ||
              lookupItem.tmdbId == null;
      if (needsSubtitleIdentityHydration) {
        lookupItem = await _api
            .meta(lookupItem)
            .timeout(const Duration(seconds: 6))
            .catchError((_) => lookupItem);
      }
      final addOnSubtitles = canUseAddOnSubtitles
          ? await _api
              .addOnSubtitles(
                _tvSettings.userAddOns,
                lookupItem,
                season: season,
                episode: episode,
              )
              .timeout(const Duration(seconds: 14))
              .catchError((error) {
              debugPrint(
                'Juicr TV add-on subtitle lookup failed '
                'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
              );
              return const <_TvSubtitle>[];
            })
          : const <_TvSubtitle>[];
      debugPrint(
        'Juicr TV add-on subtitle lookup count=${addOnSubtitles.length}',
      );
      final hostedSubtitles = canUseHostedSubtitles
          ? await _api
              .subtitles(lookupItem, season: season, episode: episode)
              .timeout(const Duration(seconds: 10))
              .catchError((error) {
              debugPrint(
                'Juicr TV hosted subtitle lookup failed '
                'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
              );
              return const <_TvSubtitle>[];
            })
          : const <_TvSubtitle>[];
      debugPrint(
        'Juicr TV hosted subtitle lookup count=${hostedSubtitles.length}',
      );
      return _mergeTvSubtitles(addOnSubtitles, hostedSubtitles);
    } catch (error) {
      debugPrint(
        'Juicr TV subtitle lookup skipped '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return const <_TvSubtitle>[];
    }
  }

  List<_TvSubtitle> _mergeTvSubtitles(
    List<_TvSubtitle> first,
    List<_TvSubtitle> second,
  ) {
    final seen = <String>{};
    final merged = <_TvSubtitle>[];
    for (final subtitle in [...first, ...second]) {
      final key = subtitle.id.trim().isNotEmpty
          ? subtitle.id.trim()
          : '${subtitle.url}|${subtitle.language}|${subtitle.label}';
      if (subtitle.url.isEmpty || !seen.add(key)) continue;
      merged.add(subtitle);
    }
    return merged.toList(growable: false);
  }

  List<_TvSubtitle> _subtitlesFromPlaybackSessions(
    List<_PlaybackSession> sessions,
  ) {
    final seen = <String>{};
    final subtitles = <_TvSubtitle>[];
    for (final session in sessions) {
      for (final subtitle in session.subtitles) {
        final key = subtitle.id.trim().isNotEmpty
            ? subtitle.id.trim()
            : '${subtitle.url}|${subtitle.language}|${subtitle.label}';
        if (subtitle.url.isEmpty || !seen.add(key)) continue;
        subtitles.add(subtitle);
      }
    }
    return subtitles.toList(growable: false);
  }

  Future<void> _playTrailer(_TvItem item) async {
    if (!_tvSettings.builtInTrailers) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Enable trailers in Settings before opening trailer choices.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Preparing trailer...'),
          duration: Duration(seconds: 1),
        ),
      );
    try {
      final trailers =
          await _api.trailers(item).timeout(const Duration(seconds: 18));
      _TvTrailer? trailer;
      for (final candidate in trailers) {
        if (candidate.isTvPlayable || candidate.isExternalLaunchable) {
          trailer = candidate;
          break;
        }
      }
      if (trailer == null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('No TV trailer is available for this title yet.'),
            ),
          );
        return;
      }
      if (trailer.isExternalLaunchable) {
        final opened = await _openTvExternalTrailer(trailer);
        if (!mounted) return;
        if (!opened) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('No TV app can open this trailer yet.'),
              ),
            );
        }
        return;
      }
      final session = _PlaybackSession(
        mediaUrl: trailer.url,
        sourceType: trailer.sourceType,
        httpHeaders: _TvApi.juicrMediaHeaders,
      );
      if (!mounted) return;
      final trailerItem = _TvItem(
        id: '${item.id}:trailer',
        type: item.type,
        title: '${item.title} trailer',
        color: item.color,
        poster: item.poster,
        background: item.background,
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _TvPlaybackPage(
            item: trailerItem,
            sessions: [session],
            initialSessionIndex: 0,
            initialSeason: 1,
            initialEpisode: 1,
            initialResumePosition: Duration.zero,
            settings: _tvSettings,
            subtitles: const <_TvSubtitle>[],
            initialSubtitleIndex: -1,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('This trailer is not ready for TV playback yet.'),
          ),
        );
    }
  }

  KeyEventResult _traceUnhandledTvKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final key = event.logicalKey;
      final isNavigationKey = key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.gameButtonA;
      if (_selectedItem == null &&
          !_searchOpen &&
          isNavigationKey &&
          _primaryFocusNeedsRestore) {
        _enterSelectedTabContent();
        return KeyEventResult.handled;
      }
      debugPrint(
        'Juicr TV key trace '
        'logical=${event.logicalKey.keyLabel}|${event.logicalKey.debugName} '
        'physical=${event.physicalKey.debugName}',
      );
    }
    return KeyEventResult.ignored;
  }

  Object? _handleRootActivate() {
    final navigationState = _navigationRailKey.currentState;
    final navFocusIndex = navigationState?.focusedIndex;
    if (navigationState?.hasFocus == true && navFocusIndex != null) {
      _selectNavigationItem(navFocusIndex);
      return null;
    }
    if (_selectedTab == 0 &&
        _homeHeroWatchFocusNode.hasFocus &&
        _homeHeroItems.isNotEmpty) {
      _play(_homeHeroItems.first);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    _applyTvSettingsGlobals(_tvSettings);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        _handleBackPressed();
      },
      child: Scaffold(
        backgroundColor: _tvTheme.background,
        body: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(_tvTextScale)),
          child: TickerMode(
            enabled: _tvMotionEnabled,
            child: Shortcuts(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter):
                    ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.gameButtonA):
                    ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
                SingleActivator(LogicalKeyboardKey.arrowLeft):
                    DirectionalFocusIntent(TraversalDirection.left),
                SingleActivator(LogicalKeyboardKey.arrowRight):
                    DirectionalFocusIntent(TraversalDirection.right),
                SingleActivator(LogicalKeyboardKey.arrowUp):
                    DirectionalFocusIntent(TraversalDirection.up),
                SingleActivator(LogicalKeyboardKey.arrowDown):
                    DirectionalFocusIntent(TraversalDirection.down),
              },
              child: Actions(
                actions: {
                  DismissIntent: CallbackAction<DismissIntent>(
                    onInvoke: (_) {
                      _handleBackPressed();
                      return null;
                    },
                  ),
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) => _handleRootActivate(),
                  ),
                },
                child: FocusTraversalGroup(
                  policy: ReadingOrderTraversalPolicy(),
                  child: Stack(
                    children: [
                      _TvBackdrop(settings: _tvSettings),
                      Focus(
                        descendantsAreFocusable:
                            _selectedItem == null && !_searchOpen,
                        descendantsAreTraversable:
                            _selectedItem == null && !_searchOpen,
                        onKeyEvent: (_, event) => _traceUnhandledTvKey(event),
                        child: Row(
                          children: [
                            _TvNavigationRail(
                              key: _navigationRailKey,
                              items: _navItems,
                              selectedIndex: _navIndexForTab(_selectedTab),
                              onSelected: _selectNavigationItem,
                              onMoveRight: _moveRightFromNavigation,
                            ),
                            Expanded(
                              child: _TvMainSurface(
                                title: _tabItems[_selectedTab].label,
                                selectedTab: _selectedTab,
                                loading: _loading,
                                error: _error,
                                expandedRail: _expandedRail,
                                rails: _rails,
                                homeHeroItems: _homeHeroItems,
                                homeHeroIndex: _homeHeroIndex,
                                homeHeroCarouselPaused:
                                    _homeHeroCarouselPauseDepth > 0,
                                homeHeroEditorial: _homeHeroEditorial,
                                homeHeroKey: _homeHeroKey,
                                homeHeroWatchFocusNode: _homeHeroWatchFocusNode,
                                allItems: _items,
                                movies: _movies,
                                series: _series,
                                animation: _animation,
                                liveTv: _liveTv,
                                discoveryLaneItems: _discoveryLaneItems,
                                recentItems: _continueItems,
                                likedItems: _likedItems,
                                libraryLists:
                                    _libraryStore?.state.libraryLists ??
                                        const [],
                                discoveryKind: _discoveryKind,
                                discoverySort: _discoverySort,
                                discoveryGenre: _discoveryGenre,
                                discoveryLoading: _discoveryLaneLoading
                                        .contains(
                                      _tvDiscoveryLaneKey(
                                        _discoveryKind,
                                        _discoverySort,
                                        genre: _discoveryGenre,
                                      ),
                                    ) ||
                                    (_tvSettings.hasCatalogSource &&
                                        !_discoveryLaneItems.containsKey(
                                          _tvDiscoveryLaneKey(
                                            _discoveryKind,
                                            _discoverySort,
                                            genre: _discoveryGenre,
                                          ),
                                        ) &&
                                        !_discoveryLaneExhausted.contains(
                                          _tvDiscoveryLaneKey(
                                            _discoveryKind,
                                            _discoverySort,
                                            genre: _discoveryGenre,
                                          ),
                                        )),
                                discoveryExhausted:
                                    _discoveryLaneExhausted.contains(
                                  _tvDiscoveryLaneKey(
                                    _discoveryKind,
                                    _discoverySort,
                                    genre: _discoveryGenre,
                                  ),
                                ),
                                libraryFilter: _libraryFilter,
                                accountSignedIn: _accountSignedIn,
                                accountToken: _accountSession?.token ?? '',
                                accountLabel: _accountLabel,
                                accountSyncLabel: _accountSyncLabel,
                                recentCount: _recentLibraryCount,
                                savedCount: _savedLibraryCount,
                                completedCount: _completedLibraryCount,
                                activeWatchLabel: _activeWatchLabel,
                                activeWatchSeconds: _activeWatchSeconds,
                                tvSettings: _tvSettings,
                                onTvSettingsChanged: _updateTvSettings,
                                onLeaderboardScopeChanged: (scope) =>
                                    _updateTvSettings(
                                  _tvSettings.copyWith(
                                    leaderboardScope: scope,
                                  ),
                                ),
                                onAccountSignIn: () =>
                                    unawaited(_openAccountLibrary()),
                                onAccountSignOut: () =>
                                    unawaited(_signOutAccount()),
                                onAccountSync: () =>
                                    unawaited(_syncAccountNow()),
                                onDiscoveryMenu: _openDiscoveryMenu,
                                onDiscoveryLoadMore: () =>
                                    unawaited(_loadMoreDiscoveryLane()),
                                onLibraryMenu: _openLibraryMenu,
                                onOpenItemLibraryMenu: (item) =>
                                    unawaited(_openItemLibraryMenu(item)),
                                onOpenLibraryRanking: () => setState(
                                  () =>
                                      _libraryFilter = _TvLibraryFilter.ranking,
                                ),
                                onOpenLibraryMetrics: () => setState(
                                  () =>
                                      _libraryFilter = _TvLibraryFilter.metrics,
                                ),
                                onOpenItem: _openItem,
                                onHomeHeroIndexChanged: (index) {
                                  if (_homeHeroIndex == index) return;
                                  setState(() => _homeHeroIndex = index);
                                },
                                onPlayItem: (item) => _play(item),
                                onTrailerItem: (item) =>
                                    unawaited(_playTrailer(item)),
                                onOpenRail: (rail) {
                                  setState(() => _expandedRail = rail);
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (!mounted) return;
                                    _focusPageEntry();
                                  });
                                },
                                onBackToHome: () =>
                                    setState(() => _expandedRail = null),
                                onFocusNavigation: () => _navigationRailKey
                                    .currentState
                                    ?.focusSelected(),
                                pageEntryFocusNode:
                                    _pageEntryFocusNodes[_selectedTab],
                                pageContentFocusNode:
                                    _pageContentFocusNodes[_selectedTab],
                                onFocusPageEntry: _focusPageEntry,
                                onFocusPageContent: _focusPageContent,
                                onRememberPageFocus: _rememberPageFocus,
                                onRememberPageItemFocus: _rememberPageItemFocus,
                                onRestorePageItemFocus: _consumePageItemFocus,
                                onRetry: () => _loadCatalog(force: true),
                                restoreItemKey:
                                    _pendingPageFocusItemKeys[_selectedTab],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_selectedItem != null)
                        _TvDetailsOverlay(
                          item: _selectedItem!,
                          onClose: _closeOverlay,
                          preparing: _preparingPlaybackKey?.startsWith(
                                '${_selectedItem!.type}:${_selectedItem!.id}:',
                              ) ==
                              true,
                          liked: _isItemLiked(_selectedItem!),
                          settings: _tvSettings,
                          onPlay: () => _play(_selectedItem!),
                          onPlayEpisode: (season, episode) => _play(
                            _selectedItem!,
                            season: season,
                            episode: episode,
                          ),
                          onToggleLike: () => _toggleLike(_selectedItem!),
                        ),
                      if (_searchOpen)
                        _TvSearchOverlay(
                          key: _searchOverlayKey,
                          api: _api,
                          items: _items,
                          onClose: () => _closeOverlay(focusNavigation: true),
                          onOpenItem: _openItem,
                        ),
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
}
