import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'app_state.dart';
import 'catalog_item.dart';
import 'copy_normalization.dart';
import 'diagnostic_log.dart';
import 'p2p_stream_bridge.dart';
import 'personal_server_api.dart';
import 'playback_provider.dart';
import 'source_ranking.dart';

class StreamCatalogResult {
  const StreamCatalogResult({
    required this.items,
    this.skipDelta,
    this.hasMore,
  });

  final List<CatalogItem> items;
  final int? skipDelta;
  final bool? hasMore;
}

class AuthCodeSendResult {
  const AuthCodeSendResult({
    required this.expiresInSeconds,
    required this.resendCooldownSeconds,
  });

  final int expiresInSeconds;
  final int resendCooldownSeconds;
}

class AuthVerificationResult {
  const AuthVerificationResult({required this.profile, required this.session});

  final AccountProfile profile;
  final AccountSession session;
}

class AccountLibrarySyncSnapshotResult {
  const AccountLibrarySyncSnapshotResult({
    required this.snapshot,
    required this.updatedAt,
    required this.revision,
  });

  factory AccountLibrarySyncSnapshotResult.fromJson(Map<String, dynamic> json) {
    final snapshot = json['snapshot'];
    final updatedAt = (json['updatedAt'] ?? '').toString().trim();
    final revision = (json['revision'] ?? updatedAt).toString().trim();
    return AccountLibrarySyncSnapshotResult(
      snapshot: snapshot is Map ? Map<String, dynamic>.from(snapshot) : null,
      updatedAt: updatedAt,
      revision: revision,
    );
  }

  final Map<String, dynamic>? snapshot;
  final String updatedAt;
  final String revision;
}

class AccountLibrarySyncPushResult {
  const AccountLibrarySyncPushResult({
    required this.ok,
    required this.conflict,
    required this.snapshot,
    required this.updatedAt,
    required this.revision,
  });

  factory AccountLibrarySyncPushResult.fromJson(Map<String, dynamic> json) {
    final snapshot = json['snapshot'];
    final updatedAt = (json['updatedAt'] ?? '').toString().trim();
    final revision = (json['revision'] ?? updatedAt).toString().trim();
    return AccountLibrarySyncPushResult(
      ok: json['ok'] != false,
      conflict: json['conflict'] == true,
      snapshot: snapshot is Map ? Map<String, dynamic>.from(snapshot) : null,
      updatedAt: updatedAt,
      revision: revision,
    );
  }

  final bool ok;
  final bool conflict;
  final Map<String, dynamic>? snapshot;
  final String updatedAt;
  final String revision;
}

class LeaderboardResult {
  const LeaderboardResult({
    required this.scope,
    required this.rows,
    required this.viewer,
  });

  factory LeaderboardResult.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'];
    return LeaderboardResult(
      scope: (json['scope'] ?? '').toString().trim(),
      rows: rawRows is List
          ? rawRows
                .whereType<Map>()
                .map(
                  (row) =>
                      LeaderboardEntry.fromJson(Map<String, dynamic>.from(row)),
                )
                .toList(growable: false)
          : const <LeaderboardEntry>[],
      viewer: LeaderboardViewer.fromJson(json['viewer']),
    );
  }

  final String scope;
  final List<LeaderboardEntry> rows;
  final LeaderboardViewer viewer;
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.username,
    required this.emoji,
    required this.activeWatchSeconds,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: _intValue(json['rank']) ?? 0,
      username: (json['username'] ?? '').toString().trim(),
      emoji: (json['emoji'] ?? '').toString().trim(),
      activeWatchSeconds: _intValue(json['activeWatchSeconds']) ?? 0,
    );
  }

  final int rank;
  final String username;
  final String emoji;
  final int activeWatchSeconds;
}

class LeaderboardViewer {
  const LeaderboardViewer({
    this.rank,
    required this.percentile,
    required this.activeWatchSeconds,
    required this.optedIn,
  });

  factory LeaderboardViewer.fromJson(dynamic value) {
    final json = value is Map<String, dynamic>
        ? value
        : value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    final rank = _intValue(json['rank']);
    return LeaderboardViewer(
      rank: rank != null && rank > 0 ? rank : null,
      percentile: (_intValue(json['percentile']) ?? 0).clamp(0, 100).toInt(),
      activeWatchSeconds: _intValue(json['activeWatchSeconds']) ?? 0,
      optedIn: json['optedIn'] == true,
    );
  }

  final int? rank;
  final int percentile;
  final int activeWatchSeconds;
  final bool optedIn;
}

enum _CatalogSafetyGateResult {
  keep,
  future,
  pastUpcoming,
  adult,
  noAudienceSignal,
  missingDescription,
}

class ProviderHealthSample {
  const ProviderHealthSample({
    required this.type,
    required this.id,
    this.title,
    this.year,
    this.season = 1,
    this.episode = 1,
  });

  final MediaType type;
  final String id;
  final String? title;
  final String? year;
  final int season;
  final int episode;
}

class ProviderHealthSampleCheck {
  const ProviderHealthSampleCheck({
    required this.sample,
    required this.result,
    this.providerCounts = const <String, int>{},
    this.sourceClassCounts = const <String, int>{},
    this.timedOut = false,
  });

  final ProviderHealthSample sample;
  final PlaybackResult result;
  final Map<String, int> providerCounts;
  final Map<String, int> sourceClassCounts;
  final bool timedOut;
}

class HomeEditorialEdition {
  const HomeEditorialEdition({
    required this.editionId,
    required this.editionDate,
    required this.hero,
    required this.topSignal,
    required this.todaySignal,
    required this.juicrTopSignal,
    required this.movie,
    required this.series,
    required this.animation,
  });

  factory HomeEditorialEdition.fromJson(Map<String, dynamic> json) {
    final rails = _homeEditorialRailsById(json['rails']);
    return HomeEditorialEdition(
      editionId: (json['editionId'] ?? '').toString(),
      editionDate: (json['editionDate'] ?? '').toString(),
      hero: HomeEditorialRail.fromJson(json['hero']),
      topSignal: HomeEditorialRail.fromJson(rails['topSignal']),
      todaySignal: HomeEditorialRail.fromJson(rails['todaySignal']),
      juicrTopSignal: HomeEditorialRail.fromJson(rails['juicrTopSignal']),
      movie: HomeEditorialRail.fromJson(
        rails['movieEditorial'] ?? rails['movie'],
      ),
      series: HomeEditorialRail.fromJson(
        rails['seriesEditorial'] ?? rails['series'],
      ),
      animation: HomeEditorialRail.fromJson(
        rails['animationEditorial'] ?? rails['animation'],
      ),
    );
  }

  final String editionId;
  final String editionDate;
  final HomeEditorialRail hero;
  final HomeEditorialRail topSignal;
  final HomeEditorialRail todaySignal;
  final HomeEditorialRail juicrTopSignal;
  final HomeEditorialRail movie;
  final HomeEditorialRail series;
  final HomeEditorialRail animation;

  bool get hasUsableRails =>
      hero.title.isNotEmpty ||
      topSignal.title.isNotEmpty ||
      todaySignal.title.isNotEmpty ||
      juicrTopSignal.title.isNotEmpty ||
      movie.title.isNotEmpty ||
      series.title.isNotEmpty ||
      animation.title.isNotEmpty;

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
      ],
    };
  }
}

class HomeEditorialRail {
  const HomeEditorialRail({
    required this.title,
    required this.subtitle,
    this.id = '',
    this.kind = '',
    this.genres = const <String>[],
    this.types = const <MediaType>[],
    this.sort = CatalogSort.top,
    this.perType = 4,
    this.requireGenreMatch = false,
    this.intent = '',
    this.releaseWindow = '',
    this.theme = '',
    this.seasonalWindow = '',
    this.query = '',
    this.curationKind = '',
    this.notificationHook = '',
    this.pageOneOnly = false,
    this.limit = 10,
    this.movieLimit = 5,
    this.seriesLimit = 5,
    this.items = const <HomeEditorialTrendItem>[],
  });

  factory HomeEditorialRail.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return empty;
    final route = json['route'] is Map
        ? Map<String, dynamic>.from(json['route'] as Map)
        : const <String, dynamic>{};
    final title = (json['title'] ?? '').toString().trim();
    final subtitle = (json['subtitle'] ?? '').toString().trim();
    final routeGenre = (route['genre'] ?? '').toString().trim();
    final genres = _stringList(json['genres']);
    final routeType = (route['type'] ?? '').toString().trim();
    final types = _stringList(json['types']);
    final sort = (json['sort'] ?? route['sort'] ?? '').toString();
    final query = (json['query'] ?? route['query'] ?? '').toString().trim();
    return HomeEditorialRail(
      id: (json['id'] ?? '').toString().trim(),
      kind: (json['kind'] ?? '').toString().trim(),
      title: title,
      subtitle: juicrCopyWithoutRepeatedTitlePhrase(
        title: title,
        subtitle: subtitle,
      ),
      genres: genres.isNotEmpty
          ? genres
          : routeGenre.isNotEmpty && routeGenre.toLowerCase() != 'all genres'
          ? [routeGenre]
          : const <String>[],
      types: (types.isNotEmpty ? types : [if (routeType.isNotEmpty) routeType])
          .map(_mediaTypeFromRemote)
          .whereType<MediaType>()
          .toList(growable: false),
      sort: _catalogSortFromRemote(sort),
      perType:
          int.tryParse(
            (json['perType'] ?? '').toString(),
          )?.clamp(1, 12).toInt() ??
          4,
      requireGenreMatch: json['requireGenreMatch'] == true,
      intent: (json['intent'] ?? '').toString().trim(),
      releaseWindow: (json['releaseWindow'] ?? '').toString().trim(),
      theme: (json['theme'] ?? '').toString().trim(),
      seasonalWindow: (json['seasonalWindow'] ?? '').toString().trim(),
      query: query,
      curationKind: (json['curationKind'] ?? '').toString().trim(),
      notificationHook: (json['notificationHook'] ?? '').toString().trim(),
      pageOneOnly: json['pageOneOnly'] == true,
      limit:
          int.tryParse(
            (json['limit'] ?? '').toString(),
          )?.clamp(1, 20).toInt() ??
          10,
      movieLimit:
          int.tryParse(
            (json['movieLimit'] ?? '').toString(),
          )?.clamp(1, 10).toInt() ??
          5,
      seriesLimit:
          int.tryParse(
            (json['seriesLimit'] ?? '').toString(),
          )?.clamp(1, 10).toInt() ??
          5,
      items: _homeEditorialTrendItems(json['items']),
    );
  }

  static const empty = HomeEditorialRail(title: '', subtitle: '');

  final String id;
  final String kind;
  final String title;
  final String subtitle;
  final List<String> genres;
  final List<MediaType> types;
  final CatalogSort sort;
  final int perType;
  final bool requireGenreMatch;
  final String intent;
  final String releaseWindow;
  final String theme;
  final String seasonalWindow;
  final String query;
  final String curationKind;
  final String notificationHook;
  final bool pageOneOnly;
  final int limit;
  final int movieLimit;
  final int seriesLimit;
  final List<HomeEditorialTrendItem> items;

  Map<String, dynamic> toJson({String? idOverride}) {
    return {
      'id': idOverride ?? id,
      'kind': kind,
      'title': title,
      'subtitle': subtitle,
      'genres': genres,
      'types': types.map((type) => type.compatTypeValue).toList(),
      'sort': sort.id,
      'perType': perType,
      'requireGenreMatch': requireGenreMatch,
      if (intent.isNotEmpty) 'intent': intent,
      if (releaseWindow.isNotEmpty) 'releaseWindow': releaseWindow,
      if (theme.isNotEmpty) 'theme': theme,
      if (seasonalWindow.isNotEmpty) 'seasonalWindow': seasonalWindow,
      if (query.isNotEmpty) 'query': query,
      if (curationKind.isNotEmpty) 'curationKind': curationKind,
      if (notificationHook.isNotEmpty) 'notificationHook': notificationHook,
      if (pageOneOnly) 'pageOneOnly': true,
      'limit': limit,
      'movieLimit': movieLimit,
      'seriesLimit': seriesLimit,
      if (items.isNotEmpty)
        'items': items.map((item) => item.toJson()).toList(growable: false),
      'route': {
        if (types.isNotEmpty) 'type': types.first.compatTypeValue,
        if (genres.isNotEmpty) 'genre': genres.first,
        'sort': sort.id,
        if (query.isNotEmpty) 'query': query,
      },
    };
  }
}

class HomeEditorialTrendItem {
  const HomeEditorialTrendItem({
    required this.type,
    required this.title,
    this.tmdbId,
    this.year = '',
    this.rank,
    this.genres = const <String>[],
  });

  factory HomeEditorialTrendItem.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return empty;
    return HomeEditorialTrendItem(
      type: _mediaTypeFromRemote((json['type'] ?? '').toString()),
      title: (json['title'] ?? json['name'] ?? '').toString().trim(),
      tmdbId: int.tryParse(
        (json['tmdbId'] ?? json['tmdb_id'] ?? '').toString(),
      ),
      year: (json['year'] ?? '').toString().trim(),
      rank: int.tryParse((json['rank'] ?? '').toString()),
      genres: _stringList(json['genres']),
    );
  }

  static const empty = HomeEditorialTrendItem(type: null, title: '');

  final MediaType? type;
  final String title;
  final int? tmdbId;
  final String year;
  final int? rank;
  final List<String> genres;

  bool get isUsable => type != null && title.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      if (type != null) 'type': type!.compatTypeValue,
      'title': title,
      if (tmdbId != null) 'tmdbId': tmdbId,
      if (year.isNotEmpty) 'year': year,
      if (rank != null) 'rank': rank,
      if (genres.isNotEmpty) 'genres': genres,
    };
  }
}

class NotificationPolicy {
  const NotificationPolicy({
    required this.enabled,
    required this.message,
    required this.automatic,
    required this.interstitial,
    required this.controls,
  });

  factory NotificationPolicy.fromJson(Map<String, dynamic> json) {
    return NotificationPolicy(
      enabled: json['enabled'] == true,
      message: (json['message'] ?? '').toString().trim(),
      automatic: NotificationAutomaticPolicy.fromJson(json['automatic']),
      interstitial: NotificationInterstitialPolicy.fromJson(
        json['interstitial'],
      ),
      controls: NotificationControls.fromJson(json['controls']),
    );
  }

  final bool enabled;
  final String message;
  final NotificationAutomaticPolicy automatic;
  final NotificationInterstitialPolicy interstitial;
  final NotificationControls controls;
}

class NotificationAutomaticPolicy {
  const NotificationAutomaticPolicy({
    required this.enabled,
    required this.dailyCurationEnabled,
    required this.smartSuggestionsEnabled,
    required this.interstitialCardsEnabled,
    required this.dailyCap,
    required this.quietHours,
    required this.topics,
    required this.userMetricsAllowed,
  });

  factory NotificationAutomaticPolicy.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return disabled;
    return NotificationAutomaticPolicy(
      enabled: json['enabled'] == true,
      dailyCurationEnabled: json['dailyCurationEnabled'] != false,
      smartSuggestionsEnabled: json['smartSuggestionsEnabled'] != false,
      interstitialCardsEnabled: json['interstitialCardsEnabled'] != false,
      dailyCap:
          int.tryParse(
            (json['dailyCap'] ?? '').toString(),
          )?.clamp(0, 3).toInt() ??
          0,
      quietHours: (json['quietHours'] ?? '').toString().trim(),
      topics: _stringList(json['topics']),
      userMetricsAllowed: json['userMetricsAllowed'] == true,
    );
  }

  static const disabled = NotificationAutomaticPolicy(
    enabled: false,
    dailyCurationEnabled: false,
    smartSuggestionsEnabled: false,
    interstitialCardsEnabled: false,
    dailyCap: 0,
    quietHours: '',
    topics: <String>[],
    userMetricsAllowed: false,
  );

  final bool enabled;
  final bool dailyCurationEnabled;
  final bool smartSuggestionsEnabled;
  final bool interstitialCardsEnabled;
  final int dailyCap;
  final String quietHours;
  final List<String> topics;
  final bool userMetricsAllowed;
}

class NotificationInterstitialPolicy {
  const NotificationInterstitialPolicy({
    required this.enabled,
    required this.carousel,
    required this.maxCards,
    required this.minHoursBetweenShows,
    required this.dismissible,
  });

  factory NotificationInterstitialPolicy.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return disabled;
    return NotificationInterstitialPolicy(
      enabled: json['enabled'] == true,
      carousel: json['carousel'] != false,
      maxCards:
          int.tryParse(
            (json['maxCards'] ?? '').toString(),
          )?.clamp(1, 8).toInt() ??
          5,
      minHoursBetweenShows:
          int.tryParse(
            (json['minHoursBetweenShows'] ?? '').toString(),
          )?.clamp(1, 168).toInt() ??
          24,
      dismissible: json['dismissible'] != false,
    );
  }

  static const disabled = NotificationInterstitialPolicy(
    enabled: false,
    carousel: true,
    maxCards: 5,
    minHoursBetweenShows: 24,
    dismissible: true,
  );

  final bool enabled;
  final bool carousel;
  final int maxCards;
  final int minHoursBetweenShows;
  final bool dismissible;
}

class NotificationControls {
  const NotificationControls({
    required this.allowedSurfaces,
    required this.requireUserOptIn,
  });

  factory NotificationControls.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return const NotificationControls(
        allowedSurfaces: <String>[],
        requireUserOptIn: true,
      );
    }
    return NotificationControls(
      allowedSurfaces: _stringList(json['allowedSurfaces']),
      requireUserOptIn: json['requireUserOptIn'] != false,
    );
  }

  final List<String> allowedSurfaces;
  final bool requireUserOptIn;

  bool allows(String surface) {
    if (allowedSurfaces.isEmpty) return true;
    return allowedSurfaces.contains(surface);
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

List<HomeEditorialTrendItem> _homeEditorialTrendItems(dynamic value) {
  if (value is! List) return const <HomeEditorialTrendItem>[];
  return value
      .map(HomeEditorialTrendItem.fromJson)
      .where((item) => item.isUsable)
      .take(20)
      .toList(growable: false);
}

MediaType? _mediaTypeFromRemote(String value) {
  for (final type in MediaType.values) {
    if (type.matchesCompatType(value)) return type;
  }
  return null;
}

CatalogSort _catalogSortFromRemote(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'imdb' ||
    'imdbrating' ||
    'imdb_rating' ||
    'rating' ||
    'best' ||
    'featured' => CatalogSort.imdbRating,
    'toprated' || 'top_rated' || 'top-rated' => CatalogSort.topRated,
    'newest' || 'latest' || 'recent' => CatalogSort.newest,
    'oldest' => CatalogSort.oldest,
    'az' || 'a_z' || 'a-z' || 'alphaasc' || 'alpha_asc' => CatalogSort.alphaAsc,
    'za' ||
    'z_a' ||
    'z-a' ||
    'alphadesc' ||
    'alpha_desc' => CatalogSort.alphaDesc,
    'nowplaying' || 'now_playing' || 'now-playing' => CatalogSort.nowPlaying,
    'airingtoday' ||
    'airing_today' ||
    'airing-today' => CatalogSort.airingToday,
    'ontv' || 'on_tv' || 'on-tv' => CatalogSort.onTv,
    'upcoming' || 'comingsoon' || 'coming_soon' => CatalogSort.upcoming,
    'hidden' ||
    'hiddengems' ||
    'hidden_gems' ||
    'hidden-gems' ||
    'obscure' ||
    'gems' => CatalogSort.hiddenGems,
    'new' || 'year' => CatalogSort.year,
    'popular' || 'top' || 'trending' => CatalogSort.top,
    _ => CatalogSort.top,
  };
}

class AddonCapabilities {
  const AddonCapabilities({
    required this.catalogTypes,
    required this.resources,
    required this.name,
    required this.description,
  });

  final String name;
  final String description;
  final Set<String> catalogTypes;
  final Set<String> resources;

  bool get supportsCatalogs => catalogTypes.isNotEmpty;

  bool get supportsStreams {
    return resources.any((resource) {
      final normalized = resource.trim().toLowerCase();
      return normalized == 'stream' || normalized == 'streams';
    });
  }

  bool get supportsMeta {
    return resources.any((resource) {
      final normalized = resource.trim().toLowerCase();
      return normalized == 'meta' || normalized == 'metadata';
    });
  }

  bool supportsCatalogType(MediaType type) {
    return catalogTypes.any(type.matchesCompatType);
  }

  bool get supportsOnlyLiveTvCatalogs {
    return supportsCatalogs &&
        catalogTypes.every(MediaType.liveTv.matchesCompatType);
  }

  bool get supportsSubtitles {
    return resources.any((resource) {
      final normalized = resource.trim().toLowerCase();
      return normalized == 'subtitles' || normalized == 'subtitle';
    });
  }

  bool get supportsTrailers {
    return resources.any((resource) {
          final normalized = resource.trim().toLowerCase();
          return normalized == 'trailers' || normalized == 'trailer';
        }) ||
        catalogTypes.any((type) {
          final normalized = type.trim().toLowerCase();
          return normalized == 'trailers' || normalized == 'trailer';
        });
  }

  List<String> get capabilityBundleLabels {
    final labels = <String>[];
    if (supportsCatalogs) labels.add('Catalogs');
    if (supportsStreams) labels.add('Streams');
    if (supportsMeta) labels.add('Details');
    if (supportsSubtitles) labels.add('Subtitles');
    if (supportsTrailers) labels.add('Trailers');
    return labels;
  }

  bool get isMixedCapabilityBundle => capabilityBundleLabels.length > 1;

  String get capabilitySummary {
    final labels = capabilityBundleLabels;
    return labels.isEmpty ? 'Needs check' : labels.join(' / ');
  }

  bool get looksTorrentOrDebrid {
    return looksTorrentLike || looksDebridLike;
  }

  bool get looksDebridLike {
    final text =
        '$name $description ${resources.join(" ")} ${catalogTypes.join(" ")}'
            .toLowerCase();
    return text.contains('debrid') ||
        text.contains('cached') ||
        text.contains('premium') ||
        text.contains('usenet');
  }

  bool get usesPlaybackFallbackLane => supportsStreams;

  bool get usesCatalogDetailsLane {
    return !usesPlaybackFallbackLane &&
        !supportsOnlyLiveTvCatalogs &&
        (supportsCatalogs || supportsMeta);
  }

  bool get looksTorrentLike {
    final text =
        '$name $description ${resources.join(" ")} ${catalogTypes.join(" ")}'
            .toLowerCase();
    return text.contains('torrent') ||
        text.contains('magnet') ||
        text.contains('infohash') ||
        text.contains('peer');
  }

