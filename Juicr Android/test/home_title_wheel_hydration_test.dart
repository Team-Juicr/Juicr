import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/catalog_item.dart';
import 'package:juicr/src/home_page.dart';

void main() {
  CatalogItem item({
    required String id,
    String? logo,
    int? tmdbId,
    String name = 'Title',
  }) {
    return CatalogItem(
      type: MediaType.movie,
      id: id,
      name: name,
      logo: logo,
      tmdbId: tmdbId,
    );
  }

  test('title wheel hydration candidates stay bounded to visible missing logos',
      () {
    final candidates = homeTitleWheelHydrationCandidates(
      [
        item(id: 'with-logo', logo: 'https://image/logo.png', tmdbId: 1),
        item(id: 'missing-1', tmdbId: 2, name: 'Missing One'),
        item(id: 'missing-2', tmdbId: 3, name: 'Missing Two'),
        item(id: 'no-tmdb'),
        item(id: 'below-fold', tmdbId: 4, name: 'Below Fold'),
      ],
      visibleLimit: 4,
    );

    expect(
      candidates.map((candidate) => candidate.id),
      const ['missing-1', 'missing-2'],
    );
  });

  test('title wheel hydration keeps distinct catalog identities separate', () {
    final candidates = homeTitleWheelHydrationCandidates(
      [
        item(id: 'first', tmdbId: 10, name: 'Same Title'),
        item(id: 'duplicate', tmdbId: 10, name: 'Same Title'),
      ],
    );

    expect(
      candidates.map((candidate) => candidate.id),
      const ['first', 'duplicate'],
    );
  });

  test('Home artwork hydration preserves catalog identity and metadata', () {
    const base = CatalogItem(
      type: MediaType.series,
      id: 'catalog-series-id',
      name: 'Server Ordered Series',
      year: '2026',
      releaseDate: '2026-08-01',
      tmdbId: 123,
      imdbId: 'tt123',
      genres: ['Drama'],
      description: 'Server metadata',
      imdbRating: '8.4',
      voteCount: 42,
    );
    const artwork = CatalogItem(
      type: MediaType.movie,
      id: 'wrong-id',
      name: 'Wrong name',
      year: '1999',
      tmdbId: 999,
      imdbId: 'tt999',
      genres: ['Wrong'],
      description: 'Wrong metadata',
      poster: 'poster',
      background: 'background',
      logo: 'logo',
    );

    final merged = homeArtworkOnlyMerge(base, artwork);

    expect(merged.type, base.type);
    expect(merged.id, base.id);
    expect(merged.name, base.name);
    expect(merged.year, base.year);
    expect(merged.releaseDate, base.releaseDate);
    expect(merged.tmdbId, base.tmdbId);
    expect(merged.imdbId, base.imdbId);
    expect(merged.genres, base.genres);
    expect(merged.description, base.description);
    expect(merged.imdbRating, base.imdbRating);
    expect(merged.voteCount, base.voteCount);
    expect(merged.poster, artwork.poster);
    expect(merged.background, artwork.background);
    expect(merged.logo, artwork.logo);
  });
}
