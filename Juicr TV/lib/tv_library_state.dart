import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String tvLibraryStatePrefsKey = 'juicr_tv_library_state_v1';

const int _schemaVersion = 1;
const int _maxLikedKeys = 1000;
const int _maxRecentItems = 80;
const int _maxProgressEntries = 200;
const int _maxCompletedMarkers = 300;
const int _maxStringLength = 240;

class TvLibraryStateStore {
  TvLibraryStateStore._(this._prefs, this.state);

  final SharedPreferences _prefs;
  TvLibraryState state;

  static Future<TvLibraryStateStore> load({
    SharedPreferences? preferences,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final encoded = prefs.getString(tvLibraryStatePrefsKey);
    final restored = TvLibraryState.fromEncodedJson(encoded);
    return TvLibraryStateStore._(prefs, restored);
  }

  bool isLiked(String key) => state.isLiked(key);

  bool isCompleted(String key) => state.isCompleted(key);

  TvPlaybackProgress? progressFor(String key) {
    final normalizedKey = _safeString(key);
    if (normalizedKey == null) return null;
    return state.progress[normalizedKey];
  }

  Future<void> save(TvLibraryState nextState) async {
    state = nextState.normalized();
    await _prefs.setString(tvLibraryStatePrefsKey, state.toEncodedJson());
  }

  Future<bool> toggleLiked(String key) async {
    final normalizedKey = _safeString(key);
    if (normalizedKey == null) return state.isLiked(key);
    final liked = Set<String>.from(state.likedKeys);
    final isNowLiked = !liked.contains(normalizedKey);
    if (isNowLiked) {
      liked.add(normalizedKey);
    } else {
      liked.remove(normalizedKey);
    }
    await save(state.copyWith(likedKeys: liked));
    return isNowLiked;
  }

  Future<void> setLiked(String key, bool liked) async {
    final normalizedKey = _safeString(key);
    if (normalizedKey == null) return;
    final likedKeys = Set<String>.from(state.likedKeys);
    if (liked) {
      likedKeys.add(normalizedKey);
    } else {
      likedKeys.remove(normalizedKey);
    }
    await save(state.copyWith(likedKeys: likedKeys));
  }

  Future<void> addRecentItem({
    required String key,
    String? itemId,
    Map<String, Object?>? snapshot,
  }) async {
    final recent = TvRecentItemSnapshot.fromValues(
      key: key,
      itemId: itemId,
      snapshot: snapshot,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    if (recent == null) return;

    final nextRecent = [
      recent,
      ...state.recentItems.where((item) => item.key != recent.key),
    ].take(_maxRecentItems).toList(growable: false);

    await save(state.copyWith(recentItems: nextRecent));
  }

  Future<void> updateProgress({
    required String key,
    required int positionMillis,
    int? durationMillis,
  }) async {
    final progress = TvPlaybackProgress.fromValues(
      key: key,
      positionMillis: positionMillis,
      durationMillis: durationMillis,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    if (progress == null) return;

    final nextProgress = Map<String, TvPlaybackProgress>.from(state.progress)
      ..[progress.key] = progress;
    final completed = Set<String>.from(state.completedKeys);
    if (progress.positionMillis <= 0) {
      completed.remove(progress.key);
    }

    await save(
      state.copyWith(
        progress: nextProgress,
        completedKeys: completed,
      ),
    );
  }

  Future<void> clearProgress(String key) async {
    final normalizedKey = _safeString(key);
    if (normalizedKey == null) return;
    final nextProgress = Map<String, TvPlaybackProgress>.from(state.progress)
      ..remove(normalizedKey);
    final completed = Set<String>.from(state.completedKeys)
      ..remove(normalizedKey);
    await save(
      state.copyWith(
        progress: nextProgress,
        completedKeys: completed,
      ),
    );
  }

  Future<void> markCompleted(String key, {bool completed = true}) async {
    final normalizedKey = _safeString(key);
    if (normalizedKey == null) return;
    final completedKeys = Set<String>.from(state.completedKeys);
    if (completed) {
      completedKeys.add(normalizedKey);
    } else {
      completedKeys.remove(normalizedKey);
    }
    await save(state.copyWith(completedKeys: completedKeys));
  }

  Future<void> clear() async {
    state = const TvLibraryState();
    await _prefs.remove(tvLibraryStatePrefsKey);
  }
}

class TvLibraryState {
  const TvLibraryState({
    this.likedKeys = const <String>{},
    this.recentItems = const <TvRecentItemSnapshot>[],
    this.progress = const <String, TvPlaybackProgress>{},
    this.completedKeys = const <String>{},
  });

  final Set<String> likedKeys;
  final List<TvRecentItemSnapshot> recentItems;
  final Map<String, TvPlaybackProgress> progress;
  final Set<String> completedKeys;

  bool isLiked(String key) {
    final normalizedKey = _safeString(key);
    return normalizedKey != null && likedKeys.contains(normalizedKey);
  }

  bool isCompleted(String key) {
    final normalizedKey = _safeString(key);
    return normalizedKey != null && completedKeys.contains(normalizedKey);
  }

  int get activeWatchSeconds {
    var total = 0;
    for (final progress in normalized().progress.values) {
      final durationMillis = progress.durationMillis;
      if (durationMillis == null || durationMillis <= 0) continue;
      final baseKey = _baseItemKeyFromPlaybackKey(progress.key, recentItems.map((item) => item.key));
      final snapshot = baseKey == null
          ? null
          : recentItems.where((item) => item.key == baseKey).firstOrNull;
      if (_normalizeMobileType(snapshot?.itemType) == 'live') continue;
      total += (progress.positionMillis / 1000).round().clamp(0, (durationMillis / 1000).round()).toInt();
    }
    return total;
  }

  static TvLibraryState fromEncodedJson(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) {
      return const TvLibraryState();
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const TvLibraryState();
      return TvLibraryState.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return const TvLibraryState();
    }
  }

  factory TvLibraryState.fromJson(Map<String, Object?> json) {
    if (json['version'] != _schemaVersion) return const TvLibraryState();

    final likedKeys = _safeStringSet(json['likedKeys'], _maxLikedKeys);
    final completedKeys = _safeStringSet(
      json['completedKeys'],
      _maxCompletedMarkers,
    );
    final recentItems = _safeMapList(json['recentItems'])
        .map(TvRecentItemSnapshot.fromJson)
        .whereType<TvRecentItemSnapshot>()
        .toList(growable: false);
    final progressEntries = _safeMapList(json['progress'])
        .map(TvPlaybackProgress.fromJson)
        .whereType<TvPlaybackProgress>();

    final progress = <String, TvPlaybackProgress>{};
    for (final entry in progressEntries) {
      progress[entry.key] = entry;
    }

    return TvLibraryState(
      likedKeys: likedKeys,
      recentItems: recentItems,
      progress: progress,
      completedKeys: completedKeys,
    ).normalized();
  }

  TvLibraryState copyWith({
    Set<String>? likedKeys,
    List<TvRecentItemSnapshot>? recentItems,
    Map<String, TvPlaybackProgress>? progress,
    Set<String>? completedKeys,
  }) {
    return TvLibraryState(
      likedKeys: likedKeys ?? this.likedKeys,
      recentItems: recentItems ?? this.recentItems,
      progress: progress ?? this.progress,
      completedKeys: completedKeys ?? this.completedKeys,
    );
  }

  TvLibraryState normalized() {
    final liked = _limitedStrings(likedKeys, _maxLikedKeys).toSet();
    final completed = _limitedStrings(
      completedKeys,
      _maxCompletedMarkers,
    ).toSet();

    final recentByKey = <String, TvRecentItemSnapshot>{};
    for (final item in recentItems) {
      recentByKey[item.key] = item;
    }
    final recent = recentByKey.values.toList(growable: false)
      ..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));

    final progressValues = progress.values.toList(growable: false)
      ..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    final limitedProgress = <String, TvPlaybackProgress>{};
    for (final entry in progressValues.take(_maxProgressEntries)) {
      limitedProgress[entry.key] = entry;
    }

    return TvLibraryState(
      likedKeys: liked,
      recentItems: recent.take(_maxRecentItems).toList(growable: false),
      progress: limitedProgress,
      completedKeys: completed,
    );
  }