  bool get looksAccountBased {
    final text = '$name $description'.toLowerCase();
    return text.contains('account') ||
        text.contains('login') ||
        text.contains('api key') ||
        text.contains('configure') ||
        text.contains('configured') ||
        text.contains('settings');
  }
}

class StreamConfig {
  const StreamConfig({
    required this.providers,
    required this.movieGenres,
    required this.seriesGenres,
    required this.animationGenres,
    this.liveTvGenres = const <String>[],
    this.liveTvCountries = const <String>[],
    this.musicGenres = const <String>[],
    this.nsfwGenres = const <String>[],
    this.addonCatalogTypes = const <String>[],
    this.addonYearsByType = const <String, List<String>>{},
    this.catalogOriginCountriesByType = const <String, List<String>>{},
    required this.years,
    required this.features,
    this.sourcePolicy = const <String, dynamic>{},
    required this.adBlock,
  });

  factory StreamConfig.fromJson(Map<String, dynamic> json) {
    return StreamConfig(
      providers: _mapList(json['providers'], ApiProvider.fromJson)
          .where((provider) => provider.enabled && provider.id.isNotEmpty)
          .toList(),
      movieGenres: _stringList(json['movieGenres']),
      seriesGenres: _stringList(json['seriesGenres']),
      animationGenres: _stringList(json['animationGenres']),
      liveTvGenres: _stringList(json['liveTvGenres']),
      liveTvCountries: _stringList(json['liveTvCountries']),
      musicGenres: _stringList(json['musicGenres']),
      nsfwGenres: _stringList(json['nsfwGenres']),
      addonCatalogTypes: _stringList(json['addonCatalogTypes']),
      addonYearsByType: _stringListMap(json['addonYearsByType']),
      catalogOriginCountriesByType: _stringListMap(
        json['catalogOriginCountriesByType'],
      ),
      years: _stringList(json['years']),
      features: json['features'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['features'] as Map<String, dynamic>)
          : const <String, dynamic>{},
      sourcePolicy: json['sourcePolicy'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(
              json['sourcePolicy'] as Map<String, dynamic>,
            )
          : const <String, dynamic>{},
      adBlock: AdBlockConfig.fromJson(json['adBlock']),
    );
  }

  final List<ApiProvider> providers;
  final List<String> movieGenres;
  final List<String> seriesGenres;
  final List<String> animationGenres;
  final List<String> liveTvGenres;
  final List<String> liveTvCountries;
  final List<String> musicGenres;
  final List<String> nsfwGenres;
  final List<String> addonCatalogTypes;
  final Map<String, List<String>> addonYearsByType;
  final Map<String, List<String>> catalogOriginCountriesByType;
  final List<String> years;
  final Map<String, dynamic> features;
  final Map<String, dynamic> sourcePolicy;
  final AdBlockConfig adBlock;

  bool supportsAddonCatalogType(MediaType type) {
    return addonCatalogTypes.any((rawType) {
      return type.matchesCompatType(rawType);
    });
  }

  List<String> addonYearsFor(MediaType type) {
    final years = <String>{};
    for (final entry in addonYearsByType.entries) {
      if (type.matchesCompatType(entry.key)) years.addAll(entry.value);
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }
}

class AdBlockConfig {
  const AdBlockConfig({
    required this.enabled,
    required this.strictMode,
    required this.blockedHosts,
  });

  factory AdBlockConfig.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return disabled;
    return AdBlockConfig(
      enabled: json['enabled'] == true,
      strictMode: json['strictMode'] == true,
      blockedHosts: _stringList(json['blockedHosts'])
          .map((host) => host.trim().toLowerCase())
          .where((host) => host.isNotEmpty)
          .toSet(),
    );
  }

  static const AdBlockConfig disabled = AdBlockConfig(
    enabled: false,
    strictMode: false,
    blockedHosts: <String>{},
  );

  final bool enabled;
  final bool strictMode;
  final Set<String> blockedHosts;
}

class RuntimeAppPolicy {
  const RuntimeAppPolicy({
    required this.schema,
    required this.features,
    required this.signedInAds,
    required this.sourcePolicy,
    required this.addonCompatibilityRules,
  });

  factory RuntimeAppPolicy.fromJson(Map<String, dynamic> json) {
    return RuntimeAppPolicy(
      schema: (json['schema'] ?? '').toString(),
      features: Map<String, dynamic>.from(json['features'] as Map? ?? const {}),
      signedInAds: Map<String, dynamic>.from(
        json['signedInAds'] as Map? ?? const {},
      ),
      sourcePolicy: Map<String, dynamic>.from(
        json['sourcePolicy'] as Map? ?? const {},
      ),
      addonCompatibilityRules: Map<String, dynamic>.from(
        json['addonCompatibilityRules'] as Map? ?? const {},
      ),
    );
  }

  final String schema;
  final Map<String, dynamic> features;
  final Map<String, dynamic> signedInAds;
  final Map<String, dynamic> sourcePolicy;
  final Map<String, dynamic> addonCompatibilityRules;

  bool get streamResourcesCanCoexist =>
      addonCompatibilityRules['streamResourcesCanCoexist'] != false;

  bool get catalogDetailsSubtitleSingleActive =>
      addonCompatibilityRules['catalogDetailsSubtitleSingleActive'] != false;

  bool get directAndAccountBackedFirst =>
      sourcePolicy['directAndAccountBackedFirst'] != false;

  bool get riskyFormatsStayClientAdaptive =>
      (sourcePolicy['riskyFormatHandling'] ?? '').toString() ==
      'client_device_adaptive';

  bool get signedInAdsResetGuestOnSignOut =>
      signedInAds['resetGuestOnSignOut'] != false;
}

class StreamApi {
  StreamApi({http.Client? client}) : _client = client ?? http.Client();

  static const String baseUrl = 'https://api.juicr.app';
  static const String subtitleLanguages = 'en,es,fr,de,pt';
  static const int pageSize = 100;
  static const int _builtInCatalogPageSize = 50;
  static const String providerHealthMovieId = '299534';
  static const String providerHealthMovieTitle = 'Avengers: Endgame';
  static const String providerHealthMovieYear = '2019';
  static const int _addonLocalSearchMaxPages = 32;
  static const int _addonLocalSearchMinMatches = 80;
  static const int _builtInYearScanMaxPages = 12;
  static const int _builtInYearScanTargetMatches = 48;
  static const int _builtInAnimationScanMaxPages = 10;
  static const int _builtInAnimationScanTargetMatches = 48;
  static const int _builtInGenreScanMaxPages = 8;
  static const int _builtInGenreScanTargetMatches = 48;
  static const String _catalogCacheSchema = 'catalog-cache-v6';
  static const int _catalogCacheLimit = 48;
  static const int _metadataCacheLimit = 160;
  static const int _recommendationsCacheLimit = 80;
  static const int _remotePlaybackBusyBackoffSeconds = 8;
  static const Duration _remoteBootstrapTimeout = Duration(seconds: 20);
  static const Duration _remotePlaybackBusyBackoff = Duration(
    seconds: _remotePlaybackBusyBackoffSeconds,
  );
  static const Map<String, String> _hostedHeaders = <String, String>{
    'user-agent': 'JuicrApp/1 Flutter',
    'x-juicr-client': 'flutter-native',
    'x-juicr-client-version': '1',
  };

  final http.Client _client;
  late final PersonalServerApi _personalServers = PersonalServerApi(
    client: _client,
  );
  static final Map<String, _AddonManifest> _addonManifestCache =
      <String, _AddonManifest>{};
  static final Map<String, List<CatalogItem>> _builtInYearScanCache =
      <String, List<CatalogItem>>{};
  static final Map<String, List<CatalogItem>> _builtInGenreScanCache =
      <String, List<CatalogItem>>{};
  static final Map<String, List<String>> _builtInYearOptionsCache =
      <String, List<String>>{};
  static final Map<String, StreamCatalogResult> _catalogCache =
      <String, StreamCatalogResult>{};
  static final Map<String, Future<StreamCatalogResult>> _catalogInFlight =
      <String, Future<StreamCatalogResult>>{};
  static final Map<String, List<String>> _catalogOriginCountriesCache =
      <String, List<String>>{};
  static final Map<String, Future<List<String>>>
  _catalogOriginCountriesInFlight = <String, Future<List<String>>>{};
  static final Map<String, MetaDetails> _metadataCache =
      <String, MetaDetails>{};
  static final Map<String, Future<MetaDetails>> _metadataInFlight =
      <String, Future<MetaDetails>>{};
  static final Map<String, List<CatalogItem>> _recommendationsCache =
      <String, List<CatalogItem>>{};
  static final Map<String, Future<List<CatalogItem>>> _recommendationsInFlight =
      <String, Future<List<CatalogItem>>>{};
  static StreamConfig? _configCache;
  static Future<StreamConfig>? _configInFlight;
  static String? _configCacheScope;
  static String? _configInFlightScope;
  static DateTime? _configCacheStoredAt;
  static final Map<String, DateTime> _remotePlaybackBusyUntilByKey =
      <String, DateTime>{};

  static StreamConfig? get cachedConfig => _configCache;

  static void clearAddonManifestCache() {
    _addonManifestCache.clear();
    _catalogCache.clear();
    _catalogInFlight.clear();
    _catalogOriginCountriesCache.clear();
    _catalogOriginCountriesInFlight.clear();
    _metadataCache.clear();
    _metadataInFlight.clear();
    _recommendationsCache.clear();
    _recommendationsInFlight.clear();
    _configCache = null;
    _configInFlight = null;
    _configCacheScope = null;
    _configInFlightScope = null;
    _configCacheStoredAt = null;
  }

  void close() {
    _client.close();
  }

  Future<http.Response> _getHosted(Uri uri) {
    return _client.get(uri, headers: _hostedHeaders);
  }

