part of 'main.dart';

class _TvApi {
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);

  List<String>? _providerIds;

  static const juicrClientHeaders = <String, String>{
    'accept': 'application/json',
    'user-agent': 'JuicrTV/0.1 AndroidTV',
    'x-juicr-client': 'tv',
    'x-juicr-client-version': '0.1',
  };

  static const juicrMediaHeaders = <String, String>{
    'accept': 'application/vnd.apple.mpegurl, application/x-mpegURL, video/*, */*',
    'user-agent': 'JuicrTV/0.1 AndroidTV',
    'x-juicr-client': 'tv',
    'x-juicr-client-version': '0.1',
  };

  Future<List<_TvItem>> catalog({
    required String type,
    required String sort,
  }) async {
    final uri = Uri.parse('$_apiBase/catalog').replace(
      queryParameters: {
        'type': type,
        'sort': sort,
        'page': '1',
      },
    );
    final json = await _getJson(uri);
    final rawItems = json['items'] ?? json['metas'];
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map>()
        .map((raw) => _TvItem.fromJson(Map<String, dynamic>.from(raw), fallbackType: type))
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList();
  }

  Future<_TvHomeEditorialEdition?> homeEditorial() async {
    try {
      final uri = Uri.parse('$_apiBase/home/editorial').replace(
        queryParameters: const {'locale': 'en'},
      );
      final json = await _getJson(uri).timeout(const Duration(seconds: 4));
      final editorialJson = _homeEditorialPayload(json);
      if (editorialJson == null) return null;
      return _TvHomeEditorialEdition.fromJson(editorialJson);
    } catch (error) {
      debugPrint(
        'Juicr TV home editorial direct fallback '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      try {
        final uri = Uri.parse('$_apiBase/config').replace(
          queryParameters: const {'locale': 'en'},
        );
        final json = await _getJson(uri).timeout(const Duration(seconds: 5));
        final editorialJson = _homeEditorialPayload(json);
        if (editorialJson == null) return null;
        return _TvHomeEditorialEdition.fromJson(editorialJson);
      } catch (configError) {
        debugPrint(
          'Juicr TV home editorial fallback '
          'bucket=${_apiErrorBucket(configError)} errorType=${configError.runtimeType}',
        );
        return null;
      }
    }
  }

  Future<_TvItem> meta(_TvItem item) async {
    final uri = Uri.parse('$_apiBase/meta').replace(
      queryParameters: {'type': item.type == 'animation' ? 'series' : item.type, 'id': item.id},
    );
    final json = await _getJson(uri);
    final meta = json['item'] ?? json['meta'];
    if (meta is! Map) return item;
    return item.merge(
      _TvItem.fromJson(Map<String, dynamic>.from(meta), fallbackType: item.type),
    );
  }

  Future<List<_TvTrailer>> trailers(_TvItem item) async {
    final type = item.type == 'movie' ? 'movie' : 'tv';
    final id = item.tmdbId?.toString().isNotEmpty == true ? item.tmdbId.toString() : item.id;
    final uri = Uri.parse('$_apiBase/trailers/$type').replace(
      queryParameters: {
        'id': id,
        'imdbId': item.id,
        if (item.tmdbId != null) 'tmdbId': item.tmdbId.toString(),
        'language': 'en-US',
      },
    );
    final json = await _getJson(uri).timeout(const Duration(seconds: 10));
    final rawTrailers = json['trailers'] ?? json['items'];
    if (rawTrailers is! List) return const <_TvTrailer>[];
    final trailers = rawTrailers
        .whereType<Map>()
        .map((raw) => _TvTrailer.fromJson(Map<String, dynamic>.from(raw)))
        .where((trailer) => trailer.url.isNotEmpty)
        .toList();
    trailers.sort((left, right) => right.score.compareTo(left.score));
    return trailers;
  }

  Future<List<_TvSubtitle>> subtitles(
    _TvItem item, {
    int season = 1,
    int episode = 1,
  }) async {
    final seriesLike = item.type == 'series' || item.type == 'animation';
    final path = seriesLike ? 'tv' : 'movie';
    final id = item.tmdbId?.toString().isNotEmpty == true ? item.tmdbId.toString() : item.id;
    final uri = Uri.parse('$_apiBase/subtitles/$path').replace(
      queryParameters: {
        'id': id,
        'imdbId': item.id,
        if (item.tmdbId != null) 'tmdbId': item.tmdbId.toString(),
        if (seriesLike) 'season': season.toString(),
        if (seriesLike) 'episode': episode.toString(),
        'languages': 'en',
      },
    );
    final json = await _getJson(uri).timeout(const Duration(seconds: 8));
    final rawSubtitles = json['subtitles'] ?? json['items'];
    if (rawSubtitles is! List) return const <_TvSubtitle>[];
    final seen = <String>{};
    return [
      for (final raw in rawSubtitles.whereType<Map>())
        _TvSubtitle.fromJson(Map<String, dynamic>.from(raw)),
    ].where((subtitle) {
      if (subtitle.url.isEmpty || !subtitle.url.startsWith('https://')) return false;
      return seen.add('${subtitle.language}|${subtitle.label}|${subtitle.url}');
    }).toList(growable: false);
  }

  Future<String> subtitleText(_TvSubtitle subtitle) async {
    final request = await _client.getUrl(Uri.parse(subtitle.url));
    _applyJuicrHeaders(request);
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _TvApiException('subtitle_unavailable');
    }
    return response.transform(utf8.decoder).join();
  }

  Future<List<_PlaybackSession>> playbackSessions(
    _TvItem item, {
    int season = 1,
    int episode = 1,
    bool allowWebFallback = true,
  }) async {
    final sessions = <_PlaybackSession>[];
    try {
      sessions.addAll(
        await _nativePlaybackSessions(item, season: season, episode: episode),
      );
    } catch (error) {
      debugPrint(
        'Juicr TV native playback resolve skipped '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
    }
    if (sessions.isNotEmpty) {
      return sessions;
    }
    if (!allowWebFallback) {
      throw const _TvApiException('native_playback_unavailable');
    }
    sessions.add(await _webPlaybackSession(item, season: season, episode: episode));
    if (sessions.isEmpty) {
      throw const _TvApiException('no_tv_safe_source');
    }
    return sessions;
  }

  Future<List<_PlaybackSession>> _nativePlaybackSessions(
    _TvItem item, {
    required int season,
    required int episode,
  }) async {
    final type = item.type == 'series' || item.type == 'animation' ? 'tv' : 'movie';
    final id = item.tmdbId?.toString().isNotEmpty == true ? item.tmdbId.toString() : item.id;
    final endpoint = type == 'tv' ? 'resolve/tv' : 'resolve/movie';
    final sessions = <_PlaybackSession>[];
    final providers = _prioritizedProviders(await _providers());
    var checked = 0;
    for (final providerId in providers) {
      if (checked >= 10) break;
      if (sessions.length >= 4) break;
      checked++;
      final uri = Uri.parse('$_apiBase/$endpoint').replace(
        queryParameters: <String, String>{
          'id': id,
          'provider': providerId,
          'title': item.title,
          if (item.year != null && item.year!.isNotEmpty) 'year': item.year!,
          if (type == 'tv') 'season': season.toString(),
          if (type == 'tv') 'episode': episode.toString(),
        },
      );
      try {
        final json = await _getJson(uri).timeout(const Duration(seconds: 7));
        final found = _sessionsFromSources(json['sources']);
        sessions.addAll(found);
        if (found.isNotEmpty && (sessions.length >= 2 || checked >= 3)) break;
      } catch (error) {
        debugPrint(
          'Juicr TV provider candidate skipped '
          'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
        );
        if (_apiErrorBucket(error) == 'resolver_temporarily_limited' && sessions.isNotEmpty) {
          break;
        }
      }
    }
    return sessions;
  }

  List<String> _prioritizedProviders(List<String> configured) {
    const preferred = <String>[
      'cinesu',
      'popr',
      'vixsrc',
      'vidlink',
      'vidsrc',
      'hydrahd',
      'moviesapi',
      'vidking',
      'vidrock',
      'vidzee',
      'flixer',
      '7xstream',
      'icefy',
      'vidnest',
      'xpass',
      'rgshows',
    ];
    final seen = <String>{};
    final ordered = <String>[];
    void add(String value) {
      final id = value.trim();
      if (id.isEmpty) return;
      if (seen.add(id.toLowerCase())) ordered.add(id);
    }

    for (final provider in preferred) {
      add(provider);
    }
    for (final provider in configured) {
      add(provider);
    }
    return ordered;
  }

  Future<List<String>> _providers() async {
    final cached = _providerIds;
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final json = await _getJson(Uri.parse('$_apiBase/config')).timeout(
        const Duration(seconds: 8),
      );
      final providers = json['providers'];
      if (providers is List) {
        final ids = providers
            .whereType<Map>()
            .map((raw) => (raw['id'] ?? raw['providerId'] ?? raw['key'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty)
            .toList(growable: false);
        if (ids.isNotEmpty) {
          _providerIds = ids;
          return ids;
        }
      }
    } catch (error) {
      debugPrint(
        'Juicr TV provider config fallback '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
    }
    const fallback = <String>[
      'vidlink',
      'vidsrc',
      'hydrahd',
      'icefy',
      'vidnest',
      'xpass',
      'moviesapi',
      'vidking',
      'popr',
      'rgshows',
      'vixsrc',
      'vidrock',
      'vidzee',
      'cinesu',
      'flixer',
      '7xstream',
    ];
    _providerIds = fallback;
    return fallback;
  }

  List<_PlaybackSession> _sessionsFromSources(Object? sources) {
    if (sources is! List) return const <_PlaybackSession>[];
    final sessions = <_PlaybackSession>[];
    for (final raw in sources.whereType<Map>()) {
      final source = Map<String, dynamic>.from(raw);
      final url = (source['url'] ?? '').toString().trim();
      if (!url.startsWith('https://')) continue;
      final sourceClass = (source['sourceClass'] ?? '').toString().toLowerCase();
      if (sourceClass.isNotEmpty && sourceClass != 'direct' && sourceClass != 'debrid') continue;
      final sourceType = (source['type'] ?? '').toString();
      final normalizedType = sourceType.toLowerCase();
      if (normalizedType == 'torrent' || normalizedType == 'magnet' || normalizedType == 'p2p') continue;
      final headers = _stringHeaderMap(source['headers']);
      sessions.add(
        _PlaybackSession(
          mediaUrl: url,
          sourceType: sourceType,
          httpHeaders: headers.isEmpty ? juicrMediaHeaders : headers,
        ),
      );
    }
    return sessions;
  }

  Future<_PlaybackSession> _webPlaybackSession(
    _TvItem item, {
    required int season,
    required int episode,
  }) async {
    final type = item.type == 'series' || item.type == 'animation' ? 'tv' : 'movie';
    final body = <String, dynamic>{
      'type': type,
      'id': item.tmdbId?.toString().isNotEmpty == true ? item.tmdbId.toString() : item.id,
      'imdbId': item.id.startsWith('tt') ? item.id : '',
      'tmdbId': item.tmdbId?.toString() ?? '',
      'title': item.title,
      'year': item.year ?? '',
      if (type == 'tv') 'season': season,
      if (type == 'tv') 'episode': episode,
    };
    final json = await _postJson(Uri.parse('$_apiBase/web/playback/session'), body);
    if (json['ok'] != true || json['mediaUrl'] == null || json['rawSourceExposed'] == true) {
      throw _TvApiException((json['status'] ?? json['error'] ?? 'playback_unavailable').toString());
    }
    return _PlaybackSession(
      mediaUrl: json['mediaUrl'].toString(),
      sourceType: (json['sourceType'] ?? '').toString(),
      httpHeaders: juicrMediaHeaders,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final request = await _client.getUrl(uri);
    _applyJuicrHeaders(request);
    final response = await request.close();
    return _decodeJson(response);
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, Map<String, dynamic> body) async {
    final request = await _client.postUrl(uri);
    _applyJuicrHeaders(request);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    return _decodeJson(response);
  }

  void _applyJuicrHeaders(HttpClientRequest request) {
    for (final entry in juicrClientHeaders.entries) {
      request.headers.set(entry.key, entry.value);
    }
  }

  Future<Map<String, dynamic>> _decodeJson(HttpClientResponse response) async {
    final text = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('Unexpected API response.');
    return Map<String, dynamic>.from(decoded);
  }

  static Map<String, String> _stringHeaderMap(Object? value) {
    if (value is! Map) return const <String, String>{};
    final headers = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key?.toString().trim() ?? '';
      final rawValue = entry.value?.toString() ?? '';
      if (key.isNotEmpty && rawValue.isNotEmpty) headers[key] = rawValue;
    }
    return headers;
  }
}

Map<String, dynamic>? _homeEditorialPayload(Map<String, dynamic> json) {
  if (json['ok'] != true) return null;
  final nested = json['homeEditorial'];
  if (nested is Map) return Map<String, dynamic>.from(nested);
  return json;
}

class _TvItem {
  const _TvItem({
    required this.id,
    required this.type,
    required this.title,
    required this.color,
    this.poster,
    this.background,
    this.year,
    this.tmdbId,
    this.genres = const [],
    this.description,
    this.imdbRating,
    this.episodes = const [],
  });

  factory _TvItem.fromJson(Map<String, dynamic> json, {required String fallbackType}) {
    final id = (json['id'] ?? '').toString();
    final title = (json['name'] ?? json['title'] ?? 'Untitled').toString();
    final genres = _stringList(json['genres']);
    return _TvItem(
      id: id,
      type: _normalizeType((json['type'] ?? fallbackType).toString()),
      title: title,
      color: _colorFromText(id.isEmpty ? title : id),
      poster: _image(json['poster'] ?? json['posterUrl'] ?? json['image'] ?? json['thumbnail']),
      background: _image(json['background'] ?? json['backdrop'] ?? json['fanart'] ?? json['landscape']),
      year: _year(json),
      tmdbId: int.tryParse((json['tmdb_id'] ?? json['moviedb_id'] ?? json['tmdbId'] ?? '').toString()),
      genres: genres,
      description: (json['description'] ?? json['overview'])?.toString(),
      imdbRating: (json['imdbRating'] ?? json['rating'])?.toString(),
      episodes: _TvEpisode.fromList(json['videos'] ?? json['episodes']),
    );
  }

  final String id;
  final String type;
  final String title;
  final Color color;
  final String? poster;
  final String? background;
  final String? year;
  final int? tmdbId;
  final List<String> genres;
  final String? description;
  final String? imdbRating;
  final List<_TvEpisode> episodes;

  String get subtitle {
    final parts = [
      if (year != null && year!.isNotEmpty) year!,
      if (imdbRating != null && imdbRating!.isNotEmpty) 'IMDb $imdbRating',
      ...genres.take(2),
    ];
    return parts.join(' - ');
  }

  _TvItem merge(_TvItem other) {
    return _TvItem(
      id: other.id.isNotEmpty ? other.id : id,
      type: other.type,
      title: other.title.isNotEmpty ? other.title : title,
      color: color,
      poster: other.poster ?? poster,
      background: other.background ?? background,
      year: other.year ?? year,
      tmdbId: other.tmdbId ?? tmdbId,
      genres: other.genres.isNotEmpty ? other.genres : genres,
      description: other.description ?? description,
      imdbRating: other.imdbRating ?? imdbRating,
      episodes: other.episodes.isNotEmpty ? other.episodes : episodes,
    );
  }

  _TvItem withType(String nextType) {
    return _TvItem(
      id: id,
      type: nextType,
      title: title,
      color: color,
      poster: poster,
      background: background,
      year: year,
      tmdbId: tmdbId,
      genres: genres,
      description: description,
      imdbRating: imdbRating,
      episodes: episodes,
    );
  }
}

class _TvEpisode {
  const _TvEpisode({
    required this.season,
    required this.episode,
    required this.title,
    required this.description,
    this.thumbnail,
  });

  factory _TvEpisode.fromJson(Map<String, dynamic> json) {
    final fullId = (json['id'] ?? '').toString().split(':');
    final season = int.tryParse(json['season']?.toString() ?? '') ??
        (fullId.length > 1 ? int.tryParse(fullId[1]) : null) ??
        1;
    final episode = int.tryParse(json['episode']?.toString() ?? '') ??
        (fullId.length > 2 ? int.tryParse(fullId[2]) : null) ??
        1;
    final rawTitle = (json['name'] ?? json['title'] ?? '').toString().trim();
    final title = rawTitle.isEmpty ? 'Episode $episode' : rawTitle;
    final rawDescription = (json['description'] ?? json['overview'] ?? '').toString().trim();
    return _TvEpisode(
      season: season,
      episode: episode,
      title: title,
      description: rawDescription.isEmpty ? 'Episode $episode' : rawDescription,
      thumbnail: _image(json['thumbnail'] ?? json['poster'] ?? json['image']),
    );
  }

  final int season;
  final int episode;
  final String title;
  final String description;
  final String? thumbnail;

  static List<_TvEpisode> fromList(Object? value) {
    if (value is! List) return const <_TvEpisode>[];
    final bySlot = <String, _TvEpisode>{};
    for (final raw in value.whereType<Map>()) {
      final episode = _TvEpisode.fromJson(Map<String, dynamic>.from(raw));
      final key = '${episode.season}:${episode.episode}';
      final existing = bySlot[key];
      if (existing == null ||
          episode.description.length + episode.title.length >
              existing.description.length + existing.title.length) {
        bySlot[key] = episode;
      }
    }
    final episodes = bySlot.values.toList()
      ..sort((left, right) {
        final seasonCompare = left.season.compareTo(right.season);
        if (seasonCompare != 0) return seasonCompare;
        return left.episode.compareTo(right.episode);
      });
    return episodes;
  }
}

class _TvTrailer {
  const _TvTrailer({
    required this.title,
    required this.url,
  });

  factory _TvTrailer.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] ?? json['name'] ?? 'Trailer').toString().trim();
    return _TvTrailer(
      title: title.isEmpty ? 'Trailer' : title,
      url: (json['url'] ?? json['externalUrl'] ?? json['href'] ?? '').toString().trim(),
    );
  }

  final String title;
  final String url;

  bool get isTvPlayable {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.contains('youtube.com') || host.contains('youtu.be')) return false;
    final lower = uri.path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.m3u8') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
  }

  String get sourceType {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'hls';
    if (lower.contains('.mpd')) return 'dash';
    return 'video';
  }

  int get score {
    final text = title.toLowerCase();
    var value = 0;
    if (text.contains('official')) value += 6;
    if (text.contains('trailer')) value += 4;
    if (text.contains('teaser')) value += 2;
    return value;
  }
}

