part of 'main.dart';

const MethodChannel _tvTrailerChannel = MethodChannel(
  'app.juicr.flutter/trailer',
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
    required this.onOpenItem,
    required this.onFocusNavigation,
    required this.entryFocusNode,
    required this.onFocusHeader,
    required this.onRememberFocus,
    required this.onLoadMore,
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
  final ValueChanged<_TvItem> onOpenItem;
  final VoidCallback onFocusNavigation;
  final FocusNode entryFocusNode;
  final VoidCallback onFocusHeader;
  final ValueChanged<FocusNode> onRememberFocus;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final fallbackItems = switch (kind) {
      _TvDiscoveryKind.movie => movies,
      _TvDiscoveryKind.series => series,
      _TvDiscoveryKind.animation => animation,
      _TvDiscoveryKind.liveTv => liveTv,
    };
    final laneItems =
        discoveryLaneItems[_tvDiscoveryLaneKey(kind, sort)] ??
        const <_TvItem>[];
    final items = _sortedCatalogItems(
      laneItems.isEmpty ? fallbackItems : laneItems,
      sort,
      preserveLaneOrder: laneItems.isNotEmpty,
    );
    final visibleItems = genre == 'All genres'
        ? items
        : items.where((item) {
            return item.genres.any(
              (itemGenre) => itemGenre.toLowerCase() == genre.toLowerCase(),
            );
          }).toList();

    if (visibleItems.isEmpty) {
      return _TvEmptyCatalogState(
        title: 'Discovery is waiting for catalog data.',
        subtitle: genre == 'All genres'
            ? 'Turn on a source in Settings or refresh when your connection is ready.'
            : 'No ${kind.label.toLowerCase()} are available for $genre yet.',
        height: MediaQuery.sizeOf(context).height - 210,
        verticalOffset: -42,
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
      onLoadMore: onLoadMore,
    );
  }

  List<_TvItem> _sortedCatalogItems(
    List<_TvItem> source,
    _TvDiscoverySort sort, {
    required bool preserveLaneOrder,
  }) {
    final items = source.where((item) => item.poster != null).toList();
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
}

class _TvLibrarySurface extends StatelessWidget {
  const _TvLibrarySurface({
    required this.recentItems,
    required this.likedItems,
    required this.filter,
    required this.onOpenItem,
    required this.onFocusNavigation,
    required this.entryFocusNode,
    required this.onFocusHeader,
    required this.onRememberFocus,
  });

  final List<_TvItem> recentItems;
  final List<_TvItem> likedItems;
  final _TvLibraryFilter filter;
  final ValueChanged<_TvItem> onOpenItem;
  final VoidCallback onFocusNavigation;
  final FocusNode entryFocusNode;
  final VoidCallback onFocusHeader;
  final ValueChanged<FocusNode> onRememberFocus;

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;

    if (items.isEmpty) {
      return _TvEmptyCatalogState(
        title: _emptyTitle,
        subtitle: _emptySubtitle,
        height: MediaQuery.sizeOf(context).height - 210,
        verticalOffset: 42,
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
    );
  }

  List<_TvItem> get _filteredItems {
    switch (filter) {
      case _TvLibraryFilter.continueWatching:
        return recentItems.where((item) => item.poster != null).toList();
      case _TvLibraryFilter.movies:
        return likedItems
            .where((item) => item.type == 'movie' && item.poster != null)
            .toList();
      case _TvLibraryFilter.series:
        return likedItems
            .where((item) => item.type == 'series' && item.poster != null)
            .toList();
      case _TvLibraryFilter.animation:
        return likedItems
            .where((item) => item.type == 'animation' && item.poster != null)
            .toList();
      case _TvLibraryFilter.liveTv:
        return likedItems
            .where(
              (item) =>
                  (item.type == 'live' ||
                      item.type == 'livetv' ||
                      item.type == 'channel') &&
                  item.poster != null,
            )
            .toList();
    }
  }

  String get _title {
    return switch (filter) {
      _TvLibraryFilter.continueWatching => 'Continue watching',
      _TvLibraryFilter.movies => 'Liked movies',
      _TvLibraryFilter.series => 'Liked series',
      _TvLibraryFilter.animation => 'Liked animation',
      _TvLibraryFilter.liveTv => 'Liked Live TV',
    };
  }

  String get _subtitle {
    return switch (filter) {
      _TvLibraryFilter.continueWatching =>
        'Recently opened titles from this TV session.',
      _TvLibraryFilter.movies => 'Movies you hearted on this TV.',
      _TvLibraryFilter.series => 'Series you hearted on this TV.',
      _TvLibraryFilter.animation => 'Animation you hearted on this TV.',
      _TvLibraryFilter.liveTv => 'Live TV items you hearted on this TV.',
    };
  }

  String get _emptyTitle {
    return switch (filter) {
      _TvLibraryFilter.continueWatching => 'Nothing to continue yet.',
      _TvLibraryFilter.movies => 'No liked movies yet.',
      _TvLibraryFilter.series => 'No liked series yet.',
      _TvLibraryFilter.animation => 'No liked animation yet.',
      _TvLibraryFilter.liveTv => 'No liked Live TV yet.',
    };
  }

  String get _emptySubtitle {
    return switch (filter) {
      _TvLibraryFilter.continueWatching =>
        'Open or play a title and it will appear here for this session.',
      _TvLibraryFilter.movies =>
        'Heart a movie from Home, Discovery, or Details to show it here.',
      _TvLibraryFilter.series =>
        'Heart a series from Home, Discovery, or Details to show it here.',
      _TvLibraryFilter.animation =>
        'Heart an animation title from Home, Discovery, or Details to show it here.',
      _TvLibraryFilter.liveTv =>
        'Heart Live TV items when they are available on this TV.',
    };
  }
}

class _TvEmptyCatalogState extends StatelessWidget {
  const _TvEmptyCatalogState({
    required this.title,
    required this.subtitle,
    this.height,
    this.verticalOffset = 0,
    this.focusNode,
    this.onFocusNavigation,
    this.onFocusHeader,
  });

  final String title;
  final String subtitle;
  final double? height;
  final double verticalOffset;
  final FocusNode? focusNode;
  final VoidCallback? onFocusNavigation;
  final VoidCallback? onFocusHeader;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Transform.translate(
        offset: Offset(0, verticalOffset),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.explore_off_rounded,
                color: Color(0xFFAAA6BD),
                size: 52,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFAAA6BD),
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
            builder: (focused) {
              return AnimatedContainer(
                duration: _tvDuration(130),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: focused ? _tvFocusBorder : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: content,
              );
            },
          );
    final targetHeight = height;
    if (targetHeight == null) return focusableContent;
    return SizedBox(
      height: targetHeight < 300 ? 300 : targetHeight,
      child: focusableContent,
    );
  }
}