  Map<String, Object?> toJson() {
    final normalizedState = normalized();
    final progress = normalizedState.progress.values.toList(growable: false)
      ..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    return <String, Object?>{
      'version': _schemaVersion,
      'likedKeys': normalizedState.likedKeys.toList(growable: false)..sort(),
      'recentItems': normalizedState.recentItems
          .map((item) => item.toJson())
          .toList(growable: false),
      'progress': progress.map((entry) => entry.toJson()).toList(
            growable: false,
          ),
      'completedKeys': normalizedState.completedKeys.toList(growable: false)
        ..sort(),
    };
  }

  String toEncodedJson() => jsonEncode(toJson());

  Map<String, Object?> toMobileLibraryBackup({DateTime? exportedAt}) {
    final normalizedState = normalized();
    final snapshotsByKey = {
      for (final item in normalizedState.recentItems) item.key: item,
    };
    final saved = normalizedState.likedKeys
        .map((key) => _mobileItemJsonForKey(key, snapshotsByKey[key]))
        .whereType<Map<String, Object?>>()
        .toList(growable: false)
      ..sort(
        (left, right) => (left['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((right['name'] ?? '').toString().toLowerCase()),
      );

    final progressEntries = normalizedState.progress.values.toList(growable: false)
      ..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    final continueWatching = <Map<String, Object?>>[];
    final completedWatching = <Map<String, Object?>>[];
    for (final progress in progressEntries) {
      final baseKey = _baseItemKeyFromPlaybackKey(progress.key, snapshotsByKey.keys);
      final snapshot = baseKey == null ? null : snapshotsByKey[baseKey];
      final item = _mobileItemJsonForKey(baseKey ?? progress.key, snapshot);
      if (item == null || item['type'] == 'live') continue;
      final durationSeconds = ((progress.durationMillis ?? 0) / 1000).round();
      if (durationSeconds <= 0 || progress.positionMillis <= 0) continue;
      final watchedSeconds = (progress.positionMillis / 1000).round().clamp(0, durationSeconds);
      final progressFraction = (watchedSeconds / durationSeconds).clamp(0.0, 1.0).toDouble();
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(progress.updatedAtMillis);
      final entry = <String, Object?>{
        'key': progress.key,
        'item': item,
        'title': (snapshot?.title ?? item['name'] ?? 'Continue watching').toString(),
        'subtitle': _subtitleForSnapshot(snapshot),
        'watchedSeconds': watchedSeconds,
        'credibleWatchedSeconds': watchedSeconds,
        'durationSeconds': durationSeconds,
        'progress': progressFraction,
        'updatedAt': updatedAt.toIso8601String(),
      };
      if (normalizedState.completedKeys.contains(progress.key)) {
        completedWatching.add(<String, Object?>{
          'key': progress.key,
          'item': item,
          'title': entry['title'],
          'subtitle': entry['subtitle'],
          'watchedSeconds': watchedSeconds,
          'credibleWatchedSeconds': watchedSeconds,
          'durationSeconds': durationSeconds,
          'completedAt': updatedAt.toIso8601String(),
          'completionCount': 1,
        });
      } else if (progressFraction > 0 && progressFraction < 0.98) {
        continueWatching.add(entry);
      }
    }

    return <String, Object?>{
      'schema': 'juicr.library.backup.v1',
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      'saved': saved,
      'lists': const <Object?>[],
      'continueWatching': continueWatching,
      'completedWatching': completedWatching,
    };
  }

  TvLibraryState mergeMobileLibraryBackup(Map<String, Object?> backup) {
    if (backup['schema'] != 'juicr.library.backup.v1') return normalized();

    final nextLiked = Set<String>.from(likedKeys);
    final recentByKey = {
      for (final item in recentItems) item.key: item,
    };
    final nextProgress = Map<String, TvPlaybackProgress>.from(progress);
    final nextCompleted = Set<String>.from(completedKeys);

    for (final item in _safeMapList(backup['saved'])) {
      final snapshot = _snapshotFromMobileItem(item);
      if (snapshot == null) continue;
      nextLiked.add(snapshot.key);
      recentByKey[snapshot.key] = snapshot;
    }

    for (final entry in _safeMapList(backup['continueWatching'])) {
      final imported = _progressFromMobileEntry(entry, completed: false);
      if (imported == null) continue;
      nextProgress[imported.progress.key] = imported.progress;
      nextCompleted.remove(imported.progress.key);
      recentByKey[imported.snapshot.key] = imported.snapshot;
    }

    for (final entry in _safeMapList(backup['completedWatching'])) {
      final imported = _progressFromMobileEntry(entry, completed: true);
      if (imported == null) continue;
      nextProgress[imported.progress.key] = imported.progress;
      nextCompleted.add(imported.progress.key);
      recentByKey[imported.snapshot.key] = imported.snapshot;
    }

    return copyWith(
      likedKeys: nextLiked,
      recentItems: recentByKey.values.toList(growable: false),
      progress: nextProgress,
      completedKeys: nextCompleted,
    ).normalized();
  }
}

class TvRecentItemSnapshot {
  const TvRecentItemSnapshot({
    required this.key,
    this.itemId,
    this.itemType,
    this.title,
    this.year,
    required this.updatedAtMillis,
  });

  final String key;
  final String? itemId;
  final String? itemType;
  final String? title;
  final String? year;
  final int updatedAtMillis;

  static TvRecentItemSnapshot? fromValues({
    required String key,
    String? itemId,
    Map<String, Object?>? snapshot,
    int? updatedAtMillis,
  }) {
    final normalizedKey = _safeString(key);
    if (normalizedKey == null) return null;
    return TvRecentItemSnapshot(
      key: normalizedKey,
      itemId: _safeString(itemId ?? snapshot?['id']),
      itemType: _safeString(snapshot?['type']),
      title: _safeString(snapshot?['title'] ?? snapshot?['name']),
      year: _safeString(snapshot?['year']),
      updatedAtMillis: _safeNonNegativeInt(updatedAtMillis) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  static TvRecentItemSnapshot? fromJson(Map<String, Object?> json) {
    final key = _safeString(json['key']);
    final updatedAtMillis = _safeNonNegativeInt(json['updatedAtMillis']);
    if (key == null || updatedAtMillis == null) return null;
    return TvRecentItemSnapshot(
      key: key,
      itemId: _safeString(json['itemId']),
      itemType: _safeString(json['itemType']),
      title: _safeString(json['title']),
      year: _safeString(json['year']),
      updatedAtMillis: updatedAtMillis,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      if (itemId != null) 'itemId': itemId,
      if (itemType != null) 'itemType': itemType,
      if (title != null) 'title': title,
      if (year != null) 'year': year,
      'updatedAtMillis': updatedAtMillis,
    };
  }
}

class TvPlaybackProgress {
  const TvPlaybackProgress({
    required this.key,
    required this.positionMillis,
    this.durationMillis,
    required this.updatedAtMillis,
  });

  final String key;
  final int positionMillis;
  final int? durationMillis;
  final int updatedAtMillis;

  double get fraction {
    final duration = durationMillis;
    if (duration == null || duration <= 0) return 0;
    return (positionMillis / duration).clamp(0, 1).toDouble();
  }

  static TvPlaybackProgress? fromValues({
    required String key,
    required int positionMillis,
    int? durationMillis,
    int? updatedAtMillis,
  }) {
    final normalizedKey = _safeString(key);
    final normalizedPosition = _safeNonNegativeInt(positionMillis);
    final normalizedUpdatedAt = _safeNonNegativeInt(updatedAtMillis);
    if (normalizedKey == null || normalizedPosition == null) return null;

    final normalizedDuration = _safePositiveInt(durationMillis);
    return TvPlaybackProgress(
      key: normalizedKey,
      positionMillis: normalizedDuration == null
          ? normalizedPosition
          : normalizedPosition.clamp(0, normalizedDuration).toInt(),
      durationMillis: normalizedDuration,
      updatedAtMillis:
          normalizedUpdatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  static TvPlaybackProgress? fromJson(Map<String, Object?> json) {
    return TvPlaybackProgress.fromValues(
      key: (json['key'] ?? '').toString(),
      positionMillis: _safeNonNegativeInt(json['positionMillis']) ?? -1,
      durationMillis: _safePositiveInt(json['durationMillis']),
      updatedAtMillis: _safeNonNegativeInt(json['updatedAtMillis']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      'positionMillis': positionMillis,
      if (durationMillis != null) 'durationMillis': durationMillis,
      'updatedAtMillis': updatedAtMillis,
    };
  }
}

List<String> _limitedStrings(Iterable<Object?> values, int limit) {
  return values
      .map(_safeString)
      .whereType<String>()
      .take(limit)
      .toList(growable: false);
}

Set<String> _safeStringSet(Object? value, int limit) {
  if (value is! List) return <String>{};
  return _limitedStrings(value.whereType<Object>(), limit).toSet();
}

List<Map<String, Object?>> _safeMapList(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  final maps = <Map<String, Object?>>[];
  for (final entry in value.whereType<Map>()) {
    try {
      maps.add(Map<String, Object?>.from(entry));
    } catch (_) {
      continue;
    }
  }
  return maps;
}

String? _safeString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  if (text.length <= _maxStringLength) return text;
  return text.substring(0, _maxStringLength);
}

int? _safeNonNegativeInt(Object? value) {
  final parsed = _safeInt(value);
  if (parsed == null || parsed < 0) return null;
  return parsed;
}

int? _safePositiveInt(Object? value) {
  final parsed = _safeInt(value);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

int? _safeInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

Map<String, Object?>? _mobileItemJsonForKey(
  String key,
  TvRecentItemSnapshot? snapshot,
) {
  final parts = _itemKeyParts(key);
  final type = _normalizeMobileType(snapshot?.itemType ?? parts.$1);
  final id = _safeString(snapshot?.itemId ?? parts.$2);
  final name = _safeString(snapshot?.title) ?? id;
  if (id == null || name == null) return null;
  return <String, Object?>{
    'type': type,
    'id': id,
    'name': name,
    'poster': null,
    'background': null,
    'logo': null,
    if (snapshot?.year != null) 'year': snapshot!.year,
    'releaseDate': null,
    'tmdb_id': null,
    'imdb_id': null,
    'genres': const <Object?>[],
    'description': null,
    'imdbRating': null,
    'voteCount': null,
    'adult': false,
    'isUpcoming': false,
    'isLocalCatalogItem': false,
    'localPlaybackLocked': false,
    'localCatalogId': null,
    'localCatalogItemId': null,
    'localCatalogName': null,
    'localMediaKind': null,
    'localSourceLabel': null,
    'localRelinkNeededCount': null,
    'personalServerTypeId': null,
    'personalServerItemId': null,
    'personalServerSeriesItemId': null,
  };
}

(String, String) _itemKeyParts(String key) {
  final index = key.indexOf(':');
  if (index <= 0 || index >= key.length - 1) return ('movie', key);
  return (key.substring(0, index), key.substring(index + 1));
}

String _normalizeMobileType(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  if (normalized == 'series' || normalized == 'tv') return 'series';
  if (normalized == 'animation') return 'animation';
  if (normalized == 'live' ||
      normalized == 'livetv' ||
      normalized == 'live_tv' ||
      normalized == 'channel') {
    return 'live';
  }
  return 'movie';
}

String? _baseItemKeyFromPlaybackKey(String playbackKey, Iterable<String> itemKeys) {
  String? best;
  for (final key in itemKeys) {
    if (playbackKey == key || playbackKey.startsWith('$key:')) {
      if (best == null || key.length > best.length) best = key;
    }
  }
  if (best != null) return best;
  final parts = playbackKey.split(':');
  if (parts.length < 2) return null;
  return '${parts[0]}:${parts[1]}';
}

String? _subtitleForSnapshot(TvRecentItemSnapshot? snapshot) {
  final year = snapshot?.year?.trim();
  if (year == null || year.isEmpty) return null;
  return year;
}

TvRecentItemSnapshot? _snapshotFromMobileItem(
  Map<String, Object?> item, {
  int? updatedAtMillis,
}) {
  final type = _normalizeMobileType(item['type']?.toString());
  final id = _safeString(item['id']);
  final title = _safeString(item['name'] ?? item['title']);
  if (id == null || title == null) return null;
  return TvRecentItemSnapshot(
    key: '$type:$id',
    itemId: id,
    itemType: type,
    title: title,
    year: _safeString(item['year']),
    updatedAtMillis: updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch,
  );
}

({TvRecentItemSnapshot snapshot, TvPlaybackProgress progress})?
    _progressFromMobileEntry(
  Map<String, Object?> entry, {
  required bool completed,
}) {
  final key = _safeString(entry['key']);
  final item = entry['item'];
  if (key == null || item is! Map) return null;
  final updatedAt = DateTime.tryParse(
        (completed ? entry['completedAt'] : entry['updatedAt'])?.toString() ?? '',
      ) ??
      DateTime.now();
  final snapshot = _snapshotFromMobileItem(
    Map<String, Object?>.from(item),
    updatedAtMillis: updatedAt.millisecondsSinceEpoch,
  );
  if (snapshot == null) return null;
  final watchedSeconds = _safeNonNegativeInt(entry['watchedSeconds']) ??
      _safeNonNegativeInt(entry['credibleWatchedSeconds']) ??
      0;
  final durationSeconds = _safePositiveInt(entry['durationSeconds']);
  final progress = TvPlaybackProgress.fromValues(
    key: key,
    positionMillis: watchedSeconds * 1000,
    durationMillis: durationSeconds == null ? null : durationSeconds * 1000,
    updatedAtMillis: updatedAt.millisecondsSinceEpoch,
  );
  if (progress == null) return null;
  return (snapshot: snapshot, progress: progress);
}
