import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_state.dart';
import 'catalog_item.dart';
import 'playback_provider.dart';

class PersonalServerApi {
  PersonalServerApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const int pageSize = 50;

  Future<List<CatalogItem>> catalog({
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? search,
  }) async {
    if (type != MediaType.movie &&
        type != MediaType.series &&
        type != MediaType.animation) {
      return const <CatalogItem>[];
    }
    final connections = AppState.personalServerConnections.value
        .where((connection) => connection.active && connection.isConfigured)
        .toList(growable: false);
    if (connections.isEmpty) return const <CatalogItem>[];
    final buckets = await Future.wait([
      for (final connection in connections)
        _catalogForConnection(
          connection,
          type: type,
          sort: sort,
          skip: skip,
          search: search,
        ).catchError((_) => const <CatalogItem>[]),
    ]);
    final items = buckets.expand((bucket) => bucket).toList(growable: false);
    final scopedItems = type == MediaType.animation
        ? items.where(_isAnimationTaggedPersonalItem).toList(growable: false)
        : items;
    return _sortItems(scopedItems, sort).take(pageSize).toList(growable: false);
  }

  Future<MetaDetails?> meta(CatalogItem item) async {
    final connection = _connectionFor(item);
    if (connection == null) return null;
    if (connection.type == PersonalServerType.plex) {
      return _plexMeta(connection, item);
    }
    return _jellyfinStyleMeta(connection, item);
  }

  Future<PlaybackResult?> playback(
    CatalogItem item, {
    int? season,
    int? episode,
  }) async {
    final connection = _connectionFor(item);
    if (connection == null) return null;
    final source = connection.type == PersonalServerType.plex
        ? await _plexPlaybackSource(connection, item)
        : await _jellyfinStylePlaybackSource(connection, item);
    if (source == null) return null;
    return PlaybackResult(
      sources: [source],
      embeds: const <PlaybackCandidate>[],
      debug: PlaybackDebug.empty,
    );
  }

  PersonalServerConnection? _connectionFor(CatalogItem item) {
    final typeId = item.personalServerTypeId?.trim();
    if (typeId == null || typeId.isEmpty) return null;
    final type = PersonalServerType.fromId(typeId);
    return AppState.personalServerConnection(type);
  }

  Future<List<CatalogItem>> _catalogForConnection(
    PersonalServerConnection connection, {
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? search,
  }) {
    return switch (connection.type) {
      PersonalServerType.plex => _plexCatalog(
        connection,
        type: type,
        sort: sort,
        skip: skip,
        search: search,
      ),
      PersonalServerType.jellyfin ||
      PersonalServerType.emby => _jellyfinStyleCatalog(
        connection,
        type: type,
        sort: sort,
        skip: skip,
        search: search,
      ),
    };
  }

  Future<List<CatalogItem>> _plexCatalog(
    PersonalServerConnection connection, {
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? search,
  }) async {
    final sections = await _plexSections(connection);
    final wantedTypes = type == MediaType.movie
        ? const {'movie'}
        : const {'show'};
    final sectionKeys = [
      for (final section in sections)
        if (wantedTypes.contains((section['type'] ?? '').toString()))
          (section['key'] ?? '').toString(),
    ].where((key) => key.isNotEmpty).toList(growable: false);
    final buckets = await Future.wait([
      for (final key in sectionKeys)
        _plexSectionItems(
          connection,
          key,
          type: type,
          skip: skip,
          search: search,
        ).catchError((_) => const <CatalogItem>[]),
    ]);
    return _sortItems(
      buckets.expand((bucket) => bucket).toList(growable: false),
      sort,
    );
  }

  Future<List<Map<String, dynamic>>> _plexSections(
    PersonalServerConnection connection,
  ) async {
    final decoded = await _getJson(
      _endpoint(
        connection.serverUrl,
        '/library/sections',
      ).replace(queryParameters: {'X-Plex-Token': connection.token}),
      headers: _plexHeaders(connection),
    );
    final directory = decoded['MediaContainer'] is Map<String, dynamic>
        ? (decoded['MediaContainer'] as Map<String, dynamic>)['Directory']
        : null;
    return _mapList(directory);
  }

