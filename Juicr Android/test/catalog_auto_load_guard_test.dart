import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/catalog_page.dart';

void main() {
  test('does not chain catalog auto-load from the top of a short list', () {
    final shouldLoad = shouldChainCatalogAutoLoad(
      pixels: 0,
      maxScrollExtent: 1067.7,
      threshold: 1146.9,
    );

    expect(shouldLoad, isFalse);
  });

  test('chains catalog auto-load when the user is actually near the end', () {
    final shouldLoad = shouldChainCatalogAutoLoad(
      pixels: 1010,
      maxScrollExtent: 1067.7,
      threshold: 180,
    );

    expect(shouldLoad, isTrue);
  });
}
