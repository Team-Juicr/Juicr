part of 'main.dart';

class _TvCatalogConfig {
  const _TvCatalogConfig({
    this.liveTvGenres = const <String>[],
    this.liveTvCountries = const <String>[],
  });

  factory _TvCatalogConfig.fromJson(Map<String, dynamic> json) {
    return _TvCatalogConfig(
      liveTvGenres: _stringList(json['liveTvGenres']),
      liveTvCountries: _stringList(json['liveTvCountries']),
    );
  }

  final List<String> liveTvGenres;
  final List<String> liveTvCountries;
}

class _TvApi {
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);

  static const int _metaCacheLimit = 160;
  static final Map<String, Future<List<_TvItem>>> _catalogInFlight =
      <String, Future<List<_TvItem>>>{};
  static final Map<String, _TvItem> _metaCache = <String, _TvItem>{};
  static final Map<String, Future<_TvItem>> _metaInflight =
      <String, Future<_TvItem>>{};
  static List<String>? _nativeProviderCache;
  static DateTime? _nativeProviderCacheStoredAt;
  static _TvCatalogConfig? _catalogConfigCache;
  static DateTime? _catalogConfigCacheStoredAt;
  int _playbackInventoryGeneration = 0;

  static void clearCatalogCache() {
    _catalogInFlight.clear();
  }

  Future<_TvCatalogConfig> catalogConfig() async {
    final cached = _catalogConfigCache;
    final cachedAt = _catalogConfigCacheStoredAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 15)) {
      return cached;
    }
    try {
      final json = await _getJson(
        Uri.parse('$_apiBase/config'),
      ).timeout(const Duration(seconds: 12));
      final config = _TvCatalogConfig.fromJson(json);
      _catalogConfigCache = config;
      _catalogConfigCacheStoredAt = DateTime.now();
      return config;
    } catch (error) {
      debugPrint(
        'Juicr TV catalog config unavailable '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return cached ?? const _TvCatalogConfig();
    }
  }

  static const List<String> _defaultNativeProviderOrder = <String>[
    'vidlink',
    'vidsrc',
    'icefy',
    'vidnest',
    'xpass',
    'moviesapi',
    'vidking',
    'popr',
    'cinesu',
    'rgshows',
    'vixsrc',
    'vidrock',
    'vidzee',
    'vidapi',
    'xyra',
    'videasy',
    'vidfun',
    'flixhq',
    'flixer',
    '7xstream',
    'meowtv',
  ];

  static const juicrClientHeaders = <String, String>{
    'accept': 'application/json',
    'user-agent': 'JuicrTV/0.1 AndroidTV',
    'x-juicr-client': 'tv',
    'x-juicr-client-version': '0.1',
    'x-juicr-capabilities':
        'playback_v2,source_pool,mirrors,playback_feedback,subtitle_v2',
  };

  static const juicrMediaHeaders = <String, String>{
    'accept':
        'application/vnd.apple.mpegurl, application/x-mpegURL, video/*, */*',
    'user-agent': 'JuicrTV/0.1 AndroidTV',
    'x-juicr-client': 'tv',
    'x-juicr-client-version': '0.1',
  };

  Future<List<_TvItem>> catalog({
    required String type,
    required String sort,
    int page = 1,
    String genre = '',
    String year = '',
    String search = '',
    bool deepSearch = false,
    bool preferDefaultCatalog = false,
    bool showMatureContent = false,
    String? fallbackType,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final cacheKey = _catalogCacheKey(
      type: type,
      sort: sort,
      page: safePage,
      genre: genre,
      year: year,
      search: search,
      deepSearch: deepSearch,
      preferDefaultCatalog: preferDefaultCatalog,
      showMatureContent: showMatureContent,
      fallbackType: fallbackType,
    );
    final inFlight = _catalogInFlight[cacheKey];
    if (inFlight != null) {
      debugPrint(
        'Juicr TV catalog in-flight hit '
        'type=$type sort=$sort page=$safePage',
      );
      return inFlight;
    }
    final future = _fetchCatalogUncached(
      type: type,
      sort: sort,
      page: safePage,
      genre: genre,
      year: year,
      search: search,
      deepSearch: deepSearch,
      preferDefaultCatalog: preferDefaultCatalog,
      showMatureContent: showMatureContent,
      fallbackType: fallbackType,
    );
    _catalogInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_catalogInFlight[cacheKey], future)) {
        _catalogInFlight.remove(cacheKey);
      }
    }
  }

  Future<List<_TvItem>> _fetchCatalogUncached({
    required String type,
    required String sort,
    required int page,
    required String genre,
    required String year,
    required String search,
    required bool deepSearch,
    required bool preferDefaultCatalog,
    required bool showMatureContent,
    String? fallbackType,
  }) async {
    final uri = Uri.parse('$_apiBase/catalog').replace(
      queryParameters: {
        'type': type,
        'sort': sort,
        'page': page.toString(),
        if (genre.trim().isNotEmpty &&
            genre.trim().toLowerCase() != 'all genres' &&
            genre.trim().toLowerCase() != 'all countries')
          'genre': genre.trim(),
        if (RegExp(r'^\d{4}$').hasMatch(year.trim())) 'year': year.trim(),
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (deepSearch) 'deepSearch': 'true',
        if (preferDefaultCatalog) 'preferDefaultCatalog': 'true',
        ...tvMatureCatalogQuery(showMatureContent),
      },
    );
    final json = await _getJson(uri);
    final rawItems = json['items'] ?? json['metas'];
    if (rawItems is! List) return const [];
    final items = rawItems
        .whereType<Map>()
        .map(
          (raw) => _TvItem.fromJson(
            Map<String, dynamic>.from(raw),
            fallbackType: fallbackType ?? type,
          ),
        )
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .where(
          (item) => tvShouldShowCatalogItem(
            showMatureContent: showMatureContent,
            hasMatureContentSignal: item.hasMatureContentSignal,
          ),
        )
        .toList();
    return items;
  }

  String _catalogCacheKey({
    required String type,
    required String sort,
    required int page,
    required String genre,
    required String year,
    required String search,
    required bool deepSearch,
    required bool preferDefaultCatalog,
    required bool showMatureContent,
    String? fallbackType,
  }) {
    return [
      type.trim().toLowerCase(),
      fallbackType?.trim().toLowerCase() ?? '',
      sort.trim().toLowerCase(),
      page.toString(),
      genre.trim().toLowerCase(),
      year.trim(),
      search.trim().toLowerCase(),
      deepSearch ? 'deep' : '',
      preferDefaultCatalog ? 'default' : '',
      showMatureContent ? 'mature' : 'safe',
    ].join('|');
  }

  Future<_TvHomeEditorialEdition?> homeEditorial() async {
    try {
      final uri = Uri.parse(
        '$_apiBase/home/editorial',
      ).replace(queryParameters: const {'locale': 'en'});
      final json = await _getJson(uri).timeout(const Duration(seconds: 12));
      if (json['degraded'] == true || json.containsKey('fallbackReason')) {
        return null;
      }
      final editorialJson = _homeEditorialPayload(json);
      if (editorialJson == null) return null;
      if (editorialJson['degraded'] == true ||
          editorialJson.containsKey('fallbackReason')) {
        return null;
      }
      if (editorialJson['schema'] != 'juicr.home_editorial.v1') return null;
      final editorial = _TvHomeEditorialEdition.fromJson(editorialJson);
      if (!editorial.hasUsableRails) return null;
      return editorial;
    } catch (error) {
      debugPrint(
        'Juicr TV home editorial unavailable '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return null;
    }
  }

  Future<_TvItem> meta(_TvItem item) async {
    final cacheKey = _metaCacheKey(item);
    final cached = _metaCache[cacheKey];
    if (cached != null) return item.merge(cached);
    final inFlight = _metaInflight[cacheKey];
    if (inFlight != null) return item.merge(await inFlight);
    final future = _fetchMetaUncached(item);
    _metaInflight[cacheKey] = future;
    try {
      final merged = await future;
      _metaCache[cacheKey] = merged;
      _evictOldestMetaCacheEntries();
      return item.merge(merged);
    } finally {
      _metaInflight.remove(cacheKey);
    }
  }

  Future<_TvItem> _fetchMetaUncached(_TvItem item) async {
    final uri = Uri.parse('$_apiBase/meta').replace(
      queryParameters: {
        'type': item.type == 'animation' ? 'series' : item.type,
        'id': _tvResolveHostedId(item),
        if (_tvImdbIdForHostedLookup(item) != null)
          'imdbId': _tvImdbIdForHostedLookup(item)!,
        if (item.tmdbId != null) 'tmdbId': item.tmdbId.toString(),
      },
    );
    final json = await _getJson(uri);
    final meta = json['item'] ?? json['meta'];
    if (meta is! Map) return item;
    return item.merge(
      _TvItem.fromJson(
        Map<String, dynamic>.from(meta),
        fallbackType: item.type,
      ),
    );
  }

  String _metaCacheKey(_TvItem item) {
    return [
      item.type == 'animation' ? 'series' : item.type,
      _tvResolveHostedId(item),
      _tvImdbIdForHostedLookup(item) ?? '',
      item.tmdbId?.toString() ?? '',
    ].join('|');
  }

  void _evictOldestMetaCacheEntries() {
    while (_metaCache.length > _metaCacheLimit) {
      _metaCache.remove(_metaCache.keys.first);
    }
  }

  Future<List<_TvItem>> recommendations(
    _TvItem item, {
    bool showMatureContent = false,
  }) async {
    if (item.type == 'live') return const <_TvItem>[];
    final uri = Uri.parse('$_apiBase/recommendations').replace(
      queryParameters: {
        'type': item.type == 'animation' ? 'movie' : item.type,
        'id': item.id,
        ...tvMatureCatalogQuery(showMatureContent),
      },
    );
    try {
      final json = await _getJson(uri).timeout(const Duration(seconds: 10));
      final rawItems = json['items'] ?? json['metas'];
      if (rawItems is! List) return const <_TvItem>[];
      final items = rawItems
          .whereType<Map>()
          .map(
            (raw) => _TvItem.fromJson(
              Map<String, dynamic>.from(raw),
              fallbackType: item.type == 'animation' ? 'movie' : item.type,
            ),
          )
          .where(
            (candidate) => candidate.id.isNotEmpty && candidate.poster != null,
          )
          .take(12)
          .toList(growable: false);
      final hydrated = await Future.wait(
        items.map((candidate) async {
          if ((candidate.logo ?? '').trim().isNotEmpty) return candidate;
          try {
            return await meta(candidate).timeout(const Duration(seconds: 4));
          } catch (_) {
            return candidate;
          }
        }),
      );
      return hydrated
          .where(
            (candidate) => tvShouldShowCatalogItem(
              showMatureContent: showMatureContent,
              hasMatureContentSignal: candidate.hasMatureContentSignal,
            ),
          )
          .toList(growable: false);
    } catch (error) {
      debugPrint(
        'Juicr TV recommendations unavailable '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return const <_TvItem>[];
    }
  }

  Future<List<_TvTrailer>> trailers(_TvItem item) async {
    final type = item.type == 'movie' ? 'movie' : 'tv';
    final id = item.tmdbId?.toString().isNotEmpty == true
        ? item.tmdbId.toString()
        : item.id;
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
    final id = _tvResolveHostedId(item);
    final imdbId = _tvImdbIdForHostedLookup(item);
    final uri = Uri.parse('$_apiBase/subtitles/$path').replace(
      queryParameters: {
        'id': id,
        if (imdbId != null) 'imdbId': imdbId,
        if (item.tmdbId != null) 'tmdbId': item.tmdbId.toString(),
        if (seriesLike) 'season': season.toString(),
        if (seriesLike) 'episode': episode.toString(),
        'languages': 'en,es,fr,de,pt',
      },
    );
    final json = await _getJson(uri).timeout(const Duration(seconds: 8));
    final rawSubtitles = json['subtitles'] ?? json['items'];
    if (rawSubtitles is! List) return const <_TvSubtitle>[];
    final seen = <String>{};
    final subtitles = [
      for (final raw in rawSubtitles.whereType<Map>())
        _TvSubtitle.fromJson(Map<String, dynamic>.from(raw)),
    ].where((subtitle) {
      if (subtitle.url.isEmpty) return false;
      return seen.add(
        '${subtitle.language}|${subtitle.label}|${subtitle.url}',
      );
    }).toList(growable: false);
    debugPrint(
      'Juicr TV subtitle lookup ok '
      'type=$path idBucket=${id.isEmpty ? 'missing' : 'present'} '
      'imdbLinked=${imdbId != null} tmdbLinked=${item.tmdbId != null} '
      'count=${subtitles.length}',
    );
    return subtitles;
  }

  Future<List<_TvSubtitle>> addOnSubtitles(
    List<_TvUserAddOn> addOns,
    _TvItem item, {
    int season = 1,
    int episode = 1,
  }) async {
    final activeAddOns = addOns.where((addOn) => addOn.enabled).toList();
    if (activeAddOns.isEmpty) {
      debugPrint('Juicr TV add-on subtitle lookup skipped enabled=0');
      return const <_TvSubtitle>[];
    }
    final seriesLike = item.type == 'series' || item.type == 'animation';
    final type = seriesLike ? 'series' : 'movie';
    final ids = _tvSubtitleAddOnIdsForItem(
      item,
      season: seriesLike ? season : null,
      episode: seriesLike ? episode : null,
    );
    if (ids.isEmpty) {
      debugPrint(
        'Juicr TV add-on subtitle lookup skipped '
        'enabled=${activeAddOns.length} ids=0',
      );
      return const <_TvSubtitle>[];
    }
    debugPrint(
      'Juicr TV add-on subtitle lookup start '
      'enabled=${activeAddOns.length} ids=${ids.length} type=$type',
    );
    final subtitles = <_TvSubtitle>[];
    for (final addOn in activeAddOns) {
      try {
        final manifest = await _getJson(
          Uri.parse(addOn.manifest),
        ).timeout(const Duration(seconds: 8));
        final supportsPlural = _tvManifestSupportsResource(
          manifest,
          'subtitles',
        );
        final supportsSingular = _tvManifestSupportsResource(
          manifest,
          'subtitle',
        );
        if (!supportsPlural && !supportsSingular) continue;
        final resources = <String>[
          if (supportsPlural) 'subtitles',
          if (supportsSingular) 'subtitle',
        ];
        for (final id in ids) {
          var foundForAddOn = false;
          for (final resource in resources) {
            for (final uri in _tvAddOnResourceUris(
              addOn.manifest,
              resource: resource,
              type: type,
              id: id,
            )) {
              try {
                final json = await _getJson(
                  uri,
                ).timeout(const Duration(seconds: 10));
                final parsed = _tvSubtitlesFromJson(
                  json['subtitles'] ?? json['items'],
                );
                if (parsed.isEmpty) continue;
                subtitles.addAll(parsed);
                foundForAddOn = true;
                break;
              } catch (_) {
                continue;
              }
            }
            if (foundForAddOn) break;
          }
          if (foundForAddOn) break;
        }
      } catch (_) {
        continue;
      }
    }
    final deduped = _tvDedupeSubtitles(subtitles);
    debugPrint(
      'Juicr TV add-on subtitle lookup ok '
      'enabled=${activeAddOns.length} ids=${ids.length} count=${deduped.length}',
    );
    return deduped;
  }

  Future<String> subtitleText(_TvSubtitle subtitle) async {
    final request = await _client.getUrl(Uri.parse(subtitle.url));
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const _TvApiException('subtitle_unavailable');
    }
    final bytes = await response.expand((chunk) => chunk).toList();
    debugPrint(
      'Juicr TV subtitle fetch '
      'status=${response.statusCode} bytes=${bytes.length} '
      'type=${response.headers.contentType?.primaryType ?? 'unknown'}/'
      '${response.headers.contentType?.subType ?? 'unknown'} '
      'encoding=${response.headers.value(HttpHeaders.contentEncodingHeader) ?? 'identity'}',
    );
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<List<_PlaybackSession>> playbackSessions(
    _TvItem item, {
    required _TvSettingsState settings,
    int season = 1,
    int episode = 1,
  }) async {
    final inventoryGeneration = ++_playbackInventoryGeneration;
    final requestKind = tvPlaybackRequestKindForItemType(item.type);
    Future<_PlaybackSession?>? serverFallbackFuture;
    if (settings.builtInPlayback && requestKind != TvPlaybackRequestKind.live) {
      serverFallbackFuture = _serverPlaybackSession(
        item,
        season: season,
        episode: episode,
      ).then<_PlaybackSession?>((session) => session).catchError((error) {
        debugPrint(
          'Juicr TV server playback fallback unavailable '
          'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
        );
        return null;
      });
    }
    final rawNativeSessions = settings.builtInPlayback
        ? await _nativePlaybackSessions(
            item,
            season: season,
            episode: episode,
          )
        : const <_PlaybackSession>[];
    final rawAddOnSessions = requestKind == TvPlaybackRequestKind.live
        ? const <_PlaybackSession>[]
        : await _addOnPlaybackSessions(
            settings.userAddOns,
            item,
            settings: settings,
            season: season,
            episode: episode,
            allowP2p: settings.p2pPlaybackActive,
          );
    final nativeSessions = _tagPlaybackInventory(
      rawNativeSessions,
      generation: inventoryGeneration,
      family: TvPlaybackCandidateFamily.builtIn,
    );
    final addOnSessions = _tagPlaybackInventory(
      rawAddOnSessions,
      generation: inventoryGeneration,
      family: TvPlaybackCandidateFamily.addOn,
    );
    final sessions = <_PlaybackSession>[];
    for (final candidate in <_PlaybackSession>[
      ...addOnSessions,
      ...nativeSessions,
    ]) {
      _appendUniquePlaybackSession(sessions, candidate);
    }
    if (requestKind == TvPlaybackRequestKind.live) {
      if (sessions.isNotEmpty) return sessions;
      throw const _TvApiException('live_tv_playback_unavailable');
    }
    final fallbackWait = serverFallbackFuture == null
        ? Future<_PlaybackSession?>.value(null)
        : sessions.isEmpty
            ? serverFallbackFuture
            : serverFallbackFuture.timeout(
                const Duration(seconds: 2),
                onTimeout: () => null,
              );
    final session = await fallbackWait;
    if (session != null) {
      final taggedFallback = _tagPlaybackInventory(
        <_PlaybackSession>[session],
        generation: inventoryGeneration,
        family: TvPlaybackCandidateFamily.fallback,
      );
      if (taggedFallback.isNotEmpty) {
        _appendUniquePlaybackSession(sessions, taggedFallback.single);
      }
    }
    if (sessions.isNotEmpty) {
      return sessions;
    }
    throw const _TvApiException('no_tv_safe_source');
  }

  List<_PlaybackSession> _tagPlaybackInventory(
    List<_PlaybackSession> sessions, {
    required int generation,
    required TvPlaybackCandidateFamily family,
  }) {
    return tvTagPlaybackCandidateInventory(
      sessions,
      generation: generation,
      family: family,
      tag: (session, identity, poolGeneration, sourceFamily) =>
          session.copyWith(
        candidateId: identity,
        sourceFamily: sourceFamily.wireValue,
        sourcePoolGeneration: poolGeneration,
      ),
    );
  }

  Future<List<_PlaybackSession>> _addOnPlaybackSessions(
    List<_TvUserAddOn> addOns,
    _TvItem item, {
    required _TvSettingsState settings,
    required int season,
    required int episode,
    required bool allowP2p,
  }) async {
    final active = addOns.where((addOn) => addOn.enabled).toList();
    if (active.isEmpty) return const <_PlaybackSession>[];
    final episodic = item.type == 'series' || item.type == 'animation';
    final requestIds = tvAddonPlaybackRequestIds(
      id: item.id,
      tmdbId: item.tmdbId,
      imdbId: item.imdbId ?? _tvImdbIdForHostedLookup(item),
      season: episodic ? season : null,
      episode: episodic ? episode : null,
    );
    if (requestIds.isEmpty) return const <_PlaybackSession>[];
    final type = episodic ? 'series' : 'movie';
    final sessions = <_PlaybackSession>[];
    for (final addOn in active) {
      try {
        final manifest = await _getJson(
          Uri.parse(addOn.manifest),
        ).timeout(const Duration(seconds: 8));
        if (!_tvManifestSupportsResource(manifest, 'stream') &&
            !_tvManifestSupportsResource(manifest, 'streams')) {
          continue;
        }
        var found = false;
        for (final id in requestIds) {
          for (final resource in const <String>['stream', 'streams']) {
            if (!_tvManifestSupportsResource(manifest, resource)) continue;
            for (final uri in _tvAddOnResourceUris(
              addOn.manifest,
              resource: resource,
              type: type,
              id: id,
            )) {
              try {
                final json = await _getJson(
                  uri,
                ).timeout(const Duration(seconds: 18));
                final candidates = parseTvAddonPlaybackCandidates(
                  json['streams'] ?? json['items'],
                  sourceId: 'addon-${addOn.id}',
                  allowP2p: allowP2p,
                );
                for (final candidate in candidates) {
                  _appendUniquePlaybackSession(
                    sessions,
                    _PlaybackSession(
                      mediaUrl: candidate.mediaUrl,
                      sourceType: candidate.sourceType,
                      httpHeaders: candidate.headers,
                      providerId: _safeTvProviderId(candidate.sourceId),
                      quality: candidate.quality,
                      compatibilityRisk: candidate.compatibilityRisk,
                      sourceClass: candidate.sourceClass,
                      subtitles: _tvSubtitlesFromJson(candidate.subtitles),
                      p2pDescriptor: candidate.p2pDescriptor,
                    ),
                  );
                }
                if (candidates.isNotEmpty) {
                  found = true;
                  break;
                }
              } catch (_) {
                continue;
              }
            }
            if (found) break;
          }
          if (found) break;
        }
      } catch (_) {
        continue;
      }
      if (sessions.length >= 8) break;
    }
    debugPrint(
      'Juicr TV add-on playback lookup count=${sessions.length} '
      'enabled=${active.length} '
      'p2pEnabled=$allowP2p '
      'p2pCount=${sessions.where((session) => session.p2pDescriptor != null).length}',
    );
    return tvBoundedRankedPlaybackCandidateOrder(
      sessions,
      maxCount: 8,
      includeP2pFallback: allowP2p,
      isP2p: (session) => session.p2pDescriptor != null,
      rankOf: (session) => session.p2pDescriptor != null
          ? tvP2pPlaybackCandidateRank(
              mode: settings.p2pSourcePrioritiesEnabled
                  ? settings.p2pPriorityMode
                  : kTvP2pPrioritySmartStart,
              quality: session.quality,
              label: session.p2pDescriptor?.displayName ?? '',
              trackerCount: session.p2pDescriptor?.trackerCount ?? 0,
              avoidRiskyFormats: settings.p2pSourcePrioritiesEnabled
                  ? settings.p2pAvoidRiskyFormats
                  : true,
              sizeLimitMb: settings.p2pSourcePrioritiesEnabled
                  ? settings.p2pSizeLimitMb
                  : 0,
            )
          : tvPlaybackPreferenceCandidateRank(
              engine: 'Native',
              preferredQuality: 'Balanced',
              type: session.sourceType,
              quality: session.quality,
              compatibilityRisk: session.compatibilityRisk,
            ),
    );
  }

  void _appendUniquePlaybackSession(
    List<_PlaybackSession> sessions,
    _PlaybackSession session,
  ) {
    final mediaUrl = session.mediaUrl.trim();
    if (mediaUrl.isEmpty) return;
    final duplicate = sessions.any(
      (candidate) => candidate.mediaUrl.trim() == mediaUrl,
    );
    if (!duplicate) sessions.add(session);
  }

  Future<List<_PlaybackSession>> _nativePlaybackSessions(
    _TvItem item, {
    required int season,
    required int episode,
  }) async {
    final requestKind = tvPlaybackRequestKindForItemType(item.type);
    if (requestKind == TvPlaybackRequestKind.live) {
      return _liveTvPlaybackSessions(item);
    }
    final id = item.tmdbId?.toString().isNotEmpty == true
        ? item.tmdbId.toString()
        : item.id;
    final providerIds = await _nativeProviderIds();
    final sessions = <_PlaybackSession>[];
    final providerResults = providerIds.isEmpty
        ? <List<_PlaybackSession>>[
            await _nativePlaybackSessionsForProvider(
              item,
              id: id,
              requestKind: requestKind,
              season: season,
              episode: episode,
              timeout: const Duration(seconds: 20),
            ),
          ]
        : await _nativePlaybackSessionsFromProviders(
            item,
            id: id,
            providerIds: providerIds.take(8).toList(growable: false),
            requestKind: requestKind,
            season: season,
            episode: episode,
          );
    for (final providerSessions in providerResults) {
      for (final session in providerSessions) {
        _appendUniquePlaybackSession(sessions, session);
      }
      if (sessions.length >= 8) break;
    }
    debugPrint('Juicr TV native playback candidates count=${sessions.length}');
    return sessions.take(8).toList(growable: false);
  }

  Future<List<List<_PlaybackSession>>> _nativePlaybackSessionsFromProviders(
    _TvItem item, {
    required String id,
    required List<String> providerIds,
    required TvPlaybackRequestKind requestKind,
    required int season,
    required int episode,
  }) async {
    Future<List<_PlaybackSession>> guarded(
      Future<List<_PlaybackSession>> future,
    ) {
      return future.catchError((error) {
        debugPrint(
          'Juicr TV native playback unavailable '
          'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
        );
        return const <_PlaybackSession>[];
      });
    }

    final defaultFuture = guarded(
      _nativePlaybackSessionsForProvider(
        item,
        id: id,
        requestKind: requestKind,
        season: season,
        episode: episode,
        timeout: const Duration(seconds: 20),
      ),
    );
    final futures = <Future<List<_PlaybackSession>>>[
      for (final providerId in providerIds)
        guarded(
          _nativePlaybackSessionsForProvider(
            item,
            id: id,
            providerId: providerId,
            requestKind: requestKind,
            season: season,
            episode: episode,
            quietFailures: true,
          ),
        ),
    ];
    final results = <List<_PlaybackSession>>[];
    final defaultSessions = await defaultFuture;
    if (defaultSessions.isNotEmpty) {
      results.add(defaultSessions);
    }
    try {
      final providerResults = await Future.wait(futures).timeout(
        const Duration(seconds: 28),
        onTimeout: () => const <List<_PlaybackSession>>[],
      );
      for (final providerSessions in providerResults) {
        if (providerSessions.isEmpty) continue;
        results.add(providerSessions);
        final count = results.fold<int>(
          0,
          (total, sessions) => total + sessions.length,
        );
        if (count >= 8) break;
      }
    } catch (error) {
      debugPrint(
        'Juicr TV native provider scan stopped '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
    }
    return results;
  }

  Future<List<_PlaybackSession>> _nativePlaybackSessionsForProvider(
    _TvItem item, {
    required String id,
    String? providerId,
    required TvPlaybackRequestKind requestKind,
    required int season,
    required int episode,
    Duration timeout = const Duration(seconds: 16),
    bool quietFailures = false,
  }) async {
    final query = <String, String>{
      'id': id,
      'title': item.title,
      'mediaType': _resolverMediaTypeForItem(item),
      if ((providerId ?? '').trim().isNotEmpty) 'provider': providerId!.trim(),
      if ((item.year ?? '').isNotEmpty) 'year': item.year!,
      if (requestKind.includesEpisode) 'season': season.toString(),
      if (requestKind.includesEpisode) 'episode': episode.toString(),
    };
    final endpoint =
        requestKind.includesEpisode ? 'resolve/tv' : 'resolve/movie';
    try {
      final json = await _getJson(
        Uri.parse('$_apiBase/$endpoint').replace(queryParameters: query),
      ).timeout(timeout);
      final rawSources = json['sources'];
      if (rawSources is! List) return const <_PlaybackSession>[];
      final sessions = <_PlaybackSession>[];
      for (final rawSource in rawSources.whereType<Map>()) {
        final source = Map<String, dynamic>.from(rawSource);
        final session = _playbackSessionFromNativeSource(
          source,
          fallbackProviderId: providerId,
        );
        if (session != null) sessions.add(session);
      }
      return sessions.take(8).toList(growable: false);
    } catch (error) {
      if (!quietFailures) {
        debugPrint(
          'Juicr TV native playback unavailable '
          'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
        );
      }
      return const <_PlaybackSession>[];
    }
  }

  Future<List<_PlaybackSession>> _liveTvPlaybackSessions(_TvItem item) async {
    final query = <String, String>{
      'id': item.id,
      'title': item.title,
      'mediaType': _resolverMediaTypeForItem(item),
    };
    try {
      final json = await _getJson(
        Uri.parse('$_apiBase/resolve/live-tv').replace(queryParameters: query),
      ).timeout(const Duration(seconds: 24));
      final rawSources = json['sources'];
      if (rawSources is! List) return const <_PlaybackSession>[];
      final sessions = <_PlaybackSession>[];
      for (final rawSource in rawSources.whereType<Map>()) {
        final source = Map<String, dynamic>.from(rawSource);
        final session = _playbackSessionFromNativeSource(source);
        if (session != null) sessions.add(session);
      }
      return sessions.take(8).toList(growable: false);
    } catch (error) {
      debugPrint(
        'Juicr TV live playback unavailable '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return const <_PlaybackSession>[];
    }
  }

  String _resolverMediaTypeForItem(_TvItem item) {
    final type = _normalizeType(item.type);
    return switch (type) {
      'series' => 'series',
      'animation' => 'animation',
      'live' || 'live_tv' || 'livetv' || 'channel' => 'live_tv',
      _ => 'movie',
    };
  }

  Future<List<String>> _nativeProviderIds() async {
    final cached = _nativeProviderCache;
    final cachedAt = _nativeProviderCacheStoredAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 15)) {
      return cached;
    }
    try {
      final json = await _getJson(
        Uri.parse('$_apiBase/config'),
      ).timeout(const Duration(seconds: 12));
      final providers = json['providers'];
      if (providers is! List) return _defaultNativeProviderOrder;
      final ids = <String>[];
      for (final raw in providers.whereType<Map>()) {
        if (raw['enabled'] == false) continue;
        final id = (raw['id'] ?? raw['provider'] ?? '').toString().trim();
        if (id.isEmpty || ids.contains(id)) continue;
        ids.add(id);
      }
      final orderedIds = ids.isEmpty
          ? _defaultNativeProviderOrder
          : [
              for (final id in _defaultNativeProviderOrder)
                if (ids.contains(id)) id,
              for (final id in ids)
                if (!_defaultNativeProviderOrder.contains(id)) id,
            ];
      _nativeProviderCache = List<String>.unmodifiable(orderedIds);
      _nativeProviderCacheStoredAt = DateTime.now();
      return orderedIds;
    } catch (error) {
      debugPrint(
        'Juicr TV provider config skipped '
        'bucket=${_apiErrorBucket(error)} errorType=${error.runtimeType}',
      );
      return _defaultNativeProviderOrder;
    }
  }

  _PlaybackSession? _playbackSessionFromNativeSource(
    Map<String, dynamic> source, {
    String? fallbackProviderId,
  }) {
    if (source['drm'] != null) return null;
    final url = (source['url'] ?? '').toString().trim();
    final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final sourceClass = (source['sourceClass'] ?? '').toString().toLowerCase();
    if (sourceClass.isNotEmpty &&
        sourceClass != 'direct' &&
        sourceClass != 'debrid') {
      return null;
    }
    final sourceType = _nativeSourceType(source, url);
    if (!_tvNativeSourceTypeAllowed(sourceType)) return null;
    return _PlaybackSession(
      mediaUrl: url,
      sourceType: sourceType,
      httpHeaders: _stringMap(source['headers']),
      providerId: _safeTvProviderId(source['provider'] ?? fallbackProviderId),
      quality: _displayTvQuality(source['quality']),
      sourceClass: sourceClass,
      mirrorGroupId:
          (source['mirrorGroupId'] ?? source['mirror_group_id'])?.toString(),
      mirrorRank: _intFromJson(source['mirrorRank'] ?? source['mirror_rank']),
      sourcePoolVersion:
          (source['sourcePoolVersion'] ?? source['source_pool_version'])
              ?.toString(),
      subtitles: _tvSubtitlesFromJson(source['subtitles']),
    );
  }

  String _safeTvProviderId(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw.isEmpty) return '';
    return raw.replaceAll(RegExp(r'[^a-z0-9_-]+'), '').trim();
  }

  String _displayTvQuality(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return 'Unknown';
    final lower = raw.toLowerCase();
    if (lower == 'auto' || lower == 'adaptive') {
      return 'Auto';
    }
    if (lower == 'unknown') return 'Unknown';
    final resolution = RegExp(
      r'\b(2160|1440|1080|720|576|480|360|240)\s*p\b',
      caseSensitive: false,
    ).firstMatch(raw);
    if (resolution != null) return '${resolution.group(1)}P';
    final compact = lower.replaceAll(RegExp(r'[\s_-]+'), '');
    final named = switch (compact) {
      _ when compact.contains('4k') || compact.contains('uhd') => '2160P',
      _ when compact.contains('2k') || compact.contains('qhd') => '1440P',
      'fhd' || 'fullhd' => '1080P',
      'hd' => '720P',
      'sd' => '480P',
      _ => '',
    };
    return named.isEmpty ? 'Unknown' : named;
  }

  String _nativeSourceType(Map<String, dynamic> source, String url) {
    final rawType = (source['type'] ?? '').toString().trim().toLowerCase();
    if (rawType.isNotEmpty) return rawType;
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('.m3u8')) return 'hls';
    if (lowerUrl.contains('.mpd')) return 'dash';
    if (lowerUrl.contains('.mp4')) return 'mp4';
    return 'video';
  }

  bool _tvNativeSourceTypeAllowed(String sourceType) {
    final type = sourceType.toLowerCase();
    return type == 'hls' ||
        type == 'm3u8' ||
        type == 'application/x-mpegurl' ||
        type == 'application/vnd.apple.mpegurl' ||
        type == 'dash' ||
        type == 'mpd' ||
        type == 'mp4' ||
        type == 'video/mp4' ||
        type == 'application/mp4' ||
        type == 'video';
  }

  Future<_PlaybackSession> _serverPlaybackSession(
    _TvItem item, {
    required int season,
    required int episode,
  }) async {
    final requestKind = tvPlaybackRequestKindForItemType(item.type);
    final type = requestKind.apiValue;
    final body = <String, dynamic>{
      'type': type,
      'id': item.tmdbId?.toString().isNotEmpty == true
          ? item.tmdbId.toString()
          : item.id,
      'imdbId': item.id.startsWith('tt') ? item.id : '',
      'tmdbId': item.tmdbId?.toString() ?? '',
      'title': item.title,
      'year': item.year ?? '',
      if (requestKind.includesEpisode) 'season': season,
      if (requestKind.includesEpisode) 'episode': episode,
    };
    final json = await _postJson(
      Uri.parse('$_apiBase/web/playback/session'),
      body,
    ).timeout(const Duration(seconds: 20));
    if (json['ok'] != true ||
        json['mediaUrl'] == null ||
        json['rawSourceExposed'] == true) {
      throw _TvApiException(
        (json['status'] ?? json['error'] ?? 'playback_unavailable').toString(),
      );
    }
    return _PlaybackSession(
      mediaUrl: json['mediaUrl'].toString(),
      sourceType: (json['sourceType'] ?? '').toString(),
      httpHeaders: juicrMediaHeaders,
      quality: _displayTvQuality(json['quality']),
      subtitles: _tvSubtitlesFromJson(json['subtitles']),
    );
  }

  Future<_TvAuthCodeSendResult> sendAuthCode(String email) async {
    final json = await _postJson(Uri.parse('$_apiBase/auth/send-code'), {
      'email': email.trim(),
    }).timeout(const Duration(seconds: 12));
    return _TvAuthCodeSendResult(
      expiresInSeconds: _intFromJson(json['expiresInSeconds']) ?? 600,
      resendCooldownSeconds: _intFromJson(json['resendCooldownSeconds']) ?? 60,
    );
  }

  Future<_TvAuthVerificationResult> verifyAuthCode({
    required String email,
    required String code,
  }) async {
    final json = await _postJson(Uri.parse('$_apiBase/auth/verify-code'), {
      'email': email.trim(),
      'code': code.trim(),
    }).timeout(const Duration(seconds: 12));
    final user = json['user'];
    final session = json['session'];
    if (user is! Map || session is! Map) {
      throw const _TvApiException('auth_incomplete');
    }
    final profile = TvAccountProfile.fromJson(Map<String, Object?>.from(user));
    final accountSession = TvAccountSession.fromJson(
      Map<String, Object?>.from(session),
    );
    if (!profile.isUsable || !accountSession.isValid) {
      throw const _TvApiException('auth_incomplete');
    }
    return _TvAuthVerificationResult(profile: profile, session: accountSession);
  }

  Future<TvAccountProfile?> refreshAuthSession(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return null;
    final response = await _getResponse(
      Uri.parse('$_apiBase/auth/session'),
      bearerToken: cleanToken,
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode == 401) return null;
    final json = await _decodeJson(response);
    final user = json['user'];
    if (user is! Map) return null;
    final profile = TvAccountProfile.fromJson(Map<String, Object?>.from(user));
    return profile.isUsable ? profile : null;
  }

  Future<void> signOutAuthSession(String token) async {
    final cleanToken = token.trim();
    await _postJson(
      Uri.parse('$_apiBase/auth/sign-out'),
      const <String, Object?>{},
      bearerToken: cleanToken.isEmpty ? null : cleanToken,
    ).timeout(const Duration(seconds: 8));
  }

  Future<void> syncAccountWatchMetrics({
    required String token,
    required int activeWatchSeconds,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return;
    await _postJson(
            Uri.parse('$_apiBase/account/watch-metrics'),
            {
              'activeWatchSeconds': math.max(0, activeWatchSeconds),
            },
            bearerToken: cleanToken)
        .timeout(const Duration(seconds: 8));
  }

  Future<int?> fetchAccountActiveWatchSeconds(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return null;
    final json = await _getJson(
      Uri.parse('$_apiBase/account/watch-metrics'),
      bearerToken: cleanToken,
    ).timeout(const Duration(seconds: 8));
    return _intFromJson(json['activeWatchSeconds']);
  }

  Future<TvAccountProfile> updateAccountProfile({
    required String token,
    required String username,
    required String emoji,
    required bool leaderboardOptIn,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw const _TvApiException('auth_required');
    }
    final json = await _postJson(
            Uri.parse('$_apiBase/account/profile'),
            {
              'username': username.trim(),
              'emoji': emoji.trim(),
              'leaderboardOptIn': leaderboardOptIn,
            },
            bearerToken: cleanToken)
        .timeout(const Duration(seconds: 12));
    final user = json['user'];
    if (user is! Map) {
      throw const _TvApiException('account_profile_incomplete');
    }
    final profile = TvAccountProfile.fromJson(Map<String, Object?>.from(user));
    if (!profile.isUsable) {
      throw const _TvApiException('account_profile_incomplete');
    }
    return profile;
  }

  Future<void> deleteAccount(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw const _TvApiException('auth_required');
    }
    await _postJson(
      Uri.parse('$_apiBase/account/delete'),
      const <String, Object?>{},
      bearerToken: cleanToken,
    ).timeout(const Duration(seconds: 12));
  }

  Future<String> sendDiagnosticReport(String report) async {
    final json =
        await _postJson(Uri.parse('$_apiBase/ops/diagnostics/report'), {
      'appVersion': '$_tvAppVersion+$_tvAppBuildNumber',
      'platform': 'android-tv',
      'report': report,
    }).timeout(const Duration(seconds: 12));
    final ticketId = (json['ticketId'] ?? '').toString().trim();
    if (ticketId.isEmpty) {
      throw const _TvApiException('diagnostic_ticket_missing');
    }
    return ticketId;
  }

  Future<_TvLeaderboardResult> fetchLeaderboard({
    required String scope,
    required String token,
  }) async {
    final uri = Uri.parse('$_apiBase/leaderboard').replace(
      queryParameters: {
        'scope': scope.trim().isEmpty ? 'weekly' : scope.trim(),
      },
    );
    final json = await _getJson(
      uri,
      bearerToken: token.trim().isEmpty ? null : token.trim(),
    ).timeout(const Duration(seconds: 8));
    return _TvLeaderboardResult.fromJson(json);
  }

  Future<_TvAccountLibrarySnapshotResult?> fetchAccountLibrarySnapshot(
    String token,
  ) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return null;
    final json = await _getJson(
      Uri.parse('$_apiBase/account/library-sync'),
      bearerToken: cleanToken,
    ).timeout(const Duration(seconds: 8));
    return _TvAccountLibrarySnapshotResult.fromJson(json);
  }

  Future<_TvAccountLibraryPushResult> pushAccountLibrarySnapshot({
    required String token,
    required Map<String, Object?> snapshot,
    String baseRevision = '',
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      return const _TvAccountLibraryPushResult(
        ok: false,
        conflict: false,
        revision: '',
        snapshot: null,
      );
    }
    final json = await _postJson(
            Uri.parse('$_apiBase/account/library-sync'),
            {
              'snapshot': snapshot,
              if (baseRevision.trim().isNotEmpty)
                'baseRevision': baseRevision.trim(),
            },
            bearerToken: cleanToken)
        .timeout(const Duration(seconds: 8));
    return _TvAccountLibraryPushResult.fromJson(json);
  }

  Future<HttpClientResponse> _getResponse(
    Uri uri, {
    String? bearerToken,
  }) async {
    final request = await _client.getUrl(uri);
    _applyJuicrHeaders(request);
    final token = bearerToken?.trim();
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    return request.close();
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, {String? bearerToken}) async {
    final response = await _getResponse(uri, bearerToken: bearerToken);
    return _decodeJson(response);
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, Object?> body, {
    String? bearerToken,
  }) async {
    final request = await _client.postUrl(uri);
    _applyJuicrHeaders(request);
    final token = bearerToken?.trim();
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
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
    if (decoded is! Map) {
      throw const FormatException('Unexpected API response.');
    }
    return Map<String, dynamic>.from(decoded);
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
    this.logo,
    this.year,
    this.tmdbId,
    this.imdbId,
    this.genres = const [],
    this.description,
    this.imdbRating,
    this.releaseDate,
    this.isUpcoming = false,
    this.runtime,
    this.directorPeople = const [],
    this.castPeople = const [],
    this.episodes = const [],
    this.hasMatureContentSignal = false,
  });

  factory _TvItem.fromJson(
    Map<String, dynamic> json, {
    required String fallbackType,
  }) {
    final id = (json['id'] ?? '').toString();
    final title = (json['name'] ?? json['title'] ?? 'Untitled').toString();
    final genres = _genreList(json);
    return _TvItem(
      id: id,
      type: _normalizeItemType(json['type'], fallbackType),
      title: title,
      color: _colorFromText(id.isEmpty ? title : id),
      poster: _image(
        json['poster'] ??
            json['posterUrl'] ??
            json['image'] ??
            json['thumbnail'],
      ),
      background: _image(
        json['background'] ??
            json['backdrop'] ??
            json['fanart'] ??
            json['landscape'],
      ),
      logo: _logoImage(
        json['logo'] ??
            json['logoUrl'] ??
            json['clearLogo'] ??
            json['clear_logo'] ??
            json['titleLogo'] ??
            json['title_logo'] ??
            json['titleArt'] ??
            json['title_art'] ??
            json['logos'] ??
            json['images'] ??
            json['artwork'],
      ),
      year: _year(json),
      tmdbId: int.tryParse(
        (json['tmdb_id'] ?? json['moviedb_id'] ?? json['tmdbId'] ?? '')
            .toString(),
      ),
      imdbId: _imdbIdFromJson(json),
      genres: genres,
      description: (json['description'] ?? json['overview'])?.toString(),
      imdbRating: (json['imdbRating'] ?? json['rating'])?.toString(),
      releaseDate: _releaseDateFromJson(json),
      isUpcoming: json['isUpcoming'] == true ||
          _isUpcomingCatalogValue(
            json['sort'] ?? json['catalogSort'] ?? json['category'],
          ) ||
          (json['releaseStatus'] ?? json['status'])
              .toString()
              .toLowerCase()
              .contains('upcoming'),
      runtime: (json['runtime'] ?? json['runtimeLabel'])?.toString(),
      directorPeople: _TvPersonCredit.fromList(json['director']),
      castPeople: _TvPersonCredit.fromList(json['cast']),
      episodes: _TvEpisode.fromList(json['videos'] ?? json['episodes']),
      hasMatureContentSignal: tvHasMatureContentSignal(json),
    );
  }

  final String id;
  final String type;
  final String title;
  final Color color;
  final String? poster;
  final String? background;
  final String? logo;
  final String? year;
  final int? tmdbId;
  final String? imdbId;
  final List<String> genres;
  final String? description;
  final String? imdbRating;
  final String? releaseDate;
  final bool isUpcoming;
  final String? runtime;
  final List<_TvPersonCredit> directorPeople;
  final List<_TvPersonCredit> castPeople;
  final List<_TvEpisode> episodes;
  final bool hasMatureContentSignal;

  String get subtitle {
    final parts = [
      if (year != null && year!.isNotEmpty) year!,
      if (imdbRating != null && imdbRating!.isNotEmpty) 'IMDb $imdbRating',
      if (runtime != null && runtime!.isNotEmpty) runtime!,
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
      logo: other.logo ?? logo,
      year: other.year ?? year,
      tmdbId: other.tmdbId ?? tmdbId,
      imdbId: other.imdbId ?? imdbId,
      genres: other.genres.isNotEmpty ? other.genres : genres,
      description: other.description ?? description,
      imdbRating: other.imdbRating ?? imdbRating,
      releaseDate: other.releaseDate ?? releaseDate,
      isUpcoming: other.isUpcoming || isUpcoming,
      runtime: other.runtime ?? runtime,
      directorPeople: other.directorPeople.isNotEmpty
          ? other.directorPeople
          : directorPeople,
      castPeople: other.castPeople.isNotEmpty ? other.castPeople : castPeople,
      episodes: other.episodes.isNotEmpty ? other.episodes : episodes,
      hasMatureContentSignal:
          hasMatureContentSignal || other.hasMatureContentSignal,
    );
  }

  _TvItem withArtwork({String? poster, String? background, String? logo}) {
    return _TvItem(
      id: id,
      type: type,
      title: title,
      color: color,
      poster: poster ?? this.poster,
      background: background ?? this.background,
      logo: logo ?? this.logo,
      year: year,
      tmdbId: tmdbId,
      imdbId: imdbId,
      genres: genres,
      description: description,
      imdbRating: imdbRating,
      releaseDate: releaseDate,
      isUpcoming: isUpcoming,
      runtime: runtime,
      directorPeople: directorPeople,
      castPeople: castPeople,
      episodes: episodes,
      hasMatureContentSignal: hasMatureContentSignal,
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
      logo: logo,
      year: year,
      tmdbId: tmdbId,
      imdbId: imdbId,
      genres: genres,
      description: description,
      imdbRating: imdbRating,
      releaseDate: releaseDate,
      isUpcoming: isUpcoming,
      runtime: runtime,
      directorPeople: directorPeople,
      castPeople: castPeople,
      episodes: episodes,
      hasMatureContentSignal: hasMatureContentSignal,
    );
  }
}

