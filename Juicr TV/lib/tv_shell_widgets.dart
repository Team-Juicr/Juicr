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
    required this.onAccountSignIn,
    required this.onAccountSignOut,
    required this.onAccountSync,
    required this.onDiscoveryMenu,
    required this.onDiscoveryLoadMore,
    required this.onLibraryMenu,
    required this.onOpenLibraryRanking,
    required this.onOpenLibraryMetrics,
    required this.onOpenItem,
    required this.onPlayItem,
    required this.onTrailerItem,
    required this.onToggleLike,
    required this.isItemLiked,
    required this.onOpenRail,
    required this.onBackToHome,
    required this.onFocusNavigation,
    required this.pageEntryFocusNode,
    required this.pageContentFocusNode,
    required this.onFocusPageEntry,
    required this.onFocusPageContent,
    required this.onRememberPageFocus,
    required this.onRetry,
  });

  final String title;
  final int selectedTab;
  final bool loading;
  final String? error;
  final _TvRail? expandedRail;
  final List<_TvRail> rails;
  final List<_TvItem> homeHeroItems;
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
  final VoidCallback onAccountSignIn;
  final VoidCallback onAccountSignOut;
  final VoidCallback onAccountSync;
  final VoidCallback onDiscoveryMenu;
  final VoidCallback onDiscoveryLoadMore;
  final VoidCallback onLibraryMenu;
  final VoidCallback onOpenLibraryRanking;
  final VoidCallback onOpenLibraryMetrics;
  final ValueChanged<_TvItem> onOpenItem;
  final ValueChanged<_TvItem> onPlayItem;
  final ValueChanged<_TvItem> onTrailerItem;
  final ValueChanged<_TvItem> onToggleLike;
  final bool Function(_TvItem item) isItemLiked;
  final ValueChanged<_TvRail> onOpenRail;
  final VoidCallback onBackToHome;
  final VoidCallback onFocusNavigation;
  final FocusNode pageEntryFocusNode;
  final FocusNode pageContentFocusNode;
  final VoidCallback onFocusPageEntry;
  final VoidCallback onFocusPageContent;
  final ValueChanged<FocusNode> onRememberPageFocus;
  final VoidCallback onRetry;

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
            slivers: [
              SliverPadding(
                padding: selectedTab == 0
                    ? const EdgeInsets.fromLTRB(0, 0, 0, 36)
                    : const EdgeInsets.fromLTRB(30, 0, 48, 90),
                sliver: _body(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body() {
    if (loading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _TvLoadingState(),
      );
    }
    if (error != null) {
      return SliverToBoxAdapter(
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
        ),
      );
    }
    if (selectedTab == 1) {
      if (!tvSettings.hasCatalogSource) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _TvEmptyCatalogState(
            title: 'Choose a source to fill Discovery.',
            subtitle: 'Enable built-in browsing in Settings to start.',
            verticalOffset: -42,
            focusNode: pageContentFocusNode,
            onFocusNavigation: onFocusNavigation,
            onFocusHeader: onFocusPageEntry,
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
          onOpenItem: onOpenItem,
          onFocusNavigation: onFocusNavigation,
          entryFocusNode: pageContentFocusNode,
          onFocusHeader: onFocusPageEntry,
          onRememberFocus: onRememberPageFocus,
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
          recentCount: recentCount,
          savedCount: savedCount,
          completedCount: completedCount,
          onOpenItem: onOpenItem,
          onFocusNavigation: onFocusNavigation,
          entryFocusNode: pageContentFocusNode,
          onFocusHeader: onFocusPageEntry,
          onRememberFocus: onRememberPageFocus,
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
    if (!tvSettings.hasCatalogSource) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _TvEmptyCatalogState(
          title: 'Juicr TV is ready for your sources.',
          subtitle: 'Open Settings and enable built-in browsing to start.',
          verticalOffset: -42,
          focusNode: pageContentFocusNode,
          onFocusNavigation: onFocusNavigation,
          onFocusHeader: onFocusPageEntry,
        ),
      );
    }
    final heroItems = homeHeroItems;
    final heroItem = heroItems.isEmpty ? null : heroItems.first;
    final heroOffset = heroItems.isEmpty ? 0 : 1;
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (heroItem != null && index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TvHomeHero(
                key: homeHeroKey,
                items: heroItems,
                editorial: homeHeroEditorial,
                onOpenItem: onOpenItem,
                onPlayItem: onPlayItem,
                onTrailerItem: onTrailerItem,
                onToggleLike: onToggleLike,
                isItemLiked: isItemLiked,
                onFocusNavigation: onFocusNavigation,
                onFocusFirstRail: () {
                  pageEntryFocusNode.requestFocus();
                  final firstRailContext = pageEntryFocusNode.context;
                  if (firstRailContext == null) return;
                  Scrollable.ensureVisible(
                    firstRailContext,
                    duration: _tvDuration(180),
                    curve: Curves.easeOutCubic,
                    alignment: 0.36,
                    alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                  );
                },
                watchFocusNode: homeHeroWatchFocusNode,
                onRememberFocus: onRememberPageFocus,
              ),
              const _TvHeroRailFade(),
            ],
          );
        }
        final railIndex = index - heroOffset;
        return Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 48, _tvSpacing),
          child: _TvContentRail(
            rail: rails[railIndex],
            onSeeAll: () => onOpenRail(rails[railIndex]),
            onOpenItem: onOpenItem,
            onFocusNavigation: onFocusNavigation,
            firstItemFocusNode: railIndex == 0 ? pageEntryFocusNode : null,
            onRememberFocus: onRememberPageFocus,
            centerOnFocus: selectedTab == 0,
            onItemArrowUp: railIndex == 0 && heroItem != null
                ? () {
                    homeHeroWatchFocusNode.requestFocus();
                    final heroContext = homeHeroKey.currentContext;
                    if (heroContext == null) return;
                    Scrollable.ensureVisible(
                      heroContext,
                      duration: _tvDuration(180),
                      curve: Curves.easeOutCubic,
                      alignment: 0,
                      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                    );
                  }
                : null,
          ),
        );
      }, childCount: rails.length + heroOffset),
    );
  }
}