class _TvSubtitle {
  const _TvSubtitle({
    required this.id,
    required this.label,
    required this.language,
    required this.url,
    this.format = 'vtt',
    this.isDefault = false,
    this.isForced = false,
  });

  factory _TvSubtitle.fromJson(Map<String, dynamic> json) {
    final language = (json['language'] ?? json['lang'] ?? '').toString().trim();
    final label = (json['label'] ?? json['name'] ?? language).toString().trim();
    return _TvSubtitle(
      id: (json['id'] ?? json['subtitleId'] ?? language.ifEmpty(label)).toString(),
      label: label.isEmpty ? 'Subtitle' : label,
      language: language,
      url: (json['url'] ?? json['src'] ?? '').toString().trim(),
      format: (json['format'] ?? 'vtt').toString().trim(),
      isDefault: json['isDefault'] == true || json['default'] == true,
      isForced: json['isForced'] == true || json['forced'] == true,
    );
  }

  final String id;
  final String label;
  final String language;
  final String url;
  final String format;
  final bool isDefault;
  final bool isForced;
}

class _TvHomeEditorialEdition {
  const _TvHomeEditorialEdition({
    required this.editionId,
    required this.editionDate,
    required this.hero,
    required this.topSignal,
    required this.movie,
    required this.series,
    required this.animation,
    required this.personal,
    required this.history,
    required this.saved,
    required this.privateShelf,
    required this.throwback,
    required this.upcoming,
  });

