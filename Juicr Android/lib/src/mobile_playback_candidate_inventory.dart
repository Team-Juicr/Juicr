enum MobilePlaybackCandidateFamily {
  addOn('addon'),
  builtIn('builtin'),
  fallback('fallback');

  const MobilePlaybackCandidateFamily(this.wireValue);

  final String wireValue;
}

class MobilePlaybackCandidate<T> {
  const MobilePlaybackCandidate({
    required this.value,
    required this.identity,
    required this.generation,
    required this.family,
    required this.rank,
  });

  final T value;
  final String identity;
  final int generation;
  final MobilePlaybackCandidateFamily family;
  final int rank;
}

class MobilePlaybackCandidateInventory<T> {
  const MobilePlaybackCandidateInventory({
    required this.entries,
    this.active,
  });

  final List<MobilePlaybackCandidate<T>> entries;
  final MobilePlaybackCandidate<T>? active;
}

String mobileOpaquePlaybackCandidateId({
  required int generation,
  required MobilePlaybackCandidateFamily family,
  required int sourceOrdinal,
}) {
  if (generation <= 0 || sourceOrdinal < 0) return '';
  return 'g$generation-${family.wireValue}-${sourceOrdinal + 1}';
}

final RegExp _safeCandidateIdentity = RegExp(
  r'^g[1-9][0-9]*-(?:addon|builtin|fallback)-[1-9][0-9]*$',
);

MobilePlaybackCandidateInventory<T> mergeMobilePlaybackCandidateInventory<T>({
  required int generation,
  required List<MobilePlaybackCandidate<T>> fresh,
  required List<MobilePlaybackCandidate<T>> retained,
  String? activeIdentity,
  Set<String> rejectedIdentities = const <String>{},
  int maxAddOn = 8,
  int maxBuiltIn = 8,
  int maxFallback = 1,
}) {
  if (generation <= 0) {
    return const MobilePlaybackCandidateInventory(entries: []);
  }

  final all = <MobilePlaybackCandidate<T>>[...fresh, ...retained];
  if (all.any(
    (candidate) =>
        candidate.generation != generation ||
        candidate.identity.length > 80 ||
        !_safeCandidateIdentity.hasMatch(candidate.identity),
  )) {
    return const MobilePlaybackCandidateInventory(entries: []);
  }

  final unique = <String, MobilePlaybackCandidate<T>>{};
  for (final candidate in all) {
    unique.putIfAbsent(candidate.identity, () => candidate);
  }

  final active = activeIdentity == null ? null : unique[activeIdentity];
  final ordered = unique.values
      .where((candidate) => !rejectedIdentities.contains(candidate.identity))
      .toList(growable: false)
    ..sort((left, right) {
      final rankOrder = left.rank.compareTo(right.rank);
      if (rankOrder != 0) return rankOrder;
      return left.identity.compareTo(right.identity);
    });

  final limits = <MobilePlaybackCandidateFamily, int>{
    MobilePlaybackCandidateFamily.addOn: maxAddOn < 0 ? 0 : maxAddOn,
    MobilePlaybackCandidateFamily.builtIn: maxBuiltIn < 0 ? 0 : maxBuiltIn,
    MobilePlaybackCandidateFamily.fallback: maxFallback < 0 ? 0 : maxFallback,
  };
  final counts = <MobilePlaybackCandidateFamily, int>{};
  final entries = <MobilePlaybackCandidate<T>>[];
  for (final candidate in ordered) {
    final count = counts[candidate.family] ?? 0;
    if (count >= limits[candidate.family]!) continue;
    entries.add(candidate);
    counts[candidate.family] = count + 1;
  }

  return MobilePlaybackCandidateInventory<T>(
    entries: List<MobilePlaybackCandidate<T>>.unmodifiable(entries),
    active: active,
  );
}
