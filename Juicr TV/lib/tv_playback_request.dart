enum TvPlaybackRequestKind {
  movie('movie', false),
  tv('tv', true),
  live('live', false);

  const TvPlaybackRequestKind(this.apiValue, this.includesEpisode);

  final String apiValue;
  final bool includesEpisode;
}

TvPlaybackRequestKind tvPlaybackRequestKindForItemType(String itemType) {
  switch (itemType.trim().toLowerCase()) {
    case 'series':
    case 'animation':
      return TvPlaybackRequestKind.tv;
    case 'live':
    case 'live_tv':
    case 'livetv':
    case 'channel':
    case 'channels':
      return TvPlaybackRequestKind.live;
    default:
      return TvPlaybackRequestKind.movie;
  }
}
