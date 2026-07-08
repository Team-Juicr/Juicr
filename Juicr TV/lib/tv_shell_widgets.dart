part of 'main.dart';

class _TvMainSurface extends StatelessWidget {
  const _TvMainSurface({
    required this.title,
    required this.selectedTab,
    required this.loading,
    required this.error,
    required this.expandedRail,
    required this.rails,
    required this.homeHeroItems,
    required this.homeHeroIndex,
    required this.homeHeroCarouselPaused,
    required this.homeHeroEditorial,
    required this.homeHeroKey,
    required this.homeHeroWatchFocusNode,
    required this.allItems,
    required this.movies,
    required this.series,
    required this.animation,
    required this.liveTv,
    required this.discoveryLaneItems,
    required this.recentItems,
    required this.likedItems,
    required this.libraryLists,
    required this.discoveryKind,
    required this.discoverySort,
    required this.discoveryGenre,
    required this.discoveryLoading,
    required this.discoveryExhausted,
    required this.libraryFilter,
    required this.accountSignedIn,
    required this.accountToken,
    required this.accountLabel,
    required this.accountSyncLabel,
    required this.recentCount,
    required this.savedCount,
    required this.completedCount,
    required this.activeWatchLabel,
    required this.activeWatchSeconds,
    required this.tvSettings,
    required this.onTvSettingsChanged,
    required this.onLeaderboardScopeChanged,
    required this.onAccountSignIn,
    required this.onAccountSignOut,
    required this.onAccountSync,
    required this.onDiscoveryMenu,
    required this.onDiscoveryLoadMore,
    required this.onLibraryMenu,
    required this.onOpenLibraryRanking,
    required this.onOpenLibraryMetrics,
    required this.onOpenItem,
    required this.onHomeHeroIndexChanged,
    required this.onOpenItemLibraryMenu,
    required this.onPlayItem,
    required this.onTrailerItem,
    required this.onOpenRail,
    required this.onBackToHome,
    required this.onFocusNavigation,
    required this.pageEntryFocusNode,
    required this.pageContentFocusNode,
    required this.onFocusPageEntry,
    required this.onFocusPageContent,
    required this.onRememberPageFocus,
    required this.onRememberPageItemFocus,
    required this.onRestorePageItemFocus,
    required this.onRetry,
    this.restoreItemKey,
  });

  final String title;
  final int selectedTab;
  final bool loading;
  final String? error;
  final _TvRail? expandedRail;
  final List<_TvRail> rails;
  final List<_TvItem> homeHeroItems;
  final int homeHeroIndex;
  final bool homeHeroCarouselPaused;
  final _TvHomeEditorialRail homeHeroEditorial;
  final GlobalKey homeHeroKey;
  final FocusNode homeHeroWatchFocusNode;
  final List<_TvItem> allItems;
  final List<_TvItem> movies;
  final List<_TvItem> series;
  final List<_TvItem> animation;
  final List<_TvItem> liveTv;
  final Map<String, List<_TvItem>> discoveryLaneItems;
  final List<_TvItem> recentItems;
  final List<_TvItem> likedItems;
  final List<TvLibraryList> libraryLists;
  final _TvDiscoveryKind discoveryKind;
  final _TvDiscoverySort discoverySort;
  final String discoveryGenre;
  final bool discoveryLoading;
  final bool discoveryExhausted;
  final _TvLibraryFilter libraryFilter;
  final bool accountSignedIn;
  final String accountToken;
  final String accountLabel;
  final String accountSyncLabel;
  final int recentCount;
  final int savedCount;
  final int completedCount;
  final String activeWatchLabel;
  final int activeWatchSeconds;
  final _TvSettingsState tvSettings;
  final ValueChanged<_TvSettingsState> onTvSettingsChanged;
  final ValueChanged<String> onLeaderboardScopeChanged;
  final VoidCallback onAccountSignIn;
  final VoidCallback onAccountSignOut;
  final VoidCallback onAccountSync;
  final VoidCallback onDiscoveryMenu;
  final VoidCallback onDiscoveryLoadMore;
  final VoidCallback onLibraryMenu;
  final VoidCallback onOpenLibraryRanking;
  final VoidCallback onOpenLibraryMetrics;
  final Future<void> Function(_TvItem item) onOpenItem;
  final ValueChanged<int> onHomeHeroIndexChanged;
  final ValueChanged<_TvItem> onOpenItemLibraryMenu;
  final ValueChanged<_TvItem> onPlayItem;
  final ValueChanged<_TvItem> onTrailerItem;
  final ValueChanged<_TvRail> onOpenRail;
  final VoidCallback onBackToHome;
  final VoidCallback onFocusNavigation;
  final FocusNode pageEntryFocusNode;
  final FocusNode pageContentFocusNode;
  final VoidCallback onFocusPageEntry;
  final VoidCallback onFocusPageContent;
  final ValueChanged<FocusNode> onRememberPageFocus;
  final void Function(FocusNode node, _TvItem item) onRememberPageItemFocus;
  final ValueChanged<String> onRestorePageItemFocus;
  final VoidCallback onRetry;
  final String? restoreItemKey;

