import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

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
  return _tvMotionEnabled ? Duration(milliseconds: milliseconds) : Duration.zero;
}

class _TvLeftBoundaryIntent extends Intent {
  const _TvLeftBoundaryIntent();
}

class _TvRightBoundaryIntent extends Intent {
  const _TvRightBoundaryIntent();
}

class _TvUpBoundaryIntent extends Intent {
  const _TvUpBoundaryIntent();
}

class _TvDownBoundaryIntent extends Intent {
  const _TvDownBoundaryIntent();
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

class TvHomePage extends StatefulWidget {
  const TvHomePage({super.key});

  @override
  State<TvHomePage> createState() => _TvHomePageState();
}

class _TvHomePageState extends State<TvHomePage> {
  final GlobalKey<_TvNavigationRailState> _navigationRailKey = GlobalKey<_TvNavigationRailState>();
  final GlobalKey _homeHeroKey = GlobalKey(debugLabel: 'tv-home-hero');
  final FocusNode _homeHeroWatchFocusNode = FocusNode(debugLabel: 'tv-home-hero-watch');
  late final List<FocusNode> _pageEntryFocusNodes = List.generate(
    _tabItems.length,
    (index) => FocusNode(debugLabel: 'tv-page-entry-${_tabItems[index].label}'),
  );
  late final List<FocusNode> _pageContentFocusNodes = List.generate(
    _tabItems.length,
    (index) => FocusNode(debugLabel: 'tv-page-content-${_tabItems[index].label}'),
  );
  final _api = _TvApi();
  final _items = <_TvItem>[];
  final _movies = <_TvItem>[];
  final _series = <_TvItem>[];
  final _animation = <_TvItem>[];
  final _liveTv = <_TvItem>[];
  final _recentItems = <_TvItem>[];
  final _likedItemKeys = <String>{};
  final _watchedProgress = <String, _TvPlaybackProgress>{};
  _TvHomeEditorialEdition? _homeEditorial;
  int _selectedTab = 0;
  bool _loading = true;
  String? _error;
  _TvItem? _selectedItem;
  _TvRail? _expandedRail;
  bool _searchOpen = false;
  String? _preparingPlaybackKey;
  DateTime? _lastExitBackPressAt;
  _TvDiscoveryKind _discoveryKind = _TvDiscoveryKind.movie;
  _TvDiscoverySort _discoverySort = _TvDiscoverySort.popular;
  String _discoveryGenre = 'All genres';
  _TvLibraryFilter _libraryFilter = _TvLibraryFilter.continueWatching;
  _TvSettingsState _tvSettings = const _TvSettingsState();

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
    unawaited(_restoreTvSettings());
  }

