import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_item.dart';
import 'diagnostic_log.dart';
import 'p2p_indexer_connectors.dart';
import 'p2p_stream_bridge.dart';
import 'playback_provider.dart';
import 'source_ranking.dart';
import 'stream_api.dart'
    show
        AccountLibrarySyncPushResult,
        AccountLibrarySyncSnapshotResult,
        RuntimeAppPolicy;

final NativeProviderHealth _untestedProviderHealth = NativeProviderHealth(
  status: NativeProviderHealthStatus.untested,
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

enum NativeProviderHealthStatus {
  untested,
  checkedNoSample,
  ready,
  slow,
  limited,
  protected,
  noSource,
  failing;

  String get label {
    return switch (this) {
      NativeProviderHealthStatus.untested => 'Not checked',
      NativeProviderHealthStatus.checkedNoSample => 'Not checked',
      NativeProviderHealthStatus.ready => 'Available',
      NativeProviderHealthStatus.slow => 'Slow',
      NativeProviderHealthStatus.limited => 'Limited',
      NativeProviderHealthStatus.protected => 'Not checked',
      NativeProviderHealthStatus.noSource => 'Limited',
      NativeProviderHealthStatus.failing => 'Offline',
    };
  }
}

class NativeProviderHealth {
  const NativeProviderHealth({
    required this.status,
    required this.updatedAt,
    this.sourceCount,
    this.responseMillis,
  });

  final NativeProviderHealthStatus status;
  final DateTime updatedAt;
  final int? sourceCount;
  final int? responseMillis;
}

class DiscoveryIntent {
  const DiscoveryIntent({
    required this.type,
    required this.sort,
    required this.genre,
    required this.createdAt,
  });

  final MediaType type;
  final CatalogSort sort;
  final String genre;
  final DateTime createdAt;
}

class BrowseFilterPreference {
  const BrowseFilterPreference({
    this.type = MediaType.movie,
    this.sortByType = const <String, CatalogSort>{},
    this.yearByType = const <String, String>{},
    this.genreByType = const <String, String>{},
    this.originByType = const <String, String>{},
  });

  factory BrowseFilterPreference.fromJson(Map<String, dynamic> json) {
    return BrowseFilterPreference(
      type: _mediaTypeFromStoredName(json['type']?.toString()),
      sortByType: _browseSortsFromJson(json['sortByType']),
      yearByType: _browseStringsFromJson(json['yearByType']),
      genreByType: _browseGenresFromJson(json['genreByType']),
      originByType: _browseStringsFromJson(json['originByType']),
    );
  }

  final MediaType type;
  final Map<String, CatalogSort> sortByType;
  final Map<String, String> yearByType;
  final Map<String, String> genreByType;
  final Map<String, String> originByType;

  CatalogSort sortFor(MediaType type) {
    return sortByType[type.compatTypeValue] ?? CatalogSort.top;
  }

  String genreFor(MediaType type) {
    final value = genreByType[type.compatTypeValue]?.trim();
    return value == null || value.isEmpty ? 'All genres' : value;
  }

  String yearFor(MediaType type) {
    final value = yearByType[type.compatTypeValue]?.trim();
    return value == null || value.isEmpty ? 'All' : value;
  }

  String originFor(MediaType type) {
    final value = originByType[type.compatTypeValue]?.trim().toUpperCase();
    return value == null || !RegExp(r'^[A-Z]{2}$').hasMatch(value) ? '' : value;
  }

  BrowseFilterPreference remember({
    required MediaType type,
    required CatalogSort sort,
    required String year,
    required String genre,
    required String origin,
  }) {
    final nextSortByType = Map<String, CatalogSort>.from(sortByType);
    final nextYearByType = Map<String, String>.from(yearByType);
    final nextGenreByType = Map<String, String>.from(genreByType);
    final nextOriginByType = Map<String, String>.from(originByType);
    final key = type.compatTypeValue;
    nextSortByType[key] = sort;
    nextYearByType[key] = year.trim().isEmpty ? 'All' : year.trim();
    nextGenreByType[key] = genre.trim().isEmpty ? 'All genres' : genre.trim();
    final cleanOrigin = origin.trim().toUpperCase();
    if (RegExp(r'^[A-Z]{2}$').hasMatch(cleanOrigin)) {
      nextOriginByType[key] = cleanOrigin;
    } else {
      nextOriginByType.remove(key);
    }
    return BrowseFilterPreference(
      type: type,
      sortByType: Map.unmodifiable(nextSortByType),
      yearByType: Map.unmodifiable(nextYearByType),
      genreByType: Map.unmodifiable(nextGenreByType),
      originByType: Map.unmodifiable(nextOriginByType),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.compatTypeValue,
      'sortByType': {
        for (final entry in sortByType.entries) entry.key: entry.value.id,
      },
      'yearByType': yearByType,
      'genreByType': genreByType,
      'originByType': originByType,
    };
  }
}

class TasteProfile {
  const TasteProfile({
    this.genreScores = const <String, double>{},
    this.typeScores = const <String, double>{},
    this.eventCount = 0,
    this.updatedAt,
  });

  factory TasteProfile.fromJson(Map<String, dynamic> json) {
    return TasteProfile(
      genreScores: _scoreMapFromJson(json['genres']),
      typeScores: _scoreMapFromJson(json['types']),
      eventCount: int.tryParse((json['eventCount'] ?? '').toString()) ?? 0,
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
    );
  }

  final Map<String, double> genreScores;
  final Map<String, double> typeScores;
  final int eventCount;
  final DateTime? updatedAt;

  TasteProfile add({
    Map<String, double> genres = const <String, double>{},
    Map<String, double> types = const <String, double>{},
  }) {
    final nextGenres = Map<String, double>.from(genreScores);
    final nextTypes = Map<String, double>.from(typeScores);
    for (final entry in genres.entries) {
      nextGenres[entry.key] = (nextGenres[entry.key] ?? 0) + entry.value;
    }
    for (final entry in types.entries) {
      nextTypes[entry.key] = (nextTypes[entry.key] ?? 0) + entry.value;
    }
    return TasteProfile(
      genreScores: _trimScoreMap(nextGenres, 12),
      typeScores: _trimScoreMap(nextTypes, 6),
      eventCount: eventCount + 1,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'genres': genreScores,
      'types': typeScores,
      'eventCount': eventCount,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class AccountSession {
  const AccountSession({required this.token, required this.expiresAt});

  factory AccountSession.fromJson(Map<String, dynamic> json) {
    return AccountSession(
      token: (json['token'] ?? '').toString().trim(),
      expiresAt:
          DateTime.tryParse((json['expiresAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String token;
  final DateTime expiresAt;

  bool get isValid =>
      token.trim().isNotEmpty && expiresAt.isAfter(DateTime.now());
}

class AccountAdPreferences {
  const AccountAdPreferences({
    required this.adsEnabled,
    this.source = 'account',
    this.resetGuestOnSignOut = true,
  });

  factory AccountAdPreferences.fromJson(dynamic json) {
    final data = json is Map ? Map<String, dynamic>.from(json) : const {};
    return AccountAdPreferences(
      adsEnabled: _boolFromAccountAdValue(data['adsEnabled'], fallback: true),
      source: (data['source'] ?? 'account').toString().trim().isEmpty
          ? 'account'
          : (data['source'] ?? 'account').toString().trim(),
      resetGuestOnSignOut: data['resetGuestOnSignOut'] != false,
    );
  }

  final bool adsEnabled;
  final String source;
  final bool resetGuestOnSignOut;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'adsEnabled': adsEnabled,
      'source': source,
      'resetGuestOnSignOut': resetGuestOnSignOut,
    };
  }
}

class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.email,
    this.username = '',
    this.emoji = '',
    this.leaderboardOptIn = false,
    this.usernameLocked = false,
    this.adPreferences = const AccountAdPreferences(adsEnabled: true),
    this.createdAt,
    this.lastLoginAt,
  });

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    return AccountProfile(
      id: (json['id'] ?? '').toString().trim(),
      email: (json['email'] ?? '').toString().trim(),
      username: (json['username'] ?? '').toString().trim(),
      emoji: (json['emoji'] ?? '').toString().trim(),
      leaderboardOptIn: json['leaderboardOptIn'] == true,
      usernameLocked: json['usernameLocked'] == true,
      adPreferences: AccountAdPreferences.fromJson(json['adPreferences']),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      lastLoginAt: DateTime.tryParse((json['lastLoginAt'] ?? '').toString()),
    );
  }

  final String id;
  final String email;
  final String username;
  final String emoji;
  final bool leaderboardOptIn;
  final bool usernameLocked;
  final AccountAdPreferences adPreferences;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  bool get isUsable => id.isNotEmpty && email.isNotEmpty;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'email': email,
      if (username.isNotEmpty) 'username': username,
      if (emoji.isNotEmpty) 'emoji': emoji,
      'leaderboardOptIn': leaderboardOptIn,
      'usernameLocked': usernameLocked,
      'adPreferences': adPreferences.toJson(),
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (lastLoginAt != null) 'lastLoginAt': lastLoginAt!.toIso8601String(),
    };
  }
}

bool _boolFromAccountAdValue(dynamic value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return fallback;
}

enum AccountLibrarySyncPhase { idle, syncing, synced, retrying }

class AccountLibrarySyncStatus {
  const AccountLibrarySyncStatus({
    required this.phase,
    required this.updatedAt,
  });

  const AccountLibrarySyncStatus.idle()
    : phase = AccountLibrarySyncPhase.idle,
      updatedAt = null;

  final AccountLibrarySyncPhase phase;
  final DateTime? updatedAt;

  String get safeLabel {
    return switch (phase) {
      AccountLibrarySyncPhase.idle => 'Library sync starts after sign-in',
      AccountLibrarySyncPhase.syncing => 'Library sync in progress',
      AccountLibrarySyncPhase.synced => 'Library sync up to date',
      AccountLibrarySyncPhase.retrying => 'Library sync will retry',
    };
  }
}

class UserAddon {
  const UserAddon({
    required this.id,
    required this.name,
    required this.manifestUrl,
    this.active = false,
  });

  final String id;
  final String name;
  final String manifestUrl;
  final bool active;

  factory UserAddon.fromJson(Map<String, dynamic> json) {
    return UserAddon(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Add-on').toString(),
      manifestUrl: (json['manifestUrl'] ?? '').toString(),
      active: json['active'] == true,
    );
  }

  UserAddon copyWith({
    String? id,
    String? name,
    String? manifestUrl,
    bool? active,
  }) {
    return UserAddon(
      id: id ?? this.id,
      name: name ?? this.name,
      manifestUrl: manifestUrl ?? this.manifestUrl,
      active: active ?? this.active,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'manifestUrl': manifestUrl,
      'active': active,
    };
  }
}

enum PersonalServerType {
  plex,
  jellyfin,
  emby;

  String get id => switch (this) {
    PersonalServerType.plex => 'plex',
    PersonalServerType.jellyfin => 'jellyfin',
    PersonalServerType.emby => 'emby',
  };

  String get label => switch (this) {
    PersonalServerType.plex => 'Plex',
    PersonalServerType.jellyfin => 'Jellyfin',
    PersonalServerType.emby => 'Emby',
  };

  static PersonalServerType fromId(String value) {
    return switch (value.trim().toLowerCase()) {
      'jellyfin' => PersonalServerType.jellyfin,
      'emby' => PersonalServerType.emby,
      _ => PersonalServerType.plex,
    };
  }
}

class PersonalServerConnection {
  const PersonalServerConnection({
    required this.type,
    required this.serverUrl,
    required this.updatedAt,
    this.username = '',
    this.token = '',
    this.password = '',
    this.userId = '',
    this.active = true,
  });

  factory PersonalServerConnection.fromJson(Map<String, dynamic> json) {
    return PersonalServerConnection(
      type: PersonalServerType.fromId((json['type'] ?? '').toString()),
      serverUrl: _safeHttpUrlOrEmpty(json['serverUrl']),
      username: (json['username'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      active: json['active'] != false,
      updatedAt:
          DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final PersonalServerType type;
  final String serverUrl;
  final String username;
  final String token;
  final String password;
  final String userId;
  final bool active;
  final DateTime updatedAt;

  bool get isConfigured {
    if (serverUrl.trim().isEmpty) return false;
    return switch (type) {
      PersonalServerType.plex => token.trim().isNotEmpty,
      PersonalServerType.jellyfin || PersonalServerType.emby =>
        username.trim().isNotEmpty &&
            userId.trim().isNotEmpty &&
            (token.trim().isNotEmpty || password.trim().isNotEmpty),
    };
  }

  PersonalServerConnection copyWith({
    String? serverUrl,
    String? username,
    String? token,
    String? password,
    String? userId,
    bool? active,
    DateTime? updatedAt,
  }) {
    return PersonalServerConnection(
      type: type,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      token: token ?? this.token,
      password: password ?? this.password,
      userId: userId ?? this.userId,
      active: active ?? this.active,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.id,
      'serverUrl': serverUrl,
      if (username.trim().isNotEmpty) 'username': username,
      if (token.trim().isNotEmpty) 'token': token,
      if (password.trim().isNotEmpty) 'password': password,
      if (userId.trim().isNotEmpty) 'userId': userId,
      'active': active,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class LocalCatalog {
  const LocalCatalog({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description = '',
    this.itemCount = 0,
  });

  factory LocalCatalog.fromJson(Map<String, dynamic> json) {
    return LocalCatalog(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Local catalog').toString(),
      description: (json['description'] ?? '').toString(),
      itemCount: _intOrNull(json['itemCount']) ?? 0,
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;
  final String name;
  final String description;
  final int itemCount;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'itemCount': itemCount,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class LocalCatalogItem {
  const LocalCatalogItem({
    required this.id,
    required this.catalogId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.mediaKind = 'movie',
    this.tags = const <String>[],
    this.releaseYear,
    this.runtimeSeconds,
    this.posterUrl = '',
    this.backgroundUrl = '',
    this.preferredPlaybackEngine = 'auto',
  });

  factory LocalCatalogItem.fromJson(Map<String, dynamic> json) {
    return LocalCatalogItem(
      id: (json['id'] ?? '').toString(),
      catalogId: (json['catalogId'] ?? '').toString(),
      title: (json['title'] ?? 'Local item').toString(),
      description: (json['description'] ?? '').toString(),
      mediaKind: (json['mediaKind'] ?? 'movie').toString(),
      tags: _stringList(json['tags']),
      releaseYear: _intOrNull(json['releaseYear']),
      runtimeSeconds: _intOrNull(json['runtimeSeconds']),
      posterUrl: _safeHttpUrlOrEmpty(json['posterUrl']),
      backgroundUrl: _safeHttpUrlOrEmpty(json['backgroundUrl']),
      preferredPlaybackEngine: _safePlaybackEngineOrAuto(
        json['preferredPlaybackEngine'],
      ),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;
  final String catalogId;
  final String title;
  final String description;
  final String mediaKind;
  final List<String> tags;
  final int? releaseYear;
  final int? runtimeSeconds;
  final String posterUrl;
  final String backgroundUrl;
  final String preferredPlaybackEngine;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'catalogId': catalogId,
      'title': title,
      'description': description,
      'mediaKind': mediaKind,
      'tags': tags,
      if (releaseYear != null) 'releaseYear': releaseYear,
      if (runtimeSeconds != null) 'runtimeSeconds': runtimeSeconds,
      if (_safeHttpUrlOrEmpty(posterUrl).isNotEmpty)
        'posterUrl': _safeHttpUrlOrEmpty(posterUrl),
      if (_safeHttpUrlOrEmpty(backgroundUrl).isNotEmpty)
        'backgroundUrl': _safeHttpUrlOrEmpty(backgroundUrl),
      'preferredPlaybackEngine': _safePlaybackEngineOrAuto(
        preferredPlaybackEngine,
      ),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class LocalPickedAssetRef {
  const LocalPickedAssetRef({
    required this.id,
    required this.catalogId,
    required this.itemId,
    required this.mediaKind,
    required this.createdAt,
    required this.updatedAt,
    this.relinkNeeded = true,
    this.proofState = 'picker_pending',
  });

  factory LocalPickedAssetRef.fromJson(Map<String, dynamic> json) {
    return LocalPickedAssetRef(
      id: (json['id'] ?? '').toString(),
      catalogId: (json['catalogId'] ?? '').toString(),
      itemId: (json['itemId'] ?? '').toString(),
      mediaKind: (json['mediaKind'] ?? 'video').toString(),
      relinkNeeded: json['relinkNeeded'] != false,
      proofState: (json['proofState'] ?? 'picker_pending').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;
  final String catalogId;
  final String itemId;
  final String mediaKind;
  final bool relinkNeeded;
  final String proofState;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'catalogId': catalogId,
      'itemId': itemId,
      'mediaKind': mediaKind,
      'relinkNeeded': relinkNeeded,
      'proofState': proofState,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class LocalCatalogImportResult {
  const LocalCatalogImportResult({
    required this.catalogName,
    required this.itemCount,
  });

  final String catalogName;
  final int itemCount;
}

class VerifiedPlaybackSource {
  const VerifiedPlaybackSource({
    required this.source,
    required this.engineId,
    required this.cachedAt,
    this.confidence = 10,
    this.successCount = 1,
    this.failureCount = 0,
    this.lastFailureReason,
    this.lastFailureAt,
  });

  factory VerifiedPlaybackSource.fromJson(Map<String, dynamic> json) {
    final sourceJson = json['source'];
    return VerifiedPlaybackSource(
      source: sourceJson is Map<String, dynamic>
          ? PlaybackSource.fromJson(sourceJson)
          : const PlaybackSource(providerId: '', name: '', url: ''),
      engineId: (json['engineId'] ?? '').toString(),
      cachedAt:
          DateTime.tryParse(json['cachedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      confidence: _intOrNull(json['confidence']) ?? 10,
      successCount: _intOrNull(json['successCount']) ?? 1,
      failureCount: _intOrNull(json['failureCount']) ?? 0,
      lastFailureReason: json['lastFailureReason']?.toString(),
      lastFailureAt: DateTime.tryParse(json['lastFailureAt']?.toString() ?? ''),
    );
  }

  final PlaybackSource source;
  final String engineId;
  final DateTime cachedAt;
  final int confidence;
  final int successCount;
  final int failureCount;
  final String? lastFailureReason;
  final DateTime? lastFailureAt;

  VerifiedPlaybackSource copyWith({
    PlaybackSource? source,
    String? engineId,
    DateTime? cachedAt,
    int? confidence,
    int? successCount,
    int? failureCount,
    String? lastFailureReason,
    DateTime? lastFailureAt,
    bool clearFailure = false,
  }) {
    return VerifiedPlaybackSource(
      source: source ?? this.source,
      engineId: engineId ?? this.engineId,
      cachedAt: cachedAt ?? this.cachedAt,
      confidence: confidence ?? this.confidence,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
      lastFailureReason: clearFailure
          ? null
          : lastFailureReason ?? this.lastFailureReason,
      lastFailureAt: clearFailure ? null : lastFailureAt ?? this.lastFailureAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'source': source.toJson(),
      'engineId': engineId,
      'cachedAt': cachedAt.toIso8601String(),
      'confidence': confidence,
      'successCount': successCount,
      'failureCount': failureCount,
      if (lastFailureReason != null) 'lastFailureReason': lastFailureReason,
      if (lastFailureAt != null)
        'lastFailureAt': lastFailureAt!.toIso8601String(),
    };
  }
}

class LibraryList {
  const LibraryList({
    required this.id,
    required this.name,
    required this.itemIds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<String> itemIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory LibraryList.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawItems = json['itemIds'] is List
        ? json['itemIds'] as List
        : json['items'] is List
        ? json['items'] as List
        : const [];
    return LibraryList(
      id: (json['id'] ?? '').toString(),
      name: _normalizeLibraryListName((json['name'] ?? '').toString()),
      itemIds: _dedupeLibraryListItemIds(
        rawItems.map((item) => item.toString()),
      ),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? now,
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()) ?? now,
    );
  }

  LibraryList copyWith({
    String? id,
    String? name,
    List<String>? itemIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LibraryList(
      id: id ?? this.id,
      name: name ?? this.name,
      itemIds: itemIds ?? this.itemIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'itemIds': itemIds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static String _normalizeLibraryListName(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'Untitled list';
    return normalized.length <= 48 ? normalized : normalized.substring(0, 48);
  }

  static List<String> _dedupeLibraryListItemIds(Iterable<String> ids) {
    final seen = <String>{};
    final output = <String>[];
    for (final id in ids) {
      final trimmed = id.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      output.add(trimmed);
    }
    return output;
  }
}

class AppState {
  AppState._();

  static const String autoNativeProviderId = 'auto';
  static const String accentGreen = 'green';
  static const String accentPurple = 'purple';
  static const String accentOcean = 'ocean';
  static const String accentAmber = 'amber';
  static const String accentCustom = 'custom';
  static const String _nativeProviderKey = 'selected_native_provider';
  static const String _libraryKey = 'saved_library';
  static const String _libraryListsKey = 'library_lists_v1';
  static const String _themeModeKey = 'theme_mode';
  static const String _pureBlackThemeKey = 'pure_black_theme';
  static const String _useDeviceAccentKey = 'use_device_accent';
  static const String _accentThemeKey = 'accent_theme';
  static const String _customAccentColorKey = 'custom_accent_color';
  static const String _startupTabModeKey = 'startup_tab_mode';
  static const String _startupBehaviorKey = 'startup_behavior';
  static const String _shellTabKey = 'shell_tab';
  static const String _compactLayoutKey = 'compact_layout';
  static const String _reduceMotionKey = 'reduce_motion';
  static const String _textSizeKey = 'text_size';
  static const String _navigationStyleKey = 'navigation_style';
  static const String _homeDensityKey = 'home_density';
  static const String _artworkMotionKey = 'artwork_motion';
  static const String _confirmDestructiveActionsKey =
      'confirm_destructive_actions';
  static const String _hapticsEnabledKey = 'haptics_enabled';
  static const String _statusMessageStyleKey = 'status_message_style';
  static const String _posterImageIntensityKey = 'poster_image_intensity';
  static const String _systemBarStyleKey = 'system_bar_style';
  static const String _firstRunWelcomeSeenKey = 'first_run_welcome_seen';
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _notificationDialogsEnabledKey =
      'notification_dialogs_enabled';
  static const String _notificationInterstitialsEnabledKey =
      'notification_interstitials_enabled';
  static const String _notificationDailyCountDateKey =
      'notification_daily_count_date';
  static const String _notificationDailyCountKey = 'notification_daily_count';
  static const String _notificationLastCurationEditionKey =
      'notification_last_curation_edition';
  static const String _notificationLastCurationDialogEditionKey =
      'notification_last_curation_dialog_edition';
  static const String _notificationLastCurationDialogDateKey =
      'notification_last_curation_dialog_date';
  static const String _notificationSeenCampaignsKey =
      'notification_seen_campaigns';
  static const String _notificationLastInterstitialAtKey =
      'notification_last_interstitial_at';
  static const String _notificationLastSmartSuggestionAtKey =
      'notification_last_smart_suggestion_at';
  static const String _rewardedVideoAdsEnabledKey =
      'rewarded_video_ads_enabled';
  static const String _interstitialAdsEnabledKey = 'interstitial_ads_enabled';
  static const String _bannerAdsEnabledKey = 'banner_ads_enabled';
  static const String _adDisableRewardUnlockKey = 'ad_disable_reward_unlock_v1';
  static const String _sampleAdDefaultsMigratedKey =
      'sample_ad_defaults_migrated_v1';
  static const String _showMatureContentKey = 'show_mature_content';
  static const String _matureContentChoiceSeenKey =
      'mature_content_choice_seen_v1';
  static const String _browseFilterPreferenceKey = 'browse_filter_preference';
  static const String _searchHistoryKey = 'search_history';
  static const String _tasteProfileKey = 'taste_profile';
  static const String _continueWatchingKey = 'continue_watching';
  static const String _completedWatchingKey = 'completed_watching';
  static const String _retainedActiveWatchSecondsKey =
      'retained_active_watch_seconds_v1';
  static const String _verifiedPlaybackSourcesKey = 'verified_playback_sources';
  static const String _addonRouteAttemptHistoryKey =
      'addon_route_attempt_history';
  static const String _providerHealthKey = 'provider_health';
  static const String _providerHealthCheckKey = 'provider_health_last_check';
  static const String _nativePlaybackOverridesEnabledKey =
      'native_playback_overrides_enabled';
  static const String _nativePlaybackOverridesKey = 'native_playback_overrides';
  static const String _nativePlayerVolumeKey = 'native_player_volume';
  static const String _nativePlayerBrightnessKey = 'native_player_brightness';
  static const String _playerBehaviorSettingsKey = 'player_behavior_settings';
  static const int _playerBehaviorSettingsSchemaVersion = 10;
  static const String _batteryDataSettingsKey = 'battery_data_settings';
  static const String _userAddonsKey = 'user_addons';
  static const String _p2pIndexerConnectorsKey = 'p2p_indexer_connectors';
  static const String _p2pIndexerConnectorsEnabledKey =
      'p2p_indexer_connectors_enabled';
  static const String _p2pIndexerConnectorsAcknowledgedKey =
      'p2p_indexer_connectors_acknowledged';
  static const String _personalServerConnectionsKey =
      'personal_server_connections';
  static const String _localCatalogsKey = 'local_catalogs';
  static const String _localCatalogItemsKey = 'local_catalog_items';
  static const String _localPickedAssetRefsKey = 'local_picked_asset_refs';
  static const String _defaultCatalogEnabledKey = 'default_catalog_enabled';
  static const String _defaultProvidersEnabledKey = 'default_providers_enabled';
  static const String _defaultSubtitlesEnabledKey = 'default_subtitles_enabled';
  static const String _defaultTrailersEnabledKey = 'default_trailers_enabled';
  static const String _tvSourcesEnabledKey = 'tv_sources_enabled';
  static const String _publicIptvEnabledKey = 'public_iptv_enabled';
  static const String _defaultSourceDisclaimerAcceptedKey =
      'default_source_disclaimer_accepted';
  static const String _addonDisclaimerAcceptedKey = 'addon_disclaimer_accepted';
  static const String _experimentalDisclaimerAcceptedKey =
      'experimental_disclaimer_accepted';
  static const String _accountProfileKey = 'account_profile_v1';
  static const String _accountSecureSessionTokenKey =
      'account_session_token_v1';
  static const String _accountSecureSessionExpiresAtKey =
      'account_session_expires_at_v1';
  static const String _leaderboardScopeKey = 'leaderboard_scope_v1';
  static const int _providerHealthSchemaVersion = 2;
  static const int _verifiedPlaybackSourceLimit = 80;
  static const int addonRouteAttemptHistoryLimit = 24;
  static const int searchHistoryLimit = 6;
  static const Duration providerHealthRefreshCooldown = Duration.zero;
  static const Duration interactionQuietWindow = Duration(seconds: 4);
  static SharedPreferences? _prefs;
  static SharedPreferences? get prefs => _prefs;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final ValueNotifier<bool> preferencesReady = ValueNotifier<bool>(
    false,
  );
  static DateTime? _lastProviderHealthCheckAt;
  static DateTime? _lastUserInteractionAt;
  static int _retainedActiveWatchSeconds = 0;

  static final ValueNotifier<String> nativeProviderId = ValueNotifier<String>(
    autoNativeProviderId,
  );
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );
  static final ValueNotifier<bool> pureBlackTheme = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> useDeviceAccent = ValueNotifier<bool>(false);
  static final ValueNotifier<String> accentThemeId = ValueNotifier<String>(
    accentGreen,
  );
  static final ValueNotifier<Color> customAccentColor = ValueNotifier<Color>(
    const Color(0xFF1DB954),
  );
  static final ValueNotifier<String> startupTabMode = ValueNotifier<String>(
    'home',
  );
  static final ValueNotifier<String> startupBehavior = ValueNotifier<String>(
    'normal',
  );
  static final ValueNotifier<bool> compactLayout = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> reduceMotion = ValueNotifier<bool>(false);
  static final ValueNotifier<String> textSize = ValueNotifier<String>(
    'default',
  );
  static final ValueNotifier<String> navigationStyle = ValueNotifier<String>(
    'always',
  );
  static final ValueNotifier<String> homeDensity = ValueNotifier<String>(
    'comfortable',
  );
  static final ValueNotifier<bool> artworkMotion = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> confirmDestructiveActions =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> hapticsEnabled = ValueNotifier<bool>(true);
  static final ValueNotifier<String> statusMessageStyle = ValueNotifier<String>(
    'floating',
  );
  static final ValueNotifier<String> posterImageIntensity =
      ValueNotifier<String>('normal');
  static final ValueNotifier<String> systemBarStyle = ValueNotifier<String>(
    'match',
  );
  static final ValueNotifier<bool> firstRunWelcomeSeen = ValueNotifier<bool>(
    false,
  );
  static final ValueNotifier<bool> notificationsEnabled = ValueNotifier<bool>(
    true,
  );
  static final ValueNotifier<bool> notificationDialogsEnabled =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> notificationInterstitialsEnabled =
      ValueNotifier<bool>(true);
  static final ValueNotifier<int> notificationSettingsRevision =
      ValueNotifier<int>(0);
  static final ValueNotifier<bool> rewardedVideoAdsEnabled =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> interstitialAdsEnabled = ValueNotifier<bool>(
    true,
  );
  static final ValueNotifier<bool> bannerAdsEnabled = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> adDisableRewardUnlocked =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> showMatureContent = ValueNotifier<bool>(
    false,
  );
  static final ValueNotifier<bool> matureContentChoiceSeen =
      ValueNotifier<bool>(false);
  static bool _matureContentChoiceInFlight = false;
  static bool _applyingAccountAdPreferences = false;
  static bool get _signedInAdPreferencesActive =>
      accountSession.value?.isValid == true ||
      accountAdPreferences.value != null;
  static final ValueNotifier<AccountSession?> accountSession =
      ValueNotifier<AccountSession?>(null);
  static final ValueNotifier<AccountProfile?> accountProfile =
      ValueNotifier<AccountProfile?>(null);
  static final ValueNotifier<AccountAdPreferences?> accountAdPreferences =
      ValueNotifier<AccountAdPreferences?>(null);
  static final ValueNotifier<RuntimeAppPolicy?> runtimeAppPolicy =
      ValueNotifier<RuntimeAppPolicy?>(null);
  static final ValueNotifier<AccountLibrarySyncStatus>
  accountLibrarySyncStatus = ValueNotifier<AccountLibrarySyncStatus>(
    const AccountLibrarySyncStatus.idle(),
  );
  static final ValueNotifier<String> leaderboardScope = ValueNotifier<String>(
    'weekly',
  );

  static final ValueNotifier<Map<String, CatalogItem>> library =
      ValueNotifier<Map<String, CatalogItem>>(<String, CatalogItem>{});
  static final ValueNotifier<List<LibraryList>> libraryLists =
      ValueNotifier<List<LibraryList>>(const <LibraryList>[]);

  static final ValueNotifier<List<String>> searchHistory =
      ValueNotifier<List<String>>(<String>[]);
  static final ValueNotifier<TasteProfile> tasteProfile =
      ValueNotifier<TasteProfile>(const TasteProfile());
  static final ValueNotifier<DiscoveryIntent?> discoveryIntent =
      ValueNotifier<DiscoveryIntent?>(null);
  static final ValueNotifier<BrowseFilterPreference> browseFilterPreference =
      ValueNotifier<BrowseFilterPreference>(const BrowseFilterPreference());

  static final ValueNotifier<Map<String, ContinueWatchingEntry>>
  continueWatching = ValueNotifier<Map<String, ContinueWatchingEntry>>(
    <String, ContinueWatchingEntry>{},
  );
  static final ValueNotifier<Map<String, CompletedWatchingEntry>>
  completedWatching = ValueNotifier<Map<String, CompletedWatchingEntry>>(
    <String, CompletedWatchingEntry>{},
  );
  static final ValueNotifier<Map<String, List<VerifiedPlaybackSource>>>
  verifiedPlaybackSources =
      ValueNotifier<Map<String, List<VerifiedPlaybackSource>>>(
        <String, List<VerifiedPlaybackSource>>{},
      );
  static final ValueNotifier<List<Map<String, Object?>>>
  addonRouteAttemptHistory = ValueNotifier<List<Map<String, Object?>>>(
    const <Map<String, Object?>>[],
  );
  static final ValueNotifier<Map<String, NativeProviderHealth>>
  nativeProviderHealth = ValueNotifier<Map<String, NativeProviderHealth>>(
    <String, NativeProviderHealth>{},
  );
  static final ValueNotifier<bool> nativePlaybackOverridesEnabled =
      ValueNotifier<bool>(false);
  static final ValueNotifier<NativePlaybackOverrides> nativePlaybackOverrides =
      ValueNotifier<NativePlaybackOverrides>(const NativePlaybackOverrides());
  static final ValueNotifier<double> nativePlayerVolume = ValueNotifier<double>(
    0.5,
  );
  static final ValueNotifier<double> nativePlayerBrightness =
      ValueNotifier<double>(0.5);
  static final ValueNotifier<PlayerBehaviorSettings> playerBehaviorSettings =
      ValueNotifier<PlayerBehaviorSettings>(const PlayerBehaviorSettings());
  static final ValueNotifier<BatteryDataSettings> batteryDataSettings =
      ValueNotifier<BatteryDataSettings>(const BatteryDataSettings());
  static final ValueNotifier<List<UserAddon>> userAddons =
      ValueNotifier<List<UserAddon>>(const <UserAddon>[]);
  static final ValueNotifier<List<P2pIndexerConnector>> p2pIndexerConnectors =
      ValueNotifier<List<P2pIndexerConnector>>(const <P2pIndexerConnector>[]);
  static final ValueNotifier<bool> p2pIndexerConnectorsEnabled =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> p2pIndexerConnectorsAcknowledged =
      ValueNotifier<bool>(false);
  static final ValueNotifier<List<PersonalServerConnection>>
  personalServerConnections = ValueNotifier<List<PersonalServerConnection>>(
    const <PersonalServerConnection>[],
  );
  static final ValueNotifier<List<LocalCatalog>> localCatalogs =
      ValueNotifier<List<LocalCatalog>>(const <LocalCatalog>[]);
  static final ValueNotifier<List<LocalCatalogItem>> localCatalogItems =
      ValueNotifier<List<LocalCatalogItem>>(const <LocalCatalogItem>[]);
  static final ValueNotifier<List<LocalPickedAssetRef>> localPickedAssetRefs =
      ValueNotifier<List<LocalPickedAssetRef>>(const <LocalPickedAssetRef>[]);
  static final ValueNotifier<bool> defaultCatalogEnabled = ValueNotifier<bool>(
    false,
  );
  static final ValueNotifier<bool> defaultProvidersEnabled =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> defaultSubtitlesEnabled =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> defaultTrailersEnabled = ValueNotifier<bool>(
    false,
  );
  static final ValueNotifier<bool> tvSourcesEnabled = ValueNotifier<bool>(
    false,
  );
  static final ValueNotifier<bool> publicIptvEnabled = ValueNotifier<bool>(
    false,
  );
  static final ValueNotifier<bool> defaultSourceDisclaimerAccepted =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> addonDisclaimerAccepted =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> experimentalDisclaimerAccepted =
      ValueNotifier<bool>(false);

  static final ValueNotifier<int> shellTab = ValueNotifier<int>(0);
  static final ValueNotifier<String?> settingsIntent = ValueNotifier<String?>(
    null,
  );
  static Map<String, ContinueWatchingEntry>? _pendingContinueWatching;
  static bool _continueWatchingFlushScheduled = false;
  static bool _accountLibrarySyncApplying = false;
  static bool _accountLibrarySyncApplyingRemote = false;
  static bool _accountLibrarySyncPendingUpload = false;
  static bool _accountLibrarySyncPendingPushOnly = false;
  static String _accountLibrarySyncRevision = '';
  static Timer? _accountLibrarySyncTimer;
  static Future<AccountLibrarySyncSnapshotResult?> Function(String token)?
  _accountLibraryFetch;
  static Future<AccountLibrarySyncPushResult> Function(
    String token,
    Map<String, dynamic> snapshot,
    String baseRevision,
  )?
  _accountLibraryPush;
  static const List<String> nativeProviderOrder = <String>[
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
    'videasy',
    'vidfun',
    'flixhq',
    'flixer',
    '7xstream',
    'meowtv',
  ];
  static const Set<String> _experimentalNativeProviders = <String>{
    'vidrock',
    'vidzee',
    'flixer',
    '7xstream',
  };
  static final Map<String, String> _nativeProviderSuccessByMedia =
      <String, String>{};
  static final Map<String, Map<String, int>> _nativeProviderFailuresByMedia =
      <String, Map<String, int>>{};
  static int _continueWatchingGeneration = 0;

  static int get continueWatchingGeneration => _continueWatchingGeneration;

  static void applyRuntimeAppPolicy(RuntimeAppPolicy? policy) {
    if (policy?.schema != 'juicr.runtime.app_policy.v1') {
      runtimeAppPolicy.value = null;
      return;
    }
    runtimeAppPolicy.value = policy;
  }

  static String get selectedNativeProviderId =>
      _normalizeNativeProviderId(nativeProviderId.value);

  static List<String> orderedNativeProviderIds({
    String? selected,
    String? mediaKey,
  }) {
    final behavior = playerBehaviorSettings.value;
    final useLastWorkingSource = behavior.preferLastWorkingSource;
    final normalized = _normalizeNativeProviderId(
      selected ?? selectedNativeProviderId,
    );
    final autoSelected = normalized == autoNativeProviderId;
    if (!autoSelected) {
      return nativeProviderOrder.contains(normalized)
          ? <String>[normalized]
          : <String>[];
    }
    final allowedProviders = nativeProviderOrder.where((providerId) {
      return !_experimentalNativeProviders.contains(providerId);
    }).toList();

    final memory = behavior.experimentalControlsEnabled
        ? behavior.autoProviderMemory
        : const PlayerBehaviorSettings().autoProviderMemory;
    final preferred = useLastWorkingSource && memory != 'fresh'
        ? _nativeProviderSuccessByMedia[mediaKey]
        : null;
    final failures =
        _nativeProviderFailuresByMedia[mediaKey] ?? const <String, int>{};
    final ordered = _autoProviderOrder(allowedProviders, failures);
    final filtered = memory == 'sticky'
        ? ordered.toList()
        : ordered.where((providerId) {
            if (providerId == preferred) return true;
            return (failures[providerId] ?? 0) <= 0;
          }).toList();

    if (preferred != null &&
        preferred != normalized &&
        filtered.remove(preferred)) {
      filtered.insert(0, preferred);
    }
    return filtered.isEmpty ? ordered : filtered;
  }

  static void recordNativeProviderSuccess({
    required String? mediaKey,
    required String providerId,
    int? sourceCount,
  }) {
    final key = mediaKey?.trim();
    final normalized = _normalizeNativeProviderId(providerId);
    if (key != null && key.isNotEmpty) {
      _nativeProviderSuccessByMedia[key] = normalized;
      final failures = _nativeProviderFailuresByMedia[key];
      failures?.remove(normalized);
    }
    _setNativeProviderHealth(
      normalized,
      NativeProviderHealthStatus.ready,
      sourceCount: sourceCount,
    );
  }

  static void recordResolvedNativeSources({
    required String? mediaKey,
    required List<PlaybackSource> sources,
  }) {
    final counts = <String, int>{};
    for (final source in sources) {
      if (source.url.trim().isEmpty) continue;
      final normalized = _normalizeNativeProviderId(source.providerId);
      if (normalized.isEmpty || normalized.startsWith('addon-')) continue;
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
    if (counts.isEmpty) return;

    final key = mediaKey?.trim();
    final failures = key == null || key.isEmpty
        ? null
        : _nativeProviderFailuresByMedia[key];
    final next = Map<String, NativeProviderHealth>.from(
      nativeProviderHealth.value,
    );
    final now = DateTime.now();
    for (final entry in counts.entries) {
      failures?.remove(entry.key);
      final previous = next[entry.key];
      next[entry.key] = NativeProviderHealth(
        status: NativeProviderHealthStatus.ready,
        updatedAt: now,
        sourceCount: entry.value,
        responseMillis: previous?.responseMillis,
      );
    }
    nativeProviderHealth.value = next;
    unawaited(_persistProviderHealth());
  }

  static void recordNativeProviderFailure({
    required String? mediaKey,
    required String providerId,
    NativeProviderHealthStatus status = NativeProviderHealthStatus.failing,
    int? sourceCount,
    bool updateHealth = true,
  }) {
    final key = mediaKey?.trim();
    final normalized = _normalizeNativeProviderId(providerId);
    final shouldPenalizeMedia = status != NativeProviderHealthStatus.protected;
    if (shouldPenalizeMedia && key != null && key.isNotEmpty) {
      final failures = _nativeProviderFailuresByMedia.putIfAbsent(
        key,
        () => <String, int>{},
      );
      failures[normalized] = (failures[normalized] ?? 0) + 1;
    }
    if (!updateHealth) return;
    _setNativeProviderHealth(normalized, status, sourceCount: sourceCount);
  }

  static NativeProviderHealthStatus nativeProviderHealthFor(String providerId) {
    return nativeProviderHealthDetailsFor(providerId).status;
  }

  static NativeProviderHealth nativeProviderHealthDetailsFor(
    String providerId,
  ) {
    final normalized = _normalizeNativeProviderId(providerId);
    return nativeProviderHealth.value[normalized] ?? _untestedProviderHealth;
  }

  static void clearSampleOnlyNativeProviderHealth({
    Set<String> keepProviderIds = const <String>{},
  }) {
    final keep = keepProviderIds.map(_normalizeNativeProviderId).toSet();
    final next =
        Map<String, NativeProviderHealth>.from(
          nativeProviderHealth.value,
        )..removeWhere((providerId, health) {
          return health.status == NativeProviderHealthStatus.checkedNoSample &&
              !keep.contains(_normalizeNativeProviderId(providerId));
        });
    if (next.length == nativeProviderHealth.value.length) return;
    nativeProviderHealth.value = next;
    unawaited(_persistProviderHealth());
  }

  static void _setNativeProviderHealth(
    String providerId,
    NativeProviderHealthStatus status, {
    int? sourceCount,
    int? responseMillis,
  }) {
    final normalized = _normalizeNativeProviderId(providerId);
    if (normalized.isEmpty) return;
    final previous = nativeProviderHealth.value[normalized];
    final next = Map<String, NativeProviderHealth>.from(
      nativeProviderHealth.value,
    );
    final keepPreviousCount =
        status == NativeProviderHealthStatus.ready ||
        status == NativeProviderHealthStatus.slow ||
        status == NativeProviderHealthStatus.limited ||
        status == NativeProviderHealthStatus.protected;
    next[normalized] = NativeProviderHealth(
      status: status,
      updatedAt: DateTime.now(),
      sourceCount:
          sourceCount ?? (keepPreviousCount ? previous?.sourceCount : null),
      responseMillis: responseMillis ?? previous?.responseMillis,
    );
    nativeProviderHealth.value = next;
    unawaited(_persistProviderHealth());
  }

  static void recordNativeProviderResolve({
    required String providerId,
    required int sourceCount,
    required Duration elapsed,
  }) {
    final previous = nativeProviderHealthDetailsFor(providerId);
    if (sourceCount <= 0 &&
        previous.status == NativeProviderHealthStatus.ready) {
      _setNativeProviderHealth(
        providerId,
        NativeProviderHealthStatus.ready,
        responseMillis: elapsed.inMilliseconds,
      );
      return;
    }

    _setNativeProviderHealth(
      providerId,
      sourceCount > 0
          ? elapsed > const Duration(seconds: 6)
                ? NativeProviderHealthStatus.slow
                : NativeProviderHealthStatus.ready
          : elapsed > const Duration(seconds: 10)
          ? NativeProviderHealthStatus.protected
          : NativeProviderHealthStatus.noSource,
      sourceCount: sourceCount,
      responseMillis: elapsed.inMilliseconds,
    );
  }

  static void recordNativeProviderServerHealth({
    required String providerId,
    required String label,
    int? sourceCount,
    int? responseMillis,
  }) {
    final normalizedLabel = label.trim().toLowerCase();
    final status = switch (normalizedLabel) {
      'available' || 'healthy' || 'good' => NativeProviderHealthStatus.ready,
      'limited' || 'partial' => NativeProviderHealthStatus.limited,
      'slow' => NativeProviderHealthStatus.slow,
      'offline' || 'dead' || 'failed' => NativeProviderHealthStatus.failing,
      _ => NativeProviderHealthStatus.untested,
    };
    _setNativeProviderHealth(
      providerId,
      status,
      sourceCount: sourceCount,
      responseMillis: responseMillis,
    );
  }

  static Duration providerHealthRefreshRemaining() {
    final checkedAt = _lastProviderHealthCheckAt;
    if (checkedAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(checkedAt);
    final remaining = providerHealthRefreshCooldown - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static DateTime? get providerHealthLastCheckedAt =>
      _lastProviderHealthCheckAt;

  static void markUserInteraction([String reason = 'interaction']) {
    _lastUserInteractionAt = DateTime.now();
  }

  static Duration interactionQuietRemaining() {
    final lastInteractionAt = _lastUserInteractionAt;
    if (lastInteractionAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(lastInteractionAt);
    final remaining = interactionQuietWindow - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static bool get isInInteractionQuietWindow =>
      interactionQuietRemaining() > Duration.zero;

  static Future<void> markProviderHealthRefreshStarted() async {
    _lastProviderHealthCheckAt = DateTime.now();
    await _prefs?.setString(
      _providerHealthCheckKey,
      _lastProviderHealthCheckAt!.toIso8601String(),
    );
  }

  static Future<void> saveAccountSession({
    required AccountSession session,
    required AccountProfile profile,
  }) async {
    if (!session.isValid || !profile.isUsable) return;
    accountSession.value = session;
    accountProfile.value = profile;
    applyAccountAdPreferences(profile.adPreferences);
    await _secureStorage.write(
      key: _accountSecureSessionTokenKey,
      value: session.token,
    );
    await _secureStorage.write(
      key: _accountSecureSessionExpiresAtKey,
      value: session.expiresAt.toIso8601String(),
    );
    await _prefs?.setString(_accountProfileKey, jsonEncode(profile.toJson()));
  }

  static Future<void> updateAccountProfileCache(AccountProfile? profile) async {
    accountProfile.value = profile;
    if (profile == null || !profile.isUsable) {
      applyAccountAdPreferences(null);
      await _prefs?.remove(_accountProfileKey);
      return;
    }
    applyAccountAdPreferences(profile.adPreferences);
    await _prefs?.setString(_accountProfileKey, jsonEncode(profile.toJson()));
  }

  static int activeWatchSecondsForAccountSync() {
    return math.max(
      0,
      _retainedActiveWatchSeconds +
          _activeWatchSecondsFromCompletedWatching() +
          _activeWatchSecondsFromContinueWatching(),
    );
  }

  static Future<void> syncSignedInWatchMetrics(
    Future<void> Function(String token, int activeWatchSeconds) sync,
  ) async {
    final session = accountSession.value;
    if (session?.isValid != true) return;
    final activeWatchSeconds = activeWatchSecondsForAccountSync();
    try {
      await sync(session!.token, activeWatchSeconds);
    } catch (_) {
      DiagnosticLog.add('account watch metrics sync failed');
    }
  }

  static void configureAccountLibrarySync({
    required Future<AccountLibrarySyncSnapshotResult?> Function(String token)
    fetch,
    required Future<AccountLibrarySyncPushResult> Function(
      String token,
      Map<String, dynamic> snapshot,
      String baseRevision,
    )
    push,
  }) {
    _accountLibraryFetch = fetch;
    _accountLibraryPush = push;
  }

  static Map<String, dynamic> exportLibrarySnapshot() {
    return jsonDecode(exportLibraryBackup()) as Map<String, dynamic>;
  }

  static Future<void> syncSignedInLibrary({
    Future<AccountLibrarySyncSnapshotResult?> Function(String token)? fetch,
    Future<AccountLibrarySyncPushResult> Function(
      String token,
      Map<String, dynamic> snapshot,
      String baseRevision,
    )?
    push,
  }) async {
    final session = accountSession.value;
    final fetcher = fetch ?? _accountLibraryFetch;
    final pusher = push ?? _accountLibraryPush;
    if (session?.isValid != true || fetcher == null || pusher == null) return;
    if (_accountLibrarySyncApplying) {
      _accountLibrarySyncPendingUpload = true;
      return;
    }
    _accountLibrarySyncApplying = true;
    try {
      accountLibrarySyncStatus.value = const AccountLibrarySyncStatus(
        phase: AccountLibrarySyncPhase.syncing,
        updatedAt: null,
      );
      final remote = await fetcher(session!.token);
      if (remote != null) {
        _accountLibrarySyncRevision = remote.revision;
        _accountLibrarySyncApplyingRemote = true;
        try {
          final snapshot = remote.snapshot;
          if (snapshot != null) {
            mergeLibraryBackup(snapshot);
          }
        } finally {
          _accountLibrarySyncApplyingRemote = false;
        }
      }
      await _pushAccountLibrarySnapshotWithConflictHandling(
        pusher: pusher,
        token: session.token,
      );
      accountLibrarySyncStatus.value = AccountLibrarySyncStatus(
        phase: AccountLibrarySyncPhase.synced,
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      DiagnosticLog.add('account library sync failed');
      accountLibrarySyncStatus.value = AccountLibrarySyncStatus(
        phase: AccountLibrarySyncPhase.retrying,
        updatedAt: DateTime.now(),
      );
    } finally {
      _accountLibrarySyncApplying = false;
      if (_accountLibrarySyncPendingUpload) {
        _accountLibrarySyncPendingUpload = false;
        if (_accountLibrarySyncPendingPushOnly) {
          _accountLibrarySyncPendingPushOnly = false;
          unawaited(pushSignedInLibrarySnapshot(reason: 'pending_local_clear'));
        } else {
          _scheduleAccountLibraryUpload();
        }
      }
    }
  }

  static Future<void> pushSignedInLibrarySnapshot({
    String reason = 'local_change',
  }) async {
    final session = accountSession.value;
    final pusher = _accountLibraryPush;
    if (session?.isValid != true || pusher == null) return;
    if (_accountLibrarySyncApplying) {
      if (!_accountLibrarySyncApplyingRemote) {
        _accountLibrarySyncPendingUpload = true;
        _accountLibrarySyncPendingPushOnly = true;
      }
      return;
    }
    _accountLibrarySyncTimer?.cancel();
    _accountLibrarySyncTimer = null;
    _accountLibrarySyncApplying = true;
    try {
      accountLibrarySyncStatus.value = const AccountLibrarySyncStatus(
        phase: AccountLibrarySyncPhase.syncing,
        updatedAt: null,
      );
      await _pushAccountLibrarySnapshotWithConflictHandling(
        pusher: pusher,
        token: session!.token,
      );
      accountLibrarySyncStatus.value = AccountLibrarySyncStatus(
        phase: AccountLibrarySyncPhase.synced,
        updatedAt: DateTime.now(),
      );
      DiagnosticLog.add(
        'account library push-only sync complete reason=$reason',
      );
    } catch (_) {
      DiagnosticLog.add('account library push-only sync failed reason=$reason');
      accountLibrarySyncStatus.value = AccountLibrarySyncStatus(
        phase: AccountLibrarySyncPhase.retrying,
        updatedAt: DateTime.now(),
      );
    } finally {
      _accountLibrarySyncApplying = false;
      if (_accountLibrarySyncPendingUpload) {
        _accountLibrarySyncPendingUpload = false;
        if (_accountLibrarySyncPendingPushOnly) {
          _accountLibrarySyncPendingPushOnly = false;
          unawaited(
            pushSignedInLibrarySnapshot(reason: 'pending_push_only_change'),
          );
        } else {
          _scheduleAccountLibraryUpload();
        }
      }
    }
  }

  static Future<void> _pushAccountLibrarySnapshotWithConflictHandling({
    required Future<AccountLibrarySyncPushResult> Function(
      String token,
      Map<String, dynamic> snapshot,
      String baseRevision,
    )
    pusher,
    required String token,
  }) async {
    final first = await pusher(
      token,
      exportLibrarySnapshot(),
      _accountLibrarySyncRevision,
    );
    if (!first.conflict) {
      _accountLibrarySyncRevision = first.revision;
      return;
    }

    _accountLibrarySyncRevision = first.revision;
    final remoteSnapshot = first.snapshot;
    if (remoteSnapshot != null) {
      _accountLibrarySyncApplyingRemote = true;
      try {
        mergeLibraryBackup(remoteSnapshot);
      } finally {
        _accountLibrarySyncApplyingRemote = false;
      }
    }

    final retry = await pusher(
      token,
      exportLibrarySnapshot(),
      _accountLibrarySyncRevision,
    );
    _accountLibrarySyncRevision = retry.revision;
    if (retry.conflict) {
      throw StateError('account library sync conflict');
    }
  }

  static void _scheduleAccountLibraryUpload() {
    final session = accountSession.value;
    if (session?.isValid != true || _accountLibraryPush == null) {
      return;
    }
    if (_accountLibrarySyncApplying) {
      if (!_accountLibrarySyncApplyingRemote) {
        _accountLibrarySyncPendingUpload = true;
      }
      return;
    }
    _accountLibrarySyncTimer?.cancel();
    _accountLibrarySyncTimer = Timer(const Duration(seconds: 3), () {
      unawaited(syncSignedInLibrary());
    });
  }

  static Future<void> clearAccountSession() async {
    accountSession.value = null;
    accountProfile.value = null;
    _accountLibrarySyncRevision = '';
    applyAccountAdPreferences(null);
    await resetGuestAdChoices();
    await _secureStorage.delete(key: _accountSecureSessionTokenKey);
    await _secureStorage.delete(key: _accountSecureSessionExpiresAtKey);
    await _prefs?.remove(_accountProfileKey);
  }

  static Future<void> _restoreAccountSession() async {
    accountSession.value = null;
    accountProfile.value = null;
    try {
      final rawProfile = _prefs?.getString(_accountProfileKey);
      if (rawProfile != null && rawProfile.isNotEmpty) {
        final decoded = jsonDecode(rawProfile);
        if (decoded is Map<String, dynamic>) {
          final profile = AccountProfile.fromJson(decoded);
          if (profile.isUsable) {
            accountProfile.value = profile;
            applyAccountAdPreferences(profile.adPreferences);
          }
        }
      }
      final token = (await _secureStorage.read(
        key: _accountSecureSessionTokenKey,
      ))?.trim();
      final expiresAtText = await _secureStorage.read(
        key: _accountSecureSessionExpiresAtKey,
      );
      final expiresAt = DateTime.tryParse((expiresAtText ?? '').trim());
      if (token == null || token.isEmpty || expiresAt == null) return;
      final session = AccountSession(token: token, expiresAt: expiresAt);
      if (session.isValid) {
        accountSession.value = session;
      } else {
        await clearAccountSession();
      }
    } catch (_) {
      await clearAccountSession();
    }
  }

  static Future<void> init({
    SharedPreferences? prefs,
    bool restoreShellTab = true,
  }) async {
    preferencesReady.value = false;
    _prefs = prefs ?? await SharedPreferences.getInstance();
    await _restoreAccountSession();

    themeMode.value = _themeModeFromName(_prefs!.getString(_themeModeKey));
    pureBlackTheme.value = _prefs!.getBool(_pureBlackThemeKey) ?? false;
    useDeviceAccent.value = _prefs!.getBool(_useDeviceAccentKey) ?? false;
    accentThemeId.value = _accentThemeFromName(
      _prefs!.getString(_accentThemeKey),
    );
    customAccentColor.value = _colorFromStoredInt(
      _prefs!.getInt(_customAccentColorKey),
      fallback: const Color(0xFF1DB954),
    );
    startupTabMode.value = _startupTabModeFromName(
      _prefs!.getString(_startupTabModeKey),
    );
    startupBehavior.value = _startupBehaviorFromName(
      _prefs!.getString(_startupBehaviorKey),
    );
    if (restoreShellTab) {
      _restoreShellTabFromPrefs();
      shellTab.value = _clampedShellTab(preferredStartupTabIndex());
    }
    compactLayout.value = _prefs!.getBool(_compactLayoutKey) ?? false;
    reduceMotion.value = _prefs!.getBool(_reduceMotionKey) ?? false;
    textSize.value = _textSizeFromName(_prefs!.getString(_textSizeKey));
    navigationStyle.value = _navigationStyleFromName(
      _prefs!.getString(_navigationStyleKey),
    );
    homeDensity.value = _homeDensityFromName(
      _prefs!.getString(_homeDensityKey),
    );
    artworkMotion.value = _prefs!.getBool(_artworkMotionKey) ?? true;
    confirmDestructiveActions.value =
        _prefs!.getBool(_confirmDestructiveActionsKey) ?? true;
    hapticsEnabled.value = _prefs!.getBool(_hapticsEnabledKey) ?? true;
    statusMessageStyle.value = _statusMessageStyleFromName(
      _prefs!.getString(_statusMessageStyleKey),
    );
    posterImageIntensity.value = _posterImageIntensityFromName(
      _prefs!.getString(_posterImageIntensityKey),
    );
    systemBarStyle.value = _systemBarStyleFromName(
      _prefs!.getString(_systemBarStyleKey),
    );
    firstRunWelcomeSeen.value =
        _prefs!.getBool(_firstRunWelcomeSeenKey) ?? false;
    leaderboardScope.value = _leaderboardScopeFromName(
      _prefs!.getString(_leaderboardScopeKey),
    );
    _retainedActiveWatchSeconds = math.max(
      0,
      _prefs!.getInt(_retainedActiveWatchSecondsKey) ?? 0,
    );
    notificationsEnabled.value =
        _prefs!.getBool(_notificationsEnabledKey) ?? true;
    notificationDialogsEnabled.value =
        _prefs!.getBool(_notificationDialogsEnabledKey) ?? true;
    notificationInterstitialsEnabled.value =
        _prefs!.getBool(_notificationInterstitialsEnabledKey) ?? true;
    if (_prefs!.getBool(_sampleAdDefaultsMigratedKey) != true) {
      rewardedVideoAdsEnabled.value = true;
      interstitialAdsEnabled.value = true;
      bannerAdsEnabled.value = true;
      await _prefs!.setBool(_rewardedVideoAdsEnabledKey, true);
      await _prefs!.setBool(_interstitialAdsEnabledKey, true);
      await _prefs!.setBool(_bannerAdsEnabledKey, true);
      await _prefs!.setBool(_sampleAdDefaultsMigratedKey, true);
    } else {
      rewardedVideoAdsEnabled.value =
          _prefs!.getBool(_rewardedVideoAdsEnabledKey) ?? true;
      interstitialAdsEnabled.value =
          _prefs!.getBool(_interstitialAdsEnabledKey) ?? true;
      bannerAdsEnabled.value = _prefs!.getBool(_bannerAdsEnabledKey) ?? true;
    }
    final hasDisabledAdSetting =
        !rewardedVideoAdsEnabled.value ||
        !interstitialAdsEnabled.value ||
        !bannerAdsEnabled.value;
    adDisableRewardUnlocked.value =
        _prefs!.getBool(_adDisableRewardUnlockKey) ?? hasDisabledAdSetting;
    showMatureContent.value = _prefs!.getBool(_showMatureContentKey) ?? false;
    matureContentChoiceSeen.value =
        _prefs!.getBool(_matureContentChoiceSeenKey) ?? false;

    final storedNativeProvider = _prefs!.getString(_nativeProviderKey);
    if (storedNativeProvider != null && storedNativeProvider.isNotEmpty) {
      nativeProviderId.value = _normalizeNativeProviderId(storedNativeProvider);
    }

    final rawLibrary = _prefs!.getString(_libraryKey);
    if (rawLibrary != null && rawLibrary.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawLibrary);
        if (decoded is List) {
          final items = decoded
              .whereType<Map<String, dynamic>>()
              .map(CatalogItem.fromJson)
              .toList();
          library.value = {for (final item in items) item.id: item};
        }
      } catch (_) {}
    }

    final rawLibraryLists = _prefs!.getString(_libraryListsKey);
    if (rawLibraryLists != null && rawLibraryLists.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawLibraryLists);
        if (decoded is List) {
          final availableItemIds = library.value.keys.toSet();
          final lists = decoded
              .whereType<Map<String, dynamic>>()
              .map(LibraryList.fromJson)
              .where((list) => list.id.trim().isNotEmpty)
              .map((list) {
                final itemIds = list.itemIds
                    .where(availableItemIds.contains)
                    .toList(growable: false);
                return list.copyWith(itemIds: itemIds);
              })
              .toList();
          libraryLists.value = lists;
        }
      } catch (_) {}
    }

    final rawHistory = _prefs!.getStringList(_searchHistoryKey);
    if (rawHistory != null) {
      searchHistory.value = rawHistory
          .where((item) => item.trim().isNotEmpty)
          .take(searchHistoryLimit)
          .toList();
    }

    tasteProfile.value = const TasteProfile();
    unawaited(_prefs!.remove(_tasteProfileKey));

    final rawBrowseFilter = _prefs!.getString(_browseFilterPreferenceKey);
    if (rawBrowseFilter != null && rawBrowseFilter.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBrowseFilter);
        if (decoded is Map<String, dynamic>) {
          browseFilterPreference.value = BrowseFilterPreference.fromJson(
            decoded,
          );
        }
      } catch (_) {}
    }

    final rawContinue = _prefs!.getString(_continueWatchingKey);
    if (rawContinue != null && rawContinue.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawContinue);
        if (decoded is List) {
          final entries =
              decoded
                  .whereType<Map<String, dynamic>>()
                  .map(ContinueWatchingEntry.fromJson)
                  .where((entry) => entry.progress > 0 && entry.progress < 0.96)
                  .toList()
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          continueWatching.value = _dedupeContinueWatchingMap({
            for (final entry in entries) entry.key: entry,
          });
        }
      } catch (_) {}
    }

    final rawCompleted = _prefs!.getString(_completedWatchingKey);
    if (rawCompleted != null && rawCompleted.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCompleted);
        if (decoded is List) {
          final entries =
              decoded
                  .whereType<Map<String, dynamic>>()
                  .map(CompletedWatchingEntry.fromJson)
                  .where((entry) => entry.key.isNotEmpty)
                  .toList()
                ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
          completedWatching.value = {
            for (final entry in entries.take(500)) entry.key: entry,
          };
        }
      } catch (_) {}
    }

    final rawVerifiedSources = _prefs!.getString(_verifiedPlaybackSourcesKey);
    if (rawVerifiedSources != null && rawVerifiedSources.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawVerifiedSources);
        if (decoded is Map<String, dynamic>) {
          verifiedPlaybackSources.value =
              <String, List<VerifiedPlaybackSource>>{
                for (final entry in decoded.entries)
                  if (_verifiedSourceListFromJson(entry.value).isNotEmpty)
                    entry.key: _verifiedSourceListFromJson(entry.value),
              };
        }
      } catch (_) {}
    }

    final rawAddonRouteHistory = _prefs!.getString(
      _addonRouteAttemptHistoryKey,
    );
    if (rawAddonRouteHistory != null && rawAddonRouteHistory.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAddonRouteHistory);
        if (decoded is List) {
          addonRouteAttemptHistory.value = decoded
              .map(_safeAddonRouteAttemptEvidence)
              .whereType<Map<String, Object?>>()
              .take(addonRouteAttemptHistoryLimit)
              .toList(growable: false);
        }
      } catch (_) {}
    }

    _restoreProviderHealth();
    _lastProviderHealthCheckAt = DateTime.tryParse(
      _prefs!.getString(_providerHealthCheckKey) ?? '',
    );
    nativePlaybackOverridesEnabled.value =
        _prefs!.getBool(_nativePlaybackOverridesEnabledKey) ?? false;
    final rawNativeOverrides = _prefs!.getString(_nativePlaybackOverridesKey);
    if (rawNativeOverrides != null && rawNativeOverrides.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawNativeOverrides);
        if (decoded is Map<String, dynamic>) {
          nativePlaybackOverrides.value = NativePlaybackOverrides.fromJson(
            decoded,
          );
        }
      } catch (_) {}
    }
    nativePlayerVolume.value =
        (_prefs!.getDouble(_nativePlayerVolumeKey) ?? 0.5)
            .clamp(0.0, 1.0)
            .toDouble();
    nativePlayerBrightness.value =
        (_prefs!.getDouble(_nativePlayerBrightnessKey) ?? 0.5)
            .clamp(0.0, 1.0)
            .toDouble();
    final rawPlayerBehavior = _prefs!.getString(_playerBehaviorSettingsKey);
    if (rawPlayerBehavior != null && rawPlayerBehavior.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPlayerBehavior);
        if (decoded is Map<String, dynamic>) {
          playerBehaviorSettings.value = PlayerBehaviorSettings.fromJson(
            decoded,
          );
        }
      } catch (_) {}
    }
    final rawBatteryData = _prefs!.getString(_batteryDataSettingsKey);
    if (rawBatteryData != null && rawBatteryData.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBatteryData);
        if (decoded is Map<String, dynamic>) {
          batteryDataSettings.value = BatteryDataSettings.fromJson(decoded);
        }
      } catch (_) {}
    }
    final rawAddons = _prefs!.getString(_userAddonsKey);
    if (rawAddons != null && rawAddons.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAddons);
        if (decoded is List) {
          userAddons.value = decoded
              .whereType<Map<String, dynamic>>()
              .map(UserAddon.fromJson)
              .where(
                (addon) => addon.id.isNotEmpty && addon.manifestUrl.isNotEmpty,
              )
              .toList();
        }
      } catch (_) {}
    }
    p2pIndexerConnectorsEnabled.value =
        _prefs!.getBool(_p2pIndexerConnectorsEnabledKey) ?? false;
    p2pIndexerConnectorsAcknowledged.value =
        _prefs!.getBool(_p2pIndexerConnectorsAcknowledgedKey) ?? false;
    final rawP2pIndexerConnectors = _prefs!.getString(_p2pIndexerConnectorsKey);
    if (rawP2pIndexerConnectors != null && rawP2pIndexerConnectors.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawP2pIndexerConnectors);
        if (decoded is List) {
          p2pIndexerConnectors.value = decoded
              .whereType<Map<String, dynamic>>()
              .map(P2pIndexerConnector.fromJson)
              .where((connector) => connector.id.isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {}
    }
    final rawPersonalServers = _prefs!.getString(_personalServerConnectionsKey);
    if (rawPersonalServers != null && rawPersonalServers.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPersonalServers);
        if (decoded is List) {
          personalServerConnections.value = decoded
              .whereType<Map<String, dynamic>>()
              .map(PersonalServerConnection.fromJson)
              .where(
                (connection) =>
                    connection.serverUrl.isNotEmpty && connection.isConfigured,
              )
              .toList(growable: false);
        }
      } catch (_) {}
    }
    final rawLocalCatalogs = _prefs!.getString(_localCatalogsKey);
    if (rawLocalCatalogs != null && rawLocalCatalogs.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawLocalCatalogs);
        if (decoded is List) {
          localCatalogs.value = decoded
              .whereType<Map<String, dynamic>>()
              .map(LocalCatalog.fromJson)
              .where((catalog) => catalog.id.isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {}
    }
    final rawLocalCatalogItems = _prefs!.getString(_localCatalogItemsKey);
    if (rawLocalCatalogItems != null && rawLocalCatalogItems.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawLocalCatalogItems);
        if (decoded is List) {
          localCatalogItems.value = decoded
              .whereType<Map<String, dynamic>>()
              .map(LocalCatalogItem.fromJson)
              .where((item) => item.id.isNotEmpty && item.catalogId.isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {}
    }
    final rawLocalPickedAssetRefs = _prefs!.getString(_localPickedAssetRefsKey);
    if (rawLocalPickedAssetRefs != null && rawLocalPickedAssetRefs.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawLocalPickedAssetRefs);
        if (decoded is List) {
          localPickedAssetRefs.value = decoded
              .whereType<Map<String, dynamic>>()
              .map(LocalPickedAssetRef.fromJson)
              .where(
                (ref) =>
                    ref.id.isNotEmpty &&
                    ref.catalogId.isNotEmpty &&
                    ref.itemId.isNotEmpty,
              )
              .toList(growable: false);
        }
      } catch (_) {}
    }
    defaultSourceDisclaimerAccepted.value =
        _prefs!.getBool(_defaultSourceDisclaimerAcceptedKey) ?? false;
    final canUseDefaultSources = defaultSourceDisclaimerAccepted.value;
    defaultCatalogEnabled.value =
        canUseDefaultSources &&
        (_prefs!.getBool(_defaultCatalogEnabledKey) ?? false);
    defaultProvidersEnabled.value =
        canUseDefaultSources &&
        (_prefs!.getBool(_defaultProvidersEnabledKey) ?? false);
    defaultSubtitlesEnabled.value =
        canUseDefaultSources &&
        (_prefs!.getBool(_defaultSubtitlesEnabledKey) ?? false);
    defaultTrailersEnabled.value =
        canUseDefaultSources &&
        (_prefs!.getBool(_defaultTrailersEnabledKey) ?? false);
    tvSourcesEnabled.value = _prefs!.getBool(_tvSourcesEnabledKey) ?? false;
    publicIptvEnabled.value =
        tvSourcesEnabled.value &&
        (_prefs!.getBool(_publicIptvEnabledKey) ?? false);
    addonDisclaimerAccepted.value =
        _prefs!.getBool(_addonDisclaimerAcceptedKey) ?? false;
    experimentalDisclaimerAccepted.value =
        _prefs!.getBool(_experimentalDisclaimerAcceptedKey) ?? false;

    themeMode.addListener(_persistThemeMode);
    pureBlackTheme.addListener(_persistPureBlackTheme);
    useDeviceAccent.addListener(_persistUseDeviceAccent);
    accentThemeId.addListener(_persistAccentTheme);
    customAccentColor.addListener(_persistCustomAccentColor);
    startupTabMode.addListener(_persistStartupTabMode);
    startupBehavior.addListener(_persistStartupBehavior);
    shellTab.addListener(_persistShellTab);
    compactLayout.addListener(_persistCompactLayout);
    reduceMotion.addListener(_persistReduceMotion);
    textSize.addListener(_persistTextSize);
    navigationStyle.addListener(_persistNavigationStyle);
    homeDensity.addListener(_persistHomeDensity);
    artworkMotion.addListener(_persistArtworkMotion);
    confirmDestructiveActions.addListener(_persistConfirmDestructiveActions);
    hapticsEnabled.addListener(_persistHapticsEnabled);
    statusMessageStyle.addListener(_persistStatusMessageStyle);
    posterImageIntensity.addListener(_persistPosterImageIntensity);
    systemBarStyle.addListener(_persistSystemBarStyle);
    firstRunWelcomeSeen.addListener(_persistFirstRunWelcomeSeen);
    notificationsEnabled.addListener(_persistNotificationsEnabled);
    notificationDialogsEnabled.addListener(_persistNotificationDialogsEnabled);
    notificationInterstitialsEnabled.addListener(
      _persistNotificationInterstitialsEnabled,
    );
    rewardedVideoAdsEnabled.addListener(_persistRewardedVideoAdsEnabled);
    interstitialAdsEnabled.addListener(_persistInterstitialAdsEnabled);
    bannerAdsEnabled.addListener(_persistBannerAdsEnabled);
    adDisableRewardUnlocked.addListener(_persistAdDisableRewardUnlocked);
    showMatureContent.addListener(_persistShowMatureContent);
    matureContentChoiceSeen.addListener(_persistMatureContentChoiceSeen);
    leaderboardScope.addListener(_persistLeaderboardScope);
    nativeProviderId.addListener(_persistNativeProvider);
    library.addListener(_persistLibrary);
    libraryLists.addListener(_persistLibraryLists);
    searchHistory.addListener(_persistSearchHistory);
    browseFilterPreference.addListener(_persistBrowseFilterPreference);
    continueWatching.addListener(_persistContinueWatching);
    completedWatching.addListener(_persistCompletedWatching);
    verifiedPlaybackSources.addListener(_persistVerifiedPlaybackSources);
    addonRouteAttemptHistory.addListener(_persistAddonRouteAttemptHistory);
    nativePlaybackOverridesEnabled.addListener(
      _persistNativePlaybackOverridesEnabled,
    );
    nativePlaybackOverrides.addListener(_persistNativePlaybackOverrides);
    playerBehaviorSettings.addListener(_persistPlayerBehaviorSettings);
    batteryDataSettings.addListener(_persistBatteryDataSettings);
    userAddons.addListener(_persistUserAddons);
    p2pIndexerConnectors.addListener(_persistP2pIndexerConnectors);
    p2pIndexerConnectorsEnabled.addListener(
      _persistP2pIndexerConnectorsEnabled,
    );
    p2pIndexerConnectorsAcknowledged.addListener(
      _persistP2pIndexerConnectorsAcknowledged,
    );
    personalServerConnections.addListener(_persistPersonalServerConnections);
    localCatalogs.addListener(_persistLocalCatalogs);
    localCatalogItems.addListener(_persistLocalCatalogItems);
    localPickedAssetRefs.addListener(_persistLocalPickedAssetRefs);
    defaultCatalogEnabled.addListener(_persistDefaultCatalogEnabled);
    defaultProvidersEnabled.addListener(_persistDefaultProvidersEnabled);
    defaultSubtitlesEnabled.addListener(_persistDefaultSubtitlesEnabled);
    defaultTrailersEnabled.addListener(_persistDefaultTrailersEnabled);
    tvSourcesEnabled.addListener(_persistTvSourcesEnabled);
    publicIptvEnabled.addListener(_persistPublicIptvEnabled);
    defaultSourceDisclaimerAccepted.addListener(
      _persistDefaultSourceDisclaimerAccepted,
    );
    addonDisclaimerAccepted.addListener(_persistAddonDisclaimerAccepted);
    experimentalDisclaimerAccepted.addListener(
      _persistExperimentalDisclaimerAccepted,
    );
    preferencesReady.value = true;
  }

  static bool isSaved(CatalogItem item) {
    return library.value.containsKey(item.id);
  }

  static bool get hasCatalogSource {
    return defaultCatalogEnabled.value ||
        (tvSourcesEnabled.value && publicIptvEnabled.value) ||
        userAddons.value.any((addon) => addon.active) ||
        personalServerConnections.value.any(
          (connection) => connection.active && connection.isConfigured,
        );
  }

  static void openDiscovery({
    required MediaType type,
    required CatalogSort sort,
    required String genre,
  }) {
    discoveryIntent.value = DiscoveryIntent(
      type: type,
      sort: sort,
      genre: genre,
      createdAt: DateTime.now(),
    );
    shellTab.value = 1;
  }

  static void rememberBrowseFilter({
    required MediaType type,
    required CatalogSort sort,
    required String year,
    required String genre,
    String origin = '',
  }) {
    final next = browseFilterPreference.value.remember(
      type: type,
      sort: sort,
      year: year,
      genre: genre,
      origin: origin,
    );
    if (jsonEncode(next.toJson()) ==
        jsonEncode(browseFilterPreference.value.toJson())) {
      return;
    }
    browseFilterPreference.value = next;
  }

  static void openAddOnsSettings() {
    settingsIntent.value = 'addons';
    shellTab.value = 3;
  }

  static void toggleSaved(CatalogItem item) {
    final next = Map<String, CatalogItem>.from(library.value);
    if (next.containsKey(item.id)) {
      next.remove(item.id);
    } else {
      next.remove(item.id);
      library.value = {item.id: item, ...next};
      recordTasteForItem(item, weight: 5);
      return;
    }
    library.value = next;
  }

  static LibraryList createLibraryList(
    String name, {
    CatalogItem? initialItem,
  }) {
    final now = DateTime.now();
    final normalizedName = LibraryList._normalizeLibraryListName(name);
    if (initialItem != null) {
      _ensureLibraryItem(initialItem);
    }
    final list = LibraryList(
      id: _newLibraryListId(now),
      name: normalizedName,
      itemIds: initialItem == null
          ? const <String>[]
          : <String>[initialItem.id],
      createdAt: now,
      updatedAt: now,
    );
    libraryLists.value = <LibraryList>[list, ...libraryLists.value];
    return list;
  }

  static void renameLibraryList(String listId, String name) {
    final normalizedName = LibraryList._normalizeLibraryListName(name);
    final now = DateTime.now();
    libraryLists.value = libraryLists.value
        .map(
          (list) => list.id == listId
              ? list.copyWith(name: normalizedName, updatedAt: now)
              : list,
        )
        .toList(growable: false);
  }

  static void deleteLibraryList(String listId) {
    libraryLists.value = libraryLists.value
        .where((list) => list.id != listId)
        .toList(growable: false);
  }

  static bool isItemInLibraryList(String listId, CatalogItem item) {
    for (final list in libraryLists.value) {
      if (list.id == listId) return list.itemIds.contains(item.id);
    }
    return false;
  }

  static void toggleItemInLibraryList(String listId, CatalogItem item) {
    _ensureLibraryItem(item);
    final now = DateTime.now();
    libraryLists.value = libraryLists.value
        .map((list) {
          if (list.id != listId) return list;
          final nextItemIds = List<String>.from(list.itemIds);
          if (nextItemIds.contains(item.id)) {
            nextItemIds.remove(item.id);
          } else {
            nextItemIds.insert(0, item.id);
          }
          return list.copyWith(
            itemIds: LibraryList._dedupeLibraryListItemIds(nextItemIds),
            updatedAt: now,
          );
        })
        .toList(growable: false);
  }

  static List<CatalogItem> itemsForLibraryList(LibraryList list) {
    return list.itemIds
        .map((id) => library.value[id])
        .whereType<CatalogItem>()
        .toList(growable: false);
  }

  static void _ensureLibraryItem(CatalogItem item) {
    if (library.value.containsKey(item.id)) return;
    final next = Map<String, CatalogItem>.from(library.value);
    library.value = {item.id: item, ...next};
    recordTasteForItem(item, weight: 5);
  }

  static String _newLibraryListId(DateTime now) {
    final existingIds = libraryLists.value.map((list) => list.id).toSet();
    var id = 'list-${now.microsecondsSinceEpoch}';
    while (existingIds.contains(id)) {
      id = 'list-${now.microsecondsSinceEpoch}-${math.Random().nextInt(9999)}';
    }
    return id;
  }

  static void clearLibrary() {
    if (library.value.isEmpty && libraryLists.value.isEmpty) return;
    library.value = const <String, CatalogItem>{};
    libraryLists.value = const <LibraryList>[];
    unawaited(_prefs?.setString(_libraryKey, '[]') ?? Future<void>.value());
    unawaited(
      _prefs?.setString(_libraryListsKey, '[]') ?? Future<void>.value(),
    );
  }

  static void clearSavedLibraryFavorites() {
    if (library.value.isEmpty) return;
    library.value = const <String, CatalogItem>{};
    unawaited(_prefs?.setString(_libraryKey, '[]') ?? Future<void>.value());
  }

  static void clearRetainedActiveWatchTime() {
    if (_retainedActiveWatchSeconds <= 0) return;
    _retainedActiveWatchSeconds = 0;
    unawaited(
      _prefs?.remove(_retainedActiveWatchSecondsKey) ?? Future<void>.value(),
    );
  }

  static String exportLibraryBackup() {
    final savedItems = library.value.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final continueItems = continueWatching.value.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final completedItems = completedWatching.value.values.toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    final lists = libraryLists.value.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'juicr.library.backup.v1',
      'exportedAt': DateTime.now().toIso8601String(),
      'saved': savedItems.map((item) => item.toJson()).toList(),
      'lists': lists.map((list) => list.toJson()).toList(),
      'continueWatching': continueItems.map((entry) => entry.toJson()).toList(),
      'completedWatching': completedItems
          .map((entry) => entry.toJson())
          .toList(),
    });
  }

  static LibraryBackupImportResult importLibraryBackup(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Backup must be a JSON object.');
    }
    return mergeLibraryBackup(Map<String, dynamic>.from(decoded));
  }

  static LibraryBackupImportResult mergeLibraryBackup(
    Map<String, dynamic> decoded,
  ) {
    final savedItems =
        (decoded['saved'] is List ? decoded['saved'] as List : const [])
            .whereType<Map<String, dynamic>>()
            .map(CatalogItem.fromJson)
            .where((item) => item.id.isNotEmpty && item.name.trim().isNotEmpty)
            .toList();
    final continueItems =
        (decoded['continueWatching'] is List
                ? decoded['continueWatching'] as List
                : const [])
            .whereType<Map<String, dynamic>>()
            .map(ContinueWatchingEntry.fromJson)
            .where((entry) => entry.key.isNotEmpty && entry.progress > 0)
            .toList();
    final completedItems =
        (decoded['completedWatching'] is List
                ? decoded['completedWatching'] as List
                : const [])
            .whereType<Map<String, dynamic>>()
            .map(CompletedWatchingEntry.fromJson)
            .where((entry) => entry.key.isNotEmpty)
            .toList();
    final lists =
        (decoded['lists'] is List ? decoded['lists'] as List : const [])
            .whereType<Map<String, dynamic>>()
            .map(LibraryList.fromJson)
            .where((list) => list.id.isNotEmpty)
            .toList();

    if (savedItems.isEmpty &&
        continueItems.isEmpty &&
        completedItems.isEmpty &&
        lists.isEmpty) {
      throw const FormatException('No Juicr library data found in backup.');
    }

    library.value = {
      ...library.value,
      for (final item in savedItems) item.id: item,
    };
    if (lists.isNotEmpty) {
      final savedIds = library.value.keys.toSet();
      final existingLists = {
        for (final list in libraryLists.value) list.id: list,
      };
      for (final list in lists) {
        existingLists[list.id] = list.copyWith(
          itemIds: list.itemIds
              .where(savedIds.contains)
              .toList(growable: false),
        );
      }
      libraryLists.value = existingLists.values.toList(growable: false);
    }
    final nextContinue = Map<String, ContinueWatchingEntry>.from(
      _continueWatchingSnapshot,
    );
    for (final entry in continueItems) {
      final existing = nextContinue[entry.key];
      nextContinue[entry.key] = existing == null
          ? entry
          : _preferredContinueEntry(existing, entry);
    }
    final nextCompleted = {
      ...completedWatching.value,
      for (final entry in completedItems) entry.key: entry,
    }.values.toList()..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    completedWatching.value = {
      for (final entry in nextCompleted.take(500)) entry.key: entry,
    };
    for (final entry in completedWatching.value.values) {
      nextContinue.remove(entry.key);
    }
    _setContinueWatching(nextContinue);

    return LibraryBackupImportResult(
      savedCount: savedItems.length,
      continueCount: continueItems.length,
      completedCount: completedItems.length,
    );
  }

  static void setThemeMode(ThemeMode mode) {
    if (themeMode.value == mode) return;
    themeMode.value = mode;
  }

  static void setPureBlackTheme(bool enabled) {
    if (pureBlackTheme.value == enabled) return;
    pureBlackTheme.value = enabled;
  }

  static void setUseDeviceAccent(bool enabled) {
    if (useDeviceAccent.value == enabled) return;
    useDeviceAccent.value = enabled;
  }

  static void setAccentTheme(String id) {
    final normalized = _accentThemeFromName(id);
    if (accentThemeId.value == normalized) return;
    accentThemeId.value = normalized;
  }

  static void setCustomAccentColor(Color color) {
    final normalized = color.withAlpha(0xFF);
    if (customAccentColor.value.value != normalized.value) {
      customAccentColor.value = normalized;
    }
    if (accentThemeId.value != accentCustom) {
      accentThemeId.value = accentCustom;
    }
  }

  static Color get effectiveAccentColor {
    return switch (accentThemeId.value) {
      accentPurple => const Color(0xFF9B6DFF),
      accentOcean => const Color(0xFF00A8CC),
      accentAmber => const Color(0xFFFFB703),
      accentCustom => customAccentColor.value,
      _ => const Color(0xFF1DB954),
    };
  }

  static int preferredStartupTabIndex() {
    if (startupBehavior.value == 'freshHome') return 0;
    return switch (startupTabMode.value) {
      'home' => 0,
      'discovery' => 1,
      'library' => 2,
      'settings' => 3,
      _ => shellTab.value,
    };
  }

  static int _clampedShellTab(int? value) {
    return (value ?? 0).clamp(0, 3).toInt();
  }

  static void _restoreShellTabFromPrefs() {
    shellTab.value = _clampedShellTab(_prefs!.getInt(_shellTabKey));
  }

  static void setStartupTabMode(String mode) {
    final normalized = _startupTabModeFromName(mode);
    if (startupTabMode.value == normalized) return;
    startupTabMode.value = normalized;
  }

  static void setStartupBehavior(String behavior) {
    final normalized = _startupBehaviorFromName(behavior);
    if (startupBehavior.value == normalized) return;
    startupBehavior.value = normalized;
  }

  static void setCompactLayout(bool enabled) {
    if (compactLayout.value == enabled) return;
    compactLayout.value = enabled;
  }

  static void setReduceMotion(bool enabled) {
    if (reduceMotion.value == enabled) return;
    reduceMotion.value = enabled;
  }

  static void setTextSize(String size) {
    final normalized = _textSizeFromName(size);
    if (textSize.value == normalized) return;
    textSize.value = normalized;
  }

  static double get textScaleFactor {
    return switch (textSize.value) {
      'small' => 0.92,
      'large' => 1.08,
      _ => 1.0,
    };
  }

  static void setNavigationStyle(String style) {
    final normalized = _navigationStyleFromName(style);
    if (navigationStyle.value == normalized) return;
    navigationStyle.value = normalized;
  }

  static void setHomeDensity(String density) {
    final normalized = _homeDensityFromName(density);
    if (homeDensity.value == normalized) return;
    homeDensity.value = normalized;
  }

  static void setArtworkMotion(bool enabled) {
    if (artworkMotion.value == enabled) return;
    artworkMotion.value = enabled;
  }

  static void setConfirmDestructiveActions(bool enabled) {
    if (confirmDestructiveActions.value == enabled) return;
    confirmDestructiveActions.value = enabled;
  }

  static void setHapticsEnabled(bool enabled) {
    if (hapticsEnabled.value == enabled) return;
    hapticsEnabled.value = enabled;
  }

  static void setLeaderboardScope(String scope) {
    final normalized = _leaderboardScopeFromName(scope);
    if (leaderboardScope.value == normalized) return;
    leaderboardScope.value = normalized;
  }

  static void setNotificationsEnabled(bool enabled) {
    if (notificationsEnabled.value == enabled) return;
    notificationsEnabled.value = enabled;
    _bumpNotificationSettingsRevision();
  }

  static void setNotificationDialogsEnabled(bool enabled) {
    if (notificationDialogsEnabled.value == enabled) return;
    notificationDialogsEnabled.value = enabled;
    _bumpNotificationSettingsRevision();
  }

  static void setNotificationInterstitialsEnabled(bool enabled) {
    if (notificationInterstitialsEnabled.value == enabled) return;
    notificationInterstitialsEnabled.value = enabled;
    _bumpNotificationSettingsRevision();
  }

  static int notificationDailyCount() {
    final prefs = _prefs;
    if (prefs == null) return 0;
    final today = _dateStamp(DateTime.now());
    if (prefs.getString(_notificationDailyCountDateKey) != today) return 0;
    return prefs.getInt(_notificationDailyCountKey) ?? 0;
  }

  static Future<void> recordNotificationDelivery() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final today = _dateStamp(DateTime.now());
    final current = prefs.getString(_notificationDailyCountDateKey) == today
        ? prefs.getInt(_notificationDailyCountKey) ?? 0
        : 0;
    await prefs.setString(_notificationDailyCountDateKey, today);
    await prefs.setInt(_notificationDailyCountKey, current + 1);
  }

  static String lastCurationNotificationEdition() {
    return _prefs?.getString(_notificationLastCurationEditionKey) ?? '';
  }

  static Future<void> setLastCurationNotificationEdition(String edition) async {
    await _prefs?.setString(_notificationLastCurationEditionKey, edition);
  }

  static String lastCurationDialogEdition() {
    return _prefs?.getString(_notificationLastCurationDialogEditionKey) ?? '';
  }

  static Future<void> setLastCurationDialogEdition(String edition) async {
    await _prefs?.setString(_notificationLastCurationDialogEditionKey, edition);
  }

  static bool hasShownCurationDialogToday() {
    final prefs = _prefs;
    if (prefs == null) return false;
    return prefs.getString(_notificationLastCurationDialogDateKey) ==
        _dateStamp(DateTime.now());
  }

  static Future<void> markCurationDialogShownToday() async {
    await _prefs?.setString(
      _notificationLastCurationDialogDateKey,
      _dateStamp(DateTime.now()),
    );
  }

  static bool hasSeenNotificationCampaign(String campaignId) {
    if (campaignId.trim().isEmpty) return false;
    return _notificationSeenCampaigns().contains(campaignId);
  }

  static Future<void> markNotificationCampaignSeen(String campaignId) async {
    final trimmed = campaignId.trim();
    if (trimmed.isEmpty) return;
    final campaigns = _notificationSeenCampaigns()..add(trimmed);
    await _prefs?.setStringList(
      _notificationSeenCampaignsKey,
      campaigns.take(40).toList(growable: false),
    );
  }

  static DateTime? lastNotificationInterstitialAt() {
    return _dateTimeFromPrefs(_notificationLastInterstitialAtKey);
  }

  static Future<void> setLastNotificationInterstitialAt(DateTime value) async {
    await _prefs?.setString(
      _notificationLastInterstitialAtKey,
      value.toUtc().toIso8601String(),
    );
  }

  static DateTime? lastSmartSuggestionNotificationAt() {
    return _dateTimeFromPrefs(_notificationLastSmartSuggestionAtKey);
  }

  static Future<void> setLastSmartSuggestionNotificationAt(
    DateTime value,
  ) async {
    await _prefs?.setString(
      _notificationLastSmartSuggestionAtKey,
      value.toUtc().toIso8601String(),
    );
  }

  static void _bumpNotificationSettingsRevision() {
    notificationSettingsRevision.value = notificationSettingsRevision.value + 1;
  }

  static void setRewardedVideoAdsEnabled(bool enabled) {
    if (rewardedVideoAdsEnabled.value == enabled) return;
    rewardedVideoAdsEnabled.value = enabled;
  }

  static void setInterstitialAdsEnabled(bool enabled) {
    if (interstitialAdsEnabled.value == enabled) return;
    interstitialAdsEnabled.value = enabled;
  }

  static void setBannerAdsEnabled(bool enabled) {
    if (bannerAdsEnabled.value == enabled) return;
    bannerAdsEnabled.value = enabled;
  }

  static void applyAccountAdPreferences(AccountAdPreferences? preferences) {
    accountAdPreferences.value = preferences;
    if (preferences == null) return;
    _applyingAccountAdPreferences = true;
    try {
      rewardedVideoAdsEnabled.value = preferences.adsEnabled;
      interstitialAdsEnabled.value = preferences.adsEnabled;
      bannerAdsEnabled.value = preferences.adsEnabled;
    } finally {
      _applyingAccountAdPreferences = false;
    }
  }

  static Future<void> resetGuestAdChoices() async {
    rewardedVideoAdsEnabled.value = true;
    interstitialAdsEnabled.value = true;
    bannerAdsEnabled.value = true;
    await _prefs?.setBool(_rewardedVideoAdsEnabledKey, true);
    await _prefs?.setBool(_interstitialAdsEnabledKey, true);
    await _prefs?.setBool(_bannerAdsEnabledKey, true);
  }

  static void setAdDisableRewardUnlocked(bool unlocked) {
    if (adDisableRewardUnlocked.value == unlocked) return;
    adDisableRewardUnlocked.value = unlocked;
  }

  static void setStatusMessageStyle(String style) {
    final normalized = _statusMessageStyleFromName(style);
    if (statusMessageStyle.value == normalized) return;
    statusMessageStyle.value = normalized;
  }

  static void setPosterImageIntensity(String intensity) {
    final normalized = _posterImageIntensityFromName(intensity);
    if (posterImageIntensity.value == normalized) return;
    posterImageIntensity.value = normalized;
  }

  static void setSystemBarStyle(String style) {
    final normalized = _systemBarStyleFromName(style);
    if (systemBarStyle.value == normalized) return;
    systemBarStyle.value = normalized;
  }

  static void addSearchHistory(String query, {bool recordTaste = true}) {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return;
    final lower = cleaned.toLowerCase();
    final next = [
      cleaned,
      ...searchHistory.value.where((item) => item.toLowerCase() != lower),
    ].take(searchHistoryLimit).toList();
    searchHistory.value = next;
    if (recordTaste) recordTasteForSearch(cleaned);
  }

  static void recordTasteForItem(CatalogItem item, {double weight = 1}) {
    return;
  }

  static void recordTasteForSearch(String query) {
    return;
  }

  static void clearSearchHistory() {
    searchHistory.value = const [];
    unawaited(_prefs?.remove(_searchHistoryKey) ?? Future<void>.value());
  }

  static void clearCompletedWatching() {
    _clearCompletedWatching(retainActiveWatchTime: true);
  }

  static void clearCompletedWatchingForAccountDeletion() {
    _clearCompletedWatching(retainActiveWatchTime: false);
  }

  static int _activeWatchSecondsFromContinueWatching() {
    return continueWatching.value.values
        .where(isDisplayableContinueEntry)
        .fold<int>(0, (total, entry) => total + entry.credibleWatchedSeconds);
  }

  static int _activeWatchSecondsFromCompletedWatching() {
    return completedWatching.value.values
        .where((entry) => !entry.item.type.isLive)
        .fold<int>(0, (total, entry) => total + entry.credibleWatchedSeconds);
  }

  static void _retainActiveWatchSecondsFromContinueWatching() {
    _retainActiveWatchSeconds(
      _activeWatchSecondsFromContinueWatching(),
      reason: 'clear_continue_watching',
    );
  }

  static void _retainActiveWatchSecondsFromCompletedWatching() {
    _retainActiveWatchSeconds(
      _activeWatchSecondsFromCompletedWatching(),
      reason: 'clear_completed_history',
    );
  }

  static void _retainActiveWatchSeconds(int seconds, {required String reason}) {
    if (seconds <= 0) return;
    _retainedActiveWatchSeconds = math.max(
      0,
      _retainedActiveWatchSeconds + seconds,
    );
    DiagnosticLog.add(
      'account active watch time retained reason=$reason seconds=$seconds total=$_retainedActiveWatchSeconds',
    );
    unawaited(
      _prefs?.setInt(
            _retainedActiveWatchSecondsKey,
            _retainedActiveWatchSeconds,
          ) ??
          Future<void>.value(),
    );
  }

  static void _clearCompletedWatching({required bool retainActiveWatchTime}) {
    if (completedWatching.value.isEmpty) return;
    if (retainActiveWatchTime) {
      _retainActiveWatchSecondsFromCompletedWatching();
    }
    completedWatching.value = <String, CompletedWatchingEntry>{};
    unawaited(_prefs?.remove(_completedWatchingKey) ?? Future<void>.value());
  }

  static void clearVerifiedPlaybackSources() {
    if (verifiedPlaybackSources.value.isEmpty) return;
    verifiedPlaybackSources.value = <String, List<VerifiedPlaybackSource>>{};
    unawaited(
      _prefs?.remove(_verifiedPlaybackSourcesKey) ?? Future<void>.value(),
    );
  }

  static void clearAddonRouteAttemptHistory() {
    if (addonRouteAttemptHistory.value.isEmpty) return;
    addonRouteAttemptHistory.value = const <Map<String, Object?>>[];
    unawaited(
      _prefs?.remove(_addonRouteAttemptHistoryKey) ?? Future<void>.value(),
    );
  }

  static void removeSearchHistoryItem(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return;
    searchHistory.value = [
      for (final item in searchHistory.value)
        if (item.toLowerCase() != lower) item,
    ];
  }

  static void addUserAddon({
    required String name,
    required String manifestUrl,
    bool active = true,
  }) {
    final cleanedName = name.trim();
    final cleanedUrl = manifestUrl.trim();
    if (cleanedName.isEmpty || cleanedUrl.isEmpty) return;
    final next = List<UserAddon>.from(userAddons.value);
    next.add(
      UserAddon(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: cleanedName,
        manifestUrl: cleanedUrl,
        active: active,
      ),
    );
    userAddons.value = next;
  }

  static void updateUserAddon(UserAddon addon) {
    userAddons.value = [
      for (final item in userAddons.value)
        if (item.id == addon.id) addon else item,
    ];
  }

  static void removeUserAddon(String id) {
    userAddons.value = [
      for (final item in userAddons.value)
        if (item.id != id) item,
    ];
  }

  static void removeUserAddons(Set<String> ids) {
    if (ids.isEmpty) return;
    userAddons.value = [
      for (final item in userAddons.value)
        if (!ids.contains(item.id)) item,
    ];
  }

  static void clearUserAddons() {
    if (userAddons.value.isEmpty) return;
    userAddons.value = const <UserAddon>[];
  }

  static void reorderUserAddons(int oldIndex, int newIndex) {
    final next = List<UserAddon>.from(userAddons.value);
    if (oldIndex < 0 || oldIndex >= next.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex > next.length) return;
    final addon = next.removeAt(oldIndex);
    next.insert(newIndex, addon);
    userAddons.value = next;
  }

  static void upsertP2pIndexerConnector(P2pIndexerConnector connector) {
    final cleaned = connector.copyWith(
      id: connector.id.trim().isEmpty
          ? DateTime.now().microsecondsSinceEpoch.toString()
          : connector.id.trim(),
      label: connector.label.trim(),
      baseUrl: _safeHttpUrlOrEmpty(connector.baseUrl),
      apiKey: connector.apiKey.trim(),
      lastStatusBucket: connector.lastStatusBucket,
    );
    if (!cleaned.isConfigured) return;
    p2pIndexerConnectors.value = [
      for (final item in p2pIndexerConnectors.value)
        if (item.id != cleaned.id) item,
      cleaned,
    ];
  }

  static void updateP2pIndexerConnector(P2pIndexerConnector connector) {
    final cleaned = connector.copyWith(
      label: connector.label.trim(),
      baseUrl: _safeHttpUrlOrEmpty(connector.baseUrl),
      apiKey: connector.apiKey.trim(),
    );
    p2pIndexerConnectors.value = [
      for (final item in p2pIndexerConnectors.value)
        if (item.id == cleaned.id) cleaned else item,
    ];
  }

  static void removeP2pIndexerConnector(String id) {
    p2pIndexerConnectors.value = [
      for (final connector in p2pIndexerConnectors.value)
        if (connector.id != id) connector,
    ];
  }

  static void setP2pIndexerConnectorsEnabled(bool enabled) {
    p2pIndexerConnectorsEnabled.value = enabled;
  }

  static void markP2pIndexerConnectorsAcknowledged() {
    p2pIndexerConnectorsAcknowledged.value = true;
  }

  static List<P2pIndexerConnector> enabledP2pIndexerConnectors() {
    if (!p2pIndexerConnectorsEnabled.value) {
      return const <P2pIndexerConnector>[];
    }
    return p2pIndexerConnectors.value
        .where((connector) => connector.enabled && connector.isConfigured)
        .toList(growable: false);
  }

  static PersonalServerConnection? personalServerConnection(
    PersonalServerType type,
  ) {
    for (final connection in personalServerConnections.value) {
      if (connection.type == type) return connection;
    }
    return null;
  }

  static void upsertPersonalServerConnection(
    PersonalServerConnection connection,
  ) {
    final cleaned = connection.copyWith(
      serverUrl: _safeHttpUrlOrEmpty(connection.serverUrl),
      username: connection.username.trim(),
      token: connection.token.trim(),
      password: connection.password.trim(),
      userId: connection.userId.trim(),
      updatedAt: DateTime.now(),
    );
    if (!cleaned.isConfigured) return;
    personalServerConnections.value = [
      for (final item in personalServerConnections.value)
        if (item.type != cleaned.type) item,
      cleaned,
    ];
  }

  static void removePersonalServerConnection(PersonalServerType type) {
    personalServerConnections.value = [
      for (final item in personalServerConnections.value)
        if (item.type != type) item,
    ];
  }

  static void addLocalCatalog({required String name, String description = ''}) {
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) return;
    final next = List<LocalCatalog>.from(localCatalogs.value);
    next.add(
      LocalCatalog(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: cleanedName,
        description: description.trim(),
        createdAt: DateTime.now(),
      ),
    );
    localCatalogs.value = next;
  }

  static void updateLocalCatalogMetadata({
    required String id,
    required String name,
    String description = '',
  }) {
    final cleanedId = id.trim();
    final cleanedName = name.trim();
    if (cleanedId.isEmpty || cleanedName.isEmpty) return;
    localCatalogs.value = [
      for (final catalog in localCatalogs.value)
        if (catalog.id == cleanedId)
          LocalCatalog(
            id: catalog.id,
            name: cleanedName,
            description: description.trim(),
            itemCount: catalog.itemCount,
            createdAt: catalog.createdAt,
          )
        else
          catalog,
    ];
  }

  static void removeLocalCatalog(String id) {
    localCatalogs.value = [
      for (final catalog in localCatalogs.value)
        if (catalog.id != id) catalog,
    ];
    localCatalogItems.value = [
      for (final item in localCatalogItems.value)
        if (item.catalogId != id) item,
    ];
    localPickedAssetRefs.value = [
      for (final ref in localPickedAssetRefs.value)
        if (ref.catalogId != id) ref,
    ];
  }

  static int localCatalogItemCount(String catalogId) {
    return localCatalogItems.value
        .where((item) => item.catalogId == catalogId)
        .length;
  }

  static List<LocalCatalogItem> localCatalogItemsFor(String catalogId) {
    return [
      for (final item in localCatalogItems.value)
        if (item.catalogId == catalogId) item,
    ];
  }

  static bool get hasLocalCatalogContent {
    // Catalog Builder is parked as a future feature and must not surface in-app.
    return false;
  }

  static LocalCatalog? localCatalogById(String catalogId) {
    final cleanedCatalogId = catalogId.trim();
    if (cleanedCatalogId.isEmpty) return null;
    for (final catalog in localCatalogs.value) {
      if (catalog.id == cleanedCatalogId) return catalog;
    }
    return null;
  }

  static LocalCatalogItem? localCatalogItemById(String itemId) {
    final cleanedItemId = itemId.trim();
    if (cleanedItemId.isEmpty) return null;
    for (final item in localCatalogItems.value) {
      if (item.id == cleanedItemId) return item;
    }
    return null;
  }

  static String localCatalogSurfaceItemId(String catalogId, String itemId) {
    return 'local-catalog:$catalogId:$itemId';
  }

  static bool isLocalCatalogSurfaceItemId(String itemId) {
    return itemId.startsWith('local-catalog:');
  }

  static MediaType _localCatalogMediaType(String mediaKind) {
    final normalized = mediaKind.trim().toLowerCase();
    return switch (normalized) {
      'series' || 'episode' => MediaType.series,
      'animation' => MediaType.animation,
      _ => MediaType.movie,
    };
  }

  static String? _safeLocalArtworkUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return null;
    return trimmed;
  }

  static String _safeLocalPlaybackEngine(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'exoplayer' => 'exoplayer',
      'libvlc' => 'libvlc',
      _ => 'auto',
    };
  }

  static bool _localCatalogTagMatchesGenre(
    LocalCatalogItem item,
    String genre,
  ) {
    final normalizedGenre = genre.trim().toLowerCase();
    if (normalizedGenre.isEmpty || normalizedGenre == 'all genres') {
      return true;
    }
    if (RegExp(r'^\d{4}$').hasMatch(normalizedGenre)) {
      return item.releaseYear?.toString() == normalizedGenre;
    }
    return item.tags.any((tag) => tag.trim().toLowerCase() == normalizedGenre);
  }

  static bool _localCatalogItemMatchesSearch(
    LocalCatalogItem item,
    LocalCatalog? catalog,
    String query,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    final haystack = [
      item.title,
      item.description,
      item.mediaKind,
      ...item.tags,
      catalog?.name ?? '',
      catalog?.description ?? '',
      item.releaseYear?.toString() ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(normalizedQuery);
  }

  static CatalogItem localCatalogSurfaceItem(
    LocalCatalog catalog,
    LocalCatalogItem item,
  ) {
    final relinkNeededCount = localPickedAssetRefsFor(
      item.id,
    ).where((ref) => ref.relinkNeeded).length;
    final type = _localCatalogMediaType(item.mediaKind);
    final subtitleLines = <String>[
      'Private shelf: ${catalog.name}',
      if (item.description.trim().isNotEmpty) item.description.trim(),
      if (relinkNeededCount > 0)
        relinkNeededCount == 1
            ? '1 local video still needs to be re-picked on this device.'
            : '$relinkNeededCount local video references still need to be re-picked on this device.',
      if (relinkNeededCount == 0)
        'Playback stays locked until local playback setup is completed.',
    ];
    return CatalogItem(
      type: type,
      id: localCatalogSurfaceItemId(catalog.id, item.id),
      name: item.title,
      poster: _safeLocalArtworkUrl(item.posterUrl),
      background: _safeLocalArtworkUrl(item.backgroundUrl),
      year: item.releaseYear?.toString(),
      genres: item.tags,
      description: subtitleLines.join('\n\n'),
      isLocalCatalogItem: true,
      localPlaybackLocked: true,
      localCatalogId: catalog.id,
      localCatalogItemId: item.id,
      localCatalogName: catalog.name,
      localMediaKind: item.mediaKind,
      localSourceLabel: 'Local private shelf',
      localRelinkNeededCount: relinkNeededCount,
    );
  }

  static List<CatalogItem> localCatalogSurfaceItems({
    MediaType? type,
    String search = '',
    String genre = 'All genres',
  }) {
    // Catalog Builder is parked; existing saved metadata stays inert.
    return const <CatalogItem>[];
    final items = <CatalogItem>[];
    for (final localItem in localCatalogItems.value) {
      final catalog = localCatalogById(localItem.catalogId);
      if (catalog == null) continue;
      final itemType = _localCatalogMediaType(localItem.mediaKind);
      if (type != null && itemType != type) continue;
      if (!_localCatalogTagMatchesGenre(localItem, genre)) continue;
      if (!_localCatalogItemMatchesSearch(localItem, catalog, search)) {
        continue;
      }
      items.add(localCatalogSurfaceItem(catalog, localItem));
    }
    items.sort((left, right) {
      final yearCompare = _itemYearFromCatalogItem(
        right,
      ).compareTo(_itemYearFromCatalogItem(left));
      if (yearCompare != 0) return yearCompare;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return items;
  }

  static int _itemYearFromCatalogItem(CatalogItem item) {
    return int.tryParse(item.year ?? '') ?? 0;
  }

  static List<LocalPickedAssetRef> localPickedAssetRefsFor(String itemId) {
    return [
      for (final ref in localPickedAssetRefs.value)
        if (ref.itemId == itemId) ref,
    ];
  }

  static List<LocalPickedAssetRef> localPickedAssetRefsForCatalog(
    String catalogId,
  ) {
    return [
      for (final ref in localPickedAssetRefs.value)
        if (ref.catalogId == catalogId) ref,
    ];
  }

  static void registerLocalPickedAssetRef({
    required String catalogId,
    required String itemId,
    String mediaKind = 'video',
  }) {
    final cleanedCatalogId = catalogId.trim();
    final cleanedItemId = itemId.trim();
    if (cleanedCatalogId.isEmpty || cleanedItemId.isEmpty) return;
    final now = DateTime.now();
    localPickedAssetRefs.value = <LocalPickedAssetRef>[
      ...localPickedAssetRefs.value,
      LocalPickedAssetRef(
        id: now.microsecondsSinceEpoch.toString(),
        catalogId: cleanedCatalogId,
        itemId: cleanedItemId,
        mediaKind: mediaKind.trim().isEmpty ? 'video' : mediaKind.trim(),
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  static void clearLocalPickedAssetRefsForItem(String itemId) {
    final cleanedItemId = itemId.trim();
    if (cleanedItemId.isEmpty) return;
    localPickedAssetRefs.value = [
      for (final ref in localPickedAssetRefs.value)
        if (ref.itemId != cleanedItemId) ref,
    ];
  }

  static Map<String, dynamic> exportLocalCatalogSummary() {
    final kindCounts = <String, int>{};
    var taggedItemCount = 0;
    var runtimeItemCount = 0;
    var releaseYearItemCount = 0;
    var artworkUrlItemCount = 0;
    var preferredEngineItemCount = 0;
    var relinkNeededCount = 0;
    for (final ref in localPickedAssetRefs.value) {
      if (ref.relinkNeeded) relinkNeededCount++;
    }
    for (final item in localCatalogItems.value) {
      kindCounts[item.mediaKind] = (kindCounts[item.mediaKind] ?? 0) + 1;
      if (item.tags.isNotEmpty) taggedItemCount++;
      if (item.runtimeSeconds != null && item.runtimeSeconds! > 0) {
        runtimeItemCount++;
      }
      if (item.releaseYear != null && item.releaseYear! > 0) {
        releaseYearItemCount++;
      }
      if (_safeLocalArtworkUrl(item.posterUrl) != null ||
          _safeLocalArtworkUrl(item.backgroundUrl) != null) {
        artworkUrlItemCount++;
      }
      if (_safeLocalPlaybackEngine(item.preferredPlaybackEngine) != 'auto') {
        preferredEngineItemCount++;
      }
    }
    return <String, dynamic>{
      'catalogCount': localCatalogs.value.length,
      'itemCount': localCatalogItems.value.length,
      'localSurfaceCount': localCatalogSurfaceItems().length,
      'localPlaybackLockedCount': localCatalogItems.value.length,
      'kindCounts': kindCounts,
      'taggedItemCount': taggedItemCount,
      'runtimeItemCount': runtimeItemCount,
      'releaseYearItemCount': releaseYearItemCount,
      'artworkUrlItemCount': artworkUrlItemCount,
      'preferredEngineItemCount': preferredEngineItemCount,
      'pickedAssetRefCount': localPickedAssetRefs.value.length,
      'relinkNeededPickedAssetCount': relinkNeededCount,
      'hasPickedAssetRefs': localPickedAssetRefs.value.isNotEmpty,
      'hasMediaRefs': false,
      'hasPathLikeFields': false,
      'hasRawUris': false,
      'hasPickerHandles': false,
      'hasFileNames': false,
      'resolverProviderLearning': false,
      'verifiedCacheMovement': false,
      'watchMetricMovement': false,
      'storagePermissionMode': 'none',
      'fileAccessMode': localPickedAssetRefs.value.isEmpty
          ? 'not_started'
          : 'picker_refs_require_relink',
      'diagnosticsRedaction': 'counts_only',
    };
  }

  static String exportLocalCatalogMetadata(LocalCatalog catalog) {
    final items = localCatalogItemsFor(catalog.id);
    final pickedRefs = localPickedAssetRefsForCatalog(catalog.id);
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'juicr.local_catalog.metadata_export.v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'scope': 'metadata_only',
      'relink': <String, Object>{
        'pickedAssetsRequireRelink': pickedRefs.isNotEmpty,
        'pickedAssetCount': pickedRefs.length,
      },
      'redaction': <String, Object>{
        'containsFileNames': false,
        'containsFilePaths': false,
        'containsPickedFileHandles': false,
        'containsScopedUris': false,
        'containsMediaRefs': false,
        'containsUploads': false,
        'storagePermissionMode': 'none',
      },
      'catalog': catalog.toJson(),
      'items': [for (final item in items) item.toJson()],
      'pickedEntries': [for (final ref in pickedRefs) ref.toJson()],
    });
  }

  static String exportLocalCatalogItemMetadata({
    required LocalCatalog catalog,
    required LocalCatalogItem item,
  }) {
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'juicr.local_catalog.item_metadata_export.v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'scope': 'metadata_only',
      'redaction': <String, Object>{
        'containsFileNames': false,
        'containsFilePaths': false,
        'containsPickedFileHandles': false,
        'containsScopedUris': false,
        'containsMediaRefs': false,
        'containsUploads': false,
        'storagePermissionMode': 'none',
      },
      'catalog': <String, Object>{'id': catalog.id, 'name': catalog.name},
      'item': item.toJson(),
    });
  }

  static LocalCatalogImportResult? importLocalCatalogMetadata(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['schema'] != 'juicr.local_catalog.metadata_export.v1') {
      return null;
    }
    if (decoded['scope'] != 'metadata_only') return null;
    final redaction = decoded['redaction'];
    if (redaction is! Map<String, dynamic>) return null;
    final safeRedaction =
        redaction['containsFileNames'] == false &&
        redaction['containsFilePaths'] == false &&
        redaction['containsPickedFileHandles'] == false &&
        redaction['containsScopedUris'] == false &&
        redaction['containsMediaRefs'] == false &&
        redaction['containsUploads'] == false &&
        redaction['storagePermissionMode'] == 'none';
    if (!safeRedaction) return null;
    final catalogJson = decoded['catalog'];
    if (catalogJson is! Map<String, dynamic>) return null;
    final catalogName = (catalogJson['name'] ?? '').toString().trim();
    if (catalogName.isEmpty) return null;
    final now = DateTime.now();
    final catalogId = now.microsecondsSinceEpoch.toString();
    final importedCatalog = LocalCatalog(
      id: catalogId,
      name: catalogName,
      description: (catalogJson['description'] ?? '').toString().trim(),
      createdAt: now,
    );
    final importedItems = <LocalCatalogItem>[];
    final importedItemIdByOriginalId = <String, String>{};
    final rawItems = decoded['items'];
    if (rawItems is List) {
      var index = 0;
      for (final rawItem in rawItems) {
        if (rawItem is! Map<String, dynamic>) continue;
        final title = (rawItem['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final itemTime = now.add(Duration(microseconds: ++index));
        final itemId = itemTime.microsecondsSinceEpoch.toString();
        final originalItemId = (rawItem['id'] ?? '').toString().trim();
        if (originalItemId.isNotEmpty) {
          importedItemIdByOriginalId[originalItemId] = itemId;
        }
        importedItems.add(
          LocalCatalogItem(
            id: itemId,
            catalogId: catalogId,
            title: title,
            description: (rawItem['description'] ?? '').toString().trim(),
            mediaKind: (rawItem['mediaKind'] ?? 'movie').toString().trim(),
            tags: _stringList(rawItem['tags']),
            releaseYear: _intOrNull(rawItem['releaseYear']),
            runtimeSeconds: _intOrNull(rawItem['runtimeSeconds']),
            createdAt: itemTime,
            updatedAt: itemTime,
          ),
        );
      }
    }
    final importedPickedRefs = <LocalPickedAssetRef>[];
    final rawPickedEntries = decoded['pickedEntries'];
    if (rawPickedEntries is List) {
      var index = 0;
      for (final rawRef in rawPickedEntries) {
        if (rawRef is! Map<String, dynamic>) continue;
        const forbiddenPickedEntryKeys = <String>{
          'fileName',
          'filePath',
          'pickedFileHandle',
          'scopedUri',
          'mediaRef',
          'assetRef',
          'contentHash',
          'uri',
          'path',
        };
        if (rawRef.keys.any(forbiddenPickedEntryKeys.contains)) return null;
        final originalItemId = (rawRef['itemId'] ?? '').toString().trim();
        final importedItemId = importedItemIdByOriginalId[originalItemId];
        if (importedItemId == null || importedItemId.isEmpty) continue;
        final refTime = now.add(
          Duration(milliseconds: 1, microseconds: ++index),
        );
        importedPickedRefs.add(
          LocalPickedAssetRef(
            id: refTime.microsecondsSinceEpoch.toString(),
            catalogId: catalogId,
            itemId: importedItemId,
            mediaKind: (rawRef['mediaKind'] ?? 'video').toString().trim(),
            relinkNeeded: true,
            proofState: 'relink_required_after_import',
            createdAt: refTime,
            updatedAt: refTime,
          ),
        );
      }
    }
    localCatalogs.value = <LocalCatalog>[
      ...localCatalogs.value,
      importedCatalog,
    ];
    if (importedItems.isNotEmpty) {
      localCatalogItems.value = <LocalCatalogItem>[
        ...localCatalogItems.value,
        ...importedItems,
      ];
    }
    if (importedPickedRefs.isNotEmpty) {
      localPickedAssetRefs.value = <LocalPickedAssetRef>[
        ...localPickedAssetRefs.value,
        ...importedPickedRefs,
      ];
    }
    return LocalCatalogImportResult(
      catalogName: catalogName,
      itemCount: importedItems.length,
    );
  }

  static LocalCatalogImportResult? importLocalCatalogItemMetadata(
    String value, {
    required String catalogId,
  }) {
    final cleanedCatalogId = catalogId.trim();
    if (cleanedCatalogId.isEmpty) return null;
    LocalCatalog? targetCatalog;
    for (final catalog in localCatalogs.value) {
      if (catalog.id == cleanedCatalogId) {
        targetCatalog = catalog;
        break;
      }
    }
    if (targetCatalog == null) return null;
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['schema'] != 'juicr.local_catalog.item_metadata_export.v1') {
      return null;
    }
    if (decoded['scope'] != 'metadata_only') return null;
    final redaction = decoded['redaction'];
    if (redaction is! Map<String, dynamic>) return null;
    final safeRedaction =
        redaction['containsFileNames'] == false &&
        redaction['containsFilePaths'] == false &&
        redaction['containsPickedFileHandles'] == false &&
        redaction['containsScopedUris'] == false &&
        redaction['containsMediaRefs'] == false &&
        redaction['containsUploads'] == false &&
        redaction['storagePermissionMode'] == 'none';
    if (!safeRedaction) return null;
    final rawItem = decoded['item'];
    if (rawItem is! Map<String, dynamic>) return null;
    final forbiddenKeys = <String>{
      'fileName',
      'filePath',
      'pickedFileHandle',
      'scopedUri',
      'mediaRef',
      'assetRef',
      'uri',
      'path',
    };
    if (rawItem.keys.any((key) => forbiddenKeys.contains(key))) return null;
    final title = (rawItem['title'] ?? '').toString().trim();
    if (title.isEmpty) return null;
    final now = DateTime.now();
    localCatalogItems.value = <LocalCatalogItem>[
      ...localCatalogItems.value,
      LocalCatalogItem(
        id: now.microsecondsSinceEpoch.toString(),
        catalogId: cleanedCatalogId,
        title: title,
        description: (rawItem['description'] ?? '').toString().trim(),
        mediaKind: (rawItem['mediaKind'] ?? 'movie').toString().trim(),
        tags: _stringList(rawItem['tags']),
        releaseYear: _intOrNull(rawItem['releaseYear']),
        runtimeSeconds: _intOrNull(rawItem['runtimeSeconds']),
        createdAt: now,
        updatedAt: now,
      ),
    ];
    return LocalCatalogImportResult(
      catalogName: targetCatalog.name,
      itemCount: 1,
    );
  }

  static void addLocalCatalogItem({
    required String catalogId,
    required String title,
    String description = '',
    String mediaKind = 'movie',
    List<String> tags = const <String>[],
    int? releaseYear,
    int? runtimeSeconds,
    String posterUrl = '',
    String backgroundUrl = '',
    String preferredPlaybackEngine = 'auto',
  }) {
    final cleanedCatalogId = catalogId.trim();
    final cleanedTitle = title.trim();
    if (cleanedCatalogId.isEmpty || cleanedTitle.isEmpty) return;
    if (!localCatalogs.value.any((catalog) => catalog.id == cleanedCatalogId)) {
      return;
    }
    final now = DateTime.now();
    final cleanedTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    localCatalogItems.value = <LocalCatalogItem>[
      ...localCatalogItems.value,
      LocalCatalogItem(
        id: now.microsecondsSinceEpoch.toString(),
        catalogId: cleanedCatalogId,
        title: cleanedTitle,
        description: description.trim(),
        mediaKind: mediaKind.trim().isEmpty ? 'movie' : mediaKind.trim(),
        tags: cleanedTags,
        releaseYear: releaseYear,
        runtimeSeconds: runtimeSeconds,
        posterUrl: _safeLocalArtworkUrl(posterUrl) ?? '',
        backgroundUrl: _safeLocalArtworkUrl(backgroundUrl) ?? '',
        preferredPlaybackEngine: _safeLocalPlaybackEngine(
          preferredPlaybackEngine,
        ),
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  static void updateLocalCatalogItemMetadata({
    required String id,
    required String title,
    String description = '',
    String mediaKind = 'movie',
    List<String> tags = const <String>[],
    int? releaseYear,
    int? runtimeSeconds,
    String? posterUrl,
    String? backgroundUrl,
    String? preferredPlaybackEngine,
  }) {
    final cleanedId = id.trim();
    final cleanedTitle = title.trim();
    if (cleanedId.isEmpty || cleanedTitle.isEmpty) return;

    final cleanedTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    localCatalogItems.value = [
      for (final item in localCatalogItems.value)
        if (item.id == cleanedId)
          LocalCatalogItem(
            id: item.id,
            catalogId: item.catalogId,
            title: cleanedTitle,
            description: description.trim(),
            mediaKind: mediaKind.trim().isEmpty ? 'movie' : mediaKind.trim(),
            tags: cleanedTags,
            releaseYear: releaseYear,
            runtimeSeconds: runtimeSeconds,
            posterUrl: posterUrl == null
                ? item.posterUrl
                : (_safeLocalArtworkUrl(posterUrl) ?? ''),
            backgroundUrl: backgroundUrl == null
                ? item.backgroundUrl
                : (_safeLocalArtworkUrl(backgroundUrl) ?? ''),
            preferredPlaybackEngine: preferredPlaybackEngine == null
                ? item.preferredPlaybackEngine
                : _safeLocalPlaybackEngine(preferredPlaybackEngine),
            createdAt: item.createdAt,
            updatedAt: DateTime.now(),
          )
        else
          item,
    ];
  }

  static void removeLocalCatalogItem(String id) {
    localCatalogItems.value = [
      for (final item in localCatalogItems.value)
        if (item.id != id) item,
    ];
    localPickedAssetRefs.value = [
      for (final ref in localPickedAssetRefs.value)
        if (ref.itemId != id) ref,
    ];
  }

  static void clearLocalCatalogItems(String catalogId) {
    localCatalogItems.value = [
      for (final item in localCatalogItems.value)
        if (item.catalogId != catalogId) item,
    ];
    localPickedAssetRefs.value = [
      for (final ref in localPickedAssetRefs.value)
        if (ref.catalogId != catalogId) ref,
    ];
  }

  static void setDefaultCatalogEnabled(bool enabled) {
    if (defaultCatalogEnabled.value == enabled) return;
    defaultCatalogEnabled.value = enabled;
  }

  static void setShowMatureContent(bool enabled) {
    markMatureContentChoiceSeen();
    if (showMatureContent.value == enabled) return;
    showMatureContent.value = enabled;
  }

  static void markMatureContentChoiceSeen() {
    if (matureContentChoiceSeen.value) return;
    matureContentChoiceSeen.value = true;
  }

  static bool tryBeginMatureContentChoice() {
    if (_matureContentChoiceInFlight || matureContentChoiceSeen.value) {
      return false;
    }
    _matureContentChoiceInFlight = true;
    return true;
  }

  static void finishMatureContentChoice() {
    _matureContentChoiceInFlight = false;
  }

  static void setDefaultProvidersEnabled(bool enabled) {
    if (defaultProvidersEnabled.value == enabled) return;
    defaultProvidersEnabled.value = enabled;
  }

  static void setDefaultSubtitlesEnabled(bool enabled) {
    if (defaultSubtitlesEnabled.value == enabled) return;
    defaultSubtitlesEnabled.value = enabled;
  }

  static void setDefaultTrailersEnabled(bool enabled) {
    if (defaultTrailersEnabled.value == enabled) return;
    defaultTrailersEnabled.value = enabled;
  }

  static void setTvSourcesEnabled(bool enabled) {
    if (tvSourcesEnabled.value == enabled) return;
    tvSourcesEnabled.value = enabled;
    if (!enabled && publicIptvEnabled.value) {
      publicIptvEnabled.value = false;
    }
  }

  static void setPublicIptvEnabled(bool enabled) {
    if (enabled && !tvSourcesEnabled.value) {
      tvSourcesEnabled.value = true;
    }
    if (publicIptvEnabled.value == enabled) return;
    publicIptvEnabled.value = enabled;
  }

  static void acceptDefaultSourceDisclaimer() {
    if (defaultSourceDisclaimerAccepted.value) return;
    defaultSourceDisclaimerAccepted.value = true;
  }

  static void acceptAddonDisclaimer() {
    if (addonDisclaimerAccepted.value) return;
    addonDisclaimerAccepted.value = true;
  }

  static void markFirstRunWelcomeSeen() {
    if (firstRunWelcomeSeen.value) return;
    firstRunWelcomeSeen.value = true;
  }

  static void acceptExperimentalDisclaimer() {
    if (experimentalDisclaimerAccepted.value) return;
    experimentalDisclaimerAccepted.value = true;
  }

  static ContinueWatchingEntry? progressFor(
    CatalogItem item, {
    String? playbackKey,
  }) {
    if (item.type.isLive) return null;
    final current = _continueWatchingSnapshot;
    final key = playbackKey?.trim();
    if (key == null || key.isEmpty) return current[item.id];
    final exact = current[key];
    final contentKey = contentPlaybackKeyFor(item, key);
    final canonical = current[contentKey];
    final bestKnown = _preferredResumeEntry(exact, canonical);
    if (bestKnown != null) return bestKnown;

    if (!item.type.isPlayableSeries) return current[item.id];
    final targetIdentity =
        '${item.type.compatTypeValue}:${contentKey.toLowerCase()}';
    ContinueWatchingEntry? bestIdentityMatch;
    for (final entry in current.values) {
      if (_continueWatchingIdentityFor(entry) == targetIdentity) {
        bestIdentityMatch = _preferredResumeEntry(bestIdentityMatch, entry);
      }
    }
    return bestIdentityMatch;
  }

  static ContinueWatchingEntry? _preferredResumeEntry(
    ContinueWatchingEntry? a,
    ContinueWatchingEntry? b,
  ) {
    if (a == null) return b;
    if (b == null) return a;

    final watchedCompare = a.watchedSeconds.compareTo(b.watchedSeconds);
    if (watchedCompare != 0) return watchedCompare > 0 ? a : b;

    final progressCompare = a.progress.compareTo(b.progress);
    if (progressCompare != 0) return progressCompare > 0 ? a : b;

    final updatedCompare = a.updatedAt.compareTo(b.updatedAt);
    if (updatedCompare != 0) return updatedCompare > 0 ? a : b;

    final aCanonical = a.key == contentPlaybackKeyFor(a.item, a.key);
    final bCanonical = b.key == contentPlaybackKeyFor(b.item, b.key);
    if (aCanonical != bCanonical) return aCanonical ? a : b;

    return a;
  }

  static ContinueWatchingEntry _canonicalProgressMirrorEntry({
    required CatalogItem item,
    required String contentKey,
    required String title,
    String? subtitle,
    required int watchedSeconds,
    required int credibleWatchedSeconds,
    required int durationSeconds,
    required double progress,
    required DateTime updatedAt,
    NativePlayerPreferences? nativePreferences,
  }) {
    final existing = _continueWatchingSnapshot[contentKey];
    final watched = math
        .max(existing?.watchedSeconds ?? 0, watchedSeconds)
        .clamp(0, durationSeconds)
        .toInt();
    final credibleWatched = math
        .max(existing?.credibleWatchedSeconds ?? 0, credibleWatchedSeconds)
        .clamp(0, durationSeconds)
        .toInt();
    final safeProgress = math
        .max(existing?.progress ?? 0, progress)
        .clamp(0.02, 0.98)
        .toDouble();
    return ContinueWatchingEntry(
      key: contentKey,
      item: item,
      title: title,
      subtitle: subtitle,
      watchedSeconds: watched,
      credibleWatchedSeconds: credibleWatched,
      durationSeconds: durationSeconds,
      progress: safeProgress,
      updatedAt: updatedAt,
      nativePreferences: nativePreferences ?? existing?.nativePreferences,
    );
  }

  static String contentPlaybackKeyFor(CatalogItem item, String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty || trimmed == item.id) return trimmed;
    final suffix = ':${item.id}';
    final suffixIndex = trimmed.lastIndexOf(suffix);
    if (suffixIndex < 0) return trimmed;
    return trimmed.substring(suffixIndex + 1);
  }

  static bool isDisplayableContinueEntry(ContinueWatchingEntry entry) {
    if (entry.item.type.isLive) return false;
    final contentKey = contentPlaybackKeyFor(entry.item, entry.key);
    if (!entry.item.type.isPlayableSeries) {
      return contentKey == entry.item.id;
    }
    final prefix = '${entry.item.id}:';
    if (!contentKey.startsWith(prefix)) return false;
    final parts = contentKey.substring(prefix.length).split(':');
    if (parts.length != 2) return false;
    final season = int.tryParse(parts[0]);
    final episode = int.tryParse(parts[1]);
    return season != null && season > 0 && episode != null && episode > 0;
  }

  static List<ContinueWatchingEntry> displayableContinueEntries(
    Iterable<ContinueWatchingEntry> entries,
  ) {
    final byIdentity = <String, ContinueWatchingEntry>{};
    for (final entry in entries) {
      final identity = _continueWatchingDisplayIdentityFor(entry);
      if (identity == null) continue;
      final existing = byIdentity[identity];
      byIdentity[identity] = existing == null
          ? entry
          : _preferredContinueEntry(existing, entry);
    }
    return byIdentity.values.toList();
  }

  static void recordPlaybackProgress({
    required CatalogItem item,
    required String playbackKey,
    required String title,
    String? subtitle,
    int? durationSeconds,
    required int watchedSeconds,
    int? credibleWatchedSeconds,
    bool completionObserved = false,
    bool trustedCompletionObserved = false,
    int? generation,
    NativePlayerPreferences? nativePreferences,
  }) {
    if (item.type.isLive) return;
    if (generation != null && generation != _continueWatchingGeneration) return;
    final fallbackDuration = durationSeconds == null || durationSeconds <= 0
        ? (item.type.isPlayableSeries ? 10 * 60 * 60 : 45 * 60)
        : durationSeconds;
    final current = _continueWatchingSnapshot;
    final existing = current[playbackKey];
    final credibleDelta = (credibleWatchedSeconds ?? watchedSeconds)
        .clamp(0, fallbackDuration)
        .toInt();
    final watched = ((existing?.watchedSeconds ?? 0) + watchedSeconds)
        .clamp(0, fallbackDuration)
        .toInt();
    final credibleWatched =
        ((existing?.credibleWatchedSeconds ?? 0) + credibleDelta)
            .clamp(0, fallbackDuration)
            .toInt();
    final progress = (watched / fallbackDuration).clamp(0.02, 0.98).toDouble();
    if (credibleDelta > 0) {
      recordTasteForItem(item, weight: (credibleDelta / 90).clamp(0.25, 4));
    }
    final completionCredible = hasCredibleCompletionEvidence(
      durationSeconds: fallbackDuration,
      credibleWatchedSeconds: credibleWatched,
    );
    if (completionObserved &&
        progress >= 0.95 &&
        (trustedCompletionObserved || completionCredible)) {
      _markPlaybackCompleted(
        item: item,
        playbackKey: playbackKey,
        title: title,
        subtitle: subtitle,
        watchedSeconds: watched,
        credibleWatchedSeconds: credibleWatched,
        durationSeconds: fallbackDuration,
      );
      final next = Map<String, ContinueWatchingEntry>.from(
        _continueWatchingSnapshot,
      )..remove(playbackKey);
      final contentKey = contentPlaybackKeyFor(item, playbackKey);
      if (contentKey != playbackKey) next.remove(contentKey);
      if (playbackKey != item.id) next.remove(item.id);
      _setContinueWatching(next);
      return;
    }
    final next = Map<String, ContinueWatchingEntry>.from(current);
    final contentKey = contentPlaybackKeyFor(item, playbackKey);
    next[playbackKey] = ContinueWatchingEntry(
      key: playbackKey,
      item: item,
      title: title,
      subtitle: subtitle,
      watchedSeconds: watched,
      credibleWatchedSeconds: credibleWatched,
      durationSeconds: fallbackDuration,
      progress: progress,
      updatedAt: DateTime.now(),
      nativePreferences: nativePreferences ?? existing?.nativePreferences,
    );
    if (contentKey.isNotEmpty && contentKey != playbackKey) {
      next[contentKey] = _canonicalProgressMirrorEntry(
        item: item,
        contentKey: contentKey,
        title: title,
        subtitle: subtitle,
        watchedSeconds: watched,
        credibleWatchedSeconds: credibleWatched,
        durationSeconds: fallbackDuration,
        progress: progress,
        updatedAt: DateTime.now(),
        nativePreferences: nativePreferences,
      );
    }
    _setContinueWatching(next);
  }

  static void setPlaybackProgress({
    required CatalogItem item,
    required String playbackKey,
    required String title,
    String? subtitle,
    required int durationSeconds,
    required int watchedSeconds,
    int credibleWatchedSeconds = 0,
    bool completionObserved = false,
    bool trustedCompletionObserved = false,
    int? generation,
    NativePlayerPreferences? nativePreferences,
  }) {
    if (item.type.isLive) return;
    if (generation != null && generation != _continueWatchingGeneration) return;
    if (durationSeconds <= 0) return;

    final watched = watchedSeconds.clamp(0, durationSeconds).toInt();
    final current = _continueWatchingSnapshot;
    final existing = current[playbackKey];
    final credibleWatched = math
        .max(existing?.credibleWatchedSeconds ?? 0, credibleWatchedSeconds)
        .clamp(0, durationSeconds)
        .toInt();
    final progress = (watched / durationSeconds).clamp(0.02, 0.98).toDouble();
    final credibleDelta = math.max(
      0,
      credibleWatched - (existing?.credibleWatchedSeconds ?? 0),
    );
    if (credibleDelta > 0) {
      recordTasteForItem(item, weight: (credibleDelta / 300).clamp(0.5, 5));
    }
    final completionCredible = hasCredibleCompletionEvidence(
      durationSeconds: durationSeconds,
      credibleWatchedSeconds: credibleWatched,
    );
    if (completionObserved &&
        progress >= 0.95 &&
        (trustedCompletionObserved || completionCredible)) {
      _markPlaybackCompleted(
        item: item,
        playbackKey: playbackKey,
        title: title,
        subtitle: subtitle,
        watchedSeconds: watched,
        credibleWatchedSeconds: credibleWatched,
        durationSeconds: durationSeconds,
      );
      final next = Map<String, ContinueWatchingEntry>.from(
        _continueWatchingSnapshot,
      )..remove(playbackKey);
      final contentKey = contentPlaybackKeyFor(item, playbackKey);
      if (contentKey != playbackKey) next.remove(contentKey);
      if (playbackKey != item.id) next.remove(item.id);
      _setContinueWatching(next);
      return;
    }

    final next = Map<String, ContinueWatchingEntry>.from(current);
    final contentKey = contentPlaybackKeyFor(item, playbackKey);
    next[playbackKey] = ContinueWatchingEntry(
      key: playbackKey,
      item: item,
      title: title,
      subtitle: subtitle,
      watchedSeconds: watched,
      credibleWatchedSeconds: credibleWatched,
      durationSeconds: durationSeconds,
      progress: progress,
      updatedAt: DateTime.now(),
      nativePreferences: nativePreferences ?? existing?.nativePreferences,
    );
    if (contentKey.isNotEmpty && contentKey != playbackKey) {
      next[contentKey] = _canonicalProgressMirrorEntry(
        item: item,
        contentKey: contentKey,
        title: title,
        subtitle: subtitle,
        watchedSeconds: watched,
        credibleWatchedSeconds: credibleWatched,
        durationSeconds: durationSeconds,
        progress: progress,
        updatedAt: DateTime.now(),
        nativePreferences: nativePreferences,
      );
    }
    _setContinueWatching(next);
  }

  static void updateNativePlayerPreferences({
    required CatalogItem item,
    required String playbackKey,
    required String title,
    String? subtitle,
    int? generation,
    required NativePlayerPreferences nativePreferences,
  }) {
    if (item.type.isLive) return;
    if (generation != null && generation != _continueWatchingGeneration) return;
    if (playbackKey.trim().isEmpty) return;

    final current = _continueWatchingSnapshot;
    final existing = progressFor(item, playbackKey: playbackKey);
    final durationSeconds =
        existing?.durationSeconds ??
        (item.type.isPlayableSeries ? 10 * 60 * 60 : 45 * 60);
    final watchedSeconds = (existing?.watchedSeconds ?? 0)
        .clamp(0, durationSeconds)
        .toInt();
    final credibleWatchedSeconds = (existing?.credibleWatchedSeconds ?? 0)
        .clamp(0, durationSeconds)
        .toInt();
    final progress = (existing?.progress ?? 0.02).clamp(0.02, 0.98).toDouble();
    final updatedAt = DateTime.now();
    final contentKey = contentPlaybackKeyFor(item, playbackKey);
    final next = Map<String, ContinueWatchingEntry>.from(current);

    next[playbackKey] = ContinueWatchingEntry(
      key: playbackKey,
      item: item,
      title: title,
      subtitle: subtitle,
      watchedSeconds: watchedSeconds,
      credibleWatchedSeconds: credibleWatchedSeconds,
      durationSeconds: durationSeconds,
      progress: progress,
      updatedAt: updatedAt,
      nativePreferences: nativePreferences,
    );
    if (contentKey.isNotEmpty && contentKey != playbackKey) {
      next[contentKey] = _canonicalProgressMirrorEntry(
        item: item,
        contentKey: contentKey,
        title: title,
        subtitle: subtitle,
        watchedSeconds: watchedSeconds,
        credibleWatchedSeconds: credibleWatchedSeconds,
        durationSeconds: durationSeconds,
        progress: progress,
        updatedAt: updatedAt,
        nativePreferences: nativePreferences,
      );
    }
    _setContinueWatching(next);
  }

  static void clearSavedNativePlayerSettings() {
    final current = _continueWatchingSnapshot;
    if (current.isEmpty) return;
    _setContinueWatching({
      for (final entry in current.entries)
        entry.key: entry.value.copyWith(clearNativePreferences: true),
    });
  }

  static void removeContinueWatching(String key) {
    final current = _continueWatchingSnapshot;
    if (!current.containsKey(key)) return;
    final next = Map<String, ContinueWatchingEntry>.from(current)..remove(key);
    _setContinueWatching(next);
  }

  static void _markPlaybackCompleted({
    required CatalogItem item,
    required String playbackKey,
    required String title,
    String? subtitle,
    required int watchedSeconds,
    required int credibleWatchedSeconds,
    required int durationSeconds,
  }) {
    if (item.type.isLive || playbackKey.isEmpty) return;
    final next = Map<String, CompletedWatchingEntry>.from(
      completedWatching.value,
    );
    final completedKey = _completedPlaybackKey(item, playbackKey);
    if (!item.type.isPlayableSeries) {
      next.removeWhere((_, entry) => entry.item.id == item.id);
    }
    final existing = next[completedKey];
    next[completedKey] = CompletedWatchingEntry(
      key: completedKey,
      item: item,
      title: title,
      subtitle: subtitle,
      watchedSeconds: (existing?.watchedSeconds ?? 0) + watchedSeconds,
      credibleWatchedSeconds:
          (existing?.credibleWatchedSeconds ?? 0) + credibleWatchedSeconds,
      durationSeconds: durationSeconds,
      completedAt: DateTime.now(),
      completionCount: (existing?.completionCount ?? 0) + 1,
    );
    final entries = next.values.toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    completedWatching.value = {
      for (final entry in entries.take(500)) entry.key: entry,
    };
    _removeContinueWatchingForCompletion(item: item, playbackKey: playbackKey);
  }

  static void _removeContinueWatchingForCompletion({
    required CatalogItem item,
    required String playbackKey,
  }) {
    final current = _continueWatchingSnapshot;
    if (current.isEmpty) return;
    final contentKey = contentPlaybackKeyFor(item, playbackKey);
    final next = Map<String, ContinueWatchingEntry>.from(current)
      ..remove(playbackKey)
      ..remove(contentKey)
      ..remove(item.id);
    if (!item.type.isPlayableSeries) {
      next.removeWhere((_, entry) => entry.item.id == item.id);
    }
    if (next.length == current.length) return;
    _setContinueWatching(next);
  }

  static String _completedPlaybackKey(CatalogItem item, String playbackKey) {
    if (item.type.isPlayableSeries) return playbackKey;
    return item.id;
  }

  static bool hasCredibleCompletionEvidence({
    required int durationSeconds,
    required int credibleWatchedSeconds,
  }) {
    if (durationSeconds <= 0) return false;
    final threshold = (durationSeconds * 0.18).round().clamp(180, 900).toInt();
    return credibleWatchedSeconds >= threshold;
  }

  static void clearContinueWatching() {
    _clearContinueWatching(retainActiveWatchTime: true);
  }

  static void clearContinueWatchingForAccountDeletion() {
    _clearContinueWatching(retainActiveWatchTime: false);
  }

  static void _clearContinueWatching({required bool retainActiveWatchTime}) {
    if (retainActiveWatchTime) {
      _retainActiveWatchSecondsFromContinueWatching();
    }
    _continueWatchingGeneration += 1;
    _setContinueWatching(<String, ContinueWatchingEntry>{});
    unawaited(
      _prefs?.setString(_continueWatchingKey, '[]') ?? Future<void>.value(),
    );
  }

  static VerifiedPlaybackSource? verifiedPlaybackSourceFor(String? key) {
    if (key == null || key.isEmpty) return null;
    final entries = verifiedPlaybackSourcesFor(key);
    return entries.isEmpty ? null : entries.first;
  }

  static List<VerifiedPlaybackSource> verifiedPlaybackSourcesFor(String? key) {
    if (key == null || key.isEmpty) return const <VerifiedPlaybackSource>[];
    final entries = verifiedPlaybackSources.value[key] ?? const [];
    final sorted =
        entries.where((entry) => entry.source.url.isNotEmpty).toList()
          ..sort(_compareVerifiedPlaybackSources);
    return List<VerifiedPlaybackSource>.unmodifiable(sorted.take(3));
  }

  static void rememberVerifiedPlaybackSource({
    required String key,
    required PlaybackSource source,
    required String engineId,
    required DateTime cachedAt,
    int confidenceDelta = 10,
  }) {
    if (key.isEmpty || source.url.isEmpty) return;
    final next = Map<String, List<VerifiedPlaybackSource>>.from(
      verifiedPlaybackSources.value,
    );
    final current = List<VerifiedPlaybackSource>.from(
      next[key] ?? const <VerifiedPlaybackSource>[],
    );
    final index = current.indexWhere((entry) => entry.source.url == source.url);
    if (index >= 0) {
      final previous = current[index];
      current[index] = previous.copyWith(
        source: source,
        engineId: engineId,
        cachedAt: cachedAt,
        confidence: (previous.confidence + confidenceDelta).clamp(0, 100),
        successCount: previous.successCount + 1,
        clearFailure: true,
      );
    } else {
      current.add(
        VerifiedPlaybackSource(
          source: source,
          engineId: engineId,
          cachedAt: cachedAt,
          confidence: confidenceDelta.clamp(1, 100),
        ),
      );
    }
    current.sort(_compareVerifiedPlaybackSources);
    next[key] = List<VerifiedPlaybackSource>.unmodifiable(current.take(3));
    final totalEntries = next.values.fold<int>(
      0,
      (sum, entries) => sum + entries.length,
    );
    if (totalEntries > _verifiedPlaybackSourceLimit) {
      final orderedKeys = next.keys.toList()
        ..sort((a, b) {
          final left = next[a]!.isEmpty
              ? DateTime.fromMillisecondsSinceEpoch(0)
              : next[a]!.last.cachedAt;
          final right = next[b]!.isEmpty
              ? DateTime.fromMillisecondsSinceEpoch(0)
              : next[b]!.last.cachedAt;
          return left.compareTo(right);
        });
      var overflow = totalEntries - _verifiedPlaybackSourceLimit;
      for (final staleKey in orderedKeys.take(overflow)) {
        overflow -= next[staleKey]?.length ?? 0;
        next.remove(staleKey);
        if (overflow <= 0) break;
      }
    }
    verifiedPlaybackSources.value = next;
  }

  static void recordVerifiedPlaybackSourceFailure({
    required String key,
    required String sourceUrl,
    required String reason,
  }) {
    if (key.isEmpty || sourceUrl.isEmpty) return;
    final entries = List<VerifiedPlaybackSource>.from(
      verifiedPlaybackSources.value[key] ?? const <VerifiedPlaybackSource>[],
    );
    final index = entries.indexWhere((entry) => entry.source.url == sourceUrl);
    if (index < 0) return;
    final previous = entries[index];
    final penalty = _verifiedSourceFailurePenalty(reason);
    final nextConfidence = (previous.confidence - penalty).clamp(0, 100);
    if (nextConfidence <= 0 || _verifiedSourceIsHardExpired(reason)) {
      entries.removeAt(index);
    } else {
      entries[index] = previous.copyWith(
        confidence: nextConfidence,
        failureCount: previous.failureCount + 1,
        lastFailureReason: reason,
        lastFailureAt: DateTime.now(),
      );
    }
    entries.sort(_compareVerifiedPlaybackSources);
    final next = Map<String, List<VerifiedPlaybackSource>>.from(
      verifiedPlaybackSources.value,
    );
    if (entries.isEmpty) {
      next.remove(key);
    } else {
      next[key] = List<VerifiedPlaybackSource>.unmodifiable(entries.take(3));
    }
    verifiedPlaybackSources.value = next;
  }

  static void forgetVerifiedPlaybackSource(String key) {
    if (key.isEmpty || !verifiedPlaybackSources.value.containsKey(key)) return;
    verifiedPlaybackSources.value =
        Map<String, List<VerifiedPlaybackSource>>.from(
          verifiedPlaybackSources.value,
        )..remove(key);
  }

  static void _setContinueWatching(Map<String, ContinueWatchingEntry> next) {
    final normalized = _dedupeContinueWatchingMap(next);
    final schedulerPhase = SchedulerBinding.instance.schedulerPhase;
    if (schedulerPhase == SchedulerPhase.idle ||
        schedulerPhase == SchedulerPhase.postFrameCallbacks) {
      _pendingContinueWatching = null;
      continueWatching.value = normalized;
      return;
    }

    _pendingContinueWatching = normalized;
    if (_continueWatchingFlushScheduled) return;
    _continueWatchingFlushScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _continueWatchingFlushScheduled = false;
      final pending = _pendingContinueWatching;
      _pendingContinueWatching = null;
      if (pending != null) {
        continueWatching.value = pending;
      }
    });
  }

  static Map<String, ContinueWatchingEntry> get _continueWatchingSnapshot {
    return _pendingContinueWatching ?? continueWatching.value;
  }

  static Map<String, ContinueWatchingEntry> _dedupeContinueWatchingMap(
    Map<String, ContinueWatchingEntry> entries,
  ) {
    final passthrough = <String, ContinueWatchingEntry>{};
    final displayable = displayableContinueEntries(entries.values);
    final displayableKeys = displayable.map((entry) => entry.key).toSet();
    final displayableIdentities = displayable
        .map(_continueWatchingIdentityFor)
        .whereType<String>()
        .toSet();

    for (final entry in entries.values) {
      final identity = _continueWatchingIdentityFor(entry);
      if (identity != null && displayableIdentities.contains(identity)) {
        continue;
      }
      passthrough[entry.key] = entry;
    }

    return {
      ...passthrough,
      for (final entry in displayable)
        if (displayableKeys.contains(entry.key)) entry.key: entry,
    };
  }

  static String? _continueWatchingIdentityFor(ContinueWatchingEntry entry) {
    if (!isDisplayableContinueEntry(entry)) return null;
    final contentKey = contentPlaybackKeyFor(entry.item, entry.key);
    return '${entry.item.type.compatTypeValue}:${contentKey.toLowerCase()}';
  }

  static String? _continueWatchingDisplayIdentityFor(
    ContinueWatchingEntry entry,
  ) {
    if (!isDisplayableContinueEntry(entry)) return null;
    final contentKey = contentPlaybackKeyFor(entry.item, entry.key);
    if (!entry.item.type.isPlayableSeries) {
      return '${entry.item.type.compatTypeValue}:${contentKey.toLowerCase()}';
    }
    final prefix = '${entry.item.id}:';
    final identityKey = contentKey.startsWith(prefix)
        ? entry.item.id
        : contentKey;
    return '${entry.item.type.compatTypeValue}:${identityKey.toLowerCase()}';
  }

  static ContinueWatchingEntry _preferredContinueEntry(
    ContinueWatchingEntry a,
    ContinueWatchingEntry b,
  ) {
    if (a.item.type.isPlayableSeries || b.item.type.isPlayableSeries) {
      final updatedCompare = a.updatedAt.compareTo(b.updatedAt);
      if (updatedCompare != 0) return updatedCompare > 0 ? a : b;
    }

    final progressCompare = a.progress.compareTo(b.progress);
    if (progressCompare != 0) return progressCompare > 0 ? a : b;

    final updatedCompare = a.updatedAt.compareTo(b.updatedAt);
    if (updatedCompare != 0) return updatedCompare > 0 ? a : b;

    if (!a.item.type.isPlayableSeries) {
      final aCanonical = a.key == a.item.id;
      final bCanonical = b.key == b.item.id;
      if (aCanonical != bCanonical) return aCanonical ? a : b;
    }

    return a;
  }

  static Future<void> _persistThemeMode() async {
    await _prefs?.setString(_themeModeKey, themeMode.value.name);
  }

  static Future<void> _persistPureBlackTheme() async {
    await _prefs?.setBool(_pureBlackThemeKey, pureBlackTheme.value);
  }

  static Future<void> _persistUseDeviceAccent() async {
    await _prefs?.setBool(_useDeviceAccentKey, useDeviceAccent.value);
  }

  static Future<void> _persistAccentTheme() async {
    await _prefs?.setString(_accentThemeKey, accentThemeId.value);
  }

  static Future<void> _persistCustomAccentColor() async {
    await _prefs?.setInt(_customAccentColorKey, customAccentColor.value.value);
  }

  static Future<void> _persistStartupTabMode() async {
    await _prefs?.setString(_startupTabModeKey, startupTabMode.value);
  }

  static Future<void> _persistStartupBehavior() async {
    await _prefs?.setString(_startupBehaviorKey, startupBehavior.value);
  }

  static Future<void> _persistShellTab() async {
    await _prefs?.setInt(_shellTabKey, shellTab.value.clamp(0, 3).toInt());
  }

  static Future<void> _persistCompactLayout() async {
    await _prefs?.setBool(_compactLayoutKey, compactLayout.value);
  }

  static Future<void> _persistReduceMotion() async {
    await _prefs?.setBool(_reduceMotionKey, reduceMotion.value);
  }

  static Future<void> _persistTextSize() async {
    await _prefs?.setString(_textSizeKey, textSize.value);
  }

  static Future<void> _persistNavigationStyle() async {
    await _prefs?.setString(_navigationStyleKey, navigationStyle.value);
  }

  static Future<void> _persistHomeDensity() async {
    await _prefs?.setString(_homeDensityKey, homeDensity.value);
  }

  static Future<void> _persistArtworkMotion() async {
    await _prefs?.setBool(_artworkMotionKey, artworkMotion.value);
  }

  static Future<void> _persistConfirmDestructiveActions() async {
    await _prefs?.setBool(
      _confirmDestructiveActionsKey,
      confirmDestructiveActions.value,
    );
  }

  static Future<void> _persistHapticsEnabled() async {
    await _prefs?.setBool(_hapticsEnabledKey, hapticsEnabled.value);
  }

  static Future<void> _persistLeaderboardScope() async {
    await _prefs?.setString(_leaderboardScopeKey, leaderboardScope.value);
  }

  static Future<void> _persistStatusMessageStyle() async {
    await _prefs?.setString(_statusMessageStyleKey, statusMessageStyle.value);
  }

  static Future<void> _persistPosterImageIntensity() async {
    await _prefs?.setString(
      _posterImageIntensityKey,
      posterImageIntensity.value,
    );
  }

  static Future<void> _persistSystemBarStyle() async {
    await _prefs?.setString(_systemBarStyleKey, systemBarStyle.value);
  }

  static Future<void> _persistFirstRunWelcomeSeen() async {
    await _prefs?.setBool(_firstRunWelcomeSeenKey, firstRunWelcomeSeen.value);
  }

  static Future<void> _persistNotificationsEnabled() async {
    await _prefs?.setBool(_notificationsEnabledKey, notificationsEnabled.value);
  }

  static Future<void> _persistNotificationDialogsEnabled() async {
    await _prefs?.setBool(
      _notificationDialogsEnabledKey,
      notificationDialogsEnabled.value,
    );
  }

  static Future<void> _persistNotificationInterstitialsEnabled() async {
    await _prefs?.setBool(
      _notificationInterstitialsEnabledKey,
      notificationInterstitialsEnabled.value,
    );
  }

  static Future<void> _persistRewardedVideoAdsEnabled() async {
    if (_applyingAccountAdPreferences || _signedInAdPreferencesActive) return;
    await _prefs?.setBool(
      _rewardedVideoAdsEnabledKey,
      rewardedVideoAdsEnabled.value,
    );
  }

  static Future<void> _persistInterstitialAdsEnabled() async {
    if (_applyingAccountAdPreferences || _signedInAdPreferencesActive) return;
    await _prefs?.setBool(
      _interstitialAdsEnabledKey,
      interstitialAdsEnabled.value,
    );
  }

  static Future<void> _persistBannerAdsEnabled() async {
    if (_applyingAccountAdPreferences || _signedInAdPreferencesActive) return;
    await _prefs?.setBool(_bannerAdsEnabledKey, bannerAdsEnabled.value);
  }

  static Future<void> _persistAdDisableRewardUnlocked() async {
    await _prefs?.setBool(
      _adDisableRewardUnlockKey,
      adDisableRewardUnlocked.value,
    );
  }

  static Future<void> _persistShowMatureContent() async {
    await _prefs?.setBool(_showMatureContentKey, showMatureContent.value);
  }

  static Future<void> _persistMatureContentChoiceSeen() async {
    await _prefs?.setBool(
      _matureContentChoiceSeenKey,
      matureContentChoiceSeen.value,
    );
  }

  static Future<void> _persistNativeProvider() async {
    await _prefs?.setString(_nativeProviderKey, selectedNativeProviderId);
  }

  static Future<void> _persistLibrary() async {
    final suppressAccountSyncUpload = _accountLibrarySyncApplyingRemote;
    final encoded = jsonEncode(
      library.value.values.map((item) => item.toJson()).toList(),
    );
    await _prefs?.setString(_libraryKey, encoded);
    if (!suppressAccountSyncUpload) {
      _scheduleAccountLibraryUpload();
    }
  }

  static Future<void> _persistLibraryLists() async {
    final suppressAccountSyncUpload = _accountLibrarySyncApplyingRemote;
    final encoded = jsonEncode(
      libraryLists.value.map((list) => list.toJson()).toList(),
    );
    await _prefs?.setString(_libraryListsKey, encoded);
    if (!suppressAccountSyncUpload) {
      _scheduleAccountLibraryUpload();
    }
  }

  static Future<void> _persistSearchHistory() async {
    await _prefs?.setStringList(_searchHistoryKey, searchHistory.value);
  }

  static Future<void> _persistBrowseFilterPreference() async {
    await _prefs?.setString(
      _browseFilterPreferenceKey,
      jsonEncode(browseFilterPreference.value.toJson()),
    );
  }

  static Future<void> _persistContinueWatching() async {
    final suppressAccountSyncUpload = _accountLibrarySyncApplyingRemote;
    final entries = displayableContinueEntries(continueWatching.value.values)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _prefs?.setString(
      _continueWatchingKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    if (!suppressAccountSyncUpload) {
      _scheduleAccountLibraryUpload();
    }
  }

  static Future<void> _persistCompletedWatching() async {
    final suppressAccountSyncUpload = _accountLibrarySyncApplyingRemote;
    final entries = completedWatching.value.values.toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    await _prefs?.setString(
      _completedWatchingKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    if (!suppressAccountSyncUpload) {
      _scheduleAccountLibraryUpload();
    }
  }

  static Future<void> _persistVerifiedPlaybackSources() async {
    await _prefs?.setString(
      _verifiedPlaybackSourcesKey,
      jsonEncode(
        verifiedPlaybackSources.value.map(
          (key, entries) => MapEntry<String, dynamic>(
            key,
            entries.map((entry) => entry.toJson()).toList(),
          ),
        ),
      ),
    );
  }

  static void recordAddonRouteAttemptEvidence(Map<String, Object?> evidence) {
    final safe = _safeAddonRouteAttemptEvidence(evidence);
    if (safe == null) return;
    final next = <Map<String, Object?>>[
      safe,
      ...addonRouteAttemptHistory.value,
    ].take(addonRouteAttemptHistoryLimit).toList(growable: false);
    addonRouteAttemptHistory.value = next;
  }

  static String exportAddonRouteAttemptHistory() {
    final entries = addonRouteAttemptHistory.value
        .map(_safeAddonRouteAttemptEvidence)
        .whereType<Map<String, Object?>>()
        .take(addonRouteAttemptHistoryLimit)
        .toList(growable: false);
    final summary = _addonRouteAttemptHistorySummary(entries);
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'juicr.addon.route_attempt_history.v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'retention': <String, Object>{
        'limit': addonRouteAttemptHistoryLimit,
        'policy': 'bounded_latest_only',
      },
      'redaction': <String, Object>{
        'stored': <String>[
          'mediaType',
          'status',
          'statusLabel',
          'statusHint',
          'counts',
          'checkedAtUtc',
        ],
        'excluded': <String>[
          'manifestUrls',
          'streamUrls',
          'externalUrls',
          'infoHashes',
          'trackers',
          'headers',
          'tokens',
          'accountDetails',
          'privateAddonConfiguration',
        ],
      },
      'summary': summary,
      'entries': entries,
    });
  }

  static String exportCompactAddonRouteAttemptHistory() {
    final entries = addonRouteAttemptHistory.value
        .map(_safeAddonRouteAttemptEvidence)
        .whereType<Map<String, Object?>>()
        .take(addonRouteAttemptHistoryLimit)
        .toList(growable: false);
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'juicr.addon.route_attempt_history.v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'retention': <String, Object>{
        'limit': addonRouteAttemptHistoryLimit,
        'policy': 'compact_latest_only_for_upload',
      },
      'redaction': <String, Object>{
        'stored': <String>[
          'mediaType',
          'status',
          'statusLabel',
          'statusHint',
          'counts',
          'checkedAtUtc',
        ],
        'excluded': <String>[
          'manifestUrls',
          'streamUrls',
          'externalUrls',
          'infoHashes',
          'trackers',
          'headers',
          'tokens',
          'accountDetails',
          'privateAddonConfiguration',
        ],
      },
      'summary': _addonRouteAttemptHistorySummary(entries),
      'latestEntries': entries.take(5).toList(growable: false),
      'omittedEntryCount': entries.length > 5 ? entries.length - 5 : 0,
    });
  }

  static Map<String, Object> _addonRouteAttemptHistorySummary(
    List<Map<String, Object?>> entries,
  ) {
    final byStatus = <String, int>{};
    final byMediaType = <String, int>{};
    String? latestCheckedAtUtc;

    for (final entry in entries) {
      final status = entry['status']?.toString().trim();
      if (status != null && status.isNotEmpty) {
        byStatus[status] = (byStatus[status] ?? 0) + 1;
      }

      final mediaType = entry['mediaType']?.toString().trim();
      if (mediaType != null && mediaType.isNotEmpty) {
        byMediaType[mediaType] = (byMediaType[mediaType] ?? 0) + 1;
      }

      final checkedAtUtc = entry['checkedAtUtc']?.toString().trim();
      if (checkedAtUtc != null && checkedAtUtc.isNotEmpty) {
        if (latestCheckedAtUtc == null ||
            checkedAtUtc.compareTo(latestCheckedAtUtc) > 0) {
          latestCheckedAtUtc = checkedAtUtc;
        }
      }
    }

    return <String, Object>{
      'total': entries.length,
      'byStatus': byStatus,
      'byMediaType': byMediaType,
      if (latestCheckedAtUtc != null) 'latestCheckedAtUtc': latestCheckedAtUtc,
    };
  }

  static String exportP2pBridgeReadiness() {
    final behavior = playerBehaviorSettings.value;
    final bridge = P2pLocalStreamBridge.instance;
    final effective = p2pRuntimePlaybackEffective;
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'juicr.p2p.bridge_readiness.v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'bridge': <String, Object>{
        'available': bridge.isAvailable,
        'status': bridge.isAvailable ? 'available' : 'locked',
        'reason': bridge.isAvailable
            ? 'Advanced P2P playback support is installed.'
            : bridge.unavailableReason,
      },
      'consent': <String, Object?>{
        'accepted': behavior.p2pPlaybackConsentAccepted,
        'version': behavior.p2pPlaybackConsentVersion,
        'requiredVersion': kP2pHeavyConsentVersion,
        'acceptedAt': behavior.p2pPlaybackConsentAcceptedAt,
      },
      'settings': <String, Object>{
        'requestedEnabled': behavior.p2pPlaybackEnabled,
        'effectiveEnabled': effective,
        'effectiveMode': effective ? 'controlled_beta' : 'locked',
      },
      'approvalChecklist': P2pBridgeApprovalChecklist.lockedBaseline().toJson(),
      'runtimeCapabilities': P2pRuntimeCapabilityState.lockedBaseline(
        localBridgeAvailable: bridge.isAvailable,
      ).map((capability) => capability.toJson()).toList(growable: false),
      'brakes': <String>[
        if (!bridge.isAvailable) 'noPeerFetchingInThisBuild',
        if (!bridge.isAvailable) 'noLocalStreamRuntimeInThisBuild',
        if (!bridge.isAvailable) 'noTorrentDependencyInThisBuild',
        'noP2pSensitivePermissionInThisBuild',
        'heavyConsentRequired',
        'directAndDebridFirst',
      ],
      'redaction': <String, Object>{
        'excluded': <String>[
          'manifestUrls',
          'streamUrls',
          'externalUrls',
          'magnetLinks',
          'infoHashes',
          'trackerAddresses',
          'peerAddresses',
          'headers',
          'tokens',
          'accountDetails',
          'privateAddonConfiguration',
        ],
      },
    });
  }

  static bool get p2pRuntimePlaybackEffective {
    final behavior = playerBehaviorSettings.value;
    final bridge = P2pLocalStreamBridge.instance;
    return bridge.isAvailable &&
        behavior.p2pPlaybackEnabled &&
        behavior.p2pPlaybackConsentAccepted;
  }

  static bool playbackSourceClassAllowedForNative(
    PlaybackSourceClass sourceClass,
  ) {
    return switch (sourceClass) {
      PlaybackSourceClass.direct || PlaybackSourceClass.debrid => true,
      PlaybackSourceClass.p2p => p2pRuntimePlaybackEffective,
      PlaybackSourceClass.external || PlaybackSourceClass.unsupported => false,
    };
  }

  static String exportP2pRuntimeDecisionPacket() {
    final checklist = P2pBridgeApprovalChecklist.lockedBaseline();
    final bridge = P2pLocalStreamBridge.instance;
    final effective = p2pRuntimePlaybackEffective;
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'juicr.p2p.runtime_decision_packet.v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'packetEffect': effective ? 'controlled_beta' : 'review_only',
      'runtimeApproval': effective ? 'app_consent_beta_granted' : 'not_granted',
      'bridgePathSelection': effective
          ? 'local_http_bridge_beta'
          : 'not_granted',
      'selectedBridgePath': effective ? 'local_http_bridge' : 'not_selected',
      'plainEnglishOutcome': effective
          ? 'Direct and account-backed streams stay first. Advanced P2P can be tested from recognized sources on this Android build after heavy consent.'
          : 'Direct and account-backed streams can play through the existing safe path. Advanced P2P playback stays locked until the controlled test path is enabled.',
      'candidates': <Map<String, Object>>[
        <String, Object>{
          'id': 'directDebridFirst',
          'status': 'effective_safe_baseline',
          'selected': true,
          'runtimePath': false,
          'summary': 'Keep direct and account-backed playback first when available.',
        },
        <String, Object>{
          'id': 'externalHandoff',
          'status': 'not_selected',
          'selected': false,
          'runtimePath': true,
          'nextGate': 'external handoff proof',
        },
        <String, Object>{
          'id': 'localHttpBridge',
          'status': effective
              ? 'controlled_beta_effective'
              : bridge.isAvailable
              ? 'beta_scaffold_selected'
              : 'not_selected',
          'selected': bridge.isAvailable,
          'runtimePath': true,
          'nextGate': bridge.isAvailable
              ? effective
                    ? 'real device playback proof'
                    : 'advanced consent and enablement'
              : 'local bridge architecture proof',
        },
        <String, Object>{
          'id': 'nativeP2pEngineCandidate',
          'status': 'not_selected',
          'selected': false,
          'runtimePath': true,
          'nextGate': 'native dependency and permission proof',
        },
      ],
      'proofGates': checklist.toJson(),
      'runtimeCapabilities': P2pRuntimeCapabilityState.lockedBaseline(
        localBridgeAvailable: bridge.isAvailable,
      ).map((capability) => capability.toJson()).toList(growable: false),
      'approvalCheckpoint': <String, Object>{
        'singleHighRiskApprovalRequired': !effective,
        'nextMissingGate': checklist.nextMissingRequirement?.id ?? 'none',
        'allowedApprovalTargets': <String>[
          'approveExternalHandoff',
          'approveLocalHttpBridge',
          'approveNativeP2pEngineCandidate',
          'approveDependencyChange',
          'approvePermissionChange',
          'approvePeerRuntime',
          'approveLocalStreamBridge',
          'approveReleaseBehavior',
          'approveLegalPrivacyCopy',
          'approvePlayableNoDebridRuntime',
        ],
      },
      'stopRules': <String>[
        if (!effective) 'doNotSelectBridge',
        'doNotInstallDependency',
        'doNotChangePermissions',
        if (!effective) 'doNotOpenSockets',
        if (!effective) 'doNotServeLocalStreams',
        'doNotPromoteOutOfBeta',
        'doNotExposeSourceIdentity',
        'doNotMoveMetrics',
        if (!effective) 'doNotTreatNoDebridAsPlayable',
      ],
      'redaction': <String, Object>{
        'excluded': <String>[
          'manifestUrls',
          'streamUrls',
          'externalUrls',
          'localRuntimeEndpoints',
          'magnetLinks',
          'infoHashes',
          'trackerAddresses',
          'peerAddresses',
          'headers',
          'tokens',
          'accountDetails',
          'privateAddonConfiguration',
        ],
      },
    });
  }

  static String exportP2pRuntimeApprovalPacket() {
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'juicr.p2p.runtime_approval_packet.v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'approvalPacketState': 'approved_for_locked_scaffold',
      'approvalSource': 'user_explicit_thread_approval',
      'approvalRecordedAt': '2026-05-07',
      'selectedBridgePath': 'locked_local_bridge_scaffold',
      'runtimeEffect': 'disabled_until_lower_layers_pass',
      'directDebridFirst': true,
      'dependencyApproval': 'not_granted',
      'permissionApproval': 'not_granted',
      'peerRuntimeApproval': 'not_granted',
      'localStreamServingApproval': 'not_granted',
      'socketBehavior': 'not_allowed',
      'trackerContact': 'not_allowed',
      'dhtBehavior': 'not_allowed',
      'torrentMetadataParsing': 'not_allowed',
      'foregroundServiceApproval': 'not_granted',
      'storageBudgetApproval': 'not_granted',
      'publicReleaseEnablement': 'not_allowed',
      'legalPrivacyApproval': 'not_granted',
      'sourceIdentifyingDiagnostics': 'not_allowed',
      'metricsApproval': 'not_granted',
      'playableNoDebridRuntime': 'not_granted',
      'nextImplementationBatch': 'fail_closed_scaffold_only',
      'redaction': <String, Object>{
        'excluded': <String>[
          'manifestUrls',
          'streamUrls',
          'externalUrls',
          'localRuntimeEndpoints',
          'magnetLinks',
          'infoHashes',
          'torrentNames',
          'trackerAddresses',
          'peerAddresses',
          'dhtDetails',
          'headers',
          'tokens',
          'accountDetails',
          'privateAddonConfiguration',
          'rawRuntimePayloads',
          'sourceProviderIdentity',
        ],
      },
    });
  }

  static String exportP2pReadyToTestGateAttestationMatrix() {
    const gateRows = <Map<String, String>>[
      <String, String>{
        'field': 'dependencyReview',
        'currentState': 'not_passed',
        'requiredProofSource': 'dependency_intake_plus_approved_decision',
      },
      <String, String>{
        'field': 'permissionPolicyReview',
        'currentState': 'not_passed',
        'requiredProofSource': 'permission_intake_plus_approved_decision',
      },
      <String, String>{
        'field': 'privacyLegalReview',
        'currentState': 'not_passed',
        'requiredProofSource': 'privacy_legal_intake_plus_approved_decision',
      },
      <String, String>{
        'field': 'resourceLimits',
        'currentState': 'not_passed',
        'requiredProofSource': 'resource_intake_plus_approved_decision',
      },
      <String, String>{
        'field': 'sessionLifecycleCleanup',
        'currentState': 'not_passed',
        'requiredProofSource':
            'session_lifecycle_intake_plus_approved_decision',
      },
      <String, String>{
        'field': 'killSwitchRollback',
        'currentState': 'not_passed',
        'requiredProofSource':
            'rollback_kill_switch_intake_plus_approved_decision',
      },
      <String, String>{
        'field': 'releaseExclusion',
        'currentState': 'not_passed',
        'requiredProofSource':
            'release_exclusion_intake_plus_approved_decision',
      },
      <String, String>{
        'field': 'workerCommandCenterAppEffectiveGates',
        'currentState': 'not_passed',
        'requiredProofSource':
            'worker_command_center_app_effective_gate_decision',
      },
      <String, String>{
        'field': 'diagnosticsRedaction',
        'currentState': 'not_passed',
        'requiredProofSource': 'ready_export_freeze_plus_redaction_decision',
      },
      <String, String>{
        'field': 'controlledRealDevicePreconditions',
        'currentState': 'not_passed',
        'requiredProofSource':
            'controlled_test_intake_plus_precondition_packet',
      },
      <String, String>{
        'field': 'readyToTestDiagnosticPacket',
        'currentState': 'not_available',
        'requiredProofSource': 'all_gate_rows_attested_current',
      },
    ];

    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'juicr.p2p.ready_to_test_gate_attestation_matrix.v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'readyToTestGateAttestationMatrix': 'fail_closed_only',
      'readyToTestState': 'not_ready',
      'p2pRuntimeBridgeScore': '99/100',
      'selectedBridgePath': 'locked_local_bridge_scaffold',
      'allGateAttestations': 'current_not_passed',
      'allGateProofSources': 'required_before_ready',
      'partialGatePass': 'not_allowed',
      'staleGatePass': 'not_allowed',
      'workerPolicyGatePass': 'not_sufficient',
      'commandCenterGatePass': 'not_sufficient',
      'copiedDiagnosticGatePass': 'not_sufficient',
      'sourceIdentifyingDiagnostics': 'not_allowed',
      'runtimeMetrics': 'not_granted',
      'publicReleaseEnablement': 'not_allowed',
      'playableNoDebridRuntime': 'not_granted',
      'scoreMovement': 'none',
      'currentness': <String, Object>{
        'scope': 'copied_diagnostic_only',
        'retainedPacketAuthority': 'not_allowed',
        'staleGatePass': 'not_allowed',
        'importRestoreGatePass': 'not_allowed',
        'replayGatePass': 'not_allowed',
        'currentLowerLayerProofRequired': true,
        'readyPacketMustBeGeneratedFromCurrentGateRows': true,
      },
      'gateRows': gateRows,
      'redaction': <String, Object>{
        'shape': 'fixed_strings_booleans_and_counts_only',
        'excluded': <String>[
          'manifestUrls',
          'streamUrls',
          'externalUrls',
          'localRuntimeEndpoints',
          'magnetLinks',
          'infoHashes',
          'torrentNames',
          'trackerAddresses',
          'peerAddresses',
          'headers',
          'tokens',
          'accountDetails',
          'privateAddonConfiguration',
          'rawRuntimePayloads',
          'sourceProviderIdentity',
        ],
      },
    });
  }

  static Future<void> _persistAddonRouteAttemptHistory() async {
    await _prefs?.setString(
      _addonRouteAttemptHistoryKey,
      jsonEncode(addonRouteAttemptHistory.value),
    );
  }

  static Future<void> _persistUserAddons() async {
    await _prefs?.setString(
      _userAddonsKey,
      jsonEncode(userAddons.value.map((addon) => addon.toJson()).toList()),
    );
  }

  static Future<void> _persistP2pIndexerConnectors() async {
    await _prefs?.setString(
      _p2pIndexerConnectorsKey,
      jsonEncode(
        p2pIndexerConnectors.value
            .map((connector) => connector.toJson())
            .toList(),
      ),
    );
  }

  static Future<void> _persistP2pIndexerConnectorsEnabled() async {
    await _prefs?.setBool(
      _p2pIndexerConnectorsEnabledKey,
      p2pIndexerConnectorsEnabled.value,
    );
  }

  static Future<void> _persistP2pIndexerConnectorsAcknowledged() async {
    await _prefs?.setBool(
      _p2pIndexerConnectorsAcknowledgedKey,
      p2pIndexerConnectorsAcknowledged.value,
    );
  }

  static Map<String, Object> p2pIndexerConnectorsDiagnosticSummary() {
    final connectors = p2pIndexerConnectors.value;
    final byType = <String, int>{'prowlarr': 0, 'jackett': 0};
    final byStatus = <String, int>{};
    for (final connector in connectors) {
      byType[connector.type.wireName] =
          (byType[connector.type.wireName] ?? 0) + 1;
      byStatus[connector.lastStatusBucket] =
          (byStatus[connector.lastStatusBucket] ?? 0) + 1;
    }
    return <String, Object>{
      'schema': 'juicr.p2p.indexer_connectors.v1',
      'configured': connectors.length,
      'enabled': connectors
          .where((connector) => connector.enabled && connector.isConfigured)
          .length,
      'switchEnabled': p2pIndexerConnectorsEnabled.value,
      'acknowledged': p2pIndexerConnectorsAcknowledged.value,
      'types': byType,
      'statuses': byStatus,
      'redaction': <String>[
        'baseUrl',
        'apiKey',
        'rawQueryUrls',
        'magnetLinks',
        'infoHashes',
        'trackerAddresses',
        'peerAddresses',
        'headers',
        'accountDetails',
        'localEndpoints',
        'rawPayloads',
      ],
    };
  }

  static Map<String, Object> p2pSourcePrioritiesDiagnosticSummary() {
    final behavior = playerBehaviorSettings.value;
    return <String, Object>{
      'schema': 'juicr.p2p.source_priorities.v1',
      'enabled': behavior.p2pSourcePrioritiesEnabled,
      'mode': behavior.p2pPriorityMode,
      'resultsPerQualityBucket': behavior.p2pResultsPerQuality <= 1
          ? 'one'
          : behavior.p2pResultsPerQuality <= 3
          ? 'two_to_three'
          : 'four_to_five',
      'preferredAudioLanguageMode': behavior.p2pPreferredAudioLanguageMode,
      'avoidRiskyFormats': behavior.p2pAvoidRiskyFormats,
      'sizeLimitBucket': behavior.p2pSizeLimitMb <= 0
          ? 'off'
          : behavior.p2pSizeLimitMb <= 2048
          ? 'up_to_2gb'
          : behavior.p2pSizeLimitMb <= 4096
          ? 'up_to_4gb'
          : 'over_4gb',
      'redaction': <String>[
        'streamUrls',
        'externalUrls',
        'magnetLinks',
        'infoHashes',
        'trackerAddresses',
        'peerAddresses',
        'headers',
        'tokens',
        'accountDetails',
        'privateAddonConfiguration',
      ],
    };
  }

  static Future<void> _persistPersonalServerConnections() async {
    await _prefs?.setString(
      _personalServerConnectionsKey,
      jsonEncode(
        personalServerConnections.value
            .map((connection) => connection.toJson())
            .toList(),
      ),
    );
  }

  static Future<void> _persistLocalCatalogs() async {
    await _prefs?.setString(
      _localCatalogsKey,
      jsonEncode(
        localCatalogs.value.map((catalog) => catalog.toJson()).toList(),
      ),
    );
  }

  static Future<void> _persistLocalCatalogItems() async {
    await _prefs?.setString(
      _localCatalogItemsKey,
      jsonEncode(localCatalogItems.value.map((item) => item.toJson()).toList()),
    );
  }

  static Future<void> _persistLocalPickedAssetRefs() async {
    await _prefs?.setString(
      _localPickedAssetRefsKey,
      jsonEncode(
        localPickedAssetRefs.value.map((ref) => ref.toJson()).toList(),
      ),
    );
  }

  static Future<void> _persistDefaultCatalogEnabled() async {
    await _prefs?.setBool(
      _defaultCatalogEnabledKey,
      defaultCatalogEnabled.value,
    );
  }

  static Future<void> _persistDefaultProvidersEnabled() async {
    await _prefs?.setBool(
      _defaultProvidersEnabledKey,
      defaultProvidersEnabled.value,
    );
  }

  static Future<void> _persistDefaultSubtitlesEnabled() async {
    await _prefs?.setBool(
      _defaultSubtitlesEnabledKey,
      defaultSubtitlesEnabled.value,
    );
  }

  static Future<void> _persistDefaultTrailersEnabled() async {
    await _prefs?.setBool(
      _defaultTrailersEnabledKey,
      defaultTrailersEnabled.value,
    );
  }

  static Future<void> _persistTvSourcesEnabled() async {
    await _prefs?.setBool(_tvSourcesEnabledKey, tvSourcesEnabled.value);
  }

  static Future<void> _persistPublicIptvEnabled() async {
    await _prefs?.setBool(_publicIptvEnabledKey, publicIptvEnabled.value);
  }

  static Future<void> _persistDefaultSourceDisclaimerAccepted() async {
    await _prefs?.setBool(
      _defaultSourceDisclaimerAcceptedKey,
      defaultSourceDisclaimerAccepted.value,
    );
  }

  static Future<void> _persistAddonDisclaimerAccepted() async {
    await _prefs?.setBool(
      _addonDisclaimerAcceptedKey,
      addonDisclaimerAccepted.value,
    );
  }

  static Future<void> _persistExperimentalDisclaimerAccepted() async {
    await _prefs?.setBool(
      _experimentalDisclaimerAcceptedKey,
      experimentalDisclaimerAccepted.value,
    );
  }

  static void _restoreProviderHealth() {
    final raw = _prefs?.getString(_providerHealthKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final version = _intOrNull(decoded['version']) ?? 0;
      if (version != _providerHealthSchemaVersion) {
        nativeProviderHealth.value = const <String, NativeProviderHealth>{};
        unawaited(_persistProviderHealth());
        return;
      }
      nativeProviderHealth.value = _healthMapFromJson(decoded['native']);
    } catch (_) {}
  }

  static Future<void> _persistProviderHealth() async {
    await _prefs?.setString(
      _providerHealthKey,
      jsonEncode({
        'version': _providerHealthSchemaVersion,
        'native': _healthMapToJson(nativeProviderHealth.value),
      }),
    );
  }

  static void setNativePlaybackOverridesEnabled(bool enabled) {
    if (nativePlaybackOverridesEnabled.value == enabled) return;
    nativePlaybackOverridesEnabled.value = enabled;
  }

  static void updateNativePlaybackOverrides(NativePlaybackOverrides value) {
    nativePlaybackOverrides.value = value;
  }

  static void updateNativePlayerVolume(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if ((nativePlayerVolume.value - clamped).abs() < 0.001) return;
    nativePlayerVolume.value = clamped;
    unawaited(_prefs?.setDouble(_nativePlayerVolumeKey, clamped));
  }

  static void updateNativePlayerBrightness(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if ((nativePlayerBrightness.value - clamped).abs() < 0.001) return;
    nativePlayerBrightness.value = clamped;
    unawaited(_prefs?.setDouble(_nativePlayerBrightnessKey, clamped));
  }

  static void updatePlayerBehaviorSettings(PlayerBehaviorSettings value) {
    playerBehaviorSettings.value = value;
  }

  static void updateBatteryDataSettings(BatteryDataSettings value) {
    batteryDataSettings.value = value;
  }

  static Future<void> _persistNativePlaybackOverridesEnabled() async {
    await _prefs?.setBool(
      _nativePlaybackOverridesEnabledKey,
      nativePlaybackOverridesEnabled.value,
    );
  }

  static Future<void> _persistNativePlaybackOverrides() async {
    await _prefs?.setString(
      _nativePlaybackOverridesKey,
      jsonEncode(nativePlaybackOverrides.value.toJson()),
    );
  }

  static Future<void> _persistPlayerBehaviorSettings() async {
    await _prefs?.setString(
      _playerBehaviorSettingsKey,
      jsonEncode(playerBehaviorSettings.value.toJson()),
    );
  }

  static Future<void> _persistBatteryDataSettings() async {
    await _prefs?.setString(
      _batteryDataSettingsKey,
      jsonEncode(batteryDataSettings.value.toJson()),
    );
  }
}

