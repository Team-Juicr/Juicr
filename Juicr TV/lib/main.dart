import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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
part 'tv_data.dart';

const _apiBase = 'https://api.juicr.app';
const _tvSettingsPrefsKey = 'juicr_tv_settings_v1';
const _juicrGreen = Color(0xFF20D66B);
const double _tvSpacing = 12;
Color _tvAccentColor = _juicrGreen;
double _tvTextScale = 1.0;
bool _tvMotionEnabled = true;

Color get _tvFocusBorder => _tvAccentColor;

Color _accentForSetting(String accent) {
  return switch (accent) {
    'Ocean' => const Color(0xFF24C8DB),
    'Sunset' => const Color(0xFFFFA64D),
    'Mono' => const Color(0xFFE8E4F5),
    _ => _juicrGreen,
  };
}

double _textScaleForSetting(String size) {
  return switch (size) {
    'Smaller' => 0.88,
    'Small' => 0.94,
    'Larger' => 1.08,
    'Maximum' => 1.16,
    _ => 1.0,
  };
}

Duration _tvDuration(int milliseconds) {
  return _tvMotionEnabled
      ? Duration(milliseconds: milliseconds)
      : Duration.zero;
}

enum _TvLibraryFilter {
  continueWatching('Continue', 'Recently opened titles', Icons.history_rounded),
  movies('Movies', 'Liked movies', Icons.movie_rounded),
  series('Series', 'Liked series', Icons.tv_rounded),
  animation('Animation', 'Liked animation', Icons.auto_awesome_rounded),
  liveTv('Live TV', 'Liked live channels', Icons.live_tv_rounded);

  const _TvLibraryFilter(this.label, this.subtitle, this.icon);

  final String label;
  final String subtitle;
  final IconData icon;
}

enum _TvAccountSyncState { guest, idle, syncing, synced, needsAttention }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const JuicrTvApp());
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
        scaffoldBackgroundColor: const Color(0xFF07080D),
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
          insetPadding: const EdgeInsets.only(bottom: 34),
        ),
        useMaterial3: true,
      ),
      home: const TvHomePage(),
    );
  }
}

class _ScoredTvItem {
  const _ScoredTvItem(this.item, this.score);

  final _TvItem item;
  final double score;
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
  });

  final _TvDiscoveryKind kind;
  final _TvDiscoverySort sort;
  final String type;
  final String catalogSort;
}

class TvHomePage extends StatefulWidget {
  const TvHomePage({super.key});

  @override
  State<TvHomePage> createState() => _TvHomePageState();
}

