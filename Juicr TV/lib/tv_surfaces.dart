part of 'main.dart';

const MethodChannel _tvTrailerChannel = MethodChannel(
  'app.juicr.flutter/trailer',
);
const MethodChannel _tvQuickLinkChannel = MethodChannel(
  'app.juicr.flutter/quick_links',
);

Future<bool> _openTvExternalTrailer(_TvTrailer trailer) async {
  if (!trailer.isExternalLaunchable) return false;
  try {
    return await _tvTrailerChannel.invokeMethod<bool>('openTrailer', {
          'url': trailer.url,
        }) ??
        false;
  } catch (error) {
    debugPrint(
      'Juicr TV trailer handoff skipped '
      'bucket=trailer_handoff errorType=${error.runtimeType}',
    );
    return false;
  }
}

class _TvDiscoverySurface extends StatelessWidget {
  const _TvDiscoverySurface({
    required this.allItems,
    required this.movies,
    required this.series,
    required this.animation,
    required this.liveTv,
    required this.discoveryLaneItems,
    required this.kind,
    required this.sort,
    required this.genre,
    required this.loadingMore,
    required this.exhausted,
    required this.onOpenItem,
    required this.onFocusNavigation,
    required this.entryFocusNode,
    required this.onFocusHeader,
    required this.onRememberFocus,
    required this.onRememberItemFocus,
    required this.onRestoreItemFocus,
    required this.onLoadMore,
    this.restoreItemKey,
  });

  final List<_TvItem> allItems;
  final List<_TvItem> movies;
  final List<_TvItem> series;
  final List<_TvItem> animation;
  final List<_TvItem> liveTv;
  final Map<String, List<_TvItem>> discoveryLaneItems;
  final _TvDiscoveryKind kind;
  final _TvDiscoverySort sort;
  final String genre;
  final bool loadingMore;
  final bool exhausted;
  final Future<void> Function(_TvItem item) onOpenItem;
  final VoidCallback onFocusNavigation;
  final FocusNode entryFocusNode;
  final VoidCallback onFocusHeader;
  final ValueChanged<FocusNode> onRememberFocus;
  final void Function(FocusNode node, _TvItem item) onRememberItemFocus;
  final ValueChanged<String> onRestoreItemFocus;
  final String? restoreItemKey;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final fallbackItems = switch (kind) {
      _TvDiscoveryKind.movie => movies,
      _TvDiscoveryKind.series => series,
      _TvDiscoveryKind.animation => animation,
      _TvDiscoveryKind.liveTv => liveTv,
    };
    final genreLaneItems =
        discoveryLaneItems[_tvDiscoveryLaneKey(kind, sort, genre: genre)];
    final baseLaneItems = discoveryLaneItems[_tvDiscoveryLaneKey(kind, sort)];
    final broadLaneItems = <_TvItem>[
      for (final entry in discoveryLaneItems.entries)
        if (entry.key.startsWith('${kind.name}:')) ...entry.value,
    ];
    final laneItems = genreLaneItems ?? baseLaneItems ?? const <_TvItem>[];
    final laneSource = _filteredCatalogItems(
      laneItems.isEmpty
          ? broadLaneItems.isEmpty
              ? fallbackItems
              : broadLaneItems
          : laneItems,
      kind,
      genre,
    );
    final fallbackSource = _filteredCatalogItems(fallbackItems, kind, genre);
    final items = _sortedCatalogItems(
      laneSource.isEmpty ? fallbackSource : laneSource,
      sort,
      preserveLaneOrder: laneSource.isNotEmpty && laneItems.isNotEmpty,
    );
    final visibleItems = items;

    if (visibleItems.isEmpty) {
      if (loadingMore) {
        return const Padding(
          padding: EdgeInsets.only(top: 32, bottom: 70),
          child: _TvCatalogSkeletonGrid(),
        );
      }
      return _TvEmptyCatalogState(
        title: 'Discovery is waiting for catalog data.',
        subtitle: genre == 'All genres'
            ? 'Turn on a source in Settings or refresh when your connection is ready.'
            : 'No ${kind.label.toLowerCase()} are available for $genre yet.',
        height: MediaQuery.sizeOf(context).height - 210,
        focusNode: entryFocusNode,
        onFocusNavigation: onFocusNavigation,
        onFocusHeader: onFocusHeader,
      );
    }

