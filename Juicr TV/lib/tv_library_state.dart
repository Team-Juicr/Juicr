import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String tvLibraryStatePrefsKey = 'juicr_tv_library_state_v1';

const int _schemaVersion = 1;
const int _maxLikedKeys = 1000;
const int _maxLibraryLists = 80;
const int _maxLibraryListItems = 500;
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

  Future<TvLibraryList> createLibraryList(
    String name, {
    String? initialItemKey,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalizedInitialItemKey = _safeString(initialItemKey);
    final list = TvLibraryList(
      id: _newLibraryListId(state.libraryLists, now),
      name: name,
      itemKeys: [
        if (normalizedInitialItemKey != null) normalizedInitialItemKey,
      ],
      createdAtMillis: now,
      updatedAtMillis: now,
    ).normalized();
    final likedKeys = Set<String>.from(state.likedKeys);
    if (normalizedInitialItemKey != null) {
      likedKeys.add(normalizedInitialItemKey);
    }
    await save(
      state.copyWith(
        likedKeys: likedKeys,
        libraryLists: [list, ...state.libraryLists],
      ),
    );
    return list;
  }

  Future<void> renameLibraryList(String listId, String name) async {
    final normalizedId = _safeString(listId);
    if (normalizedId == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await save(
      state.copyWith(
        libraryLists: [
          for (final list in state.libraryLists)
            if (list.id == normalizedId)
              list.copyWith(name: name, updatedAtMillis: now)
            else
              list,
        ],
      ),
    );
  }

  Future<void> deleteLibraryList(String listId) async {
    final normalizedId = _safeString(listId);
    if (normalizedId == null) return;
    await save(
      state.copyWith(
        libraryLists: [
          for (final list in state.libraryLists)
            if (list.id != normalizedId) list,
        ],
      ),
    );
  }

  Future<bool> toggleItemInLibraryList(String listId, String itemKey) async {
    final normalizedId = _safeString(listId);
    final normalizedItemKey = _safeString(itemKey);
    if (normalizedId == null || normalizedItemKey == null) return false;
    var selected = false;
    var found = false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final likedKeys = Set<String>.from(state.likedKeys)..add(normalizedItemKey);
    final lists = [
      for (final list in state.libraryLists)
        if (list.id == normalizedId)
          () {
            found = true;
            final itemKeys = list.itemKeys.toList();
            if (itemKeys.contains(normalizedItemKey)) {
              itemKeys.remove(normalizedItemKey);
            } else {
              itemKeys.insert(0, normalizedItemKey);
              selected = true;
            }
            return list.copyWith(itemKeys: itemKeys, updatedAtMillis: now);
          }()
        else
          list,
    ];
    if (!found) return false;
    await save(state.copyWith(likedKeys: likedKeys, libraryLists: lists));
    return selected;
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
    int? credibleWatchedMillis,
    int? durationMillis,
  }) async {
    final progress = TvPlaybackProgress.fromValues(
      key: key,
      positionMillis: positionMillis,
      credibleWatchedMillis: credibleWatchedMillis,
      durationMillis: durationMillis,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    if (progress == null) return;

    final nextProgress = Map<String, TvPlaybackProgress>.from(state.progress)
      ..[progress.key] = _mergeImportedProgress(
        state.progress[progress.key],
        progress,
      );
    final completed = Set<String>.from(state.completedKeys);
    if (progress.positionMillis <= 0) {
      completed.remove(progress.key);
    }

    await save(
      state.copyWith(progress: nextProgress, completedKeys: completed),
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
      state.copyWith(progress: nextProgress, completedKeys: completed),
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
    this.libraryLists = const <TvLibraryList>[],
    this.recentItems = const <TvRecentItemSnapshot>[],
    this.progress = const <String, TvPlaybackProgress>{},
    this.completedKeys = const <String>{},
  });

  final Set<String> likedKeys;
  final List<TvLibraryList> libraryLists;
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
    final normalizedState = normalized();
    var total = 0;
    for (final progress in normalizedState.progress.values) {
      final durationMillis = progress.durationMillis;
      if (durationMillis == null || durationMillis <= 0) continue;
      final baseKey = _baseItemKeyFromPlaybackKey(
        progress.key,
        normalizedState.recentItems.map((item) => item.key),
      );
      final snapshot = baseKey == null
          ? null
          : normalizedState.recentItems
              .where((item) => item.key == baseKey)
              .firstOrNull;
      final itemType = snapshot?.itemType ??
          (baseKey == null ? null : _itemKeyParts(baseKey).$1);
      if (_normalizeMobileType(itemType) == 'live') continue;
      total += ((progress.credibleWatchedMillis ?? progress.positionMillis) / 1000)
          .round()
          .clamp(0, (durationMillis / 1000).round())
          .toInt();
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
    final libraryLists = _safeMapList(json['libraryLists'])
        .map(TvLibraryList.fromJson)
        .whereType<TvLibraryList>()
        .toList(growable: false);
    final completedKeys = _safeStringSet(
      json['completedKeys'],
      _maxCompletedMarkers,
    );
    final recentItems = _safeMapList(json['recentItems'])
        .map(TvRecentItemSnapshot.fromJson)
        .whereType<TvRecentItemSnapshot>()
        .toList(growable: false);
    final progressEntries = _safeMapList(
      json['progress'],
    ).map(TvPlaybackProgress.fromJson).whereType<TvPlaybackProgress>();

    final progress = <String, TvPlaybackProgress>{};
    for (final entry in progressEntries) {
      progress[entry.key] = entry;
    }

    return TvLibraryState(
      likedKeys: likedKeys,
      libraryLists: libraryLists,
      recentItems: recentItems,
      progress: progress,
      completedKeys: completedKeys,
    ).normalized();
  }

  TvLibraryState copyWith({
    Set<String>? likedKeys,
    List<TvLibraryList>? libraryLists,
    List<TvRecentItemSnapshot>? recentItems,
    Map<String, TvPlaybackProgress>? progress,
    Set<String>? completedKeys,
  }) {
    return TvLibraryState(
      likedKeys: likedKeys ?? this.likedKeys,
      libraryLists: libraryLists ?? this.libraryLists,
      recentItems: recentItems ?? this.recentItems,
      progress: progress ?? this.progress,
      completedKeys: completedKeys ?? this.completedKeys,
    );
  }

  TvLibraryState normalized() {
    final aliases = <String, String>{};
    final recentByKey = <String, TvRecentItemSnapshot>{};
    for (final item in recentItems) {
      final canonicalKey = _canonicalSnapshotKey(item);
      aliases[item.key] = canonicalKey;
      final itemId = _safeString(item.itemId);
      if (itemId != null) {
        aliases['${_normalizeMobileType(item.itemType)}:$itemId'] = canonicalKey;
      }
      final canonicalItem = _snapshotWithKey(item, canonicalKey);
      final existing = recentByKey[canonicalKey];
      recentByKey[canonicalKey] = existing == null
          ? canonicalItem
          : _mergeRecentSnapshots(existing, canonicalItem);
    }

    String migrateItemKey(String key) => aliases[key] ?? key;
    String migratePlaybackKey(String key) {
      for (final entry in aliases.entries) {
        if (key == entry.key) return entry.value;
        if (key.startsWith('${entry.key}:')) {
          return '${entry.value}:${key.substring(entry.key.length + 1)}';
        }
      }
      return key;
    }

    final liked = _limitedStrings(
      likedKeys.map((key) => migrateItemKey(key)),
      _maxLikedKeys,
    ).toSet();
    final completed = _limitedStrings(
      completedKeys.map((key) => migratePlaybackKey(key)),
      _maxCompletedMarkers,
    ).toSet();
    final listsById = <String, TvLibraryList>{};
    for (final list in libraryLists) {
      listsById[list.id] = TvLibraryList(
        id: list.id,
        name: list.name,
        itemKeys: list.itemKeys.map(migrateItemKey).toList(growable: false),
        createdAtMillis: list.createdAtMillis,
        updatedAtMillis: list.updatedAtMillis,
      ).normalized();
    }
    final lists = listsById.values.toList(growable: false)
      ..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));

    final recent = recentByKey.values.toList(growable: false)
      ..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));

    final migratedProgress = <String, TvPlaybackProgress>{};
    for (final entry in progress.values) {
      final migratedKey = migratePlaybackKey(entry.key);
      final migrated = TvPlaybackProgress(
        key: migratedKey,
        positionMillis: entry.positionMillis,
        credibleWatchedMillis: entry.credibleWatchedMillis,
        durationMillis: entry.durationMillis,
        updatedAtMillis: entry.updatedAtMillis,
      );
      migratedProgress[migratedKey] = _mergeImportedProgress(
        migratedProgress[migratedKey],
        migrated,
      );
    }
    final progressValues = migratedProgress.values.toList(growable: false)
      ..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    final limitedProgress = <String, TvPlaybackProgress>{};
    for (final entry in progressValues.take(_maxProgressEntries)) {
      limitedProgress[entry.key] = entry;
    }

    return TvLibraryState(
      likedKeys: liked,
      libraryLists: lists.take(_maxLibraryLists).toList(growable: false),
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
      'libraryLists': normalizedState.libraryLists
          .map((list) => list.toJson())
          .toList(growable: false),
      'recentItems': normalizedState.recentItems
          .map((item) => item.toJson())
          .toList(growable: false),
      'progress':
          progress.map((entry) => entry.toJson()).toList(growable: false),
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

    final progressEntries = normalizedState.progress.values.toList(
      growable: false,
    )..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    final continueWatching = <Map<String, Object?>>[];
    final completedWatching = <Map<String, Object?>>[];
    for (final progress in progressEntries) {
      final baseKey = _baseItemKeyFromPlaybackKey(
        progress.key,
        snapshotsByKey.keys,
      );
      final snapshot = baseKey == null ? null : snapshotsByKey[baseKey];
      final item = _mobileItemJsonForKey(baseKey ?? progress.key, snapshot);
      if (item == null || item['type'] == 'live') continue;
      final durationSeconds = ((progress.durationMillis ?? 0) / 1000).round();
      if (durationSeconds <= 0 || progress.positionMillis <= 0) continue;
      final watchedSeconds = (progress.positionMillis / 1000).round().clamp(
            0,
            durationSeconds,
          );
      final credibleWatchedSeconds =
          ((progress.credibleWatchedMillis ?? progress.positionMillis) / 1000)
              .round()
              .clamp(0, durationSeconds);
      final progressFraction =
          (watchedSeconds / durationSeconds).clamp(0.0, 1.0).toDouble();
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(
        progress.updatedAtMillis,
      );
      final entry = <String, Object?>{
        'key': progress.key,
        'item': item,
        'title':
            (snapshot?.title ?? item['name'] ?? 'Continue watching').toString(),
        'subtitle': _subtitleForSnapshot(snapshot),
        'watchedSeconds': watchedSeconds,
        'credibleWatchedSeconds': credibleWatchedSeconds,
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
          'credibleWatchedSeconds': credibleWatchedSeconds,
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
      'lists': normalizedState.libraryLists
          .map((list) => list.toMobileBackupJson())
          .toList(growable: false),
      'continueWatching': continueWatching,
      'completedWatching': completedWatching,
    };
  }

  TvLibraryState mergeMobileLibraryBackup(Map<String, Object?> backup) {
    if (backup['schema'] != 'juicr.library.backup.v1') return normalized();

    final nextLiked = Set<String>.from(likedKeys);
    final nextLists = {for (final list in libraryLists) list.id: list};
    final recentByKey = {for (final item in recentItems) item.key: item};
    final nextProgress = Map<String, TvPlaybackProgress>.from(progress);
    final nextCompleted = Set<String>.from(completedKeys);
    void mergeSnapshot(TvRecentItemSnapshot snapshot) {
      final existing = recentByKey[snapshot.key];
      recentByKey[snapshot.key] = existing == null
          ? snapshot
          : _mergeRecentSnapshots(existing, snapshot);
    }

    for (final item in _safeMapList(backup['saved'])) {
      final snapshot = _snapshotFromMobileItem(item);
      if (snapshot == null) continue;
      nextLiked.add(snapshot.key);
      mergeSnapshot(snapshot);
    }

    for (final rawList in _safeMapList(backup['lists'])) {
      final list = TvLibraryList.fromMobileBackupJson(rawList);
      if (list == null) continue;
      final existing = nextLists[list.id];
      final acceptImportedList = existing == null ||
          list.updatedAtMillis > existing.updatedAtMillis;
      if (acceptImportedList) {
        nextLists[list.id] = list;
        nextLiked.addAll(list.itemKeys);
      }
    }

    for (final entry in _safeMapList(backup['continueWatching'])) {
      final imported = _progressFromMobileEntry(entry, completed: false);
      if (imported == null) continue;
      final local = nextProgress[imported.progress.key];
      final merged = _mergeImportedProgress(local, imported.progress);
      nextProgress[imported.progress.key] = merged;
      mergeSnapshot(imported.snapshot);
    }

    for (final entry in _safeMapList(backup['completedWatching'])) {
      final imported = _progressFromMobileEntry(entry, completed: true);
      if (imported == null) continue;
      final local = nextProgress[imported.progress.key];
      final merged = _mergeImportedProgress(local, imported.progress);
      nextProgress[imported.progress.key] = merged;
      nextCompleted.add(imported.progress.key);
      mergeSnapshot(imported.snapshot);
    }

    return copyWith(
      likedKeys: nextLiked,
      libraryLists: nextLists.values.toList(growable: false),
      recentItems: recentByKey.values.toList(growable: false),
      progress: nextProgress,
      completedKeys: nextCompleted,
    ).normalized();
  }
}

