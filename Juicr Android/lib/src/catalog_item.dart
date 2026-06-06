enum MediaType { movie, series, animation, liveTv, music, nsfw }

extension MediaTypeInfo on MediaType {
  String get compatTypeValue {
    return switch (this) {
      MediaType.movie => 'movie',
      MediaType.series => 'series',
      MediaType.animation => 'animation',
      MediaType.liveTv => 'tv',
      MediaType.music => 'music',
      MediaType.nsfw => 'nsfw',
    };
  }

  Set<String> get compatTypeAliases {
    return switch (this) {
      MediaType.movie => const {'movie'},
      MediaType.series => const {'series'},
      MediaType.animation => const {'animation'},
      MediaType.liveTv => const {'tv', 'channel', 'live', 'livetv', 'live_tv'},
      MediaType.music => const {'music', 'audio', 'track'},
      MediaType.nsfw => const {'nsfw', 'adult', 'xxx', 'porn'},
    };
  }

  bool matchesCompatType(String rawType) {
    final normalized = rawType.trim().toLowerCase();
    return compatTypeAliases.contains(normalized);
  }

  String get label {
    return switch (this) {
      MediaType.movie => 'Movie',
      MediaType.series => 'Series',
      MediaType.animation => 'Animation',
      MediaType.liveTv => 'Live TV',
      MediaType.music => 'Music',
      MediaType.nsfw => 'NSFW',
    };
  }

  String get pluralLabel {
    return switch (this) {
      MediaType.movie => 'Movies',
      MediaType.series => 'Series',
      MediaType.animation => 'Animation',
      MediaType.liveTv => 'Live TV',
      MediaType.music => 'Music',
      MediaType.nsfw => 'NSFW',
    };
  }

  bool get isPlayableSeries =>
      this == MediaType.series || this == MediaType.animation;
  bool get isLive => this == MediaType.liveTv;
}

enum CatalogSort {
  top,
  topRated,
  newest,
  oldest,
  alphaAsc,
  alphaDesc,
  nowPlaying,
  airingToday,
  onTv,
  year,
  upcoming,
  imdbRating,
  hiddenGems,
}

extension CatalogSortInfo on CatalogSort {
  String get id {
    return switch (this) {
      CatalogSort.top => 'top',
      CatalogSort.topRated => 'topRated',
      CatalogSort.newest => 'newest',
      CatalogSort.oldest => 'oldest',
      CatalogSort.alphaAsc => 'alphaAsc',
      CatalogSort.alphaDesc => 'alphaDesc',
      CatalogSort.nowPlaying => 'nowPlaying',
      CatalogSort.airingToday => 'airingToday',
      CatalogSort.onTv => 'onTv',
      CatalogSort.year => 'year',
      CatalogSort.upcoming => 'upcoming',
      CatalogSort.imdbRating => 'imdbRating',
      CatalogSort.hiddenGems => 'hiddenGems',
    };
  }

  String get label {
    return switch (this) {
      CatalogSort.top => 'Popular',
      CatalogSort.topRated => 'Top Rated',
      CatalogSort.newest => 'Newest',
      CatalogSort.oldest => 'Oldest',
      CatalogSort.alphaAsc => 'A-Z',
      CatalogSort.alphaDesc => 'Z-A',
      CatalogSort.nowPlaying => 'Now Playing',
      CatalogSort.airingToday => 'Airing Today',
      CatalogSort.onTv => 'On TV',
      CatalogSort.year => 'By Year',
      CatalogSort.upcoming => 'Upcoming',
      CatalogSort.imdbRating => 'Featured',
      CatalogSort.hiddenGems => 'Hidden Gems',
    };
  }
}

class CatalogItem {
  const CatalogItem({
    required this.type,
    required this.id,
    required this.name,
    this.poster,
    this.background,
    this.logo,
    this.year,
    this.releaseDate,
    this.tmdbId,
    this.imdbId,
    this.genres = const [],
    this.description,
    this.imdbRating,
    this.voteCount,
    this.adult = false,
    this.isUpcoming = false,
    this.isLocalCatalogItem = false,
    this.localPlaybackLocked = false,
    this.localCatalogId,
    this.localCatalogItemId,
    this.localCatalogName,
    this.localMediaKind,
    this.localSourceLabel,
    this.localRelinkNeededCount,
    this.personalServerTypeId,
    this.personalServerItemId,
    this.personalServerSeriesItemId,
  });