  @override
  Widget build(BuildContext context) {
    final showHeader = selectedTab != 0;
    final headerTitle = selectedTab == 1 ? _tvDiscoveryGreetingTitle() : title;
    return Column(
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 24, 48, 18),
            child: _TvHeader(
              title: headerTitle,
              onFocusNavigation: onFocusNavigation,
              trailing: selectedTab == 1
                  ? _TvDiscoveryFilterButton(
                      kind: discoveryKind,
                      sort: discoverySort,
                      genre: discoveryGenre,
                      onPressed: () {
                        onRememberPageFocus(pageEntryFocusNode);
                        onDiscoveryMenu();
                      },
                      onFocus: () => onRememberPageFocus(pageEntryFocusNode),
                      onArrowLeft: onFocusNavigation,
                      onArrowUp: onFocusPageEntry,
                      onArrowDown: onFocusPageContent,
                      onArrowRight: onFocusPageEntry,
                      focusNode: pageEntryFocusNode,
                    )
                  : selectedTab == 2
                  ? _TvLibraryHeaderActions(
                      filter: libraryFilter,
                      filterFocusNode: pageEntryFocusNode,
                      onFilterPressed: () {
                        onRememberPageFocus(pageEntryFocusNode);
                        onLibraryMenu();
                      },
                      onOpenRanking: onOpenLibraryRanking,
                      onOpenMetrics: onOpenLibraryMetrics,
                      onFocusFilter: () =>
                          onRememberPageFocus(pageEntryFocusNode),
                      onFocusNavigation: onFocusNavigation,
                      onFocusPageEntry: onFocusPageEntry,
                      onFocusPageContent: onFocusPageContent,
                      onRememberPageFocus: onRememberPageFocus,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        Expanded(
          child: CustomScrollView(
            key: selectedTab == 0
                ? const ValueKey<String>('tv-main-scroll-home')
                : PageStorageKey<String>(
                    'tv-main-scroll-$selectedTab-${expandedRail == null ? 'root' : 'expanded'}',
                  ),
            slivers: [
              SliverPadding(
                padding: selectedTab == 0
                    ? const EdgeInsets.fromLTRB(0, 0, 0, 24)
                    : const EdgeInsets.fromLTRB(30, 0, 48, 90),
                sliver: _body(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    SliverToBoxAdapter viewportStateSliver(Widget child) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: math.max(0, MediaQuery.sizeOf(context).height - 210),
          child: child,
        ),
      );
    }

    if (selectedTab == 3) {
      return SliverToBoxAdapter(
        child: _TvSettingsSurface(
          totalCount: allItems.length,
          movieCount: movies.length,
          seriesCount: series.length,
          animationCount: animation.length,
          hasCatalog: allItems.isNotEmpty,
          accountSignedIn: accountSignedIn,
          accountLabel: accountLabel,
          accountSyncLabel: accountSyncLabel,
          recentCount: recentCount,
          savedCount: savedCount,
          completedCount: completedCount,
          activeWatchLabel: activeWatchLabel,
          settings: tvSettings,
          onSettingsChanged: onTvSettingsChanged,
          onAccountSignIn: onAccountSignIn,
          onAccountSignOut: onAccountSignOut,
          onAccountSync: onAccountSync,
          onFocusNavigation: onFocusNavigation,
          onRefresh: onRetry,
          entryFocusNode: pageEntryFocusNode,
          onRememberFocus: onRememberPageFocus,
        ),
      );
    }
    if (loading) {
      if (selectedTab == 1) {
        return viewportStateSliver(
          _TvCatalogLoadingState(
            height: MediaQuery.sizeOf(context).height - 210,
          ),
        );
      }
      return viewportStateSliver(_TvLoadingState(selectedTab: selectedTab));
    }
    if (error != null && selectedTab != 2 && selectedTab != 3) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _TvErrorState(message: error!, onRetry: onRetry),
      );
    }
    if (expandedRail != null) {
      return SliverToBoxAdapter(
        child: _TvExpandedRail(
          rail: expandedRail!,
          onBack: onBackToHome,
          onOpenItem: onOpenItem,
          onFocusNavigation: onFocusNavigation,
          backFocusNode: pageEntryFocusNode,
          gridFocusNode: pageContentFocusNode,
          onRememberFocus: onRememberPageFocus,
          onRememberItemFocus: onRememberPageItemFocus,
          restoreItemKey: restoreItemKey,
          onRestoreItemFocus: onRestorePageItemFocus,
        ),
      );
    }
    if (selectedTab == 1) {
      if (!tvSettings.hasCatalogSource) {
        return SliverToBoxAdapter(
          child: _TvEmptyCatalogState(
            title: 'Choose a source to fill Discovery.',
            subtitle: 'Enable built-in browsing in Settings to start.',
            height: MediaQuery.sizeOf(context).height - 210,
            focusNode: pageContentFocusNode,
            onFocusNavigation: onFocusNavigation,
            onFocusHeader: onFocusPageEntry,
          ),
        );
      }
      if (allItems.isEmpty && !discoveryExhausted) {
        return viewportStateSliver(
          _TvCatalogLoadingState(
            height: MediaQuery.sizeOf(context).height - 210,
          ),
        );
      }
      return SliverToBoxAdapter(
        child: _TvDiscoverySurface(
          allItems: allItems,
          movies: movies,
          series: series,
          animation: animation,
          liveTv: liveTv,
          discoveryLaneItems: discoveryLaneItems,
          kind: discoveryKind,
          sort: discoverySort,
          genre: discoveryGenre,
          loadingMore: discoveryLoading,
          exhausted: discoveryExhausted,
          onOpenItem: onOpenItem,
          onFocusNavigation: onFocusNavigation,
          entryFocusNode: pageContentFocusNode,
          onFocusHeader: onFocusPageEntry,
          onRememberFocus: onRememberPageFocus,
          onRememberItemFocus: onRememberPageItemFocus,
          restoreItemKey: restoreItemKey,
          onRestoreItemFocus: onRestorePageItemFocus,
          onLoadMore: onDiscoveryLoadMore,
        ),
      );
    }
    if (selectedTab == 2) {
      return SliverToBoxAdapter(
        child: _TvLibrarySurface(
          recentItems: recentItems,
          likedItems: likedItems,
          libraryLists: libraryLists,
          filter: libraryFilter,
          accountSignedIn: accountSignedIn,
          accountToken: accountToken,
          activeWatchLabel: activeWatchLabel,
          activeWatchSeconds: activeWatchSeconds,
          leaderboardScope: tvSettings.leaderboardScope,
          recentCount: recentCount,
          savedCount: savedCount,
          completedCount: completedCount,
          onLeaderboardScopeChanged: onLeaderboardScopeChanged,
          onAccountSignIn: onAccountSignIn,
          onOpenItem: onOpenItem,
          onFocusNavigation: onFocusNavigation,
          entryFocusNode: pageContentFocusNode,
          onFocusHeader: onFocusPageEntry,
          onRememberFocus: onRememberPageFocus,
          onRememberItemFocus: onRememberPageItemFocus,
          restoreItemKey: restoreItemKey,
          onRestoreItemFocus: onRestorePageItemFocus,
        ),
      );
    }
    if (!tvSettings.hasCatalogSource) {
      return SliverToBoxAdapter(
        child: Column(
          children: [
            const SizedBox(height: _tvHomeEmptyStateHeaderSpacer),
            _TvEmptyCatalogState(
              title: 'Juicr TV is ready for your sources.',
              subtitle: 'Open Settings and enable built-in browsing to start.',
              height: MediaQuery.sizeOf(context).height - 210,
              focusNode: pageContentFocusNode,
              onFocusNavigation: onFocusNavigation,
              onFocusHeader: onFocusPageEntry,
            ),
          ],
        ),
      );
    }
    final heroItems = homeHeroItems;
    final heroItem = heroItems.isEmpty ? null : heroItems.first;
    final heroOffset = heroItems.isEmpty ? 0 : 1;
    if (heroItem == null && rails.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _TvErrorState(
          message: 'Catalog is unavailable right now. Try again shortly.',
          onRetry: onRetry,
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (heroItem != null && index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TvHomeHero(
                  key: homeHeroKey,
                  items: heroItems,
                  initialIndex: homeHeroIndex,
                  paused: homeHeroCarouselPaused,
                  onIndexChanged: onHomeHeroIndexChanged,
                  editorial: homeHeroEditorial,
                  onOpenItem: onOpenItem,
                  onOpenLibraryMenu: onOpenItemLibraryMenu,
                  onFocusNavigation: onFocusNavigation,
                  onFocusFirstRail: () {
                    pageEntryFocusNode.requestFocus();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final firstRailContext = pageEntryFocusNode.context;
                      if (firstRailContext == null ||
                          !firstRailContext.mounted ||
                          !pageEntryFocusNode.hasFocus) {
                        return;
                      }
                      try {
                        Scrollable.ensureVisible(
                          firstRailContext,
                          duration: _tvDuration(180),
                          curve: Curves.easeOutCubic,
                          alignment: 0.36,
                          alignmentPolicy:
                              ScrollPositionAlignmentPolicy.explicit,
                        );
                      } on FlutterError {
                        // The Home rail can rebuild while catalog data swaps in.
                        // Focus is already on the requested node; skip scrolling
                        // if its old scrollable disappeared during that frame.
                      }
                    });
                  },
                  watchFocusNode: homeHeroWatchFocusNode,
                  onRememberFocus: onRememberPageFocus,
                  onRememberItemFocus: onRememberPageItemFocus,
                ),
                const _TvHeroRailFade(),
              ],
            );
          }
          if (rails.isEmpty) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(30, 0, 48, 90),
              child: _TvPendingHomeRailsSkeleton(),
            );
          }
          final railIndex = index - heroOffset;
          final isLastRail = railIndex == rails.length - 1;
          return Padding(
            padding: const EdgeInsets.fromLTRB(30, 0, 48, _tvSpacing),
            child: _TvContentRail(
              rail: rails[railIndex],
              onOpenItem: onOpenItem,
              onFocusNavigation: onFocusNavigation,
              firstItemFocusNode: railIndex == 0 ? pageEntryFocusNode : null,
              onRememberFocus: onRememberPageFocus,
              onRememberItemFocus: onRememberPageItemFocus,
              restoreItemKey: restoreItemKey,
              onRestoreItemFocus: onRestorePageItemFocus,
              centerOnFocus: selectedTab == 0,
              trapArrowDown: isLastRail,
              bottomPadding: isLastRail ? 16 : 0,
              revealAlignment: isLastRail ? 0.38 : 0.26,
              onItemArrowUp: railIndex == 0 && heroItem != null
                  ? () {
                      homeHeroWatchFocusNode.requestFocus();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final heroContext = homeHeroKey.currentContext;
                        if (heroContext == null ||
                            !heroContext.mounted ||
                            !homeHeroWatchFocusNode.hasFocus) {
                          return;
                        }
                        try {
                          Scrollable.ensureVisible(
                            heroContext,
                            duration: _tvDuration(180),
                            curve: Curves.easeOutCubic,
                            alignment: 0,
                            alignmentPolicy:
                                ScrollPositionAlignmentPolicy.explicit,
                          );
                        } on FlutterError {
                          // Ignore stale scrollables during Home rebuilds.
                        }
                      });
                    }
                  : null,
            ),
          );
        },
        childCount: rails.isEmpty && heroItem != null
            ? 2
            : rails.length + heroOffset,
      ),
    );
  }
}

class _TvHeroRailFade extends StatelessWidget {
  const _TvHeroRailFade();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF000000), Color(0xF2000000), Color(0xFF000000)],
          ),
        ),
      ),
    );
  }
}

class _TvHomeHero extends StatefulWidget {
  const _TvHomeHero({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.paused,
    required this.onIndexChanged,
    required this.editorial,
    required this.onOpenItem,
    required this.onOpenLibraryMenu,
    required this.onFocusNavigation,
    required this.onFocusFirstRail,
    required this.watchFocusNode,
    required this.onRememberFocus,
    required this.onRememberItemFocus,
  });

  final List<_TvItem> items;
  final int initialIndex;
  final bool paused;
  final ValueChanged<int> onIndexChanged;
  final _TvHomeEditorialRail editorial;
  final ValueChanged<_TvItem> onOpenItem;
  final ValueChanged<_TvItem> onOpenLibraryMenu;
  final VoidCallback onFocusNavigation;
  final VoidCallback onFocusFirstRail;
  final FocusNode watchFocusNode;
  final ValueChanged<FocusNode> onRememberFocus;
  final void Function(FocusNode node, _TvItem item) onRememberItemFocus;

  @override
  State<_TvHomeHero> createState() => _TvHomeHeroState();
}

class _TvHomeHeroState extends State<_TvHomeHero> {
  Timer? _carouselTimer;
  final FocusNode _likeFocusNode = FocusNode(debugLabel: 'tv-home-hero-like');
  int _index = 0;

  _TvItem get _item =>
      widget.items[_index.clamp(0, widget.items.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    _index = _clampedInitialIndex();
    _syncCarouselTimer();
  }

  @override
  void didUpdateWidget(covariant _TvHomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.map((item) => '${item.type}:${item.id}').join('|') !=
        widget.items.map((item) => '${item.type}:${item.id}').join('|')) {
      _index = _clampedInitialIndex();
      _syncCarouselTimer();
    } else if (oldWidget.initialIndex != widget.initialIndex &&
        widget.initialIndex != _index) {
      _index = _clampedInitialIndex();
    } else if (oldWidget.paused != widget.paused) {
      _syncCarouselTimer();
    }
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _likeFocusNode.dispose();
    super.dispose();
  }