String _tvResolveHostedId(_TvItem item) {
  final tmdbId = item.tmdbId;
  if (tmdbId != null) return tmdbId.toString();
  final raw = item.id.trim();
  final tmdbMatch =
      RegExp(r'^tmdb:(\d+)$', caseSensitive: false).firstMatch(raw);
  if (tmdbMatch != null) return tmdbMatch.group(1)!;
  return raw;
}

String? _tvImdbIdForHostedLookup(_TvItem item) {
  final itemImdbId = item.imdbId?.trim();
  if (itemImdbId != null &&
      RegExp(r'^tt\d{5,12}$', caseSensitive: false).hasMatch(itemImdbId)) {
    return itemImdbId;
  }
  final raw = item.id.trim();
  if (RegExp(r'^tt\d{5,12}$', caseSensitive: false).hasMatch(raw)) {
    return raw;
  }
  return null;
}

String? _imdbIdFromJson(Map<String, dynamic> json) {
  final direct = (json['imdb_id'] ?? json['imdbId'])?.toString().trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final externalIds = json['external_ids'] ?? json['externalIds'];
  if (externalIds is Map) {
    final nested =
        (externalIds['imdb_id'] ?? externalIds['imdbId'])?.toString().trim();
    if (nested != null && nested.isNotEmpty) return nested;
  }
  return null;
}