  final MediaType type;
  final String id;
  final String name;
  final String? poster;
  final String? background;
  final String? logo;
  final String? year;
  final String? releaseDate;
  final int? tmdbId;
  final String? imdbId;
  final List<String> genres;
  final String? description;
  final String? imdbRating;
  final int? voteCount;
  final bool adult;
  final bool isUpcoming;
  final bool isLocalCatalogItem;
  final bool localPlaybackLocked;
  final String? localCatalogId;
  final String? localCatalogItemId;
  final String? localCatalogName;
  final String? localMediaKind;
  final String? localSourceLabel;
  final int? localRelinkNeededCount;
  final String? personalServerTypeId;
  final String? personalServerItemId;
  final String? personalServerSeriesItemId;

  bool get isPersonalServerItem =>
      personalServerTypeId != null &&
      personalServerTypeId!.trim().isNotEmpty &&
      personalServerItemId != null &&
      personalServerItemId!.trim().isNotEmpty;

  bool get isTmdbBackedItem => tmdbId != null || id.startsWith('tmdb:');

  bool get hasMatureContentSignal {
    if (adult || type == MediaType.nsfw) return true;
    final text = [
      name,
      if (description != null) description!,
      ...genres,
    ].join(' ').toLowerCase();
    if (text.trim().isEmpty) return false;
    return RegExp(
          r'\b(adult|nsfw|xxx|porn|pornography|erotic|explicit|softcore|sexploitation|sexuality|sexual|sex|nudity|nude|naked|striptease|hentai|seduction|seduce|lust|desire|affair|mistress|virgin|scandal)\b',
        ).hasMatch(text) ||
        RegExp(r'\b(vivamax|viva\s*max)\b').hasMatch(text) ||
        RegExp(r'\bfifty\s+shades\b').hasMatch(text) ||
        RegExp(r'\b365\s+days\b').hasMatch(text);
  }