  factory _TvHomeEditorialEdition.fromJson(Map<String, dynamic> json) {
    final rails = _homeEditorialRailsById(json['rails']);
    return _TvHomeEditorialEdition(
      editionId: (json['editionId'] ?? '').toString(),
      editionDate: (json['editionDate'] ?? '').toString(),
      hero: _TvHomeEditorialRail.fromJson(json['hero']),
      topSignal: _TvHomeEditorialRail.fromJson(rails['topSignal']),
      movie: _TvHomeEditorialRail.fromJson(rails['movieEditorial'] ?? rails['movie']),
      series: _TvHomeEditorialRail.fromJson(rails['seriesEditorial'] ?? rails['series']),
      animation: _TvHomeEditorialRail.fromJson(rails['animationEditorial'] ?? rails['animation']),
      personal: _TvHomeEditorialRail.fromJson(rails['personalEditorial'] ?? rails['personal']),
      history: _TvHomeEditorialRail.fromJson(rails['historyEditorial'] ?? rails['history']),
      saved: _TvHomeEditorialRail.fromJson(rails['savedEditorial'] ?? rails['saved']),
      privateShelf: _TvHomeEditorialRail.fromJson(rails['privateShelfEditorial'] ?? rails['privateShelf']),
      throwback: _TvHomeEditorialRail.fromJson(rails['throwbackEditorial'] ?? rails['throwback']),
      upcoming: _TvHomeEditorialRail.fromJson(rails['upcomingEditorial'] ?? rails['upcoming']),
    );
  }

