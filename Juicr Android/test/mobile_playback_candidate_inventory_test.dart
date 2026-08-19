import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/mobile_playback_candidate_inventory.dart';

MobilePlaybackCandidate<String> candidate(
  String value, {
  required int generation,
  required MobilePlaybackCandidateFamily family,
  required int ordinal,
  int rank = 0,
}) {
  return MobilePlaybackCandidate<String>(
    value: value,
    identity: mobileOpaquePlaybackCandidateId(
      generation: generation,
      family: family,
      sourceOrdinal: ordinal,
    ),
    generation: generation,
    family: family,
    rank: rank,
  );
}

void main() {
  test('retained inventory enforces 8 add-on 8 built-in and 1 fallback', () {
    final fresh = <MobilePlaybackCandidate<String>>[
      for (var index = 0; index < 10; index += 1)
        candidate(
          'addon-$index',
          generation: 7,
          family: MobilePlaybackCandidateFamily.addOn,
          ordinal: index,
          rank: index,
        ),
      for (var index = 0; index < 10; index += 1)
        candidate(
          'builtin-$index',
          generation: 7,
          family: MobilePlaybackCandidateFamily.builtIn,
          ordinal: index,
          rank: index,
        ),
      for (var index = 0; index < 3; index += 1)
        candidate(
          'fallback-$index',
          generation: 7,
          family: MobilePlaybackCandidateFamily.fallback,
          ordinal: index,
          rank: index,
        ),
    ];

    final result = mergeMobilePlaybackCandidateInventory(
      generation: 7,
      fresh: fresh,
      retained: const <MobilePlaybackCandidate<String>>[],
    );

    expect(result.entries, hasLength(17));
    expect(
      result.entries.where(
          (entry) => entry.family == MobilePlaybackCandidateFamily.addOn),
      hasLength(8),
    );
    expect(
      result.entries.where(
        (entry) => entry.family == MobilePlaybackCandidateFamily.builtIn,
      ),
      hasLength(8),
    );
    expect(
      result.entries.where(
        (entry) => entry.family == MobilePlaybackCandidateFamily.fallback,
      ),
      hasLength(1),
    );
  });

  test('equal-rank completion order is deterministic by opaque identity', () {
    final forward = <MobilePlaybackCandidate<String>>[
      candidate(
        'second',
        generation: 3,
        family: MobilePlaybackCandidateFamily.builtIn,
        ordinal: 1,
      ),
      candidate(
        'first',
        generation: 3,
        family: MobilePlaybackCandidateFamily.builtIn,
        ordinal: 0,
      ),
    ];

    final first = mergeMobilePlaybackCandidateInventory(
      generation: 3,
      fresh: forward,
      retained: const <MobilePlaybackCandidate<String>>[],
    );
    final second = mergeMobilePlaybackCandidateInventory(
      generation: 3,
      fresh: forward.reversed.toList(),
      retained: const <MobilePlaybackCandidate<String>>[],
    );

    expect(
      first.entries.map((entry) => entry.identity),
      second.entries.map((entry) => entry.identity),
    );
    expect(first.entries.map((entry) => entry.value), ['first', 'second']);
  });

  test('malformed and cross-generation inventory fails closed', () {
    final valid = candidate(
      'valid',
      generation: 4,
      family: MobilePlaybackCandidateFamily.builtIn,
      ordinal: 0,
    );
    final malformed = MobilePlaybackCandidate<String>(
      value: 'malformed',
      identity: 'private-route-value',
      generation: 4,
      family: MobilePlaybackCandidateFamily.builtIn,
      rank: 0,
    );
    final crossGeneration = candidate(
      'old',
      generation: 3,
      family: MobilePlaybackCandidateFamily.builtIn,
      ordinal: 0,
    );

    expect(
      mergeMobilePlaybackCandidateInventory(
        generation: 4,
        fresh: [valid, malformed],
        retained: const <MobilePlaybackCandidate<String>>[],
      ).entries,
      isEmpty,
    );
    expect(
      mergeMobilePlaybackCandidateInventory(
        generation: 4,
        fresh: [valid],
        retained: [crossGeneration],
      ).entries,
      isEmpty,
    );
  });

  test('rejected identity cannot re-enter while active remains privately owned',
      () {
    final active = candidate(
      'active',
      generation: 9,
      family: MobilePlaybackCandidateFamily.builtIn,
      ordinal: 0,
      rank: 20,
    );
    final rejected = candidate(
      'rejected',
      generation: 9,
      family: MobilePlaybackCandidateFamily.addOn,
      ordinal: 0,
    );
    final replacement = candidate(
      'replacement',
      generation: 9,
      family: MobilePlaybackCandidateFamily.addOn,
      ordinal: 1,
    );

    final result = mergeMobilePlaybackCandidateInventory(
      generation: 9,
      fresh: [rejected, replacement],
      retained: [active, rejected],
      activeIdentity: active.identity,
      rejectedIdentities: {rejected.identity},
      maxBuiltIn: 0,
    );

    expect(result.entries.map((entry) => entry.value), ['replacement']);
    expect(result.active?.value, 'active');
  });
}
