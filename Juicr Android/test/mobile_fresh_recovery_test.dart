import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/native_player_page.dart';
import 'package:juicr/src/playback_provider.dart';

void main() {
  test('fresh recovery excludes exhausted resolved route providers', () {
    final providers = mobileFreshRecoveryProviderIds(
      orderedProviderIds: const ['alpha', 'beta', 'gamma'],
      exhaustedProviderIds: const ['alpha'],
    );

    expect(providers, const ['beta', 'gamma']);
  });

  test('fresh recovery drops empty and duplicate exhausted ids', () {
    final providers = mobileFreshRecoveryProviderIds(
      orderedProviderIds: const ['alpha', 'beta', 'gamma'],
      exhaustedProviderIds: const ['', ' beta ', 'beta'],
    );

    expect(providers, const ['alpha', 'gamma']);
  });

  test('fresh recovery can cap resolved-only auto candidates', () {
    final providers = mobileFreshRecoveryProviderIds(
      orderedProviderIds: const ['alpha', 'beta', 'gamma', 'delta'],
      exhaustedProviderIds: const ['alpha'],
      maxCandidates: 2,
    );

    expect(providers, const ['beta', 'gamma']);
  });

  test('temporary resolver block continues to a queued resolved fallback', () {
    final shouldContinue = mobileHasResolvedFallbackAfter(
      currentIndex: 1,
      requestSourceCounts: const [1, 0, 1, 0],
    );

    expect(shouldContinue, isTrue);
  });

  test('temporary resolver block stops when no resolved fallback remains', () {
    final shouldContinue = mobileHasResolvedFallbackAfter(
      currentIndex: 1,
      requestSourceCounts: const [1, 0, 0, 0],
    );

    expect(shouldContinue, isFalse);
  });

  test('failed libVLC HLS session is skipped for the current route', () {
    final shouldSkip = mobileShouldSkipFailedLibVlcHlsSession(
      engineId: 'libvlc',
      isHls: true,
      candidateKey: 'provider|720P|session-a',
      failedCandidateKeys: const {'provider|720P|session-a'},
    );

    expect(shouldSkip, isTrue);
  });

  test('failed HLS quarantine does not exclude direct MP4 or Media3', () {
    const failed = {'provider|720P|session-a'};

    expect(
      mobileShouldSkipFailedLibVlcHlsSession(
        engineId: 'libvlc',
        isHls: false,
        candidateKey: 'provider|720P|session-a',
        failedCandidateKeys: failed,
      ),
      isFalse,
    );
    expect(
      mobileShouldSkipFailedLibVlcHlsSession(
        engineId: 'exoplayer',
        isHls: true,
        candidateKey: 'provider|720P|session-a',
        failedCandidateKeys: failed,
      ),
      isFalse,
    );
  });

  test('explicit libVLC prioritizes resolved MP4 before bounded fresh sample',
      () {
    final requests = <NativePlaybackRequest>[
      NativePlaybackRequest(
        providerId: 'hls-alpha',
        sources: [_source('hls-alpha', 'https://example.test/a.m3u8')],
      ),
      const NativePlaybackRequest(providerId: 'unresolved-alpha'),
      NativePlaybackRequest(
        providerId: 'mp4-alpha',
        sources: [_source('mp4-alpha', 'https://example.test/a.mp4')],
      ),
      NativePlaybackRequest(
        providerId: 'other-alpha',
        sources: [_source('other-alpha', 'https://example.test/video')],
      ),
    ];

    final ordered = mobilePrioritizeExplicitLibVlcRequestsByTransport(
      requests,
      explicitLibVlc: true,
    );

    expect(
      ordered.map((request) => request.providerId),
      const [
        'mp4-alpha',
        'unresolved-alpha',
        'other-alpha',
        'hls-alpha',
      ],
    );
  });

  test('explicit libVLC request ordering is stable and retains HLS fallback',
      () {
    final requests = <NativePlaybackRequest>[
      NativePlaybackRequest(
        providerId: 'hls-alpha',
        sources: [_source('hls-alpha', 'https://example.test/a.m3u8')],
      ),
      NativePlaybackRequest(
        providerId: 'mp4-alpha',
        sources: [_source('mp4-alpha', 'https://example.test/a.mp4')],
      ),
      NativePlaybackRequest(
        providerId: 'hls-beta',
        sources: [_source('hls-beta', 'https://example.test/b.m3u8')],
      ),
      NativePlaybackRequest(
        providerId: 'mp4-beta',
        sources: [_source('mp4-beta', 'https://example.test/b.mp4')],
      ),
    ];

    final ordered = mobilePrioritizeExplicitLibVlcRequestsByTransport(
      requests,
      explicitLibVlc: true,
    );

    expect(
      ordered.map((request) => request.providerId),
      const ['mp4-alpha', 'mp4-beta', 'hls-alpha', 'hls-beta'],
    );
  });

  test('request transport ordering leaves non-explicit libVLC unchanged', () {
    final requests = <NativePlaybackRequest>[
      NativePlaybackRequest(
        providerId: 'hls-alpha',
        sources: [_source('hls-alpha', 'https://example.test/a.m3u8')],
      ),
      NativePlaybackRequest(
        providerId: 'mp4-alpha',
        sources: [_source('mp4-alpha', 'https://example.test/a.mp4')],
      ),
    ];

    final ordered = mobilePrioritizeExplicitLibVlcRequestsByTransport(
      requests,
      explicitLibVlc: false,
    );

    expect(identical(ordered, requests), isTrue);
  });

  test('explicit libVLC prioritizes MP4 within one provider', () {
    final sources = <PlaybackSource>[
      _source('alpha', 'https://example.test/master.m3u8'),
      _source('alpha', 'https://example.test/video'),
      _source('alpha', 'https://example.test/movie.mp4'),
    ];

    final ordered = mobilePrioritizeExplicitLibVlcSourcesByTransport(
      sources,
      explicitLibVlc: true,
    );

    expect(
      ordered.map((source) => source.url),
      const [
        'https://example.test/movie.mp4',
        'https://example.test/video',
        'https://example.test/master.m3u8',
      ],
    );
  });

  test('source transport ordering leaves non-explicit libVLC unchanged', () {
    final sources = <PlaybackSource>[
      _source('alpha', 'https://example.test/master.m3u8'),
      _source('alpha', 'https://example.test/movie.mp4'),
    ];

    final ordered = mobilePrioritizeExplicitLibVlcSourcesByTransport(
      sources,
      explicitLibVlc: false,
    );

    expect(identical(ordered, sources), isTrue);
  });

  test('clean verified libVLC MP4 is eligible for bounded early fallback', () {
    final eligible = mobileVerifiedLibVlcMp4CanUseEarlyFallback(
      strictLibVlc: true,
      cachedEngineId: 'libvlc',
      source: _source('alpha', 'https://example.test/movie.mp4'),
      cacheAge: const Duration(minutes: 34),
      stale: false,
      nativeSupported: true,
      descriptorOpenable: true,
      providerOffline: false,
      failureCount: 0,
      confidence: 12,
    );

    expect(eligible, isTrue);
  });

  test('aged verified libVLC MP4 stays in the last-resort fallback bucket', () {
    final eligible = mobileVerifiedLibVlcMp4CanUseEarlyFallback(
      strictLibVlc: true,
      cachedEngineId: 'libvlc',
      source: _source('alpha', 'https://example.test/movie.mp4'),
      cacheAge: const Duration(minutes: 194),
      stale: false,
      nativeSupported: true,
      descriptorOpenable: true,
      providerOffline: false,
      failureCount: 0,
      confidence: 100,
    );

    expect(eligible, isFalse);
  });

  test('verified libVLC HLS remains outside the MP4 early fallback', () {
    final eligible = mobileVerifiedLibVlcMp4CanUseEarlyFallback(
      strictLibVlc: true,
      cachedEngineId: 'libvlc',
      source: _source('alpha', 'https://example.test/master.m3u8'),
      cacheAge: const Duration(minutes: 34),
      stale: false,
      nativeSupported: true,
      descriptorOpenable: true,
      providerOffline: false,
      failureCount: 0,
      confidence: 100,
    );

    expect(eligible, isFalse);
  });

  test('stale failed or engine-mismatched MP4 cannot move forward', () {
    final source = _source('alpha', 'https://example.test/movie.mp4');

    expect(
      mobileVerifiedLibVlcMp4CanUseEarlyFallback(
        strictLibVlc: true,
        cachedEngineId: 'libvlc',
        source: source,
        cacheAge: const Duration(minutes: 34),
        stale: true,
        nativeSupported: true,
        descriptorOpenable: true,
        providerOffline: false,
        failureCount: 0,
        confidence: 100,
      ),
      isFalse,
    );
    expect(
      mobileVerifiedLibVlcMp4CanUseEarlyFallback(
        strictLibVlc: true,
        cachedEngineId: 'libvlc',
        source: source,
        cacheAge: const Duration(minutes: 34),
        stale: false,
        nativeSupported: true,
        descriptorOpenable: true,
        providerOffline: false,
        failureCount: 1,
        confidence: 100,
      ),
      isFalse,
    );
    expect(
      mobileVerifiedLibVlcMp4CanUseEarlyFallback(
        strictLibVlc: true,
        cachedEngineId: 'exoplayer',
        source: source,
        cacheAge: const Duration(minutes: 34),
        stale: false,
        nativeSupported: true,
        descriptorOpenable: true,
        providerOffline: false,
        failureCount: 0,
        confidence: 100,
      ),
      isFalse,
    );
  });
}

PlaybackSource _source(String providerId, String url) {
  return PlaybackSource(
    providerId: providerId,
    name: providerId,
    url: url,
    type: url.endsWith('.m3u8')
        ? 'hls'
        : url.endsWith('.mp4')
            ? 'mp4'
            : null,
  );
}
