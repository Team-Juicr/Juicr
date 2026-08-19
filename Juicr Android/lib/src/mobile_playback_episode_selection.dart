import 'mobile_playback_route_startup.dart';
import 'playback_request_transport.dart';

class MobilePlaybackEpisodeSlot {
  const MobilePlaybackEpisodeSlot({
    required this.season,
    required this.episode,
  });

  final int season;
  final int episode;

  @override
  bool operator ==(Object other) =>
      other is MobilePlaybackEpisodeSlot &&
      other.season == season &&
      other.episode == episode;

  @override
  int get hashCode => Object.hash(season, episode);
}

enum MobileEpisodePickerStage { seasons, done }

MobileEpisodePickerStage mobileEpisodePickerStageAfterChildResult({
  required bool hasSelection,
}) =>
    hasSelection
        ? MobileEpisodePickerStage.done
        : MobileEpisodePickerStage.seasons;

class MobileEpisodeTransitionResolver {
  MobileEpisodeTransitionResolver({
    MobilePlaybackRouteStartupOwner Function(int generation)? ownerFactory,
  }) : _ownerFactory = ownerFactory ?? _defaultOwnerFactory;

  final MobilePlaybackRouteStartupOwner Function(int generation) _ownerFactory;
  MobilePlaybackRouteStartupOwner? _owner;
  int _generation = 0;

  static MobilePlaybackRouteStartupOwner _defaultOwnerFactory(int generation) {
    return MobilePlaybackRouteStartupOwner(
      generation: generation,
      startedAt: DateTime.now(),
    );
  }

  Future<T> resolve<T>(
    Future<T> Function(PlaybackRequestCancellation cancellation) operation,
  ) async {
    _owner?.dispose();
    final owner = _ownerFactory(++_generation);
    _owner = owner;
    try {
      final result = await owner.runWork<T>(operation);
      owner.completeSuccessfully();
      return result;
    } finally {
      if (identical(_owner, owner)) _owner = null;
      owner.dispose();
    }
  }

  void dispose() {
    _owner?.dispose();
    _owner = null;
  }
}

List<int> mobilePlaybackSeasons(
  Iterable<MobilePlaybackEpisodeSlot> episodes,
) {
  final seasons = episodes.map((episode) => episode.season).toSet().toList()
    ..sort();
  return seasons;
}

List<MobilePlaybackEpisodeSlot> mobilePlaybackEpisodesForSeason(
  Iterable<MobilePlaybackEpisodeSlot> episodes,
  int season,
) {
  final unique = <int, MobilePlaybackEpisodeSlot>{};
  for (final episode in episodes) {
    if (episode.season == season) unique[episode.episode] = episode;
  }
  return unique.values.toList()
    ..sort((left, right) => left.episode.compareTo(right.episode));
}
