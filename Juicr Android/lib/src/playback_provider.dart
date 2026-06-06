enum PlaybackSourceClass { direct, debrid, external, p2p, unsupported }

extension PlaybackSourceClassInfo on PlaybackSourceClass {
  String get wireName {
    return switch (this) {
      PlaybackSourceClass.direct => 'direct',
      PlaybackSourceClass.debrid => 'debrid',
      PlaybackSourceClass.external => 'external',
      PlaybackSourceClass.p2p => 'p2p',
      PlaybackSourceClass.unsupported => 'unsupported',
    };
  }

  String get label {
    return switch (this) {
      PlaybackSourceClass.direct => 'Direct stream',
      PlaybackSourceClass.debrid => 'Cached stream',
      PlaybackSourceClass.external => 'External stream',
      PlaybackSourceClass.p2p => 'P2P source',
      PlaybackSourceClass.unsupported => 'Unsupported source',
    };
  }

  static PlaybackSourceClass fromWireName(String? value) {
    return switch ((value ?? '').trim().toLowerCase()) {
      'debrid' || 'cached' => PlaybackSourceClass.debrid,
      'external' || 'embed' => PlaybackSourceClass.external,
      'p2p' || 'torrent' => PlaybackSourceClass.p2p,
      'unsupported' => PlaybackSourceClass.unsupported,
      _ => PlaybackSourceClass.direct,
    };
  }
}

class ApiProvider {
  const ApiProvider({
    required this.id,
    required this.name,
    this.enabled = true,
  });

  factory ApiProvider.fromJson(Map<String, dynamic> json) {
    return ApiProvider(
      id: (json['id'] ?? json['provider'] ?? '').toString(),
      name: (json['name'] ?? json['label'] ?? json['id'] ?? 'Provider')
          .toString(),
      enabled: json['enabled'] != false,
    );
  }

  final String id;
  final String name;
  final bool enabled;
}

class PlaybackCandidate {
  const PlaybackCandidate({
    required this.providerId,
    required this.name,
    required this.url,
  });

  factory PlaybackCandidate.fromJson(Map<String, dynamic> json) {
    final providerId = (json['provider'] ?? json['id'] ?? '').toString();
    return PlaybackCandidate(
      providerId: providerId,
      name: (json['name'] ?? providerId).toString(),
      url: (json['url'] ?? '').toString(),
    );
  }

  final String providerId;
  final String name;
  final String url;
}

class TrailerItem {
  const TrailerItem({
    required this.providerId,
    required this.name,
    required this.title,
    required this.url,
  });

  factory TrailerItem.fromJson(Map<String, dynamic> json) {
    final providerId = (json['provider'] ?? json['id'] ?? 'trailer').toString();
    return TrailerItem(
      providerId: providerId,
      name: (json['name'] ?? providerId).toString(),
      title: (json['title'] ?? json['name'] ?? 'Trailer').toString(),
      url: (json['url'] ?? '').toString(),
    );
  }

  final String providerId;
  final String name;
  final String title;
  final String url;

  PlaybackCandidate toPlaybackCandidate() {
    return PlaybackCandidate(providerId: providerId, name: name, url: url);
  }
}

class PlaybackSource {
  const PlaybackSource({
    required this.providerId,
    required this.name,
    required this.url,
    this.type,
    this.quality,
    this.sourceClass = PlaybackSourceClass.direct,
    this.headers = const <String, String>{},
    this.subtitles = const <PlaybackSubtitle>[],
    this.drm,
  });

