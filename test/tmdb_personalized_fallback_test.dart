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
