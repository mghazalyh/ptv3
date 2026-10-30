import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'unit-test-only',
    });
    TmdbDiscoverService.instance.resetForTesting(spacing: Duration.zero);
  });
  tearDown(() => TmdbDiscoverService.instance.resetForTesting());

  test('Farscape cannot enter 2025-2026 TV first-premiere results', () async {
    final requests = <Uri>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      requests.add(uri);
      return http.Response(jsonEncode({
        'page': 1, 'total_pages': 1, 'total_results': 3,
        'results': [
          {'id': 1, 'name': 'Farscape',
            'first_air_date': '1999-03-19', 'genre_ids': [10765],
            'origin_country': ['US','AU'], 'original_language': 'en'},
          {'id': 2, 'name': 'New science fiction',
            'first_air_date': '2026-08-11', 'genre_ids': [10765],
            'origin_country': ['US'], 'original_language': 'en'},
          {'id': 3, 'name': 'Unrelated documentary',
            'first_air_date': '2026-05-01', 'genre_ids': [99],
            'origin_country': ['US'], 'original_language': 'en'},
        ]
      }), 200);
    };
    const filters = DiscoverFilters(type: DiscoverType.series,
        fromYear: 2025, toYear: 2026, genreId: 10765,
        country: 'US', sort: 'vote_count.desc');
    final result = await TmdbDiscoverService.instance.browse(filters);
    expect(requests, hasLength(1));
    final query = requests.single.queryParameters;
    expect(query['first_air_date.gte'], '2025-01-01');
    expect(query['first_air_date.lte'], '2026-12-31');
    expect(query.containsKey('air_date.gte'), isFalse);
    expect(result.titles.map((item) => item.tmdbId), [2]);
  });

  test('TMDB weekly trending uses ranked feed and applies all local filters',
      () async {
    final requests = <Uri>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      requests.add(uri);
      return http.Response(jsonEncode({
        'page': 1, 'total_pages': 5, 'total_results': 100,
        'results': [
          {'id': 20, 'name': 'Older trending',
            'first_air_date': '1999-03-19', 'genre_ids': [10765],
            'origin_country': ['US'], 'original_language': 'en',
            'popularity': 900},
          {'id': 21, 'name': 'Matching recent trend',
            'first_air_date': '2026-03-01', 'genre_ids': [10765],
            'origin_country': ['US'], 'original_language': 'en',
            'popularity': 35},
          {'id': 22, 'name': 'Different origin',
            'first_air_date': '2026-02-01', 'genre_ids': [10765],
            'origin_country': ['KR'], 'original_language': 'ko',
            'popularity': 999},
          {'id': 23, 'name': 'Another matching trend',
            'first_air_date': '2025-11-01', 'genre_ids': [10765],
            'origin_country': ['US'], 'original_language': 'en',
            'popularity': 75},
        ],
      }), 200);
    };
    const filters = DiscoverFilters(type: DiscoverType.series,
        sort: 'trending.week', fromYear: 2025, toYear: 2026,
        country: 'US', originalLanguage: 'en', genreId: 10765);
    expect(filters.buildUri().path, '/3/trending/tv/week');
    final result = await TmdbDiscoverService.instance.browse(filters);
    expect(requests.single.path, '/3/trending/tv/week');
    expect(requests.single.queryParameters.containsKey('with_genres'), isFalse);
    expect(result.titles.map((item) => item.tmdbId), [21, 23],
        reason: 'TMDB trend rank must be preserved; no popularity re-sort');
    expect(result.totalPages, 5);
    expect(filters.withPage(2).toQuery()['page'], '2');
  });

  test('trending title filter stays on trending endpoint, not popularity search',
      () async {
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      expect(uri.path, '/3/trending/tv/week');
      expect(uri.queryParameters.containsKey('query'), isFalse);
      return http.Response(jsonEncode({
        'page': 1, 'total_pages': 1, 'total_results': 2,
        'results': [
          {'id': 43, 'name': 'Elsewhere',
            'first_air_date': '2026-01-01'},
          {'id': 44, 'name': 'Blade Runner 2099',
            'first_air_date': '2026-08-01'},
        ],
      }), 200);
    };
    const filters = DiscoverFilters(type: DiscoverType.series,
      sort: 'trending.week', titleQuery: 'blade runner');
    expect(filters.buildUri().path, '/3/trending/tv/week');
    final result = await TmdbDiscoverService.instance.browse(filters);
    expect(result.titles.map((x) => x.tmdbId), [44]);
  });

  test('unreleased badge reflects a future date, not a speculative title', () {
    final futureYear = DateTime.now().year + 2;
    final future = DiscoverTitle.parse({
      'id': 300, 'name': 'Upcoming TV', 'first_air_date': '$futureYear-01-01',
    }, DiscoverType.series);
    final released = DiscoverTitle.parse({
      'id': 301, 'name': 'Older TV', 'first_air_date': '1999-03-19',
    }, DiscoverType.series);
    final unknown = DiscoverTitle.parse({
      'id': 302, 'name': 'Date not announced', 'first_air_date': '',
    }, DiscoverType.series);
    expect(future.isUnreleased, isTrue);
    expect(released.isUnreleased, isFalse);
    expect(unknown.isUnreleased, isFalse);
  });
}