class _TvHeroRailFade extends StatelessWidget {
  const _TvHeroRailFade();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF07080D), Color(0xF20A0A12), Color(0xFF0D0B1B)],
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
    required this.editorial,
    required this.onOpenItem,
    required this.onPlayItem,
    required this.onTrailerItem,
    required this.onToggleLike,
    required this.isItemLiked,
    required this.onFocusNavigation,
    required this.onFocusFirstRail,
    required this.watchFocusNode,
    required this.onRememberFocus,
  });

  final List<_TvItem> items;
  final _TvHomeEditorialRail editorial;
  final ValueChanged<_TvItem> onOpenItem;
  final ValueChanged<_TvItem> onPlayItem;
  final ValueChanged<_TvItem> onTrailerItem;
  final ValueChanged<_TvItem> onToggleLike;
  final bool Function(_TvItem item) isItemLiked;
  final VoidCallback onFocusNavigation;
  final VoidCallback onFocusFirstRail;
  final FocusNode watchFocusNode;
  final ValueChanged<FocusNode> onRememberFocus;

  @override
  State<_TvHomeHero> createState() => _TvHomeHeroState();
}

class _TvHomeHeroState extends State<_TvHomeHero> {
  Timer? _carouselTimer;
  final FocusNode _trailerFocusNode = FocusNode(
    debugLabel: 'tv-home-hero-trailer',
  );
  final FocusNode _detailsFocusNode = FocusNode(
    debugLabel: 'tv-home-hero-details',
  );
  final FocusNode _likeFocusNode = FocusNode(debugLabel: 'tv-home-hero-like');
  int _index = 0;

  _TvItem get _item =>
      widget.items[_index.clamp(0, widget.items.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    _syncCarouselTimer();
  }

  @override
  void didUpdateWidget(covariant _TvHomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.map((item) => '${item.type}:${item.id}').join('|') !=
        widget.items.map((item) => '${item.type}:${item.id}').join('|')) {
      _index = 0;
      _syncCarouselTimer();
    }
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _trailerFocusNode.dispose();
    _detailsFocusNode.dispose();
    _likeFocusNode.dispose();
    super.dispose();
  }

