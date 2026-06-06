import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ad_policy.dart';
import 'app_state.dart';
import 'catalog_empty_state.dart';
import 'catalog_item.dart';
import 'copy_normalization.dart';
import 'details_page.dart';
import 'diagnostic_log.dart';
import 'motion.dart';
import 'playback_provider.dart';
import 'stream_api.dart';
import 'visual_style.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin<HomePage> {
  static const String _homeWarmSnapshotKey = 'home_warm_snapshot_v1';
  static const String _homeEditorialCacheKey = 'home_editorial_cache_v1';

  final StreamApi _api = StreamApi();
  final Stopwatch _homeStartupStopwatch = Stopwatch()..start();
  List<CatalogItem> _newMovies = const <CatalogItem>[];
  List<CatalogItem> _newSeries = const <CatalogItem>[];
  List<CatalogItem> _topMovies = const <CatalogItem>[];
  List<CatalogItem> _topSeries = const <CatalogItem>[];
  List<CatalogItem> _animationPicks = const <CatalogItem>[];
  List<CatalogItem> _upcomingPicks = const <CatalogItem>[];
  List<CatalogItem> _heroEditorialItems = const <CatalogItem>[];
  List<CatalogItem> _topSignalRemoteItems = const <CatalogItem>[];
  List<CatalogItem> _todaySignalRemoteItems = const <CatalogItem>[];
  List<CatalogItem> _juicrTopSignalRemoteItems = const <CatalogItem>[];
  final Map<String, bool> _heroTrailerAvailability = <String, bool>{};
  final Set<String> _heroTrailerAvailabilityInFlight = <String>{};
  final Map<String, CatalogItem> _heroTrailerAvailabilityPending =
      <String, CatalogItem>{};
  final Map<String, int> _heroTrailerAvailabilityAttempts = <String, int>{};
  HomeEditorialEdition? _remoteEditorial;
  bool _loading = true;
  bool _matureContentChoiceScheduled = false;
  bool _firstHomeFrameLogged = false;
  bool _firstHomeReadyLogged = false;
  int _loadGeneration = 0;
  String? _lastHomeRailCountLog;
  bool _heroTrailerAvailabilityWorkerRunning = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    DiagnosticLog.add('startup home init');
    AppState.shellTab.addListener(_handleShellTabChanged);
    AppState.preferencesReady.addListener(_handleCatalogSourcesChanged);
    AppState.defaultCatalogEnabled.addListener(_handleCatalogSourcesChanged);
    AppState.userAddons.addListener(_handleCatalogSourcesChanged);
    AppState.personalServerConnections.addListener(
      _handleCatalogSourcesChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_firstHomeFrameLogged) {
        _firstHomeFrameLogged = true;
        DiagnosticLog.add(
          'startup home first frame hasCatalogSource=$_hasCatalogSource',
        );
        DiagnosticLog.viewTiming(
          surface: 'home_startup',
          state: 'first_frame',
          cacheStateBucket: _hasCatalogSource ? 'source_ready' : 'empty_source',
          mediaKind: 'mixed',
        );
      }
      if (mounted && AppState.preferencesReady.value && _hasCatalogSource) {
        _restoreHomeWarmSnapshot();
        unawaited(_warmStartThenLoadHome());
      }
    });
  }

  @override
  void dispose() {
    AppState.shellTab.removeListener(_handleShellTabChanged);
    AppState.preferencesReady.removeListener(_handleCatalogSourcesChanged);
    AppState.defaultCatalogEnabled.removeListener(_handleCatalogSourcesChanged);
    AppState.userAddons.removeListener(_handleCatalogSourcesChanged);
    AppState.personalServerConnections.removeListener(
      _handleCatalogSourcesChanged,
    );
    _api.close();
    super.dispose();
  }

  bool get _hasCatalogSource =>
      AppState.preferencesReady.value && AppState.hasCatalogSource;
  bool get _hasHomeContent => _hasCatalogSource;
  bool get _isHomeTabVisible => AppState.shellTab.value == 0;

  void _maybeShowMatureContentChoice() {
    if (!mounted ||
        !_isHomeTabVisible ||
        _loading ||
        !_hasCatalogSource ||
        _matureContentChoiceScheduled ||
        AppState.matureContentChoiceSeen.value) {
      return;
    }
    if (!AppState.tryBeginMatureContentChoice()) return;
    _matureContentChoiceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_isHomeTabVisible ||
          _loading ||
          !_hasCatalogSource ||
          AppState.matureContentChoiceSeen.value) {
        _matureContentChoiceScheduled = false;
        AppState.finishMatureContentChoice();
        return;
      }
      unawaited(_showMatureContentChoice());
    });
  }

  Future<void> _showMatureContentChoice() async {
    try {
      DiagnosticLog.screen(context, 'Home mature content choice');
      final showMatureContent = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Show 18+ titles?'),
              content: const Text(
                'Juicr can keep mature titles hidden, or include them in Home and Discovery.\n\n'
                'You can change this anytime in Settings General.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Keep hidden'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Show 18+'),
                ),
              ],
            ),
          );
        },
      );
      if (showMatureContent == null) {
        DiagnosticLog.add('home mature content choice closed without choice');
        return;
      }
      AppState.setShowMatureContent(showMatureContent);
      DiagnosticLog.add(
        'home mature content choice ${showMatureContent ? 'show' : 'hide'}',
      );
    } finally {
      _matureContentChoiceScheduled = false;
      AppState.finishMatureContentChoice();
    }
  }

  void _handleShellTabChanged() {
    if (!_isHomeTabVisible) return;
    _maybeShowMatureContentChoice();
  }

  void _handleCatalogSourcesChanged() {
    if (!_hasHomeContent) {
      _loadGeneration += 1;
      setState(() {
        _newMovies = const <CatalogItem>[];
        _newSeries = const <CatalogItem>[];
        _topMovies = const <CatalogItem>[];
        _topSeries = const <CatalogItem>[];
        _animationPicks = const <CatalogItem>[];
        _upcomingPicks = const <CatalogItem>[];
        _heroEditorialItems = const <CatalogItem>[];
        _topSignalRemoteItems = const <CatalogItem>[];
        _todaySignalRemoteItems = const <CatalogItem>[];
        _juicrTopSignalRemoteItems = const <CatalogItem>[];
        _heroTrailerAvailability.clear();
        _heroTrailerAvailabilityInFlight.clear();
        _heroTrailerAvailabilityPending.clear();
        _heroTrailerAvailabilityAttempts.clear();
        _remoteEditorial = null;
        _loading = false;
      });
      return;
    }
    _loadGeneration += 1;
    setState(() {
      _newMovies = const <CatalogItem>[];
      _newSeries = const <CatalogItem>[];
      _topMovies = const <CatalogItem>[];
      _topSeries = const <CatalogItem>[];
      _animationPicks = const <CatalogItem>[];
      _upcomingPicks = const <CatalogItem>[];
      _heroEditorialItems = const <CatalogItem>[];
      _topSignalRemoteItems = const <CatalogItem>[];
      _todaySignalRemoteItems = const <CatalogItem>[];
      _juicrTopSignalRemoteItems = const <CatalogItem>[];
      _heroTrailerAvailability.clear();
      _heroTrailerAvailabilityInFlight.clear();
      _heroTrailerAvailabilityPending.clear();
      _heroTrailerAvailabilityAttempts.clear();
      _remoteEditorial = null;
      _loading = true;
    });
    _restoreHomeWarmSnapshot();
    unawaited(_warmStartThenLoadHome());
  }

  Future<void> _warmStartThenLoadHome() async {
    if (!mounted) return;
    DiagnosticLog.add('home client fallback skipped reason=server_source_only');
    unawaited(_loadHomeRails());
  }

  Future<void> _loadHomeRails() async {
    final loadStopwatch = Stopwatch()..start();
    final generation = ++_loadGeneration;
    if (!_hasCatalogSource) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
      return;
    }
    DiagnosticLog.viewTiming(
      surface: 'home',
      state: 'skeleton_visible',
      mediaKind: 'mixed',
      itemCount: 0,
    );
    try {
      final remoteEditorial = AppState.defaultCatalogEnabled.value
          ? await _api.homeEditorial()
          : null;
      final effectiveEditorial = remoteEditorial ?? _remoteEditorial;
      if (!mounted || generation != _loadGeneration) return;
      if (AppState.defaultCatalogEnabled.value && effectiveEditorial == null) {
        setState(() {
          _newMovies = const <CatalogItem>[];
          _newSeries = const <CatalogItem>[];
          _topMovies = const <CatalogItem>[];
          _topSeries = const <CatalogItem>[];
          _animationPicks = const <CatalogItem>[];
          _upcomingPicks = const <CatalogItem>[];
          _heroEditorialItems = const <CatalogItem>[];
          _topSignalRemoteItems = const <CatalogItem>[];
          _todaySignalRemoteItems = const <CatalogItem>[];
          _juicrTopSignalRemoteItems = const <CatalogItem>[];
          _remoteEditorial = null;
          _loading = false;
        });
        DiagnosticLog.add(
          'home sync failed reason=editorial_unavailable elapsedMs=${loadStopwatch.elapsedMilliseconds}',
        );
        DiagnosticLog.viewTiming(
          surface: 'home',
          state: 'interaction_ready',
          elapsed: loadStopwatch.elapsed,
          mediaKind: 'mixed',
          cacheStateBucket: 'server_editorial_unavailable',
          itemCount: 0,
        );
        if (!_firstHomeReadyLogged) {
          _firstHomeReadyLogged = true;
          DiagnosticLog.add(
            'startup home sync failed elapsedMs=${loadStopwatch.elapsedMilliseconds}',
          );
          DiagnosticLog.viewTiming(
            surface: 'home_startup',
            state: 'interaction_ready',
            elapsed: loadStopwatch.elapsed,
            cacheStateBucket: 'server_editorial_unavailable',
            mediaKind: 'mixed',
            itemCount: 0,
          );
        }
        return;
      }
      final results = await Future.wait([
        _api.catalog(type: MediaType.movie, sort: CatalogSort.year, skip: 0),
        _api.catalog(type: MediaType.series, sort: CatalogSort.year, skip: 0),
        _api.catalog(type: MediaType.animation, sort: CatalogSort.top, skip: 0),
        _api.catalog(type: MediaType.movie, sort: CatalogSort.top, skip: 0),
        _api.catalog(type: MediaType.series, sort: CatalogSort.top, skip: 0),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final newMovies = results[0] as StreamCatalogResult;
      final newSeries = results[1] as StreamCatalogResult;
      final animationPicks = results[2] as StreamCatalogResult;
      final topMovies = results[3] as StreamCatalogResult;
      final topSeries = results[4] as StreamCatalogResult;
      const moreAnimationPicks = StreamCatalogResult(items: <CatalogItem>[]);
      const moreNewMovies = StreamCatalogResult(items: <CatalogItem>[]);
      const moreTopMovies = StreamCatalogResult(items: <CatalogItem>[]);
      const upcomingMovies = StreamCatalogResult(items: <CatalogItem>[]);
      final previousEditorialEdition = _remoteEditorial?.editionId ?? '';
      final nextEditorialEdition = effectiveEditorial?.editionId ?? '';
      final editorialEditionChanged =
          nextEditorialEdition.isNotEmpty &&
          previousEditorialEdition != nextEditorialEdition;
      final movieNewPool = _availableHomeItems(
        _dedupeItems([...newMovies.items, ...moreNewMovies.items]),
      );
      final movieTopPool = _availableHomeItems(
        _dedupeItems([...topMovies.items, ...moreTopMovies.items]),
      );
      final seriesNewPool = _availableHomeItems(newSeries.items);
      final seriesTopPool = _availableHomeItems(topSeries.items);
      final animationPool = _availableHomeItems(
        _dedupeItems([...animationPicks.items, ...moreAnimationPicks.items]),
      );
      final animationHomePool = _dedupeItems([
        ...animationPool,
        ..._animationCompatibleHomeItems([...seriesNewPool, ...seriesTopPool]),
      ]);
      final upcomingPool = _upcomingThisYearItems(
        movies: _dedupeItems(upcomingMovies.items),
      );
      final heroEditorial = _editorialOrNull(
        AppState.defaultCatalogEnabled.value ? effectiveEditorial?.hero : null,
        _dailyHeroEditorial(),
      );
      final initialHeroItems = await _loadCuratedHeroItems(heroEditorial);
      if (!mounted || generation != _loadGeneration) return;
      final totalVisible =
          movieNewPool.take(24).length +
          seriesNewPool.take(24).length +
          animationHomePool.take(24).length +
          movieTopPool.take(24).length +
          seriesTopPool.take(24).length +
          upcomingPool.length +
          initialHeroItems.length;
      setState(() {
        _newMovies = movieNewPool.take(24).toList(growable: false);
        _newSeries = seriesNewPool.take(24).toList(growable: false);
        _animationPicks = animationHomePool.take(24).toList(growable: false);
        _topMovies = movieTopPool.take(24).toList(growable: false);
        _topSeries = seriesTopPool.take(24).toList(growable: false);
        _upcomingPicks = upcomingPool;
        if (editorialEditionChanged) {
          _topSignalRemoteItems = const <CatalogItem>[];
          _todaySignalRemoteItems = const <CatalogItem>[];
          _juicrTopSignalRemoteItems = const <CatalogItem>[];
          _heroTrailerAvailability.clear();
          _heroTrailerAvailabilityInFlight.clear();
          _heroTrailerAvailabilityPending.clear();
          _heroTrailerAvailabilityAttempts.clear();
        }
        _heroEditorialItems = initialHeroItems;
        _remoteEditorial = AppState.defaultCatalogEnabled.value
            ? effectiveEditorial
            : null;
        _loading = false;
        DiagnosticLog.viewTiming(
          surface: 'home',
          state: 'interaction_ready',
          elapsed: loadStopwatch.elapsed,
          mediaKind: 'mixed',
          cacheStateBucket: 'network_or_unknown',
          itemCount: totalVisible,
        );
      });
      DiagnosticLog.add(
        'home rail pools loaded movieNew=${_newMovies.length} movieTop=${_topMovies.length} seriesNew=${_newSeries.length} seriesTop=${_topSeries.length} animation=${_animationPicks.length}',
      );
      _saveHomeWarmSnapshot(editorial: effectiveEditorial);
      if (editorialEditionChanged) {
        DiagnosticLog.add(
          'home editorial edition changed previous=${previousEditorialEdition.isEmpty ? "none" : previousEditorialEdition} next=$nextEditorialEdition resetDerived=true',
        );
      }
      _warmHeroTrailerAvailability([
        ...initialHeroItems.take(8),
        ..._newMovies.take(3),
        ..._topMovies.take(3),
        ..._newSeries.take(3),
        ..._topSeries.take(3),
        ..._animationPicks.take(3),
      ]);
      _warmUpcomingReleaseDates(_upcomingPicks.take(40));
      DiagnosticLog.add(
        'home client fallback save skipped reason=server_source_only',
      );
      if (!_firstHomeReadyLogged) {
        _firstHomeReadyLogged = true;
        DiagnosticLog.add(
          'startup home data ready elapsedMs=${loadStopwatch.elapsedMilliseconds} itemCount=$totalVisible',
        );
        DiagnosticLog.viewTiming(
          surface: 'home_startup',
          state: 'interaction_ready',
          elapsed: loadStopwatch.elapsed,
          cacheStateBucket: 'network_or_unknown',
          mediaKind: 'mixed',
          itemCount: totalVisible,
        );
      }
      _maybeShowMatureContentChoice();
      final topSignalEditorial = _editorialOrNull(
        AppState.defaultCatalogEnabled.value
            ? effectiveEditorial?.topSignal
            : null,
        _weeklyTopSignalEditorial(),
      );
      final todaySignalEditorial = _editorialOrNull(
        AppState.defaultCatalogEnabled.value
            ? effectiveEditorial?.todaySignal
            : null,
        _dailyTopSignalEditorial(),
      );
      final juicrTopSignalEditorial = _editorialOrNull(
        AppState.defaultCatalogEnabled.value
            ? effectiveEditorial?.juicrTopSignal
            : null,
        _juicrTopSignalEditorial(),
      );
      unawaited(
        _loadRemoteTopSignalItems(topSignalEditorial, limit: 20).then((
          rankedItems,
        ) {
          if (!mounted || generation != _loadGeneration) return;
          setState(() {
            _topSignalRemoteItems = _mergeHomeRailRefreshItems(
              _topSignalRemoteItems,
              rankedItems,
            );
          });
        }),
      );
      unawaited(
        _loadRemoteTopSignalItems(todaySignalEditorial, limit: 20).then((
          rankedItems,
        ) {
          if (!mounted || generation != _loadGeneration) return;
          setState(() {
            _todaySignalRemoteItems = _mergeHomeRailRefreshItems(
              _todaySignalRemoteItems,
              rankedItems,
            );
          });
        }),
      );
      unawaited(
        _loadRemoteTopSignalItems(juicrTopSignalEditorial, limit: 10).then((
          rankedItems,
        ) {
          if (!mounted || generation != _loadGeneration) return;
          setState(() {
            _juicrTopSignalRemoteItems = _mergeHomeRailRefreshItems(
              _juicrTopSignalRemoteItems,
              rankedItems,
            );
          });
        }),
      );
      unawaited(
        _loadHomeSupplementalRails(
          generation: generation,
          newMovies: newMovies,
          newSeries: newSeries,
          animationPicks: animationPicks,
          topMovies: topMovies,
          topSeries: topSeries,
          effectiveEditorial: AppState.defaultCatalogEnabled.value
              ? effectiveEditorial
              : null,
        ),
      );
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
        _maybeShowMatureContentChoice();
      }
    }
  }

  Future<void> _loadHomeSupplementalRails({
    required int generation,
    required StreamCatalogResult newMovies,
    required StreamCatalogResult newSeries,
    required StreamCatalogResult animationPicks,
    required StreamCatalogResult topMovies,
    required StreamCatalogResult topSeries,
    required HomeEditorialEdition? effectiveEditorial,
  }) async {
    final loadStopwatch = Stopwatch()..start();
    try {
      final results = await Future.wait([
        _api.catalog(
          type: MediaType.animation,
          sort: CatalogSort.top,
          skip: StreamApi.pageSize,
        ),
        _api.catalog(
          type: MediaType.movie,
          sort: CatalogSort.year,
          skip: StreamApi.pageSize,
        ),
        _api.catalog(
          type: MediaType.movie,
          sort: CatalogSort.top,
          skip: StreamApi.pageSize,
        ),
        _loadUpcomingThisYearMovieCatalog(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final moreAnimationPicks = results[0] as StreamCatalogResult;
      final moreNewMovies = results[1] as StreamCatalogResult;
      final moreTopMovies = results[2] as StreamCatalogResult;
      final upcomingMovies = results[3] as StreamCatalogResult;
      final movieNewPool = _availableHomeItems(
        _dedupeItems([...newMovies.items, ...moreNewMovies.items]),
      );
      final movieTopPool = _availableHomeItems(
        _dedupeItems([...topMovies.items, ...moreTopMovies.items]),
      );
      final seriesNewPool = _availableHomeItems(newSeries.items);
      final seriesTopPool = _availableHomeItems(topSeries.items);
      final animationPool = _availableHomeItems(
        _dedupeItems([...animationPicks.items, ...moreAnimationPicks.items]),
      );
      final animationHomePool = _dedupeItems([
        ...animationPool,
        ..._animationCompatibleHomeItems([...seriesNewPool, ...seriesTopPool]),
      ]);
      final upcomingPool = _upcomingThisYearItems(
        movies: _dedupeItems(upcomingMovies.items),
      );
      setState(() {
        _newMovies = movieNewPool.take(24).toList(growable: false);
        _newSeries = seriesNewPool.take(24).toList(growable: false);
        _animationPicks = animationHomePool.take(24).toList(growable: false);
        _topMovies = movieTopPool.take(24).toList(growable: false);
        _topSeries = seriesTopPool.take(24).toList(growable: false);
        _upcomingPicks = upcomingPool;
      });
      DiagnosticLog.add(
        'home supplemental rails loaded elapsedMs=${loadStopwatch.elapsedMilliseconds} movieNew=${_newMovies.length} movieTop=${_topMovies.length} animation=${_animationPicks.length} upcoming=${_upcomingPicks.length}',
      );
      _saveHomeWarmSnapshot(editorial: effectiveEditorial);
      _warmUpcomingReleaseDates(_upcomingPicks.take(40));
      DiagnosticLog.add('home local content cache skipped reason=server_only');
    } catch (error) {
      DiagnosticLog.add('home supplemental rails skipped error=$error');
    }
  }

  Future<StreamCatalogResult> _loadUpcomingThisYearMovieCatalog() async {
    final currentYear = DateTime.now().year.toString();
    final items = <CatalogItem>[];
    var skip = 0;
    var hasMore = true;
    for (var page = 0; page < 8 && hasMore; page += 1) {
      final result = await _api.catalog(
        type: MediaType.movie,
        sort: CatalogSort.upcoming,
        year: currentYear,
        skip: skip,
        preferDefaultCatalog: true,
      );
      items.addAll(result.items);
      final stride = result.skipDelta ?? StreamApi.pageSize;
      hasMore = result.hasMore ?? result.items.isNotEmpty;
      if (result.items.isEmpty || stride <= 0) break;
      skip += stride;
    }
    return StreamCatalogResult(items: _dedupeItems(items), hasMore: hasMore);
  }

  void _recordHomeRailCounts({
    required String movieTitle,
    required int movieCount,
    required String seriesTitle,
    required int seriesCount,
    required String animationTitle,
    required int animationCount,
  }) {
    final signature =
        'movie=$movieCount:$movieTitle|series=$seriesCount:$seriesTitle|animation=$animationCount:$animationTitle';
    if (_lastHomeRailCountLog == signature) return;
    _lastHomeRailCountLog = signature;
    DiagnosticLog.add(
      'home rail counts movie=$movieCount title="$movieTitle" series=$seriesCount title="$seriesTitle" animation=$animationCount title="$animationTitle"',
    );
  }

  Future<List<CatalogItem>> _loadCuratedHeroItems(_EditorialRail? rail) async {
    if (rail == null ||
        rail.title.isEmpty ||
        (rail.genres.isEmpty &&
            rail.query.isEmpty &&
            !_isInTheatersEditorial(rail))) {
      DiagnosticLog.add(
        'home hero editorial skipped reason=missing_rail hasTitle=${rail?.title.isNotEmpty ?? false} genreCount=${rail?.genres.length ?? 0} hasQuery=${rail?.query.isNotEmpty ?? false}',
      );
      return const <CatalogItem>[];
    }
    if (_isInTheatersEditorial(rail) &&
        rail.curationKind.trim().toLowerCase() != 'tmdb_daily_genre') {
      return _loadInTheatersHeroItems(rail);
    }
    final types = rail.types.isEmpty
        ? const [MediaType.movie, MediaType.series, MediaType.animation]
        : rail.types;
    final genre = rail.genres.isEmpty
        ? 'All genres'
        : _displayGenre(rail.genres.first);
    final perType = rail.perType.clamp(1, 12);
    DiagnosticLog.add(
      'home hero editorial start genre=$genre genreCount=${rail.genres.length} types=${types.map((type) => type.compatTypeValue).join("|")} sort=${rail.sort.id} perType=$perType requireGenre=${rail.requireGenreMatch} intent=${rail.intent} releaseWindow=${rail.releaseWindow} theme=${rail.theme} seasonalWindow=${rail.seasonalWindow} hasQuery=${rail.query.isNotEmpty}',
    );
    final buckets = await Future.wait<List<CatalogItem>>([
      for (final type in types)
        _loadCuratedHeroBucket(type, rail, genre, perType),
    ]);
    final interleaved = _interleaveBuckets(
      buckets,
    ).take(12).toList(growable: false);
    DiagnosticLog.add(
      'home hero editorial result bucketCounts=${buckets.map((bucket) => bucket.length).join("|")} final=${interleaved.length}',
    );
    return interleaved;
  }

  Future<List<CatalogItem>> _loadInTheatersHeroItems(
    _EditorialRail rail,
  ) async {
    final gathered = <CatalogItem>[];
    final seen = <String>{};
    final maxPages = _curatedHeroMaxPages(rail);
    var skip = 0;
    for (var page = 0; page < maxPages; page += 1) {
      try {
        final result = await _api.catalog(
          type: MediaType.movie,
          sort: CatalogSort.nowPlaying,
          skip: skip,
          genre: 'All genres',
          preferDefaultCatalog: true,
        );
        final before = gathered.length;
        for (final item in result.items) {
          if (!_homeItemMatchesInTheaters(item, rail)) continue;
          if (seen.add(_homeContentKey(item))) gathered.add(item);
        }
        DiagnosticLog.add(
          'home hero in_theaters page sort=${CatalogSort.nowPlaying.id} skip=$skip page=${page + 1}/$maxPages fetched=${result.items.length} added=${gathered.length - before} gathered=${gathered.length} hasMore=${result.hasMore ?? false}',
        );
        if (gathered.length >= _targetHeroItems) {
          break;
        }
        final delta = result.skipDelta ?? result.items.length;
        if (result.items.isEmpty || delta <= 0 || result.hasMore == false) {
          break;
        }
        skip += delta;
      } catch (_) {
        DiagnosticLog.add(
          'home hero in_theaters error sort=${CatalogSort.nowPlaying.id} skip=$skip gathered=${gathered.length}',
        );
        break;
      }
    }
    final items = gathered.take(_targetHeroItems).toList(growable: false);
    DiagnosticLog.add(
      'home hero in_theaters result gathered=${gathered.length} final=${items.length}',
    );
    return items;
  }

  Future<List<CatalogItem>> _loadCuratedHeroBucket(
    MediaType type,
    _EditorialRail rail,
    String genre,
    int perType,
  ) async {
    final gathered = <CatalogItem>[];
    final seen = <String>{};
    final maxPages = _curatedHeroMaxPages(rail);
    final allowBoundedPagination = maxPages > 1;
    for (final sort in _curatedSortFallbacks(rail.sort)) {
      var skip = 0;
      for (var page = 0; page < maxPages; page += 1) {
        try {
          final result = await _api.catalog(
            type: type,
            sort: sort,
            skip: skip,
            genre: genre,
            search: rail.query,
            deepSearch: rail.query.isNotEmpty,
            preferDefaultCatalog: true,
          );
          final before = gathered.length;
          for (final item in result.items) {
            if (!_homeItemMatchesEditorialIntent(item, rail)) continue;
            if (seen.add(_itemKey(item))) gathered.add(item);
          }
          final isDailyGenre =
              rail.curationKind.trim().toLowerCase() == 'tmdb_daily_genre';
          final matches = isDailyGenre
              ? gathered.take(perType).toList(growable: false)
              : _bestEditorialMatches(
                  gathered,
                  rail,
                  perType,
                  allowUnknownGenre: true,
                );
          DiagnosticLog.add(
            'home hero bucket page type=${type.compatTypeValue} sort=${sort.id} skip=$skip page=${page + 1}/$maxPages fetched=${result.items.length} added=${gathered.length - before} gathered=${gathered.length} matches=${matches.length} hasMore=${result.hasMore ?? false}',
          );
          if (matches.length >= perType) return matches;
          if (rail.pageOneOnly && !allowBoundedPagination) break;
          final delta = result.skipDelta ?? result.items.length;
          if (result.items.isEmpty || delta <= 0 || result.hasMore == false) {
            DiagnosticLog.add(
              'home hero bucket stop type=${type.compatTypeValue} sort=${sort.id} reason=${result.items.isEmpty
                  ? "empty"
                  : delta <= 0
                  ? "no_delta"
                  : "no_more"} gathered=${gathered.length} matches=${matches.length}',
            );
            break;
          }
          skip += delta;
        } catch (_) {
          DiagnosticLog.add(
            'home hero bucket error type=${type.compatTypeValue} sort=${sort.id} skip=$skip gathered=${gathered.length}',
          );
          break;
        }
      }
      if (rail.pageOneOnly && !allowBoundedPagination) break;
    }
    final isDailyGenre =
        rail.curationKind.trim().toLowerCase() == 'tmdb_daily_genre';
    final matches = isDailyGenre
        ? gathered.take(perType).toList(growable: false)
        : _bestEditorialMatches(
            gathered,
            rail,
            perType,
            allowUnknownGenre: true,
          );
    DiagnosticLog.add(
      'home hero bucket result type=${type.compatTypeValue} gathered=${gathered.length} matches=${matches.length}',
    );
    return matches;
  }

  bool _restoreHomeWarmSnapshot() {
    if (!mounted || !_hasCatalogSource) return false;
    final prefs = AppState.prefs;
    if (prefs == null) return false;
    final raw = prefs.getString(_homeWarmSnapshotKey);
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      final editorialRaw =
          decoded['editorial'] ??
          _safeJsonDecodeMap(prefs.getString(_homeEditorialCacheKey));
      final editorial = editorialRaw is Map<String, dynamic>
          ? HomeEditorialEdition.fromJson(editorialRaw)
          : null;
      final newMovies = _catalogSnapshotList(decoded['newMovies']);
      final newSeries = _catalogSnapshotList(decoded['newSeries']);
      final animation = _catalogSnapshotList(decoded['animation']);
      final topMovies = _catalogSnapshotList(decoded['topMovies']);
      final topSeries = _catalogSnapshotList(decoded['topSeries']);
      final upcoming = _catalogSnapshotList(decoded['upcoming']);
      final hero = _catalogSnapshotList(decoded['hero']);
      final topSignal = _catalogSnapshotList(decoded['topSignal']);
      final todaySignal = _catalogSnapshotList(decoded['todaySignal']);
      final juicrTopSignal = _catalogSnapshotList(decoded['juicrTopSignal']);
      final itemCount =
          newMovies.length +
          newSeries.length +
          animation.length +
          topMovies.length +
          topSeries.length +
          upcoming.length +
          hero.length;
      if (itemCount <= 0 && editorial == null) return false;
      setState(() {
        _newMovies = newMovies;
        _newSeries = newSeries;
        _animationPicks = animation;
        _topMovies = topMovies;
        _topSeries = topSeries;
        _upcomingPicks = upcoming;
        _heroEditorialItems = hero;
        _topSignalRemoteItems = topSignal;
        _todaySignalRemoteItems = todaySignal;
        _juicrTopSignalRemoteItems = juicrTopSignal;
        _remoteEditorial = editorial;
        _loading = false;
      });
      DiagnosticLog.add(
        'home warm snapshot restored source=local_snapshot itemCount=$itemCount hasEditorial=${editorial != null}',
      );
      DiagnosticLog.viewTiming(
        surface: 'home',
        state: 'interaction_ready',
        cacheStateBucket: 'local_snapshot',
        mediaKind: 'mixed',
        itemCount: itemCount,
      );
      return true;
    } catch (error) {
      DiagnosticLog.add(
        'home warm snapshot skipped reason=decode_failed error=${error.runtimeType}',
      );
      return false;
    }
  }

  void _saveHomeWarmSnapshot({required HomeEditorialEdition? editorial}) {
    final prefs = AppState.prefs;
    if (prefs == null || !_hasCatalogSource) return;
    final itemCount =
        _newMovies.length +
        _newSeries.length +
        _animationPicks.length +
        _topMovies.length +
        _topSeries.length +
        _upcomingPicks.length +
        _heroEditorialItems.length;
    if (itemCount <= 0 && editorial == null) return;
    Map<String, dynamic>? editorialJson;
    if (editorial != null) {
      editorialJson = editorial.toJson();
    }
    final payload = <String, dynamic>{
      'version': 1,
      'savedAt': DateTime.now().toIso8601String(),
      if (editorialJson != null) 'editorial': editorialJson,
      'newMovies': _safePublicSnapshotItems(_newMovies),
      'newSeries': _safePublicSnapshotItems(_newSeries),
      'animation': _safePublicSnapshotItems(_animationPicks),
      'topMovies': _safePublicSnapshotItems(_topMovies),
      'topSeries': _safePublicSnapshotItems(_topSeries),
      'upcoming': _safePublicSnapshotItems(_upcomingPicks),
      'hero': _safePublicSnapshotItems(_heroEditorialItems),
      'topSignal': _safePublicSnapshotItems(_topSignalRemoteItems),
      'todaySignal': _safePublicSnapshotItems(_todaySignalRemoteItems),
      'juicrTopSignal': _safePublicSnapshotItems(_juicrTopSignalRemoteItems),
    };
    unawaited(prefs.setString(_homeWarmSnapshotKey, jsonEncode(payload)));
    if (editorialJson != null) {
      unawaited(
        prefs.setString(_homeEditorialCacheKey, jsonEncode(editorialJson)),
      );
    }
  }

  int _curatedHeroMaxPages(_EditorialRail rail) {
    final curationKind = rail.curationKind.trim().toLowerCase();
    if (curationKind == 'tmdb_daily_genre') return 1;
    if (_isSourceBoundEditorial(rail)) {
      return 5;
    }
    return rail.pageOneOnly ? 1 : 3;
  }

  Future<List<CatalogItem>> _loadRemoteTopSignalItems(
    _EditorialRail? editorial, {
    int limit = 20,
  }) async {
    if (editorial == null || editorial.items.isEmpty) {
      DiagnosticLog.add(
        'home top signal hydrate requested=0 matched=0 reason=no_remote_items',
      );
      return const <CatalogItem>[];
    }
    final ranked = <CatalogItem>[];
    final seen = <String>{};
    for (final signal in editorial.items.take(limit)) {
      final types = signal.type == null
          ? const [MediaType.movie, MediaType.series, MediaType.animation]
          : [signal.type!];
      for (final type in types) {
        try {
          CatalogItem? match;
          if (signal.tmdbId != null) {
            final details = await _api.meta(
              CatalogItem(
                type: type,
                id: 'tmdb:${signal.tmdbId}',
                name: signal.title,
                tmdbId: signal.tmdbId,
                year: signal.year.isEmpty ? null : signal.year,
              ),
            );
            if (_itemMatchesTrendSignal(details.item, signal)) {
              match = details.item;
            }
          }
          if (match != null && !_hasHomePoster(match)) {
            final richerMatch = await _findHomeTopSignalCatalogMatch(
              signal,
              type,
            );
            if (richerMatch != null) {
              match = match.merge(richerMatch);
            }
          }
          if (match == null) {
            match = await _findHomeTopSignalCatalogMatch(signal, type);
          }
          if (match == null || !_hasHomePoster(match)) continue;
          final key = _itemKey(match);
          if (seen.add(key)) ranked.add(match);
          break;
        } catch (_) {
          break;
        }
      }
    }
    DiagnosticLog.add(
      'home top signal hydrate requested=${editorial.items.length} matched=${ranked.length}',
    );
    return ranked.toList(growable: false);
  }

  Future<CatalogItem?> _findHomeTopSignalCatalogMatch(
    HomeEditorialTrendItem signal,
    MediaType type,
  ) async {
    final result = await _api.catalog(
      type: type,
      sort: CatalogSort.top,
      skip: 0,
      search: signal.title,
      deepSearch: true,
      preferDefaultCatalog: true,
    );
    for (final item in result.items) {
      if (_itemMatchesTrendSignal(item, signal) && _hasHomePoster(item)) {
        return item;
      }
    }
    for (final item in result.items) {
      if (_itemMatchesTrendSignal(item, signal)) return item;
    }
    return null;
  }

  void _openDetails(CatalogItem item) {
    unawaited(JuicrAdPolicy.maybeShowInterstitial(reason: 'home_title_open'));
    Navigator.of(
      context,
    ).push(AppPageRoute<void>(builder: (_) => DetailsPage(item: item)));
  }

  Future<void> _openTrailer(CatalogItem item) {
    return Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => DetailsPage(item: item, autoOpenTrailer: true),
      ),
    );
  }

  void _warmHeroTrailerAvailability(Iterable<CatalogItem> items) {
    var queued = 0;
    for (final item in items) {
      if (queued >= 8) break;
      if (item.type.isLive || item.isPersonalServerItem) continue;
      final key = _heroTrailerAvailabilityKey(item);
      if (_heroTrailerAvailability.containsKey(key) ||
          _heroTrailerAvailabilityInFlight.contains(key) ||
          _heroTrailerAvailabilityPending.containsKey(key)) {
        continue;
      }
      _heroTrailerAvailabilityPending[key] = item;
      queued += 1;
    }
    _startHeroTrailerAvailabilityWorker();
  }

  void _warmUpcomingReleaseDates(Iterable<CatalogItem> items) {
    final candidates = items
        .where((item) => item.isUpcoming && (item.releaseDate ?? '').isEmpty)
        .take(40)
        .toList(growable: false);
    if (candidates.isEmpty) return;
    unawaited(
      _hydrateUpcomingReleaseDates(candidates).then((hydratedItems) {
        if (!mounted || hydratedItems.isEmpty) return;
        setState(() {
          _upcomingPicks = _mergeHydratedUpcomingItems(
            _upcomingPicks,
            hydratedItems,
          );
        });
      }),
    );
  }

  Future<List<CatalogItem>> _hydrateUpcomingReleaseDates(
    List<CatalogItem> items,
  ) async {
    final hydrated = <CatalogItem>[];
    for (final item in items) {
      try {
        final details = await _api
            .meta(item)
            .timeout(const Duration(seconds: 5));
        final merged = item.merge(details.item);
        if ((merged.releaseDate ?? '').isNotEmpty) hydrated.add(merged);
      } catch (_) {
        // Metadata hydration is best-effort; the badge can still show TBA.
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return hydrated;
  }

  void _startHeroTrailerAvailabilityWorker() {
    if (_heroTrailerAvailabilityWorkerRunning ||
        _heroTrailerAvailabilityPending.isEmpty) {
      return;
    }
    _heroTrailerAvailabilityWorkerRunning = true;
    unawaited(_runHeroTrailerAvailabilityWorker());
  }

  Future<void> _runHeroTrailerAvailabilityWorker() async {
    while (mounted && _heroTrailerAvailabilityPending.isNotEmpty) {
      final entry = _heroTrailerAvailabilityPending.entries.first;
      _heroTrailerAvailabilityPending.remove(entry.key);
      final key = entry.key;
      final item = entry.value;
      if (_heroTrailerAvailability.containsKey(key)) continue;
      _heroTrailerAvailabilityInFlight.add(key);
      var shouldRetry = false;
      try {
        final trailers = await _api
            .resolveTrailers(item)
            .timeout(const Duration(seconds: 6));
        if (!mounted) return;
        setState(() {
          if (trailers.isNotEmpty) {
            _heroTrailerAvailability[key] = true;
            _heroTrailerAvailabilityAttempts.remove(key);
          } else {
            _heroTrailerAvailability.remove(key);
          }
          _heroTrailerAvailabilityInFlight.remove(key);
        });
      } catch (error) {
        if (!mounted) return;
        final attempts = (_heroTrailerAvailabilityAttempts[key] ?? 0) + 1;
        _heroTrailerAvailabilityAttempts[key] = attempts;
        shouldRetry = attempts < 2;
        setState(() {
          _heroTrailerAvailabilityInFlight.remove(key);
        });
        DiagnosticLog.add(
          'home trailer availability retryable key=$key attempt=$attempts error=${_safeHomeTrailerErrorLabel(error)}',
        );
      }
      if (shouldRetry) {
        await Future<void>.delayed(const Duration(seconds: 8));
        if (mounted && !_heroTrailerAvailability.containsKey(key)) {
          _heroTrailerAvailabilityPending[key] = item;
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 2500));
      }
    }
    _heroTrailerAvailabilityWorkerRunning = false;
    if (mounted && _heroTrailerAvailabilityPending.isNotEmpty) {
      _startHeroTrailerAvailabilityWorker();
    }
  }

  void _openDiscovery() {
    AppState.shellTab.value = 1;
  }

  void _openDiscoveryForShelf({
    required _EditorialRail editorial,
    required List<CatalogItem> items,
    String? genreOverride,
  }) {
    if (editorial.isRanked) {
      final isUpcomingShelf =
          editorial.title.trim().toLowerCase() == 'upcoming this year';
      _openCuratedShelf(
        title: editorial.title,
        subtitle: editorial.sectionSubtitle,
        items: items,
        showRankPills: !isUpcomingShelf,
      );
      return;
    }
    final type = _discoveryTypeFor(editorial, items);
    if (type == null) {
      _openCuratedShelf(
        title: editorial.title,
        subtitle: editorial.sectionSubtitle,
        items: items,
        showRankPills: editorial.isRanked,
      );
      return;
    }
    final genre = _discoveryGenreFor(
      editorial: editorial,
      items: items,
      genreOverride: genreOverride,
    );
    AppState.openDiscovery(type: type, sort: editorial.sort, genre: genre);
  }

  MediaType? _discoveryTypeFor(
    _EditorialRail editorial,
    List<CatalogItem> items,
  ) {
    if (editorial.types.length == 1) return editorial.types.first;
    if (editorial.types.length > 1) return null;
    final typeCounts = <MediaType, int>{};
    for (final item in items) {
      if (item.type.isLive) continue;
      typeCounts[item.type] = (typeCounts[item.type] ?? 0) + 1;
    }
    if (typeCounts.length == 1) return typeCounts.keys.first;
    return null;
  }

  String _discoveryGenreFor({
    required _EditorialRail editorial,
    required List<CatalogItem> items,
    String? genreOverride,
  }) {
    final rawGenre = genreOverride?.trim().isNotEmpty == true
        ? genreOverride!.trim()
        : editorial.genres.isNotEmpty
        ? editorial.genres.first
        : items
              .expand((item) => item.genres)
              .map((genre) => genre.trim())
              .firstWhere((genre) => genre.isNotEmpty, orElse: () => '');
    return _displayGenre(rawGenre);
  }

  void _openLibrary() {
    AppState.shellTab.value = 2;
  }

  void _openCuratedShelf({
    required String title,
    required String subtitle,
    required List<CatalogItem> items,
    bool showRankPills = false,
    bool externalTopSignal = false,
    bool insightsEnabled = false,
  }) {
    final shelfItems = _dedupeItems(
      items,
    ).where((item) => !item.type.isLive).toList(growable: false);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => _HomeShelfPage(
          title: title,
          items: shelfItems,
          showRankPills:
              showRankPills || _isTopTenShelfTitle(title.trim().toLowerCase()),
          externalTopSignal: externalTopSignal,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: SafeArea(
        left: !JuicrVisual.compactLandscape(context),
        child: ValueListenableBuilder<bool>(
          valueListenable: AppState.preferencesReady,
          builder: (context, preferencesReady, _) {
            if (!preferencesReady) return const _HomePageSkeleton();
            const insightsEnabled = false;
            return ValueListenableBuilder<Map<String, ContinueWatchingEntry>>(
              valueListenable: AppState.continueWatching,
              builder: (context, progress, _) {
                return ValueListenableBuilder<Map<String, CatalogItem>>(
                  valueListenable: AppState.library,
                  builder: (context, library, __) {
                    if (!_hasHomeContent) {
                      return const CatalogEmptyState(title: 'Home');
                    }
                    final continueItems = progress.values.toList()
                      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                    final visibleContinueItems = [
                      for (final entry in continueItems)
                        if (AppState.isDisplayableContinueEntry(entry)) entry,
                    ];
                    final continueKeys = {
                      for (final entry in continueItems) _itemKey(entry.item),
                    };
                    final heroEditorial = _editorialOrNull(
                      AppState.defaultCatalogEnabled.value
                          ? _remoteEditorial?.hero
                          : null,
                      _dailyHeroEditorial(),
                    );
                    final heroItems = _withoutContinueWatching(
                      _dedupeItems(_heroEditorialItems),
                      continueKeys,
                    );
                    final displayHeroEditorial =
                        heroEditorial ??
                        const _EditorialRail(title: '', subtitle: '');
                    final displayHeroItems = heroItems;
                    if (heroEditorial != null &&
                        displayHeroItems.length < _minimumServerHeroItems) {
                      DiagnosticLog.add(
                        'home hero editorial kept server scoped items=${displayHeroItems.length}',
                      );
                    }
                    final usedHomeKeys = <String>{
                      for (final item in displayHeroItems.take(8))
                        _homeUsedKey(item),
                    };
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _warmHeroTrailerAvailability(displayHeroItems.take(8));
                    });
                    final catalogPool = _dedupeItems([
                      ..._topSignalRemoteItems,
                      ..._todaySignalRemoteItems,
                      ..._juicrTopSignalRemoteItems,
                      ..._newMovies,
                      ..._newSeries,
                      ..._topMovies,
                      ..._topSeries,
                      ..._animationPicks,
                      if (insightsEnabled) ...library.values,
                    ]);
                    final topSignalEditorial = _editorialOrNull(
                      AppState.defaultCatalogEnabled.value
                          ? _remoteEditorial?.topSignal
                          : null,
                      _weeklyTopSignalEditorial(),
                    );
                    final rawTopSignalItems = _weeklyTopSignalItems(
                      catalogPool,
                      editorial: topSignalEditorial,
                      limit: 20,
                      library: library,
                      progress: progress,
                      completed: AppState.completedWatching.value,
                      searchHistory: AppState.searchHistory.value,
                      insightsEnabled: insightsEnabled,
                    );
                    final topSignalUsesRemote =
                        _remoteTopSignalItems(
                          catalogPool,
                          topSignalEditorial,
                        ).length >=
                        3;
                    final todaySignalEditorial = _editorialOrNull(
                      AppState.defaultCatalogEnabled.value
                          ? _remoteEditorial?.todaySignal
                          : null,
                      _dailyTopSignalEditorial(),
                    );
                    final rawTodaySignalItems = _weeklyTopSignalItems(
                      catalogPool,
                      editorial: todaySignalEditorial,
                      limit: 20,
                      library: library,
                      progress: progress,
                      completed: AppState.completedWatching.value,
                      searchHistory: AppState.searchHistory.value,
                      insightsEnabled: insightsEnabled,
                    );
                    final todaySignalUsesRemote =
                        _remoteTopSignalItems(
                          catalogPool,
                          todaySignalEditorial,
                        ).length >=
                        3;
                    final juicrTopSignalEditorial = _editorialOrNull(
                      AppState.defaultCatalogEnabled.value
                          ? _remoteEditorial?.juicrTopSignal
                          : null,
                      _juicrTopSignalEditorial(),
                    );
                    final rawJuicrTopSignalItems = _weeklyTopSignalItems(
                      catalogPool,
                      editorial: juicrTopSignalEditorial,
                      limit: 10,
                      library: library,
                      progress: progress,
                      completed: AppState.completedWatching.value,
                      searchHistory: AppState.searchHistory.value,
                      insightsEnabled: insightsEnabled,
                    );
                    final juicrTopSignalUsesRemote =
                        _remoteTopSignalItems(
                          catalogPool,
                          juicrTopSignalEditorial,
                        ).length >=
                        3;
                    const localTopSignalFallback = <CatalogItem>[];
                    final todaySignalItems = _backfilledSignalRailItems(
                      rawTodaySignalItems,
                      fallbackPool: localTopSignalFallback,
                      usedKeys: usedHomeKeys,
                      limit: 20,
                      preservePrimaryRank: todaySignalUsesRemote,
                    );
                    usedHomeKeys.addAll(
                      todaySignalItems.take(20).map(_homeUsedKey),
                    );
                    final topSignalItems = _backfilledSignalRailItems(
                      rawTopSignalItems,
                      fallbackPool: localTopSignalFallback,
                      usedKeys: usedHomeKeys,
                      limit: 20,
                      preservePrimaryRank: topSignalUsesRemote,
                    );
                    usedHomeKeys.addAll(
                      topSignalItems.take(20).map(_homeUsedKey),
                    );
                    final juicrTopSignalItems = _backfilledSignalRailItems(
                      rawJuicrTopSignalItems,
                      fallbackPool: localTopSignalFallback,
                      usedKeys: usedHomeKeys,
                      limit: 10,
                      preservePrimaryRank: juicrTopSignalUsesRemote,
                    );
                    usedHomeKeys.addAll(
                      juicrTopSignalItems.take(10).map(_homeUsedKey),
                    );
                    const savedEditorial = _EditorialRail(
                      title: 'Saved For Later',
                      subtitle: '',
                    );
                    const upcomingEditorial = _EditorialRail(
                      title: 'Upcoming This Year',
                      subtitle: '',
                      kind: 'ranked',
                      sort: CatalogSort.upcoming,
                      types: [MediaType.movie],
                      perType: 20,
                    );
                    final upcomingItems = _withoutContinueWatching(
                      _upcomingPicks,
                      continueKeys,
                    ).toList(growable: false);
                    usedHomeKeys.addAll(
                      upcomingItems.take(20).map(_homeUsedKey),
                    );
                    final savedItems = _withoutContinueWatching(
                      _savedForLaterItems(library.values),
                      continueKeys,
                    );
                    usedHomeKeys.addAll(savedItems.take(8).map(_homeUsedKey));
                    final showFullLoading =
                        _loading &&
                        _newMovies.isEmpty &&
                        _newSeries.isEmpty &&
                        _animationPicks.isEmpty &&
                        _topMovies.isEmpty &&
                        _topSeries.isEmpty;
                    if (showFullLoading) {
                      return const _HomePageSkeleton();
                    }
                    if (AppState.defaultCatalogEnabled.value &&
                        _remoteEditorial == null) {
                      return CatalogEmptyState(
                        title: 'Home',
                        message: 'Home could not sync. Try again.',
                        actionLabel: 'Retry',
                        onAction: _handleCatalogSourcesChanged,
                      );
                    }
                    return CustomScrollView(
                      cacheExtent: 900,
                      slivers: [
                        SliverToBoxAdapter(
                          child: _HeroCarousel(
                            title: displayHeroEditorial.title,
                            subtitle: displayHeroEditorial.displaySubtitle,
                            editorialGenres: displayHeroEditorial.genres,
                            items: displayHeroItems,
                            trailerAvailability: _heroTrailerAvailability,
                            loading: _loading && displayHeroItems.isEmpty,
                            onPlay: _openDetails,
                            onTrailer: _openTrailer,
                            onDiscover: _openDiscovery,
                          ),
                        ),
                        if (visibleContinueItems.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _ContinuePromptCard(
                              entries: visibleContinueItems,
                              onTap: _openLibrary,
                            ),
                          ),
                        if (todaySignalEditorial != null &&
                            todaySignalItems.length >= 3)
                          _RankedHomeRail(
                            title: todaySignalEditorial.title,
                            subtitle: todaySignalEditorial.sectionSubtitle,
                            items: todaySignalItems
                                .take(20)
                                .toList(growable: false),
                            onTap: _openDetails,
                            onOpenDiscovery: () => _openCuratedShelf(
                              title: todaySignalEditorial.title,
                              subtitle: todaySignalEditorial.sectionSubtitle,
                              items: todaySignalItems,
                              showRankPills: true,
                              externalTopSignal: todaySignalUsesRemote,
                              insightsEnabled: insightsEnabled,
                            ),
                          ),
                        if (topSignalEditorial != null &&
                            topSignalItems.length >= 3)
                          _RankedHomeRail(
                            title: topSignalEditorial.title,
                            subtitle: topSignalEditorial.sectionSubtitle,
                            items: topSignalItems
                                .take(20)
                                .toList(growable: false),
                            onTap: _openDetails,
                            onOpenDiscovery: () => _openCuratedShelf(
                              title: topSignalEditorial.title,
                              subtitle: topSignalEditorial.sectionSubtitle,
                              items: topSignalItems,
                              showRankPills: true,
                              externalTopSignal: topSignalUsesRemote,
                              insightsEnabled: insightsEnabled,
                            ),
                          ),
                        if (juicrTopSignalEditorial != null &&
                            juicrTopSignalItems.length >= 3)
                          _RankedHomeRail(
                            title: juicrTopSignalEditorial.title,
                            subtitle: juicrTopSignalEditorial.sectionSubtitle,
                            items: juicrTopSignalItems
                                .take(10)
                                .toList(growable: false),
                            onTap: _openDetails,
                            onOpenDiscovery: () => _openCuratedShelf(
                              title: juicrTopSignalEditorial.title,
                              subtitle: juicrTopSignalEditorial.sectionSubtitle,
                              items: juicrTopSignalItems,
                              showRankPills: true,
                              externalTopSignal: juicrTopSignalUsesRemote,
                              insightsEnabled: insightsEnabled,
                            ),
                          ),
                        if (savedItems.isNotEmpty)
                          _HomeRail(
                            title: savedEditorial.title,
                            subtitle: savedEditorial.sectionSubtitle,
                            entries: [
                              for (final item in savedItems.take(12))
                                _HomeRailEntry(item: item),
                            ],
                            onTap: _openDetails,
                            onOpenDiscovery: () => _openCuratedShelf(
                              title: savedEditorial.title,
                              subtitle: savedEditorial.sectionSubtitle,
                              items: savedItems,
                              insightsEnabled: insightsEnabled,
                            ),
                          ),
                        if (upcomingItems.length >= 3)
                          _RankedHomeRail(
                            title: upcomingEditorial.title,
                            subtitle: upcomingEditorial.sectionSubtitle,
                            items: upcomingItems
                                .take(20)
                                .toList(growable: false),
                            showRankPills: false,
                            onTap: _openDetails,
                            onOpenDiscovery: () => _openCuratedShelf(
                              title: upcomingEditorial.title,
                              subtitle: upcomingEditorial.sectionSubtitle,
                              items: upcomingItems,
                              insightsEnabled: insightsEnabled,
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

List<CatalogItem> _dedupeItems(List<CatalogItem> items) {
  final seen = <String>{};
  final seenContent = <String>{};
  final result = <CatalogItem>[];
  for (final item in items) {
    if (!_isHomeAllowedByMatureGate(item)) continue;
    final key = _itemKey(item);
    final contentKey = _homeContentKey(item);
    if (!seen.add(key)) continue;
    if (contentKey.isNotEmpty && !seenContent.add(contentKey)) continue;
    result.add(item);
  }
  return result;
}

Map<String, dynamic>? _safeJsonDecodeMap(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

List<CatalogItem> _catalogSnapshotList(dynamic value) {
  if (value is! List) return const <CatalogItem>[];
  final items = <CatalogItem>[];
  for (final raw in value) {
    if (raw is! Map<String, dynamic>) continue;
    final item = CatalogItem.fromJson(raw);
    if (item.isLocalCatalogItem ||
        item.personalServerItemId != null ||
        item.personalServerSeriesItemId != null) {
      continue;
    }
    items.add(item);
  }
  return _dedupeItems(items).take(30).toList(growable: false);
}

List<Map<String, dynamic>> _safePublicSnapshotItems(
  Iterable<CatalogItem> items,
) {
  return [
    for (final item in items.take(30))
      if (!item.isLocalCatalogItem &&
          item.personalServerItemId == null &&
          item.personalServerSeriesItemId == null)
        item.toJson(),
  ];
}

List<CatalogItem> _savedForLaterItems(Iterable<CatalogItem> items) {
  final deduped = _dedupeItems(items.toList().reversed.toList());
  final vod = [
    for (final item in deduped)
      if (!item.type.isLive) item,
  ];
  return [
    for (final item in vod)
      if (_isHomeAllowedByMatureGate(item)) item,
  ];
}

List<CatalogItem> _upcomingThisYearItems({required List<CatalogItem> movies}) {
  final currentYear = DateTime.now().year;
  final items = [
    for (final item in movies)
      if (item.type == MediaType.movie &&
          item.isUpcoming &&
          _itemYear(item) == currentYear &&
          _hasHomePoster(item) &&
          _isHomeAllowedByMatureGate(item))
        item,
  ];
  items.sort(_compareUpcomingReleaseDate);
  return items.toList(growable: false);
}

bool _hasHomePoster(CatalogItem item) {
  final poster = item.type.isLive ? item.logo ?? item.poster : item.poster;
  return poster != null && poster.trim().isNotEmpty;
}

bool _hasHomeArtwork(CatalogItem item) {
  final artwork = item.type.isLive
      ? item.logo ?? item.poster ?? item.background
      : item.background ?? item.poster;
  return artwork != null && artwork.trim().isNotEmpty;
}

bool _hasCredibleHomeCurationMetadata(CatalogItem item) {
  final rating = double.tryParse(item.imdbRating?.trim() ?? '');
  if (rating != null && rating <= 0.1) return false;
  final voteCount = item.voteCount;
  if (voteCount != null && voteCount <= 0) return false;
  return true;
}

bool _isHomeEditorialCandidate(CatalogItem item, _EditorialRail rail) {
  if (!_hasHomePoster(item)) return false;
  if (!_hasCredibleHomeCurationMetadata(item)) return false;
  if (rail.requireGenreMatch && !_itemMatchesAnyGenre(item, rail.genres)) {
    return false;
  }
  return true;
}

bool _isHomeInTheatersCandidate(CatalogItem item, _EditorialRail rail) {
  if (!_hasHomeArtwork(item)) return false;
  if (!_isHomeAllowedByMatureGate(item)) return false;
  if (rail.requireGenreMatch && !_itemMatchesAnyGenre(item, rail.genres)) {
    return false;
  }
  return true;
}

bool _isHomeAllowedByMatureGate(CatalogItem item) {
  return AppState.showMatureContent.value || !item.hasMatureContentSignal;
}

List<CatalogItem> _availableHomeItems(Iterable<CatalogItem> items) {
  return [
    for (final item in items)
      if (!item.isUpcoming && _isHomeAllowedByMatureGate(item)) item,
  ];
}

List<CatalogItem> _animationCompatibleHomeItems(Iterable<CatalogItem> items) {
  return items
      .where(_isHomeAllowedByMatureGate)
      .where(_isAnimationCompatibleHomeItem)
      .map((item) => item.withType(MediaType.animation))
      .toList(growable: false);
}

bool _isAnimationCompatibleHomeItem(CatalogItem item) {
  if (item.type == MediaType.animation) return true;
  if (item.type != MediaType.series) return false;
  return item.genres.any((genre) {
    final normalized = genre.trim().toLowerCase();
    return normalized == 'animation';
  });
}

String _itemKey(CatalogItem item) {
  return '${item.type.compatTypeValue}:${item.id}';
}

String _homeContentKey(CatalogItem item) {
  final title = _normalizeEditorialSearchText(item.name);
  if (title.isEmpty) return '';
  final year = item.year?.trim() ?? '';
  return '$title:$year';
}

String _homeUsedKey(CatalogItem item) {
  final contentKey = _homeContentKey(item);
  return contentKey.isEmpty ? _itemKey(item) : contentKey;
}

List<CatalogItem> _mergeHomeRailRefreshItems(
  List<CatalogItem> previous,
  List<CatalogItem> refreshed,
) {
  if (refreshed.isEmpty || previous.isEmpty) return refreshed;
  final previousByItemKey = {for (final item in previous) _itemKey(item): item};
  final previousByContentKey = <String, CatalogItem>{
    for (final item in previous)
      if (_homeContentKey(item).isNotEmpty) _homeContentKey(item): item,
  };
  return [
    for (final item in refreshed)
      (previousByItemKey[_itemKey(item)] ??
                  previousByContentKey[_homeContentKey(item)])
              ?.merge(item) ??
          item,
  ];
}

String _heroTrailerAvailabilityKey(CatalogItem item) {
  return '${item.type.compatTypeValue}:${item.id}:${item.tmdbId ?? ''}';
}

String _safeHomeTrailerErrorLabel(Object error) {
  final text = error.toString();
  if (text.contains('429')) return 'rate_limited';
  if (text.toLowerCase().contains('timeout')) return 'timeout';
  return 'unavailable';
}

List<CatalogItem> _mergeHydratedUpcomingItems(
  List<CatalogItem> current,
  List<CatalogItem> hydrated,
) {
  if (current.isEmpty || hydrated.isEmpty) return current;
  final byKey = <String, CatalogItem>{
    for (final item in hydrated) _itemKey(item): item,
  };
  final merged = [for (final item in current) byKey[_itemKey(item)] ?? item];
  merged.sort(_compareUpcomingReleaseDate);
  return merged;
}

int _compareUpcomingReleaseDate(CatalogItem left, CatalogItem right) {
  final leftDate = _upcomingReleaseSortDate(left);
  final rightDate = _upcomingReleaseSortDate(right);
  if (leftDate == null && rightDate == null) {
    return _imdbScore(right).compareTo(_imdbScore(left));
  }
  if (leftDate == null) return 1;
  if (rightDate == null) return -1;
  final dateCompare = leftDate.compareTo(rightDate);
  if (dateCompare != 0) return dateCompare;
  return _imdbScore(right).compareTo(_imdbScore(left));
}

DateTime? _upcomingReleaseSortDate(CatalogItem item) {
  final rawDate = item.releaseDate?.trim();
  if (rawDate == null || rawDate.isEmpty) return null;
  final date = DateTime.tryParse(rawDate);
  if (date == null) return null;
  final currentYear = DateTime.now().year;
  if (date.year != currentYear) return null;
  return DateTime(date.year, date.month, date.day);
}

List<CatalogItem> _withoutUsedHomeItems(
  List<CatalogItem> items,
  Set<String> usedKeys,
) {
  return [
    for (final item in items)
      if (!usedKeys.contains(_homeUsedKey(item)) &&
          _isHomeAllowedByMatureGate(item))
        item,
  ];
}

List<CatalogItem> _withoutContinueWatching(
  List<CatalogItem> items,
  Set<String> progressKeys,
) {
  return [
    for (final item in items)
      if (!progressKeys.contains(_itemKey(item)) &&
          _isHomeAllowedByMatureGate(item))
        item,
  ];
}

List<CatalogItem> _backfilledSignalRailItems(
  List<CatalogItem> primaryItems, {
  required List<CatalogItem> fallbackPool,
  required Set<String> usedKeys,
  required int limit,
  bool preservePrimaryRank = false,
}) {
  final seen = <String>{};
  final result = <CatalogItem>[];
  void addItems(Iterable<CatalogItem> items, {required bool allowUsed}) {
    for (final item in items) {
      if (result.length >= limit) break;
      if (item.type.isLive || !_isHomeAllowedByMatureGate(item)) continue;
      final key = _homeUsedKey(item);
      if ((!allowUsed && usedKeys.contains(key)) || !seen.add(key)) continue;
      result.add(item);
    }
  }

  addItems(primaryItems, allowUsed: preservePrimaryRank);
  if (result.length < limit) addItems(fallbackPool, allowUsed: false);
  return result.toList(growable: false);
}

List<CatalogItem> _localTopSignalItems(
  List<CatalogItem> items, {
  int limit = 20,
  required Map<String, CatalogItem> library,
  required Map<String, ContinueWatchingEntry> progress,
  required Map<String, CompletedWatchingEntry> completed,
  required List<String> searchHistory,
  required bool insightsEnabled,
}) {
  final ranked =
      [
        for (final item in items)
          if (!item.type.isLive && _isHomeAllowedByMatureGate(item))
            _ScoredCatalogItem(
              item,
              _weeklySignalScore(
                item,
                library: library,
                progress: progress,
                completed: completed,
                searchHistory: searchHistory,
                insightsEnabled: insightsEnabled,
              ),
            ),
      ]..sort((left, right) {
        final score = right.score.compareTo(left.score);
        if (score != 0) return score;
        return itemTieBreaker(left.item).compareTo(itemTieBreaker(right.item));
      });
  return _dedupeItems(
    ranked.map((entry) => entry.item).toList(growable: false),
  ).take(limit).toList(growable: false);
}

List<CatalogItem> _weeklyTopSignalItems(
  List<CatalogItem> items, {
  required _EditorialRail? editorial,
  int limit = 20,
  required Map<String, CatalogItem> library,
  required Map<String, ContinueWatchingEntry> progress,
  required Map<String, CompletedWatchingEntry> completed,
  required List<String> searchHistory,
  required bool insightsEnabled,
}) {
  if (editorial == null) return const <CatalogItem>[];
  final remoteRanked = _remoteTopSignalItems(items, editorial);
  return remoteRanked.take(limit).toList(growable: false);
}

List<CatalogItem> _remoteTopSignalItems(
  List<CatalogItem> items,
  _EditorialRail? editorial,
) {
  if (editorial == null) return const <CatalogItem>[];
  if (editorial.items.isEmpty) return const <CatalogItem>[];
  final remaining = items
      .where((item) => !item.type.isLive && _isHomeAllowedByMatureGate(item))
      .toList();
  final ranked = <CatalogItem>[];
  final seen = <String>{};
  for (final signal in editorial.items) {
    final matchIndex = remaining.indexWhere(
      (item) => _itemMatchesTrendSignal(item, signal),
    );
    if (matchIndex < 0) continue;
    final match = remaining.removeAt(matchIndex);
    final key = _itemKey(match);
    if (seen.add(key)) ranked.add(match);
  }
  return ranked;
}

bool _itemMatchesTrendSignal(CatalogItem item, HomeEditorialTrendItem signal) {
  if (signal.type != null && item.type != signal.type) return false;
  if (signal.tmdbId != null && item.tmdbId == signal.tmdbId) return true;
  final itemTitle = _normalizedTrendTitle(item.name);
  final signalTitle = _normalizedTrendTitle(signal.title);
  if (itemTitle.isEmpty || signalTitle.isEmpty || itemTitle != signalTitle) {
    return false;
  }
  if (signal.year.isEmpty) return true;
  final year = item.year?.trim() ?? '';
  return year.isEmpty || year.startsWith(signal.year);
}

String _normalizedTrendTitle(String value) {
  return _normalizeEditorialSearchText(value);
}

double _weeklySignalScore(
  CatalogItem item, {
  required Map<String, CatalogItem> library,
  required Map<String, ContinueWatchingEntry> progress,
  required Map<String, CompletedWatchingEntry> completed,
  required List<String> searchHistory,
  required bool insightsEnabled,
}) {
  final key = _itemKey(item);
  var score = _imdbScore(item) * 10;
  final year = _itemYear(item);
  final nowYear = DateTime.now().year;
  if (year != null) {
    final age = (nowYear - year).abs();
    score += math.max(0, 8 - age).toDouble();
  }
  if (insightsEnabled) {
    if (library.containsKey(key)) score += 12;
    final progressEntry = progress[key];
    if (progressEntry != null) {
      score += 18 + progressEntry.progress.clamp(0.0, 1.0).toDouble() * 8;
    }
    if (completed.containsKey(key)) score += 20;
    final normalizedName = item.name.toLowerCase();
    for (final query in searchHistory.take(6)) {
      final normalizedQuery = query.trim().toLowerCase();
      if (normalizedQuery.isEmpty) continue;
      if (normalizedName.contains(normalizedQuery) ||
          normalizedQuery.contains(normalizedName)) {
        score += 10;
      }
    }
  }
  return score;
}

int itemTieBreaker(CatalogItem item) {
  return item.id.codeUnits.fold<int>(0, (value, unit) => value + unit) +
      item.name.codeUnits.fold<int>(0, (value, unit) => value + unit);
}

String _externalTopSignalSubtitle(String fallback) {
  final cleanFallback = fallback.trim();
  final sourceLine =
      'Ranked from the shared trend source, then matched to Juicr catalog cards.';
  return cleanFallback.isEmpty ? sourceLine : '$cleanFallback $sourceLine';
}

String _topTenItemReason(
  CatalogItem item,
  int rank, {
  required bool externalTopSignal,
}) {
  final clues = <String>[];
  final year = _itemYear(item);
  if (year != null && year >= DateTime.now().year - 1) {
    clues.add('fresh release');
  }
  if (item.imdbRating != null && item.imdbRating!.isNotEmpty) {
    clues.add('IMDb ${item.imdbRating}');
  }
  final genre = item.genres
      .map(_displayGenre)
      .firstWhere((value) => value != 'All genres', orElse: () => '');
  if (genre.isNotEmpty) clues.add(genre.toLowerCase());
  if (AppState.continueWatching.value.containsKey(item.id)) {
    clues.add('in Continue');
  } else if (AppState.library.value.containsKey(item.id)) {
    clues.add('saved');
  }
  final reason = clues.isEmpty
      ? 'strong shelf momentum'
      : clues.take(3).join(' - ');
  return externalTopSignal
      ? 'Rank $rank from the shared trend source, matched here with $reason.'
      : 'Rank $rank because of $reason.';
}

bool _isTopTenShelfTitle(String title) {
  return title == "juicr's top 10" ||
      title == 'juicr top 10' ||
      title == 'trending today' ||
      title == 'trending this week' ||
      title == 'people keep picking this' ||
      title == 'the hot row' ||
      title == 'most wanted right now' ||
      title == "everyone's hovering here" ||
      title == 'big week energy' ||
      title == 'trending on the couch' ||
      title == 'this week on juicr';
}

_EditorialRail _weeklyTopSignalEditorial() {
  final week = DateTime.now().difference(DateTime(2024)).inDays ~/ 7;
  return _pickEditorial(const [
    _EditorialRail(
      title: 'Trending This Week',
      subtitle: 'Local titles carrying this week\'s pulse.',
      id: 'topSignal',
      kind: 'ranked',
      perType: 20,
    ),
    _EditorialRail(
      title: 'Trending This Week',
      subtitle: 'The picks that keep winning the room.',
      id: 'topSignal',
      kind: 'ranked',
      perType: 20,
    ),
    _EditorialRail(
      title: 'Trending This Week',
      subtitle: 'Saved, searched, resumed, hard to ignore.',
      id: 'topSignal',
      kind: 'ranked',
      perType: 20,
    ),
    _EditorialRail(
      title: 'Trending This Week',
      subtitle: 'The shelf with the loudest pulse.',
      id: 'topSignal',
      kind: 'ranked',
      perType: 20,
    ),
  ], offset: week);
}

_EditorialRail _dailyTopSignalEditorial() {
  return const _EditorialRail(
    id: 'todaySignal',
    kind: 'ranked',
    title: 'Trending Today',
    subtitle: 'Local picks moving fastest right now.',
    types: [MediaType.movie, MediaType.series],
    perType: 20,
    intent: 'local_trending_fallback',
    releaseWindow: 'local_trends',
    theme: 'trend:local',
  );
}

_EditorialRail _juicrTopSignalEditorial() {
  return const _EditorialRail(
    id: 'juicrTopSignal',
    kind: 'ranked',
    title: "Juicr's Top 10",
    subtitle: 'Local movies and shows with the strongest score signal.',
    types: [MediaType.movie, MediaType.series],
    perType: 10,
    intent: 'local_score_fallback',
    releaseWindow: 'local_trends',
    theme: 'score:local',
  );
}

int? _itemYear(CatalogItem item) {
  final raw = item.year?.trim();
  if (raw == null || raw.length < 4) return null;
  return int.tryParse(raw.substring(0, 4));
}

bool _requiresStrictEditorialIntent(_EditorialRail rail) {
  final intent = rail.intent.trim().toLowerCase();
  final window = rail.releaseWindow.trim().toLowerCase();
  final title = rail.title.trim().toLowerCase();
  return intent == 'current_releases' ||
      intent == 'theatrical_trailers' ||
      window == 'current_year' ||
      window == 'now_playing' ||
      title == 'in theaters' ||
      title == 'new this week';
}

bool _isSourceBoundEditorial(_EditorialRail rail) {
  final intent = rail.intent.trim().toLowerCase();
  final kind = rail.curationKind.trim().toLowerCase();
  return _isInTheatersEditorial(rail) ||
      intent == 'upcoming' ||
      intent == 'external_trending' ||
      kind == 'tmdb_list_top10' ||
      rail.sort == CatalogSort.nowPlaying ||
      rail.sort == CatalogSort.upcoming ||
      rail.sort == CatalogSort.airingToday ||
      rail.sort == CatalogSort.onTv;
}

bool _keepsEditorialScope(_EditorialRail rail) {
  return _isSourceBoundEditorial(rail) ||
      rail.query.trim().isNotEmpty ||
      rail.requireGenreMatch;
}

bool _isInTheatersEditorial(_EditorialRail rail) {
  final title = rail.title.trim().toLowerCase();
  final intent = rail.intent.trim().toLowerCase();
  final window = rail.releaseWindow.trim().toLowerCase();
  return title == 'in theaters' ||
      intent == 'theatrical_trailers' ||
      window == 'now_playing';
}

bool _allowsUpcomingEditorialIntent(_EditorialRail rail) {
  final title = rail.title.trim().toLowerCase();
  final intent = rail.intent.trim().toLowerCase();
  return title == 'upcoming this year' || intent == 'upcoming';
}

bool _homeItemMatchesEditorialIntent(CatalogItem item, _EditorialRail rail) {
  if (_isDailyGenreEditorial(rail)) {
    return _isDailyCurationPreviewCandidate(item);
  }
  if (_isInTheatersEditorial(rail)) {
    return _homeItemMatchesInTheaters(item, rail);
  }
  if (!_isHomeEditorialCandidate(item, rail)) return false;
  if (item.isUpcoming && !_allowsUpcomingEditorialIntent(rail)) return false;
  if (!_homeItemMatchesEditorialQuery(item, rail.query)) return false;
  if (!_requiresStrictEditorialIntent(rail)) return true;
  if (item.type.isLive) return false;
  final year = _itemYear(item);
  return year != null && year == DateTime.now().year;
}

bool _isDailyGenreEditorial(_EditorialRail rail) {
  return rail.curationKind.trim().toLowerCase() == 'tmdb_daily_genre';
}

bool _isDailyCurationPreviewCandidate(CatalogItem item) {
  if (!_hasHomeArtwork(item)) return false;
  return _isHomeAllowedByMatureGate(item);
}

bool _homeItemMatchesEditorialQuery(CatalogItem item, String query) {
  final cleaned = _normalizeEditorialSearchText(query);
  if (cleaned.isEmpty) return true;
  final haystack = _normalizeEditorialSearchText(
    [item.name, item.id, item.year ?? '', ...item.genres].join(' '),
  );
  final tokens = cleaned
      .split(RegExp(r'[\s:_-]+'))
      .where((token) => token.length >= 3)
      .toList(growable: false);
  if (tokens.isEmpty) return haystack.contains(cleaned);
  return tokens.every(haystack.contains);
}

String _normalizeEditorialSearchText(String value) {
  return value
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('í', 'i')
      .replaceAll('ì', 'i')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ò', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

List<CatalogItem> _homeItemsMatchingEditorialIntent(
  List<CatalogItem> items,
  _EditorialRail rail,
) {
  if (_isInTheatersEditorial(rail)) {
    return items
        .where((item) => _homeItemMatchesInTheaters(item, rail))
        .toList(growable: false);
  }
  final hasQuery = rail.query.trim().isNotEmpty;
  if (_isDailyGenreEditorial(rail)) {
    return [
      for (final item in items)
        if (_isDailyCurationPreviewCandidate(item)) item,
    ];
  }
  if (!hasQuery && !_requiresStrictEditorialIntent(rail)) {
    return [
      for (final item in items)
        if ((!item.isUpcoming || _allowsUpcomingEditorialIntent(rail)) &&
            _isHomeEditorialCandidate(item, rail))
          item,
    ];
  }
  return items
      .where((item) {
        if (!_isHomeEditorialCandidate(item, rail)) return false;
        if (item.isUpcoming && !_allowsUpcomingEditorialIntent(rail)) {
          return false;
        }
        if (!_homeItemMatchesEditorialQuery(item, rail.query)) return false;
        if (!_requiresStrictEditorialIntent(rail)) return true;
        if (item.type.isLive) return false;
        final year = _itemYear(item);
        return year != null && year == DateTime.now().year;
      })
      .toList(growable: false);
}

bool _homeItemMatchesInTheaters(CatalogItem item, _EditorialRail rail) {
  if (item.type != MediaType.movie) return false;
  return _isHomeInTheatersCandidate(item, rail);
}

class _ScoredCatalogItem {
  const _ScoredCatalogItem(this.item, this.score);

  final CatalogItem item;
  final double score;
}

List<CatalogItem> _bestGenreMatches(
  List<CatalogItem> items,
  List<String> genres,
  int limit, {
  bool allowUnknownGenre = false,
}) {
  if (genres.isEmpty) {
    final sorted = items.toList()
      ..sort((left, right) => _imdbScore(right).compareTo(_imdbScore(left)));
    return sorted.take(limit).toList(growable: false);
  }
  final matches = items
      .where((item) {
        if (_itemMatchesAnyGenre(item, genres)) return true;
        return allowUnknownGenre && item.genres.isEmpty;
      })
      .toList(growable: false);
  final sorted = matches.toList()
    ..sort((left, right) => _imdbScore(right).compareTo(_imdbScore(left)));
  return sorted.take(limit).toList(growable: false);
}

List<CatalogItem> _bestEditorialMatches(
  List<CatalogItem> items,
  _EditorialRail rail,
  int limit, {
  bool allowUnknownGenre = false,
}) {
  final scopedItems = _homeItemsMatchingEditorialIntent(items, rail);
  if (scopedItems.isEmpty && rail.query.trim().isNotEmpty) {
    return const <CatalogItem>[];
  }
  final matches = _bestGenreMatches(
    scopedItems,
    rail.genres,
    limit,
    allowUnknownGenre: allowUnknownGenre,
  );
  if (matches.length >= limit ||
      rail.requireGenreMatch ||
      scopedItems.isEmpty) {
    return matches;
  }
  final matchedKeys = {for (final item in matches) _itemKey(item)};
  final fallback =
      scopedItems
          .where((item) => !matchedKeys.contains(_itemKey(item)))
          .toList(growable: false)
        ..sort((left, right) => _imdbScore(right).compareTo(_imdbScore(left)));
  return _dedupeItems([
    ...matches,
    ...fallback,
  ]).take(limit).toList(growable: false);
}

List<CatalogSort> _curatedSortFallbacks(CatalogSort preferred) {
  return [
    preferred,
    for (final sort in const [
      CatalogSort.imdbRating,
      CatalogSort.top,
      CatalogSort.year,
    ])
      if (sort != preferred) sort,
  ];
}

List<CatalogItem> _interleaveBuckets(List<List<CatalogItem>> buckets) {
  final result = <CatalogItem>[];
  final seen = <String>{};
  var index = 0;
  var added = true;
  while (added) {
    added = false;
    for (final bucket in buckets) {
      if (index >= bucket.length) continue;
      final item = bucket[index];
      if (seen.add(_homeUsedKey(item))) {
        result.add(item);
        added = true;
      }
    }
    index += 1;
  }
  return result;
}

bool _itemMatchesAnyGenre(CatalogItem item, List<String> genres) {
  final itemGenres = item.genres.map((genre) => genre.toLowerCase());
  return genres.any((target) {
    final normalizedTarget = target.toLowerCase();
    return itemGenres.any((genre) => genre.contains(normalizedTarget));
  });
}

double _imdbScore(CatalogItem item) {
  return double.tryParse(item.imdbRating ?? '') ?? 0;
}

String _displayGenre(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return 'All genres';
  final lower = cleaned.toLowerCase();
  if (lower == 'sci-fi' || lower == 'sci fi' || lower == 'science fiction') {
    return 'Sci-Fi';
  }
  if (lower == 'film-noir') return 'Film Noir';
  if (lower == 'sports') return 'Sport';
  if (lower == 'tv-movie' || lower == 'tv movie') return 'TV Movie';
  if (lower == 'reality-tv') return 'Reality-TV';
  if (lower == 'talk-show') return 'Talk-Show';
  if (lower == 'game-show') return 'Game-Show';
  return lower
      .split(RegExp(r'[\s_-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _formatHomeEditorialText(String value, {String? genre, int? year}) {
  return value
      .replaceAll(
        '{genre}',
        genre?.trim().isNotEmpty == true ? genre!.trim() : 'Watch history',
      )
      .replaceAll('{year}', year?.toString() ?? DateTime.now().year.toString())
      .trim();
}

String _titleCaseHomeLabel(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return normalized;
  const acronyms = {'dc': 'DC', 'imdb': 'IMDb', 'p2p': 'P2P', 'tv': 'TV'};
  return normalized
      .split(' ')
      .map((word) {
        return word
            .split('-')
            .map((part) {
              if (part.isEmpty) return part;
              final lower = part.toLowerCase();
              final acronym = acronyms[lower];
              if (acronym != null) return acronym;
              return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
            })
            .join('-');
      })
      .join(' ');
}

class _EditorialRail {
  const _EditorialRail({
    required this.title,
    required this.subtitle,
    this.id = '',
    this.kind = '',
    this.genres = const <String>[],
    this.types = const <MediaType>[],
    this.sort = CatalogSort.top,
    this.perType = 4,
    this.requireGenreMatch = false,
    this.intent = '',
    this.releaseWindow = '',
    this.theme = '',
    this.seasonalWindow = '',
    this.query = '',
    this.curationKind = '',
    this.notificationHook = '',
    this.pageOneOnly = false,
    this.limit = 10,
    this.movieLimit = 5,
    this.seriesLimit = 5,
    this.items = const <HomeEditorialTrendItem>[],
  });

  final String id;
  final String kind;
  final String title;
  final String subtitle;
  final List<String> genres;
  final List<MediaType> types;
  final CatalogSort sort;
  final int perType;
  final bool requireGenreMatch;
  final String intent;
  final String releaseWindow;
  final String theme;
  final String seasonalWindow;
  final String query;
  final String curationKind;
  final String notificationHook;
  final bool pageOneOnly;
  final int limit;
  final int movieLimit;
  final int seriesLimit;
  final List<HomeEditorialTrendItem> items;

  String get displayTitle => _titleCaseHomeLabel(title);

  String get displaySubtitle => juicrCopyWithoutRepeatedTitlePhrase(
    title: displayTitle,
    subtitle: subtitle,
  );

  String get sectionSubtitle => '';

  bool get isRanked => kind.trim().toLowerCase() == 'ranked';

  _EditorialRail withDefaultTypes(List<MediaType> defaults) {
    if (types.isNotEmpty) return this;
    return _EditorialRail(
      id: id,
      kind: kind,
      title: title,
      subtitle: subtitle,
      genres: genres,
      types: defaults,
      sort: sort,
      perType: perType,
      requireGenreMatch: requireGenreMatch,
      intent: intent,
      releaseWindow: releaseWindow,
      theme: theme,
      seasonalWindow: seasonalWindow,
      query: query,
      curationKind: curationKind,
      notificationHook: notificationHook,
      pageOneOnly: pageOneOnly,
      limit: limit,
      movieLimit: movieLimit,
      seriesLimit: seriesLimit,
      items: items,
    );
  }
}

int _editorialBucket({int offset = 0}) {
  final now = DateTime.now();
  final days = now.difference(DateTime(2024)).inDays;
  return days + offset;
}

_EditorialRail _pickEditorial(List<_EditorialRail> rails, {int offset = 0}) {
  return rails[_editorialBucket(offset: offset) % rails.length];
}

_EditorialRail _editorialOrFallback(
  HomeEditorialRail? remote,
  _EditorialRail fallback,
) {
  if (remote == null || remote.title.isEmpty) return fallback;
  return _EditorialRail(
    id: remote.id.isEmpty ? fallback.id : remote.id,
    kind: remote.kind.isEmpty ? fallback.kind : remote.kind,
    title: _titleCaseHomeLabel(remote.title),
    subtitle: remote.subtitle.isEmpty ? fallback.subtitle : remote.subtitle,
    genres: remote.genres.isEmpty ? fallback.genres : remote.genres,
    types: remote.types.isEmpty ? fallback.types : remote.types,
    sort: remote.sort,
    perType: remote.perType,
    requireGenreMatch: remote.requireGenreMatch || fallback.requireGenreMatch,
    intent: remote.intent.isEmpty ? fallback.intent : remote.intent,
    releaseWindow: remote.releaseWindow.isEmpty
        ? fallback.releaseWindow
        : remote.releaseWindow,
    theme: remote.theme.isEmpty ? fallback.theme : remote.theme,
    seasonalWindow: remote.seasonalWindow.isEmpty
        ? fallback.seasonalWindow
        : remote.seasonalWindow,
    query: remote.query.isEmpty ? fallback.query : remote.query,
    curationKind: remote.curationKind.isEmpty
        ? fallback.curationKind
        : remote.curationKind,
    notificationHook: remote.notificationHook.isEmpty
        ? fallback.notificationHook
        : remote.notificationHook,
    pageOneOnly: remote.pageOneOnly || fallback.pageOneOnly,
    limit: remote.limit,
    movieLimit: remote.movieLimit,
    seriesLimit: remote.seriesLimit,
    items: remote.items.isEmpty ? fallback.items : remote.items,
  );
}

_EditorialRail? _editorialOrNull(
  HomeEditorialRail? remote,
  _EditorialRail fallback,
) {
  if (remote == null || remote.title.isEmpty) return null;
  return _editorialOrFallback(remote, fallback);
}

_EditorialRail _dailyHeroEditorial() {
  return _pickEditorial(const [
    _EditorialRail(
      title: 'In Theaters',
      subtitle: 'Big-screen energy, couch-ready.',
      types: [MediaType.movie],
      sort: CatalogSort.nowPlaying,
      intent: 'theatrical_trailers',
      releaseWindow: 'now_playing',
    ),
    _EditorialRail(
      title: 'New This Week',
      subtitle: 'Fresh before the rush.',
      genres: ['thriller', 'mystery', 'action', 'drama'],
      sort: CatalogSort.year,
      intent: 'current_releases',
      releaseWindow: 'current_year',
      requireGenreMatch: true,
    ),
    _EditorialRail(
      title: 'Horror night',
      subtitle: 'Every hallway is suspicious.',
      types: [MediaType.movie, MediaType.series, MediaType.animation],
      genres: ['horror'],
      sort: CatalogSort.imdbRating,
      perType: 3,
      requireGenreMatch: true,
    ),
    _EditorialRail(
      title: 'Story momentum',
      subtitle: 'Series and animation with room to pull you in.',
      types: [MediaType.series, MediaType.animation],
      genres: ['drama', 'adventure', 'action', 'mystery'],
      requireGenreMatch: true,
    ),
    _EditorialRail(
      title: 'Weekend Picks',
      subtitle: 'Snacks, couch, low pressure.',
      genres: ['comedy', 'drama', 'adventure'],
      requireGenreMatch: true,
    ),
  ], offset: 3);
}

_EditorialRail _dailyMovieEditorial() {
  final rail = _pickEditorial(const [
    _EditorialRail(
      title: 'Near the remote',
      subtitle: 'No endless scrolling required.',
      genres: ['drama', 'thriller', 'action'],
    ),
    _EditorialRail(
      title: 'Big-screen picks',
      subtitle: 'A fresh movie shelf for tonight.',
      genres: ['adventure', 'action', 'thriller'],
    ),
    _EditorialRail(
      title: 'Not alone',
      subtitle: 'Bring backup.',
      genres: ['horror', 'thriller', 'mystery'],
    ),
    _EditorialRail(
      title: 'Suspicious curtains',
      subtitle: 'Blankets encouraged.',
      genres: ['horror', 'mystery', 'thriller'],
    ),
    _EditorialRail(
      title: 'No sitting still',
      subtitle: 'Fast starts, bad decisions.',
      genres: ['action', 'crime', 'thriller'],
    ),
    _EditorialRail(
      title: 'Strange little winners',
      subtitle: 'Odd, sharp, weirdly cozy.',
      genres: ['comedy', 'drama', 'crime'],
    ),
  ]);
  return rail.withDefaultTypes(const [MediaType.movie]);
}

_EditorialRail _dailySeriesEditorial() {
  final rail = _pickEditorial(const [
    _EditorialRail(
      title: 'Cancel plans',
      subtitle: 'There goes the evening.',
      genres: ['drama', 'action', 'mystery'],
    ),
    _EditorialRail(
      title: 'Rabbit hole',
      subtitle: 'One peek. Too late.',
      genres: ['mystery', 'drama', 'thriller'],
    ),
    _EditorialRail(
      title: 'Series worth starting',
      subtitle: 'A few episodes with room to pull you in.',
      genres: ['drama', 'mystery', 'thriller'],
    ),
    _EditorialRail(
      title: 'Secrets everywhere',
      subtitle: 'That is where it gets good.',
      genres: ['crime', 'thriller', 'mystery'],
    ),
    _EditorialRail(
      title: 'Weird rent',
      subtitle: 'Visit once. Move in.',
      genres: ['sci-fi', 'science fiction', 'fantasy', 'adventure'],
    ),
    _EditorialRail(
      title: 'Messy people',
      subtitle: 'Soft landing, complicated hearts.',
      genres: ['comedy', 'drama', 'romance'],
    ),
  ], offset: 1);
  return rail.withDefaultTypes(const [MediaType.series]);
}

_EditorialRail _dailyAnimationEditorial() {
  final rail = _pickEditorial(const [
    _EditorialRail(
      title: 'Neon nerves',
      subtitle: 'Bright worlds, sharp turns.',
      genres: ['action', 'fantasy', 'adventure'],
    ),
    _EditorialRail(
      title: 'Powering up',
      subtitle: 'Courage with volume.',
      genres: ['action', 'adventure'],
    ),
    _EditorialRail(
      title: 'Sleep can wait',
      subtitle: 'Just one more. Allegedly.',
      genres: ['adventure', 'comedy', 'action'],
    ),
    _EditorialRail(
      title: 'Bad map',
      subtitle: 'Lost in a good way.',
      genres: ['fantasy', 'mystery', 'sci-fi', 'science fiction'],
    ),
  ], offset: 2);
  return rail.withDefaultTypes(const [MediaType.animation]);
}

List<CatalogItem> _dailyEditorialItems(
  _EditorialRail rail,
  List<CatalogItem> items,
) {
  final shuffledItems = _dailyShuffle(items, seed: rail.title.hashCode);
  final scopedItems = rail.types.isEmpty
      ? shuffledItems
      : shuffledItems
            .where((item) => rail.types.contains(item.type))
            .toList(growable: false);
  final candidates = [
    for (final item in (scopedItems.isEmpty ? items : scopedItems))
      if (_hasHomePoster(item)) item,
  ];
  final intentCandidates = _homeItemsMatchingEditorialIntent(candidates, rail);
  final hasScopedQuery = rail.query.trim().isNotEmpty;
  if ((_requiresStrictEditorialIntent(rail) || hasScopedQuery) &&
      intentCandidates.isEmpty) {
    return const <CatalogItem>[];
  }
  final editorialCandidates = intentCandidates.isEmpty
      ? candidates
      : intentCandidates;
  if (rail.genres.isEmpty) {
    return editorialCandidates.take(12).toList(growable: false);
  }
  final genreMatches = editorialCandidates
      .where((item) {
        final itemGenres = item.genres.map((genre) => genre.toLowerCase());
        return rail.genres.any(
          (target) => itemGenres.any((genre) => genre.contains(target)),
        );
      })
      .toList(growable: false);
  if (genreMatches.isEmpty) {
    return rail.requireGenreMatch
        ? const <CatalogItem>[]
        : editorialCandidates.take(12).toList(growable: false);
  }
  if (rail.requireGenreMatch) {
    return genreMatches.take(12).toList(growable: false);
  }
  final matchedKeys = {for (final item in genreMatches) _itemKey(item)};
  final fallback = [
    for (final item in editorialCandidates)
      if (!matchedKeys.contains(_itemKey(item))) item,
  ];
  return _dedupeItems([
    ...genreMatches,
    ...fallback,
  ]).take(12).toList(growable: false);
}

const int _minimumHomeRailItems = 10;
const int _targetHomeRailItems = 10;
const int _minimumServerHeroItems = 3;
const int _targetHeroItems = 12;

List<CatalogItem> _dailyShuffle(List<CatalogItem> items, {required int seed}) {
  final copy = items.toList(growable: false);
  final random = math.Random(_editorialBucket(offset: seed.abs() % 997));
  for (var index = copy.length - 1; index > 0; index -= 1) {
    final swapIndex = random.nextInt(index + 1);
    final value = copy[index];
    copy[index] = copy[swapIndex];
    copy[swapIndex] = value;
  }
  return copy;
}

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({
    required this.title,
    required this.subtitle,
    required this.editorialGenres,
    required this.items,
    required this.trailerAvailability,
    required this.loading,
    required this.onPlay,
    required this.onTrailer,
    required this.onDiscover,
  });

  final String title;
  final String subtitle;
  final List<String> editorialGenres;
  final List<CatalogItem> items;
  final Map<String, bool> trailerAvailability;
  final bool loading;
  final ValueChanged<CatalogItem> onPlay;
  final Future<void> Function(CatalogItem item) onTrailer;
  final VoidCallback onDiscover;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel>
    with SingleTickerProviderStateMixin {
  static const int _loopPageCount = 10000;

  late final PageController _controller;
  late final AnimationController _trailerBusyController;
  Timer? _rotateTimer;
  late int _page;
  int _index = 0;
  bool _autoRotatePaused = false;
  String? _trailerLoadingKey;
  double _dragDelta = 0;

  @override
  void initState() {
    super.initState();
    _index = 0;
    _page = _initialLoopPageForItemCount(widget.items.length);
    _controller = PageController(viewportFraction: 0.76, initialPage: _page);
    _trailerBusyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAutoRotate();
  }

  void _openTrailer(CatalogItem item) {
    if (_trailerLoadingKey != null) return;
    _autoRotatePaused = true;
    _rotateTimer?.cancel();
    setState(() {
      _trailerLoadingKey = item.id;
    });
    _trailerBusyController.repeat();
    widget.onTrailer(item).whenComplete(() {
      if (!mounted) return;
      _trailerBusyController
        ..stop()
        ..reset();
      _autoRotatePaused = false;
      setState(() {
        _trailerLoadingKey = null;
      });
      _syncAutoRotate();
    });
  }

  void _animateToRelativePage(int delta, {String reason = 'manual'}) {
    if (widget.items.length < 2 || !_controller.hasClients) {
      DiagnosticLog.add(
        'home hero carousel skip reason=$reason items=${widget.items.length} hasClients=${_controller.hasClients}',
      );
      return;
    }
    _rotateTimer?.cancel();
    if (reason != 'auto') {
      DiagnosticLog.add(
        'home hero carousel animate reason=$reason from=$_page to=${_page + delta} index=$_index items=${widget.items.length}',
      );
    }
    final targetIndex = (_index + delta) % widget.items.length;
    var target = _nearestPageForLogicalIndex(targetIndex);
    if (target == _page) {
      target += delta >= 0 ? widget.items.length : -widget.items.length;
    }
    _controller
        .animateToPage(
          target,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (mounted) _syncAutoRotate();
        });
  }

  @override
  void didUpdateWidget(covariant _HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final itemCountChanged = oldWidget.items.length != widget.items.length;
    final itemsChanged =
        itemCountChanged ||
        _heroCarouselItemsSignature(oldWidget.items) !=
            _heroCarouselItemsSignature(widget.items);
    if (_index >= widget.items.length && widget.items.isNotEmpty) {
      _index = widget.items.length - 1;
    }
    if (itemsChanged && widget.items.isNotEmpty) {
      _index = _index.clamp(0, widget.items.length - 1).toInt();
      _page = _initialLoopPageForItemCount(widget.items.length) + _index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(_page);
        }
      });
    }
    if (itemsChanged) _syncAutoRotate();
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    _trailerBusyController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncAutoRotate() {
    _rotateTimer?.cancel();
    if (!mounted ||
        _autoRotatePaused ||
        widget.items.length < 2 ||
        juicrMotionDisabled(context)) {
      return;
    }
    if (!_isCurrentRoute(context)) {
      _rotateTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) _syncAutoRotate();
      });
      return;
    }
    _rotateTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      if (_autoRotatePaused ||
          widget.items.length < 2 ||
          juicrMotionDisabled(context)) {
        return;
      }
      if (!_isCurrentRoute(context)) {
        _syncAutoRotate();
        return;
      }
      if (!_controller.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncAutoRotate();
        });
        return;
      }
      _animateToRelativePage(1, reason: 'auto');
    });
  }

  bool _isCurrentRoute(BuildContext context) {
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  int _logicalIndex(int page, int itemCount) {
    if (itemCount < 1) return 0;
    return page % itemCount;
  }

  int _nearestPageForLogicalIndex(int targetIndex) {
    final itemCount = widget.items.length;
    if (itemCount < 2) return 0;
    final normalizedTarget = targetIndex.clamp(0, itemCount - 1).toInt();
    final base = _page - (_page % itemCount) + normalizedTarget;
    final candidates = [base - itemCount, base, base + itemCount];
    candidates.sort(
      (left, right) => (left - _page).abs().compareTo((right - _page).abs()),
    );
    return candidates.first.clamp(0, _loopPageCount - 1).toInt();
  }

  int _initialLoopPageForItemCount(int itemCount) {
    if (itemCount < 2) return 0;
    final middle = _loopPageCount ~/ 2;
    return middle - (middle % itemCount);
  }

  @override
  Widget build(BuildContext context) {
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final stageHeight = compactLandscape ? 166.0 : 218.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compactLandscape ? 14 : 18,
        compactLandscape ? 2 : 8,
        compactLandscape ? 14 : 18,
        compactLandscape ? 10 : 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _HeroEditorialHeader(title: widget.title)),
          SizedBox(height: compactLandscape ? 5 : 10),
          SizedBox(
            height: stageHeight,
            child: PageView.builder(
              controller: _controller,
              clipBehavior: Clip.none,
              physics: const BouncingScrollPhysics(),
              itemCount: widget.items.length < 2
                  ? (widget.items.isEmpty ? 1 : widget.items.length)
                  : _loopPageCount,
              onPageChanged: (page) => setState(() {
                _page = page;
                _index = _logicalIndex(page, widget.items.length);
              }),
              itemBuilder: (context, page) {
                final item = widget.items.isEmpty
                    ? null
                    : widget.items[_logicalIndex(page, widget.items.length)];
                final hasTrailer =
                    item != null &&
                    widget.trailerAvailability[_heroTrailerAvailabilityKey(
                          item,
                        )] !=
                        null;
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final rawPage =
                        _controller.hasClients &&
                            _controller.position.haveDimensions
                        ? _controller.page ?? _page.toDouble()
                        : _page.toDouble();
                    final pageOffset = (page - rawPage).clamp(-1.0, 1.0);
                    final distance = pageOffset.abs();
                    final scale = 1 - (distance * 0.16);
                    final xOffset = -pageOffset * 18;
                    final yOffset = distance * 16;
                    return Transform.translate(
                      offset: Offset(xOffset, yOffset),
                      child: Transform.scale(scale: scale, child: child),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _HeroSlide(
                      item: item,
                      loading: widget.loading,
                      editorialGenres: widget.editorialGenres,
                      focused: true,
                      onPlay: () {
                        item == null
                            ? widget.onDiscover()
                            : widget.onPlay(item);
                      },
                      trailerLoading:
                          item != null && _trailerLoadingKey == item.id,
                      trailerAnimation: _trailerBusyController,
                      onTrailer: item == null
                          ? null
                          : !hasTrailer
                          ? null
                          : () {
                              if (item != null) _openTrailer(item);
                            },
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.items.length > 1) ...[
            SizedBox(height: compactLandscape ? 4 : 6),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final itemCount = widget.items.length;
                final rawPage =
                    _controller.hasClients &&
                        _controller.position.haveDimensions
                    ? _controller.page ?? _page.toDouble()
                    : _page.toDouble();
                final activeIndex = _logicalIndex(rawPage.round(), itemCount);
                return _ThreeDotHeroIndicator(
                  itemCount: itemCount,
                  activeIndex: activeIndex,
                  onTap: (index) {
                    _controller.animateToPage(
                      _nearestPageForLogicalIndex(index),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

String _heroCarouselItemsSignature(List<CatalogItem> items) {
  return items.map(_homeContentKey).join('|');
}

class _HeroEditorialHeader extends StatelessWidget {
  const _HeroEditorialHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayTitle = _titleCaseHomeLabel(title);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _heroHeaderKicker(displayTitle),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.primary.withValues(alpha: 0.78),
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 22,
          child: _AutoScrollTitle(
            text: displayTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.35,
            ),
          ),
        ),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                colorScheme.primary.withValues(alpha: 0.46),
                colorScheme.onSurface.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
          ),
          child: const SizedBox(width: 74, height: 2),
        ),
      ],
    );
  }
}

String _heroHeaderKicker(String title) {
  final normalized = title.toLowerCase();
  if (normalized.contains('trend') || normalized.contains('hot')) {
    return 'PULSE CHECK';
  }
  if (normalized.contains('theater') || normalized.contains('cinema')) {
    return 'NOW PLAYING';
  }
  return 'TODAY\'S CURATION';
}

List<int> _centeredIndicatorIndexes(int itemCount, int activeIndex) {
  return [
    for (var offset = -1; offset <= 1; offset += 1)
      (activeIndex + offset + itemCount) % itemCount,
  ];
}

class _ThreeDotHeroIndicator extends StatelessWidget {
  const _ThreeDotHeroIndicator({
    required this.itemCount,
    required this.activeIndex,
    required this.onTap,
  });

  final int itemCount;
  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final indexes = _centeredIndicatorIndexes(itemCount, activeIndex);
    final color = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var slot = 0; slot < indexes.length; slot += 1) ...[
          GestureDetector(
            onTap: () => onTap(indexes[slot]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: slot == 1 ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: color.withValues(alpha: slot == 1 ? 0.72 : 0.24),
              ),
            ),
          ),
          if (slot != indexes.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _AnimatedHeroStackCard extends StatelessWidget {
  const _AnimatedHeroStackCard({
    required this.pageOffset,
    required this.item,
    required this.editorialGenres,
    required this.loading,
    required this.onTap,
    required this.onTrailer,
    required this.trailerLoading,
    required this.trailerAnimation,
  });

  final double pageOffset;
  final CatalogItem? item;
  final List<String> editorialGenres;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback onTrailer;
  final bool trailerLoading;
  final Animation<double> trailerAnimation;

  @override
  Widget build(BuildContext context) {
    final distance = pageOffset.abs().clamp(0.0, 1.0);
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final focused = distance < 0.18;
    final widthFactor = focused
        ? (compactLandscape ? 0.74 : 0.82)
        : (compactLandscape ? 0.28 : 0.34);
    final height = focused
        ? (compactLandscape ? 148.0 : 190.0)
        : (compactLandscape ? 118.0 : 156.0);
    final horizontalOffset =
        pageOffset.clamp(-1.0, 1.0) * (compactLandscape ? 138 : 180);
    final verticalOffset = focused ? 0.0 : (compactLandscape ? 7.0 : 10.0);
    final opacity = (1.0 - distance * 0.22).clamp(0.0, 1.0);
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Transform.translate(
        offset: Offset(horizontalOffset, verticalOffset),
        child: Opacity(
          opacity: opacity,
          child: SizedBox(
            height: height,
            child: _HeroSlide(
              item: item,
              editorialGenres: editorialGenres,
              loading: loading && focused,
              focused: focused,
              onPlay: onTap,
              trailerLoading: trailerLoading,
              trailerAnimation: trailerAnimation,
              onTrailer: focused && item != null ? onTrailer : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({
    required this.item,
    required this.editorialGenres,
    required this.loading,
    required this.focused,
    required this.onPlay,
    required this.onTrailer,
    required this.trailerLoading,
    required this.trailerAnimation,
  });

  final CatalogItem? item;
  final List<String> editorialGenres;
  final bool loading;
  final bool focused;
  final VoidCallback onPlay;
  final VoidCallback? onTrailer;
  final bool trailerLoading;
  final Animation<double> trailerAnimation;

  @override
  Widget build(BuildContext context) {
    final image = item?.background ?? item?.poster;
    final colorScheme = Theme.of(context).colorScheme;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final cacheWidth = _homeImageCacheWidth(
      context,
      MediaQuery.sizeOf(context).width * (compactLandscape ? 0.72 : 0.82),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: focused ? 0.34 : 0.2),
            blurRadius: focused ? 22 : 14,
            spreadRadius: focused ? -6 : -9,
            offset: Offset(0, focused ? 12 : 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onPlay,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (loading)
                  const _HeroFallback()
                else if (image != null)
                  Image.network(
                    image,
                    fit: BoxFit.cover,
                    cacheWidth: cacheWidth,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const _HeroFallback();
                    },
                    errorBuilder: (_, __, ___) => const _HeroFallback(),
                  )
                else
                  const _HeroFallback(),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.18),
                        Colors.black.withValues(alpha: 0.58),
                      ],
                      stops: const [0, 0.44, 0.72, 1],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: focused ? 0.38 : 0.28),
                        Colors.black.withValues(alpha: focused ? 0.14 : 0.08),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.36, 0.78],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: focused ? 14 : 10,
                  top: focused ? 14 : 12,
                  child: _MetaBadge(item: item, compact: !focused),
                ),
                if (onTrailer != null)
                  Positioned(
                    right: focused ? 14 : 10,
                    top: focused ? 14 : 12,
                    child: Semantics(
                      button: true,
                      enabled: !trailerLoading,
                      label: trailerLoading
                          ? 'Loading trailer'
                          : 'Watch trailer',
                      child: ExcludeSemantics(
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.58),
                          elevation: focused ? 4 : 2,
                          shadowColor: Colors.black.withValues(alpha: 0.42),
                          shape: const StadiumBorder(),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(99),
                            onTap: trailerLoading ? null : onTrailer,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: focused ? 10 : 7,
                                vertical: focused ? 7 : 5,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  trailerLoading
                                      ? _HomeTrailerBusyIcon(
                                          animation: trailerAnimation,
                                          size: focused ? 15 : 10,
                                        )
                                      : Icon(
                                          Icons.video_library_rounded,
                                          color: Colors.white,
                                          size: focused ? 15 : 10,
                                        ),
                                  if (focused) ...[
                                    const SizedBox(width: 5),
                                    Text(
                                      trailerLoading ? 'Loading...' : 'Trailer',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
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
                Positioned(
                  left: focused ? 14 : 10,
                  right: focused ? 62 : 42,
                  bottom: focused ? 18 : 12,
                  child: _HeroCardCaption(
                    item: item,
                    editorialGenres: editorialGenres,
                    loading: loading,
                    focused: focused,
                  ),
                ),
                Positioned(
                  right: focused ? 14 : 10,
                  bottom: focused ? 14 : 12,
                  child: ValueListenableBuilder<Map<String, CatalogItem>>(
                    valueListenable: AppState.library,
                    builder: (context, library, _) {
                      final saved =
                          item != null && library.containsKey(item!.id);
                      return Material(
                        color: JuicrVisual.floatingActionSurface(colorScheme),
                        elevation: focused ? 4 : 2,
                        shadowColor: JuicrVisual.floatingActionShadow(
                          colorScheme,
                        ),
                        shape: const CircleBorder(),
                        child: SizedBox(
                          width: focused ? 38 : 24,
                          height: focused ? 38 : 24,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: item == null
                                ? null
                                : () => AppState.toggleSaved(item!),
                            icon: Icon(
                              saved
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: focused ? 20 : 13,
                            ),
                            color: saved ? colorScheme.primary : Colors.white,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: saved
                                  ? colorScheme.primary
                                  : Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
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

class _HomeTrailerBusyIcon extends StatelessWidget {
  const _HomeTrailerBusyIcon({required this.animation, required this.size});

  final Animation<double> animation;
  final double size;

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: animation,
      child: Icon(Icons.hourglass_top_rounded, color: Colors.white, size: size),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.18),
        const Color(0xFF20251F),
      ),
    );
  }
}

class _HeroCardCaption extends StatelessWidget {
  const _HeroCardCaption({
    required this.item,
    required this.editorialGenres,
    required this.loading,
    required this.focused,
  });

  final CatalogItem? item;
  final List<String> editorialGenres;
  final bool loading;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final title = loading
        ? 'Loading picks...'
        : item?.name ?? 'Find your next watch';
    final subtitle = loading
        ? 'A little shelf we would point at today.'
        : _heroCardSubtitle(item, editorialGenres);
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      color: Colors.white,
      fontSize: focused ? (compactLandscape ? 18 : 21) : 11,
      fontWeight: FontWeight.w900,
      letterSpacing: focused ? -0.8 : -0.2,
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: focused ? 0.78 : 0.66),
          blurRadius: focused ? 10 : 6,
          offset: Offset(0, focused ? 2 : 1),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: focused ? (compactLandscape ? 23 : 27) : 15,
          child: _AutoScrollTitle(text: title, style: titleStyle),
        ),
        SizedBox(height: compactLandscape ? 2 : 3),
        SizedBox(
          height: focused ? (compactLandscape ? 15 : 17) : 12,
          child: _AutoScrollTitle(
            text: subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: focused ? (compactLandscape ? 11 : 12) : 8,
              fontWeight: FontWeight.w700,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: focused ? 0.68 : 0.56),
                  blurRadius: focused ? 8 : 5,
                  offset: Offset(0, focused ? 1.6 : 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _heroCardSubtitle(CatalogItem? item, List<String> editorialGenres) {
  if (item == null) return 'A little shelf we would point at today.';
  final tags = <String>[];
  final mainTag = editorialGenres
      .map(_displayGenre)
      .firstWhere((genre) => genre != 'All genres', orElse: () => '');
  if (mainTag.isNotEmpty) tags.add(mainTag);
  for (final genre in item.genres) {
    final tag = _displayGenre(genre);
    if (tag == 'All genres') continue;
    if (tags.any((existing) => existing.toLowerCase() == tag.toLowerCase())) {
      continue;
    }
    tags.add(tag);
    if (tags.length >= 2) break;
  }
  if (tags.length < 2) {
    final typeTag = _mediaTypeTag(item.type);
    if (!tags.any(
      (existing) => existing.toLowerCase() == typeTag.toLowerCase(),
    )) {
      tags.add(typeTag);
    }
  }
  final parts = <String>[
    if (item.year != null && item.year!.isNotEmpty) item.year!,
    if (item.imdbRating != null && item.imdbRating!.isNotEmpty)
      'IMDb ${item.imdbRating}',
    if (tags.isNotEmpty) tags.take(2).join(', '),
  ];
  return parts.isEmpty
      ? 'A little shelf we would point at today.'
      : parts.join(' - ');
}

String _mediaTypeTag(MediaType type) {
  return switch (type) {
    MediaType.movie => 'Movie',
    MediaType.series => 'Series',
    MediaType.animation => 'Animation',
    MediaType.liveTv => 'Live TV',
    MediaType.music => 'Music',
    MediaType.nsfw => 'Mature',
    _ => 'Title',
  };
}

class _ContinuePromptSummary {
  const _ContinuePromptSummary({
    required this.type,
    required this.count,
    required this.icon,
    required this.subtitle,
  });

  final MediaType type;
  final int count;
  final IconData icon;
  final String subtitle;
}

List<_ContinuePromptSummary> _continuePromptSummaries(
  List<ContinueWatchingEntry> entries,
) {
  final counts = <MediaType, int>{};
  for (final entry in entries) {
    counts[entry.item.type] = (counts[entry.item.type] ?? 0) + 1;
  }
  final orderedTypes = const [
    MediaType.movie,
    MediaType.series,
    MediaType.animation,
    MediaType.music,
    MediaType.nsfw,
  ];
  final summaries = <_ContinuePromptSummary>[];
  for (final type in orderedTypes) {
    final count = counts[type] ?? 0;
    if (count <= 0) continue;
    final label = _continuePromptTypeLabel(type, count);
    final lines = _continuePromptLines(type, count, label);
    final start =
        _editorialBucket(offset: count + type.index * 17) % lines.length;
    for (var offset = 0; offset < lines.length; offset += 1) {
      final index = (start + offset) % lines.length;
      summaries.add(
        _ContinuePromptSummary(
          type: type,
          count: count,
          icon: _continuePromptIcon(type, offset),
          subtitle: lines[index],
        ),
      );
    }
  }
  if (summaries.isNotEmpty) return summaries;
  final count = entries.length;
  final label = count == 1 ? 'title' : 'titles';
  return [
    _ContinuePromptSummary(
      type: MediaType.movie,
      count: count,
      icon: Icons.history_rounded,
      subtitle: '$count $label still waiting on you',
    ),
  ];
}

IconData _continuePromptIcon(MediaType type, [int variant = 0]) {
  return switch (type) {
    MediaType.movie => const [
      Icons.movie_creation_rounded,
      Icons.local_movies_rounded,
      Icons.theaters_rounded,
      Icons.movie_filter_rounded,
    ][variant % 4],
    MediaType.series => const [
      Icons.live_tv_rounded,
      Icons.tv_rounded,
      Icons.video_library_rounded,
      Icons.play_lesson_rounded,
    ][variant % 4],
    MediaType.animation => const [
      Icons.auto_awesome_rounded,
      Icons.bolt_rounded,
      Icons.flare_rounded,
      Icons.blur_on_rounded,
    ][variant % 4],
    MediaType.music => const [
      Icons.music_note_rounded,
      Icons.queue_music_rounded,
      Icons.album_rounded,
      Icons.graphic_eq_rounded,
    ][variant % 4],
    MediaType.nsfw => const [
      Icons.lock_rounded,
      Icons.privacy_tip_rounded,
      Icons.visibility_off_rounded,
      Icons.shield_rounded,
    ][variant % 4],
    MediaType.liveTv => const [
      Icons.tv_rounded,
      Icons.live_tv_rounded,
      Icons.connected_tv_rounded,
      Icons.sensors_rounded,
    ][variant % 4],
  };
}

String _continuePromptTypeLabel(MediaType type, int count) {
  final plural = count != 1;
  return switch (type) {
    MediaType.movie => plural ? 'movies' : 'movie',
    MediaType.series => plural ? 'series' : 'series',
    MediaType.animation => 'animation',
    MediaType.music => 'music',
    MediaType.nsfw => plural ? 'mature titles' : 'mature title',
    MediaType.liveTv => 'live TV',
  };
}

List<String> _continuePromptLines(MediaType type, int count, String label) {
  return switch (type) {
    MediaType.movie => [
      '$count $label left unwatched',
      '$count $label saved for the good part',
      '$count $label saved from the cliff',
      '$count $label keeping the couch warm',
    ],
    MediaType.series => [
      '$count $label still mid-conversation',
      '$count $label with loose ends',
      '$count $label asking for one more',
      '$count $label waiting where you left them',
    ],
    MediaType.animation => [
      '$count $label arcs still glowing',
      '$count $label saved mid-power-up',
      '$count $label one episode from chaos',
      '$count $label with energy left',
    ],
    MediaType.music => [
      '$count $label sessions still warm',
      '$count $label picks waiting their turn',
      '$count $label tracks left humming',
      '$count $label moments you parked',
    ],
    MediaType.nsfw => [
      '$count $label kept private',
      '$count $label waiting quietly',
      '$count $label saved on your terms',
      '$count $label staying out of the way',
    ],
    MediaType.liveTv => [
      '$count $label moments waiting',
      '$count $label sessions saved',
      '$count $label picks parked',
      '$count $label ready when you are',
    ],
  };
}

String _continuePromptSignature(List<ContinueWatchingEntry> entries) {
  final counts = <MediaType, int>{};
  for (final entry in entries) {
    counts[entry.item.type] = (counts[entry.item.type] ?? 0) + 1;
  }
  return MediaType.values
      .map((type) => '${type.compatTypeValue}:${counts[type] ?? 0}')
      .join('|');
}

class _ContinuePromptCard extends StatefulWidget {
  const _ContinuePromptCard({required this.entries, required this.onTap});

  final List<ContinueWatchingEntry> entries;
  final VoidCallback onTap;

  @override
  State<_ContinuePromptCard> createState() => _ContinuePromptCardState();
}

class _ContinuePromptCardState extends State<_ContinuePromptCard> {
  Timer? _rotationTimer;
  int _summaryIndex = 0;
  String _signature = '';

  @override
  void initState() {
    super.initState();
    _signature = _continuePromptSignature(widget.entries);
    _syncRotation();
  }

  @override
  void didUpdateWidget(covariant _ContinuePromptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = _continuePromptSignature(widget.entries);
    if (nextSignature != _signature) {
      _signature = nextSignature;
      _summaryIndex = 0;
      _syncRotation();
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  void _syncRotation() {
    _rotationTimer?.cancel();
    final summaries = _continuePromptSummaries(widget.entries);
    if (summaries.length < 2) return;
    if (_summaryIndex >= summaries.length) _summaryIndex = 0;
    _rotationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      setState(() {
        _summaryIndex = (_summaryIndex + 1) % summaries.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final summaries = _continuePromptSummaries(widget.entries);
    final summary = summaries[_summaryIndex.clamp(0, summaries.length - 1)];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compactLandscape ? 14 : 18,
        0,
        compactLandscape ? 14 : 18,
        compactLandscape ? 12 : 20,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          child: Container(
            padding: EdgeInsets.all(compactLandscape ? 10 : 14),
            decoration: JuicrVisual.elevatedCardDecoration(
              colorScheme,
              radius: 18,
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.58,
              ),
              borderAlpha: 0.32,
            ),
            child: Row(
              children: [
                Container(
                  width: compactLandscape ? 34 : 42,
                  height: compactLandscape ? 34 : 42,
                  decoration: JuicrVisual.elevatedIconDecoration(
                    colorScheme,
                    radius: 14,
                  ),
                  child: AnimatedSwitcher(
                    duration: _continuePromptSwapDuration,
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final scale = Tween<double>(
                        begin: 0.72,
                        end: 1,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: scale, child: child),
                      );
                    },
                    child: Icon(
                      summary.icon,
                      key: ValueKey<String>(
                        'continue-icon-${summary.icon.codePoint}-${summary.icon.fontFamily}-${summary.subtitle}',
                      ),
                      color: colorScheme.primary,
                      size: compactLandscape ? 19 : 22,
                    ),
                  ),
                ),
                SizedBox(width: compactLandscape ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Pick up where you left off?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      SizedBox(
                        height: 17,
                        child: _ContinuePromptAnimatedContext(
                          text: summary.subtitle,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 112),
                  child: FilledButton(
                    onPressed: widget.onTap,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Text(
                      'Continue',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

const Duration _continuePromptSwapDuration = Duration(milliseconds: 520);

class _ContinuePromptAnimatedContext extends StatelessWidget {
  const _ContinuePromptAnimatedContext({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _continuePromptSwapDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.none,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final offset =
            Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>('continue-context-$text'),
        child: _AutoScrollTitle(text: text, style: style),
      ),
    );
  }
}

class _HomeRailEntry {
  const _HomeRailEntry({required this.item, this.progress});

  final CatalogItem item;
  final ContinueWatchingEntry? progress;
}

class _HomeRail extends StatelessWidget {
  const _HomeRail({
    required this.title,
    required this.entries,
    required this.onTap,
    this.subtitle,
    this.onOpenDiscovery,
  });

  final String title;
  final List<_HomeRailEntry> entries;
  final ValueChanged<CatalogItem> onTap;
  final String? subtitle;
  final VoidCallback? onOpenDiscovery;

  @override
  Widget build(BuildContext context) {
    final displayTitle = _titleCaseHomeLabel(title);
    final compactLandscape = JuicrVisual.compactLandscape(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(bottom: compactLandscape ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compactLandscape ? 14 : 18,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 22,
                          child: _AutoScrollTitle(
                            text: displayTitle,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          SizedBox(
                            height: 17,
                            child: _AutoScrollTitle(
                              text: subtitle!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onOpenDiscovery != null)
                    _RailDiscoveryButton(onTap: onOpenDiscovery!),
                ],
              ),
            ),
            SizedBox(height: compactLandscape ? 6 : 10),
            SizedBox(
              height: compactLandscape ? 158 : 206,
              child: ListView.separated(
                padding: EdgeInsets.symmetric(
                  horizontal: compactLandscape ? 14 : 18,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: entries.length,
                separatorBuilder: (_, __) =>
                    SizedBox(width: compactLandscape ? 8 : 10),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return _HomePosterCard(
                    entry: entry,
                    onTap: () => onTap(entry.item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailDiscoveryButton extends StatelessWidget {
  const _RailDiscoveryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Open this shelf',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: JuicrVisual.elevatedCircleDecoration(
            colorScheme,
            shadowAlpha: 0.1,
          ),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 24,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _RankedHomeRail extends StatelessWidget {
  const _RankedHomeRail({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.onTap,
    this.showRankPills = true,
    this.onOpenDiscovery,
  });

  final String title;
  final String subtitle;
  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onTap;
  final bool showRankPills;
  final VoidCallback? onOpenDiscovery;

  @override
  Widget build(BuildContext context) {
    final displayTitle = _titleCaseHomeLabel(title);
    final compactLandscape = JuicrVisual.compactLandscape(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(bottom: compactLandscape ? 12 : 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compactLandscape ? 14 : 18,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 23,
                          child: _AutoScrollTitle(
                            text: displayTitle,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.35,
                                ),
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          SizedBox(
                            height: 17,
                            child: _AutoScrollTitle(
                              text: subtitle,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onOpenDiscovery != null)
                    _RailDiscoveryButton(onTap: onOpenDiscovery!),
                ],
              ),
            ),
            SizedBox(
              height: subtitle.isEmpty
                  ? (compactLandscape ? 5 : 8)
                  : (compactLandscape ? 7 : 12),
            ),
            SizedBox(
              height: compactLandscape ? 150 : 194,
              child: ListView.separated(
                padding: EdgeInsets.symmetric(
                  horizontal: compactLandscape ? 14 : 18,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    SizedBox(width: compactLandscape ? 8 : 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (showRankPills) {
                    return _RankedPosterCard(
                      item: item,
                      rank: index + 1,
                      onTap: () => onTap(item),
                    );
                  }
                  return _HomePosterCard(
                    entry: _HomeRailEntry(item: item),
                    onTap: () => onTap(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeShelfPage extends StatelessWidget {
  const _HomeShelfPage({
    required this.title,
    required this.items,
    this.showRankPills = false,
    this.externalTopSignal = false,
  });

  final String title;
  final List<CatalogItem> items;
  final bool showRankPills;
  final bool externalTopSignal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayTitle = _titleCaseHomeLabel(title);
    if (showRankPills) {
      return _TopTenShelfPage(
        title: displayTitle,
        items: items,
        externalTopSignal: externalTopSignal,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Text(displayTitle),
              backgroundColor: colorScheme.surface,
              surfaceTintColor: colorScheme.surfaceTint,
            ),
            if (items.isEmpty)
              const SliverFillRemaining(child: CatalogEmptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                sliver: SliverGrid.builder(
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.58,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _HomeShelfGridCard(
                      item: item,
                      rank: showRankPills ? index + 1 : null,
                      onTap: () => Navigator.of(context).push(
                        AppPageRoute<void>(
                          builder: (_) => DetailsPage(item: item),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopTenShelfPage extends StatelessWidget {
  const _TopTenShelfPage({
    required this.title,
    required this.items,
    required this.externalTopSignal,
  });

  final String title;
  final List<CatalogItem> items;
  final bool externalTopSignal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayTitle = _titleCaseHomeLabel(title);
    final rankedLimit = _rankedShelfLimit(title, externalTopSignal);
    final rankedItems = items.take(rankedLimit).toList(growable: false);
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Text(displayTitle),
              backgroundColor: colorScheme.surface,
              surfaceTintColor: colorScheme.surfaceTint,
            ),
            if (rankedItems.isEmpty)
              const SliverFillRemaining(child: CatalogEmptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                sliver: SliverList.separated(
                  itemCount: rankedItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final rank = index + 1;
                    final item = rankedItems[index];
                    return _TopTenWideCard(
                      item: item,
                      rank: rank,
                      reason: _topTenItemReason(
                        item,
                        rank,
                        externalTopSignal: externalTopSignal,
                      ),
                      externalTopSignal: externalTopSignal,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

int _rankedShelfLimit(String title, bool externalTopSignal) {
  final normalized = title.trim().toLowerCase();
  if (externalTopSignal && normalized != "juicr's top 10") return 20;
  return 10;
}

class _TopTenWideCard extends StatelessWidget {
  const _TopTenWideCard({
    required this.item,
    required this.rank,
    required this.reason,
    required this.externalTopSignal,
  });

  final CatalogItem item;
  final int rank;
  final String reason;
  final bool externalTopSignal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sourceLabel = externalTopSignal ? 'shared trend' : 'local';
    final background = item.background ?? item.poster;
    final poster = item.type.isLive ? item.logo ?? item.poster : item.poster;
    final backgroundCacheWidth = _homeImageCacheWidth(context, 360);
    final posterCacheWidth = _homeImageCacheWidth(context, 96);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: 'Open $sourceLabel rank $rank, ${item.name}',
        child: InkWell(
          onTap: () {
            Navigator.of(
              context,
            ).push(AppPageRoute<void>(builder: (_) => DetailsPage(item: item)));
          },
          child: SizedBox(
            height: 154,
            child: Stack(
              children: [
                Positioned.fill(
                  child: background == null || background.isEmpty
                      ? ColoredBox(color: colorScheme.surfaceContainerHighest)
                      : Image.network(
                          background,
                          fit: BoxFit.cover,
                          cacheWidth: backgroundCacheWidth,
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                        ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xF2000000),
                          Color(0xC8000000),
                          Color(0x52000000),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 82,
                          height: 124,
                          child: poster == null || poster.isEmpty
                              ? ColoredBox(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.movie_rounded,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.54,
                                    ),
                                  ),
                                )
                              : Image.network(
                                  poster,
                                  fit: item.type.isLive
                                      ? BoxFit.contain
                                      : BoxFit.cover,
                                  cacheWidth: posterCacheWidth,
                                  errorBuilder: (_, __, ___) => ColoredBox(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.broken_image_rounded,
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.54,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _RankBadge(rank: rank),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _AutoScrollTitle(
                                    text: item.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              reason,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _HomeShelfGridCard extends StatelessWidget {
  const _HomeShelfGridCard({
    required this.item,
    required this.onTap,
    this.rank,
  });

  final CatalogItem item;
  final VoidCallback onTap;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cacheWidth = _homeImageCacheWidth(context, 120);
    final poster = item.type.isLive ? item.logo ?? item.poster : item.poster;
    final imageFit = item.type.isLive ? BoxFit.contain : BoxFit.cover;
    return Semantics(
      button: true,
      label: 'Open ${item.name}',
      hint: 'Show details',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (poster != null && poster.isNotEmpty)
                        Image.network(
                          poster,
                          fit: imageFit,
                          cacheWidth: cacheWidth,
                          errorBuilder: (_, __, ___) =>
                              const AppShimmerBox(radius: 14),
                        )
                      else
                        const AppShimmerBox(radius: 14),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _MetaBadge(item: item, compact: true),
                      ),
                      if (rank != null)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: _RankBadge(rank: rank!),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankedPosterCard extends StatelessWidget {
  const _RankedPosterCard({
    required this.item,
    required this.rank,
    required this.onTap,
  });

  final CatalogItem item;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final poster = item.poster;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final cardWidth = compactLandscape ? 104.0 : 124.0;
    final cacheWidth = _homeImageCacheWidth(context, cardWidth);
    final rankLabel = rank.toString();
    return SizedBox(
      width: cardWidth,
      child: Semantics(
        button: true,
        label: 'Open Juicr top $rankLabel, ${item.name}',
        hint: 'Show details',
        child: ExcludeSemantics(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 25,
                  right: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _HomePosterArtwork(
                          poster: poster,
                          cacheWidth: cacheWidth,
                          radius: 16,
                        ),
                        Positioned(
                          left: 8,
                          top: 8,
                          child: _MetaBadge(item: item, compact: true),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: _RankBadge(rank: rank),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _AutoScrollTitle(
                    text: item.name,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.9),
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

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: JuicrVisual.elevatedCardDecoration(
          colorScheme,
          radius: 999,
          color: Colors.black.withValues(alpha: 0.64),
          borderAlpha: 0,
          shadowAlpha: 0.12,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            'Rank $rank',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
              height: 1.05,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePosterCard extends StatelessWidget {
  const _HomePosterCard({required this.entry, required this.onTap});

  final _HomeRailEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final poster = entry.item.poster;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final cardWidth = compactLandscape ? 104.0 : 124.0;
    final cacheWidth = _homeImageCacheWidth(context, cardWidth);
    return SizedBox(
      width: cardWidth,
      child: Semantics(
        button: true,
        label: 'Open ${entry.item.name}',
        hint: 'Show details',
        child: ExcludeSemantics(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _HomePosterArtwork(
                          poster: poster,
                          cacheWidth: cacheWidth,
                          radius: 14,
                        ),
                        if (entry.progress != null)
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: LinearProgressIndicator(
                              value: entry.progress!.progress
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                              minHeight: 3,
                              borderRadius: BorderRadius.circular(99),
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                        Positioned(
                          left: 8,
                          top: 8,
                          child: _MetaBadge(item: entry.item, compact: true),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                _AutoScrollTitle(
                  text: entry.item.name,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w800,
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

class _HomePosterArtwork extends StatelessWidget {
  const _HomePosterArtwork({
    required this.poster,
    required this.cacheWidth,
    required this.radius,
  });

  final String? poster;
  final int cacheWidth;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final posterUrl = poster?.trim();
    if (posterUrl == null || posterUrl.isEmpty) {
      return const _HomeArtworkFallback();
    }
    return Image.network(
      posterUrl,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return AppShimmerBox(radius: radius);
      },
      errorBuilder: (_, __, ___) => const _HomeArtworkFallback(),
    );
  }
}

class _HomeArtworkFallback extends StatelessWidget {
  const _HomeArtworkFallback();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
            colorScheme.surfaceContainerHigh.withValues(alpha: 0.52),
            colorScheme.surface.withValues(alpha: 0.92),
          ],
          stops: const [0, 0.58, 1],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

int _homeImageCacheWidth(BuildContext context, double logicalWidth) {
  final width = logicalWidth * MediaQuery.devicePixelRatioOf(context);
  return width.clamp(160, 900).round();
}

class _AutoScrollTitle extends StatefulWidget {
  const _AutoScrollTitle({
    required this.text,
    required this.style,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  State<_AutoScrollTitle> createState() => _AutoScrollTitleState();
}

class _AutoScrollTitleState extends State<_AutoScrollTitle> {
  static const _pause = Duration(milliseconds: 900);
  final ScrollController _controller = ScrollController();

  bool _started = false;
  bool _overflowing = false;

  @override
  void didUpdateWidget(covariant _AutoScrollTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _started = false;
      _overflowing = false;
      if (_controller.hasClients) _controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startIfNeeded() {
    if (_started || !_controller.hasClients) return;
    if (!_controller.position.hasContentDimensions) return;
    final max = _controller.position.maxScrollExtent;
    if (_overflowing != max > 0 && mounted) {
      setState(() => _overflowing = max > 0);
    }
    if (max <= 0) return;
    _started = true;
    Future<void>.delayed(_pause, _loop);
  }

  Future<void> _loop() async {
    if (!mounted || !_controller.hasClients) return;
    if (!_controller.position.hasContentDimensions) return;
    final max = _controller.position.maxScrollExtent;
    if (max <= 0) return;
    final forwardMs = (max * 34).clamp(1400, 4200).round();
    await _controller.animateTo(
      max,
      duration: Duration(milliseconds: forwardMs),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;
    await Future<void>.delayed(_pause);
    if (!mounted || !_controller.hasClients) return;
    await _controller.animateTo(
      0,
      duration: Duration(milliseconds: (forwardMs * 0.72).round()),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;
    await Future<void>.delayed(_pause);
    if (mounted) unawaited(_loop());
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfNeeded());
    final scroller = SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        textAlign: widget.textAlign,
        maxLines: 1,
        softWrap: false,
        style: widget.style,
      ),
    );
    return SizedBox(
      height: 18,
      child: _overflowing
          ? ShaderMask(
              shaderCallback: (bounds) {
                return LinearGradient(
                  colors: const [
                    Color(0xCCFFFFFF),
                    Colors.white,
                    Colors.white,
                    Color(0xCCFFFFFF),
                  ],
                  stops: const [0, 0.035, 0.965, 1],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: scroller,
            )
          : scroller,
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.item, required this.compact});

  final CatalogItem? item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = _metaBadgeLabel(item);
    if (label == null) return const SizedBox.shrink();
    final rating = label.startsWith('IMDb ') ? label.substring(5).trim() : '';
    final hasRating = rating.isNotEmpty;
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: compact ? 9 : 11,
      fontWeight: FontWeight.w900,
      letterSpacing: compact ? -0.1 : 0,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 9,
          vertical: compact ? 3 : 5,
        ),
        child: hasRating
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('IMDb', maxLines: 1, style: textStyle),
                  SizedBox(width: compact ? 3 : 4),
                  Text(
                    rating,
                    maxLines: 1,
                    style: textStyle.copyWith(color: colorScheme.primary),
                  ),
                ],
              )
            : Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
      ),
    );
  }
}

String? _metaBadgeLabel(CatalogItem? item) {
  if (item == null) return null;
  if (item.isLocalCatalogItem) return 'Local';
  if (item.isUpcoming) return _upcomingDateLabel(item);
  final rating = item.imdbRating?.trim();
  if (rating != null && rating.isNotEmpty) return 'IMDb $rating';
  final year = item.year?.trim();
  if (year != null && year.isNotEmpty) return year;
  return item.type.label;
}

String _upcomingDateLabel(CatalogItem item) {
  final rawDate = item.releaseDate?.trim();
  if (rawDate == null || rawDate.isEmpty) return 'TBA';
  final date = DateTime.tryParse(rawDate);
  if (date == null || date.month < 1 || date.month > 12) return 'TBA';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

class _HomePageSkeleton extends StatelessWidget {
  const _HomePageSkeleton();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: const [
        SliverToBoxAdapter(child: _HeroSkeleton()),
        SliverToBoxAdapter(child: _ContinuePromptSkeleton()),
        SliverToBoxAdapter(child: _RailSkeleton()),
        SliverToBoxAdapter(child: _RailSkeleton(compact: true)),
        SliverToBoxAdapter(child: _RailSkeleton()),
        SliverToBoxAdapter(child: SizedBox(height: 30)),
      ],
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      child: Column(
        children: const [
          AppSkeletonLine(width: 78, height: 9),
          SizedBox(height: 5),
          AppSkeletonLine(width: 104, height: 15),
          SizedBox(height: 7),
          AppSkeletonLine(width: 74, height: 2),
          SizedBox(height: 12),
          _HeroCarouselSkeletonStage(),
          SizedBox(height: 8),
          _HeroIndicatorSkeleton(),
        ],
      ),
    );
  }
}

class _HeroCarouselSkeletonStage extends StatelessWidget {
  const _HeroCarouselSkeletonStage();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactLandscape = JuicrVisual.compactLandscape(context);
        final cardWidth =
            constraints.maxWidth * (compactLandscape ? 0.68 : 0.76);
        final sideOffset = compactLandscape
            ? (cardWidth * 0.72).clamp(190.0, 250.0)
            : (cardWidth * 0.92).clamp(270.0, 318.0);
        final stageHeight = compactLandscape ? 166.0 : 218.0;
        final cardHeight = compactLandscape ? 148.0 : 190.0;
        final sideYOffset = compactLandscape ? 9.0 : 16.0;
        return SizedBox(
          height: stageHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: Offset(-sideOffset, sideYOffset),
                child: Transform.scale(
                  scale: 0.84,
                  child: _HeroSkeletonCard(
                    width: cardWidth,
                    height: cardHeight,
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(sideOffset, sideYOffset),
                child: Transform.scale(
                  scale: 0.84,
                  child: _HeroSkeletonCard(
                    width: cardWidth,
                    height: cardHeight,
                  ),
                ),
              ),
              _HeroSkeletonCard(
                width: cardWidth,
                height: cardHeight,
                focused: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroSkeletonCard extends StatelessWidget {
  const _HeroSkeletonCard({
    required this.width,
    required this.height,
    this.focused = false,
  });

  final double width;
  final double height;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: focused ? 0.32 : 0.2),
              blurRadius: focused ? 22 : 14,
              spreadRadius: focused ? -6 : -8,
              offset: Offset(0, focused ? 12 : 9),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppShimmerBox(radius: 24),
              Positioned(
                left: focused ? 14 : 8,
                top: focused ? 14 : 10,
                child: AppShimmerBox(
                  width: focused ? 62 : 42,
                  height: focused ? 22 : 15,
                  radius: 99,
                ),
              ),
              if (focused)
                const Positioned(
                  right: 14,
                  top: 14,
                  child: AppShimmerBox(width: 70, height: 28, radius: 99),
                ),
              Positioned(
                left: focused ? 14 : 8,
                right: focused ? 78 : 18,
                bottom: focused ? 36 : 30,
                child: AppShimmerBox(height: focused ? 18 : 12, radius: 99),
              ),
              Positioned(
                left: focused ? 14 : 8,
                right: focused ? 120 : 30,
                bottom: focused ? 18 : 16,
                child: AppShimmerBox(height: focused ? 10 : 7, radius: 99),
              ),
              Positioned(
                right: focused ? 14 : 8,
                bottom: focused ? 14 : 12,
                child: AppShimmerBox(
                  width: focused ? 44 : 30,
                  height: focused ? 44 : 30,
                  radius: 999,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroIndicatorSkeleton extends StatelessWidget {
  const _HeroIndicatorSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 10,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          AppSkeletonCircle(size: 6),
          SizedBox(width: 6),
          AppShimmerBox(width: 18, height: 6, radius: 99),
          SizedBox(width: 6),
          AppSkeletonCircle(size: 6),
        ],
      ),
    );
  }
}

class _ContinuePromptSkeleton extends StatelessWidget {
  const _ContinuePromptSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      child: SizedBox(
        height: 70,
        child: Stack(
          children: const [
            Positioned.fill(child: AppSkeletonCard(radius: 18)),
            Positioned(
              left: 14,
              top: 14,
              child: AppSkeletonCard(width: 42, height: 42, radius: 14),
            ),
            Positioned(
              left: 68,
              right: 112,
              top: 18,
              child: AppSkeletonLine(height: 14),
            ),
            Positioned(
              left: 68,
              right: 172,
              bottom: 18,
              child: AppSkeletonLine(height: 9),
            ),
            Positioned(
              right: 14,
              top: 16,
              child: AppShimmerBox(width: 78, height: 38, radius: 99),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cardHeight = compact ? 166.0 : 206.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 0, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: compact ? 0.36 : 0.48,
                        child: const AppSkeletonLine(height: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const AppSkeletonCircle(size: 34),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _RailSkeletonCard(height: cardHeight, compact: compact),
              const SizedBox(width: 10),
              _RailSkeletonCard(height: cardHeight, compact: compact),
              const SizedBox(width: 10),
              _RailSkeletonCard(height: cardHeight, compact: compact),
            ],
          ),
        ],
      ),
    );
  }
}

class _RailSkeletonCard extends StatelessWidget {
  const _RailSkeletonCard({required this.height, required this.compact});

  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 124,
      height: height,
      child: AppPosterSkeleton(compact: compact),
    );
  }
}
