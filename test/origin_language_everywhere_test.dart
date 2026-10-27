import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('global title card renders original production origin and language', () {
    final card = File('lib/widgets/movie/movie_card.dart')
        .readAsStringSync();
    expect(card, contains('OriginLanguageLabel('));
    expect(card, contains('knownCountries: movie.originCountries'));
    expect(card, contains('knownLanguage: movie.originalLanguage'));
    expect(card, contains('posterHeight + 108'));
  });

  test('all separate movie and series grids show both fields', () {
    for (final path in [
      'lib/pages/details/details_page.dart',
      'lib/pages/search/advanced_discover_page.dart',
      'lib/pages/networks/networks_page.dart',
      'lib/pages/details/person_credits_page.dart',
      'lib/pages/my_list/my_list_page.dart',
      'lib/widgets/home/continue_watching_slider.dart',
    ]) {
      expect(File(path).readAsStringSync(), contains('OriginLanguageLabel('),
          reason: 'Missing production origin/language in $path');
    }
    expect(File('lib/pages/catalog/catalog_page.dart').readAsStringSync(),
        contains('sizing.cardWidth / sizing.totalHeight'));
    expect(File('lib/pages/discover/discover_page.dart').readAsStringSync(),
        contains('sizing.cardWidth / sizing.totalHeight'));
    final sim = File('lib/pages/details/details_page.dart')
        .readAsStringSync();
    expect(sim, contains("'Origin:"));
    expect(sim, contains("'Original:"));
  });

  test('original-language labels cannot be confused with dubbed audio', () {
    final service = File('lib/services/metadata/title_origin_language_service.dart')
        .readAsStringSync();
    expect(service, contains("Original language: "));
    expect(service, contains('Not listed'));
    expect(service, contains('24 on-demand'));
    expect(service, contains('titleOriginLanguage('));
    expect(service, isNot(contains("English dub available")));
    final tmdb = File('lib/services/metadata/tmdb_discover_service.dart')
        .readAsStringSync();
    expect(tmdb, contains('find/\$imdbId'));
    expect(tmdb, contains("'tv_results' : 'movie_results'"));
  });
}
