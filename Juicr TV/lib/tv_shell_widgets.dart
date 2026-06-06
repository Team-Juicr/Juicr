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
    required this.homeHeroKey,
    required this.homeHeroWatchFocusNode,
    required this.allItems,
    required this.movies,
    required this.series,
    required this.animation,
    required this.liveTv,
    required this.recentItems,
    required this.likedItems,
    required this.discoveryKind,
    required this.discoverySort,
    required this.discoveryGenre,
    required this.libraryFilter,
    required this.tvSettings,
    required this.onTvSettingsChanged,
    required this.onDiscoveryMenu,
    required this.onLibraryMenu,
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
    required this.onRetry,
  });

  final String title;
  final int selectedTab;
  final bool loading;
  final String? error;
  final _TvRail? expandedRail;
  final List<_TvRail> rails;
  final List<_TvItem> homeHeroItems;
  final GlobalKey homeHeroKey;
  final FocusNode homeHeroWatchFocusNode;
  final List<_TvItem> allItems;
  final List<_TvItem> movies;
  final List<_TvItem> series;
  final List<_TvItem> animation;
  final List<_TvItem> liveTv;
  final List<_TvItem> recentItems;
  final List<_TvItem> likedItems;
  final _TvDiscoveryKind discoveryKind;
  final _TvDiscoverySort discoverySort;
  final String discoveryGenre;
  final _TvLibraryFilter libraryFilter;
  final _TvSettingsState tvSettings;
  final ValueChanged<_TvSettingsState> onTvSettingsChanged;
  final VoidCallback onDiscoveryMenu;
  final VoidCallback onLibraryMenu;
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
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final showHeader = selectedTab != 0;
    return Column(
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 24, 48, 18),
            child: _TvHeader(
              title: title,
              onFocusNavigation: onFocusNavigation,
              trailing: selectedTab == 1
                    ? _TvDiscoveryFilterButton(
                      kind: discoveryKind,
                      sort: discoverySort,
                      genre: discoveryGenre,
                      onPressed: onDiscoveryMenu,
                      onArrowLeft: onFocusNavigation,
                      onArrowDown: onFocusPageContent,
                      focusNode: pageEntryFocusNode,
                    )
                  : selectedTab == 2
                      ? _TvLibraryFilterButton(
                          filter: libraryFilter,
                          onPressed: onLibraryMenu,
                          onArrowLeft: onFocusNavigation,
                          onArrowDown: onFocusPageContent,
                          focusNode: pageEntryFocusNode,
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
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: _TvEmptyCatalogState(
            title: 'Choose a source to fill Discovery.',
            subtitle: 'Enable Built-in catalog in Settings or add your own add-on.',
            verticalOffset: -42,
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
          kind: discoveryKind,
          sort: discoverySort,
          genre: discoveryGenre,
          onOpenItem: onOpenItem,
          onFocusNavigation: onFocusNavigation,
          entryFocusNode: pageContentFocusNode,
          onFocusHeader: onFocusPageEntry,
        ),
      );
    }
    if (selectedTab == 2) {
      return SliverToBoxAdapter(
        child: _TvLibrarySurface(
          recentItems: recentItems,
          likedItems: likedItems,
          filter: libraryFilter,
          onOpenItem: onOpenItem,
          onFocusNavigation: onFocusNavigation,
          entryFocusNode: pageContentFocusNode,
          onFocusHeader: onFocusPageEntry,
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
          settings: tvSettings,
          onSettingsChanged: onTvSettingsChanged,
          onFocusNavigation: onFocusNavigation,
          onRefresh: onRetry,
          entryFocusNode: pageEntryFocusNode,
        ),
      );
    }
    if (!tvSettings.hasCatalogSource) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _TvEmptyCatalogState(
          title: 'Juicr TV is ready for your sources.',
          subtitle: 'Open Settings, enable Built-in catalog, or add your own add-on to start browsing.',
          verticalOffset: -42,
        ),
      );
    }
    final heroItems = homeHeroItems;
    final heroItem = heroItems.isEmpty ? null : heroItems.first;
    final heroOffset = heroItems.isEmpty ? 0 : 1;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (heroItem != null && index == 0) {
            return Column(
              children: [
                _TvHomeHero(
                  key: homeHeroKey,
                  items: heroItems,
                  onOpenItem: onOpenItem,
                  onPlayItem: onPlayItem,
                  onTrailerItem: onTrailerItem,
                  onToggleLike: onToggleLike,
                  isItemLiked: isItemLiked,
                  onFocusNavigation: onFocusNavigation,
                  watchFocusNode: homeHeroWatchFocusNode,
                ),
                const _TvHeroRailFade(),
              ],
            );
          }
          final railIndex = index - heroOffset;
          return Padding(
            padding: const EdgeInsets.fromLTRB(30, 0, 48, 12),
            child: _TvContentRail(
              rail: rails[railIndex],
              onSeeAll: () => onOpenRail(rails[railIndex]),
              onOpenItem: onOpenItem,
              onFocusNavigation: onFocusNavigation,
              firstItemFocusNode: railIndex == 0 ? pageEntryFocusNode : null,
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
        },
        childCount: rails.length + heroOffset,
      ),
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
            colors: [
              Color(0xFF07080D),
              Color(0xF20A0A12),
              Color(0xFF0D0B1B),
            ],
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
    required this.onOpenItem,
    required this.onPlayItem,
    required this.onTrailerItem,
    required this.onToggleLike,
    required this.isItemLiked,
    required this.onFocusNavigation,
    required this.watchFocusNode,
  });

  final List<_TvItem> items;
  final ValueChanged<_TvItem> onOpenItem;
  final ValueChanged<_TvItem> onPlayItem;
  final ValueChanged<_TvItem> onTrailerItem;
  final ValueChanged<_TvItem> onToggleLike;
  final bool Function(_TvItem item) isItemLiked;
  final VoidCallback onFocusNavigation;
  final FocusNode watchFocusNode;

  @override
  State<_TvHomeHero> createState() => _TvHomeHeroState();
}