  final String editionId;
  final String editionDate;
  final _TvHomeEditorialRail hero;
  final _TvHomeEditorialRail topSignal;
  final _TvHomeEditorialRail movie;
  final _TvHomeEditorialRail series;
  final _TvHomeEditorialRail animation;
  final _TvHomeEditorialRail personal;
  final _TvHomeEditorialRail history;
  final _TvHomeEditorialRail saved;
  final _TvHomeEditorialRail privateShelf;
  final _TvHomeEditorialRail throwback;
  final _TvHomeEditorialRail upcoming;
}

class _TvHomeEditorialRail {
  const _TvHomeEditorialRail({
    required this.title,
    required this.subtitle,
    this.id = '',
    this.kind = '',
    this.types = const <String>[],
    this.genres = const <String>[],
    this.sort = 'imdbRating',
    this.perType = 4,
    this.requireGenreMatch = false,
    this.intent = '',
    this.releaseWindow = '',
    this.theme = '',
    this.seasonalWindow = '',
    this.query = '',
  });

  factory _TvHomeEditorialRail.fromJson(dynamic json) {
    if (json is! Map) return empty;
    final raw = Map<String, dynamic>.from(json);
    final route = raw['route'] is Map ? Map<String, dynamic>.from(raw['route'] as Map) : const <String, dynamic>{};
    final title = (raw['title'] ?? '').toString().trim();
    final subtitle = _copyWithoutRepeatedTitlePhrase(title: title, subtitle: (raw['subtitle'] ?? '').toString().trim());
    final routeType = (route['type'] ?? '').toString().trim();
    final routeGenre = (route['genre'] ?? '').toString().trim();
    final types = _stringList(raw['types']);
    final genres = _stringList(raw['genres']);
    return _TvHomeEditorialRail(
      id: (raw['id'] ?? '').toString().trim(),
      kind: (raw['kind'] ?? '').toString().trim(),
      title: title,
      subtitle: subtitle,
      types: (types.isNotEmpty ? types : [if (routeType.isNotEmpty) routeType])
          .map(_normalizeType)
          .where((type) => type == 'movie' || type == 'series' || type == 'animation')
          .toList(growable: false),
      genres: genres.isNotEmpty
          ? genres
          : routeGenre.isNotEmpty && routeGenre.toLowerCase() != 'all genres'
              ? [routeGenre]
              : const <String>[],
      sort: (raw['sort'] ?? route['sort'] ?? 'imdbRating').toString().trim(),
      perType: int.tryParse((raw['perType'] ?? '').toString())?.clamp(1, 12).toInt() ?? 4,
      requireGenreMatch: raw['requireGenreMatch'] == true,
      intent: (raw['intent'] ?? '').toString().trim(),
      releaseWindow: (raw['releaseWindow'] ?? '').toString().trim(),
      theme: (raw['theme'] ?? '').toString().trim(),
      seasonalWindow: (raw['seasonalWindow'] ?? '').toString().trim(),
      query: (raw['query'] ?? route['query'] ?? '').toString().trim(),
    );
  }