class _TvResumePlaybackDialog extends StatelessWidget {
  const _TvResumePlaybackDialog({required this.progress});

  final _TvPlaybackProgress progress;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF15141D),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Continue watching?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Resume from ${_formatDuration(progress.position)} or start over.',
              style: const TextStyle(
                color: Color(0xFFBDB9D5),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _TvTextButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Continue',
                  onPressed: () => Navigator.of(context).pop(true),
                ),
                _TvTextButton(
                  icon: Icons.replay_rounded,
                  label: 'Start over',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ],
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
            'Personal servers',
            'Personal library sources stay separate from built-in and add-on choices.',
          ),
          _TvSettingsLine(
            'Safety',
            'Only add links you trust; Juicr does not review third-party services.',
          ),
        ],
      ),
      const _TvSettingsSection(
        'Advanced',
        'History, storage, and power-user TV controls.',
        Icons.admin_panel_settings_outlined,
        [
          _TvSettingsLine(
            'Runtime controls',
            'Advanced playback controls stay guarded until ready for this TV build.',
          ),
          _TvSettingsLine(
            'History tools',
            'Session history can be reviewed without exposing private playback details.',
          ),
          _TvSettingsLine(
            'Playback tuning',
            'Timing and recovery controls stay grouped away from everyday settings.',
          ),
          _TvSettingsLine(
            'Advanced P2P',
            'Advanced P2P stays locked until TV runtime support is proven.',
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
        'Version, status, and redacted diagnostic tools.',
        Icons.info_rounded,
        [
          const _TvSettingsLine('TV app', 'Juicr TV remote-first build.'),
          _TvSettingsLine(
            'Catalog',
            hasCatalog
                ? '$totalCount titles loaded: $movieCount movies, $seriesCount series, $animationCount animation.'
                : 'Catalog is ready to refresh when your connection is available.',
          ),
          const _TvSettingsLine(
            'Diagnostics',
            'Reports use safe counts and status buckets only.',
          ),
          const _TvSettingsLine(
            'Privacy boundary',
            'Private playback details are not shown in TV diagnostics.',
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _TvSettingsSectionDialog(
        section: section,
        settings: settings,
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
                onArrowRight:
                    index + 1 < widget.sections.length &&
                        index % _columnCount != _columnCount - 1
                    ? () => _focusIndex(index + 1)
                    : null,
                onArrowUp: index - _columnCount >= 0
                    ? () => _focusIndex(index - _columnCount, alignment: 0.2)
                    : null,
                onArrowDown: index + _columnCount < widget.sections.length
                    ? () => _focusIndex(index + _columnCount, alignment: 0.56)
                    : null,
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
            height: 150,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: focused ? _tvAccentColor : const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: focused ? _tvFocusBorder : const Color(0x1FFFFFFF),
                width: focused ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  section.icon,
                  color: focused ? Colors.black : _tvAccentColor,
                  size: 28,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        section.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: focused ? Colors.black : Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: focused ? Colors.black : const Color(0xFFAAA6BD),
                      size: 26,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  section.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: focused
                        ? Colors.black.withValues(alpha: 0.72)
                        : const Color(0xFFAAA6BD),
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
  final FocusNode _closeFocusNode = FocusNode(
    debugLabel: 'tv-settings-dialog-close',
  );
  final FocusNode _firstActionFocusNode = FocusNode(
    debugLabel: 'tv-settings-dialog-first',
  );
  final List<FocusNode> _actionFocusNodes = <FocusNode>[];
  FocusNode? _lastActionFocusNode;

  late _TvSettingsState _current = widget.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusAction(0);
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (mounted && FocusManager.instance.primaryFocus == null) {
          _focusAction(0);
        }
      });
    });
  }

  @override
  void dispose() {
    _closeFocusNode.dispose();
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

  void _restoreLastActionFocus() {
    final node = _lastActionFocusNode ?? _firstActionFocusNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !node.canRequestFocus) return;
      node.requestFocus();
      final context = node.context;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: _tvDuration(160),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  void _update(_TvSettingsState next) {
    setState(() => _current = next);
    widget.onSettingsChanged(next);
  }

  Future<String?> _pickOption(
    BuildContext context, {
    required String title,
    required String selected,
    required List<String> options,
  }) async {
    final result = await showDialog<String>(
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

  Future<void> _showStatusDialog(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.info_outline_rounded,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 180, vertical: 80),
        child: Container(
          width: 620,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xF215151E),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0x22FFFFFF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: _tvAccentColor, size: 32),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: Color(0xFFAAA6BD),
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
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

  Future<bool> _confirmBuiltInConsent(
    BuildContext context,
    _TvSettingsState current,
  ) async {
    if (current.defaultSourceConsentAccepted) return true;
    final accepted = await showDialog<bool>(
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
    final accepted = await showDialog<bool>(
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
    await showDialog<void>(
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
      return candidate.name == addon.name &&
          candidate.manifest == addon.manifest;
    }

    void updateDialogState(_TvSettingsState next) {
      dialogState = next;
      update(next);
    }

    await showDialog<void>(
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
    ValueChanged<_TvSettingsState> update,
  ) async {
    if (!await _confirmAddOnConsent(context, current)) return;
    if (!mounted) return;
    if (!context.mounted) return;
    final consented = current.copyWith(addOnConsentAccepted: true);
    update(consented);
    final added = await showDialog<_TvUserAddOn>(
      context: context,
      builder: (dialogContext) => const _TvAddOnEntryDialog(),
    );
    _restoreLastActionFocus();
    if (added == null) return;
    update(consented.copyWith(userAddOns: [...consented.userAddOns, added]));
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
                options: const ['System', 'Light', 'Dark'],
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
              final selected = await _pickOption(
                context,
                title: 'App color accent',
                selected: current.accent,
                options: const ['Juicr Green', 'Ocean', 'Sunset', 'Mono'],
              );
              if (selected != null) update(current.copyWith(accent: selected));
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
                  'Small',
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
            subtitle: 'Auto keeps playback on the safest available TV route.',
            value: current.playbackEngine,
            icon: Icons.memory_rounded,
            onPressed: () => unawaited(() async {
              final selected = await _pickOption(
                context,
                title: 'Playback engine',
                selected: current.playbackEngine,
                options: const ['Auto', 'Native'],
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
            title: 'Add add-on',
            subtitle:
                'Name a trusted add-on link for TV-side management. Diagnostics keep private details hidden.',
            value: current.userAddOns.isEmpty
                ? 'None'
                : '${current.userAddOns.length} saved',
            icon: Icons.add_link_rounded,
            onPressed: () => unawaited(_addUserAddOn(context, current, update)),
          ),
          for (final addon in current.userAddOns)
            _TvSettingsAction(
              title: addon.displayName,
              subtitle:
                  'Saved add-on. Open to enable, disable, or remove this TV entry.',
              value: addon.enabled ? 'On' : 'Off',
              icon: Icons.extension_rounded,
              onPressed: () =>
                  unawaited(_openUserAddOn(context, current, update, addon)),
            ),
          _TvSettingsAction(
            title: 'Personal servers',
            subtitle:
                'Personal library source setup stays separate from built-in and add-on choices.',
            value: 'Planned',
            icon: Icons.dns_rounded,
            onPressed: () => unawaited(
              _showStatusDialog(
                context,
                title: 'Personal servers',
                message:
                    'TV personal server setup will stay in its own source lane. Server addresses, access keys, and media links will stay out of diagnostics.',
                icon: Icons.dns_rounded,
              ),
            ),
          ),
        ];
      case 'Advanced':
        return [
          _TvSettingsAction(
            title: 'Advanced controls',
            subtitle:
                'Show guarded power-user playback controls when they are ready for TV.',
            value: current.advancedControls ? 'On' : 'Off',
            icon: Icons.admin_panel_settings_outlined,
            onPressed: () => update(
              current.copyWith(advancedControls: !current.advancedControls),
            ),
          ),
          _TvSettingsAction(
            title: 'History tools',
            subtitle:
                'Keep local session history controls available for this TV.',
            value: current.history ? 'On' : 'Off',
            icon: Icons.history_rounded,
            onPressed: () =>
                update(current.copyWith(history: !current.history)),
          ),
          _TvSettingsAction(
            title: 'Safe diagnostics',
            subtitle:
                'Keep diagnostics limited to safe counts and status buckets.',
            value: current.safeDiagnostics ? 'On' : 'Required',
            icon: Icons.privacy_tip_rounded,
            onPressed: () => unawaited(
              _showStatusDialog(
                context,
                title: 'Safe diagnostics are required',
                message:
                    'TV diagnostics only show safe status labels and counts. Private playback details and source configuration stay hidden.',
                icon: Icons.privacy_tip_rounded,
              ),
            ),
          ),
          _TvSettingsAction(
            title: 'Advanced P2P',
            subtitle:
                'Unavailable on this TV build until TV-specific runtime support is proven.',
            value: 'Locked',
            icon: Icons.lock_outline_rounded,
            onPressed: () => unawaited(
              _showStatusDialog(
                context,
                title: 'Advanced P2P',
                message:
                    'Advanced P2P stays locked on TV unless a TV-specific runtime is present, consent is granted, and diagnostics remain safe.',
                icon: Icons.lock_outline_rounded,
              ),
            ),
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
            title: 'Juicr connection',
            subtitle:
                'Catalog, metadata, editorial, trailers, and guarded playback use Juicr app services.',
            value: 'Connected',
            icon: Icons.cloud_done_rounded,
            onPressed: () => unawaited(
              _showStatusDialog(
                context,
                title: 'Juicr connection',
                message:
                    'Catalog, metadata, editorial, trailers, and guarded playback checks use Juicr app services. The TV never shows private request details here.',
                icon: Icons.cloud_done_rounded,
              ),
            ),
          ),
          _TvSettingsAction(
            title: 'Playback',
            subtitle:
                'TV playback uses protected app routes and keeps private playback details hidden.',
            value: 'Guarded',
            icon: Icons.play_circle_fill_rounded,
            onPressed: () => unawaited(
              _showStatusDialog(
                context,
                title: 'Playback',
                message:
                    'Playback stays behind TV-safe app controls. Enable playback in Settings before starting titles.',
                icon: Icons.play_circle_fill_rounded,
              ),
            ),
          ),
          _TvSettingsAction(
            title: 'Diagnostics',
            subtitle:
                'Reports stay redacted and do not show private playback or source details.',
            value: 'Safe',
            icon: Icons.info_outline_rounded,
            onPressed: () => unawaited(
              _showStatusDialog(
                context,
                title: 'Send diagnostics',
                message:
                    'Use this screen to review safe TV status. If support asks for diagnostics, send only screenshots or exported summaries that keep private playback details hidden.',
              ),
            ),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 64, vertical: 34),
      child: Container(
        width: 920,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xF215151E),
          borderRadius: BorderRadius.circular(28),
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
                size: 48,
                onArrowUp: () => _closeFocusNode.requestFocus(),
                onArrowRight: () => _closeFocusNode.requestFocus(),
                onArrowLeft: () => _focusAction(0),
                onArrowDown: () => _focusAction(0),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.section.icon,
                        color: _tvAccentColor,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.section.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.section.subtitle,
                    style: const TextStyle(
                      color: Color(0xFFAAA6BD),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (var index = 0; index < actions.length; index++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _TvSettingsLineCard(
                                action: actions[index],
                                autofocus: index == 0,
                                focusNode: _actionNode(index),
                                onFocus: () =>
                                    _rememberActionFocus(_actionNode(index)),
                                onArrowUp: index == 0
                                    ? () => _closeFocusNode.requestFocus()
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
  });

  final _TvSettingsAction action;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

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
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: focused ? _tvAccentColor : const Color(0x18FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: focused ? _tvFocusBorder : const Color(0x1FFFFFFF),
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: TextStyle(
                        color: focused ? Colors.black : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      action.subtitle,
                      style: TextStyle(
                        color: focused
                            ? Colors.black.withValues(alpha: 0.72)
                            : const Color(0xFFAAA6BD),
                        fontSize: 13,
                        height: 1.28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                constraints: const BoxConstraints(minWidth: 86),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: focused
                      ? Colors.black.withValues(alpha: 0.14)
                      : const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: focused
                        ? Colors.black.withValues(alpha: 0.18)
                        : const Color(0x22FFFFFF),
                  ),
                ),
                child: Text(
                  action.value,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: focused ? Colors.black : Colors.white,
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
  final _closeFocusNode = FocusNode(debugLabel: 'tv-default-source-close');
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
    _closeFocusNode.dispose();
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

  void _update(_TvSettingsState next) {
    setState(() => _current = next);
    widget.onSettingsChanged(next);
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
        ),
      ),
      _TvSettingsAction(
        title: 'Built-in Live TV',
        subtitle:
            'Show optional public live TV channels when this lane is enabled.',
        value: _current.builtInLiveTv ? 'On' : 'Off',
        icon: Icons.live_tv_rounded,
        onPressed: () =>
            _update(_current.copyWith(builtInLiveTv: !_current.builtInLiveTv)),
      ),
      _TvSettingsAction(
        title: 'Built-in playback',
        subtitle: 'Allow optional built-in TV playback after safe app checks.',
        value: _current.builtInPlayback ? 'On' : 'Off',
        icon: Icons.play_circle_outline_rounded,
        onPressed: () => _update(
          _current.copyWith(builtInPlayback: !_current.builtInPlayback),
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
        width: 760,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xF215151E),
          borderRadius: BorderRadius.circular(28),
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
                size: 48,
                onArrowUp: () => _closeFocusNode.requestFocus(),
                onArrowRight: () => _closeFocusNode.requestFocus(),
                onArrowLeft: () => _focusAction(0),
                onArrowDown: () => _focusAction(0),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Default',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enable only the built-in tools you want on this TV.',
                    style: TextStyle(
                      color: Color(0xFFAAA6BD),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (var index = 0; index < actions.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TvSettingsLineCard(
                        action: actions[index],
                        autofocus: index == 0,
                        focusNode: _actionNode(index),
                        onArrowUp: index == 0
                            ? () => _closeFocusNode.requestFocus()
                            : () => _focusAction(index - 1),
                        onArrowDown: index == actions.length - 1
                            ? () => _focusAction(0)
                            : () => _focusAction(index + 1),
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
  final _closeFocusNode = FocusNode(debugLabel: 'tv-user-addon-close');
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
    _closeFocusNode.dispose();
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
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xF215151E),
          borderRadius: BorderRadius.circular(28),
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
                size: 48,
                onArrowUp: () => _closeFocusNode.requestFocus(),
                onArrowRight: () => _closeFocusNode.requestFocus(),
                onArrowLeft: () => _focusAction(0),
                onArrowDown: () => _focusAction(0),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.addon.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Manage this source by safe label. Private links stay hidden.',
                    style: TextStyle(
                      color: Color(0xFFAAA6BD),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (var index = 0; index < actions.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TvSettingsLineCard(
                        action: actions[index],
                        autofocus: index == 0,
                        focusNode: _actionNode(index),
                        onArrowUp: index == 0
                            ? () => _closeFocusNode.requestFocus()
                            : () => _focusAction(index - 1),
                        onArrowDown: index == actions.length - 1
                            ? () => _focusAction(0)
                            : () => _focusAction(index + 1),
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
  final FocusNode _closeFocusNode = FocusNode(
    debugLabel: 'tv-settings-option-close',
  );
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
    _closeFocusNode.dispose();
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
        constraints: const BoxConstraints(maxWidth: 560),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF214141E),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0x22FFFFFF)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                    onArrowLeft: () => _focusOption(_selectedIndex),
                    onArrowDown: () => _focusOption(_selectedIndex),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 64),
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    for (var index = 0; index < widget.options.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TvSettingsOptionRow(
                          label: widget.options[index],
                          selected: widget.options[index] == widget.selected,
                          focusNode: _optionFocusNodes[index],
                          onArrowUp: index == 0
                              ? () => _closeFocusNode.requestFocus()
                              : () => _focusOption(index - 1),
                          onArrowDown: index == widget.options.length - 1
                              ? () => _focusOption(index)
                              : () => _focusOption(index + 1),
                          onPressed: () =>
                              Navigator.of(context).pop(widget.options[index]),
                        ),
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
        final fill = active ? _tvAccentColor : const Color(0x18FFFFFF);
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: focused && selected
                  ? _tvFocusBorder
                  : active
                  ? _tvAccentColor
                  : const Color(0x22FFFFFF),
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: active ? Colors.black : const Color(0xFFAAA6BD),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.black : Colors.white,
                  fontSize: 17,
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
        width: 760,
        constraints: const BoxConstraints(maxHeight: 570),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xF215151E),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.intro,
              style: const TextStyle(
                color: Color(0xFFAAA6BD),
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < widget.acknowledgements.length;
                      index++
                    )
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TvConsentRow(
                          acknowledgement: widget.acknowledgements[index],
                          checked: _acceptedIndexes.contains(index),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    allAccepted
                        ? 'Thanks. These tools can be enabled now.'
                        : 'Check every acknowledgement to continue.',
                    style: TextStyle(
                      color: allAccepted
                          ? _tvAccentColor
                          : const Color(0xFFAAA6BD),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _TvTextButton(
                  icon: Icons.close_rounded,
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 10),
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
  });

  final _TvConsentAcknowledgement acknowledgement;
  final bool checked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autoReveal: true,
      onPressed: onPressed,
      builder: (focused) {
        final active = focused || checked;
        return AnimatedContainer(
          duration: _tvDuration(140),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: active ? _tvAccentColor : const Color(0x18FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: focused && checked
                  ? Colors.white
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
                color: active ? Colors.black : const Color(0xFFAAA6BD),
                size: 25,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      acknowledgement.title,
                      style: TextStyle(
                        color: active ? Colors.black : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      acknowledgement.text,
                      style: TextStyle(
                        color: active
                            ? Colors.black.withValues(alpha: 0.72)
                            : const Color(0xFFAAA6BD),
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
  final _cancelFocusNode = FocusNode(debugLabel: 'tv-addon-cancel');
  final _saveFocusNode = FocusNode(debugLabel: 'tv-addon-save');

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
    _cancelFocusNode.dispose();
    _saveFocusNode.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final manifest = _manifestController.text.trim();
    if (name.isEmpty || !manifest.startsWith('https://')) return;
    Navigator.of(context).pop(_TvUserAddOn(name: name, manifest: manifest));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 170, vertical: 50),
      child: Container(
        width: 680,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xF215151E),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add your own add-on',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter a display name and add-on link you trust.',
              style: TextStyle(
                color: Color(0xFFAAA6BD),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            _TvDialogTextField(
              controller: _nameController,
              icon: Icons.label_outline_rounded,
              hintText: 'Display name',
              focusNode: _nameFocusNode,
              onArrowDown: () => _manifestFocusNode.requestFocus(),
            ),
            const SizedBox(height: 12),
            _TvDialogTextField(
              controller: _manifestController,
              icon: Icons.link_rounded,
              hintText: 'Add-on link',
              focusNode: _manifestFocusNode,
              onArrowUp: () => _nameFocusNode.requestFocus(),
              onArrowDown: () => _saveFocusNode.requestFocus(),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TvTextButton(
                  icon: Icons.close_rounded,
                  label: 'Cancel',
                  focusNode: _cancelFocusNode,
                  onArrowRight: () => _saveFocusNode.requestFocus(),
                  onArrowUp: () => _manifestFocusNode.requestFocus(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                _TvTextButton(
                  icon: Icons.check_rounded,
                  label: 'Save',
                  focusNode: _saveFocusNode,
                  onArrowLeft: () => _cancelFocusNode.requestFocus(),
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
  final FocusNode _guestFocusNode = FocusNode(debugLabel: 'tv-account-guest');
  final FocusNode _primaryFocusNode = FocusNode(
    debugLabel: 'tv-account-primary',
  );
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _emailFocusNode.dispose();
    _codeFocusNode.dispose();
    _guestFocusNode.dispose();
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
        width: 700,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xF215151E),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sign in to Juicr',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your email is used for sign-in and account recovery. Use a supported personal email provider.',
              style: TextStyle(
                color: Color(0xFFAAA6BD),
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF9A8B),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TvTextButton(
                  icon: Icons.person_outline_rounded,
                  label: 'Continue as guest',
                  focusNode: _guestFocusNode,
                  onArrowRight: () => _primaryFocusNode.requestFocus(),
                  onArrowUp: () => _codeSent
                      ? _codeFocusNode.requestFocus()
                      : _emailFocusNode.requestFocus(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                _TvTextButton(
                  icon: _busy
                      ? Icons.hourglass_top_rounded
                      : Icons.arrow_forward_rounded,
                  label: _busy ? 'Please wait' : primaryLabel,
                  enabled: !_busy,
                  focusNode: _primaryFocusNode,
                  onArrowLeft: () => _guestFocusNode.requestFocus(),
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
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hintText;
  final FocusNode? focusNode;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvEditableDialogField(
      controller: controller,
      icon: icon,
      hintText: hintText,
      focusNode: focusNode,
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
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hintText;
  final FocusNode? focusNode;
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
    _textFocusNode
      ..canRequestFocus = true
      ..skipTraversal = false;
    setState(() => _editing = true);
    _textFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
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
                    color: active ? _tvFocusBorder : const Color(0x22FFFFFF),
                    width: active ? 2 : 1,
                  ),
                ),
                child: TextField(
                  controller: widget.controller,
                  focusNode: _textFocusNode,
                  readOnly: !_editing,
                  onTap: _beginEditing,
                  onTapOutside: (_) => _endEditing(),
                  onEditingComplete: _endEditing,
                  onSubmitted: (_) => _endEditing(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      widget.icon,
                      color: const Color(0xFFAAA6BD),
                    ),
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(
                      color: Color(0xFFAAA6BD),
                      fontWeight: FontWeight.w700,
                    ),
                    filled: true,
                    fillColor: const Color(0x18FFFFFF),
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
  final FocusNode _closeFocusNode = FocusNode(debugLabel: 'tv-details-close');
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

  bool get _isSeriesLike =>
      widget.item.type == 'series' || widget.item.type == 'animation';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initialNode = widget.preparing
          ? _closeFocusNode
          : _primaryActionFocusNode;
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
    _closeFocusNode.dispose();
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
    final closeFocusNode = FocusNode(debugLabel: 'tv-trailer-picker-close');
    final trailerFocusNodes = [
      for (var index = 0; index < trailers.take(6).length; index++)
        FocusNode(debugLabel: 'tv-trailer-picker-$index'),
    ];
    void focusTrailer(int index) {
      if (index < 0 || index >= trailerFocusNodes.length) return;
      trailerFocusNodes[index].requestFocus();
    }

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 580,
              constraints: const BoxConstraints(maxHeight: 590),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF15151E),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0x22FFFFFF)),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _TvCircleIconButton(
                      focusNode: closeFocusNode,
                      icon: Icons.close_rounded,
                      onArrowUp: () => closeFocusNode.requestFocus(),
                      onArrowRight: () => closeFocusNode.requestFocus(),
                      onArrowLeft: () => focusTrailer(0),
                      onArrowDown: () => focusTrailer(0),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.item.title} trailers',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Choose a trailer to open on this TV.',
                          style: TextStyle(
                            color: Color(0xFFAAA6BD),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (
                                  var index = 0;
                                  index < trailers.take(6).length;
                                  index++
                                )
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: _TvTextButton(
                                        focusNode: trailerFocusNodes[index],
                                        icon:
                                            trailers[index].isTvPlayable ||
                                                trailers[index]
                                                    .isExternalLaunchable
                                            ? Icons.movie_filter_rounded
                                            : Icons.lock_clock_rounded,
                                        label:
                                            trailers[index].isTvPlayable ||
                                                trailers[index]
                                                    .isExternalLaunchable
                                            ? trailers[index].title
                                            : '${trailers[index].title} unavailable',
                                        autofocus: index == 0,
                                        enabled:
                                            trailers[index].isTvPlayable ||
                                            trailers[index]
                                                .isExternalLaunchable,
                                        onArrowUp: index == 0
                                            ? () =>
                                                  closeFocusNode.requestFocus()
                                            : () => focusTrailer(index - 1),
                                        onArrowDown:
                                            index ==
                                                trailerFocusNodes.length - 1
                                            ? () => focusTrailer(index)
                                            : () => focusTrailer(index + 1),
                                        onPressed: () {
                                          Navigator.of(dialogContext).pop();
                                          unawaited(
                                            _openTrailer(
                                              context,
                                              trailers[index],
                                            ),
                                          );
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
                ],
              ),
            ),
          );
        },
      );
    } finally {
      closeFocusNode.dispose();
      for (final node in trailerFocusNodes) {
        node.dispose();
      }
    }
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
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
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

  Future<void> _showEpisodePicker(BuildContext context) async {
    final allEpisodes = widget.item.episodes.isNotEmpty
        ? widget.item.episodes.toList()
        : List<_TvEpisode>.generate(
            8,
            (index) => _TvEpisode(
              season: 1,
              episode: index + 1,
              title: 'Episode ${index + 1}',
              description: index == 0
                  ? widget.item.description?.trim().isNotEmpty == true
                        ? widget.item.description!.trim()
                        : 'Start the season from the first episode.'
                  : 'Episode details will appear here when metadata is available.',
            ),
          );
    final seasons =
        allEpisodes.map((episode) => episode.season).toSet().toList()..sort();
    var selectedSeason = seasons.isNotEmpty ? seasons.first : 1;
    final closeFocusNode = FocusNode(debugLabel: 'tv-episode-picker-close');
    final firstEpisodeFocusNode = FocusNode(
      debugLabel: 'tv-episode-picker-first',
    );
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                final episodes = allEpisodes
                    .where((episode) => episode.season == selectedSeason)
                    .toList();
                return Container(
                  width: 800,
                  constraints: const BoxConstraints(maxHeight: 610),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15151E),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0x22FFFFFF)),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _TvCircleIconButton(
                          focusNode: closeFocusNode,
                          icon: Icons.close_rounded,
                          size: 48,
                          onArrowUp: () => closeFocusNode.requestFocus(),
                          onArrowRight: () => closeFocusNode.requestFocus(),
                          onArrowLeft: () =>
                              firstEpisodeFocusNode.requestFocus(),
                          onArrowDown: () =>
                              firstEpisodeFocusNode.requestFocus(),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 70),
                              child: Text(
                                '${widget.item.title} episodes',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(height: _tvSpacing / 2),
                            Text(
                              widget.item.episodes.isNotEmpty
                                  ? 'Choose an episode to start playback on this TV.'
                                  : 'Episode metadata is still loading for this title.',
                              style: const TextStyle(
                                color: Color(0xFFAAA6BD),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final season in seasons)
                                  _TvSeasonButton(
                                    label: 'Season $season',
                                    selected: season == selectedSeason,
                                    onPressed: () => setDialogState(() {
                                      selectedSeason = season;
                                    }),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    for (final episode in episodes)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: _TvEpisodeCard(
                                          episode: episode,
                                          autofocus: episode == episodes.first,
                                          focusNode: episode == episodes.first
                                              ? firstEpisodeFocusNode
                                              : null,
                                          onArrowUp: episode == episodes.first
                                              ? () => closeFocusNode
                                                    .requestFocus()
                                              : null,
                                          onPlay: () {
                                            Navigator.of(dialogContext).pop();
                                            widget.onPlayEpisode(
                                              episode.season,
                                              episode.episode,
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
                    ],
                  ),
                );
              },
            ),
          );
        },
      );
    } finally {
      closeFocusNode.dispose();
      firstEpisodeFocusNode.dispose();
    }
    if (!mounted) return;
    _episodesFocusNode.requestFocus();
  }

  List<Widget> _detailActions(BuildContext context) {
    final afterPrimary = _isSeriesLike ? _episodesFocusNode : _trailerFocusNode;
    final beforeTrailer = _isSeriesLike
        ? _episodesFocusNode
        : _primaryActionFocusNode;
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
        onArrowRight: afterPrimary.requestFocus,
        onArrowUp: _closeFocusNode.requestFocus,
        onArrowDown: _closeFocusNode.requestFocus,
        onPressed: widget.onPlay,
      ),
      if (_isSeriesLike)
        _TvTextButton(
          focusNode: _episodesFocusNode,
          icon: Icons.format_list_numbered_rounded,
          label: 'Episodes',
          enabled: !widget.preparing,
          onArrowLeft: _primaryActionFocusNode.requestFocus,
          onArrowRight: _trailerFocusNode.requestFocus,
          onArrowUp: _closeFocusNode.requestFocus,
          onArrowDown: _closeFocusNode.requestFocus,
          onPressed: () => _showEpisodePicker(context),
        ),
      _TvTextButton(
        focusNode: _trailerFocusNode,
        icon: Icons.movie_filter_rounded,
        label: 'Trailer',
        enabled: !widget.preparing,
        onArrowLeft: beforeTrailer.requestFocus,
        onArrowRight: _likeFocusNode.requestFocus,
        onArrowUp: _closeFocusNode.requestFocus,
        onArrowDown: _closeFocusNode.requestFocus,
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
        onArrowUp: _closeFocusNode.requestFocus,
        onArrowDown: _closeFocusNode.requestFocus,
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
                    width: 790,
                    constraints: const BoxConstraints(maxHeight: 500),
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: const Color(0xFF15151E),
                      borderRadius: BorderRadius.circular(28),
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
                            size: 48,
                            onArrowLeft: _likeFocusNode.requestFocus,
                            onArrowRight: _closeFocusNode.requestFocus,
                            onArrowUp: _closeFocusNode.requestFocus,
                            onArrowDown: widget.preparing
                                ? _closeFocusNode.requestFocus
                                : _primaryActionFocusNode.requestFocus,
                            onPressed: widget.onClose,
                          ),
                        ),
                        Row(
                          children: [
                            _PosterArtwork(
                              item: widget.item,
                              width: 210,
                              height: 300,
                            ),
                            const SizedBox(width: 28),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 24,
                                  right: 70,
                                ),
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
                                    const SizedBox(height: 10),
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
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.item.subtitle,
                                      style: const TextStyle(
                                        color: Color(0xFFAAA6BD),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Text(
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
                                    const SizedBox(height: 24),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: _detailActions(context),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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
              color: focused && selected
                  ? Colors.white
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
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autoReveal: true,
      onPressed: onPressed,
      builder: (focused) {
        final active = focused || selected;
        return AnimatedContainer(
          duration: _tvDuration(140),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: selected
                ? _tvAccentColor
                : focused
                ? const Color(0x1F20D66B)
                : const Color(0x5531313C),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused && selected
                  ? Colors.white
                  : active
                  ? _tvAccentColor
                  : const Color(0x33FFFFFF),
              width: active ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
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
    this.autofocus = false,
    this.focusNode,
    this.onArrowUp,
  });

  final _TvEpisode episode;
  final VoidCallback onPlay;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onArrowUp;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      autoReveal: true,
      onArrowUp: onArrowUp,
      onPressed: onPlay,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(140),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: focused ? const Color(0x1F20D66B) : const Color(0x16FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: focused ? _tvFocusBorder : const Color(0x22FFFFFF),
              width: focused ? 2 : 1,
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
                      ? const ColoredBox(
                          color: Color(0xFF20242E),
                          child: Icon(
                            Icons.smart_display_rounded,
                            color: Colors.white54,
                            size: 34,
                          ),
                        )
                      : Image.network(
                          episode.thumbnail!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return const ColoredBox(
                              color: Color(0xFF20242E),
                              child: Icon(
                                Icons.smart_display_rounded,
                                color: Colors.white54,
                                size: 34,
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'S${episode.season} E${episode.episode} - ${episode.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      episode.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFAAA6BD),
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              AnimatedContainer(
                duration: _tvDuration(140),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: focused ? _tvAccentColor : const Color(0x1FFFFFFF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x22FFFFFF)),
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: focused ? Colors.black : Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvSearchOverlay extends StatefulWidget {
  const _TvSearchOverlay({
    required this.items,
    required this.onClose,
    required this.onOpenItem,
  });

  final List<_TvItem> items;
  final VoidCallback onClose;
  final ValueChanged<_TvItem> onOpenItem;

  @override
  State<_TvSearchOverlay> createState() => _TvSearchOverlayState();
}

class _TvSearchOverlayState extends State<_TvSearchOverlay> {
  static const _voiceChannel = MethodChannel('app.juicr.flutter/voice_search');

  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchBarFocusNode = FocusNode(debugLabel: 'tv-search-bar');
  final FocusNode _searchTextFocusNode = FocusNode(
    debugLabel: 'tv-search-text',
  );
  final FocusNode _voiceFocusNode = FocusNode(debugLabel: 'tv-search-voice');
  final FocusNode _closeFocusNode = FocusNode(debugLabel: 'tv-search-close');
  final FocusNode _resultsFocusNode = FocusNode(
    debugLabel: 'tv-search-results-first',
  );
  String _query = '';
  bool _listening = false;
  bool _editingText = false;

  @override
  void initState() {
    super.initState();
    _searchTextFocusNode
      ..canRequestFocus = false
      ..skipTraversal = true;
    _controller.addListener(() {
      setState(() => _query = _controller.text.trim());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchBarFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchBarFocusNode.dispose();
    _searchTextFocusNode.dispose();
    _voiceFocusNode.dispose();
    _closeFocusNode.dispose();
    _resultsFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<_TvItem> get _results {
    final query = _query.toLowerCase();
    if (query.isEmpty) return widget.items.take(24).toList();
    return widget.items
        .where((item) {
          final haystack = [
            item.title,
            item.type,
            item.year,
            item.genres.join(' '),
            item.description,
          ].whereType<String>().join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .take(36)
        .toList();
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

  void _focusSearchBar() {
    _endTextEntry();
    _searchBarFocusNode.requestFocus();
  }

  void _focusSearchResults() {
    if (_results.isEmpty) return;
    _resultsFocusNode.requestFocus();
  }

  KeyEventResult _handleSearchFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (!_editingText &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space)) {
      _beginTextEntry();
      return KeyEventResult.handled;
    }
    if (_editingText &&
        (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape)) {
      _endTextEntry();
      return KeyEventResult.handled;
    }
    if (_editingText) {
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
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _TvCircleIconButton(
                          icon: Icons.close_rounded,
                          onPressed: widget.onClose,
                          focusNode: _closeFocusNode,
                          onArrowLeft: () => _voiceFocusNode.requestFocus(),
                          onArrowDown: _focusSearchBar,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 60),
                            child: Row(
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
                                  onArrowRight: () =>
                                      _closeFocusNode.requestFocus(),
                                  onArrowDown: _focusSearchBar,
                                  onPressed: () => unawaited(_voiceSearch()),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Focus(
                            focusNode: _searchBarFocusNode,
                            autofocus: true,
                            onKeyEvent: _handleSearchFieldKey,
                            canRequestFocus: !_editingText,
                            skipTraversal: _editingText,
                            child: Builder(
                              builder: (context) {
                                final focused =
                                    _searchBarFocusNode.hasFocus ||
                                    _searchTextFocusNode.hasFocus;
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
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: focused || _editingText
                                            ? _tvFocusBorder
                                            : const Color(0x22FFFFFF),
                                        width: focused || _editingText ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.search_rounded,
                                          color: Color(0xFFBDB9D5),
                                          size: 26,
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
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
                                            onEditingComplete: _endTextEntry,
                                            onSubmitted: (_) => _endTextEntry(),
                                          ),
                                        ),
                                        if (_query.isNotEmpty)
                                          _TvTextButton(
                                            icon: Icons.clear_rounded,
                                            label: 'Clear',
                                            onPressed: _controller.clear,
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          Expanded(
                            child: SingleChildScrollView(
                              child: _results.isEmpty
                                  ? _TvEmptyCatalogState(
                                      title: 'No TV results yet.',
                                      subtitle:
                                          'Try another title, channel, or animation name.',
                                      height:
                                          MediaQuery.sizeOf(context).height -
                                          300,
                                      verticalOffset: 0,
                                    )
                                  : _TvPosterGrid(
                                      title: _query.isEmpty
                                          ? 'Suggested'
                                          : 'Results',
                                      subtitle: _query.isEmpty
                                          ? 'Remote-select an item to open details.'
                                          : '${_results.length} matching title(s).',
                                      items: _results,
                                      showRank: false,
                                      columnCount: 8,
                                      posterAspect: 1.36,
                                      firstItemFocusNode: _resultsFocusNode,
                                      onTopRowArrowUp: _focusSearchBar,
                                      onOpenItem: widget.onOpenItem,
                                    ),
                            ),
                          ),
                        ],
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