  void _syncCarouselTimer() {
    _carouselTimer?.cancel();
    if (widget.paused) return;
    if (widget.items.length < 2) return;
    _carouselTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || widget.items.length < 2) return;
      final nextIndex = (_index + 1) % widget.items.length;
      setState(() => _index = nextIndex);
      widget.onIndexChanged(nextIndex);
    });
  }

  int _clampedInitialIndex() {
    if (widget.items.isEmpty) return 0;
    return widget.initialIndex.clamp(0, widget.items.length - 1).toInt();
  }

  String _typeLabel(_TvItem item) {
    return switch (item.type.trim().toLowerCase()) {
      'movie' => 'Movie',
      'series' => 'Series',
      'animation' => 'Animations',
      'live_tv' || 'livetv' || 'live-tv' => 'Live TV',
      _ => 'Title',
    };
  }

  List<String> _metadataFor(_TvItem item) {
    final values = <String>[
      if ((item.year ?? '').trim().isNotEmpty) item.year!.trim(),
      _typeLabel(item),
      if ((item.imdbRating ?? '').trim().isNotEmpty)
        'IMDb ${item.imdbRating!.trim()}',
      if ((item.runtime ?? '').trim().isNotEmpty) item.runtime!.trim(),
      ...item.genres
          .map((genre) => genre.trim())
          .where((genre) => genre.isNotEmpty)
          .take(2),
    ];
    return values.toSet().toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final item = _item;
    final metadata = _metadataFor(item);
    final backdrop = item.background ?? item.poster;
    final displayBackdrop = backdrop == null
        ? null
        : _tvSizedTmdbImage(backdrop, 'w1280');
    return SizedBox(
      width: double.infinity,
      height: _tvHomeHeroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF000000)),
          if (displayBackdrop != null)
            Positioned.fill(
              child: ClipPath(
                clipper: const _TvHomeHeroArtClipper(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      bottom: -_tvHomeHeroBackdropOverscan,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Image.network(
                          displayBackdrop,
                          fit: BoxFit.cover,
                          alignment: Alignment.topRight,
                          cacheWidth: 1280,
                          filterQuality: FilterQuality.low,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: Color(0xFF000000)),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      bottom: -_tvHomeHeroBackdropOverscan,
                      child: Image.network(
                        displayBackdrop,
                        fit: BoxFit.cover,
                        alignment: Alignment.topRight,
                        cacheWidth: 1280,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: Color(0xFF000000)),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: _tvHomeHeroBottomBlurHeight,
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0x08000000),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const _TvHomeHeroCurveScrim(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xFF000000),
                  Color(0xD6000000),
                  Color(0x66000000),
                  Color(0x18000000),
                  Color(0x00000000),
                ],
                stops: [0, 0.16, 0.36, 0.62, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.centerRight,
                radius: 1.1,
                colors: [Color(0x00000000), Color(0x73000000)],
              ),
            ),
          ),
          Positioned(
            left: _tvHomeHeroCopyLeftInset,
            top: _tvHomeHeroCopyTopInset,
            right: _tvHomeHeroCopyRightInset,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedSwitcher(
                duration: _tvDuration(520),
                reverseDuration: _tvDuration(320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0.018, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: Row(
                  key: ValueKey('hero-copy-${item.type}:${item.id}'),
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _TvHomeHeroPoster(item: item),
                    const SizedBox(width: 26),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: _TvHeroTitleWheel(item: item),
                          ),
                          if (metadata.isNotEmpty) ...[
                            const SizedBox(height: _tvSpacing),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 540),
                              child: Text(
                                metadata.join('  -  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFD4D0E5),
                                  fontSize: 13,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: _tvSpacing),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: SizedBox(
                              height:
                                  _TvHeroScrollingDescription.viewportHeight,
                              child:
                                  (item.description ?? '').trim().isNotEmpty
                                  ? _TvHeroScrollingDescription(
                                      text: item.description!.trim(),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _TvTextButton(
                                icon: Icons.info_outline_rounded,
                                label: 'Details',
                                autofocus: true,
                                autoReveal: false,
                                focusNode: widget.watchFocusNode,
                                onFocus: () {
                                  widget.onRememberFocus(
                                    widget.watchFocusNode,
                                  );
                                  widget.onRememberItemFocus(
                                    widget.watchFocusNode,
                                    item,
                                  );
                                },
                                onArrowLeft: widget.onFocusNavigation,
                                onArrowRight: _likeFocusNode.requestFocus,
                                onArrowUp: widget.watchFocusNode.requestFocus,
                                onArrowDown: widget.onFocusFirstRail,
                                minHeight: 42,
                                horizontalPadding: 16,
                                verticalPadding: 10,
                                iconSize: 18,
                                fontSize: 14,
                                onPressed: () => widget.onOpenItem(item),
                              ),
                              const SizedBox(width: 10),
                              _TvCircleIconButton(
                                icon: Icons.more_horiz_rounded,
                                selected: false,
                                size: 42,
                                focusNode: _likeFocusNode,
                                onArrowLeft: widget.watchFocusNode.requestFocus,
                                onArrowRight: _likeFocusNode.requestFocus,
                                onArrowUp: widget.watchFocusNode.requestFocus,
                                onArrowDown: widget.onFocusFirstRail,
                                onPressed: () => widget.onOpenLibraryMenu(item),
                              ),
                              const Spacer(),
                              if (widget.items.length > 1)
                                _TvHeroPager(
                                  count: widget.items.length.clamp(0, 8).toInt(),
                                  index: _index.clamp(0, 7).toInt(),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvHomeHeroPoster extends StatelessWidget {
  const _TvHomeHeroPoster({required this.item});

  final _TvItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0xA6000000),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          _PosterArtwork(item: item, width: 156, height: 242),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x24FFFFFF)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvHeroTitleWheel extends StatefulWidget {
  const _TvHeroTitleWheel({required this.item});

  final _TvItem item;

  @override
  State<_TvHeroTitleWheel> createState() => _TvHeroTitleWheelState();
}

class _TvHeroTitleWheelState extends State<_TvHeroTitleWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (_tvMotionEnabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _TvHeroTitleWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tvMotionEnabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_tvMotionEnabled && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = widget.item.logo?.trim();
    if (logo != null && logo.isNotEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 390,
          height: 104,
          child: _TvTitleLogoArtwork(
            logo: logo,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            fallback: _TvHeroFallbackTitle(
              controller: _controller,
              title: widget.item.title,
            ),
          ),
        ),
      );
    }
    return _TvHeroFallbackTitle(
      controller: _controller,
      title: widget.item.title,
    );
  }
}

class _TvTitleLogoArtwork extends StatelessWidget {
  const _TvTitleLogoArtwork({
    required this.logo,
    required this.fit,
    required this.alignment,
    required this.fallback,
  });

  final String logo;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final displayLogo = _tvSizedTmdbImage(logo, 'w500');
    if (_tvLooksLikeSvg(logo)) {
      return SvgPicture.network(
        displayLogo,
        fit: fit,
        alignment: alignment,
        placeholderBuilder: (_) => Align(
          alignment: alignment,
          child: const _TvShimmerBox(
            width: 260,
            height: 72,
            radius: 14,
            alpha: 0.42,
          ),
        ),
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return Image.network(
      displayLogo,
      fit: fit,
      alignment: alignment,
      cacheWidth: 520,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Align(
          alignment: alignment,
          child: const _TvShimmerBox(
            width: 260,
            height: 72,
            radius: 14,
            alpha: 0.42,
          ),
        );
      },
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

bool _tvLooksLikeSvg(String value) {
  final normalized = value.split('?').first.toLowerCase();
  return normalized.endsWith('.svg');
}

String _tvSizedTmdbImage(String value, String size) {
  const base = 'https://image.tmdb.org/t/p/';
  if (!value.startsWith(base)) return value;
  final rest = value.substring(base.length);
  final slash = rest.indexOf('/');
  if (slash <= 0) return value;
  return '$base$size${rest.substring(slash)}';
}

class _TvHeroScrollingDescription extends StatefulWidget {
  const _TvHeroScrollingDescription({required this.text});

  static const _visibleLines = 3;
  static const viewportHeight = 13 * 1.28 * _visibleLines;

  final String text;

  @override
  State<_TvHeroScrollingDescription> createState() =>
      _TvHeroScrollingDescriptionState();
}

class _TvHeroScrollingDescriptionState
    extends State<_TvHeroScrollingDescription>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _style = TextStyle(
    color: Color(0xD1FFFFFF),
    fontSize: 13,
    height: 1.28,
    fontWeight: FontWeight.w700,
  );
  static const _scrollDuration = Duration(milliseconds: 12000);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _scrollDuration);
    if (_tvMotionEnabled) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _TvHeroScrollingDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.value = 0;
    }
    if (_tvMotionEnabled && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!_tvMotionEnabled && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: _style),
          maxLines: null,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxWidth);
        if (!_tvMotionEnabled ||
            painter.height <= _TvHeroScrollingDescription.viewportHeight) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.text,
              maxLines: _TvHeroScrollingDescription._visibleLines,
              overflow: TextOverflow.ellipsis,
              style: _style,
            ),
          );
        }
        final distance =
            painter.height - _TvHeroScrollingDescription.viewportHeight + 6;
        return SizedBox(
          height: _TvHeroScrollingDescription.viewportHeight,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final eased = Curves.easeInOut.transform(_controller.value);
                return Transform.translate(
                  offset: Offset(0, -distance * eased),
                  child: child,
                );
              },
              child: SizedBox(
                width: maxWidth,
                child: Text(
                  widget.text,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: _style,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TvHeroFallbackTitle extends StatelessWidget {
  const _TvHeroFallbackTitle({required this.controller, required this.title});

  final Animation<double> controller;
  final String title;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = _tvMotionEnabled ? controller.value : 0.35;
        final pulse = _tvMotionEnabled
            ? 0.99 + (math.sin(progress * math.pi * 2) + 1) * 0.004
            : 1.0;
        final shimmerStart = -1.15 + progress * 2.3;
        return Align(
          alignment: Alignment.centerLeft,
          child: Transform.scale(
            alignment: Alignment.centerLeft,
            scale: pulse,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  return LinearGradient(
                    begin: Alignment(shimmerStart, -0.35),
                    end: Alignment(shimmerStart + 0.9, 0.35),
                    colors: const [
                      Color(0xB3FFFFFF),
                      Color(0xFFFFFFFF),
                      Color(0xFFBDF6D2),
                      Color(0xFFFFFFFF),
                      Color(0xB3FFFFFF),
                    ],
                    stops: const [0, 0.36, 0.5, 0.64, 1],
                  ).createShader(bounds);
                },
                child: Text(
                  title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    height: 0.88,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TvHeroPager extends StatelessWidget {
  const _TvHeroPager({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var dot = 0; dot < count; dot++) ...[
          AnimatedContainer(
            duration: _tvDuration(180),
            width: dot == index ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: dot == index
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          if (dot != count - 1) const SizedBox(width: _tvPosterGridGap),
        ],
      ],
    );
  }
}

class _TvNavigationRail extends StatefulWidget {
  const _TvNavigationRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.onMoveRight,
  });

  final List<_TvNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onMoveRight;

  @override
  State<_TvNavigationRail> createState() => _TvNavigationRailState();
}

class _TvNavigationRailState extends State<_TvNavigationRail> {
  late final List<FocusNode> _nodes = [
    for (var index = 0; index < widget.items.length; index++)
      FocusNode(
        debugLabel: 'tv-nav-${widget.items[index].label}',
        onKeyEvent: (_, event) => _handleNavKey(index, event),
      ),
  ];

  void focusSelected() {
    if (!mounted || _nodes.isEmpty) return;
    final index = widget.selectedIndex.clamp(0, _nodes.length - 1);
    _nodes[index].requestFocus();
  }

  bool get hasFocus => _nodes.any((node) => node.hasFocus);

  int? get focusedIndex {
    final index = _nodes.indexWhere((node) => node.hasFocus);
    return index == -1 ? null : index;
  }

  KeyEventResult _handleNavKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      final next = (index + 1).clamp(0, _nodes.length - 1);
      _nodes[next].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final previous = (index - 1).clamp(0, _nodes.length - 1);
      _nodes[previous].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onMoveRight(index);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _nodes[index].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      widget.onSelected(index);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didUpdateWidget(covariant _TvNavigationRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      throw StateError('TV navigation item count changed after init.');
    }
    if (oldWidget.selectedIndex != widget.selectedIndex &&
        _nodes.any((node) => node.hasFocus)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        focusSelected();
      });
    }
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: _tvNavigationRailWidth,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _tvTheme.railGradient,
            ),
            border: Border(right: BorderSide(color: _tvTheme.railBorder)),
          ),
          child: Column(
            children: [
              const Spacer(),
              for (var index = 0; index < widget.items.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: _tvNavItemGap),
                  child: _FocusableIconButton(
                    icon: widget.items[index].icon,
                    selected: widget.selectedIndex == index,
                    focusNode: _nodes[index],
                    autofocus: false,
                    onArrowUp: () {
                      final previous = (index - 1).clamp(0, _nodes.length - 1);
                      _nodes[previous].requestFocus();
                    },
                    onArrowDown: () {
                      final next = (index + 1).clamp(0, _nodes.length - 1);
                      _nodes[next].requestFocus();
                    },
                    onArrowRight: () => widget.onMoveRight(index),
                    onPressed: () => widget.onSelected(index),
                  ),
                ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvHeader extends StatelessWidget {
  const _TvHeader({
    required this.title,
    required this.onFocusNavigation,
    required this.trailing,
  });

  final String title;
  final VoidCallback onFocusNavigation;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: _tvTheme.text,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            height: 0.98,
          ),
        ),
        const Spacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Align(alignment: Alignment.centerRight, child: trailing),
        ),
      ],
    );
  }
}