class _TvPersonCredit {
  const _TvPersonCredit({required this.name, this.image});

  factory _TvPersonCredit.fromJson(dynamic value) {
    if (value is Map) {
      return _TvPersonCredit(
        name: (value['name'] ?? '').toString().trim(),
        image: _image(
          value['image'] ?? value['profile'] ?? value['profileUrl'],
        ),
      );
    }
    return _TvPersonCredit(name: value.toString().trim());
  }

  final String name;
  final String? image;

  static List<_TvPersonCredit> fromList(dynamic value) {
    if (value is! List) return const <_TvPersonCredit>[];
    return value
        .map(_TvPersonCredit.fromJson)
        .where((person) => person.name.isNotEmpty)
        .toList(growable: false);
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
    final rawDescription =
        (json['description'] ?? json['overview'] ?? '').toString().trim();
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
  const _TvTrailer({required this.title, required this.url});

  factory _TvTrailer.fromJson(Map<String, dynamic> json) {
    final title =
        (json['title'] ?? json['name'] ?? 'Trailer').toString().trim();
    return _TvTrailer(
      title: title.isEmpty ? 'Trailer' : title,
      url: (json['url'] ?? json['externalUrl'] ?? json['href'] ?? '')
          .toString()
          .trim(),
    );
  }

  final String title;
  final String url;

  bool get isExternalLaunchable {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host.contains('youtube.com') || host.contains('youtu.be');
  }

  bool get isTvPlayable {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.contains('youtube.com') || host.contains('youtu.be')) return false;
    final lower = uri.path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.m3u8') ||
        lower.endsWith('.mpd') ||
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
    this.provider = '',
    this.format = 'vtt',
    this.isDefault = false,
    this.isForced = false,
  });

  factory _TvSubtitle.fromJson(Map<String, dynamic> json) {
    final language = (json['language'] ?? json['lang'] ?? '').toString().trim();
    final label = (json['label'] ?? json['name'] ?? language).toString().trim();
    final url = (json['url'] ?? json['src'] ?? '').toString().trim();
    return _TvSubtitle(
      id: (json['id'] ?? json['subtitleId'] ?? language.ifEmpty(label))
          .toString(),
      label: label.isEmpty ? 'Subtitle' : label,
      language: language,
      url: url,
      provider: (json['provider'] ?? json['source'] ?? json['sourceKey'] ?? '')
          .toString()
          .trim(),
      format: tvSubtitleFormatFromJson(json, label: label, url: url),
      isDefault: json['isDefault'] == true || json['default'] == true,
      isForced: json['isForced'] == true || json['forced'] == true,
    );
  }

  final String id;
  final String label;
  final String language;
  final String url;
  final String provider;
  final String format;
  final bool isDefault;
  final bool isForced;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'language': language,
      'url': url,
      'provider': provider,
      'format': format,
      'isDefault': isDefault,
      'isForced': isForced,
    };
  }
}

