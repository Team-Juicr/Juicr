import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/mobile_playback_quality_selection.dart';

void main() {
  test('mobile quality labels normalize shared resolution aliases', () {
    expect(mobilePlaybackDisplayQuality('2160P'), '4K');
    expect(mobilePlaybackDisplayQuality('uhd'), '4K');
    expect(mobilePlaybackDisplayQuality('1440p'), '2K');
    expect(mobilePlaybackDisplayQuality('qhd'), '2K');
    expect(mobilePlaybackDisplayQuality('1080p'), '1080P');
    expect(mobilePlaybackDisplayQuality('4K HDR'), '4K');
    expect(mobilePlaybackDisplayQuality('2K HEVC'), '2K');
    expect(mobilePlaybackDisplayQuality('adaptive'), 'Auto');
    expect(mobilePlaybackDisplayQuality(''), 'Unknown');
  });

  test('manual quality candidates contain every matching retained mirror', () {
    expect(
      mobilePlaybackQualityCandidateIndexes(
        qualities: const ['720P', '1080P', 'Auto', '1080p', '2160P'],
        selected: '1080P',
      ),
      const [1, 3],
    );
    expect(
      mobilePlaybackQualityCandidateIndexes(
        qualities: const ['4K', '2160P', '1440P', 'Auto'],
        selected: '4K',
      ),
      const [0, 1],
    );
  });

  test('available manual qualities are distinct and highest first', () {
    expect(
      mobilePlaybackAvailableQualityLabels(
        const ['720P', '2160P', '4K', 'Auto', '1440P', '1080P', '720p'],
      ),
      const ['4K', '2K', '1080P', '720P'],
    );
  });

  test('Auto is selectable only when the retained inventory contains it', () {
    expect(
      mobilePlaybackHasAutomaticCandidate(
        const ['1080P', 'adaptive', '720P'],
      ),
      isTrue,
    );
    expect(
      mobilePlaybackHasAutomaticCandidate(const ['1080P', 'unknown', '720P']),
      isFalse,
    );
    expect(
      mobilePlaybackQualityCandidateIndexes(
        qualities: const ['1080P', 'adaptive', '720P'],
        selected: 'Auto',
      ),
      const [1],
    );
  });
}
