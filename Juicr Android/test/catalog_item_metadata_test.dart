import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/catalog_item.dart';

void main() {
  test(
    'metadata merge preserves hosted imdb id for tmdb playback identity',
    () {
      const original = CatalogItem(
        type: MediaType.series,
        id: 'tmdb:76479',
        name: 'The Boys',
        tmdbId: 76479,
      );
      const metadata = CatalogItem(
        type: MediaType.series,
        id: 'tmdb:76479',
        name: 'The Boys',
        tmdbId: 76479,
        imdbId: 'tt1190634',
      );

      final merged = metadata.merge(original);

      expect(merged.id, original.id);
      expect(merged.tmdbId, original.tmdbId);
      expect(merged.imdbId, 'tt1190634');
    },
  );
}