  static const empty = _TvHomeEditorialRail(title: '', subtitle: '');

  final String id;
  final String kind;
  final String title;
  final String subtitle;
  final List<String> types;
  final List<String> genres;
  final String sort;
  final int perType;
  final bool requireGenreMatch;
  final String intent;
  final String releaseWindow;
  final String theme;
  final String seasonalWindow;
  final String query;
}

Map<String, dynamic> _homeEditorialRailsById(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is! List) return const <String, dynamic>{};
  final rails = <String, dynamic>{};
  for (final item in value) {
    if (item is! Map) continue;
    final rail = Map<String, dynamic>.from(item);
    final id = (rail['id'] ?? '').toString().trim();
    if (id.isEmpty) continue;
    rails[id] = rail;
  }
  return rails;
}

class _PlaybackSession {
  const _PlaybackSession({
    required this.mediaUrl,
    required this.sourceType,
    required this.httpHeaders,
  });

  final String mediaUrl;
  final String sourceType;
  final Map<String, String> httpHeaders;

  VideoFormat? get videoFormatHint {
    final type = sourceType.toLowerCase();
    if (type == 'hls' || type == 'm3u8') return VideoFormat.hls;
    if (type == 'dash' || type == 'mpd') return VideoFormat.dash;
    if (type == 'ss') return VideoFormat.ss;
    return null;
  }