TvPlaybackProgress _mergeImportedProgress(
  TvPlaybackProgress? local,
  TvPlaybackProgress imported,
) {
  if (local == null) return imported;
  final preferred = imported.positionMillis > local.positionMillis
      ? imported
      : local;
  return TvPlaybackProgress(
    key: preferred.key,
    positionMillis: preferred.positionMillis,
    credibleWatchedMillis: _maxNullableInt(
      local.credibleWatchedMillis,
      imported.credibleWatchedMillis,
    ),
    durationMillis: _maxNullableInt(
      local.durationMillis,
      imported.durationMillis,
    ),
    updatedAtMillis: local.updatedAtMillis >= imported.updatedAtMillis
        ? local.updatedAtMillis
        : imported.updatedAtMillis,
  );
}

int? _maxNullableInt(int? first, int? second) {
  if (first == null) return second;
  if (second == null) return first;
  return first >= second ? first : second;
}

class TvLibraryList {
  const TvLibraryList({
    required this.id,
    required this.name,
    required this.itemKeys,
    required this.createdAtMillis,
    required this.updatedAtMillis,
  });

  final String id;
  final String name;
  final List<String> itemKeys;
  final int createdAtMillis;
  final int updatedAtMillis;

  static TvLibraryList? fromJson(Map<String, Object?> json) {
    final id = _safeString(json['id']);
    final createdAtMillis = _safeNonNegativeInt(json['createdAtMillis']);
    final updatedAtMillis = _safeNonNegativeInt(json['updatedAtMillis']);
    if (id == null || createdAtMillis == null || updatedAtMillis == null) {
      return null;
    }
    final rawItems = json.containsKey('itemKeys')
        ? json['itemKeys']
        : json.containsKey('itemIds')
            ? json['itemIds']
            : json['items'];
    if (rawItems is! List) return null;
    final itemKeys = <String>[];
    for (final item in rawItems) {
      if (item is! String) return null;
      final itemKey = _safeString(item);
      if (itemKey == null) return null;
      itemKeys.add(itemKey);
    }
    return TvLibraryList(
      id: id,
      name: (json['name'] ?? '').toString(),
      itemKeys: itemKeys,
      createdAtMillis: createdAtMillis,
      updatedAtMillis: updatedAtMillis,
    ).normalized();
  }

