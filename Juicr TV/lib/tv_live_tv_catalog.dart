const String tvLiveTvCatalogType = 'live_tv';
const int tvLiveTvFilteredScanMaxPages = 8;

bool tvCatalogUsesLandscapeSkeleton(String type) {
  final normalized = type.trim().toLowerCase().replaceAll('-', '_');
  return normalized == 'live' ||
      normalized == 'live_tv' ||
      normalized == 'livetv';
}

double tvCatalogSkeletonHeight({
  required String type,
  required double width,
}) {
  return tvCatalogUsesLandscapeSkeleton(type) ? width * 9 / 16 : width * 1.42;
}

bool tvShowCatalogSecondaryLogo({required bool logoFirst}) => !logoFirst;

enum TvLiveTvPlaylist { alpha, beta, gamma }

const List<String> _tvBetaCountryFallback = <String>[
  'Argentina',
  'Australia',
  'Brazil',
  'Canada',
  'China',
  'France',
  'Germany',
  'India',
  'Indonesia',
  'Italy',
  'Japan',
  'Mexico',
  'Philippines',
  'South Korea',
  'Spain',
  'Thailand',
  'United Kingdom',
  'United States',
];

const List<String> _tvGammaGenreFallback = <String>[
  'Documentary',
  'Entertainment',
  'Kids',
  'Lifestyle',
  'Local',
  'Movies',
  'Music',
  'News',
  'Sports',
];

const List<String> _tvAlphaGenreFallback = <String>[
  'Auto',
  'Business',
  'Comedy',
  'Culture',
  'Documentary',
  'Education',
  'Entertainment',
  'Family',
  'General',
  'Kids',
  'Lifestyle',
  'Local',
  'Movies',
  'Music',
  'News',
  'Religious',
  'Shop',
  'Sports',
  'Weather',
];

List<String> tvLiveTvFilterOptions({
  required TvLiveTvPlaylist playlist,
  Iterable<String> serverGenres = const <String>[],
  Iterable<String> serverCountries = const <String>[],
}) {
  final (root, values, normalizeValues) = switch (playlist) {
    TvLiveTvPlaylist.alpha => (
        'All genres',
        serverGenres.isEmpty ? _tvAlphaGenreFallback : serverGenres,
        serverGenres.isNotEmpty,
      ),
    TvLiveTvPlaylist.beta => (
        'All countries',
        serverCountries.isEmpty ? _tvBetaCountryFallback : serverCountries,
        serverCountries.isNotEmpty,
      ),
    TvLiveTvPlaylist.gamma => (
        'All genres',
        _tvGammaGenreFallback,
        false,
      ),
  };
  return <String>[
    root,
    ...normalizeValues
        ? _tvNormalizedFilterValues(values, root: root)
        : _tvDedupeFilterValues(values, root: root),
  ];
}

String tvReconcileLiveTvFilter({
  required TvLiveTvPlaylist playlist,
  required String current,
  Iterable<String> serverGenres = const <String>[],
  Iterable<String> serverCountries = const <String>[],
}) {
  final options = tvLiveTvFilterOptions(
    playlist: playlist,
    serverGenres: serverGenres,
    serverCountries: serverCountries,
  );
  final normalized = current.trim().toLowerCase();
  return options.firstWhere(
    (option) => option.toLowerCase() == normalized,
    orElse: () => options.first,
  );
}

String tvLiveTvFilterTitle(TvLiveTvPlaylist playlist) =>
    playlist == TvLiveTvPlaylist.beta ? 'Country' : 'Genre';

bool tvShouldApplyClientLiveTvGenreFilter(TvLiveTvPlaylist playlist) =>
    playlist != TvLiveTvPlaylist.beta;

bool tvIsLiveTvRootFilter(String filter) {
  final normalized = filter.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'all genres' ||
      normalized == 'all countries';
}

List<T> tvSelectLiveTvDisplayLane<T>({
  required bool hasScopedFilter,
  required List<T>? scopedItems,
  required List<T> baseItems,
}) {
  if (hasScopedFilter) return scopedItems ?? List<T>.empty(growable: false);
  return baseItems;
}

List<String> _tvNormalizedFilterValues(
  Iterable<String> values, {
  required String root,
}) {
  final seen = <String>{root.toLowerCase()};
  final normalized = <String>[];
  for (final raw in values) {
    final display = _tvFilterDisplay(raw);
    final key = display.toLowerCase();
    if (display.isEmpty || !seen.add(key)) continue;
    normalized.add(display);
  }
  return normalized;
}

List<String> _tvDedupeFilterValues(
  Iterable<String> values, {
  required String root,
}) {
  final seen = <String>{root.toLowerCase()};
  final result = <String>[];
  for (final raw in values) {
    final display = raw.trim();
    final key = display.toLowerCase();
    if (display.isEmpty || !seen.add(key)) continue;
    result.add(display);
  }
  return result;
}

String _tvFilterDisplay(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return '';
  final lower = cleaned.toLowerCase();
  if (lower == 'science-fiction' ||
      lower == 'science fiction' ||
      lower == 'sci-fi' ||
      lower == 'sci fi') {
    return 'Science Fiction';
  }
  if (lower == 'sports') return 'Sport';
  return lower
      .split(RegExp(r'[\s_-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
