import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/continue_watching/continue_watching_item.dart';
import 'package:playtorrio/models/my_list/my_list_item.dart';
import 'package:playtorrio/services/continue_watching/continue_watching_service.dart';
import 'package:playtorrio/services/continue_watching/watched_history_service.dart';
import 'package:playtorrio/services/home/home_page_settings.dart';
import 'package:playtorrio/services/metadata/bestsimilar_scraper.dart';
import 'package:playtorrio/services/my_list/my_list_service.dart';

BSItem _related(int id, String title, int year, {bool series = false}) {
  final item = BSItem(
    id: id,
    slug: 'related',
    title: title,
    year: year,
    rating: 8.0,
    voteCount: '1000',
    thumbUrl: 'https://images.example/poster.jpg',
    similarityPercent: 90,
    genre: null,
    country: null,
    duration: null,
    story: null,
    styleTags: const [],
    plotTags: const [],
    audienceTags: const [],
    timeTags: const [],
    placeTags: const [],
  );
  // Verified classification means the suggestion never needs a live lookup.
  item.tmdbMediaType = series ? 'tv' : 'movie';
  return item;
}

BSDetails _sourceDetails(int id, String name, int year,
    List<BSItem> similar) {
  return BSDetails(
    id: id,
    slug: 'source',
    title: name,
    year: year,
    rating: 8.0,
    voteCount: '1000',
    thumbUrl: '',
    story: null,
    genre: null,
    country: null,
    duration: null,
    styleTags: const [],
    plotTags: const [],
    audienceTags: const [],
    timeTags: const [],
    placeTags: const [],
    blurb: null,
    similar: similar,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HomePageSettings.enableSimilar.value = true;
    HomePageSettings.enableWatchingSimilar.value = true;
    HomePageSettings.enableTraktRecommendations.value = true;
    HomePageSettings.enableSimklRecommendations.value = true;
    MyListService.items.value = [
      MyListItem(
        imdbId: 'tt0137523',
        title: 'Fight Club',
        type: 'movie',
        year: 1999,
        addedAt: DateTime.utc(2026),
      ),
    ];
    ContinueWatchingService.activeItems.value = [
      ContinueWatchingItem(
        id: 'tt112807736',
        title: 'Severance',
        type: 'series',
        year: '2022',
        positionSeconds: 500,
        totalDurationSeconds: 3000,
        lastWatchedAt: DateTime.utc(2026),
        isTorrent: false,
      ),
    ];
    WatchedHistoryService.items.value = [];

    BestSimilarScraper.findBestOverride = ({
      required String title,
      int? year,
      required bool isTv,
    }) async {
      if (title == 'Fight Club' && year == 1999 && !isTv) {
        return const BSAutocompleteHit(
          id: 1, slug: '1-fight-club', label: 'Fight Club (1999)',
          title: 'Fight Club', year: 1999, isTv: false,
          url: '/movies/1-fight-club',
        );
      }
      if (title == 'Severance' && year == 2022 && isTv) {
        return const BSAutocompleteHit(
          id: 2, slug: '2-severance', label: 'Severance (2022)',
          title: 'Severance', year: 2022, isTv: true,
          url: '/movies/2-severance',
        );
      }
      return null;
    };
    BestSimilarScraper.fetchDetailsOverride = ({
      required int id,
      required String slug,
    }) async {
      if (id == 1 && slug == '1-fight-club') {
        return _sourceDetails(1, 'Fight Club', 1999, [
          _related(101, 'Se7en', 1995),
          _related(102, 'The Game', 1997),
        ]);
      }
      if (id == 2 && slug == '2-severance') {
        return _sourceDetails(2, 'Severance', 2022, [
          _related(103, 'Silo', 2023, series: true),
          _related(104, 'Dark', 2017, series: true),
        ]);
      }
      return null;
    };
  });

  tearDown(() {
    BestSimilarScraper.findBestOverride = null;
    BestSimilarScraper.fetchDetailsOverride = null;
    MyListService.items.value = [];
    ContinueWatchingService.activeItems.value = [];
    WatchedHistoryService.items.value = [];
    HomePageSettings.enableSimilar.value = true;
    HomePageSettings.enableWatchingSimilar.value = true;
    HomePageSettings.enableTraktRecommendations.value = true;
    HomePageSettings.enableSimklRecommendations.value = true;
  });

  test('My List and Continue Watching produce independently verified sections',
      () async {
    final list = await HomePageSettings.fetchBestSimilarSection(
        forceRefresh: true);
    expect(list, isNotNull);
    expect(list!.title, contains('Fight Club'));
    expect(list.movies.map((item) => item.name).toList(), ['Se7en', 'The Game']);
    expect(list.movies.every((item) => item.type == 'movie'), isTrue);

    final watching = await HomePageSettings.fetchContinueWatchingSimilarSection(
        forceRefresh: true);
    expect(watching, isNotNull);
    expect(watching!.title, contains('Severance'));
    expect(watching.movies.map((item) => item.name).toList(), ['Silo', 'Dark']);
    expect(watching.movies.every((item) => item.type == 'series'), isTrue);
  });

  test('mismatched recommendation identity is rejected, not misattributed',
      () async {
    BestSimilarScraper.fetchDetailsOverride = ({
      required int id,
      required String slug,
    }) async => _sourceDetails(
      id, 'Wrong Series', 2022,
      [_related(500, 'Something Else', 2022)],
    );
    final watching = await HomePageSettings.fetchContinueWatchingSimilarSection(
        forceRefresh: true);
    expect(watching, isNull);
  });

  test('recommendation toggles disable every corresponding fetch', () async {
    HomePageSettings.enableSimilar.value = false;
    HomePageSettings.enableWatchingSimilar.value = false;
    HomePageSettings.enableTraktRecommendations.value = false;
    HomePageSettings.enableSimklRecommendations.value = false;

    expect(await HomePageSettings.fetchBestSimilarSection(
        forceRefresh: true), isNull);
    expect(await HomePageSettings.fetchContinueWatchingSimilarSection(
        forceRefresh: true), isNull);
    expect(await HomePageSettings.fetchTraktRecommendationsSection(
        forceRefresh: true), isNull);
    expect(await HomePageSettings.fetchSimklRecommendationsSection(
        forceRefresh: true), isNull);
  });
}