class _TvHomePageState extends State<TvHomePage> {
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
  final _api = _TvApi();
  final _items = <_TvItem>[];
  final _movies = <_TvItem>[];
  final _series = <_TvItem>[];
  final _animation = <_TvItem>[];
  final _liveTv = <_TvItem>[];
  final _discoveryLaneItems = <String, List<_TvItem>>{};
  final _upcomingPicks = <_TvItem>[];
  List<_TvItem> _heroEditorialItems = const <_TvItem>[];
  List<_TvItem> _topSignalRemoteItems = const <_TvItem>[];
  List<_TvItem> _todaySignalRemoteItems = const <_TvItem>[];
  List<_TvItem> _juicrTopSignalRemoteItems = const <_TvItem>[];
  final _recentItems = <_TvItem>[];
  final _likedItemKeys = <String>{};
  final _watchedProgress = <String, _TvPlaybackProgress>{};
  final _accountStore = const TvAccountStateStore();
  TvLibraryStateStore? _libraryStore;
  TvAccountSession? _accountSession;
  TvAccountProfile? _accountProfile;
  String _accountLibraryRevision = '';
  _TvAccountSyncState _accountSyncState = _TvAccountSyncState.guest;
  Timer? _accountLibraryPushTimer;
  _TvHomeEditorialEdition? _homeEditorial;
  int _selectedTab = 0;
  bool _loading = true;
  String? _error;
  _TvItem? _selectedItem;
  _TvRail? _expandedRail;
  bool _searchOpen = false;
  String? _preparingPlaybackKey;
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
    FocusManager.instance.addListener(_tracePrimaryFocus);
    unawaited(_restoreTvLibraryState());
    unawaited(_restoreTvAccountState());
    unawaited(_restoreTvSettings());
  }

  @override
  void dispose() {
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

  void _tracePrimaryFocus() {
    if (!kDebugMode) return;
    final label = FocusManager.instance.primaryFocus?.debugLabel;
    final safeLabel = label == null || label.trim().isEmpty ? 'none' : label;
    if (safeLabel == _lastFocusTraceLabel) return;
    _lastFocusTraceLabel = safeLabel;
    debugPrint(
      'Juicr TV focus trace label=$safeLabel tab=${_tabItems[_selectedTab].label}',
    );
  }

  Future<void> _loadCatalog() async {
    if (!_tvSettings.hasCatalogSource) {
      setState(() {
        _loading = false;
        _error = null;
        _homeEditorial = null;
        _items.clear();
        _movies.clear();
        _series.clear();
        _animation.clear();
        _liveTv.clear();
        _discoveryLaneItems.clear();
        _upcomingPicks.clear();
        _heroEditorialItems = const <_TvItem>[];
        _topSignalRemoteItems = const <_TvItem>[];
        _todaySignalRemoteItems = const <_TvItem>[];
        _juicrTopSignalRemoteItems = const <_TvItem>[];
      });
      return;
    }
    setState(() {
      _loading = true;
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
          catalogSort: _TvDiscoverySort.popular.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.animation,
          sort: _TvDiscoverySort.onTv,
          type: 'animation',
          catalogSort: _TvDiscoverySort.onTv.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.popular,
          type: 'live_tv',
          catalogSort: _TvDiscoverySort.popular.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.newest,
          type: 'live_tv',
          catalogSort: _TvDiscoverySort.newest.catalogSortId,
        ),
        _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.featured,
          type: 'live_tv',
          catalogSort: _TvDiscoverySort.featured.catalogSortId,
        ),
        const _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.popular,
          type: 'livetv',
          catalogSort: 'top',
        ),
        const _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.popular,
          type: 'channel',
          catalogSort: 'top',
        ),
        const _TvCatalogLaneRequest(
          kind: _TvDiscoveryKind.liveTv,
          sort: _TvDiscoverySort.popular,
          type: 'channels',
          catalogSort: 'top',
        ),
      ];
      final results = await Future.wait<Object?>([
        for (final request in catalogRequests)
          _safeCatalog(type: request.type, sort: request.catalogSort),
        _api.homeEditorial(),
      ]).timeout(const Duration(seconds: 22));
      final editorialResult = results[catalogRequests.length];
      final editorial = editorialResult is _TvHomeEditorialEdition
          ? editorialResult
          : null;
      final merged = <String, _TvItem>{};
      final discoveryLaneMaps = <String, Map<String, _TvItem>>{};
      for (var index = 0; index < catalogRequests.length; index++) {
        final list = results[index];
        if (list is! List<_TvItem>) continue;
        final request = catalogRequests[index];
        final laneKey = _tvDiscoveryLaneKey(request.kind, request.sort);
        final laneMap = discoveryLaneMaps.putIfAbsent(
          laneKey,
          () => <String, _TvItem>{},
        );
        for (final item in list) {
          final normalized = _normalizeCatalogLane(item);
          final itemKey = '${normalized.type}:${normalized.id}';
          laneMap[itemKey] = normalized;
          merged[itemKey] = normalized;
        }
      }
      final discoveryLanes = {
        for (final entry in discoveryLaneMaps.entries)
          entry.key: entry.value.values
              .where((item) => item.poster != null)
              .toList(growable: false),
      };
      final all = merged.values.where((item) => item.poster != null).toList();
      final upcomingPicks =
          discoveryLanes[_tvDiscoveryLaneKey(
            _TvDiscoveryKind.movie,
            _TvDiscoverySort.upcoming,
          )]?.where((item) => item.type == 'movie').toList(growable: false) ??
          const <_TvItem>[];
      final heroEditorial = _editorialOrFallback(
        editorial?.hero,
        _dailyHeroEditorial(),
      );
      final heroItems = await _loadCuratedHeroItems(heroEditorial);
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
          ..addAll(all.where(_isLiveTvItem));
        _discoveryLaneItems
          ..clear()
          ..addAll(discoveryLanes);
        _upcomingPicks
          ..clear()
          ..addAll(upcomingPicks);
        _heroEditorialItems = heroItems;
        _topSignalRemoteItems = const <_TvItem>[];
        _todaySignalRemoteItems = const <_TvItem>[];
        _juicrTopSignalRemoteItems = const <_TvItem>[];
        _homeEditorial = editorial;
        _loading = false;
        _reconcileRecentItemsWithCatalog();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedItem != null || _searchOpen) return;
        _focusSelectedTabFirstItem();
      });
      unawaited(_refreshHomeSignalRails(editorial, seedItems: all));
    } catch (error) {
      setState(() {
        _loading = false;
        _error = 'Catalog is unavailable right now. Try again shortly.';
      });
    }
  }

  Future<List<_TvItem>> _safeCatalog({
    required String type,
    required String sort,
  }) async {
    try {
      return await _api
          .catalog(type: type, sort: sort)
          .timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint(
        'Juicr TV catalog lane skipped '
        'lane=$type bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return const <_TvItem>[];
    }
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
    final currentKey = current == null
        ? ''
        : '${current.editionId}|${current.editionDate}';
    if (currentKey != editionKey) return;
    setState(() {
      _topSignalRemoteItems = hydrated.topSignal;
      _todaySignalRemoteItems = hydrated.todaySignal;
      _juicrTopSignalRemoteItems = hydrated.juicrTopSignal;
    });
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
          final meta = await _api
              .meta(metaSeed)
              .timeout(const Duration(seconds: 5));
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
    if (_isLiveTvItem(item)) return item.withType('live');
    if (_isAnimationOrAnimationItem(item)) return item.withType('animation');
    return item;
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
    if (item.type == 'live' || item.type == 'livetv' || item.type == 'channel')
      return true;
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
    try {
      final prefs = await SharedPreferences.getInstance();
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
    if (restored.hasCatalogSource) {
      unawaited(_loadCatalog());
    } else {
      setState(() => _loading = false);
    }
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
        profile =
            await _api
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
      if (fetchRemote) {
        final remote = await _api.fetchAccountLibrarySnapshot(session!.token);
        final remoteSnapshot = remote?.snapshot;
        if (remoteSnapshot != null && remoteSnapshot.isNotEmpty) {
          _accountLibraryRevision = remote!.revision;
          final merged = store.state.mergeMobileLibraryBackup(remoteSnapshot);
          await store.save(merged);
          if (mounted) {
            setState(() => _applyLibraryState(store.state));
          }
        }
      }
      final push = await _api.pushAccountLibrarySnapshot(
        token: session!.token,
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
      await _api.syncAccountWatchMetrics(
        token: session.token,
        activeWatchSeconds: store.state.activeWatchSeconds,
      );
      if (mounted) {
        setState(() => _accountSyncState = _TvAccountSyncState.synced);
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
    if (parts.length != 2 || parts.first.isEmpty || parts.last.isEmpty)
      return 'Signed in';
    final name = parts.first;
    final visible = name.length <= 2 ? name : name.substring(0, 2);
    return '$visible***@${parts.last}';
  }

  Future<void> _openAccountSignIn() async {
    final credentials = await showDialog<_TvAccountSignInResult>(
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

  List<_TvRail> get _rails {
    final editorial = _homeEditorial;
    final rails = <_TvRail>[];
    final usedKeys = <String>{
      for (final item in _homeHeroItems.take(8)) _homeUsedKey(item),
    };

    void addRail({
      required String title,
      required String subtitle,
      required List<_TvItem> primary,
      List<_TvItem> fallback = const <_TvItem>[],
      int limit = 20,
      bool preservePrimaryRank = false,
    }) {
      final items = _backfilledHomeRailItems(
        primary,
        fallbackPool: fallback,
        usedKeys: usedKeys,
        limit: limit,
        preservePrimaryRank: preservePrimaryRank,
      );
      if (items.isEmpty) return;
      rails.add(_TvRail(title, subtitle, items));
      usedKeys.addAll(items.map(_homeUsedKey));
    }

    final todayEditorial = _editorialOrFallback(
      editorial?.todaySignal,
      _dailyTopSignalEditorial(),
    );
    final todayRemoteItems = _remoteHomeSignalItems(
      _todaySignalRemoteItems,
      todayEditorial,
    );
    addRail(
      title: todayEditorial.title,
      subtitle: todayEditorial.subtitle,
      primary: todayRemoteItems.length >= 3
          ? todayRemoteItems
          : _itemsForEditorial(todayEditorial),
      fallback: todayRemoteItems.length >= 3
          ? const <_TvItem>[]
          : _topSignalFallbackItems(todayEditorial),
      limit: 20,
      preservePrimaryRank: todayRemoteItems.length >= 3,
    );

    final weekEditorial = _editorialOrFallback(
      editorial?.topSignal,
      _weeklyTopSignalEditorial(),
    );
    final weekRemoteItems = _remoteHomeSignalItems(
      _topSignalRemoteItems,
      weekEditorial,
    );
    addRail(
      title: weekEditorial.title,
      subtitle: weekEditorial.subtitle,
      primary: weekRemoteItems.length >= 3
          ? weekRemoteItems
          : _itemsForEditorial(weekEditorial),
      fallback: weekRemoteItems.length >= 3
          ? const <_TvItem>[]
          : _topSignalFallbackItems(weekEditorial),
      limit: 20,
      preservePrimaryRank: weekRemoteItems.length >= 3,
    );

    final topTenEditorial = _editorialOrFallback(
      editorial?.juicrTopSignal,
      _juicrTopSignalEditorial(),
    );
    final topTenRemoteItems = _remoteHomeSignalItems(
      _juicrTopSignalRemoteItems,
      topTenEditorial,
    );
    addRail(
      title: topTenEditorial.title,
      subtitle: topTenEditorial.subtitle,
      primary: topTenRemoteItems.length >= 3
          ? topTenRemoteItems
          : _itemsForEditorial(topTenEditorial),
      fallback: topTenRemoteItems.length >= 3
          ? const <_TvItem>[]
          : _topSignalFallbackItems(topTenEditorial),
      limit: 10,
      preservePrimaryRank: topTenRemoteItems.length >= 3,
    );

    addRail(
      title: 'Saved For Later',
      subtitle: 'Titles you marked to revisit.',
      primary: _likedItems,
      limit: 12,
    );

    final upcomingEditorial = _editorialOrFallback(
      editorial?.upcoming,
      _upcomingThisYearEditorial(),
    );
    addRail(
      title: upcomingEditorial.title,
      subtitle: '',
      primary: _upcomingPicks,
      fallback: const <_TvItem>[],
      limit: 20,
    );

    if (rails.isNotEmpty) return rails;
    return [
      _TvRail(
        'Trending Today',
        'Fresh picks moving fastest right now.',
        _availableHomeItems(_items).take(10).toList(),
      ),
      _TvRail(
        'Trending This Week',
        'The picks that keep winning the room.',
        _availableHomeItems(_movies).take(10).toList(),
      ),
      _TvRail(
        "Juicr's Top 10",
        'Movies and shows with the strongest score signal.',
        _availableHomeItems(_series).take(10).toList(),
      ),
    ].where((rail) => rail.items.isNotEmpty).toList();
  }

  List<_TvItem> get _homeHeroItems {
    if (_heroEditorialItems.isNotEmpty) {
      return _heroEditorialItems.take(8).toList();
    }
    final editorial = _homeEditorial;
    if (editorial != null) {
      final curated = _itemsForEditorial(editorial.hero);
      if (curated.isNotEmpty) return curated.take(8).toList();
    }
    final fallback = _availableHomeItems([
      ..._movies,
      ..._series,
      ..._animation,
      ..._items,
    ]);
    return _stableDailyShuffle(
      fallback,
      seed: 'tv-home-hero'.hashCode,
    ).take(8).toList();
  }

  _TvHomeEditorialRail get _homeHeroEditorial {
    return _editorialOrFallback(_homeEditorial?.hero, _dailyHeroEditorial());
  }

  Future<List<_TvItem>> _loadCuratedHeroItems(
    _TvHomeEditorialRail editorial,
  ) async {
    if (!_hasHeroEditorialScope(editorial)) return const <_TvItem>[];
    final ranked = await _hydrateHomeSignalRail(
      editorial,
      seedItems: _items,
      limit: 12,
    );
    if (ranked.isNotEmpty) return ranked.take(12).toList(growable: false);
    final types = editorial.types.isEmpty
        ? const ['movie', 'series', 'animation']
        : editorial.types;
    final genre = editorial.genres.isEmpty
        ? 'All genres'
        : editorial.genres.first;
    final perType = editorial.perType.clamp(1, 12).toInt();
    final buckets = await Future.wait<List<_TvItem>>([
      for (final type in types)
        _loadCuratedHeroBucket(
          type: type,
          editorial: editorial,
          genre: genre,
          limit: perType,
        ),
    ]);
    return _interleaveHeroBuckets(buckets).take(12).toList(growable: false);
  }

  bool _hasHeroEditorialScope(_TvHomeEditorialRail editorial) {
    return editorial.title.isNotEmpty &&
        (editorial.genres.isNotEmpty ||
            editorial.query.isNotEmpty ||
            editorial.items.isNotEmpty ||
            _isInTheatersEditorial(editorial));
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
      try {
        final items = await _api
            .catalog(
              type: type,
              sort: sort,
              genre: genre,
              search: editorial.query,
              deepSearch: editorial.query.isNotEmpty,
              preferDefaultCatalog: true,
            )
            .timeout(const Duration(seconds: 8));
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
          'type=$type bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
        );
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
    final normalized = preferred.trim().isEmpty
        ? 'imdbRating'
        : preferred.trim();
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
    final tokens = cleaned
        .split(RegExp(r'[\s:_-]+'))
        .where((token) => token.length >= 3);
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
    final genreMatches = scoped
        .where((item) {
          if (_itemMatchesAnyEditorialGenre(item, editorial.genres))
            return true;
          return allowUnknownGenre && item.genres.isEmpty;
        })
        .toList(growable: false);
    final ranked = (editorial.genres.isEmpty ? scoped : genreMatches)
      ..sort(
        (left, right) =>
            _homeSignalScore(right).compareTo(_homeSignalScore(left)),
      );
    if (ranked.length >= limit || editorial.requireGenreMatch) {
      return _dedupeHomeItems(ranked).take(limit).toList(growable: false);
    }
    final matched = {for (final item in ranked) _homeUsedKey(item)};
    final fallback =
        [
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

  _TvHomeEditorialRail _dailyHeroEditorial() {
    return _pickDailyHeroEditorial(const [
      _TvHomeEditorialRail(
        id: 'hero',
        title: 'In Theaters',
        subtitle: 'Big-screen energy, couch-ready.',
        types: ['movie'],
        sort: 'nowPlaying',
        intent: 'theatrical_trailers',
        releaseWindow: 'now_playing',
      ),
      _TvHomeEditorialRail(
        id: 'hero',
        title: 'New This Week',
        subtitle: 'Fresh before the rush.',
        genres: ['thriller', 'mystery', 'action', 'drama'],
        sort: 'year',
        intent: 'current_releases',
        releaseWindow: 'current_year',
        requireGenreMatch: true,
      ),
      _TvHomeEditorialRail(
        id: 'hero',
        title: 'Horror night',
        subtitle: 'Every hallway is suspicious.',
        types: ['movie', 'series', 'animation'],
        genres: ['horror'],
        sort: 'imdbRating',
        perType: 3,
        requireGenreMatch: true,
      ),
      _TvHomeEditorialRail(
        id: 'hero',
        title: 'Story momentum',
        subtitle: 'Series and animation with room to pull you in.',
        types: ['series', 'animation'],
        genres: ['drama', 'adventure', 'action', 'mystery'],
        requireGenreMatch: true,
      ),
      _TvHomeEditorialRail(
        id: 'hero',
        title: 'Weekend Picks',
        subtitle: 'Snacks, couch, low pressure.',
        genres: ['comedy', 'drama', 'adventure'],
        requireGenreMatch: true,
      ),
    ], offset: 3);
  }

  _TvHomeEditorialRail _pickDailyHeroEditorial(
    List<_TvHomeEditorialRail> rails, {
    int offset = 0,
  }) {
    final day = DateTime.now().difference(DateTime(2024)).inDays;
    return rails[(day + offset) % rails.length];
  }

  _TvHomeEditorialRail _editorialOrFallback(
    _TvHomeEditorialRail? remote,
    _TvHomeEditorialRail fallback,
  ) {
    if (remote == null ||
        (remote.title.isEmpty &&
            remote.subtitle.isEmpty &&
            remote.items.isEmpty &&
            remote.query.isEmpty &&
            remote.genres.isEmpty)) {
      return fallback;
    }
    return remote;
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

  _TvHomeEditorialRail _dailyTopSignalEditorial() {
    return const _TvHomeEditorialRail(
      id: 'todaySignal',
      kind: 'ranked',
      title: 'Trending Today',
      subtitle: 'Fresh picks moving fastest right now.',
      types: ['movie', 'series'],
      perType: 20,
      intent: 'local_trending_fallback',
      releaseWindow: 'local_trends',
    );
  }

  _TvHomeEditorialRail _weeklyTopSignalEditorial() {
    return const _TvHomeEditorialRail(
      id: 'topSignal',
      kind: 'ranked',
      title: 'Trending This Week',
      subtitle: 'The picks that keep winning the room.',
      types: ['movie', 'series'],
      perType: 20,
      intent: 'local_trending_fallback',
      releaseWindow: 'local_trends',
    );
  }

  _TvHomeEditorialRail _juicrTopSignalEditorial() {
    return const _TvHomeEditorialRail(
      id: 'juicrTopSignal',
      kind: 'ranked',
      title: "Juicr's Top 10",
      subtitle: 'Movies and shows with the strongest score signal.',
      types: ['movie', 'series'],
      perType: 10,
      intent: 'local_score_fallback',
      releaseWindow: 'local_trends',
    );
  }

  _TvHomeEditorialRail _upcomingThisYearEditorial() {
    return const _TvHomeEditorialRail(
      id: 'upcoming',
      kind: 'ranked',
      title: 'Upcoming This Year',
      subtitle: 'Movies expected this year.',
      types: ['movie'],
      sort: 'year',
      perType: 20,
      intent: 'upcoming',
      releaseWindow: 'current_year',
    );
  }

  String _homeUsedKey(_TvItem item) {
    final tmdbId = item.tmdbId;
    if (tmdbId != null) return '${item.type}:tmdb:$tmdbId';
    return '${item.type}:${_normalizeHomeText(item.title)}:${item.year ?? ''}';
  }

  List<_TvItem> _availableHomeItems(Iterable<_TvItem> items) {
    return [
      for (final item in items)
        if (item.poster != null && !_isLiveTvItem(item)) item,
    ];
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

  List<_TvItem> _topSignalFallbackItems(_TvHomeEditorialRail editorial) {
    final pool = _availableHomeItems([
      ..._movies,
      ..._series,
      ..._animation,
      ..._likedItems,
      ..._recentItems,
    ]);
    final scored =
        [for (final item in pool) _ScoredTvItem(item, _homeSignalScore(item))]
          ..sort((left, right) {
            final score = right.score.compareTo(left.score);
            if (score != 0) return score;
            return _homeUsedKey(left.item).compareTo(_homeUsedKey(right.item));
          });
    return _dedupeHomeItems(scored.map((entry) => entry.item));
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

  List<_TvItem> _itemsForEditorial(_TvHomeEditorialRail editorial) {
    var candidates = _availableHomeItems(_items);
    final ranked = _rankedItemsForEditorial(editorial, candidates);
    if (ranked.isNotEmpty) return ranked;
    if (editorial.types.isNotEmpty) {
      final types = editorial.types.toSet();
      candidates = candidates
          .where((item) => types.contains(item.type))
          .toList();
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
      final genres = editorial.genres
          .map((genre) => genre.toLowerCase())
          .toSet();
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
    final day = DateTime.now().difference(DateTime(2024)).inDays;
    final random = math.Random(day + seed.abs());
    copy.shuffle(random);
    return copy;
  }

  void _selectTab(int index) {
    setState(() {
      _selectedTab = index;
      _selectedItem = null;
      _expandedRail = null;
      _searchOpen = false;
    });
  }

  void _selectNavigationItem(int index) {
    if (_navItems[index].label == 'Search') {
      setState(() {
        _selectedItem = null;
        _expandedRail = null;
        _searchOpen = true;
      });
      return;
    }
    final tabIndex = _tabIndexForNavIndex(index);
    if (tabIndex != null) {
      if (tabIndex == _selectedTab) {
        _enterSelectedTabContent();
        return;
      }
      _selectTab(tabIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _enterSelectedTabContent();
      });
    }
  }

  void _moveRightFromNavigation(int index) {
    if (_navItems[index].label == 'Search') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusSelectedTabFirstItem();
      });
      return;
    }
    final tabIndex = _tabIndexForNavIndex(index);
    if (tabIndex == null) return;
    if (tabIndex != _selectedTab) {
      _selectTab(tabIndex);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _enterSelectedTabContent();
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

  Future<void> _openItem(_TvItem item) async {
    _rememberItem(item);
    setState(() {
      _selectedItem = item;
      _searchOpen = false;
    });
    try {
      final detailed = await _api
          .meta(item)
          .timeout(const Duration(seconds: 10));
      if (!mounted || _selectedItem?.id != item.id) return;
      setState(() => _selectedItem = detailed);
    } catch (_) {
      // Keep the catalog card details visible if metadata is unavailable.
    }
  }

  void _rememberItem(_TvItem item) {
    _recentItems.removeWhere(
      (candidate) => candidate.type == item.type && candidate.id == item.id,
    );
    _recentItems.insert(0, item);
    if (_recentItems.length > 24) {
      _recentItems.removeRange(24, _recentItems.length);
    }
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
    );
  }

  Map<String, Object?> _itemSnapshot(_TvItem item) {
    return <String, Object?>{
      'id': item.id,
      'type': item.type,
      'title': item.title,
      if (item.year != null) 'year': item.year,
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
    return [
      for (final item in _items)
        if (_isItemLiked(item)) item,
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
    _scheduleAccountLibraryPush();
  }

  void _updateTvSettings(_TvSettingsState next) {
    final hadCatalogSource = _tvSettings.hasCatalogSource;
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
    if (!hadCatalogSource && next.hasCatalogSource) {
      unawaited(_loadCatalog());
    } else if (hadCatalogSource && !next.hasCatalogSource) {
      unawaited(_loadCatalog());
    }
  }

  void _closeOverlay({bool focusNavigation = false}) {
    setState(() {
      _selectedItem = null;
      _searchOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (focusNavigation) {
        _navigationRailKey.currentState?.focusSelected();
      } else {
        _focusPageEntry();
      }
    });
  }

  void _handleBackPressed() {
    final now = DateTime.now();
    final duplicateBack =
        _lastBackDispatchAt != null &&
        now.difference(_lastBackDispatchAt!) <
            const Duration(milliseconds: 180);
    if (duplicateBack) return;
    _lastBackDispatchAt = now;
    if (_selectedItem != null || _searchOpen) {
      _closeOverlay(focusNavigation: _searchOpen);
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
      _selectTab(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _navigationRailKey.currentState?.focusSelected();
      });
      return;
    }
    final shouldExit =
        _lastExitBackPressAt != null &&
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
    final selection = await showDialog<_TvDiscoverySelection>(
      context: context,
      builder: (context) => _TvDiscoveryMenuDialog(
        kind: _discoveryKind,
        sort: _discoverySort,
        genre: _discoveryGenre,
        genres: _availableDiscoveryGenres,
      ),
    );
    if (!mounted || selection == null) return;
    setState(() {
      _discoveryKind = selection.kind;
      _discoverySort = selection.sort;
      _discoveryGenre = selection.genre;
    });
  }

  List<String> get _availableDiscoveryGenres {
    final genres = <String>{};
    for (final item in _items) {
      genres.addAll(item.genres.where((genre) => genre.trim().isNotEmpty));
    }
    final sorted = genres.toList()
      ..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
    return sorted;
  }

  Future<void> _openLibraryMenu() async {
    final selection = await showDialog<_TvLibraryFilter>(
      context: context,
      builder: (context) => _TvLibraryMenuDialog(filter: _libraryFilter),
    );
    if (!mounted || selection == null) return;
    setState(() => _libraryFilter = selection);
  }

  void _focusPageEntry() {
    if (!mounted) return;
    if (_selectedTab == 0) {
      void focusHero() {
        if (!mounted) return;
        final watchContext = _homeHeroWatchFocusNode.context;
        if (watchContext == null) {
          final firstRailContext = _pageEntryFocusNodes[0].context;
          if (firstRailContext != null) {
            _pageEntryFocusNodes[0].requestFocus();
            Scrollable.ensureVisible(
              firstRailContext,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: 0.36,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            );
          }
          return;
        }
        _rememberPageFocus(_homeHeroWatchFocusNode);
        _homeHeroWatchFocusNode.requestFocus();
        final heroContext = _homeHeroKey.currentContext;
        if (heroContext != null) {
          Scrollable.ensureVisible(
            heroContext,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: 0,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
        }
      }

      focusHero();
      WidgetsBinding.instance.addPostFrameCallback((_) => focusHero());
      return;
    }
    final index = _selectedTab
        .clamp(0, _pageEntryFocusNodes.length - 1)
        .toInt();
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
        if (attempt >= 2) return;
        Future<void>.delayed(
          const Duration(milliseconds: 70),
          () => retryFocus(attempt + 1),
        );
      });
    }

    retryFocus();
  }

  void _focusPageContent() {
    if (!mounted) return;
    final index = _selectedTab
        .clamp(0, _pageContentFocusNodes.length - 1)
        .toInt();
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
        if (attempt >= 2) return;
        Future<void>.delayed(
          const Duration(milliseconds: 70),
          () => retryFocus(attempt + 1),
        );
      });
    }

    retryFocus();
  }

  void _rememberPageFocus(FocusNode node) {
    if (!mounted ||
        _selectedTab < 0 ||
        _selectedTab >= _lastPageFocusNodes.length)
      return;
    _lastPageFocusNodes[_selectedTab] = node;
  }

  bool _focusRememberedPageNode({double alignment = 0.38}) {
    if (!mounted ||
        _selectedTab < 0 ||
        _selectedTab >= _lastPageFocusNodes.length) {
      return false;
    }
    final node = _lastPageFocusNodes[_selectedTab];
    final context = node?.context;
    if (node == null || context == null || !node.canRequestFocus) {
      return false;
    }
    node.requestFocus();
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: alignment,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
    return true;
  }

  void _enterSelectedTabContent() {
    if (_selectedTab != 0) {
      _focusSelectedTabFirstItem();
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
    final ordered = [...sessions];
    int rank(_PlaybackSession session) {
      final type = session.sourceType.toLowerCase();
      final adaptive =
          type.contains('hls') ||
          type.contains('m3u8') ||
          type.contains('dash') ||
          type.contains('mpd');
      final direct = type.contains('mp4') || type.contains('video');
      return switch (_tvSettings.preferredQuality) {
        'Best available' =>
          adaptive
              ? 0
              : direct
              ? 1
              : 2,
        'Data saver' =>
          direct
              ? 0
              : adaptive
              ? 1
              : 2,
        _ =>
          adaptive
              ? 0
              : direct
              ? 1
              : 2,
      };
    }

    ordered.sort((left, right) => rank(left).compareTo(rank(right)));
    return ordered;
  }

  String _playbackProgressKey(_TvItem item, int season, int episode) {
    return '${item.type}:${item.id}:$season:$episode';
  }

  bool _shouldOfferResume(_TvPlaybackProgress progress) {
    if (!_tvSettings.resumePrompt) return false;
    if (progress.position < const Duration(seconds: 45)) return false;
    if (progress.duration <= Duration.zero) return true;
    return progress.duration - progress.position > const Duration(minutes: 2);
  }

  Future<Duration?> _resumePositionFor(
    _TvItem item,
    int season,
    int episode,
  ) async {
    final progress =
        _watchedProgress[_playbackProgressKey(item, season, episode)];
    if (progress == null || !_shouldOfferResume(progress)) return Duration.zero;
    final continuePlayback = await showDialog<bool>(
      context: context,
      builder: (context) => _TvResumePlaybackDialog(progress: progress),
    );
    if (!mounted || continuePlayback == null) return null;
    return continuePlayback ? progress.position : Duration.zero;
  }

  Future<void> _play(_TvItem item, {int season = 1, int episode = 1}) async {
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
    final playbackKey = '${item.type}:${item.id}:$season:$episode';
    if (_preparingPlaybackKey != null) return;
    if (!mounted) return;
    setState(() => _preparingPlaybackKey = playbackKey);
    debugPrint(
      'Juicr TV playback requested hasSource=${_tvSettings.hasPlaybackSource}',
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resumePosition = await _resumePositionFor(item, season, episode);
      if (resumePosition == null) return;
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Preparing playback...'),
            duration: Duration(seconds: 1),
          ),
        );
      final subtitles = await _subtitlesForPlayback(
        item,
        season: season,
        episode: episode,
      );
      final sessions = _orderedPlaybackSessions(
        await _api
            .playbackSessions(item, season: season, episode: episode)
            .timeout(const Duration(seconds: 75)),
      );
      if (!mounted) return;
      final progress = await Navigator.of(context).push<_TvPlaybackProgress>(
        MaterialPageRoute<_TvPlaybackProgress>(
          builder: (_) => _TvPlaybackPage(
            item: item,
            sessions: sessions,
            initialSessionIndex: 0,
            initialSeason: season,
            initialEpisode: episode,
            initialResumePosition: resumePosition,
            settings: _tvSettings,
            subtitles: subtitles,
            initialSubtitleIndex: subtitles.isEmpty ? -1 : 0,
          ),
        ),
      );
      if (progress != null && progress.duration > Duration.zero) {
        _watchedProgress[playbackKey] = progress;
        unawaited(
          _libraryStore?.updateProgress(
                key: playbackKey,
                positionMillis: progress.position.inMilliseconds,
                durationMillis: progress.duration.inMilliseconds,
              ) ??
              Future<void>.value(),
        );
        if (_isPlaybackComplete(progress)) {
          unawaited(
            _libraryStore?.markCompleted(playbackKey) ?? Future<void>.value(),
          );
        }
        _scheduleAccountLibraryPush();
      }
      if (_tvSettings.keepHistory) _rememberItem(item);
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
    } finally {
      if (mounted && _preparingPlaybackKey == playbackKey) {
        setState(() => _preparingPlaybackKey = null);
      }
    }
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
    if (!_tvSettings.subtitles || !_tvSettings.builtInSubtitles) {
      return const <_TvSubtitle>[];
    }
    try {
      return await _api
          .subtitles(item, season: season, episode: episode)
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint(
        'Juicr TV subtitle lookup skipped '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return const <_TvSubtitle>[];
    }
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
      final trailers = await _api
          .trailers(item)
          .timeout(const Duration(seconds: 18));
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
    _tvAccentColor = _accentForSetting(_tvSettings.accent);
    _tvTextScale = _textScaleForSetting(_tvSettings.textSize);
    _tvMotionEnabled = _tvSettings.motion;
    final lightTheme = _tvSettings.theme == 'Light';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        _handleBackPressed();
      },
      child: Scaffold(
        backgroundColor: lightTheme
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF07080D),
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
                                homeHeroEditorial: _homeHeroEditorial,
                                homeHeroKey: _homeHeroKey,
                                homeHeroWatchFocusNode: _homeHeroWatchFocusNode,
                                allItems: _items,
                                movies: _movies,
                                series: _series,
                                animation: _animation,
                                liveTv: _liveTv,
                                discoveryLaneItems: _discoveryLaneItems,
                                recentItems: _recentItems,
                                likedItems: _likedItems,
                                discoveryKind: _discoveryKind,
                                discoverySort: _discoverySort,
                                discoveryGenre: _discoveryGenre,
                                libraryFilter: _libraryFilter,
                                accountSignedIn: _accountSignedIn,
                                accountLabel: _accountLabel,
                                accountSyncLabel: _accountSyncLabel,
                                tvSettings: _tvSettings,
                                onTvSettingsChanged: _updateTvSettings,
                                onAccountSignIn: () =>
                                    unawaited(_openAccountSignIn()),
                                onAccountSignOut: () =>
                                    unawaited(_signOutAccount()),
                                onAccountSync: () =>
                                    unawaited(_syncAccountNow()),
                                onDiscoveryMenu: _openDiscoveryMenu,
                                onLibraryMenu: _openLibraryMenu,
                                onOpenItem: _openItem,
                                onPlayItem: (item) => _play(item),
                                onTrailerItem: (item) =>
                                    unawaited(_playTrailer(item)),
                                onToggleLike: _toggleLike,
                                isItemLiked: _isItemLiked,
                                onOpenRail: (rail) =>
                                    setState(() => _expandedRail = rail),
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
                                onRetry: _loadCatalog,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_selectedItem != null)
                        _TvDetailsOverlay(
                          item: _selectedItem!,
                          onClose: _closeOverlay,
                          preparing:
                              _preparingPlaybackKey?.startsWith(
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
