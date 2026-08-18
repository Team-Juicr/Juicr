enum TvPlaybackCandidateFamily {
  addOn('addon'),
  builtIn('builtin'),
  fallback('fallback');

  const TvPlaybackCandidateFamily(this.wireValue);

  final String wireValue;
}

TvPlaybackCandidateFamily? tvPlaybackCandidateFamilyFromWire(Object? value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  for (final family in TvPlaybackCandidateFamily.values) {
    if (family.wireValue == normalized) return family;
  }
  return null;
}

String tvOpaquePlaybackCandidateId({
  required int generation,
  required TvPlaybackCandidateFamily family,
  required int sourceOrdinal,
}) {
  if (generation <= 0 || sourceOrdinal < 0) return '';
  return 'g$generation-${family.wireValue}-${sourceOrdinal + 1}';
}

bool tvPlaybackCandidateIdentityIsSafe(String identity) {
  final normalized = identity.trim();
  if (normalized.isEmpty || normalized.length > 80) return false;
  return RegExp(r'^g[1-9][0-9]*-(addon|builtin|fallback)-[1-9][0-9]*$')
      .hasMatch(normalized);
}

List<R> tvTagPlaybackCandidateInventory<T, R>(
  List<T> candidates, {
  required int generation,
  required TvPlaybackCandidateFamily family,
  required R Function(
    T candidate,
    String identity,
    int poolGeneration,
    TvPlaybackCandidateFamily family,
  ) tag,
}) {
  if (generation <= 0 || candidates.isEmpty) return <R>[];
  return [
    for (final entry in candidates.indexed)
      tag(
        entry.$2,
        tvOpaquePlaybackCandidateId(
          generation: generation,
          family: family,
          sourceOrdinal: entry.$1,
        ),
        generation,
        family,
      ),
  ];
}