String _tvDiscoveryGreetingTitle() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class _TvDiscoveryFilterButton extends StatelessWidget {
  const _TvDiscoveryFilterButton({
    required this.kind,
    required this.sort,
    required this.genre,
    required this.onPressed,
    this.onFocus,
    this.onArrowLeft,
    this.onArrowUp,
    this.onArrowDown,
    this.onArrowRight,
    this.focusNode,
  });

  final _TvDiscoveryKind kind;
  final _TvDiscoverySort sort;
  final String genre;
  final VoidCallback onPressed;
  final VoidCallback? onFocus;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowRight;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      onPressed: onPressed,
      onArrowLeft: onArrowLeft,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      onArrowRight: onArrowRight,
      onFocus: onFocus,
      focusNode: focusNode,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: 270,
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: _tvSpacing),
          decoration: BoxDecoration(
            color: _tvTheme.valuePill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused ? _tvFocusBorder : _tvTheme.valuePillBorder,
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                color: focused ? _tvAccentColor : _tvTheme.muted,
                size: 24,
              ),
              const SizedBox(width: _tvSpacing),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _tvTheme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      sort.subtitleFor(kind, genre),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _tvTheme.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _tvTheme.muted,
                size: 26,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvLibraryHeaderActions extends StatefulWidget {
  const _TvLibraryHeaderActions({
    required this.filter,
    required this.filterFocusNode,
    required this.onFilterPressed,
    required this.onOpenRanking,
    required this.onOpenMetrics,
    required this.onFocusFilter,
    required this.onFocusNavigation,
    required this.onFocusPageEntry,
    required this.onFocusPageContent,
    required this.onRememberPageFocus,
  });

  final _TvLibraryFilter filter;
  final FocusNode filterFocusNode;
  final VoidCallback onFilterPressed;
  final VoidCallback onOpenRanking;
  final VoidCallback onOpenMetrics;
  final VoidCallback onFocusFilter;
  final VoidCallback onFocusNavigation;
  final VoidCallback onFocusPageEntry;
  final VoidCallback onFocusPageContent;
  final ValueChanged<FocusNode> onRememberPageFocus;

  @override
  State<_TvLibraryHeaderActions> createState() =>
      _TvLibraryHeaderActionsState();
}

class _TvLibraryHeaderActionsState extends State<_TvLibraryHeaderActions> {
  final FocusNode _rankingFocusNode = FocusNode(
    debugLabel: 'tv-library-header-ranking',
  );
  final FocusNode _metricsFocusNode = FocusNode(
    debugLabel: 'tv-library-header-metrics',
  );

  _TvLibraryFilter get _contentFilter =>
      _tvLibraryContentFilters.contains(widget.filter)
      ? widget.filter
      : _TvLibraryFilter.continueWatching;

  @override
  void dispose() {
    _rankingFocusNode.dispose();
    _metricsFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TvCircleIconButton(
          icon: _TvLibraryFilter.ranking.icon,
          selected: widget.filter == _TvLibraryFilter.ranking,
          focusNode: _rankingFocusNode,
          onPressed: widget.onOpenRanking,
          onArrowLeft: widget.onFocusNavigation,
          onArrowRight: () => _metricsFocusNode.requestFocus(),
          onArrowUp: widget.onFocusPageEntry,
          onArrowDown: widget.onFocusPageContent,
        ),
        const SizedBox(width: _tvSpacing),
        _TvCircleIconButton(
          icon: _TvLibraryFilter.metrics.icon,
          selected: widget.filter == _TvLibraryFilter.metrics,
          focusNode: _metricsFocusNode,
          onPressed: widget.onOpenMetrics,
          onArrowLeft: () => _rankingFocusNode.requestFocus(),
          onArrowRight: () => widget.filterFocusNode.requestFocus(),
          onArrowUp: widget.onFocusPageEntry,
          onArrowDown: widget.onFocusPageContent,
        ),
        const SizedBox(width: _tvSpacing),
        _TvLibraryFilterButton(
          filter: _contentFilter,
          onPressed: widget.onFilterPressed,
          onFocus: widget.onFocusFilter,
          onArrowLeft: () => _metricsFocusNode.requestFocus(),
          onArrowUp: widget.onFocusPageEntry,
          onArrowDown: widget.onFocusPageContent,
          onArrowRight: widget.onFocusPageEntry,
          focusNode: widget.filterFocusNode,
        ),
      ],
    );
  }
}

class _TvLibraryFilterButton extends StatelessWidget {
  const _TvLibraryFilterButton({
    required this.filter,
    required this.onPressed,
    this.onFocus,
    this.onArrowLeft,
    this.onArrowUp,
    this.onArrowDown,
    this.onArrowRight,
    this.focusNode,
  });

  final _TvLibraryFilter filter;
  final VoidCallback onPressed;
  final VoidCallback? onFocus;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowRight;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      onPressed: onPressed,
      onArrowLeft: onArrowLeft,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      onArrowRight: onArrowRight,
      onFocus: onFocus,
      focusNode: focusNode,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: 250,
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: _tvSpacing),
          decoration: BoxDecoration(
            color: _tvTheme.valuePill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused ? _tvFocusBorder : _tvTheme.valuePillBorder,
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                filter.icon,
                color: focused ? _tvAccentColor : _tvTheme.muted,
                size: 24,
              ),
              const SizedBox(width: _tvSpacing),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filter.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _tvTheme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      filter.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _tvTheme.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _tvTheme.muted,
                size: 24,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvDiscoveryMenuDialog extends StatefulWidget {
  const _TvDiscoveryMenuDialog({
    required this.kind,
    required this.sort,
    required this.genre,
    required this.genres,
    required this.onChanged,
  });

  final _TvDiscoveryKind kind;
  final _TvDiscoverySort sort;
  final String genre;
  final List<String> genres;
  final ValueChanged<_TvDiscoverySelection> onChanged;

  @override
  State<_TvDiscoveryMenuDialog> createState() => _TvDiscoveryMenuDialogState();
}

