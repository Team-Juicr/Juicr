class TvPlaybackEpisodeSlot {
  const TvPlaybackEpisodeSlot({required this.season, required this.episode});

  final int season;
  final int episode;

  @override
  bool operator ==(Object other) =>
      other is TvPlaybackEpisodeSlot &&
      other.season == season &&
      other.episode == episode;

  @override
  int get hashCode => Object.hash(season, episode);
}

class TvPlaybackEpisodeAttemptGate {
  int _generation = 0;

  int begin() => ++_generation;

  bool owns(int attempt) => attempt == _generation;

  void cancel(int attempt) {
    if (owns(attempt)) _generation += 1;
  }

  Future<T?> runOwned<T>(
    int attempt,
    Future<T> Function() operation,
  ) async {
    if (!owns(attempt)) return null;
    final result = await operation();
    return owns(attempt) ? result : null;
  }
}

List<int> tvPlaybackSeasons(List<TvPlaybackEpisodeSlot> episodes) {
  final seasons = episodes.map((episode) => episode.season).toSet().toList();
  seasons.sort();
  return seasons;
}

int tvPlaybackInitialSeasonIndex({
  required List<int> seasons,
  required int activeSeason,
}) {
  if (seasons.isEmpty) return 0;
  final activeIndex = seasons.indexOf(activeSeason);
  return activeIndex < 0 ? 0 : activeIndex;
}

List<TvPlaybackEpisodeSlot> tvPlaybackEpisodesForSeason(
  List<TvPlaybackEpisodeSlot> episodes,
  int season,
) {
  final unique = <int, TvPlaybackEpisodeSlot>{};
  for (final episode in episodes) {
    if (episode.season == season) unique[episode.episode] = episode;
  }
  final result = unique.values.toList();
  result.sort((a, b) => a.episode.compareTo(b.episode));
  return result;
}

int tvPlaybackInitialEpisodeIndex({
  required List<TvPlaybackEpisodeSlot> episodes,
  required int activeSeason,
  required int activeEpisode,
}) {
  if (episodes.isEmpty) return 0;
  final activeIndex = episodes.indexWhere(
    (episode) =>
        episode.season == activeSeason && episode.episode == activeEpisode,
  );
  return activeIndex < 0 ? 0 : activeIndex;
}
