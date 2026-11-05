import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';
import 'package:playtorrio/services/metadata/tvdb_series_service.dart';
import 'package:playtorrio/services/metadata/similar_recommendations_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'fake-key-not-secret',
    });
    TmdbDiscoverService.instance.resetForTesting(
        spacing: Duration.zero, cooldown: const Duration(seconds: 5));
  });

  tearDown(() => TmdbDiscoverService.instance.resetForTesting());

  test('The Order and other series year ranges parse their first year', () {
    expect(SimilarRecommendationsService.firstReleaseYear('2019–2020'), 2019);
    expect(SimilarRecommendationsService.firstReleaseYear('2019-2020'), 2019);
    expect(SimilarRecommendationsService.firstReleaseYear('2019–'), 2019);
    expect(SimilarRecommendationsService.firstReleaseYear('2023'), 2023);
    expect(SimilarRecommendationsService.firstReleaseYear('1999-2001'), 1999);
    expect(SimilarRecommendationsService.firstReleaseYear('unknown'), isNull);
  });

  test('TMDB identification rejects unrelated and wrong-year TV titles', () {
    final hits = <dynamic>[
      {'id': 99, 'name': 'Another Order', 'first_air_date': '2019-01-01'},
      {'id': 44, 'name': 'The Order', 'first_air_date': '2001-01-01'},
      {'id': 55, 'name': 'The Order', 'first_air_date': '2019-03-01'},
    ];
    expect(TmdbDiscoverService.selectSeriesId(hits, 'The Order', 2019), 55);
    expect(TmdbDiscoverService.selectSeriesId(hits, 'The Order', 2020), isNull);
    expect(TmdbDiscoverService.selectSeriesId(hits, 'Missing', 2019), isNull);
  });

  test('related TV returns real recommendations then similar, cached', () async {
    final paths = <String>[];
    final tmdb = TmdbDiscoverService.instance;
    tmdb.httpGetOverride = (uri, headers) async {
      paths.add(uri.path);
      switch (uri.path) {
        case '/3/find/tt8826128':
          return http.Response(jsonEncode({
            'tv_results': [
              {'id': 270, 'name': 'The Order',
               'first_air_date': '2019-03-07'}
            ],
          }), 200);
        case '/3/tv/270/recommendations':
          return http.Response(jsonEncode({
            'results': [
              {'id': 311, 'name': 'Mystery Academy',
               'first_air_date': '2019-01-01',
               'poster_path': '/academy.jpg', 'genre_ids': [10765]},
              {'id': 270, 'name': 'The Order',
               'first_air_date': '2019-01-01',
               'poster_path': '/self.jpg'},
            ],
          }), 200);
        case '/3/tv/270/similar':
          return http.Response(jsonEncode({
            'results': [
              {'id': 311, 'name': 'Mystery Academy',
               'poster_path': '/academy.jpg'},
              {'id': 412, 'name': 'Witching Hour',
               'poster_path': '/witch.jpg',
               'first_air_date': '2018-01-01',
               'genre_ids': [9648, 10765]},
            ],
          }), 200);
        default:
          return http.Response('{}', 404);
      }
    };
    final results = await tmdb.relatedSeries(
      title: 'The Order', startYear: 2019, imdbId: 'tt8826128');
    expect(paths, [
      '/3/find/tt8826128', '/3/tv/270/recommendations', '/3/tv/270/similar'
    ]);
    final converted = SimilarRecommendationsService.fromTmdbTitles(
        results, 'The Order');
    expect(converted.map((x) => x.title), ['Mystery Academy', 'Witching Hour']);
    expect(converted.every((x) => x.mediaType == 'series'), isTrue);
    expect(converted.every((x) => x.similarityPercent == null), isTrue);
    expect(converted.last.tmdbId, 412);

    await tmdb.relatedSeries(
      title: 'The Order', startYear: 2019, imdbId: 'tt8826128');
    expect(paths.length, 3, reason: '24-hour cache avoids repeated provider calls');
  });

  test('TMDB movie cards are movies, exclude the seed and TV results', () {
    final cards = SimilarRecommendationsService.fromTmdbTitles([
      const DiscoverTitle(tmdbId: 11, title: 'Example Film',
          type: DiscoverType.movie, poster: 'https://img.test/self.jpg'),
      const DiscoverTitle(tmdbId: 12, title: 'Different Film',
          type: DiscoverType.movie, poster: 'https://img.test/movie.jpg',
          premiereYear: 2024, originalLanguage: 'ko'),
      const DiscoverTitle(tmdbId: 12, title: 'Different Film',
          type: DiscoverType.movie, poster: 'https://img.test/movie.jpg'),
      const DiscoverTitle(tmdbId: 13, title: 'Different Series',
          type: DiscoverType.series, poster: 'https://img.test/series.jpg'),
    ], 'Example Film', type: DiscoverType.movie);
    expect(cards, hasLength(1));
    expect(cards.single.tmdbId, 12);
    expect(cards.single.mediaType, 'movie');
    expect(cards.single.originalLanguage, 'ko');
    expect(cards.single.similarityPercent, isNull);
  });

  test('movie recommendations paginate verified film endpoints without duplicates', () async {
    final paths = <String>[];
    final tmdb = TmdbDiscoverService.instance;
    tmdb.httpGetOverride = (uri, headers) async {
      paths.add('${uri.path}:${uri.queryParameters['page'] ?? ''}');
      if (uri.path == '/3/find/tt1234567') {
        return http.Response(jsonEncode({
          'movie_results': [
            {'id': 101, 'title': 'Example Film', 'release_date': '2022-03-04'},
          ],
        }), 200);
      }
      final page = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
      if (uri.path == '/3/movie/101/recommendations') {
        return http.Response(jsonEncode({
          'total_pages': 2,
          'results': [
            {'id': page == 1 ? 102 : 104,
             'title': page == 1 ? 'Film One' : 'Film Three',
             'poster_path': '/film.jpg', 'release_date': '2020-01-01'},
          ],
        }), 200);
      }
      if (uri.path == '/3/movie/101/similar') {
        return http.Response(jsonEncode({
          'total_pages': 2,
          'results': [
            {'id': page == 1 ? 102 : 105,
             'title': page == 1 ? 'Film One' : 'Film Four',
             'poster_path': '/movie.jpg', 'release_date': '2019-01-01'},
          ],
        }), 200);
      }
      return http.Response('{}', 404);
    };
    final first = await tmdb.moreRelatedTitles(
      title: 'Example Film', type: DiscoverType.movie,
      page: 1, imdbId: 'tt1234567', startYear: 2022);
    expect(first.items.map((x) => x.tmdbId), [102]);
    expect(first.items.every((x) => x.type == DiscoverType.movie), isTrue);
    expect(first.hasMore, isTrue);
    final second = await tmdb.moreRelatedTitles(
      title: 'Example Film', type: DiscoverType.movie,
      page: 2, imdbId: 'tt1234567', startYear: 2022);
    expect(second.items.map((x) => x.tmdbId), [104, 105]);
    expect(second.hasMore, isFalse);
    expect(paths, [
      '/3/find/tt1234567:',
      '/3/movie/101/recommendations:1', '/3/movie/101/similar:1',
      '/3/movie/101/recommendations:2', '/3/movie/101/similar:2',
    ]);
  });

  test('series pagination uses TV endpoints and verified TVDB ID', () async {
    final paths = <String>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      paths.add(uri.path);
      if (uri.path == '/3/tv/270/recommendations' ||
          uri.path == '/3/tv/270/similar') {
        return http.Response(jsonEncode({
          'total_pages': 1,
          'results': [
            {'id': uri.path.endsWith('similar') ? 272 : 271,
             'name': 'Another Show', 'poster_path': '/tv.jpg'},
          ],
        }), 200);
      }
      return http.Response('{}', 404);
    };
    final page = await TmdbDiscoverService.instance.moreRelatedTitles(
      title: 'The Order', type: DiscoverType.series,
      page: 1, verifiedTvdbTmdbId: 270);
    expect(page.items.map((x) => x.tmdbId), [271, 272]);
    expect(page.items.every((x) => x.type == DiscoverType.series), isTrue);
    expect(page.hasMore, isFalse);
    expect(paths, ['/3/tv/270/recommendations', '/3/tv/270/similar']);
  });


  test('BestSimilar supports user-requested TMDB continuation when configured',
      () async {
    expect(await SimilarRecommendationsService.canLoadMoreFromTmdb(), isTrue);
    await TmdbDiscoverService.instance.saveKey('');
    expect(await SimilarRecommendationsService.canLoadMoreFromTmdb(), isFalse);
  });

  test('movie and series recommendations continue beyond page 10', () async {
    final requested = <String>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      final page = int.parse(uri.queryParameters['page'] ?? '1');
      requested.add('${uri.path}:$page');
      final isSeries = uri.path.contains('/tv/');
      final isSimilar = uri.path.endsWith('/similar');
      final lastPage = isSimilar ? 12 : 2;
      if (page > lastPage) return http.Response('{}', 400);
      return http.Response(jsonEncode({
        'total_pages': lastPage,
        'results': [
          {
            'id': (isSeries ? 5000 : 1000) + page + (isSimilar ? 100 : 0),
            if (isSeries) 'name': 'Series $page'
            else 'title': 'Film $page',
            'poster_path': '/poster.jpg',
            if (isSeries) 'first_air_date': '2020-01-01'
            else 'release_date': '2020-01-01',
          }
        ],
      }), 200);
    };

    for (final type in [DiscoverType.movie, DiscoverType.series]) {
      final isSeries = type == DiscoverType.series;
      final kind = isSeries ? 'tv' : 'movie';
      final id = isSeries ? 270 : 101;
      final seed = isSeries ? 'Example Series' : 'Example Film';
      final first = await TmdbDiscoverService.instance.moreRelatedTitles(
          title: seed, type: type, page: 1, tmdbId: id);
      expect(first.items, hasLength(2));
      expect(first.hasMore, isTrue);

      final eleventh = await TmdbDiscoverService.instance.moreRelatedTitles(
          title: seed, type: type, page: 11, tmdbId: id);
      expect(eleventh.items, hasLength(1));
      expect(eleventh.items.single.type, type);
      expect(eleventh.hasMore, isTrue);

      final twelfth = await TmdbDiscoverService.instance.moreRelatedTitles(
          title: seed, type: type, page: 12, tmdbId: id);
      expect(twelfth.items, hasLength(1));
      expect(twelfth.hasMore, isFalse);

      expect(requested, isNot(contains('/3/$kind/$id/recommendations:11')));
      expect(requested, isNot(contains('/3/$kind/$id/recommendations:12')));
      expect(requested, contains('/3/$kind/$id/similar:11'));
      expect(requested, contains('/3/$kind/$id/similar:12'));
    }
  });

  test('missing TMDB key never calls provider', () async {
    await TmdbDiscoverService.instance.saveKey('');
    var requests = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      requests++;
      return http.Response('{}', 200);
    };
    final result = await TmdbDiscoverService.instance.relatedSeries(
      title: 'The Order', startYear: 2019);
    expect(result, isEmpty);
    expect(requests, 0);
  });

  test('TMDB 429 blocks any follow-up fallback traffic', () async {
    var calls = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      calls++;
      return http.Response('{}', 429, headers: {'retry-after': '90'});
    };
    await expectLater(
      TmdbDiscoverService.instance.relatedSeries(
        title: 'The Order', startYear: 2019, tmdbId: 270),
      throwsFormatException,
    );
    expect(calls, 1);
    await expectLater(
      TmdbDiscoverService.instance.relatedSeries(
        title: 'Another Show', startYear: 2018, tmdbId: 271),
      throwsFormatException,
    );
    expect(calls, 1);
  });

  test('TVDB metadata offers optional genre-informed candidate ordering', () {
    final seed = TvdbSeriesInfo.fromExtended({
      'id': 212,
      'genres': [
        {'id': 1, 'name': 'Fantasy'},
        {'id': 2, 'name': 'Mystery'},
      ],
      'remoteIds': [
        {'sourceName': 'The Movie Database', 'id': '270'},
      ],
    }, 'The Order', 2019)!;
    expect(seed.tmdbId, 270);
    expect(seed.id, 212);
    expect(seed.genreOverlap(const DiscoverTitle(
      tmdbId: 1, title: 'Crossover', type: DiscoverType.series,
      genreIds: [10765, 9648])), 2);
    final choices = [
      const DiscoverTitle(tmdbId: 1, title: 'Ordinary',
          type: DiscoverType.series, genreIds: [35]),
      const DiscoverTitle(tmdbId: 2, title: 'Mystery',
          type: DiscoverType.series, genreIds: [10765, 9648]),
    ];
    expect(seed.prioritize(choices).first.tmdbId, 2);
  });
}