  String get subtitle {
    final parts = <String>[
      if (year != null && year!.isNotEmpty) year!,
      if (imdbRating != null && imdbRating!.isNotEmpty) 'IMDb $imdbRating',
      if (genres.isNotEmpty) genres.take(2).join(', '),
    ];
    return parts.join(' - ');
  }

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? 'movie').toString().trim().toLowerCase();
    return CatalogItem(
      type: switch (rawType) {
        'series' => MediaType.series,
        'tv' ||
        'channel' ||
        'live' ||
        'live_tv' ||
        'live-tv' ||
        'livetv' => MediaType.liveTv,
        'music' || 'audio' || 'track' => MediaType.music,
        'nsfw' || 'adult' || 'xxx' || 'porn' => MediaType.nsfw,
        'animation' => MediaType.animation,
        _ => MediaType.movie,
      },
      id: (json['id'] ?? '').toString(),
      name: _cleanTitle(
        (json['name'] ?? json['title'] ?? 'Untitled').toString(),
      ),
      poster: json['poster']?.toString(),
      background: json['background']?.toString(),
      logo: json['logo']?.toString(),
      year: _yearFromJson(json),
      releaseDate: _releaseDateFromJson(json),
      tmdbId: int.tryParse(
        (json['moviedb_id'] ?? json['tmdb_id'] ?? json['tmdbId'] ?? '')
            .toString(),
      ),
      imdbId: _imdbIdFromJson(json),
      genres: _stringList(json['genres']),
      description: (json['description'] ?? json['overview'])?.toString(),
      imdbRating: (json['imdbRating'] ?? json['rating'])?.toString(),
      voteCount: int.tryParse(
        (json['voteCount'] ?? json['vote_count'] ?? json['votes'] ?? '')
            .toString(),
      ),
      adult:
          json['adult'] == true ||
          json['isAdult'] == true ||
          json['nsfw'] == true,
      isUpcoming:
          json['isUpcoming'] == true ||
          json['releaseStatus']?.toString().toLowerCase() == 'upcoming',
      isLocalCatalogItem: json['isLocalCatalogItem'] == true,
      localPlaybackLocked: json['localPlaybackLocked'] == true,
      localCatalogId: json['localCatalogId']?.toString(),
      localCatalogItemId: json['localCatalogItemId']?.toString(),
      localCatalogName: json['localCatalogName']?.toString(),
      localMediaKind: json['localMediaKind']?.toString(),
      localSourceLabel: json['localSourceLabel']?.toString(),
      localRelinkNeededCount: int.tryParse(
        (json['localRelinkNeededCount'] ?? '').toString(),
      ),
      personalServerTypeId: json['personalServerTypeId']?.toString(),
      personalServerItemId: json['personalServerItemId']?.toString(),
      personalServerSeriesItemId: json['personalServerSeriesItemId']
          ?.toString(),
    );
  }

  CatalogItem merge(CatalogItem other) {
    return CatalogItem(
      type: other.type,
      id: other.id,
      name: other.name,
      poster: other.poster ?? poster,
      background: other.background ?? background,
      logo: other.logo ?? logo,
      year: other.year ?? year,
      releaseDate: other.releaseDate ?? releaseDate,
      tmdbId: other.tmdbId ?? tmdbId,
      imdbId: other.imdbId ?? imdbId,
      genres: other.genres.isNotEmpty ? other.genres : genres,
      description: other.description ?? description,
      imdbRating: other.imdbRating ?? imdbRating,
      voteCount: other.voteCount ?? voteCount,
      adult: other.adult || adult,
      isUpcoming: other.isUpcoming || isUpcoming,
      isLocalCatalogItem: other.isLocalCatalogItem || isLocalCatalogItem,
      localPlaybackLocked: other.localPlaybackLocked || localPlaybackLocked,
      localCatalogId: other.localCatalogId ?? localCatalogId,
      localCatalogItemId: other.localCatalogItemId ?? localCatalogItemId,
      localCatalogName: other.localCatalogName ?? localCatalogName,
      localMediaKind: other.localMediaKind ?? localMediaKind,
      localSourceLabel: other.localSourceLabel ?? localSourceLabel,
      localRelinkNeededCount:
          other.localRelinkNeededCount ?? localRelinkNeededCount,
      personalServerTypeId: other.personalServerTypeId ?? personalServerTypeId,
      personalServerItemId: other.personalServerItemId ?? personalServerItemId,
      personalServerSeriesItemId:
          other.personalServerSeriesItemId ?? personalServerSeriesItemId,
    );
  }

  CatalogItem withType(MediaType nextType) {
    return CatalogItem(
      type: nextType,
      id: id,
      name: name,
      poster: poster,
      background: background,
      logo: logo,
      year: year,
      releaseDate: releaseDate,
      tmdbId: tmdbId,
      imdbId: imdbId,
      genres: genres,
      description: description,
      imdbRating: imdbRating,
      voteCount: voteCount,
      adult: adult,
      isUpcoming: isUpcoming,
      isLocalCatalogItem: isLocalCatalogItem,
      localPlaybackLocked: localPlaybackLocked,
      localCatalogId: localCatalogId,
      localCatalogItemId: localCatalogItemId,
      localCatalogName: localCatalogName,
      localMediaKind: localMediaKind,
      localSourceLabel: localSourceLabel,
      localRelinkNeededCount: localRelinkNeededCount,
      personalServerTypeId: personalServerTypeId,
      personalServerItemId: personalServerItemId,
      personalServerSeriesItemId: personalServerSeriesItemId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.compatTypeValue,
      'id': id,
      'name': name,
      'poster': poster,
      'background': background,
      'logo': logo,
      'year': year,
      'releaseDate': releaseDate,
      'tmdb_id': tmdbId,
      'imdb_id': imdbId,
      'genres': genres,
      'description': description,
      'imdbRating': imdbRating,
      'voteCount': voteCount,
      'adult': adult,
      'isUpcoming': isUpcoming,
      'isLocalCatalogItem': isLocalCatalogItem,
      'localPlaybackLocked': localPlaybackLocked,
      'localCatalogId': localCatalogId,
      'localCatalogItemId': localCatalogItemId,
      'localCatalogName': localCatalogName,
      'localMediaKind': localMediaKind,
      'localSourceLabel': localSourceLabel,
      'localRelinkNeededCount': localRelinkNeededCount,
      'personalServerTypeId': personalServerTypeId,
      'personalServerItemId': personalServerItemId,
      'personalServerSeriesItemId': personalServerSeriesItemId,
    };
  }
}

class EpisodeItem {
  const EpisodeItem({
    required this.id,
    required this.title,
    required this.season,
    required this.episode,
    this.thumbnail,
    this.released,
    this.description,
  });

  final String id;
  final String title;
  final int season;
  final int episode;
  final String? thumbnail;
  final String? released;
  final String? description;

  factory EpisodeItem.fromJson(Map<String, dynamic> json) {
    final fullId = (json['id'] ?? '').toString().split(':');
    final season =
        int.tryParse(json['season']?.toString() ?? '') ??
        (fullId.length > 1 ? int.tryParse(fullId[1]) : null) ??
        1;
    final episode =
        int.tryParse(json['episode']?.toString() ?? '') ??
        (fullId.length > 2 ? int.tryParse(fullId[2]) : null) ??
        1;

    return EpisodeItem(
      id: (json['id'] ?? '').toString(),
      title: _episodeTitleFromJson(json, episode),
      season: season,
      episode: episode,
      thumbnail: json['thumbnail']?.toString(),
      released: json['released']?.toString(),
      description: (json['description'] ?? json['overview'])?.toString(),
    );
  }
}

