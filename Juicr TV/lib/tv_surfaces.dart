part of 'main.dart';

class _TvDiscoverySurface extends StatelessWidget {
  const _TvDiscoverySurface({
    required this.allItems,
    required this.movies,
    required this.series,
    required this.animation,
    required this.liveTv,
    required this.kind,
    required this.sort,
    required this.genre,
    required this.onOpenItem,
    required this.onFocusNavigation,
    required this.entryFocusNode,
    required this.onFocusHeader,
  });

  final List<_TvItem> allItems;
  final List<_TvItem> movies;
  final List<_TvItem> series;
  final List<_TvItem> animation;
  final List<_TvItem> liveTv;
  final _TvDiscoveryKind kind;
  final _TvDiscoverySort sort;
  final String genre;
  final ValueChanged<_TvItem> onOpenItem;
  final VoidCallback onFocusNavigation;
  final FocusNode entryFocusNode;
  final VoidCallback onFocusHeader;

  @override
  Widget build(BuildContext context) {
    final items = _sortedCatalogItems(
      switch (kind) {
        _TvDiscoveryKind.movie => movies,
        _TvDiscoveryKind.series => series,
        _TvDiscoveryKind.animation => animation,
        _TvDiscoveryKind.liveTv => liveTv,
      },
      sort,
    );
    final visibleItems = genre == 'All genres'
        ? items
        : items.where((item) {
            return item.genres.any((itemGenre) => itemGenre.toLowerCase() == genre.toLowerCase());
          }).toList();

    if (visibleItems.isEmpty) {
      return _TvEmptyCatalogState(
        title: 'Discovery is waiting for catalog data.',
        subtitle: genre == 'All genres'
            ? 'Turn on a source in Settings or refresh when your connection is ready.'
            : 'No ${kind.label.toLowerCase()} are available for $genre yet.',
        height: MediaQuery.sizeOf(context).height - 210,
        verticalOffset: -42,
      );
    }

    return _TvPosterGrid(
      title: '${kind.label} catalog',
      subtitle: sort.subtitle,
      items: visibleItems,
      showRank: false,
      showHeader: false,
      firstItemFocusNode: entryFocusNode,
      onOpenItem: onOpenItem,
      onFocusNavigation: onFocusNavigation,
      onTopRowArrowUp: onFocusHeader,
    );
  }

  List<_TvItem> _sortedCatalogItems(List<_TvItem> source, _TvDiscoverySort sort) {
    final items = source.where((item) => item.poster != null).toList();
    switch (sort) {
      case _TvDiscoverySort.newest:
        items.sort((a, b) => (_yearInt(b.year)).compareTo(_yearInt(a.year)));
      case _TvDiscoverySort.featured:
        items.sort((a, b) => (_ratingDouble(b.imdbRating)).compareTo(_ratingDouble(a.imdbRating)));
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
  });

  final List<_TvItem> recentItems;
  final List<_TvItem> likedItems;
  final _TvLibraryFilter filter;
  final ValueChanged<_TvItem> onOpenItem;
  final VoidCallback onFocusNavigation;
  final FocusNode entryFocusNode;
  final VoidCallback onFocusHeader;

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;

    if (items.isEmpty) {
      return _TvEmptyCatalogState(
        title: _emptyTitle,
        subtitle: _emptySubtitle,
        height: MediaQuery.sizeOf(context).height - 210,
        verticalOffset: 42,
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
    );
  }

