import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'account_auth_sheet.dart';
import 'ad_policy.dart';
import 'app_state.dart';
import 'catalog_empty_state.dart';
import 'catalog_item.dart';
import 'diagnostic_log.dart';
import 'details_page.dart';
import 'juicr_bottom_sheet.dart';
import 'library_lists_section.dart';
import 'motion.dart';
import 'stream_api.dart';
import 'visual_style.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with AutomaticKeepAliveClientMixin<LibraryPage> {
  final StreamApi _api = StreamApi();
  final ScrollController _scrollController = ScrollController();
  _LibrarySection _selectedSection = _LibrarySection.continueWatching;
  _LibraryContinueSort _continueSort = _LibraryContinueSort.recent;
  _LibrarySavedSort _savedSort = _LibrarySavedSort.titleAZ;
  late Future<_LibraryAddonAvailability> _addonAvailabilityFuture;
  bool _showInitialShimmer = true;
  bool _controlsVisible = true;
  bool _showScrollTop = false;
  double _lastScrollOffset = 0;
  Timer? _initialShimmerTimer;

  @override
  void initState() {
    super.initState();
    _addonAvailabilityFuture = Future<_LibraryAddonAvailability>.value(
      _LibraryAddonAvailability.empty,
    );
    AppState.userAddons.addListener(_handleAddonSourcesChanged);
    AppState.preferencesReady.addListener(_handleAddonSourcesChanged);
    AppState.defaultCatalogEnabled.addListener(_handleAddonSourcesChanged);
    AppState.tvSourcesEnabled.addListener(_handleAddonSourcesChanged);
    AppState.publicIptvEnabled.addListener(_handleAddonSourcesChanged);
    AppState.libraryLists.addListener(_handleLibraryListsChanged);
    _scrollController.addListener(_handleScroll);
    if (AppState.preferencesReady.value) {
      _addonAvailabilityFuture = Future<_LibraryAddonAvailability>.delayed(
        const Duration(milliseconds: 900),
        _loadAddonAvailability,
      );
    }
    _initialShimmerTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        setState(() => _showInitialShimmer = false);
      }
    });
  }

  @override
  void dispose() {
    _initialShimmerTimer?.cancel();
    AppState.userAddons.removeListener(_handleAddonSourcesChanged);
    AppState.preferencesReady.removeListener(_handleAddonSourcesChanged);
    AppState.defaultCatalogEnabled.removeListener(_handleAddonSourcesChanged);
    AppState.tvSourcesEnabled.removeListener(_handleAddonSourcesChanged);
    AppState.publicIptvEnabled.removeListener(_handleAddonSourcesChanged);
    AppState.libraryLists.removeListener(_handleLibraryListsChanged);
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _api.close();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final pixels = _scrollController.position.pixels;
    final delta = pixels - _lastScrollOffset;
    var nextControlsVisible = _controlsVisible;
    var nextShowScrollTop = _showScrollTop;

    if (pixels <= 18) {
      nextControlsVisible = true;
      nextShowScrollTop = false;
    } else {
      if (delta > 18 && pixels > 128) nextControlsVisible = false;
      if (delta < -12) nextControlsVisible = true;
      nextShowScrollTop = pixels > 520;
    }

    _lastScrollOffset = pixels;
    if (nextControlsVisible != _controlsVisible ||
        nextShowScrollTop != _showScrollTop) {
      setState(() {
        _controlsVisible = nextControlsVisible;
        _showScrollTop = nextShowScrollTop;
      });
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    setState(() {
      _controlsVisible = true;
      _showScrollTop = false;
    });
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleLibraryListsChanged() {
    if (_selectedSection != _LibrarySection.lists) return;
    _restoreListScrollAfterContentChange();
  }

  void _restoreListScrollAfterContentChange() {
    if (!mounted) return;
    if (!_controlsVisible || _showScrollTop) {
      setState(() {
        _controlsVisible = true;
        _showScrollTop = false;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      final target = position.pixels.clamp(0.0, position.maxScrollExtent);
      if ((position.pixels - target).abs() > 0.5) {
        _scrollController.jumpTo(target);
      }
      if (_scrollController.hasClients) {
        _lastScrollOffset = _scrollController.position.pixels;
      }
    });
  }

  void _handleAddonSourcesChanged() {
    _addonAvailabilityFuture = Future<_LibraryAddonAvailability>.delayed(
      const Duration(milliseconds: 500),
      _loadAddonAvailability,
    );
    if (mounted) setState(() {});
  }

  Future<_LibraryAddonAvailability> _loadAddonAvailability() async {
    final activeTypes = <MediaType>{};
    if (AppState.tvSourcesEnabled.value && AppState.publicIptvEnabled.value) {
      activeTypes.add(MediaType.liveTv);
    }
    try {
      final config = await _api.config();
      for (final type in const [
        MediaType.liveTv,
        MediaType.music,
        MediaType.nsfw,
      ]) {
        if (config.supportsAddonCatalogType(type)) activeTypes.add(type);
      }
    } catch (_) {}

    final ids = <String>{};
    if (activeTypes.contains(MediaType.liveTv)) {
      for (var skip = 0; skip < StreamApi.pageSize * 8;) {
        try {
          final result = await _api.addonCatalogOnly(
            type: MediaType.liveTv,
            sort: CatalogSort.top,
            skip: skip,
          );
          ids.addAll(result.items.map((item) => item.id));
          if (!(result.hasMore ?? result.items.isNotEmpty)) break;
          skip += result.skipDelta ?? StreamApi.pageSize;
        } catch (_) {
          break;
        }
      }
    }
    return _LibraryAddonAvailability(
      activeTypes: activeTypes,
      activeLiveTvIds: ids,
    );
  }

  void _sortContinueItems(List<ContinueWatchingEntry> items) {
    items.sort((a, b) {
      return switch (_continueSort) {
        _LibraryContinueSort.recent => b.updatedAt.compareTo(a.updatedAt),
        _LibraryContinueSort.progress => b.progress.compareTo(a.progress),
        _LibraryContinueSort.remaining => a.remainingSeconds.compareTo(
          b.remainingSeconds,
        ),
        _LibraryContinueSort.titleAZ => _compareText(a.title, b.title),
      };
    });
  }

  void _sortSavedItems(List<CatalogItem> items) {
    items.sort((a, b) {
      return switch (_savedSort) {
        _LibrarySavedSort.titleAZ => _compareText(a.name, b.name),
        _LibrarySavedSort.titleZA => _compareText(b.name, a.name),
        _LibrarySavedSort.newest => _itemYear(b).compareTo(_itemYear(a)),
        _LibrarySavedSort.highestRated => _itemRating(
          b,
        ).compareTo(_itemRating(a)),
      };
    });
  }

  Future<void> _showLibraryMetrics() async {
    DiagnosticLog.screen(context, 'Library metrics');
    final metrics = _LibraryMetrics.fromState(
      saved: AppState.library.value.values,
      progress: AppState.continueWatching.value.values,
      completed: AppState.completedWatching.value.values,
    );
    await showJuicrBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Padding(
          padding: juicrBottomSheetPadding(sheetContext, top: 4),
          child: _LibraryMetricsSheet(metrics: metrics),
        );
      },
    );
  }

  Future<void> _showLibraryLeaderboard() async {
    DiagnosticLog.screen(context, 'Library leaderboard');
    final metrics = _LibraryMetrics.fromState(
      saved: AppState.library.value.values,
      progress: AppState.continueWatching.value.values,
      completed: AppState.completedWatching.value.values,
    );
    await showJuicrBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var selectedScope = _LeaderboardScope.fromId(
          AppState.leaderboardScope.value,
        );
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SingleChildScrollView(
              padding: juicrBottomSheetPadding(sheetContext, top: 4),
              child: _LibraryLeaderboardSheet(
                metrics: metrics,
                selectedScope: selectedScope,
                onScopeChanged: (scope) {
                  AppState.setLeaderboardScope(scope.apiId);
                  setSheetState(() => selectedScope = scope);
                },
                onSignInRequested: () {
                  Navigator.of(sheetContext).pop();
                  AppState.shellTab.value = 3;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) unawaited(showAccountAuthSheet(context));
                  });
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showLibrarySettings() async {
    DiagnosticLog.screen(context, 'Library settings');
    await showJuicrBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final showContinueSort =
            _selectedSection == _LibrarySection.continueWatching;
        return SingleChildScrollView(
          padding: juicrBottomSheetPadding(sheetContext, top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Library settings',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                showContinueSort
                    ? 'Sort your recently played titles.'
                    : 'Sort saved ${_selectedSection.label.toLowerCase()}.',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.64),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              if (showContinueSort)
                for (final option in _LibraryContinueSort.values)
                  _LibrarySettingsOption(
                    label: option.label,
                    icon: option.icon,
                    selected: option == _continueSort,
                    onTap: () {
                      DiagnosticLog.add(
                        'library continue sort changed ${_continueSort.name} -> ${option.name}',
                      );
                      setState(() => _continueSort = option);
                      Navigator.of(sheetContext).pop();
                    },
                  )
              else
                for (final option in _LibrarySavedSort.values)
                  _LibrarySettingsOption(
                    label: option.label,
                    icon: option.icon,
                    selected: option == _savedSort,
                    onTap: () {
                      DiagnosticLog.add(
                        'library saved sort changed ${_savedSort.name} -> ${option.name}',
                      );
                      setState(() => _savedSort = option);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createLibraryList() async {
    String draftName = '';
    final name = await showJuicrBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SingleChildScrollView(
              padding: juicrBottomSheetPadding(sheetContext),
              child: LibraryCreateListSheet(
                draftName: draftName,
                onChanged: (value) => setSheetState(() => draftName = value),
                onCancel: () => Navigator.of(sheetContext).pop(),
                onCreate: () => Navigator.of(sheetContext).pop(draftName),
              ),
            );
          },
        );
      },
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    AppState.createLibraryList(trimmed);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('$trimmed created')));
  }

  Future<void> _renameLibraryList(LibraryList list) async {
    final controller = TextEditingController(text: list.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename list'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 48,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'List name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == list.name) return;
    AppState.renameLibraryList(list.id, trimmed);
  }

  Future<void> _deleteLibraryList(LibraryList list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete list?'),
        content: Text('This deletes "${list.name}" but keeps saved titles.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    AppState.deleteLibraryList(list.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('${list.name} deleted')));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!AppState.preferencesReady.value) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: JuicrVisual.topLevelTitleSpacingFor(context),
          toolbarHeight: JuicrVisual.topLevelToolbarHeightFor(context),
          title: const Text('Library'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          left: !JuicrVisual.compactLandscape(context),
          child: const _LibraryPageSkeleton(),
        ),
      );
    }
    if (!AppState.hasCatalogSource) {
      return Scaffold(
        body: SafeArea(
          left: !JuicrVisual.compactLandscape(context),
          child: const CatalogEmptyState(title: 'Library'),
        ),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final motionDisabled = juicrMotionDisabled(context);
    final controlAnimationDuration = motionDisabled
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final filterCardHeight = compactLandscape ? 62.0 : 78.0;
    final libraryCardGap = compactLandscape ? 8.0 : 12.0;
    final filterHeaderHeight = filterCardHeight + libraryCardGap;

    return Scaffold(
      floatingActionButton: AnimatedScale(
        scale: _showScrollTop ? 1 : 0.82,
        duration: controlAnimationDuration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _showScrollTop ? 1 : 0,
          duration: controlAnimationDuration,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: Semantics(
              button: true,
              enabled: _showScrollTop,
              label: 'Back to top',
              child: ExcludeSemantics(
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _showScrollTop ? _scrollToTop : null,
                  child: Tooltip(
                    message: 'Back to top',
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: JuicrVisual.elevatedCircleDecoration(
                        colorScheme,
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.9,
                        ),
                        shadowAlpha: 0.14,
                        glowAlpha: 0.03,
                      ),
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        size: 22,
                        color: colorScheme.onSurface.withValues(alpha: 0.92),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: JuicrVisual.topLevelTitleSpacingFor(context),
        toolbarHeight: JuicrVisual.topLevelToolbarHeightFor(context),
        title: const Text('Library'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Leaderboard',
            onPressed: _showLibraryLeaderboard,
            icon: const Icon(Icons.emoji_events_outlined),
          ),
          IconButton(
            tooltip: 'Library metrics',
            onPressed: _showLibraryMetrics,
            icon: const Icon(Icons.insights_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Library settings',
              onPressed: _showLibrarySettings,
              icon: const Icon(Icons.settings_rounded),
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder<Map<String, ContinueWatchingEntry>>(
        valueListenable: AppState.continueWatching,
        builder: (context, progress, _) {
          return ValueListenableBuilder<Map<String, CompletedWatchingEntry>>(
            valueListenable: AppState.completedWatching,
            builder: (context, completed, _) {
              return ValueListenableBuilder<Map<String, CatalogItem>>(
                valueListenable: AppState.library,
                builder: (context, saved, _) {
                  return ValueListenableBuilder<List<LibraryList>>(
                    valueListenable: AppState.libraryLists,
                    builder: (context, lists, _) {
                      return FutureBuilder<_LibraryAddonAvailability>(
                        future: _addonAvailabilityFuture,
                        builder: (context, availabilitySnapshot) {
                          final hasLocalLibraryContent =
                              progress.isNotEmpty ||
                              completed.isNotEmpty ||
                              saved.isNotEmpty ||
                              lists.isNotEmpty;
                          if (_showInitialShimmer ||
                              availabilitySnapshot.connectionState !=
                                  ConnectionState.done) {
                            if (!hasLocalLibraryContent) {
                              return const _LibraryPageSkeleton();
                            }
                            DiagnosticLog.viewTiming(
                              surface: 'library',
                              state: 'interaction_ready',
                              cacheStateBucket: 'local_state',
                              mediaKind: 'mixed',
                              itemCount:
                                  progress.length +
                                  completed.length +
                                  saved.length,
                            );
                          }

                          final availability =
                              availabilitySnapshot.data ??
                              _LibraryAddonAvailability.empty;
                          const localItems = <CatalogItem>[];
                          final completedItems = _dedupeCompletedItems(
                            completed.values.where(
                              (entry) => !entry.item.type.isLive,
                            ),
                          );
                          final sections = _LibrarySectionInfo.visibleSections(
                            availability.activeTypes,
                            hasCompleted: completedItems.isNotEmpty,
                            hasLocalCatalogItems: localItems.isNotEmpty,
                          );
                          final shouldPreferPrivateCatalogs =
                              _selectedSection ==
                                  _LibrarySection.continueWatching &&
                              progress.isEmpty &&
                              localItems.isNotEmpty;
                          if (!sections.contains(_selectedSection) ||
                              shouldPreferPrivateCatalogs) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              if (!sections.contains(_selectedSection)) {
                                setState(() {
                                  _selectedSection = localItems.isNotEmpty
                                      ? _LibrarySection.privateCatalogs
                                      : _LibrarySection.continueWatching;
                                });
                              } else if (shouldPreferPrivateCatalogs) {
                                setState(() {
                                  _selectedSection =
                                      _LibrarySection.privateCatalogs;
                                });
                              }
                            });
                          }
                          final activeSection =
                              sections.contains(_selectedSection)
                              ? _selectedSection
                              : _LibrarySection.continueWatching;
                          final allItems = saved.values.where((item) {
                            if (item.type.isLive) {
                              return (AppState.tvSourcesEnabled.value &&
                                      AppState.publicIptvEnabled.value) ||
                                  availability.activeLiveTvIds.contains(
                                    item.id,
                                  );
                            }
                            if (item.type == MediaType.music ||
                                item.type == MediaType.nsfw) {
                              return availability.activeTypes.contains(
                                item.type,
                              );
                            }
                            return true;
                          }).toList();
                          final continueItems =
                              AppState.displayableContinueEntries(
                                progress.values,
                              ).toList(growable: false);
                          _sortContinueItems(continueItems);
                          if (allItems.isEmpty &&
                              localItems.isEmpty &&
                              lists.isEmpty &&
                              continueItems.isEmpty &&
                              completedItems.isEmpty) {
                            return const _EmptyLibrary();
                          }

                          final selectedType = activeSection.mediaType;
                          final showPrivateCatalogs =
                              activeSection == _LibrarySection.privateCatalogs;
                          final items = showPrivateCatalogs
                              ? localItems
                              : allItems
                                    .where(
                                      (item) =>
                                          selectedType != null &&
                                          item.type == selectedType,
                                    )
                                    .toList();
                          _sortSavedItems(items);
                          final showContinue =
                              activeSection == _LibrarySection.continueWatching;
                          final showCompleted =
                              activeSection == _LibrarySection.completed;
                          final showLists =
                              activeSection == _LibrarySection.lists;

                          final filterCard = _LibrarySectionCard(
                            selectedSection: activeSection,
                            sections: sections,
                            onChanged: (section) {
                              if (section == _selectedSection) return;
                              DiagnosticLog.add(
                                'library section changed ${_selectedSection.name} -> ${section.name}',
                              );
                              setState(() {
                                _selectedSection = section;
                                _controlsVisible = true;
                              });
                            },
                          );

                          return Stack(
                            children: [
                              CustomScrollView(
                                controller: _scrollController,
                                slivers: [
                                  SliverToBoxAdapter(
                                    child: AnimatedContainer(
                                      duration: controlAnimationDuration,
                                      curve: Curves.easeOutCubic,
                                      height: _controlsVisible
                                          ? filterHeaderHeight
                                          : 0,
                                    ),
                                  ),
                                  if (showContinue && continueItems.isNotEmpty)
                                    SliverPadding(
                                      padding: EdgeInsets.fromLTRB(
                                        compactLandscape ? 14 : 18,
                                        0,
                                        compactLandscape ? 14 : 18,
                                        compactLandscape ? 14 : 22,
                                      ),
                                      sliver: SliverList.separated(
                                        itemCount: continueItems.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 12),
                                        itemBuilder: (context, index) {
                                          final entry = continueItems[index];
                                          return _ContinueWatchingCard(
                                            entry: entry,
                                            completionSummary:
                                                _completionSummaryForItem(
                                                  entry.item,
                                                  completed,
                                                ),
                                          );
                                        },
                                      ),
                                    )
                                  else if (showContinue)
                                    const SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: _EmptyContinueWatching(),
                                    )
                                  else if (showCompleted &&
                                      completedItems.isNotEmpty)
                                    SliverPadding(
                                      padding: EdgeInsets.fromLTRB(
                                        compactLandscape ? 14 : 18,
                                        0,
                                        compactLandscape ? 14 : 18,
                                        compactLandscape ? 14 : 22,
                                      ),
                                      sliver: SliverList.separated(
                                        itemCount: completedItems.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 12),
                                        itemBuilder: (context, index) {
                                          return _CompletedWatchingCard(
                                            entry: completedItems[index],
                                          );
                                        },
                                      ),
                                    )
                                  else if (showCompleted)
                                    const SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: _EmptyCompletedWatching(),
                                    )
                                  else if (showLists)
                                    SliverPadding(
                                      padding: EdgeInsets.fromLTRB(
                                        compactLandscape ? 14 : 18,
                                        0,
                                        compactLandscape ? 14 : 18,
                                        compactLandscape ? 14 : 22,
                                      ),
                                      sliver: LibraryListsGrid(
                                        lists: lists,
                                        onCreate: _createLibraryList,
                                        onRename: _renameLibraryList,
                                        onDelete: _deleteLibraryList,
                                        imageCacheWidthBuilder:
                                            _libraryImageCacheWidth,
                                        itemBuilder: (context, item, index) =>
                                            _LibraryPoster(
                                              item: item,
                                              index: index,
                                            ),
                                      ),
                                    )
                                  else if (items.isEmpty)
                                    SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: _EmptyLibraryType(
                                        type: selectedType ?? MediaType.movie,
                                      ),
                                    )
                                  else
                                    SliverPadding(
                                      padding: EdgeInsets.fromLTRB(
                                        compactLandscape ? 14 : 18,
                                        0,
                                        compactLandscape ? 14 : 18,
                                        compactLandscape ? 14 : 22,
                                      ),
                                      sliver: SliverGrid.builder(
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount:
                                                  selectedType ==
                                                      MediaType.liveTv
                                                  ? (compactLandscape ? 3 : 2)
                                                  : (compactLandscape ? 5 : 3),
                                              crossAxisSpacing: compactLandscape
                                                  ? 8
                                                  : 12,
                                              mainAxisSpacing: compactLandscape
                                                  ? 8
                                                  : 12,
                                              childAspectRatio:
                                                  selectedType ==
                                                      MediaType.liveTv
                                                  ? 1.45
                                                  : 2 / 3,
                                            ),
                                        itemCount: items.length,
                                        itemBuilder: (context, index) {
                                          final item = items[index];
                                          return _LibraryPoster(
                                            item: item,
                                            index: index,
                                            completionSummary:
                                                _completionSummaryForItem(
                                                  item,
                                                  completed,
                                                ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                              AnimatedPositioned(
                                duration: controlAnimationDuration,
                                curve: Curves.easeOutCubic,
                                top: _controlsVisible
                                    ? -1
                                    : -(filterHeaderHeight + 1),
                                left: 0,
                                right: 0,
                                height: filterHeaderHeight + 1,
                                child: IgnorePointer(
                                  ignoring: !_controlsVisible,
                                  child: Material(
                                    color: Theme.of(
                                      context,
                                    ).scaffoldBackgroundColor,
                                    elevation: 8,
                                    shadowColor: Colors.black.withValues(
                                      alpha: 0.24,
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        compactLandscape ? 14 : 18,
                                        1,
                                        compactLandscape ? 14 : 18,
                                        libraryCardGap,
                                      ),
                                      child: SizedBox(
                                        height: filterCardHeight,
                                        child: filterCard,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({required this.entry, this.completionSummary});

  final ContinueWatchingEntry entry;
  final _CompletionSummary? completionSummary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundCacheWidth = _libraryImageCacheWidth(context, 360);
    final posterCacheWidth = _libraryImageCacheWidth(context, 96);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          DiagnosticLog.screen(context, 'Library continue tap');
          DiagnosticLog.add(
            'library continue tap key=${entry.key} type=${entry.item.type.compatTypeValue} progress=${entry.progress.toStringAsFixed(3)}',
          );
          unawaited(
            JuicrAdPolicy.maybeShowInterstitial(
              reason: 'library_continue_open',
            ),
          );
          Navigator.of(context).push(
            AppPageRoute<void>(builder: (_) => DetailsPage(item: entry.item)),
          );
        },
        child: SizedBox(
          height: 154,
          child: Stack(
            children: [
              Positioned.fill(
                child:
                    entry.item.background == null && entry.item.poster == null
                    ? ColoredBox(color: colorScheme.surfaceContainerHighest)
                    : Image.network(
                        entry.item.background ?? entry.item.poster!,
                        fit: BoxFit.cover,
                        cacheWidth: backgroundCacheWidth,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const AppSkeletonCard(radius: 0);
                        },
                        errorBuilder: (_, __, ___) {
                          return ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                          );
                        },
                      ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xF2000000),
                        Color(0xB8000000),
                        Color(0x40000000),
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
                        child: entry.item.poster == null
                            ? ColoredBox(
                                color: colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.movie,
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.54,
                                  ),
                                ),
                              )
                            : Image.network(
                                entry.item.poster!,
                                fit: BoxFit.cover,
                                cacheWidth: posterCacheWidth,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const AppSkeletonCard(radius: 10);
                                    },
                                errorBuilder: (_, __, ___) {
                                  return ColoredBox(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.broken_image,
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.54,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          JuicrAutoScrollText(
                            text: entry.title,
                            height: 22,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 4),
                          JuicrAutoScrollText(
                            text: entry.subtitle ?? entry.item.subtitle,
                            height: 17,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (completionSummary != null) ...[
                            const SizedBox(height: 8),
                            _CompletionPill(label: completionSummary!.label),
                          ],
                          const Spacer(),
                          Row(
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                                onPressed: () {
                                  DiagnosticLog.add(
                                    'library resume pressed key=${entry.key} type=${entry.item.type.compatTypeValue}',
                                  );
                                  Navigator.of(context).push(
                                    AppPageRoute<void>(
                                      builder: (_) =>
                                          DetailsPage(item: entry.item),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 18,
                                ),
                                label: const Text('Resume'),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  entry.remainingLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 5,
                              value: entry.progress,
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.primary,
                              ),
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
    );
  }
}

class _CompletedWatchingCard extends StatelessWidget {
  const _CompletedWatchingCard({required this.entry});

  final CompletedWatchingEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundCacheWidth = _libraryImageCacheWidth(context, 360);
    final posterCacheWidth = _libraryImageCacheWidth(context, 96);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          DiagnosticLog.screen(context, 'Library completed tap');
          DiagnosticLog.add(
            'library completed tap key=${entry.key} type=${entry.item.type.compatTypeValue}',
          );
          Navigator.of(context).push(
            AppPageRoute<void>(builder: (_) => DetailsPage(item: entry.item)),
          );
        },
        child: SizedBox(
          height: 132,
          child: Stack(
            children: [
              Positioned.fill(
                child:
                    entry.item.background == null && entry.item.poster == null
                    ? ColoredBox(color: colorScheme.surfaceContainerHighest)
                    : Image.network(
                        entry.item.background ?? entry.item.poster!,
                        fit: BoxFit.cover,
                        cacheWidth: backgroundCacheWidth,
                        errorBuilder: (_, __, ___) {
                          return ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                          );
                        },
                      ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xF2000000),
                        Color(0xC4000000),
                        Color(0x60000000),
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
                        width: 72,
                        height: 108,
                        child: entry.item.poster == null
                            ? ColoredBox(
                                color: colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.movie,
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.54,
                                  ),
                                ),
                              )
                            : Image.network(
                                entry.item.poster!,
                                fit: BoxFit.cover,
                                cacheWidth: posterCacheWidth,
                                errorBuilder: (_, __, ___) {
                                  return ColoredBox(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.broken_image,
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.54,
                                      ),
                                    ),
                                  );
                                },
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
                              Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: JuicrAutoScrollText(
                                  text: entry.title,
                                  height: 22,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          JuicrAutoScrollText(
                            text: entry.subtitle ?? entry.item.subtitle,
                            height: 17,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    AppPageRoute<void>(
                                      builder: (_) =>
                                          DetailsPage(item: entry.item),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.replay_rounded,
                                  size: 18,
                                ),
                                label: const Text('Rewatch'),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  entry.completionCount > 1
                                      ? '${_completedDateLabel(entry.completedAt)} - ${_watchCountLabel(entry.completionCount)}'
                                      : _completedDateLabel(entry.completedAt),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ),
                            ],
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
    );
  }
}

class _LibraryMetricsSheet extends StatelessWidget {
  const _LibraryMetricsSheet({required this.metrics});

  final _LibraryMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Watching metrics',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            metrics.summary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.64),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          _LibraryMetricHeroTile(
            icon: Icons.schedule_rounded,
            label: 'Active watch time',
            value: metrics.watchTimeLabel,
          ),
          if (metrics.rewatchCount > 0) ...[
            const SizedBox(height: 12),
            _LibraryMetricTile(
              icon: Icons.replay_rounded,
              label: 'Rewatches',
              value: '${metrics.rewatchCount}',
            ),
          ],
          const SizedBox(height: 14),
          _LibraryMetricBreakdownSection(
            title: 'Continue',
            icon: Icons.history_rounded,
            movieCount: metrics.continueMovieCount,
            seriesCount: metrics.continueSeriesCount,
            animationCount: metrics.continueAnimationCount,
          ),
          const SizedBox(height: 10),
          _LibraryMetricBreakdownSection(
            title: 'Completed',
            icon: Icons.check_circle_outline_rounded,
            movieCount: metrics.completedMovieCount,
            seriesCount: metrics.completedSeriesCount,
            animationCount: metrics.completedAnimationCount,
          ),
          const SizedBox(height: 10),
          _LibraryMetricBreakdownSection(
            title: 'Saved',
            icon: Icons.bookmark_added_outlined,
            movieCount: metrics.savedMovieCount,
            seriesCount: metrics.savedSeriesCount,
            animationCount: metrics.savedAnimationCount,
          ),
        ],
      ),
    );
  }
}

enum _LeaderboardScope {
  today('Today'),
  weekly('Weekly'),
  allTime('All time');

  const _LeaderboardScope(this.label);

  final String label;

  String get apiId => switch (this) {
    _LeaderboardScope.today => 'today',
    _LeaderboardScope.weekly => 'weekly',
    _LeaderboardScope.allTime => 'all',
  };

  static _LeaderboardScope fromId(String value) {
    return switch (value) {
      'today' => _LeaderboardScope.today,
      'all' || 'allTime' => _LeaderboardScope.allTime,
      _ => _LeaderboardScope.weekly,
    };
  }
}

class _LibraryLeaderboardSheet extends StatelessWidget {
  const _LibraryLeaderboardSheet({
    required this.metrics,
    required this.selectedScope,
    required this.onScopeChanged,
    required this.onSignInRequested,
  });

  final _LibraryMetrics metrics;
  final _LeaderboardScope selectedScope;
  final ValueChanged<_LeaderboardScope> onScopeChanged;
  final VoidCallback onSignInRequested;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<AccountSession?>(
      valueListenable: AppState.accountSession,
      builder: (context, session, _) {
        final signedIn = session?.isValid == true;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Leaderboard',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              signedIn
                  ? 'Active watch time rankings appear here after you choose a username and opt in from Account.'
                  : 'Sign in to join rankings after you choose a username and opt in from Account.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.64),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final scope in _LeaderboardScope.values) ...[
                  Expanded(
                    child: _LeaderboardScopeButton(
                      label: scope.label,
                      selected: selectedScope == scope,
                      onTap: () => onScopeChanged(scope),
                    ),
                  ),
                  if (scope != _LeaderboardScope.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _LeaderboardFutureSheet(
              key: ValueKey(selectedScope),
              metrics: metrics,
              selectedScope: selectedScope,
            ),
          ],
        );
        if (signedIn) return content;
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 0.46,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: content,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.28),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: _LeaderboardSignInGate(
                    colorScheme: colorScheme,
                    onSignIn: onSignInRequested,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LeaderboardFutureSheet extends StatefulWidget {
  const _LeaderboardFutureSheet({
    super.key,
    required this.metrics,
    required this.selectedScope,
  });

  final _LibraryMetrics metrics;
  final _LeaderboardScope selectedScope;

  @override
  State<_LeaderboardFutureSheet> createState() =>
      _LeaderboardFutureSheetState();
}

class _LeaderboardFutureSheetState extends State<_LeaderboardFutureSheet> {
  late final StreamApi _api;
  late Future<LeaderboardResult> _future;

  @override
  void initState() {
    super.initState();
    _api = StreamApi();
    _future = _load();
  }

  Future<LeaderboardResult> _load() async {
    await AppState.syncSignedInWatchMetrics(
      (token, activeWatchSeconds) => _api.syncAccountWatchMetrics(
        token: token,
        activeWatchSeconds: activeWatchSeconds,
      ),
    );
    return _api.fetchLeaderboard(
      scope: widget.selectedScope.apiId,
      token: AppState.accountSession.value?.token ?? '',
    );
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LeaderboardResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Column(
            children: [
              _LeaderboardRankCard(
                scope: widget.selectedScope,
                watchTimeLabel: widget.metrics.watchTimeLabel,
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < 5; index += 1) ...[
                const _LeaderboardLoadingRow(),
                if (index < 4) const SizedBox(height: 8),
              ],
            ],
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Column(
            children: [
              _LeaderboardRankCard(
                scope: widget.selectedScope,
                watchTimeLabel: widget.metrics.watchTimeLabel,
              ),
              const SizedBox(height: 12),
              const _LeaderboardMessageRow(
                icon: Icons.wifi_off_rounded,
                message: 'Could not load rankings. Try again in a moment.',
              ),
            ],
          );
        }
        final result = snapshot.data!;
        final rows = result.rows;
        return Column(
          children: [
            _LeaderboardRankCard(
              scope: widget.selectedScope,
              watchTimeLabel: widget.metrics.watchTimeLabel,
              viewer: result.viewer,
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const _LeaderboardMessageRow(
                icon: Icons.emoji_events_outlined,
                message: 'No opted-in viewers yet.',
              )
            else
              for (var index = 0; index < rows.length; index += 1) ...[
                _LeaderboardEntryRow(entry: rows[index]),
                if (index < rows.length - 1) const SizedBox(height: 8),
              ],
          ],
        );
      },
    );
  }
}

class _LeaderboardSignInGate extends StatelessWidget {
  const _LeaderboardSignInGate({
    required this.colorScheme,
    required this.onSignIn,
  });

  final ColorScheme colorScheme;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.all(16),
      decoration: JuicrVisual.elevatedCardDecoration(
        colorScheme,
        radius: 18,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
        borderAlpha: 0.10,
        shadowAlpha: 0.16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_open_rounded, size: 28, color: colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            'Unlock leaderboard by signing in',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Create your account first, then choose whether to join rankings.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.70),
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onSignIn,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in to unlock'),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardScopeButton extends StatelessWidget {
  const _LeaderboardScopeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.78)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface.withValues(alpha: 0.76),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _LeaderboardRankCard extends StatelessWidget {
  const _LeaderboardRankCard({
    required this.scope,
    required this.watchTimeLabel,
    this.viewer,
  });

  final _LeaderboardScope scope;
  final String watchTimeLabel;
  final LeaderboardViewer? viewer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: JuicrVisual.elevatedCardDecoration(
        colorScheme,
        radius: 16,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderAlpha: 0,
        shadowAlpha: 0.07,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: colorScheme.primary),
              const SizedBox(width: 10),
              const Text(
                'Your rank',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _rankCopy(scope: scope, watchTimeLabel: watchTimeLabel),
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  String _rankCopy({
    required _LeaderboardScope scope,
    required String watchTimeLabel,
  }) {
    final placement = viewer;
    if (placement == null) {
      return 'Your ${scope.label.toLowerCase()} watch time is $watchTimeLabel on this device. Public placement appears after account opt-in.';
    }
    if (!placement.optedIn) {
      return 'Choose a username, emoji, and join from Account to appear here.';
    }
    if (placement.rank == null) {
      return 'Your ${scope.label.toLowerCase()} watch time is ${_watchTimeLabelForSeconds(placement.activeWatchSeconds)}. Keep watching to place on the board.';
    }
    return 'You are #${placement.rank} and ahead of ${placement.percentile}% of opted-in viewers for ${scope.label.toLowerCase()}.';
  }
}

class _LeaderboardEntryRow extends StatelessWidget {
  const _LeaderboardEntryRow({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '#${entry.rank}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          Text(entry.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.username,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.68),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            _watchTimeLabelForSeconds(entry.activeWatchSeconds),
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.64),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardLoadingRow extends StatelessWidget {
  const _LeaderboardLoadingRow();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonCard(
      height: 44,
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: const SizedBox.expand(),
    );
  }
}

class _LeaderboardMessageRow extends StatelessWidget {
  const _LeaderboardMessageRow({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.70),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryMetricHeroTile extends StatelessWidget {
  const _LibraryMetricHeroTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: JuicrVisual.elevatedCardDecoration(
        colorScheme,
        radius: 16,
        color: colorScheme.primary.withValues(alpha: 0.13),
        borderAlpha: 0,
        shadowAlpha: 0.07,
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryMetricTile extends StatelessWidget {
  const _LibraryMetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: JuicrVisual.elevatedCardDecoration(
        colorScheme,
        radius: 16,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderAlpha: 0,
        shadowAlpha: 0.07,
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary, size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.68),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryMetricBreakdownSection extends StatelessWidget {
  const _LibraryMetricBreakdownSection({
    required this.title,
    required this.icon,
    required this.movieCount,
    required this.seriesCount,
    required this.animationCount,
  });

  final String title;
  final IconData icon;
  final int movieCount;
  final int seriesCount;
  final int animationCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: JuicrVisual.elevatedCardDecoration(
        colorScheme,
        radius: 14,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.44),
        borderAlpha: 0,
        shadowAlpha: 0.05,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _LibraryMetricCountChip(
                  label: 'Movies',
                  count: movieCount,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LibraryMetricCountChip(
                  label: 'Series',
                  count: seriesCount,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LibraryMetricCountChip(
                  label: 'Animation',
                  count: animationCount,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LibraryMetricCountChip extends StatelessWidget {
  const _LibraryMetricCountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.66),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _watchTimeLabelForSeconds(int seconds) {
  final safeSeconds = math.max(0, seconds);
  final hours = safeSeconds ~/ 3600;
  final remainderSeconds = safeSeconds % 3600;
  final minutes = remainderSeconds > 0
      ? math.max(1, (remainderSeconds / 60).ceil())
      : 0;
  if (hours <= 0) return '${minutes.clamp(0, 59)}m';
  if (hours < 24) return '${hours}h ${minutes.clamp(0, 59)}m';
  final days = hours ~/ 24;
  return '${days}d ${hours % 24}h';
}

class _LibraryMetrics {
  const _LibraryMetrics({
    required this.savedCount,
    required this.completedCount,
    required this.totalCompletionCount,
    required this.rewatchCount,
    required this.continueCount,
    required this.savedMovieCount,
    required this.savedSeriesCount,
    required this.savedAnimationCount,
    required this.savedLiveTvCount,
    required this.savedOtherCount,
    required this.continueMovieCount,
    required this.continueSeriesCount,
    required this.continueAnimationCount,
    required this.completedMovieCount,
    required this.completedSeriesCount,
    required this.completedAnimationCount,
    required this.watchSeconds,
  });

  final int savedCount;
  final int completedCount;
  final int totalCompletionCount;
  final int rewatchCount;
  final int continueCount;
  final int savedMovieCount;
  final int savedSeriesCount;
  final int savedAnimationCount;
  final int savedLiveTvCount;
  final int savedOtherCount;
  final int continueMovieCount;
  final int continueSeriesCount;
  final int continueAnimationCount;
  final int completedMovieCount;
  final int completedSeriesCount;
  final int completedAnimationCount;
  final int watchSeconds;

  static _LibraryMetrics fromState({
    required Iterable<CatalogItem> saved,
    required Iterable<ContinueWatchingEntry> progress,
    required Iterable<CompletedWatchingEntry> completed,
  }) {
    final completedList = completed
        .where((entry) => !entry.item.type.isLive)
        .toList(growable: false);
    final progressList = progress
        .where(AppState.isDisplayableContinueEntry)
        .toList(growable: false);
    final savedList = saved.toList(growable: false);
    final totalCompletionCount = completedList.fold<int>(
      0,
      (total, entry) => total + entry.completionCount,
    );
    return _LibraryMetrics(
      savedCount: savedList.length,
      completedCount: completedList.length,
      totalCompletionCount: totalCompletionCount,
      rewatchCount: math.max(0, totalCompletionCount - completedList.length),
      continueCount: progressList.length,
      savedMovieCount: savedList
          .where((item) => item.type == MediaType.movie)
          .length,
      savedSeriesCount: savedList
          .where((item) => item.type == MediaType.series)
          .length,
      savedAnimationCount: savedList
          .where((item) => item.type == MediaType.animation)
          .length,
      savedLiveTvCount: savedList.where((item) => item.type.isLive).length,
      savedOtherCount: savedList
          .where(
            (item) =>
                item.type != MediaType.movie &&
                item.type != MediaType.series &&
                item.type != MediaType.animation &&
                !item.type.isLive,
          )
          .length,
      continueMovieCount: progressList
          .where((entry) => entry.item.type == MediaType.movie)
          .length,
      continueSeriesCount: progressList
          .where((entry) => entry.item.type == MediaType.series)
          .length,
      continueAnimationCount: progressList
          .where((entry) => entry.item.type == MediaType.animation)
          .length,
      completedMovieCount: completedList
          .where((entry) => entry.item.type == MediaType.movie)
          .length,
      completedSeriesCount: completedList
          .where((entry) => entry.item.type == MediaType.series)
          .length,
      completedAnimationCount: completedList
          .where((entry) => entry.item.type == MediaType.animation)
          .length,
      watchSeconds: AppState.activeWatchSecondsForAccountSync(),
    );
  }

  String get watchTimeLabel {
    return _watchTimeLabelForSeconds(watchSeconds);
  }

  String get summary {
    if (completedCount == 0 && continueCount == 0 && savedCount == 0) {
      return 'Active watch time counts only while playback is moving. Pauses, loading, and skipped-ahead time are excluded.';
    }
    return 'Active watch time counts only while playback is moving. Pauses, loading, and skipped-ahead time are excluded.';
  }
}

class _LibraryPageSkeleton extends StatelessWidget {
  const _LibraryPageSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: AppReveal(
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                shape: JuicrVisual.cardShape(colorScheme, alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: const [
                      AppSkeletonCard(width: 42, height: 42, radius: 12),
                      SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppSkeletonLine(height: 15),
                            SizedBox(height: 8),
                            FractionallySizedBox(
                              widthFactor: 0.58,
                              child: AppSkeletonLine(height: 10),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 18),
                      AppSkeletonCircle(size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          sliver: SliverList.separated(
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return AppReveal(
                delay: Duration(milliseconds: 40 * index),
                child: const _ContinueWatchingSkeletonCard(),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContinueWatchingSkeletonCard extends StatelessWidget {
  const _ContinueWatchingSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 154,
        child: Stack(
          children: [
            const Positioned.fill(child: AppSkeletonCard(radius: 14)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.surface.withValues(alpha: 0.74),
                      colorScheme.surface.withValues(alpha: 0.34),
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
                children: const [
                  AppSkeletonCard(width: 82, height: 124, radius: 10),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 8),
                        AppSkeletonLine(height: 16),
                        SizedBox(height: 9),
                        FractionallySizedBox(
                          widthFactor: 0.62,
                          child: AppSkeletonLine(height: 12),
                        ),
                        Spacer(),
                        FractionallySizedBox(
                          widthFactor: 0.46,
                          child: AppShimmerBox(height: 32, radius: 999),
                        ),
                        SizedBox(height: 12),
                        AppSkeletonLine(height: 5),
                      ],
                    ),
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

enum _LibrarySection {
  continueWatching,
  completed,
  lists,
  movie,
  series,
  animation,
  privateCatalogs,
  liveTv,
  music,
  nsfw,
}

enum _LibraryContinueSort { recent, progress, remaining, titleAZ }

extension _LibraryContinueSortInfo on _LibraryContinueSort {
  String get label {
    return switch (this) {
      _LibraryContinueSort.recent => 'Recently played',
      _LibraryContinueSort.progress => 'Most watched',
      _LibraryContinueSort.remaining => 'Least time left',
      _LibraryContinueSort.titleAZ => 'Title A-Z',
    };
  }

  IconData get icon {
    return switch (this) {
      _LibraryContinueSort.recent => Icons.schedule_rounded,
      _LibraryContinueSort.progress => Icons.trending_up_rounded,
      _LibraryContinueSort.remaining => Icons.hourglass_bottom_rounded,
      _LibraryContinueSort.titleAZ => Icons.sort_by_alpha_rounded,
    };
  }
}

enum _LibrarySavedSort { titleAZ, titleZA, newest, highestRated }

extension _LibrarySavedSortInfo on _LibrarySavedSort {
  String get label {
    return switch (this) {
      _LibrarySavedSort.titleAZ => 'Title A-Z',
      _LibrarySavedSort.titleZA => 'Title Z-A',
      _LibrarySavedSort.newest => 'Newest year',
      _LibrarySavedSort.highestRated => 'Highest IMDb',
    };
  }

  IconData get icon {
    return switch (this) {
      _LibrarySavedSort.titleAZ => Icons.sort_by_alpha_rounded,
      _LibrarySavedSort.titleZA => Icons.text_rotation_none_rounded,
      _LibrarySavedSort.newest => Icons.calendar_month_rounded,
      _LibrarySavedSort.highestRated => Icons.star_rounded,
    };
  }
}

extension _LibrarySectionInfo on _LibrarySection {
  static List<_LibrarySection> visibleSections(
    Set<MediaType> activeTypes, {
    bool hasCompleted = false,
    bool hasLocalCatalogItems = false,
  }) {
    return [
      _LibrarySection.continueWatching,
      if (hasCompleted) _LibrarySection.completed,
      _LibrarySection.lists,
      if (hasLocalCatalogItems) _LibrarySection.privateCatalogs,
      _LibrarySection.movie,
      _LibrarySection.series,
      _LibrarySection.animation,
      if (activeTypes.contains(MediaType.liveTv)) _LibrarySection.liveTv,
      if (activeTypes.contains(MediaType.music)) _LibrarySection.music,
      if (activeTypes.contains(MediaType.nsfw)) _LibrarySection.nsfw,
    ];
  }

  String get label {
    return switch (this) {
      _LibrarySection.continueWatching => 'Continue',
      _LibrarySection.completed => 'Completed',
      _LibrarySection.lists => 'Lists',
      _LibrarySection.movie => 'Movies',
      _LibrarySection.series => 'Series',
      _LibrarySection.animation => 'Animation',
      _LibrarySection.privateCatalogs => 'Custom Catalogs',
      _LibrarySection.liveTv => 'Live TV',
      _LibrarySection.music => 'Music',
      _LibrarySection.nsfw => 'NSFW',
    };
  }

  String get subtitle {
    return switch (this) {
      _LibrarySection.continueWatching => 'Recently played titles',
      _LibrarySection.completed => 'Finished titles',
      _LibrarySection.lists => 'Custom watchlists',
      _LibrarySection.movie => 'Saved movies',
      _LibrarySection.series => 'Saved series',
      _LibrarySection.animation => 'Saved animation',
      _LibrarySection.privateCatalogs => 'Private Catalog Builder items',
      _LibrarySection.liveTv => 'Saved live channels',
      _LibrarySection.music => 'Saved music',
      _LibrarySection.nsfw => 'Saved mature titles',
    };
  }

  IconData get icon {
    return switch (this) {
      _LibrarySection.continueWatching => Icons.history_rounded,
      _LibrarySection.completed => Icons.check_circle_outline_rounded,
      _LibrarySection.lists => Icons.bookmarks_outlined,
      _LibrarySection.movie => Icons.movie_outlined,
      _LibrarySection.series => Icons.tv_outlined,
      _LibrarySection.animation => Icons.auto_awesome_outlined,
      _LibrarySection.privateCatalogs => Icons.folder_special_outlined,
      _LibrarySection.liveTv => Icons.live_tv_rounded,
      _LibrarySection.music => Icons.library_music_outlined,
      _LibrarySection.nsfw => Icons.visibility_off_outlined,
    };
  }

  MediaType? get mediaType {
    return switch (this) {
      _LibrarySection.continueWatching => null,
      _LibrarySection.completed => null,
      _LibrarySection.lists => null,
      _LibrarySection.movie => MediaType.movie,
      _LibrarySection.series => MediaType.series,
      _LibrarySection.animation => MediaType.animation,
      _LibrarySection.privateCatalogs => null,
      _LibrarySection.liveTv => MediaType.liveTv,
      _LibrarySection.music => MediaType.music,
      _LibrarySection.nsfw => MediaType.nsfw,
    };
  }
}

String _completedDateLabel(DateTime completedAt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final completedDay = DateTime(
    completedAt.year,
    completedAt.month,
    completedAt.day,
  );
  final days = today.difference(completedDay).inDays;
  if (days <= 0) return 'Completed today';
  if (days == 1) return 'Completed yesterday';
  if (days < 7) return 'Completed ${days}d ago';
  if (days < 30) return 'Completed ${(days / 7).floor()}w ago';
  return 'Completed ${completedAt.year}';
}

String _watchCountLabel(int count) {
  if (count <= 1) return 'Watched once';
  return 'Watched ${count}x';
}

class _LibraryAddonAvailability {
  const _LibraryAddonAvailability({
    required this.activeTypes,
    required this.activeLiveTvIds,
  });

  static const empty = _LibraryAddonAvailability(
    activeTypes: <MediaType>{},
    activeLiveTvIds: <String>{},
  );

  final Set<MediaType> activeTypes;
  final Set<String> activeLiveTvIds;
}

class _LibrarySettingsOption extends StatelessWidget {
  const _LibrarySettingsOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return JuicrSheetOptionTile(
      label: label,
      icon: icon,
      selected: selected,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    );
  }
}

class _LibrarySectionCard extends StatelessWidget {
  const _LibrarySectionCard({
    required this.selectedSection,
    required this.sections,
    required this.onChanged,
  });

  final _LibrarySection selectedSection;
  final List<_LibrarySection> sections;
  final ValueChanged<_LibrarySection> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(
        alpha: colorScheme.brightness == Brightness.dark ? 0.5 : 0.16,
      ),
      shape: JuicrVisual.cardShape(colorScheme, alpha: 0.3),
      child: Semantics(
        button: true,
        label: 'Library section',
        value: selectedSection.label,
        hint: 'Choose library section',
        child: ExcludeSemantics(
          child: InkWell(
            borderRadius: BorderRadius.circular(JuicrVisual.cardRadius),
            onTap: () => _showSectionPicker(context),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compactLandscape ? 12 : 14,
                vertical: compactLandscape ? 9 : 13,
              ),
              child: Row(
                children: [
                  Container(
                    width: compactLandscape ? 34 : 42,
                    height: compactLandscape ? 34 : 42,
                    decoration: JuicrVisual.elevatedIconDecoration(
                      colorScheme,
                      radius: 12,
                      shadowAlpha: 0.12,
                      glowAlpha: 0.11,
                    ),
                    child: Icon(
                      selectedSection.icon,
                      color: colorScheme.primary,
                      size: compactLandscape ? 19 : 22,
                    ),
                  ),
                  SizedBox(width: compactLandscape ? 10 : 13),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedSection.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (compactLandscape
                                      ? Theme.of(context).textTheme.titleSmall
                                      : Theme.of(context).textTheme.titleMedium)
                                  ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: compactLandscape ? 2 : 3),
                        Text(
                          selectedSection.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.62,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: compactLandscape ? 8 : 10),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.primary,
                    size: compactLandscape ? 22 : 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSectionPicker(BuildContext context) async {
    final selected = await showJuicrBottomSheet<_LibrarySection>(
      context: context,
      builder: (sheetContext) {
        return SingleChildScrollView(
          padding: juicrBottomSheetPadding(sheetContext, left: 0, right: 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final section in sections)
                JuicrSheetOptionTile(
                  label: section.label,
                  subtitle: section.subtitle,
                  icon: section.icon,
                  selected: selectedSection == section,
                  onTap: () => Navigator.of(sheetContext).pop(section),
                ),
            ],
          ),
        );
      },
    );
    if (selected != null) onChanged(selected);
  }
}

class _CompletionSummary {
  const _CompletionSummary(this.label);

  final String label;
}

bool _continueEntryHasCompletedRecord(
  ContinueWatchingEntry entry,
  Map<String, CompletedWatchingEntry> completed,
) {
  if (completed.isEmpty) return false;
  if (!entry.item.type.isPlayableSeries) {
    return completed.values.any(
      (completedEntry) => completedEntry.item.id == entry.item.id,
    );
  }
  final contentKey = AppState.contentPlaybackKeyFor(entry.item, entry.key);
  return completed.containsKey(entry.key) ||
      completed.containsKey(contentKey) ||
      completed.values.any((completedEntry) {
        final completedKey = AppState.contentPlaybackKeyFor(
          entry.item,
          completedEntry.key,
        );
        return completedKey == contentKey;
      });
}

_CompletionSummary? _completionSummaryForItem(
  CatalogItem item,
  Map<String, CompletedWatchingEntry> completed,
) {
  final itemEntries = completed.values.where((entry) {
    final contentKey = AppState.contentPlaybackKeyFor(item, entry.key);
    return entry.item.id == item.id ||
        contentKey == item.id ||
        contentKey.startsWith('${item.id}:');
  }).toList();
  if (itemEntries.isEmpty) return null;

  if (!item.type.isPlayableSeries) {
    return itemEntries.any(
          (entry) => AppState.contentPlaybackKeyFor(item, entry.key) == item.id,
        )
        ? const _CompletionSummary('Watched')
        : null;
  }

  final episodeSlots = <_EpisodeSlot>{};
  for (final entry in itemEntries) {
    final slot = _episodeSlotFromKey(item.id, entry.key);
    if (slot != null) episodeSlots.add(slot);
  }
  if (episodeSlots.isEmpty) return null;

  final sorted = episodeSlots.toList()
    ..sort((a, b) {
      final seasonCompare = a.season.compareTo(b.season);
      if (seasonCompare != 0) return seasonCompare;
      return a.episode.compareTo(b.episode);
    });
  if (sorted.length == 1) {
    final slot = sorted.first;
    return _CompletionSummary('S${slot.season} E${slot.episode} watched');
  }
  return _CompletionSummary('${sorted.length} episodes watched');
}

List<CompletedWatchingEntry> _dedupeCompletedItems(
  Iterable<CompletedWatchingEntry> entries,
) {
  final sorted = entries.toList()
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  final seen = <String>{};
  final deduped = <CompletedWatchingEntry>[];
  for (final entry in sorted) {
    final identity = entry.item.type.isPlayableSeries
        ? entry.key
        : entry.item.id.toLowerCase();
    if (identity.isEmpty || !seen.add(identity)) continue;
    deduped.add(entry);
  }
  return deduped;
}

_EpisodeSlot? _episodeSlotFromKey(String itemId, String key) {
  final suffix = ':$itemId:';
  final suffixIndex = key.lastIndexOf(suffix);
  if (suffixIndex >= 0) {
    key = key.substring(suffixIndex + 1);
  }
  final prefix = '$itemId:';
  if (!key.startsWith(prefix)) return null;
  final parts = key.substring(prefix.length).split(':');
  if (parts.length < 2) return null;
  final season = int.tryParse(parts[0]);
  final episode = int.tryParse(parts[1]);
  if (season == null || episode == null) return null;
  return _EpisodeSlot(season, episode);
}

class _EpisodeSlot {
  const _EpisodeSlot(this.season, this.episode);

  final int season;
  final int episode;

  @override
  bool operator ==(Object other) {
    return other is _EpisodeSlot &&
        other.season == season &&
        other.episode == episode;
  }

  @override
  int get hashCode => Object.hash(season, episode);
}

class _CompletionPill extends StatelessWidget {
  const _CompletionPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: colorScheme.primary.withValues(alpha: 0.9),
          boxShadow: JuicrVisual.softShadow(
            colorScheme,
            alpha: 0.3,
            blur: 16,
            y: 7,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 13, color: colorScheme.onPrimary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w900,
                    height: 1,
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

class _LibraryPoster extends StatelessWidget {
  const _LibraryPoster({
    required this.item,
    required this.index,
    this.completionSummary,
  });

  final CatalogItem item;
  final int index;
  final _CompletionSummary? completionSummary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cacheWidth = _libraryImageCacheWidth(context, 180);
    return AppReveal(
      delay: Duration(milliseconds: 22 * (index % 12)),
      child: Semantics(
        button: true,
        label: 'Open ${item.name}',
        hint: 'Show details',
        child: ExcludeSemantics(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              unawaited(
                JuicrAdPolicy.maybeShowInterstitial(
                  reason: 'library_title_open',
                ),
              );
              Navigator.of(context).push(
                AppPageRoute<void>(builder: (_) => DetailsPage(item: item)),
              );
            },
            child: item.type.isLive
                ? _LibraryLiveChannel(item: item)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ColoredBox(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.72,
                          ),
                          child: item.poster == null
                              ? item.isLocalCatalogItem
                                    ? _LibraryLocalPosterFallback(item: item)
                                    : Center(
                                        child: Icon(
                                          Icons.movie,
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.38),
                                        ),
                                      )
                              : Image.network(
                                  item.poster!,
                                  fit: BoxFit.cover,
                                  cacheWidth: cacheWidth,
                                  errorBuilder: (_, __, ___) {
                                    return Center(
                                      child: Icon(
                                        Icons.broken_image,
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.38,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      if (item.isLocalCatalogItem)
                        const Positioned(
                          left: 7,
                          top: 7,
                          child: _LibraryLocalBadge(),
                        ),
                      if (completionSummary != null)
                        Positioned(
                          left: 7,
                          right: 7,
                          bottom: 7,
                          child: _CompletionPill(
                            label: completionSummary!.label,
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

class _LibraryLocalPosterFallback extends StatelessWidget {
  const _LibraryLocalPosterFallback({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shelfName = item.localCatalogName?.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.32),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 34, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.video_library_outlined,
              color: colorScheme.primary,
              size: 24,
            ),
            const Spacer(),
            Text(
              item.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                height: 1.08,
              ),
            ),
            if (shelfName != null && shelfName.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                shelfName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LibraryLocalBadge extends StatelessWidget {
  const _LibraryLocalBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'LOCAL',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _LibraryLiveChannel extends StatelessWidget {
  const _LibraryLiveChannel({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = item.logo ?? item.poster;
    final cacheWidth = _libraryImageCacheWidth(context, 160);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: imageUrl == null
                      ? Icon(
                          Icons.live_tv_rounded,
                          color: colorScheme.onSurface.withValues(alpha: 0.46),
                          size: 34,
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          cacheWidth: cacheWidth,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) {
                            return Icon(
                              Icons.live_tv_rounded,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.46,
                              ),
                              size: 34,
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int _libraryImageCacheWidth(BuildContext context, double logicalWidth) {
  final width = logicalWidth * MediaQuery.devicePixelRatioOf(context);
  return width.clamp(120, 900).round();
}

int _compareText(String left, String right) {
  return left.toLowerCase().compareTo(right.toLowerCase());
}

int _itemYear(CatalogItem item) {
  final match = RegExp(r'\d{4}').firstMatch(item.year ?? '');
  return int.tryParse(match?.group(0) ?? '') ?? 0;
}

double _itemRating(CatalogItem item) {
  return double.tryParse(item.imdbRating ?? '') ?? 0;
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: AppReveal(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_border,
                size: 54,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Your library is empty',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap the heart on any movie or series to save it here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                ),
              ),
              const SizedBox(height: 22),
              const SizedBox(
                width: double.infinity,
                child: JuicrBannerAdSlot(placement: 'library_empty'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyContinueWatching extends StatelessWidget {
  const _EmptyContinueWatching();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: AppReveal(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 54, color: colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'Nothing to continue yet',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Start watching something and it will show up here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                ),
              ),
              const SizedBox(height: 22),
              const SizedBox(
                width: double.infinity,
                child: JuicrBannerAdSlot(placement: 'library_empty_continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCompletedWatching extends StatelessWidget {
  const _EmptyCompletedWatching();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 54,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing completed yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Finished movies and episodes will move here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
            const SizedBox(height: 22),
            const SizedBox(
              width: double.infinity,
              child: JuicrBannerAdSlot(placement: 'library_empty_completed'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibraryType extends StatelessWidget {
  const _EmptyLibraryType({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: AppReveal(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                switch (type) {
                  MediaType.movie => Icons.movie_outlined,
                  MediaType.series => Icons.tv_outlined,
                  MediaType.animation => Icons.auto_awesome_outlined,
                  MediaType.liveTv => Icons.live_tv_rounded,
                  MediaType.music => Icons.library_music_outlined,
                  MediaType.nsfw => Icons.visibility_off_outlined,
                },
                size: 54,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'No saved ${type.pluralLabel.toLowerCase()} yet',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Switch the filter or save more ${type.pluralLabel.toLowerCase()} to see them here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                ),
              ),
              const SizedBox(height: 22),
              const SizedBox(
                width: double.infinity,
                child: JuicrBannerAdSlot(placement: 'library_empty_type'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
