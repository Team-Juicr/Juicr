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

  test('title wheel hydration candidates stay bounded to visible missing logos', () {
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

  test('title wheel hydration candidates dedupe matching visible content', () {
    final candidates = homeTitleWheelHydrationCandidates(
      [
        item(id: 'first', tmdbId: 10, name: 'Same Title'),
        item(id: 'duplicate', tmdbId: 10, name: 'Same Title'),
      ],
    );

    expect(candidates.map((candidate) => candidate.id), const ['first']);
  });
}