class _TvHomeHeroState extends State<_TvHomeHero> {
  Timer? _carouselTimer;
  int _index = 0;

  _TvItem get _item => widget.items[_index.clamp(0, widget.items.length - 1).toInt()];

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
    return SizedBox(
      height: 390,
      child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null)
              Image.network(
                image,
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                errorBuilder: (_, __, ___) => ColoredBox(color: item.color.withValues(alpha: 0.35)),
              )
            else
              ColoredBox(color: item.color.withValues(alpha: 0.35)),
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
                colors: [
                  Color(0x0007080D),
                  Color(0x7307080D),
                ],
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
                    Text(
                      item.type.toUpperCase(),
                      style: TextStyle(
                        color: _tvAccentColor,
                        fontSize: 10,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 12),
                    Text(
                      item.description?.isNotEmpty == true
                          ? item.description!
                          : item.subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE2DDED),
                        fontSize: 13,
                        height: 1.34,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _TvTextButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Watch now',
                          autofocus: true,
                          focusNode: widget.watchFocusNode,
                          onArrowLeft: widget.onFocusNavigation,
                          onPressed: () => widget.onPlayItem(item),
                        ),
                        _TvTextButton(
                          icon: Icons.movie_filter_rounded,
                          label: 'Trailer',
                          onPressed: () => widget.onTrailerItem(item),
                        ),
                        _TvTextButton(
                          icon: Icons.info_outline_rounded,
                          label: 'Details',
                          onPressed: () => widget.onOpenItem(item),
                        ),
                    _TvCircleIconButton(
                          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          selected: liked,
                          size: 48,
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
    return KeyEventResult.ignored;
  }

  @override
  void didUpdateWidget(covariant _TvNavigationRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      throw StateError('TV navigation item count changed after init.');
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
          const SizedBox(height: 28),
          const _TvRailAppMark(),
          const Spacer(),
          for (var index = 0; index < widget.items.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
            child: _FocusableIconButton(
                icon: widget.items[index].icon,
                selected: widget.selectedIndex == index,
                focusNode: _nodes[index],
                autofocus: index == 0,
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
          const Spacer(flex: 2),
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
        SizedBox(width: 350, child: trailing),
      ],
    );
  }
}

class _TvRailAppMark extends StatelessWidget {
  const _TvRailAppMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Juicr TV',
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: _tvAccentColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3320D66B),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(
          Icons.local_drink_rounded,
          color: Colors.black,
          size: 26,
        ),
      ),
    );
  }
}

class _TvDiscoveryFilterButton extends StatelessWidget {
  const _TvDiscoveryFilterButton({
    required this.kind,
    required this.sort,
    required this.genre,
    required this.onPressed,
    this.onArrowLeft,
    this.onArrowDown,
    this.focusNode,
  });

