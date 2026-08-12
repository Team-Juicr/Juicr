class DetailsTitleHydrationOwnership {
  DetailsTitleHydrationOwnership({required String titleIdentity})
      : _titleIdentity = titleIdentity;

  String _titleIdentity;
  int _generation = 0;
  bool _disposed = false;

  String get titleIdentity => _titleIdentity;
  int get generation => _generation;

  int resetForTitle(String titleIdentity) {
    if (_disposed) return _generation;
    _titleIdentity = titleIdentity;
    _generation += 1;
    return _generation;
  }

  bool accepts(String titleIdentity, int generation) {
    return !_disposed &&
        titleIdentity == _titleIdentity &&
        generation == _generation;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
  }
}

class DetailsSeasonOwnership {
  DetailsSeasonOwnership({
    required String titleIdentity,
    required List<int> availableSeasons,
    int? canonicalResumeSeason,
  })  : _titleIdentity = titleIdentity,
        _selectedSeason = _initialSeason(
          availableSeasons,
          canonicalResumeSeason,
        );

  String _titleIdentity;
  int _selectedSeason;
  bool _hasExplicitSelection = false;
  bool _disposed = false;
  int _generation = 0;

  String get titleIdentity => _titleIdentity;
  int get selectedSeason => _selectedSeason;
  bool get hasExplicitSelection => _hasExplicitSelection;
  int get generation => _generation;

  void selectSeason(int season) {
    if (_disposed || season < 1) return;
    _selectedSeason = season;
    _hasExplicitSelection = true;
    _generation += 1;
  }

  bool applyAsyncSeasons({
    required String titleIdentity,
    required int generation,
    required List<int> availableSeasons,
    int? canonicalResumeSeason,
  }) {
    if (_disposed ||
        titleIdentity != _titleIdentity ||
        generation != _generation) {
      return false;
    }
    if (!_hasExplicitSelection) {
      _selectedSeason = _initialSeason(
        availableSeasons,
        canonicalResumeSeason,
      );
    }
    return true;
  }

  void resetForTitle({
    required String titleIdentity,
    required List<int> availableSeasons,
    int? canonicalResumeSeason,
  }) {
    if (_disposed) return;
    _titleIdentity = titleIdentity;
    _selectedSeason = _initialSeason(
      availableSeasons,
      canonicalResumeSeason,
    );
    _hasExplicitSelection = false;
    _generation += 1;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
  }

  static int _initialSeason(
    List<int> availableSeasons,
    int? canonicalResumeSeason,
  ) {
    final seasons =
        availableSeasons.where((season) => season > 0).toSet().toList()..sort();
    if (canonicalResumeSeason != null &&
        seasons.contains(canonicalResumeSeason)) {
      return canonicalResumeSeason;
    }
    return seasons.isEmpty ? 1 : seasons.first;
  }
}