String tvSubtitleFormatFromJson(
  Map<String, dynamic> json, {
  required String label,
  required String url,
}) {
  final explicit = (json['format'] ??
          json['type'] ??
          json['extension'] ??
          json['mimeType'] ??
          json['mime'] ??
          '')
      .toString()
      .trim()
      .toLowerCase();
  final candidates = <String>[
    label.toLowerCase(),
    Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase(),
    explicit,
  ];
  for (final value in candidates) {
    if (value.isEmpty) continue;
    if (value.contains('subrip') ||
        value.contains('/srt') ||
        value.contains('[srt]') ||
        value.endsWith('.srt') ||
        value == 'srt') {
      return 'srt';
    }
    if (value.contains('webvtt') ||
        value.contains('text/vtt') ||
        value.contains('[vtt]') ||
        value.endsWith('.vtt') ||
        value == 'vtt') {
      return 'vtt';
    }
    if (value.contains('text/x-ssa') ||
        value.contains('[ssa]') ||
        value.endsWith('.ssa') ||
        value == 'ssa') {
      return 'ssa';
    }
    if (value.contains('text/x-ass') ||
        value.contains('[ass]') ||
        value.endsWith('.ass') ||
        value == 'ass') {
      return 'ass';
    }
    if (value.contains('ttml') ||
        value.contains('dfxp') ||
        value.endsWith('.ttml') ||
        value.endsWith('.dfxp')) {
      return 'ttml';
    }
  }
  return 'vtt';
}

List<_TvSubtitle> _tvSubtitlesFromJson(dynamic value) {
  if (value is! List) return const <_TvSubtitle>[];
  final subtitles = <_TvSubtitle>[
    for (final raw in value.whereType<Map>())
      _TvSubtitle.fromJson(Map<String, dynamic>.from(raw)),
  ];
  return _tvDedupeSubtitles(subtitles);
}

