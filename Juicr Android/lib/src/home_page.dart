import 'dart:async';
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
  final StreamApi _api = StreamApi();
  final Stopwatch _homeStartupStopwatch = Stopwatch()..start();
  List<CatalogItem> _heroEditorialItems = const <CatalogItem>[];
  List<_HydratedHomeRail> _editorialRails = const <_HydratedHomeRail>[];
  final Map<String, bool> _heroTrailerAvailability = <String, bool>{};
  final Set<String> _heroTrailerAvailabilityInFlight = <String>{};
  final Map<String, CatalogItem> _heroTrailerAvailabilityPending =
      <String, CatalogItem>{};
  final Map<String, int> _heroTrailerAvailabilityAttempts = <String, int>{};
  final Map<String, CatalogItem> _titleWheelArtworkCache =
      <String, CatalogItem>{};
  final Set<String> _titleWheelArtworkInFlight = <String>{};
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
        _heroEditorialItems = const <CatalogItem>[];
        _editorialRails = const <_HydratedHomeRail>[];
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
      _heroEditorialItems = const <CatalogItem>[];
      _editorialRails = const <_HydratedHomeRail>[];
      _heroTrailerAvailability.clear();
      _heroTrailerAvailabilityInFlight.clear();
      _heroTrailerAvailabilityPending.clear();
      _heroTrailerAvailabilityAttempts.clear();
      _remoteEditorial = null;
      _loading = true;
    });
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
    final currentEditorial = await _api.homeEditorial();
    if (!mounted || generation != _loadGeneration) return;
    if (currentEditorial == null) {
      setState(() {
        _heroEditorialItems = const <CatalogItem>[];
        _editorialRails = const <_HydratedHomeRail>[];
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
      return;
    }

    late final List<List<CatalogItem>> hydrated;
    try {
      hydrated = await Future.wait<List<CatalogItem>>([
        _hydrateHomeEditorialRail(currentEditorial.hero),
        for (final rail in currentEditorial.orderedRails)
          _hydrateHomeEditorialRail(rail),
      ]);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _heroEditorialItems = const <CatalogItem>[];
        _editorialRails = const <_HydratedHomeRail>[];
        _remoteEditorial = null;
        _loading = false;
      });
      DiagnosticLog.add(
        'home sync failed reason=authoritative_hydration_unavailable elapsedMs=${loadStopwatch.elapsedMilliseconds}',
      );
      return;
    }
    if (!mounted || generation != _loadGeneration) return;

    final orderedRailItems = hydrated.skip(1).toList(growable: false);
    final orderedRails = <_HydratedHomeRail>[
      for (var index = 0;
          index < currentEditorial.orderedRails.length;
          index += 1)
        _HydratedHomeRail(
          editorial: currentEditorial.orderedRails[index],
          entries: _rankedEditorialEntries(
            currentEditorial.orderedRails[index],
            orderedRailItems[index],
          ),
        ),
    ];
    final itemCount = hydrated.fold<int>(
      0,
      (count, items) => count + items.length,
    );
    setState(() {
      _heroEditorialItems = hydrated[0];
      _editorialRails = orderedRails;
      _remoteEditorial = currentEditorial;
      _loading = false;
    });
    DiagnosticLog.add(
      'home current edition hydrated edition=${currentEditorial.editionId} rails=${orderedRails.length} items=$itemCount',
    );
    DiagnosticLog.viewTiming(
      surface: 'home',
      state: 'interaction_ready',
      elapsed: loadStopwatch.elapsed,
      mediaKind: 'mixed',
      cacheStateBucket: 'network_or_unknown',
      itemCount: itemCount,
    );
    _warmHeroTrailerAvailability(_heroEditorialItems.take(8));
    _warmHomeTitleWheelArtwork(
      items: _heroEditorialItems,
      generation: generation,
    );
    for (final rail in _editorialRails) {
      _warmHomeTitleWheelArtwork(
        items: rail.items,
        generation: generation,
        editorialRailId: rail.editorial.id,
      );
    }
    _maybeShowMatureContentChoice();
  }

  Future<List<CatalogItem>> _hydrateHomeEditorialRail(
    HomeEditorialRail editorial,
  ) async {
    switch (editorial.id) {
      case 'savedEditorial':
        return const <CatalogItem>[];
      case 'upcomingEditorial':
        return _loadServerUpcomingEditorialItems(editorial);
    }
    if (editorial.items.isEmpty) {
      return _loadServerScopedHeroEditorialItems(editorial);
    }
    final hydrated = <CatalogItem>[];
    for (final signal in editorial.items) {
      if (!signal.isUsable) continue;
      CatalogItem? match;
      try {
        final type = signal.type!;
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
          if (_itemMatchesEditorialSignal(details.item, signal)) {
            match = details.item;
          }
        }
        match ??= await _findHomeEditorialCatalogMatch(signal, type);
      } catch (error) {
        DiagnosticLog.add(
          'home editorial hydration missed rail=${editorial.id} type=${signal.type?.compatTypeValue ?? "unknown"}',
        );
      }
      if (match == null) {
        throw StateError('authoritative_home_item_unavailable');
      }
      hydrated.add(match);
    }
    DiagnosticLog.add(
      'home editorial rail hydrated id=${editorial.id} requested=${editorial.items.length} matched=${hydrated.length}',
    );
    return hydrated.toList(growable: false);
  }

  Future<List<CatalogItem>> _loadServerScopedHeroEditorialItems(
    HomeEditorialRail editorial,
  ) async {
    final types = editorial.types.isEmpty
        ? const <MediaType>[
            MediaType.movie,
            MediaType.series,
            MediaType.animation,
          ]
        : editorial.types;
    final perType = editorial.perType.clamp(1, 12);
    final buckets = await Future.wait<List<CatalogItem>>([
      for (final type in types)
        () async {
          final gathered = <CatalogItem>[];
          var skip = 0;
          for (var page = 0; page < 3 && gathered.length < perType; page += 1) {
            final result = await _api.catalog(
              type: type,
              sort: editorial.sort,
              skip: skip,
              genre: editorial.genres.isEmpty
                  ? 'All genres'
                  : _displayGenre(editorial.genres.first),
              search: editorial.query,
              deepSearch: editorial.query.trim().isNotEmpty,
              preferDefaultCatalog: true,
            );
            for (final item in result.items) {
              if (!_isHomeAllowedByMatureGate(item)) continue;
              if (!_hasHomeArtwork(item)) continue;
              if (editorial.requireGenreMatch &&
                  !_itemMatchesAnyGenre(item, editorial.genres)) {
                continue;
              }
              gathered.add(item);
              if (gathered.length >= perType) break;
            }
            final stride = result.skipDelta ?? result.items.length;
            if (result.items.isEmpty ||
                stride <= 0 ||
                result.hasMore == false) {
              break;
            }
            skip += stride;
          }
          return _dedupeItems(gathered).take(perType).toList(growable: false);
        }(),
    ]);
    return _interleaveBuckets(buckets).take(12).toList(growable: false);
  }

  Future<List<CatalogItem>> _loadServerUpcomingEditorialItems(
    HomeEditorialRail editorial,
  ) async {
    final items = <CatalogItem>[];
    var skip = 0;
    var hasMore = true;
    for (var page = 0; page < 8 && hasMore; page += 1) {
      late final StreamCatalogResult result;
      try {
        result = await _api.catalog(
          type: MediaType.movie,
          sort: CatalogSort.upcoming,
          year: editorial.year,
          skip: skip,
          preferDefaultCatalog: true,
        );
      } catch (error) {
        DiagnosticLog.add(
          'home upcoming editorial hydration missed skip=$skip',
        );
        break;
      }
      items.addAll(result.items);
      final stride = result.skipDelta ?? result.items.length;
      hasMore = result.hasMore ?? result.items.isNotEmpty;
      if (result.items.isEmpty || stride <= 0) break;
      skip += stride;
    }
    return items.toList(growable: false);
  }

  Future<CatalogItem?> _findHomeEditorialCatalogMatch(
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
      if (_itemMatchesEditorialSignal(item, signal)) return item;
    }
    return null;
  }

  void _warmHomeTitleWheelArtwork({
    required List<CatalogItem> items,
    required int generation,
    String? editorialRailId,
  }) {
    if (items.isEmpty) return;
    final candidates = homeTitleWheelHydrationCandidates(items);
    if (candidates.isEmpty) return;
    unawaited(() async {
      final hydrated = <CatalogItem>[];
      var skippedCached = 0;
      for (final item in candidates) {
        if (!mounted || generation != _loadGeneration) return;
        final key = _itemKey(item);
        final cached = _titleWheelArtworkCache[key];
        if (cached != null) {
          hydrated.add(homeArtworkOnlyMerge(item, cached));
          skippedCached += 1;
          continue;
        }
        if (!_titleWheelArtworkInFlight.add(key)) continue;
        try {
          final details = await _api.meta(item).timeout(
                const Duration(seconds: 5),
              );
          final artworkOnly = homeArtworkOnlyMerge(item, details.item);
          if ((artworkOnly.logo ?? '').trim().isNotEmpty) {
            _titleWheelArtworkCache[key] = artworkOnly;
            hydrated.add(artworkOnly);
          }
        } catch (error) {
          DiagnosticLog.add(
            'mobile title wheel artwork hydrate skipped rail=${editorialRailId ?? "hero"} type=${item.type.compatTypeValue} id=${item.id} error=${error.runtimeType}',
          );
        } finally {
          _titleWheelArtworkInFlight.remove(key);
        }
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      if (!mounted || generation != _loadGeneration || hydrated.isEmpty) {
        return;
      }
      setState(() {
        if (editorialRailId == null) {
          _heroEditorialItems = _mergeHomeTitleWheelHydratedItems(
            _heroEditorialItems,
            hydrated,
          );
          return;
        }
        _editorialRails = [
          for (final rail in _editorialRails)
            rail.editorial.id == editorialRailId
                ? rail.withItems(
                    _mergeHomeTitleWheelHydratedItems(rail.items, hydrated),
                  )
                : rail,
        ];
      });
      DiagnosticLog.add(
        'mobile title wheel artwork hydrated rail=${editorialRailId ?? "hero"} requested=${candidates.length} hydrated=${hydrated.length} cached=$skippedCached',
      );
    }());
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
      _openCuratedShelf(
        title: editorial.title,
        subtitle: editorial.sectionSubtitle,
        items: items,
        showRankPills: true,
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
    List<int?> ranks = const <int?>[],
  }) {
    final shelfItems = items.toList(growable: false);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => _HomeShelfPage(
          title: title,
          items: shelfItems,
          showRankPills: showRankPills,
          externalTopSignal: externalTopSignal,
          ranks: ranks,
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
                    final heroEditorial = _remoteEditorial?.hero;
                    final displayHeroEditorial = heroEditorial == null
                        ? const _EditorialRail(title: '', subtitle: '')
                        : _editorialFromServer(heroEditorial);
                    final displayHeroItems = _heroEditorialItems;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _warmHeroTrailerAvailability(displayHeroItems.take(8));
                    });
                    final displayEditorialRails = [
                      for (final rail in _editorialRails)
                        rail.withEntries(_entriesForHomeRail(rail, library)),
                    ];
                    final showFullLoading =
                        _loading && _remoteEditorial == null;
                    if (showFullLoading) {
                      return const _HomePageSkeleton();
                    }
                    if (_remoteEditorial == null) {
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
                            subtitle: displayHeroEditorial.subtitle,
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
                        for (final rail in displayEditorialRails)
                          if (rail.items.isNotEmpty)
                            rail.editorial.kind.trim().toLowerCase() == 'ranked'
                                ? _RankedHomeRail(
                                    title: rail.editorial.title,
                                    subtitle: rail.editorial.subtitle,
                                    entries: rail.entries,
                                    onTap: _openDetails,
                                    onOpenDiscovery: () => _openCuratedShelf(
                                      title: rail.editorial.title,
                                      subtitle: rail.editorial.subtitle,
                                      items: rail.items,
                                      showRankPills: true,
                                      externalTopSignal: true,
                                      insightsEnabled: insightsEnabled,
                                      ranks: [
                                        for (final entry in rail.entries)
                                          entry.rank,
                                      ],
                                    ),
                                  )
                                : _HomeRail(
                                    title: rail.editorial.title,
                                    subtitle: rail.editorial.subtitle,
                                    entries: [
                                      for (final item in rail.items)
                                        _HomeRailEntry(item: item),
                                    ],
                                    onTap: _openDetails,
                                    onOpenDiscovery: () => _openCuratedShelf(
                                      title: rail.editorial.title,
                                      subtitle: rail.editorial.subtitle,
                                      items: rail.items,
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

class _HydratedHomeRail {
  const _HydratedHomeRail({required this.editorial, required this.entries});

  final HomeEditorialRail editorial;
  final List<_HydratedEditorialItem> entries;

  List<CatalogItem> get items =>
      entries.map((entry) => entry.item).toList(growable: false);

  _HydratedHomeRail withItems(List<CatalogItem> nextItems) {
    final nextByKey = {for (final item in nextItems) _itemKey(item): item};
    return _HydratedHomeRail(
      editorial: editorial,
      entries: [
        for (final entry in entries)
          _HydratedEditorialItem(
            item: nextByKey[_itemKey(entry.item)] ?? entry.item,
            rank: entry.rank,
          ),
      ],
    );
  }

  _HydratedHomeRail withEntries(List<_HydratedEditorialItem> nextEntries) {
    return _HydratedHomeRail(editorial: editorial, entries: nextEntries);
  }
}

class _HydratedEditorialItem {
  const _HydratedEditorialItem({required this.item, required this.rank});

  final CatalogItem item;
  final int? rank;
}

List<_HydratedEditorialItem> _rankedEditorialEntries(
  HomeEditorialRail editorial,
  List<CatalogItem> items,
) {
  if (editorial.items.isEmpty) {
    return [
      for (final item in items) _HydratedEditorialItem(item: item, rank: null),
    ];
  }
  final entries = <_HydratedEditorialItem>[];
  var itemIndex = 0;
  for (final signal in editorial.items) {
    if (itemIndex >= items.length) break;
    final item = items[itemIndex];
    if (!_itemMatchesEditorialSignal(item, signal)) continue;
    entries.add(
      _HydratedEditorialItem(
        item: item,
        rank: signal.rank,
      ),
    );
    itemIndex += 1;
  }
  return entries;
}

List<_HydratedEditorialItem> _entriesForHomeRail(
  _HydratedHomeRail rail,
  Map<String, CatalogItem> library,
) {
  switch (rail.editorial.id) {
    case 'savedEditorial':
      return [
        for (final item in _savedForLaterItems(library.values))
          _HydratedEditorialItem(item: item, rank: null),
      ];
    case 'upcomingEditorial':
      return rail.entries;
    default:
      return rail.entries;
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

List<CatalogItem> _mergeHomeTitleWheelHydratedItems(
  List<CatalogItem> current,
  List<CatalogItem> hydrated,
) {
  if (current.isEmpty || hydrated.isEmpty) return current;
  final byItemKey = {for (final item in hydrated) _itemKey(item): item};
  var changed = false;
  final merged = [
    for (final item in current)
      (() {
        final richer = byItemKey[_itemKey(item)];
        if (richer == null) return item;
        final mergedItem = homeArtworkOnlyMerge(item, richer);
        if ((mergedItem.logo ?? '').trim() != (item.logo ?? '').trim()) {
          changed = true;
        }
        return mergedItem;
      })(),
  ];
  return changed ? merged : current;
}

@visibleForTesting
CatalogItem homeArtworkOnlyMerge(CatalogItem base, CatalogItem artwork) {
  return CatalogItem(
    type: base.type,
    id: base.id,
    name: base.name,
    poster: artwork.poster ?? base.poster,
    background: artwork.background ?? base.background,
    logo: artwork.logo ?? base.logo,
    year: base.year,
    releaseDate: base.releaseDate,
    tmdbId: base.tmdbId,
    imdbId: base.imdbId,
    genres: base.genres,
    description: base.description,
    imdbRating: base.imdbRating,
    voteCount: base.voteCount,
    adult: base.adult,
    isUpcoming: base.isUpcoming,
    isLocalCatalogItem: base.isLocalCatalogItem,
    localPlaybackLocked: base.localPlaybackLocked,
    localCatalogId: base.localCatalogId,
    localCatalogItemId: base.localCatalogItemId,
    localCatalogName: base.localCatalogName,
    localMediaKind: base.localMediaKind,
    localSourceLabel: base.localSourceLabel,
    localRelinkNeededCount: base.localRelinkNeededCount,
    personalServerTypeId: base.personalServerTypeId,
    personalServerItemId: base.personalServerItemId,
    personalServerSeriesItemId: base.personalServerSeriesItemId,
  );
}

@visibleForTesting
List<CatalogItem> homeTitleWheelHydrationCandidates(
  Iterable<CatalogItem> items, {
  int visibleLimit = 8,
}) {
  if (visibleLimit <= 0) return const <CatalogItem>[];
  final candidates = <CatalogItem>[];
  final seen = <String>{};
  for (final item in items.take(visibleLimit)) {
    if ((item.logo ?? '').trim().isNotEmpty) continue;
    if (item.tmdbId == null) continue;
    final key = _itemKey(item);
    if (seen.add(key)) candidates.add(item);
  }
  return candidates;
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

bool _itemMatchesEditorialSignal(
  CatalogItem item,
  HomeEditorialTrendItem signal,
) {
  if (signal.type != null && item.type != signal.type) return false;
  if (signal.tmdbId != null) {
    return item.tmdbId == signal.tmdbId;
  }
  final itemTitle = _normalizedTrendTitle(item.name);
  final signalTitle = _normalizedTrendTitle(signal.title);
  if (itemTitle.isEmpty || signalTitle.isEmpty || itemTitle != signalTitle) {
    return false;
  }
  if (signal.year.isEmpty) return true;
  final year = item.year?.trim() ?? '';
  return year.startsWith(signal.year);
}

String _normalizedTrendTitle(String value) {
  return _normalizeEditorialSearchText(value);
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
  return items.where((item) {
    if (!_isHomeEditorialCandidate(item, rail)) return false;
    if (item.isUpcoming && !_allowsUpcomingEditorialIntent(rail)) {
      return false;
    }
    if (!_homeItemMatchesEditorialQuery(item, rail.query)) return false;
    if (!_requiresStrictEditorialIntent(rail)) return true;
    if (item.type.isLive) return false;
    final year = _itemYear(item);
    return year != null && year == DateTime.now().year;
  }).toList(growable: false);
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
  final matches = items.where((item) {
    if (_itemMatchesAnyGenre(item, genres)) return true;
    return allowUnknownGenre && item.genres.isEmpty;
  }).toList(growable: false);
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
  final fallback = scopedItems
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
  return normalized.split(' ').map((word) {
    return word.split('-').map((part) {
      if (part.isEmpty) return part;
      final lower = part.toLowerCase();
      final acronym = acronyms[lower];
      if (acronym != null) return acronym;
      return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
    }).join('-');
  }).join(' ');
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

_EditorialRail _editorialFromServer(HomeEditorialRail remote) {
  return _EditorialRail(
    id: remote.id,
    kind: remote.kind,
    title: remote.title,
    subtitle: remote.subtitle,
    genres: remote.genres,
    types: remote.types,
    sort: remote.sort,
    perType: remote.perType,
    requireGenreMatch: remote.requireGenreMatch,
    intent: remote.intent,
    releaseWindow: remote.releaseWindow,
    theme: remote.theme,
    seasonalWindow: remote.seasonalWindow,
    query: remote.query,
    curationKind: remote.curationKind,
    notificationHook: remote.notificationHook,
    pageOneOnly: remote.pageOneOnly,
    limit: remote.limit,
    movieLimit: remote.movieLimit,
    seriesLimit: remote.seriesLimit,
    items: remote.items,
  );
}

const double _homeHeroViewportFraction = 0.76;

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
    _controller = PageController(
      viewportFraction: _homeHeroViewportFraction,
      initialPage: _page,
    );
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
    final itemsChanged = itemCountChanged ||
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
    final phoneLandscape = JuicrVisual.phoneLandscape(context);
    final stageHeight = _homeHeroStageHeight(context);
    final heroItemPadding = phoneLandscape
        ? 34.0
        : compactLandscape
            ? 18.0
            : 2.0;
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
          SizedBox(height: compactLandscape ? (phoneLandscape ? 1 : 5) : 10),
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
                final hasTrailer = item != null &&
                    widget.trailerAvailability[_heroTrailerAvailabilityKey(
                          item,
                        )] !=
                        null;
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final rawPage = _controller.hasClients &&
                            _controller.position.haveDimensions
                        ? _controller.page ?? _page.toDouble()
                        : _page.toDouble();
                    final pageOffset = (page - rawPage).clamp(-1.0, 1.0);
                    final distance = pageOffset.abs();
                    final scale = 1 -
                        (distance *
                            (phoneLandscape
                                ? 0.30
                                : compactLandscape
                                    ? 0.24
                                    : 0.16));
                    final opacity = (1.0 -
                            distance *
                                (phoneLandscape
                                    ? 0.58
                                    : compactLandscape
                                        ? 0.42
                                        : 0.0))
                        .clamp(0.0, 1.0)
                        .toDouble();
                    final xOffset = -pageOffset *
                        (phoneLandscape
                            ? 96
                            : compactLandscape
                                ? 74
                                : 18);
                    final yOffset = distance * 16;
                    return Opacity(
                      opacity: opacity,
                      child: Transform.translate(
                        offset: Offset(xOffset, yOffset),
                        child: Transform.scale(scale: scale, child: child),
                      ),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: heroItemPadding),
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
            SizedBox(height: compactLandscape ? 8 : 10),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final itemCount = widget.items.length;
                final rawPage = _controller.hasClients &&
                        _controller.position.haveDimensions
                    ? _controller.page ?? _page.toDouble()
                    : _page.toDouble();
                final activeIndex = _logicalIndex(rawPage.round(), itemCount);
                return Center(
                  child: _AdaptiveHeroIndicator(
                    itemCount: itemCount,
                    activeIndex: activeIndex,
                    onTap: (index) {
                      _controller.animateToPage(
                        _nearestPageForLogicalIndex(index),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

double _homeHeroStageHeight(BuildContext context) {
  if (!JuicrVisual.compactLandscape(context)) {
    return 218.0;
  }
  final phoneLandscape = JuicrVisual.phoneLandscape(context);
  final availableWidth = MediaQuery.sizeOf(context).width - 28.0;
  final focusedCardWidth = availableWidth * _homeHeroViewportFraction;
  final aspect = phoneLandscape ? 3.05 : 2.36;
  final minHeight = phoneLandscape ? 144.0 : 198.0;
  final maxHeight = phoneLandscape ? 172.0 : 252.0;
  return (focusedCardWidth / aspect).clamp(minHeight, maxHeight).toDouble();
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
    final displayTitle = title;
    final phoneLandscape = JuicrVisual.phoneLandscape(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: phoneLandscape ? 16 : 22,
          child: _AutoScrollTitle(
            text: displayTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: phoneLandscape ? 13 : null,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.35,
                ),
          ),
        ),
        SizedBox(height: phoneLandscape ? 3 : 6),
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

class _AdaptiveHeroIndicator extends StatelessWidget {
  const _AdaptiveHeroIndicator({
    required this.itemCount,
    required this.activeIndex,
    required this.onTap,
  });

  final int itemCount;
  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var dot = 0; dot < itemCount; dot++) ...[
          GestureDetector(
            onTap: () => onTap(dot),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: dot == activeIndex ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: color.withValues(
                  alpha: dot == activeIndex ? 0.86 : 0.24,
                ),
              ),
            ),
          ),
          if (dot != itemCount - 1) const SizedBox(width: 7),
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
    final heroImageAlignment =
        compactLandscape ? const Alignment(0, -0.72) : Alignment.center;
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
                    alignment: heroImageAlignment,
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
                      label:
                          trailerLoading ? 'Loading trailer' : 'Watch trailer',
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
                              foregroundColor:
                                  saved ? colorScheme.primary : Colors.white,
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
    final phoneLandscape = JuicrVisual.phoneLandscape(context);
    final title =
        loading ? 'Loading picks...' : item?.name ?? 'Find your next watch';
    final subtitle = loading
        ? 'A little shelf we would point at today.'
        : _heroCardSubtitle(item, editorialGenres);
    final titleHeight = focused
        ? (phoneLandscape
            ? 25.0
            : compactLandscape
                ? 34.0
                : 38.0)
        : 18.0;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      color: Colors.white,
      fontSize: focused
          ? (phoneLandscape
              ? 15
              : compactLandscape
                  ? 18
                  : 21)
          : 11,
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
          height: titleHeight,
          child: _HeroTitleWheelArtwork(
            item: loading ? null : item,
            maxHeight: titleHeight,
            fallback: _AutoScrollTitle(text: title, style: titleStyle),
          ),
        ),
        SizedBox(
            height: phoneLandscape
                ? 1
                : compactLandscape
                    ? 2
                    : 3),
        SizedBox(
          height: focused
              ? (phoneLandscape
                  ? 13
                  : compactLandscape
                      ? 15
                      : 17)
              : 12,
          child: _AutoScrollTitle(
            text: subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: focused
                  ? (phoneLandscape
                      ? 9.5
                      : compactLandscape
                          ? 11
                          : 12)
                  : 8,
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

class _HeroTitleWheelArtwork extends StatelessWidget {
  const _HeroTitleWheelArtwork({
    required this.item,
    required this.maxHeight,
    required this.fallback,
  });

  final CatalogItem? item;
  final double maxHeight;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final logo = item?.logo?.trim();
    if (logo == null || logo.isEmpty || _isSvgLikeImage(logo)) {
      return fallback;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Image.network(
          logo,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          cacheWidth: _homeImageCacheWidth(context, 180),
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return fallback;
          },
        ),
      ),
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
    final phoneLandscape = JuicrVisual.phoneLandscape(context);
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
            padding: EdgeInsets.all(phoneLandscape
                ? 8
                : compactLandscape
                    ? 10
                    : 14),
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
                  width: phoneLandscape
                      ? 28
                      : compactLandscape
                          ? 34
                          : 42,
                  height: phoneLandscape
                      ? 28
                      : compactLandscape
                          ? 34
                          : 42,
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
                      size: phoneLandscape
                          ? 16
                          : compactLandscape
                              ? 19
                              : 22,
                    ),
                  ),
                ),
                SizedBox(
                    width: phoneLandscape
                        ? 8
                        : compactLandscape
                            ? 10
                            : 12),
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
                          fontSize: phoneLandscape ? 13 : null,
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
        final offset = Tween<Offset>(
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
    final displayTitle = title;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final phoneLandscape = JuicrVisual.phoneLandscape(context);
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
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
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
              height: phoneLandscape
                  ? 104
                  : compactLandscape
                      ? 122
                      : 206,
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
                  if (compactLandscape) {
                    return _HomeLandscapeCard(
                      entry: entry,
                      onTap: () => onTap(entry.item),
                    );
                  }
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
    required this.entries,
    required this.onTap,
    this.showRankPills = true,
    this.onOpenDiscovery,
  });

  final String title;
  final String subtitle;
  final List<_HydratedEditorialItem> entries;
  final ValueChanged<CatalogItem> onTap;
  final bool showRankPills;
  final VoidCallback? onOpenDiscovery;

  @override
  Widget build(BuildContext context) {
    final displayTitle = title;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final phoneLandscape = JuicrVisual.phoneLandscape(context);
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
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
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
              height: phoneLandscape
                  ? 104
                  : compactLandscape
                      ? 122
                      : 194,
              child: ListView.separated(
                padding: EdgeInsets.symmetric(
                  horizontal: compactLandscape ? 14 : 18,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: entries.length,
                separatorBuilder: (_, __) =>
                    SizedBox(width: compactLandscape ? 8 : 12),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final item = entry.item;
                  if (compactLandscape) {
                    return _HomeLandscapeCard(
                      entry: _HomeRailEntry(item: item),
                      rank: showRankPills ? entry.rank : null,
                      onTap: () => onTap(item),
                    );
                  }
                  if (showRankPills) {
                    return _RankedPosterCard(
                      item: item,
                      rank: entry.rank!,
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
    this.ranks = const <int?>[],
  });

  final String title;
  final List<CatalogItem> items;
  final bool showRankPills;
  final bool externalTopSignal;
  final List<int?> ranks;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayTitle = title;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    if (showRankPills) {
      return _TopTenShelfPage(
        title: displayTitle,
        items: items,
        externalTopSignal: externalTopSignal,
        ranks: ranks,
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
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: compactLandscape ? 5 : 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: compactLandscape ? 10 : 16,
                    childAspectRatio: compactLandscape ? 16 / 9 : 0.58,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    if (compactLandscape && !item.type.isLive) {
                      return _HomeShelfLandscapeGridCard(
                        item: item,
                        rank: showRankPills ? index + 1 : null,
                        onTap: () => Navigator.of(context).push(
                          AppPageRoute<void>(
                            builder: (_) => DetailsPage(item: item),
                          ),
                        ),
                      );
                    }
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
    required this.ranks,
  });

  final String title;
  final List<CatalogItem> items;
  final bool externalTopSignal;
  final List<int?> ranks;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayTitle = title;
    final rankedItems = items;
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
                    final rank = ranks[index]!;
                    final item = rankedItems[index];
                    return _TopTenWideCard(
                      item: item,
                      rank: rank,
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

class _TopTenWideCard extends StatelessWidget {
  const _TopTenWideCard({
    required this.item,
    required this.rank,
  });

  final CatalogItem item;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = item.background ?? item.poster;
    final poster = item.type.isLive ? item.logo ?? item.poster : item.poster;
    final backgroundCacheWidth = _homeImageCacheWidth(context, 360);
    final posterCacheWidth = _homeImageCacheWidth(context, 96);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: 'Open rank $rank, ${item.name}',
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const Spacer(),
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

class _HomeShelfLandscapeGridCard extends StatelessWidget {
  const _HomeShelfLandscapeGridCard({
    required this.item,
    required this.onTap,
    this.rank,
  });

  final CatalogItem item;
  final VoidCallback onTap;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.background ?? item.poster;
    final cacheWidth = _homeImageCacheWidth(context, 190);
    return Semantics(
      button: true,
      label: 'Open ${item.name}',
      hint: 'Show details',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    cacheWidth: cacheWidth,
                    errorBuilder: (_, __, ___) =>
                        const AppShimmerBox(radius: 12),
                  )
                else
                  const AppShimmerBox(radius: 12),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xD607080D),
                          Color(0x7807080D),
                          Color(0x0807080D),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: _MetaBadge(item: item, compact: true),
                ),
                Positioned(
                  left: 10,
                  right: rank == null ? 10 : 70,
                  bottom: 10,
                  child: _HomeLandscapeTitleWheel(item: item),
                ),
                if (rank != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _RankBadge(rank: rank!),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
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

class _HomeLandscapeCard extends StatelessWidget {
  const _HomeLandscapeCard({
    required this.entry,
    required this.onTap,
    this.rank,
  });

  static const double _radius = 16;

  final _HomeRailEntry entry;
  final VoidCallback onTap;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final image = item.background ?? item.poster;
    final imageUrl = image?.trim();
    final phoneLandscape = JuicrVisual.phoneLandscape(context);
    final cardWidth = phoneLandscape ? 164.0 : 198.0;
    final cardHeight = phoneLandscape ? 94.0 : 112.0;
    final cacheWidth = _homeImageCacheWidth(context, cardWidth);
    final titleBottom = entry.progress == null ? 12.0 : 20.0;
    final rankLabel = rank == null ? null : ' rank $rank';
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Semantics(
        button: true,
        label: 'Open${rankLabel ?? ''}, ${item.name}',
        hint: 'Show details',
        child: ExcludeSemantics(
          child: InkWell(
            borderRadius: BorderRadius.circular(_radius),
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      cacheWidth: cacheWidth,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const _HomeArtworkFallback();
                      },
                      errorBuilder: (_, __, ___) =>
                          const _HomeArtworkFallback(),
                    )
                  else
                    const _HomeArtworkFallback(),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Color(0xD607080D),
                            Color(0x7607080D),
                            Color(0x0007080D),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _MetaBadge(item: item, compact: true),
                  ),
                  Positioned(
                    left: 12,
                    right: rank == null ? 12 : 76,
                    bottom: titleBottom,
                    child: _HomeLandscapeTitleWheel(item: item),
                  ),
                  if (rank != null)
                    Positioned(
                      right: 8,
                      bottom: entry.progress == null ? 8 : 18,
                      child: _RankBadge(rank: rank!),
                    ),
                  if (entry.progress != null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 9,
                      child: LinearProgressIndicator(
                        value:
                            entry.progress!.progress.clamp(0.0, 1.0).toDouble(),
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(99),
                        backgroundColor: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_radius),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
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

class _HomeLandscapeTitleWheel extends StatelessWidget {
  const _HomeLandscapeTitleWheel({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final logo = item.logo?.trim();
    final fallback = Text(
      item.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w900,
        height: 1,
      ),
    );
    if (logo == null || logo.isEmpty || _isSvgLikeImage(logo)) {
      return fallback;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 34),
        child: Image.network(
          logo,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          cacheWidth: _homeImageCacheWidth(context, 132),
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return fallback;
          },
        ),
      ),
    );
  }
}

bool _isSvgLikeImage(String value) {
  final normalized = value.toLowerCase().split('?').first;
  return normalized.endsWith('.svg');
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
        final phoneLandscape = JuicrVisual.phoneLandscape(context);
        final cardWidth = (constraints.maxWidth *
                (compactLandscape ? _homeHeroViewportFraction : 0.76)) -
            (phoneLandscape
                ? 68.0
                : compactLandscape
                    ? 36.0
                    : 0.0);
        final sideOffset = compactLandscape
            ? phoneLandscape
                ? (cardWidth * 0.32).clamp(86.0, 132.0)
                : (cardWidth * 0.56).clamp(148.0, 210.0)
            : (cardWidth * 0.92).clamp(270.0, 318.0);
        final stageHeight = _homeHeroStageHeight(context);
        final cardHeight = compactLandscape ? stageHeight - 18.0 : 190.0;
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