  void _syncCarouselTimer() {
    _carouselTimer?.cancel();
    if (widget.items.length < 2) return;
    _carouselTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || widget.items.length < 2) return;
      setState(() => _index = (_index + 1) % widget.items.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final item = _item;
    final image = item.background ?? item.poster;
    final liked = widget.isItemLiked(item);
    final curationTitle = widget.editorial.title.trim();
    final hasCurationTitle = curationTitle.isNotEmpty;
    return SizedBox(
      width: double.infinity,
      height: 390,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: _tvDuration(620),
            reverseDuration: _tvDuration(420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  for (final child in previousChildren)
                    Positioned.fill(child: child),
                  if (currentChild != null)
                    Positioned.fill(child: currentChild),
                ],
              );
            },
            child: KeyedSubtree(
              key: ValueKey('hero-artwork-${item.type}:${item.id}'),
              child: SizedBox.expand(
                child: image == null
                    ? ColoredBox(color: item.color.withValues(alpha: 0.35))
                    : Image.network(
                        image,
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: item.color.withValues(alpha: 0.35),
                        ),
                      ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xD907080D),
                  Color(0xA607080D),
                  Color(0x5207080D),
                  Color(0x1007080D),
                ],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xFF07080D),
                  Color(0xD607080D),
                  Color(0x6607080D),
                  Color(0x1807080D),
                  Color(0x0007080D),
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
                colors: [Color(0x0007080D), Color(0x7307080D)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(38, 48, 88, 42),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 470),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
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
                          child: SlideTransition(
                            position: offset,
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        key: ValueKey('hero-copy-${item.type}:${item.id}'),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: TextStyle(
                                color: _tvAccentColor,
                                fontSize: 10,
                                letterSpacing: 3,
                                fontWeight: FontWeight.w900,
                              ),
                              children: hasCurationTitle
                                  ? [
                                      const TextSpan(
                                        text: "TODAY'S CURATION: ",
                                      ),
                                      TextSpan(
                                        text: curationTitle,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ]
                                  : [TextSpan(text: item.type.toUpperCase())],
                            ),
                          ),
                          const SizedBox(height: _tvSpacing),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              height: 0.96,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: _tvSpacing),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _TvTextButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Watch now',
                          autofocus: true,
                          focusNode: widget.watchFocusNode,
                          onFocus: () =>
                              widget.onRememberFocus(widget.watchFocusNode),
                          onArrowLeft: widget.onFocusNavigation,
                          onArrowRight: _trailerFocusNode.requestFocus,
                          onArrowUp: widget.watchFocusNode.requestFocus,
                          onArrowDown: widget.onFocusFirstRail,
                          onPressed: () => widget.onPlayItem(item),
                        ),
                        _TvTextButton(
                          icon: Icons.movie_filter_rounded,
                          label: 'Trailer',
                          focusNode: _trailerFocusNode,
                          onFocus: () =>
                              widget.onRememberFocus(_trailerFocusNode),
                          onArrowLeft: widget.watchFocusNode.requestFocus,
                          onArrowRight: _detailsFocusNode.requestFocus,
                          onArrowUp: widget.watchFocusNode.requestFocus,
                          onArrowDown: widget.onFocusFirstRail,
                          onPressed: () => widget.onTrailerItem(item),
                        ),
                        _TvTextButton(
                          icon: Icons.info_outline_rounded,
                          label: 'Details',
                          focusNode: _detailsFocusNode,
                          onFocus: () =>
                              widget.onRememberFocus(_detailsFocusNode),
                          onArrowLeft: _trailerFocusNode.requestFocus,
                          onArrowRight: _likeFocusNode.requestFocus,
                          onArrowUp: widget.watchFocusNode.requestFocus,
                          onArrowDown: widget.onFocusFirstRail,
                          onPressed: () => widget.onOpenItem(item),
                        ),
                        _TvCircleIconButton(
                          icon: liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          selected: liked,
                          size: 48,
                          focusNode: _likeFocusNode,
                          onArrowLeft: _detailsFocusNode.requestFocus,
                          onArrowRight: _likeFocusNode.requestFocus,
                          onArrowUp: widget.watchFocusNode.requestFocus,
                          onArrowDown: widget.onFocusFirstRail,
                          onPressed: () => widget.onToggleLike(item),
                        ),
                      ],
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
    return Container(
      width: 94,
      decoration: const BoxDecoration(
        color: Color(0xCC0B0C14),
        border: Border(right: BorderSide(color: Color(0x1FFFFFFF))),
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
          style: const TextStyle(
            color: Colors.white,
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
          width: 240,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: _tvSpacing),
          decoration: BoxDecoration(
            color: const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused ? _tvFocusBorder : const Color(0x1FFFFFFF),
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                color: focused ? _tvAccentColor : const Color(0xFFBDB9D5),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      sort.subtitleFor(kind, genre),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFBDB9D5),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFFBDB9D5),
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
          width: 220,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: _tvSpacing),
          decoration: BoxDecoration(
            color: const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused ? _tvFocusBorder : const Color(0x1FFFFFFF),
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                filter.icon,
                color: focused ? _tvAccentColor : const Color(0xFFBDB9D5),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      filter.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFBDB9D5),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFFBDB9D5),
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
  });

  final _TvDiscoveryKind kind;
  final _TvDiscoverySort sort;
  final String genre;
  final List<String> genres;

  @override
  State<_TvDiscoveryMenuDialog> createState() => _TvDiscoveryMenuDialogState();
}