  String get tvMediaUrl {
    final type = sourceType.toLowerCase();
    if ((type == 'hls' || type == 'm3u8') &&
        mediaUrl.contains('/web/playback/session/') &&
        !mediaUrl.contains('/media.m3u8')) {
      return mediaUrl.replaceFirst('/media', '/media.m3u8');
    }
    return mediaUrl;
  }
}

class _TvApiException implements Exception {
  const _TvApiException(this.status);

  final String status;
}

class _TvNavItem {
  const _TvNavItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum _TvDiscoveryKind { movie, series, animation, liveTv }

extension _TvDiscoveryKindInfo on _TvDiscoveryKind {
  String get label {
    return switch (this) {
      _TvDiscoveryKind.movie => 'Movies',
      _TvDiscoveryKind.series => 'Series',
      _TvDiscoveryKind.animation => 'Animation',
      _TvDiscoveryKind.liveTv => 'Live TV',
    };
  }

  IconData get icon {
    return switch (this) {
      _TvDiscoveryKind.movie => Icons.movie_creation_outlined,
      _TvDiscoveryKind.series => Icons.tv_rounded,
      _TvDiscoveryKind.animation => Icons.auto_awesome_rounded,
      _TvDiscoveryKind.liveTv => Icons.live_tv_rounded,
    };
  }
}

enum _TvDiscoverySort { popular, newest, featured }

extension _TvDiscoverySortInfo on _TvDiscoverySort {
  String get label {
    return switch (this) {
      _TvDiscoverySort.popular => 'Popular',
      _TvDiscoverySort.newest => 'New',
      _TvDiscoverySort.featured => 'Featured',
    };
  }

  String get subtitle {
    return switch (this) {
      _TvDiscoverySort.popular => 'Popular in all genres',
      _TvDiscoverySort.newest => 'New in all genres',
      _TvDiscoverySort.featured => 'Featured in all genres',
    };
  }
}

class _TvDiscoverySelection {
  const _TvDiscoverySelection(this.kind, this.sort, this.genre);

  final _TvDiscoveryKind kind;
  final _TvDiscoverySort sort;
  final String genre;
}

class _TvPlaybackProgress {
  const _TvPlaybackProgress({
    required this.position,
    required this.duration,
  });

  final Duration position;
  final Duration duration;
}

class _TvRail {
  const _TvRail(this.title, this.subtitle, this.items);

  final String title;
  final String subtitle;
  final List<_TvItem> items;
}

class _TvSetting {
  const _TvSetting(this.title, this.subtitle, this.icon);

  final String title;
  final String subtitle;
  final IconData icon;
}

class _TvSettingsState {
  const _TvSettingsState({
    this.theme = 'System',
    this.accent = 'Juicr Green',
    this.textSize = 'Large',
    this.motion = true,
    this.playbackEngine = 'Auto',
    this.preferredQuality = 'Balanced',
    this.resumePrompt = true,
    this.subtitles = false,
    this.nextEpisode = true,
    this.defaultSourceConsentAccepted = false,
    this.showDefaultSourceSettings = false,
    this.addOnConsentAccepted = false,
    this.builtInCatalog = false,
    this.builtInSubtitles = false,
    this.builtInTrailers = false,
    this.builtInLiveTv = false,
    this.builtInPlayback = false,
    this.advancedControls = false,
    this.history = true,
    this.safeDiagnostics = true,
    this.userAddOns = const <_TvUserAddOn>[],
  });

  final String theme;
  final String accent;
  final String textSize;
  final bool motion;
  final String playbackEngine;
  final String preferredQuality;
  final bool resumePrompt;
  final bool subtitles;
  final bool nextEpisode;
  final bool defaultSourceConsentAccepted;
  final bool showDefaultSourceSettings;
  final bool addOnConsentAccepted;
  final bool builtInCatalog;
  final bool builtInSubtitles;
  final bool builtInTrailers;
  final bool builtInLiveTv;
  final bool builtInPlayback;
  final bool advancedControls;
  final bool history;
  final bool safeDiagnostics;
  final List<_TvUserAddOn> userAddOns;