  Future<List<CatalogItem>> _plexSectionItems(
    PersonalServerConnection connection,
    String sectionKey, {
    required MediaType type,
    required int skip,
    String? search,
  }) async {
    final query = <String, String>{
      'X-Plex-Token': connection.token,
      'X-Plex-Container-Start': skip.toString(),
      'X-Plex-Container-Size': pageSize.toString(),
      if ((search ?? '').trim().isNotEmpty) 'title': search!.trim(),
    };
    final decoded = await _getJson(
      _endpoint(
        connection.serverUrl,
        '/library/sections/$sectionKey/all',
      ).replace(queryParameters: query),
      headers: _plexHeaders(connection),
    );
    final rawItems = decoded['MediaContainer'] is Map<String, dynamic>
        ? (decoded['MediaContainer'] as Map<String, dynamic>)['Metadata']
        : null;
    return [
      for (final raw in _mapList(rawItems))
        _plexCatalogItem(connection, raw, type: type),
    ];
  }

  CatalogItem _plexCatalogItem(
    PersonalServerConnection connection,
    Map<String, dynamic> raw, {
    required MediaType type,
    String? seriesItemId,
  }) {
    final ratingKey = (raw['ratingKey'] ?? raw['key'] ?? '').toString();
    final title = (raw['title'] ?? raw['grandparentTitle'] ?? 'Untitled')
        .toString();
    return CatalogItem(
      type: type,
      id: 'personal:${connection.type.id}:$ratingKey',
      name: title,
      poster: _plexImageUrl(connection, raw['thumb']),
      background: _plexImageUrl(connection, raw['art']),
      year: (raw['year'] ?? raw['originallyAvailableAt'])?.toString(),
      description: (raw['summary'] ?? '').toString(),
      genres: [
        for (final genre in _mapList(raw['Genre']))
          if ((genre['tag'] ?? '').toString().isNotEmpty)
            (genre['tag'] ?? '').toString(),
      ],
      personalServerTypeId: connection.type.id,
      personalServerItemId: ratingKey,
      personalServerSeriesItemId: seriesItemId,
    );
  }

  Future<MetaDetails?> _plexMeta(
    PersonalServerConnection connection,
    CatalogItem item,
  ) async {
    if (item.type != MediaType.series && item.type != MediaType.animation) {
      return MetaDetails(item: item);
    }
    final itemId = item.personalServerItemId;
    if (itemId == null || itemId.isEmpty) return MetaDetails(item: item);
    final decoded = await _getJson(
      _endpoint(
        connection.serverUrl,
        '/library/metadata/$itemId/allLeaves',
      ).replace(queryParameters: {'X-Plex-Token': connection.token}),
      headers: _plexHeaders(connection),
    );
    final rawItems = decoded['MediaContainer'] is Map<String, dynamic>
        ? (decoded['MediaContainer'] as Map<String, dynamic>)['Metadata']
        : null;
    final episodes = [
      for (final raw in _mapList(rawItems))
        EpisodeItem(
          id: (raw['ratingKey'] ?? '').toString(),
          title: (raw['title'] ?? 'Episode').toString(),
          season: _intValue(raw['parentIndex']) ?? 1,
          episode: _intValue(raw['index']) ?? 1,
          thumbnail: _plexImageUrl(connection, raw['thumb']),
          released: raw['originallyAvailableAt']?.toString(),
          description: raw['summary']?.toString(),
        ),
    ];
    return MetaDetails(item: item, videos: episodes);
  }