Map<String, Object?>? _safeAddonRouteAttemptEvidence(dynamic value) {
  if (value is! Map) return null;
  final mediaType = value['mediaType']?.toString().trim();
  final status = value['status']?.toString().trim();
  final statusLabel = value['statusLabel']?.toString().trim();
  final statusHint = value['statusHint']?.toString().trim();
  final checkedAtUtc = value['checkedAtUtc']?.toString().trim();
  final counts = value['counts'];
  if (mediaType == null ||
      mediaType.isEmpty ||
      status == null ||
      status.isEmpty ||
      checkedAtUtc == null ||
      checkedAtUtc.isEmpty ||
      counts is! Map) {
    return null;
  }
  return <String, Object?>{
    'mediaType': mediaType,
    'status': status,
    if (statusLabel != null && statusLabel.isNotEmpty)
      'statusLabel': statusLabel,
    if (statusHint != null && statusHint.isNotEmpty) 'statusHint': statusHint,
    'counts': <String, int>{
      'direct': _intOrNull(counts['direct']) ?? 0,
      'externalOnly': _intOrNull(counts['externalOnly']) ?? 0,
      'torrentLocked': _intOrNull(counts['torrentLocked']) ?? 0,
      'accountRequired': _intOrNull(counts['accountRequired']) ?? 0,
      'unsupported': _intOrNull(counts['unsupported']) ?? 0,
      'empty': _intOrNull(counts['empty']) ?? 0,
    },
    'checkedAtUtc': checkedAtUtc,
  };
}