  bool get hasUserAddOns => userAddOns.any((addon) => addon.enabled);
  bool get hasCatalogSource => builtInCatalog || builtInLiveTv || hasUserAddOns;
  bool get hasPlaybackSource => builtInPlayback || hasUserAddOns;
  bool get keepHistory => history;

  factory _TvSettingsState.fromJson(Map<String, dynamic> json) {
    return _TvSettingsState(
      theme: (json['theme'] ?? 'System').toString(),
      accent: (json['accent'] ?? 'Juicr Green').toString(),
      textSize: (json['textSize'] ?? 'Large').toString(),
      motion: json['motion'] != false,
      playbackEngine: (json['playbackEngine'] ?? 'Auto').toString(),
      preferredQuality: (json['preferredQuality'] ?? 'Balanced').toString(),
      resumePrompt: json['resumePrompt'] != false,
      subtitles: json['subtitles'] == true,
      nextEpisode: json['nextEpisode'] != false,
      defaultSourceConsentAccepted: json['defaultSourceConsentAccepted'] == true,
      showDefaultSourceSettings: json['showDefaultSourceSettings'] == true,
      addOnConsentAccepted: json['addOnConsentAccepted'] == true,
      builtInCatalog: json['builtInCatalog'] == true,
      builtInSubtitles: json['builtInSubtitles'] == true,
      builtInTrailers: json['builtInTrailers'] == true,
      builtInLiveTv: json['builtInLiveTv'] == true,
      builtInPlayback: json['builtInPlayback'] == true,
      advancedControls: json['advancedControls'] == true,
      history: json['history'] != false,
      safeDiagnostics: json['safeDiagnostics'] != false,
      userAddOns: _TvUserAddOn.fromList(json['userAddOns']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'accent': accent,
      'textSize': textSize,
      'motion': motion,
      'playbackEngine': playbackEngine,
      'preferredQuality': preferredQuality,
      'resumePrompt': resumePrompt,
      'subtitles': subtitles,
      'nextEpisode': nextEpisode,
      'defaultSourceConsentAccepted': defaultSourceConsentAccepted,
      'showDefaultSourceSettings': showDefaultSourceSettings,
      'addOnConsentAccepted': addOnConsentAccepted,
      'builtInCatalog': builtInCatalog,
      'builtInSubtitles': builtInSubtitles,
      'builtInTrailers': builtInTrailers,
      'builtInLiveTv': builtInLiveTv,
      'builtInPlayback': builtInPlayback,
      'advancedControls': advancedControls,
      'history': history,
      'safeDiagnostics': safeDiagnostics,
      'userAddOns': userAddOns.map((addon) => addon.toJson()).toList(),
    };
  }

  _TvSettingsState copyWith({
    String? theme,
    String? accent,
    String? textSize,
    bool? motion,
    String? playbackEngine,
    String? preferredQuality,
    bool? resumePrompt,
    bool? subtitles,
    bool? nextEpisode,
    bool? defaultSourceConsentAccepted,
    bool? showDefaultSourceSettings,
    bool? addOnConsentAccepted,
    bool? builtInCatalog,
    bool? builtInSubtitles,
    bool? builtInTrailers,
    bool? builtInLiveTv,
    bool? builtInPlayback,
    bool? advancedControls,
    bool? history,
    bool? safeDiagnostics,
    List<_TvUserAddOn>? userAddOns,
  }) {
    return _TvSettingsState(
      theme: theme ?? this.theme,
      accent: accent ?? this.accent,
      textSize: textSize ?? this.textSize,
      motion: motion ?? this.motion,
      playbackEngine: playbackEngine ?? this.playbackEngine,
      preferredQuality: preferredQuality ?? this.preferredQuality,
      resumePrompt: resumePrompt ?? this.resumePrompt,
      subtitles: subtitles ?? this.subtitles,
      nextEpisode: nextEpisode ?? this.nextEpisode,
      defaultSourceConsentAccepted: defaultSourceConsentAccepted ?? this.defaultSourceConsentAccepted,
      showDefaultSourceSettings: showDefaultSourceSettings ?? this.showDefaultSourceSettings,
      addOnConsentAccepted: addOnConsentAccepted ?? this.addOnConsentAccepted,
      builtInCatalog: builtInCatalog ?? this.builtInCatalog,
      builtInSubtitles: builtInSubtitles ?? this.builtInSubtitles,
      builtInTrailers: builtInTrailers ?? this.builtInTrailers,
      builtInLiveTv: builtInLiveTv ?? this.builtInLiveTv,
      builtInPlayback: builtInPlayback ?? this.builtInPlayback,
      advancedControls: advancedControls ?? this.advancedControls,
      history: history ?? this.history,
      safeDiagnostics: safeDiagnostics ?? this.safeDiagnostics,
      userAddOns: userAddOns ?? this.userAddOns,
    );
  }
}

class _TvUserAddOn {
  const _TvUserAddOn({
    required this.name,
    required this.manifest,
    this.enabled = true,
  });

  final String name;
  final String manifest;
  final bool enabled;