  @override
  void dispose() {
    _homeHeroWatchFocusNode.dispose();
    for (final node in _pageEntryFocusNodes) {
      node.unfocus();
      node.dispose();
    }
    for (final node in _pageContentFocusNodes) {
      node.unfocus();
      node.dispose();
    }
    super.dispose();
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
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        _safeCatalog(type: 'movie', sort: 'top'),
        _safeCatalog(type: 'movie', sort: 'imdbRating'),
        _safeCatalog(type: 'series', sort: 'top'),
        _safeCatalog(type: 'series', sort: 'imdbRating'),
        _safeCatalog(type: 'animation', sort: 'top'),
        _safeCatalog(type: 'animation', sort: 'imdbRating'),
        _safeCatalog(type: 'animation', sort: 'top'),
        _safeCatalog(type: 'live', sort: 'top'),
        _safeCatalog(type: 'livetv', sort: 'top'),
        _safeCatalog(type: 'channel', sort: 'top'),
        _safeCatalog(type: 'channels', sort: 'top'),
        _api.homeEditorial(),
      ]).timeout(const Duration(seconds: 22));
      final catalogResults = results.take(11).whereType<List<_TvItem>>();
      final editorial = results[11] is _TvHomeEditorialEdition ? results[11] as _TvHomeEditorialEdition : null;
      final merged = <String, _TvItem>{};
      for (final list in catalogResults) {
        for (final item in list) {
          final normalized = _normalizeCatalogLane(item);
          merged['${normalized.type}:${normalized.id}'] = normalized;
        }
      }
      final all = merged.values.where((item) => item.poster != null).toList();
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
        _homeEditorial = editorial;
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = 'Catalog is unavailable right now. Try again shortly.';
      });
    }
  }

  Future<List<_TvItem>> _safeCatalog({required String type, required String sort}) async {
    try {
      return await _api.catalog(type: type, sort: sort).timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint(
        'Juicr TV catalog lane skipped '
        'lane=$type bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return const <_TvItem>[];
    }
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
    if (item.type == 'live' || item.type == 'livetv' || item.type == 'channel') return true;
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
          restored = _TvSettingsState.fromJson(Map<String, dynamic>.from(decoded));
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

  List<_TvRail> get _rails {
    final editorial = _homeEditorial;
    if (editorial != null) {
      final rails = [
        _railFromEditorial(editorial.topSignal, fallbackItems: _items.take(10).toList()),
        _railFromEditorial(editorial.movie, fallbackItems: _movies.skip(4).take(10).toList()),
        _railFromEditorial(editorial.series, fallbackItems: _series.take(10).toList()),
        _railFromEditorial(editorial.animation, fallbackItems: _animation.take(10).toList()),
      ].whereType<_TvRail>().where((rail) => rail.items.isNotEmpty).toList();
      if (rails.isNotEmpty) return rails;
    }
    return [
      _TvRail('People keep picking this', 'Popular titles ready for the room.', _items.take(10).toList()),
      _TvRail('Good noise', 'Easy starts when nobody wants to choose.', _movies.skip(4).take(10).toList()),
      _TvRail('Before trouble', 'Series with momentum.', _series.take(10).toList()),
    ].where((rail) => rail.items.isNotEmpty).toList();
  }

  List<_TvItem> get _homeHeroItems {
    final editorial = _homeEditorial;
    if (editorial != null) {
      final curated = _itemsForEditorial(editorial.hero);
      if (curated.isNotEmpty) return curated.take(8).toList();
    }
    final rails = _rails;
    if (rails.isEmpty || rails.first.items.isEmpty) return const <_TvItem>[];
    return rails.first.items.take(8).toList();
  }

  _TvItem? get _homeHeroItem {
    final items = _homeHeroItems;
    if (items.isEmpty) return null;
    return items.first;
  }

  _TvRail? _railFromEditorial(_TvHomeEditorialRail editorial, {required List<_TvItem> fallbackItems}) {
    if (editorial.title.isEmpty && editorial.subtitle.isEmpty) return null;
    final curated = _itemsForEditorial(editorial);
    final items = curated.isNotEmpty ? curated : fallbackItems;
    return _TvRail(
      editorial.title.isNotEmpty ? editorial.title : 'Worth a look',
      editorial.subtitle.isNotEmpty ? editorial.subtitle : 'Fresh picks for this shelf.',
      items.take(10).toList(),
    );
  }

  List<_TvItem> _itemsForEditorial(_TvHomeEditorialRail editorial) {
    var candidates = _items.where((item) => item.poster != null).toList();
    if (editorial.types.isNotEmpty) {
      final types = editorial.types.toSet();
      candidates = candidates.where((item) => types.contains(item.type)).toList();
    }
    if (editorial.query.isNotEmpty) {
      final query = editorial.query.toLowerCase();
      candidates = candidates.where((item) => item.title.toLowerCase().contains(query)).toList();
    }
    if (editorial.genres.isNotEmpty) {
      final genres = editorial.genres.map((genre) => genre.toLowerCase()).toSet();
      final genreMatches = candidates.where((item) {
        return item.genres.any((genre) => genres.contains(genre.toLowerCase()));
      }).toList();
      if (genreMatches.isNotEmpty || editorial.requireGenreMatch) {
        candidates = genreMatches;
      }
    }
    if (_requiresCurrentReleaseWindow(editorial)) {
      final currentYear = DateTime.now().year;
      final current = candidates.where((item) => _yearInt(item.year) >= currentYear - 1).toList();
      if (current.isNotEmpty || editorial.requireGenreMatch) {
        candidates = current;
      }
    }
    if (editorial.sort == 'year') {
      candidates.sort((a, b) => (_yearInt(b.year)).compareTo(_yearInt(a.year)));
    } else if (editorial.sort.toLowerCase().contains('imdb')) {
      candidates.sort((a, b) => (_ratingDouble(b.imdbRating)).compareTo(_ratingDouble(a.imdbRating)));
    }
    return _stableDailyShuffle(candidates, seed: editorial.title.hashCode);
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
      _selectTab(tabIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusSelectedTabFirstItem();
      });
    }
  }

  void _moveRightFromNavigation(int index) {
    if (_navItems[index].label == 'Search') {
      return;
    }
    final tabIndex = _tabIndexForNavIndex(index);
    if (tabIndex == null || tabIndex != _selectedTab) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusSelectedTabFirstItem();
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
      final detailed = await _api.meta(item).timeout(const Duration(seconds: 10));
      if (!mounted || _selectedItem?.id != item.id) return;
      setState(() => _selectedItem = detailed);
    } catch (_) {
      // Keep the catalog card details visible if metadata is unavailable.
    }
  }

  void _rememberItem(_TvItem item) {
    _recentItems.removeWhere((candidate) => candidate.type == item.type && candidate.id == item.id);
    _recentItems.insert(0, item);
    if (_recentItems.length > 24) {
      _recentItems.removeRange(24, _recentItems.length);
    }
  }

  String _itemKey(_TvItem item) => '${item.type}:${item.id}';

  bool _isItemLiked(_TvItem item) => _likedItemKeys.contains(_itemKey(item));

  List<_TvItem> get _likedItems {
    return [
      for (final item in _items)
        if (_isItemLiked(item)) item,
    ];
  }

  void _toggleLike(_TvItem item) {
    setState(() {
      final key = _itemKey(item);
      if (!_likedItemKeys.add(key)) {
        _likedItemKeys.remove(key);
      }
    });
  }

  void _updateTvSettings(_TvSettingsState next) {
    final hadCatalogSource = _tvSettings.hasCatalogSource;
    setState(() {
      _tvSettings = next;
      if (!next.keepHistory) {
        _recentItems.clear();
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
    if (_selectedItem != null || _searchOpen) {
      _closeOverlay(focusNavigation: _searchOpen);
      return;
    }
    if (_expandedRail != null) {
      setState(() => _expandedRail = null);
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
    final now = DateTime.now();
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
      ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
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
      return;
    }
    final index = _selectedTab.clamp(0, _pageEntryFocusNodes.length - 1).toInt();
    final node = _pageEntryFocusNodes[index];
    if (node.context != null) {
      node.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || node.context == null) return;
      node.requestFocus();
    });
  }

  void _focusPageContent() {
    if (!mounted) return;
    final index = _selectedTab.clamp(0, _pageContentFocusNodes.length - 1).toInt();
    final node = _pageContentFocusNodes[index];
    if (node.context != null) {
      node.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || node.context == null) return;
      node.requestFocus();
    });
  }

  void _focusSelectedTabFirstItem() {
    if (_selectedTab == 0) {
      _focusPageEntry();
      return;
    }
    if (_selectedTab == 1 || _selectedTab == 2 || _selectedTab == 3) {
      _focusPageEntry();
      return;
    }
    _focusPageContent();
  }

  List<_PlaybackSession> _orderedPlaybackSessions(List<_PlaybackSession> sessions) {
    final ordered = [...sessions];
    int rank(_PlaybackSession session) {
      final type = session.sourceType.toLowerCase();
      final adaptive = type.contains('hls') || type.contains('m3u8') || type.contains('dash') || type.contains('mpd');
      final direct = type.contains('mp4') || type.contains('video');
      return switch (_tvSettings.preferredQuality) {
        'Best available' => adaptive ? 0 : direct ? 1 : 2,
        'Data saver' => direct ? 0 : adaptive ? 1 : 2,
        _ => adaptive ? 0 : direct ? 1 : 2,
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

  Future<Duration?> _resumePositionFor(_TvItem item, int season, int episode) async {
    final progress = _watchedProgress[_playbackProgressKey(item, season, episode)];
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
            content: Text('Enable a playback source in Settings or add your own add-on first.'),
            duration: Duration(seconds: 3),
          ),
        );
      return;
    }
    final playbackKey = '${item.type}:${item.id}:$season:$episode';
    if (_preparingPlaybackKey != null) return;
    final resumePosition = await _resumePositionFor(item, season, episode);
    if (resumePosition == null) return;
    setState(() => _preparingPlaybackKey = playbackKey);
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Preparing playback...'),
          duration: Duration(seconds: 1),
        ),
      );
    try {
      final subtitles = await _subtitlesForPlayback(item, season: season, episode: episode);
      final sessions = _orderedPlaybackSessions(
        await _api.playbackSessions(
          item,
          season: season,
          episode: episode,
          allowWebFallback: _tvSettings.playbackEngine != 'Native',
        ).timeout(
        const Duration(seconds: 75),
        ),
      );
      VideoPlayerController? readyController;
      var readyIndex = 0;
      Object? lastInitError;
      for (var index = 0; index < sessions.length; index++) {
        final session = sessions[index];
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(session.tvMediaUrl),
          formatHint: session.videoFormatHint,
          httpHeaders: session.httpHeaders,
          closedCaptionFile: subtitles.isNotEmpty ? _captionFileFor(subtitles.first) : null,
        );
        try {
          await controller.initialize().timeout(const Duration(seconds: 22));
          if (resumePosition > Duration.zero && resumePosition < controller.value.duration) {
            await controller.seekTo(resumePosition);
          }
          await controller.play();
          readyController = controller;
          readyIndex = index;
          break;
        } catch (error) {
          lastInitError = error;
          debugPrint(
            'Juicr TV playback candidate failed '
            'candidate=${index + 1}/${sessions.length} '
            'bucket=${_playbackInitBucket(error)} '
            'errorType=${error.runtimeType}',
          );
          await controller.dispose();
        }
      }
      final controller = readyController;
      if (controller == null) {
        throw _PlaybackUnavailableException(
          _playbackInitBucket(lastInitError ?? 'media_init'),
        );
      }
      if (!mounted) return;
      final progress = await Navigator.of(context).push<_TvPlaybackProgress>(
        MaterialPageRoute<_TvPlaybackProgress>(
          builder: (_) => _TvPlaybackPage(
            item: item,
            controller: controller,
            sessions: sessions,
            initialSessionIndex: readyIndex,
            initialSeason: season,
            initialEpisode: episode,
            settings: _tvSettings,
            subtitles: subtitles,
            initialSubtitleIndex: subtitles.isEmpty ? -1 : 0,
          ),
        ),
      );
      if (progress != null && progress.duration > Duration.zero) {
        _watchedProgress[playbackKey] = progress;
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

  Future<ClosedCaptionFile> _captionFileFor(_TvSubtitle subtitle) async {
    final text = await _api.subtitleText(subtitle);
    return subtitle.format.toLowerCase().contains('srt')
        ? SubRipCaptionFile(text)
        : WebVTTCaptionFile(text);
  }

  Future<void> _playTrailer(_TvItem item) async {
    if (!_tvSettings.builtInTrailers && !_tvSettings.hasUserAddOns) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Enable trailers in Settings or add your own add-on first.'),
            duration: Duration(seconds: 3),
          ),
        );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Preparing trailer...'), duration: Duration(seconds: 1)),
      );
    VideoPlayerController? controller;
    try {
      final trailers = await _api.trailers(item).timeout(const Duration(seconds: 18));
      _TvTrailer? trailer;
      for (final candidate in trailers) {
        if (candidate.isTvPlayable) {
          trailer = candidate;
          break;
        }
      }
      if (trailer == null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('No TV trailer is available for this title yet.')),
          );
        return;
      }
      final session = _PlaybackSession(
        mediaUrl: trailer.url,
        sourceType: trailer.sourceType,
        httpHeaders: _TvApi.juicrMediaHeaders,
      );
      controller = VideoPlayerController.networkUrl(
        Uri.parse(session.tvMediaUrl),
        formatHint: session.videoFormatHint,
        httpHeaders: session.httpHeaders,
      );
      await controller.initialize().timeout(const Duration(seconds: 22));
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
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
            controller: controller!,
            sessions: [session],
            initialSessionIndex: 0,
            initialSeason: 1,
            initialEpisode: 1,
            settings: _tvSettings,
            subtitles: const <_TvSubtitle>[],
            initialSubtitleIndex: -1,
          ),
        ),
      );
    } catch (_) {
      await controller?.dispose();
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('This trailer is not ready for TV playback yet.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    _tvAccentColor = _accentForSetting(_tvSettings.accent);
    _tvTextScale = _textScaleForSetting(_tvSettings.textSize);
    _tvMotionEnabled = _tvSettings.motion;
    final lightTheme = _tvSettings.theme == 'Light';
    return WillPopScope(
      onWillPop: () async {
        _handleBackPressed();
        return false;
      },
      child: Scaffold(
        backgroundColor: lightTheme ? const Color(0xFFFFFFFF) : const Color(0xFF07080D),
        body: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(_tvTextScale),
          ),
          child: TickerMode(
            enabled: _tvMotionEnabled,
            child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(TraversalDirection.left),
          SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(TraversalDirection.right),
          SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
          SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                _handleBackPressed();
                return null;
              },
            ),
          },
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Stack(
              children: [
                _TvBackdrop(settings: _tvSettings),
                Focus(
                  descendantsAreFocusable: _selectedItem == null && !_searchOpen,
                  descendantsAreTraversable: _selectedItem == null && !_searchOpen,
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
                          homeHeroKey: _homeHeroKey,
                          homeHeroWatchFocusNode: _homeHeroWatchFocusNode,
                          allItems: _items,
                          movies: _movies,
                          series: _series,
                          animation: _animation,
                          liveTv: _liveTv,
                          recentItems: _recentItems,
                          likedItems: _likedItems,
                          discoveryKind: _discoveryKind,
                          discoverySort: _discoverySort,
                          discoveryGenre: _discoveryGenre,
                          libraryFilter: _libraryFilter,
                          tvSettings: _tvSettings,
                          onTvSettingsChanged: _updateTvSettings,
                          onDiscoveryMenu: _openDiscoveryMenu,
                          onLibraryMenu: _openLibraryMenu,
                          onOpenItem: _openItem,
                          onPlayItem: (item) => _play(item),
                          onTrailerItem: (item) => unawaited(_playTrailer(item)),
                          onToggleLike: _toggleLike,
                          isItemLiked: _isItemLiked,
                          onOpenRail: (rail) => setState(() => _expandedRail = rail),
                          onBackToHome: () => setState(() => _expandedRail = null),
                          onFocusNavigation: () => _navigationRailKey.currentState?.focusSelected(),
                          pageEntryFocusNode: _pageEntryFocusNodes[_selectedTab],
                          pageContentFocusNode: _pageContentFocusNodes[_selectedTab],
                          onFocusPageEntry: _focusPageEntry,
                          onFocusPageContent: _focusPageContent,
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
                    preparing: _preparingPlaybackKey?.startsWith('${_selectedItem!.type}:${_selectedItem!.id}:') == true,
                    liked: _isItemLiked(_selectedItem!),
                    onPlay: () => _play(_selectedItem!),
                    onPlayEpisode: (season, episode) => _play(_selectedItem!, season: season, episode: episode),
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


