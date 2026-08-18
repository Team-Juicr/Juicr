import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_playback_source_groups.dart';

void main() {
  test('quality labels normalize TV resolution names', () {
    expect(tvPlaybackDisplayQuality('2160P'), '4K');
    expect(tvPlaybackDisplayQuality('4k'), '4K');
    expect(tvPlaybackDisplayQuality('1440p'), '2K');
    expect(tvPlaybackDisplayQuality('1080p'), '1080P');
    expect(tvPlaybackDisplayQuality('720P'), '720P');
    expect(tvPlaybackDisplayQuality('4K HDR'), '4K');
    expect(tvPlaybackDisplayQuality('2K HEVC'), '2K');
    expect(tvPlaybackDisplayQuality(''), 'Unknown');
  });

  test('available quality labels are distinct and highest first', () {
    expect(
      tvPlaybackAvailableQualityLabels(
        const ['720P', '2160P', '4K', 'Auto', '1440P', '1080P', '720p'],
      ),
      const ['4K', '2K', '1080P', '720P'],
    );
  });

  test('manual quality order contains only matching retained mirrors', () {
    expect(
      tvPlaybackQualityCandidateOrder(
        qualities: const ['720P', '1080P', 'Auto', '1080p', '2160P'],
        currentIndex: 0,
        selected: '1080P',
      ),
      const [1, 3],
    );
    expect(
      tvPlaybackQualityCandidateOrder(
        qualities: const ['4K', '2160P', '1440P', 'Auto'],
        currentIndex: 3,
        selected: '4K',
      ),
      const [0, 1],
    );
  });

  test('Auto order contains only an actual automatic candidate', () {
    expect(
      tvPlaybackQualityCandidateOrder(
        qualities: const ['1080P', 'Auto', '720P'],
        currentIndex: 2,
        selected: 'Auto',
      ),
      const [1],
    );
    expect(
      tvPlaybackQualityCandidateOrder(
        qualities: const ['1080P', '720P'],
        currentIndex: 1,
        selected: 'Auto',
      ),
      isEmpty,
    );
  });

  test('missing and unknown qualities never fabricate Auto', () {
    expect(tvPlaybackQualityBucket(''), 'unknown');
    expect(tvPlaybackQualityBucket('unknown'), 'unknown');
    expect(tvPlaybackQualityBucket('adaptive'), 'auto');
    expect(
      tvPlaybackQualityCandidateOrder(
        qualities: const ['', 'unknown', 'adaptive', '1080P'],
        currentIndex: 0,
        selected: 'Auto',
      ),
      const [2],
    );
  });

  test('quality Auto resolves only to an actual automatic candidate', () {
    expect(
      tvPlaybackQualityChoiceIndex(
        qualities: const ['1080P', 'Auto', '720P'],
        currentIndex: 2,
        selected: 'Auto',
      ),
      1,
    );
    expect(
      tvPlaybackQualityChoiceIndex(
        qualities: const ['1080P', '720P'],
        currentIndex: 1,
        selected: 'Auto',
      ),
      1,
    );
    expect(
      tvPlaybackQualityChoiceIndex(
        qualities: const ['1080P', '720P'],
        currentIndex: 0,
        selected: '720P',
      ),
      1,
    );
  });

  test('source groups retain descending quality order', () {
    final groups = groupTvPlaybackSources(const [
      TvPlaybackSourceGroupEntry(sessionIndex: 0, quality: '360P'),
      TvPlaybackSourceGroupEntry(sessionIndex: 1, quality: '1080P'),
      TvPlaybackSourceGroupEntry(sessionIndex: 2, quality: '720P'),
    ]);

    expect(groups.map((group) => group.quality), ['1080P', '720P', '360P']);
    expect(groups.map((group) => group.sessionIndexes.single), [1, 2, 0]);
  });

  test('only explicit pool metadata creates a mirror family', () {
    final groups = groupTvPlaybackSources(const [
      TvPlaybackSourceGroupEntry(
        sessionIndex: 0,
        quality: '720P',
        mirrorGroupId: 'group-a',
        mirrorRank: 2,
        sourcePoolVersion: 'pool-v2',
      ),
      TvPlaybackSourceGroupEntry(
        sessionIndex: 1,
        quality: '720P',
        mirrorGroupId: 'group-a',
        mirrorRank: 1,
        sourcePoolVersion: 'pool-v2',
      ),
      TvPlaybackSourceGroupEntry(sessionIndex: 2, quality: '720P'),
    ]);

    expect(groups, hasLength(2));
    expect(groups.first.sessionIndexes, [1, 0]);
    expect(groups.last.sessionIndexes, [2]);
  });

  test('mirror metadata without an exact pool version fails closed', () {
    final groups = groupTvPlaybackSources(const [
      TvPlaybackSourceGroupEntry(
        sessionIndex: 0,
        quality: '720P',
        mirrorGroupId: 'group-a',
        mirrorRank: 1,
      ),
      TvPlaybackSourceGroupEntry(
        sessionIndex: 1,
        quality: '720P',
        mirrorGroupId: 'group-a',
        mirrorRank: 2,
      ),
    ]);

    expect(groups, hasLength(2));
    expect(groups.expand((group) => group.sessionIndexes), [0, 1]);
  });

  test('malformed pool metadata cannot create a mirror family', () {
    final groups = groupTvPlaybackSources(const [
      TvPlaybackSourceGroupEntry(
        sessionIndex: 0,
        quality: '1080P',
        mirrorGroupId: 'group/a',
        sourcePoolVersion: 'pool-v2',
      ),
      TvPlaybackSourceGroupEntry(
        sessionIndex: 1,
        quality: '1080P',
        mirrorGroupId: 'group/a',
        sourcePoolVersion: 'pool-v2',
      ),
      TvPlaybackSourceGroupEntry(
        sessionIndex: 2,
        quality: '1080P',
        mirrorGroupId: 'group-b',
        sourcePoolVersion: 'pool version',
      ),
      TvPlaybackSourceGroupEntry(
        sessionIndex: 3,
        quality: '1080P',
        mirrorGroupId: 'group-b',
        sourcePoolVersion: 'pool version',
      ),
    ]);

    expect(groups, hasLength(4));
    expect(groups.expand((group) => group.sessionIndexes), [0, 1, 2, 3]);
  });
}