  final _TvDiscoveryKind kind;
  final _TvDiscoverySort sort;
  final String genre;
  final VoidCallback onPressed;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowDown;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      onPressed: onPressed,
      onArrowLeft: onArrowLeft,
      onArrowDown: onArrowDown,
      focusNode: focusNode,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(140),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
              Icon(Icons.tune_rounded, color: focused ? _tvAccentColor : const Color(0xFFBDB9D5), size: 24),
              const SizedBox(width: 12),
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
                      genre == 'All genres' ? sort.subtitle : '${sort.label} in $genre',
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
              const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFFBDB9D5), size: 26),
            ],
          ),
        );
      },
    );
  }
}

class _TvLibraryFilterButton extends StatelessWidget {
  const _TvLibraryFilterButton({
    required this.filter,
    required this.onPressed,
    this.onArrowLeft,
    this.onArrowDown,
    this.focusNode,
  });

  final _TvLibraryFilter filter;
  final VoidCallback onPressed;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowDown;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      onPressed: onPressed,
      onArrowLeft: onArrowLeft,
      onArrowDown: onArrowDown,
      focusNode: focusNode,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(140),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
              Icon(filter.icon, color: focused ? _tvAccentColor : const Color(0xFFBDB9D5), size: 24),
              const SizedBox(width: 12),
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
              const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFFBDB9D5), size: 24),
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
  late _TvDiscoveryKind _kind = widget.kind;
  late _TvDiscoverySort _sort = widget.sort;
  late String _genre = widget.genre;

  Future<void> _pickGenre() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _TvGenreMenuDialog(
        selected: _genre,
        genres: widget.genres,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _genre = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 150, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: Container(
          padding: const EdgeInsets.all(24),
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
                  icon: Icons.close_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 56),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Discovery menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose the catalog and ordering for this screen.',
                  style: TextStyle(
                    color: Color(0xFFBDB9D5),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                _TvChoiceListSection(
                  title: 'Catalog',
                  children: [
                    for (final kind in _TvDiscoveryKind.values)
                      _TvChoiceRow(
                        icon: kind.icon,
                        label: kind.label,
                        selected: _kind == kind,
                        onPressed: () => setState(() => _kind = kind),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _TvChoiceListSection(
                  title: 'Genre',
                  children: [
                    _TvChoiceRow(
                      icon: Icons.category_rounded,
                      label: _genre,
                      selected: true,
                      onPressed: () => unawaited(_pickGenre()),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _TvChoiceListSection(
                  title: 'Sort',
                  children: [
                    for (final sort in _TvDiscoverySort.values)
                      _TvChoiceRow(
                        icon: Icons.sort_rounded,
                        label: sort.label,
                        selected: _sort == sort,
                        onPressed: () => setState(() => _sort = sort),
                      ),
                  ],
                ),
                    const SizedBox(height: 22),
                    _TvTextButton(
                      icon: Icons.check_rounded,
                      label: 'Apply',
                      onPressed: () => Navigator.of(context).pop(
                        _TvDiscoverySelection(_kind, _sort, _genre),
                      ),
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

class _TvGenreMenuDialog extends StatelessWidget {
  const _TvGenreMenuDialog({
    required this.selected,
    required this.genres,
  });

  final String selected;
  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    final choices = <String>['All genres', ...genres.where((genre) => genre != 'All genres')];
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 520),
        padding: const EdgeInsets.all(24),
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
                icon: Icons.close_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 56),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Genres',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final genre in choices)
                          _TvChoicePill(
                            icon: genre == selected ? Icons.check_circle_rounded : Icons.category_rounded,
                            label: genre,
                            selected: genre == selected,
                            onPressed: () => Navigator.of(context).pop(genre),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvLibraryMenuDialog extends StatefulWidget {
  const _TvLibraryMenuDialog({required this.filter});

  final _TvLibraryFilter filter;

  @override
  State<_TvLibraryMenuDialog> createState() => _TvLibraryMenuDialogState();
}

class _TvLibraryMenuDialogState extends State<_TvLibraryMenuDialog> {
  late _TvLibraryFilter _filter = widget.filter;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
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
                icon: Icons.close_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 56),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Library menu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Choose which saved TV items to show.',
                    style: TextStyle(
                      color: Color(0xFFAAA6BD),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _TvChoiceListSection(
                    title: 'Library',
                    children: [
                      for (final filter in _TvLibraryFilter.values)
                        _TvChoiceRow(
                          icon: filter.icon,
                          label: filter.label,
                          selected: _filter == filter,
                          onPressed: () => setState(() => _filter = filter),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _TvTextButton(
                    icon: Icons.check_rounded,
                    label: 'Apply',
                    onPressed: () => Navigator.of(context).pop(_filter),
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

class _TvChoiceSection extends StatelessWidget {
  const _TvChoiceSection({
    required this.title,
    required this.children,
  });

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
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: children,
        ),
      ],
    );
  }
}

class _TvChoiceListSection extends StatelessWidget {
  const _TvChoiceListSection({
    required this.title,
    required this.children,
  });

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
        const SizedBox(height: 10),
        Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1) const SizedBox(height: 10),
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
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      onPressed: onPressed,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(130),
          height: 64,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: selected ? _tvAccentColor : const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(24),
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
              Icon(icon, color: selected ? Colors.black : _tvAccentColor, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selected) const Icon(Icons.check_rounded, color: Colors.black, size: 24),
            ],
          ),
        );
      },
    );
  }
}

class _TvChoicePill extends StatelessWidget {
  const _TvChoicePill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
      onPressed: onPressed,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(130),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? _tvAccentColor : const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(999),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? Colors.black : Colors.white, size: 21),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
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

  @override
  State<_TvContentRail> createState() => _TvContentRailState();
}

class _TvContentRailState extends State<_TvContentRail> {
  final _nodes = <FocusNode>[];
  final GlobalKey _railKey = GlobalKey(debugLabel: 'tv-content-rail');

  @override
  void initState() {
    super.initState();
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
      _nodes.add(FocusNode(debugLabel: 'tv-rail-card-$index'));
    }
  }

  FocusNode _nodeFor(int index) {
    if (index == 0 && widget.firstItemFocusNode != null) {
      return widget.firstItemFocusNode!;
    }
    return _nodes[index];
  }

  void _focusIndex(int index) {
    if (index < 0 || index >= widget.rail.items.length) return;
    _nodeFor(index).requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _revealFocusedCard(index);
      _revealRailContext();
    });
  }

  void _revealFocusedCard(int index) {
    final context = _nodeFor(index).context;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: _tvDuration(150),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
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
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.rail.title,
                    style: const TextStyle(
                      color: Colors.white,
          fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
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
              ),
            ),
            if (widget.onSeeAll != null) _CircleArrowButton(onPressed: widget.onSeeAll!),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 214,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < widget.rail.items.length; index++) ...[
                  _PosterCard(
                    item: widget.rail.items[index],
                    rank: index + 1,
                    width: 140,
                    posterHeight: 182,
                    focusNode: _nodeFor(index),
                    autoReveal: false,
                    onFocus: () {
                      _revealFocusedCard(index);
                      _revealRailContext();
                    },
                    onPressed: () => widget.onOpenItem(widget.rail.items[index]),
                    onArrowLeft: index == 0 ? widget.onFocusNavigation : () => _focusIndex(index - 1),
                    onArrowRight: index + 1 < widget.rail.items.length ? () => _focusIndex(index + 1) : null,
                    onArrowUp: widget.onItemArrowUp,
                  ),
                  if (index != widget.rail.items.length - 1) const SizedBox(width: _tvSpacing),
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
        const SizedBox(height: 18),
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

  void _focusIndex(int index) {
    if (index < 0 || index >= _nodes.length) return;
    _nodeFor(index).requestFocus();
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
            final cardWidth = (constraints.maxWidth - (_tvSpacing * (columnCount - 1))) / columnCount;
            final posterHeight = cardWidth * widget.posterAspect;
            return Wrap(
              spacing: _tvSpacing,
              runSpacing: _tvSpacing,
              children: [
                for (var index = 0; index < widget.items.length; index++)
                  _PosterCard(
                    item: widget.items[index],
                    rank: index + 1,
                    width: cardWidth,
                    posterHeight: posterHeight,
                    showRank: widget.showRank,
                    focusNode: _nodeFor(index),
                    onPressed: () => widget.onOpenItem(widget.items[index]),
                    onArrowLeft: index % columnCount == 0 ? widget.onFocusNavigation : () => _focusIndex(index - 1),
                    onArrowRight: index + 1 < widget.items.length ? () => _focusIndex(index + 1) : null,
                    onArrowUp: index - columnCount >= 0 ? () => _focusIndex(index - columnCount) : widget.onTopRowArrowUp,
                    onArrowDown: index + columnCount < widget.items.length ? () => _focusIndex(index + columnCount) : null,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}