class _TvDiscoveryMenuDialogState extends State<_TvDiscoveryMenuDialog> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _firstCatalogFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-first',
  );
  final FocusNode _seriesCatalogFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-series',
  );
  final FocusNode _animationCatalogFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-animation',
  );
  final FocusNode _liveCatalogFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-live',
  );
  final FocusNode _genreFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-genre',
  );
  final FocusNode _popularSortFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-sort-popular',
  );
  final FocusNode _nowPlayingSortFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-sort-now-playing',
  );
  final FocusNode _topRatedSortFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-sort-top-rated',
  );
  final FocusNode _upcomingSortFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-sort-upcoming',
  );
  final FocusNode _airingTodaySortFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-sort-airing-today',
  );
  final FocusNode _onTvSortFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-sort-on-tv',
  );
  final FocusNode _newSortFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-sort-newest',
  );
  final FocusNode _featuredSortFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-sort-featured',
  );

  late _TvDiscoveryKind _kind = widget.kind;
  late _TvDiscoverySort _sort = widget.sort;
  late String _genre = widget.genre;

  @override
  void initState() {
    super.initState();
    _ensureSortFitsKind();
    _requestInitialFocus();
  }

  List<_TvDiscoverySort> get _sortOptions => _tvDiscoverySortOptionsFor(_kind);

  void _ensureSortFitsKind() {
    final options = _sortOptions;
    if (!options.contains(_sort)) {
      _sort = options.first;
    }
  }

  void _setKind(_TvDiscoveryKind kind) {
    setState(() {
      _kind = kind;
      _genre = 'All genres';
      _ensureSortFitsKind();
    });
    widget.onChanged(_TvDiscoverySelection(_kind, _sort, _genre));
  }

  void _setSort(_TvDiscoverySort sort) {
    setState(() => _sort = sort);
    widget.onChanged(_TvDiscoverySelection(_kind, _sort, _genre));
  }

  void _setGenre(String genre) {
    setState(() => _genre = genre);
    widget.onChanged(_TvDiscoverySelection(_kind, _sort, _genre));
  }

  void _focusMenuNode(FocusNode node, {double alignment = 0.45}) {
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(140),
        curve: Curves.easeOutCubic,
        alignment: alignment,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  void _requestInitialFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusMenuNode(_firstCatalogFocusNode);
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (mounted && FocusManager.instance.primaryFocus == null) {
          _focusMenuNode(_firstCatalogFocusNode);
        }
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _firstCatalogFocusNode.dispose();
    _seriesCatalogFocusNode.dispose();
    _animationCatalogFocusNode.dispose();
    _liveCatalogFocusNode.dispose();
    _genreFocusNode.dispose();
    _popularSortFocusNode.dispose();
    _nowPlayingSortFocusNode.dispose();
    _topRatedSortFocusNode.dispose();
    _upcomingSortFocusNode.dispose();
    _airingTodaySortFocusNode.dispose();
    _onTvSortFocusNode.dispose();
    _newSortFocusNode.dispose();
    _featuredSortFocusNode.dispose();
    super.dispose();
  }

  FocusNode _kindNode(_TvDiscoveryKind kind) {
    return switch (kind) {
      _TvDiscoveryKind.movie => _firstCatalogFocusNode,
      _TvDiscoveryKind.series => _seriesCatalogFocusNode,
      _TvDiscoveryKind.animation => _animationCatalogFocusNode,
      _TvDiscoveryKind.liveTv => _liveCatalogFocusNode,
    };
  }

  FocusNode _sortNode(_TvDiscoverySort sort) {
    return switch (sort) {
      _TvDiscoverySort.popular => _popularSortFocusNode,
      _TvDiscoverySort.nowPlaying => _nowPlayingSortFocusNode,
      _TvDiscoverySort.topRated => _topRatedSortFocusNode,
      _TvDiscoverySort.upcoming => _upcomingSortFocusNode,
      _TvDiscoverySort.airingToday => _airingTodaySortFocusNode,
      _TvDiscoverySort.onTv => _onTvSortFocusNode,
      _TvDiscoverySort.newest => _newSortFocusNode,
      _TvDiscoverySort.featured => _featuredSortFocusNode,
    };
  }

  Future<void> _pickGenre() async {
    await _showTvDialog<void>(
      context: context,
      builder: (context) => _TvGenreMenuDialog(
        selected: _genre,
        genres: widget.genres,
        onChanged: _setGenre,
      ),
    );
    if (!mounted) return;
    _focusMenuNode(_genreFocusNode);
  }

  @override
  Widget build(BuildContext context) {
    final sortOptions = _sortOptions;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 160, vertical: 50),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
          child: Container(
            padding: const EdgeInsets.all(_tvSpacing),
            decoration: BoxDecoration(
              color: _tvTheme.dialog,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: _tvTheme.rowBorder),
            ),
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discovery menu',
                        style: TextStyle(
                          color: _tvTheme.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: _tvSpacing),
                      Text(
                        'Choose the catalog and ordering for this screen.',
                        style: TextStyle(
                          color: _tvTheme.muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: _tvSpacing),
                      _TvChoiceListSection(
                        title: 'Catalog',
                        children: [
                          for (
                            var index = 0;
                            index < _TvDiscoveryKind.values.length;
                            index++
                          )
                            _TvChoiceRow(
                              focusNode: _kindNode(
                                _TvDiscoveryKind.values[index],
                              ),
                              icon: _TvDiscoveryKind.values[index].icon,
                              label: _TvDiscoveryKind.values[index].label,
                              selected: _kind == _TvDiscoveryKind.values[index],
                              autofocus: index == 0,
                              onArrowUp: index == 0
                                  ? () => _focusMenuNode(_firstCatalogFocusNode)
                                  : () => _focusMenuNode(
                                      _kindNode(
                                        _TvDiscoveryKind.values[index - 1],
                                      ),
                                    ),
                              onArrowDown:
                                  index + 1 < _TvDiscoveryKind.values.length
                                  ? () => _focusMenuNode(
                                      _kindNode(
                                        _TvDiscoveryKind.values[index + 1],
                                      ),
                                    )
                                  : () => _focusMenuNode(_genreFocusNode),
                              onArrowLeft: () => _focusMenuNode(
                                _kindNode(_TvDiscoveryKind.values[index]),
                              ),
                              onArrowRight: () => _focusMenuNode(
                                _kindNode(_TvDiscoveryKind.values[index]),
                              ),
                              onPressed: () =>
                                  _setKind(_TvDiscoveryKind.values[index]),
                            ),
                        ],
                      ),
                      const SizedBox(height: _tvSpacing),
                      _TvChoiceListSection(
                        title: 'Genre',
                        children: [
                          _TvChoiceRow(
                            focusNode: _genreFocusNode,
                            icon: Icons.category_rounded,
                            label: _genre,
                            selected: true,
                            onArrowUp: () => _focusMenuNode(
                              _liveCatalogFocusNode,
                              alignment: 0.28,
                            ),
                            onArrowDown: () =>
                                _focusMenuNode(_sortNode(sortOptions.first)),
                            onArrowLeft: () => _focusMenuNode(_genreFocusNode),
                            onArrowRight: () => _focusMenuNode(_genreFocusNode),
                            onPressed: () => unawaited(_pickGenre()),
                          ),
                        ],
                      ),
                      const SizedBox(height: _tvSpacing),
                      _TvChoiceListSection(
                        title: 'Sort',
                        children: [
                          for (
                            var index = 0;
                            index < sortOptions.length;
                            index++
                          )
                            _TvChoiceRow(
                              focusNode: _sortNode(sortOptions[index]),
                              icon: Icons.sort_rounded,
                              label: sortOptions[index].labelFor(_kind),
                              selected: _sort == sortOptions[index],
                              onArrowUp: index == 0
                                  ? () => _focusMenuNode(
                                      _genreFocusNode,
                                      alignment: 0.22,
                                    )
                                  : () => _focusMenuNode(
                                      _sortNode(sortOptions[index - 1]),
                                    ),
                              onArrowDown: index + 1 < sortOptions.length
                                  ? () => _focusMenuNode(
                                      _sortNode(sortOptions[index + 1]),
                                    )
                                  : () => _focusMenuNode(
                                      _sortNode(sortOptions[index]),
                                    ),
                              onArrowLeft: () =>
                                  _focusMenuNode(_sortNode(sortOptions[index])),
                              onArrowRight: () =>
                                  _focusMenuNode(_sortNode(sortOptions[index])),
                              onPressed: () => _setSort(sortOptions[index]),
                            ),
                        ],
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

class _TvGenreMenuDialog extends StatefulWidget {
  const _TvGenreMenuDialog({
    required this.selected,
    required this.genres,
    required this.onChanged,
  });

  final String selected;
  final List<String> genres;
  final ValueChanged<String> onChanged;

  @override
  State<_TvGenreMenuDialog> createState() => _TvGenreMenuDialogState();
}

class _TvGenreMenuDialogState extends State<_TvGenreMenuDialog> {
  final Map<String, FocusNode> _genreFocusNodes = <String, FocusNode>{};
  final ScrollController _scrollController = ScrollController();
  late String _selected = widget.selected;

  @override
  void initState() {
    super.initState();
    _syncGenreFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusGenre(widget.selected);
    });
  }

  List<String> get _choices {
    final choices = <String>['All genres'];
    final seen = <String>{'all genres'};
    for (final rawGenre in widget.genres) {
      final genre = rawGenre.trim();
      if (genre.isEmpty) continue;
      final key = genre
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (key.isEmpty || !seen.add(key)) continue;
      choices.add(_titleCaseGenre(genre));
    }
    return choices;
  }

  String _titleCaseGenre(String genre) {
    return genre
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) {
          if (part.length == 1) return part.toUpperCase();
          return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  void _syncGenreFocusNodes() {
    final choices = _choices.toSet();
    for (final key in _genreFocusNodes.keys.toList()) {
      if (!choices.contains(key)) {
        _genreFocusNodes.remove(key)?.dispose();
      }
    }
    for (final genre in choices) {
      _genreFocusNodes.putIfAbsent(
        genre,
        () => FocusNode(debugLabel: 'tv-genre-menu-${_focusLabelFor(genre)}'),
      );
    }
  }

  FocusNode _genreNode(String genre) {
    return _genreFocusNodes.putIfAbsent(
      genre,
      () => FocusNode(debugLabel: 'tv-genre-menu-${_focusLabelFor(genre)}'),
    );
  }

  String _focusLabelFor(String value) {
    final safe = value
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return safe.isEmpty ? 'unknown' : safe;
  }

  void _focusGenre(String genre, {double alignment = 0.42}) {
    final node = _genreNode(genre);
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(140),
        curve: Curves.easeOutCubic,
        alignment: alignment,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final node in _genreFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncGenreFocusNodes();
    final choices = _choices;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 170, vertical: 50),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
          padding: const EdgeInsets.all(_tvSpacing),
          decoration: BoxDecoration(
            color: _tvTheme.dialog,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _tvTheme.rowBorder),
          ),
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Genres',
                      style: TextStyle(
                        color: _tvTheme.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: _tvSpacing),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (
                          var index = 0;
                          index < choices.length;
                          index++
                        ) ...[
                          _TvChoiceRow(
                            icon: choices[index] == _selected
                                ? Icons.check_circle_rounded
                                : Icons.category_rounded,
                            label: choices[index],
                            selected: choices[index] == _selected,
                            autofocus: choices[index] == _selected,
                            focusNode: _genreNode(choices[index]),
                            onArrowUp: index == 0
                                ? () => _focusGenre(choices[index])
                                : () => _focusGenre(choices[index - 1]),
                            onArrowDown: index + 1 < choices.length
                                ? () => _focusGenre(choices[index + 1])
                                : () => _focusGenre(choices[index]),
                            onArrowLeft: () => _focusGenre(choices[index]),
                            onArrowRight: () => _focusGenre(choices[index]),
                            onPressed: () {
                              setState(() => _selected = choices[index]);
                              widget.onChanged(choices[index]);
                            },
                          ),
                          if (index != choices.length - 1)
                            const SizedBox(height: _tvSpacing),
                        ],
                      ],
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

const List<_TvLibraryFilter> _tvLibraryContentFilters = [
  _TvLibraryFilter.continueWatching,
  _TvLibraryFilter.lists,
  _TvLibraryFilter.movies,
  _TvLibraryFilter.series,
  _TvLibraryFilter.animation,
  _TvLibraryFilter.liveTv,
];