  List<_TvItem> get _filteredItems {
    switch (filter) {
      case _TvLibraryFilter.continueWatching:
        return recentItems.where((item) => item.poster != null).toList();
      case _TvLibraryFilter.movies:
        return likedItems.where((item) => item.type == 'movie' && item.poster != null).toList();
      case _TvLibraryFilter.series:
        return likedItems.where((item) => item.type == 'series' && item.poster != null).toList();
      case _TvLibraryFilter.animation:
        return likedItems.where((item) => item.type == 'animation' && item.poster != null).toList();
      case _TvLibraryFilter.liveTv:
        return likedItems
            .where((item) => (item.type == 'live' || item.type == 'livetv' || item.type == 'channel') && item.poster != null)
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
      _TvLibraryFilter.continueWatching => 'Recently opened titles from this TV session.',
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
      _TvLibraryFilter.continueWatching => 'Open or play a title and it will appear here for this session.',
      _TvLibraryFilter.movies => 'Heart a movie from Home, Discovery, or Details to show it here.',
      _TvLibraryFilter.series => 'Heart a series from Home, Discovery, or Details to show it here.',
      _TvLibraryFilter.animation => 'Heart an animation title from Home, Discovery, or Details to show it here.',
      _TvLibraryFilter.liveTv => 'Heart Live TV items when they are available on this TV.',
    };
  }
}

class _TvSurfaceIntro extends StatelessWidget {
  const _TvSurfaceIntro({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 580,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFFAAA6BD),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvEmptyCatalogState extends StatelessWidget {
  const _TvEmptyCatalogState({
    required this.title,
    required this.subtitle,
    this.height,
    this.verticalOffset = 0,
  });

  final String title;
  final String subtitle;
  final double? height;
  final double verticalOffset;

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
              const Icon(Icons.explore_off_rounded, color: Color(0xFFAAA6BD), size: 52),
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
    final targetHeight = height;
    if (targetHeight == null) return content;
    return SizedBox(
      height: targetHeight < 300 ? 300 : targetHeight,
      child: content,
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
    required this.settings,
    required this.onSettingsChanged,
    required this.onFocusNavigation,
    required this.onRefresh,
    required this.entryFocusNode,
  });

  final int totalCount;
  final int movieCount;
  final int seriesCount;
  final int animationCount;
  final bool hasCatalog;
  final _TvSettingsState settings;
  final ValueChanged<_TvSettingsState> onSettingsChanged;
  final VoidCallback onFocusNavigation;
  final VoidCallback onRefresh;
  final FocusNode entryFocusNode;

  @override
  Widget build(BuildContext context) {
    final sections = [
      const _TvSettingsSection(
        'General',
        'Theme, display, language, and TV home preferences.',
        Icons.settings_rounded,
        [
          _TvSettingsLine('Appearance', 'Use the TV visual style tuned for large screens and remote viewing.'),
          _TvSettingsLine('Language', 'App language follows the device until TV language controls are enabled.'),
          _TvSettingsLine('Text size', 'Large readable labels stay enabled for living-room distance.'),
          _TvSettingsLine('Home experience', 'Home uses shared editorial curation with TV-safe fallbacks.'),
        ],
      ),
      const _TvSettingsSection(
        'Playback',
        'Player defaults, captions, quality, and watch behavior.',
        Icons.play_circle_fill_rounded,
        [
          _TvSettingsLine('Playback engine', 'Auto chooses the safest available TV playback path.'),
          _TvSettingsLine('Preferred quality', 'TV playback starts with a balanced quality target.'),
          _TvSettingsLine('Subtitles', 'Captions stay readable and can be refined in playback settings.'),
          _TvSettingsLine('Continue watching', 'Progress is kept for the current TV session.'),
          _TvSettingsLine('Next episode', 'Series playback can continue from the playback HUD.'),
        ],
      ),
      const _TvSettingsSection(
        'Add-ons',
        'Catalog and playback manifests you choose to manage.',
        Icons.extension_rounded,
        [
          _TvSettingsLine('Manage add-ons', 'TV add-on management is being prepared for remote-first controls.'),
          _TvSettingsLine('Default source lanes', 'Catalog, subtitle, and playback capabilities stay separated.'),
          _TvSettingsLine('Import and export', 'Add-on transfer will stay user-controlled and redacted.'),
          _TvSettingsLine('Safety', 'Only add manifests you trust; Juicr does not review third-party services.'),
        ],
      ),
      const _TvSettingsSection(
        'Advanced',
        'History, storage, and power-user TV controls.',
        Icons.admin_panel_settings_outlined,
        [
          _TvSettingsLine('Runtime controls', 'Advanced playback controls stay guarded until ready for this TV build.'),
          _TvSettingsLine('History tools', 'Session history can be reviewed without exposing private playback details.'),
          _TvSettingsLine('Playback tuning', 'Timing and recovery controls stay grouped away from everyday settings.'),
          _TvSettingsLine('Storage', 'TV storage tools will use safe counts and clear actions.'),
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
          const _TvSettingsLine('Diagnostics', 'Reports use safe counts and status buckets only.'),
          const _TvSettingsLine('Privacy boundary', 'Private playback details are not shown in TV diagnostics.'),
        ],
      ),
    ];
    return _TvSettingsGrid(
      sections: sections,
      entryFocusNode: entryFocusNode,
      onFocusNavigation: onFocusNavigation,
      onOpenSection: (section) => _showTvSettingsSection(context, section),
    );
  }

  Future<void> _showTvSettingsSection(BuildContext context, _TvSettingsSection section) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => _TvSettingsSectionDialog(
        section: section,
        settings: settings,
        onSettingsChanged: onSettingsChanged,
      ),
    );
  }
}

