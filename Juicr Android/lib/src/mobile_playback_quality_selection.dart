String mobilePlaybackQualityBucket(String quality) {
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
  if (normalized.contains('fullhd') || normalized.contains('fhd')) {
    return '1080';
  }
  if (RegExp(r'(^|\W)hd($|\W)').hasMatch(normalized)) return '720';
  if (RegExp(r'(^|\W)sd($|\W)').hasMatch(normalized)) return '480';
  final match = RegExp(r'(\d{3,4})').firstMatch(normalized);
  final height = int.tryParse(match?.group(1) ?? '');
  return height == null
      ? normalized
      : _normalizedPlaybackQualityHeight(height).toString();
}

String mobilePlaybackDisplayQuality(String quality) {
  final bucket = mobilePlaybackQualityBucket(quality);
  if (bucket == 'auto') return 'Auto';
  if (bucket == 'unknown') return 'Unknown';
  if (bucket == '2160') return '4K';
  if (bucket == '1440') return '2K';
  final height = int.tryParse(bucket);
  return height == null ? quality.trim() : '${height}P';
}

bool mobilePlaybackHasAutomaticCandidate(Iterable<String> qualities) {
  return qualities.any(
    (quality) => mobilePlaybackQualityBucket(quality) == 'auto',
  );
}

List<String> mobilePlaybackAvailableQualityLabels(
  Iterable<String> qualities,
) {
  final labelsByBucket = <String, String>{};
  for (final quality in qualities) {
    final bucket = mobilePlaybackQualityBucket(quality);
    if (bucket == 'auto' || bucket == 'unknown') continue;
    labelsByBucket.putIfAbsent(
      bucket,
      () => mobilePlaybackDisplayQuality(quality),
    );
  }
  final labels = labelsByBucket.values.toList(growable: false);
  return labels.toList()
    ..sort((left, right) => _qualityRank(right).compareTo(_qualityRank(left)));
}

List<int> mobilePlaybackQualityCandidateIndexes({
  required List<String> qualities,
  required String selected,
}) {
  final bucket = mobilePlaybackQualityBucket(selected);
  return <int>[
    for (var index = 0; index < qualities.length; index++)
      if (mobilePlaybackQualityBucket(qualities[index]) == bucket) index,
  ];
}

int _qualityRank(String quality) {
  return int.tryParse(mobilePlaybackQualityBucket(quality)) ?? 0;
}

int _normalizedPlaybackQualityHeight(int height) {
  if (height >= 120 && height <= 170) return 144;
  if (height >= 220 && height <= 285) return 240;
  if (height >= 320 && height <= 390) return 360;
  if (height >= 430 && height <= 570) return 480;
  if (height >= 640 && height <= 820) return 720;
  if (height >= 1000 && height <= 1120) return 1080;
  if (height >= 1320 && height <= 1500) return 1440;
  if (height >= 1900 && height <= 2250) return 2160;
  if (height >= 3900 && height <= 4450) return 4320;
  return height;
}