  factory PlaybackSource.fromJson(Map<String, dynamic> json) {
    final providerId =
        (json['provider'] ??
                json['providerId'] ??
                json['provider_id'] ??
                json['id'] ??
                '')
            .toString();
    return PlaybackSource(
      providerId: providerId,
      name: (json['name'] ?? providerId).toString(),
      url: (json['url'] ?? '').toString(),
      type: json['type']?.toString(),
      quality: json['quality']?.toString(),
      sourceClass: PlaybackSourceClassInfo.fromWireName(
        (json['sourceClass'] ?? json['source_class'])?.toString(),
      ),
      headers: _stringMap(json['headers']),
      subtitles: _mapList(
        json['subtitles'],
        PlaybackSubtitle.fromJson,
      ).where((subtitle) => subtitle.url.isNotEmpty).toList(),
      drm: PlaybackDrm.fromJson(json['drm']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'provider': providerId,
      'name': name,
      'url': sourceClass == PlaybackSourceClass.p2p ? '[p2p-hidden]' : url,
      if (type != null && type!.isNotEmpty) 'type': type,
      if (quality != null && quality!.isNotEmpty) 'quality': quality,
      'sourceClass': sourceClass.wireName,
      if (headers.isNotEmpty) 'headers': headers,
      if (subtitles.isNotEmpty)
        'subtitles': subtitles.map((subtitle) => subtitle.toJson()).toList(),
      if (drm?.isPresent == true) 'drm': drm!.toSafeJson(),
    };
  }

  final String providerId;
  final String name;
  final String url;
  final String? type;
  final String? quality;
  final PlaybackSourceClass sourceClass;
  final Map<String, String> headers;
  final List<PlaybackSubtitle> subtitles;
  final PlaybackDrm? drm;

  bool get hasProtectedDrm => drm?.isPlayableClearKey == true;

  PlaybackSource copyWith({
    String? providerId,
    String? name,
    String? url,
    String? type,
    String? quality,
    PlaybackSourceClass? sourceClass,
    Map<String, String>? headers,
    List<PlaybackSubtitle>? subtitles,
    PlaybackDrm? drm,
  }) {
    return PlaybackSource(
      providerId: providerId ?? this.providerId,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type ?? this.type,
      quality: quality ?? this.quality,
      sourceClass: sourceClass ?? this.sourceClass,
      headers: headers ?? this.headers,
      subtitles: subtitles ?? this.subtitles,
      drm: drm ?? this.drm,
    );
  }
}

class PlaybackDrm {
  const PlaybackDrm({
    required this.scheme,
    required this.present,
    this.clearKey,
  });

  factory PlaybackDrm.fromJson(dynamic value) {
    if (value is! Map) return const PlaybackDrm(scheme: '', present: false);
    return PlaybackDrm(
      scheme: (value['scheme'] ?? value['type'] ?? '').toString(),
      present: value['present'] == true || value['clearKey'] != null,
      clearKey: value['clearKey']?.toString(),
    );
  }

  final String scheme;
  final bool present;
  final String? clearKey;

  bool get isPresent => present || (clearKey?.trim().isNotEmpty ?? false);

  bool get isPlayableClearKey =>
      scheme.trim().toLowerCase() == 'clearkey' &&
      (clearKey?.trim().isNotEmpty ?? false);

  Map<String, dynamic> toSafeJson() {
    return <String, dynamic>{'scheme': scheme, 'present': isPresent};
  }
}

class VisiblePlaybackSourceGroup {
  const VisiblePlaybackSourceGroup({
    required this.primary,
    required this.variants,
  });

  final PlaybackSource primary;
  final List<PlaybackSource> variants;
}

class PlaybackSubtitle {
  const PlaybackSubtitle({
    required this.id,
    required this.label,
    required this.language,
    required this.url,
    this.format = 'vtt',
    this.isDefault = false,
    this.isForced = false,
  });

  factory PlaybackSubtitle.fromJson(Map<String, dynamic> json) {
    final language = (json['language'] ?? json['lang'] ?? '').toString();
    final label = (json['label'] ?? json['name'] ?? language).toString();
    return PlaybackSubtitle(
      id: (json['id'] ?? json['subtitleId'] ?? language.ifEmpty(label))
          .toString(),
      label: label.isEmpty ? 'Subtitle' : label,
      language: language,
      url: (json['url'] ?? json['src'] ?? '').toString(),
      format: (json['format'] ?? 'vtt').toString(),
      isDefault: json['isDefault'] == true || json['default'] == true,
      isForced: json['isForced'] == true || json['forced'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'language': language,
      'url': url,
      'format': format,
      'isDefault': isDefault,
      'isForced': isForced,
    };
  }

  final String id;
  final String label;
  final String language;
  final String url;
  final String format;
  final bool isDefault;
  final bool isForced;
}

extension _SubtitleString on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class PlaybackResult {
  const PlaybackResult({
    required this.sources,
    required this.embeds,
    required this.debug,
    this.retryAfterSeconds = 0,
    this.unavailableReason,
  });