  Future<RuntimeAppPolicy?> runtimeAppPolicy() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/runtime/app-policy'), headers: _hostedHeaders)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final decoded = _decodeResponse(response, 'Runtime app policy');
      return RuntimeAppPolicy.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<AuthCodeSendResult> sendAuthCode(String email) async {
    final uri = Uri.parse('$baseUrl/auth/send-code');
    final response = await _client
        .post(
          uri,
          headers: {..._hostedHeaders, 'content-type': 'application/json'},
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = _decodeResponse(response, 'Sign-in code');
    return AuthCodeSendResult(
      expiresInSeconds: _intValue(decoded['expiresInSeconds']) ?? 600,
      resendCooldownSeconds: _intValue(decoded['resendCooldownSeconds']) ?? 60,
    );
  }

  Future<AuthVerificationResult> verifyAuthCode({
    required String email,
    required String code,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/verify-code');
    final response = await _client
        .post(
          uri,
          headers: {..._hostedHeaders, 'content-type': 'application/json'},
          body: jsonEncode({'email': email.trim(), 'code': code.trim()}),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = _decodeResponse(response, 'Sign-in verification');
    final profile = _accountProfileFromAuth(decoded['user']);
    final session = _accountSessionFromAuth(decoded['session']);
    if (profile == null || session == null || !session.isValid) {
      throw const StreamApiException('Sign-in response was incomplete.');
    }
    return AuthVerificationResult(profile: profile, session: session);
  }

  Future<AccountProfile?> refreshAuthSession(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return null;
    final uri = Uri.parse('$baseUrl/auth/session');
    final response = await _client
        .get(
          uri,
          headers: {..._hostedHeaders, 'authorization': 'Bearer $cleanToken'},
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 401) return null;
    final decoded = _decodeResponse(response, 'Account session');
    return _accountProfileFromAuth(decoded['user']);
  }

  Future<void> signOutAuthSession(String token) async {
    final cleanToken = token.trim();
    final uri = Uri.parse('$baseUrl/auth/sign-out');
    final response = await _client
        .post(
          uri,
          headers: {
            ..._hostedHeaders,
            'content-type': 'application/json',
            if (cleanToken.isNotEmpty) 'authorization': 'Bearer $cleanToken',
          },
        )
        .timeout(const Duration(seconds: 8));
    _decodeResponse(response, 'Sign out');
  }

  Future<void> syncAccountWatchMetrics({
    required String token,
    required int activeWatchSeconds,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return;
    final uri = Uri.parse('$baseUrl/account/watch-metrics');
    final response = await _client
        .post(
          uri,
          headers: {
            ..._hostedHeaders,
            'content-type': 'application/json',
            'authorization': 'Bearer $cleanToken',
          },
          body: jsonEncode({'activeWatchSeconds': max(0, activeWatchSeconds)}),
        )
        .timeout(const Duration(seconds: 8));
    _decodeResponse(response, 'Watch metrics');
  }

  Future<AccountLibrarySyncSnapshotResult?> fetchAccountLibrarySnapshot(
    String token,
  ) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return null;
    final uri = Uri.parse('$baseUrl/account/library-sync');
    final response = await _client
        .get(
          uri,
          headers: {..._hostedHeaders, 'authorization': 'Bearer $cleanToken'},
        )
        .timeout(const Duration(seconds: 8));
    final decoded = _decodeResponse(response, 'Library sync');
    return AccountLibrarySyncSnapshotResult.fromJson(decoded);
  }

  Future<AccountLibrarySyncPushResult> pushAccountLibrarySnapshot({
    required String token,
    required Map<String, dynamic> snapshot,
    String baseRevision = '',
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      return const AccountLibrarySyncPushResult(
        ok: false,
        conflict: false,
        snapshot: null,
        updatedAt: '',
        revision: '',
      );
    }
    final uri = Uri.parse('$baseUrl/account/library-sync');
    final response = await _client
        .post(
          uri,
          headers: {
            ..._hostedHeaders,
            'content-type': 'application/json',
            'authorization': 'Bearer $cleanToken',
          },
          body: jsonEncode({
            'snapshot': snapshot,
            if (baseRevision.trim().isNotEmpty)
              'baseRevision': baseRevision.trim(),
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 409) {
      final decoded = _tryDecodeObject(response.body);
      if (decoded != null && decoded['conflict'] == true) {
        return AccountLibrarySyncPushResult.fromJson(decoded);
      }
    }
    final decoded = _decodeResponse(response, 'Library sync');
    return AccountLibrarySyncPushResult.fromJson(decoded);
  }

  Future<LeaderboardResult> fetchLeaderboard({
    required String scope,
    String token = '',
  }) async {
    final uri = Uri.parse(
      '$baseUrl/leaderboard',
    ).replace(queryParameters: {'scope': scope.trim()});
    final cleanToken = token.trim();
    final response = await _client
        .get(
          uri,
          headers: {
            ..._hostedHeaders,
            if (cleanToken.isNotEmpty) 'authorization': 'Bearer $cleanToken',
          },
        )
        .timeout(const Duration(seconds: 8));
    final decoded = _decodeResponse(response, 'Leaderboard');
    return LeaderboardResult.fromJson(decoded);
  }

  Future<AccountProfile> updateAccountProfile({
    required String token,
    required String username,
    required String emoji,
    required bool leaderboardOptIn,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw const StreamApiException('Sign in again to update your profile.');
    }
    final uri = Uri.parse('$baseUrl/account/profile');
    final response = await _client
        .post(
          uri,
          headers: {
            ..._hostedHeaders,
            'content-type': 'application/json',
            'authorization': 'Bearer $cleanToken',
          },
          body: jsonEncode({
            'username': username.trim(),
            'emoji': emoji.trim(),
            'leaderboardOptIn': leaderboardOptIn,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = _decodeResponse(response, 'Account profile');
    final profile = _accountProfileFromAuth(decoded['user']);
    if (profile == null) {
      throw const StreamApiException('Account profile was not updated.');
    }
    return profile;
  }

  Future<void> deleteAccount(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw const StreamApiException('Sign in again to delete this account.');
    }
    final uri = Uri.parse('$baseUrl/account/delete');
    final response = await _client
        .post(
          uri,
          headers: {
            ..._hostedHeaders,
            'content-type': 'application/json',
            'authorization': 'Bearer $cleanToken',
          },
          body: '{}',
        )
        .timeout(const Duration(seconds: 12));
    _decodeResponse(response, 'Delete account');
  }

  Future<String> sendDiagnosticReport(String report) async {
    final uri = Uri.parse('$baseUrl/ops/diagnostics/report');
    final response = await _client
        .post(
          uri,
          headers: {..._hostedHeaders, 'content-type': 'application/json'},
          body: jsonEncode({
            'appVersion': DiagnosticLog.appVersionLabel,
            'platform': 'android',
            'report': report,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = _decodeResponse(response, 'Diagnostic report');
    final ticketId = (decoded['ticketId'] ?? '').toString().trim();
    if (ticketId.isEmpty) {
      throw const StreamApiException('Diagnostic ticket was not created.');
    }
    return ticketId;
  }

  Future<void> sendPlaybackFeedback({
    required String providerId,
    required String event,
    String? engine,
    String? mediaType,
    String? quality,
    String? sourceType,
    String? sourceClass,
    int? positionSeconds,
    int? durationSeconds,
    int? startupMs,
    int? sourceCount,
  }) async {
    if (providerId.trim().isEmpty || event.trim().isEmpty) return;
    if (providerId.trim().toLowerCase() == 'public-iptv') {
      DiagnosticLog.add(
        'playback feedback skipped provider=public-iptv event=$event reason=local-live-tv-directory',
      );
      return;
    }
    final uri = Uri.parse('$baseUrl/ops/playback-feedback');
    final remoteProviderId = _resolverProviderIdFor(providerId);
    try {
      final response = await _client
          .post(
            uri,
            headers: {..._hostedHeaders, 'content-type': 'application/json'},
            body: jsonEncode({
              'providerId': remoteProviderId,
              'event': event,
              if (engine != null && engine.isNotEmpty) 'engine': engine,
              if (mediaType != null && mediaType.isNotEmpty)
                'mediaType': mediaType,
              if (quality != null && quality.isNotEmpty) 'quality': quality,
              if (sourceType != null && sourceType.isNotEmpty)
                'sourceType': sourceType,
              if (sourceClass != null && sourceClass.isNotEmpty)
                'sourceClass': sourceClass,
              if (positionSeconds != null) 'positionSeconds': positionSeconds,
              if (durationSeconds != null) 'durationSeconds': durationSeconds,
              if (startupMs != null) 'startupMs': startupMs,
              if (sourceCount != null) 'sourceCount': sourceCount,
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        DiagnosticLog.add(
          'playback feedback rejected provider=$providerId remoteProvider=$remoteProviderId event=$event status=${response.statusCode}',
        );
      }
    } catch (error) {
      DiagnosticLog.add(
        'playback feedback failed provider=$providerId remoteProvider=$remoteProviderId event=$event error=$error',
      );
    }
  }

  Future<StreamConfig> config() async {
    final scope = _configScopeKey();
    final cached = _configCache;
    final cachedAt = _configCacheStoredAt;
    if (cached != null &&
        _configCacheScope == scope &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 15)) {
      DiagnosticLog.add(
        'config cache hit providers=${cached.providers.length} liveTvGenres=${cached.liveTvGenres.length} addonTypes=${cached.addonCatalogTypes.length}',
      );
      return cached;
    }
    final inFlight = _configInFlight;
    if (inFlight != null && _configInFlightScope == scope) {
      DiagnosticLog.add('config in-flight hit');
      return inFlight;
    }
    final future = _loadConfig(scope);
    _configInFlight = future;
    _configInFlightScope = scope;
    return future;
  }

  Future<List<String>> catalogOriginCountries({
    required MediaType type,
    required CatalogSort sort,
    String? genre,
    String? year,
    String? company,
    String? collection,
    String? search,
  }) async {
    final cacheKey = _catalogOriginCountriesCacheKey(
      type: type,
      sort: sort,
      genre: genre,
      year: year,
      company: company,
      collection: collection,
      search: search,
    );
    final cached = _catalogOriginCountriesCache[cacheKey];
    if (cached != null) {
      DiagnosticLog.add(
        'catalog origin countries cache hit type=${type.compatTypeValue} sort=${sort.id} year=${year ?? ""} genre=${genre ?? ""} count=${cached.length}',
      );
      return cached;
    }
    final inFlight = _catalogOriginCountriesInFlight[cacheKey];
    if (inFlight != null) {
      DiagnosticLog.add(
        'catalog origin countries in-flight hit type=${type.compatTypeValue} sort=${sort.id} year=${year ?? ""} genre=${genre ?? ""}',
      );
      return inFlight;
    }
    final future = _loadCatalogOriginCountries(
      cacheKey: cacheKey,
      type: type,
      sort: sort,
      genre: genre,
      year: year,
      company: company,
      collection: collection,
      search: search,
    );
    _catalogOriginCountriesInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _catalogOriginCountriesInFlight.remove(cacheKey);
    }
  }

  Future<StreamConfig> _loadConfig(String scope) async {
    final uri = Uri.parse('$baseUrl/config');
    try {
      final response = await _getHosted(uri);
      final decoded = _decodeResponse(response, 'Config');
      final addonCatalogTypes = await _addonCatalogTypes();
      if (AppState.tvSourcesEnabled.value && AppState.publicIptvEnabled.value) {
        addonCatalogTypes.add(MediaType.liveTv.compatTypeValue);
      }
      final addonMovieGenres = await _addonGenreOptions(MediaType.movie);
      final addonSeriesGenres = await _addonGenreOptions(MediaType.series);
      final addonAnimationGenres = await _addonGenreOptions(
        MediaType.animation,
      );
      final liveTvGenres = await _addonGenreOptions(MediaType.liveTv);
      final addonMusicGenres = await _addonGenreOptions(MediaType.music);
      final addonNsfwGenres = await _addonGenreOptions(MediaType.nsfw);

      final config = StreamConfig.fromJson({
        ...decoded,
        'movieGenres': _mergedGenreOptions(
          decoded['movieGenres'],
          addonMovieGenres,
        ),
        'seriesGenres': _mergedGenreOptions(
          decoded['seriesGenres'],
          addonSeriesGenres,
        ),
        'animationGenres': _mergedGenreOptions(
          decoded['animationGenres'],
          addonAnimationGenres,
        ),
        'liveTvGenres': _mergedGenreOptions(
          decoded['liveTvGenres'],
          liveTvGenres,
        ),
        'musicGenres': addonMusicGenres.toSet().toList(),
        'nsfwGenres': addonNsfwGenres.toSet().toList(),
        'addonCatalogTypes': addonCatalogTypes.toSet().toList(),
        'addonYearsByType': await _addonYearOptionsByType(),
      });
      if (config.providers.isEmpty) {
        throw const StreamApiException(
          'Config response did not include providers.',
        );
      }
      _configCache = config;
      _configCacheScope = scope;
      _configCacheStoredAt = DateTime.now();
      DiagnosticLog.add(
        'config loaded providers=${config.providers.length} liveTvGenres=${config.liveTvGenres.length} addonTypes=${config.addonCatalogTypes.length}',
      );
      return config;
    } finally {
      if (_configInFlightScope == scope) {
        _configInFlight = null;
        _configInFlightScope = null;
      }
    }
  }

  String _configScopeKey() {
    final addons =
        AppState.userAddons.value
            .where((addon) => addon.active)
            .map((addon) => '${addon.id}:${addon.manifestUrl}')
            .toList()
          ..sort();
    final personalServers =
        AppState.personalServerConnections.value
            .where((connection) => connection.active && connection.isConfigured)
            .map((connection) => connection.type.id)
            .toList()
          ..sort();
    return <String>[
      AppState.defaultCatalogEnabled.value
          ? 'default-catalog-on'
          : 'default-catalog-off',
      AppState.defaultProvidersEnabled.value
          ? 'default-providers-on'
          : 'default-providers-off',
      AppState.tvSourcesEnabled.value ? 'tv-on' : 'tv-off',
      AppState.publicIptvEnabled.value ? 'public-iptv-on' : 'public-iptv-off',
      'addons=${addons.join('|')}',
      'servers=${personalServers.join('|')}',
    ].join(';');
  }

  Future<void> refreshNativeProviderServerHealth() async {
    final uri = Uri.parse('$baseUrl/ops/providers');
    try {
      final response = await _getHosted(
        uri,
      ).timeout(const Duration(seconds: 6));
      final decoded = _decodeResponse(response, 'Playback health');
      final providers = decoded['providers'];
      if (providers is! List) return;
      var applied = 0;
      for (final raw in providers) {
        if (raw is! Map) continue;
        final providerId = (raw['providerId'] ?? raw['id'] ?? '').toString();
        final serverHealth = raw['serverHealth'];
        final health = serverHealth is Map ? serverHealth : raw;
        if (providerId.trim().isEmpty) continue;
        final serverLabel = serverHealth is Map
            ? (serverHealth['label'] ?? '').toString()
            : '';
        final rowLabel = _providerHealthLabelFromResolverRow(raw);
        final label = _isUsefulProviderHealthLabel(serverLabel)
            ? serverLabel
            : rowLabel;
        AppState.recordNativeProviderServerHealth(
          providerId: providerId,
          label: label,
          sourceCount:
              _firstInt(health, const [
                'sourceCount',
                'avgSourceCount',
                'lastSourceCount',
              ]) ??
              _firstInt(raw, const [
                'sourceCount',
                'avgSourceCount',
                'lastSourceCount',
              ]),
          responseMillis:
              _firstInt(health, const [
                'medianMs',
                'avgLatencyMs',
                'lastLatencyMs',
              ]) ??
              _firstInt(raw, const [
                'medianMs',
                'avgLatencyMs',
                'lastLatencyMs',
              ]),
        );
        applied += 1;
      }
      DiagnosticLog.add('provider server health synced providers=$applied');
    } catch (error) {
      DiagnosticLog.add('provider server health sync failed error=$error');
    }
  }

  Future<HomeEditorialEdition?> homeEditorial() async {
    try {
      final uri = Uri.parse(
        '$baseUrl/home/editorial',
      ).replace(queryParameters: {'locale': 'en'});
      final response = await _getHosted(
        uri,
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        return null;
      }
      if (decoded['degraded'] == true ||
          decoded.containsKey('fallbackReason') ||
          decoded['schema'] != 'juicr.home_editorial.v1') {
        DiagnosticLog.add('home editorial skipped reason=degraded_or_invalid');
        return null;
      }
      final editorial = HomeEditorialEdition.fromJson(decoded);
      if (!editorial.hasUsableRails) {
        DiagnosticLog.add('home editorial skipped reason=empty_rails');
        return null;
      }
      return editorial;
    } catch (error) {
      DiagnosticLog.add('home editorial unavailable reason=$error');
      return null;
    }
  }

  Future<List<String>> _loadCatalogOriginCountries({
    required String cacheKey,
    required MediaType type,
    required CatalogSort sort,
    String? genre,
    String? year,
    String? company,
    String? collection,
    String? search,
  }) async {
    final query = <String, String>{
      'type': _backendCatalogTypeFor(type),
      'sort': _sortId(sort),
    };
    final cleanGenre = genre?.trim() ?? '';
    if (cleanGenre.isNotEmpty && cleanGenre != 'All genres') {
      query['genre'] = cleanGenre;
    }
    final cleanYear = year?.trim() ?? '';
    if (RegExp(r'^\d{4}$').hasMatch(cleanYear)) {
      query['year'] = cleanYear;
    }
    _applyCatalogScope(
      query,
      type: type,
      company: company,
      collection: collection,
    );
    final cleanSearch = search?.trim() ?? '';
    if (cleanSearch.isNotEmpty) {
      query['search'] = cleanSearch;
    }
    _applyMatureCatalogPreference(query);
    final uri = Uri.parse(
      '$baseUrl/catalog/origin-countries',
    ).replace(queryParameters: query);
    final response = await _getHosted(uri).timeout(const Duration(seconds: 8));
    final decoded = _decodeResponse(response, 'Catalog origin countries');
    final countries = _stringList(decoded['countries'])
        .map((code) => code.trim().toUpperCase())
        .where((code) => RegExp(r'^[A-Z]{2}$').hasMatch(code))
        .toList(growable: false);
    _catalogOriginCountriesCache[cacheKey] = countries;
    _evictOldestCacheEntries(
      _catalogOriginCountriesCache,
      _metadataCacheLimit,
      'catalog origin countries',
    );
    DiagnosticLog.add(
      'catalog origin countries loaded type=${type.compatTypeValue} sort=${sort.id} year=${year ?? ""} genre=${genre ?? ""} count=${countries.length}',
    );
    return countries;
  }

  Future<NotificationPolicy?> notificationPolicy() async {
    try {
      final uri = Uri.parse('$baseUrl/notifications/policy');
      final response = await _getHosted(
        uri,
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        return null;
      }
      return NotificationPolicy.fromJson(decoded);
    } catch (error) {
      DiagnosticLog.add('notification policy unavailable error=$error');
      return null;
    }
  }

  Future<List<String>> _addonGenreOptions(MediaType type) async {
    final genres = <String>{};
    final activeAddons = AppState.userAddons.value.where(
      (addon) => addon.active,
    );
    for (final addon in activeAddons) {
      try {
        final manifest = await _addonManifest(addon);
        for (final catalog in manifest.catalogsFor(type)) {
          genres.addAll(catalog.extraOptions('genre'));
        }
      } catch (_) {}
    }
    final options = genres.where((genre) => genre.trim().isNotEmpty).toList()
      ..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
    DiagnosticLog.add(
      'addon catalog genre options type=${type.compatTypeValue} count=${options.length}',
    );
    return options;
  }

  List<String> _mergedGenreOptions(Object? primary, Iterable<String> extras) {
    final values = <String>{};
    for (final genre in _stringList(primary)) {
      final cleaned = genre.trim();
      if (cleaned.isNotEmpty) values.add(cleaned);
    }
    for (final genre in extras) {
      final cleaned = genre.trim();
      if (cleaned.isNotEmpty) values.add(cleaned);
    }
    final options = values.toList()
      ..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
    return options;
  }

  Future<List<String>> _addonCatalogTypes() async {
    final types = <String>{};
    final activeAddons = AppState.userAddons.value.where(
      (addon) => addon.active,
    );
    for (final addon in activeAddons) {
      try {
        final manifest = await _addonManifest(addon);
        for (final catalog in manifest.catalogs) {
          types.add(catalog.type);
        }
      } catch (_) {}
    }
    return types.toList();
  }

  Future<Map<String, List<String>>> _addonYearOptionsByType() async {
    final yearsByType = <String, Set<String>>{};
    final activeAddons = AppState.userAddons.value.where(
      (addon) => addon.active,
    );
    for (final addon in activeAddons) {
      try {
        final manifest = await _addonManifest(addon);
        for (final catalog in manifest.catalogs) {
          final label = '${catalog.id} ${catalog.name}'.toLowerCase();
          final looksYearCapable = const [
            'new',
            'recent',
            'year',
            'latest',
          ].any(label.contains);
          final yearOptions = catalog
              .extraOptions('genre')
              .where(_looksLikeYear);
          if (!looksYearCapable && yearOptions.isEmpty) continue;
          if (yearOptions.isEmpty) continue;
          yearsByType
              .putIfAbsent(catalog.type, () => <String>{})
              .addAll(yearOptions);
        }
      } catch (_) {}
    }
    return {
      for (final entry in yearsByType.entries)
        entry.key: (entry.value.toList()..sort((a, b) => b.compareTo(a))),
    };
  }

  Future<List<String>> builtInYearOptions(MediaType type) async {
    if (!AppState.defaultCatalogEnabled.value) {
      DiagnosticLog.add(
        'catalog built-in year options skipped type=${type.compatTypeValue} reason=default catalog disabled',
      );
      return const <String>[];
    }
    final cacheKey = type.compatTypeValue;
    final cachedYears = _builtInYearOptionsCache[cacheKey];
    if (cachedYears != null) return cachedYears;

    final years = <String>{};
    for (var page = 1; page <= _builtInYearScanMaxPages; page += 1) {
      try {
        final query = <String, String>{
          'type': type.compatTypeValue,
          'sort': _sortId(CatalogSort.year),
          'page': page.toString(),
        };
        final uri = Uri.parse(
          '$baseUrl/catalog',
        ).replace(queryParameters: query);
        final response = await _getHosted(uri);
        final decoded = _decodeResponse(response, 'Catalog');
        final metas = decoded['items'] ?? decoded['metas'];
        if (metas is! List) break;
        final pageItems = metas
            .whereType<Map<String, dynamic>>()
            .map(CatalogItem.fromJson)
            .where(
              (item) =>
                  _isSafeCatalogId(item, type) &&
                  !_badCatalogIds.contains(item.id),
            )
            .toList();
        if (pageItems.isEmpty) break;
        for (final item in pageItems) {
          final match = RegExp(
            r'\b(19\d{2}|20\d{2})\b',
          ).firstMatch(item.year ?? '');
          if (match != null) years.add(match.group(1)!);
        }
      } catch (error) {
        DiagnosticLog.add(
          'catalog built-in year options failed type=${type.compatTypeValue} page=$page error=$error',
        );
        break;
      }
    }

    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
    _builtInYearOptionsCache[cacheKey] = List<String>.unmodifiable(sortedYears);
    DiagnosticLog.add(
      'catalog built-in year options type=${type.compatTypeValue} count=${sortedYears.length} years=${sortedYears.take(12).join(",")}',
    );
    return sortedYears;
  }

  Future<AddonCapabilities> addonCapabilities(UserAddon addon) async {
    final manifest = await _addonManifest(addon);
    return AddonCapabilities(
      name: manifest.name,
      description: manifest.description,
      catalogTypes: manifest.catalogs
          .map((catalog) => catalog.type.trim().toLowerCase())
          .where((type) => type.isNotEmpty)
          .toSet(),
      resources: manifest.resources
          .map((resource) => resource.trim().toLowerCase())
          .where((resource) => resource.isNotEmpty)
          .toSet(),
    );
  }

  Future<ProviderHealthSampleCheck> checkNativeProviderHealthSample({
    String? customId,
  }) async {
    final normalizedId = customId?.trim() ?? '';
    final fallbackSample = ProviderHealthSample(
      type: MediaType.movie,
      id: normalizedId.isEmpty ? providerHealthMovieId : normalizedId,
      title: normalizedId.isEmpty ? providerHealthMovieTitle : null,
      year: normalizedId.isEmpty ? providerHealthMovieYear : null,
    );
    DiagnosticLog.add(
      'playback health sample resolve start id=${normalizedId.isEmpty ? 'playback-random' : normalizedId} custom=${normalizedId.isNotEmpty}',
    );
    final uri = Uri.parse('$baseUrl/resolve/health-sample').replace(
      queryParameters: {if (normalizedId.isNotEmpty) 'id': normalizedId},
    );
    try {
      final check =
          await _resolveHealthSampleOrEmpty(
            uri,
            fallbackSample: fallbackSample,
          ).timeout(
            const Duration(seconds: 4),
            onTimeout: () {
              DiagnosticLog.add(
                'playback health sample timeout after 4s id=${fallbackSample.id}: using fallback sample',
              );
              return ProviderHealthSampleCheck(
                sample: fallbackSample,
                providerCounts: const <String, int>{},
                sourceClassCounts: const <String, int>{},
                timedOut: true,
                result: const PlaybackResult(
                  sources: <PlaybackSource>[],
                  embeds: <PlaybackCandidate>[],
                  debug: PlaybackDebug.empty,
                ),
              );
            },
          );
      DiagnosticLog.add(
        'playback health sample ok type=${check.sample.type.compatTypeValue} id=${check.sample.id} sources=${check.result.sources.length} embeds=${check.result.embeds.length}',
      );
      DiagnosticLog.add(
        'playback health sample sourceClasses=${_sourceClassCountsDiagnostic(check.sourceClassCounts)}',
      );
      return check;
    } catch (error) {
      if (_isTemporaryResolverBlock(error)) {
        DiagnosticLog.add(
          'playback health sample temporarily blocked: using fallback sample',
        );
        return ProviderHealthSampleCheck(
          sample: fallbackSample,
          providerCounts: const <String, int>{},
          sourceClassCounts: const <String, int>{},
          timedOut: true,
          result: const PlaybackResult(
            sources: <PlaybackSource>[],
            embeds: <PlaybackCandidate>[],
            debug: PlaybackDebug.empty,
          ),
        );
      }
      rethrow;
    }
  }

  Future<StreamCatalogResult> catalog({
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? genre,
    String? year,
    String? originCountry,
    String? company,
    String? collection,
    String? search,
    bool deepSearch = false,
    bool preferDefaultCatalog = false,
  }) async {
    final effectivePreferDefaultCatalog =
        preferDefaultCatalog ||
        _shouldPreferDefaultCatalogForBrowse(
          sort,
          year: year,
          originCountry: originCountry,
          company: company,
          collection: collection,
        );
    final cacheKey = _catalogCacheKey(
      type: type,
      sort: sort,
      skip: skip,
      genre: genre,
      year: year,
      originCountry: originCountry,
      company: company,
      collection: collection,
      search: search,
      deepSearch: deepSearch,
      preferDefaultCatalog: effectivePreferDefaultCatalog,
    );
    final cachedCatalog = _catalogCache[cacheKey];
    if (cachedCatalog != null) {
      DiagnosticLog.add(
        'catalog cache hit type=${type.compatTypeValue} sort=${sort.id} skip=$skip year=${year ?? ""} genre=${genre ?? ""} origin=${originCountry ?? ""} search="${(search ?? '').trim()}" count=${cachedCatalog.items.length} hasMore=${cachedCatalog.hasMore ?? false}',
      );
      return cachedCatalog;
    }
    final inFlightCatalog = _catalogInFlight[cacheKey];
    if (inFlightCatalog != null) {
      DiagnosticLog.add(
        'catalog in-flight hit type=${type.compatTypeValue} sort=${sort.id} skip=$skip year=${year ?? ""} genre=${genre ?? ""} origin=${originCountry ?? ""} search="${(search ?? '').trim()}"',
      );
      return inFlightCatalog;
    }

    final future = _fetchCatalogUncached(
      cacheKey: cacheKey,
      type: type,
      sort: sort,
      skip: skip,
      genre: genre,
      year: year,
      originCountry: originCountry,
      company: company,
      collection: collection,
      search: search,
      deepSearch: deepSearch,
      preferDefaultCatalog: effectivePreferDefaultCatalog,
    );
    _catalogInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _catalogInFlight.remove(cacheKey);
    }
  }

  Future<StreamCatalogResult?> prefetchCatalogPage({
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? genre,
    String? year,
    String? originCountry,
    String? company,
    String? collection,
    String? search,
    bool deepSearch = false,
    bool preferDefaultCatalog = false,
  }) async {
    final effectivePreferDefaultCatalog =
        preferDefaultCatalog ||
        _shouldPreferDefaultCatalogForBrowse(
          sort,
          year: year,
          originCountry: originCountry,
          company: company,
          collection: collection,
        );
    final cacheKey = _catalogCacheKey(
      type: type,
      sort: sort,
      skip: skip,
      genre: genre,
      year: year,
      originCountry: originCountry,
      company: company,
      collection: collection,
      search: search,
      deepSearch: deepSearch,
      preferDefaultCatalog: effectivePreferDefaultCatalog,
    );
    if (_catalogCache.containsKey(cacheKey) ||
        _catalogInFlight.containsKey(cacheKey)) {
      return _catalogCache[cacheKey];
    }
    DiagnosticLog.add(
      'catalog prefetch scheduled type=${type.compatTypeValue} sort=${sort.id} skip=$skip genre=${genre ?? ""} search="${(search ?? '').trim()}"',
    );
    try {
      return await catalog(
        type: type,
        sort: sort,
        skip: skip,
        genre: genre,
        year: year,
        originCountry: originCountry,
        company: company,
        collection: collection,
        search: search,
        deepSearch: deepSearch,
        preferDefaultCatalog: effectivePreferDefaultCatalog,
      );
    } catch (_) {
      return null;
    }
  }

  Future<StreamCatalogResult> _fetchCatalogUncached({
    required String cacheKey,
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? genre,
    String? year,
    String? originCountry,
    String? company,
    String? collection,
    String? search,
    required bool deepSearch,
    required bool preferDefaultCatalog,
  }) async {
    final cleanedSearch = search?.trim() ?? '';
    String? defaultFallbackReason;
    final cleanYear = year?.trim();
    final hasYearFilter = cleanYear != null && cleanYear.isNotEmpty;
    final cleanGenre = genre?.trim() ?? '';
    final focusedCatalogFilter =
        cleanedSearch.isNotEmpty ||
        hasYearFilter ||
        (originCountry?.trim().isNotEmpty == true) ||
        (company?.trim().isNotEmpty == true) ||
        (collection?.trim().isNotEmpty == true) ||
        (cleanGenre.isNotEmpty &&
            cleanGenre != 'All genres' &&
            !RegExp(r'^\d{4}$').hasMatch(cleanGenre));
    final addonGenre = hasYearFilter ? cleanYear : genre;
    final personalItems = preferDefaultCatalog
        ? const <CatalogItem>[]
        : await _personalServers
              .catalog(type: type, sort: sort, skip: skip, search: search)
              .catchError((_) => const <CatalogItem>[]);
    var supplementalItems = personalItems;
    final addonResult = preferDefaultCatalog
        ? null
        : await _addonCatalog(
            type: type,
            sort: sort,
            skip: skip,
            genre: addonGenre,
            search: search,
            deepSearch: deepSearch,
          );
    if (addonResult != null) {
      if (cleanedSearch.isEmpty || addonResult.items.isNotEmpty) {
        final yearFilter =
            addonGenre != null &&
            RegExp(r'^\d{4}$').hasMatch(addonGenre.trim());
        if (cleanedSearch.isEmpty && addonResult.items.isEmpty && yearFilter) {
          defaultFallbackReason = 'addon returned no year matches';
        } else if (cleanedSearch.isEmpty &&
            yearFilter &&
            addonResult.items.any(
              (item) => !_catalogItemMatchesYear(item, addonGenre.trim()),
            )) {
          defaultFallbackReason = 'addon returned mixed years';
        } else if (cleanedSearch.isEmpty &&
            yearFilter &&
            AppState.defaultCatalogEnabled.value) {
          supplementalItems = <CatalogItem>[
            ...personalItems,
            ...addonResult.items,
          ];
          defaultFallbackReason = 'addon year results supplemented';
        } else if (cleanedSearch.isEmpty &&
            AppState.defaultCatalogEnabled.value) {
          supplementalItems = <CatalogItem>[
            ...personalItems,
            ...addonResult.items,
          ];
          defaultFallbackReason = 'addon results supplemented';
        } else {
          final mergedResult = _mergePersonalCatalogItems(
            addonResult,
            personalItems,
          );
          final safeResult = _filterCatalogResultForAdultLane(
            mergedResult,
            requestedType: type,
            sort: sort,
            focusedCatalogFilter: focusedCatalogFilter,
          );
          _storeCatalogCache(cacheKey, safeResult);
          DiagnosticLog.add(
            'catalog cache store source=addon type=${type.compatTypeValue} sort=${sort.id} skip=$skip count=${safeResult.items.length} hasMore=${safeResult.hasMore ?? false}',
          );
          return safeResult;
        }
      } else {
        defaultFallbackReason = 'addon search returned no matches';
      }
    }
    if (type == MediaType.liveTv) {
      if (!AppState.tvSourcesEnabled.value ||
          !AppState.publicIptvEnabled.value) {
        DiagnosticLog.add('catalog live tv skipped reason=tv source disabled');
        final emptyResult = _mergePersonalCatalogItems(
          const StreamCatalogResult(items: <CatalogItem>[]),
          personalItems,
        );
        _storeCatalogCache(cacheKey, emptyResult);
        return emptyResult;
      }
      final liveResult = await _builtInCatalogWithRetry(
        type: type,
        sort: sort,
        skip: skip,
        genre: genre,
        year: year,
        originCountry: originCountry,
        company: company,
        collection: collection,
        search: search,
        softFail: cleanedSearch.isNotEmpty || skip > 0,
      );
      final mergedResult = _filterCatalogResultForAdultLane(
        _mergePersonalCatalogItems(liveResult, personalItems),
        requestedType: type,
        sort: sort,
        focusedCatalogFilter: focusedCatalogFilter,
      );
      _storeCatalogCache(cacheKey, mergedResult);
      DiagnosticLog.add(
        'catalog cache store source=backend-live-tv type=${type.compatTypeValue} sort=${sort.id} skip=$skip count=${mergedResult.items.length} hasMore=${mergedResult.hasMore ?? false}',
      );
      return mergedResult;
    }
    if (!AppState.defaultCatalogEnabled.value) {
      DiagnosticLog.add(
        'catalog built-in skipped type=${type.compatTypeValue} sort=${sort.id} genre=${genre ?? ""} reason=${defaultFallbackReason ?? "default catalog disabled"}',
      );
      final emptyResult = _filterCatalogResultForAdultLane(
        _mergePersonalCatalogItems(
          const StreamCatalogResult(items: <CatalogItem>[]),
          personalItems,
        ),
        requestedType: type,
        sort: sort,
        focusedCatalogFilter: focusedCatalogFilter,
      );
      _storeCatalogCache(cacheKey, emptyResult);
      DiagnosticLog.add(
        'catalog cache store source=empty-disabled type=${type.compatTypeValue} sort=${sort.id} skip=$skip count=0 hasMore=false',
      );
      return emptyResult;
    }
    if (defaultFallbackReason != null) {
      DiagnosticLog.add(
        'catalog backend source selected type=${type.compatTypeValue} sort=${sort.id} genre=${genre ?? ""} search="$cleanedSearch" reason=$defaultFallbackReason',
      );
    }

    final result = await _builtInCatalogWithRetry(
      type: type,
      sort: sort,
      skip: skip,
      genre: genre,
      year: year,
      originCountry: originCountry,
      company: company,
      collection: collection,
      search: search,
      softFail:
          (addonResult != null && cleanedSearch.isNotEmpty) ||
          (skip > 0 && cleanedSearch.isEmpty),
    );
    final mergedResult = _filterCatalogResultForAdultLane(
      _mergePersonalCatalogItems(result, supplementalItems),
      requestedType: type,
      sort: sort,
      focusedCatalogFilter: focusedCatalogFilter,
    );
    _storeCatalogCache(cacheKey, mergedResult);
    DiagnosticLog.add(
      'catalog cache store source=builtin type=${type.compatTypeValue} sort=${sort.id} skip=$skip count=${mergedResult.items.length} hasMore=${mergedResult.hasMore ?? false}',
    );
    return mergedResult;
  }

  void _storeCatalogCache(String key, StreamCatalogResult result) {
    _catalogCache[key] = result;
    _evictOldestCacheEntries(_catalogCache, _catalogCacheLimit, 'catalog');
  }

  Future<StreamCatalogResult> _builtInCatalogWithRetry({
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? genre,
    String? year,
    String? originCountry,
    String? company,
    String? collection,
    String? search,
    required bool softFail,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 1; attempt <= 2; attempt += 1) {
      try {
        final result = await _builtInCatalog(
          type: type,
          sort: sort,
          skip: skip,
          genre: genre,
          year: year,
          originCountry: originCountry,
          company: company,
          collection: collection,
          search: search,
          softFail: softFail,
        );
        if (attempt > 1) {
          DiagnosticLog.add(
            'catalog built-in retry recovered type=${type.compatTypeValue} sort=${sort.id} skip=$skip genre=${genre ?? ""} attempt=$attempt count=${result.items.length}',
          );
        }
        return result;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt >= 2 || !_shouldRetryBuiltInCatalog(error)) rethrow;
        _dropBuiltInGenreScanCache(type: type, sort: sort, genre: genre);
        DiagnosticLog.add(
          'catalog built-in retry scheduled type=${type.compatTypeValue} sort=${sort.id} skip=$skip genre=${genre ?? ""} attempt=$attempt reason=${_builtInCatalogRetryBucket(error)}',
        );
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    Error.throwWithStackTrace(
      lastError ?? const StreamApiException('Catalog request failed.'),
      lastStackTrace ?? StackTrace.current,
    );
  }

  void _dropBuiltInGenreScanCache({
    required MediaType type,
    required CatalogSort sort,
    String? genre,
  }) {
    final normalizedGenre = (genre ?? '').trim().toLowerCase();
    if (normalizedGenre.isEmpty ||
        normalizedGenre == 'all genres' ||
        RegExp(r'^\d{4}$').hasMatch(normalizedGenre)) {
      return;
    }
    final key = '${type.compatTypeValue}:${sort.id}:$normalizedGenre';
    if (_builtInGenreScanCache.remove(key) != null) {
      DiagnosticLog.add(
        'catalog built-in genre scan cache dropped type=${type.compatTypeValue} sort=${sort.id} reason=retry',
      );
    }
  }

  bool _shouldRetryBuiltInCatalog(Object error) {
    if (error is StreamApiDisabledException) return false;
    final bucket = _builtInCatalogRetryBucket(error);
    return bucket == 'server_error' ||
        bucket == 'timeout' ||
        bucket == 'temporary_block' ||
        bucket == 'network';
  }

  String _builtInCatalogRetryBucket(Object error) {
    if (_isTemporaryResolverBlock(error)) return 'temporary_block';
    final text = error.toString().toLowerCase();
    if (text.contains('500') ||
        text.contains('502') ||
        text.contains('503') ||
        text.contains('504') ||
        text.contains('server')) {
      return 'server_error';
    }
    if (text.contains('timeout') || text.contains('timed out')) {
      return 'timeout';
    }
    if (text.contains('socket') ||
        text.contains('connection') ||
        text.contains('network')) {
      return 'network';
    }
    return 'not_retryable';
  }

  StreamCatalogResult _mergePersonalCatalogItems(
    StreamCatalogResult base,
    List<CatalogItem> personalItems,
  ) {
    if (personalItems.isEmpty) return base;
    final seen = <String>{};
    final items = <CatalogItem>[];
    for (final item in [...personalItems, ...base.items]) {
      if (seen.add('${item.type.compatTypeValue}:${item.id}')) {
        items.add(item);
      }
    }
    return StreamCatalogResult(
      items: items,
      skipDelta:
          base.skipDelta ??
          (base.items.isEmpty ? PersonalServerApi.pageSize : pageSize),
      hasMore:
          base.hasMore == true ||
          personalItems.length >= PersonalServerApi.pageSize,
    );
  }

  StreamCatalogResult _filterCatalogResultForAdultLane(
    StreamCatalogResult result, {
    required MediaType requestedType,
    required CatalogSort sort,
    required bool focusedCatalogFilter,
  }) {
    if (result.items.isEmpty) {
      return result;
    }
    final futureReleaseAllowed =
        sort == CatalogSort.upcoming || sort == CatalogSort.nowPlaying;
    final today = _todayReleaseDate();
    var removedAdult = 0;
    var removedFuture = 0;
    var removedPastUpcoming = 0;
    var removedNoAudienceSignal = 0;
    var removedMissingDescription = 0;
    final filtered = <CatalogItem>[];
    for (final item in result.items) {
      final safety = _catalogSafetyGate(
        item,
        requestedType: requestedType,
        upcomingCatalog: sort == CatalogSort.upcoming,
        futureReleaseAllowed: futureReleaseAllowed,
        focusedCatalogFilter: focusedCatalogFilter,
        today: today,
      );
      if (safety == _CatalogSafetyGateResult.pastUpcoming) {
        removedPastUpcoming++;
        continue;
      }
      if (safety == _CatalogSafetyGateResult.future) {
        removedFuture++;
        continue;
      }
      if (safety == _CatalogSafetyGateResult.adult) {
        removedAdult++;
        continue;
      }
      if (safety == _CatalogSafetyGateResult.noAudienceSignal) {
        removedNoAudienceSignal++;
        continue;
      }
      if (safety == _CatalogSafetyGateResult.missingDescription) {
        removedMissingDescription++;
        continue;
      }
      filtered.add(item);
    }
    if (filtered.length == result.items.length) return result;
    DiagnosticLog.add(
      'catalog safety gate filtered type=${requestedType.compatTypeValue} futureRemoved=$removedFuture pastUpcomingRemoved=$removedPastUpcoming adultRemoved=$removedAdult noAudienceSignalRemoved=$removedNoAudienceSignal missingDescriptionRemoved=$removedMissingDescription',
    );
    return StreamCatalogResult(
      items: filtered,
      skipDelta: result.skipDelta,
      hasMore: result.hasMore,
    );
  }

  _CatalogSafetyGateResult _catalogSafetyGate(
    CatalogItem item, {
    required MediaType requestedType,
    required bool upcomingCatalog,
    required bool futureReleaseAllowed,
    required bool focusedCatalogFilter,
    String? today,
  }) {
    final date = today ?? _todayReleaseDate();
    if (upcomingCatalog && _catalogItemHasPastReleaseDate(item, today: date)) {
      return _CatalogSafetyGateResult.pastUpcoming;
    }
    if (!futureReleaseAllowed &&
        _catalogItemHasFutureReleaseDate(item, today: date)) {
      return _CatalogSafetyGateResult.future;
    }
    if (requestedType != MediaType.nsfw && !AppState.showMatureContent.value) {
      final standardAdultAllowed = item.type != MediaType.nsfw && !item.adult;
      if (!standardAdultAllowed || item.hasMatureContentSignal) {
        return _CatalogSafetyGateResult.adult;
      }
    }
    if (!focusedCatalogFilter &&
        !upcomingCatalog &&
        !_catalogItemHasAudienceSignal(item)) {
      return _CatalogSafetyGateResult.noAudienceSignal;
    }
    if (!focusedCatalogFilter && !_catalogItemHasDescription(item)) {
      return _CatalogSafetyGateResult.missingDescription;
    }
    return _CatalogSafetyGateResult.keep;
  }

  bool _catalogItemPassesSafetyGate(
    CatalogItem item, {
    required MediaType requestedType,
    required CatalogSort sort,
    String? today,
  }) {
    return _catalogSafetyGate(
          item,
          requestedType: requestedType,
          upcomingCatalog: sort == CatalogSort.upcoming,
          futureReleaseAllowed:
              sort == CatalogSort.upcoming || sort == CatalogSort.nowPlaying,
          focusedCatalogFilter: false,
          today: today,
        ) ==
        _CatalogSafetyGateResult.keep;
  }

  bool _catalogItemHasFutureReleaseDate(CatalogItem item, {String? today}) {
    final releaseDate = item.releaseDate?.trim();
    if (releaseDate == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(releaseDate)) {
      return false;
    }
    return releaseDate.compareTo(today ?? _todayReleaseDate()) > 0;
  }

  bool _catalogItemHasPastReleaseDate(CatalogItem item, {String? today}) {
    final releaseDate = item.releaseDate?.trim();
    if (releaseDate == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(releaseDate)) {
      return false;
    }
    return releaseDate.compareTo(today ?? _todayReleaseDate()) < 0;
  }

  bool _catalogItemHasAudienceSignal(CatalogItem item) {
    if (item.type.isLive || item.isUpcoming || !item.isTmdbBackedItem) {
      return true;
    }
    final votes = item.voteCount ?? 0;
    final score = double.tryParse(item.imdbRating ?? '') ?? 0;
    return votes > 0 && score > 0;
  }

  bool _catalogItemHasDescription(CatalogItem item) {
    if (item.type.isLive || !item.isTmdbBackedItem) return true;
    return item.description?.trim().isNotEmpty == true;
  }

  String _todayReleaseDate() {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}';
  }

  String _catalogCacheKey({
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? genre,
    String? year,
    String? originCountry,
    String? company,
    String? collection,
    String? search,
    required bool deepSearch,
    required bool preferDefaultCatalog,
  }) {
    return [
      _catalogCacheSchema,
      type.compatTypeValue,
      sort.id,
      skip,
      (genre ?? '').trim(),
      (year ?? '').trim(),
      (originCountry ?? '').trim().toUpperCase(),
      (company ?? '').trim().toLowerCase(),
      (collection ?? '').trim().toLowerCase(),
      (search ?? '').trim().toLowerCase(),
      deepSearch ? 'deep' : 'shallow',
      preferDefaultCatalog ? 'default-preferred' : 'addon-preferred',
      AppState.showMatureContent.value ? 'mature-on' : 'mature-off',
      AppState.defaultCatalogEnabled.value ? 'default-on' : 'default-off',
      AppState.tvSourcesEnabled.value ? 'tv-on' : 'tv-off',
      AppState.publicIptvEnabled.value ? 'public-iptv-on' : 'public-iptv-off',
      AppState.userAddons.value
          .where((addon) => addon.active)
          .map((addon) => '${addon.name}|${addon.manifestUrl}')
          .join('||'),
      AppState.personalServerConnections.value
          .where((connection) => connection.active && connection.isConfigured)
          .map((connection) => '${connection.type.id}|${connection.serverUrl}')
          .join('||'),
    ].join('::');
  }

  String _catalogOriginCountriesCacheKey({
    required MediaType type,
    required CatalogSort sort,
    String? genre,
    String? year,
    String? company,
    String? collection,
    String? search,
  }) {
    return [
      'catalog-origin-countries-v1',
      type.compatTypeValue,
      sort.id,
      (genre ?? '').trim(),
      (year ?? '').trim(),
      (company ?? '').trim().toLowerCase(),
      (collection ?? '').trim().toLowerCase(),
      (search ?? '').trim().toLowerCase(),
      AppState.showMatureContent.value ? 'mature-on' : 'mature-off',
      AppState.defaultCatalogEnabled.value ? 'default-on' : 'default-off',
    ].join('::');
  }

  Future<StreamCatalogResult> addonCatalogOnly({
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? genre,
    String? year,
    String? search,
  }) async {
    return await _addonCatalog(
          type: type,
          sort: sort,
          skip: skip,
          genre: year?.trim().isNotEmpty == true ? year!.trim() : genre,
          search: search,
        ) ??
        const StreamCatalogResult(items: <CatalogItem>[]);
  }

  Future<StreamCatalogResult?> _addonCatalog({
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? genre,
    String? search,
    bool deepSearch = false,
  }) async {
    final activeAddons = AppState.userAddons.value
        .where((addon) => addon.active)
        .toList();
    if (activeAddons.isEmpty) return null;

    final items = <CatalogItem>[];
    var sawCatalog = false;
    var canPage = false;
    var skipDelta = 0;
    for (final addon in activeAddons) {
      try {
        final manifest = await _addonManifest(addon);
        DiagnosticLog.add(
          'addon manifest loaded addon=${addon.name} catalogs=${manifest.catalogs.map((catalog) => '${catalog.type}:${catalog.id}').join(',')}',
        );
        final catalog = manifest.catalogFor(
          type: type,
          sort: sort,
          search: search,
          genre: genre,
        );
        if (catalog == null) {
          DiagnosticLog.add(
            'addon catalog skipped addon=${addon.name} type=${type.compatTypeValue} sort=${sort.id} genre=${genre ?? ""} search="${search ?? ""}" reason=no matching catalog',
          );
          continue;
        }
        final yearFilter =
            genre != null && RegExp(r'^\d{4}$').hasMatch(genre.trim());
        final catalogYearOptions = catalog.extraOptions('genre');
        if (yearFilter && !catalogYearOptions.contains(genre.trim())) {
          DiagnosticLog.add(
            'addon catalog skipped addon=${addon.name} type=${type.compatTypeValue} sort=${sort.id} year=$genre reason=year filter unsupported',
          );
          continue;
        }
        sawCatalog = true;
        DiagnosticLog.add(
          'addon catalog selected addon=${addon.name} catalog=${catalog.type}:${catalog.id} supportsSearch=${catalog.supportsExtra('search')} supportsGenre=${catalog.supportsExtra('genre')} supportsSkip=${catalog.supportsExtra('skip')} search="${search ?? ""}"',
        );
        final cleanedSearch = search?.trim() ?? '';
        final supportsSkip = catalog.supportsExtra('skip');
        if (cleanedSearch.isNotEmpty && !catalog.supportsExtra('search')) {
          final fetchedItems = await _scanAddonCatalogForLocalSearch(
            addon: addon,
            catalog: catalog,
            type: type,
            skip: skip,
            genre: genre,
            search: cleanedSearch,
            deepSearch: deepSearch,
          );
          final filtered = fetchedItems
              .where((item) => _matchesCatalogSearch(item, cleanedSearch))
              .toList();
          DiagnosticLog.add(
            'addon catalog local search addon=${addon.name} query="$cleanedSearch" fetched=${fetchedItems.length} matched=${filtered.length}',
          );
          items.addAll(filtered);
        } else {
          final fetchedItems = await _fetchAddonCatalogItems(
            addon: addon,
            catalog: catalog,
            type: type,
            skip: skip,
            genre: genre,
            search: search,
          );
          if (supportsSkip) {
            canPage = true;
            skipDelta = max(skipDelta, fetchedItems.length);
          }
          items.addAll(fetchedItems);
        }
      } catch (error) {
        DiagnosticLog.add(
          'addon catalog failed addon=${addon.name} error=$error',
        );
      }
    }

    return sawCatalog
        ? StreamCatalogResult(
            items: items,
            skipDelta: canPage && skipDelta > 0 ? skipDelta : null,
            hasMore: canPage && skipDelta > 0,
          )
        : null;
  }

  Future<StreamCatalogResult> _builtInCatalog({
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    String? genre,
    String? year,
    String? originCountry,
    String? company,
    String? collection,
    String? search,
    required bool softFail,
  }) async {
    final cleanedSearch = search?.trim() ?? '';
    final selectedYear = year?.trim().isNotEmpty == true
        ? year!.trim()
        : genre != null && RegExp(r'^\d{4}$').hasMatch(genre.trim())
        ? genre.trim()
        : null;
    final selectedGenre =
        cleanedSearch.isEmpty &&
            genre != null &&
            genre.trim().isNotEmpty &&
            genre != 'All genres' &&
            !RegExp(r'^\d{4}$').hasMatch(genre.trim())
        ? genre.trim()
        : null;
    if (cleanedSearch.isEmpty &&
        selectedYear != null &&
        selectedGenre == null) {
      return _builtInYearCatalog(
        type: type,
        sort: sort,
        skip: skip,
        year: selectedYear,
        originCountry: originCountry,
        company: company,
        collection: collection,
        softFail: softFail,
      );
    }
    final variants = <String>[
      cleanedSearch,
      if (cleanedSearch.length > 3 && cleanedSearch.toLowerCase().endsWith('s'))
        cleanedSearch.substring(0, cleanedSearch.length - 1),
    ].where((item) => item.isNotEmpty).toList();
    final searchVariants = variants.isEmpty ? const <String>[''] : variants;
    StreamApiException? lastError;

    for (final searchVariant in searchVariants) {
      try {
        final startPage = (skip ~/ _builtInCatalogPageSize) + 1;
        const maxFilteredPageAdvances = 4;
        for (
          var page = startPage;
          page < startPage + maxFilteredPageAdvances;
          page += 1
        ) {
          final catalogType = _backendCatalogTypeFor(type);
          final query = <String, String>{
            'type': catalogType,
            'sort': _sortId(sort),
            'page': page.toString(),
          };
          _applyMatureCatalogPreference(query);
          _applyCatalogScope(
            query,
            type: type,
            company: company,
            collection: collection,
          );
          if (searchVariant.isNotEmpty) {
            query['search'] = searchVariant;
          } else {
            if (selectedYear != null) {
              query['year'] = selectedYear;
            }
            if (selectedGenre != null) {
              query['genre'] = selectedGenre;
            }
            _applyOriginCountryFilter(query, originCountry);
          }

          final uri = Uri.parse(
            '$baseUrl/catalog',
          ).replace(queryParameters: query);
          final response = await _getHosted(uri);
          final decoded = _decodeResponse(response, 'Catalog');
          final metas = decoded['items'] ?? decoded['metas'];
          if (metas is! List) {
            throw const StreamApiException(
              'Catalog response did not include items.',
            );
          }
          final rawCount = metas.length;
          final serverHasMore = decoded['hasMore'] == true;
          if (searchVariant != cleanedSearch && cleanedSearch.isNotEmpty) {
            DiagnosticLog.add(
              'catalog built-in search variant used original="$cleanedSearch" variant="$searchVariant"',
            );
          }
          final items = _catalogItemsFromMetas(metas, requestedType: type);
          if (items.isEmpty && serverHasMore && searchVariant.isEmpty) {
            DiagnosticLog.add(
              'catalog built-in filtered page advanced type=${type.compatTypeValue} sort=${sort.id} page=$page reason=empty_usable',
            );
            continue;
          }
          return StreamCatalogResult(
            items: items,
            skipDelta: (page - startPage + 1) * _builtInCatalogPageSize,
            hasMore: rawCount > 0 && serverHasMore,
          );
        }
        return StreamCatalogResult(
          items: const <CatalogItem>[],
          skipDelta: maxFilteredPageAdvances * _builtInCatalogPageSize,
          hasMore: false,
        );
      } on StreamApiException catch (error) {
        lastError = error;
        DiagnosticLog.add(
          'catalog built-in lookup failed type=${type.compatTypeValue} search="$searchVariant" error=$error',
        );
      }
    }

    if (softFail) {
      DiagnosticLog.add(
        'catalog built-in lookup soft failed type=${type.compatTypeValue} search="$cleanedSearch"',
      );
      return StreamCatalogResult(
        items: const <CatalogItem>[],
        skipDelta: _builtInCatalogPageSize,
        hasMore: skip > 0 && cleanedSearch.isEmpty,
      );
    }
    throw lastError ?? const StreamApiException('Catalog request failed.');
  }

  Future<StreamCatalogResult> _scanBuiltInGenreCatalog({
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    required String genre,
    String? year,
    String? originCountry,
    String? company,
    String? collection,
    required bool softFail,
  }) async {
    final normalizedGenre = genre.trim().toLowerCase();
    final cacheKey = [
      type.compatTypeValue,
      sort.id,
      normalizedGenre,
      (year ?? '').trim(),
      (originCountry ?? '').trim().toUpperCase(),
      (company ?? '').trim().toLowerCase(),
      (collection ?? '').trim().toLowerCase(),
    ].join(':');
    final cachedMatches = _builtInGenreScanCache[cacheKey];
    if (cachedMatches != null) {
      final pageMatches = cachedMatches
          .skip(skip)
          .take(_builtInCatalogPageSize)
          .toList();
      DiagnosticLog.add(
        'catalog built-in genre scan cache type=${type.compatTypeValue} sort=${sort.id} genre="$genre" matched=${cachedMatches.length} returned=${pageMatches.length}',
      );
      return StreamCatalogResult(
        items: pageMatches,
        skipDelta: _builtInCatalogPageSize,
        hasMore: skip + _builtInCatalogPageSize < cachedMatches.length,
      );
    }

    final matches = <CatalogItem>[];
    StreamApiException? lastError;
    final targetMatches = max(
      skip + _builtInCatalogPageSize,
      _builtInGenreScanTargetMatches,
    );
    var scanExhausted = false;
    for (
      var page = 1;
      page <= _builtInGenreScanMaxPages && matches.length < targetMatches;
      page += 1
    ) {
      try {
        final query = <String, String>{
          'type': _backendCatalogTypeFor(type),
          'sort': _sortId(sort),
          'page': page.toString(),
        };
        _applyMatureCatalogPreference(query);
        _applyCatalogScope(
          query,
          type: type,
          company: company,
          collection: collection,
        );
        _applyOriginCountryFilter(query, originCountry);
        if (year != null && year.trim().isNotEmpty) {
          query['year'] = year.trim();
        }
        final uri = Uri.parse(
          '$baseUrl/catalog',
        ).replace(queryParameters: query);
        final response = await _getHosted(uri);
        final decoded = _decodeResponse(response, 'Catalog');
        final metas = decoded['items'] ?? decoded['metas'];
        if (metas is! List) {
          throw const StreamApiException(
            'Catalog response did not include items.',
          );
        }
        final pageItems = _catalogItemsFromMetas(metas, requestedType: type);
        if (pageItems.isEmpty) {
          scanExhausted = true;
          break;
        }
        matches.addAll(
          pageItems.where(
            (item) => _catalogItemMatchesGenre(item, normalizedGenre),
          ),
        );
        if (metas.length < _builtInCatalogPageSize) {
          scanExhausted = true;
          break;
        }
      } on StreamApiException catch (error) {
        lastError = error;
        DiagnosticLog.add(
          'catalog built-in genre scan failed type=${type.compatTypeValue} sort=${sort.id} genre="$genre" page=$page error=$error',
        );
        break;
      }
    }

    final hitTarget = matches.length >= targetMatches;
    if (lastError == null && (!hitTarget || scanExhausted)) {
      _builtInGenreScanCache[cacheKey] = List<CatalogItem>.unmodifiable(
        matches,
      );
    } else if (lastError != null) {
      DiagnosticLog.add(
        'catalog built-in genre scan cache skipped type=${type.compatTypeValue} sort=${sort.id} genre="$genre" reason=scan_error',
      );
    }
    final pageMatches = matches
        .skip(skip)
        .take(_builtInCatalogPageSize)
        .toList();
    DiagnosticLog.add(
      'catalog built-in genre scan type=${type.compatTypeValue} sort=${sort.id} genre="$genre" matched=${matches.length} returned=${pageMatches.length}',
    );
    if (pageMatches.isEmpty && lastError != null && !softFail) throw lastError;
    return StreamCatalogResult(
      items: pageMatches,
      skipDelta: _builtInCatalogPageSize,
      hasMore: hitTarget || skip + _builtInCatalogPageSize < matches.length,
    );
  }

  Future<StreamCatalogResult> _builtInAnimationCatalog({
    required CatalogSort sort,
    required int skip,
    String? genre,
    String? year,
    String? originCountry,
    String? company,
    String? collection,
    String? search,
    required bool softFail,
  }) async {
    final cleanedSearch = search?.trim() ?? '';
    final selectedYear = year?.trim().isNotEmpty == true
        ? year!.trim()
        : genre != null && RegExp(r'^\d{4}$').hasMatch(genre.trim())
        ? genre.trim()
        : null;
    final targetMatches = max(
      skip + _builtInCatalogPageSize,
      _builtInAnimationScanTargetMatches,
    );
    final animationMatches = <CatalogItem>[];
    final seenIds = <String>{};
    StreamApiException? lastError;
    var exhausted = false;
    var serverHasMore = false;
    final today = _todayReleaseDate();
    final genrePasses = <String?>[
      if (cleanedSearch.isEmpty &&
          selectedYear == null &&
          (genre == null || genre == 'All genres')) ...const <String?>[
        'Animation',
        null,
      ] else if (selectedYear != null &&
          genre != null &&
          genre.trim().isNotEmpty &&
          genre != 'All genres' &&
          !RegExp(r'^\d{4}$').hasMatch(genre.trim()))
        genre.trim()
      else if (selectedYear != null)
        null
      else
        genre == 'All genres' ? null : genre,
    ];

    for (final genrePass in genrePasses) {
      for (
        var page = 1;
        page <= _builtInAnimationScanMaxPages &&
            animationMatches.length < targetMatches;
        page += 1
      ) {
        try {
          final query = <String, String>{
            'type': MediaType.animation.compatTypeValue,
            'sort': _sortId(sort),
            'page': page.toString(),
          };
          _applyMatureCatalogPreference(query);
          _applyCatalogScope(
            query,
            type: MediaType.animation,
            company: company,
            collection: collection,
          );
          if (cleanedSearch.isNotEmpty) {
            query['search'] = cleanedSearch;
          } else if (genrePass != null && genrePass.isNotEmpty) {
            query['genre'] = genrePass;
          }
          if (cleanedSearch.isEmpty && selectedYear != null) {
            query['year'] = selectedYear;
          }
          if (cleanedSearch.isEmpty) {
            _applyOriginCountryFilter(query, originCountry);
          }

          final uri = Uri.parse(
            '$baseUrl/catalog',
          ).replace(queryParameters: query);
          final response = await _getHosted(uri);
          final decoded = _decodeResponse(response, 'Catalog');
          final metas = decoded['items'] ?? decoded['metas'];
          if (metas is! List) {
            throw const StreamApiException(
              'Catalog response did not include items.',
            );
          }
          serverHasMore = decoded['hasMore'] == true;

          final pageItems = _catalogItemsFromMetas(
            metas,
            requestedType: MediaType.animation,
          );
          for (final item in pageItems) {
            if (!_catalogItemPassesSafetyGate(
              item,
              requestedType: MediaType.animation,
              sort: sort,
              today: today,
            )) {
              continue;
            }
            if (seenIds.add(item.id)) animationMatches.add(item);
          }

          if (metas.isEmpty && serverHasMore) {
            continue;
          }
          if (metas.isEmpty || !serverHasMore) {
            if (genrePass == null) exhausted = true;
            break;
          }
        } on StreamApiException catch (error) {
          lastError = error;
          DiagnosticLog.add(
            'catalog built-in animation scan failed sort=${sort.id} genre=${genrePass ?? genre ?? ""} search="$cleanedSearch" page=$page error=$error',
          );
          break;
        }
      }
      if (animationMatches.length >= targetMatches) break;
    }

    final pageMatches = animationMatches
        .skip(skip)
        .take(_builtInCatalogPageSize)
        .toList();
    DiagnosticLog.add(
      'catalog built-in animation scan sort=${sort.id} genre=${genre ?? ""} search="$cleanedSearch" matched=${animationMatches.length} returned=${pageMatches.length}',
    );
    if (pageMatches.isEmpty && lastError != null && !softFail) throw lastError;
    return StreamCatalogResult(
      items: pageMatches,
      skipDelta: _builtInCatalogPageSize,
      hasMore:
          pageMatches.isNotEmpty &&
          (serverHasMore ||
              !exhausted ||
              skip + _builtInCatalogPageSize < animationMatches.length),
    );
  }

  bool _shouldPreferDefaultCatalogForBrowse(
    CatalogSort sort, {
    String? year,
    String? originCountry,
    String? company,
    String? collection,
  }) {
    return (year != null && year.trim().isNotEmpty) ||
        (originCountry != null && originCountry.trim().isNotEmpty) ||
        (company != null && company.trim().isNotEmpty) ||
        (collection != null && collection.trim().isNotEmpty);
  }

  Future<StreamCatalogResult> _builtInYearCatalog({
    required MediaType type,
    required CatalogSort sort,
    required int skip,
    required String year,
    String? originCountry,
    String? company,
    String? collection,
    required bool softFail,
  }) async {
    final targetMatches = max(
      skip + _builtInCatalogPageSize,
      _builtInCatalogPageSize,
    );
    final matches = <CatalogItem>[];
    final seenIds = <String>{};
    StreamApiException? lastError;
    var scanExhausted = false;
    var scannedRaw = 0;
    final today = _todayReleaseDate();

    for (
      var page = 1;
      page <= _builtInYearScanMaxPages && matches.length < targetMatches;
      page += 1
    ) {
      try {
        final query = <String, String>{
          'type': type.compatTypeValue,
          'sort': _sortId(sort),
          'year': year,
          'page': page.toString(),
        };
        _applyMatureCatalogPreference(query);
        _applyCatalogScope(
          query,
          type: type,
          company: company,
          collection: collection,
        );
        _applyOriginCountryFilter(query, originCountry);
        final uri = Uri.parse(
          '$baseUrl/catalog',
        ).replace(queryParameters: query);
        final response = await _getHosted(uri);
        final decoded = _decodeResponse(response, 'Catalog');
        final metas = decoded['items'] ?? decoded['metas'];
        if (metas is! List) {
          throw const StreamApiException(
            'Catalog response did not include items.',
          );
        }
        final pageItems = _catalogItemsFromMetas(metas, requestedType: type);
        final serverHasMore = decoded['hasMore'] == true;
        scannedRaw += pageItems.length;
        if (pageItems.isEmpty) {
          if (serverHasMore) continue;
          scanExhausted = true;
          break;
        }
        for (final item in pageItems) {
          if (!_catalogItemMatchesYear(item, year)) continue;
          if (!_catalogItemPassesSafetyGate(
            item,
            requestedType: type,
            sort: sort,
            today: today,
          )) {
            continue;
          }
          if (seenIds.add('${item.type.compatTypeValue}:${item.id}')) {
            matches.add(item);
          }
        }
        if (metas.length < _builtInCatalogPageSize && !serverHasMore) {
          scanExhausted = true;
          break;
        }
      } on StreamApiException catch (error) {
        lastError = error;
        DiagnosticLog.add(
          'catalog built-in year lookup failed type=${type.compatTypeValue} sort=${sort.id} year="$year" page=$page error=$error',
        );
        break;
      }
    }

    final pageMatches = matches
        .skip(skip)
        .take(_builtInCatalogPageSize)
        .toList();
    DiagnosticLog.add(
      'catalog built-in year direct type=${type.compatTypeValue} sort=${sort.id} year="$year" raw=$scannedRaw matched=${matches.length} returned=${pageMatches.length} origin=${originCountry ?? ""}',
    );
    if (pageMatches.isEmpty && lastError != null && !softFail) throw lastError;
    final pageFilled = pageMatches.length >= _builtInCatalogPageSize;
    return StreamCatalogResult(
      items: pageMatches,
      skipDelta: _builtInCatalogPageSize,
      hasMore:
          pageFilled &&
          (!scanExhausted || skip + _builtInCatalogPageSize < matches.length),
    );
  }

  Future<StreamCatalogResult> _scanBuiltInYearCatalog({
    required MediaType type,
    required int skip,
    required String year,
    required bool softFail,
  }) async {
    final cacheKey = '${type.compatTypeValue}:$year';
    final cachedMatches = _builtInYearScanCache[cacheKey];
    if (cachedMatches != null) {
      final pageMatches = cachedMatches
          .skip(skip)
          .take(_builtInCatalogPageSize)
          .toList();
      DiagnosticLog.add(
        'catalog built-in year scan cache type=${type.compatTypeValue} year="$year" matched=${cachedMatches.length} returned=${pageMatches.length}',
      );
      return StreamCatalogResult(
        items: pageMatches,
        skipDelta: _builtInCatalogPageSize,
        hasMore: skip + _builtInCatalogPageSize < cachedMatches.length,
      );
    }
    final matches = <CatalogItem>[];
    StreamApiException? lastError;
    final targetMatches = max(
      skip + _builtInCatalogPageSize,
      _builtInYearScanTargetMatches,
    );
    var scanExhausted = false;
    for (
      var page = 1;
      page <= _builtInYearScanMaxPages && matches.length < targetMatches;
      page += 1
    ) {
      try {
        final query = <String, String>{
          'type': type.compatTypeValue,
          'sort': _sortId(CatalogSort.year),
          'page': page.toString(),
        };
        _applyMatureCatalogPreference(query);
        final uri = Uri.parse(
          '$baseUrl/catalog',
        ).replace(queryParameters: query);
        final response = await _getHosted(uri);
        final decoded = _decodeResponse(response, 'Catalog');
        final metas = decoded['items'] ?? decoded['metas'];
        if (metas is! List) {
          throw const StreamApiException(
            'Catalog response did not include items.',
          );
        }
        final pageItems = _catalogItemsFromMetas(metas, requestedType: type);
        if (pageItems.isEmpty) {
          scanExhausted = true;
          break;
        }
        matches.addAll(
          pageItems.where((item) => _catalogItemMatchesYear(item, year)),
        );
      } on StreamApiException catch (error) {
        lastError = error;
        DiagnosticLog.add(
          'catalog built-in year scan failed type=${type.compatTypeValue} year="$year" error=$error',
        );
        break;
      }
    }
    final hitTarget = matches.length >= targetMatches;
    if (!hitTarget || scanExhausted) {
      _builtInYearScanCache[cacheKey] = List<CatalogItem>.unmodifiable(matches);
    }
    final pageMatches = matches
        .skip(skip)
        .take(_builtInCatalogPageSize)
        .toList();
    DiagnosticLog.add(
      'catalog built-in year scan type=${type.compatTypeValue} year="$year" matched=${matches.length} returned=${pageMatches.length}',
    );
    if (pageMatches.isEmpty && lastError != null && !softFail) throw lastError;
    return StreamCatalogResult(
      items: pageMatches,
      skipDelta: _builtInCatalogPageSize,
      hasMore: hitTarget || skip + _builtInCatalogPageSize < matches.length,
    );
  }

  Future<List<CatalogItem>> _scanAddonCatalogForLocalSearch({
    required UserAddon addon,
    required _AddonCatalog catalog,
    required MediaType type,
    required int skip,
    String? genre,
    required String search,
    required bool deepSearch,
  }) async {
    final supportsSkip = catalog.supportsExtra('skip');
    if (!deepSearch || !supportsSkip || skip > 0) {
      return _fetchAddonCatalogItems(
        addon: addon,
        catalog: catalog,
        type: type,
        skip: skip,
        genre: genre,
      );
    }

    final scanned = <String, CatalogItem>{};
    var nextSkip = 0;
    var pages = 0;
    while (pages < _addonLocalSearchMaxPages) {
      final pageItems = await _fetchAddonCatalogItems(
        addon: addon,
        catalog: catalog,
        type: type,
        skip: nextSkip,
        genre: genre,
      );
      pages += 1;
      if (pageItems.isEmpty) break;
      final before = scanned.length;
      for (final item in pageItems) {
        scanned[item.id] = item;
      }
      if (scanned.length == before) break;
      final matches = scanned.values
          .where((item) => _matchesCatalogSearch(item, search))
          .length;
      if (matches >= _addonLocalSearchMinMatches) break;
      nextSkip += pageItems.length;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    DiagnosticLog.add(
      'addon catalog local search scan addon=${addon.name} query="$search" pages=$pages scanned=${scanned.length}',
    );
    return scanned.values.toList();
  }

  Future<List<CatalogItem>> _fetchAddonCatalogItems({
    required UserAddon addon,
    required _AddonCatalog catalog,
    required MediaType type,
    required int skip,
    String? genre,
    String? search,
  }) async {
    final uri = _addonCatalogUri(
      addon.manifestUrl,
      type: type,
      catalogId: catalog.id,
      skip: skip,
      genre: genre,
      search: search,
      supportsGenre: catalog.supportsExtra('genre'),
      supportsSearch: catalog.supportsExtra('search'),
      supportsSkip: catalog.supportsExtra('skip'),
      catalogType: catalog.type,
    );
    DiagnosticLog.add('addon catalog start addon=${addon.name} uri=[hidden]');
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    final decoded = _decodeResponse(response, 'Add-on catalog');
    final metas = decoded['metas'] ?? decoded['items'];
    if (metas is! List) return const <CatalogItem>[];
    return _catalogItemsFromMetas(
      metas,
      requestedType: type,
      fallbackType: type.compatTypeValue,
    ).where((item) => item.id.isNotEmpty).toList();
  }

  Future<_AddonManifest> _addonManifest(UserAddon addon) async {
    final cached = _addonManifestCache[addon.manifestUrl];
    if (cached != null) return cached;
    final response = await _client
        .get(Uri.parse(addon.manifestUrl))
        .timeout(const Duration(seconds: 12));
    final decoded = _decodeResponse(response, 'Add-on manifest');
    final manifest = _AddonManifest.fromJson(decoded);
    _addonManifestCache[addon.manifestUrl] = manifest;
    return manifest;
  }

  Future<MetaDetails> meta(CatalogItem item) async {
    final cacheKey = '${item.type.compatTypeValue}:${item.id}';
    final cached = _metadataCache[cacheKey];
    if (cached != null) {
      if (item.type.isPlayableSeries && cached.videos.isEmpty) {
        DiagnosticLog.add(
          'metadata cache skipped reason=series_empty_episodes type=${item.type.compatTypeValue} id=${item.id}',
        );
      } else if (_needsImdbMetadataRefresh(item, cached.item)) {
        DiagnosticLog.add(
          'metadata cache skipped reason=missing_imdb_id type=${item.type.compatTypeValue} id=${item.id}',
        );
      } else {
        DiagnosticLog.add(
          'metadata cache hit type=${item.type.compatTypeValue} id=${item.id}',
        );
        return cached;
      }
    }
    final inFlight = _metadataInFlight[cacheKey];
    if (inFlight != null) {
      DiagnosticLog.add(
        'metadata in-flight hit type=${item.type.compatTypeValue} id=${item.id}',
      );
      final details = await inFlight;
      if (_needsImdbMetadataRefresh(item, details.item)) {
        DiagnosticLog.add(
          'metadata in-flight skipped reason=missing_imdb_id type=${item.type.compatTypeValue} id=${item.id}',
        );
        return _fetchMetaUncached(item, cacheKey: cacheKey);
      }
      return details;
    }
    final future = _fetchMetaUncached(item, cacheKey: cacheKey);
    _metadataInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _metadataInFlight.remove(cacheKey);
    }
  }

  Future<MetaDetails> _fetchMetaUncached(
    CatalogItem item, {
    required String cacheKey,
  }) async {
    final personalDetails = await _personalServers.meta(item);
    if (personalDetails != null) {
      _storeMetadataCache(cacheKey, personalDetails);
      return personalDetails;
    }
    final addonDetails = await _addonMetaDetails(item);
    if (!AppState.defaultCatalogEnabled.value) {
      final details = addonDetails ?? MetaDetails(item: item);
      _storeMetadataCache(cacheKey, details);
      return details;
    }
    if (item.type == MediaType.music || item.type == MediaType.nsfw) {
      final details = addonDetails ?? MetaDetails(item: item);
      _storeMetadataCache(cacheKey, details);
      return details;
    }
    try {
      final uri = Uri.parse('$baseUrl/meta').replace(
        queryParameters: {
          'type': _backendCatalogTypeFor(item.type),
          'id': item.id,
        },
      );
      final response = await _getHosted(uri);
      final decoded = _decodeResponse(response, 'Metadata');
      final hostedDetails = MetaDetails.fromJson(decoded);
      DiagnosticLog.add(
        'hosted metadata ok id=${item.id} imdbLinked=${_imdbIdForHostedLookup(hostedDetails.item) != null}',
      );
      final details = addonDetails == null
          ? hostedDetails
          : _mergeMetaDetails(addonDetails, hostedDetails);
      if (!item.type.isPlayableSeries || details.videos.isNotEmpty) {
        _storeMetadataCache(cacheKey, details);
      } else {
        DiagnosticLog.add(
          'metadata cache skipped reason=hosted_series_empty_episodes type=${item.type.compatTypeValue} id=${item.id}',
        );
      }
      return details;
    } catch (error) {
      DiagnosticLog.add('hosted metadata failed id=${item.id} error=$error');
      final details = addonDetails ?? MetaDetails(item: item);
      final shouldCacheFallback =
          !item.type.isPlayableSeries || details.videos.isNotEmpty;
      if (shouldCacheFallback &&
          (addonDetails != null || _hasUsefulMetadata(details.item, item))) {
        _storeMetadataCache(cacheKey, details);
      }
      return details;
    }
  }

  void _storeMetadataCache(String key, MetaDetails details) {
    _metadataCache[key] = details;
    _evictOldestCacheEntries(_metadataCache, _metadataCacheLimit, 'metadata');
  }

  bool _hasUsefulMetadata(CatalogItem details, CatalogItem fallback) {
    final hasArtwork =
        (details.poster?.trim().isNotEmpty ?? false) ||
        (details.background?.trim().isNotEmpty ?? false) ||
        (details.logo?.trim().isNotEmpty ?? false);
    final hasDescription = (details.description?.trim().isNotEmpty ?? false);
    final hasGenres = details.genres.isNotEmpty;
    final hasRating = (details.imdbRating?.trim().isNotEmpty ?? false);
    final changedTitle =
        details.name.trim().isNotEmpty &&
        details.name.trim().toLowerCase() != fallback.name.trim().toLowerCase();
    return hasArtwork ||
        hasDescription ||
        hasGenres ||
        hasRating ||
        changedTitle;
  }

  bool _needsImdbMetadataRefresh(CatalogItem request, CatalogItem details) {
    if (!request.isTmdbBackedItem) return false;
    if (request.type.isLive ||
        request.type == MediaType.music ||
        request.type == MediaType.nsfw) {
      return false;
    }
    return _imdbIdForHostedLookup(request) == null &&
        _imdbIdForHostedLookup(details) == null;
  }

  Future<List<CatalogItem>> recommendations(CatalogItem item) async {
    if (!AppState.defaultCatalogEnabled.value ||
        item.type.isLive ||
        item.type == MediaType.music ||
        item.type == MediaType.nsfw) {
      return const <CatalogItem>[];
    }
    final cacheKey =
        '${item.type.compatTypeValue}:${item.id}:${AppState.showMatureContent.value ? "mature-on" : "mature-off"}';
    final cached = _recommendationsCache[cacheKey];
    if (cached != null) {
      DiagnosticLog.add(
        'recommendations cache hit type=${item.type.compatTypeValue} id=${item.id} count=${cached.length}',
      );
      return cached;
    }
    final inFlight = _recommendationsInFlight[cacheKey];
    if (inFlight != null) {
      DiagnosticLog.add(
        'recommendations in-flight hit type=${item.type.compatTypeValue} id=${item.id}',
      );
      return inFlight;
    }
    final future = _fetchRecommendationsUncached(item, cacheKey: cacheKey);
    _recommendationsInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _recommendationsInFlight.remove(cacheKey);
    }
  }

  Future<List<CatalogItem>> _fetchRecommendationsUncached(
    CatalogItem item, {
    required String cacheKey,
  }) async {
    try {
      final query = <String, String>{
        'type': item.type.compatTypeValue,
        'id': item.id,
      };
      _applyMatureCatalogPreference(query);
      final uri = Uri.parse(
        '$baseUrl/recommendations',
      ).replace(queryParameters: query);
      final response = await _getHosted(uri);
      final decoded = _decodeResponse(response, 'Recommendations');
      final metas = decoded['items'] ?? decoded['metas'];
      if (metas is! List) {
        throw const StreamApiException(
          'Recommendations response did not include items.',
        );
      }
      final items = _catalogItemsFromMetas(metas, requestedType: item.type);
      _storeRecommendationsCache(
        cacheKey,
        List<CatalogItem>.unmodifiable(items),
      );
      DiagnosticLog.add(
        'hosted recommendations ok type=${item.type.compatTypeValue} id=${item.id} count=${items.length}',
      );
      return _recommendationsCache[cacheKey]!;
    } catch (error) {
      DiagnosticLog.add(
        'hosted recommendations failed type=${item.type.compatTypeValue} id=${item.id} error=$error',
      );
      _storeRecommendationsCache(cacheKey, const <CatalogItem>[]);
      return const <CatalogItem>[];
    }
  }

  void _storeRecommendationsCache(String key, List<CatalogItem> items) {
    _recommendationsCache[key] = items;
    _evictOldestCacheEntries(
      _recommendationsCache,
      _recommendationsCacheLimit,
      'recommendations',
    );
  }

  void _evictOldestCacheEntries<K, V>(
    Map<K, V> cache,
    int limit,
    String label,
  ) {
    var evicted = 0;
    while (cache.length > limit) {
      cache.remove(cache.keys.first);
      evicted += 1;
    }
    if (evicted > 0) {
      DiagnosticLog.add(
        '$label cache evicted reason=limit evicted=$evicted size=${cache.length}',
      );
    }
  }

  Future<MetaDetails?> _addonMetaDetails(CatalogItem item) async {
    final activeAddons = AppState.userAddons.value
        .where((addon) => addon.active)
        .toList();
    for (final addon in activeAddons) {
      try {
        final manifest = await _addonManifest(addon);
        if (!manifest.supportsResource('meta')) continue;
        final uris = _addonResourceUris(
          addon.manifestUrl,
          resource: 'meta',
          type: item.type.compatTypeValue,
          id: item.id,
        );
        for (final uri in uris) {
          DiagnosticLog.add(
            'addon metadata start addon=${addon.name} uri=[hidden]',
          );
          final response = await _client
              .get(uri)
              .timeout(const Duration(seconds: 10));
          final decoded = _decodeResponse(response, 'Add-on metadata');
          final rawMeta = decoded['meta'] ?? decoded['item'];
          if (rawMeta is! Map<String, dynamic>) continue;
          final details = MetaDetails.fromJson({'meta': rawMeta});
          DiagnosticLog.add(
            'addon metadata ok addon=${addon.name} id=${item.id} episodes=${details.videos.length}',
          );
          return details;
        }
      } catch (error) {
        DiagnosticLog.add(
          'addon metadata failed addon=${addon.name} id=${item.id} error=$error',
        );
      }
    }
    return null;
  }

  Future<PlaybackResult> resolveMovie(CatalogItem item) {
    if (item.isPersonalServerItem) {
      return _personalServers.playback(item).then((result) {
        if (result == null) {
          throw const StreamApiException(
            'Personal server item is unavailable.',
          );
        }
        return result;
      });
    }
    if (!AppState.defaultProvidersEnabled.value) {
      throw const StreamApiException('Default stream providers are disabled.');
    }
    final id = _resolveId(item);
    DiagnosticLog.add(
      'resolveMovie id=$id selectedNative=${AppState.selectedNativeProviderId}',
    );
    return _resolveRemote(
      Uri.parse('$baseUrl/resolve/movie').replace(
        queryParameters: {'id': id, 'mediaType': item.type.compatTypeValue},
      ),
      cooldownKey: 'movie:$id',
    );
  }

  Future<PlaybackResult> resolveMovieAddonStreams(CatalogItem item) {
    return _addonStreams(
      type: switch (item.type) {
        MediaType.liveTv => MediaType.liveTv,
        MediaType.music => MediaType.music,
        MediaType.nsfw => MediaType.nsfw,
        _ => MediaType.movie,
      },
      ids: _addonRouteIdsForItem(item),
      fallbackProviderId: 'addon',
    );
  }

  Future<List<PlaybackSource>> resolveMovieNativeSources(
    CatalogItem item, {
    required String providerId,
  }) {
    if (item.isPersonalServerItem) {
      return _personalServers
          .playback(item)
          .then((result) => result?.sources ?? const <PlaybackSource>[]);
    }
    if (item.type == MediaType.liveTv) {
      if (!AppState.tvSourcesEnabled.value ||
          !AppState.publicIptvEnabled.value) {
        DiagnosticLog.add(
          'native live tv resolve skipped reason=tv source disabled',
        );
        return Future<List<PlaybackSource>>.value(const <PlaybackSource>[]);
      }
      return _resolveHostedNativeSources(
        Uri.parse('$baseUrl/resolve/live-tv').replace(
          queryParameters: {
            'id': item.id,
            'title': item.name,
            'mediaType': item.type.compatTypeValue,
          },
        ),
        providerId: 'public-iptv',
      );
    }
    if (!AppState.defaultProvidersEnabled.value) {
      DiagnosticLog.add(
        'native provider resolve skipped provider=$providerId reason=default providers disabled',
      );
      return Future<List<PlaybackSource>>.value(const <PlaybackSource>[]);
    }
    final id = _resolveId(item);
    final resolverProviderId = _resolverProviderIdFor(providerId);
    return _resolveHostedNativeSources(
      Uri.parse('$baseUrl/resolve/movie').replace(
        queryParameters: {
          'id': id,
          'mediaType': item.type.compatTypeValue,
          'provider': resolverProviderId,
          'title': item.name,
          if (item.year != null && item.year!.isNotEmpty) 'year': item.year!,
        },
      ),
      providerId: providerId,
      resolverProviderId: resolverProviderId,
    );
  }

  Future<List<PlaybackSubtitle>> resolveMovieSubtitles(
    CatalogItem item, {
    bool includeDefault = true,
  }) async {
    if (item.isPersonalServerItem) return const <PlaybackSubtitle>[];
    final id = _resolveId(item);
    final subtitles = <PlaybackSubtitle>[
      ...await _addonSubtitles(
        type: item.type == MediaType.movie ? MediaType.movie : item.type,
        id: item.id,
        label: '${item.type.compatTypeValue} ${item.id}',
      ),
    ];
    if (includeDefault &&
        AppState.defaultSubtitlesEnabled.value &&
        item.type == MediaType.movie) {
      subtitles.addAll(
        await _resolveHostedSubtitles(
          Uri.parse('$baseUrl/subtitles/movie').replace(
            queryParameters: {
              'id': id,
              if (_imdbIdForHostedLookup(item) != null)
                'imdbId': _imdbIdForHostedLookup(item)!,
              if (item.tmdbId != null) 'tmdbId': item.tmdbId.toString(),
              'languages': subtitleLanguages,
            },
          ),
          label: 'movie $id',
        ),
      );
    }
    return _dedupeSubtitles(subtitles);
  }

  Future<List<TrailerItem>> resolveTrailers(CatalogItem item) async {
    if (item.isPersonalServerItem) return const <TrailerItem>[];
    final id = _resolveId(item);
    final trailers = <TrailerItem>[
      ...await _addonTrailers(
        type: item.type == MediaType.movie ? MediaType.movie : item.type,
        id: item.id,
        label: '${item.type.compatTypeValue} ${item.id}',
      ),
    ];
    if (!AppState.defaultTrailersEnabled.value) {
      DiagnosticLog.add(
        'hosted trailers skipped type=${item.type.compatTypeValue} id=${item.id} reason=default trailers disabled',
      );
      return _rankTrailersEnglishFirst(_dedupeTrailers(trailers));
    }
    final path = item.type == MediaType.movie ? 'movie' : 'tv';
    trailers.addAll(
      await _resolveHostedTrailers(
        Uri.parse('$baseUrl/trailers/$path').replace(
          queryParameters: {
            'id': id,
            if (_imdbIdForHostedLookup(item) != null)
              'imdbId': _imdbIdForHostedLookup(item)!,
            if (item.tmdbId != null) 'tmdbId': item.tmdbId.toString(),
            'language': 'en-US',
          },
        ),
        label: '${item.type.compatTypeValue} $id',
      ),
    );
    return _rankTrailersEnglishFirst(_dedupeTrailers(trailers));
  }

  Future<PlaybackResult> resolveEpisode(
    CatalogItem item, {
    required int season,
    required int episode,
  }) {
    if (item.isPersonalServerItem) {
      return _personalServers.playback(item).then((result) {
        if (result == null) {
          throw const StreamApiException(
            'Personal server item is unavailable.',
          );
        }
        return result;
      });
    }
    if (!AppState.defaultProvidersEnabled.value) {
      throw const StreamApiException('Default stream providers are disabled.');
    }
    final id = _resolveId(item);
    DiagnosticLog.add(
      'resolveEpisode id=$id S$season E$episode selectedNative=${AppState.selectedNativeProviderId}',
    );
    return _resolveRemote(
      Uri.parse('$baseUrl/resolve/tv').replace(
        queryParameters: {
          'id': id,
          'season': season.toString(),
          'episode': episode.toString(),
          'mediaType': item.type.compatTypeValue,
        },
      ),
      cooldownKey: 'tv:$id:$season:$episode',
    );
  }

  Future<PlaybackResult> resolveEpisodeAddonStreams(
    CatalogItem item, {
    required int season,
    required int episode,
  }) {
    return _addonStreams(
      type: MediaType.series,
      ids: _addonRouteIdsForItem(item, season: season, episode: episode),
      fallbackProviderId: 'addon',
    );
  }

  Future<PlaybackResult> _addonStreams({
    required MediaType type,
    required List<String> ids,
    required String fallbackProviderId,
  }) async {
    final requestIds = _uniqueNonEmptyStrings(ids);
    if (requestIds.isEmpty) {
      throw const StreamApiException('No active stream add-ons.');
    }
    final activeAddons = AppState.userAddons.value
        .where((addon) => addon.active)
        .toList();
    if (activeAddons.isEmpty) {
      throw const StreamApiException('No active stream add-ons.');
    }

    final sources = <PlaybackSource>[];
    final embeds = <PlaybackCandidate>[];
    final routeSummary = _AddonRouteSummary();
    final torrentOnlyAddons = <String>{};
    var sawStreamAddon = false;
    for (final addon in activeAddons) {
      try {
        final manifest = await _addonManifest(addon);
        if (!manifest.supportsResource('stream')) continue;
        sawStreamAddon = true;
        List<dynamic>? rawStreams;
        for (final requestId in requestIds) {
          final uris = _addonResourceUris(
            addon.manifestUrl,
            resource: 'stream',
            type: type.compatTypeValue,
            id: requestId,
          );
          for (final uri in uris) {
            DiagnosticLog.add(
              'addon stream start addon=${addon.name} uri=[hidden]',
            );
            final response = await _client
                .get(uri)
                .timeout(const Duration(seconds: 18));
            final decoded = _decodeResponse(response, 'Add-on streams');
            final candidateStreams = decoded['streams'];
            if (candidateStreams is List && candidateStreams.isNotEmpty) {
              rawStreams = candidateStreams;
              break;
            }
            rawStreams ??= candidateStreams is List ? candidateStreams : null;
          }
          if (rawStreams is List && rawStreams.isNotEmpty) break;
        }
        if (rawStreams is! List) continue;
        for (final stream in rawStreams.whereType<Map<String, dynamic>>()) {
          final url = (stream['url'] ?? '').toString().trim();
          final externalUrl = (stream['externalUrl'] ?? '').toString().trim();
          final ytId = (stream['ytId'] ?? '').toString().trim();
          final p2pDescriptor = P2pStreamDescriptor.fromAddonStream(stream);
          final headers = _streamHeaders(stream);
          void addP2pDescriptorSource({required String shape}) {
            routeSummary.torrentLocked += 1;
            torrentOnlyAddons.add(addon.id);
            sources.add(
              PlaybackSource(
                providerId: _addonProviderId(addon),
                name: _streamName(stream, addon.name),
                url: p2pDescriptor.syntheticUrl,
                type: 'p2p',
                quality: _streamQuality(stream),
                sourceClass: PlaybackSourceClass.p2p,
                subtitles: _mapList(
                  stream['subtitles'],
                  PlaybackSubtitle.fromJson,
                ),
              ),
            );
            DiagnosticLog.add(
              'addon p2p stream locked addon=${addon.name} shape=$shape ${p2pDescriptor.redactedDiagnostic} ${p2pDescriptor.lockedOperatorSummary}',
            );
          }

          if (url.isNotEmpty) {
            if (_looksLikeNativeStreamUrl(url)) {
              final sourceClass = _addonSourceClass(stream, url: url);
              sources.add(
                PlaybackSource(
                  providerId: _addonProviderId(addon),
                  name: _streamName(stream, addon.name),
                  url: url,
                  type: _streamType(url),
                  quality: _streamQuality(stream),
                  sourceClass: sourceClass,
                  headers: headers,
                  subtitles: _mapList(
                    stream['subtitles'],
                    PlaybackSubtitle.fromJson,
                  ),
                ),
              );
            } else if (_looksLikeP2pStreamUrl(url)) {
              routeSummary.torrentLocked += 1;
              torrentOnlyAddons.add(addon.id);
              DiagnosticLog.add(
                'addon p2p stream locked addon=${addon.name} shape=url',
              );
            } else if (p2pDescriptor.isUsable) {
              addP2pDescriptorSource(shape: 'mixed_url_descriptor');
            } else {
              routeSummary.unsupported += 1;
            }
          } else if (_looksLikeExternalDirectStream(stream, externalUrl)) {
            final sourceClass = _addonSourceClass(stream, url: externalUrl);
            sources.add(
              PlaybackSource(
                providerId: _addonProviderId(addon),
                name: _streamName(stream, addon.name),
                url: externalUrl,
                type: _streamType(externalUrl),
                quality: _streamQuality(stream),
                sourceClass: sourceClass,
                headers: headers,
                subtitles: _mapList(
                  stream['subtitles'],
                  PlaybackSubtitle.fromJson,
                ),
              ),
            );
          } else if (p2pDescriptor.isUsable) {
            addP2pDescriptorSource(shape: 'descriptor');
          } else if (ytId.isNotEmpty) {
            embeds.add(
              PlaybackCandidate(
                providerId: _addonProviderId(addon),
                name: _streamName(stream, addon.name),
                url: _youtubeWatchUrl(ytId),
              ),
            );
          } else if (externalUrl.isNotEmpty) {
            embeds.add(
              PlaybackCandidate(
                providerId: _addonProviderId(addon),
                name: _streamName(stream, addon.name),
                url: externalUrl,
              ),
            );
          } else if (_looksAccountRequiredStream(stream)) {
            routeSummary.accountRequired += 1;
          } else {
            routeSummary.unsupported += 1;
          }
        }
      } catch (error) {
        DiagnosticLog.add(
          'addon stream failed addon=${addon.name} error=$error',
        );
      }
    }

    final p2pSourceCount = sources
        .where((source) => source.sourceClass == PlaybackSourceClass.p2p)
        .length;
    routeSummary.direct = sources.length - p2pSourceCount;
    routeSummary.external = embeds.length;
    final routeEvidence = _AddonRouteAttemptEvidence.fromSummary(
      mediaType: type,
      summary: routeSummary,
    );
    DiagnosticLog.add(
      'addon streams result id=${requestIds.first} ${routeSummary.diagnostic} routeEvidence=${routeEvidence.redactedDiagnostic} torrentAddons=${torrentOnlyAddons.length} sourceClasses=${_playbackSourceClassCountsDiagnostic(sources)} lockedSourceClasses=${_lockedAddonSourceClassDiagnostic(torrentOnly: routeSummary.torrentLocked, accountRequired: routeSummary.accountRequired)}',
    );
    AppState.recordAddonRouteAttemptEvidence(routeEvidence.toJson());
    if (!sawStreamAddon) {
      throw const StreamApiException('No active stream add-ons.');
    }
    final playableSources = _nativeEligiblePlaybackSources(sources);
    if (playableSources.isEmpty && embeds.isEmpty) {
      throw StreamApiException(routeSummary.failureMessage);
    }

    final rankedSources = rankedNativePlaybackSources(
      playableSources,
      sourceClassAllowed: AppState.playbackSourceClassAllowedForNative,
      p2pConfig: _p2pPriorityConfigFromSettings(),
    );
    _logAddonPlaybackOrdering(rankedSources);

    return PlaybackResult(
      sources: rankedSources,
      embeds: embeds,
      debug: PlaybackDebug.empty,
    );
  }

  Future<List<PlaybackSubtitle>> _addonSubtitles({
    required MediaType type,
    required String id,
    required String label,
  }) async {
    final activeAddons = AppState.userAddons.value
        .where((addon) => addon.active)
        .toList();
    if (activeAddons.isEmpty) return const <PlaybackSubtitle>[];

    final subtitles = <PlaybackSubtitle>[];
    for (final addon in activeAddons) {
      try {
        final manifest = await _addonManifest(addon);
        if (!manifest.supportsResource('subtitles') &&
            !manifest.supportsResource('subtitle')) {
          continue;
        }
        final uris = _addonResourceUris(
          addon.manifestUrl,
          resource: 'subtitles',
          type: type.compatTypeValue,
          id: id,
        );
        if (manifest.supportsResource('subtitle') &&
            !manifest.supportsResource('subtitles')) {
          uris.addAll(
            _addonResourceUris(
              addon.manifestUrl,
              resource: 'subtitle',
              type: type.compatTypeValue,
              id: id,
            ),
          );
        }
        for (final uri in uris) {
          DiagnosticLog.add(
            'addon subtitles start addon=${addon.name} uri=[hidden]',
          );
          final response = await _client
              .get(uri)
              .timeout(const Duration(seconds: 12));
          final decoded = _decodeResponse(response, 'Add-on subtitles');
          final rawSubtitles = decoded['subtitles'] ?? decoded['items'];
          final parsed = _mapList(
            rawSubtitles,
            PlaybackSubtitle.fromJson,
          ).where((subtitle) => subtitle.url.isNotEmpty).toList();
          if (parsed.isNotEmpty) {
            subtitles.addAll(parsed);
            break;
          }
        }
      } catch (error) {
        DiagnosticLog.add(
          'addon subtitles failed addon=${addon.name} label="$label" error=$error',
        );
      }
    }
    DiagnosticLog.add(
      'addon subtitles result label="$label" count=${subtitles.length}',
    );
    return subtitles;
  }

  Future<List<TrailerItem>> _addonTrailers({
    required MediaType type,
    required String id,
    required String label,
  }) async {
    final activeAddons = AppState.userAddons.value
        .where((addon) => addon.active)
        .toList();
    if (activeAddons.isEmpty) return const <TrailerItem>[];

    final trailers = <TrailerItem>[];
    for (final addon in activeAddons) {
      try {
        final manifest = await _addonManifest(addon);
        final resourceNames = <String>[
          if (manifest.supportsResource('trailers')) 'trailers',
          if (manifest.supportsResource('trailer')) 'trailer',
        ];
        if (resourceNames.isEmpty) continue;

        for (final resource in resourceNames) {
          final uris = _addonResourceUris(
            addon.manifestUrl,
            resource: resource,
            type: type.compatTypeValue,
            id: id,
          );
          for (final uri in uris) {
            DiagnosticLog.add(
              'addon trailers start addon=${addon.name} resource=$resource uri=[hidden]',
            );
            final response = await _client
                .get(uri)
                .timeout(const Duration(seconds: 10));
            final decoded = _decodeResponse(response, 'Add-on trailers');
            final rawTrailers = decoded['trailers'] ?? decoded['items'];
            final parsed = _mapList(
              rawTrailers,
              TrailerItem.fromJson,
            ).where((trailer) => trailer.url.isNotEmpty).toList();
            if (parsed.isNotEmpty) {
              trailers.addAll(parsed);
              break;
            }
          }
        }
      } catch (error) {
        DiagnosticLog.add(
          'addon trailers failed addon=${addon.name} label="$label" error=$error',
        );
      }
    }
    DiagnosticLog.add(
      'addon trailers result label="$label" count=${trailers.length}',
    );
    return trailers;
  }

  Future<List<PlaybackSource>> resolveEpisodeNativeSources(
    CatalogItem item, {
    required int season,
    required int episode,
    required String providerId,
  }) {
    if (!AppState.defaultProvidersEnabled.value) {
      DiagnosticLog.add(
        'native provider resolve skipped provider=$providerId reason=default providers disabled',
      );
      return Future<List<PlaybackSource>>.value(const <PlaybackSource>[]);
    }
    final id = _resolveId(item);
    final resolverProviderId = _resolverProviderIdFor(providerId);
    return _resolveHostedNativeSources(
      Uri.parse('$baseUrl/resolve/tv').replace(
        queryParameters: {
          'id': id,
          'season': season.toString(),
          'episode': episode.toString(),
          'mediaType': item.type.compatTypeValue,
          'provider': resolverProviderId,
          'title': item.name,
          if (item.year != null && item.year!.isNotEmpty) 'year': item.year!,
        },
      ),
      providerId: providerId,
      resolverProviderId: resolverProviderId,
    );
  }

  Future<List<PlaybackSubtitle>> resolveEpisodeSubtitles(
    CatalogItem item, {
    required int season,
    required int episode,
    bool includeDefault = true,
  }) async {
    final id = _resolveId(item);
    final addonId = '${item.id}:$season:$episode';
    final subtitles = <PlaybackSubtitle>[
      ...await _addonSubtitles(
        type: MediaType.series,
        id: addonId,
        label: 'series $addonId',
      ),
    ];
    if (includeDefault && AppState.defaultSubtitlesEnabled.value) {
      subtitles.addAll(
        await _resolveHostedSubtitles(
          Uri.parse('$baseUrl/subtitles/tv').replace(
            queryParameters: {
              'id': id,
              if (_imdbIdForHostedLookup(item) != null)
                'imdbId': _imdbIdForHostedLookup(item)!,
              if (item.tmdbId != null) 'tmdbId': item.tmdbId.toString(),
              'season': season.toString(),
              'episode': episode.toString(),
              'languages': subtitleLanguages,
            },
          ),
          label: 'tv $id S$season E$episode',
        ),
      );
    }
    return _dedupeSubtitles(subtitles);
  }

  Future<PlaybackResult> _resolveRemote(
    Uri remoteUri, {
    required String cooldownKey,
  }) async {
    final now = DateTime.now();
    _remotePlaybackBusyUntilByKey.removeWhere(
      (_, until) => !now.isBefore(until),
    );
    final busyUntil = _remotePlaybackBusyUntilByKey[cooldownKey];
    if (busyUntil != null && now.isBefore(busyUntil)) {
      DiagnosticLog.add(
        'remote resolve skipped reason=recent_timeout key=$cooldownKey remainingMs=${busyUntil.difference(now).inMilliseconds}',
      );
      throw const StreamApiTemporaryBlockException(
        'Finding sources is taking longer than usual. Try again in a few seconds.',
        retryAfterSeconds: _remotePlaybackBusyBackoffSeconds,
      );
    }
    DiagnosticLog.add('remote resolve start: uri=[hidden]');
    final remote = await _resolve(remoteUri).timeout(
      _remoteBootstrapTimeout,
      onTimeout: () {
        _remotePlaybackBusyUntilByKey[cooldownKey] = DateTime.now().add(
          _remotePlaybackBusyBackoff,
        );
        DiagnosticLog.add(
          'remote resolve timeout after ${_remoteBootstrapTimeout.inSeconds}s: fail closed before provider scan key=$cooldownKey',
        );
        throw const StreamApiTemporaryBlockException(
          'Finding sources is taking longer than usual. Try again in a few seconds.',
          retryAfterSeconds: _remotePlaybackBusyBackoffSeconds,
        );
      },
    );
    DiagnosticLog.add(
      'remote resolve ok: sources=${remote.sources.length} embeds=${remote.embeds.length} sourceClasses=${_playbackSourceClassCountsDiagnostic(remote.sources)}',
    );
    return remote;
  }

  Future<ProviderHealthSampleCheck> _resolveHealthSampleOrEmpty(
    Uri uri, {
    required ProviderHealthSample fallbackSample,
  }) async {
    final response = await _getHosted(uri);
    final decoded = _decodeResponse(response, 'Playback health sample');
    final sample =
        _providerHealthSampleFromJson(decoded['sample']) ??
        _providerHealthSampleFromJson(decoded) ??
        fallbackSample;
    return ProviderHealthSampleCheck(
      sample: sample,
      result: PlaybackResult.fromJson(decoded),
      providerCounts: _providerHealthCountsFromJson(decoded),
      sourceClassCounts: _sourceClassCountsFromJson(
        decoded['sourceClassCounts'],
      ),
    );
  }

  Future<PlaybackResult> _resolve(Uri uri) async {
    final response = await _getHosted(uri);
    final decoded = _decodeResponse(response, 'Playback');

    final result = PlaybackResult.fromJson(decoded);
    if (result.sources.isEmpty) {
      DiagnosticLog.add(
        'playback response empty ${_playbackEmptyDiagnostic(decoded)}',
      );
      if (result.retryAfterSeconds > 0) {
        throw StreamApiTemporaryBlockException(
          'Title unavailable; retry after ${result.retryAfterSeconds}s.',
          retryAfterSeconds: result.retryAfterSeconds,
        );
      }
      final remoteBlock = _playbackTemporaryBlockMessage(decoded);
      if (remoteBlock != null) {
        throw StreamApiTemporaryBlockException(remoteBlock);
      }
      throw const StreamApiException(
        'Playback response did not include playable sources.',
      );
    }
    return result;
  }

  Future<List<PlaybackSource>> _resolveHostedNativeSources(
    Uri uri, {
    required String providerId,
    String? resolverProviderId,
  }) async {
    final remoteProviderId = resolverProviderId ?? providerId;
    try {
      DiagnosticLog.add(
        'hosted playback lookup start provider=$providerId remoteProvider=$remoteProviderId uri=[hidden]',
      );
      final timeoutSeconds =
          AppState.playerBehaviorSettings.value.experimentalControlsEnabled
          ? AppState.playerBehaviorSettings.value.providerResolveTimeoutSeconds
          : const PlayerBehaviorSettings().providerResolveTimeoutSeconds;
      final result = await _resolve(
        uri,
      ).timeout(Duration(seconds: timeoutSeconds));
      final sources = result.sources
          .where(
            (source) =>
                source.providerId == providerId ||
                source.providerId == remoteProviderId,
          )
          .map((source) => _sourceWithProviderId(source, providerId))
          .toList();
      DiagnosticLog.add(
        'hosted playback lookup ok provider=$providerId remoteProvider=$remoteProviderId sources=${sources.length} sourceClasses=${_playbackSourceClassCountsDiagnostic(sources)}',
      );
      return sources;
    } catch (error) {
      DiagnosticLog.add(
        'hosted playback lookup failed provider=$providerId remoteProvider=$remoteProviderId error=$error',
      );
      if (_isTemporaryResolverBlock(error)) {
        throw StreamApiTemporaryBlockException(error.toString());
      }
      return const <PlaybackSource>[];
    }
  }

  Future<List<PlaybackSubtitle>> _resolveHostedSubtitles(
    Uri uri, {
    required String label,
  }) async {
    try {
      DiagnosticLog.add('hosted subtitles start label="$label" uri=[hidden]');
      final response = await _getHosted(
        uri,
      ).timeout(const Duration(seconds: 8));
      final decoded = _decodeResponse(response, 'Subtitles');
      final rawSubtitles = decoded['subtitles'] ?? decoded['items'];
      final subtitles = _mapList(
        rawSubtitles,
        PlaybackSubtitle.fromJson,
      ).where((subtitle) => subtitle.url.isNotEmpty).toList();
      DiagnosticLog.add(
        'hosted subtitles ok label="$label" count=${subtitles.length}',
      );
      return subtitles;
    } catch (error) {
      DiagnosticLog.add('hosted subtitles failed label="$label" error=$error');
      return const <PlaybackSubtitle>[];
    }
  }

  List<PlaybackSubtitle> _dedupeSubtitles(List<PlaybackSubtitle> subtitles) {
    final seen = <String>{};
    return [
      for (final subtitle in subtitles)
        if (seen.add('${subtitle.language}|${subtitle.label}|${subtitle.url}'))
          subtitle,
    ];
  }

  List<TrailerItem> _dedupeTrailers(List<TrailerItem> trailers) {
    final seen = <String>{};
    return [
      for (final trailer in trailers)
        if (seen.add('${trailer.providerId}|${trailer.title}|${trailer.url}'))
          trailer,
    ];
  }

  Future<List<TrailerItem>> _resolveHostedTrailers(
    Uri uri, {
    required String label,
  }) async {
    try {
      DiagnosticLog.add('hosted trailers start label="$label" uri=[hidden]');
      final response = await _getHosted(
        uri,
      ).timeout(const Duration(seconds: 6));
      final decoded = _decodeResponse(response, 'Trailers');
      final rawTrailers = decoded['trailers'] ?? decoded['items'];
      final trailers = _mapList(
        rawTrailers,
        TrailerItem.fromJson,
      ).where((trailer) => trailer.url.isNotEmpty).toList();
      final rankedTrailers = _rankTrailersEnglishFirst(trailers);
      DiagnosticLog.add(
        'hosted trailers ok label="$label" count=${rankedTrailers.length} first=${rankedTrailers.isEmpty ? 'none' : rankedTrailers.first.title}',
      );
      return rankedTrailers;
    } catch (error) {
      DiagnosticLog.add('hosted trailers failed label="$label" error=$error');
      return const <TrailerItem>[];
    }
  }
}

List<CatalogItem> _catalogItemsFromMetas(
  dynamic metas, {
  required MediaType requestedType,
  String? fallbackType,
}) {
  final items = (metas as List)
      .whereType<Map<String, dynamic>>()
      .map(
        (json) => CatalogItem.fromJson({
          ...json,
          'type': json['type'] ?? fallbackType ?? requestedType.compatTypeValue,
        }),
      )
      .where(
        (item) =>
            _isSafeCatalogId(item, requestedType) &&
            !_badCatalogIds.contains(item.id),
      )
      .toList();

  if (requestedType != MediaType.animation) return items;

  return [
    for (final item in items)
      if (_isAnimationTaggedItem(item)) item.withType(MediaType.animation),
  ];
}

MetaDetails _mergeMetaDetails(MetaDetails primary, MetaDetails fallback) {
  return MetaDetails(
    item: primary.item.merge(fallback.item),
    runtime: primary.runtime ?? fallback.runtime,
    director: primary.director.isNotEmpty
        ? primary.director
        : fallback.director,
    cast: primary.cast.isNotEmpty ? primary.cast : fallback.cast,
    directorPeople: primary.directorPeople.isNotEmpty
        ? primary.directorPeople
        : fallback.directorPeople,
    castPeople: primary.castPeople.isNotEmpty
        ? primary.castPeople
        : fallback.castPeople,
    videos: primary.videos.isNotEmpty ? primary.videos : fallback.videos,
  );
}

bool _isAnimationTaggedItem(CatalogItem item) {
  return item.genres.any((genre) {
    final normalized = genre.trim().toLowerCase();
    return normalized == 'animation';
  });
}

int _animationCatalogScore(CatalogItem item) {
  final genres = item.genres.map((genre) => genre.trim().toLowerCase()).toSet();
  final title = item.name.toLowerCase();
  final description = (item.description ?? '').toLowerCase();
  final text = '$title $description';
  var score = 0;

  if (genres.contains('animation')) score += 80;

  for (final genre in const [
    'action',
    'adventure',
    'fantasy',
    'sci-fi',
    'mystery',
    'thriller',
  ]) {
    if (genres.contains(genre)) score += 8;
  }

  for (final genre in const ['family', 'kids', 'children']) {
    if (genres.contains(genre)) score -= 18;
  }

  for (final token in const [
    'animation',
    'manga',
    'shonen',
    'shoujo',
    'isekai',
    'mecha',
    'titan',
    'jujutsu',
    'naruto',
    'bleach',
    'one piece',
    'demon',
    'sorcerer',
    'curse',
    'academy',
    'tokyo',
    'japan',
  ]) {
    if (text.contains(token)) score += 10;
  }

  for (final token in const [
    'bluey',
    'batman',
    'regular show',
    'cartoon network',
    'nickelodeon',
    'disney channel',
    'pixar',
    'dreamworks',
    'superhero dog',
    'family cartoon',
  ]) {
    if (text.contains(token)) score -= 20;
  }

  return score;
}

List<TrailerItem> _rankTrailersEnglishFirst(List<TrailerItem> trailers) {
  final indexed = <({int index, TrailerItem trailer})>[
    for (var index = 0; index < trailers.length; index++)
      (index: index, trailer: trailers[index]),
  ];
  indexed.sort((a, b) {
    final score = _englishTrailerScore(
      b.trailer,
    ).compareTo(_englishTrailerScore(a.trailer));
    if (score != 0) return score;
    return a.index.compareTo(b.index);
  });
  return [for (final entry in indexed) entry.trailer];
}

P2pPriorityConfig _p2pPriorityConfigFromSettings() {
  final behavior = AppState.playerBehaviorSettings.value;
  return P2pPriorityConfig(
    enabled: behavior.p2pSourcePrioritiesEnabled,
    mode: behavior.p2pPriorityMode,
    resultsPerQuality: behavior.p2pResultsPerQuality,
    preferredAudioLanguageMode: behavior.p2pPreferredAudioLanguageMode,
    avoidRiskyFormats: behavior.p2pAvoidRiskyFormats,
    sizeLimitMb: behavior.p2pSizeLimitMb,
  );
}

List<PlaybackSource> _nativeEligiblePlaybackSources(
  List<PlaybackSource> sources,
) {
  final eligible = sources
      .where(
        (source) =>
            AppState.playbackSourceClassAllowedForNative(source.sourceClass),
      )
      .toList(growable: false);
  final skipped = sources.length - eligible.length;
  if (skipped > 0) {
    DiagnosticLog.add(
      'addon playable source gate skipped count=$skipped sourceClasses=${_playbackSourceClassCountsDiagnostic(sources)}',
    );
  }
  return eligible;
}

bool _isSafeCatalogId(CatalogItem item, MediaType requestedType) {
  if (item.id.isEmpty) return false;
  if (requestedType == MediaType.liveTv) return true;
  if (item.id.startsWith('tt')) return true;
  if (item.id.startsWith('tmdb:') && item.tmdbId != null) return true;
  return false;
}

void _logAddonPlaybackOrdering(List<PlaybackSource> sources) {
  PlaybackSource? firstP2p;
  for (final source in sources) {
    if (source.sourceClass == PlaybackSourceClass.p2p) {
      firstP2p = source;
      break;
    }
  }
  if (firstP2p == null) return;
  final descriptor = P2pStreamDescriptor.fromSyntheticUrl(firstP2p.url);
  DiagnosticLog.add(
    'addon p2p playback order first=trackers:${descriptor?.trackers.length ?? 0} fileIdx:${descriptor?.fileIdx ?? 'auto'} quality:${playbackQualityLabel(firstP2p)} healthRank=${p2pPlaybackHealthRank(firstP2p)}',
  );
}

int _englishTrailerScore(TrailerItem trailer) {
  final text =
      '${trailer.providerId} ${trailer.name} ${trailer.title} ${trailer.url}'
          .toLowerCase();
  var score = 0;

  for (final token in const [
    'official trailer',
    'english',
    ' en ',
    '/en',
    'marvel entertainment',
    'warner bros. pictures',
    'warner bros pictures',
    'universal pictures',
    'paramount pictures',
    'sony pictures',
    '20th century studios',
    'lionsgate',
    'netflix',
    'disney',
    'movieclips trailers',
  ]) {
    if (text.contains(token)) score += 12;
  }

  for (final token in const [
    'italia',
    'italiano',
    'italian',
    'deutsch',
    'german',
    'français',
    'france',
    'español',
    'espanol',
    'latino',
    'português',
    'portugues',
    'brasil',
    'hindi',
    'sub ita',
    'sub español',
    'sub espanol',
    'dubbed',
  ]) {
    if (text.contains(token)) score -= 20;
  }

  if (RegExp(r'\btrailer\b').hasMatch(text)) score += 2;
  return score;
}

const Set<String> _badCatalogIds = {
  // Metahub currently serves the Law & Order: SVU poster for this unrelated title.
  'tt0118933',
};

void _applyMatureCatalogPreference(Map<String, String> query) {
  if (AppState.showMatureContent.value) {
    query['allowMature'] = 'true';
  }
}

String _backendCatalogTypeFor(MediaType type) {
  return switch (type) {
    MediaType.animation => MediaType.animation.compatTypeValue,
    MediaType.liveTv => 'live_tv',
    _ => type.compatTypeValue,
  };
}

void _applyCatalogScope(
  Map<String, String> query, {
  required MediaType type,
  String? company,
  String? collection,
}) {
  final cleanCompany = company?.trim();
  if (cleanCompany != null && cleanCompany.isNotEmpty) {
    query['company'] = cleanCompany;
  }
  final cleanCollection = collection?.trim();
  if (type == MediaType.movie &&
      cleanCollection != null &&
      cleanCollection.isNotEmpty) {
    query['collection'] = cleanCollection;
  }
}

void _applyOriginCountryFilter(
  Map<String, String> query,
  String? originCountry,
) {
  final cleanOrigin = originCountry?.trim().toUpperCase();
  if (cleanOrigin != null && RegExp(r'^[A-Z]{2}$').hasMatch(cleanOrigin)) {
    query['originCountry'] = cleanOrigin;
  }
}

String _sortId(CatalogSort sort) {
  return switch (sort) {
    CatalogSort.top => 'popular',
    CatalogSort.topRated => 'top_rated',
    CatalogSort.newest => 'newest',
    CatalogSort.oldest => 'oldest',
    CatalogSort.alphaAsc => 'a_z',
    CatalogSort.alphaDesc => 'z_a',
    CatalogSort.nowPlaying => 'now_playing',
    CatalogSort.airingToday => 'airing_today',
    CatalogSort.onTv => 'on_tv',
    CatalogSort.year => 'year',
    CatalogSort.upcoming => 'upcoming',
    CatalogSort.imdbRating => 'imdbRating',
    CatalogSort.hiddenGems => 'hidden_gems',
  };
}

String _resolveId(CatalogItem item) {
  return item.tmdbId?.toString() ?? item.id;
}

String? _imdbIdForHostedLookup(CatalogItem item) {
  final metadataId = item.imdbId?.trim();
  if (metadataId != null && _isImdbId(metadataId)) return metadataId;
  final raw = item.id.trim();
  return _isImdbId(raw) ? raw : null;
}

List<String> _addonRouteIdsForItem(
  CatalogItem item, {
  int? season,
  int? episode,
}) {
  final baseIds = _uniqueNonEmptyStrings([
    if (_imdbIdForHostedLookup(item) != null) _imdbIdForHostedLookup(item)!,
    item.id,
    if (item.tmdbId != null) 'tmdb:${item.tmdbId}',
  ]);
  if (season == null || episode == null) return baseIds;
  return baseIds.map((id) => '$id:$season:$episode').toList();
}

List<String> _uniqueNonEmptyStrings(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || result.contains(trimmed)) continue;
    result.add(trimmed);
  }
  return result;
}

bool _isImdbId(String value) {
  return RegExp(r'^tt\d{5,12}$', caseSensitive: false).hasMatch(value.trim());
}

bool _matchesCatalogSearch(CatalogItem item, String search) {
  final query = search.trim().toLowerCase();
  if (query.isEmpty) return true;
  final haystack = [
    item.name,
    item.year ?? '',
    item.id,
    item.tmdbId?.toString() ?? '',
  ].join(' ').toLowerCase();
  final terms = query.split(RegExp(r'\s+')).where((term) => term.isNotEmpty);
  return terms.every(haystack.contains);
}

bool _catalogItemMatchesYear(CatalogItem item, String year) {
  final rawYear = item.year?.trim();
  if (rawYear == null || rawYear.isEmpty) return false;
  return RegExp('\\b${RegExp.escape(year)}\\b').hasMatch(rawYear);
}

bool _catalogItemMatchesGenre(CatalogItem item, String normalizedGenre) {
  return item.genres.any((genre) {
    return genre.trim().toLowerCase() == normalizedGenre;
  });
}

ProviderHealthSample? _providerHealthSampleFromJson(dynamic json) {
  if (json is! Map<String, dynamic>) return null;
  final id = (json['id'] ?? '').toString().trim();
  if (id.isEmpty) return null;
  return ProviderHealthSample(
    type: _providerHealthSampleTypeFromString(json['type']),
    id: id,
    title: _optionalString(json['title']),
    year: _optionalString(json['year']),
    season: _intValue(json['season']) ?? 1,
    episode: _intValue(json['episode']) ?? 1,
  );
}

Map<String, int> _providerHealthCountsFromJson(Map<String, dynamic> decoded) {
  final counts = <String, int>{};
  final providers = decoded['providers'];
  if (providers is List) {
    for (final item in providers) {
      if (item is! Map) continue;
      final provider = _optionalString(item['provider'] ?? item['id']);
      if (provider == null) continue;
      final sourceCount = _intValue(item['sourceCount'] ?? item['count']) ?? 0;
      if (sourceCount > 0) counts[provider] = sourceCount;
    }
  }
  if (counts.isNotEmpty) return counts;

  final sourceProviders = decoded['sourceProviders'];
  if (sourceProviders is List) {
    for (final providerValue in sourceProviders) {
      final provider = _optionalString(providerValue);
      if (provider == null) continue;
      counts[provider] = max(1, counts[provider] ?? 0);
    }
  }
  return counts;
}

Map<String, int> _sourceClassCountsFromJson(dynamic json) {
  final counts = <String, int>{};
  if (json is! Map) return counts;
  for (final entry in json.entries) {
    final sourceClass = _optionalString(entry.key);
    if (sourceClass == null) continue;
    final rawClass = sourceClass.toLowerCase();
    final normalized = rawClass == 'unknown' ? 'unsupported' : rawClass;
    if (!const <String>{
      'direct',
      'debrid',
      'external',
      'p2p',
      'unsupported',
    }.contains(normalized)) {
      continue;
    }
    final count = _intValue(entry.value) ?? 0;
    if (count > 0) counts[normalized] = (counts[normalized] ?? 0) + count;
  }
  return counts;
}

String _sourceClassCountsDiagnostic(Map<String, int> counts) {
  if (counts.isEmpty) return 'none';
  const order = <String>['direct', 'debrid', 'external', 'p2p', 'unsupported'];
  final parts = <String>[];
  for (final sourceClass in order) {
    final count = counts[sourceClass] ?? 0;
    if (count > 0) parts.add('$sourceClass:$count');
  }
  return parts.isEmpty ? 'none' : parts.join(',');
}

String _playbackSourceClassCountsDiagnostic(List<PlaybackSource> sources) {
  if (sources.isEmpty) return 'none';
  final counts = <String, int>{};
  for (final source in sources) {
    final sourceClass = source.sourceClass.wireName;
    counts[sourceClass] = (counts[sourceClass] ?? 0) + 1;
  }
  return _sourceClassCountsDiagnostic(counts);
}

String _lockedAddonSourceClassDiagnostic({
  required int torrentOnly,
  required int accountRequired,
}) {
  final parts = <String>[];
  if (torrentOnly > 0) parts.add('p2p:$torrentOnly');
  if (accountRequired > 0) parts.add('accountRequired:$accountRequired');
  return parts.isEmpty ? 'none' : parts.join(',');
}

class _AddonRouteSummary {
  int direct = 0;
  int external = 0;
  int torrentLocked = 0;
  int accountRequired = 0;
  int unsupported = 0;

  String get diagnostic {
    return [
      'status=$status',
      'direct=$direct',
      'external=$external',
      'torrentLocked=$torrentLocked',
      'accountRequired=$accountRequired',
      'unsupported=$unsupported',
    ].join(' ');
  }

  String get status {
    if (direct > 0) return 'direct';
    if (external > 0) return 'external_only';
    if (torrentLocked > 0 && AppState.p2pRuntimePlaybackEffective) {
      return 'p2p_ready';
    }
    if (torrentLocked > 0) return 'torrent_locked';
    if (accountRequired > 0) return 'account_required';
    if (unsupported > 0) return 'unsupported';
    return 'empty';
  }

  String get statusLabel {
    return switch (status) {
      'direct' => 'Direct streams ready',
      'external_only' => 'External only',
      'p2p_ready' => 'Advanced P2P ready',
      'torrent_locked' => 'P2P locked',
      'account_required' => 'Needs account setup',
      'unsupported' => 'Unsupported source',
      _ => 'No routes found',
    };
  }

  String get statusHint {
    return switch (status) {
      'direct' =>
        'Juicr found native-readable direct or account-backed routes.',
      'external_only' => 'External routes need an explicit handoff.',
      'p2p_ready' =>
        'Advanced P2P playback is enabled for recognized sources. Source health can still vary.',
      'torrent_locked' =>
        P2pLocalStreamBridge.instance.isAvailable
            ? 'P2P playback needs Advanced P2P consent and the playback switch enabled. Use direct or account-backed streams first.'
            : 'P2P playback needs a build with Advanced P2P support. Use direct or account-backed streams first.',
      'account_required' =>
        'The add-on may need account setup before it can return direct streams.',
      'unsupported' =>
        'The add-on returned source shapes Juicr does not support yet.',
      _ => 'The add-on did not return a usable route shape.',
    };
  }

  String get failureMessage {
    if (torrentLocked > 0 && AppState.p2pRuntimePlaybackEffective) {
      return 'Advanced P2P sources were recognized, but none opened yet.';
    }
    if (torrentLocked > 0) return _lockedP2pAddonMessage(torrentLocked);
    if (accountRequired > 0) {
      return 'This add-on may need account setup before it can return direct streams.';
    }
    if (external > 0) {
      return 'This add-on returned external results. Juicr will not treat them as native playback unless you choose an external handoff.';
    }
    if (unsupported > 0) {
      return 'This add-on returned sources Juicr does not support yet.';
    }
    return 'Add-ons did not return playable sources.';
  }
}

class _AddonRouteAttemptEvidence {
  const _AddonRouteAttemptEvidence({
    required this.mediaType,
    required this.status,
    required this.statusLabel,
    required this.statusHint,
    required this.direct,
    required this.external,
    required this.torrentLocked,
    required this.accountRequired,
    required this.unsupported,
    required this.empty,
    required this.checkedAtUtc,
  });

  factory _AddonRouteAttemptEvidence.fromSummary({
    required MediaType mediaType,
    required _AddonRouteSummary summary,
  }) {
    final total =
        summary.direct +
        summary.external +
        summary.torrentLocked +
        summary.accountRequired +
        summary.unsupported;
    return _AddonRouteAttemptEvidence(
      mediaType: mediaType.compatTypeValue,
      status: summary.status,
      statusLabel: summary.statusLabel,
      statusHint: summary.statusHint,
      direct: summary.direct,
      external: summary.external,
      torrentLocked: summary.torrentLocked,
      accountRequired: summary.accountRequired,
      unsupported: summary.unsupported,
      empty: total == 0 ? 1 : 0,
      checkedAtUtc: DateTime.now().toUtc().toIso8601String(),
    );
  }

  final String mediaType;
  final String status;
  final String statusLabel;
  final String statusHint;
  final int direct;
  final int external;
  final int torrentLocked;
  final int accountRequired;
  final int unsupported;
  final int empty;
  final String checkedAtUtc;

  Map<String, Object> toJson() {
    return {
      'mediaType': mediaType,
      'status': status,
      'statusLabel': statusLabel,
      'statusHint': statusHint,
      'counts': {
        'direct': direct,
        'externalOnly': external,
        'torrentLocked': torrentLocked,
        'accountRequired': accountRequired,
        'unsupported': unsupported,
        'empty': empty,
      },
      'checkedAtUtc': checkedAtUtc,
    };
  }

  String get redactedDiagnostic {
    return [
      'mediaType=$mediaType',
      'status=$status',
      'direct=$direct',
      'externalOnly=$external',
      'torrentLocked=$torrentLocked',
      'accountRequired=$accountRequired',
      'unsupported=$unsupported',
      'empty=$empty',
      'checkedAtUtc=$checkedAtUtc',
    ].join(' ');
  }
}

String _lockedP2pAddonMessage(int count) {
  final streamLabel = count == 1 ? '1 P2P stream' : '$count P2P streams';
  if (P2pLocalStreamBridge.instance.isAvailable) {
    return 'This add-on returned $streamLabel. Review Advanced P2P consent and turn on the playback switch to test recognized sources. Use direct or account-backed streams first.';
  }
  return 'This add-on returned $streamLabel. P2P playback needs a build with Advanced P2P support. Use direct or account-backed streams first.';
}

MediaType _providerHealthSampleTypeFromString(dynamic value) {
  final normalized = (value ?? '').toString().trim().toLowerCase();
  return switch (normalized) {
    'series' || 'tv' => MediaType.series,
    'animation' => MediaType.animation,
    _ => MediaType.movie,
  };
}

String? _optionalString(dynamic value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

int? _intValue(dynamic value) {
  if (value is int) return value;
  return int.tryParse((value ?? '').toString().trim());
}

String _playbackEmptyDiagnostic(Map<String, dynamic> decoded) {
  final parts = <String>[];
  if (decoded.containsKey('ok')) {
    parts.add('ok=${decoded['ok']}');
  }
  final error = _shortDiagnosticText(decoded['error']);
  if (error != null) {
    parts.add('error="$error"');
  }
  final message = _shortDiagnosticText(decoded['message']);
  if (message != null && message != error) {
    parts.add('message="$message"');
  }
  final retryAfter = _intValue(decoded['retryAfterSeconds']);
  if (retryAfter != null && retryAfter > 0) {
    parts.add('retryAfter=${retryAfter}s');
  }
  final unavailableReason = _shortDiagnosticText(decoded['unavailableReason']);
  if (unavailableReason != null) {
    parts.add('unavailable=$unavailableReason');
  }
  final resolve = decoded['resolve'];
  if (resolve is Map<String, dynamic>) {
    final outcome = _shortDiagnosticText(resolve['outcome']);
    if (outcome != null) parts.add('outcome=$outcome');
    final cacheHint = _shortDiagnosticText(resolve['cacheHint']);
    if (cacheHint != null) parts.add('cache=$cacheHint');
  }
  final debug = decoded['debug'];
  if (debug is Map<String, dynamic>) {
    final validation = debug['validation'];
    if (validation is Map<String, dynamic>) {
      parts.add(
        'validation=${validation['passed'] ?? 0}/${validation['checked'] ?? '?'}',
      );
    }
    final provider = _shortDiagnosticText(debug['provider']);
    if (provider != null) {
      parts.add('debugProvider=$provider');
    }
  }
  return parts.isEmpty ? 'reason=unknown' : parts.join(' ');
}

String? _playbackTemporaryBlockMessage(Map<String, dynamic> decoded) {
  for (final value in <dynamic>[decoded['error'], decoded['message']]) {
    final message = _shortDiagnosticText(value);
    if (message != null && _isTemporaryResolverBlock(message)) {
      return message;
    }
  }
  return null;
}

String? _shortDiagnosticText(dynamic value) {
  final text = (value ?? '').toString().trim();
  if (text.isEmpty) return null;
  return text.length <= 120 ? text : '${text.substring(0, 117)}...';
}

Map<String, dynamic> _decodeResponse(http.Response response, String label) {
  final decoded = _tryDecodeObject(response.body);
  if (decoded != null && decoded['disabled'] == true) {
    throw StreamApiDisabledException(
      (decoded['error'] ??
              decoded['message'] ??
              'Service is currently unavailable.')
          .toString(),
    );
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    final message = decoded?['error'] ?? decoded?['message'];
    final retryAfter =
        _intValue(decoded?['retryAfterSeconds']) ??
        _intValue(response.headers['retry-after']);
    if (response.statusCode == 429 || (retryAfter != null && retryAfter > 0)) {
      throw StreamApiTemporaryBlockException(
        message == null
            ? '$label request failed: ${response.statusCode}.'
            : message.toString(),
        retryAfterSeconds: retryAfter ?? 0,
      );
    }
    throw StreamApiException(
      message == null
          ? '$label request failed: ${response.statusCode}.'
          : message.toString(),
    );
  }

  if (decoded == null) {
    throw StreamApiException('Unexpected ${label.toLowerCase()} response.');
  }
  return decoded;
}

Map<String, dynamic>? _tryDecodeObject(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

AccountProfile? _accountProfileFromAuth(dynamic value) {
  if (value is! Map) return null;
  final json = Map<String, dynamic>.from(value);
  json['adPreferences'] = AccountAdPreferences.fromJson(
    json['adPreferences'],
  ).toJson();
  final profile = AccountProfile.fromJson(json);
  return profile.isUsable ? profile : null;
}

AccountSession? _accountSessionFromAuth(dynamic value) {
  if (value is! Map) return null;
  final session = AccountSession.fromJson(Map<String, dynamic>.from(value));
  return session.isValid ? session : null;
}

class StreamApiException implements Exception {
  const StreamApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StreamApiTemporaryBlockException extends StreamApiException {
  const StreamApiTemporaryBlockException(
    super.message, {
    this.retryAfterSeconds = 0,
  });

  final int retryAfterSeconds;
}

class StreamApiDisabledException extends StreamApiException {
  const StreamApiDisabledException(super.message);
}

bool _isTemporaryResolverBlock(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('rate limit') ||
      text.contains('retry after') ||
      text.contains('temporarily blocked') ||
      text.contains('too many requests');
}

class _AddonManifest {
  const _AddonManifest({
    required this.name,
    required this.description,
    required this.catalogs,
    required this.resources,
  });

  final String name;
  final String description;
  final List<_AddonCatalog> catalogs;
  final List<String> resources;

  factory _AddonManifest.fromJson(Map<String, dynamic> json) {
    return _AddonManifest(
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      catalogs: _mapList(json['catalogs'], _AddonCatalog.fromJson)
          .where((catalog) => catalog.id.isNotEmpty && catalog.type.isNotEmpty)
          .toList(),
      resources: _resourceNames(json['resources']),
    );
  }

  bool supportsResource(String resource) {
    final normalized = resource.trim().toLowerCase();
    return resources.any((item) => item.trim().toLowerCase() == normalized);
  }

  List<_AddonCatalog> catalogsFor(MediaType type) {
    return catalogs
        .where((catalog) => type.matchesCompatType(catalog.type))
        .toList();
  }

  _AddonCatalog? catalogFor({
    required MediaType type,
    required CatalogSort sort,
    String? search,
    String? genre,
  }) {
    final byType = catalogs
        .where((catalog) => type.matchesCompatType(catalog.type))
        .toList();
    if (byType.isEmpty) return null;

    final hasSearch = search != null && search.trim().isNotEmpty;
    if (hasSearch) {
      final searchable = byType
          .where((catalog) => catalog.supportsExtra('search'))
          .toList();
      if (searchable.isNotEmpty)
        return _bestSortedCatalog(searchable, sort) ?? searchable.first;
    }

    final hasGenre = genre != null && genre != 'All genres';
    if (hasGenre) {
      final genreCatalogs = byType
          .where((catalog) => catalog.supportsExtra('genre'))
          .toList();
      if (genreCatalogs.isNotEmpty) {
        final yearFilter = RegExp(r'^\d{4}$').hasMatch(genre.trim());
        if (yearFilter) {
          final selectedYear = genre.trim();
          final yearCatalogs = genreCatalogs
              .where(
                (catalog) =>
                    catalog.extraOptions('genre').contains(selectedYear),
              )
              .toList();
          if (yearCatalogs.isNotEmpty) {
            return _bestSortedCatalog(yearCatalogs, sort) ?? yearCatalogs.first;
          }
          return null;
        }
        return _bestSortedCatalog(genreCatalogs, sort) ?? genreCatalogs.first;
      }
    }

    return _bestSortedCatalog(byType, sort);
  }

  _AddonCatalog? _bestSortedCatalog(
    List<_AddonCatalog> catalogs,
    CatalogSort sort,
  ) {
    final keywords = switch (sort) {
      CatalogSort.top => const ['popular', 'top', 'trending', 'netflix'],
      CatalogSort.topRated => const [
        'top_rated',
        'top rated',
        'rating',
        'best',
      ],
      CatalogSort.newest => const ['new', 'latest', 'recent'],
      CatalogSort.oldest => const ['oldest', 'classic'],
      CatalogSort.alphaAsc => const ['a-z', 'az', 'alphabetical'],
      CatalogSort.alphaDesc => const ['z-a', 'za'],
      CatalogSort.nowPlaying => const ['now_playing', 'now playing', 'new'],
      CatalogSort.airingToday => const [
        'airing_today',
        'airing today',
        'today',
      ],
      CatalogSort.onTv => const ['on_tv', 'on tv', 'currently airing'],
      CatalogSort.year => const ['new', 'recent', 'year', 'latest'],
      CatalogSort.upcoming => const ['upcoming', 'coming soon'],
      CatalogSort.imdbRating => const ['featured', 'imdb', 'rating', 'best'],
      CatalogSort.hiddenGems => const [
        'hidden',
        'hidden gems',
        'gems',
        'obscure',
      ],
    };
    for (final catalog in catalogs) {
      final label = '${catalog.id} ${catalog.name}'.toLowerCase();
      if (keywords.any(label.contains)) return catalog;
    }
    return sort == CatalogSort.top ? catalogs.first : null;
  }
}

class _AddonCatalog {
  const _AddonCatalog({
    required this.id,
    required this.type,
    required this.name,
    required this.extra,
    required this.extraOptionValues,
  });

  final String id;
  final String type;
  final String name;
  final List<String> extra;
  final Map<String, List<String>> extraOptionValues;

  factory _AddonCatalog.fromJson(Map<String, dynamic> json) {
    return _AddonCatalog(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      name: (json['name'] ?? json['id'] ?? '').toString(),
      extra: _extraNames(json['extra']),
      extraOptionValues: _extraOptions(json['extra']),
    );
  }

  bool supportsExtra(String name) => extra.contains(name);

  List<String> extraOptions(String name) => extraOptionValues[name] ?? const [];
}

Uri _addonCatalogUri(
  String manifestUrl, {
  required MediaType type,
  required String catalogId,
  required String catalogType,
  required int skip,
  String? genre,
  String? search,
  required bool supportsGenre,
  required bool supportsSearch,
  required bool supportsSkip,
}) {
  final base = _addonBaseUrl(manifestUrl);
  final extras = <String>[];
  final cleanedSearch = search?.trim();
  if (supportsSearch && cleanedSearch != null && cleanedSearch.isNotEmpty) {
    extras.add('search=${Uri.encodeComponent(cleanedSearch)}');
  }
  if (supportsGenre && genre != null && genre != 'All genres') {
    extras.add('genre=${Uri.encodeComponent(genre)}');
  }
  if (supportsSkip && skip > 0) {
    extras.add('skip=$skip');
  }
  final extraPath = extras.isEmpty ? '' : '/${extras.join('&')}';
  final effectiveType = catalogType.trim().isEmpty
      ? type.compatTypeValue
      : catalogType;
  return Uri.parse('$base/catalog/$effectiveType/$catalogId$extraPath.json');
}

List<Uri> _addonResourceUris(
  String manifestUrl, {
  required String resource,
  required String type,
  required String id,
}) {
  final base = _addonBaseUrl(manifestUrl);
  final encoded = Uri.parse(
    '$base/$resource/$type/${Uri.encodeComponent(id)}.json',
  );
  final raw = Uri.tryParse('$base/$resource/$type/$id.json');
  if (raw == null || raw == encoded) return [encoded];
  return [encoded, raw];
}

String _addonBaseUrl(String manifestUrl) {
  final manifestIndex = manifestUrl.toLowerCase().lastIndexOf('/manifest.json');
  if (manifestIndex >= 0) return manifestUrl.substring(0, manifestIndex);
  return manifestUrl.endsWith('/')
      ? manifestUrl.substring(0, manifestUrl.length - 1)
      : manifestUrl;
}

String _addonProviderId(UserAddon addon) {
  return 'addon-${addon.id}';
}

String _resolverProviderIdFor(String providerId) {
  return switch (providerId.trim().toLowerCase()) {
    'theta' => 'popr',
    'rho' => 'cinesu',
    _ => providerId,
  };
}

PlaybackSource _sourceWithProviderId(PlaybackSource source, String providerId) {
  if (source.providerId == providerId) return source;
  return PlaybackSource(
    providerId: providerId,
    name: source.name,
    url: source.url,
    type: source.type,
    quality: source.quality,
    sourceClass: source.sourceClass,
    headers: source.headers,
    subtitles: source.subtitles,
    drm: source.drm,
  );
}

PlaybackSourceClass _addonSourceClass(
  Map<String, dynamic> stream, {
  required String url,
}) {
  if (_looksAccountRequiredStream(stream) || _looksDebridStream(stream, url)) {
    return PlaybackSourceClass.debrid;
  }
  return PlaybackSourceClass.direct;
}

bool _looksDebridStream(Map<String, dynamic> stream, String url) {
  final text = [
    stream['name'],
    stream['title'],
    stream['description'],
    stream['behaviorHints'],
    url,
  ].join(' ').toLowerCase();
  return text.contains('debrid') ||
      text.contains('cached') ||
      text.contains('premium') ||
      text.contains('usenet');
}

String _streamName(Map<String, dynamic> stream, String fallback) {
  final title = (stream['title'] ?? '').toString().trim();
  final name = (stream['name'] ?? '').toString().trim();
  if (title.isNotEmpty && name.isNotEmpty) return '$name - $title';
  if (title.isNotEmpty) return title;
  if (name.isNotEmpty) return name;
  return fallback;
}

String? _streamQuality(Map<String, dynamic> stream) {
  final title =
      '${stream['name'] ?? ''} ${stream['title'] ?? ''} ${stream['description'] ?? ''}';
  final match = RegExp(
    r'\b(2160p|1440p|1080p|720p|480p|360p|4k)\b',
    caseSensitive: false,
  ).firstMatch(title);
  return match?.group(1)?.toUpperCase();
}

String? _streamType(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('.m3u8')) return 'hls';
  if (lower.contains('.mpd')) return 'dash';
  return null;
}

bool _looksLikeNativeStreamUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  final scheme = uri?.scheme.trim().toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

bool _looksLikeP2pStreamUrl(String url) {
  final lower = url.trim().toLowerCase();
  return lower.startsWith('magnet:') ||
      lower.startsWith('btih:') ||
      lower.startsWith('torrent:');
}

bool _looksLikeDirectMediaUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.m3u8') ||
      lower.contains('.mpd') ||
      lower.contains('.mp4') ||
      lower.contains('.mkv');
}

bool _looksLikeExternalDirectStream(Map<String, dynamic> stream, String url) {
  if (!_looksLikeNativeStreamUrl(url)) return false;
  if (_looksLikeDirectMediaUrl(url)) return true;
  if (_looksDebridStream(stream, url)) return true;

  final text =
      [
            stream['name'],
            stream['title'],
            stream['description'],
            stream['message'],
            stream['error'],
            stream['behaviorHints'],
            url,
          ]
          .whereType<Object>()
          .map((value) => value.toString().toLowerCase())
          .join(' ');
  final hasQuality = RegExp(
    r'\b(2160p|1440p|1080p|720p|480p|360p|4k)\b',
    caseSensitive: false,
  ).hasMatch(text);
  final hasDirectHint = RegExp(
    r'\b(hls|dash|mp4|mkv|cached|cache|direct|playlist|file|stream)\b',
    caseSensitive: false,
  ).hasMatch(text);
  return hasQuality && hasDirectHint;
}

String _youtubeWatchUrl(String ytId) {
  final cleaned = ytId.trim();
  if (cleaned.startsWith('http://') || cleaned.startsWith('https://')) {
    return cleaned;
  }
  return 'https://www.youtube.com/watch?v=${Uri.encodeComponent(cleaned)}';
}

bool _looksAccountRequiredStream(Map<String, dynamic> stream) {
  final text =
      [
            stream['name'],
            stream['title'],
            stream['description'],
            stream['message'],
            stream['error'],
            stream['externalUrl'],
          ]
          .whereType<Object>()
          .map((value) => value.toString().toLowerCase())
          .join(' ');
  return text.contains('debrid') ||
      text.contains('cached') ||
      text.contains('premium') ||
      text.contains('usenet') ||
      text.contains('account') ||
      text.contains('login') ||
      text.contains('api key') ||
      text.contains('configure');
}

Map<String, String> _streamHeaders(Map<String, dynamic> stream) {
  final headers = <String, String>{};
  void addHeaders(dynamic value) {
    if (value is! Map) return;
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      final headerValue = entry.value?.toString().trim() ?? '';
      if (key.isNotEmpty && headerValue.isNotEmpty) headers[key] = headerValue;
    }
  }

  addHeaders(stream['headers']);
  final behaviorHints = stream['behaviorHints'];
  if (behaviorHints is Map) {
    final proxyHeaders = behaviorHints['proxyHeaders'];
    if (proxyHeaders is Map) {
      addHeaders(proxyHeaders['request']);
    }
  }
  return headers;
}

List<String> _resourceNames(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) {
        if (item is String) return item;
        if (item is Map) return (item['name'] ?? '').toString();
        return '';
      })
      .where((item) => item.isNotEmpty)
      .toList();
}

List<String> _extraNames(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((item) => (item['name'] ?? '').toString())
      .where((item) => item.isNotEmpty)
      .toList();
}

Map<String, List<String>> _extraOptions(dynamic value) {
  if (value is! List) return const <String, List<String>>{};
  final result = <String, List<String>>{};
  for (final item in value.whereType<Map<String, dynamic>>()) {
    final name = (item['name'] ?? '').toString();
    if (name.isEmpty) continue;
    final options = _stringList(item['options']);
    if (options.isNotEmpty) result[name] = options;
  }
  return result;
}

Map<String, List<String>> _stringListMap(dynamic value) {
  if (value is! Map) return const <String, List<String>>{};
  return {
    for (final entry in value.entries)
      entry.key.toString(): _stringList(entry.value),
  };
}

List<T> _mapList<T>(
  dynamic value,
  T Function(Map<String, dynamic> json) convert,
) {
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().map(convert).toList();
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toList();
}

int? _intOrNull(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

int? _firstInt(Map<dynamic, dynamic> value, List<String> keys) {
  for (final key in keys) {
    final parsed = _intOrNull(value[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

bool _isUsefulProviderHealthLabel(String label) {
  final normalized = label.trim().toLowerCase();
  return normalized == 'available' ||
      normalized == 'healthy' ||
      normalized == 'good' ||
      normalized == 'limited' ||
      normalized == 'partial' ||
      normalized == 'slow' ||
      normalized == 'offline' ||
      normalized == 'dead' ||
      normalized == 'failed';
}

String _providerHealthLabelFromResolverRow(Map<dynamic, dynamic> row) {
  final state = (row['state'] ?? row['label'] ?? '').toString().toLowerCase();
  final successes = _intOrNull(row['successCount']) ?? 0;
  final failures = _intOrNull(row['failureCount']) ?? 0;
  final timeouts = _intOrNull(row['timeoutCount']) ?? 0;
  final noSources = _intOrNull(row['noSourceCount']) ?? 0;
  final latencyMs =
      _intOrNull(row['medianMs']) ??
      _intOrNull(row['avgLatencyMs']) ??
      _intOrNull(row['lastLatencyMs']) ??
      0;
  final sourceCount =
      _intOrNull(row['sourceCount']) ??
      _intOrNull(row['avgSourceCount']) ??
      _intOrNull(row['lastSourceCount']) ??
      0;

  if (state == 'healthy' || state == 'available') return 'Available';
  if (state == 'cooldown' || state == 'protected') return 'Limited';
  if (state == 'offline' || state == 'dead' || state == 'failed') {
    return 'Offline';
  }
  if (successes > 0 || sourceCount > 0) {
    if (latencyMs >= 9000 || timeouts > 0) return 'Slow';
    if (failures > successes || noSources > successes) return 'Limited';
    return 'Available';
  }
  if (timeouts > 0) return 'Slow';
  if (failures > 0 || noSources > 0 || state == 'degraded') return 'Limited';
  return 'Not checked';
}

bool _looksLikeYear(String value) {
  final trimmed = value.trim();
  final parsed = int.tryParse(trimmed);
  return parsed != null && parsed >= 1900 && parsed <= DateTime.now().year + 2;
}