Map<String, NativeProviderHealth> _healthMapFromJson(dynamic value) {
  if (value is! Map) return const <String, NativeProviderHealth>{};
  final result = <String, NativeProviderHealth>{};
  for (final entry in value.entries) {
    final raw = entry.value;
    if (raw is! Map) continue;
    final statusName = raw['status']?.toString();
    final status = NativeProviderHealthStatus.values.firstWhere(
      (item) => item.name == statusName,
      orElse: () => NativeProviderHealthStatus.untested,
    );
    result[entry.key.toString()] = NativeProviderHealth(
      status: status,
      updatedAt:
          DateTime.tryParse(raw['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceCount: _intOrNull(raw['sourceCount']),
      responseMillis: _intOrNull(raw['responseMillis']),
    );
  }
  return result;
}

List<VerifiedPlaybackSource> _verifiedSourceListFromJson(dynamic value) {
  final entries = <VerifiedPlaybackSource>[];
  if (value is List) {
    for (final item in value.whereType<Map<String, dynamic>>()) {
      final entry = VerifiedPlaybackSource.fromJson(item);
      if (entry.source.url.isNotEmpty) entries.add(entry);
    }
  } else if (value is Map<String, dynamic>) {
    final entry = VerifiedPlaybackSource.fromJson(value);
    if (entry.source.url.isNotEmpty) entries.add(entry);
  }
  entries.sort(_compareVerifiedPlaybackSources);
  return List<VerifiedPlaybackSource>.unmodifiable(entries.take(3));
}

int _compareVerifiedPlaybackSources(
  VerifiedPlaybackSource left,
  VerifiedPlaybackSource right,
) {
  final confidenceDiff = right.confidence.compareTo(left.confidence);
  if (confidenceDiff != 0) return confidenceDiff;
  final successDiff = right.successCount.compareTo(left.successCount);
  if (successDiff != 0) return successDiff;
  return right.cachedAt.compareTo(left.cachedAt);
}

int _verifiedSourceFailurePenalty(String reason) {
  final normalized = reason.toLowerCase();
  if (normalized.contains('403') ||
      normalized.contains('404') ||
      normalized.contains('expired') ||
      normalized.contains('descriptor_missing') ||
      normalized.contains('unreadable')) {
    return 100;
  }
  if (normalized.contains('black_video') ||
      normalized.contains('runtime') ||
      normalized.contains('open_failed')) {
    return 45;
  }
  return 28;
}

bool _verifiedSourceIsHardExpired(String reason) {
  final normalized = reason.toLowerCase();
  return normalized.contains('403') ||
      normalized.contains('404') ||
      normalized.contains('expired') ||
      normalized.contains('descriptor_missing') ||
      normalized.contains('unreadable');
}

Map<String, Map<String, Object>> _healthMapToJson(
  Map<String, NativeProviderHealth> value,
) {
  return {
    for (final entry in value.entries)
      entry.key: {
        'status': entry.value.status.name,
        'updatedAt': entry.value.updatedAt.toIso8601String(),
        if (entry.value.sourceCount != null)
          'sourceCount': entry.value.sourceCount!,
        if (entry.value.responseMillis != null)
          'responseMillis': entry.value.responseMillis!,
      },
  };
}

Map<String, double> _scoreMapFromJson(dynamic value) {
  if (value is! Map) return const <String, double>{};
  return {
    for (final entry in value.entries)
      if (_normalizeTasteToken(entry.key.toString()).isNotEmpty)
        _normalizeTasteToken(entry.key.toString()):
            double.tryParse((entry.value ?? '').toString()) ?? 0,
  }..removeWhere((_, score) => score <= 0);
}

Map<String, double> _trimScoreMap(Map<String, double> value, int limit) {
  final entries = value.entries.where((entry) => entry.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {for (final entry in entries.take(limit)) entry.key: entry.value};
}

String _normalizeTasteToken(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.isEmpty) return '';
  return switch (lower) {
    'science fiction' || 'sci fi' => 'sci-fi',
    'tv' => 'series',
    _ => lower,
  };
}

int? _intOrNull(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

String _safeHttpUrlOrEmpty(dynamic value) {
  final trimmed = value?.toString().trim() ?? '';
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) return '';
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return '';
  return trimmed;
}

String _safePlaybackEngineOrAuto(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  return switch (normalized) {
    'exoplayer' => 'exoplayer',
    'libvlc' => 'libvlc',
    _ => 'auto',
  };
}

class ContinueWatchingEntry {
  const ContinueWatchingEntry({
    required this.key,
    required this.item,
    required this.title,
    required this.watchedSeconds,
    this.credibleWatchedSeconds = 0,
    required this.durationSeconds,
    required this.progress,
    required this.updatedAt,
    this.subtitle,
    this.nativePreferences,
  });

  final String key;
  final CatalogItem item;
  final String title;
  final String? subtitle;
  final int watchedSeconds;
  final int credibleWatchedSeconds;
  final int durationSeconds;
  final double progress;
  final DateTime updatedAt;
  final NativePlayerPreferences? nativePreferences;

  int get remainingSeconds {
    return (durationSeconds - watchedSeconds).clamp(0, durationSeconds).toInt();
  }

  String get remainingLabel {
    if (watchedSeconds > 0 &&
        (progress >= 0.92 || remainingSeconds <= 3 * 60)) {
      return 'Almost done';
    }
    final minutes = (remainingSeconds / 60).ceil();
    if (minutes <= 1) return 'Less than 1 min left';
    return '$minutes min left';
  }

  factory ContinueWatchingEntry.fromJson(Map<String, dynamic> json) {
    final watchedSeconds =
        int.tryParse((json['watchedSeconds'] ?? '').toString()) ?? 0;
    final credibleWatchedSeconds =
        int.tryParse((json['credibleWatchedSeconds'] ?? '').toString()) ?? 0;
    final parsedDuration =
        int.tryParse((json['durationSeconds'] ?? '').toString()) ?? 45 * 60;
    final durationSeconds = parsedDuration <= 0 ? 45 * 60 : parsedDuration;
    final rawProgress = double.tryParse((json['progress'] ?? '').toString());
    return ContinueWatchingEntry(
      key: (json['key'] ?? '').toString(),
      item: CatalogItem.fromJson(
        (json['item'] is Map<String, dynamic>)
            ? json['item'] as Map<String, dynamic>
            : const {},
      ),
      title: (json['title'] ?? 'Continue watching').toString(),
      subtitle: json['subtitle']?.toString(),
      watchedSeconds: watchedSeconds,
      credibleWatchedSeconds: credibleWatchedSeconds,
      durationSeconds: durationSeconds,
      progress:
          rawProgress ??
          (watchedSeconds / durationSeconds).clamp(0.02, 0.98).toDouble(),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.now(),
      nativePreferences: json['nativePreferences'] is Map<String, dynamic>
          ? NativePlayerPreferences.fromJson(
              json['nativePreferences'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  ContinueWatchingEntry copyWith({
    NativePlayerPreferences? nativePreferences,
    bool clearNativePreferences = false,
  }) {
    return ContinueWatchingEntry(
      key: key,
      item: item,
      title: title,
      subtitle: subtitle,
      watchedSeconds: watchedSeconds,
      credibleWatchedSeconds: credibleWatchedSeconds,
      durationSeconds: durationSeconds,
      progress: progress,
      updatedAt: updatedAt,
      nativePreferences: clearNativePreferences
          ? null
          : nativePreferences ?? this.nativePreferences,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'item': item.toJson(),
      'title': title,
      'subtitle': subtitle,
      'watchedSeconds': watchedSeconds,
      'credibleWatchedSeconds': credibleWatchedSeconds,
      'durationSeconds': durationSeconds,
      'progress': progress,
      'updatedAt': updatedAt.toIso8601String(),
      if (nativePreferences != null)
        'nativePreferences': nativePreferences!.toJson(),
    };
  }
}

class CompletedWatchingEntry {
  const CompletedWatchingEntry({
    required this.key,
    required this.item,
    required this.title,
    required this.watchedSeconds,
    this.credibleWatchedSeconds = 0,
    required this.durationSeconds,
    required this.completedAt,
    this.subtitle,
    this.completionCount = 1,
  });

  final String key;
  final CatalogItem item;
  final String title;
  final String? subtitle;
  final int watchedSeconds;
  final int credibleWatchedSeconds;
  final int durationSeconds;
  final DateTime completedAt;
  final int completionCount;

  factory CompletedWatchingEntry.fromJson(Map<String, dynamic> json) {
    return CompletedWatchingEntry(
      key: (json['key'] ?? '').toString(),
      item: CatalogItem.fromJson(
        (json['item'] is Map<String, dynamic>)
            ? json['item'] as Map<String, dynamic>
            : const {},
      ),
      title: (json['title'] ?? 'Watched').toString(),
      subtitle: json['subtitle']?.toString(),
      watchedSeconds:
          int.tryParse((json['watchedSeconds'] ?? '').toString()) ?? 0,
      credibleWatchedSeconds:
          int.tryParse((json['credibleWatchedSeconds'] ?? '').toString()) ?? 0,
      durationSeconds:
          int.tryParse((json['durationSeconds'] ?? '').toString()) ?? 0,
      completedAt:
          DateTime.tryParse((json['completedAt'] ?? '').toString()) ??
          DateTime.now(),
      completionCount: math.max(
        1,
        int.tryParse((json['completionCount'] ?? '').toString()) ?? 1,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'item': item.toJson(),
      'title': title,
      'subtitle': subtitle,
      'watchedSeconds': watchedSeconds,
      'credibleWatchedSeconds': credibleWatchedSeconds,
      'durationSeconds': durationSeconds,
      'completedAt': completedAt.toIso8601String(),
      'completionCount': completionCount,
    };
  }
}

class LibraryBackupImportResult {
  const LibraryBackupImportResult({
    required this.savedCount,
    required this.continueCount,
    required this.completedCount,
  });

  final int savedCount;
  final int continueCount;
  final int completedCount;

  int get totalCount => savedCount + continueCount + completedCount;
}

class NativePlayerPreferences {
  const NativePlayerPreferences({
    this.quality,
    this.speed = 1,
    this.subtitleId,
    this.subtitleDelaySeconds = 0,
    this.subtitleDelayCustomized = false,
    this.subtitleFontSize = 16,
    this.subtitleBackgroundOpacity = 0.68,
    this.subtitleBackgroundColor = 0xFF000000,
    this.subtitleBackgroundRadius = 999,
    this.subtitleTextColor = 0xFFFFFFFF,
    this.subtitleBottomOffset = 30,
    this.videoFitMode = 'fit',
  });

  final String? quality;
  final double speed;
  final String? subtitleId;
  final double subtitleDelaySeconds;
  final bool subtitleDelayCustomized;
  final double subtitleFontSize;
  final double subtitleBackgroundOpacity;
  final int subtitleBackgroundColor;
  final double subtitleBackgroundRadius;
  final int subtitleTextColor;
  final double subtitleBottomOffset;
  final String videoFitMode;

  factory NativePlayerPreferences.fromJson(Map<String, dynamic> json) {
    return NativePlayerPreferences(
      quality: json['quality']?.toString(),
      speed: _doubleFromJson(json['speed'], fallback: 1),
      subtitleId: json['subtitleId']?.toString(),
      subtitleDelaySeconds: _doubleFromJson(json['subtitleDelaySeconds']),
      subtitleDelayCustomized: json['subtitleDelayCustomized'] == true,
      subtitleFontSize: _doubleFromJson(json['subtitleFontSize'], fallback: 16),
      subtitleBackgroundOpacity: _doubleFromJson(
        json['subtitleBackgroundOpacity'],
        fallback: 0.68,
      ),
      subtitleBackgroundColor:
          int.tryParse((json['subtitleBackgroundColor'] ?? '').toString()) ??
          0xFF000000,
      subtitleBackgroundRadius: _doubleFromJson(
        json['subtitleBackgroundRadius'],
        fallback: 999,
      ),
      subtitleTextColor:
          int.tryParse((json['subtitleTextColor'] ?? '').toString()) ??
          0xFFFFFFFF,
      subtitleBottomOffset: _doubleFromJson(
        json['subtitleBottomOffset'],
        fallback: 30,
      ),
      videoFitMode: (json['videoFitMode'] ?? 'fit').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'quality': quality,
      'speed': speed,
      'subtitleId': subtitleId,
      'subtitleDelaySeconds': subtitleDelaySeconds,
      'subtitleDelayCustomized': subtitleDelayCustomized,
      'subtitleFontSize': subtitleFontSize,
      'subtitleBackgroundOpacity': subtitleBackgroundOpacity,
      'subtitleBackgroundColor': subtitleBackgroundColor,
      'subtitleBackgroundRadius': subtitleBackgroundRadius,
      'subtitleTextColor': subtitleTextColor,
      'subtitleBottomOffset': subtitleBottomOffset,
      'videoFitMode': videoFitMode,
    };
  }
}

class NativePlaybackOverrides {
  const NativePlaybackOverrides({
    this.qualityMode = 'recommended',
    this.advancedQuality = '1080P',
    this.seekStepSeconds = 15,
    this.speed = 1,
    this.subtitleDelaySeconds = 0,
    this.subtitleFontSize = 16,
    this.subtitleBackgroundOpacity = 0.68,
    this.subtitleBackgroundColor = 0xFF000000,
    this.subtitleBackgroundRadius = 999,
    this.subtitleTextColor = 0xFFFFFFFF,
    this.subtitleBottomOffset = 30,
    this.videoFitMode = 'fit',
  });

  final String qualityMode;
  final String advancedQuality;
  final double seekStepSeconds;
  final double speed;
  final double subtitleDelaySeconds;
  final double subtitleFontSize;
  final double subtitleBackgroundOpacity;
  final int subtitleBackgroundColor;
  final double subtitleBackgroundRadius;
  final int subtitleTextColor;
  final double subtitleBottomOffset;
  final String videoFitMode;

  factory NativePlaybackOverrides.fromJson(Map<String, dynamic> json) {
    return NativePlaybackOverrides(
      qualityMode: (json['qualityMode'] ?? 'recommended').toString(),
      advancedQuality: (json['advancedQuality'] ?? '1080P').toString(),
      seekStepSeconds: _doubleFromJson(json['seekStepSeconds'], fallback: 15),
      speed: _doubleFromJson(json['speed'], fallback: 1),
      subtitleDelaySeconds: _doubleFromJson(json['subtitleDelaySeconds']),
      subtitleFontSize: _doubleFromJson(json['subtitleFontSize'], fallback: 16),
      subtitleBackgroundOpacity: _doubleFromJson(
        json['subtitleBackgroundOpacity'],
        fallback: 0.68,
      ),
      subtitleBackgroundColor:
          int.tryParse((json['subtitleBackgroundColor'] ?? '').toString()) ??
          0xFF000000,
      subtitleBackgroundRadius: _doubleFromJson(
        json['subtitleBackgroundRadius'],
        fallback: 999,
      ),
      subtitleTextColor:
          int.tryParse((json['subtitleTextColor'] ?? '').toString()) ??
          0xFFFFFFFF,
      subtitleBottomOffset: _doubleFromJson(
        json['subtitleBottomOffset'],
        fallback: 30,
      ),
      videoFitMode: (json['videoFitMode'] ?? 'fit').toString(),
    );
  }

  NativePlaybackOverrides copyWith({
    String? qualityMode,
    String? advancedQuality,
    double? seekStepSeconds,
    double? speed,
    double? subtitleDelaySeconds,
    double? subtitleFontSize,
    double? subtitleBackgroundOpacity,
    int? subtitleBackgroundColor,
    double? subtitleBackgroundRadius,
    int? subtitleTextColor,
    double? subtitleBottomOffset,
    String? videoFitMode,
  }) {
    return NativePlaybackOverrides(
      qualityMode: qualityMode ?? this.qualityMode,
      advancedQuality: advancedQuality ?? this.advancedQuality,
      seekStepSeconds: seekStepSeconds ?? this.seekStepSeconds,
      speed: speed ?? this.speed,
      subtitleDelaySeconds: subtitleDelaySeconds ?? this.subtitleDelaySeconds,
      subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
      subtitleBackgroundOpacity:
          subtitleBackgroundOpacity ?? this.subtitleBackgroundOpacity,
      subtitleBackgroundColor:
          subtitleBackgroundColor ?? this.subtitleBackgroundColor,
      subtitleBackgroundRadius:
          subtitleBackgroundRadius ?? this.subtitleBackgroundRadius,
      subtitleTextColor: subtitleTextColor ?? this.subtitleTextColor,
      subtitleBottomOffset: subtitleBottomOffset ?? this.subtitleBottomOffset,
      videoFitMode: videoFitMode ?? this.videoFitMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'qualityMode': qualityMode,
      'advancedQuality': advancedQuality,
      'seekStepSeconds': seekStepSeconds,
      'speed': speed,
      'subtitleDelaySeconds': subtitleDelaySeconds,
      'subtitleFontSize': subtitleFontSize,
      'subtitleBackgroundOpacity': subtitleBackgroundOpacity,
      'subtitleBackgroundColor': subtitleBackgroundColor,
      'subtitleBackgroundRadius': subtitleBackgroundRadius,
      'subtitleTextColor': subtitleTextColor,
      'subtitleBottomOffset': subtitleBottomOffset,
      'videoFitMode': videoFitMode,
    };
  }
}

class BatteryDataSettings {
  const BatteryDataSettings({
    this.batterySaverPlayback = false,
    this.wifiOnlyAdvancedP2p = true,
    this.pauseP2pWhenBackgrounded = true,
    this.stopP2pOnLowBattery = true,
    this.lowBatteryThresholdPercent = 20,
  });

  final bool batterySaverPlayback;
  final bool wifiOnlyAdvancedP2p;
  final bool pauseP2pWhenBackgrounded;
  final bool stopP2pOnLowBattery;
  final int lowBatteryThresholdPercent;

  factory BatteryDataSettings.fromJson(Map<String, dynamic> json) {
    return BatteryDataSettings(
      batterySaverPlayback: json['batterySaverPlayback'] == true,
      wifiOnlyAdvancedP2p: json['wifiOnlyAdvancedP2p'] != false,
      pauseP2pWhenBackgrounded: json['pauseP2pWhenBackgrounded'] != false,
      stopP2pOnLowBattery: json['stopP2pOnLowBattery'] != false,
      lowBatteryThresholdPercent:
          _intOrNull(
            json['lowBatteryThresholdPercent'],
          )?.clamp(10, 40).toInt() ??
          20,
    );
  }

  BatteryDataSettings copyWith({
    bool? batterySaverPlayback,
    bool? wifiOnlyAdvancedP2p,
    bool? pauseP2pWhenBackgrounded,
    bool? stopP2pOnLowBattery,
    int? lowBatteryThresholdPercent,
  }) {
    return BatteryDataSettings(
      batterySaverPlayback: batterySaverPlayback ?? this.batterySaverPlayback,
      wifiOnlyAdvancedP2p: wifiOnlyAdvancedP2p ?? this.wifiOnlyAdvancedP2p,
      pauseP2pWhenBackgrounded:
          pauseP2pWhenBackgrounded ?? this.pauseP2pWhenBackgrounded,
      stopP2pOnLowBattery: stopP2pOnLowBattery ?? this.stopP2pOnLowBattery,
      lowBatteryThresholdPercent:
          (lowBatteryThresholdPercent ?? this.lowBatteryThresholdPercent)
              .clamp(10, 40)
              .toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'batterySaverPlayback': batterySaverPlayback,
      'wifiOnlyAdvancedP2p': wifiOnlyAdvancedP2p,
      'pauseP2pWhenBackgrounded': pauseP2pWhenBackgrounded,
      'stopP2pOnLowBattery': stopP2pOnLowBattery,
      'lowBatteryThresholdPercent': lowBatteryThresholdPercent,
    };
  }
}

const int kP2pHeavyConsentVersion = 1;
const String kP2pHeavyConsentPhrase = 'I UNDERSTAND';

class PlayerBehaviorSettings {
  const PlayerBehaviorSettings({
    this.useNativePlayer = true,
    this.playbackEngine = 'auto',
    this.externalPlayerPackage,
    this.externalPlayerActivity,
    this.externalPlayerLabel,
    this.startBehavior = 'ask',
    this.retryStyle = 'balanced',
    this.subtitleAutoSelect = 'default',
    this.subtitleLanguage = 'en',
    this.preferredAudioLanguage = 'auto',
    this.controlsTimeoutSeconds = 3,
    this.preferLastWorkingSource = true,
    this.autoSwitchOnStall = true,
    this.autoplayNextEpisode = false,
    this.pipOnBackground = false,
    this.confirmBeforeLeaving = false,
    this.experimentalControlsEnabled = false,
    this.failureReadSeconds = 5,
    this.libVlcWarmupSeconds = 12,
    this.libVlcReleaseSettleMs = 750,
    this.stallWatchdogSeconds = 4,
    this.libVlcOpenTimeoutSeconds = 8,
    this.libVlcContinuousTsVisualGraceSeconds = 45,
    this.providerWarmupCount = 0,
    this.providerResolveTimeoutSeconds = 16,
    this.zeroClockSkipEnabled = true,
    this.progressFallbackClockEnabled = true,
    this.resumeSeekRetrySeconds = 14,
    this.blackVideoWatchdogSeconds = 8,
    this.autoProviderMemory = 'balanced',
    this.loadingBackdropStyle = 'scan',
    this.exoPlayerOpenTimeoutSeconds = 8,
    this.media3NativeExoEnabled = false,
    this.p2pPlaybackConsentAccepted = false,
    this.p2pPlaybackConsentVersion = 0,
    this.p2pPlaybackConsentAcceptedAt,
    this.p2pPlaybackEnabled = false,
    this.advancedRuntimeControlsExpanded = false,
    this.p2pSourcePrioritiesEnabled = false,
    this.p2pPriorityMode = p2pPriorityModeSmartStart,
    this.p2pResultsPerQuality = 3,
    this.p2pPreferredAudioLanguageMode = p2pAudioLanguageFollowPlayback,
    this.p2pAvoidRiskyFormats = true,
    this.p2pSizeLimitMb = 0,
  });

  final bool useNativePlayer;
  final String playbackEngine;
  final String? externalPlayerPackage;
  final String? externalPlayerActivity;
  final String? externalPlayerLabel;
  final String startBehavior;
  final String retryStyle;
  final String subtitleAutoSelect;
  final String subtitleLanguage;
  final String preferredAudioLanguage;
  final int controlsTimeoutSeconds;
  final bool preferLastWorkingSource;
  final bool autoSwitchOnStall;
  final bool autoplayNextEpisode;
  final bool pipOnBackground;
  final bool confirmBeforeLeaving;
  final bool experimentalControlsEnabled;
  final int failureReadSeconds;
  final int libVlcWarmupSeconds;
  final int libVlcReleaseSettleMs;
  final int stallWatchdogSeconds;
  final int libVlcOpenTimeoutSeconds;
  final int libVlcContinuousTsVisualGraceSeconds;
  final int providerWarmupCount;
  final int providerResolveTimeoutSeconds;
  final bool zeroClockSkipEnabled;
  final bool progressFallbackClockEnabled;
  final int resumeSeekRetrySeconds;
  final int blackVideoWatchdogSeconds;
  final String autoProviderMemory;
  final String loadingBackdropStyle;
  final int exoPlayerOpenTimeoutSeconds;
  final bool media3NativeExoEnabled;
  final bool p2pPlaybackConsentAccepted;
  final int p2pPlaybackConsentVersion;
  final String? p2pPlaybackConsentAcceptedAt;
  final bool p2pPlaybackEnabled;
  final bool advancedRuntimeControlsExpanded;
  final bool p2pSourcePrioritiesEnabled;
  final String p2pPriorityMode;
  final int p2pResultsPerQuality;
  final String p2pPreferredAudioLanguageMode;
  final bool p2pAvoidRiskyFormats;
  final int p2pSizeLimitMb;

  factory PlayerBehaviorSettings.fromJson(Map<String, dynamic> json) {
    final version = _intOrNull(json['version']) ?? 1;
    final rawFailureReadSeconds = _intOrNull(json['failureReadSeconds']);
    final rawPlaybackEngine = _normalizedPlaybackEngine(json['playbackEngine']);
    final playbackEngine = version < 9 && rawPlaybackEngine == 'libvlc'
        ? 'auto'
        : rawPlaybackEngine;
    return PlayerBehaviorSettings(
      useNativePlayer: json['useNativePlayer'] != false,
      playbackEngine: playbackEngine,
      externalPlayerPackage: _nonEmptyString(json['externalPlayerPackage']),
      externalPlayerActivity: _nonEmptyString(json['externalPlayerActivity']),
      externalPlayerLabel: _nonEmptyString(json['externalPlayerLabel']),
      startBehavior: (json['startBehavior'] ?? 'ask').toString(),
      retryStyle: (json['retryStyle'] ?? 'balanced').toString(),
      subtitleAutoSelect: (json['subtitleAutoSelect'] ?? 'default').toString(),
      subtitleLanguage: (json['subtitleLanguage'] ?? 'en').toString(),
      preferredAudioLanguage: (json['preferredAudioLanguage'] ?? 'auto')
          .toString(),
      controlsTimeoutSeconds:
          _intOrNull(json['controlsTimeoutSeconds'])?.clamp(2, 10).toInt() ?? 3,
      preferLastWorkingSource: json['preferLastWorkingSource'] != false,
      autoSwitchOnStall: json['autoSwitchOnStall'] != false,
      autoplayNextEpisode: json['autoplayNextEpisode'] == true,
      pipOnBackground: json['pipOnBackground'] == true,
      confirmBeforeLeaving: json['confirmBeforeLeaving'] == true,
      experimentalControlsEnabled: json['experimentalControlsEnabled'] == true,
      failureReadSeconds:
          (version < 2 && rawFailureReadSeconds == 3
                  ? 5
                  : rawFailureReadSeconds)
              ?.clamp(2, 10)
              .toInt() ??
          5,
      libVlcWarmupSeconds:
          _intOrNull(json['libVlcWarmupSeconds'])?.clamp(4, 24).toInt() ?? 12,
      libVlcReleaseSettleMs:
          _intOrNull(json['libVlcReleaseSettleMs'])?.clamp(0, 2000).toInt() ??
          750,
      stallWatchdogSeconds:
          _intOrNull(json['stallWatchdogSeconds'])?.clamp(2, 10).toInt() ?? 4,
      libVlcOpenTimeoutSeconds:
          _intOrNull(json['libVlcOpenTimeoutSeconds'])?.clamp(4, 18).toInt() ??
          8,
      libVlcContinuousTsVisualGraceSeconds:
          _intOrNull(
            json['libVlcContinuousTsVisualGraceSeconds'],
          )?.clamp(12, 90).toInt() ??
          45,
      providerWarmupCount:
          _intOrNull(json['providerWarmupCount'])?.clamp(0, 3).toInt() ?? 0,
      providerResolveTimeoutSeconds:
          _intOrNull(
            json['providerResolveTimeoutSeconds'],
          )?.clamp(8, 30).toInt() ??
          16,
      zeroClockSkipEnabled: json['zeroClockSkipEnabled'] != false,
      progressFallbackClockEnabled:
          json['progressFallbackClockEnabled'] != false,
      resumeSeekRetrySeconds:
          _intOrNull(json['resumeSeekRetrySeconds'])?.clamp(4, 20).toInt() ??
          14,
      blackVideoWatchdogSeconds:
          _intOrNull(json['blackVideoWatchdogSeconds'])?.clamp(4, 20).toInt() ??
          8,
      autoProviderMemory: _normalizedAutoProviderMemory(
        json['autoProviderMemory'],
      ),
      loadingBackdropStyle: _normalizedLoadingBackdropStyle(
        json['loadingBackdropStyle'],
      ),
      exoPlayerOpenTimeoutSeconds:
          _intOrNull(
            json['exoPlayerOpenTimeoutSeconds'],
          )?.clamp(4, 18).toInt() ??
          8,
      media3NativeExoEnabled:
          version >= 8 && json['media3NativeExoEnabled'] == true,
      p2pPlaybackConsentAccepted: _validP2pHeavyConsent(json),
      p2pPlaybackConsentVersion: _validP2pHeavyConsent(json)
          ? _intOrNull(json['p2pPlaybackConsentVersion']) ??
                kP2pHeavyConsentVersion
          : 0,
      p2pPlaybackConsentAcceptedAt: _validP2pHeavyConsent(json)
          ? _nonEmptyString(json['p2pPlaybackConsentAcceptedAt'])
          : null,
      p2pPlaybackEnabled:
          json['p2pPlaybackEnabled'] == true && _validP2pHeavyConsent(json),
      advancedRuntimeControlsExpanded:
          json['advancedRuntimeControlsExpanded'] == true &&
          _validP2pHeavyConsent(json),
      p2pSourcePrioritiesEnabled:
          json['p2pSourcePrioritiesEnabled'] == true &&
          json['p2pPlaybackEnabled'] == true &&
          _validP2pHeavyConsent(json),
      p2pPriorityMode: _normalizedP2pPriorityMode(json['p2pPriorityMode']),
      p2pResultsPerQuality:
          _intOrNull(json['p2pResultsPerQuality'])?.clamp(1, 5).toInt() ?? 3,
      p2pPreferredAudioLanguageMode: _normalizedP2pPreferredAudioLanguageMode(
        json['p2pPreferredAudioLanguageMode'],
      ),
      p2pAvoidRiskyFormats: json['p2pAvoidRiskyFormats'] != false,
      p2pSizeLimitMb:
          _intOrNull(json['p2pSizeLimitMb'])?.clamp(0, 65536).toInt() ?? 0,
    );
  }

  PlayerBehaviorSettings copyWith({
    bool? useNativePlayer,
    String? playbackEngine,
    String? externalPlayerPackage,
    String? externalPlayerActivity,
    String? externalPlayerLabel,
    String? startBehavior,
    String? retryStyle,
    String? subtitleAutoSelect,
    String? subtitleLanguage,
    String? preferredAudioLanguage,
    int? controlsTimeoutSeconds,
    bool? preferLastWorkingSource,
    bool? autoSwitchOnStall,
    bool? autoplayNextEpisode,
    bool? pipOnBackground,
    bool? confirmBeforeLeaving,
    bool? experimentalControlsEnabled,
    int? failureReadSeconds,
    int? libVlcWarmupSeconds,
    int? libVlcReleaseSettleMs,
    int? stallWatchdogSeconds,
    int? libVlcOpenTimeoutSeconds,
    int? libVlcContinuousTsVisualGraceSeconds,
    int? providerWarmupCount,
    int? providerResolveTimeoutSeconds,
    bool? zeroClockSkipEnabled,
    bool? progressFallbackClockEnabled,
    int? resumeSeekRetrySeconds,
    int? blackVideoWatchdogSeconds,
    String? autoProviderMemory,
    String? loadingBackdropStyle,
    int? exoPlayerOpenTimeoutSeconds,
    bool? media3NativeExoEnabled,
    bool? p2pPlaybackConsentAccepted,
    int? p2pPlaybackConsentVersion,
    String? p2pPlaybackConsentAcceptedAt,
    bool? p2pPlaybackEnabled,
    bool? advancedRuntimeControlsExpanded,
    bool? p2pSourcePrioritiesEnabled,
    String? p2pPriorityMode,
    int? p2pResultsPerQuality,
    String? p2pPreferredAudioLanguageMode,
    bool? p2pAvoidRiskyFormats,
    int? p2pSizeLimitMb,
  }) {
    final nextP2pConsent =
        p2pPlaybackConsentAccepted ?? this.p2pPlaybackConsentAccepted;
    final nextP2pConsentVersion =
        p2pPlaybackConsentVersion ?? this.p2pPlaybackConsentVersion;
    final validP2pConsent =
        nextP2pConsent && nextP2pConsentVersion >= kP2pHeavyConsentVersion;
    final nextP2pEnabled =
        (p2pPlaybackEnabled ?? this.p2pPlaybackEnabled) && validP2pConsent;
    final nextAdvancedRuntimeControlsExpanded =
        (advancedRuntimeControlsExpanded ??
            this.advancedRuntimeControlsExpanded) &&
        validP2pConsent;
    final requestedP2pSourcePrioritiesEnabled =
        p2pSourcePrioritiesEnabled ?? this.p2pSourcePrioritiesEnabled;
    final nextP2pSourcePrioritiesEnabled =
        requestedP2pSourcePrioritiesEnabled && nextP2pEnabled;
    return PlayerBehaviorSettings(
      useNativePlayer: useNativePlayer ?? this.useNativePlayer,
      playbackEngine: playbackEngine ?? this.playbackEngine,
      externalPlayerPackage:
          externalPlayerPackage ?? this.externalPlayerPackage,
      externalPlayerActivity:
          externalPlayerActivity ?? this.externalPlayerActivity,
      externalPlayerLabel: externalPlayerLabel ?? this.externalPlayerLabel,
      startBehavior: startBehavior ?? this.startBehavior,
      retryStyle: retryStyle ?? this.retryStyle,
      subtitleAutoSelect: subtitleAutoSelect ?? this.subtitleAutoSelect,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      preferredAudioLanguage:
          preferredAudioLanguage ?? this.preferredAudioLanguage,
      controlsTimeoutSeconds:
          controlsTimeoutSeconds ?? this.controlsTimeoutSeconds,
      preferLastWorkingSource:
          preferLastWorkingSource ?? this.preferLastWorkingSource,
      autoSwitchOnStall: autoSwitchOnStall ?? this.autoSwitchOnStall,
      autoplayNextEpisode: autoplayNextEpisode ?? this.autoplayNextEpisode,
      pipOnBackground: pipOnBackground ?? this.pipOnBackground,
      confirmBeforeLeaving: confirmBeforeLeaving ?? this.confirmBeforeLeaving,
      experimentalControlsEnabled:
          experimentalControlsEnabled ?? this.experimentalControlsEnabled,
      failureReadSeconds: failureReadSeconds ?? this.failureReadSeconds,
      libVlcWarmupSeconds: libVlcWarmupSeconds ?? this.libVlcWarmupSeconds,
      libVlcReleaseSettleMs:
          libVlcReleaseSettleMs ?? this.libVlcReleaseSettleMs,
      stallWatchdogSeconds: stallWatchdogSeconds ?? this.stallWatchdogSeconds,
      libVlcOpenTimeoutSeconds:
          libVlcOpenTimeoutSeconds ?? this.libVlcOpenTimeoutSeconds,
      libVlcContinuousTsVisualGraceSeconds:
          libVlcContinuousTsVisualGraceSeconds ??
          this.libVlcContinuousTsVisualGraceSeconds,
      providerWarmupCount: providerWarmupCount ?? this.providerWarmupCount,
      providerResolveTimeoutSeconds:
          providerResolveTimeoutSeconds ?? this.providerResolveTimeoutSeconds,
      zeroClockSkipEnabled: zeroClockSkipEnabled ?? this.zeroClockSkipEnabled,
      progressFallbackClockEnabled:
          progressFallbackClockEnabled ?? this.progressFallbackClockEnabled,
      resumeSeekRetrySeconds:
          resumeSeekRetrySeconds ?? this.resumeSeekRetrySeconds,
      blackVideoWatchdogSeconds:
          blackVideoWatchdogSeconds ?? this.blackVideoWatchdogSeconds,
      autoProviderMemory: autoProviderMemory ?? this.autoProviderMemory,
      loadingBackdropStyle: loadingBackdropStyle ?? this.loadingBackdropStyle,
      exoPlayerOpenTimeoutSeconds:
          exoPlayerOpenTimeoutSeconds ?? this.exoPlayerOpenTimeoutSeconds,
      media3NativeExoEnabled:
          media3NativeExoEnabled ?? this.media3NativeExoEnabled,
      p2pPlaybackConsentAccepted: validP2pConsent,
      p2pPlaybackConsentVersion: validP2pConsent ? nextP2pConsentVersion : 0,
      p2pPlaybackConsentAcceptedAt: validP2pConsent
          ? p2pPlaybackConsentAcceptedAt ?? this.p2pPlaybackConsentAcceptedAt
          : null,
      p2pPlaybackEnabled: nextP2pEnabled,
      advancedRuntimeControlsExpanded: nextAdvancedRuntimeControlsExpanded,
      p2pSourcePrioritiesEnabled: nextP2pSourcePrioritiesEnabled,
      p2pPriorityMode: _normalizedP2pPriorityMode(
        p2pPriorityMode ?? this.p2pPriorityMode,
      ),
      p2pResultsPerQuality: (p2pResultsPerQuality ?? this.p2pResultsPerQuality)
          .clamp(1, 5)
          .toInt(),
      p2pPreferredAudioLanguageMode: _normalizedP2pPreferredAudioLanguageMode(
        p2pPreferredAudioLanguageMode ?? this.p2pPreferredAudioLanguageMode,
      ),
      p2pAvoidRiskyFormats: p2pAvoidRiskyFormats ?? this.p2pAvoidRiskyFormats,
      p2pSizeLimitMb: (p2pSizeLimitMb ?? this.p2pSizeLimitMb)
          .clamp(0, 65536)
          .toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': AppState._playerBehaviorSettingsSchemaVersion,
      'useNativePlayer': useNativePlayer,
      'playbackEngine': playbackEngine,
      if (externalPlayerPackage != null)
        'externalPlayerPackage': externalPlayerPackage,
      if (externalPlayerActivity != null)
        'externalPlayerActivity': externalPlayerActivity,
      if (externalPlayerLabel != null)
        'externalPlayerLabel': externalPlayerLabel,
      'startBehavior': startBehavior,
      'retryStyle': retryStyle,
      'subtitleAutoSelect': subtitleAutoSelect,
      'subtitleLanguage': subtitleLanguage,
      'preferredAudioLanguage': preferredAudioLanguage,
      'controlsTimeoutSeconds': controlsTimeoutSeconds,
      'preferLastWorkingSource': preferLastWorkingSource,
      'autoSwitchOnStall': autoSwitchOnStall,
      'autoplayNextEpisode': autoplayNextEpisode,
      'pipOnBackground': pipOnBackground,
      'confirmBeforeLeaving': confirmBeforeLeaving,
      'experimentalControlsEnabled': experimentalControlsEnabled,
      'failureReadSeconds': failureReadSeconds,
      'libVlcWarmupSeconds': libVlcWarmupSeconds,
      'libVlcReleaseSettleMs': libVlcReleaseSettleMs,
      'stallWatchdogSeconds': stallWatchdogSeconds,
      'libVlcOpenTimeoutSeconds': libVlcOpenTimeoutSeconds,
      'libVlcContinuousTsVisualGraceSeconds':
          libVlcContinuousTsVisualGraceSeconds,
      'providerWarmupCount': providerWarmupCount,
      'providerResolveTimeoutSeconds': providerResolveTimeoutSeconds,
      'zeroClockSkipEnabled': zeroClockSkipEnabled,
      'progressFallbackClockEnabled': progressFallbackClockEnabled,
      'resumeSeekRetrySeconds': resumeSeekRetrySeconds,
      'blackVideoWatchdogSeconds': blackVideoWatchdogSeconds,
      'autoProviderMemory': autoProviderMemory,
      'loadingBackdropStyle': loadingBackdropStyle,
      'exoPlayerOpenTimeoutSeconds': exoPlayerOpenTimeoutSeconds,
      'media3NativeExoEnabled': media3NativeExoEnabled,
      'p2pPlaybackConsentAccepted': p2pPlaybackConsentAccepted,
      'p2pPlaybackConsentVersion': p2pPlaybackConsentVersion,
      if (p2pPlaybackConsentAcceptedAt != null)
        'p2pPlaybackConsentAcceptedAt': p2pPlaybackConsentAcceptedAt,
      'p2pPlaybackEnabled': p2pPlaybackEnabled,
      'advancedRuntimeControlsExpanded': advancedRuntimeControlsExpanded,
      'p2pSourcePrioritiesEnabled': p2pSourcePrioritiesEnabled,
      'p2pPriorityMode': p2pPriorityMode,
      'p2pResultsPerQuality': p2pResultsPerQuality,
      'p2pPreferredAudioLanguageMode': p2pPreferredAudioLanguageMode,
      'p2pAvoidRiskyFormats': p2pAvoidRiskyFormats,
      'p2pSizeLimitMb': p2pSizeLimitMb,
    };
  }
}

bool _validP2pHeavyConsent(Map<String, dynamic> json) {
  return json['p2pPlaybackConsentAccepted'] == true &&
      (_intOrNull(json['p2pPlaybackConsentVersion']) ?? 0) >=
          kP2pHeavyConsentVersion;
}

String _normalizedAutoProviderMemory(dynamic value) {
  final raw = (value ?? 'balanced').toString().trim().toLowerCase();
  return switch (raw) {
    'fresh' => 'fresh',
    'sticky' => 'sticky',
    _ => 'balanced',
  };
}

String _normalizedLoadingBackdropStyle(dynamic value) {
  final raw = (value ?? 'scan').toString().trim().toLowerCase();
  return switch (raw) {
    'none' || 'off' => 'none',
    'artwork' ||
    'artworkblur' ||
    'background' ||
    'backgroundblur' => 'artworkBlur',
    _ => 'scan',
  };
}

String? _nonEmptyString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

double _doubleFromJson(dynamic value, {double fallback = 0}) {
  return double.tryParse((value ?? '').toString()) ?? fallback;
}

Set<String> _notificationSeenCampaigns() {
  return AppState.prefs
          ?.getStringList(AppState._notificationSeenCampaignsKey)
          ?.where((value) => value.trim().isNotEmpty)
          .toSet() ??
      <String>{};
}

DateTime? _dateTimeFromPrefs(String key) {
  final raw = AppState.prefs?.getString(key);
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

String _dateStamp(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

String _normalizedPlaybackEngine(dynamic value) {
  final raw = (value ?? 'auto').toString().trim().toLowerCase();
  return switch (raw) {
    'exo' || 'exoplayer' => 'exoplayer',
    'vlc' || 'libvlc' => 'libvlc',
    'ks' || 'ksplayer' => 'ksplayer',
    _ => 'auto',
  };
}

String _normalizedP2pPriorityMode(dynamic value) {
  final raw = (value ?? p2pPriorityModeSmartStart).toString().trim();
  return switch (raw) {
    p2pPriorityModeQualityFirst => p2pPriorityModeQualityFirst,
    p2pPriorityModeAvailabilityFirst => p2pPriorityModeAvailabilityFirst,
    p2pPriorityModeSmallerFasterFiles => p2pPriorityModeSmallerFasterFiles,
    p2pPriorityModeBalancedQualityAvailability =>
      p2pPriorityModeBalancedQualityAvailability,
    _ => p2pPriorityModeSmartStart,
  };
}

String _normalizedP2pPreferredAudioLanguageMode(dynamic value) {
  final raw = (value ?? p2pAudioLanguageFollowPlayback).toString().trim();
  return switch (raw) {
    p2pAudioLanguageFollowPlayback => p2pAudioLanguageFollowPlayback,
    _ => p2pAudioLanguageFollowPlayback,
  };
}

ThemeMode _themeModeFromName(String? name) {
  return switch (name) {
    'system' => ThemeMode.system,
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

String _accentThemeFromName(String? name) {
  return switch (name) {
    AppState.accentPurple => AppState.accentPurple,
    AppState.accentOcean => AppState.accentOcean,
    AppState.accentAmber => AppState.accentAmber,
    AppState.accentCustom => AppState.accentCustom,
    _ => AppState.accentGreen,
  };
}

String _startupTabModeFromName(String? name) {
  return switch (name) {
    'home' => 'home',
    'discovery' => 'discovery',
    'library' => 'library',
    'settings' => 'settings',
    'last' => 'last',
    _ => 'home',
  };
}

String _startupBehaviorFromName(String? name) {
  return switch (name) {
    'freshHome' => 'freshHome',
    'normal' => 'normal',
    _ => 'normal',
  };
}

String _textSizeFromName(String? name) {
  return switch (name) {
    'small' => 'small',
    'large' => 'large',
    'default' => 'default',
    _ => 'default',
  };
}

String _navigationStyleFromName(String? name) {
  return switch (name) {
    'selected' => 'selected',
    'hidden' => 'hidden',
    'always' => 'always',
    _ => 'always',
  };
}

String _homeDensityFromName(String? name) {
  return switch (name) {
    'compact' => 'compact',
    'large' => 'large',
    'comfortable' => 'comfortable',
    _ => 'comfortable',
  };
}

String _leaderboardScopeFromName(String? name) {
  return switch (name) {
    'today' => 'today',
    'all' || 'allTime' => 'all',
    'weekly' => 'weekly',
    _ => 'weekly',
  };
}

String _statusMessageStyleFromName(String? name) {
  return switch (name) {
    'bottom' => 'bottom',
    'quiet' => 'quiet',
    'floating' => 'floating',
    _ => 'floating',
  };
}

String _posterImageIntensityFromName(String? name) {
  return switch (name) {
    'soft' => 'soft',
    'normal' => 'normal',
    'bold' => 'bold',
    _ => 'normal',
  };
}

String _systemBarStyleFromName(String? name) {
  return switch (name) {
    'match' => 'match',
    'black' => 'black',
    'transparent' => 'transparent',
    _ => 'match',
  };
}

MediaType _mediaTypeFromStoredName(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  for (final type in MediaType.values) {
    if (type.matchesCompatType(normalized)) return type;
  }
  return MediaType.movie;
}

CatalogSort _catalogSortFromStoredName(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'year' => CatalogSort.year,
    'new' || 'latest' || 'recent' || 'newest' => CatalogSort.newest,
    'oldest' => CatalogSort.oldest,
    'az' || 'a_z' || 'a-z' || 'alphaasc' || 'alpha_asc' => CatalogSort.alphaAsc,
    'za' ||
    'z_a' ||
    'z-a' ||
    'alphadesc' ||
    'alpha_desc' => CatalogSort.alphaDesc,
    'toprated' ||
    'top_rated' ||
    'top-rated' ||
    'rating' ||
    'rated' => CatalogSort.topRated,
    'nowplaying' ||
    'now_playing' ||
    'now-playing' ||
    'theaters' => CatalogSort.nowPlaying,
    'airing_today' || 'airingtoday' => CatalogSort.airingToday,
    'on_tv' || 'ontv' => CatalogSort.onTv,
    'upcoming' || 'comingsoon' || 'coming_soon' => CatalogSort.upcoming,
    'hidden' ||
    'hiddengems' ||
    'hidden_gems' ||
    'hidden-gems' ||
    'obscure' ||
    'gems' => CatalogSort.hiddenGems,
    'imdbrating' ||
    'imdb_rating' ||
    'imdb' ||
    'featured' => CatalogSort.imdbRating,
    _ => CatalogSort.top,
  };
}

Map<String, CatalogSort> _browseSortsFromJson(Object? value) {
  if (value is! Map) return const <String, CatalogSort>{};
  final sorts = <String, CatalogSort>{};
  for (final entry in value.entries) {
    final type = _mediaTypeFromStoredName(entry.key?.toString());
    sorts[type.compatTypeValue] = _catalogSortFromStoredName(
      entry.value?.toString(),
    );
  }
  return Map.unmodifiable(sorts);
}

Map<String, String> _browseGenresFromJson(Object? value) {
  return _browseStringsFromJson(value);
}

Map<String, String> _browseStringsFromJson(Object? value) {
  if (value is! Map) return const <String, String>{};
  final values = <String, String>{};
  for (final entry in value.entries) {
    final type = _mediaTypeFromStoredName(entry.key?.toString());
    final stored = entry.value?.toString().trim() ?? '';
    if (stored.isNotEmpty) {
      values[type.compatTypeValue] = stored;
    }
  }
  return Map.unmodifiable(values);
}

Color _colorFromStoredInt(int? value, {required Color fallback}) {
  if (value == null) return fallback;
  return Color(value).withAlpha(0xFF);
}

List<String> _rotateProviderOrder(List<String> providers, String selected) {
  final index = providers.indexOf(selected);
  if (index < 0) return providers;
  return [...providers.skip(index), ...providers.take(index)];
}

String _normalizeNativeProviderId(String value) {
  return switch (value.trim().toLowerCase()) {
    'auto' => AppState.autoNativeProviderId,
    'alpha' || 'vidlink' => 'vidlink',
    'beta' || 'vidsrc' => 'vidsrc',
    'fmovies4u' || 'hydrahd' => AppState.autoNativeProviderId,
    'delta' || 'icefy' => 'icefy',
    'epsilon' || 'vidnest' => 'vidnest',
    'zeta' || 'primesrc' || 'xpass' => 'xpass',
    'eta' || 'cineby' || 'moviesapi' => 'moviesapi',
    'nu' || 'vidking' => 'vidking',
    'theta' || 'popr' => 'popr',
    'rho' || 'cinesu' => 'cinesu',
    'sigma' || 'vidapi' => 'vidapi',
    'tau' || 'videasy' => 'videasy',
    'upsilon' || 'vidfun' => 'vidfun',
    'phi' || 'flixhq' => 'flixhq',
    'iota' || 'rgshows' => 'rgshows',
    'kappa' || 'vixsrc' => 'vixsrc',
    'lambda' || 'vidrock' => 'vidrock',
    'mu' || 'vidzee' => 'vidzee',
    'xi' || 'flixer' => 'flixer',
    'omicron' || '7xstream' => '7xstream',
    'pi' || 'meowtv' => 'meowtv',
    _ => value.trim().toLowerCase(),
  };
}

List<String> _autoProviderOrder(
  List<String> providerIds,
  Map<String, int> failures,
) {
  final indexed = <({String id, int index, int score})>[
    for (var index = 0; index < providerIds.length; index++)
      (
        id: providerIds[index],
        index: index,
        score: _autoProviderScore(providerIds[index], failures),
      ),
  ];
  indexed.sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;
    return a.index.compareTo(b.index);
  });
  return [for (final item in indexed) item.id];
}

int _autoProviderScore(String providerId, Map<String, int> failures) {
  final health = AppState.nativeProviderHealthDetailsFor(providerId);
  final sourceCount = health.sourceCount ?? 0;
  final failurePenalty = (failures[providerId] ?? 0) * 120;
  final latencyPenalty = ((health.responseMillis ?? 2500) / 25).round();
  final healthScore = switch (health.status) {
    NativeProviderHealthStatus.ready => 1000,
    NativeProviderHealthStatus.slow => 620,
    NativeProviderHealthStatus.limited => 520,
    NativeProviderHealthStatus.protected => 430,
    NativeProviderHealthStatus.untested => 420,
    NativeProviderHealthStatus.checkedNoSample => 420,
    NativeProviderHealthStatus.noSource => 360,
    NativeProviderHealthStatus.failing => 0,
  };
  return healthScore + (sourceCount * 35) - failurePenalty - latencyPenalty;
}