class _TvSettingsGrid extends StatefulWidget {
  const _TvSettingsGrid({
    required this.sections,
    required this.entryFocusNode,
    required this.onFocusNavigation,
    required this.onOpenSection,
  });

  final List<_TvSettingsSection> sections;
  final FocusNode entryFocusNode;
  final VoidCallback onFocusNavigation;
  final ValueChanged<_TvSettingsSection> onOpenSection;

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

  void _focusIndex(int index) {
    if (index < 0 || index >= widget.sections.length) return;
    _nodeFor(index).requestFocus();
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
                onArrowLeft: index % _columnCount == 0 ? widget.onFocusNavigation : () => _focusIndex(index - 1),
                onArrowRight: index + 1 < widget.sections.length && index % _columnCount != _columnCount - 1
                    ? () => _focusIndex(index + 1)
                    : null,
                onArrowUp: index - _columnCount >= 0 ? () => _focusIndex(index - _columnCount) : null,
                onArrowDown: index + _columnCount < widget.sections.length ? () => _focusIndex(index + _columnCount) : null,
                onPressed: () => widget.onOpenSection(widget.sections[index]),
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
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
  });

  final _TvSettingsSection section;
  final VoidCallback onPressed;
  final double width;
  final FocusNode? focusNode;
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
        autoReveal: true,
        onPressed: onPressed,
        onArrowLeft: onArrowLeft,
        onArrowRight: onArrowRight,
        onArrowUp: onArrowUp,
        onArrowDown: onArrowDown,
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
                Icon(section.icon, color: focused ? Colors.black : _tvAccentColor, size: 28),
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
                    color: focused ? Colors.black.withValues(alpha: 0.72) : const Color(0xFFAAA6BD),
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
    required this.onSettingsChanged,
  });

  final _TvSettingsSection section;
  final _TvSettingsState settings;
  final ValueChanged<_TvSettingsState> onSettingsChanged;

  @override
  State<_TvSettingsSectionDialog> createState() => _TvSettingsSectionDialogState();
}

class _TvSettingsSectionDialogState extends State<_TvSettingsSectionDialog> {
  late _TvSettingsState _current = widget.settings;

  void _update(_TvSettingsState next) {
    setState(() => _current = next);
    widget.onSettingsChanged(next);
  }

  Future<String?> _pickOption(
    BuildContext context, {
    required String title,
    required String selected,
    required List<String> options,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _TvSettingsOptionDialog(
        title: title,
        selected: selected,
        options: options,
      ),
    );
  }

