class TvPlaybackSourceGroupEntry {
  const TvPlaybackSourceGroupEntry({
    required this.sessionIndex,
    required this.quality,
    this.mirrorGroupId,
    this.mirrorRank,
    this.sourcePoolVersion,
  });

  final int sessionIndex;
  final String quality;
  final String? mirrorGroupId;
  final int? mirrorRank;
  final String? sourcePoolVersion;
}

class TvPlaybackSourceGroupResult {
  const TvPlaybackSourceGroupResult({
    required this.quality,
    required this.sessionIndexes,
  });

  final String quality;
  final List<int> sessionIndexes;
}

int tvPlaybackQualityChoiceIndex({
  required List<String> qualities,
  required int currentIndex,
  required String selected,
}) {
  if (qualities.isEmpty) return currentIndex;
  final boundedCurrent = currentIndex.clamp(0, qualities.length - 1);
  final normalizedSelection = selected.trim();
  final index = qualities.indexWhere(
    (quality) => quality.trim() == normalizedSelection,
  );
  return index < 0 ? boundedCurrent : index;
}

String tvPlaybackQualityBucket(String quality) {
  final normalized = quality.trim().toLowerCase();
  if (normalized == 'auto' ||
      normalized == 'automatic' ||
      normalized == 'adaptive') {
    return 'auto';
  }
  if (normalized.isEmpty || normalized == 'unknown') return 'unknown';
  if (normalized.contains('2160') ||
      RegExp(r'(^|\W)4k($|\W)').hasMatch(normalized) ||
      normalized.contains('uhd')) {
    return '2160';
  }
  if (normalized.contains('1440') ||
      RegExp(r'(^|\W)2k($|\W)').hasMatch(normalized) ||
      normalized.contains('qhd')) {
    return '1440';
  }
  final match = RegExp(r'(\d{3,4})').firstMatch(normalized);
  return match?.group(1) ?? normalized;
}

String tvPlaybackDisplayQuality(String quality) {
  final bucket = tvPlaybackQualityBucket(quality);
  if (bucket == 'auto') return 'Auto';
  if (bucket == 'unknown') return 'Unknown';
  if (bucket == '2160') return '4K';
  if (bucket == '1440') return '2K';
  final height = int.tryParse(bucket);
  return height == null ? quality.trim() : '${height}P';
}

List<String> tvPlaybackAvailableQualityLabels(List<String> qualities) {
  final labelsByBucket = <String, String>{};
  for (final quality in qualities) {
    final bucket = tvPlaybackQualityBucket(quality);
    if (bucket == 'auto' || bucket == 'unknown') continue;
    labelsByBucket.putIfAbsent(bucket, () => tvPlaybackDisplayQuality(quality));
  }
  final labels = labelsByBucket.values.toList(growable: false);
  return labels.toList()
    ..sort((left, right) => _qualityRank(right).compareTo(_qualityRank(left)));
}

List<int> tvPlaybackQualityCandidateOrder({
  required List<String> qualities,
  required int currentIndex,
  required String selected,
}) {
  if (qualities.isEmpty) return const <int>[];
  final selectedBucket = tvPlaybackQualityBucket(selected);
  return <int>[
    for (var index = 0; index < qualities.length; index++)
      if (tvPlaybackQualityBucket(qualities[index]) == selectedBucket) index,
  ];
}

List<TvPlaybackSourceGroupResult> groupTvPlaybackSources(
  List<TvPlaybackSourceGroupEntry> entries,
) {
  final grouped = <String, List<TvPlaybackSourceGroupEntry>>{};
  for (final entry in entries) {
    final mirrorGroupId = entry.mirrorGroupId?.trim() ?? '';
    final sourcePoolVersion = entry.sourcePoolVersion?.trim() ?? '';
    final hasTrustedPoolMetadata = _isSafePoolToken(mirrorGroupId) &&
        _isSafePoolToken(sourcePoolVersion);
    final key = !hasTrustedPoolMetadata
        ? 'session:${entry.sessionIndex}'
        : 'pool:$sourcePoolVersion|$mirrorGroupId';
    grouped.putIfAbsent(key, () => <TvPlaybackSourceGroupEntry>[]).add(entry);
  }
  final results = [
    for (final group in grouped.entries)
      TvPlaybackSourceGroupResult(
        quality: group.value.first.quality.trim().isEmpty
            ? 'Auto'
            : group.value.first.quality.trim(),
        sessionIndexes: (group.value.toList()
              ..sort((a, b) {
                final rank = (a.mirrorRank ?? 1 << 20).compareTo(
                  b.mirrorRank ?? 1 << 20,
                );
                return rank != 0
                    ? rank
                    : a.sessionIndex.compareTo(b.sessionIndex);
              }))
            .map((entry) => entry.sessionIndex)
            .toList(growable: false),
      ),
  ];
  results.sort((a, b) {
    final rank = _qualityRank(b.quality).compareTo(_qualityRank(a.quality));
    if (rank != 0) return rank;
    if (a.quality == 'Auto') return 1;
    if (b.quality == 'Auto') return -1;
    final label = a.quality.compareTo(b.quality);
    if (label != 0) return label;
    return a.sessionIndexes.first.compareTo(b.sessionIndexes.first);
  });
  return results;
}

bool _isSafePoolToken(String value) {
  if (value.isEmpty || value.length > 80) return false;
  return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);
}

int _qualityRank(String label) {
  return int.tryParse(tvPlaybackQualityBucket(label)) ?? 0;
}