List<_TvSubtitle> _tvDedupeSubtitles(Iterable<_TvSubtitle> subtitles) {
  final seen = <String>{};
  final deduped = <_TvSubtitle>[];
  for (final subtitle in subtitles) {
    if (subtitle.url.isEmpty) continue;
    final key = subtitle.id.trim().isNotEmpty
        ? subtitle.id.trim()
        : '${subtitle.url}|${subtitle.language}|${subtitle.label}';
    if (!seen.add(key)) continue;
    deduped.add(subtitle);
  }
  return deduped.toList(growable: false);
}

bool _tvManifestSupportsResource(Map<String, dynamic> manifest, String name) {
  final resources = manifest['resources'];
  if (resources is! List) return false;
  for (final resource in resources) {
    if (resource is String && resource == name) return true;
    if (resource is Map && resource['name'] == name) return true;
  }
  return false;
}

List<Uri> _tvAddOnResourceUris(
  String manifestUrl, {
  required String resource,
  required String type,
  required String id,
}) {
  final base = _tvAddOnBaseUrl(manifestUrl);
  final encoded = Uri.tryParse(
    '$base/$resource/$type/${Uri.encodeComponent(id)}.json',
  );
  final raw = Uri.tryParse('$base/$resource/$type/$id.json');
  return <Uri>[
    if (encoded != null) encoded,
    if (raw != null && raw != encoded) raw,
  ];
}

String _tvAddOnBaseUrl(String manifestUrl) {
  final trimmed = manifestUrl.trim();
  final manifestIndex = trimmed.toLowerCase().lastIndexOf('/manifest.json');
  if (manifestIndex >= 0) return trimmed.substring(0, manifestIndex);
  return trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

List<String> _tvSubtitleAddOnIdsForItem(
  _TvItem item, {
  int? season,
  int? episode,
}) {
  final baseIds = _tvUniqueNonEmptyStrings([
    if (_tvImdbIdForHostedLookup(item) != null) _tvImdbIdForHostedLookup(item)!,
    item.id,
    if (item.tmdbId != null) 'tmdb:${item.tmdbId}',
  ]);
  if (season == null || episode == null) return baseIds;
  return baseIds.map((id) => '$id:$season:$episode').toList(growable: false);
}

List<String> _tvUniqueNonEmptyStrings(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || result.contains(trimmed)) continue;
    result.add(trimmed);
  }
  return result;
}

class _TvHomeEditorialEdition {
  const _TvHomeEditorialEdition({
    required this.editionId,
    required this.editionDate,
    required this.hero,
    required this.topSignal,
    required this.todaySignal,
    required this.juicrTopSignal,
    required this.movie,
    required this.series,
    required this.animation,
    required this.personal,
    required this.history,
    required this.saved,
    required this.privateShelf,
    required this.throwback,
    required this.upcoming,
    required this.rails,
  });

  factory _TvHomeEditorialEdition.fromJson(Map<String, dynamic> json) {
    final rails = _homeEditorialRailsById(json['rails']);
    final orderedRails = _homeEditorialRails(json['rails']);
    final edition = _TvHomeEditorialEdition(
      editionId: (json['editionId'] ?? '').toString(),
      editionDate: (json['editionDate'] ?? '').toString(),
      hero: _TvHomeEditorialRail.fromJson(json['hero']),
      topSignal: _TvHomeEditorialRail.fromJson(rails['topSignal']),
      todaySignal: _TvHomeEditorialRail.fromJson(rails['todaySignal']),
      juicrTopSignal: _TvHomeEditorialRail.fromJson(rails['juicrTopSignal']),
      movie: _TvHomeEditorialRail.fromJson(
        rails['movieEditorial'] ?? rails['movie'],
      ),
      series: _TvHomeEditorialRail.fromJson(
        rails['seriesEditorial'] ?? rails['series'],
      ),
      animation: _TvHomeEditorialRail.fromJson(
        rails['animationEditorial'] ?? rails['animation'],
      ),
      personal: _TvHomeEditorialRail.fromJson(
        rails['personalEditorial'] ?? rails['personal'],
      ),
      history: _TvHomeEditorialRail.fromJson(
        rails['historyEditorial'] ?? rails['history'],
      ),
      saved: _TvHomeEditorialRail.fromJson(
        rails['savedEditorial'] ?? rails['saved'],
      ),
      privateShelf: _TvHomeEditorialRail.fromJson(
        rails['privateShelfEditorial'] ?? rails['privateShelf'],
      ),
      throwback: _TvHomeEditorialRail.fromJson(
        rails['throwbackEditorial'] ?? rails['throwback'],
      ),
      upcoming: _TvHomeEditorialRail.fromJson(
        rails['upcomingEditorial'] ?? rails['upcoming'],
      ),
      rails: const <_TvHomeEditorialRail>[],
    );
    return edition.copyWith(
      rails: orderedRails.isNotEmpty
          ? orderedRails
          : [
              edition.topSignal,
              edition.todaySignal,
              edition.juicrTopSignal,
              edition.movie,
              edition.series,
              edition.animation,
              edition.personal,
              edition.history,
              edition.saved,
              edition.privateShelf,
              edition.throwback,
              edition.upcoming,
            ]
              .where(
                (rail) => rail.title.isNotEmpty || rail.subtitle.isNotEmpty,
              )
              .toList(growable: false),
    );
  }

  final String editionId;
  final String editionDate;
  final _TvHomeEditorialRail hero;
  final _TvHomeEditorialRail topSignal;
  final _TvHomeEditorialRail todaySignal;
  final _TvHomeEditorialRail juicrTopSignal;
  final _TvHomeEditorialRail movie;
  final _TvHomeEditorialRail series;
  final _TvHomeEditorialRail animation;
  final _TvHomeEditorialRail personal;
  final _TvHomeEditorialRail history;
  final _TvHomeEditorialRail saved;
  final _TvHomeEditorialRail privateShelf;
  final _TvHomeEditorialRail throwback;
  final _TvHomeEditorialRail upcoming;
  final List<_TvHomeEditorialRail> rails;

  bool get hasUsableRails {
    bool usableRail(_TvHomeEditorialRail rail) {
      return rail.title.trim().isNotEmpty &&
          (rail.items.isNotEmpty ||
              rail.genres.isNotEmpty ||
              rail.query.trim().isNotEmpty ||
              rail.types.isNotEmpty ||
              rail.curationKind.trim().isNotEmpty);
    }

    return usableRail(hero) || rails.any(usableRail);
  }

  bool get hasCompleteHomeContract {
    const requiredIds = <String>[
      'todaySignal',
      'topSignal',
      'juicrTopSignal',
      'savedEditorial',
      'upcomingEditorial',
    ];
    if (editionId.trim().isEmpty ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(editionDate.trim()) ||
        hero.title.trim().isEmpty ||
        rails.length != requiredIds.length) {
      return false;
    }
    for (var index = 0; index < requiredIds.length; index += 1) {
      final rail = rails[index];
      if (rail.id != requiredIds[index] || rail.title.trim().isEmpty) {
        return false;
      }
    }
    final rankedRails = rails.take(3);
    final rankedRolesAreExact = rankedRails.every((rail) {
      if (rail.kind != 'ranked' || rail.items.isEmpty) return false;
      for (var index = 0; index < rail.items.length; index += 1) {
        final item = rail.items[index];
        if (!item.isUsable || item.rank != index + 1) return false;
      }
      return true;
    });
    return rankedRolesAreExact &&
        saved.kind == 'library' &&
        saved.intent == 'saved_library' &&
        upcoming.kind == 'catalog' &&
        upcoming.intent == 'upcoming' &&
        upcoming.sort == 'upcoming' &&
        RegExp(r'^\d{4}$').hasMatch(upcoming.year);
  }

  _TvHomeEditorialEdition copyWith({List<_TvHomeEditorialRail>? rails}) {
    return _TvHomeEditorialEdition(
      editionId: editionId,
      editionDate: editionDate,
      hero: hero,
      topSignal: topSignal,
      todaySignal: todaySignal,
      juicrTopSignal: juicrTopSignal,
      movie: movie,
      series: series,
      animation: animation,
      personal: personal,
      history: history,
      saved: saved,
      privateShelf: privateShelf,
      throwback: throwback,
      upcoming: upcoming,
      rails: rails ?? this.rails,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'editionId': editionId,
      'editionDate': editionDate,
      'hero': hero.toJson(),
      'rails': [
        topSignal.toJson(idOverride: 'topSignal'),
        todaySignal.toJson(idOverride: 'todaySignal'),
        juicrTopSignal.toJson(idOverride: 'juicrTopSignal'),
        movie.toJson(idOverride: 'movieEditorial'),
        series.toJson(idOverride: 'seriesEditorial'),
        animation.toJson(idOverride: 'animationEditorial'),
        personal.toJson(idOverride: 'personalEditorial'),
        history.toJson(idOverride: 'historyEditorial'),
        saved.toJson(idOverride: 'savedEditorial'),
        privateShelf.toJson(idOverride: 'privateShelfEditorial'),
        throwback.toJson(idOverride: 'throwbackEditorial'),
        upcoming.toJson(idOverride: 'upcomingEditorial'),
        for (final rail in rails)
          if (rail.id.isNotEmpty) rail.toJson(),
      ],
    };
  }
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
    this.curationKind = '',
    this.pageOneOnly = false,
    this.releaseWindow = '',
    this.year = '',
    this.theme = '',
    this.seasonalWindow = '',
    this.query = '',
    this.items = const <_TvHomeEditorialTrendItem>[],
  });

  factory _TvHomeEditorialRail.fromJson(dynamic json) {
    if (json is! Map) return empty;
    final raw = Map<String, dynamic>.from(json);
    final route = raw['route'] is Map
        ? Map<String, dynamic>.from(raw['route'] as Map)
        : const <String, dynamic>{};
    final title = (raw['title'] ?? '').toString().trim();
    final subtitle = _copyWithoutRepeatedTitlePhrase(
      title: title,
      subtitle: (raw['subtitle'] ?? '').toString().trim(),
    );
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
          .where(
            (type) =>
                type == 'movie' || type == 'series' || type == 'animation',
          )
          .toList(growable: false),
      genres: genres.isNotEmpty
          ? genres
          : routeGenre.isNotEmpty && routeGenre.toLowerCase() != 'all genres'
              ? [routeGenre]
              : const <String>[],
      sort: (raw['sort'] ?? route['sort'] ?? 'imdbRating').toString().trim(),
      perType: int.tryParse(
            (raw['perType'] ?? '').toString(),
          )?.clamp(1, 12).toInt() ??
          4,
      requireGenreMatch: raw['requireGenreMatch'] == true,
      intent: (raw['intent'] ?? '').toString().trim(),
      curationKind:
          (raw['curationKind'] ?? raw['curation_kind'] ?? '').toString().trim(),
      pageOneOnly: raw['pageOneOnly'] == true,
      releaseWindow: (raw['releaseWindow'] ?? '').toString().trim(),
      year: (raw['year'] ?? route['year'] ?? '').toString().trim(),
      theme: (raw['theme'] ?? '').toString().trim(),
      seasonalWindow: (raw['seasonalWindow'] ?? '').toString().trim(),
      query: (raw['query'] ?? route['query'] ?? '').toString().trim(),
      items: _homeEditorialTrendItems(raw['items']),
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
  final String curationKind;
  final bool pageOneOnly;
  final String releaseWindow;
  final String year;
  final String theme;
  final String seasonalWindow;
  final String query;
  final List<_TvHomeEditorialTrendItem> items;

  Map<String, dynamic> toJson({String? idOverride}) {
    return {
      'id': idOverride ?? id,
      'kind': kind,
      'title': title,
      'subtitle': subtitle,
      'types': types,
      'genres': genres,
      'sort': sort,
      'perType': perType,
      'requireGenreMatch': requireGenreMatch,
      'intent': intent,
      'curationKind': curationKind,
      'pageOneOnly': pageOneOnly,
      'releaseWindow': releaseWindow,
      'year': year,
      'theme': theme,
      'seasonalWindow': seasonalWindow,
      'query': query,
      'items': items.map((item) => item.toJson()).toList(growable: false),
    };
  }
}

class _TvHomeEditorialTrendItem {
  const _TvHomeEditorialTrendItem({
    required this.type,
    required this.title,
    this.tmdbId,
    this.year,
    this.rank,
  });

  factory _TvHomeEditorialTrendItem.fromJson(dynamic json) {
    if (json is! Map) return empty;
    final raw = Map<String, dynamic>.from(json);
    return _TvHomeEditorialTrendItem(
      type: _normalizeType((raw['type'] ?? '').toString()),
      title: (raw['title'] ?? raw['name'] ?? '').toString().trim(),
      tmdbId: int.tryParse((raw['tmdbId'] ?? raw['tmdb_id'] ?? '').toString()),
      year: _year(raw),
      rank: _intFromJson(raw['rank']),
    );
  }

  static const empty = _TvHomeEditorialTrendItem(type: '', title: '');

  final String type;
  final String title;
  final int? tmdbId;
  final String? year;
  final int? rank;

  bool get isUsable =>
      type.isNotEmpty && title.isNotEmpty && (tmdbId == null || tmdbId! > 0);

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'title': title,
      if (tmdbId != null) 'tmdbId': tmdbId,
      if ((year ?? '').isNotEmpty) 'year': year,
      if (rank != null) 'rank': rank,
    };
  }
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