  factory _TvUserAddOn.fromJson(Map<String, dynamic> json) {
    return _TvUserAddOn(
      name: (json['name'] ?? '').toString(),
      manifest: (json['manifest'] ?? '').toString(),
      enabled: json['enabled'] != false,
    );
  }

  static List<_TvUserAddOn> fromList(Object? value) {
    if (value is! List) return const <_TvUserAddOn>[];
    return value
        .whereType<Map>()
        .map((raw) => _TvUserAddOn.fromJson(Map<String, dynamic>.from(raw)))
        .where((addon) => addon.name.trim().isNotEmpty && addon.manifest.trim().isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'manifest': manifest,
      'enabled': enabled,
    };
  }

  _TvUserAddOn copyWith({String? name, String? manifest, bool? enabled}) {
    return _TvUserAddOn(
      name: name ?? this.name,
      manifest: manifest ?? this.manifest,
      enabled: enabled ?? this.enabled,
    );
  }
}

String _normalizeType(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'tv' || normalized == 'series') return 'series';
  if (normalized == 'animation') return 'animation';
  if (normalized == 'live' || normalized == 'livetv' || normalized == 'channel') return 'live';
  return 'movie';
}

String? _image(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || !text.startsWith('https://')) return null;
  return text;
}

String? _year(Map<String, dynamic> json) {
  final raw = json['year'] ??
      json['releaseInfo'] ??
      json['releaseDate'] ??
      json['released'] ??
      json['premiered'];
  final text = raw?.toString();
  if (text == null || text.isEmpty) return null;
  return RegExp(r'(19\d{2}|20\d{2})').firstMatch(text)?.group(1) ?? text;
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
}

int _yearInt(String? value) {
  if (value == null || value.isEmpty) return 0;
  return int.tryParse(RegExp(r'(19\d{2}|20\d{2})').firstMatch(value)?.group(1) ?? value) ?? 0;
}

double _ratingDouble(String? value) {
  if (value == null || value.isEmpty) return 0;
  return double.tryParse(RegExp(r'\d+(\.\d+)?').firstMatch(value)?.group(0) ?? value) ?? 0;
}

String _copyWithoutRepeatedTitlePhrase({required String title, required String subtitle}) {
  final cleanTitle = title.trim();
  var cleanSubtitle = subtitle.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleanTitle.isEmpty || cleanSubtitle.isEmpty) return cleanSubtitle;
  final lowerTitle = cleanTitle.toLowerCase();
  final lowerSubtitle = cleanSubtitle.toLowerCase();
  if (lowerSubtitle.startsWith(lowerTitle)) {
    cleanSubtitle = cleanSubtitle.substring(cleanTitle.length).trimLeft();
    cleanSubtitle = cleanSubtitle.replaceFirst(RegExp(r'^[-:,.]\s*'), '');
  }
  return cleanSubtitle;
}

extension _TvStringFallback on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

Color _colorFromText(String text) {
  final hash = text.codeUnits.fold<int>(0, (value, code) => (value * 31 + code) & 0xFFFFFF);
  final hue = (hash % 360).toDouble();
  return HSVColor.fromAHSV(1, hue, 0.64, 0.32).toColor();
}

String _friendlyPlaybackError(Object error) {
  if (error is _PlaybackUnavailableException) {
    return switch (error.bucket) {
      'media_timeout' => 'Playback took too long to start.',
      'media_network' => 'Playback could not reach the video right now.',
      'media_format' => 'Playback format is not ready for this TV yet.',
      _ => 'Playback is unavailable right now. (${error.bucket})',
    };
  }
  if (error is _TvApiException) {
    return switch (error.status) {
      'resolver_temporarily_limited' => 'Video is busy right now. Please try again shortly.',
      'resolver_timeout' => 'Playback took too long. Try another title.',
      'resolver_unavailable' => 'Video service is busy right now. Try again shortly.',
      'no_browser_safe_source' => 'No TV-safe source was ready for this title.',
      'no_tv_safe_source' => 'No TV-ready source was available for this title.',
      _ => 'Playback is unavailable right now.',
    };
  }
  return 'Playback is unavailable right now.';
}

String _apiErrorBucket(Object error) {
  if (error is TimeoutException) return 'timeout';
  if (error is _TvApiException) return error.status;
  final message = error.toString().toLowerCase();
  if (message.contains('timeout')) return 'timeout';
  if (message.contains('socket') || message.contains('handshake')) return 'network';
  if (message.contains('format') || message.contains('json')) return 'response';
  return 'unavailable';
}

String _playbackInitBucket(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('timeout')) return 'media_timeout';
  if (message.contains('403') ||
      message.contains('404') ||
      message.contains('410') ||
      message.contains('http') ||
      message.contains('source error') ||
      message.contains('network')) {
    return 'media_network';
  }
  if (message.contains('format') ||
      message.contains('hls') ||
      message.contains('parser') ||
      message.contains('decoder')) {
    return 'media_format';
  }
  return 'media_init';
}

class _PlaybackUnavailableException implements Exception {
  const _PlaybackUnavailableException(this.bucket);

  final String bucket;
}