  static TvLibraryList? fromMobileBackupJson(Map<String, Object?> json) {
    final id = _safeString(json['id']);
    if (id == null) return null;
    final createdAt = _strictMobileTimestamp(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(
          _safeNonNegativeInt(json['createdAtMillis']) ?? 0,
        );
    final updatedAtMillis =
        _strictMobileTimestamp(json['updatedAt'])?.millisecondsSinceEpoch ??
            _safeNonNegativeInt(json['updatedAtMillis']);
    if (updatedAtMillis == null || updatedAtMillis <= 0) return null;
    final rawItems = json.containsKey('itemIds')
        ? json['itemIds']
        : json.containsKey('itemKeys')
            ? json['itemKeys']
            : json['items'];
    if (rawItems is! List) return null;
    final itemKeys = <String>[];
    for (final item in rawItems) {
      if (item is! String) return null;
      final itemKey = _safeString(item);
      if (itemKey == null) return null;
      itemKeys.add(itemKey);
    }
    return TvLibraryList(
      id: id,
      name: (json['name'] ?? '').toString(),
      itemKeys: itemKeys,
      createdAtMillis: createdAt.millisecondsSinceEpoch,
      updatedAtMillis: updatedAtMillis,
    ).normalized();
  }

  TvLibraryList copyWith({
    String? id,
    String? name,
    List<String>? itemKeys,
    int? createdAtMillis,
    int? updatedAtMillis,
  }) {
    return TvLibraryList(
      id: id ?? this.id,
      name: name ?? this.name,
      itemKeys: itemKeys ?? this.itemKeys,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
    ).normalized();
  }

  TvLibraryList normalized() {
    return TvLibraryList(
      id: _safeString(id) ?? 'list',
      name: _normalizeLibraryListName(name),
      itemKeys: _dedupeLibraryListItemKeys(itemKeys),
      createdAtMillis: _safeNonNegativeInt(createdAtMillis) ?? 0,
      updatedAtMillis: _safeNonNegativeInt(updatedAtMillis) ?? 0,
    );
  }

  Map<String, Object?> toJson() {
    final normalizedList = normalized();
    return <String, Object?>{
      'id': normalizedList.id,
      'name': normalizedList.name,
      'itemKeys': normalizedList.itemKeys,
      'createdAtMillis': normalizedList.createdAtMillis,
      'updatedAtMillis': normalizedList.updatedAtMillis,
    };
  }

  Map<String, Object?> toMobileBackupJson() {
    final normalizedList = normalized();
    return <String, Object?>{
      'id': normalizedList.id,
      'name': normalizedList.name,
      'itemIds': normalizedList.itemKeys,
      'createdAt': DateTime.fromMillisecondsSinceEpoch(
        normalizedList.createdAtMillis,
      ).toIso8601String(),
      'updatedAt': DateTime.fromMillisecondsSinceEpoch(
        normalizedList.updatedAtMillis,
      ).toIso8601String(),
    };
  }
}

class TvRecentItemSnapshot {
  const TvRecentItemSnapshot({
    required this.key,
    this.itemId,
    this.itemType,
    this.title,
    this.year,
    this.poster,
    this.background,
    this.logo,
    this.tmdbId,
    this.imdbId,
    required this.updatedAtMillis,
  });