List<_TvHomeEditorialRail> _homeEditorialRails(dynamic value) {
  if (value is! List) return const <_TvHomeEditorialRail>[];
  return value
      .map(_TvHomeEditorialRail.fromJson)
      .where((rail) => rail.title.isNotEmpty || rail.subtitle.isNotEmpty)
      .toList(growable: false);
}

List<_TvHomeEditorialTrendItem> _homeEditorialTrendItems(dynamic value) {
  if (value is! List) return const <_TvHomeEditorialTrendItem>[];
  return value
      .map(_TvHomeEditorialTrendItem.fromJson)
      .where((item) => item.title.isNotEmpty || item.tmdbId != null)
      .toList(growable: false);
}

int _boundedTvCompatibilityRisk(Object? value) {
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  return (parsed ?? 0).clamp(0, 20);
}

class _PlaybackSession {
  const _PlaybackSession({
    required this.mediaUrl,
    required this.sourceType,
    required this.httpHeaders,
    this.providerId = '',
    this.quality = 'Unknown',
    this.compatibilityRisk = 0,
    this.sourceClass = '',
    this.candidateId = '',
    this.sourceFamily = '',
    this.sourcePoolGeneration = 0,
    this.mirrorGroupId,
    this.mirrorRank,
    this.sourcePoolVersion,
    this.subtitles = const <_TvSubtitle>[],
    this.p2pDescriptor,
  });

  final String mediaUrl;
  final String sourceType;
  final Map<String, String> httpHeaders;
  final String providerId;
  final String quality;
  final int compatibilityRisk;
  final String sourceClass;
  final String candidateId;
  final String sourceFamily;
  final int sourcePoolGeneration;
  final String? mirrorGroupId;
  final int? mirrorRank;
  final String? sourcePoolVersion;
  final List<_TvSubtitle> subtitles;
  final TvP2pStreamDescriptor? p2pDescriptor;

  // ignore: unused_element
  factory _PlaybackSession.fromJson(Map<String, dynamic> json) {
    return _PlaybackSession(
      mediaUrl: (json['mediaUrl'] ?? '').toString(),
      sourceType: (json['sourceType'] ?? '').toString(),
      httpHeaders: _stringMap(json['httpHeaders']),
      providerId: (json['providerId'] ?? '').toString(),
      quality: (json['quality'] ?? 'Unknown').toString(),
      compatibilityRisk: _boundedTvCompatibilityRisk(json['compatibilityRisk']),
      sourceClass: (json['sourceClass'] ?? '').toString(),
      candidateId: tvPlaybackCandidateIdentityIsSafe(
        (json['candidateId'] ?? '').toString(),
      )
          ? (json['candidateId'] ?? '').toString()
          : '',
      sourceFamily:
          tvPlaybackCandidateFamilyFromWire(json['sourceFamily'])?.wireValue ??
              '',
      sourcePoolGeneration:
          ((_intFromJson(json['sourcePoolGeneration']) ?? 0) > 0)
              ? (_intFromJson(json['sourcePoolGeneration']) ?? 0)
              : 0,
      mirrorGroupId:
          (json['mirrorGroupId'] ?? json['mirror_group_id'])?.toString(),
      mirrorRank: _intFromJson(json['mirrorRank'] ?? json['mirror_rank']),
      sourcePoolVersion:
          (json['sourcePoolVersion'] ?? json['source_pool_version'])
              ?.toString(),
      subtitles: _tvSubtitlesFromJson(json['subtitles']),
    );
  }

  VideoFormat? get videoFormatHint {
    final type = sourceType.toLowerCase();
    if (type == 'hls' || type == 'm3u8') return VideoFormat.hls;
    if (type == 'dash' || type == 'mpd') return VideoFormat.dash;
    if (type == 'ss') return VideoFormat.ss;
    return null;
  }

  String get tvMediaUrl {
    return mediaUrl;
  }

  _PlaybackSession copyWith({
    String? mediaUrl,
    String? sourceType,
    Map<String, String>? httpHeaders,
    String? providerId,
    String? quality,
    int? compatibilityRisk,
    String? sourceClass,
    String? candidateId,
    String? sourceFamily,
    int? sourcePoolGeneration,
    String? mirrorGroupId,
    int? mirrorRank,
    String? sourcePoolVersion,
    List<_TvSubtitle>? subtitles,
    TvP2pStreamDescriptor? p2pDescriptor,
  }) {
    return _PlaybackSession(
      mediaUrl: mediaUrl ?? this.mediaUrl,
      sourceType: sourceType ?? this.sourceType,
      httpHeaders: httpHeaders ?? this.httpHeaders,
      providerId: providerId ?? this.providerId,
      quality: quality ?? this.quality,
      compatibilityRisk: compatibilityRisk ?? this.compatibilityRisk,
      sourceClass: sourceClass ?? this.sourceClass,
      candidateId: candidateId ?? this.candidateId,
      sourceFamily: sourceFamily ?? this.sourceFamily,
      sourcePoolGeneration: sourcePoolGeneration ?? this.sourcePoolGeneration,
      mirrorGroupId: mirrorGroupId ?? this.mirrorGroupId,
      mirrorRank: mirrorRank ?? this.mirrorRank,
      sourcePoolVersion: sourcePoolVersion ?? this.sourcePoolVersion,
      subtitles: subtitles ?? this.subtitles,
      p2pDescriptor: p2pDescriptor ?? this.p2pDescriptor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mediaUrl': mediaUrl,
      'sourceType': sourceType,
      'httpHeaders': httpHeaders,
      'providerId': providerId,
      'quality': quality,
      'compatibilityRisk': compatibilityRisk,
      'sourceClass': sourceClass,
      if (candidateId.isNotEmpty) 'candidateId': candidateId,
      if (sourceFamily.isNotEmpty) 'sourceFamily': sourceFamily,
      if (sourcePoolGeneration > 0)
        'sourcePoolGeneration': sourcePoolGeneration,
      if ((mirrorGroupId ?? '').isNotEmpty) 'mirrorGroupId': mirrorGroupId,
      if (mirrorRank != null) 'mirrorRank': mirrorRank,
      if ((sourcePoolVersion ?? '').isNotEmpty)
        'sourcePoolVersion': sourcePoolVersion,
      'subtitles': subtitles.map((subtitle) => subtitle.toJson()).toList(),
    };
  }
}

class _TvVerifiedPlaybackSession {
  const _TvVerifiedPlaybackSession({
    required this.session,
    required this.engineId,
    required this.cachedAt,
    this.confidence = 10,
    this.successCount = 1,
    this.failureCount = 0,
  });

  final _PlaybackSession session;
  final String engineId;
  final DateTime cachedAt;
  final int confidence;
  final int successCount;
  final int failureCount;

  _TvVerifiedPlaybackSession copyWith({
    _PlaybackSession? session,
    String? engineId,
    DateTime? cachedAt,
    int? confidence,
    int? successCount,
    int? failureCount,
  }) {
    return _TvVerifiedPlaybackSession(
      session: session ?? this.session,
      engineId: engineId ?? this.engineId,
      cachedAt: cachedAt ?? this.cachedAt,
      confidence: confidence ?? this.confidence,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session': session.toJson(),
      'engineId': engineId,
      'cachedAt': cachedAt.toIso8601String(),
      'confidence': confidence,
      'successCount': successCount,
      'failureCount': failureCount,
    };
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

enum _TvDiscoverySort {
  popular,
  nowPlaying,
  topRated,
  upcoming,
  airingToday,
  onTv,
  newest,
  featured,
}

extension _TvDiscoverySortInfo on _TvDiscoverySort {
  TvLiveTvPlaylist get liveTvPlaylist {
    return switch (this) {
      _TvDiscoverySort.newest => TvLiveTvPlaylist.beta,
      _TvDiscoverySort.featured => TvLiveTvPlaylist.gamma,
      _ => TvLiveTvPlaylist.alpha,
    };
  }

  String get label {
    return switch (this) {
      _TvDiscoverySort.popular => 'Popular',
      _TvDiscoverySort.nowPlaying => 'Now Playing',
      _TvDiscoverySort.topRated => 'Top Rated',
      _TvDiscoverySort.upcoming => 'Upcoming',
      _TvDiscoverySort.airingToday => 'Airing Today',
      _TvDiscoverySort.onTv => 'On TV',
      _TvDiscoverySort.newest => 'Newest',
      _TvDiscoverySort.featured => 'Featured',
    };
  }

  String labelFor(_TvDiscoveryKind kind) {
    if (kind == _TvDiscoveryKind.liveTv) {
      return switch (this) {
        _TvDiscoverySort.newest => 'Beta',
        _TvDiscoverySort.featured => 'Gamma',
        _ => 'Alpha',
      };
    }
    if (kind == _TvDiscoveryKind.animation) {
      return switch (this) {
        _TvDiscoverySort.onTv => 'Series',
        _ => 'Movie',
      };
    }
    return label;
  }

  String get catalogSortId {
    return switch (this) {
      _TvDiscoverySort.popular => 'popular',
      _TvDiscoverySort.nowPlaying => 'now_playing',
      _TvDiscoverySort.topRated => 'top_rated',
      _TvDiscoverySort.upcoming => 'upcoming',
      _TvDiscoverySort.airingToday => 'airing_today',
      _TvDiscoverySort.onTv => 'on_tv',
      _TvDiscoverySort.newest => 'newest',
      _TvDiscoverySort.featured => 'imdbRating',
    };
  }

  String subtitleFor(_TvDiscoveryKind kind, String genre) {
    final label = labelFor(kind);
    if (genre == 'All genres' || genre == 'All countries') {
      return kind == _TvDiscoveryKind.liveTv && genre == 'All countries'
          ? '$label in all countries'
          : '$label in all genres';
    }
    return '$label in $genre';
  }
}

List<_TvDiscoverySort> _tvDiscoverySortOptionsFor(_TvDiscoveryKind kind) {
  return switch (kind) {
    _TvDiscoveryKind.movie => const [
        _TvDiscoverySort.popular,
        _TvDiscoverySort.nowPlaying,
        _TvDiscoverySort.topRated,
        _TvDiscoverySort.upcoming,
      ],
    _TvDiscoveryKind.series => const [
        _TvDiscoverySort.popular,
        _TvDiscoverySort.airingToday,
        _TvDiscoverySort.onTv,
        _TvDiscoverySort.topRated,
      ],
    _TvDiscoveryKind.animation => const [
        _TvDiscoverySort.popular,
        _TvDiscoverySort.onTv,
      ],
    _TvDiscoveryKind.liveTv => const [
        _TvDiscoverySort.popular,
        _TvDiscoverySort.newest,
        _TvDiscoverySort.featured,
      ],
  };
}

String _tvDiscoveryLaneKey(
  _TvDiscoveryKind kind,
  _TvDiscoverySort sort, {
  String genre = 'All genres',
}) {
  final normalizedGenre = genre.trim().toLowerCase();
  final base = '${kind.name}:${sort.name}';
  if (tvIsLiveTvRootFilter(genre)) return base;
  return '$base:${normalizedGenre.replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
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
    this.credibleWatched = Duration.zero,
  });

  final Duration position;
  final Duration duration;
  final Duration credibleWatched;
}

class _TvPlaybackResult {
  const _TvPlaybackResult({
    required this.season,
    required this.episode,
    required this.progress,
  });

  final int season;
  final int episode;
  final _TvPlaybackProgress progress;
}

class _TvPlaybackUnavailable {
  const _TvPlaybackUnavailable(this.message);

  final String message;
}

class _TvAuthCodeSendResult {
  const _TvAuthCodeSendResult({
    required this.expiresInSeconds,
    required this.resendCooldownSeconds,
  });

  final int expiresInSeconds;
  final int resendCooldownSeconds;
}

class _TvAuthVerificationResult {
  const _TvAuthVerificationResult({
    required this.profile,
    required this.session,
  });

  final TvAccountProfile profile;
  final TvAccountSession session;
}

class _TvAccountLibrarySnapshotResult {
  const _TvAccountLibrarySnapshotResult({
    required this.snapshot,
    required this.revision,
    required this.updatedAt,
  });

