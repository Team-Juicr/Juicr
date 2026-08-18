import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_playback_candidate_order.dart';

void main() {
  test('Media3 ranks broadly open MP4 qualities ahead of 2160P', () {
    expect(tvPlaybackCandidateRank(engine: 'Native', type: 'mp4', quality: '1080P', compatibilityRisk: 0), 10);
    expect(tvPlaybackCandidateRank(engine: 'Native', type: 'mp4', quality: '720P', compatibilityRisk: 0), 11);
    expect(tvPlaybackCandidateRank(engine: 'Native', type: 'mp4', quality: '2160P', compatibilityRisk: 0), 14);
  });

  test('Media3 ranks risky codecs behind a same-quality AVC candidate', () {
    expect(
      tvPlaybackCandidateRank(
        engine: 'Native',
        type: 'mp4',
        quality: '1080P',
        compatibilityRisk: 8,
      ),
      greaterThan(
        tvPlaybackCandidateRank(
          engine: 'Native',
          type: 'mp4',
          quality: '1080P',
          compatibilityRisk: 0,
        ),
      ),
    );
  });

  test('libVLC retains best-quality order for direct MP4', () {
    expect(tvPlaybackCandidateRank(engine: 'Compatibility', type: 'mp4', quality: '2160P', compatibilityRisk: 8), 10);
    expect(tvPlaybackCandidateRank(engine: 'Compatibility', type: 'mp4', quality: '1080P', compatibilityRisk: 8), 11);
    expect(tvPlaybackCandidateRank(engine: 'Compatibility', type: 'mp4', quality: '720P', compatibilityRisk: 8), 12);
  });

  test('balanced libVLC prefers compatible 1080P before risky 2160P', () {
    expect(
      tvPlaybackPreferenceCandidateRank(
        engine: 'Compatibility',
        preferredQuality: 'Balanced',
        type: 'mp4',
        quality: '1080P',
        compatibilityRisk: 0,
      ),
      lessThan(
        tvPlaybackPreferenceCandidateRank(
          engine: 'Compatibility',
          preferredQuality: 'Balanced',
          type: 'mp4',
          quality: '2160P',
          compatibilityRisk: 7,
        ),
      ),
    );
    expect(
      tvPlaybackPreferenceCandidateRank(
        engine: 'Compatibility',
        preferredQuality: 'Best available',
        type: 'mp4',
        quality: '2160P',
        compatibilityRisk: 7,
      ),
      lessThan(
        tvPlaybackPreferenceCandidateRank(
          engine: 'Compatibility',
          preferredQuality: 'Best available',
          type: 'mp4',
          quality: '1080P',
          compatibilityRisk: 0,
        ),
      ),
    );
  });

  test('adaptive media remains ahead of direct files', () {
    expect(tvPlaybackCandidateRank(engine: 'Native', type: 'hls', quality: 'Auto', compatibilityRisk: 8), 0);
    expect(tvPlaybackCandidateRank(engine: 'Native', type: 'dash', quality: 'Auto', compatibilityRisk: 8), 0);
  });

  test('bounded startup keeps one consented P2P fallback', () {
    final ordered = ['direct-1', 'direct-2', 'direct-3', 'direct-4', 'p2p-1'];

    expect(
      tvBoundedPlaybackCandidateOrder(
        ordered,
        maxCount: 4,
        includeP2pFallback: true,
        isP2p: (candidate) => candidate.startsWith('p2p'),
      ),
      ['direct-1', 'direct-2', 'direct-3', 'p2p-1'],
    );
    expect(
      tvBoundedPlaybackCandidateOrder(
        ordered,
        maxCount: 4,
        includeP2pFallback: false,
        isP2p: (candidate) => candidate.startsWith('p2p'),
      ),
      ['direct-1', 'direct-2', 'direct-3', 'direct-4'],
    );
  });

  test('startup and recovery share one four-candidate transaction budget', () {
    expect(tvPlaybackCandidateAttemptBudget(), 4);
    expect(tvPlaybackCandidateAttemptBudget(requestedMaxCount: 16), 4);
    expect(tvPlaybackCandidateAttemptBudget(requestedMaxCount: 1), 1);
    expect(tvPlaybackCandidateAttemptBudget(requestedMaxCount: 0), 0);
  });

  test('ranked inventory keeps compatible candidates beyond the raw cap', () {
    final candidates = <({String id, int rank, bool p2p})>[
      for (var index = 0; index < 8; index += 1)
        (id: '2160-$index', rank: 21, p2p: false),
      (id: '1080-compatible', rank: 10, p2p: false),
    ];

    final bounded = tvBoundedRankedPlaybackCandidateOrder(
      candidates,
      maxCount: 8,
      includeP2pFallback: false,
      isP2p: (candidate) => candidate.p2p,
      rankOf: (candidate) => candidate.rank,
    );

    expect(bounded, hasLength(8));
    expect(bounded.first.id, '1080-compatible');
    expect(bounded.where((candidate) => candidate.id.startsWith('2160-')), hasLength(7));
  });

  test('opaque candidate handles are generation and family scoped', () {
    expect(
      tvOpaquePlaybackCandidateId(
        generation: 7,
        family: TvPlaybackCandidateFamily.builtIn,
        sourceOrdinal: 2,
      ),
      'g7-builtin-3',
    );
    expect(
      tvPlaybackCandidateFamilyFromWire('addon'),
      TvPlaybackCandidateFamily.addOn,
    );
    expect(tvPlaybackCandidateFamilyFromWire('private-provider'), isNull);
    expect(
      tvPlaybackCandidateIdentityIsSafe('g7-builtin-3'),
      isTrue,
    );
    expect(
      tvPlaybackCandidateIdentityIsSafe('https://private.invalid/media'),
      isFalse,
    );
  });

  test('equal-rank candidates use opaque identity instead of completion order', () {
    final candidates = <({String id, int rank})>[
      (id: 'g2-builtin-3', rank: 4),
      (id: 'g2-builtin-1', rank: 4),
      (id: 'g2-builtin-2', rank: 4),
    ];

    final ordered = tvDeterministicRankedPlaybackCandidateOrder(
      candidates,
      rankOf: (candidate) => candidate.rank,
      identityOf: (candidate) => candidate.id,
    );

    expect(
      ordered.map((candidate) => candidate.id),
      ['g2-builtin-1', 'g2-builtin-2', 'g2-builtin-3'],
    );
  });

  test('inventory tagging assigns bounded opaque handles without private data', () {
    final tagged = tvTagPlaybackCandidateInventory(
      const ['private-route-a', 'private-route-b'],
      generation: 9,
      family: TvPlaybackCandidateFamily.addOn,
      tag: (candidate, identity, poolGeneration, family) => (
        privateRoute: candidate,
        identity: identity,
        poolGeneration: poolGeneration,
        family: family,
      ),
    );

    expect(tagged.map((entry) => entry.identity), [
      'g9-addon-1',
      'g9-addon-2',
    ]);
    expect(tagged.map((entry) => entry.poolGeneration), [9, 9]);
    expect(
      tagged.map((entry) => entry.family),
      [TvPlaybackCandidateFamily.addOn, TvPlaybackCandidateFamily.addOn],
    );
    expect(tagged.first.identity, isNot(contains('private-route')));
    expect(
      tvTagPlaybackCandidateInventory(
        const ['candidate'],
        generation: 0,
        family: TvPlaybackCandidateFamily.builtIn,
        tag: (candidate, identity, poolGeneration, family) => identity,
      ),
      isEmpty,
    );
  });

  test('fresh retained merge stays bounded across source families', () {
    final fresh = <({String id, String family})>[
      for (var index = 0; index < 10; index += 1)
        (id: 'addon-$index', family: 'addon'),
      for (var index = 0; index < 10; index += 1)
        (id: 'builtin-$index', family: 'builtin'),
      for (var index = 0; index < 3; index += 1)
        (id: 'fallback-$index', family: 'fallback'),
    ];
    final cached = <({String id, String family})>[
      (id: 'addon-0', family: 'addon'),
      (id: 'builtin-0', family: 'builtin'),
      (id: 'cached-addon', family: 'addon'),
    ];

    final merged = tvBoundedRetainedCandidateMerge(
      fresh: fresh,
      cached: cached,
      identityOf: (candidate) => candidate.id,
      isAddOn: (candidate) => candidate.family == 'addon',
      isFallback: (candidate) => candidate.family == 'fallback',
    );

    expect(merged, hasLength(17));
    expect(merged.where((candidate) => candidate.family == 'addon'), hasLength(8));
    expect(merged.where((candidate) => candidate.family == 'builtin'), hasLength(8));
    expect(merged.where((candidate) => candidate.family == 'fallback'), hasLength(1));
    expect(merged.first.id, 'addon-0');
    expect(merged.where((candidate) => candidate.id == 'addon-0'), hasLength(1));
  });

  test('equal-length fresh replacement and capped shrink both publish', () {
    expect(
      tvPlaybackCandidateInventoryChanged(
        previousIdentities: const ['old-a', 'old-b'],
        nextIdentities: const ['fresh-a', 'old-b'],
      ),
      isTrue,
    );
    expect(
      tvPlaybackCandidateInventoryChanged(
        previousIdentities: List<String>.generate(20, (index) => 'old-$index'),
        nextIdentities: List<String>.generate(17, (index) => 'old-$index'),
      ),
      isTrue,
    );
    expect(
      tvPlaybackCandidateInventoryChanged(
        previousIdentities: const ['same-a', 'same-b'],
        nextIdentities: const ['same-a', 'same-b'],
      ),
      isFalse,
    );
  });

  test('retained candidate identity rebases after fresh reorder and shrink', () {
    expect(
      tvPlaybackCandidateIndexForIdentity(
        identities: const ['fresh-a', 'retained', 'fresh-b'],
        identity: 'retained',
      ),
      1,
    );
    expect(
      tvPlaybackCandidateIndexForIdentity(
        identities: const ['fresh-a', 'fresh-b'],
        identity: 'retained',
      ),
      isNull,
    );
  });

  test('refresh cap retains both active and refreshed candidate identities', () {
    final fresh = <({String id, String family})>[
      (id: 'active', family: 'builtin'),
      (id: 'refreshed', family: 'builtin'),
      for (var index = 0; index < 8; index += 1)
        (id: 'fresh-$index', family: 'builtin'),
    ];

    final merged = tvBoundedRetainedCandidateMerge(
      fresh: fresh,
      cached: const <({String id, String family})>[],
      identityOf: (candidate) => candidate.id,
      isAddOn: (candidate) => candidate.family == 'addon',
      isFallback: (candidate) => candidate.family == 'fallback',
    );

    expect(merged, hasLength(8));
    expect(merged.map((candidate) => candidate.id), containsAll(<String>[
      'active',
      'refreshed',
    ]));
  });

  test('rotating fallback publishes target then restores retained identity', () {
    final targetInventory = tvBoundedRetainedCandidateMerge(
      fresh: const ['refreshed-fallback', 'active-fallback'],
      cached: const <String>[],
      identityOf: (candidate) => candidate,
      isAddOn: (_) => false,
      isFallback: (_) => true,
    );
    expect(targetInventory, const ['refreshed-fallback']);

    final rollbackInventory = tvBoundedRetainedCandidateMerge(
      fresh: const ['active-fallback'],
      cached: targetInventory,
      identityOf: (candidate) => candidate,
      isAddOn: (_) => false,
      isFallback: (_) => true,
    );
    expect(rollbackInventory, const ['active-fallback']);
  });

  test('P2P priority uses candidate quality and size instead of generic type', () {
    expect(
      tvP2pPlaybackCandidateRank(
        mode: 'smallerFasterFiles',
        quality: '1080P',
        label: '1080P 1.2 GB',
        avoidRiskyFormats: true,
        sizeLimitMb: 0,
      ),
      lessThan(
        tvP2pPlaybackCandidateRank(
          mode: 'smallerFasterFiles',
          quality: '2160P',
          label: '2160P 18 GB',
          avoidRiskyFormats: true,
          sizeLimitMb: 0,
        ),
      ),
    );
  });

  test('P2P availability priority prefers the healthier private swarm', () {
    expect(
      tvP2pPlaybackCandidateRank(
        mode: 'availabilityFirst',
        quality: '1080P',
        label: '1080P S: 240',
        trackerCount: 3,
        avoidRiskyFormats: true,
        sizeLimitMb: 0,
      ),
      lessThan(
        tvP2pPlaybackCandidateRank(
          mode: 'availabilityFirst',
          quality: '1080P',
          label: '1080P S: 0',
          trackerCount: 0,
          avoidRiskyFormats: true,
          sizeLimitMb: 0,
        ),
      ),
    );
  });
}