class _TvDiscoveryMenuDialogState extends State<_TvDiscoveryMenuDialog> {
  final FocusNode _closeFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-close',
  );
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
  final FocusNode _applyFocusNode = FocusNode(
    debugLabel: 'tv-discovery-menu-apply',
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
      _ensureSortFitsKind();
    });
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
    _closeFocusNode.dispose();
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
    _applyFocusNode.dispose();
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
    final selected = await showDialog<String>(
      context: context,
      builder: (context) =>
          _TvGenreMenuDialog(selected: _genre, genres: widget.genres),
    );
    if (!mounted) return;
    if (selected != null) {
      setState(() => _genre = selected);
    }
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
              color: const Color(0xFF15141D),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x22FFFFFF)),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  child: _TvCircleIconButton(
                    focusNode: _closeFocusNode,
                    icon: Icons.close_rounded,
                    onArrowUp: () => _closeFocusNode.requestFocus(),
                    onArrowRight: () => _closeFocusNode.requestFocus(),
                    onArrowLeft: () => _focusMenuNode(_firstCatalogFocusNode),
                    onArrowDown: () => _focusMenuNode(_firstCatalogFocusNode),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: _tvSpacing),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Discovery menu',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: _tvSpacing),
                        const Text(
                          'Choose the catalog and ordering for this screen.',
                          style: TextStyle(
                            color: Color(0xFFBDB9D5),
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
                                selected:
                                    _kind == _TvDiscoveryKind.values[index],
                                autofocus: index == 0,
                                onArrowUp: index == 0
                                    ? () => _closeFocusNode.requestFocus()
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
                              onArrowLeft: () =>
                                  _focusMenuNode(_genreFocusNode),
                              onArrowRight: () =>
                                  _focusMenuNode(_genreFocusNode),
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
                                    : () => _focusMenuNode(_applyFocusNode),
                                onArrowLeft: () => _focusMenuNode(
                                  _sortNode(sortOptions[index]),
                                ),
                                onArrowRight: () => _focusMenuNode(
                                  _sortNode(sortOptions[index]),
                                ),
                                onPressed: () =>
                                    setState(() => _sort = sortOptions[index]),
                              ),
                          ],
                        ),
                        const SizedBox(height: _tvSpacing),
                        _TvTextButton(
                          focusNode: _applyFocusNode,
                          autoReveal: true,
                          icon: Icons.check_rounded,
                          label: 'Apply',
                          onArrowUp: () =>
                              _focusMenuNode(_sortNode(sortOptions.last)),
                          onArrowDown: () => _focusMenuNode(_applyFocusNode),
                          onArrowLeft: () => _focusMenuNode(_applyFocusNode),
                          onArrowRight: () => _focusMenuNode(_applyFocusNode),
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(_TvDiscoverySelection(_kind, _sort, _genre)),
                        ),
                      ],
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

class _TvGenreMenuDialog extends StatefulWidget {
  const _TvGenreMenuDialog({required this.selected, required this.genres});

  final String selected;
  final List<String> genres;

  @override
  State<_TvGenreMenuDialog> createState() => _TvGenreMenuDialogState();
}