    return _TvPosterGrid(
      title: '${kind.label} catalog',
      subtitle: sort.subtitleFor(kind, genre),
      items: visibleItems,
      showRank: false,
      showHeader: false,
      firstItemFocusNode: entryFocusNode,
      onOpenItem: onOpenItem,
      onFocusNavigation: onFocusNavigation,
      onTopRowArrowUp: onFocusHeader,
      onRememberFocus: onRememberFocus,
      onRememberItemFocus: onRememberItemFocus,
      restoreItemKey: restoreItemKey,
      onRestoreItemFocus: onRestoreItemFocus,
      onLoadMore: onLoadMore,
      loadingMore: loadingMore,
      exhausted: exhausted,
      landscapeCards: kind == _TvDiscoveryKind.liveTv,
    );
  }

  List<_TvItem> _filteredCatalogItems(
    List<_TvItem> source,
    _TvDiscoveryKind kind,
    String genre,
  ) {
    final seen = <String>{};
    final items = <_TvItem>[];
    for (final item in source) {
      if (!_matchesDiscoveryKind(item, kind)) continue;
      if (!_matchesDiscoveryGenre(item, genre)) continue;
      final key = '${item.type}:${item.id}:${item.title.toLowerCase()}';
      if (!seen.add(key)) continue;
      items.add(item);
    }
    return items;
  }

  List<_TvItem> _sortedCatalogItems(
    List<_TvItem> source,
    _TvDiscoverySort sort, {
    required bool preserveLaneOrder,
  }) {
    final items = source.toList();
    if (preserveLaneOrder) return items;
    switch (sort) {
      case _TvDiscoverySort.nowPlaying:
      case _TvDiscoverySort.airingToday:
      case _TvDiscoverySort.onTv:
      case _TvDiscoverySort.newest:
        items.sort((a, b) => (_yearInt(b.year)).compareTo(_yearInt(a.year)));
      case _TvDiscoverySort.topRated:
      case _TvDiscoverySort.featured:
        items.sort(
          (a, b) => (_ratingDouble(
            b.imdbRating,
          )).compareTo(_ratingDouble(a.imdbRating)),
        );
      case _TvDiscoverySort.upcoming:
        items.sort((a, b) => (_yearInt(a.year)).compareTo(_yearInt(b.year)));
      case _TvDiscoverySort.popular:
        break;
    }
    return items;
  }

  bool _matchesDiscoveryKind(_TvItem item, _TvDiscoveryKind kind) {
    final type = _normalDiscoveryToken(item.type);
    switch (kind) {
      case _TvDiscoveryKind.movie:
        return type == 'movie';
      case _TvDiscoveryKind.series:
        return type == 'series';
      case _TvDiscoveryKind.animation:
        return type == 'animation' ||
            item.genres.any((genre) {
              final normalized = _normalDiscoveryToken(genre);
              return normalized == 'animation' ||
                  normalized == 'animated' ||
                  normalized == 'anime';
            });
      case _TvDiscoveryKind.liveTv:
        return type == 'live' ||
            type == 'live tv' ||
            type == 'livetv' ||
            type == 'channel' ||
            type == 'channels';
    }
  }

  bool _matchesDiscoveryGenre(_TvItem item, String genre) {
    final selected = _normalDiscoveryToken(genre);
    if (selected.isEmpty || selected == 'all genres') return true;
    return item.genres.any(
      (itemGenre) => _normalDiscoveryToken(itemGenre) == selected,
    );
  }

  String _normalDiscoveryToken(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _TvLibrarySurface extends StatelessWidget {
  const _TvLibrarySurface({
    required this.recentItems,
    required this.likedItems,
    required this.libraryLists,
    required this.filter,
    required this.accountSignedIn,
    required this.accountToken,
    required this.activeWatchLabel,
    required this.activeWatchSeconds,
    required this.leaderboardScope,
    required this.recentCount,
    required this.savedCount,
    required this.completedCount,
    required this.onLeaderboardScopeChanged,
    required this.onAccountSignIn,
    required this.onOpenItem,
    required this.onFocusNavigation,
    required this.entryFocusNode,
    required this.onFocusHeader,
    required this.onRememberFocus,
    required this.onRememberItemFocus,
    required this.onRestoreItemFocus,
    this.restoreItemKey,
  });

  final List<_TvItem> recentItems;
  final List<_TvItem> likedItems;
  final List<TvLibraryList> libraryLists;
  final _TvLibraryFilter filter;
  final bool accountSignedIn;
  final String accountToken;
  final String activeWatchLabel;
  final int activeWatchSeconds;
  final String leaderboardScope;
  final int recentCount;
  final int savedCount;
  final int completedCount;
  final ValueChanged<String> onLeaderboardScopeChanged;
  final VoidCallback onAccountSignIn;
  final Future<void> Function(_TvItem item) onOpenItem;
  final VoidCallback onFocusNavigation;
  final FocusNode entryFocusNode;
  final VoidCallback onFocusHeader;
  final ValueChanged<FocusNode> onRememberFocus;
  final void Function(FocusNode node, _TvItem item) onRememberItemFocus;
  final ValueChanged<String> onRestoreItemFocus;
  final String? restoreItemKey;

  @override
  Widget build(BuildContext context) {
    if (filter == _TvLibraryFilter.lists) {
      return _TvLibraryListsSurface(
        lists: libraryLists,
        entryFocusNode: entryFocusNode,
        onFocusNavigation: onFocusNavigation,
        onFocusHeader: onFocusHeader,
      );
    }
    if (filter == _TvLibraryFilter.metrics) {
      return _TvLibraryMetricsSurface(
        activeWatchLabel: activeWatchLabel,
        recentCount: recentCount,
        savedCount: savedCount,
        completedCount: completedCount,
        movieCount: likedItems.where((item) => item.type == 'movie').length,
        seriesCount: likedItems.where((item) => item.type == 'series').length,
        animationCount:
            likedItems.where((item) => item.type == 'animation').length,
        entryFocusNode: entryFocusNode,
        onFocusNavigation: onFocusNavigation,
        onFocusHeader: onFocusHeader,
      );
    }
    if (filter == _TvLibraryFilter.ranking) {
      return _TvLibraryRankingSurface(
        accountSignedIn: accountSignedIn,
        accountToken: accountToken,
        activeWatchLabel: activeWatchLabel,
        activeWatchSeconds: activeWatchSeconds,
        selectedScope: leaderboardScope,
        onScopeChanged: onLeaderboardScopeChanged,
        onSignIn: onAccountSignIn,
        entryFocusNode: entryFocusNode,
        onFocusNavigation: onFocusNavigation,
        onFocusHeader: onFocusHeader,
      );
    }
    final items = _filteredItems;

    if (items.isEmpty) {
      return _TvEmptyCatalogState(
        title: _emptyTitle,
        subtitle: _emptySubtitle,
        height: MediaQuery.sizeOf(context).height - 210,
        focusNode: entryFocusNode,
        onFocusNavigation: onFocusNavigation,
        onFocusHeader: onFocusHeader,
      );
    }

    return _TvPosterGrid(
      title: _title,
      subtitle: _subtitle,
      items: items,
      showRank: false,
      showHeader: false,
      firstItemFocusNode: entryFocusNode,
      onOpenItem: onOpenItem,
      onFocusNavigation: onFocusNavigation,
      onTopRowArrowUp: onFocusHeader,
      onRememberFocus: onRememberFocus,
      onRememberItemFocus: onRememberItemFocus,
      restoreItemKey: restoreItemKey,
      onRestoreItemFocus: onRestoreItemFocus,
    );
  }

  List<_TvItem> get _filteredItems {
    switch (filter) {
      case _TvLibraryFilter.continueWatching:
        return recentItems;
      case _TvLibraryFilter.lists:
      case _TvLibraryFilter.metrics:
      case _TvLibraryFilter.ranking:
        return const [];
      case _TvLibraryFilter.movies:
        return likedItems.where((item) => item.type == 'movie').toList();
      case _TvLibraryFilter.series:
        return likedItems.where((item) => item.type == 'series').toList();
      case _TvLibraryFilter.animation:
        return likedItems.where((item) => item.type == 'animation').toList();
      case _TvLibraryFilter.liveTv:
        return likedItems
            .where(
              (item) => (item.type == 'live' ||
                  item.type == 'live_tv' ||
                  item.type == 'livetv' ||
                  item.type == 'channel'),
            )
            .toList();
    }
  }

  String get _title {
    return switch (filter) {
      _TvLibraryFilter.continueWatching => 'Continue watching',
      _TvLibraryFilter.lists => 'Lists',
      _TvLibraryFilter.movies => 'Liked movies',
      _TvLibraryFilter.series => 'Liked series',
      _TvLibraryFilter.animation => 'Liked animations',
      _TvLibraryFilter.liveTv => 'Liked Live TV',
      _TvLibraryFilter.metrics => 'Watching metrics',
      _TvLibraryFilter.ranking => 'Ranking',
    };
  }

  String get _subtitle {
    return switch (filter) {
      _TvLibraryFilter.continueWatching =>
        'Titles with playback left on this TV.',
      _TvLibraryFilter.lists => 'Custom watchlists on this TV.',
      _TvLibraryFilter.movies => 'Movies you hearted on this TV.',
      _TvLibraryFilter.series => 'Series you hearted on this TV.',
      _TvLibraryFilter.animation => 'Animations you hearted on this TV.',
      _TvLibraryFilter.liveTv => 'Live TV items you hearted on this TV.',
      _TvLibraryFilter.metrics => 'Safe playback totals from this TV.',
      _TvLibraryFilter.ranking => 'Account ranking based on active watch time.',
    };
  }

  String get _emptyTitle {
    return switch (filter) {
      _TvLibraryFilter.continueWatching => 'Nothing to continue yet.',
      _TvLibraryFilter.lists => 'No lists yet.',
      _TvLibraryFilter.movies => 'No liked movies yet.',
      _TvLibraryFilter.series => 'No liked series yet.',
      _TvLibraryFilter.animation => 'No liked animations yet.',
      _TvLibraryFilter.liveTv => 'No liked Live TV yet.',
      _TvLibraryFilter.metrics => 'No metrics yet.',
      _TvLibraryFilter.ranking => 'Ranking is not ready yet.',
    };
  }

  String get _emptySubtitle {
    return switch (filter) {
      _TvLibraryFilter.continueWatching =>
        'Start watching a title and unfinished playback will appear here.',
      _TvLibraryFilter.lists =>
        'Create a list from a title details page to organize it here.',
      _TvLibraryFilter.movies =>
        'Save a movie from Home, Discovery, or Details to show it here.',
      _TvLibraryFilter.series =>
        'Save a series from Home, Discovery, or Details to show it here.',
      _TvLibraryFilter.animation =>
        'Save animations from Home, Discovery, or Details to show them here.',
      _TvLibraryFilter.liveTv =>
        'Save Live TV items when they are available on this TV.',
      _TvLibraryFilter.metrics =>
        'Watch playback on this TV to build safe local totals.',
      _TvLibraryFilter.ranking =>
        'Sign in and opt in from Account to join rankings.',
    };
  }
}

class _TvLibraryListsSurface extends StatelessWidget {
  const _TvLibraryListsSurface({
    required this.lists,
    required this.entryFocusNode,
    required this.onFocusNavigation,
    required this.onFocusHeader,
  });

  final List<TvLibraryList> lists;
  final FocusNode entryFocusNode;
  final VoidCallback onFocusNavigation;
  final VoidCallback onFocusHeader;

  @override
  Widget build(BuildContext context) {
    if (lists.isEmpty) {
      return _TvEmptyCatalogState(
        title: 'No lists yet.',
        subtitle:
            'Create a list from a title details page to organize it here.',
        height: MediaQuery.sizeOf(context).height - 210,
        focusNode: entryFocusNode,
        onFocusNavigation: onFocusNavigation,
        onFocusHeader: onFocusHeader,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: _tvSpacing),
      child: Column(
        children: [
          for (var index = 0; index < lists.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: _tvSpacing),
              child: _TvLibraryListCard(
                list: lists[index],
                autofocus: index == 0,
                focusNode: index == 0 ? entryFocusNode : null,
                onArrowLeft: onFocusNavigation,
                onArrowUp: index == 0 ? onFocusHeader : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _TvLibraryListCard extends StatelessWidget {
  const _TvLibraryListCard({
    required this.list,
    this.autofocus = false,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowUp,
  });

  final TvLibraryList list;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowUp;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      focusNode: focusNode,
      autoReveal: true,
      onArrowLeft: onArrowLeft,
      onArrowUp: onArrowUp,
      onPressed: () {},
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: focused ? const Color(0x3320D66B) : const Color(0x5531313C),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: focused ? _tvAccentColor : const Color(0x22FFFFFF),
              width: focused ? 3 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.bookmarks_outlined, color: _tvAccentColor, size: 34),
              const SizedBox(width: _tvSpacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: _tvSpacing),
                    Text(
                      '${list.itemKeys.length} ${list.itemKeys.length == 1 ? 'title' : 'titles'}',
                      style: const TextStyle(
                        color: Color(0xFFAAA6BD),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvLibraryMetricsSurface extends StatelessWidget {
  const _TvLibraryMetricsSurface({
    required this.activeWatchLabel,
    required this.recentCount,
    required this.savedCount,
    required this.completedCount,
    required this.movieCount,
    required this.seriesCount,
    required this.animationCount,
    required this.entryFocusNode,
    required this.onFocusNavigation,
    required this.onFocusHeader,
  });

  final String activeWatchLabel;
  final int recentCount;
  final int savedCount;
  final int completedCount;
  final int movieCount;
  final int seriesCount;
  final int animationCount;
  final FocusNode entryFocusNode;
  final VoidCallback onFocusNavigation;
  final VoidCallback onFocusHeader;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: true,
      focusNode: entryFocusNode,
      onPressed: () {},
      onArrowLeft: onFocusNavigation,
      onArrowUp: onFocusHeader,
      builder: (focused) {
        return Padding(
          padding: const EdgeInsets.only(top: _tvSpacing),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TvMetricHeroCard(
                label: 'Active watch time',
                value: activeWatchLabel,
                focused: focused,
              ),
              const SizedBox(height: _tvSpacing),
              Row(
                children: [
                  Expanded(
                    child: _TvMetricCard(
                      label: 'Continue watching',
                      value: '$recentCount',
                    ),
                  ),
                  const SizedBox(width: _tvSpacing),
                  Expanded(
                    child: _TvMetricCard(label: 'Saved', value: '$savedCount'),
                  ),
                  const SizedBox(width: _tvSpacing),
                  Expanded(
                    child: _TvMetricCard(
                      label: 'Completed',
                      value: '$completedCount',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _tvSpacing),
              Row(
                children: [
                  Expanded(
                    child: _TvMetricCard(label: 'Movies', value: '$movieCount'),
                  ),
                  const SizedBox(width: _tvSpacing),
                  Expanded(
                    child: _TvMetricCard(
                      label: 'Series',
                      value: '$seriesCount',
                    ),
                  ),
                  const SizedBox(width: _tvSpacing),
                  Expanded(
                    child: _TvMetricCard(
                      label: 'Animations',
                      value: '$animationCount',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvMetricHeroCard extends StatelessWidget {
  const _TvMetricHeroCard({
    required this.label,
    required this.value,
    required this.focused,
  });

  final String label;
  final String value;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _tvDuration(140),
      width: double.infinity,
      padding: const EdgeInsets.all(_tvSpacing),
      decoration: BoxDecoration(
        color: const Color(0x5531313C),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: focused ? _tvAccentColor : const Color(0x22FFFFFF),
          width: focused ? 3 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: _tvAccentColor, size: 36),
          const SizedBox(width: _tvSpacing),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFAAA6BD),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TvMetricCard extends StatelessWidget {
  const _TvMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_tvSpacing),
      decoration: BoxDecoration(
        color: const Color(0x5531313C),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFAAA6BD),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: _tvSpacing),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvLibraryRankingSurface extends StatefulWidget {
  const _TvLibraryRankingSurface({
    required this.accountSignedIn,
    required this.accountToken,
    required this.activeWatchLabel,
    required this.activeWatchSeconds,
    required this.selectedScope,
    required this.onScopeChanged,
    required this.onSignIn,
    required this.entryFocusNode,
    required this.onFocusNavigation,
    required this.onFocusHeader,
  });

  final bool accountSignedIn;
  final String accountToken;
  final String activeWatchLabel;
  final int activeWatchSeconds;
  final String selectedScope;
  final ValueChanged<String> onScopeChanged;
  final VoidCallback onSignIn;
  final FocusNode entryFocusNode;
  final VoidCallback onFocusNavigation;
  final VoidCallback onFocusHeader;

  @override
  State<_TvLibraryRankingSurface> createState() =>
      _TvLibraryRankingSurfaceState();
}

class _TvLibraryRankingSurfaceState extends State<_TvLibraryRankingSurface> {
  final _scopeFocusNodes = [
    FocusNode(debugLabel: 'tv-ranking-today'),
    FocusNode(debugLabel: 'tv-ranking-weekly'),
    FocusNode(debugLabel: 'tv-ranking-all'),
  ];
  final _rankFocusNode = FocusNode(debugLabel: 'tv-ranking-rank-card');
  final _messageFocusNode = FocusNode(debugLabel: 'tv-ranking-message');
  final _rowFocusNodes = <FocusNode>[];
  late String _scope = _normalizeTvLeaderboardScope(widget.selectedScope);
  late Future<_TvLeaderboardResult?> _future = _load();

  @override
  void didUpdateWidget(covariant _TvLibraryRankingSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextScope = _normalizeTvLeaderboardScope(widget.selectedScope);
    if (nextScope != _scope ||
        oldWidget.accountToken != widget.accountToken ||
        oldWidget.activeWatchSeconds != widget.activeWatchSeconds ||
        oldWidget.accountSignedIn != widget.accountSignedIn) {
      _scope = nextScope;
      _future = _load();
    }
  }

  @override
  void dispose() {
    for (final node in _scopeFocusNodes) {
      node.dispose();
    }
    _rankFocusNode.dispose();
    _messageFocusNode.dispose();
    for (final node in _rowFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncRowFocusNodes(int count) {
    while (_rowFocusNodes.length > count) {
      _rowFocusNodes.removeLast().dispose();
    }
    while (_rowFocusNodes.length < count) {
      _rowFocusNodes.add(
        FocusNode(debugLabel: 'tv-ranking-row-${_rowFocusNodes.length}'),
      );
    }
  }

  Future<_TvLeaderboardResult?> _load() async {
    if (!widget.accountSignedIn || widget.accountToken.trim().isEmpty) {
      return null;
    }
    return _TvApi().fetchLeaderboard(scope: _scope, token: widget.accountToken);
  }

  void _selectScope(String scope) {
    final normalized = _normalizeTvLeaderboardScope(scope);
    if (normalized == _scope) return;
    setState(() {
      _scope = normalized;
      _future = _load();
    });
    widget.onScopeChanged(normalized);
  }

  int get _selectedScopeIndex {
    return switch (_scope) {
      'today' => 0,
      'all' => 2,
      _ => 1,
    };
  }

  void _focusScope(int index) {
    if (index < 0 || index >= _scopeFocusNodes.length) return;
    _scopeFocusNodes[index].requestFocus();
  }

  void _focusRank() {
    _rankFocusNode.requestFocus();
  }

  void _focusRow(int index) {
    if (index < 0 || index >= _rowFocusNodes.length) return;
    _rowFocusNodes[index].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    const scopes = [
      ('today', 'Today'),
      ('weekly', 'Weekly'),
      ('all', 'All time'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: _tvSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(
            focusNode: widget.entryFocusNode,
            onFocusChange: (focused) {
              if (!focused) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _focusScope(_selectedScopeIndex);
              });
            },
            child: const SizedBox.shrink(),
          ),
          Row(
            children: [
              for (var index = 0; index < scopes.length; index++) ...[
                Expanded(
                  child: _TvLeaderboardScopeButton(
                    label: scopes[index].$2,
                    selected: _scope == scopes[index].$1,
                    focusNode: _scopeFocusNodes[index],
                    autofocus: index == _selectedScopeIndex,
                    onPressed: () => _selectScope(scopes[index].$1),
                    onArrowLeft: index == 0
                        ? widget.onFocusNavigation
                        : () => _focusScope(index - 1),
                    onArrowRight: index == scopes.length - 1
                        ? () => _focusScope(index)
                        : () => _focusScope(index + 1),
                    onArrowUp: widget.onFocusHeader,
                    onArrowDown: _focusRank,
                  ),
                ),
                if (index < scopes.length - 1)
                  const SizedBox(width: _tvSpacing),
              ],
            ],
          ),
          const SizedBox(height: _tvSpacing),
          if (!widget.accountSignedIn)
            _TvLeaderboardSignInGate(
              activeWatchLabel: widget.activeWatchLabel,
              onSignIn: widget.onSignIn,
            )
          else
            FutureBuilder<_TvLeaderboardResult?>(
              key: ValueKey(_scope),
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  _syncRowFocusNodes(1);
                  return Column(
                    children: [
                      _TvLeaderboardRankCard(
                        scope: _scope,
                        watchTimeLabel: widget.activeWatchLabel,
                        focusNode: _rankFocusNode,
                        onArrowUp: () => _focusScope(_selectedScopeIndex),
                        onArrowDown: () => _focusRow(0),
                      ),
                      const SizedBox(height: _tvSpacing),
                      Padding(
                        padding: const EdgeInsets.only(bottom: _tvSpacing),
                        child: _TvLeaderboardLoadingRow(
                          focusNode: _rowFocusNodes[0],
                          onArrowUp: _focusRank,
                          onArrowDown: () => _focusRow(0),
                        ),
                      ),
                    ],
                  );
                }
                if (snapshot.hasError || snapshot.data == null) {
                  _syncRowFocusNodes(0);
                  return Column(
                    children: [
                      _TvLeaderboardRankCard(
                        scope: _scope,
                        watchTimeLabel: widget.activeWatchLabel,
                        focusNode: _rankFocusNode,
                        onArrowUp: () => _focusScope(_selectedScopeIndex),
                        onArrowDown: () => _messageFocusNode.requestFocus(),
                      ),
                      const SizedBox(height: _tvSpacing),
                      _TvLeaderboardMessageRow(
                        icon: Icons.wifi_off_rounded,
                        message:
                            'Could not load rankings. Try again in a moment.',
                        focusNode: _messageFocusNode,
                        onArrowUp: _focusRank,
                        onArrowDown: () => _messageFocusNode.requestFocus(),
                      ),
                    ],
                  );
                }
                final result = snapshot.data!;
                _syncRowFocusNodes(result.rows.length);
                return Column(
                  children: [
                    _TvLeaderboardRankCard(
                      scope: _scope,
                      watchTimeLabel: widget.activeWatchLabel,
                      viewer: result.viewer,
                      focusNode: _rankFocusNode,
                      onArrowUp: () => _focusScope(_selectedScopeIndex),
                      onArrowDown: result.rows.isEmpty
                          ? () => _messageFocusNode.requestFocus()
                          : () => _focusRow(0),
                    ),
                    const SizedBox(height: _tvSpacing),
                    if (result.rows.isEmpty)
                      _TvLeaderboardMessageRow(
                        icon: Icons.emoji_events_outlined,
                        message: 'No opted-in viewers yet.',
                        focusNode: _messageFocusNode,
                        onArrowUp: _focusRank,
                        onArrowDown: () => _messageFocusNode.requestFocus(),
                      )
                    else
                      for (var index = 0; index < result.rows.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _tvSpacing),
                          child: _TvLeaderboardEntryRow(
                            entry: result.rows[index],
                            focusNode: _rowFocusNodes[index],
                            onArrowUp: index == 0
                                ? _focusRank
                                : () => _focusRow(index - 1),
                            onArrowDown: index == result.rows.length - 1
                                ? () => _focusRow(index)
                                : () => _focusRow(index + 1),
                          ),
                        ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _TvLeaderboardScopeButton extends StatelessWidget {
  const _TvLeaderboardScopeButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) {
        final fill = focused
            ? _tvAccentColor
            : selected
                ? _tvAccentColor.withValues(alpha: 0.22)
                : _tvTheme.row;
        final border = focused
            ? _tvSolidFocusBorder
            : selected
                ? _tvAccentColor
                : _tvTheme.rowBorder;
        return AnimatedContainer(
          duration: _tvDuration(140),
          height: 62,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: focused ? 2 : 1),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: focused ? Colors.black : _tvTheme.text,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TvLeaderboardSignInGate extends StatelessWidget {
  const _TvLeaderboardSignInGate({
    required this.activeWatchLabel,
    required this.onSignIn,
  });

  final String activeWatchLabel;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autoReveal: true,
      onPressed: onSignIn,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: focused ? _tvAccentColor : _tvTheme.row,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: focused ? _tvSolidFocusBorder : _tvTheme.rowBorder,
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_open_rounded,
                color: focused ? Colors.black : _tvAccentColor,
                size: 38,
              ),
              const SizedBox(width: _tvSpacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unlock leaderboard by signing in',
                      style: TextStyle(
                        color: focused ? Colors.black : _tvTheme.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: _tvSpacing),
                    Text(
                      'Create your account first, then choose whether to join rankings. Your active watch time is $activeWatchLabel on this TV.',
                      style: TextStyle(
                        color: focused
                            ? Colors.black.withValues(alpha: 0.72)
                            : _tvTheme.muted,
                        fontSize: 15,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: _tvSpacing),
              Icon(
                Icons.arrow_forward_rounded,
                color: focused ? Colors.black : _tvTheme.muted,
                size: 30,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvLeaderboardRankCard extends StatelessWidget {
  const _TvLeaderboardRankCard({
    required this.scope,
    required this.watchTimeLabel,
    this.viewer,
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  final String scope;
  final String watchTimeLabel;
  final _TvLeaderboardViewer? viewer;
  final FocusNode? focusNode;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autoReveal: true,
      focusNode: focusNode,
      onPressed: () {},
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) => AnimatedContainer(
        duration: _tvDuration(140),
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _tvTheme.row,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: focused ? _tvSolidFocusBorder : _tvTheme.rowBorder,
            width: focused ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.emoji_events_outlined, color: _tvAccentColor, size: 36),
            const SizedBox(width: _tvSpacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your rank',
                    style: TextStyle(
                      color: _tvTheme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: _tvSpacing),
                  Text(
                    _rankCopy(),
                    style: TextStyle(
                      color: _tvTheme.muted,
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
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

  String _rankCopy() {
    final placement = viewer;
    final label = _tvLeaderboardScopeLabel(scope).toLowerCase();
    if (placement == null) {
      return 'Your $label watch time is $watchTimeLabel on this TV. Public placement appears after account opt-in.';
    }
    if (!placement.optedIn) {
      return 'Choose a username, icon, and join from Account to appear here.';
    }
    if (placement.rank == null) {
      return 'Your $label watch time is ${_tvWatchTimeLabelForSeconds(placement.activeWatchSeconds)}. Keep watching to place on the board.';
    }
    return 'You are #${placement.rank} and ahead of ${placement.percentile}% of opted-in viewers for $label.';
  }
}

class _TvLeaderboardEntryRow extends StatelessWidget {
  const _TvLeaderboardEntryRow({
    required this.entry,
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  final _TvLeaderboardEntry entry;
  final FocusNode? focusNode;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autoReveal: true,
      focusNode: focusNode,
      onPressed: () {},
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) => AnimatedContainer(
        duration: _tvDuration(140),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: _tvTheme.row,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: focused ? _tvSolidFocusBorder : _tvTheme.rowBorder,
            width: focused ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 54,
              child: Text(
                '#${entry.rank}',
                style: TextStyle(
                  color: _tvTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: _tvSpacing),
            Text(
              entry.emoji.isEmpty ? '⭐' : entry.emoji,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: _tvSpacing),
            Expanded(
              child: Text(
                entry.username.isEmpty ? 'Viewer' : entry.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _tvTheme.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              _tvWatchTimeLabelForSeconds(entry.activeWatchSeconds),
              style: TextStyle(
                color: _tvTheme.muted,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvLeaderboardLoadingRow extends StatelessWidget {
  const _TvLeaderboardLoadingRow({
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  final FocusNode? focusNode;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autoReveal: true,
      focusNode: focusNode,
      onPressed: () {},
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) => AnimatedContainer(
        duration: _tvDuration(140),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _tvTheme.row,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: focused ? _tvSolidFocusBorder : _tvTheme.rowBorder,
            width: focused ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: _tvAccentColor,
              ),
            ),
            const SizedBox(width: _tvSpacing),
            Expanded(
              child: Text(
                'Loading leaderboard...',
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvLeaderboardMessageRow extends StatelessWidget {
  const _TvLeaderboardMessageRow({
    required this.icon,
    required this.message,
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  final IconData icon;
  final String message;
  final FocusNode? focusNode;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autoReveal: true,
      focusNode: focusNode,
      onPressed: () {},
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) => AnimatedContainer(
        duration: _tvDuration(140),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _tvTheme.row,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: focused ? _tvSolidFocusBorder : _tvTheme.rowBorder,
            width: focused ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: _tvAccentColor, size: 24),
            const SizedBox(width: _tvSpacing),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _tvLeaderboardScopeLabel(String scope) {
  return switch (_normalizeTvLeaderboardScope(scope)) {
    'today' => 'Today',
    'all' => 'All time',
    _ => 'Weekly',
  };
}

String _tvWatchTimeLabelForSeconds(int seconds) {
  final safeSeconds = math.max(0, seconds);
  final hours = safeSeconds ~/ 3600;
  final minutes = ((safeSeconds % 3600) / 60).ceil();
  if (hours <= 0) return '${minutes.clamp(0, 59)}m';
  if (hours < 24) return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  final days = hours ~/ 24;
  return '${days}d ${hours % 24}h';
}

class _TvEmptyCatalogState extends StatelessWidget {
  const _TvEmptyCatalogState({
    required this.title,
    required this.subtitle,
    this.height,
    this.focusNode,
    this.onFocusNavigation,
    this.onFocusHeader,
    // ignore: unused_element_parameter
    this.verticalOffset = _tvEmptyStateVisualOffset,
  });

  final String title;
  final String subtitle;
  final double? height;
  final FocusNode? focusNode;
  final VoidCallback? onFocusNavigation;
  final VoidCallback? onFocusHeader;
  final double verticalOffset;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Transform.translate(
        offset: Offset(0, verticalOffset),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _tvTheme.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final focusableContent = focusNode == null
        ? content
        : _TvFocusable(
            focusNode: focusNode,
            onPressed: () {},
            onArrowLeft: onFocusNavigation,
            onArrowUp: onFocusHeader,
            onArrowRight: () => focusNode!.requestFocus(),
            onArrowDown: () => focusNode!.requestFocus(),
            builder: (_) => content,
          );
    final targetHeight = height;
    if (targetHeight == null) return focusableContent;
    return SizedBox(
      height: targetHeight < 300 ? 300 : targetHeight,
      child: focusableContent,
    );
  }
}

class _TvCatalogLoadingState extends StatelessWidget {
  const _TvCatalogLoadingState({
    this.height,
  });

  final double? height;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Transform.translate(
        offset: const Offset(0, _tvEmptyStateVisualOffset),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: _tvAccentColor,
                  backgroundColor: const Color(0x22FFFFFF),
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                'Loading catalog data...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _tvTheme.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                'Fetching movies, series, and artwork for this source.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final targetHeight = height;
    if (targetHeight == null) return content;
    return SizedBox(
      height: targetHeight < 300 ? 300 : targetHeight,
      child: content,
    );
  }
}

class _TvResumePlaybackDialog extends StatefulWidget {
  const _TvResumePlaybackDialog({required this.progress});

  final _TvPlaybackProgress progress;

  @override
  State<_TvResumePlaybackDialog> createState() =>
      _TvResumePlaybackDialogState();
}

class _TvResumePlaybackDialogState extends State<_TvResumePlaybackDialog> {
  final FocusNode _dialogFocusNode = FocusNode(
    debugLabel: 'tv-resume-dialog',
  );
  final FocusNode _continueFocusNode = FocusNode(
    debugLabel: 'tv-resume-continue',
  );
  final FocusNode _startOverFocusNode = FocusNode(
    debugLabel: 'tv-resume-start-over',
  );

  @override
  void initState() {
    super.initState();
    _restoreContinueFocus();
  }

  void _restoreContinueFocus([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_continueFocusNode.hasFocus && !_startOverFocusNode.hasFocus) {
        _continueFocusNode.requestFocus();
      }
      if (attempt >= 2) return;
      Future<void>.delayed(
        const Duration(milliseconds: 60),
        () => _restoreContinueFocus(attempt + 1),
      );
    });
  }

  @override
  void dispose() {
    _dialogFocusNode.dispose();
    _continueFocusNode.dispose();
    _startOverFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _dialogFocusNode,
      descendantsAreFocusable: true,
      onFocusChange: (focused) {
        if (focused) _restoreContinueFocus();
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 330),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _tvTheme.dialog,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _tvTheme.rowBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Continue watching?',
                  style: TextStyle(
                    color: _tvTheme.text,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Resume from ${_formatDuration(widget.progress.position)} or start over.',
                  style: TextStyle(
                    color: _tvTheme.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TvTextButton(
                      icon: Icons.play_arrow_rounded,
                      label: 'Continue',
                      autofocus: true,
                      focusNode: _continueFocusNode,
                      minHeight: 40,
                      horizontalPadding: 11,
                      verticalPadding: 9,
                      iconSize: 18,
                      fontSize: 13,
                      onArrowRight: _startOverFocusNode.requestFocus,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                    const SizedBox(width: 8),
                    _TvTextButton(
                      icon: Icons.replay_rounded,
                      label: 'Start over',
                      focusNode: _startOverFocusNode,
                      minHeight: 40,
                      horizontalPadding: 11,
                      verticalPadding: 9,
                      iconSize: 18,
                      fontSize: 13,
                      onArrowLeft: _continueFocusNode.requestFocus,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvSettingsSurface extends StatelessWidget {
  const _TvSettingsSurface({
    required this.totalCount,
    required this.movieCount,
    required this.seriesCount,
    required this.animationCount,
    required this.hasCatalog,
    required this.accountSignedIn,
    required this.accountLabel,
    required this.accountSyncLabel,
    required this.recentCount,
    required this.savedCount,
    required this.completedCount,
    required this.activeWatchLabel,
    required this.settings,
    required this.onSettingsChanged,
    required this.onAccountSignIn,
    required this.onAccountSignOut,
    required this.onAccountSync,
    required this.onFocusNavigation,
    required this.onRefresh,
    required this.entryFocusNode,
    required this.onRememberFocus,
  });

  final int totalCount;
  final int movieCount;
  final int seriesCount;
  final int animationCount;
  final bool hasCatalog;
  final bool accountSignedIn;
  final String accountLabel;
  final String accountSyncLabel;
  final int recentCount;
  final int savedCount;
  final int completedCount;
  final String activeWatchLabel;
  final _TvSettingsState settings;
  final ValueChanged<_TvSettingsState> onSettingsChanged;
  final VoidCallback onAccountSignIn;
  final VoidCallback onAccountSignOut;
  final VoidCallback onAccountSync;
  final VoidCallback onFocusNavigation;
  final VoidCallback onRefresh;
  final FocusNode entryFocusNode;
  final ValueChanged<FocusNode> onRememberFocus;

  @override
  Widget build(BuildContext context) {
    final sections = [
      const _TvSettingsSection(
        'General',
        'Theme, accent, text size, motion, and TV home preferences.',
        Icons.settings_rounded,
        [
          _TvSettingsLine(
            'Appearance',
            'Use the TV visual style tuned for large screens and remote viewing.',
          ),
          _TvSettingsLine(
            'Text size',
            'Large readable labels stay enabled for living-room distance.',
          ),
          _TvSettingsLine(
            'Home experience',
            'Home uses shared editorial curation with TV-safe fallbacks.',
          ),
        ],
      ),
      const _TvSettingsSection(
        'Playback',
        'Player defaults, captions, quality, and watch behavior.',
        Icons.play_circle_fill_rounded,
        [
          _TvSettingsLine(
            'Playback engine',
            'Auto chooses the safest available TV playback choice.',
          ),
          _TvSettingsLine(
            'Preferred quality',
            'TV playback starts with a balanced quality target.',
          ),
          _TvSettingsLine(
            'Subtitles',
            'Captions stay readable and can be refined in playback settings.',
          ),
          _TvSettingsLine(
            'Continue watching',
            'Progress is kept for the current TV session.',
          ),
          _TvSettingsLine(
            'Next episode',
            'Series playback can continue from the playback HUD.',
          ),
        ],
      ),
      const _TvSettingsSection(
        'Sources',
        'Built-in tools, add-ons, and source choices you control.',
        Icons.extension_rounded,
        [
          _TvSettingsLine(
            'Default',
            'Built-in catalog, subtitles, trailers, Live TV, and playback stay grouped.',
          ),
          _TvSettingsLine(
            'Add-ons',
            'Saved add-on links stay manageable by safe labels only.',
          ),
          _TvSettingsLine(
            'Safety',
            'Only add links you trust; Juicr does not review third-party services.',
          ),
        ],
      ),
      const _TvSettingsSection(
        'Advanced',
        'Advanced playback controls and source priority preferences.',
        Icons.admin_panel_settings_outlined,
        [
          _TvSettingsLine(
            'Advanced P2P playback',
            'Configure consent-guarded P2P playback and source priority controls.',
          ),
        ],
      ),
      _TvSettingsSection(
        'Account & Library',
        accountSignedIn
            ? '$accountLabel - $accountSyncLabel'
            : 'Sign in, library sync, saved titles, and watch time.',
        Icons.account_circle_rounded,
        [
          _TvSettingsLine(
            accountSignedIn ? 'Signed in' : 'Sign in to Juicr',
            accountSignedIn
                ? 'Library sync is available for this TV.'
                : 'Use email sign-in when you want account features.',
          ),
          const _TvSettingsLine(
            'Library sync',
            'Saved titles and watch progress can follow your account.',
          ),
          _TvSettingsLine(
            'Local library',
            '$savedCount saved, $recentCount recent, $completedCount completed.',
          ),
          _TvSettingsLine('Active watch time', activeWatchLabel),
          const _TvSettingsLine(
            'Privacy',
            'Your account session stays in secure TV storage.',
          ),
        ],
      ),
      _TvSettingsSection(
        'About & Diagnostics',
        'Juicr TV $_tvAppVersion+$_tvAppBuildNumber - ${_tvBuildChannelLabel(_tvReleaseChannelForVersion(_tvAppVersion))} build.',
        Icons.info_rounded,
        [
          const _TvSettingsLine(
            'Version',
            'Installed TV app version and build channel.',
          ),
          _TvSettingsLine(
            'Catalog',
            hasCatalog
                ? '$totalCount titles loaded: $movieCount movies, $seriesCount series, $animationCount animations.'
                : 'Catalog is ready to refresh when your connection is available.',
          ),
          const _TvSettingsLine(
            'Updates',
            'Check release notes and current Android TV downloads.',
          ),
          const _TvSettingsLine(
            'Diagnostics',
            'Send a private support ticket with redacted TV status only.',
          ),
        ],
      ),
    ];
    return _TvSettingsGrid(
      sections: sections,
      entryFocusNode: entryFocusNode,
      onFocusNavigation: onFocusNavigation,
      onOpenSection: (section, originFocusNode) =>
          _showTvSettingsSection(context, section, originFocusNode),
      onRememberFocus: onRememberFocus,
    );
  }

  Future<void> _showTvSettingsSection(
    BuildContext context,
    _TvSettingsSection section,
    FocusNode originFocusNode,
  ) async {
    if (section.title == 'Account & Library') {
      onAccountSignIn();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (originFocusNode.canRequestFocus) {
          originFocusNode.requestFocus();
        }
      });
      return;
    }
    final sectionSettings = settings;
    if (!context.mounted) return;
    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) => _TvSettingsSectionDialog(
        section: section,
        settings: sectionSettings,
        accountSignedIn: accountSignedIn,
        accountLabel: accountLabel,
        accountSyncLabel: accountSyncLabel,
        recentCount: recentCount,
        savedCount: savedCount,
        completedCount: completedCount,
        activeWatchLabel: activeWatchLabel,
        onAccountSignIn: onAccountSignIn,
        onAccountSignOut: onAccountSignOut,
        onAccountSync: onAccountSync,
        onSettingsChanged: onSettingsChanged,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (originFocusNode.canRequestFocus) {
        originFocusNode.requestFocus();
      }
    });
  }
}

class _TvSettingsGrid extends StatefulWidget {
  const _TvSettingsGrid({
    required this.sections,
    required this.entryFocusNode,
    required this.onFocusNavigation,
    required this.onOpenSection,
    required this.onRememberFocus,
  });

  final List<_TvSettingsSection> sections;
  final FocusNode entryFocusNode;
  final VoidCallback onFocusNavigation;
  final void Function(_TvSettingsSection section, FocusNode originFocusNode)
      onOpenSection;
  final ValueChanged<FocusNode> onRememberFocus;

  @override
  State<_TvSettingsGrid> createState() => _TvSettingsGridState();
}

class _TvSettingsGridState extends State<_TvSettingsGrid> {
  static const _columnCount = 2;
  final _nodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncNodes();
  }

  @override
  void didUpdateWidget(covariant _TvSettingsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sections.length != widget.sections.length) {
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
    while (_nodes.length > widget.sections.length) {
      _nodes.removeLast().dispose();
    }
    while (_nodes.length < widget.sections.length) {
      final index = _nodes.length;
      _nodes.add(FocusNode(debugLabel: 'tv-settings-card-$index'));
    }
  }

  FocusNode _nodeFor(int index) {
    if (index == 0) return widget.entryFocusNode;
    return _nodes[index];
  }

  void _focusIndex(int index, {double alignment = 0.34}) {
    if (index < 0 || index >= widget.sections.length) return;
    final node = _nodeFor(index);
    widget.onRememberFocus(node);
    node.requestFocus();
    _revealIndex(index, alignment: alignment);
  }

  void _revealIndex(int index, {double alignment = 0.34}) {
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;
        final cardWidth = (constraints.maxWidth - gap) / _columnCount;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var index = 0; index < widget.sections.length; index++)
              _TvSettingsHomeCard(
                section: widget.sections[index],
                width: cardWidth,
                focusNode: _nodeFor(index),
                autoReveal: false,
                onFocus: () {
                  widget.onRememberFocus(_nodeFor(index));
                  _revealIndex(index);
                },
                onArrowLeft: index % _columnCount == 0
                    ? widget.onFocusNavigation
                    : () => _focusIndex(index - 1),
                onArrowRight: index + 1 < widget.sections.length &&
                        index % _columnCount != _columnCount - 1
                    ? () => _focusIndex(index + 1)
                    : () => _focusIndex(index),
                onArrowUp: index - _columnCount >= 0
                    ? () => _focusIndex(index - _columnCount, alignment: 0.2)
                    : () => _focusIndex(index, alignment: 0.2),
                onArrowDown: index + _columnCount < widget.sections.length
                    ? () => _focusIndex(index + _columnCount, alignment: 0.56)
                    : () => _focusIndex(index, alignment: 0.56),
                onPressed: () => widget.onOpenSection(
                  widget.sections[index],
                  _nodeFor(index),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TvSettingsHomeCard extends StatelessWidget {
  const _TvSettingsHomeCard({
    required this.section,
    required this.onPressed,
    required this.width,
    this.autoReveal = true,
    this.focusNode,
    this.onFocus,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
  });

  final _TvSettingsSection section;
  final VoidCallback onPressed;
  final double width;
  final bool autoReveal;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: _TvFocusable(
        focusNode: focusNode,
        autoReveal: autoReveal,
        onPressed: onPressed,
        onArrowLeft: onArrowLeft,
        onArrowRight: onArrowRight,
        onArrowUp: onArrowUp,
        onArrowDown: onArrowDown,
        onFocus: onFocus,
        builder: (focused) {
          return AnimatedContainer(
            duration: _tvDuration(140),
            constraints: const BoxConstraints(minHeight: 104),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: focused ? _tvAccentColor : _tvTheme.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: focused ? _tvSolidFocusBorder : _tvTheme.rowBorder,
                width: focused ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      section.icon,
                      color: focused ? Colors.black : _tvAccentColor,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        section.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: focused ? Colors.black : _tvTheme.text,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: focused ? Colors.black : _tvTheme.muted,
                      size: 26,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  section.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: focused
                        ? Colors.black.withValues(alpha: 0.72)
                        : _tvTheme.muted,
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TvSettingsSectionDialog extends StatefulWidget {
  const _TvSettingsSectionDialog({
    required this.section,
    required this.settings,
    required this.accountSignedIn,
    required this.accountLabel,
    required this.accountSyncLabel,
    required this.recentCount,
    required this.savedCount,
    required this.completedCount,
    required this.activeWatchLabel,
    required this.onAccountSignIn,
    required this.onAccountSignOut,
    required this.onAccountSync,
    required this.onSettingsChanged,
  });

  final _TvSettingsSection section;
  final _TvSettingsState settings;
  final bool accountSignedIn;
  final String accountLabel;
  final String accountSyncLabel;
  final int recentCount;
  final int savedCount;
  final int completedCount;
  final String activeWatchLabel;
  final VoidCallback onAccountSignIn;
  final VoidCallback onAccountSignOut;
  final VoidCallback onAccountSync;
  final ValueChanged<_TvSettingsState> onSettingsChanged;

  @override
  State<_TvSettingsSectionDialog> createState() =>
      _TvSettingsSectionDialogState();
}

class _TvSettingsSectionDialogState extends State<_TvSettingsSectionDialog> {
  final FocusNode _firstActionFocusNode = FocusNode(
    debugLabel: 'tv-settings-dialog-first',
  );
  final List<FocusNode> _actionFocusNodes = <FocusNode>[];
  FocusNode? _lastActionFocusNode;

  late _TvSettingsState _current = widget.settings;

  @override
  void initState() {
    super.initState();
    _restoreInitialActionFocus();
  }

  @override
  void dispose() {
    _firstActionFocusNode.dispose();
    for (final node in _actionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncActionFocusNodes(int count) {
    final extraCount = math.max(0, count - 1);
    while (_actionFocusNodes.length > extraCount) {
      _actionFocusNodes.removeLast().dispose();
    }
    while (_actionFocusNodes.length < extraCount) {
      final index = _actionFocusNodes.length + 1;
      _actionFocusNodes.add(FocusNode(debugLabel: 'tv-settings-action-$index'));
    }
  }

  FocusNode _actionNode(int index) {
    if (index == 0) return _firstActionFocusNode;
    return _actionFocusNodes[index - 1];
  }

  void _rememberActionFocus(FocusNode node) {
    _lastActionFocusNode = node;
  }

  bool get _hasDialogActionFocus {
    return _firstActionFocusNode.hasFocus ||
        _actionFocusNodes.any((node) => node.hasFocus);
  }

  void _restoreInitialActionFocus([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (!_hasDialogActionFocus) {
        _focusAction(0);
      }
      if (!_hasDialogActionFocus && attempt < 6) {
        Future<void>.delayed(
          Duration(milliseconds: 80 + attempt * 60),
          () => _restoreInitialActionFocus(attempt + 1),
        );
      }
    });
  }

  void _focusAction(int index) {
    final node = _actionNode(index);
    _rememberActionFocus(node);
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(150),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  void _restoreLastActionFocus({bool reveal = true}) {
    final node = _lastActionFocusNode ?? _firstActionFocusNode;
    void focusIfReady() {
      if (!mounted || !node.canRequestFocus) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      node.requestFocus();
      if (!reveal) return;
      final nodeContext = node.context;
      if (nodeContext == null) return;
      Scrollable.ensureVisible(
        nodeContext,
        duration: _tvDuration(160),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => focusIfReady());
    Future<void>.delayed(const Duration(milliseconds: 120), focusIfReady);
    Future<void>.delayed(const Duration(milliseconds: 420), focusIfReady);
  }

  void _update(_TvSettingsState next) {
    _applyTvSettingsGlobals(next);
    setState(() => _current = next);
    widget.onSettingsChanged(next);
    _restoreLastActionFocus(reveal: false);
  }

  Future<String?> _pickOption(
    BuildContext context, {
    required String title,
    required String selected,
    required List<String> options,
  }) async {
    final result = await _showTvDialog<String>(
      context: context,
      builder: (dialogContext) => _TvSettingsOptionDialog(
        title: title,
        selected: selected,
        options: options,
      ),
    );
    _restoreLastActionFocus();
    return result;
  }

  Future<_TvAccentSelection?> _pickAccent(
    BuildContext context,
    _TvSettingsState current,
  ) async {
    final selected = await _showTvDialog<_TvAccentSelection>(
      context: context,
      builder: (dialogContext) => _TvAccentPickerDialog(settings: current),
    );
    _restoreLastActionFocus();
    if (selected == null || selected.accent != 'Custom') return selected;
    if (!context.mounted) return selected;
    final color = await _showTvDialog<Color>(
      context: context,
      builder: (dialogContext) =>
          _TvCustomAccentDialog(initialColor: Color(current.customAccentColor)),
    );
    _restoreLastActionFocus();
    if (color == null) return null;
    return _TvAccentSelection('Custom', color);
  }

  Future<void> _openSubtitleStyleSettings(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update,
  ) async {
    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _TvSubtitleStyleDialog(settings: current, onSettingsChanged: update),
    );
    _restoreLastActionFocus();
  }

  Future<void> _showStatusDialog(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.info_outline_rounded,
  }) async {
    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 180, vertical: 80),
        child: Container(
          width: 620,
          padding: const EdgeInsets.all(_tvSpacing),
          decoration: BoxDecoration(
            color: _tvTheme.dialog,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _tvTheme.rowBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: _tvAccentColor, size: 32),
              const SizedBox(height: _tvSpacing),
              Text(
                title,
                style: TextStyle(
                  color: _tvTheme.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                message,
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Align(
                alignment: Alignment.centerRight,
                child: _TvTextButton(
                  icon: Icons.check_rounded,
                  label: 'OK',
                  autofocus: true,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _restoreLastActionFocus();
  }

  Future<void> _openAboutDialog(BuildContext context) async {
    final channel = _tvReleaseChannelForVersion(_tvAppVersion);
    final snapshot = _fallbackTvReleaseSnapshot(channel);
    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) => _TvAboutDialog(snapshot: snapshot),
    );
    _restoreLastActionFocus();
  }

  Future<void> _openUpdatesDialog(BuildContext context) async {
    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) => _TvUpdatesDialog(
        initialSnapshot: _fallbackTvReleaseSnapshot(
          _tvReleaseChannelForVersion(_tvAppVersion),
        ),
        onOpenDownload: _openDownloadLink,
      ),
    );
    _restoreLastActionFocus();
  }

  Future<void> _openDownloadLink(Uri uri) async {
    var opened = false;
    try {
      opened = await _tvQuickLinkChannel.invokeMethod<bool>('open', {
            'url': uri.toString(),
          }) ??
          false;
    } on MissingPluginException {
      opened = false;
    } on PlatformException {
      opened = false;
    }
    if (!mounted) return;
    if (opened) {
      _snack('Opening download.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    _snack('Download link copied.');
  }

  Future<void> _openDiagnosticConsent(BuildContext context) async {
    final sent = await _showTvDialog<bool>(
      context: context,
      builder: (dialogContext) => _TvDiagnosticConsentDialog(
        onSend: () async {
          final ticketId = await _TvApi().sendDiagnosticReport(
            _buildTvDiagnosticReport(),
          );
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).pop(true);
          }
          if (!mounted) return;
          _snack('Diagnostic sent: $ticketId');
        },
      ),
    );
    _restoreLastActionFocus();
    if (sent == true) return;
  }

  _TvReleaseUpdatesSnapshot _fallbackTvReleaseSnapshot(
    _TvReleaseUpdateChannel channel,
  ) {
    return _TvReleaseUpdatesSnapshot(
      installedVersion: _tvAppVersion,
      installedCode: _tvAppBuildNumber,
      channel: channel,
      latest: _fallbackTvReleaseInfo(channel),
    );
  }

  String _buildTvDiagnosticReport() {
    final channel = _tvReleaseChannelForVersion(_tvAppVersion);
    final enabledAddOns = _current.userAddOns.where((addon) => addon.enabled);
    final lines = <String>[
      'Juicr TV diagnostic report',
      'Schema: juicr.tv.diagnostic.v1',
      'Generated: ${DateTime.now().toUtc().toIso8601String()}',
      'App: $_tvAppVersion+$_tvAppBuildNumber',
      'Build channel: ${_tvBuildChannelLabel(channel)}',
      'Package: $_tvAppPackageName',
      'Account signed in: ${widget.accountSignedIn}',
      'Account sync: ${widget.accountSyncLabel}',
      'Library counts: recent=${widget.recentCount}, saved=${widget.savedCount}, completed=${widget.completedCount}',
      'Active watch time: ${widget.activeWatchLabel}',
      'Theme: ${_current.theme}',
      'Accent: ${_current.accent == 'Custom' ? 'Custom' : _current.accent}',
      'Text size: ${_current.textSize}',
      'Motion: ${_current.motion ? 'Full' : 'Reduced'}',
      'Built-in tools enabled: ${_current.builtInCatalog || _current.builtInSubtitles || _current.builtInTrailers || _current.builtInLiveTv || _current.builtInPlayback}',
      'Saved add-ons: ${_current.userAddOns.length}',
      'Enabled add-ons: ${enabledAddOns.length}',
      'Advanced P2P consent: ${_current.hasP2pConsent}',
      'Advanced P2P playback: ${_current.p2pPlaybackEnabled}',
      'Advanced source priorities: ${_current.p2pSourcePrioritiesEnabled}',
      'Playback engine: ${_current.playbackEngine}',
      'Preferred quality: ${_current.preferredQuality}',
      'Diagnostics redaction: counts_and_status_buckets_only',
      'Private playback, source, account secrets, add-on links, URLs, tokens, headers, and local paths are not included.',
    ];
    return lines.join('\n');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1600),
        ),
      );
  }

  Future<bool> _confirmBuiltInConsent(
    BuildContext context,
    _TvSettingsState current,
  ) async {
    if (current.defaultSourceConsentAccepted) return true;
    final accepted = await _showTvDialog<bool>(
      context: context,
      builder: (dialogContext) => const _TvConsentDialog(
        title: 'Enable built-in tools?',
        intro:
            'Before Juicr turns these optional tools on, confirm each acknowledgement. Juicr provides the app tools; you choose what to enable and use.',
        confirmLabel: 'Enable tools',
        acknowledgements: [
          _TvConsentAcknowledgement(
            'Juicr does not provide media',
            'Built-in browsing and playback tools are optional and remain under your control.',
          ),
          _TvConsentAcknowledgement(
            'Use only allowed content',
            'You are responsible for subscriptions, permissions, local laws, and what you choose to access.',
          ),
          _TvConsentAcknowledgement(
            'No bypassing access controls',
            'Juicr does not bypass DRM, paywalls, access protections, geoblocks, subscriptions, or other controls.',
          ),
        ],
      ),
    );
    _restoreLastActionFocus();
    return accepted == true;
  }

  Future<bool> _confirmAddOnConsent(
    BuildContext context,
    _TvSettingsState current,
  ) async {
    if (current.addOnConsentAccepted) return true;
    final accepted = await _showTvDialog<bool>(
      context: context,
      builder: (dialogContext) => const _TvConsentDialog(
        title: 'Add third-party add-on?',
        intro:
            'Add-ons are links you choose. Juicr does not review, control, or endorse third-party add-ons.',
        confirmLabel: 'I understand',
        acknowledgements: [
          _TvConsentAcknowledgement(
            'Only add links you trust',
            'Add-ons may contact outside services, and those services may see network information such as your IP address.',
          ),
          _TvConsentAcknowledgement(
            'Use only allowed content',
            'Only use add-ons for content you are legally allowed to access in your region.',
          ),
          _TvConsentAcknowledgement(
            'No bypassing access controls',
            'Do not use add-ons to bypass DRM, paywalls, access protections, geoblocks, subscriptions, or other controls.',
          ),
        ],
      ),
    );
    _restoreLastActionFocus();
    return accepted == true;
  }

  Future<void> _openDefaultSources(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update,
  ) async {
    if (!await _confirmBuiltInConsent(context, current)) return;
    final consented = current.copyWith(defaultSourceConsentAccepted: true);
    update(consented);
    if (!context.mounted) return;
    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) => _TvDefaultSourceDialog(
        settings: consented,
        onSettingsChanged: update,
      ),
    );
    _restoreLastActionFocus();
  }

  Future<void> _openUserAddOn(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update,
    _TvUserAddOn addon,
  ) async {
    var dialogState = current;
    bool sameAddon(_TvUserAddOn candidate) {
      return candidate.id == addon.id;
    }

    void updateDialogState(_TvSettingsState next) {
      dialogState = next;
      update(next);
    }

    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) => _TvUserAddOnDialog(
        addon: addon,
        onEnabledChanged: (enabled) {
          updateDialogState(
            dialogState.copyWith(
              userAddOns: [
                for (final candidate in dialogState.userAddOns)
                  sameAddon(candidate)
                      ? candidate.copyWith(enabled: enabled)
                      : candidate,
              ],
            ),
          );
        },
        onRemove: () {
          Navigator.of(dialogContext).pop();
          updateDialogState(
            dialogState.copyWith(
              userAddOns: [
                for (final candidate in dialogState.userAddOns)
                  if (!sameAddon(candidate)) candidate,
              ],
            ),
          );
        },
      ),
    );
    _restoreLastActionFocus();
  }

  Future<void> _addUserAddOn(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update, {
    bool openAfterSave = true,
    bool restoreLauncherFocus = true,
  }) async {
    if (!await _confirmAddOnConsent(context, current)) return;
    if (!mounted) return;
    if (!context.mounted) return;
    final consented = current.copyWith(addOnConsentAccepted: true);
    update(consented);
    final added = await _showTvDialog<_TvUserAddOn>(
      context: context,
      builder: (dialogContext) => const _TvAddOnEntryDialog(),
    );
    if (restoreLauncherFocus) {
      _restoreLastActionFocus();
    }
    if (added == null) return;
    final next = consented.copyWith(
      userAddOns: [...consented.userAddOns, added],
    );
    update(next);
    if (!context.mounted) return;
    if (openAfterSave) {
      await _openUserAddOn(context, next, update, added);
    }
  }

  Future<void> _openUserAddOnManager(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update,
  ) async {
    var dialogState = current;

    void updateDialogState(_TvSettingsState next) {
      dialogState = next;
      update(next);
    }

    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) => _TvUserAddOnManagerDialog(
        settings: dialogState,
        onAddAddOn: () async {
          await _addUserAddOn(
            dialogContext,
            dialogState,
            updateDialogState,
            openAfterSave: false,
            restoreLauncherFocus: false,
          );
          return dialogState;
        },
        onOpenAddOn: (addon) async {
          await _openUserAddOn(
            dialogContext,
            dialogState,
            updateDialogState,
            addon,
          );
          return dialogState;
        },
      ),
    );
    _restoreLastActionFocus();
  }

  Future<void> _showAdvancedP2pNeedsAddOn(BuildContext context) async {
    await _showStatusDialog(
      context,
      title: 'Advanced P2P playback',
      message:
          'Add and enable at least one add-on before turning on Advanced P2P playback.',
      icon: Icons.extension_rounded,
    );
  }

  Future<bool> _confirmTvP2pConsent(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update,
  ) async {
    if (current.hasP2pConsent) return true;
    final accepted = await _showTvDialog<bool>(
      context: context,
      builder: (dialogContext) => const _TvConsentDialog(
        title: 'Heavy P2P consent',
        intro:
            'Advanced P2P playback is user-controlled. Juicr does not provide content or legal permission. Continue only if you understand the risks and will use sources you are allowed to access.',
        confirmLabel: 'Save P2P consent',
        acknowledgements: [
          _TvConsentAcknowledgement(
            'Juicr does not provide content',
            'Juicr does not provide, host, promote, or endorse P2P content, media goods, or legal permission.',
          ),
          _TvConsentAcknowledgement(
            'I choose my own sources',
            'I am responsible for the add-ons, sources, and media I choose to use.',
          ),
          _TvConsentAcknowledgement(
            'Network visibility',
            'P2P can expose network information to peers and may be visible to my network provider.',
          ),
          _TvConsentAcknowledgement(
            'Resource usage',
            'P2P depends on availability and can use more bandwidth, battery, and storage.',
          ),
          _TvConsentAcknowledgement(
            'TV add-ons are required',
            'Advanced P2P playback on TV only applies to enabled user add-ons.',
          ),
        ],
      ),
    );
    _restoreLastActionFocus();
    if (accepted != true) return false;
    final consented = current.copyWith(
      p2pPlaybackConsentAccepted: true,
      p2pPlaybackConsentVersion: kTvP2pConsentVersion,
      p2pPlaybackConsentAcceptedAt: DateTime.now().toUtc().toIso8601String(),
    );
    update(consented);
    return true;
  }

  Future<void> _openAdvancedP2pPlayback(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update,
  ) async {
    if (!await _confirmTvP2pConsent(context, current, update)) return;
    if (!context.mounted) return;
    final latest = _current.hasP2pConsent ? _current : current;
    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) => _TvSettingsSectionDialog(
        section: const _TvSettingsSection(
          'Advanced P2P playback',
          'Consent-guarded P2P playback and source priority controls.',
          Icons.hub_outlined,
          [
            _TvSettingsLine(
              'Advanced P2P playback',
              'P2P playback stays behind heavy consent and enabled add-ons.',
            ),
            _TvSettingsLine(
              'Advanced source priorities',
              'Priority tuning stays separate from the P2P playback switch.',
            ),
          ],
        ),
        settings: latest,
        accountSignedIn: widget.accountSignedIn,
        accountLabel: widget.accountLabel,
        accountSyncLabel: widget.accountSyncLabel,
        recentCount: widget.recentCount,
        savedCount: widget.savedCount,
        completedCount: widget.completedCount,
        activeWatchLabel: widget.activeWatchLabel,
        onAccountSignIn: widget.onAccountSignIn,
        onAccountSignOut: widget.onAccountSignOut,
        onAccountSync: widget.onAccountSync,
        onSettingsChanged: update,
      ),
    );
    _restoreLastActionFocus();
  }

  Future<void> _openP2pSourcePriorities(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update,
  ) async {
    var dialogState = current;

    void updateDialogState(_TvSettingsState next) {
      dialogState = next;
      update(next);
    }

    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) => _TvP2pSourcePrioritiesDialog(
        settings: dialogState,
        onSettingsChanged: updateDialogState,
      ),
    );
    _restoreLastActionFocus();
  }

  List<_TvSettingsAction> _actions(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update,
  ) {
    switch (widget.section.title) {
      case 'General':
        return [
          _TvSettingsAction(
            title: 'Theme',
            subtitle: 'Choose how the TV shell should appear.',
            value: current.theme,
            icon: Icons.contrast_rounded,
            onPressed: () => unawaited(() async {
              final selected = await _pickOption(
                context,
                title: 'Theme',
                selected: current.theme,
                options: const ['System', 'Light', 'Dark', 'Amoled Black'],
              );
              if (selected != null) update(current.copyWith(theme: selected));
            }()),
          ),
          _TvSettingsAction(
            title: 'App color accent',
            subtitle:
                'Choose the highlight color used for focus and selected controls.',
            value: current.accent,
            icon: Icons.palette_rounded,
            onPressed: () => unawaited(() async {
              final selected = await _pickAccent(context, current);
              if (selected != null) {
                update(
                  current.copyWith(
                    accent: selected.accent,
                    customAccentColor: selected.color.toARGB32(),
                  ),
                );
              }
            }()),
          ),
          _TvSettingsAction(
            title: 'Text size',
            subtitle: 'Scale labels for living-room readability.',
            value: current.textSize,
            icon: Icons.text_fields_rounded,
            onPressed: () => unawaited(() async {
              final selected = await _pickOption(
                context,
                title: 'Text size',
                selected: current.textSize,
                options: const [
                  'Smaller',
                  'Default',
                  'Large',
                  'Larger',
                  'Maximum',
                ],
              );
              if (selected != null) {
                update(current.copyWith(textSize: selected));
              }
            }()),
          ),
          _TvSettingsAction(
            title: 'Motion',
            subtitle:
                'Keep TV transitions smooth without making navigation noisy.',
            value: current.motion ? 'Full' : 'Reduced',
            icon: Icons.animation_rounded,
            onPressed: () => unawaited(() async {
              final selected = await _pickOption(
                context,
                title: 'Motion',
                selected: current.motion ? 'Full' : 'Reduced',
                options: const ['Full', 'Reduced'],
              );
              if (selected != null) {
                update(current.copyWith(motion: selected == 'Full'));
              }
            }()),
          ),
        ];
      case 'Playback':
        return [
          _TvSettingsAction(
            title: 'Playback engine',
            subtitle: 'Choose how this TV starts playback.',
            value: current.playbackEngine,
            icon: Icons.memory_rounded,
            onPressed: () => unawaited(() async {
              final selected = await _pickOption(
                context,
                title: 'Playback engine',
                selected: current.playbackEngine,
                options: const ['Auto', 'Native', 'Compatibility'],
              );
              if (selected != null) {
                update(current.copyWith(playbackEngine: selected));
              }
            }()),
          ),
          _TvSettingsAction(
            title: 'Preferred quality',
            subtitle:
                'Choose the default quality target before playback starts.',
            value: current.preferredQuality,
            icon: Icons.high_quality_rounded,
            onPressed: () => unawaited(() async {
              final selected = await _pickOption(
                context,
                title: 'Preferred quality',
                selected: current.preferredQuality,
                options: const ['Balanced', 'Best available', 'Data saver'],
              );
              if (selected != null) {
                update(current.copyWith(preferredQuality: selected));
              }
            }()),
          ),
          _TvSettingsAction(
            title: 'Resume prompt',
            subtitle:
                'Ask whether to continue or start over when progress is saved.',
            value: current.resumePrompt ? 'Ask' : 'Start over',
            icon: Icons.restore_rounded,
            onPressed: () =>
                update(current.copyWith(resumePrompt: !current.resumePrompt)),
          ),
          _TvSettingsAction(
            title: 'Subtitles',
            subtitle:
                'Show TV-readable captions when subtitle data is available.',
            value: current.subtitles ? 'On' : 'Off',
            icon: Icons.closed_caption_rounded,
            onPressed: () =>
                update(current.copyWith(subtitles: !current.subtitles)),
          ),
          _TvSettingsAction(
            title: 'Subtitle style',
            subtitle: 'Configure caption size, color, background, and delay.',
            value: 'Configure',
            icon: Icons.format_color_text_rounded,
            onPressed: () =>
                unawaited(_openSubtitleStyleSettings(context, current, update)),
          ),
          _TvSettingsAction(
            title: 'Next episode',
            subtitle:
                'Keep series continuation controls available in the playback HUD.',
            value: current.nextEpisode ? 'On' : 'Off',
            icon: Icons.skip_next_rounded,
            onPressed: () =>
                update(current.copyWith(nextEpisode: !current.nextEpisode)),
          ),
        ];
      case 'Sources':
        final builtInCount = current.enabledBuiltInSourceCount;
        return [
          _TvSettingsAction(
            title: 'Default',
            subtitle:
                'Open built-in catalog, subtitles, trailers, Live TV, and playback controls.',
            value: !current.defaultSourceConsentAccepted
                ? 'Consent'
                : builtInCount == 0
                    ? 'Off'
                    : builtInCount == _TvSettingsState.builtInSourceCount
                        ? 'Active'
                        : 'Partial',
            icon: Icons.inventory_2_outlined,
            onPressed: () =>
                unawaited(_openDefaultSources(context, current, update)),
          ),
          _TvSettingsAction(
            title: 'Add-on',
            subtitle:
                'Add or manage trusted add-on links for TV-side management.',
            value: current.userAddOns.isEmpty
                ? 'None'
                : '${current.userAddOns.length} saved',
            icon: Icons.add_link_rounded,
            onPressed: () =>
                unawaited(_openUserAddOnManager(context, current, update)),
          ),
        ];
      case 'Advanced':
        return [
          _TvSettingsAction(
            title: 'Advanced P2P playback',
            subtitle:
                'Configure consent-guarded P2P playback and source priority controls.',
            value: 'Configure',
            icon: Icons.hub_outlined,
            onPressed: () =>
                unawaited(_openAdvancedP2pPlayback(context, current, update)),
          ),
        ];
      case 'Advanced P2P playback':
        return [
          _TvSettingsAction(
            title: 'Advanced P2P playback',
            subtitle:
                'Consent-guarded P2P playback for enabled add-ons.',
            value: !current.hasUserAddOns
                ? 'Add-on'
                : current.p2pPlaybackEnabled
                    ? 'On'
                    : 'Off',
            icon: Icons.hub_outlined,
            onPressed: () => current.hasUserAddOns
                ? update(
                    current.copyWith(
                      p2pPlaybackEnabled: !current.p2pPlaybackEnabled,
                    ),
                  )
                : unawaited(_showAdvancedP2pNeedsAddOn(context)),
          ),
          _TvSettingsAction(
            title: 'Advanced source priorities',
            subtitle: current.p2pPlaybackEnabled
                ? 'Tune source priority for enabled add-ons.'
                : 'Turn on Advanced P2P playback to tune source choice.',
            value: current.p2pPlaybackEnabled ? 'Configure' : 'Locked',
            icon: current.p2pPlaybackEnabled
                ? Icons.low_priority_rounded
                : Icons.lock_outline,
            onPressed: () {
              if (!current.p2pPlaybackEnabled) return;
              unawaited(_openP2pSourcePriorities(context, current, update));
            },
          ),
        ];
      case 'Account & Library':
        return [
          _TvSettingsAction(
            title: widget.accountSignedIn
                ? 'Signed in to Juicr'
                : 'Sign in to Juicr',
            subtitle: widget.accountSignedIn
                ? 'Saved titles and watch progress can sync with your account.'
                : 'Use email sign-in when you want account features. Guest mode stays available.',
            value: widget.accountSignedIn ? widget.accountLabel : 'Guest',
            icon: widget.accountSignedIn
                ? Icons.account_circle_rounded
                : Icons.account_circle_outlined,
            onPressed: widget.accountSignedIn
                ? widget.onAccountSync
                : widget.onAccountSignIn,
          ),
          _TvSettingsAction(
            title: 'Library sync',
            subtitle: widget.accountSignedIn
                ? 'Pull and push saved titles, continue watching, and safe watch-time totals.'
                : 'Library sync starts after sign-in.',
            value: widget.accountSignedIn ? widget.accountSyncLabel : 'Sign in',
            icon: Icons.sync_rounded,
            onPressed: widget.accountSignedIn
                ? widget.onAccountSync
                : widget.onAccountSignIn,
          ),
          _TvSettingsAction(
            title: 'Saved titles',
            subtitle:
                'Titles saved on this TV stay available in Library and can sync after sign-in.',
            value: '${widget.savedCount}',
            icon: Icons.favorite_rounded,
            onPressed: () => unawaited(
              _showStatusDialog(
                context,
                title: 'Saved titles',
                message:
                    'This TV has ${widget.savedCount} saved titles. Account sync can carry saved titles when you sign in.',
                icon: Icons.favorite_rounded,
              ),
            ),
          ),
          _TvSettingsAction(
            title: 'Continue watching',
            subtitle:
                'Recent titles and progress stay local first, then sync through the account adapter when available.',
            value: '${widget.recentCount} recent',
            icon: Icons.playlist_play_rounded,
            onPressed: () => unawaited(
              _showStatusDialog(
                context,
                title: 'Continue watching',
                message:
                    'This TV has ${widget.recentCount} recent titles and ${widget.completedCount} completed entries. Active watch time is ${widget.activeWatchLabel}.',
                icon: Icons.playlist_play_rounded,
              ),
            ),
          ),
          _TvSettingsAction(
            title: widget.accountSignedIn ? 'Sign out' : 'Continue as guest',
            subtitle: widget.accountSignedIn
                ? 'Clear the account session from this TV. Local app settings stay on this device.'
                : 'Use this TV without account sync.',
            value: widget.accountSignedIn ? 'Ready' : 'Guest',
            icon: widget.accountSignedIn
                ? Icons.logout_rounded
                : Icons.person_outline_rounded,
            onPressed: widget.accountSignedIn
                ? widget.onAccountSignOut
                : () => Navigator.of(context).pop(),
          ),
        ];
      case 'About & Diagnostics':
        return [
          _TvSettingsAction(
            title: 'About',
            subtitle: 'Version, TV environment, and last update check.',
            value: 'Open',
            icon: Icons.info_outline_rounded,
            onPressed: () => unawaited(_openAboutDialog(context)),
          ),
          _TvSettingsAction(
            title: 'Check for updates',
            subtitle: 'Read release notes and check Android TV downloads.',
            value: 'Check',
            icon: Icons.system_update_alt_rounded,
            onPressed: () => unawaited(_openUpdatesDialog(context)),
          ),
          _TvSettingsAction(
            title: 'Send diagnostic',
            subtitle:
                'Create a private support ticket with redacted TV status.',
            value: 'Send',
            icon: Icons.cloud_upload_outlined,
            onPressed: () => unawaited(_openDiagnosticConsent(context)),
          ),
        ];
      default:
        return const <_TvSettingsAction>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(context, _current, _update);
    _syncActionFocusNodes(actions.length);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 104, vertical: 34),
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: _tvSpacing),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(widget.section.icon, color: _tvAccentColor, size: 30),
                  const SizedBox(width: _tvSpacing),
                  Expanded(
                    child: Text(
                      widget.section.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _tvTheme.text,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                widget.section.subtitle,
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var index = 0; index < actions.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _tvSpacing),
                          child: _TvSettingsLineCard(
                            action: actions[index],
                            autofocus: index == 0,
                            focusNode: _actionNode(index),
                            onFocus: () =>
                                _rememberActionFocus(_actionNode(index)),
                            onArrowUp: index == 0
                                ? () => _focusAction(index)
                                : () => _focusAction(index - 1),
                            onArrowDown: index == actions.length - 1
                                ? () => _focusAction(0)
                                : () => _focusAction(index + 1),
                            onArrowLeft: () => _focusAction(index),
                            onArrowRight: () => _focusAction(index),
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

String _tvBuildChannelLabel(_TvReleaseUpdateChannel channel) {
  return channel == _TvReleaseUpdateChannel.nightly ? 'Nightly' : 'Stable';
}

String _formatTvDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour == 0 || local.hour == 12 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${_tvMonthName(local.month)} ${local.day}, ${local.year} $hour:$minute $period';
}

String _tvMonthName(int month) {
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  if (month < 1 || month > months.length) return 'Unknown';
  return months[month - 1];
}

String _tvDiagnosticErrorLabel(Object error) {
  final raw = error.toString();
  if (raw.contains('timed out') || raw.contains('TimeoutException')) {
    return 'The network request timed out.';
  }
  if (raw.contains('Failed host lookup') || raw.contains('SocketException')) {
    return 'This TV could not reach the diagnostics service.';
  }
  if (raw.contains('429') || raw.contains('Rate limit')) {
    return 'Too many reports were sent recently. Try again later.';
  }
  if (raw.contains('diagnostic_ticket_missing')) {
    return 'The diagnostics service did not return a ticket number.';
  }
  return 'The diagnostics service was unavailable.';
}

class _TvAboutDialog extends StatelessWidget {
  const _TvAboutDialog({required this.snapshot});

  final _TvReleaseUpdatesSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final lines = [
      _TvSettingsLine('App version', snapshot.installedLabel),
      _TvSettingsLine('Build channel', _tvBuildChannelLabel(snapshot.channel)),
      const _TvSettingsLine('Package', _tvAppPackageName),
      _TvSettingsLine(
        'Last update check',
        _formatTvDateTime(snapshot.latest.checkedAt),
      ),
    ];
    return _TvInfoLinesDialog(
      title: 'About',
      icon: Icons.info_outline_rounded,
      lines: lines,
    );
  }
}

class _TvInfoLinesDialog extends StatefulWidget {
  const _TvInfoLinesDialog({
    required this.title,
    required this.icon,
    required this.lines,
  });

  final String title;
  final IconData icon;
  final List<_TvSettingsLine> lines;

  @override
  State<_TvInfoLinesDialog> createState() => _TvInfoLinesDialogState();
}

class _TvInfoLinesDialogState extends State<_TvInfoLinesDialog> {
  final List<FocusNode> _lineFocusNodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncLineFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusLine(0));
  }

  @override
  void didUpdateWidget(covariant _TvInfoLinesDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLineFocusNodes();
  }

  @override
  void dispose() {
    for (final node in _lineFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncLineFocusNodes() {
    while (_lineFocusNodes.length < widget.lines.length) {
      _lineFocusNodes.add(
        FocusNode(debugLabel: 'tv-info-dialog-line-${_lineFocusNodes.length}'),
      );
    }
    while (_lineFocusNodes.length > widget.lines.length) {
      _lineFocusNodes.removeLast().dispose();
    }
  }

  void _focusLine(int index) {
    if (!mounted || _lineFocusNodes.isEmpty) return;
    final nextIndex = index.clamp(0, _lineFocusNodes.length - 1);
    final node = _lineFocusNodes[nextIndex];
    node.requestFocus();
    final context = node.context;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: _tvDuration(160),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncLineFocusNodes();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 150, vertical: 56),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: _tvAccentColor, size: 30),
                const SizedBox(width: _tvSpacing),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _tvTheme.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: _tvSpacing),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0; index < widget.lines.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: _tvSpacing),
                        child: _TvFocusable(
                          autofocus: index == 0,
                          autoReveal: true,
                          focusNode: _lineFocusNodes[index],
                          onPressed: () {},
                          onArrowUp: () => _focusLine(index - 1),
                          onArrowDown: () => _focusLine(index + 1),
                          builder: (focused) {
                            final line = widget.lines[index];
                            return AnimatedContainer(
                              duration: _tvDuration(140),
                              width: double.infinity,
                              padding: const EdgeInsets.all(_tvSpacing),
                              decoration: BoxDecoration(
                                color: _tvTheme.row,
                                borderRadius: BorderRadius.circular(18),
                                border: focused
                                    ? Border.all(
                                        color: _tvSolidFocusBorder,
                                        width: 2.5,
                                      )
                                    : Border.all(color: _tvTheme.rowBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.title,
                                    style: TextStyle(
                                      color: _tvTheme.text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    line.subtitle,
                                    style: TextStyle(
                                      color: _tvTheme.muted,
                                      fontSize: 14,
                                      height: 1.35,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
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

class _TvChangelogSection {
  const _TvChangelogSection({required this.title, required this.items});

  final String title;
  final List<String> items;
}

List<_TvChangelogSection> _parseTvChangelogSections(String raw) {
  final source = raw.trim().isEmpty ? 'No changelog notes available.' : raw;
  final sections = <_TvChangelogSection>[];
  var currentTitle = 'Highlights';
  var currentItems = <String>[];

  void flush() {
    if (currentItems.isEmpty) return;
    sections.add(
      _TvChangelogSection(
        title: currentTitle,
        items: currentItems.toList(growable: false),
      ),
    );
    currentItems = <String>[];
  }

  for (final rawLine in source.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('##')) {
      flush();
      currentTitle = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      if (currentTitle.isEmpty) currentTitle = 'Highlights';
      continue;
    }
    final cleaned =
        line.replaceFirst(RegExp(r'^[-*]\s*'), '').replaceAll('`', '').trim();
    if (cleaned.isNotEmpty) currentItems.add(cleaned);
  }
  flush();
  if (sections.isNotEmpty) return sections;
  return <_TvChangelogSection>[
    _TvChangelogSection(
      title: currentTitle,
      items: const ['No changelog notes available.'],
    ),
  ];
}

class _TvChangelogDialog extends StatefulWidget {
  const _TvChangelogDialog({required this.snapshot});

  final _TvReleaseUpdatesSnapshot snapshot;

  @override
  State<_TvChangelogDialog> createState() => _TvChangelogDialogState();
}

class _TvChangelogDialogState extends State<_TvChangelogDialog> {
  final List<FocusNode> _sectionFocusNodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncSectionFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSection(0));
  }

  @override
  void dispose() {
    for (final node in _sectionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  List<_TvChangelogSection> get _sections {
    final release = widget.snapshot.latest;
    return _parseTvChangelogSections(
      release.body.trim().isEmpty
          ? _fallbackTvChangelog(widget.snapshot.channel)
          : release.body.trim(),
    );
  }

  void _syncSectionFocusNodes() {
    final count = _sections.length;
    while (_sectionFocusNodes.length < count) {
      _sectionFocusNodes.add(
        FocusNode(
          debugLabel: 'tv-changelog-section-${_sectionFocusNodes.length}',
        ),
      );
    }
    while (_sectionFocusNodes.length > count) {
      _sectionFocusNodes.removeLast().dispose();
    }
  }

  void _focusSection(int index) {
    if (!mounted || _sectionFocusNodes.isEmpty) return;
    final nextIndex = index.clamp(0, _sectionFocusNodes.length - 1);
    final node = _sectionFocusNodes[nextIndex];
    node.requestFocus();
    final context = node.context;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: _tvDuration(160),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncSectionFocusNodes();
    final release = widget.snapshot.latest;
    final title = widget.snapshot.channel == _TvReleaseUpdateChannel.nightly
        ? 'Nightly changelog'
        : 'Release changelog';
    final sections = _sections;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 128, vertical: 40),
      child: Container(
        width: 780,
        constraints: const BoxConstraints(maxHeight: 590),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: _tvTheme.text,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${release.name} - checked ${_formatTvDateTime(release.checkedAt)}',
              style: TextStyle(
                color: _tvTheme.muted,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0; index < sections.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: _tvSpacing),
                        child: _TvFocusable(
                          autofocus: index == 0,
                          autoReveal: true,
                          focusNode: _sectionFocusNodes[index],
                          onPressed: () {},
                          onArrowUp: () => _focusSection(index - 1),
                          onArrowDown: () => _focusSection(index + 1),
                          builder: (focused) {
                            final section = sections[index];
                            return AnimatedContainer(
                              duration: _tvDuration(140),
                              width: double.infinity,
                              padding: const EdgeInsets.all(_tvSpacing),
                              decoration: BoxDecoration(
                                color: _tvTheme.row,
                                borderRadius: BorderRadius.circular(18),
                                border: focused
                                    ? Border.all(
                                        color: _tvSolidFocusBorder,
                                        width: 2.5,
                                      )
                                    : Border.all(color: _tvTheme.rowBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    section.title,
                                    style: TextStyle(
                                      color: _tvTheme.text,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  for (final item in section.items)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 7),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '- ',
                                            style: TextStyle(
                                              color: _tvAccentColor,
                                              fontSize: 15,
                                              height: 1.35,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              item,
                                              style: TextStyle(
                                                color: _tvTheme.text,
                                                fontSize: 15,
                                                height: 1.35,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
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

class _TvUpdatesDialog extends StatefulWidget {
  const _TvUpdatesDialog({
    required this.initialSnapshot,
    required this.onOpenDownload,
  });

  final _TvReleaseUpdatesSnapshot initialSnapshot;
  final Future<void> Function(Uri uri) onOpenDownload;

  @override
  State<_TvUpdatesDialog> createState() => _TvUpdatesDialogState();
}

class _TvUpdatesDialogState extends State<_TvUpdatesDialog> {
  final FocusNode _changelogFocusNode = FocusNode(
    debugLabel: 'tv-updates-changelog',
  );
  final FocusNode _updateFocusNode = FocusNode(debugLabel: 'tv-updates-check');
  late _TvReleaseUpdatesSnapshot _snapshot = widget.initialSnapshot;
  bool _checking = true;
  bool _downloadOpening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _changelogFocusNode.requestFocus();
    });
    unawaited(_checkForUpdates());
  }

  @override
  void dispose() {
    _changelogFocusNode.dispose();
    _updateFocusNode.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checking = true);
    final latest = await _TvReleaseUpdatesClient().latestForChannel(
      widget.initialSnapshot.channel,
    );
    if (!mounted) return;
    setState(() {
      _snapshot = _TvReleaseUpdatesSnapshot(
        installedVersion: widget.initialSnapshot.installedVersion,
        installedCode: widget.initialSnapshot.installedCode,
        channel: widget.initialSnapshot.channel,
        latest: latest,
      );
      _checking = false;
    });
  }

  Future<void> _openChangelog() async {
    await _showTvDialog<void>(
      context: context,
      builder: (dialogContext) => _TvChangelogDialog(snapshot: _snapshot),
    );
    if (mounted) _changelogFocusNode.requestFocus();
  }

  Future<void> _downloadUpdate() async {
    if (!_snapshot.updateAvailable || _downloadOpening) return;
    setState(() => _downloadOpening = true);
    await widget.onOpenDownload(_snapshot.downloadUri);
    if (!mounted) return;
    setState(() => _downloadOpening = false);
    _updateFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final updateLabel = _checking
        ? 'Checking updates...'
        : _snapshot.updateAvailable
            ? (_downloadOpening ? 'Opening...' : 'Download update')
            : 'Up to date';
    final updateEnabled =
        !_checking && !_downloadOpening && _snapshot.updateAvailable;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 138, vertical: 62),
      child: Container(
        width: 640,
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.system_update_alt_rounded,
                  color: _tvAccentColor,
                  size: 30,
                ),
                const SizedBox(width: _tvSpacing),
                Expanded(
                  child: Text(
                    'Check for updates',
                    style: TextStyle(
                      color: _tvTheme.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: _tvSpacing),
            Text(
              'Installed: ${_snapshot.installedLabel} - ${_tvBuildChannelLabel(_snapshot.channel)} build. Last checked: ${_formatTvDateTime(_snapshot.latest.checkedAt)}.',
              style: TextStyle(
                color: _tvTheme.muted,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            Row(
              children: [
                Expanded(
                  child: _TvTextButton(
                    icon: Icons.article_outlined,
                    label: 'Read changelog',
                    focusNode: _changelogFocusNode,
                    onArrowRight: () => _updateFocusNode.requestFocus(),
                    onPressed: () => unawaited(_openChangelog()),
                  ),
                ),
                const SizedBox(width: _tvSpacing),
                Expanded(
                  child: _TvTextButton(
                    icon: _checking
                        ? Icons.hourglass_top_rounded
                        : _snapshot.updateAvailable
                            ? Icons.download_rounded
                            : Icons.check_rounded,
                    label: updateLabel,
                    enabled: updateEnabled,
                    animateIcon: _checking,
                    focusNode: _updateFocusNode,
                    onArrowLeft: () => _changelogFocusNode.requestFocus(),
                    onPressed: () => unawaited(_downloadUpdate()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TvDiagnosticConsentDialog extends StatefulWidget {
  const _TvDiagnosticConsentDialog({required this.onSend});

  final Future<void> Function() onSend;

  @override
  State<_TvDiagnosticConsentDialog> createState() =>
      _TvDiagnosticConsentDialogState();
}

class _TvDiagnosticConsentDialogState
    extends State<_TvDiagnosticConsentDialog> {
  final FocusNode _sendFocusNode = FocusNode(debugLabel: 'tv-diagnostic-send');
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _sendFocusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSend();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _tvDiagnosticErrorLabel(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 150, vertical: 58),
      child: Container(
        width: 640,
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send diagnostic',
              style: TextStyle(
                color: _tvTheme.text,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            Text(
              'Juicr will create a private support ticket from this TV. The report includes safe app events, version, settings buckets, library counts, and TV status needed for troubleshooting. It does not include private playback details, account secrets, add-on links, URLs, tokens, headers, or local paths.',
              style: TextStyle(
                color: _tvTheme.muted,
                fontSize: 14,
                height: 1.36,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: _tvSpacing),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF9A8B),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: _tvSpacing),
            Align(
              alignment: Alignment.centerRight,
              child: _TvTextButton(
                icon: _sending
                    ? Icons.hourglass_top_rounded
                    : Icons.cloud_upload_outlined,
                label: _sending ? 'Sending...' : 'Send',
                enabled: !_sending,
                animateIcon: _sending,
                autofocus: true,
                focusNode: _sendFocusNode,
                onPressed: () => unawaited(_send()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvSettingsLineCard extends StatelessWidget {
  const _TvSettingsLineCard({
    required this.action,
    this.autofocus = false,
    this.focusNode,
    this.onFocus,
    this.onArrowUp,
    this.onArrowDown,
    this.onArrowLeft,
    this.onArrowRight,
  });

  final _TvSettingsAction action;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      autoReveal: true,
      onFocus: onFocus,
      onPressed: action.onPressed,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: double.infinity,
          padding: const EdgeInsets.all(_tvSpacing),
          decoration: BoxDecoration(
            color: focused ? _tvAccentColor : _tvTheme.row,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: focused ? _tvSolidFocusBorder : _tvTheme.rowBorder,
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                action.icon,
                color: focused ? Colors.black : _tvAccentColor,
                size: 26,
              ),
              const SizedBox(width: _tvSpacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: TextStyle(
                        color: focused ? Colors.black : _tvTheme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: _tvSpacing),
                    Text(
                      action.subtitle,
                      style: TextStyle(
                        color: focused
                            ? Colors.black.withValues(alpha: 0.72)
                            : _tvTheme.muted,
                        fontSize: 13,
                        height: 1.28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: _tvSpacing),
              Container(
                constraints: const BoxConstraints(minWidth: 86),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: focused
                      ? Colors.black.withValues(alpha: 0.14)
                      : _tvTheme.valuePill,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: focused
                        ? Colors.black.withValues(alpha: 0.18)
                        : _tvTheme.valuePillBorder,
                  ),
                ),
                child: Text(
                  action.value,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: focused ? Colors.black : _tvTheme.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

typedef _TvAccountProfileSave = Future<TvAccountProfile> Function({
  required String username,
  required String emoji,
  required bool leaderboardOptIn,
});

const List<String> _tvAccountIconOptions = [
  '🍋',
  '🎬',
  '🍿',
  '⭐',
  '🔥',
  '⚡',
  '🌙',
  '🚀',
  '🎭',
  '🏆',
  '💚',
  '😎',
];

class _TvAccountLibraryDialog extends StatefulWidget {
  const _TvAccountLibraryDialog({
    required this.profile,
    required this.accountLabel,
    required this.accountSyncLabel,
    required this.recentCount,
    required this.savedCount,
    required this.completedCount,
    required this.savedMovieCount,
    required this.savedSeriesCount,
    required this.savedAnimationCount,
    required this.savedLiveTvCount,
    required this.activeWatchLabel,
    required this.onSync,
    required this.onSaveProfile,
    required this.onClearContinue,
    required this.onClearSaved,
    required this.onClearMovies,
    required this.onClearSeries,
    required this.onClearAnimation,
    required this.onClearLiveTv,
    required this.onClearLists,
    required this.onClearCompleted,
    required this.onSignOut,
    required this.onDeleteAccount,
  });

  final TvAccountProfile profile;
  final String accountLabel;
  final String accountSyncLabel;
  final int recentCount;
  final int savedCount;
  final int completedCount;
  final int savedMovieCount;
  final int savedSeriesCount;
  final int savedAnimationCount;
  final int savedLiveTvCount;
  final String activeWatchLabel;
  final Future<void> Function() onSync;
  final _TvAccountProfileSave onSaveProfile;
  final Future<void> Function() onClearContinue;
  final Future<void> Function() onClearSaved;
  final Future<void> Function() onClearMovies;
  final Future<void> Function() onClearSeries;
  final Future<void> Function() onClearAnimation;
  final Future<void> Function() onClearLiveTv;
  final Future<void> Function() onClearLists;
  final Future<void> Function() onClearCompleted;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onDeleteAccount;

  @override
  State<_TvAccountLibraryDialog> createState() =>
      _TvAccountLibraryDialogState();
}

class _TvAccountLibraryDialogState extends State<_TvAccountLibraryDialog> {
  final _usernameController = TextEditingController();
  final _usernameFocusNode = FocusNode(debugLabel: 'tv-account-username');
  final _logoutFocusNode = FocusNode(debugLabel: 'tv-account-logout');
  final _actionFocusNodes = <FocusNode>[];
  late TvAccountProfile _profile = widget.profile;
  late String _icon = widget.profile.emoji.isEmpty
      ? _tvAccountIconOptions.first
      : widget.profile.emoji;
  late int _recentCount = widget.recentCount;
  late int _savedCount = widget.savedCount;
  late int _savedMovieCount = widget.savedMovieCount;
  late int _savedSeriesCount = widget.savedSeriesCount;
  late int _savedAnimationCount = widget.savedAnimationCount;
  late int _savedLiveTvCount = widget.savedLiveTvCount;
  String? _error;

  @override
  void initState() {
    super.initState();
    _usernameController.text = widget.profile.username;
    _focusAccountEntry();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _usernameFocusNode.dispose();
    _logoutFocusNode.dispose();
    for (final node in _actionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncActionFocusNodes(int count) {
    while (_actionFocusNodes.length > count) {
      _actionFocusNodes.removeLast().dispose();
    }
    while (_actionFocusNodes.length < count) {
      _actionFocusNodes.add(
        FocusNode(debugLabel: 'tv-account-action-${_actionFocusNodes.length}'),
      );
    }
  }

  void _focusAction(int index) {
    if (index < 0 || index >= _actionFocusNodes.length) return;
    final node = _actionFocusNodes[index];
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(150),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  void _focusAccountEntry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusAction(0);
    });
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    IconData icon = Icons.warning_amber_rounded,
  }) async {
    final accepted = await _showTvDialog<bool>(
      context: context,
      builder: (dialogContext) => _TvConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        icon: icon,
      ),
    );
    _focusAccountEntry();
    return accepted == true;
  }

  Future<void> _signOut() async {
    Navigator.of(context).pop();
    await widget.onSignOut();
  }

  Future<void> _deleteAccount() async {
    final accepted = await _confirm(
      title: 'Delete account?',
      message:
          'This deletes the account and clears this TV library session. This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
    );
    if (!accepted || !mounted) return;
    Navigator.of(context).pop();
    await widget.onDeleteAccount();
  }

  Future<void> _openProfile() async {
    final updated = await _showTvDialog<TvAccountProfile>(
      context: context,
      builder: (dialogContext) => _TvAccountProfileDialog(
        profile: _profile,
        onSaveProfile: widget.onSaveProfile,
      ),
    );
    if (!mounted) return;
    if (updated != null) {
      setState(() {
        _profile = updated;
        _icon = updated.emoji.isEmpty ? _icon : updated.emoji;
        _usernameController.text = updated.username;
      });
    }
    _focusAction(0);
  }

  Future<void> _openLibraryManagement() async {
    final result = await _showTvDialog<_TvLibraryManagementResult>(
      context: context,
      builder: (dialogContext) => _TvLibraryManagementDialog(
        recentCount: _recentCount,
        savedMovieCount: _savedMovieCount,
        savedSeriesCount: _savedSeriesCount,
        savedAnimationCount: _savedAnimationCount,
        savedLiveTvCount: _savedLiveTvCount,
        onClearContinue: widget.onClearContinue,
        onClearLists: widget.onClearLists,
        onClearMovies: widget.onClearMovies,
        onClearSeries: widget.onClearSeries,
        onClearAnimation: widget.onClearAnimation,
        onClearLiveTv: widget.onClearLiveTv,
      ),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        if (result.continueCleared) _recentCount = 0;
        if (result.listsCleared) {
          // Lists do not have a dedicated count in the account summary.
        }
        if (result.moviesCleared) _savedMovieCount = 0;
        if (result.seriesCleared) _savedSeriesCount = 0;
        if (result.animationCleared) _savedAnimationCount = 0;
        if (result.liveTvCleared) _savedLiveTvCount = 0;
        _savedCount = _savedMovieCount +
            _savedSeriesCount +
            _savedAnimationCount +
            _savedLiveTvCount;
      });
    }
    _focusAction(1);
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      _TvSettingsAction(
        title: 'Profile',
        subtitle: _profile.usernameLocked
            ? 'Change profile icon and leaderboard visibility.'
            : 'Set your username, profile icon, and leaderboard visibility.',
        value: _icon,
        icon: Icons.account_circle_rounded,
        onPressed: () => unawaited(_openProfile()),
      ),
      _TvSettingsAction(
        title: 'Library management',
        subtitle:
            'Clear Continue watching, Lists, Movies, Series, Animations, or Live TV.',
        value: '$_savedCount saved',
        icon: Icons.favorite_rounded,
        onPressed: () => unawaited(_openLibraryManagement()),
      ),
      _TvSettingsAction(
        title: 'Delete account',
        subtitle: 'Delete the account and clear this TV library session.',
        value: 'Delete',
        icon: Icons.delete_outline_rounded,
        onPressed: () => unawaited(_deleteAccount()),
      ),
    ];
    _syncActionFocusNodes(actions.length);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 108, vertical: 34),
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: _tvSpacing),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_circle_rounded,
                    color: _tvAccentColor,
                    size: 32,
                  ),
                  const SizedBox(width: _tvSpacing),
                  Expanded(
                    child: Text(
                      'Account & Library',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _tvTheme.text,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                '${widget.accountLabel} - ${widget.accountSyncLabel}. Active watch time: ${widget.activeWatchLabel}.',
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: _tvSpacing),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFF9A8B),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: _tvSpacing),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var index = 0; index < actions.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _tvSpacing),
                          child: _TvSettingsLineCard(
                            action: actions[index],
                            focusNode: _actionFocusNodes[index],
                            onArrowUp: index == 0
                                ? () => _focusAction(0)
                                : () => _focusAction(index - 1),
                            onArrowDown: index == actions.length - 1
                                ? () => _logoutFocusNode.requestFocus()
                                : () => _focusAction(index + 1),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _TvTextButton(
                          icon: Icons.logout_rounded,
                          label: 'Logout',
                          focusNode: _logoutFocusNode,
                          onArrowUp: () => _focusAction(actions.length - 1),
                          onArrowDown: () => _logoutFocusNode.requestFocus(),
                          onPressed: () => unawaited(_signOut()),
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

class _TvAccountProfileDialog extends StatefulWidget {
  const _TvAccountProfileDialog({
    required this.profile,
    required this.onSaveProfile,
  });

  final TvAccountProfile profile;
  final _TvAccountProfileSave onSaveProfile;

  @override
  State<_TvAccountProfileDialog> createState() =>
      _TvAccountProfileDialogState();
}

class _TvAccountProfileDialogState extends State<_TvAccountProfileDialog> {
  final _usernameController = TextEditingController();
  final _usernameFocusNode = FocusNode(debugLabel: 'tv-account-profile-name');
  final _saveFocusNode = FocusNode(debugLabel: 'tv-account-profile-save');
  final _actionFocusNodes = <FocusNode>[];
  late String _icon = widget.profile.emoji.isEmpty
      ? _tvAccountIconOptions.first
      : widget.profile.emoji;
  late bool _leaderboardOptIn =
      widget.profile.leaderboardOptIn || widget.profile.username.isEmpty;
  String? _busyAction;
  String? _error;

  bool get _usernameFieldEnabled =>
      !widget.profile.usernameLocked && _busyAction == null;

  @override
  void initState() {
    super.initState();
    _usernameController.text = widget.profile.username;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_usernameFieldEnabled) {
        _usernameFocusNode.requestFocus();
      } else {
        _focusAction(0);
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _usernameFocusNode.dispose();
    _saveFocusNode.dispose();
    for (final node in _actionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncActionFocusNodes(int count) {
    while (_actionFocusNodes.length > count) {
      _actionFocusNodes.removeLast().dispose();
    }
    while (_actionFocusNodes.length < count) {
      _actionFocusNodes.add(
        FocusNode(
          debugLabel: 'tv-account-profile-action-${_actionFocusNodes.length}',
        ),
      );
    }
  }

  void _focusAction(int index) {
    if (index < 0 || index >= _actionFocusNodes.length) return;
    _actionFocusNodes[index].requestFocus();
  }

  Future<void> _pickIcon() async {
    final selected = await _showTvDialog<String>(
      context: context,
      builder: (dialogContext) => _TvSettingsOptionDialog(
        title: 'Profile icon',
        selected: _icon,
        options: _tvAccountIconOptions,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _icon = selected);
    _focusAction(0);
  }

  Future<void> _saveProfile() async {
    if (_busyAction != null) return;
    setState(() {
      _busyAction = 'Profile';
      _error = null;
    });
    try {
      final profile = await widget.onSaveProfile(
        username: _usernameController.text,
        emoji: _icon,
        leaderboardOptIn: _leaderboardOptIn,
      );
      if (!mounted) return;
      Navigator.of(context).pop(profile);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Profile could not be saved right now.');
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      _TvSettingsAction(
        title: 'Profile icon',
        subtitle: 'Choose the icon used with your account profile.',
        value: _icon,
        icon: Icons.face_rounded,
        onPressed: () => unawaited(_pickIcon()),
      ),
      _TvSettingsAction(
        title: 'Leaderboard',
        subtitle:
            'Only your username, icon, and active watch time can appear after opt-in.',
        value: _leaderboardOptIn ? 'On' : 'Off',
        icon: Icons.emoji_events_outlined,
        onPressed: () => setState(() => _leaderboardOptIn = !_leaderboardOptIn),
      ),
    ];
    _syncActionFocusNodes(actions.length);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 170, vertical: 60),
      child: Container(
        width: 720,
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profile',
              style: TextStyle(
                color: _tvTheme.text,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            if (_usernameFieldEnabled) ...[
              _TvDialogTextField(
                controller: _usernameController,
                icon: Icons.alternate_email_rounded,
                hintText: 'Username',
                enabled: true,
                focusNode: _usernameFocusNode,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                onArrowDown: () => _focusAction(0),
              ),
              const SizedBox(height: _tvSpacing),
            ],
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF9A8B),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: _tvSpacing),
            ],
            for (var index = 0; index < actions.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: _tvSpacing),
                child: _TvSettingsLineCard(
                  action: actions[index],
                  focusNode: _actionFocusNodes[index],
                  onArrowUp: index == 0
                      ? () {
                          if (_usernameFieldEnabled) {
                            _usernameFocusNode.requestFocus();
                          } else {
                            _focusAction(0);
                          }
                        }
                      : () => _focusAction(index - 1),
                  onArrowDown: index == actions.length - 1
                      ? () => _saveFocusNode.requestFocus()
                      : () => _focusAction(index + 1),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: _TvTextButton(
                icon: Icons.check_rounded,
                label: _busyAction == 'Profile' ? 'Saving' : 'Save',
                enabled: _busyAction == null,
                focusNode: _saveFocusNode,
                onArrowUp: () => _focusAction(actions.length - 1),
                onArrowDown: () => _saveFocusNode.requestFocus(),
                onPressed: () => unawaited(_saveProfile()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvLibraryManagementResult {
  const _TvLibraryManagementResult({
    this.continueCleared = false,
    this.listsCleared = false,
    this.moviesCleared = false,
    this.seriesCleared = false,
    this.animationCleared = false,
    this.liveTvCleared = false,
  });

  final bool continueCleared;
  final bool listsCleared;
  final bool moviesCleared;
  final bool seriesCleared;
  final bool animationCleared;
  final bool liveTvCleared;
}

class _TvLibraryManagementDialog extends StatefulWidget {
  const _TvLibraryManagementDialog({
    required this.recentCount,
    required this.savedMovieCount,
    required this.savedSeriesCount,
    required this.savedAnimationCount,
    required this.savedLiveTvCount,
    required this.onClearContinue,
    required this.onClearLists,
    required this.onClearMovies,
    required this.onClearSeries,
    required this.onClearAnimation,
    required this.onClearLiveTv,
  });

  final int recentCount;
  final int savedMovieCount;
  final int savedSeriesCount;
  final int savedAnimationCount;
  final int savedLiveTvCount;
  final Future<void> Function() onClearContinue;
  final Future<void> Function() onClearLists;
  final Future<void> Function() onClearMovies;
  final Future<void> Function() onClearSeries;
  final Future<void> Function() onClearAnimation;
  final Future<void> Function() onClearLiveTv;

  @override
  State<_TvLibraryManagementDialog> createState() =>
      _TvLibraryManagementDialogState();
}

class _TvLibraryManagementDialogState
    extends State<_TvLibraryManagementDialog> {
  final _actionFocusNodes = <FocusNode>[];
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAction(0);
    });
  }

  @override
  void dispose() {
    for (final node in _actionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncActionFocusNodes(int count) {
    while (_actionFocusNodes.length > count) {
      _actionFocusNodes.removeLast().dispose();
    }
    while (_actionFocusNodes.length < count) {
      _actionFocusNodes.add(
        FocusNode(
          debugLabel:
              'tv-library-management-action-${_actionFocusNodes.length}',
        ),
      );
    }
  }

  void _focusAction(int index) {
    if (index < 0 || index >= _actionFocusNodes.length) return;
    _actionFocusNodes[index].requestFocus();
  }

  Future<void> _clear({
    required String label,
    required String title,
    required String message,
    required Future<void> Function() action,
    required _TvLibraryManagementResult result,
  }) async {
    if (_busyAction != null) return;
    final accepted = await _showTvDialog<bool>(
      context: context,
      builder: (dialogContext) => _TvConfirmDialog(
        title: title,
        message: message,
        confirmLabel: 'Clear',
        icon: Icons.delete_outline_rounded,
      ),
    );
    if (!mounted || accepted != true) return;
    setState(() => _busyAction = label);
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      _TvSettingsAction(
        title: 'Clear Continue watching',
        subtitle: 'Remove unfinished playback and recent titles.',
        value: _busyAction == 'Continue watching'
            ? 'Clearing'
            : '${widget.recentCount}',
        icon: Icons.history_rounded,
        onPressed: () => unawaited(
          _clear(
            label: 'Continue watching',
            title: 'Clear Continue watching?',
            message:
                'This removes saved playback progress and recent titles from this TV and synced library.',
            action: widget.onClearContinue,
            result: const _TvLibraryManagementResult(continueCleared: true),
          ),
        ),
      ),
      _TvSettingsAction(
        title: 'Clear Lists',
        subtitle: 'Remove every custom Library list.',
        value: _busyAction == 'Lists' ? 'Clearing' : 'Clear',
        icon: Icons.bookmarks_outlined,
        onPressed: () => unawaited(
          _clear(
            label: 'Lists',
            title: 'Clear Lists?',
            message: 'This removes every custom Library list.',
            action: widget.onClearLists,
            result: const _TvLibraryManagementResult(listsCleared: true),
          ),
        ),
      ),
      _TvSettingsAction(
        title: 'Clear Movies',
        subtitle: 'Remove saved movies from Library.',
        value:
            _busyAction == 'Movies' ? 'Clearing' : '${widget.savedMovieCount}',
        icon: Icons.movie_creation_rounded,
        onPressed: () => unawaited(
          _clear(
            label: 'Movies',
            title: 'Clear Movies?',
            message: 'This removes saved movies from Library.',
            action: widget.onClearMovies,
            result: const _TvLibraryManagementResult(moviesCleared: true),
          ),
        ),
      ),
      _TvSettingsAction(
        title: 'Clear Series',
        subtitle: 'Remove saved series from Library.',
        value:
            _busyAction == 'Series' ? 'Clearing' : '${widget.savedSeriesCount}',
        icon: Icons.tv_rounded,
        onPressed: () => unawaited(
          _clear(
            label: 'Series',
            title: 'Clear Series?',
            message: 'This removes saved series from Library.',
            action: widget.onClearSeries,
            result: const _TvLibraryManagementResult(seriesCleared: true),
          ),
        ),
      ),
      _TvSettingsAction(
        title: 'Clear Animations',
        subtitle: 'Remove saved animations from Library.',
        value: _busyAction == 'Animations'
            ? 'Clearing'
            : '${widget.savedAnimationCount}',
        icon: Icons.auto_awesome_rounded,
        onPressed: () => unawaited(
          _clear(
            label: 'Animations',
            title: 'Clear Animations?',
            message: 'This removes saved animations from Library.',
            action: widget.onClearAnimation,
            result: const _TvLibraryManagementResult(animationCleared: true),
          ),
        ),
      ),
      _TvSettingsAction(
        title: 'Clear Live TV',
        subtitle: 'Remove saved Live TV items from Library.',
        value: _busyAction == 'Live TV'
            ? 'Clearing'
            : '${widget.savedLiveTvCount}',
        icon: Icons.live_tv_rounded,
        onPressed: () => unawaited(
          _clear(
            label: 'Live TV',
            title: 'Clear Live TV?',
            message: 'This removes saved Live TV items from Library.',
            action: widget.onClearLiveTv,
            result: const _TvLibraryManagementResult(liveTvCleared: true),
          ),
        ),
      ),
    ];
    _syncActionFocusNodes(actions.length);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 140, vertical: 46),
      child: Container(
        width: 780,
        constraints: const BoxConstraints(maxHeight: 620),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Library management',
              style: TextStyle(
                color: _tvTheme.text,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0; index < actions.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: _tvSpacing),
                        child: _TvSettingsLineCard(
                          action: actions[index],
                          focusNode: _actionFocusNodes[index],
                          onArrowUp: index == 0
                              ? () => _focusAction(index)
                              : () => _focusAction(index - 1),
                          onArrowDown: index == actions.length - 1
                              ? () => _focusAction(index)
                              : () => _focusAction(index + 1),
                        ),
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

class _TvConfirmDialog extends StatelessWidget {
  const _TvConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.icon,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 220, vertical: 80),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _tvAccentColor, size: 30),
                const SizedBox(width: _tvSpacing),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: _tvTheme.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: _tvSpacing),
            Text(
              message,
              style: TextStyle(
                color: _tvTheme.muted,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TvTextButton(
                  icon: Icons.check_rounded,
                  label: confirmLabel,
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TvUserAddOnManagerDialog extends StatefulWidget {
  const _TvUserAddOnManagerDialog({
    required this.settings,
    required this.onAddAddOn,
    required this.onOpenAddOn,
  });

  final _TvSettingsState settings;
  final Future<_TvSettingsState> Function() onAddAddOn;
  final Future<_TvSettingsState> Function(_TvUserAddOn addon) onOpenAddOn;

  @override
  State<_TvUserAddOnManagerDialog> createState() =>
      _TvUserAddOnManagerDialogState();
}

class _TvUserAddOnManagerDialogState extends State<_TvUserAddOnManagerDialog> {
  final _firstFocusNode = FocusNode(debugLabel: 'tv-addon-manager-first');
  final List<FocusNode> _actionFocusNodes = <FocusNode>[];
  late _TvSettingsState _current = widget.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAction(0);
    });
  }

  @override
  void dispose() {
    _firstFocusNode.dispose();
    for (final node in _actionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncActionFocusNodes(int count) {
    final extraCount = math.max(0, count - 1);
    while (_actionFocusNodes.length > extraCount) {
      _actionFocusNodes.removeLast().dispose();
    }
    while (_actionFocusNodes.length < extraCount) {
      final index = _actionFocusNodes.length + 1;
      _actionFocusNodes.add(
        FocusNode(debugLabel: 'tv-addon-manager-action-$index'),
      );
    }
  }

  FocusNode _actionNode(int index) {
    if (index == 0) return _firstFocusNode;
    return _actionFocusNodes[index - 1];
  }

  void _focusAction(int index) {
    final actions = _actions();
    final clampedIndex = index.clamp(0, actions.length - 1).toInt();
    final node = _actionNode(clampedIndex);
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(150),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  void _restoreActionFocus(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusAction(index.clamp(0, _actionFocusNodes.length));
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _focusAction(index.clamp(0, _actionFocusNodes.length));
      });
    });
  }

  List<_TvSettingsAction> _actions() {
    return [
      _TvSettingsAction(
        title: 'Add add-on',
        subtitle:
            'Name a trusted add-on link for TV-side management. Diagnostics keep private details hidden.',
        value: _current.userAddOns.isEmpty
            ? 'None'
            : '${_current.userAddOns.length} saved',
        icon: Icons.add_link_rounded,
        onPressed: () => unawaited(() async {
          final next = await widget.onAddAddOn();
          if (!mounted) return;
          setState(() => _current = next);
          _restoreActionFocus(0);
        }()),
      ),
      for (var index = 0; index < _current.userAddOns.length; index++)
        _TvSettingsAction(
          title: _current.userAddOns[index].displayName,
          subtitle:
              'Saved add-on. Open to enable, disable, or remove this TV entry.',
          value: _current.userAddOns[index].enabled ? 'On' : 'Off',
          icon: Icons.extension_rounded,
          onPressed: () => unawaited(() async {
            final next = await widget.onOpenAddOn(_current.userAddOns[index]);
            if (!mounted) return;
            setState(() => _current = next);
            _restoreActionFocus(index + 1);
          }()),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions();
    _syncActionFocusNodes(actions.length);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 128, vertical: 46),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 540),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: _tvSpacing),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add add-on',
                style: TextStyle(
                  color: _tvTheme.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                'Add or manage trusted add-on links for this TV.',
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: _tvSpacing),
                    child: Column(
                      children: [
                        for (var index = 0; index < actions.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _tvSpacing),
                            child: _TvSettingsLineCard(
                              action: actions[index],
                              autofocus: index == 0,
                              focusNode: _actionNode(index),
                              onArrowUp: () => _focusAction(index - 1),
                              onArrowDown: () => _focusAction(index + 1),
                            ),
                          ),
                      ],
                    ),
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

class _TvSettingsAction {
  const _TvSettingsAction({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String value;
  final IconData icon;
  final VoidCallback onPressed;
}

class _TvSubtitleStyleDialog extends StatefulWidget {
  const _TvSubtitleStyleDialog({
    required this.settings,
    required this.onSettingsChanged,
  });

  final _TvSettingsState settings;
  final ValueChanged<_TvSettingsState> onSettingsChanged;

  @override
  State<_TvSubtitleStyleDialog> createState() => _TvSubtitleStyleDialogState();
}

class _TvSubtitleStyleDialogState extends State<_TvSubtitleStyleDialog> {
  final List<FocusNode> _actionFocusNodes = <FocusNode>[
    FocusNode(debugLabel: 'tv-subtitle-style-size'),
    FocusNode(debugLabel: 'tv-subtitle-style-color'),
    FocusNode(debugLabel: 'tv-subtitle-style-background'),
  ];
  late _TvSettingsState _current = widget.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAction(0);
    });
  }

  @override
  void dispose() {
    for (final node in _actionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusAction(int index) {
    final node =
        _actionFocusNodes[index.clamp(0, _actionFocusNodes.length - 1)];
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(150),
        curve: Curves.easeOutCubic,
        alignment: 0.45,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  Future<void> _pick(
    int index, {
    required String title,
    required String selected,
    required List<String> options,
    required _TvSettingsState Function(String value) copy,
  }) async {
    final result = await _showTvDialog<String>(
      context: context,
      builder: (dialogContext) => _TvSettingsOptionDialog(
        title: title,
        selected: selected,
        options: options,
      ),
    );
    if (!mounted || result == null) {
      _focusAction(index);
      return;
    }
    final next = copy(result);
    setState(() => _current = next);
    widget.onSettingsChanged(next);
    _focusAction(index);
  }

  List<_TvSettingsAction> get _actions {
    return [
      _TvSettingsAction(
        title: 'Text size',
        subtitle: 'Adjust subtitle size for TV viewing distance.',
        value: _current.subtitleTextSize,
        icon: Icons.format_size_rounded,
        onPressed: () => unawaited(
          _pick(
            0,
            title: 'Text size',
            selected: _current.subtitleTextSize,
            options: const ['Small', 'Default', 'Large', 'Maximum'],
            copy: (value) => _current.copyWith(subtitleTextSize: value),
          ),
        ),
      ),
      _TvSettingsAction(
        title: 'Text color',
        subtitle: 'Choose the subtitle foreground color.',
        value: _current.subtitleTextColor,
        icon: Icons.palette_rounded,
        onPressed: () => unawaited(
          _pick(
            1,
            title: 'Text color',
            selected: _current.subtitleTextColor,
            options: const ['White', 'Yellow', 'Cyan', 'Green'],
            copy: (value) => _current.copyWith(subtitleTextColor: value),
          ),
        ),
      ),
      _TvSettingsAction(
        title: 'Background',
        subtitle: 'Choose how much backing appears behind captions.',
        value: _current.subtitleBackground,
        icon: Icons.closed_caption_rounded,
        onPressed: () => unawaited(
          _pick(
            2,
            title: 'Background',
            selected: _current.subtitleBackground,
            options: const ['Dim', 'Solid', 'Off'],
            copy: (value) => _current.copyWith(subtitleBackground: value),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 128, vertical: 46),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 540),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: _tvSpacing),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Subtitle style',
                style: TextStyle(
                  color: _tvTheme.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                'Tune TV-readable captions for every playback engine.',
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var index = 0; index < actions.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _tvSpacing),
                          child: _TvSettingsLineCard(
                            action: actions[index],
                            autofocus: index == 0,
                            focusNode: _actionFocusNodes[index],
                            onArrowUp: () => _focusAction(index - 1),
                            onArrowDown: () => _focusAction(index + 1),
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

String _tvP2pPriorityModeLabel(String mode) {
  return switch (mode) {
    kTvP2pPriorityQualityFirst => 'Quality first',
    kTvP2pPriorityAvailabilityFirst => 'Availability first',
    kTvP2pPrioritySmallerFasterFiles => 'Smaller, faster files',
    kTvP2pPriorityBalanced => 'Balanced quality and availability',
    _ => 'Smart start',
  };
}

String _tvP2pPriorityModeSubtitle(String mode) {
  return switch (mode) {
    kTvP2pPriorityQualityFirst =>
      'Prefer sharper results when several playable choices are available.',
    kTvP2pPriorityAvailabilityFirst =>
      'Prefer choices that are more likely to start reliably.',
    kTvP2pPrioritySmallerFasterFiles =>
      'Prefer lighter files that can begin faster on constrained networks.',
    kTvP2pPriorityBalanced =>
      'Balance picture quality with a stronger chance of smooth startup.',
    _ => 'Balance fast startup, quality, and source health automatically.',
  };
}

String _tvP2pSizeLimitLabel(int value) {
  return value <= 0 ? 'No limit' : '$value MB';
}

class _TvP2pSourcePrioritiesDialog extends StatefulWidget {
  const _TvP2pSourcePrioritiesDialog({
    required this.settings,
    required this.onSettingsChanged,
  });

  final _TvSettingsState settings;
  final ValueChanged<_TvSettingsState> onSettingsChanged;

  @override
  State<_TvP2pSourcePrioritiesDialog> createState() =>
      _TvP2pSourcePrioritiesDialogState();
}

class _TvP2pSourcePrioritiesDialogState
    extends State<_TvP2pSourcePrioritiesDialog> {
  final _firstFocusNode = FocusNode(debugLabel: 'tv-p2p-priorities-first');
  final List<FocusNode> _actionFocusNodes = <FocusNode>[];
  late _TvSettingsState _current = widget.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAction(0);
    });
  }

  @override
  void dispose() {
    _firstFocusNode.dispose();
    for (final node in _actionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncActionFocusNodes(int count) {
    final extraCount = math.max(0, count - 1);
    while (_actionFocusNodes.length > extraCount) {
      _actionFocusNodes.removeLast().dispose();
    }
    while (_actionFocusNodes.length < extraCount) {
      final index = _actionFocusNodes.length + 1;
      _actionFocusNodes.add(FocusNode(debugLabel: 'tv-p2p-priority-$index'));
    }
  }

  FocusNode _actionNode(int index) {
    if (index == 0) return _firstFocusNode;
    return _actionFocusNodes[index - 1];
  }

  void _focusAction(int index) {
    final actions = _actions();
    final clampedIndex = index.clamp(0, actions.length - 1).toInt();
    final node = _actionNode(clampedIndex);
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(150),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  void _restoreActionFocus(int index) {
    final actions = _actions();
    final clampedIndex = index.clamp(0, actions.length - 1).toInt();
    void focusIfReady() {
      if (!mounted) return;
      _actionNode(clampedIndex).requestFocus();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => focusIfReady());
    Future<void>.delayed(const Duration(milliseconds: 120), focusIfReady);
    Future<void>.delayed(const Duration(milliseconds: 420), focusIfReady);
  }

  void _update(_TvSettingsState next, {int? restoreIndex}) {
    setState(() => _current = next);
    widget.onSettingsChanged(next);
    if (restoreIndex != null) {
      _restoreActionFocus(restoreIndex);
    }
  }

  Future<void> _pickPriorityMode() async {
    final selected = await _showTvDialog<String>(
      context: context,
      builder: (dialogContext) => _TvSettingsOptionDialog(
        title: 'Source priority',
        selected: _tvP2pPriorityModeLabel(_current.p2pPriorityMode),
        options: const [
          'Smart start',
          'Quality first',
          'Availability first',
          'Smaller, faster files',
          'Balanced quality and availability',
        ],
      ),
    );
    _focusAction(1);
    if (selected == null) return;
    final mode = switch (selected) {
      'Quality first' => kTvP2pPriorityQualityFirst,
      'Availability first' => kTvP2pPriorityAvailabilityFirst,
      'Smaller, faster files' => kTvP2pPrioritySmallerFasterFiles,
      'Balanced quality and availability' => kTvP2pPriorityBalanced,
      _ => kTvP2pPrioritySmartStart,
    };
    _update(_current.copyWith(p2pPriorityMode: mode));
  }

  Future<void> _pickResultsPerQuality() async {
    final selected = await _showTvDialog<String>(
      context: context,
      builder: (dialogContext) => _TvSettingsOptionDialog(
        title: 'Results per quality',
        selected: _current.p2pResultsPerQuality.toString(),
        options: const ['1', '2', '3', '4', '5'],
      ),
    );
    _focusAction(2);
    if (selected == null) return;
    _update(
      _current.copyWith(p2pResultsPerQuality: int.tryParse(selected) ?? 3),
    );
  }

  Future<void> _pickSizeLimit() async {
    final selected = await _showTvDialog<String>(
      context: context,
      builder: (dialogContext) => _TvSettingsOptionDialog(
        title: 'Source size limit',
        selected: _tvP2pSizeLimitLabel(_current.p2pSizeLimitMb),
        options: const [
          'No limit',
          '2048 MB',
          '4096 MB',
          '8192 MB',
          '16384 MB',
          '32768 MB',
          '65536 MB',
        ],
      ),
    );
    _focusAction(4);
    if (selected == null) return;
    final value = selected == 'No limit'
        ? 0
        : int.tryParse(selected.replaceAll(' MB', '')) ?? 0;
    _update(_current.copyWith(p2pSizeLimitMb: value));
  }

  List<_TvSettingsAction> _actions() {
    return [
      _TvSettingsAction(
        title: 'Advanced source priorities',
        subtitle: 'Direct and account-backed streams still stay first.',
        value: _current.p2pSourcePrioritiesEnabled ? 'On' : 'Off',
        icon: Icons.low_priority_rounded,
        onPressed: () => _update(
          _current.copyWith(
            p2pSourcePrioritiesEnabled: !_current.p2pSourcePrioritiesEnabled,
          ),
        ),
      ),
      _TvSettingsAction(
        title: 'Priority mode',
        subtitle:
            '${_tvP2pPriorityModeLabel(_current.p2pPriorityMode)}: ${_tvP2pPriorityModeSubtitle(_current.p2pPriorityMode)}',
        value: _tvP2pPriorityModeLabel(_current.p2pPriorityMode),
        icon: Icons.swap_vert_rounded,
        onPressed: () => unawaited(_pickPriorityMode()),
      ),
      _TvSettingsAction(
        title: 'Results per quality',
        subtitle: 'Choose how many P2P results each quality group can keep.',
        value: _current.p2pResultsPerQuality.toString(),
        icon: Icons.playlist_add_check_rounded,
        onPressed: () => unawaited(_pickResultsPerQuality()),
      ),
      _TvSettingsAction(
        title: 'Avoid risky formats',
        subtitle: 'Prefer safer formats first on this TV.',
        value: _current.p2pAvoidRiskyFormats ? 'On' : 'Off',
        icon: Icons.health_and_safety_outlined,
        onPressed: () => _update(
          _current.copyWith(
            p2pAvoidRiskyFormats: !_current.p2pAvoidRiskyFormats,
          ),
        ),
      ),
      _TvSettingsAction(
        title: 'Size limit',
        subtitle: _tvP2pSizeLimitLabel(_current.p2pSizeLimitMb),
        value: _tvP2pSizeLimitLabel(_current.p2pSizeLimitMb),
        icon: Icons.sd_storage_outlined,
        onPressed: () => unawaited(_pickSizeLimit()),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions();
    _syncActionFocusNodes(actions.length);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 118, vertical: 42),
      child: Container(
        width: 780,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: _tvSpacing),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Advanced source priorities',
                style: TextStyle(
                  color: _tvTheme.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                'Tune how enabled add-ons contribute P2P fallback choices.',
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: _tvSpacing),
                    child: Column(
                      children: [
                        for (var index = 0; index < actions.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _tvSpacing),
                            child: _TvSettingsLineCard(
                              action: actions[index],
                              autofocus: index == 0,
                              focusNode: _actionNode(index),
                              onArrowUp: () => _focusAction(index - 1),
                              onArrowDown: () => _focusAction(index + 1),
                            ),
                          ),
                      ],
                    ),
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

class _TvDefaultSourceDialog extends StatefulWidget {
  const _TvDefaultSourceDialog({
    required this.settings,
    required this.onSettingsChanged,
  });

  final _TvSettingsState settings;
  final ValueChanged<_TvSettingsState> onSettingsChanged;

  @override
  State<_TvDefaultSourceDialog> createState() => _TvDefaultSourceDialogState();
}

class _TvDefaultSourceDialogState extends State<_TvDefaultSourceDialog> {
  final _firstFocusNode = FocusNode(debugLabel: 'tv-default-source-first');
  final List<FocusNode> _actionFocusNodes = <FocusNode>[];
  late _TvSettingsState _current = widget.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAction(0);
    });
  }

  @override
  void dispose() {
    _firstFocusNode.dispose();
    for (final node in _actionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncActionFocusNodes(int count) {
    final extraCount = math.max(0, count - 1);
    while (_actionFocusNodes.length > extraCount) {
      _actionFocusNodes.removeLast().dispose();
    }
    while (_actionFocusNodes.length < extraCount) {
      final index = _actionFocusNodes.length + 1;
      _actionFocusNodes.add(
        FocusNode(debugLabel: 'tv-default-source-action-$index'),
      );
    }
  }

  FocusNode _actionNode(int index) {
    if (index == 0) return _firstFocusNode;
    return _actionFocusNodes[index - 1];
  }

  void _focusAction(int index) {
    final actions = _actions(context);
    final clampedIndex = index.clamp(0, actions.length - 1).toInt();
    final node = _actionNode(clampedIndex);
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(150),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  void _restoreActionFocus(int index) {
    final actions = _actions(context);
    final clampedIndex = index.clamp(0, actions.length - 1).toInt();
    void focusIfReady() {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (_firstFocusNode.hasFocus ||
          _actionFocusNodes.any((node) => node.hasFocus)) {
        return;
      }
      _actionNode(clampedIndex).requestFocus();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => focusIfReady());
    const delays = <Duration>[
      Duration(milliseconds: 120),
      Duration(milliseconds: 420),
      Duration(milliseconds: 900),
      Duration(milliseconds: 1600),
    ];
    for (final delay in delays) {
      Future<void>.delayed(delay, focusIfReady);
    }
  }

  void _update(_TvSettingsState next, {required int restoreIndex}) {
    setState(() => _current = next);
    widget.onSettingsChanged(next);
    _restoreActionFocus(restoreIndex);
  }

  List<_TvSettingsAction> _actions(BuildContext context) {
    return [
      _TvSettingsAction(
        title: 'Built-in catalog',
        subtitle: 'Use optional Juicr catalog results on Home and Discovery.',
        value: _current.builtInCatalog ? 'On' : 'Off',
        icon: Icons.grid_view_rounded,
        onPressed: () => _update(
          _current.copyWith(builtInCatalog: !_current.builtInCatalog),
          restoreIndex: 0,
        ),
      ),
      _TvSettingsAction(
        title: 'Built-in subtitles',
        subtitle: 'Look up optional default subtitles in the native TV player.',
        value: _current.builtInSubtitles ? 'On' : 'Off',
        icon: Icons.closed_caption_outlined,
        onPressed: () {
          final enabled = !_current.builtInSubtitles;
          _update(
            _current.copyWith(
              builtInSubtitles: enabled,
              subtitles: enabled ? true : _current.subtitles,
            ),
            restoreIndex: 1,
          );
        },
      ),
      _TvSettingsAction(
        title: 'Built-in trailers',
        subtitle: 'Show optional trailer choices on details pages.',
        value: _current.builtInTrailers ? 'On' : 'Off',
        icon: Icons.movie_filter_outlined,
        onPressed: () => _update(
          _current.copyWith(builtInTrailers: !_current.builtInTrailers),
          restoreIndex: 2,
        ),
      ),
      _TvSettingsAction(
        title: 'Built-in Live TV',
        subtitle:
            'Show optional public live TV channels when this lane is enabled.',
        value: _current.builtInLiveTv ? 'On' : 'Off',
        icon: Icons.live_tv_rounded,
        onPressed: () => _update(
          _current.copyWith(builtInLiveTv: !_current.builtInLiveTv),
          restoreIndex: 3,
        ),
      ),
      _TvSettingsAction(
        title: 'Built-in playback',
        subtitle: 'Allow optional built-in TV playback after safe app checks.',
        value: _current.builtInPlayback ? 'On' : 'Off',
        icon: Icons.play_circle_outline_rounded,
        onPressed: () => _update(
          _current.copyWith(builtInPlayback: !_current.builtInPlayback),
          restoreIndex: 4,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(context);
    _syncActionFocusNodes(actions.length);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 128, vertical: 46),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: _tvSpacing),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Default',
                style: TextStyle(
                  color: _tvTheme.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                'Enable only the built-in tools you want on this TV.',
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Flexible(
                child: SingleChildScrollView(
                  clipBehavior: Clip.hardEdge,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: _tvSpacing),
                    child: Column(
                      children: [
                        for (var index = 0; index < actions.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _tvSpacing),
                            child: _TvSettingsLineCard(
                              action: actions[index],
                              autofocus: index == 0,
                              focusNode: _actionNode(index),
                              onArrowUp: () => _focusAction(index - 1),
                              onArrowDown: () => _focusAction(index + 1),
                            ),
                          ),
                      ],
                    ),
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

class _TvUserAddOnDialog extends StatefulWidget {
  const _TvUserAddOnDialog({
    required this.addon,
    required this.onEnabledChanged,
    required this.onRemove,
  });

  final _TvUserAddOn addon;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onRemove;

  @override
  State<_TvUserAddOnDialog> createState() => _TvUserAddOnDialogState();
}

class _TvUserAddOnDialogState extends State<_TvUserAddOnDialog> {
  final _firstFocusNode = FocusNode(debugLabel: 'tv-user-addon-first');
  final List<FocusNode> _actionFocusNodes = <FocusNode>[];
  late bool _enabled = widget.addon.enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAction(0);
    });
  }

  @override
  void dispose() {
    _firstFocusNode.dispose();
    for (final node in _actionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncActionFocusNodes(int count) {
    final extraCount = math.max(0, count - 1);
    while (_actionFocusNodes.length > extraCount) {
      _actionFocusNodes.removeLast().dispose();
    }
    while (_actionFocusNodes.length < extraCount) {
      final index = _actionFocusNodes.length + 1;
      _actionFocusNodes.add(
        FocusNode(debugLabel: 'tv-user-addon-action-$index'),
      );
    }
  }

  FocusNode _actionNode(int index) {
    if (index == 0) return _firstFocusNode;
    return _actionFocusNodes[index - 1];
  }

  void _focusAction(int index) {
    final node = _actionNode(index);
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(150),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      _TvSettingsAction(
        title: 'Enabled',
        subtitle:
            'Allow this saved add-on to participate in TV source choices.',
        value: _enabled ? 'On' : 'Off',
        icon: Icons.power_settings_new_rounded,
        onPressed: () {
          final next = !_enabled;
          setState(() => _enabled = next);
          widget.onEnabledChanged(next);
        },
      ),
      _TvSettingsAction(
        title: 'Remove add-on',
        subtitle: 'Remove this saved source from this TV.',
        value: 'Remove',
        icon: Icons.delete_outline_rounded,
        onPressed: widget.onRemove,
      ),
    ];
    _syncActionFocusNodes(actions.length);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 160, vertical: 70),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 500),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: _tvSpacing),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.addon.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _tvTheme.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Text(
                'Manage this source by safe label. Private links stay hidden.',
                style: TextStyle(
                  color: _tvTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var index = 0; index < actions.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _tvSpacing),
                          child: _TvSettingsLineCard(
                            action: actions[index],
                            autofocus: index == 0,
                            focusNode: _actionNode(index),
                            onArrowUp: index == 0
                                ? () => _focusAction(index)
                                : () => _focusAction(index - 1),
                            onArrowDown: index == actions.length - 1
                                ? () => _focusAction(0)
                                : () => _focusAction(index + 1),
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

class _TvAccentSelection {
  const _TvAccentSelection(this.accent, this.color);

  final String accent;
  final Color color;
}

class _TvAccentOption {
  const _TvAccentOption(this.label, this.color);

  final String label;
  final Color color;
}

const _tvAccentOptions = [
  _TvAccentOption('Green', Color(0xFF1DB954)),
  _TvAccentOption('Purple', Color(0xFF9B6DFF)),
  _TvAccentOption('Ocean', Color(0xFF00A8CC)),
  _TvAccentOption('Amber', Color(0xFFFFB703)),
];

class _TvAccentPickerDialog extends StatefulWidget {
  const _TvAccentPickerDialog({required this.settings});

  final _TvSettingsState settings;

  @override
  State<_TvAccentPickerDialog> createState() => _TvAccentPickerDialogState();
}

class _TvAccentPickerDialogState extends State<_TvAccentPickerDialog> {
  late final List<FocusNode> _nodes = [
    for (final option in _tvAccentOptions)
      FocusNode(debugLabel: 'tv-accent-${option.label}'),
    FocusNode(debugLabel: 'tv-accent-custom'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusOption(_selectedIndex);
    });
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  int get _selectedIndex {
    final index = _tvAccentOptions.indexWhere(
      (option) => option.label == widget.settings.accent,
    );
    if (index >= 0) return index;
    return widget.settings.accent == 'Custom' ? _tvAccentOptions.length : 0;
  }

  void _focusOption(int index) {
    if (index < 0 || index >= _nodes.length) return;
    final node = _nodes[index];
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(140),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final customColor = Color(widget.settings.customAccentColor);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _tvTheme.dialog,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _tvTheme.rowBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(_tvSpacing),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App color accent',
                  style: TextStyle(
                    color: _tvTheme.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: _tvSpacing),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var index = 0;
                            index < _tvAccentOptions.length;
                            index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _tvSpacing),
                            child: _TvAccentOptionRow(
                              label: _tvAccentOptions[index].label,
                              color: _tvAccentOptions[index].color,
                              selected: widget.settings.accent ==
                                  _tvAccentOptions[index].label,
                              focusNode: _nodes[index],
                              onArrowUp: index == 0
                                  ? () => _focusOption(index)
                                  : () => _focusOption(index - 1),
                              onArrowDown: () => _focusOption(index + 1),
                              onPressed: () => Navigator.of(context).pop(
                                _TvAccentSelection(
                                  _tvAccentOptions[index].label,
                                  _tvAccentOptions[index].color,
                                ),
                              ),
                            ),
                          ),
                        _TvAccentOptionRow(
                          label: 'Custom',
                          color: customColor,
                          selected: widget.settings.accent == 'Custom',
                          focusNode: _nodes.last,
                          custom: true,
                          onArrowUp: () => _focusOption(_nodes.length - 2),
                          onArrowDown: () => _focusOption(_nodes.length - 1),
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(_TvAccentSelection('Custom', customColor)),
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

class _TvAccentOptionRow extends StatelessWidget {
  const _TvAccentOptionRow({
    required this.label,
    required this.color,
    required this.selected,
    required this.onPressed,
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
    this.custom = false,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final bool custom;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) {
        final active = focused || selected;
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: double.infinity,
          padding: const EdgeInsets.all(_tvSpacing),
          decoration: BoxDecoration(
            color: active ? color : _tvTheme.row,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: focused
                  ? _tvSolidFocusBorder
                  : selected
                      ? color
                      : _tvTheme.rowBorder,
              width: active ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: custom ? null : color,
                  gradient: custom
                      ? const SweepGradient(
                          colors: [
                            Color(0xFFFF3B30),
                            Color(0xFFFFCC00),
                            Color(0xFF34C759),
                            Color(0xFF00C7BE),
                            Color(0xFF5856D6),
                            Color(0xFFFF2D55),
                            Color(0xFFFF3B30),
                          ],
                        )
                      : null,
                  border: Border.all(
                    color: active ? Colors.black : _tvTheme.rowBorder,
                    width: 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.black : _tvTheme.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: active ? Colors.black : _tvTheme.muted,
                size: 24,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvCustomAccentDialog extends StatefulWidget {
  const _TvCustomAccentDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_TvCustomAccentDialog> createState() => _TvCustomAccentDialogState();
}

class _TvCustomAccentDialogState extends State<_TvCustomAccentDialog> {
  static const _tones = ['Darker', 'Normal', 'Brighter'];
  static const _colors = [
    _TvAccentOption('Red', Color(0xFFFF3B30)),
    _TvAccentOption('Pink', Color(0xFFFF2D55)),
    _TvAccentOption('Purple', Color(0xFF9B6DFF)),
    _TvAccentOption('Indigo', Color(0xFF5856D6)),
    _TvAccentOption('Blue', Color(0xFF007AFF)),
    _TvAccentOption('Cyan', Color(0xFF00C7BE)),
    _TvAccentOption('Teal', Color(0xFF00A878)),
    _TvAccentOption('Green', Color(0xFF1DB954)),
    _TvAccentOption('Amber', Color(0xFFFFB703)),
    _TvAccentOption('Orange', Color(0xFFFF9500)),
  ];

  late Color _baseColor = widget.initialColor;
  var _toneIndex = 1;
  late final List<FocusNode> _colorNodes = [
    for (final color in _colors)
      FocusNode(debugLabel: 'tv-custom-accent-${color.label}'),
  ];
  late final List<FocusNode> _toneNodes = [
    for (final tone in _tones)
      FocusNode(debugLabel: 'tv-custom-accent-tone-$tone'),
  ];
  final _applyFocusNode = FocusNode(debugLabel: 'tv-custom-accent-apply');

  Color get _selectedColor {
    final hsl = HSLColor.fromColor(_baseColor);
    final lightness = switch (_tones[_toneIndex]) {
      'Darker' => math.max(0.28, hsl.lightness - 0.14),
      'Brighter' => math.min(0.72, hsl.lightness + 0.14),
      _ => hsl.lightness,
    };
    return hsl.withLightness(lightness).toColor();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusColor(0);
    });
  }

  @override
  void dispose() {
    for (final node in _colorNodes) {
      node.dispose();
    }
    for (final node in _toneNodes) {
      node.dispose();
    }
    _applyFocusNode.dispose();
    super.dispose();
  }

  void _focusColor(int index) {
    final node = _colorNodes[index.clamp(0, _colorNodes.length - 1)];
    node.requestFocus();
    _ensureVisible(node);
  }

  void _focusTone(int index) {
    final node = _toneNodes[index.clamp(0, _toneNodes.length - 1)];
    node.requestFocus();
    _ensureVisible(node);
  }

  void _focusApply() {
    _applyFocusNode.requestFocus();
    _ensureVisible(_applyFocusNode);
  }

  void _ensureVisible(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(150),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 90, vertical: 44),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 620),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _tvTheme.dialog,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _tvTheme.rowBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(_tvSpacing),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custom accent',
                  style: TextStyle(
                    color: _tvTheme.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: _tvSpacing),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var index = 0; index < _colors.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _tvSpacing),
                            child: _TvAccentOptionRow(
                              label: _colors[index].label,
                              color: _colors[index].color,
                              selected: _baseColor.toARGB32() ==
                                  _colors[index].color.toARGB32(),
                              focusNode: _colorNodes[index],
                              onArrowUp: index == 0
                                  ? () => _focusColor(index)
                                  : () => _focusColor(index - 1),
                              onArrowDown: index == _colors.length - 1
                                  ? () => _focusTone(_toneIndex)
                                  : () => _focusColor(index + 1),
                              onPressed: () {
                                setState(
                                  () => _baseColor = _colors[index].color,
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: _tvSpacing),
                        Row(
                          children: [
                            for (var index = 0;
                                index < _tones.length;
                                index++) ...[
                              Expanded(
                                child: _TvAccentToneButton(
                                  label: _tones[index],
                                  selected: _toneIndex == index,
                                  focusNode: _toneNodes[index],
                                  onArrowLeft: index == 0
                                      ? () => _focusTone(index)
                                      : () => _focusTone(index - 1),
                                  onArrowRight: index == _tones.length - 1
                                      ? () => _focusTone(index)
                                      : () => _focusTone(index + 1),
                                  onArrowUp: () =>
                                      _focusColor(_colors.length - 1),
                                  onArrowDown: _focusApply,
                                  onPressed: () =>
                                      setState(() => _toneIndex = index),
                                ),
                              ),
                              if (index != _tones.length - 1)
                                const SizedBox(width: _tvSpacing),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: _tvSpacing),
                Align(
                  alignment: Alignment.centerRight,
                  child: _TvTextButton(
                    icon: Icons.check_rounded,
                    label: 'Apply',
                    focusNode: _applyFocusNode,
                    onArrowUp: () => _focusTone(_toneIndex),
                    onPressed: () => Navigator.of(context).pop(_selectedColor),
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

class _TvAccentToneButton extends StatelessWidget {
  const _TvAccentToneButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) {
        final active = focused || selected;
        return AnimatedContainer(
          duration: _tvDuration(140),
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _tvAccentColor : _tvTheme.valuePill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused ? _tvSolidFocusBorder : _tvTheme.valuePillBorder,
              width: active ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? Colors.black : _tvTheme.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      },
    );
  }
}

class _TvSettingsOptionDialog extends StatefulWidget {
  const _TvSettingsOptionDialog({
    required this.title,
    required this.selected,
    required this.options,
  });

  final String title;
  final String selected;
  final List<String> options;

  @override
  State<_TvSettingsOptionDialog> createState() =>
      _TvSettingsOptionDialogState();
}

class _TvSettingsOptionDialogState extends State<_TvSettingsOptionDialog> {
  final List<FocusNode> _optionFocusNodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncOptionFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusOption(_selectedIndex);
    });
  }

  @override
  void dispose() {
    for (final node in _optionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  int get _selectedIndex {
    final index = widget.options.indexOf(widget.selected);
    return index < 0 ? 0 : index;
  }

  void _syncOptionFocusNodes() {
    while (_optionFocusNodes.length > widget.options.length) {
      _optionFocusNodes.removeLast().dispose();
    }
    while (_optionFocusNodes.length < widget.options.length) {
      final index = _optionFocusNodes.length;
      _optionFocusNodes.add(FocusNode(debugLabel: 'tv-settings-option-$index'));
    }
  }

  void _focusOption(int index) {
    if (index < 0 || index >= _optionFocusNodes.length) return;
    final node = _optionFocusNodes[index];
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(140),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncOptionFocusNodes();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 500),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _tvTheme.dialog,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _tvTheme.rowBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(_tvSpacing),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _tvTheme.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: _tvSpacing),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var index = 0;
                            index < widget.options.length;
                            index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _tvSpacing),
                            child: _TvSettingsOptionRow(
                              label: widget.options[index],
                              selected:
                                  widget.options[index] == widget.selected,
                              focusNode: _optionFocusNodes[index],
                              onArrowUp: index == 0
                                  ? () => _focusOption(index)
                                  : () => _focusOption(index - 1),
                              onArrowDown: index == widget.options.length - 1
                                  ? () => _focusOption(index)
                                  : () => _focusOption(index + 1),
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(widget.options[index]),
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
      ),
    );
  }
}

class _TvSettingsOptionRow extends StatelessWidget {
  const _TvSettingsOptionRow({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: selected,
      focusNode: focusNode,
      autoReveal: true,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      onPressed: onPressed,
      builder: (focused) {
        final active = focused || selected;
        final fill = active ? _tvAccentColor : _tvTheme.row;
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: focused
                  ? _tvSolidFocusBorder
                  : active
                      ? _tvAccentColor
                      : _tvTheme.rowBorder,
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: active ? Colors.black : _tvTheme.muted,
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.black : _tvTheme.text,
                  fontSize: 15,
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

class _TvConsentAcknowledgement {
  const _TvConsentAcknowledgement(this.title, this.text);

  final String title;
  final String text;
}

class _TvConsentDialog extends StatefulWidget {
  const _TvConsentDialog({
    required this.title,
    required this.intro,
    required this.confirmLabel,
    required this.acknowledgements,
  });

  final String title;
  final String intro;
  final String confirmLabel;
  final List<_TvConsentAcknowledgement> acknowledgements;

  @override
  State<_TvConsentDialog> createState() => _TvConsentDialogState();
}

class _TvConsentDialogState extends State<_TvConsentDialog> {
  final _acceptedIndexes = <int>{};

  @override
  Widget build(BuildContext context) {
    final allAccepted =
        _acceptedIndexes.length == widget.acknowledgements.length;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 140, vertical: 40),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 570),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                color: _tvTheme.text,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            Text(
              widget.intro,
              style: TextStyle(
                color: _tvTheme.muted,
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0;
                        index < widget.acknowledgements.length;
                        index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: _tvSpacing),
                        child: _TvConsentRow(
                          acknowledgement: widget.acknowledgements[index],
                          checked: _acceptedIndexes.contains(index),
                          autofocus: index == 0,
                          onPressed: () {
                            setState(() {
                              if (!_acceptedIndexes.add(index)) {
                                _acceptedIndexes.remove(index);
                              }
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: _tvSpacing),
            Row(
              children: [
                Expanded(
                  child: Text(
                    allAccepted
                        ? 'Thanks. These tools can be enabled now.'
                        : 'Check every acknowledgement to continue.',
                    style: TextStyle(
                      color: allAccepted ? _tvAccentColor : _tvTheme.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _TvTextButton(
                  icon: Icons.check_rounded,
                  label: widget.confirmLabel,
                  enabled: allAccepted,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TvConsentRow extends StatelessWidget {
  const _TvConsentRow({
    required this.acknowledgement,
    required this.checked,
    required this.onPressed,
    this.autofocus = false,
  });

  final _TvConsentAcknowledgement acknowledgement;
  final bool checked;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
      autoReveal: true,
      onPressed: onPressed,
      builder: (focused) {
        final active = focused || checked;
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: double.infinity,
          padding: const EdgeInsets.all(_tvSpacing),
          decoration: BoxDecoration(
            color: active ? _tvAccentColor : const Color(0x18FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: focused
                  ? _tvSolidFocusBorder
                  : active
                      ? _tvAccentColor
                      : const Color(0x1FFFFFFF),
              width: active ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                checked
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: active ? Colors.black : _tvTheme.muted,
                size: 25,
              ),
              const SizedBox(width: _tvSpacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      acknowledgement.title,
                      style: TextStyle(
                        color: active ? Colors.black : _tvTheme.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: _tvSpacing),
                    Text(
                      acknowledgement.text,
                      style: TextStyle(
                        color: active
                            ? Colors.black.withValues(alpha: 0.72)
                            : _tvTheme.muted,
                        fontSize: 12,
                        height: 1.28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvAddOnEntryDialog extends StatefulWidget {
  const _TvAddOnEntryDialog();

  @override
  State<_TvAddOnEntryDialog> createState() => _TvAddOnEntryDialogState();
}

class _TvAddOnEntryDialogState extends State<_TvAddOnEntryDialog> {
  final _nameController = TextEditingController();
  final _manifestController = TextEditingController();
  final _nameFocusNode = FocusNode(debugLabel: 'tv-addon-name');
  final _manifestFocusNode = FocusNode(debugLabel: 'tv-addon-manifest');
  final _saveFocusNode = FocusNode(debugLabel: 'tv-addon-save');
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _manifestController.dispose();
    _nameFocusNode.dispose();
    _manifestFocusNode.dispose();
    _saveFocusNode.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final manifest = _manifestController.text.trim();
    final uri = Uri.tryParse(manifest);
    if (name.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => _error = 'Enter a name and valid manifest URL.');
      return;
    }
    Navigator.of(context).pop(
      _TvUserAddOn(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        manifest: manifest,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 170, vertical: 50),
      child: Container(
        width: 680,
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add your own add-on',
              style: TextStyle(
                color: _tvTheme.text,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            Text(
              'Enter a display name and add-on link you trust.',
              style: TextStyle(
                color: _tvTheme.muted,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            _TvDialogTextField(
              controller: _nameController,
              icon: Icons.label_outline_rounded,
              hintText: 'Display name',
              focusNode: _nameFocusNode,
              onArrowDown: () => _manifestFocusNode.requestFocus(),
            ),
            const SizedBox(height: _tvSpacing),
            _TvDialogTextField(
              controller: _manifestController,
              icon: Icons.link_rounded,
              hintText: 'Add-on link',
              focusNode: _manifestFocusNode,
              onArrowUp: () => _nameFocusNode.requestFocus(),
              onArrowDown: () => _saveFocusNode.requestFocus(),
            ),
            if (_error != null) ...[
              const SizedBox(height: _tvSpacing),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF9A8B),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: _tvSpacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TvTextButton(
                  icon: Icons.check_rounded,
                  label: 'Save',
                  focusNode: _saveFocusNode,
                  onArrowLeft: () => _manifestFocusNode.requestFocus(),
                  onArrowUp: () => _manifestFocusNode.requestFocus(),
                  onPressed: _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TvAccountSignInResult {
  const _TvAccountSignInResult({required this.profile, required this.session});

  final TvAccountProfile profile;
  final TvAccountSession session;
}

class _TvAccountSignInDialog extends StatefulWidget {
  const _TvAccountSignInDialog({required this.api});

  final _TvApi api;

  @override
  State<_TvAccountSignInDialog> createState() => _TvAccountSignInDialogState();
}

class _TvAccountSignInDialogState extends State<_TvAccountSignInDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode(debugLabel: 'tv-account-email');
  final FocusNode _codeFocusNode = FocusNode(debugLabel: 'tv-account-code');
  final FocusNode _primaryFocusNode = FocusNode(
    debugLabel: 'tv-account-primary',
  );
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_emailFocusNode.canRequestFocus) return;
      _emailFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _emailFocusNode.dispose();
    _codeFocusNode.dispose();
    _primaryFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (_busy) return;
    if (!isSupportedTvAccountEmail(email)) {
      setState(() => _error = unsupportedTvAccountEmailMessage);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.sendAuthCode(email);
      if (!mounted) return;
      setState(() => _codeSent = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocusNode.requestFocus();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyAccountError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    if (_busy) return;
    if (!isSupportedTvAccountEmail(email)) {
      setState(() => _error = unsupportedTvAccountEmailMessage);
      return;
    }
    if (code.length < 6) {
      setState(() => _error = 'Enter the 6-digit sign-in code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.verifyAuthCode(email: email, code: code);
      if (!mounted) return;
      Navigator.of(context).pop(
        _TvAccountSignInResult(
          profile: result.profile,
          session: result.session,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyAccountError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyAccountError(Object error) {
    if (error is _TvApiException) {
      final status = error.status.toLowerCase();
      if (status.contains('rate') || status.contains('cooldown')) {
        return 'Please wait a moment before trying again.';
      }
      if (status.contains('code') || status.contains('invalid')) {
        return 'That sign-in code was not accepted.';
      }
    }
    return 'Sign-in is unavailable right now. Try again shortly.';
  }

  @override
  Widget build(BuildContext context) {
    final primaryLabel = _codeSent ? 'Verify code' : 'Send code';
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 150, vertical: 46),
      child: Container(
        width: 640,
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign in to Juicr',
              style: TextStyle(
                color: _tvTheme.text,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            Text(
              'Your email is used for sign-in and account recovery. Use a supported personal email provider.',
              style: TextStyle(
                color: _tvTheme.muted,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            _TvDialogTextField(
              controller: _emailController,
              icon: Icons.email_outlined,
              hintText: 'Email',
              focusNode: _emailFocusNode,
              onArrowDown: () => _codeSent
                  ? _codeFocusNode.requestFocus()
                  : _primaryFocusNode.requestFocus(),
            ),
            if (_codeSent) ...[
              const SizedBox(height: _tvSpacing),
              _TvDialogTextField(
                controller: _codeController,
                icon: Icons.password_rounded,
                hintText: '6-digit code',
                focusNode: _codeFocusNode,
                onArrowUp: () => _emailFocusNode.requestFocus(),
                onArrowDown: () => _primaryFocusNode.requestFocus(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: _tvSpacing),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF9A8B),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: _tvSpacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TvTextButton(
                  icon: _busy
                      ? Icons.hourglass_top_rounded
                      : Icons.arrow_forward_rounded,
                  label: _busy ? 'Please wait' : primaryLabel,
                  enabled: !_busy,
                  focusNode: _primaryFocusNode,
                  onArrowUp: () => _codeSent
                      ? _codeFocusNode.requestFocus()
                      : _emailFocusNode.requestFocus(),
                  onPressed: () =>
                      unawaited(_codeSent ? _verifyCode() : _sendCode()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TvDialogTextField extends StatelessWidget {
  const _TvDialogTextField({
    required this.controller,
    required this.icon,
    required this.hintText,
    this.enabled = true,
    this.focusNode,
    this.inputFormatters,
    this.onArrowUp,
    this.onArrowDown,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hintText;
  final bool enabled;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvEditableDialogField(
      controller: controller,
      icon: icon,
      hintText: hintText,
      enabled: enabled,
      focusNode: focusNode,
      inputFormatters: inputFormatters,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
    );
  }
}

class _TvEditableDialogField extends StatefulWidget {
  const _TvEditableDialogField({
    required this.controller,
    required this.icon,
    required this.hintText,
    this.enabled = true,
    this.focusNode,
    this.inputFormatters,
    this.onArrowUp,
    this.onArrowDown,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hintText;
  final bool enabled;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  State<_TvEditableDialogField> createState() => _TvEditableDialogFieldState();
}

class _TvEditableDialogFieldState extends State<_TvEditableDialogField> {
  late final FocusNode _ownedShellFocusNode = FocusNode(
    debugLabel: 'tv-dialog-edit-shell',
  );
  final FocusNode _textFocusNode = FocusNode(debugLabel: 'tv-dialog-edit-text');
  bool _editing = false;
  FocusNode get _shellFocusNode => widget.focusNode ?? _ownedShellFocusNode;

  @override
  void initState() {
    super.initState();
    _textFocusNode
      ..canRequestFocus = false
      ..skipTraversal = true;
  }

  @override
  void dispose() {
    _ownedShellFocusNode.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  void _beginEditing() {
    if (!widget.enabled) return;
    _textFocusNode
      ..canRequestFocus = true
      ..skipTraversal = false;
    setState(() => _editing = true);
    _textFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_editing) {
        _textFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
    });
  }

  void _endEditing() {
    if (!_editing) return;
    _textFocusNode
      ..canRequestFocus = false
      ..skipTraversal = true;
    setState(() => _editing = false);
    _shellFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  @override
  Widget build(BuildContext context) {
    _textFocusNode
      ..canRequestFocus = _editing
      ..skipTraversal = !_editing;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              if (_editing) {
                _endEditing();
                return null;
              }
              Navigator.of(context).maybePop();
              return null;
            },
          ),
        },
        child: _TvFocusable(
          focusNode: _shellFocusNode,
          autoReveal: true,
          descendantsAreFocusable: true,
          enabled: widget.enabled,
          onPressed: _editing ? () {} : _beginEditing,
          onArrowUp: widget.onArrowUp,
          onArrowDown: widget.onArrowDown,
          builder: (focused) {
            final active = focused || _textFocusNode.hasFocus || _editing;
            return GestureDetector(
              onTap: _beginEditing,
              child: AnimatedContainer(
                duration: _tvDuration(130),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: active ? _tvFocusBorder : _tvTheme.rowBorder,
                    width: active ? 2 : 1,
                  ),
                ),
                child: TextField(
                  controller: widget.controller,
                  focusNode: _textFocusNode,
                  enabled: widget.enabled,
                  inputFormatters: widget.inputFormatters,
                  readOnly: !_editing,
                  onTap: _beginEditing,
                  onTapOutside: (_) => _endEditing(),
                  onEditingComplete: _endEditing,
                  onSubmitted: (_) => _endEditing(),
                  style: TextStyle(
                    color: _tvTheme.text,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    prefixIcon: Icon(widget.icon, color: _tvTheme.muted),
                    hintText: widget.hintText,
                    hintStyle: TextStyle(
                      color: _tvTheme.muted,
                      fontWeight: FontWeight.w700,
                    ),
                    filled: true,
                    fillColor: _tvTheme.row,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TvSettingsSection {
  const _TvSettingsSection(this.title, this.subtitle, this.icon, this.lines);

  final String title;
  final String subtitle;
  final IconData icon;
  final List<_TvSettingsLine> lines;
}

class _TvSettingsLine {
  const _TvSettingsLine(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

class _TvDetailsPage extends StatefulWidget {
  const _TvDetailsPage({
    required this.item,
    required this.settings,
    required this.liked,
    required this.libraryLists,
    required this.onCancelPreparing,
    required this.onPlay,
    required this.onPlayEpisode,
    required this.onOpenItem,
    required this.onToggleSaved,
    required this.onCreateList,
    required this.onToggleList,
    required this.isItemSaved,
    required this.isItemInList,
    required this.progressForPlayback,
  });

  final _TvItem item;
  final _TvSettingsState settings;
  final bool liked;
  final List<TvLibraryList> libraryLists;
  final VoidCallback onCancelPreparing;
  final Future<void> Function(_TvItem item) onPlay;
  final Future<void> Function(_TvItem item, int season, int episode)
      onPlayEpisode;
  final Future<void> Function(_TvItem item) onOpenItem;
  final ValueChanged<_TvItem> onToggleSaved;
  final Future<TvLibraryList?> Function(_TvItem item, String name) onCreateList;
  final Future<bool> Function(_TvItem item, TvLibraryList list) onToggleList;
  final bool Function(_TvItem item) isItemSaved;
  final bool Function(_TvItem item, TvLibraryList list) isItemInList;
  final _TvPlaybackProgress? Function(_TvItem item, int season, int episode)
      progressForPlayback;

  @override
  State<_TvDetailsPage> createState() => _TvDetailsPageState();
}

class _TvDetailsPageState extends State<_TvDetailsPage> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _backFocusNode = FocusNode(
    debugLabel: 'tv-details-page-back',
  );
  final FocusNode _watchFocusNode = FocusNode(
    debugLabel: 'tv-details-page-watch',
  );
  final FocusNode _episodesFocusNode = FocusNode(
    debugLabel: 'tv-details-page-episodes',
  );
  final FocusNode _trailerFocusNode = FocusNode(
    debugLabel: 'tv-details-page-trailer',
  );
  final FocusNode _libraryFocusNode = FocusNode(
    debugLabel: 'tv-details-page-library',
  );
  final FocusNode _recommendationsFocusNode = FocusNode(
    debugLabel: 'tv-details-page-recommendations-first',
  );
  final FocusNode _castFocusNode = FocusNode(
    debugLabel: 'tv-details-page-cast-first',
  );
  final FocusNode _directorFocusNode = FocusNode(
    debugLabel: 'tv-details-page-director-first',
  );
  final FocusNode _episodeListFocusNode = FocusNode(
    debugLabel: 'tv-details-page-episode-list-first',
  );
  late Future<_TvItem> _detailsFuture;
  late Future<List<_TvItem>> _recommendationsFuture;
  _TvItem? _details;
  bool _preparing = false;
  bool _saved = false;
  bool _detailsFocusRestoreQueued = false;
  late DateTime _detailsInitialFocusGuardUntil;

  _TvItem get _current => _details ?? widget.item;

  List<FocusNode> get _managedDetailsFocusNodes => [
        _backFocusNode,
        _watchFocusNode,
        _episodesFocusNode,
        _trailerFocusNode,
        _libraryFocusNode,
        _recommendationsFocusNode,
        _castFocusNode,
        _directorFocusNode,
        _episodeListFocusNode,
      ];

  bool get _isSeriesLike =>
      (_current.type == 'series' || _current.type == 'animation') &&
      _current.episodes.isNotEmpty;

  bool get _detailsFocusIsValid {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final focusContext = primaryFocus?.context;
    if (focusContext == null ||
        !focusContext.mounted ||
        primaryFocus == FocusManager.instance.rootScope) {
      return false;
    }
    if (!_focusIsInsideDetailsRoute(focusContext)) return false;
    if (_managedDetailsFocusNodes.contains(primaryFocus)) return true;
    final debugLabel = primaryFocus?.debugLabel ?? '';
    if (_detailsInitialFocusGuardActive &&
        (debugLabel.startsWith('tv-details-recommendation') ||
            debugLabel.startsWith('tv-details-cast') ||
            debugLabel.startsWith('tv-details-director') ||
            debugLabel.startsWith('tv-details-episode'))) {
      return false;
    }
    return primaryFocus?.canRequestFocus == true &&
        debugLabel.startsWith('tv-details');
  }

  bool get _detailsRouteIsCurrent => ModalRoute.of(context)?.isCurrent == true;

  bool get _detailsInitialFocusGuardActive =>
      DateTime.now().isBefore(_detailsInitialFocusGuardUntil);

  @override
  void initState() {
    super.initState();
    _saved = widget.liked;
    _detailsInitialFocusGuardUntil = DateTime.now().add(
      const Duration(milliseconds: 900),
    );
    _detailsFuture = _loadDetails();
    _recommendationsFuture = _loadRecommendations();
    FocusManager.instance.addListener(_handleDetailsPrimaryFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreDetailsFocusIfNeeded();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.minScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleDetailsPrimaryFocusChanged);
    _scrollController.dispose();
    _backFocusNode.dispose();
    _watchFocusNode.dispose();
    _episodesFocusNode.dispose();
    _trailerFocusNode.dispose();
    _libraryFocusNode.dispose();
    _recommendationsFocusNode.dispose();
    _castFocusNode.dispose();
    _directorFocusNode.dispose();
    _episodeListFocusNode.dispose();
    super.dispose();
  }

  void _handleDetailsPrimaryFocusChanged() {
    if (!mounted || !_detailsRouteIsCurrent || _detailsFocusIsValid) return;
    _restoreDetailsFocusIfNeeded();
  }

  void _requestDetailsFocusAfterBuild(
    FocusNode node, {
    double alignment = 0.28,
    bool fallbackToTop = false,
    bool keepTopVisible = false,
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentContext = node.context;
      if (!mounted) return;
      if (currentContext == null ||
          !currentContext.mounted ||
          !node.canRequestFocus) {
        if (attempt < 6) {
          Future<void>.delayed(
            _tvDuration(35 + attempt * 25),
            () => _requestDetailsFocusAfterBuild(
              node,
              alignment: alignment,
              fallbackToTop: fallbackToTop,
              keepTopVisible: keepTopVisible,
              attempt: attempt + 1,
            ),
          );
        } else if (fallbackToTop && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.minScrollExtent,
            duration: _tvDuration(180),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }
      node.requestFocus();
      if (!node.hasFocus) return;
      if (keepTopVisible) {
        _jumpDetailsToTopAfterFocus();
        return;
      }
      Scrollable.ensureVisible(
        currentContext,
        duration: _tvDuration(180),
        curve: Curves.easeOutCubic,
        alignment: alignment,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  void _focusDetailsNode(FocusNode node, {double alignment = 0.28}) {
    _requestDetailsFocusAfterBuild(node, alignment: alignment);
  }

  void _focusDetailsHeroNode(FocusNode node) {
    if (!mounted) return;
    _requestDetailsFocusAfterBuild(
      node,
      alignment: 0.1,
      fallbackToTop: true,
      keepTopVisible: true,
    );
  }

  void _jumpDetailsToTopAfterFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    });
  }

  void _scrollDetailsLower() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (_scrollController.offset + 260).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: _tvDuration(180),
      curve: Curves.easeOutCubic,
    );
  }

  void _focusFirstLowerDetails(_TvItem item) {
    if (_recommendationsFocusNode.context != null) {
      _focusDetailsNode(_recommendationsFocusNode, alignment: 0.24);
    } else if (item.castPeople.isNotEmpty && _castFocusNode.context != null) {
      _focusDetailsNode(_castFocusNode, alignment: 0.32);
    } else if (item.directorPeople.isNotEmpty &&
        _directorFocusNode.context != null) {
      _focusDetailsNode(_directorFocusNode, alignment: 0.32);
    } else if (_isSeriesLike && _episodeListFocusNode.context != null) {
      _focusDetailsNode(_episodeListFocusNode, alignment: 0.32);
    } else {
      _scrollDetailsLower();
    }
  }

  void _focusAfterRecommendations(_TvItem item) {
    if (item.castPeople.isNotEmpty && _castFocusNode.context != null) {
      _focusDetailsNode(_castFocusNode, alignment: 0.32);
    } else if (item.directorPeople.isNotEmpty &&
        _directorFocusNode.context != null) {
      _focusDetailsNode(_directorFocusNode, alignment: 0.32);
    } else if (_isSeriesLike && _episodeListFocusNode.context != null) {
      _focusDetailsNode(_episodeListFocusNode, alignment: 0.32);
    } else {
      _scrollDetailsLower();
    }
  }

  void _focusDetailsActions() {
    _focusDetailsHeroNode(_watchFocusNode);
  }

  bool _focusIsInsideDetailsRoute(BuildContext focusContext) {
    if (identical(focusContext, context)) return true;
    var inside = false;
    (focusContext as Element).visitAncestorElements((ancestor) {
      if (identical(ancestor, context)) {
        inside = true;
        return false;
      }
      return true;
    });
    return inside;
  }

  void _restoreDetailsFocusIfNeeded([int attempt = 0]) {
    if (_detailsFocusRestoreQueued && attempt == 0) return;
    _detailsFocusRestoreQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _detailsFocusRestoreQueued = false;
      if (!mounted) return;
      if (!_detailsRouteIsCurrent) return;
      if (_detailsFocusIsValid) return;
      final target = _watchFocusNode.context != null &&
              _watchFocusNode.canRequestFocus &&
              !_preparing
          ? _watchFocusNode
          : _backFocusNode;
      if (target.context == null || !target.canRequestFocus) {
        if (attempt < 3) {
          Future<void>.delayed(
            _tvDuration(40 + (attempt * 30)),
            () => _restoreDetailsFocusIfNeeded(attempt + 1),
          );
        }
        return;
      }
      _focusDetailsHeroNode(target);
    });
  }

  KeyEventResult _handleDetailsRouteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isNavigationKey = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
    if (!isNavigationKey || _detailsFocusIsValid) {
      return KeyEventResult.ignored;
    }
    _restoreDetailsFocusIfNeeded();
    return KeyEventResult.handled;
  }

  void _focusRecommendationsOrActions() {
    if (_recommendationsFocusNode.context != null) {
      _focusDetailsNode(_recommendationsFocusNode, alignment: 0.24);
      return;
    }
    _focusDetailsActions();
  }

  void _focusCastOrPrevious(_TvItem item) {
    if (item.castPeople.isNotEmpty && _castFocusNode.context != null) {
      _focusDetailsNode(_castFocusNode, alignment: 0.32);
      return;
    }
    _focusRecommendationsOrActions();
  }

  void _focusAfterCast(_TvItem item) {
    if (item.directorPeople.isNotEmpty && _directorFocusNode.context != null) {
      _focusDetailsNode(_directorFocusNode, alignment: 0.32);
    } else if (_isSeriesLike && _episodeListFocusNode.context != null) {
      _focusDetailsNode(_episodeListFocusNode, alignment: 0.32);
    } else {
      _scrollDetailsLower();
    }
  }

  void _focusBeforeEpisodes(_TvItem item) {
    if (item.directorPeople.isNotEmpty && _directorFocusNode.context != null) {
      _focusDetailsNode(_directorFocusNode, alignment: 0.32);
    } else if (item.castPeople.isNotEmpty && _castFocusNode.context != null) {
      _focusDetailsNode(_castFocusNode, alignment: 0.32);
    } else {
      _focusRecommendationsOrActions();
    }
  }

  Future<_TvItem> _loadDetails() async {
    try {
      final item =
          await _TvApi().meta(widget.item).timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() => _details = item);
        _restoreDetailsFocusIfNeeded();
      }
      return item;
    } catch (_) {
      return widget.item;
    }
  }

  Future<List<_TvItem>> _loadRecommendations() async {
    final item = await _detailsFuture;
    final recommendations = await _TvApi().recommendations(item);
    if (mounted) _restoreDetailsFocusIfNeeded();
    return recommendations;
  }

  Future<void> _scrollDetailsToTop() async {
    if (!_scrollController.hasClients) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;
    final target = _scrollController.position.minScrollExtent;
    if ((_scrollController.offset - target).abs() >= 1) {
      await _scrollController.animateTo(
        target,
        duration: _tvDuration(320),
        curve: Curves.easeOutCubic,
      );
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;
    final correctedTarget = _scrollController.position.minScrollExtent;
    if ((_scrollController.offset - correctedTarget).abs() >= 1) {
      _scrollController.jumpTo(correctedTarget);
    }
  }

  Future<void> _runPreparing(Future<void> Function() action) async {
    if (_preparing) return;
    setState(() => _preparing = true);
    try {
      await _scrollDetailsToTop();
      await action();
    } finally {
      if (mounted) {
        setState(() => _preparing = false);
        _detailsInitialFocusGuardUntil = DateTime.now().add(
          const Duration(milliseconds: 650),
        );
        _restoreDetailsFocusIfNeeded();
        _focusDetailsHeroNode(_watchFocusNode);
      }
    }
  }

  void _cancelPreparingAndStay() {
    if (!_preparing) return;
    widget.onCancelPreparing();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (mounted) setState(() => _preparing = false);
  }

  void _handleBack() {
    if (_preparing) {
      _cancelPreparingAndStay();
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _showTrailerPicker() async {
    if (!widget.settings.builtInTrailers) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Enable trailers in Settings before opening trailer choices.',
            ),
          ),
        );
      return;
    }
    final trailers = await _TvApi()
        .trailers(_current)
        .timeout(const Duration(seconds: 18))
        .catchError((_) => const <_TvTrailer>[]);
    if (!mounted) return;
    if (trailers.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No TV trailer is available yet.')),
        );
      return;
    }
    final selected = trailers.firstWhere(
      (trailer) => trailer.isTvPlayable || trailer.isExternalLaunchable,
      orElse: () => trailers.first,
    );
    if (selected.isExternalLaunchable) {
      final opened = await _openTvExternalTrailer(selected);
      if (!mounted || opened) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No TV app can open this trailer yet.')),
        );
      return;
    }
    if (!selected.isTvPlayable) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('This trailer is not ready for TV yet.'),
          ),
        );
      return;
    }
    final trailerItem = _TvItem(
      id: '${_current.id}:trailer',
      type: _current.type,
      title: '${_current.title} trailer',
      color: _current.color,
      poster: _current.poster,
      background: _current.background,
    );
    final previousFocus = FocusManager.instance.primaryFocus;
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => _TvPlaybackPage(
          item: trailerItem,
          sessions: [
            _PlaybackSession(
              mediaUrl: selected.url,
              sourceType: selected.sourceType,
              httpHeaders: _TvApi.juicrMediaHeaders,
            ),
          ],
          initialSessionIndex: 0,
          initialSeason: 1,
          initialEpisode: 1,
          initialResumePosition: Duration.zero,
          settings: widget.settings,
          subtitles: const <_TvSubtitle>[],
          initialSubtitleIndex: -1,
        ),
      ),
    );
    if (!mounted) return;
    _restoreTvFocusAfterRoutePop(previousFocus);
    if (result is _TvPlaybackUnavailable) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(result.message),
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  Future<void> _showLibraryMenu() async {
    final saved = widget.isItemSaved(_current) || _saved;
    final action = await _showTvDialog<_TvLibraryAction>(
      context: context,
      builder: (_) => _TvLibraryActionDialog(saved: saved),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _TvLibraryAction.toggleSaved:
        widget.onToggleSaved(_current);
        setState(() => _saved = !saved);
      case _TvLibraryAction.addToList:
        await _showListPicker();
    }
  }

  Future<void> _showListPicker() async {
    final result = await _showTvDialog<Object>(
      context: context,
      builder: (_) => _TvListPickerDialog(
        item: _current,
        lists: widget.libraryLists,
        isItemInList: widget.isItemInList,
      ),
    );
    if (!mounted || result == null) return;
    if (result is TvLibraryList) {
      final selected = await widget.onToggleList(_current, result);
      setState(() => _saved = true);
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
      final list = await widget.onCreateList(_current, result);
      setState(() => _saved = true);
      if (!mounted || list == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Added to ${list.name}')));
    }
  }

  ({_TvEpisode episode, _TvPlaybackProgress progress})? _latestEpisodeProgress(
    _TvItem item,
  ) {
    final episodes = item.episodes.toList(growable: false)
      ..sort((left, right) {
        final seasonCompare = left.season.compareTo(right.season);
        if (seasonCompare != 0) return seasonCompare;
        return left.episode.compareTo(right.episode);
      });
    ({_TvEpisode episode, _TvPlaybackProgress progress})? best;
    for (final episode in episodes) {
      final progress = widget.progressForPlayback(
        item,
        episode.season,
        episode.episode,
      );
      if (progress != null && progress.position > Duration.zero) {
        if (best == null ||
            episode.season > best.episode.season ||
            (episode.season == best.episode.season &&
                episode.episode > best.episode.episode) ||
            (episode.season == best.episode.season &&
                episode.episode == best.episode.episode &&
                progress.position > best.progress.position)) {
          best = (episode: episode, progress: progress);
        }
      }
    }
    return best;
  }

  List<Widget> _actions(_TvItem item) {
    final episodeProgress = _isSeriesLike ? _latestEpisodeProgress(item) : null;
    final primaryProgress =
        episodeProgress?.progress ?? widget.progressForPlayback(item, 1, 1);
    final hasPrimaryProgress =
        primaryProgress != null && primaryProgress.position > Duration.zero;
    final primaryLabel = _preparing
        ? 'Preparing'
        : episodeProgress != null
            ? 'Continue | S${episodeProgress.episode.season} E${episodeProgress.episode.episode}'
            : hasPrimaryProgress
                ? 'Continue'
                : 'Watch now';
    final primaryAction = episodeProgress == null
        ? () => widget.onPlay(item)
        : () => widget.onPlayEpisode(
              item,
              episodeProgress.episode.season,
              episodeProgress.episode.episode,
            );
    return [
      _TvTextButton(
        focusNode: _watchFocusNode,
        autofocus: true,
        icon:
            _preparing ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
        label: primaryLabel,
        enabled: !_preparing,
        animateIcon: _preparing,
        autoReveal: false,
        onArrowLeft: _backFocusNode.requestFocus,
        onArrowRight: _trailerFocusNode.requestFocus,
        onArrowUp: () => _focusDetailsHeroNode(_backFocusNode),
        onArrowDown: () => _focusFirstLowerDetails(item),
        onPressed: () => _runPreparing(primaryAction),
      ),
      _TvTextButton(
        focusNode: _trailerFocusNode,
        icon: Icons.movie_filter_rounded,
        label: 'Trailer',
        enabled: !_preparing,
        autoReveal: false,
        onArrowLeft: _watchFocusNode.requestFocus,
        onArrowRight: _libraryFocusNode.requestFocus,
        onArrowUp: () => _focusDetailsHeroNode(_backFocusNode),
        onArrowDown: () => _focusFirstLowerDetails(item),
        onPressed: _showTrailerPicker,
      ),
      _TvTextButton(
        focusNode: _libraryFocusNode,
        icon: Icons.more_horiz_rounded,
        label: 'More',
        enabled: !_preparing,
        autoReveal: false,
        onArrowLeft: _trailerFocusNode.requestFocus,
        onArrowRight: _libraryFocusNode.requestFocus,
        onArrowUp: () => _focusDetailsHeroNode(_backFocusNode),
        onArrowDown: () => _focusFirstLowerDetails(item),
        onPressed: _showLibraryMenu,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _restoreDetailsFocusIfNeeded();
    return PopScope(
      canPop: !_preparing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_preparing) {
          _cancelPreparingAndStay();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
          },
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  _handleBack();
                  return null;
                },
              ),
            },
            child: Focus(
              onKeyEvent: _handleDetailsRouteKey,
              child: FutureBuilder<_TvItem>(
                future: _detailsFuture,
                builder: (context, snapshot) {
                  final item = snapshot.data ?? _current;
                  final detailsLoading =
                      snapshot.connectionState == ConnectionState.waiting &&
                          _details == null;
                  return CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildHero(item, detailsLoading: detailsLoading),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(48, 14, 48, 54),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _TvRecommendationsSection(
                              future: _recommendationsFuture,
                              onOpenItem: widget.onOpenItem,
                              firstFocusNode: _recommendationsFocusNode,
                              onArrowUp: _focusDetailsActions,
                              onArrowDown: () =>
                                  _focusAfterRecommendations(item),
                            ),
                            if (item.genres.isNotEmpty)
                              _TvDetailsSection(
                                title: 'Genres',
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    for (final genre in item.genres.take(8))
                                      _TvInfoChip(label: genre),
                                  ],
                                ),
                              ),
                            if (item.castPeople.isNotEmpty)
                              _TvPeopleSection(
                                title: 'Cast',
                                people: item.castPeople,
                                firstFocusNode: _castFocusNode,
                                onArrowUp: _focusRecommendationsOrActions,
                                onArrowDown: () => _focusAfterCast(item),
                              ),
                            if (item.directorPeople.isNotEmpty)
                              _TvPeopleSection(
                                title: 'Director',
                                people: item.directorPeople,
                                firstFocusNode: _directorFocusNode,
                                onArrowUp: item.castPeople.isNotEmpty
                                    ? () => _focusCastOrPrevious(item)
                                    : _focusRecommendationsOrActions,
                                onArrowDown: _isSeriesLike
                                    ? () => _focusDetailsNode(
                                          _episodeListFocusNode,
                                          alignment: 0.32,
                                        )
                                    : _scrollDetailsLower,
                              ),
                            if (_isSeriesLike)
                              _TvEpisodesSection(
                                episodes: item.episodes,
                                progressForEpisode: (episode) =>
                                    widget.progressForPlayback(
                                  item,
                                  episode.season,
                                  episode.episode,
                                ),
                                firstFocusNode: _episodeListFocusNode,
                                onArrowUp: () => _focusBeforeEpisodes(item),
                                onPlay: (episode) => _runPreparing(
                                  () => widget.onPlayEpisode(
                                    item,
                                    episode.season,
                                    episode.episode,
                                  ),
                                ),
                              ),
                          ]),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(_TvItem item, {required bool detailsLoading}) {
    final background = item.background ?? item.poster;
    final actionButtons = _actions(item);
    final hasOverview = (item.description ?? '').trim().isNotEmpty;
    return SizedBox(
      height: _tvDetailsHeroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (background != null)
            Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: -_tvDetailsHeroBackdropOverscan,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Image.network(
                      background,
                      fit: BoxFit.cover,
                      cacheWidth: 1600,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) =>
                          const _TvShimmerBox(radius: 0, alpha: 0.42),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: -_tvDetailsHeroBackdropOverscan,
                  child: Image.network(
                    background,
                    fit: BoxFit.cover,
                    cacheWidth: 1600,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    alignment: Alignment.topCenter,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const _TvShimmerBox(radius: 0, alpha: 0.42);
                    },
                    errorBuilder: (_, __, ___) =>
                        const _TvShimmerBox(radius: 0, alpha: 0.42),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: _tvDetailsHeroBottomBlurHeight,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(color: Color(0x10000000)),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            const _TvShimmerBox(radius: 0, alpha: 0.42),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x88000000), Color(0xEE000000)],
              ),
            ),
          ),
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
          Positioned(
            top: 28,
            left: 38,
            child: _TvTextButton(
              focusNode: _backFocusNode,
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onArrowRight: _watchFocusNode.requestFocus,
              onArrowDown: _watchFocusNode.requestFocus,
              onPressed: _handleBack,
            ),
          ),
          Positioned(
            left: 48,
            right: 48,
            bottom: 26,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TvHeroTitleWheel(item: item),
                      if (detailsLoading) ...[
                        const SizedBox(height: _tvSpacing),
                        const _TvDetailsHeroMetadataSkeleton(),
                      ] else if (item.subtitle.isNotEmpty) ...[
                        const SizedBox(height: _tvSpacing),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _tvAccentColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: _tvSpacing),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 650),
                              child: detailsLoading
                                  ? const _TvDetailsHeroOverviewSkeleton()
                                  : hasOverview
                                      ? _TvDetailsHeroOverview(
                                          text: item.description!.trim(),
                                        )
                                      : const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(width: 16),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 450),
                            child: Wrap(
                              spacing: _tvSpacing,
                              runSpacing: _tvSpacing,
                              children: actionButtons,
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
    );
  }
}

class _TvDetailsHeroOverview extends StatefulWidget {
  const _TvDetailsHeroOverview({required this.text});

  final String text;

  @override
  State<_TvDetailsHeroOverview> createState() => _TvDetailsHeroOverviewState();
}

class _TvDetailsHeroMetadataSkeleton extends StatelessWidget {
  const _TvDetailsHeroMetadataSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _TvShimmerBox(
      width: 430,
      height: 19,
      radius: 99,
      alpha: 0.38,
    );
  }
}

class _TvDetailsHeroOverviewSkeleton extends StatelessWidget {
  const _TvDetailsHeroOverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 82,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TvShimmerBox(width: 650, height: 16, radius: 99, alpha: 0.32),
          SizedBox(height: 9),
          _TvShimmerBox(width: 610, height: 16, radius: 99, alpha: 0.30),
          SizedBox(height: 9),
          _TvShimmerBox(width: 520, height: 16, radius: 99, alpha: 0.28),
        ],
      ),
    );
  }
}

class _TvDetailsHeroOverviewState extends State<_TvDetailsHeroOverview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _style = TextStyle(
    color: Color(0xD1FFFFFF),
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w700,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 18000),
    );
    if (_tvMotionEnabled) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _TvDetailsHeroOverview oldWidget) {
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
        final width = constraints.maxWidth;
        const maxHeight = 96.0;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: _style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width.isFinite ? width : 690);
        final visibleHeight = painter.height.clamp(20.0, maxHeight).toDouble();
        if (!_tvMotionEnabled || painter.height <= maxHeight) {
          return SizedBox(
            height: visibleHeight,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                widget.text,
                maxLines: 5,
                overflow: TextOverflow.fade,
                style: _style,
              ),
            ),
          );
        }
        final distance = painter.height - maxHeight + 10;
        return SizedBox(
          height: maxHeight,
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
                width: width,
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

enum _TvLibraryAction { addToList, toggleSaved }

class _TvLibraryActionDialog extends StatelessWidget {
  const _TvLibraryActionDialog({required this.saved});

  final bool saved;

  @override
  Widget build(BuildContext context) {
    return _TvChoiceDialog<_TvLibraryAction>(
      title: 'Library',
      subtitle: 'Save this title or organize it in a list.',
      values: const [_TvLibraryAction.addToList, _TvLibraryAction.toggleSaved],
      labelFor: (action) => switch (action) {
        _TvLibraryAction.addToList => 'Add to List',
        _TvLibraryAction.toggleSaved =>
          saved ? 'Remove from Library' : 'Save to Library',
      },
      iconFor: (action) => switch (action) {
        _TvLibraryAction.addToList => Icons.bookmark_add_outlined,
        _TvLibraryAction.toggleSaved =>
          saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      },
    );
  }
}

class _TvListPickerDialog extends StatefulWidget {
  const _TvListPickerDialog({
    required this.item,
    required this.lists,
    required this.isItemInList,
  });

  final _TvItem item;
  final List<TvLibraryList> lists;
  final bool Function(_TvItem item, TvLibraryList list) isItemInList;

  @override
  State<_TvListPickerDialog> createState() => _TvListPickerDialogState();
}

class _TvListPickerDialogState extends State<_TvListPickerDialog> {
  bool _creating = false;
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_creating) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 620,
          padding: const EdgeInsets.all(_tvSpacing),
          decoration: BoxDecoration(
            color: _tvTheme.dialog,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _tvTheme.rowBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create list',
                style: TextStyle(
                  color: _tvTheme.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: _tvSpacing),
              TextField(
                controller: _controller,
                autofocus: true,
                style: TextStyle(color: _tvTheme.text),
                decoration: InputDecoration(
                  hintText: 'List name',
                  hintStyle: TextStyle(color: _tvTheme.muted),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) Navigator.of(context).pop(value);
                },
              ),
              const SizedBox(height: _tvSpacing),
              Row(
                children: [
                  _TvTextButton(
                    icon: Icons.check_rounded,
                    label: 'Create',
                    onPressed: () {
                      final value = _controller.text.trim();
                      if (value.isNotEmpty) Navigator.of(context).pop(value);
                    },
                  ),
                  const SizedBox(width: _tvSpacing),
                  _TvTextButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Back',
                    onPressed: () => setState(() => _creating = false),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return _TvChoiceDialog<Object>(
      title: 'Add to List',
      subtitle: widget.lists.isEmpty
          ? 'Create a list for this title.'
          : 'Choose one of your lists.',
      values: <Object>['__create__', ...widget.lists],
      labelFor: (value) =>
          value is TvLibraryList ? value.name : 'Create new list',
      iconFor: (value) => value is TvLibraryList
          ? widget.isItemInList(widget.item, value)
              ? Icons.check_rounded
              : Icons.bookmark_border_rounded
          : Icons.add_rounded,
      onSelected: (value) {
        if (value is String) {
          setState(() => _creating = true);
        } else {
          Navigator.of(context).pop(value);
        }
      },
    );
  }
}

class _TvChoiceDialog<T> extends StatefulWidget {
  const _TvChoiceDialog({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.labelFor,
    required this.iconFor,
    this.onSelected,
  });

  final String title;
  final String subtitle;
  final List<T> values;
  final String Function(T value) labelFor;
  final IconData Function(T value) iconFor;
  final ValueChanged<T>? onSelected;

  @override
  State<_TvChoiceDialog<T>> createState() => _TvChoiceDialogState<T>();
}

class _TvChoiceDialogState<T> extends State<_TvChoiceDialog<T>> {
  late final List<FocusNode> _nodes = [
    for (var index = 0; index < widget.values.length; index++)
      FocusNode(debugLabel: 'tv-choice-$index'),
  ];

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 520),
        padding: const EdgeInsets.all(_tvSpacing),
        decoration: BoxDecoration(
          color: _tvTheme.dialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _tvTheme.rowBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _tvTheme.text,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            Text(
              widget.subtitle,
              style: TextStyle(
                color: _tvTheme.muted,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: _tvSpacing),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < widget.values.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: _tvSpacing),
                        child: SizedBox(
                          width: double.infinity,
                          child: _TvTextButton(
                            focusNode: _nodes[index],
                            autofocus: index == 0,
                            icon: widget.iconFor(widget.values[index]),
                            label: widget.labelFor(widget.values[index]),
                            onArrowUp: index == 0
                                ? () => _nodes[index].requestFocus()
                                : () => _nodes[index - 1].requestFocus(),
                            onArrowDown: index == widget.values.length - 1
                                ? () => _nodes[index].requestFocus()
                                : () => _nodes[index + 1].requestFocus(),
                            onPressed: () {
                              final value = widget.values[index];
                              final handler = widget.onSelected;
                              if (handler != null) {
                                handler(value);
                              } else {
                                Navigator.of(context).pop(value);
                              }
                            },
                          ),
                        ),
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

class _TvDetailsSection extends StatelessWidget {
  const _TvDetailsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _tvSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: _tvSpacing),
          child,
        ],
      ),
    );
  }
}

class _TvInfoChip extends StatelessWidget {
  const _TvInfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _tvSpacing,
        vertical: _tvSpacing,
      ),
      decoration: BoxDecoration(
        color: const Color(0x5531313C),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TvRecommendationsSection extends StatefulWidget {
  const _TvRecommendationsSection({
    required this.future,
    required this.onOpenItem,
    required this.firstFocusNode,
    required this.onArrowUp,
    required this.onArrowDown,
  });

  final Future<List<_TvItem>> future;
  final Future<void> Function(_TvItem item) onOpenItem;
  final FocusNode firstFocusNode;
  final VoidCallback onArrowUp;
  final VoidCallback onArrowDown;

  @override
  State<_TvRecommendationsSection> createState() =>
      _TvRecommendationsSectionState();
}

class _TvRecommendationsSectionState extends State<_TvRecommendationsSection> {
  final List<FocusNode> _extraFocusNodes = <FocusNode>[];

  @override
  void dispose() {
    for (final node in _extraFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncFocusNodes(int itemCount) {
    final extraCount = math.max(0, itemCount - 1);
    while (_extraFocusNodes.length > extraCount) {
      _extraFocusNodes.removeLast().dispose();
    }
    while (_extraFocusNodes.length < extraCount) {
      final index = _extraFocusNodes.length + 1;
      _extraFocusNodes.add(
        FocusNode(debugLabel: 'tv-details-recommendation-$index'),
      );
    }
  }

  FocusNode _focusNodeFor(int index) {
    return index == 0 ? widget.firstFocusNode : _extraFocusNodes[index - 1];
  }

  void _restoreRecommendationFocus(FocusNode node) {
    if (!mounted || !node.canRequestFocus) return;
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !node.hasFocus) return;
      final context = node.context;
      if (context == null || !context.mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(180),
        curve: Curves.easeOutCubic,
        alignment: 0.24,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_TvItem>>(
      future: widget.future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <_TvItem>[];
        _syncFocusNodes(items.length);
        final done = snapshot.connectionState == ConnectionState.done;
        return _TvDetailsSection(
          title: 'More like this',
          child: done && items.isEmpty
              ? const Text(
                  'No recommendations are available for this title yet.',
                  style: TextStyle(
                    color: Color(0xFFAAA6BD),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : SizedBox(
                  height: 142,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.isEmpty ? 6 : items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: _tvSpacing),
                    itemBuilder: (context, index) {
                      if (items.isEmpty) {
                        return const SizedBox(
                          width: 244,
                          height: 138,
                          child: _TvShimmerBox(radius: 18, alpha: 0.5),
                        );
                      }
                      final item = items[index];
                      final focusNode = _focusNodeFor(index);
                      return _TvHomeLandscapeCard(
                        item: item,
                        rank: index + 1,
                        showRank: false,
                        focusNode: focusNode,
                        onArrowUp: widget.onArrowUp,
                        onArrowDown: widget.onArrowDown,
                        onPressed: () => unawaited(() async {
                          await widget.onOpenItem(item);
                          _restoreRecommendationFocus(focusNode);
                        }()),
                      );
                    },
                  ),
                ),
        );
      },
    );
  }
}

class _TvPeopleSection extends StatefulWidget {
  const _TvPeopleSection({
    required this.title,
    required this.people,
    required this.firstFocusNode,
    required this.onArrowUp,
    required this.onArrowDown,
  });

  final String title;
  final List<_TvPersonCredit> people;
  final FocusNode firstFocusNode;
  final VoidCallback onArrowUp;
  final VoidCallback onArrowDown;

  @override
  State<_TvPeopleSection> createState() => _TvPeopleSectionState();
}

class _TvPeopleSectionState extends State<_TvPeopleSection> {
  final List<FocusNode> _extraFocusNodes = <FocusNode>[];

  @override
  void dispose() {
    for (final node in _extraFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncFocusNodes(int itemCount) {
    final extraCount = math.max(0, itemCount - 1);
    while (_extraFocusNodes.length > extraCount) {
      _extraFocusNodes.removeLast().dispose();
    }
    while (_extraFocusNodes.length < extraCount) {
      final index = _extraFocusNodes.length + 1;
      _extraFocusNodes.add(
        FocusNode(debugLabel: 'tv-details-people-$index'),
      );
    }
  }

  FocusNode _focusNodeFor(int index) {
    return index == 0 ? widget.firstFocusNode : _extraFocusNodes[index - 1];
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.people.take(12).toList(growable: false);
    _syncFocusNodes(people.length);
    return _TvDetailsSection(
      title: widget.title,
      child: SizedBox(
        height: 148,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: people.length,
          separatorBuilder: (_, __) => const SizedBox(width: _tvSpacing),
          itemBuilder: (context, index) {
            final person = people[index];
            return _TvFocusable(
              autoReveal: true,
              focusNode: _focusNodeFor(index),
              onArrowUp: widget.onArrowUp,
              onArrowDown: widget.onArrowDown,
              onPressed: () {},
              builder: (focused) {
                return SizedBox(
                  width: 112,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: _tvDuration(130),
                        padding: const EdgeInsets.all(_tvPosterGridGap / 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: focused
                                ? _tvFocusBorder
                                : const Color(0x00FFFFFF),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: SizedBox(
                            width: 68,
                            height: 68,
                            child: person.image == null
                                ? const _TvPersonImageFallback()
                                : Image.network(
                                    person.image!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 160,
                                    filterQuality: FilterQuality.medium,
                                    gaplessPlayback: true,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                      if (loadingProgress == null) {
                                        return child;
                                      }
                                      return const _TvPersonImageFallback();
                                    },
                                    errorBuilder: (_, __, ___) =>
                                        const _TvPersonImageFallback(),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: _tvSpacing),
                      Text(
                        person.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _TvPersonImageFallback extends StatelessWidget {
  const _TvPersonImageFallback();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        _TvShimmerBox(radius: 99, alpha: 0.48),
        Center(
          child: Icon(Icons.person_rounded, color: Colors.white38, size: 30),
        ),
      ],
    );
  }
}

class _TvEpisodesSection extends StatefulWidget {
  const _TvEpisodesSection({
    required this.episodes,
    required this.onPlay,
    required this.progressForEpisode,
    this.firstFocusNode,
    this.onArrowUp,
  });

  final List<_TvEpisode> episodes;
  final Future<void> Function(_TvEpisode episode) onPlay;
  final _TvPlaybackProgress? Function(_TvEpisode episode) progressForEpisode;
  final FocusNode? firstFocusNode;
  final VoidCallback? onArrowUp;

  @override
  State<_TvEpisodesSection> createState() => _TvEpisodesSectionState();
}

class _TvEpisodesSectionState extends State<_TvEpisodesSection> {
  final _seasonNodes = <int, FocusNode>{};
  final _episodeNodes = <FocusNode>[];
  int? _selectedSeason;
  String? _playingEpisodeKey;

  List<int> get _seasons {
    final seasons = widget.episodes.map((episode) => episode.season).toSet()
      ..removeWhere((season) => season <= 0);
    final sorted = seasons.toList()..sort();
    return sorted.isEmpty ? const [1] : sorted;
  }

  bool get _hasSeasonTabs => widget.episodes.isNotEmpty;

  List<_TvEpisode> get _visibleEpisodes {
    final season = _selectedSeason ?? _seasons.first;
    return widget.episodes
        .where((episode) => episode.season == season)
        .take(24)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _syncSelectedSeason();
    _syncEpisodeNodes();
  }

  @override
  void didUpdateWidget(covariant _TvEpisodesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSelectedSeason();
    _syncEpisodeNodes();
  }

  @override
  void dispose() {
    for (final node in _seasonNodes.values) {
      node.dispose();
    }
    for (final node in _episodeNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncSelectedSeason() {
    final seasons = _seasons;
    if (_selectedSeason == null || !seasons.contains(_selectedSeason)) {
      _selectedSeason = seasons.first;
    }
  }

  void _syncEpisodeNodes() {
    final count = _visibleEpisodes.length;
    while (_episodeNodes.length > count) {
      _episodeNodes.removeLast().dispose();
    }
    while (_episodeNodes.length < count) {
      final index = _episodeNodes.length;
      _episodeNodes.add(
        FocusNode(debugLabel: 'tv-details-episode-card-$index'),
      );
    }
  }

  FocusNode _seasonNode(int season, int index) {
    if (index == 0 && widget.firstFocusNode != null) {
      return widget.firstFocusNode!;
    }
    return _seasonNodes.putIfAbsent(
      season,
      () => FocusNode(debugLabel: 'tv-details-season-$season'),
    );
  }

  FocusNode _episodeNode(int index) {
    if (!_hasSeasonTabs && index == 0 && widget.firstFocusNode != null) {
      return widget.firstFocusNode!;
    }
    return _episodeNodes[index];
  }

  void _focusEpisode(int index) {
    if (index < 0 || index >= _visibleEpisodes.length) return;
    final node = _episodeNode(index);
    node.requestFocus();
    final context = node.context;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: _tvDuration(180),
      curve: Curves.easeOutCubic,
      alignment: 0.36,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  void _focusSeason(int index) {
    final seasons = _seasons;
    if (index < 0 || index >= seasons.length) return;
    final node = _seasonNode(seasons[index], index);
    node.requestFocus();
    final context = node.context;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: _tvDuration(180),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  void _selectSeason(int season) {
    if (_playingEpisodeKey != null) return;
    if (_selectedSeason == season) return;
    setState(() {
      _selectedSeason = season;
      _syncEpisodeNodes();
    });
  }

  String _episodeKey(_TvEpisode episode) {
    return '${episode.season}:${episode.episode}';
  }

  Future<void> _playEpisode(_TvEpisode episode) async {
    if (_playingEpisodeKey != null) return;
    final key = _episodeKey(episode);
    setState(() => _playingEpisodeKey = key);
    try {
      await widget.onPlay(episode);
    } finally {
      if (mounted && _playingEpisodeKey == key) {
        setState(() => _playingEpisodeKey = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasons = _seasons;
    final visibleEpisodes = _visibleEpisodes;
    final playingEpisodeKey = _playingEpisodeKey;
    return _TvDetailsSection(
      title: 'Episodes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasSeasonTabs) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < seasons.length; index++)
                    Padding(
                      padding: EdgeInsets.only(
                        right: index == seasons.length - 1 ? 0 : _tvSpacing,
                      ),
                      child: _TvSeasonButton(
                        label: 'Season ${seasons[index]}',
                        selected: seasons[index] == _selectedSeason,
                        focusNode: _seasonNode(seasons[index], index),
                        autoReveal: false,
                        onArrowLeft:
                            index > 0 ? () => _focusSeason(index - 1) : null,
                        onArrowRight: index + 1 < seasons.length
                            ? () => _focusSeason(index + 1)
                            : null,
                        onArrowUp: widget.onArrowUp,
                        onArrowDown: visibleEpisodes.isEmpty
                            ? null
                            : () => _focusEpisode(0),
                        onPressed: () => _selectSeason(seasons[index]),
                        enabled: playingEpisodeKey == null,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: _tvSpacing),
          ],
          for (var index = 0; index < visibleEpisodes.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: _tvSpacing),
              child: _TvEpisodeCard(
                episode: visibleEpisodes[index],
                progress: widget.progressForEpisode(visibleEpisodes[index]),
                busy: playingEpisodeKey == _episodeKey(visibleEpisodes[index]),
                locked: playingEpisodeKey != null &&
                    playingEpisodeKey != _episodeKey(visibleEpisodes[index]),
                focusNode: _episodeNode(index),
                onArrowUp: index == 0
                    ? _hasSeasonTabs
                        ? () {
                            final seasonIndex = seasons.indexOf(
                              _selectedSeason ?? seasons.first,
                            );
                            _focusSeason(seasonIndex < 0 ? 0 : seasonIndex);
                          }
                        : widget.onArrowUp
                    : () => _focusEpisode(index - 1),
                onArrowDown: index + 1 < visibleEpisodes.length
                    ? () => _focusEpisode(index + 1)
                    : null,
                onPlay: () => unawaited(_playEpisode(visibleEpisodes[index])),
              ),
            ),
        ],
      ),
    );
  }
}

class _TvDetailsOverlay extends StatefulWidget {
  const _TvDetailsOverlay({
    required this.item,
    required this.onClose,
    required this.preparing,
    required this.liked,
    required this.settings,
    required this.onPlay,
    required this.onPlayEpisode,
    required this.onToggleLike,
  });

  final _TvItem item;
  final VoidCallback onClose;
  final bool preparing;
  final bool liked;
  final _TvSettingsState settings;
  final VoidCallback onPlay;
  final void Function(int season, int episode) onPlayEpisode;
  final VoidCallback onToggleLike;

  @override
  State<_TvDetailsOverlay> createState() => _TvDetailsOverlayState();
}

class _TvDetailsOverlayState extends State<_TvDetailsOverlay> {
  final FocusNode _primaryActionFocusNode = FocusNode(
    debugLabel: 'tv-details-primary',
  );
  final FocusNode _episodesFocusNode = FocusNode(
    debugLabel: 'tv-details-episodes',
  );
  final FocusNode _trailerFocusNode = FocusNode(
    debugLabel: 'tv-details-trailer',
  );
  final FocusNode _likeFocusNode = FocusNode(debugLabel: 'tv-details-like');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initialNode = _primaryActionFocusNode;
      initialNode.requestFocus();
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (mounted && FocusManager.instance.primaryFocus == null) {
          initialNode.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    _primaryActionFocusNode.dispose();
    _episodesFocusNode.dispose();
    _trailerFocusNode.dispose();
    _likeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _showTrailerPicker(BuildContext context) async {
    if (!widget.settings.builtInTrailers) {
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Loading trailers...'),
          duration: Duration(seconds: 1),
        ),
      );
    final trailers = await _TvApi()
        .trailers(widget.item)
        .catchError((_) => const <_TvTrailer>[]);
    if (!context.mounted) return;
    if (trailers.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No TV trailer is available for this title yet.'),
          ),
        );
      return;
    }
    final selected = trailers.firstWhere(
      (trailer) => trailer.isTvPlayable || trailer.isExternalLaunchable,
      orElse: () => trailers.first,
    );
    if (!selected.isTvPlayable && !selected.isExternalLaunchable) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('This trailer is not ready for TV yet.'),
          ),
        );
      return;
    }
    await _openTrailer(context, selected);
    if (!mounted) return;
    _trailerFocusNode.requestFocus();
  }

  Future<void> _openTrailer(BuildContext context, _TvTrailer trailer) async {
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
      if (trailer.isExternalLaunchable) {
        final opened = await _openTvExternalTrailer(trailer);
        if (!context.mounted) return;
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
      if (!context.mounted) return;
      final trailerItem = _TvItem(
        id: '${widget.item.id}:trailer',
        type: widget.item.type,
        title: '${widget.item.title} trailer',
        color: widget.item.color,
        poster: widget.item.poster,
        background: widget.item.background,
      );
      final result = await Navigator.of(context).push<Object?>(
        MaterialPageRoute<Object?>(
          builder: (_) => _TvPlaybackPage(
            item: trailerItem,
            sessions: [session],
            initialSessionIndex: 0,
            initialSeason: 1,
            initialEpisode: 1,
            initialResumePosition: Duration.zero,
            settings: widget.settings,
            subtitles: const <_TvSubtitle>[],
            initialSubtitleIndex: -1,
          ),
        ),
      );
      if (!context.mounted) return;
      if (result is _TvPlaybackUnavailable) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(result.message),
              duration: const Duration(seconds: 3),
            ),
          );
      }
    } catch (error) {
      if (!context.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('This trailer is not ready for TV playback yet.'),
          ),
        );
    }
  }

  List<Widget> _detailActions(BuildContext context) {
    return [
      _TvTextButton(
        icon: widget.preparing
            ? Icons.hourglass_top_rounded
            : Icons.play_arrow_rounded,
        label: widget.preparing ? 'Preparing' : 'Watch now',
        autofocus: true,
        focusNode: _primaryActionFocusNode,
        enabled: !widget.preparing,
        animateIcon: widget.preparing,
        onArrowRight: _trailerFocusNode.requestFocus,
        onArrowUp: _primaryActionFocusNode.requestFocus,
        onArrowDown: _primaryActionFocusNode.requestFocus,
        onPressed: widget.onPlay,
      ),
      _TvTextButton(
        focusNode: _trailerFocusNode,
        icon: Icons.movie_filter_rounded,
        label: 'Trailer',
        enabled: !widget.preparing,
        onArrowLeft: _primaryActionFocusNode.requestFocus,
        onArrowRight: _likeFocusNode.requestFocus,
        onArrowUp: _trailerFocusNode.requestFocus,
        onArrowDown: _trailerFocusNode.requestFocus,
        onPressed: () => unawaited(_showTrailerPicker(context)),
      ),
      _TvCircleIconButton(
        focusNode: _likeFocusNode,
        icon: widget.liked
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
        selected: widget.liked,
        size: 48,
        onArrowLeft: _trailerFocusNode.requestFocus,
        onArrowRight: _likeFocusNode.requestFocus,
        onArrowUp: _likeFocusNode.requestFocus,
        onArrowDown: _likeFocusNode.requestFocus,
        onPressed: widget.onToggleLike,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                widget.onClose();
                return null;
              },
            ),
          },
          child: FocusScope(
            autofocus: true,
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xDD000000)),
                child: Center(
                  child: Container(
                    width: 900,
                    constraints: const BoxConstraints(maxHeight: 500),
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: const Color(0xFF202124),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0x22FFFFFF)),
                    ),
                    child: Row(
                      children: [
                        _PosterArtwork(
                          item: widget.item,
                          width: 210,
                          height: 300,
                        ),
                        const SizedBox(width: _tvSpacing),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Details',
                                  style: TextStyle(
                                    color: Color(0xFF20D66B),
                                    fontSize: 13,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: _tvSpacing),
                                Text(
                                  widget.item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 31,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: _tvSpacing),
                                Text(
                                  widget.item.subtitle,
                                  style: const TextStyle(
                                    color: Color(0xFFAAA6BD),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: _tvSpacing),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 560,
                                        ),
                                        child: Text(
                                          widget.item.description?.isNotEmpty ==
                                                  true
                                              ? widget.item.description!
                                              : 'Catalog details are ready. Select playback to start a protected TV session.',
                                          maxLines: 5,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFD8D2E7),
                                            fontSize: 14,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 300,
                                      ),
                                      child: Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: _detailActions(context),
                                      ),
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvCircleIconButton extends StatelessWidget {
  const _TvCircleIconButton({
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.size = 48,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;
  final double size;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) {
        final active = focused || selected;
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active ? _tvAccentColor : const Color(0x5531313C),
            shape: BoxShape.circle,
            border: Border.all(
              color: focused
                  ? _tvSolidFocusBorder
                  : active
                      ? _tvAccentColor
                      : const Color(0x33FFFFFF),
              width: active ? 2 : 1,
            ),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x5520D66B),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color: active ? Colors.black : Colors.white,
            size: size * 0.5,
          ),
        );
      },
    );
  }
}

class _TvSeasonButton extends StatelessWidget {
  const _TvSeasonButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.enabled = true,
    this.autoReveal = true,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final bool enabled;
  final bool autoReveal;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autoReveal: autoReveal,
      focusNode: focusNode,
      enabled: enabled,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      onPressed: onPressed,
      builder: (focused) {
        final active = enabled && (focused || selected);
        return AnimatedContainer(
          duration: _tvDuration(140),
          padding: const EdgeInsets.symmetric(
            horizontal: _tvSpacing,
            vertical: _tvSpacing,
          ),
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: selected && enabled
                ? _tvAccentColor
                : focused && enabled
                    ? const Color(0x1F20D66B)
                    : const Color(0x5531313C),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused
                  ? _tvSolidFocusBorder
                  : active
                      ? _tvAccentColor
                      : const Color(0x33FFFFFF),
              width: active ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected && enabled
                  ? Colors.black
                  : enabled
                      ? Colors.white
                      : _tvTheme.muted,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      },
    );
  }
}

class _TvEpisodeCard extends StatelessWidget {
  const _TvEpisodeCard({
    required this.episode,
    required this.onPlay,
    this.progress,
    this.busy = false,
    this.locked = false,
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  final _TvEpisode episode;
  final VoidCallback onPlay;
  final _TvPlaybackProgress? progress;
  final bool busy;
  final bool locked;
  final FocusNode? focusNode;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      focusNode: focusNode,
      enabled: !locked && !busy,
      autoReveal: true,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      onPressed: onPlay,
      builder: (focused) {
        final active = focused && !locked;
        return AnimatedContainer(
          duration: _tvDuration(140),
          padding: const EdgeInsets.all(_tvSpacing),
          decoration: BoxDecoration(
            color: busy
                ? const Color(0x3320D66B)
                : active
                    ? const Color(0x1F20D66B)
                    : const Color(0x16FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active || busy
                  ? _tvSolidFocusBorder
                  : const Color(0x22FFFFFF),
              width: active || busy ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 118,
                  height: 66,
                  child: episode.thumbnail == null
                      ? const _TvEpisodeThumbnailFallback()
                      : Image.network(
                          episode.thumbnail!,
                          fit: BoxFit.cover,
                          cacheWidth: 280,
                          filterQuality: FilterQuality.medium,
                          gaplessPlayback: true,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const _TvEpisodeThumbnailFallback();
                          },
                          errorBuilder: (_, __, ___) {
                            return const _TvEpisodeThumbnailFallback();
                          },
                        ),
                ),
              ),
              const SizedBox(width: _tvSpacing),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'S${episode.season} E${episode.episode} - ${episode.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: locked ? _tvTheme.muted : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: _tvSpacing),
                    Text(
                      episode.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            locked ? _tvTheme.muted : const Color(0xFFAAA6BD),
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (progress != null &&
                        progress!.position > Duration.zero) ...[
                      const SizedBox(height: 10),
                      _TvEpisodeProgressStatus(progress: progress!),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: _tvSpacing),
              AnimatedContainer(
                duration: _tvDuration(140),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color:
                      busy || active ? _tvAccentColor : const Color(0x1FFFFFFF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x22FFFFFF)),
                ),
                child: Center(
                  child: busy
                      ? const _LoopingIcon(
                          icon: Icons.hourglass_top_rounded,
                          color: Colors.black,
                        )
                      : Icon(
                          locked
                              ? Icons.lock_outline_rounded
                              : Icons.play_arrow_rounded,
                          color: active ? Colors.black : _tvTheme.text,
                          size: 32,
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvEpisodeThumbnailFallback extends StatelessWidget {
  const _TvEpisodeThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        _TvShimmerBox(radius: 10, alpha: 0.52),
        Center(
          child: Icon(
            Icons.smart_display_rounded,
            color: Colors.white38,
            size: 30,
          ),
        ),
      ],
    );
  }
}

class _TvEpisodeProgressStatus extends StatelessWidget {
  const _TvEpisodeProgressStatus({required this.progress});

  final _TvPlaybackProgress progress;

  double get _fraction {
    if (progress.duration <= Duration.zero) return 0;
    return (progress.position.inMilliseconds / progress.duration.inMilliseconds)
        .clamp(0, 1)
        .toDouble();
  }

  String get _remainingLabel {
    if (progress.duration <= Duration.zero) {
      return _formatDuration(progress.position);
    }
    final remaining = progress.duration - progress.position;
    if (remaining <= Duration.zero || _fraction >= 0.92) {
      return 'Almost done';
    }
    return '${_formatDuration(remaining)} left';
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _fraction;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 15, color: _tvAccentColor),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Continue watching',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _tvAccentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: _tvSpacing),
            Text(
              _remainingLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFAAA6BD),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: fraction,
            backgroundColor: const Color(0x33FFFFFF),
            valueColor: AlwaysStoppedAnimation<Color>(_tvAccentColor),
          ),
        ),
      ],
    );
  }
}

class _TvSearchOverlay extends StatefulWidget {
  const _TvSearchOverlay({
    super.key,
    required this.api,
    required this.items,
    required this.onClose,
    required this.onOpenItem,
  });

  final _TvApi api;
  final List<_TvItem> items;
  final VoidCallback onClose;
  final ValueChanged<_TvItem> onOpenItem;

  @override
  State<_TvSearchOverlay> createState() => _TvSearchOverlayState();
}

class _TvSearchOverlayState extends State<_TvSearchOverlay> {
  static const _voiceChannel = MethodChannel('app.juicr.flutter/voice_search');
  static const _searchGroupSpecs = <_TvSearchGroupSpec>[
    _TvSearchGroupSpec(label: 'Movies', type: 'movie'),
    _TvSearchGroupSpec(label: 'Series', type: 'series'),
    _TvSearchGroupSpec(label: 'Animation', type: 'animation'),
  ];

  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchBarFocusNode = FocusNode(debugLabel: 'tv-search-bar');
  late final FocusNode _searchTextFocusNode;
  final FocusNode _voiceFocusNode = FocusNode(debugLabel: 'tv-search-voice');
  final FocusNode _clearFocusNode = FocusNode(debugLabel: 'tv-search-clear');
  final FocusNode _resultsFocusNode = FocusNode(
    debugLabel: 'tv-search-results-first',
  );
  String _query = '';
  bool _listening = false;
  bool _editingText = false;
  bool _loadingSearch = false;
  int _searchRequestToken = 0;
  String? _lastFocusedSearchItemKey;
  String? _pendingSearchItemKey;
  Timer? _searchDebounce;
  List<_TvSearchGroupResult> _searchGroups = const [];
  final List<FocusNode> _searchGroupFocusNodes = [];
  final Map<String, _TvItem> _searchArtworkCache = {};

  void _refreshSearchFocusChrome() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleSearchTextHardwareKey);
    _searchTextFocusNode = FocusNode(
      debugLabel: 'tv-search-text',
      onKeyEvent: _handleSearchTextFocusKey,
    );
    _searchTextFocusNode
      ..canRequestFocus = false
      ..skipTraversal = true;
    _searchBarFocusNode.addListener(_refreshSearchFocusChrome);
    _searchTextFocusNode.addListener(_refreshSearchFocusChrome);
    _controller.addListener(_handleQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchBarFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleSearchTextHardwareKey);
    _searchBarFocusNode.removeListener(_refreshSearchFocusChrome);
    _searchTextFocusNode.removeListener(_refreshSearchFocusChrome);
    _searchBarFocusNode.dispose();
    _searchTextFocusNode.dispose();
    _voiceFocusNode.dispose();
    _clearFocusNode.dispose();
    _resultsFocusNode.dispose();
    for (final node in _searchGroupFocusNodes) {
      node.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    final nextQuery = _controller.text.trim();
    if (nextQuery == _query) return;
    setState(() => _query = nextQuery);
    _scheduleRemoteSearch(nextQuery);
  }

  bool _handleSearchTextHardwareKey(KeyEvent event) {
    if (!_editingText || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return false;
    }
    return switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => _handleSearchTextEscape(_focusVoice),
      LogicalKeyboardKey.arrowDown => _handleSearchTextEscape(
          _focusSearchResults,
        ),
      LogicalKeyboardKey.arrowLeft => _handleSearchTextEscape(_focusSearchBar),
      LogicalKeyboardKey.arrowRight => _handleSearchTextEscape(
          _focusClearOrClose,
        ),
      LogicalKeyboardKey.escape ||
      LogicalKeyboardKey.goBack =>
        _handleSearchTextEscape(_focusSearchBar),
      _ => false,
    };
  }

  KeyEventResult _handleSearchTextFocusKey(FocusNode node, KeyEvent event) {
    if (!_editingText || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    return switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => _handleSearchTextFocusEscape(_focusVoice),
      LogicalKeyboardKey.arrowDown => _handleSearchTextFocusEscape(
          _focusSearchResults,
        ),
      LogicalKeyboardKey.arrowLeft => _handleSearchTextFocusEscape(
          _focusSearchBar,
        ),
      LogicalKeyboardKey.arrowRight => _handleSearchTextFocusEscape(
          _focusClearOrClose,
        ),
      LogicalKeyboardKey.escape ||
      LogicalKeyboardKey.goBack =>
        _handleSearchTextFocusEscape(_focusSearchBar),
      _ => KeyEventResult.ignored,
    };
  }

  bool _handleSearchTextEscape(VoidCallback action) {
    action();
    return true;
  }

  KeyEventResult _handleSearchTextFocusEscape(VoidCallback action) {
    action();
    return KeyEventResult.handled;
  }

  List<_TvItem> get _suggestedResults => widget.items.take(24).toList();

  List<_TvItem> get _activeResults {
    if (_query.isEmpty) return _suggestedResults;
    return [for (final group in _searchGroups) ...group.items];
  }

  void _scheduleRemoteSearch(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    final token = ++_searchRequestToken;
    if (trimmed.isEmpty) {
      setState(() {
        _loadingSearch = false;
        _searchGroups = const [];
      });
      _syncSearchGroupFocusNodes(0);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_loadRemoteSearch(trimmed, token));
    });
  }

  Future<void> _loadRemoteSearch(String query, int token) async {
    if (!mounted || query.trim().isEmpty) return;
    setState(() => _loadingSearch = true);
    final results = await Future.wait<_TvSearchGroupResult>(
      _searchGroupSpecs.map((spec) => _loadSearchGroup(spec, query)),
    );
    if (!mounted || token != _searchRequestToken || query != _query) return;

    final seen = <String>{};
    final groups = <_TvSearchGroupResult>[];
    for (final result in results) {
      final items = <_TvItem>[];
      for (final item in result.items) {
        final key = _searchItemKey(item);
        if (!seen.add(key)) continue;
        items.add(item);
        if (items.length >= 12) break;
      }
      if (items.isNotEmpty) {
        groups.add(_TvSearchGroupResult(label: result.label, items: items));
      }
    }

    _syncSearchGroupFocusNodes(groups.length);
    setState(() {
      _loadingSearch = false;
      _searchGroups = groups;
    });
  }

  void _syncSearchGroupFocusNodes(int groupCount) {
    final extraNodeCount = math.max(0, groupCount - 1);
    while (_searchGroupFocusNodes.length > extraNodeCount) {
      _searchGroupFocusNodes.removeLast().dispose();
    }
    while (_searchGroupFocusNodes.length < extraNodeCount) {
      final index = _searchGroupFocusNodes.length + 1;
      _searchGroupFocusNodes.add(
        FocusNode(debugLabel: 'tv-search-group-$index-first'),
      );
    }
  }

  FocusNode _searchGroupFocusNodeFor(int index) {
    if (index == 0) return _resultsFocusNode;
    return _searchGroupFocusNodes[index - 1];
  }

  void _focusSearchGroup(int index) {
    if (index < 0 || index >= _searchGroups.length) return;
    final node = _searchGroupFocusNodeFor(index);
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = node.context;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(180),
        curve: Curves.easeOutCubic,
        alignment: 0.36,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  Future<_TvSearchGroupResult> _loadSearchGroup(
    _TvSearchGroupSpec spec,
    String query,
  ) async {
    try {
      final items = await widget.api
          .catalog(
            type: spec.type,
            sort: 'top',
            page: 1,
            genre: 'All genres',
            search: query,
            deepSearch: true,
            fallbackType: spec.type,
          )
          .timeout(const Duration(seconds: 10));
      final deduped = _dedupeSearchItems(items).take(12).toList();
      final hydrated = await _hydrateSearchArtwork(deduped);
      return _TvSearchGroupResult(label: spec.label, items: hydrated);
    } catch (error) {
      debugPrint(
        'Juicr TV search group unavailable '
        'type=${spec.type} errorType=${error.runtimeType}',
      );
      return _TvSearchGroupResult(label: spec.label, items: const []);
    }
  }

  List<_TvItem> _dedupeSearchItems(Iterable<_TvItem> items) {
    final seen = <String>{};
    final deduped = <_TvItem>[];
    for (final item in items) {
      final key = _searchItemKey(item);
      if (seen.add(key)) deduped.add(item);
    }
    return deduped;
  }

  Future<List<_TvItem>> _hydrateSearchArtwork(List<_TvItem> items) async {
    if (items.isEmpty) return const <_TvItem>[];
    final hydrated = await Future.wait([
      for (final item in items) _hydrateSearchArtworkItem(item),
    ]);
    return hydrated;
  }

  Future<_TvItem> _hydrateSearchArtworkItem(_TvItem item) async {
    if ((item.logo ?? '').trim().isNotEmpty) return item;
    final key = _searchItemKey(item);
    final cached = _searchArtworkCache[key];
    if (cached != null) return item.merge(cached);
    try {
      final seed = item.tmdbId == null
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
              runtime: item.runtime,
            );
      final meta =
          await widget.api.meta(seed).timeout(const Duration(seconds: 5));
      final merged = item.merge(meta);
      if ((merged.logo ?? '').trim().isNotEmpty) {
        _searchArtworkCache[key] = merged;
      }
      return merged;
    } catch (error) {
      debugPrint(
        'Juicr TV search artwork hydrate skipped '
        'errorType=${error.runtimeType}',
      );
      return item;
    }
  }

  String _searchItemKey(_TvItem item) {
    final id = item.id.trim().toLowerCase();
    if (id.isNotEmpty) return '${item.type}:$id';
    return [
      item.type,
      item.title.trim().toLowerCase(),
      item.year ?? '',
    ].join(':');
  }

  Future<void> _voiceSearch() async {
    if (_listening) return;
    setState(() => _listening = true);
    try {
      final spoken = await _voiceChannel
          .invokeMethod<String>('startVoiceSearch')
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final query = spoken?.trim();
      if (query != null && query.isNotEmpty) {
        _controller.text = query;
      }
    } on PlatformException catch (error) {
      if (!mounted || error.code == 'cancelled') return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Voice search is unavailable on this TV.'),
          ),
        );
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Voice search did not hear anything yet.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  void _beginTextEntry() {
    _searchTextFocusNode
      ..canRequestFocus = true
      ..skipTraversal = false;
    setState(() => _editingText = true);
    _searchTextFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_editingText) {
        _searchTextFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
    });
  }

  void _endTextEntry() {
    if (!_editingText) return;
    _searchTextFocusNode
      ..canRequestFocus = false
      ..skipTraversal = true;
    setState(() => _editingText = false);
    _searchBarFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _appendSearchCharacter(String value) {
    if (value.isEmpty) return;
    final printable = value.characters.where((character) {
      final runes = character.runes;
      if (runes.isEmpty) return false;
      final unit = runes.first;
      return unit >= 0x20 && unit != 0x7f;
    }).join();
    if (printable.isEmpty) return;
    _controller.text = '${_controller.text}$printable';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _deleteSearchCharacter() {
    final text = _controller.text;
    if (text.isEmpty) return;
    final characters = text.characters.toList();
    characters.removeLast();
    _controller.text = characters.join();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _focusSearchBar() {
    _endTextEntry();
    _searchBarFocusNode.requestFocus();
  }

  void _focusVoice() {
    _endTextEntry();
    _voiceFocusNode.requestFocus();
  }

  void _focusClearOrClose() {
    _endTextEntry();
    if (_query.isNotEmpty) {
      _clearFocusNode.requestFocus();
    } else {
      _voiceFocusNode.requestFocus();
    }
  }

  void _focusSearchResults() {
    _endTextEntry();
    if (_activeResults.isEmpty) return;
    _resultsFocusNode.requestFocus();
  }

  String _itemKey(_TvItem item) => '${item.type}:${item.id}';

  void _rememberSearchItemFocus(FocusNode node, _TvItem item) {
    _lastFocusedSearchItemKey = _itemKey(item);
  }

  void _consumeSearchItemFocus(String itemKey) {
    if (_pendingSearchItemKey != itemKey) return;
    setState(() => _pendingSearchItemKey = null);
  }

  void restoreFocus([String? itemKey]) {
    if (!mounted) return;
    _endTextEntry();
    final restoreKey = itemKey ?? _lastFocusedSearchItemKey;
    if (restoreKey != null && restoreKey.trim().isNotEmpty) {
      setState(() => _pendingSearchItemKey = restoreKey);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pendingSearchItemKey != null) return;
      if (_activeResults.isNotEmpty && _resultsFocusNode.context != null) {
        _resultsFocusNode.requestFocus();
        Scrollable.ensureVisible(
          _resultsFocusNode.context!,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: 0.34,
        );
        return;
      }
      _searchBarFocusNode.requestFocus();
    });
  }

  KeyEventResult _handleSearchFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (!_editingText &&
        (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter)) {
      _beginTextEntry();
      return KeyEventResult.handled;
    }
    if (_editingText) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        _endTextEntry();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.backspace) {
        _deleteSearchCharacter();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _focusSearchResults();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _focusVoice();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _focusSearchBar();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _focusClearOrClose();
        return KeyEventResult.handled;
      }
      final character = event.character;
      if (character != null && character.isNotEmpty) {
        _appendSearchCharacter(character);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusSearchResults();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _voiceFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _focusClearOrClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    _searchTextFocusNode
      ..canRequestFocus = _editingText
      ..skipTraversal = !_editingText;
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xDD07080D)),
          child: FocusScope(
            autofocus: true,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 38),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Search',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _TvTextButton(
                            icon: _listening
                                ? Icons.hearing_rounded
                                : Icons.mic_rounded,
                            label: _listening ? 'Listening' : 'Voice',
                            enabled: !_listening,
                            animateIcon: _listening,
                            focusNode: _voiceFocusNode,
                            onArrowLeft: _focusSearchBar,
                            onArrowUp: _focusVoice,
                            onArrowRight: _focusVoice,
                            onArrowDown: _focusSearchBar,
                            onPressed: () => unawaited(_voiceSearch()),
                          ),
                        ],
                      ),
                      const SizedBox(height: _tvSpacing),
                      Row(
                        children: [
                          Expanded(
                            child: Focus(
                              focusNode: _searchBarFocusNode,
                              autofocus: true,
                              onKeyEvent: _handleSearchFieldKey,
                              canRequestFocus: true,
                              child: Builder(
                                builder: (context) {
                                  final focused =
                                      _searchBarFocusNode.hasFocus ||
                                          _searchTextFocusNode.hasFocus ||
                                          _editingText;
                                  return GestureDetector(
                                    onTap: _beginTextEntry,
                                    child: AnimatedContainer(
                                      duration: _tvDuration(130),
                                      height: 54,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      decoration: BoxDecoration(
                                        color: focused || _editingText
                                            ? const Color(0x2FFFFFFF)
                                            : const Color(0x24FFFFFF),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: focused || _editingText
                                              ? _juicrGreen
                                                  : const Color(0x22FFFFFF),
                                          width:
                                              focused || _editingText ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.search_rounded,
                                            color: Color(0xFFBDB9D5),
                                            size: 26,
                                          ),
                                          const SizedBox(width: _tvSpacing),
                                          Expanded(
                                            child: CallbackShortcuts(
                                              bindings: {
                                                const SingleActivator(
                                                  LogicalKeyboardKey.arrowUp,
                                                ): _focusVoice,
                                                const SingleActivator(
                                                  LogicalKeyboardKey.arrowDown,
                                                ): _focusSearchResults,
                                                const SingleActivator(
                                                  LogicalKeyboardKey.arrowLeft,
                                                ): _focusSearchBar,
                                                const SingleActivator(
                                                  LogicalKeyboardKey.arrowRight,
                                                ): _focusClearOrClose,
                                                const SingleActivator(
                                                  LogicalKeyboardKey.escape,
                                                ): _focusSearchBar,
                                                const SingleActivator(
                                                  LogicalKeyboardKey.goBack,
                                                ): _focusSearchBar,
                                              },
                                              child: TextField(
                                                controller: _controller,
                                                focusNode: _searchTextFocusNode,
                                                onTapOutside: (_) =>
                                                    _endTextEntry(),
                                                readOnly: !_editingText,
                                                autofocus: false,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                                decoration: InputDecoration(
                                                  border: InputBorder.none,
                                                  hintText: _editingText
                                                      ? 'Type your search...'
                                                      : 'Search titles, channels, animation',
                                                  hintStyle: const TextStyle(
                                                    color: Color(0xFFAAA6BD),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                onEditingComplete:
                                                    _endTextEntry,
                                                onSubmitted: (_) =>
                                                    _endTextEntry(),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          if (_query.isNotEmpty) ...[
                            const SizedBox(width: _tvSpacing),
                            _TvTextButton(
                              icon: Icons.clear_rounded,
                              label: 'Clear',
                              focusNode: _clearFocusNode,
                              onArrowLeft: _focusSearchBar,
                              onArrowRight: _focusVoice,
                              onArrowUp: _focusVoice,
                              onArrowDown: _focusSearchResults,
                              onPressed: () {
                                _controller.clear();
                                _focusSearchBar();
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: _tvSpacing),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _buildSearchResults(context),
                        ),
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

  Widget _buildSearchResults(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height - 300;
    if (_query.isEmpty) {
      return _suggestedResults.isEmpty
          ? _TvEmptyCatalogState(
              title: 'No TV results yet.',
              subtitle: 'Try another title, channel, or animation name.',
              focusNode: _resultsFocusNode,
              onFocusNavigation: _focusSearchBar,
              onFocusHeader: _focusSearchBar,
              height: height,
            )
          : _TvPosterGrid(
              title: 'Suggested',
              subtitle: '',
              items: _suggestedResults,
              showRank: false,
              landscapeCards: true,
              landscapeCardWidth: 210,
              firstItemFocusNode: _resultsFocusNode,
              onTopRowArrowUp: _focusSearchBar,
              onRememberFocus: (_) {},
              onRememberItemFocus: _rememberSearchItemFocus,
              restoreItemKey: _pendingSearchItemKey,
              onRestoreItemFocus: _consumeSearchItemFocus,
              onOpenItem: widget.onOpenItem,
            );
    }

    if (_searchGroups.isEmpty) {
      return _TvEmptyCatalogState(
        title: _loadingSearch ? 'Searching...' : 'No TV results yet.',
        subtitle: _loadingSearch
            ? 'Checking movies, series, and animation.'
            : 'Try another title, channel, or animation name.',
        focusNode: _resultsFocusNode,
        onFocusNavigation: _focusSearchBar,
        onFocusHeader: _focusSearchBar,
        height: height,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < _searchGroups.length; index++) ...[
          if (index > 0) const SizedBox(height: _tvSpacing * 2),
          _TvPosterGrid(
            title: _searchGroups[index].label,
            subtitle:
                '${_searchGroups[index].items.length} matching title${_searchGroups[index].items.length == 1 ? '' : 's'}.',
            items: _searchGroups[index].items,
            showRank: false,
            landscapeCards: true,
            landscapeCardWidth: 210,
            firstItemFocusNode: _searchGroupFocusNodeFor(index),
            onTopRowArrowUp: index == 0 ? _focusSearchBar : null,
            onBottomRowArrowDown: index + 1 < _searchGroups.length
                ? () => _focusSearchGroup(index + 1)
                : null,
            onRememberFocus: (_) {},
            onRememberItemFocus: _rememberSearchItemFocus,
            restoreItemKey: _pendingSearchItemKey,
            onRestoreItemFocus: _consumeSearchItemFocus,
            onOpenItem: widget.onOpenItem,
          ),
        ],
        if (_loadingSearch) ...[
          const SizedBox(height: _tvSpacing * 2),
          const _TvShimmerBox(width: 210, height: 20, radius: 8),
          const SizedBox(height: _tvSpacing),
          const _TvCatalogSkeletonRow(count: 4),
        ],
      ],
    );
  }
}

class _TvSearchGroupSpec {
  const _TvSearchGroupSpec({required this.label, required this.type});

  final String label;
  final String type;
}

class _TvSearchGroupResult {
  const _TvSearchGroupResult({required this.label, required this.items});

  final String label;
  final List<_TvItem> items;
}