  factory PlaybackResult.fromJson(Map<String, dynamic> json) {
    return PlaybackResult(
      sources: _mapList(
        json['sources'],
        PlaybackSource.fromJson,
      ).where((source) => source.url.isNotEmpty).toList(),
      embeds: _mapList(
        json['embeds'],
        PlaybackCandidate.fromJson,
      ).where((candidate) => candidate.url.isNotEmpty).toList(),
      debug: PlaybackDebug.fromJson(json['debug']),
      retryAfterSeconds:
          int.tryParse((json['retryAfterSeconds'] ?? '').toString()) ?? 0,
      unavailableReason: json['unavailableReason']?.toString(),
    );
  }

  final List<PlaybackSource> sources;
  final List<PlaybackCandidate> embeds;
  final PlaybackDebug debug;
  final int retryAfterSeconds;
  final String? unavailableReason;

  bool get hasDirectSources => sources.isNotEmpty;

  PlaybackResult copyWith({
    List<PlaybackSource>? sources,
    List<PlaybackCandidate>? embeds,
    PlaybackDebug? debug,
    int? retryAfterSeconds,
    String? unavailableReason,
  }) {
    return PlaybackResult(
      sources: sources ?? this.sources,
      embeds: embeds ?? this.embeds,
      debug: debug ?? this.debug,
      retryAfterSeconds: retryAfterSeconds ?? this.retryAfterSeconds,
      unavailableReason: unavailableReason ?? this.unavailableReason,
    );
  }
}

class PlaybackDebug {
  const PlaybackDebug({
    required this.sourceValidationEnabled,
    required this.sourceValidationPassed,
  });

  factory PlaybackDebug.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return empty;
    final validation = json['validation'];
    if (validation is! Map<String, dynamic>) return empty;

    final passed = validation['passed'];
    return PlaybackDebug(
      sourceValidationEnabled: validation['enabled'] == true,
      sourceValidationPassed: passed is num && passed > 0,
    );
  }

  static const empty = PlaybackDebug(
    sourceValidationEnabled: false,
    sourceValidationPassed: false,
  );