class _TvGenreMenuDialogState extends State<_TvGenreMenuDialog> {
  final FocusNode _closeFocusNode = FocusNode(
    debugLabel: 'tv-genre-menu-close',
  );
  final Map<String, FocusNode> _genreFocusNodes = <String, FocusNode>{};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _syncGenreFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusGenre(widget.selected);
    });
  }

  List<String> get _choices => <String>[
    'All genres',
    ...widget.genres.where((genre) => genre != 'All genres'),
  ];

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
    _closeFocusNode.dispose();
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
            color: const Color(0xFF15141D),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0x22FFFFFF)),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: _TvCircleIconButton(
                  focusNode: _closeFocusNode,
                  icon: Icons.close_rounded,
                  onArrowUp: () => _closeFocusNode.requestFocus(),
                  onArrowRight: () => _closeFocusNode.requestFocus(),
                  onArrowLeft: () => _focusGenre(_choices.first),
                  onArrowDown: () => _focusGenre(_choices.first),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: _tvSpacing),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Genres',
                        style: TextStyle(
                          color: Colors.white,
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
                              icon: choices[index] == widget.selected
                                  ? Icons.check_circle_rounded
                                  : Icons.category_rounded,
                              label: choices[index],
                              selected: choices[index] == widget.selected,
                              autofocus: choices[index] == widget.selected,
                              focusNode: _genreNode(choices[index]),
                              onArrowUp: index == 0
                                  ? () => _closeFocusNode.requestFocus()
                                  : () => _focusGenre(choices[index - 1]),
                              onArrowDown: index + 1 < choices.length
                                  ? () => _focusGenre(choices[index + 1])
                                  : () => _focusGenre(choices[index]),
                              onArrowLeft: () => _focusGenre(choices[index]),
                              onArrowRight: () => _focusGenre(choices[index]),
                              onPressed: () =>
                                  Navigator.of(context).pop(choices[index]),
                            ),
                            if (index != choices.length - 1)
                              const SizedBox(height: _tvSpacing),
                          ],
                        ],
                      ),
                    ],
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

const List<_TvLibraryFilter> _tvLibraryContentFilters = [
  _TvLibraryFilter.continueWatching,
  _TvLibraryFilter.lists,
  _TvLibraryFilter.movies,
  _TvLibraryFilter.series,
  _TvLibraryFilter.animation,
  _TvLibraryFilter.liveTv,
];

class _TvLibraryMenuDialog extends StatefulWidget {
  const _TvLibraryMenuDialog({required this.filter});

  final _TvLibraryFilter filter;

  @override
  State<_TvLibraryMenuDialog> createState() => _TvLibraryMenuDialogState();
}

class _TvLibraryMenuDialogState extends State<_TvLibraryMenuDialog> {
  final FocusNode _closeFocusNode = FocusNode(
    debugLabel: 'tv-library-menu-close',
  );
  late final Map<_TvLibraryFilter, FocusNode> _filterNodes = {
    for (final filter in _tvLibraryContentFilters)
      filter: FocusNode(debugLabel: 'tv-library-menu-${filter.name}'),
  };
  final FocusNode _applyFocusNode = FocusNode(debugLabel: 'tv-library-apply');
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
    _closeFocusNode.dispose();
    for (final node in _filterNodes.values) {
      node.dispose();
    }
    _applyFocusNode.dispose();
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
              color: const Color(0xFF15141D),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x22FFFFFF)),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  child: _TvCircleIconButton(
                    focusNode: _closeFocusNode,
                    icon: Icons.close_rounded,
                    onArrowUp: () => _closeFocusNode.requestFocus(),
                    onArrowRight: () => _closeFocusNode.requestFocus(),
                    onArrowLeft: () => _focusFilter(
                      _tvLibraryContentFilters.first,
                    ),
                    onArrowDown: () => _focusFilter(
                      _tvLibraryContentFilters.first,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: _tvSpacing),
                  child: SingleChildScrollView(
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
                        const Text(
                          'Choose which saved TV items to show.',
                          style: TextStyle(
                            color: Color(0xFFAAA6BD),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: _tvSpacing),
                        _TvChoiceListSection(
                          title: 'Library',
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
                                onPressed: () => setState(
                                  () =>
                                      _filter = _tvLibraryContentFilters[index],
                                ),
                                onArrowUp: index == 0
                                    ? () => _closeFocusNode.requestFocus()
                                    : () => _focusFilter(
                                        _tvLibraryContentFilters[index - 1],
                                      ),
                                onArrowDown:
                                    index == _tvLibraryContentFilters.length - 1
                                    ? () => _applyFocusNode.requestFocus()
                                    : () => _focusFilter(
                                        _tvLibraryContentFilters[index + 1],
                                      ),
                              ),
                          ],
                        ),
                        const SizedBox(height: _tvSpacing),
                        _TvTextButton(
                          icon: Icons.check_rounded,
                          label: 'Apply',
                          focusNode: _applyFocusNode,
                          autoReveal: true,
                          onArrowUp: () =>
                              _focusFilter(_tvLibraryContentFilters.last),
                          onPressed: () => Navigator.of(context).pop(_filter),
                        ),
                      ],
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