  Future<PlaybackSource?> _plexPlaybackSource(
    PersonalServerConnection connection,
    CatalogItem item,
  ) async {
    final itemId = item.personalServerItemId;
    if (itemId == null || itemId.isEmpty) return null;
    final decoded = await _getJson(
      _endpoint(
        connection.serverUrl,
        '/library/metadata/$itemId',
      ).replace(queryParameters: {'X-Plex-Token': connection.token}),
      headers: _plexHeaders(connection),
    );
    final rawItems = decoded['MediaContainer'] is Map<String, dynamic>
        ? (decoded['MediaContainer'] as Map<String, dynamic>)['Metadata']
        : null;
    final rawList = _mapList(rawItems);
    final raw = rawList.isEmpty ? null : rawList.first;
    if (raw == null) return null;
    final mediaList = _mapList(raw['Media']);
    final media = mediaList.isEmpty ? null : mediaList.first;
    final partList = media == null
        ? const <Map<String, dynamic>>[]
        : _mapList(media['Part']);
    final part = partList.isEmpty ? null : partList.first;
    final key = (part?['key'] ?? '').toString();
    if (key.isEmpty) return null;
    final url = _endpoint(
      connection.serverUrl,
      key,
    ).replace(queryParameters: {'X-Plex-Token': connection.token}).toString();
    return PlaybackSource(
      providerId: 'personal-${connection.type.id}',
      name: connection.type.label,
      url: url,
      type: 'direct',
      quality: _qualityFromHeight(
        _intValue(media?['videoResolution']) ?? _intValue(media?['height']),
      ),
      sourceClass: PlaybackSourceClass.direct,
    );
  }

  Future<List<CatalogItem>> _jellyfinStyleCatalog(
    PersonalServerConnection connection, {
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? search,
  }) async {
    final includeTypes = type == MediaType.movie ? 'Movie' : 'Series';
    final query = <String, String>{
      'Recursive': 'true',
      'IncludeItemTypes': includeTypes,
      'StartIndex': skip.toString(),
      'Limit': pageSize.toString(),
      'Fields': 'Overview,Genres,PremiereDate,ProductionYear',
      if ((search ?? '').trim().isNotEmpty) 'SearchTerm': search!.trim(),
    };
    final decoded = await _getJson(
      _endpoint(
        connection.serverUrl,
        '/Users/${Uri.encodeComponent(connection.userId)}/Items',
      ).replace(queryParameters: query),
      headers: _mediaBrowserHeaders(connection),
    );
    return _sortItems([
      for (final raw in _mapList(decoded['Items']))
        _jellyfinStyleCatalogItem(connection, raw, type: type),
    ], sort);
  }

  CatalogItem _jellyfinStyleCatalogItem(
    PersonalServerConnection connection,
    Map<String, dynamic> raw, {
    required MediaType type,
  }) {
    final id = (raw['Id'] ?? '').toString();
    return CatalogItem(
      type: type,
      id: 'personal:${connection.type.id}:$id',
      name: (raw['Name'] ?? 'Untitled').toString(),
      poster: _jellyfinStyleImageUrl(connection, id, 'Primary'),
      background: _jellyfinStyleImageUrl(connection, id, 'Backdrop'),
      year: (raw['ProductionYear'] ?? raw['PremiereDate'])?.toString(),
      genres: _stringList(raw['Genres']),
      description: raw['Overview']?.toString(),
      personalServerTypeId: connection.type.id,
      personalServerItemId: id,
    );
  }

  Future<MetaDetails?> _jellyfinStyleMeta(
    PersonalServerConnection connection,
    CatalogItem item,
  ) async {
    if (item.type != MediaType.series && item.type != MediaType.animation) {
      return MetaDetails(item: item);
    }
    final itemId = item.personalServerItemId;
    if (itemId == null || itemId.isEmpty) return MetaDetails(item: item);
    final decoded = await _getJson(
      _endpoint(
        connection.serverUrl,
        '/Shows/${Uri.encodeComponent(itemId)}/Episodes',
      ).replace(
        queryParameters: {
          'UserId': connection.userId,
          'Fields': 'Overview,PremiereDate',
        },
      ),
      headers: _mediaBrowserHeaders(connection),
    );
    final episodes = [
      for (final raw in _mapList(decoded['Items']))
        EpisodeItem(
          id: (raw['Id'] ?? '').toString(),
          title: (raw['Name'] ?? 'Episode').toString(),
          season: _intValue(raw['ParentIndexNumber']) ?? 1,
          episode: _intValue(raw['IndexNumber']) ?? 1,
          thumbnail: _jellyfinStyleImageUrl(
            connection,
            (raw['Id'] ?? '').toString(),
            'Primary',
          ),
          released: raw['PremiereDate']?.toString(),
          description: raw['Overview']?.toString(),
        ),
    ];
    return MetaDetails(item: item, videos: episodes);
  }

