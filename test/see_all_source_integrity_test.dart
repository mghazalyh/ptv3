import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:playtorrio/services/metadata/metadata_service.dart';
import 'package:playtorrio/models/addon/addon.dart';
import 'package:playtorrio/models/movie/movie.dart';
import 'package:playtorrio/models/movie/movie_section.dart';
import 'package:playtorrio/pages/catalog/catalog_page.dart';
import 'package:playtorrio/services/metadata/bestsimilar_scraper.dart';
import 'package:playtorrio/widgets/movie/movie_card.dart';

MovieSection section(String catalogId, {
  required bool supportsSkip,
  required String baseUrl,
  bool isCurated = false,
}) => MovieSection(
  title: 'Similar to Slow Horses', subtitle: 'Original recommendation source',
  contentType: 'series', addonBaseUrl: baseUrl,
  catalog: AddonCatalog(type: 'series', id: catalogId,
    genres: const [], supportsSearch: false, supportsSkip: supportsSkip),
  isCurated: isCurated,
  movies: [
    Movie(id: 'tt12345', name: 'London Spy', type: 'series',
      addonBaseUrl: baseUrl),
    Movie(id: 'tt54321', name: 'The Bureau', type: 'series',
      addonBaseUrl: baseUrl),
  ],
);

List<String> visibleMovies(WidgetTester tester) => tester
    .widgetList<MovieCard>(find.byType(MovieCard))
    .map((w) => w.movie.name).toList();

void main() {
  testWidgets('non-paginated addon See All preserves the original row, '
      'never fetches Cinemeta', (tester) async {
    await tester.pumpWidget(MaterialApp(home: CatalogPage(section: section(
      'featured-series', supportsSkip: false, baseUrl: '',
    ))));
    await tester.pump();
    expect(visibleMovies(tester), ['London Spy', 'The Bureau']);
    expect(find.text('Similar to Slow Horses'), findsOneWidget);
    await tester.drag(find.byType(GridView), const Offset(0, -600));
    await tester.pump();
    expect(visibleMovies(tester), ['London Spy', 'The Bureau']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('synthetic recommendation ID cannot call generic addon '
      'even if marked non-curated and supportsSkip', (tester) async {
    await tester.pumpWidget(MaterialApp(home: CatalogPage(section: section(
      'trakt_recommendations',
      supportsSkip: true, baseUrl: 'https://v3-cinemeta.strem.io',
    ))));
    await tester.pump();
    expect(visibleMovies(tester), ['London Spy', 'The Bureau']);
    await tester.drag(find.byType(GridView), const Offset(0, -600));
    await tester.pump();
    expect(visibleMovies(tester), ['London Spy', 'The Bureau']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('curated IDs never leave the source even with invalid addon URL',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: CatalogPage(section: section(
      'bestsimilar_watching', supportsSkip: false,
      baseUrl: 'https://v3-cinemeta.strem.io', isCurated: true,
    ))));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'The Bureau');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(visibleMovies(tester), ['The Bureau']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('BestSimilar rejects generic same-year same-type autocomplete hits', () {
    BSAutocompleteHit hit(String title, int year, bool isTv) =>
        BSAutocompleteHit(id: 14, slug: '14-example', label: title,
          title: title, year: year, isTv: isTv, url: '/movies/14-example');
    expect(BestSimilarScraper.verifiedSourceMatch(
      title: 'Slow Horses', year: 2022, isTv: true,
      hit: hit('Slow Motion', 2022, true),
    ), isFalse);
    expect(BestSimilarScraper.verifiedSourceMatch(
      title: 'Slow Horses', year: 2022, isTv: true,
      hit: hit('Slow Horses', 2022, false),
    ), isFalse);
    expect(BestSimilarScraper.verifiedSourceMatch(
      title: 'Slow Horses', year: 2022, isTv: true,
      hit: hit('Slow Horses', 2010, true),
    ), isFalse);
    expect(BestSimilarScraper.verifiedSourceMatch(
      title: 'The Slow Horses', year: 2022, isTv: true,
      hit: hit('Slow Horses', 2022, true),
    ), isTrue);
  });
  testWidgets('real addon paginates only its originating catalog with '
      'the correct skip, then stops repeated pages', (tester) async {
    await tester.binding.setSurfaceSize(const Size(340, 245));
    MetadataService.clearCache();
    final paths = <String>[];
    MetadataService.catalogGetOverride = (uri) async {
      paths.add(uri.toString());
      expect(uri.host, 'catalog.example.test');
      expect(uri.path, '/catalog/series/featured-series/skip=2.json');
      return http.Response(jsonEncode({'metas': [
        {'id': 'tt12345', 'name': 'London Spy', 'type': 'series'},
        {'id': 'tt54321', 'name': 'The Bureau', 'type': 'series'},
      ]}), 200);
    };
    try {
      await tester.pumpWidget(MaterialApp(home: CatalogPage(section: section(
        'featured-series', supportsSkip: true,
        baseUrl: 'https://catalog.example.test',
      ))));
      await tester.pump();
      expect(visibleMovies(tester), ['London Spy', 'The Bureau']);
      expect(paths, isEmpty, reason: 'See All reuses the row as page one.');
      await tester.drag(find.byType(GridView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(paths, hasLength(1));
      expect(visibleMovies(tester), ['London Spy', 'The Bureau']);
      await tester.drag(find.byType(GridView), const Offset(0, -500));
      await tester.pump();
      expect(paths, hasLength(1),
        reason: 'An addon ignoring skip must not loop or show generic rows.');
    } finally {
      MetadataService.catalogGetOverride = null;
      MetadataService.clearCache();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    }
  });

}