class _TvChoiceListSection extends StatelessWidget {
  const _TvChoiceListSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1) const SizedBox(height: _tvSpacing),
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
          height: 56,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: _tvSpacing),
          decoration: BoxDecoration(
            color: selected ? _tvAccentColor : const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: focused
                  ? selected
                        ? Colors.white
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
                size: 24,
              ),
              const SizedBox(width: _tvSpacing),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, color: Colors.black, size: 24),
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
    this.onSeeAll,
    this.onItemArrowUp,
    this.firstItemFocusNode,
    this.centerOnFocus = false,
  });

  final _TvRail rail;
  final VoidCallback? onSeeAll;
  final VoidCallback? onItemArrowUp;
  final FocusNode? firstItemFocusNode;
  final bool centerOnFocus;
  final ValueChanged<_TvItem> onOpenItem;
  final VoidCallback onFocusNavigation;
  final ValueChanged<FocusNode> onRememberFocus;

  @override
  State<_TvContentRail> createState() => _TvContentRailState();
}

class _TvContentRailState extends State<_TvContentRail> {
  final _nodes = <FocusNode>[];
  late final FocusNode _seeAllNode;
  final GlobalKey _railKey = GlobalKey(debugLabel: 'tv-content-rail');
  final GlobalKey _horizontalViewportKey = GlobalKey(
    debugLabel: 'tv-content-rail-horizontal',
  );
  final ScrollController _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _seeAllNode = FocusNode(debugLabel: 'tv-rail-${_debugRailId()}-see-all');
    _syncNodes();
  }

  @override
  void didUpdateWidget(covariant _TvContentRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rail.items.length != widget.rail.items.length) {
      _syncNodes();
    }
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _seeAllNode.dispose();
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
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _revealFocusedCard(index, horizontalAlignment: horizontalAlignment);
    });
  }

  void _focusSeeAll() {
    if (widget.onSeeAll == null) return;
    _seeAllNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _revealRailContext();
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

  bool _railHasFocus() {
    if (_seeAllNode.hasFocus) return true;
    return _nodes.any((node) => node.hasFocus) ||
        (widget.firstItemFocusNode?.hasFocus ?? false);
  }

  void _revealRailContext() {
    if (!widget.centerOnFocus) return;
    final context = _railKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: _tvDuration(170),
      curve: Curves.easeOutCubic,
      alignment: 0.26,
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
            if (widget.onSeeAll != null)
              _CircleArrowButton(
                focusNode: _seeAllNode,
                onPressed: widget.onSeeAll!,
                onArrowLeft: () => _focusIndex(widget.rail.items.length - 1),
                onArrowDown: () => _focusIndex(0),
              ),
          ],
        ),
        SizedBox(height: _tvHomeRailGap),
        SizedBox(
          height: 214,
          child: SingleChildScrollView(
            key: _horizontalViewportKey,
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: _tvPosterGridGap,
              vertical: _tvPosterGridGap,
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
                  _PosterCard(
                    item: widget.rail.items[index],
                    rank: index + 1,
                    width: 140,
                    posterHeight: 182,
                    focusNode: _nodeFor(index),
                    autoReveal: false,
                    onFocus: () {
                      final alreadyInRail = _railHasFocus();
                      final node = _nodeFor(index);
                      widget.onRememberFocus(node);
                      _revealFocusedCard(index);
                      if (!alreadyInRail) _revealRailContext();
                    },
                    onPressed: () =>
                        widget.onOpenItem(widget.rail.items[index]),
                    onArrowLeft: index == 0
                        ? widget.onFocusNavigation
                        : () =>
                              _focusIndex(index - 1, horizontalAlignment: 0.16),
                    onArrowRight: index + 1 < widget.rail.items.length
                        ? () =>
                              _focusIndex(index + 1, horizontalAlignment: 0.84)
                        : widget.onSeeAll != null
                        ? _focusSeeAll
                        : () => _focusIndex(index, horizontalAlignment: 0.84),
                    onArrowUp: widget.onItemArrowUp,
                  ),
                  if (index != widget.rail.items.length - 1)
                    const SizedBox(width: _tvPosterGridGap),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TvExpandedRail extends StatelessWidget {
  const _TvExpandedRail({
    required this.rail,
    required this.onBack,
    required this.onOpenItem,
    required this.onFocusNavigation,
  });

  final _TvRail rail;
  final VoidCallback onBack;
  final ValueChanged<_TvItem> onOpenItem;
  final VoidCallback onFocusNavigation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TvTextButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back to Home',
          onPressed: onBack,
        ),
        const SizedBox(height: _tvSpacing),
        _TvPosterGrid(
          title: rail.title,
          subtitle: rail.subtitle,
          items: rail.items,
          onOpenItem: onOpenItem,
          onFocusNavigation: onFocusNavigation,
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
    this.columnCount = 6,
    this.posterAspect = 1.42,
    this.firstItemFocusNode,
    this.onTopRowArrowUp,
    this.onRememberFocus,
    this.onLoadMore,
  });

  final String title;
  final String subtitle;
  final List<_TvItem> items;
  final ValueChanged<_TvItem> onOpenItem;
  final VoidCallback? onFocusNavigation;
  final bool showRank;
  final bool showHeader;
  final int columnCount;
  final double posterAspect;
  final FocusNode? firstItemFocusNode;
  final VoidCallback? onTopRowArrowUp;
  final ValueChanged<FocusNode>? onRememberFocus;
  final VoidCallback? onLoadMore;

  @override
  State<_TvPosterGrid> createState() => _TvPosterGridState();
}

