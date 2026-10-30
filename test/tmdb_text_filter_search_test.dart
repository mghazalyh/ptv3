import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'fake-unit-test-credential',
    });
    TmdbDiscoverService.instance.resetForTesting(spacing: Duration.zero);
  });
  tearDown(() => TmdbDiscoverService.instance.resetForTesting());

  test('optional blank text preserves existing Discover filters and URI', () {
    const f = DiscoverFilters(
      type: DiscoverType.series,
      country: 'US',
      originalLanguage: 'en',
      fromYear: 2020,
      toYear: 2026,
    );
    expect(f.hasTitleQuery, isFalse);
    expect(f.buildUri().path, '/3/discover/tv');
    expect(f.toQuery()['air_date.gte'], '2020-01-01');
    expect(f.toQuery()['air_date.lte'], '2026-12-31');
    expect(f.toQuery()['with_origin_country'], 'US');
    expect(f.toQuery().containsKey('query'), isFalse);
  });

  test('title text uses search endpoint; retains other filters separately', () {
    const f = DiscoverFilters(
      titleQuery: '  The Order  ',
      type: DiscoverType.series, country: 'US',
      originalLanguage: 'en', fromYear: 2019, toYear: 2020,
      sort: 'vote_count.desc',
    );
    expect(f.hasTitleQuery, isTrue);
    expect(f.buildUri().path, '/3/search/tv');
    final params = f.toQuery();
    expect(params['query'], 'The Order');
    expect(params['include_adult'], 'false');
    expect(params.containsKey('with_origin_country'), isFalse,
        reason: 'TMDB search cannot accept Discover-only country filters.');
    expect(params.containsKey('sort_by'), isFalse);
    expect(f.withPage(3).toQuery()['page'], '3');
    expect(f.withPage(3).titleQuery, f.titleQuery);
    expect(f.withPage(3).country, 'US');

    expect(const DiscoverFilters(
      type: DiscoverType.movie, titleQuery: 'Blade',
      fromYear: 2000, toYear: 2000,
    ).toQuery()['primary_release_year'], '2000');
    expect(const DiscoverFilters(
      type: DiscoverType.series, titleQuery: 'Breaking Bad',
      fromYear: 2013, toYear: 2013,
    ).toQuery()['year'], '2013');
  });

  test('one TV year allows older returning series but rejects ended ones', () async {
    final urls = <Uri>[];
    final service = TmdbDiscoverService.instance;
    service.httpGetOverride = (uri, headers) async {
      urls.add(uri);
      if (uri.path == '/3/tv/20') {
        return http.Response(jsonEncode({
          'first_air_date': '2010-01-01',
          'last_air_date': '2026-04-01',
          'status': 'Returning Series',
        }), 200);
      }
      if (uri.path == '/3/tv/22') {
        return http.Response(jsonEncode({
          'first_air_date': '1999-03-19',
          'last_air_date': '2004-10-18',
          'status': 'Ended',
        }), 200);
      }
      return http.Response(jsonEncode({
        'page': 1, 'total_pages': 1, 'total_results': 2,
        'results': [
          {
            'id': 20, 'name': 'Returning US show',
            'first_air_date': '2010-01-01',
            'original_language': 'en', 'origin_country': ['US'],
            'popularity': 50, 'vote_count': 300, 'vote_average': 8.0,
          },
          {
            'id': 21, 'name': 'Wrong country',
            'first_air_date': '2026-05-10',
            'original_language': 'en', 'origin_country': ['KR'],
            'popularity': 200, 'vote_count': 300,
          },
          {
            'id': 22, 'name': 'Old US show Farscape',
            'first_air_date': '1999-03-19',
            'original_language': 'en', 'origin_country': ['US'],
            'popularity': 400, 'vote_count': 300,
          },
        ],
      }), 200);
    };
    const filters = DiscoverFilters(
      type: DiscoverType.series,
      titleQuery: 'returning',
      fromYear: 2026,
      toYear: 2026,
      country: 'US',
      originalLanguage: 'en',
    );
    final result = await service.browse(filters);
    expect(urls.map((uri) => uri.path),
        ['/3/search/tv', '/3/tv/20', '/3/tv/22']);
    expect(urls.first.queryParameters['year'], '2026');
    expect(result.titles.map((e) => e.tmdbId), [20]);
    expect(result.totalPages, 1);
  });

  test('movie title + country verifies production origin with cached details',
      () async {
    final visited = <String>[];
    final service = TmdbDiscoverService.instance;
    service.httpGetOverride = (uri, headers) async {
      visited.add(uri.path);
      if (uri.path == '/3/search/movie') {
        return http.Response(jsonEncode({
          'page': 1, 'total_pages': 2, 'total_results': 4,
          'results': [
            {'id': 31, 'title': 'French film', 'release_date': '2022-01-01',
             'original_language': 'fr', 'vote_count': 111,
             'vote_average': 7.0},
            {'id': 32, 'title': 'Other film', 'release_date': '2022-01-01',
             'original_language': 'fr', 'vote_count': 111,
             'vote_average': 8.0},
            {'id': 33, 'title': 'Old film', 'release_date': '1994-01-01',
             'original_language': 'fr', 'vote_count': 111},
            {'id': 34, 'title': 'Wrong language', 'release_date': '2022-01-01',
             'original_language': 'en', 'vote_count': 111},
          ],
        }), 200);
      }
      if (uri.path == '/3/movie/31') {
        return http.Response(jsonEncode({'production_countries': [
          {'iso_3166_1': 'FR'}]}), 200);
      }
      if (uri.path == '/3/movie/32') {
        return http.Response(jsonEncode({'production_countries': [
          {'iso_3166_1': 'US'}]}), 200);
      }
      throw StateError('Unexpected TMDB endpoint: ${uri.path}');
    };
    const filters = DiscoverFilters(
      type: DiscoverType.movie, titleQuery: 'film',
      fromYear: 2020, toYear: 2026,
      country: 'FR', originalLanguage: 'fr', sort: 'vote_average.desc',
    );
    final result = await service.browse(filters);
    expect(result.titles.map((e) => e.tmdbId), [31]);
    expect(visited, ['/3/search/movie', '/3/movie/31', '/3/movie/32'],
        reason: 'Do not fetch details for prefiltered year/language misses.');
    await service.browse(filters);
    expect(visited.length, 3, reason: 'Repeated searches hit the cached pages.');
    expect(result.totalPages, 2,
        reason: 'Pagination must stay attached to raw text-search pages.');
  });

  test('multi-year TV text search accepts earlier premiere only with '
      'relevant episode airing', () async {
    final calls = <String>[];
    final service = TmdbDiscoverService.instance;
    service.httpGetOverride = (uri, headers) async {
      calls.add(uri.path);
      if (uri.path == '/3/tv/5') {
        return http.Response(jsonEncode({
          'last_air_date': '2010-01-01',
          'first_air_date': '2007-06-01',
          'status': 'Ended',
        }), 200);
      }
      return http.Response(jsonEncode({
        'page': 1, 'total_pages': 1, 'total_results': 3,
        'results': [
          {'id': 4, 'name': 'Range match', 'first_air_date': '2021-06-01',
           'original_language': 'en', 'origin_country': ['GB'],
           'popularity': 2, 'vote_average': 7.5, 'vote_count': 250},
          {'id': 5, 'name': 'Started earlier', 'first_air_date': '2007-06-01',
           'original_language': 'en', 'origin_country': ['GB'],
           'popularity': 15, 'vote_count': 200},
          {'id': 6, 'name': 'Low votes', 'first_air_date': '2022-06-01',
           'original_language': 'en', 'origin_country': ['GB'],
           'popularity': 50, 'vote_count': 2},
        ],
      }), 200);
    };
    const f = DiscoverFilters(
      type: DiscoverType.series, titleQuery: 'Range',
      fromYear: 2020, toYear: 2026, country: 'GB',
      originalLanguage: 'en', sort: 'vote_average.desc',
    );
    final result = await service.browse(f);
    expect(calls, ['/3/search/tv', '/3/tv/5']);
    expect(result.titles.map((x) => x.tmdbId), [4]);
  });

  test('search honors TMDB 429 backoff with no automatic retry', () async {
    var calls = 0;
    final service = TmdbDiscoverService.instance;
    service.httpGetOverride = (uri, headers) async {
      calls++;
      return http.Response('{}', 429, headers: {'retry-after': '90'});
    };
    await expectLater(service.browse(const DiscoverFilters(
      titleQuery: 'The Order', type: DiscoverType.series)),
      throwsFormatException);
    await expectLater(service.browse(const DiscoverFilters(
      titleQuery: 'Another Series', type: DiscoverType.series)),
      throwsFormatException);
    expect(calls, 1);
  });
}
