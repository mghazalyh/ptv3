import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';

void main() {
  final service = TmdbDiscoverService.instance;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'example-only-test-key',
    });
    service.resetForTesting(spacing: Duration.zero);
  });
  tearDown(() => service.resetForTesting());

  test('movie matches require exact name and unique release identity', () {
    final entries = [
      {'id': 31, 'title': 'Station One', 'release_date': '2020-03-02'},
      {'id': 32, 'title': 'One Else', 'release_date': '2020-03-03'},
    ];
    expect(TmdbDiscoverService.selectMovieId(entries, 'Station One', 2020), 31);
    expect(TmdbDiscoverService.selectMovieId(entries, 'Station', 2020), isNull);
    expect(TmdbDiscoverService.selectMovieId(entries, 'Station One', 2010), isNull);
    expect(TmdbDiscoverService.selectMovieId([
      ...entries, {'id': 33, 'title': 'Station One', 'release_date': '2020-01-01'},
    ], 'Station One', 2020), isNull);
  });

  test('movie fallback calls TMDB recommendations, then similar if sparse', () async {
    final paths = <String>[];
    service.httpGetOverride = (uri, headers) async {
      expect(uri.queryParameters['api_key'], 'example-only-test-key');
      paths.add(uri.path);
      if (uri.path == '/3/search/movie') {
        return http.Response(jsonEncode({'results': [
          {'id': 100, 'title': 'Source Movie',
            'release_date': '2020-01-01'},
        ]}), 200);
      }
      if (uri.path == '/3/movie/100/recommendations') {
        return http.Response(jsonEncode({'results': [
          {'id': 200, 'title': 'Suggested Movie',
            'release_date': '2021-01-01', 'poster_path': '/x.jpg',
            'vote_average': 8.1},
        ]}), 200);
      }
      if (uri.path == '/3/movie/100/similar') {
        return http.Response(jsonEncode({'results': [
          {'id': 300, 'title': 'Other Movie',
            'release_date': '2019-01-01', 'poster_path': '/y.jpg'},
        ]}), 200);
      }
      return http.Response('{}', 404);
    };
    final suggestions = await service.relatedTitles(
      title: 'Source Movie', type: DiscoverType.movie, startYear: 2020);
    expect(suggestions.map((x) => x.tmdbId), [200, 300]);
    expect(paths, containsAll(['/3/search/movie',
      '/3/movie/100/recommendations', '/3/movie/100/similar']));
  });

  test('See All respects independent TMDB recommendation feed page limits', () async {
    final requests = <String>[];
    service.httpGetOverride = (uri, headers) async {
      requests.add('${uri.path}?${uri.queryParameters['page'] ?? ''}');
      if (uri.path == '/3/tv/42/recommendations') {
        final page = uri.queryParameters['page'];
        return http.Response(jsonEncode({
          'total_pages': 2,
          'results': [
            {
              'id': page == '1' ? 201 : 203,
              'name': page == '1' ? 'Series One' : 'Series Three',
              'first_air_date': '2020-01-01',
              'poster_path': '/one.jpg',
            },
          ],
        }), 200);
      }
      if (uri.path == '/3/tv/42/similar') {
        return http.Response(jsonEncode({
          'total_pages': 1,
          'results': [
            {'id': 202, 'name': 'Series Two', 'poster_path': '/two.jpg',
              'first_air_date': '2018-03-02'},
          ],
        }), 200);
      }
      return http.Response('{}', 404);
    };
    final first = await service.moreRelatedTitles(
      title: 'Exact Source', type: DiscoverType.series,
      tmdbId: 42, page: 1);
    expect(first.items.map((x) => x.tmdbId), [201, 202]);
    expect(first.hasMore, isTrue);
    final second = await service.moreRelatedTitles(
      title: 'Exact Source', type: DiscoverType.series,
      tmdbId: 42, page: 2);
    expect(second.items.map((x) => x.tmdbId), [203]);
    expect(second.hasMore, isFalse);
    expect(requests, containsAll([
      '/3/tv/42/recommendations?1', '/3/tv/42/similar?1',
      '/3/tv/42/recommendations?2',
    ]));
    // The similar feed reports only one page. Do not request it again.
    expect(requests, isNot(contains('/3/tv/42/similar?2')));
    expect(requests.where((p) => p.contains('search/') ||
        p.contains('catalog/')), isEmpty);
  });

  test('See All refuses an ambiguous source rather than generic suggestions',
      () async {
    var requestedRecommendations = false;
    service.httpGetOverride = (uri, headers) async {
      if (uri.path.contains('recommendations') ||
          uri.path.contains('/similar')) {
        requestedRecommendations = true;
      }
      return http.Response(jsonEncode({'results': [
        {'id': 7, 'name': 'Wrong Title', 'first_air_date': '2019-01-01'}
      ]}), 200);
    };
    final page = await service.moreRelatedTitles(
      title: 'Real Title', type: DiscoverType.series, page: 1,
      startYear: 2019,
    );
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
    expect(requestedRecommendations, isFalse);
  });

  test('never fetch TMDB suggestions for ambiguous source identity', () async {
    var calledRecommendations = false;
    service.httpGetOverride = (uri, headers) async {
      if (uri.path.contains('/recommendations')) calledRecommendations = true;
      return http.Response(jsonEncode({'results': [
        {'id': 10, 'title': 'Similar but Wrong',
          'release_date': '2020-01-01'},
      ]}), 200);
    };
    final suggestions = await service.relatedTitles(
      title: 'Correct Title', type: DiscoverType.movie, startYear: 2020);
    expect(suggestions, isEmpty);
    expect(calledRecommendations, isFalse);
  });
}