class _TvPosterGridState extends State<_TvPosterGrid> {
  final _nodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncNodes();
  }

  @override
  void didUpdateWidget(covariant _TvPosterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _syncNodes();
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

  void _focusIndex(int index, {double alignment = 0.38}) {
    if (index < 0 || index >= _nodes.length) return;
    final node = _nodeFor(index);
    widget.onRememberFocus?.call(node);
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
      final context = _nodeFor(index).context;
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
          const SizedBox(height: _tvSpacing / 2),
          Text(
            widget.subtitle,
            style: const TextStyle(
              color: Color(0xFFAAA6BD),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: _tvSpacing),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final columnCount = widget.columnCount.clamp(1, 8);
            final cardWidth =
                (constraints.maxWidth -
                    (_tvPosterGridGap * (columnCount - 1))) /
                columnCount;
            final posterHeight = cardWidth * widget.posterAspect;
            return Wrap(
              spacing: _tvPosterGridGap,
              runSpacing: _tvPosterGridGap,
              children: [
                for (var index = 0; index < widget.items.length; index++)
                  _PosterCard(
                    item: widget.items[index],
                    rank: index + 1,
                    width: cardWidth,
                    posterHeight: posterHeight,
                    showRank: widget.showRank,
                    focusNode: _nodeFor(index),
                    autoReveal: false,
                    onFocus: () {
                      widget.onRememberFocus?.call(_nodeFor(index));
                      _prefetchNearEnd(index, columnCount);
                      _revealIndex(index);
                    },
                    onPressed: () => widget.onOpenItem(widget.items[index]),
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
                        ? () => _focusIndex(index - columnCount, alignment: 0.2)
                        : widget.onTopRowArrowUp,
                    onArrowDown: index + columnCount < widget.items.length
                        ? () =>
                              _focusIndex(index + columnCount, alignment: 0.58)
                        : () {
                            widget.onLoadMore?.call();
                            _focusIndex(index, alignment: 0.58);
                          },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
