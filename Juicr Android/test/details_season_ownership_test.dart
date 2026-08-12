import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/details_season_ownership.dart';

void main() {
  group('details title hydration ownership', () {
    test('title change invalidates every prior hydration generation', () {
      final owner = DetailsTitleHydrationOwnership(titleIdentity: 'series:a');
      final firstGeneration = owner.generation;

      expect(owner.accepts('series:a', firstGeneration), isTrue);

      final secondGeneration = owner.resetForTitle('series:b');

      expect(secondGeneration, isNot(firstGeneration));
      expect(owner.accepts('series:a', firstGeneration), isFalse);
      expect(owner.accepts('series:b', secondGeneration), isTrue);
    });

    test('disposed title owner rejects late hydration callbacks', () {
      final owner = DetailsTitleHydrationOwnership(titleIdentity: 'movie:a');
      final generation = owner.generation;

      owner.dispose();

      expect(owner.accepts('movie:a', generation), isFalse);
    });
  });

  group('details season ownership', () {
    test('explicit Season 2 survives late Season 1 hydration', () {
      final owner = DetailsSeasonOwnership(
        titleIdentity: 'series:a',
        availableSeasons: const [1, 2],
      );

      owner.selectSeason(2);
      final accepted = owner.applyAsyncSeasons(
        titleIdentity: 'series:a',
        generation: owner.generation,
        availableSeasons: const [1],
      );

      expect(accepted, isTrue);
      expect(owner.selectedSeason, 2);
      expect(owner.hasExplicitSelection, isTrue);
    });

    test('resume S2E9 may establish initial season before or after details',
        () {
      final before = DetailsSeasonOwnership(
        titleIdentity: 'series:a',
        availableSeasons: const [1, 2],
        canonicalResumeSeason: 2,
      );
      final after = DetailsSeasonOwnership(
        titleIdentity: 'series:a',
        availableSeasons: const [1],
      );

      final accepted = after.applyAsyncSeasons(
        titleIdentity: 'series:a',
        generation: after.generation,
        availableSeasons: const [1, 2],
        canonicalResumeSeason: 2,
      );

      expect(before.selectedSeason, 2);
      expect(accepted, isTrue);
      expect(after.selectedSeason, 2);
      expect(after.hasExplicitSelection, isFalse);
    });

    test('rapid Season 2 then Season 3 rejects out-of-order season result', () {
      final owner = DetailsSeasonOwnership(
        titleIdentity: 'series:a',
        availableSeasons: const [1, 2, 3],
      );

      owner.selectSeason(2);
      final season2Generation = owner.generation;
      owner.selectSeason(3);
      final accepted = owner.applyAsyncSeasons(
        titleIdentity: 'series:a',
        generation: season2Generation,
        availableSeasons: const [1, 2],
      );

      expect(accepted, isFalse);
      expect(owner.selectedSeason, 3);
    });

    test('title identity change clears explicit ownership safely', () {
      final owner = DetailsSeasonOwnership(
        titleIdentity: 'series:a',
        availableSeasons: const [1, 2],
      )..selectSeason(2);

      owner.resetForTitle(
        titleIdentity: 'series:b',
        availableSeasons: const [1, 3],
      );

      expect(owner.titleIdentity, 'series:b');
      expect(owner.selectedSeason, 1);
      expect(owner.hasExplicitSelection, isFalse);
    });

    test('disposal rejects late callbacks', () {
      final owner = DetailsSeasonOwnership(
        titleIdentity: 'series:a',
        availableSeasons: const [1, 2],
      );
      final generation = owner.generation;

      owner.dispose();
      final accepted = owner.applyAsyncSeasons(
        titleIdentity: 'series:a',
        generation: generation,
        availableSeasons: const [1],
      );

      expect(accepted, isFalse);
      expect(owner.selectedSeason, 1);
    });

    test('no explicit selection preserves canonical initial behavior', () {
      final owner = DetailsSeasonOwnership(
        titleIdentity: 'series:a',
        availableSeasons: const [1, 2],
      );

      expect(owner.selectedSeason, 1);
      expect(owner.hasExplicitSelection, isFalse);
    });
  });
}