  Future<void> _showStatusDialog(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.info_outline_rounded,
  }) {
    return showDialog<void>(
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
  }

  Future<bool> _confirmBuiltInConsent(BuildContext context, _TvSettingsState current) async {
    if (current.defaultSourceConsentAccepted) return true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _TvConsentDialog(
        title: 'Enable built-in sources?',
        intro:
            'Before Juicr turns these optional tools on, confirm each acknowledgement. Juicr provides the app tools; you choose what sources to enable and use.',
        confirmLabel: 'Enable sources',
        acknowledgements: const [
          _TvConsentAcknowledgement(
            'Juicr does not provide media',
            'Built-in sources are optional tools for catalog items, subtitles, trailers, and playback lookups.',
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
    return accepted == true;
  }

  Future<bool> _confirmAddOnConsent(BuildContext context, _TvSettingsState current) async {
    if (current.addOnConsentAccepted) return true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _TvConsentDialog(
        title: 'Add third-party add-on?',
        intro:
            'Add-ons are manifests you choose. Juicr does not review, control, or endorse third-party add-ons.',
        confirmLabel: 'I understand',
        acknowledgements: const [
          _TvConsentAcknowledgement(
            'Only add sources you trust',
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
    return accepted == true;
  }

  Future<void> _toggleBuiltIn(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update,
    _TvSettingsState Function(_TvSettingsState source) enabledState,
    _TvSettingsState Function(_TvSettingsState source) disabledState,
    bool enabled,
  ) async {
    if (!enabled) {
      update(disabledState(current));
      return;
    }
    if (!await _confirmBuiltInConsent(context, current)) return;
    update(enabledState(current.copyWith(defaultSourceConsentAccepted: true)));
  }

  Future<void> _openDefaultSources(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update,
  ) async {
    if (!await _confirmBuiltInConsent(context, current)) return;
    update(
      current.copyWith(
        defaultSourceConsentAccepted: true,
        showDefaultSourceSettings: true,
      ),
    );
  }

  Future<void> _addUserAddOn(
    BuildContext context,
    _TvSettingsState current,
    ValueChanged<_TvSettingsState> update,
  ) async {
    if (!await _confirmAddOnConsent(context, current)) return;
    final consented = current.copyWith(addOnConsentAccepted: true);
    update(consented);
    final added = await showDialog<_TvUserAddOn>(
      context: context,
      builder: (dialogContext) => const _TvAddOnEntryDialog(),
    );
    if (added == null) return;
    update(
      consented.copyWith(
        userAddOns: [...consented.userAddOns, added],
      ),
    );
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
            subtitle: 'Choose the highlight color used for focus and selected controls.',
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
                options: const ['Smaller', 'Small', 'Large', 'Larger', 'Maximum'],
              );
              if (selected != null) update(current.copyWith(textSize: selected));
            }()),
          ),
          _TvSettingsAction(
            title: 'Motion',
            subtitle: 'Keep TV transitions smooth without making navigation noisy.',
            value: current.motion ? 'Full' : 'Reduced',
            icon: Icons.animation_rounded,
            onPressed: () => unawaited(() async {
              final selected = await _pickOption(
                context,
                title: 'Motion',
                selected: current.motion ? 'Full' : 'Reduced',
                options: const ['Full', 'Reduced'],
              );
              if (selected != null) update(current.copyWith(motion: selected == 'Full'));
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
              if (selected != null) update(current.copyWith(playbackEngine: selected));
            }()),
          ),
          _TvSettingsAction(
            title: 'Preferred quality',
            subtitle: 'Choose the default quality target before playback starts.',
            value: current.preferredQuality,
            icon: Icons.high_quality_rounded,
            onPressed: () => unawaited(() async {
              final selected = await _pickOption(
                context,
                title: 'Preferred quality',
                selected: current.preferredQuality,
                options: const ['Balanced', 'Best available', 'Data saver'],
              );
              if (selected != null) update(current.copyWith(preferredQuality: selected));
            }()),
          ),
          _TvSettingsAction(
            title: 'Resume prompt',
            subtitle: 'Ask whether to continue or start over when progress is saved.',
            value: current.resumePrompt ? 'Ask' : 'Start over',
            icon: Icons.restore_rounded,
            onPressed: () => update(current.copyWith(resumePrompt: !current.resumePrompt)),
          ),
          _TvSettingsAction(
            title: 'Subtitles',
            subtitle: 'Show TV-readable captions when subtitle data is available.',
            value: current.subtitles ? 'On' : 'Off',
            icon: Icons.closed_caption_rounded,
            onPressed: () => update(current.copyWith(subtitles: !current.subtitles)),
          ),
          _TvSettingsAction(
            title: 'Next episode',
            subtitle: 'Keep series continuation controls available in the playback HUD.',
            value: current.nextEpisode ? 'On' : 'Off',
            icon: Icons.skip_next_rounded,
            onPressed: () => update(current.copyWith(nextEpisode: !current.nextEpisode)),
          ),
        ];
      case 'Add-ons':
        return [
          _TvSettingsAction(
            title: 'Add your own add-on',
            subtitle: 'Add a manifest you trust. The saved settings only show safe labels here.',
            value: current.userAddOns.isEmpty ? 'None' : '${current.userAddOns.length} saved',
            icon: Icons.add_link_rounded,
            onPressed: () => unawaited(_addUserAddOn(context, current, update)),
          ),
          _TvSettingsAction(
            title: 'Default',
            subtitle: current.defaultSourceConsentAccepted
                ? 'Manage optional Built-in catalog, subtitles, trailers, Live TV, and playback.'
                : 'Review consent before showing optional Built-in source tools.',
            value: current.defaultSourceConsentAccepted ? 'Ready' : 'Consent',
            icon: Icons.inventory_2_outlined,
            onPressed: () => unawaited(_openDefaultSources(context, current, update)),
          ),
          if (current.showDefaultSourceSettings) ...[
          _TvSettingsAction(
            title: 'Built-in catalog',
            subtitle: 'Use optional Juicr catalog results on Home and Discovery.',
            value: current.builtInCatalog ? 'On' : 'Off',
            icon: Icons.grid_view_rounded,
            onPressed: () => unawaited(
              _toggleBuiltIn(
                context,
                current,
                update,
                (source) => source.copyWith(builtInCatalog: true),
                (source) => source.copyWith(builtInCatalog: false),
                !current.builtInCatalog,
              ),
            ),
          ),
          _TvSettingsAction(
            title: 'Built-in subtitles',
            subtitle: 'Look up optional default subtitles in the native TV player.',
            value: current.builtInSubtitles ? 'On' : 'Off',
            icon: Icons.closed_caption_outlined,
            onPressed: () => unawaited(
              _toggleBuiltIn(
                context,
                current,
                update,
                (source) => source.copyWith(builtInSubtitles: true, subtitles: true),
                (source) => source.copyWith(builtInSubtitles: false),
                !current.builtInSubtitles,
              ),
            ),
          ),
          _TvSettingsAction(
            title: 'Built-in trailers',
            subtitle: 'Show optional trailer choices on details pages.',
            value: current.builtInTrailers ? 'On' : 'Off',
            icon: Icons.movie_filter_outlined,
            onPressed: () => unawaited(
              _toggleBuiltIn(
                context,
                current,
                update,
                (source) => source.copyWith(builtInTrailers: true),
                (source) => source.copyWith(builtInTrailers: false),
                !current.builtInTrailers,
              ),
            ),
          ),
          _TvSettingsAction(
            title: 'Built-in Live TV',
            subtitle: 'Show optional public live TV channels when this lane is enabled.',
            value: current.builtInLiveTv ? 'On' : 'Off',
            icon: Icons.live_tv_rounded,
            onPressed: () => unawaited(
              _toggleBuiltIn(
                context,
                current,
                update,
                (source) => source.copyWith(builtInLiveTv: true),
                (source) => source.copyWith(builtInLiveTv: false),
                !current.builtInLiveTv,
              ),
            ),
          ),
          _TvSettingsAction(
            title: 'Built-in playback',
            subtitle: 'Allow optional built-in TV playback after safe app checks.',
            value: current.builtInPlayback ? 'On' : 'Off',
            icon: Icons.play_circle_outline_rounded,
            onPressed: () => unawaited(
              _toggleBuiltIn(
                context,
                current,
                update,
                (source) => source.copyWith(builtInPlayback: true),
                (source) => source.copyWith(builtInPlayback: false),
                !current.builtInPlayback,
              ),
            ),
          ),
          ],
        ];
      case 'Advanced':
        return [
          _TvSettingsAction(
            title: 'Advanced controls',
            subtitle: 'Show guarded power-user playback controls when they are ready for TV.',
            value: current.advancedControls ? 'On' : 'Off',
            icon: Icons.admin_panel_settings_outlined,
            onPressed: () => update(current.copyWith(advancedControls: !current.advancedControls)),
          ),
          _TvSettingsAction(
            title: 'History tools',
            subtitle: 'Keep local session history controls available for this TV.',
            value: current.history ? 'On' : 'Off',
            icon: Icons.history_rounded,
            onPressed: () => update(current.copyWith(history: !current.history)),
          ),
          _TvSettingsAction(
            title: 'Safe diagnostics',
            subtitle: 'Keep diagnostics limited to safe counts and status buckets.',
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
        ];
      default:
        return [
          _TvSettingsAction(
            title: 'API connection',
            subtitle: 'Catalog, metadata, editorial, trailers, and guarded playback use Juicr API routes.',
            value: 'Connected',
            icon: Icons.cloud_done_rounded,
            onPressed: () => unawaited(
              _showStatusDialog(
                context,
                title: 'API connection',
                message:
                    'Catalog, metadata, editorial, trailers, and guarded playback checks use Juicr app routes. The TV never shows private request details here.',
                icon: Icons.cloud_done_rounded,
              ),
            ),
          ),
          _TvSettingsAction(
            title: 'Playback path',
            subtitle: 'TV playback uses protected app routes and keeps private playback details hidden.',
            value: 'Guarded',
            icon: Icons.play_circle_fill_rounded,
            onPressed: () => unawaited(
              _showStatusDialog(
                context,
                title: 'Playback path',
                message:
                    'Playback stays behind TV-safe app controls. Enable playback sources in Add-ons before starting titles.',
                icon: Icons.play_circle_fill_rounded,
              ),
            ),
          ),
          _TvSettingsAction(
            title: 'Subtitles',
            subtitle: 'Caption support is enabled when subtitle data is available for the selected title.',
            value: current.builtInSubtitles && current.subtitles ? 'On' : 'Off',
            icon: Icons.closed_caption_rounded,
            onPressed: () => update(
              current.copyWith(
                subtitles: !(current.builtInSubtitles && current.subtitles),
                builtInSubtitles: !(current.builtInSubtitles && current.subtitles),
              ),
            ),
          ),
          _TvSettingsAction(
            title: 'Diagnostics',
            subtitle: 'Reports stay redacted and do not show private playback or source details.',
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(context, _current, _update);
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
                icon: Icons.close_rounded,
                size: 48,
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
                          Icon(widget.section.icon, color: _tvAccentColor, size: 30),
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
  });

  final _TvSettingsAction action;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
      autoReveal: false,
      onPressed: action.onPressed,
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
              Icon(action.icon, color: focused ? Colors.black : _tvAccentColor, size: 26),
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
                        color: focused ? Colors.black.withValues(alpha: 0.72) : const Color(0xFFAAA6BD),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: focused ? Colors.black.withValues(alpha: 0.14) : const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: focused ? Colors.black.withValues(alpha: 0.18) : const Color(0x22FFFFFF)),
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

class _TvSettingsOptionDialog extends StatelessWidget {
  const _TvSettingsOptionDialog({
    required this.title,
    required this.selected,
    required this.options,
  });

  final String title;
  final String selected;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
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
                    icon: Icons.close_rounded,
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
                        title,
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
                    ...options.map(
                      (option) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TvSettingsOptionRow(
                          label: option,
                          selected: option == selected,
                          onPressed: () => Navigator.of(context).pop(option),
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
    );
  }
}

class _TvSettingsOptionRow extends StatelessWidget {
  const _TvSettingsOptionRow({
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
      autofocus: selected,
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
              color: focused && selected ? _tvFocusBorder : active ? _tvAccentColor : const Color(0x22FFFFFF),
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
    final allAccepted = _acceptedIndexes.length == widget.acknowledgements.length;
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
                    for (var index = 0; index < widget.acknowledgements.length; index++)
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
                        ? 'Thanks. This source lane can be enabled now.'
                        : 'Check every acknowledgement to continue.',
                    style: TextStyle(
                      color: allAccepted ? _tvAccentColor : const Color(0xFFAAA6BD),
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
                checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
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
                        color: active ? Colors.black.withValues(alpha: 0.72) : const Color(0xFFAAA6BD),
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
              'Enter a display name and manifest address for a source you trust.',
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
              hintText: 'https://example.com/manifest.json',
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
  late final FocusNode _ownedShellFocusNode = FocusNode(debugLabel: 'tv-dialog-edit-shell');
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

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (!_editing &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space)) {
      _beginEditing();
      return KeyEventResult.handled;
    }
    if (_editing &&
        (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape)) {
      _endEditing();
      return KeyEventResult.handled;
    }
    if (!_editing && key == LogicalKeyboardKey.arrowUp && widget.onArrowUp != null) {
      widget.onArrowUp!();
      return KeyEventResult.handled;
    }
    if (!_editing && key == LogicalKeyboardKey.arrowDown && widget.onArrowDown != null) {
      widget.onArrowDown!();
      return KeyEventResult.handled;
    }
    return _editing ? KeyEventResult.ignored : KeyEventResult.ignored;
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    prefixIcon: Icon(widget.icon, color: const Color(0xFFAAA6BD)),
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(color: Color(0xFFAAA6BD), fontWeight: FontWeight.w700),
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
    required this.onPlay,
    required this.onPlayEpisode,
    required this.onToggleLike,
  });

  final _TvItem item;
  final VoidCallback onClose;
  final bool preparing;
  final bool liked;
  final VoidCallback onPlay;
  final void Function(int season, int episode) onPlayEpisode;
  final VoidCallback onToggleLike;

  @override
  State<_TvDetailsOverlay> createState() => _TvDetailsOverlayState();
}

class _TvDetailsOverlayState extends State<_TvDetailsOverlay> {
  bool get _isSeriesLike => widget.item.type == 'series' || widget.item.type == 'animation';

  Future<void> _showTrailerPicker(BuildContext context) async {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Loading trailers...'), duration: Duration(seconds: 1)),
      );
    final trailers = await _TvApi().trailers(widget.item).catchError((_) => const <_TvTrailer>[]);
    if (!context.mounted) return;
    if (trailers.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No TV trailer is available for this title yet.')),
        );
      return;
    }
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
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 56),
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
                        'Choose a trailer that is ready for TV playback.',
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
                              for (var index = 0; index < trailers.take(6).length; index++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: _TvTextButton(
                                      icon: trailers[index].isTvPlayable
                                          ? Icons.movie_filter_rounded
                                          : Icons.lock_clock_rounded,
                                      label: trailers[index].isTvPlayable
                                          ? trailers[index].title
                                          : '${trailers[index].title} unavailable',
                                      autofocus: index == 0,
                                      enabled: trailers[index].isTvPlayable,
                                      onPressed: () {
                                        Navigator.of(dialogContext).pop();
                                        unawaited(_openTrailer(context, trailers[index]));
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
  }

  Future<void> _openTrailer(BuildContext context, _TvTrailer trailer) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Preparing trailer...'), duration: Duration(seconds: 1)),
      );
    VideoPlayerController? controller;
    try {
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
      if (!context.mounted) {
        await controller.dispose();
        return;
      }
      final trailerItem = _TvItem(
        id: '${widget.item.id}:trailer',
        type: 'movie',
        title: '${widget.item.title} trailer',
        color: widget.item.color,
        poster: widget.item.poster,
        background: widget.item.background,
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
            settings: const _TvSettingsState(),
            subtitles: const <_TvSubtitle>[],
            initialSubtitleIndex: -1,
          ),
        ),
      );
    } catch (error) {
      await controller?.dispose();
      if (!context.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('This trailer is not ready for TV playback yet.')),
        );
    }
  }

  Future<void> _showEpisodePicker(BuildContext context) async {
    final allEpisodes = widget.item.episodes.isNotEmpty
        ? widget.item.episodes.take(12).toList()
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
    final seasons = allEpisodes.map((episode) => episode.season).toSet().toList()..sort();
    var selectedSeason = seasons.isNotEmpty ? seasons.first : 1;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final episodes =
                  allEpisodes.where((episode) => episode.season == selectedSeason).toList();
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
                        icon: Icons.close_rounded,
                        size: 48,
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
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _TvEpisodeCard(
                                        episode: episode,
                                        autofocus: episode == episodes.first,
                                        onPlay: () {
                                          Navigator.of(dialogContext).pop();
                                          widget.onPlayEpisode(episode.season, episode.episode);
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
  }

  List<Widget> _detailActions(BuildContext context) {
    return [
      _TvTextButton(
        icon: widget.preparing ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
        label: widget.preparing ? 'Preparing' : 'Watch now',
        autofocus: true,
        enabled: !widget.preparing,
        animateIcon: widget.preparing,
        onPressed: widget.onPlay,
      ),
      if (_isSeriesLike)
        _TvTextButton(
          icon: Icons.format_list_numbered_rounded,
          label: 'Episodes',
          enabled: !widget.preparing,
          onPressed: () => _showEpisodePicker(context),
        ),
      _TvTextButton(
        icon: Icons.movie_filter_rounded,
        label: 'Trailer',
        enabled: !widget.preparing,
        onPressed: () => unawaited(_showTrailerPicker(context)),
      ),
      _TvCircleIconButton(
        icon: widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        selected: widget.liked,
        size: 48,
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
                            icon: Icons.close_rounded,
                            size: 48,
                            onPressed: widget.onClose,
                          ),
                        ),
                        Row(
                          children: [
                            _PosterArtwork(item: widget.item, width: 210, height: 300),
                            const SizedBox(width: 28),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 24, right: 70),
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
                                      widget.item.description?.isNotEmpty == true
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
    this.autofocus = false,
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
  final bool autofocus;
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
      autofocus: autofocus,
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
  });

  final _TvEpisode episode;
  final VoidCallback onPlay;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
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
  static const _voiceChannel = MethodChannel('app.juicr.tv/voice_search');

  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchBarFocusNode = FocusNode(debugLabel: 'tv-search-bar');
  final FocusNode _searchTextFocusNode = FocusNode(debugLabel: 'tv-search-text');
  final FocusNode _voiceFocusNode = FocusNode(debugLabel: 'tv-search-voice');
  final FocusNode _closeFocusNode = FocusNode(debugLabel: 'tv-search-close');
  final FocusNode _resultsFocusNode = FocusNode(debugLabel: 'tv-search-results-first');
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
    return widget.items.where((item) {
      final haystack = [
        item.title,
        item.type,
        item.year,
        item.genres.join(' '),
        item.description,
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).take(36).toList();
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
          const SnackBar(content: Text('Voice search is unavailable on this TV.')),
        );
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Voice search did not hear anything yet.')),
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
                                  icon: _listening ? Icons.hearing_rounded : Icons.mic_rounded,
                                  label: _listening ? 'Listening' : 'Voice',
                                  enabled: !_listening,
                                  animateIcon: _listening,
                                  focusNode: _voiceFocusNode,
                                  onArrowRight: () => _closeFocusNode.requestFocus(),
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
                                final focused = _searchBarFocusNode.hasFocus || _searchTextFocusNode.hasFocus;
                                return GestureDetector(
                                  onTap: _beginTextEntry,
                                  child: AnimatedContainer(
                                    duration: _tvDuration(130),
                                    height: 54,
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
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
                                        const Icon(Icons.search_rounded, color: Color(0xFFBDB9D5), size: 26),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: TextField(
                                            controller: _controller,
                                            focusNode: _searchTextFocusNode,
                                            onTapOutside: (_) => _endTextEntry(),
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
                                      subtitle: 'Try another title, channel, or animation name.',
                                      height: MediaQuery.sizeOf(context).height - 300,
                                      verticalOffset: 0,
                                    )
                                  : _TvPosterGrid(
                                      title: _query.isEmpty ? 'Suggested' : 'Results',
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