class _TvLibraryMenuDialog extends StatefulWidget {
  const _TvLibraryMenuDialog({required this.filter, required this.onChanged});

  final _TvLibraryFilter filter;
  final ValueChanged<_TvLibraryFilter> onChanged;

  @override
  State<_TvLibraryMenuDialog> createState() => _TvLibraryMenuDialogState();
}

class _TvLibraryMenuDialogState extends State<_TvLibraryMenuDialog> {
  late final Map<_TvLibraryFilter, FocusNode> _filterNodes = {
    for (final filter in _tvLibraryContentFilters)
      filter: FocusNode(debugLabel: 'tv-library-menu-${filter.name}'),
  };
  final ScrollController _scrollController = ScrollController();

  late _TvLibraryFilter _filter =
      _tvLibraryContentFilters.contains(widget.filter)
      ? widget.filter
      : _TvLibraryFilter.continueWatching;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusFilter(_filter);
    });
  }

  @override
  void dispose() {
    for (final node in _filterNodes.values) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _focusFilter(_TvLibraryFilter filter) {
    final node = _filterNodes[filter];
    if (node == null) return;
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(140),
        curve: Curves.easeOutCubic,
        alignment: 0.45,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 170, vertical: 54),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 500),
          child: Container(
            padding: const EdgeInsets.all(_tvSpacing),
            decoration: BoxDecoration(
              color: const Color(0xFF202124),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x22FFFFFF)),
            ),
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Library menu',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: _tvSpacing),
                      _TvChoiceListSection(
                        title: '',
                        children: [
                          for (
                            var index = 0;
                            index < _tvLibraryContentFilters.length;
                            index++
                          )
                            _TvChoiceRow(
                              icon: _tvLibraryContentFilters[index].icon,
                              label: _tvLibraryContentFilters[index].label,
                              selected:
                                  _filter == _tvLibraryContentFilters[index],
                              autofocus: index == 0,
                              focusNode:
                                  _filterNodes[_tvLibraryContentFilters[index]],
                              onPressed: () {
                                final selection =
                                    _tvLibraryContentFilters[index];
                                setState(() => _filter = selection);
                                widget.onChanged(selection);
                              },
                              onArrowUp: index == 0
                                  ? () => _focusFilter(
                                      _tvLibraryContentFilters[index],
                                    )
                                  : () => _focusFilter(
                                      _tvLibraryContentFilters[index - 1],
                                    ),
                              onArrowDown:
                                  index == _tvLibraryContentFilters.length - 1
                                  ? () => _focusFilter(
                                      _tvLibraryContentFilters[index],
                                    )
                                  : () => _focusFilter(
                                      _tvLibraryContentFilters[index + 1],
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
        ),
      ),
    );
  }
}

class _TvChoiceListSection extends StatelessWidget {
  const _TvChoiceListSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: TextStyle(
              color: _tvAccentColor,
              fontSize: 13,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: _tvSpacing),
        ],
        Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1)
                const SizedBox(height: _tvSpacing),
            ],
          ],
        ),
      ],
    );
  }
}

class _TvChoiceRow extends StatelessWidget {
  const _TvChoiceRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      autoReveal: true,
      onPressed: onPressed,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(130),
          height: 50,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? _tvAccentColor : const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: focused
                  ? selected
                        ? _tvSolidFocusBorder
                        : _tvFocusBorder
                  : const Color(0x22FFFFFF),
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? Colors.black : _tvAccentColor,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, color: Colors.black, size: 22),
            ],
          ),
        );
      },
    );
  }
}

class _TvContentRail extends StatefulWidget {
  const _TvContentRail({
    required this.rail,
    required this.onOpenItem,
    required this.onFocusNavigation,
    required this.onRememberFocus,
    required this.onRememberItemFocus,
    required this.onRestoreItemFocus,
    this.onItemArrowUp,
    this.firstItemFocusNode,
    this.restoreItemKey,
    this.centerOnFocus = false,
    this.trapArrowDown = false,
    this.bottomPadding = 0,
    this.revealAlignment = 0.26,
  });

  final _TvRail rail;
  final VoidCallback? onItemArrowUp;
  final FocusNode? firstItemFocusNode;
  final bool centerOnFocus;
  final bool trapArrowDown;
  final double bottomPadding;
  final double revealAlignment;
  final ValueChanged<_TvItem> onOpenItem;
  final VoidCallback onFocusNavigation;
  final ValueChanged<FocusNode> onRememberFocus;
  final void Function(FocusNode node, _TvItem item) onRememberItemFocus;
  final ValueChanged<String> onRestoreItemFocus;
  final String? restoreItemKey;

  @override
  State<_TvContentRail> createState() => _TvContentRailState();
}

class _TvContentRailState extends State<_TvContentRail> {
  final _nodes = <FocusNode>[];
  final GlobalKey _railKey = GlobalKey(debugLabel: 'tv-content-rail');
  final GlobalKey _horizontalViewportKey = GlobalKey(
    debugLabel: 'tv-content-rail-horizontal',
  );
  final ScrollController _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _syncNodes();
    _scheduleRestoreItemFocus();
  }

  @override
  void didUpdateWidget(covariant _TvContentRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rail.items.length != widget.rail.items.length) {
      _syncNodes();
    }
    if (oldWidget.restoreItemKey != widget.restoreItemKey ||
        oldWidget.rail.items.length != widget.rail.items.length) {
      _scheduleRestoreItemFocus();
    }
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncNodes() {
    while (_nodes.length > widget.rail.items.length) {
      _nodes.removeLast().dispose();
    }
    while (_nodes.length < widget.rail.items.length) {
      final index = _nodes.length;
      _nodes.add(
        FocusNode(debugLabel: 'tv-rail-${_debugRailId()}-card-$index'),
      );
    }
  }

  String _debugRailId() {
    final normalized = widget.rail.title
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), '-')
        .replaceAll(RegExp(r"(^-+|-+$)"), '');
    return normalized.isEmpty ? 'unknown' : normalized;
  }

  String _itemKey(_TvItem item) => '${item.type}:${item.id}';

  void _rememberItemFocus(int index) {
    if (index < 0 || index >= widget.rail.items.length) return;
    final node = _nodeFor(index);
    widget.onRememberFocus(node);
    widget.onRememberItemFocus(node, widget.rail.items[index]);
  }

  void _scheduleRestoreItemFocus() {
    final itemKey = widget.restoreItemKey;
    if (itemKey == null || itemKey.trim().isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.restoreItemKey != itemKey) return;
      final index = widget.rail.items.indexWhere(
        (item) => _itemKey(item) == itemKey,
      );
      if (index < 0) {
        return;
      }
      final node = _nodeFor(index);
      widget.onRememberFocus(node);
      widget.onRememberItemFocus(node, widget.rail.items[index]);
      node.requestFocus();
      _revealFocusedCard(index);
      _revealRailContext();
      widget.onRestoreItemFocus(itemKey);
    });
  }

  FocusNode _nodeFor(int index) {
    if (index == 0 && widget.firstItemFocusNode != null) {
      return widget.firstItemFocusNode!;
    }
    return _nodes[index];
  }

  void _focusIndex(int index, {double horizontalAlignment = 0.48}) {
    if (index < 0 || index >= widget.rail.items.length) return;
    final node = _nodeFor(index);
    widget.onRememberFocus(node);
    widget.onRememberItemFocus(node, widget.rail.items[index]);
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _revealFocusedCard(index, horizontalAlignment: horizontalAlignment);
    });
  }

  void _revealFocusedCard(int index, {double horizontalAlignment = 0.48}) {
    final cardContext = _nodeFor(index).context;
    final viewportContext = _horizontalViewportKey.currentContext;
    if (cardContext == null ||
        viewportContext == null ||
        !_horizontalController.hasClients) {
      return;
    }
    final cardBox = cardContext.findRenderObject() as RenderBox?;
    final viewportBox = viewportContext.findRenderObject() as RenderBox?;
    if (cardBox == null ||
        viewportBox == null ||
        !cardBox.attached ||
        !viewportBox.attached) {
      return;
    }
    final cardOffset = cardBox.localToGlobal(
      Offset.zero,
      ancestor: viewportBox,
    );
    final cardLeft = cardOffset.dx;
    final cardRight = cardLeft + cardBox.size.width;
    final viewportWidth = viewportBox.size.width;
    const inset = 18.0;
    var target = _horizontalController.offset;
    if (cardLeft < inset) {
      target += cardLeft - inset;
    } else if (cardRight > viewportWidth - inset) {
      target += cardRight - viewportWidth + inset;
    } else {
      return;
    }
    final position = _horizontalController.position;
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    _horizontalController.animateTo(
      target,
      duration: _tvDuration(150),
      curve: Curves.easeOutCubic,
    );
  }

  void _revealRailContext() {
    if (!widget.centerOnFocus) return;
    final context = _railKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: _tvDuration(170),
      curve: Curves.easeOutCubic,
      alignment: widget.revealAlignment,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: _railKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.rail.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (widget.rail.subtitle.isNotEmpty) ...[
                    const SizedBox(height: _tvSpacing),
                    Text(
                      widget.rail.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFAAA6BD),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: _tvHomeRailGap),
        SizedBox(
          height: widget.rail.posterCards ? _tvHomeUpcomingRailHeight : 150,
          child: SingleChildScrollView(
            key: _horizontalViewportKey,
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(
              top: 4,
              right: _tvPosterGridGap,
              bottom: _tvPosterGridGap,
            ),
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (
                  var index = 0;
                  index < widget.rail.items.length;
                  index++
                ) ...[
                  widget.rail.posterCards
                      ? _PosterCard(
                          item: widget.rail.items[index],
                          rank: index + 1,
                          width: _tvHomeUpcomingPosterWidth,
                          posterHeight: _tvHomeUpcomingPosterHeight,
                          showRank: false,
                          badgeLabel: _tvUpcomingDateLabel(
                            widget.rail.items[index],
                          ),
                          focusNode: _nodeFor(index),
                          autoReveal: false,
                          onFocus: () {
                            _rememberItemFocus(index);
                            _revealFocusedCard(index);
                            _revealRailContext();
                          },
                          onPressed: () =>
                              widget.onOpenItem(widget.rail.items[index]),
                          onArrowLeft: index == 0
                              ? widget.onFocusNavigation
                              : () => _focusIndex(
                                  index - 1,
                                  horizontalAlignment: 0.16,
                                ),
                          onArrowRight: index + 1 < widget.rail.items.length
                              ? () => _focusIndex(
                                  index + 1,
                                  horizontalAlignment: 0.84,
                                )
                              : () =>
                                    _focusIndex(index, horizontalAlignment: 0.84),
                          onArrowUp: widget.onItemArrowUp,
                          onArrowDown: widget.trapArrowDown
                              ? () =>
                                    _focusIndex(index, horizontalAlignment: 0.48)
                              : null,
                        )
                      : _TvHomeLandscapeCard(
                          item: widget.rail.items[index],
                          rank: index + 1,
                          showRank: widget.rail.showRank,
                          focusNode: _nodeFor(index),
                          autoReveal: false,
                          onFocus: () {
                            _rememberItemFocus(index);
                            _revealFocusedCard(index);
                            _revealRailContext();
                          },
                          onPressed: () =>
                              widget.onOpenItem(widget.rail.items[index]),
                          onArrowLeft: index == 0
                              ? widget.onFocusNavigation
                              : () => _focusIndex(
                                  index - 1,
                                  horizontalAlignment: 0.16,
                                ),
                          onArrowRight: index + 1 < widget.rail.items.length
                              ? () => _focusIndex(
                                  index + 1,
                                  horizontalAlignment: 0.84,
                                )
                              : () =>
                                    _focusIndex(index, horizontalAlignment: 0.84),
                          onArrowUp: widget.onItemArrowUp,
                          onArrowDown: widget.trapArrowDown
                              ? () =>
                                    _focusIndex(index, horizontalAlignment: 0.48)
                              : null,
                        ),
                  if (index != widget.rail.items.length - 1)
                    const SizedBox(width: _tvPosterGridGap),
                ],
              ],
            ),
          ),
        ),
        if (widget.bottomPadding > 0) SizedBox(height: widget.bottomPadding),
      ],
    );
  }
}