  Future<PlaybackSource?> _jellyfinStylePlaybackSource(
    PersonalServerConnection connection,
    CatalogItem item,
  ) async {
    final itemId = item.personalServerItemId;
    if (itemId == null || itemId.isEmpty) return null;
    final url =
        _endpoint(
              connection.serverUrl,
              '/Videos/${Uri.encodeComponent(itemId)}/stream',
            )
            .replace(
              queryParameters: {'Static': 'true', 'api_key': connection.token},
            )
            .toString();
    return PlaybackSource(
      providerId: 'personal-${connection.type.id}',
      name: connection.type.label,
      url: url,
      type: 'direct',
      sourceClass: PlaybackSourceClass.direct,
      headers: _mediaBrowserHeaders(connection),
    );
  }

  Uri _endpoint(String serverUrl, String endpointPath) {
    final serverUri = Uri.parse(serverUrl);
    final basePath = serverUri.path.endsWith('/')
        ? serverUri.path.substring(0, serverUri.path.length - 1)
        : serverUri.path;
    final endpoint = endpointPath.startsWith('/')
        ? endpointPath
        : '/$endpointPath';
    return serverUri.replace(path: '$basePath$endpoint', fragment: '');
  }

  String? _plexImageUrl(PersonalServerConnection connection, Object? rawPath) {
    final path = rawPath?.toString() ?? '';
    if (path.isEmpty) return null;
    return _endpoint(
      connection.serverUrl,
      path,
    ).replace(queryParameters: {'X-Plex-Token': connection.token}).toString();
  }

  String? _jellyfinStyleImageUrl(
    PersonalServerConnection connection,
    String itemId,
    String imageType,
  ) {
    if (itemId.isEmpty) return null;
    return _endpoint(
      connection.serverUrl,
      '/Items/${Uri.encodeComponent(itemId)}/Images/$imageType',
    ).replace(queryParameters: {'api_key': connection.token}).toString();
  }

  Map<String, String> _plexHeaders(PersonalServerConnection connection) {
    return {
      'Accept': 'application/json',
      'X-Plex-Token': connection.token,
      'X-Plex-Product': 'Juicr',
      'X-Plex-Client-Identifier': 'juicr-android',
    };
  }

  Map<String, String> _mediaBrowserHeaders(
    PersonalServerConnection connection,
  ) {
    return {
      'Accept': 'application/json',
      'X-Emby-Token': connection.token,
      'Authorization':
          'MediaBrowser Client="Juicr", Device="Android", DeviceId="juicr-android", Version="1", Token="${connection.token}"',
    };
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 14));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const FormatException('Personal server request failed.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Personal server response was unexpected.');
    }
    return decoded;
  }
}

List<CatalogItem> _sortItems(List<CatalogItem> items, CatalogSort sort) {
  final sorted = items.toList(growable: false);
  sorted.sort((left, right) {
    return switch (sort) {
      CatalogSort.year => (right.year ?? '').compareTo(left.year ?? ''),
      CatalogSort.topRated ||
      CatalogSort.imdbRating ||
      CatalogSort.hiddenGems => (right.imdbRating ?? '').compareTo(
        left.imdbRating ?? '',
      ),
      CatalogSort.newest ||
      CatalogSort.nowPlaying ||
      CatalogSort.airingToday ||
      CatalogSort.onTv ||
      CatalogSort.upcoming => (right.year ?? '').compareTo(left.year ?? ''),
      CatalogSort.oldest => (left.year ?? '').compareTo(right.year ?? ''),
      CatalogSort.alphaAsc || CatalogSort.top =>
        left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      CatalogSort.alphaDesc => right.name.toLowerCase().compareTo(
        left.name.toLowerCase(),
      ),
    };
  });
  return sorted;
}

bool _isAnimationTaggedPersonalItem(CatalogItem item) {
  return item.genres.any((genre) {
    final normalized = genre.trim().toLowerCase();
    return normalized == 'animation' || normalized == 'animation';
  });
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toList();
}

int? _intValue(Object? value) {
  if (value is int) return value;
  return int.tryParse((value ?? '').toString());
}

String? _qualityFromHeight(Object? value) {
  final height = _intValue(value);
  if (height == null || height <= 0) return null;
  return '${height}P';
}
