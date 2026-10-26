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