String _tvUpcomingDateLabel(_TvItem item) {
  final raw = item.releaseDate?.trim();
  if (raw == null || raw.isEmpty) return 'TBA';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return 'TBA';
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
  return '${months[parsed.month - 1]} ${parsed.day}';
}

class _TvHomeLandscapeCard extends StatelessWidget {
  const _TvHomeLandscapeCard({
    required this.item,
    required this.rank,
    required this.onPressed,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
    this.onFocus,
    this.autoReveal = true,
    this.showRank = true,
    this.width = _width,
    this.height = _height,
  });

  static const double _width = 244;
  static const double _height = 138;
  static const double aspectRatio = _height / _width;

  final _TvItem item;
  final int rank;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onFocus;
  final bool autoReveal;
  final bool showRank;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autoReveal: autoReveal,
      onPressed: onPressed,
      focusNode: focusNode,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      onFocus: onFocus,
      builder: (focused) {
        final image = item.background ?? item.poster;
        final displayImage = image == null
            ? null
            : _tvSizedTmdbImage(image, 'w780');
        final rating = item.imdbRating?.trim();
        const focusInset = 5.0;
        final contentWidth = width - (focusInset * 2);
        final contentHeight = height - (focusInset * 2);
        return SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: const EdgeInsets.all(focusInset),
            child: AnimatedScale(
              scale: focused ? _tvPosterFocusedScale : 1,
              duration: _tvDuration(130),
              child: SizedBox(
                width: contentWidth,
                height: contentHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0xFF0A0B0E),
                          ),
                          child: displayImage == null
                              ? const _TvPosterArtworkFallback()
                              : Image.network(
                                  displayImage,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                  cacheWidth: 520,
                                  filterQuality: FilterQuality.medium,
                                  gaplessPlayback: true,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return const _TvPosterArtworkFallback();
                                      },
                                  errorBuilder: (_, __, ___) =>
                                      const _TvPosterArtworkFallback(),
                                ),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(18)),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Color(0xD607080D),
                              Color(0x6607080D),
                              Color(0x0007080D),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (rating != null && rating.isNotEmpty)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _ImdbPill(label: rating),
                      ),
                    Positioned(
                      left: showRank ? 12 : 76,
                      right: showRank ? 76 : 12,
                      bottom: 12,
                      child: _TvHomeLandscapeTitleWheel(
                        item: item,
                        focused: focused,
                        alignment: showRank
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        maxWidth: showRank
                            ? contentWidth - 112
                            : contentWidth - 24,
                        maxHeight: contentHeight * 0.34,
                      ),
                    ),
                    if (showRank)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: _TvLandscapeRankPill(label: 'Rank $rank'),
                      ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: focused
                                ? _tvFocusBorder
                                : const Color(0x22FFFFFF),
                            width: focused ? 2 : 1,
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
      },
    );
  }
}

class _TvLandscapeRankPill extends StatelessWidget {
  const _TvLandscapeRankPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: _tvCompactPillPadding),
      alignment: Alignment.center,
      decoration: _tvPillDecoration,
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
          height: 1,
        ),
      ),
    );
  }
}

class _TvHomeLandscapeTitleWheel extends StatelessWidget {
  const _TvHomeLandscapeTitleWheel({
    required this.item,
    required this.focused,
    required this.alignment,
    required this.maxWidth,
    required this.maxHeight,
  });

  final _TvItem item;
  final bool focused;
  final Alignment alignment;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final logo = item.logo?.trim();
    final fallback = _TvHomeLandscapeTitle(
      title: item.title,
      focused: focused,
      textAlign: alignment == Alignment.centerRight
          ? TextAlign.right
          : TextAlign.left,
    );
    if (logo != null && logo.isNotEmpty) {
      return Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: _TvTitleLogoArtwork(
            logo: logo,
            fit: BoxFit.contain,
            alignment: alignment,
            fallback: fallback,
          ),
        ),
      );
    }
    return fallback;
  }
}

class _TvHomeLandscapeTitle extends StatefulWidget {
  const _TvHomeLandscapeTitle({
    required this.title,
    required this.focused,
    required this.textAlign,
  });

  final String title;
  final bool focused;
  final TextAlign textAlign;

  @override
  State<_TvHomeLandscapeTitle> createState() => _TvHomeLandscapeTitleState();
}

class _TvHomeLandscapeTitleState extends State<_TvHomeLandscapeTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _style = TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontWeight: FontWeight.w900,
    height: 1,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
  }

  @override
  void didUpdateWidget(covariant _TvHomeLandscapeTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.focused && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.title, style: _style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final overflow = painter.width > constraints.maxWidth;
        if (!widget.focused || !overflow) {
          return Text(
            widget.title,
            maxLines: 1,
            textAlign: widget.textAlign,
            overflow: TextOverflow.ellipsis,
            style: _style,
          );
        }
        if (!_controller.isAnimating) {
          _controller.repeat(reverse: true);
        }
        final distance = painter.width - constraints.maxWidth + 18;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final eased = Curves.easeInOut.transform(_controller.value);
              return Transform.translate(
                offset: Offset(-distance * eased, 0),
                child: child,
              );
            },
            child: Text(
              widget.title,
              maxLines: 1,
              softWrap: false,
              textAlign: widget.textAlign,
              style: _style,
            ),
          ),
        );
      },
    );
  }
}

class _TvExpandedRail extends StatelessWidget {
  const _TvExpandedRail({
    required this.rail,
    required this.onBack,
    required this.onOpenItem,
    required this.onFocusNavigation,
    required this.backFocusNode,
    required this.gridFocusNode,
    required this.onRememberFocus,
    required this.onRememberItemFocus,
    required this.onRestoreItemFocus,
    this.restoreItemKey,
  });

  final _TvRail rail;
  final VoidCallback onBack;
  final ValueChanged<_TvItem> onOpenItem;
  final VoidCallback onFocusNavigation;
  final FocusNode backFocusNode;
  final FocusNode gridFocusNode;
  final ValueChanged<FocusNode> onRememberFocus;
  final void Function(FocusNode node, _TvItem item) onRememberItemFocus;
  final ValueChanged<String> onRestoreItemFocus;
  final String? restoreItemKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TvTextButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back to Home',
          focusNode: backFocusNode,
          onFocus: () => onRememberFocus(backFocusNode),
          onArrowLeft: onFocusNavigation,
          onArrowDown: () {
            onRememberFocus(gridFocusNode);
            gridFocusNode.requestFocus();
          },
          onPressed: onBack,
        ),
        const SizedBox(height: _tvSpacing),
        _TvPosterGrid(
          title: rail.title,
          subtitle: rail.subtitle,
          items: rail.items,
          showRank: rail.showRank,
          onOpenItem: onOpenItem,
          onFocusNavigation: onFocusNavigation,
          firstItemFocusNode: gridFocusNode,
          onRememberItemFocus: onRememberItemFocus,
          restoreItemKey: restoreItemKey,
          onRestoreItemFocus: onRestoreItemFocus,
          onTopRowArrowUp: () {
            onRememberFocus(backFocusNode);
            backFocusNode.requestFocus();
          },
          onRememberFocus: onRememberFocus,
        ),
      ],
    );
  }
}

class _TvPosterGrid extends StatefulWidget {
  const _TvPosterGrid({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.onOpenItem,
    this.onFocusNavigation,
    this.showRank = true,
    this.showHeader = true,
    this.firstItemFocusNode,
    this.onTopRowArrowUp,
    this.onBottomRowArrowDown,
    this.onRememberFocus,
    this.onRememberItemFocus,
    this.onRestoreItemFocus,
    this.restoreItemKey,
    this.onLoadMore,
    this.loadingMore = false,
    this.exhausted = false,
    this.landscapeCards = false,
    this.landscapeCardWidth,
  });