  factory _TvAccountLibrarySnapshotResult.fromJson(Map<String, dynamic> json) {
    final snapshot = json['snapshot'];
    return _TvAccountLibrarySnapshotResult(
      snapshot: snapshot is Map
          ? Map<String, Object?>.from(snapshot)
          : const <String, Object?>{},
      revision: (json['revision'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
    );
  }

  final Map<String, Object?> snapshot;
  final String revision;
  final String updatedAt;
}

class _TvAccountLibraryPushResult {
  const _TvAccountLibraryPushResult({
    required this.ok,
    required this.conflict,
    required this.revision,
    required this.snapshot,
  });

  factory _TvAccountLibraryPushResult.fromJson(Map<String, dynamic> json) {
    final snapshot = json['snapshot'];
    return _TvAccountLibraryPushResult(
      ok: json['ok'] == true,
      conflict: json['conflict'] == true,
      revision: (json['revision'] ?? '').toString(),
      snapshot: snapshot is Map ? Map<String, Object?>.from(snapshot) : null,
    );
  }

  final bool ok;
  final bool conflict;
  final String revision;
  final Map<String, Object?>? snapshot;
}

class _TvRail {
  const _TvRail(
    this.title,
    this.subtitle,
    this.items, {
    this.showRank = true,
    this.posterCards = false,
  });

  final String title;
  final String subtitle;
  final List<_TvItem> items;
  final bool showRank;
  final bool posterCards;
}

String _normalizeTvTextSize(Object? value) {
  return switch ((value ?? 'Default').toString()) {
    'Small' => 'Smaller',
    'Large' => 'Default',
    'Larger' => 'Larger',
    'Maximum' => 'Maximum',
    'Smaller' => 'Smaller',
    _ => 'Default',
  };
}

String _normalizeTvTheme(Object? value) {
  return switch ((value ?? 'System').toString()) {
    'Light' => 'Light',
    'Dark' => 'Dark',
    'Amoled Black' => 'Amoled Black',
    _ => 'System',
  };
}

String _normalizeTvAccent(Object? value) {
  return switch ((value ?? 'Green').toString()) {
    'green' || 'Green' || 'Juicr Green' => 'Green',
    'purple' || 'Purple' || 'Mono' => 'Purple',
    'ocean' || 'Ocean' => 'Ocean',
    'amber' || 'Amber' || 'Sunset' => 'Amber',
    'custom' || 'Custom' => 'Custom',
    _ => 'Green',
  };
}

int _normalizeTvAccentColor(Object? value) {
  const fallback = 0xFF9B6DFF;
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  return fallback;
}

const int kTvP2pConsentVersion = 1;
bool get kTvP2pRuntimeAvailable => TvP2pRuntimeCapability.available;
const String kTvP2pConsentPhrase = 'I UNDERSTAND';
const String kTvP2pPrioritySmartStart = 'smartStart';
const String kTvP2pPriorityQualityFirst = 'qualityFirst';
const String kTvP2pPriorityAvailabilityFirst = 'availabilityFirst';
const String kTvP2pPrioritySmallerFasterFiles = 'smallerFasterFiles';
const String kTvP2pPriorityBalanced = 'balancedQualityAvailability';

String _normalizeTvP2pPriorityMode(Object? value) {
  return switch ((value ?? kTvP2pPrioritySmartStart).toString()) {
    kTvP2pPriorityQualityFirst => kTvP2pPriorityQualityFirst,
    kTvP2pPriorityAvailabilityFirst => kTvP2pPriorityAvailabilityFirst,
    kTvP2pPrioritySmallerFasterFiles => kTvP2pPrioritySmallerFasterFiles,
    kTvP2pPriorityBalanced => kTvP2pPriorityBalanced,
    _ => kTvP2pPrioritySmartStart,
  };
}

int _normalizeTvP2pResultsPerQuality(Object? value) {
  final parsed = int.tryParse((value ?? '').toString());
  return (parsed ?? 3).clamp(1, 5).toInt();
}

int _normalizeTvP2pSizeLimitMb(Object? value) {
  final parsed = int.tryParse((value ?? '').toString());
  return (parsed ?? 0).clamp(0, 65536).toInt();
}

class _TvSettingsState {
  const _TvSettingsState({
    this.theme = 'System',
    this.accent = 'Green',
    this.customAccentColor = 0xFF9B6DFF,
    this.textSize = 'Default',
    this.motion = true,
    this.showMatureContent = false,
    this.playbackEngine = 'Auto',
    this.preferredQuality = 'Balanced',
    this.resumePrompt = true,
    this.subtitles = true,
    this.subtitleTextSize = 'Default',
    this.subtitleTextColor = 'White',
    this.subtitleBackground = 'Dim',
    this.subtitleDelayMillis = 0,
    this.subtitleId,
    this.subtitleLanguage = 'auto',
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
    this.p2pPlaybackConsentAccepted = false,
    this.p2pPlaybackConsentVersion = 0,
    this.p2pPlaybackConsentAcceptedAt,
    this.p2pPlaybackEnabled = false,
    this.p2pSourcePrioritiesEnabled = false,
    this.p2pPriorityMode = kTvP2pPrioritySmartStart,
    this.p2pResultsPerQuality = 3,
    this.p2pAvoidRiskyFormats = true,
    this.p2pSizeLimitMb = 0,
    this.leaderboardScope = 'weekly',
    this.userAddOns = const <_TvUserAddOn>[],
  });

  final String theme;
  final String accent;
  final int customAccentColor;
  final String textSize;
  final bool motion;
  final bool showMatureContent;
  final String playbackEngine;
  final String preferredQuality;
  final bool resumePrompt;
  final bool subtitles;
  final String subtitleTextSize;
  final String subtitleTextColor;
  final String subtitleBackground;
  final int subtitleDelayMillis;
  final String? subtitleId;
  final String subtitleLanguage;
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
  final bool p2pPlaybackConsentAccepted;
  final int p2pPlaybackConsentVersion;
  final String? p2pPlaybackConsentAcceptedAt;
  final bool p2pPlaybackEnabled;
  final bool p2pSourcePrioritiesEnabled;
  final String p2pPriorityMode;
  final int p2pResultsPerQuality;
  final bool p2pAvoidRiskyFormats;
  final int p2pSizeLimitMb;
  final String leaderboardScope;
  final List<_TvUserAddOn> userAddOns;

  static const int builtInSourceCount = 5;

  int get enabledBuiltInSourceCount {
    return [
      builtInCatalog,
      builtInSubtitles,
      builtInTrailers,
      builtInLiveTv,
      builtInPlayback,
    ].where((enabled) => enabled).length;
  }

  bool get hasUserAddOns => userAddOns.any((addon) => addon.enabled);
  bool get hasP2pConsent =>
      p2pPlaybackConsentAccepted &&
      p2pPlaybackConsentVersion >= kTvP2pConsentVersion;
  bool get canUseAdvancedP2p =>
      kTvP2pRuntimeAvailable && hasUserAddOns && hasP2pConsent;
  bool get p2pPlaybackActive => p2pPlaybackEnabled && canUseAdvancedP2p;
  bool get hasCatalogSource =>
      (defaultSourceConsentAccepted && (builtInCatalog || builtInLiveTv)) ||
      (addOnConsentAccepted && hasUserAddOns);
  bool get hasPlaybackSource => builtInPlayback || hasUserAddOns;
  bool get hasBuiltInSubtitleSource =>
      defaultSourceConsentAccepted || builtInSubtitles || builtInPlayback;
  bool get hasAddOnSubtitleSource => addOnConsentAccepted && hasUserAddOns;
  bool get hasSubtitleSource =>
      hasBuiltInSubtitleSource || hasAddOnSubtitleSource;
  bool get keepHistory => history;

  factory _TvSettingsState.fromJson(Map<String, dynamic> json) {
    final userAddOns = _TvUserAddOn.fromList(json['userAddOns']);
    final hasEnabledAddOns = userAddOns.any((addon) => addon.enabled);
    final p2pConsentVersion =
        int.tryParse((json['p2pPlaybackConsentVersion'] ?? '').toString()) ?? 0;
    final hasP2pConsent = json['p2pPlaybackConsentAccepted'] == true &&
        p2pConsentVersion >= kTvP2pConsentVersion;
    final p2pPlaybackEnabled = tvP2pSavedPreferenceEnabled(
      savedEnabled: json['p2pPlaybackEnabled'] == true,
      hasConsent: hasP2pConsent,
      hasEnabledAddOns: hasEnabledAddOns,
    );
    return _TvSettingsState(
      theme: _normalizeTvTheme(json['theme']),
      accent: _normalizeTvAccent(json['accent']),
      customAccentColor: _normalizeTvAccentColor(json['customAccentColor']),
      textSize: _normalizeTvTextSize(json['textSize']),
      motion: json['motion'] != false,
      showMatureContent: tvShowMatureContentFromJson(json),
      playbackEngine: (json['playbackEngine'] ?? 'Auto').toString(),
      preferredQuality: (json['preferredQuality'] ?? 'Balanced').toString(),
      resumePrompt: json['resumePrompt'] != false,
      subtitles: json['subtitles'] != false,
      subtitleTextSize: _normalizeTvSubtitleTextSize(json['subtitleTextSize']),
      subtitleTextColor: _normalizeTvSubtitleTextColor(
        json['subtitleTextColor'],
      ),
      subtitleBackground: _normalizeTvSubtitleBackground(
        json['subtitleBackground'],
      ),
      subtitleDelayMillis: _normalizeTvSubtitleDelayMillis(
        json['subtitleDelayMillis'],
      ),
      subtitleId: (json['subtitleId'] ?? '').toString().trim().isEmpty
          ? null
          : json['subtitleId'].toString().trim(),
      subtitleLanguage:
          (json['subtitleLanguage'] ?? 'auto').toString().trim().toLowerCase(),
      nextEpisode: json['nextEpisode'] != false,
      defaultSourceConsentAccepted:
          json['defaultSourceConsentAccepted'] == true,
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
      p2pPlaybackConsentAccepted: hasP2pConsent,
      p2pPlaybackConsentVersion: hasP2pConsent ? p2pConsentVersion : 0,
      p2pPlaybackConsentAcceptedAt: !hasP2pConsent
          ? null
          : (json['p2pPlaybackConsentAcceptedAt'] ?? '')
                  .toString()
                  .trim()
                  .isEmpty
              ? null
              : json['p2pPlaybackConsentAcceptedAt'].toString(),
      p2pPlaybackEnabled: p2pPlaybackEnabled,
      p2pSourcePrioritiesEnabled:
          json['p2pSourcePrioritiesEnabled'] == true && p2pPlaybackEnabled,
      p2pPriorityMode: _normalizeTvP2pPriorityMode(json['p2pPriorityMode']),
      p2pResultsPerQuality: _normalizeTvP2pResultsPerQuality(
        json['p2pResultsPerQuality'],
      ),
      p2pAvoidRiskyFormats: json['p2pAvoidRiskyFormats'] != false,
      p2pSizeLimitMb: _normalizeTvP2pSizeLimitMb(json['p2pSizeLimitMb']),
      leaderboardScope: _normalizeTvLeaderboardScope(json['leaderboardScope']),
      userAddOns: userAddOns,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'accent': accent,
      'customAccentColor': customAccentColor,
      'textSize': textSize,
      'motion': motion,
      'showMatureContent': showMatureContent,
      'playbackEngine': playbackEngine,
      'preferredQuality': preferredQuality,
      'resumePrompt': resumePrompt,
      'subtitles': subtitles,
      'subtitleTextSize': subtitleTextSize,
      'subtitleTextColor': subtitleTextColor,
      'subtitleBackground': subtitleBackground,
      'subtitleDelayMillis': subtitleDelayMillis,
      'subtitleId': subtitleId,
      'subtitleLanguage': subtitleLanguage,
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
      'p2pPlaybackConsentAccepted': p2pPlaybackConsentAccepted,
      'p2pPlaybackConsentVersion': p2pPlaybackConsentVersion,
      if (p2pPlaybackConsentAcceptedAt != null)
        'p2pPlaybackConsentAcceptedAt': p2pPlaybackConsentAcceptedAt,
      'p2pPlaybackEnabled': p2pPlaybackEnabled,
      'p2pSourcePrioritiesEnabled': p2pSourcePrioritiesEnabled,
      'p2pPriorityMode': p2pPriorityMode,
      'p2pResultsPerQuality': p2pResultsPerQuality,
      'p2pAvoidRiskyFormats': p2pAvoidRiskyFormats,
      'p2pSizeLimitMb': p2pSizeLimitMb,
      'leaderboardScope': leaderboardScope,
      'userAddOns': userAddOns.map((addon) => addon.toJson()).toList(),
    };
  }

  _TvSettingsState copyWith({
    String? theme,
    String? accent,
    int? customAccentColor,
    String? textSize,
    bool? motion,
    bool? showMatureContent,
    String? playbackEngine,
    String? preferredQuality,
    bool? resumePrompt,
    bool? subtitles,
    String? subtitleTextSize,
    String? subtitleTextColor,
    String? subtitleBackground,
    int? subtitleDelayMillis,
    String? subtitleId,
    bool clearSubtitleId = false,
    String? subtitleLanguage,
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
    bool? p2pPlaybackConsentAccepted,
    int? p2pPlaybackConsentVersion,
    String? p2pPlaybackConsentAcceptedAt,
    bool? p2pPlaybackEnabled,
    bool? p2pSourcePrioritiesEnabled,
    String? p2pPriorityMode,
    int? p2pResultsPerQuality,
    bool? p2pAvoidRiskyFormats,
    int? p2pSizeLimitMb,
    String? leaderboardScope,
    List<_TvUserAddOn>? userAddOns,
  }) {
    final nextUserAddOns = userAddOns ?? this.userAddOns;
    final nextConsentVersion =
        p2pPlaybackConsentVersion ?? this.p2pPlaybackConsentVersion;
    final nextHasConsent =
        (p2pPlaybackConsentAccepted ?? this.p2pPlaybackConsentAccepted) &&
            nextConsentVersion >= kTvP2pConsentVersion;
    final nextHasAddOns = nextUserAddOns.any((addon) => addon.enabled);
    final nextP2pPlaybackEnabled =
        (p2pPlaybackEnabled ?? this.p2pPlaybackEnabled) &&
            nextHasConsent &&
            nextHasAddOns;
    final nextP2pSourcePrioritiesEnabled =
        (p2pSourcePrioritiesEnabled ?? this.p2pSourcePrioritiesEnabled) &&
            nextP2pPlaybackEnabled;
    return _TvSettingsState(
      theme: theme ?? this.theme,
      accent: accent ?? this.accent,
      customAccentColor: customAccentColor ?? this.customAccentColor,
      textSize: textSize ?? this.textSize,
      motion: motion ?? this.motion,
      showMatureContent: showMatureContent ?? this.showMatureContent,
      playbackEngine: playbackEngine ?? this.playbackEngine,
      preferredQuality: preferredQuality ?? this.preferredQuality,
      resumePrompt: resumePrompt ?? this.resumePrompt,
      subtitles: subtitles ?? this.subtitles,
      subtitleTextSize: _normalizeTvSubtitleTextSize(
        subtitleTextSize ?? this.subtitleTextSize,
      ),
      subtitleTextColor: _normalizeTvSubtitleTextColor(
        subtitleTextColor ?? this.subtitleTextColor,
      ),
      subtitleBackground: _normalizeTvSubtitleBackground(
        subtitleBackground ?? this.subtitleBackground,
      ),
      subtitleDelayMillis: _normalizeTvSubtitleDelayMillis(
        subtitleDelayMillis ?? this.subtitleDelayMillis,
      ),
      subtitleId: clearSubtitleId ? null : subtitleId ?? this.subtitleId,
      subtitleLanguage:
          (subtitleLanguage ?? this.subtitleLanguage).trim().toLowerCase(),
      nextEpisode: nextEpisode ?? this.nextEpisode,
      defaultSourceConsentAccepted:
          defaultSourceConsentAccepted ?? this.defaultSourceConsentAccepted,
      showDefaultSourceSettings:
          showDefaultSourceSettings ?? this.showDefaultSourceSettings,
      addOnConsentAccepted: addOnConsentAccepted ?? this.addOnConsentAccepted,
      builtInCatalog: builtInCatalog ?? this.builtInCatalog,
      builtInSubtitles: builtInSubtitles ?? this.builtInSubtitles,
      builtInTrailers: builtInTrailers ?? this.builtInTrailers,
      builtInLiveTv: builtInLiveTv ?? this.builtInLiveTv,
      builtInPlayback: builtInPlayback ?? this.builtInPlayback,
      advancedControls: advancedControls ?? this.advancedControls,
      history: history ?? this.history,
      safeDiagnostics: safeDiagnostics ?? this.safeDiagnostics,
      p2pPlaybackConsentAccepted: nextHasConsent,
      p2pPlaybackConsentVersion: nextHasConsent ? nextConsentVersion : 0,
      p2pPlaybackConsentAcceptedAt: nextHasConsent
          ? p2pPlaybackConsentAcceptedAt ?? this.p2pPlaybackConsentAcceptedAt
          : null,
      p2pPlaybackEnabled: nextP2pPlaybackEnabled,
      p2pSourcePrioritiesEnabled: nextP2pSourcePrioritiesEnabled,
      p2pPriorityMode: _normalizeTvP2pPriorityMode(
        p2pPriorityMode ?? this.p2pPriorityMode,
      ),
      p2pResultsPerQuality: _normalizeTvP2pResultsPerQuality(
        p2pResultsPerQuality ?? this.p2pResultsPerQuality,
      ),
      p2pAvoidRiskyFormats: p2pAvoidRiskyFormats ?? this.p2pAvoidRiskyFormats,
      p2pSizeLimitMb: _normalizeTvP2pSizeLimitMb(
        p2pSizeLimitMb ?? this.p2pSizeLimitMb,
      ),
      leaderboardScope: _normalizeTvLeaderboardScope(
        leaderboardScope ?? this.leaderboardScope,
      ),
      userAddOns: nextUserAddOns,
    );
  }
}

String _normalizeTvLeaderboardScope(Object? value) {
  return switch ((value ?? '').toString().trim()) {
    'today' => 'today',
    'all' || 'allTime' => 'all',
    'weekly' => 'weekly',
    _ => 'weekly',
  };
}

String _normalizeTvSubtitleTextSize(Object? value) {
  return switch ((value ?? '').toString().trim()) {
    'Small' => 'Small',
    'Large' => 'Large',
    'Maximum' => 'Maximum',
    'Default' => 'Default',
    _ => 'Default',
  };
}

String _normalizeTvSubtitleTextColor(Object? value) {
  return switch ((value ?? '').toString().trim()) {
    'Yellow' => 'Yellow',
    'Cyan' => 'Cyan',
    'Green' => 'Green',
    'White' => 'White',
    _ => 'White',
  };
}

String _normalizeTvSubtitleBackground(Object? value) {
  return switch ((value ?? '').toString().trim()) {
    'Off' => 'Off',
    'Solid' => 'Solid',
    'Dim' => 'Dim',
    _ => 'Dim',
  };
}

int _normalizeTvSubtitleDelayMillis(Object? value) {
  final parsed = int.tryParse((value ?? '').toString()) ?? 0;
  return parsed.clamp(-5000, 5000).toInt();
}

class _TvUserAddOn {
  const _TvUserAddOn({
    required this.id,
    required this.name,
    required this.manifest,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String manifest;
  final bool enabled;

  String get displayName {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.contains('://') ||
        trimmed.contains('@') ||
        trimmed.length > 48) {
      return 'Saved add-on';
    }
    final safe = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9 ._\-]'), '').trim();
    return safe.isEmpty ? 'Saved add-on' : safe;
  }

  factory _TvUserAddOn.fromJson(Map<String, dynamic> json) {
    final manifest = (json['manifest'] ?? json['manifestUrl'] ?? '').toString();
    final id = (json['id'] ?? manifest).toString();
    final name = (json['name'] ?? '').toString();
    return _TvUserAddOn(
      id: id.isEmpty ? manifest : id,
      name: name.isEmpty ? 'Saved add-on' : name,
      manifest: manifest,
      enabled: json['enabled'] != false && json['active'] != false,
    );
  }

  static List<_TvUserAddOn> fromList(Object? value) {
    if (value is! List) return const <_TvUserAddOn>[];
    return value
        .whereType<Map>()
        .map((raw) => _TvUserAddOn.fromJson(Map<String, dynamic>.from(raw)))
        .where((addon) => addon.manifest.trim().isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'manifest': manifest,
      'manifestUrl': manifest,
      'enabled': enabled,
      'active': enabled,
    };
  }

  _TvUserAddOn copyWith({
    String? id,
    String? name,
    String? manifest,
    bool? enabled,
  }) {
    return _TvUserAddOn(
      id: id ?? this.id,
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
  if (normalized == 'live' ||
      normalized == 'livetv' ||
      normalized == 'live_tv' ||
      normalized == 'channel' ||
      normalized == 'channels') {
    return 'live';
  }
  return 'movie';
}

class _TvLeaderboardResult {
  const _TvLeaderboardResult({
    required this.scope,
    required this.rows,
    required this.viewer,
  });

  factory _TvLeaderboardResult.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'];
    return _TvLeaderboardResult(
      scope: (json['scope'] ?? '').toString().trim(),
      rows: rawRows is List
          ? rawRows
              .whereType<Map>()
              .map(
                (row) => _TvLeaderboardEntry.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(growable: false)
          : const <_TvLeaderboardEntry>[],
      viewer: _TvLeaderboardViewer.fromJson(json['viewer']),
    );
  }

  final String scope;
  final List<_TvLeaderboardEntry> rows;
  final _TvLeaderboardViewer viewer;
}

class _TvLeaderboardEntry {
  const _TvLeaderboardEntry({
    required this.rank,
    required this.username,
    required this.emoji,
    required this.activeWatchSeconds,
  });

  factory _TvLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return _TvLeaderboardEntry(
      rank: _intFromJson(json['rank']) ?? 0,
      username: (json['username'] ?? '').toString().trim(),
      emoji: (json['emoji'] ?? '').toString().trim(),
      activeWatchSeconds: _intFromJson(json['activeWatchSeconds']) ?? 0,
    );
  }

  final int rank;
  final String username;
  final String emoji;
  final int activeWatchSeconds;
}

class _TvLeaderboardViewer {
  const _TvLeaderboardViewer({
    this.rank,
    required this.percentile,
    required this.activeWatchSeconds,
    required this.optedIn,
  });

  factory _TvLeaderboardViewer.fromJson(dynamic value) {
    final json = value is Map<String, dynamic>
        ? value
        : value is Map
            ? Map<String, dynamic>.from(value)
            : const <String, dynamic>{};
    final rank = _intFromJson(json['rank']);
    return _TvLeaderboardViewer(
      rank: rank != null && rank > 0 ? rank : null,
      percentile: (_intFromJson(json['percentile']) ?? 0).clamp(0, 100).toInt(),
      activeWatchSeconds: _intFromJson(json['activeWatchSeconds']) ?? 0,
      optedIn: json['optedIn'] == true,
    );
  }

  final int? rank;
  final int percentile;
  final int activeWatchSeconds;
  final bool optedIn;
}

String _normalizeItemType(dynamic rawType, String fallbackType) {
  final fallback = _normalizeType(fallbackType);
  final raw = rawType?.toString().trim();
  if (raw == null || raw.isEmpty) return fallback;
  final normalized = _normalizeType(raw);
  if (normalized == 'animation' && fallback == 'movie') return 'movie';
  return normalized;
}

String? _logoImage(dynamic value) {
  if (value is Map) {
    for (final key in const [
      'logo',
      'logos',
      'logoUrl',
      'clearLogo',
      'clear_logo',
      'titleLogo',
      'title_logo',
      'titleArt',
      'title_art',
      'url',
      'src',
      'href',
      'file_path',
      'filePath',
      'path',
    ]) {
      final image = _logoImage(value[key]);
      if (image != null) return image;
    }
    return null;
  }
  if (value is Iterable) {
    for (final item in value) {
      final image = _logoImage(item);
      if (image != null) return image;
    }
    return null;
  }
  return _image(value);
}

String? _image(dynamic value) {
  if (value is Map) {
    for (final key in const [
      'url',
      'src',
      'href',
      'image',
      'poster',
      'background',
      'backdrop',
      'file_path',
      'filePath',
      'path',
    ]) {
      final image = _image(value[key]);
      if (image != null) return image;
    }
    return null;
  }
  if (value is Iterable) {
    for (final item in value) {
      final image = _image(item);
      if (image != null) return image;
    }
    return null;
  }
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  if (text.startsWith('https://') || text.startsWith('http://')) return text;
  if (text.startsWith('//')) return 'https:$text';
  if (text.startsWith('/')) return 'https://image.tmdb.org/t/p/original$text';
  return null;
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

String? _releaseDateFromJson(Map<String, dynamic> json) {
  final raw = json['releaseDate'] ??
      json['release_date'] ??
      json['airDate'] ??
      json['firstAirDate'] ??
      json['first_air_date'] ??
      json['premiereDate'] ??
      json['premiered'] ??
      json['released'];
  final text = raw?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _isUpcomingCatalogValue(Object? value) {
  final normalized =
      value?.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return normalized != null && normalized.contains('upcoming');
}

List<String> _genreList(Map<String, dynamic> json) {
  final direct = _dedupeStringList([
    ..._stringList(json['genres']),
    ..._stringList(json['genre']),
  ]);
  if (direct.isNotEmpty) return direct;

  return _dedupeStringList([
    ..._stringList(json['categories']),
    ..._stringList(json['category']),
    ..._stringList(json['groupTitle']),
    ..._stringList(json['group_title']),
    ..._stringList(json['group']),
    ..._stringList(json['tags']),
  ]);
}

List<String> _dedupeStringList(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) continue;
    final key = trimmed.toLowerCase();
    if (key == 'all genres') continue;
    if (!seen.add(key)) continue;
    result.add(trimmed);
  }
  return result;
}

List<String> _stringList(dynamic value) {
  if (value == null) return const [];
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? const [] : <String>[trimmed];
  }
  if (value is Iterable) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

Map<String, String> _stringMap(dynamic value) {
  if (value is! Map) return const <String, String>{};
  final headers = <String, String>{};
  for (final entry in value.entries) {
    final key = entry.key?.toString().trim();
    final headerValue = entry.value?.toString().trim();
    if (key == null ||
        key.isEmpty ||
        headerValue == null ||
        headerValue.isEmpty) {
      continue;
    }
    headers[key] = headerValue;
  }
  return headers;
}

int _yearInt(String? value) {
  if (value == null || value.isEmpty) return 0;
  return int.tryParse(
        RegExp(r'(19\d{2}|20\d{2})').firstMatch(value)?.group(1) ?? value,
      ) ??
      0;
}

double _ratingDouble(String? value) {
  if (value == null || value.isEmpty) return 0;
  return double.tryParse(
        RegExp(r'\d+(\.\d+)?').firstMatch(value)?.group(0) ?? value,
      ) ??
      0;
}

int? _intFromJson(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

String _copyWithoutRepeatedTitlePhrase({
  required String title,
  required String subtitle,
}) {
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
  final hash = text.codeUnits.fold<int>(
    0,
    (value, code) => (value * 31 + code) & 0xFFFFFF,
  );
  final hue = (hash % 360).toDouble();
  return HSVColor.fromAHSV(1, hue, 0.64, 0.32).toColor();
}

String _friendlyPlaybackError(Object error) {
  if (error is _PlaybackUnavailableException) {
    return switch (error.bucket) {
      'media_timeout' => 'Playback took too long to start.',
      'media_network' => 'Playback could not reach the video right now.',
      'media_format' => 'Playback format is not ready for this TV yet.',
      _ => 'Playback is unavailable right now.',
    };
  }
  if (error is _TvApiException) {
    return switch (error.status) {
      'resolver_temporarily_limited' =>
        'Video is busy right now. Please try again shortly.',
      'resolver_timeout' => 'Playback took too long. Try another title.',
      'resolver_unavailable' =>
        'Video service is busy right now. Try again shortly.',
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
  if (message.contains('socket') || message.contains('handshake')) {
    return 'network';
  }
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