String _episodeTitleFromJson(Map<String, dynamic> json, int episode) {
  final rawTitle = _cleanTitle((json['title'] ?? '').toString()).trim();
  final rawName = _cleanTitle((json['name'] ?? '').toString()).trim();
  final fallback = 'Episode $episode';

  final genericPattern = RegExp(r'^episode\s+\d+$', caseSensitive: false);
  final titleIsGeneric = rawTitle.isEmpty || genericPattern.hasMatch(rawTitle);

  if (rawName.isNotEmpty &&
      (titleIsGeneric || rawName.toLowerCase() != rawTitle.toLowerCase())) {
    return rawName;
  }
  if (rawTitle.isNotEmpty) {
    return rawTitle;
  }
  return fallback;
}

String _cleanTitle(String value) {
  return value
      .replaceAll(RegExp(r'#\s*dupe\s*#', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class MetaDetails {
  const MetaDetails({
    required this.item,
    this.runtime,
    this.director = const [],
    this.cast = const [],
    this.directorPeople = const [],
    this.castPeople = const [],
    this.videos = const [],
  });

  final CatalogItem item;
  final String? runtime;
  final List<String> director;
  final List<String> cast;
  final List<PersonCredit> directorPeople;
  final List<PersonCredit> castPeople;
  final List<EpisodeItem> videos;

  factory MetaDetails.fromJson(Map<String, dynamic> json) {
    final meta = json['item'] ?? json['meta'];
    if (meta is! Map<String, dynamic>) {
      throw const FormatException('Missing title metadata.');
    }

    final rawVideos = meta['videos'];
    return MetaDetails(
      item: CatalogItem.fromJson(meta),
      runtime: meta['runtime']?.toString(),
      director: _stringList(meta['director']),
      cast: _stringList(meta['cast']),
      directorPeople: _personCredits(meta['director']),
      castPeople: _personCredits(meta['cast']),
      videos: rawVideos is List
          ? rawVideos
                .whereType<Map<String, dynamic>>()
                .map(EpisodeItem.fromJson)
                .toList()
          : const [],
    );
  }
}

class PersonCredit {
  const PersonCredit({required this.name, this.image});

  final String name;
  final String? image;

  factory PersonCredit.fromJson(dynamic value) {
    if (value is Map<String, dynamic>) {
      return PersonCredit(
        name: (value['name'] ?? '').toString().trim(),
        image: (value['image'] ?? value['profile'] ?? value['profileUrl'])
            ?.toString()
            .trim(),
      );
    }
    return PersonCredit(name: value.toString().trim());
  }
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) {
        if (item is Map<String, dynamic>) {
          return (item['name'] ?? '').toString();
        }
        return item.toString();
      })
      .where((item) => item.isNotEmpty)
      .toList();
}

List<PersonCredit> _personCredits(dynamic value) {
  if (value is! List) return const [];
  return value
      .map(PersonCredit.fromJson)
      .where((person) => person.name.isNotEmpty)
      .toList();
}

String? _yearFromJson(Map<String, dynamic> json) {
  final raw =
      json['year'] ??
      json['releaseInfo'] ??
      json['releaseDate'] ??
      json['release_date'] ??
      json['released'] ??
      json['premiered'] ??
      json['firstAirDate'] ??
      json['first_air_date'];
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) return null;
  final match = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(value);
  return match?.group(1) ?? value;
}

String? _releaseDateFromJson(Map<String, dynamic> json) {
  final raw =
      json['releaseDate'] ??
      json['release_date'] ??
      json['released'] ??
      json['premiered'] ??
      json['firstAirDate'] ??
      json['first_air_date'];
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) return null;
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ? value : null;
}

String? _imdbIdFromJson(Map<String, dynamic> json) {
  final externalIds = json['external_ids'] ?? json['externalIds'];
  final candidates = <dynamic>[
    json['imdb_id'],
    json['imdbId'],
    json['imdb'],
    if (externalIds is Map) externalIds['imdb_id'],
    if (externalIds is Map) externalIds['imdbId'],
    json['id'],
  ];
  for (final candidate in candidates) {
    final value = candidate?.toString().trim();
    if (value == null || value.isEmpty) continue;
    if (RegExp(r'^tt\d{5,12}$', caseSensitive: false).hasMatch(value)) {
      return value;
    }
  }
  return null;
}