List<T> tvDeterministicRankedPlaybackCandidateOrder<T>(
  List<T> candidates, {
  required int Function(T candidate) rankOf,
  required String Function(T candidate) identityOf,
}) {
  final indexed = candidates.indexed.toList(growable: false);
  indexed.sort((left, right) {
    final rankComparison = rankOf(left.$2).compareTo(rankOf(right.$2));
    if (rankComparison != 0) return rankComparison;
    final leftIdentity = identityOf(left.$2).trim();
    final rightIdentity = identityOf(right.$2).trim();
    final leftTrusted = tvPlaybackCandidateIdentityIsSafe(leftIdentity);
    final rightTrusted = tvPlaybackCandidateIdentityIsSafe(rightIdentity);
    if (leftTrusted && rightTrusted) {
      final identityComparison = leftIdentity.compareTo(rightIdentity);
      if (identityComparison != 0) return identityComparison;
    } else if (leftTrusted != rightTrusted) {
      return leftTrusted ? -1 : 1;
    }
    return left.$1.compareTo(right.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

int tvPlaybackCandidateRank({
  required String engine,
  required String type,
  required String quality,
  required int compatibilityRisk,
}) {
  final normalizedType = type.trim().toLowerCase();
  if (normalizedType.contains('hls') ||
      normalizedType.contains('m3u8') ||
      normalizedType.contains('dash') ||
      normalizedType.contains('mpd')) {
    return 0;
  }
  final normalizedQuality = quality.trim().toLowerCase();
  if (engine == 'Native') {
    final boundedRisk = compatibilityRisk.clamp(0, 20);
    if (normalizedQuality.contains('1080')) return 10 + boundedRisk;
    if (normalizedQuality.contains('720')) return 11 + boundedRisk;
    if (normalizedQuality.contains('480') ||
        normalizedQuality.contains('576') ||
        normalizedQuality.contains('360')) {
      return 12 + boundedRisk;
    }
    if (normalizedQuality == 'auto') return 13 + boundedRisk;
    if (normalizedQuality.contains('2160') ||
        normalizedQuality.contains('4k') ||
        normalizedQuality.contains('uhd')) {
      return 14 + boundedRisk;
    }
    return 15 + boundedRisk;
  }
  if (normalizedQuality.contains('2160') ||
      normalizedQuality.contains('4k') ||
      normalizedQuality.contains('uhd')) {
    return 10;
  }
  if (normalizedQuality.contains('1080')) return 11;
  if (normalizedQuality.contains('720')) return 12;
  if (normalizedQuality.contains('480') ||
      normalizedQuality.contains('576') ||
      normalizedQuality.contains('360')) {
    return 13;
  }
  if (normalizedQuality == 'auto') return 14;
  return 15;
}

int tvPlaybackPreferenceCandidateRank({
  required String engine,
  required String preferredQuality,
  required String type,
  required String quality,
  required int compatibilityRisk,
}) {
  final rankingEngine = preferredQuality == 'Best available'
      ? engine
      : 'Native';
  return tvPlaybackCandidateRank(
    engine: rankingEngine,
    type: type,
    quality: quality,
    compatibilityRisk: compatibilityRisk,
  );
}

List<T> tvBoundedPlaybackCandidateOrder<T>(
  List<T> ordered, {
  required int maxCount,
  required bool includeP2pFallback,
  required bool Function(T candidate) isP2p,
}) {
  if (maxCount <= 0 || ordered.isEmpty) return <T>[];
  if (ordered.length <= maxCount) return List<T>.from(ordered);
  final bounded = ordered.take(maxCount).toList(growable: true);
  if (!includeP2pFallback || bounded.any(isP2p)) return bounded;
  T? fallback;
  for (final candidate in ordered.skip(maxCount)) {
    if (!isP2p(candidate)) continue;
    fallback = candidate;
    break;
  }
  if (fallback == null) return bounded;
  bounded[bounded.length - 1] = fallback;
  return bounded;
}

int tvPlaybackCandidateAttemptBudget({int? requestedMaxCount}) {
  const hardLimit = 4;
  if (requestedMaxCount == null) return hardLimit;
  return requestedMaxCount.clamp(0, hardLimit);
}

List<T> tvBoundedRankedPlaybackCandidateOrder<T>(
  List<T> candidates, {
  required int maxCount,
  required bool includeP2pFallback,
  required bool Function(T candidate) isP2p,
  required int Function(T candidate) rankOf,
}) {
  final indexed = candidates.indexed.toList(growable: false)
    ..sort((left, right) {
      final rankComparison = rankOf(left.$2).compareTo(rankOf(right.$2));
      return rankComparison != 0 ? rankComparison : left.$1.compareTo(right.$1);
    });
  return tvBoundedPlaybackCandidateOrder(
    indexed.map((entry) => entry.$2).toList(growable: false),
    maxCount: maxCount,
    includeP2pFallback: includeP2pFallback,
    isP2p: isP2p,
  );
}

List<T> tvBoundedRetainedCandidateMerge<T>({
  required List<T> fresh,
  required List<T> cached,
  required String Function(T candidate) identityOf,
  required bool Function(T candidate) isAddOn,
  required bool Function(T candidate) isFallback,
  int maxAddOn = 8,
  int maxBuiltIn = 8,
  int maxFallback = 1,
}) {
  final seen = <String>{};
  final merged = <T>[];
  var addOnCount = 0;
  var builtInCount = 0;
  var fallbackCount = 0;

  void add(T candidate) {
    final identity = identityOf(candidate).trim();
    if (identity.isEmpty || !seen.add(identity)) return;
    if (isFallback(candidate)) {
      if (fallbackCount >= maxFallback) return;
      fallbackCount += 1;
    } else if (isAddOn(candidate)) {
      if (addOnCount >= maxAddOn) return;
      addOnCount += 1;
    } else {
      if (builtInCount >= maxBuiltIn) return;
      builtInCount += 1;
    }
    merged.add(candidate);
  }

  for (final candidate in fresh) {
    add(candidate);
  }
  for (final candidate in cached) {
    add(candidate);
  }
  return merged;
}

bool tvPlaybackCandidateInventoryChanged({
  required List<String> previousIdentities,
  required List<String> nextIdentities,
}) {
  if (previousIdentities.length != nextIdentities.length) return true;
  for (var index = 0; index < previousIdentities.length; index += 1) {
    if (previousIdentities[index] != nextIdentities[index]) return true;
  }
  return false;
}

int? tvPlaybackCandidateIndexForIdentity({
  required List<String> identities,
  required String identity,
}) {
  final normalized = identity.trim();
  if (normalized.isEmpty) return null;
  final index = identities.indexOf(normalized);
  return index < 0 ? null : index;
}

int tvP2pPlaybackCandidateRank({
  required String mode,
  required String quality,
  required String label,
  int trackerCount = 0,
  required bool avoidRiskyFormats,
  required int sizeLimitMb,
}) {
  final text = '$quality $label'.toLowerCase();
  final risky = avoidRiskyFormats &&
      (text.contains(' cam') ||
          text.contains('cam ') ||
          text.contains('telesync') ||
          text.contains('telecine') ||
          text.contains(' ts ') ||
          text.contains(' scr'));
  final riskyPenalty = risky ? 8 : 0;
  final qualityRank = text.contains('2160') ||
          text.contains('4k') ||
          text.contains('uhd')
      ? 0
      : text.contains('1080')
          ? 1
          : text.contains('720')
              ? 2
              : text.contains('480')
                  ? 3
                  : 4;
  final sizeMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(gb|mb)').firstMatch(text);
  final sizeMb = sizeMatch == null
      ? null
      : (double.tryParse(sizeMatch.group(1) ?? '') ?? 0) *
          (sizeMatch.group(2) == 'gb' ? 1024 : 1);
  final sizeRank = sizeMb == null
      ? 2
      : sizeLimitMb > 0 && sizeMb > sizeLimitMb
          ? 10
          : sizeMb <= 1400
              ? 0
              : sizeMb <= 4096
                  ? 1
                  : sizeMb <= 8192
                      ? 2
                      : 3;
  final seeders = _tvP2pSeederCount(text);
  final seederHealth = switch (seeders ?? -1) {
    >= 200 => 5,
    >= 75 => 4,
    >= 20 => 3,
    >= 5 => 2,
    >= 1 => 1,
    _ => 0,
  };
  final healthRank = seederHealth + trackerCount.clamp(0, 3);
  final openabilityPenalty = trackerCount > 0 ? 0 : 12;
  return switch (mode) {
    'qualityFirst' =>
      (qualityRank * 8) + (riskyPenalty * 4) - healthRank,
    'availabilityFirst' =>
      openabilityPenalty + (riskyPenalty * 4) - (healthRank * 4),
    'smallerFasterFiles' =>
      openabilityPenalty + (sizeRank * 8) + (riskyPenalty * 4) - healthRank,
    'balancedQualityAvailability' =>
      openabilityPenalty +
          (qualityRank * 4) +
          (sizeRank * 3) +
          (riskyPenalty * 4) -
          (healthRank * 2),
    _ => openabilityPenalty +
        (riskyPenalty * 4) +
        (qualityRank * 3) -
        (healthRank * 2),
  };
}

int? _tvP2pSeederCount(String text) {
  final patterns = <RegExp>[
    RegExp(r'\b(?:s|seeds?|seeders?)\s*[:=]\s*(\d{1,6})\b'),
    RegExp(r'\b(\d{1,6})\s*(?:seeds?|seeders?)\b'),
    RegExp(r'\b(\d{1,6})\s*/\s*\d{1,6}\b'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    final value = int.tryParse(match.group(1) ?? '');
    if (value != null) return value;
  }
  return null;
}
