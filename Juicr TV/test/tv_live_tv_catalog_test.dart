import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_live_tv_catalog.dart';

void main() {
  group('TV Live TV playlist filters', () {
    test('uses the canonical v2 Live TV catalog type', () {
      expect(tvLiveTvCatalogType, 'live_tv');
      expect(tvLiveTvFilteredScanMaxPages, 8);
      expect(tvIsLiveTvRootFilter('All genres'), isTrue);
      expect(tvIsLiveTvRootFilter('All countries'), isTrue);
      expect(tvIsLiveTvRootFilter('Kids'), isFalse);
      expect(tvCatalogUsesLandscapeSkeleton(tvLiveTvCatalogType), isTrue);
      expect(tvCatalogUsesLandscapeSkeleton('movie'), isFalse);
      expect(
        tvCatalogSkeletonHeight(type: tvLiveTvCatalogType, width: 160),
        90,
      );
      expect(tvShowCatalogSecondaryLogo(logoFirst: true), isFalse);
      expect(tvShowCatalogSecondaryLogo(logoFirst: false), isTrue);
    });

    test('a scoped Live TV lane never borrows its unfiltered base lane', () {
      expect(
        tvSelectLiveTvDisplayLane<String>(
          hasScopedFilter: true,
          scopedItems: null,
          baseItems: const ['unfiltered'],
        ),
        isEmpty,
      );
      expect(
        tvSelectLiveTvDisplayLane<String>(
          hasScopedFilter: false,
          scopedItems: null,
          baseItems: const ['base'],
        ),
        const ['base'],
      );
      expect(
        tvSelectLiveTvDisplayLane<String>(
          hasScopedFilter: true,
          scopedItems: const ['filtered'],
          baseItems: const ['base'],
        ),
        const ['filtered'],
      );
    });

    test('Alpha prefers server genres and keeps the all-genres root', () {
      expect(
        tvLiveTvFilterOptions(
          playlist: TvLiveTvPlaylist.alpha,
          serverGenres: const ['News', 'Kids', 'news'],
        ),
        const ['All genres', 'News', 'Kids'],
      );
    });

    test('Beta uses countries and never carries an Alpha genre', () {
      final options = tvLiveTvFilterOptions(
        playlist: TvLiveTvPlaylist.beta,
        serverCountries: const ['Philippines', 'Japan'],
      );

      expect(options, const ['All countries', 'Philippines', 'Japan']);
      expect(
        tvReconcileLiveTvFilter(
          playlist: TvLiveTvPlaylist.beta,
          current: 'Kids',
          serverCountries: const ['Philippines', 'Japan'],
        ),
        'All countries',
      );
      expect(tvLiveTvFilterTitle(TvLiveTvPlaylist.beta), 'Country');
      expect(
        tvShouldApplyClientLiveTvGenreFilter(TvLiveTvPlaylist.beta),
        isFalse,
      );
    });

    test('Gamma uses its stable genre taxonomy', () {
      final options = tvLiveTvFilterOptions(
        playlist: TvLiveTvPlaylist.gamma,
      );

      expect(options.first, 'All genres');
      expect(options, containsAll(const ['Kids', 'News', 'Sports']));
      expect(tvLiveTvFilterTitle(TvLiveTvPlaylist.gamma), 'Genre');
      expect(
        tvShouldApplyClientLiveTvGenreFilter(TvLiveTvPlaylist.gamma),
        isTrue,
      );
    });

    test('server filter values are normalized and deduplicated', () {
      expect(
        tvLiveTvFilterOptions(
          playlist: TvLiveTvPlaylist.alpha,
          serverGenres: const ['science-fiction', 'Sports', 'sports', ''],
        ),
        const ['All genres', 'Science Fiction', 'Sport'],
      );
    });
  });
}
