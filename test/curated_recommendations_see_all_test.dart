import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/addon/addon.dart';
import 'package:playtorrio/models/movie/movie.dart';
import 'package:playtorrio/models/movie/movie_section.dart';
import 'package:playtorrio/pages/catalog/catalog_page.dart';
import 'package:playtorrio/widgets/movie/movie_card.dart';

MovieSection section({
  required String catalogId,
  required bool curated,
  required List<Movie> movies,
}) => MovieSection(
  title: 'Because you have "Slow Horses" on your list',
  subtitle: 'Recommendations based on Slow Horses',
  contentType: 'series',
  addonBaseUrl: 'https://v3-cinemeta.strem.io',
  catalog: AddonCatalog(
    type: 'series',
    id: catalogId,
    genres: const [],
    supportsSearch: false,
    supportsSkip: false,
  ),
  movies: movies,
  isCurated: curated,
);

void main() {
  test('ordinary addon catalogs are not treated as curated', () {
    expect(section(catalogId: 'popular', curated: false, movies: []).isCurated,
        isFalse);
  });

  testWidgets('See All renders the actual ranked related titles, not a generic catalog',
      (tester) async {
    final related = section(
      catalogId: 'bestsimilar_list', // Not a real Stremio catalog.
      curated: true,
      movies: [
        Movie(id: 'bestsimilar_42', name: 'Spy Thriller A',
            type: 'series', addonBaseUrl: 'https://v3-cinemeta.strem.io'),
        Movie(id: 'bestsimilar_43', name: 'Spy Thriller B',
            type: 'series', addonBaseUrl: 'https://v3-cinemeta.strem.io'),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: CatalogPage(section: related),
    ));
    await tester.pump();

    final cards = tester.widgetList<MovieCard>(find.byType(MovieCard)).toList();
    expect(cards.map((c) => c.movie.name),
        containsAllInOrder(['Spy Thriller A', 'Spy Thriller B']));
    expect(cards, hasLength(2));
    // A fake catalog ID cannot be queried remotely; the grid shows the
    // exact curated recommendations instead of unknown generic content.
    expect(find.text('Because you have "Slow Horses" on your list'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('curated See All filters its own results locally', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CatalogPage(section: section(
        catalogId: 'bestsimilar_watching',
        curated: true,
        movies: [
          Movie(id: 'a', name: 'Berlin Station', type: 'series', addonBaseUrl: ''),
          Movie(id: 'b', name: 'Liaison', type: 'series', addonBaseUrl: ''),
        ],
      )),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Liaison');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    final cards = tester.widgetList<MovieCard>(find.byType(MovieCard)).toList();
    expect(cards.map((c) => c.movie.name).toList(), ['Liaison']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