  final String key;
  final String? itemId;
  final String? itemType;
  final String? title;
  final String? year;
  final String? poster;
  final String? background;
  final String? logo;
  final int? tmdbId;
  final String? imdbId;
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
      poster: _safeString(snapshot?['poster'] ?? snapshot?['posterUrl']),
      background: _safeString(
        snapshot?['background'] ?? snapshot?['backdrop'] ?? snapshot?['fanart'],
      ),
      logo: _safeString(
        snapshot?['logo'] ??
            snapshot?['logoUrl'] ??
            snapshot?['clearLogo'] ??
            snapshot?['titleLogo'],
      ),
      tmdbId: _safePositiveInt(
        snapshot?['tmdbId'] ?? snapshot?['tmdb_id'] ?? snapshot?['moviedb_id'],
      ),
      imdbId: _safeString(snapshot?['imdbId'] ?? snapshot?['imdb_id']),
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
      poster: _safeString(json['poster']),
      background: _safeString(json['background']),
      logo: _safeString(json['logo']),
      tmdbId: _safePositiveInt(json['tmdbId'] ?? json['tmdb_id']),
      imdbId: _safeString(json['imdbId'] ?? json['imdb_id']),
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
      if (poster != null) 'poster': poster,
      if (background != null) 'background': background,
      if (logo != null) 'logo': logo,
      if (tmdbId != null) 'tmdbId': tmdbId,
      if (imdbId != null) 'imdbId': imdbId,
      'updatedAtMillis': updatedAtMillis,
    };
  }
}