  final bool sourceValidationEnabled;
  final bool sourceValidationPassed;
}

String playbackQualityLabel(PlaybackSource? source) {
  final raw = source?.quality?.trim();
  if (raw == null || raw.isEmpty || raw.toLowerCase() == 'auto') {
    return 'Auto';
  }
  final normalized = raw.toLowerCase();
  final resolutionMatch = RegExp(r'\b(\d{3,4})\s*p\b').firstMatch(normalized);
  if (resolutionMatch != null) {
    return '${resolutionMatch.group(1)}P';
  }
  if (RegExp(
    r'\b(4320|2160|1440|1080|800|720|674|534|480|452|360|336|266|240)\b',
  ).hasMatch(normalized)) {
    final value = RegExp(
      r'\b(4320|2160|1440|1080|800|720|674|534|480|452|360|336|266|240)\b',
    ).firstMatch(normalized)!.group(1);
    return '${value}P';
  }
  if (normalized.contains('8k')) return '4320P';
  if (normalized.contains('4k') || normalized.contains('uhd')) return '4K';
  if (normalized.contains('fhd')) return '1080P';
  if (normalized.contains('hd')) return '720P';
  return 'Auto';
}

int playbackQualityRank(String label) {
  final normalized = label.toLowerCase();
  if (normalized == '8k') return 4320;
  if (normalized == '4k') return 2160;
  final match = RegExp(r'(\d{3,4})').firstMatch(normalized);
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}

String? playbackSourceLanguageLabel(PlaybackSource source) {
  final haystack = '${source.name} ${source.quality ?? ''} ${source.url}'
      .toLowerCase();
  const candidates = <String, String>{
    'english': 'English',
    ' eng ': 'English',
    '_eng': 'English',
    '-eng': 'English',
    'spanish': 'Spanish',
    'espanol': 'Spanish',
    'latino': 'Latino',
    'latin': 'Latino',
    'hindi': 'Hindi',
    'tamil': 'Tamil',
    'telugu': 'Telugu',
    'japanese': 'Japanese',
    'korean': 'Korean',
    'french': 'French',
    'german': 'German',
    'portuguese': 'Portuguese',
    'tagalog': 'Tagalog',
    'filipino': 'Filipino',
  };
  for (final entry in candidates.entries) {
    if (haystack.contains(entry.key)) return entry.value;
  }
  return null;
}

int playbackLanguageRank(String? language) {
  final normalized = language?.toLowerCase();
  if (normalized == 'english') return 0;
  if (normalized == null || normalized == 'unknown') return 1;
  return 2;
}

String? playbackCleanSourceName(PlaybackSource source) {
  final raw = source.name.trim();
  if (raw.isEmpty || raw == source.providerId) return null;
  final normalized = raw.toLowerCase();
  const noisyParts = <String>[
    'extracted source',
    'api source',
    'playlist source',
    'decrypted source',
    'cdn source',
    'browser extracted source',
  ];
  if (noisyParts.any(normalized.contains)) return null;
  return raw;
}

List<PlaybackSource> rankedPlaybackSources(List<PlaybackSource> sources) {
  final originalIndexByUrl = <String, int>{};
  for (var index = 0; index < sources.length; index++) {
    originalIndexByUrl.putIfAbsent(sources[index].url, () => index);
  }
  return sources.toList(growable: false)..sort((a, b) {
    final qualityCompare = playbackQualityRank(
      playbackQualityLabel(b),
    ).compareTo(playbackQualityRank(playbackQualityLabel(a)));
    if (qualityCompare != 0) return qualityCompare;
    final languageCompare = playbackLanguageRank(
      playbackSourceLanguageLabel(a),
    ).compareTo(playbackLanguageRank(playbackSourceLanguageLabel(b)));
    if (languageCompare != 0) return languageCompare;
    return (originalIndexByUrl[a.url] ?? 0).compareTo(
      originalIndexByUrl[b.url] ?? 0,
    );
  });
}

List<VisiblePlaybackSourceGroup> groupVisiblePlaybackSources(
  List<PlaybackSource> sources,
) {
  final groups = <VisiblePlaybackSourceGroup>[];
  final grouped = <String, List<PlaybackSource>>{};
  final seenUrls = <String>{};
  final rankedSources = rankedPlaybackSources(sources);
  final hasExplicitQuality = rankedSources.any(
    (source) => playbackQualityLabel(source) != 'Auto',
  );
  for (final source in rankedSources) {
    if (hasExplicitQuality && playbackQualityLabel(source) == 'Auto') continue;
    if (!seenUrls.add(source.url)) continue;
    final key =
        '${playbackQualityLabel(source)}|${playbackSourceLanguageLabel(source) ?? 'unknown'}|${source.sourceClass.wireName}';
    grouped.putIfAbsent(key, () => <PlaybackSource>[]).add(source);
  }
  for (final variants in grouped.values) {
    groups.add(
      VisiblePlaybackSourceGroup(primary: variants.first, variants: variants),
    );
  }
  return groups;
}

int visiblePlaybackSourceCount(List<PlaybackSource> sources) {
  return groupVisiblePlaybackSources(sources).length;
}

(int, int) visiblePlaybackSourceProgress(
  List<PlaybackSource> sources,
  int sourceIndex,
) {
  final groups = groupVisiblePlaybackSources(sources);
  if (groups.isEmpty) return (1, 0);
  if (groups.length == 1) return (1, 1);
  final clampedIndex = sourceIndex.clamp(0, sources.length - 1).toInt();
  final targetUrl = sources.isEmpty ? null : sources[clampedIndex].url;
  if (targetUrl == null || targetUrl.isEmpty) return (1, groups.length);
  final visibleIndex = groups.indexWhere(
    (group) => group.variants.any((source) => source.url == targetUrl),
  );
  return ((visibleIndex >= 0 ? visibleIndex : 0) + 1, groups.length);
}

String normalizeProviderId(String value) {
  return switch (value.trim().toLowerCase()) {
    'videasy' => 'alpha',
    'vidfast' => 'beta',
    'vidsrc' => 'beta',
    '111movies' => 'delta',
    'vidlink' => 'epsilon',
    _ => value.trim().toLowerCase(),
  };
}

List<T> _mapList<T>(
  dynamic value,
  T Function(Map<String, dynamic> json) convert,
) {
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().map(convert).toList();
}

Map<String, String> _stringMap(dynamic value) {
  if (value is! Map) return const <String, String>{};
  return {
    for (final entry in value.entries)
      if (entry.key != null && entry.value != null)
        entry.key.toString(): entry.value.toString(),
  };
}
