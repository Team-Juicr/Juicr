import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_mature_content.dart';

void main() {
  group('TV mature content signal', () {
    test('accepts ordinary catalog metadata', () {
      expect(
        tvHasMatureContentSignal({
          'type': 'movie',
          'name': 'Bumblebee',
          'genres': ['Action', 'Adventure'],
        }),
        isFalse,
      );
    });

    test('rejects explicit flags and mature metadata signals', () {
      expect(tvHasMatureContentSignal({'adult': true}), isTrue);
      expect(tvHasMatureContentSignal({'type': 'nsfw'}), isTrue);
      expect(
        tvHasMatureContentSignal({
          'type': 'movie',
          'name': 'Catalog title',
          'genres': ['Erotic'],
        }),
        isTrue,
      );
    });

    test('matches mobile special-title safety signals', () {
      expect(tvHasMatureContentSignal({'name': 'Fifty Shades'}), isTrue);
      expect(tvHasMatureContentSignal({'name': '365 Days'}), isTrue);
      expect(tvHasMatureContentSignal({'name': 'Viva Max Special'}), isTrue);
    });
  });

  group('TV mature content preference', () {
    test('defaults off and restores only an explicit true value', () {
      expect(tvShowMatureContentFromJson({}), isFalse);
      expect(tvShowMatureContentFromJson({'showMatureContent': false}), isFalse);
      expect(tvShowMatureContentFromJson({'showMatureContent': 'true'}), isFalse);
      expect(tvShowMatureContentFromJson({'showMatureContent': true}), isTrue);
    });

    test('adds the server opt-in only when enabled', () {
      expect(tvMatureCatalogQuery(false), isEmpty);
      expect(tvMatureCatalogQuery(true), {'allowMature': 'true'});
    });

    test('defensively hides signaled items while disabled', () {
      expect(
        tvShouldShowCatalogItem(
          showMatureContent: false,
          hasMatureContentSignal: true,
        ),
        isFalse,
      );
      expect(
        tvShouldShowCatalogItem(
          showMatureContent: true,
          hasMatureContentSignal: true,
        ),
        isTrue,
      );
    });
  });
}