class TvPlaybackProgress {
  const TvPlaybackProgress({
    required this.key,
    required this.positionMillis,
    this.credibleWatchedMillis,
    this.durationMillis,
    required this.updatedAtMillis,
  });

  final String key;
  final int positionMillis;
  final int? credibleWatchedMillis;
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
    int? credibleWatchedMillis,
    int? durationMillis,
    int? updatedAtMillis,
  }) {
    final normalizedKey = _safeString(key);
    final normalizedPosition = _safeNonNegativeInt(positionMillis);
    final normalizedUpdatedAt = _safeNonNegativeInt(updatedAtMillis);
    if (normalizedKey == null || normalizedPosition == null) return null;

    final normalizedDuration = _safePositiveInt(durationMillis);
    final normalizedCredible = _safeNonNegativeInt(credibleWatchedMillis);
    return TvPlaybackProgress(
      key: normalizedKey,
      positionMillis: normalizedDuration == null
          ? normalizedPosition
          : normalizedPosition.clamp(0, normalizedDuration).toInt(),
      credibleWatchedMillis: normalizedDuration == null
          ? normalizedCredible
          : normalizedCredible?.clamp(0, normalizedDuration).toInt(),
      durationMillis: normalizedDuration,
      updatedAtMillis:
          normalizedUpdatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  static TvPlaybackProgress? fromJson(Map<String, Object?> json) {
    return TvPlaybackProgress.fromValues(
      key: (json['key'] ?? '').toString(),
      positionMillis: _safeNonNegativeInt(json['positionMillis']) ?? -1,
      credibleWatchedMillis: _safeNonNegativeInt(json['credibleWatchedMillis']),
      durationMillis: _safePositiveInt(json['durationMillis']),
      updatedAtMillis: _safeNonNegativeInt(json['updatedAtMillis']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      'positionMillis': positionMillis,
      if (credibleWatchedMillis != null)
        'credibleWatchedMillis': credibleWatchedMillis,
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

String _newLibraryListId(Iterable<TvLibraryList> lists, int nowMillis) {
  final existingIds = lists.map((list) => list.id).toSet();
  var candidate = 'list-$nowMillis';
  var suffix = 2;
  while (existingIds.contains(candidate)) {
    candidate = 'list-$nowMillis-$suffix';
    suffix += 1;
  }
  return candidate;
}

String _normalizeLibraryListName(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return 'Untitled list';
  return normalized.length <= 48 ? normalized : normalized.substring(0, 48);
}

List<String> _dedupeLibraryListItemKeys(Iterable<Object?> values) {
  final seen = <String>{};
  final itemKeys = <String>[];
  for (final value in values) {
    final key = _safeString(value);
    if (key == null || !seen.add(key)) continue;
    itemKeys.add(key);
    if (itemKeys.length >= _maxLibraryListItems) break;
  }
  return itemKeys;
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
    'poster': snapshot?.poster,
    'background': snapshot?.background,
    'logo': snapshot?.logo,
    if (snapshot?.year != null) 'year': snapshot!.year,
    'releaseDate': null,
    'tmdb_id': snapshot?.tmdbId,
    'imdb_id': snapshot?.imdbId,
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
  if (normalized == 'series') return 'series';
  if (normalized == 'animation') return 'animation';
  if (normalized == 'live' ||
      normalized == 'tv' ||
      normalized == 'livetv' ||
      normalized == 'live_tv' ||
      normalized == 'channel') {
    return 'live';
  }
  return 'movie';
}

String? _baseItemKeyFromPlaybackKey(
  String playbackKey,
  Iterable<String> itemKeys,
) {
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
  final tmdbId = _safePositiveInt(
    item['tmdbId'] ?? item['tmdb_id'] ?? item['moviedb_id'],
  );
  return TvRecentItemSnapshot(
    key: _canonicalImportedItemKey(type: type, id: id, tmdbId: tmdbId),
    itemId: id,
    itemType: type,
    title: title,
    year: _safeString(item['year']),
    poster: _safeString(item['poster'] ?? item['posterUrl'] ?? item['image']),
    background: _safeString(
        item['background'] ?? item['backdrop'] ?? item['backdropUrl']),
    logo: _safeString(item['logo'] ?? item['logoUrl'] ?? item['titleLogo']),
    tmdbId: tmdbId,
    imdbId: _safeString(item['imdbId'] ?? item['imdb_id']),
    updatedAtMillis: updatedAtMillis ??
        _safeNonNegativeInt(item['updatedAtMillis']) ??
        _strictMobileTimestamp(item['updatedAt'])?.millisecondsSinceEpoch ??
        0,
  );
}

String _canonicalSnapshotKey(TvRecentItemSnapshot item) {
  final type = _normalizeMobileType(item.itemType);
  final itemId = _safeString(item.itemId);
  if (type == 'live') return itemId == null ? item.key : 'live:$itemId';
  final tmdbId = _safePositiveInt(item.tmdbId);
  return tmdbId == null ? item.key : '$type:tmdb:$tmdbId';
}

TvRecentItemSnapshot _snapshotWithKey(
  TvRecentItemSnapshot item,
  String key,
) {
  return TvRecentItemSnapshot(
    key: key,
    itemId: item.itemId,
    itemType: item.itemType,
    title: item.title,
    year: item.year,
    poster: item.poster,
    background: item.background,
    logo: item.logo,
    tmdbId: item.tmdbId,
    imdbId: item.imdbId,
    updatedAtMillis: item.updatedAtMillis,
  );
}

TvRecentItemSnapshot _mergeRecentSnapshots(
  TvRecentItemSnapshot first,
  TvRecentItemSnapshot second,
) {
  final newer = second.updatedAtMillis >= first.updatedAtMillis ? second : first;
  final older = identical(newer, second) ? first : second;
  return TvRecentItemSnapshot(
    key: newer.key,
    itemId: newer.itemId ?? older.itemId,
    itemType: newer.itemType ?? older.itemType,
    title: newer.title ?? older.title,
    year: newer.year ?? older.year,
    poster: newer.poster ?? older.poster,
    background: newer.background ?? older.background,
    logo: newer.logo ?? older.logo,
    tmdbId: newer.tmdbId ?? older.tmdbId,
    imdbId: newer.imdbId ?? older.imdbId,
    updatedAtMillis: newer.updatedAtMillis,
  );
}

DateTime? _strictMobileTimestamp(Object? rawValue) {
  final value = _safeString(rawValue);
  if (value == null) return null;
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
    r'(?:\.(\d{1,6}))?(?:Z|([+-])(\d{2}):(\d{2}))?$',
  ).firstMatch(value);
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final offsetHour = int.tryParse(match.group(9) ?? '0') ?? 0;
  final offsetMinute = int.tryParse(match.group(10) ?? '0') ?? 0;
  if (year < 1 ||
      month < 1 ||
      month > 12 ||
      hour > 23 ||
      minute > 59 ||
      second > 59 ||
      offsetHour > 23 ||
      offsetMinute > 59) {
    return null;
  }
  final nextMonth = month == 12
      ? DateTime.utc(year + 1, 1, 1)
      : DateTime.utc(year, month + 1, 1);
  final maxDay = nextMonth.subtract(const Duration(days: 1)).day;
  if (day < 1 || day > maxDay) return null;
  return DateTime.tryParse(value);
}

({TvRecentItemSnapshot snapshot, TvPlaybackProgress progress})?
    _progressFromMobileEntry(
  Map<String, Object?> entry, {
  required bool completed,
}) {
  final key = _safeString(entry['key']);
  final item = entry['item'];
  if (key == null || item is! Map) return null;
  final updatedAt = _strictMobileTimestamp(
        completed ? entry['completedAt'] : entry['updatedAt'],
      ) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final snapshot = _snapshotFromMobileItem(
    Map<String, Object?>.from(item),
    updatedAtMillis: updatedAt.millisecondsSinceEpoch,
  );
  if (snapshot == null) return null;
  final playbackKey = _tvPlaybackKeyFromMobileProgressKey(snapshot, key);
  final watchedSeconds = _safeNonNegativeInt(entry['watchedSeconds']) ?? 0;
  final credibleWatchedSeconds =
      _safeNonNegativeInt(entry['credibleWatchedSeconds']);
  final durationSeconds = _safePositiveInt(entry['durationSeconds']);
  final progress = TvPlaybackProgress.fromValues(
    key: playbackKey,
    positionMillis: watchedSeconds * 1000,
    credibleWatchedMillis:
        credibleWatchedSeconds == null ? null : credibleWatchedSeconds * 1000,
    durationMillis: durationSeconds == null ? null : durationSeconds * 1000,
    updatedAtMillis: updatedAt.millisecondsSinceEpoch,
  );
  if (progress == null) return null;
  return (snapshot: snapshot, progress: progress);
}

String _tvPlaybackKeyFromMobileProgressKey(
  TvRecentItemSnapshot snapshot,
  String mobileKey,
) {
  final itemKey = snapshot.key;
  final itemId = snapshot.itemId?.trim() ?? '';
  final itemType = _normalizeMobileType(snapshot.itemType);
  final legacyTypedItemKey = itemId.isEmpty ? '' : '$itemType:$itemId';
  final key = mobileKey.trim();
  if (key.isEmpty) return itemKey;
  if (key == itemKey || key.startsWith('$itemKey:')) return key;
  if (legacyTypedItemKey.isNotEmpty) {
    if (key == legacyTypedItemKey) return itemKey;
    if (key.startsWith('$legacyTypedItemKey:')) {
      return '$itemKey:${key.substring(legacyTypedItemKey.length + 1)}';
    }
  }
  if (itemId.isNotEmpty) {
    if (key == itemId) return itemKey;
    if (key.startsWith('$itemId:')) {
      return '$itemKey:${key.substring(itemId.length + 1)}';
    }
  }
  final parts = key.split(':');
  if (parts.length >= 3) {
    final season = int.tryParse(parts[parts.length - 2]);
    final episode = int.tryParse(parts.last);
    if (season != null && season > 0 && episode != null && episode > 0) {
      return '$itemKey:$season:$episode';
    }
  }
  return itemKey;
}

String _canonicalImportedItemKey({
  required String type,
  required String id,
  required int? tmdbId,
}) {
  if (type == 'live' || tmdbId == null) return '$type:$id';
  return '$type:tmdb:$tmdbId';
}