  final String title;
  final String subtitle;
  final List<_TvItem> items;
  final ValueChanged<_TvItem> onOpenItem;
  final VoidCallback? onFocusNavigation;
  final bool showRank;
  final bool showHeader;
  final FocusNode? firstItemFocusNode;
  final VoidCallback? onTopRowArrowUp;
  final VoidCallback? onBottomRowArrowDown;
  final ValueChanged<FocusNode>? onRememberFocus;
  final void Function(FocusNode node, _TvItem item)? onRememberItemFocus;
  final ValueChanged<String>? onRestoreItemFocus;
  final String? restoreItemKey;
  final VoidCallback? onLoadMore;
  final bool loadingMore;
  final bool exhausted;
  final bool landscapeCards;
  final double? landscapeCardWidth;

  @override
  State<_TvPosterGrid> createState() => _TvPosterGridState();
}

class _TvPosterGridState extends State<_TvPosterGrid> {
  static const int _columnCount = 6;
  static const double _posterAspect = 1.42;

  final _nodes = <FocusNode>[];
  late String _itemSignature;

  @override
  void initState() {
    super.initState();
    _itemSignature = _buildItemSignature(widget.items);
    _syncNodes();
    _scheduleRestoreItemFocus();
  }

  @override
  void didUpdateWidget(covariant _TvPosterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = _buildItemSignature(widget.items);
    if (oldWidget.items.length != widget.items.length ||
        nextSignature != _itemSignature) {
      final oldSignature = _itemSignature;
      final focusedInsideGrid = _nodes.any((node) => node.hasFocus);
      _itemSignature = nextSignature;
      final isAppend =
          widget.items.length > oldWidget.items.length &&
          _buildItemSignature(
                widget.items.take(oldWidget.items.length).toList(),
              ) ==
              oldSignature;
      if (isAppend) {
        _syncNodes();
      } else if (nextSignature != _buildItemSignature(oldWidget.items)) {
        _rebuildNodes();
        if (focusedInsideGrid && widget.items.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || widget.items.isEmpty) return;
            _focusIndex(0, alignment: 0.22);
          });
        }
      } else {
        _syncNodes();
      }
    }
    if (oldWidget.restoreItemKey != widget.restoreItemKey ||
        oldWidget.items.length != widget.items.length ||
        oldWidget.items != widget.items) {
      _scheduleRestoreItemFocus();
    }
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncNodes() {
    while (_nodes.length > widget.items.length) {
      _nodes.removeLast().dispose();
    }
    while (_nodes.length < widget.items.length) {
      final index = _nodes.length;
      _nodes.add(FocusNode(debugLabel: 'tv-grid-card-$index'));
    }
  }

  String _itemKey(_TvItem item) => '${item.type}:${item.id}';

  void _rememberItemFocus(int index) {
    if (index < 0 || index >= widget.items.length) return;
    final node = _nodeFor(index);
    widget.onRememberFocus?.call(node);
    widget.onRememberItemFocus?.call(node, widget.items[index]);
  }

  void _scheduleRestoreItemFocus() {
    final itemKey = widget.restoreItemKey;
    if (itemKey == null || itemKey.trim().isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.restoreItemKey != itemKey) return;
      final index = widget.items.indexWhere((item) => _itemKey(item) == itemKey);
      if (index < 0 ||
          (index == 0
              ? widget.firstItemFocusNode == null && _nodes.isEmpty
              : index >= _nodes.length)) {
        return;
      }
      final node = _nodeFor(index);
      widget.onRememberFocus?.call(node);
      widget.onRememberItemFocus?.call(node, widget.items[index]);
      node.requestFocus();
      _revealIndex(index);
      widget.onRestoreItemFocus?.call(itemKey);
    });
  }

  void _rebuildNodes() {
    for (final node in _nodes) {
      node.dispose();
    }
    _nodes.clear();
    _syncNodes();
  }

  void _focusIndex(int index, {double alignment = 0.38}) {
    if (index < 0 || index >= widget.items.length || index >= _nodes.length) {
      return;
    }
    final node = _nodeFor(index);
    widget.onRememberFocus?.call(node);
    widget.onRememberItemFocus?.call(node, widget.items[index]);
    node.requestFocus();
    _revealIndex(index, alignment: alignment);
  }

  void _prefetchNearEnd(int index, int columnCount) {
    if (widget.onLoadMore == null || widget.items.isEmpty) return;
    if (index >= widget.items.length - columnCount) {
      widget.onLoadMore!.call();
    }
  }

  void _revealIndex(int index, {double alignment = 0.38}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < 0 || index >= widget.items.length || index >= _nodes.length) {
        return;
      }
      final node = _nodeFor(index);
      if (!node.canRequestFocus) return;
      final context = node.context;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(180),
        curve: Curves.easeOutCubic,
        alignment: alignment,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  FocusNode _nodeFor(int index) {
    if (index == 0 && widget.firstItemFocusNode != null) {
      return widget.firstItemFocusNode!;
    }
    return _nodes[index];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (widget.subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: _tvSpacing / 2),
            Text(
              widget.subtitle,
              style: const TextStyle(
                color: Color(0xFFAAA6BD),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: _tvSpacing),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final landscapeColumnCount =
                ((constraints.maxWidth + _tvPosterGridGap) /
                        ((widget.landscapeCardWidth ??
                                _TvHomeLandscapeCard._width) +
                            _tvPosterGridGap))
                    .floor()
                    .clamp(1, 8)
                    .toInt();
            final columnCount = widget.landscapeCards
                ? landscapeColumnCount
                : _columnCount;
            final cardWidth = widget.landscapeCards
                ? widget.landscapeCardWidth ?? _TvHomeLandscapeCard._width
                : (constraints.maxWidth -
                          (_tvPosterGridGap * (columnCount - 1))) /
                      columnCount;
            final cardHeight = widget.landscapeCards
                ? cardWidth * _TvHomeLandscapeCard.aspectRatio
                : cardWidth * _posterAspect;
            return Wrap(
              spacing: _tvPosterGridGap,
              runSpacing: _tvPosterGridGap,
              children: [
                for (var index = 0; index < widget.items.length; index++)
                  widget.landscapeCards
                      ? _TvHomeLandscapeCard(
                          item: widget.items[index],
                          rank: index + 1,
                          showRank: widget.showRank,
                          width: cardWidth,
                          height: cardHeight,
                          focusNode: _nodeFor(index),
                          autoReveal: false,
                          onFocus: () {
                            _rememberItemFocus(index);
                            _prefetchNearEnd(index, columnCount);
                            _revealIndex(index);
                          },
                          onPressed: () =>
                              widget.onOpenItem(widget.items[index]),
                          onArrowLeft: index % columnCount == 0
                              ? widget.onFocusNavigation
                              : () => _focusIndex(index - 1),
                          onArrowRight: index + 1 < widget.items.length
                              ? () => _focusIndex(index + 1)
                              : () {
                                  widget.onLoadMore?.call();
                                  _focusIndex(index);
                                },
                          onArrowUp: index - columnCount >= 0
                              ? () => _focusIndex(
                                  index - columnCount,
                                  alignment: 0.2,
                                )
                              : widget.onTopRowArrowUp,
                          onArrowDown: index + columnCount < widget.items.length
                              ? () => _focusIndex(
                                  index + columnCount,
                                  alignment: 0.58,
                                )
                              : widget.onBottomRowArrowDown ??
                                    () {
                                      widget.onLoadMore?.call();
                                      _focusIndex(index, alignment: 0.58);
                                    },
                        )
                      : _PosterCard(
                          item: widget.items[index],
                          rank: index + 1,
                          width: cardWidth,
                          posterHeight: cardHeight,
                          showRank: widget.showRank,
                          focusNode: _nodeFor(index),
                          autoReveal: false,
                          onFocus: () {
                            _rememberItemFocus(index);
                            _prefetchNearEnd(index, columnCount);
                            _revealIndex(index);
                          },
                          onPressed: () =>
                              widget.onOpenItem(widget.items[index]),
                          onArrowLeft: index % columnCount == 0
                              ? widget.onFocusNavigation
                              : () => _focusIndex(index - 1),
                          onArrowRight: index + 1 < widget.items.length
                              ? () => _focusIndex(index + 1)
                              : () {
                                  widget.onLoadMore?.call();
                                  _focusIndex(index);
                                },
                          onArrowUp: index - columnCount >= 0
                              ? () => _focusIndex(
                                  index - columnCount,
                                  alignment: 0.2,
                                )
                              : widget.onTopRowArrowUp,
                          onArrowDown: index + columnCount < widget.items.length
                              ? () => _focusIndex(
                                  index + columnCount,
                                  alignment: 0.58,
                                )
                              : widget.onBottomRowArrowDown ??
                                    () {
                                      widget.onLoadMore?.call();
                                      _focusIndex(index, alignment: 0.58);
                                    },
                        ),
                if (widget.loadingMore)
                  for (var index = 0; index < columnCount; index++)
                    _TvCatalogLoadingCard(
                      width: cardWidth,
                      height: cardHeight,
                      landscape: widget.landscapeCards,
                    ),
                if (widget.exhausted)
                  SizedBox(
                    width: constraints.maxWidth,
                    child: _TvCatalogEndState(exhausted: widget.exhausted),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _buildItemSignature(List<_TvItem> items) {
    return items
        .map((item) => '${item.type}:${item.id}:${item.title}')
        .join('|');
  }
}

class _TvCatalogEndState extends StatelessWidget {
  const _TvCatalogEndState({required this.exhausted});

  final bool exhausted;

  @override
  Widget build(BuildContext context) {
    final label = exhausted ? "You're all caught up" : 'Loading more';
    final icon = exhausted
        ? Icons.check_circle_outline_rounded
        : Icons.hourglass_top_rounded;
    return Container(
      height: 72,
      alignment: Alignment.center,
      margin: const EdgeInsets.only(top: _tvSpacing),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFAAA6BD), size: 22),
          const SizedBox(width: _tvSpacing),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFAAA6BD),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvCatalogLoadingCard extends StatelessWidget {
  const _TvCatalogLoadingCard({
    required this.width,
    required this.height,
    required this.landscape,
  });

  final double width;
  final double height;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final inset = landscape ? 5.0 : _tvPosterFocusGutter;
    final outerHeight = landscape ? height : height + 18;
    return SizedBox(
      width: width,
      height: outerHeight,
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: _TvShimmerBox(
          width: width - (inset * 2),
          height: height - (inset * 2),
          radius: 18,
          alpha: 0.54,
        ),
      ),
    );
  }
}
