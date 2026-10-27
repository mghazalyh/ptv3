import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/network_discover_service.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'fake-only-for-tests',
    });
    TmdbDiscoverService.instance.resetForTesting(spacing: Duration.zero);
  });
  tearDown(() => TmdbDiscoverService.instance.resetForTesting());

  const netflixMovie = {
    'provider_id': 8, 'provider_name': 'Netflix',
    'logo_path': '/netflix.png',
    'display_priorities': {'SG': 0, 'US': 0},
  };
  const primeMovie = {
    'provider_id': 9, 'provider_name': 'Amazon Prime Video',
    'logo_path': '/prime.png',
    'display_priorities': {'SG': 2, 'US': 3},
  };
  const usOnly = {
    'provider_id': 531, 'provider_name': 'Paramount Plus',
    'logo_path': '/paramount.png',
    'display_priorities': {'US': 8},
  };

  test('streaming providers use real TMDB ids, region, dedupe and both types',
      () async {
    final paths = <String>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      paths.add(uri.path);
      if (uri.path == '/3/watch/providers/movie') {
        return http.Response(jsonEncode({
          'results': [primeMovie, netflixMovie, usOnly],
        }), 200);
      }
      if (uri.path == '/3/watch/providers/tv') {
        return http.Response(jsonEncode({
          'results': [netflixMovie, usOnly],
        }), 200);
      }
      throw StateError('Unexpected endpoint ${uri.path}');
    };
    final singapore = await NetworkDiscoverService.instance.loadStreaming('SG');
    expect(singapore.map((x) => x.name), ['Netflix', 'Amazon Prime Video']);
    expect(singapore.first.movies, isTrue);
    expect(singapore.first.series, isTrue);
    expect(singapore.last.movies, isTrue);
    expect(singapore.last.series, isFalse);
    final us = await NetworkDiscoverService.instance.loadStreaming('US');
    expect(us.map((x) => x.name),
        containsAll(['Netflix', 'Amazon Prime Video', 'Paramount Plus']));
    expect(paths.length, 2, reason: 'Catalog responses are cached across regions');
  });

  test('selected provider movie requests regional, filtered Discover', () async {
    final uris = <Uri>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      uris.add(uri);
      return http.Response(jsonEncode({
        'page': 1, 'total_pages': 2, 'total_results': 24,
        'results': [
          {'id': 112, 'title': 'A movie', 'release_date': '2026-03-01',
            'poster_path': '/movie.png', 'vote_average': 7.4},
          {'id': 112, 'title': 'Duplicated movie'},
        ],
      }), 200);
    };
    const choice = NetworkChoice(
        id: 8, name: 'Netflix', source: NetworkSource.streaming);
    final query = NetworkDiscoverQuery(
      choice: choice, type: DiscoverType.movie,
      region: 'SG', feed: NetworkFeed.trending,
      now: DateTime.utc(2026, 10, 27),
    );
    expect(query.toQuery()['with_watch_providers'], '8');
    expect(query.toQuery()['watch_region'], 'SG');
    expect(query.toQuery()['primary_release_date.gte'], '2025-10-27');
    expect(query.toQuery().containsKey('with_networks'), isFalse);
    expect(query.explanation, contains('recent releases'));
    final result = await NetworkDiscoverService.instance.browse(query);
    expect(uris.single.path, '/3/discover/movie');
    expect(uris.single.queryParameters['with_watch_providers'], '8');
    expect(result.titles.single.tmdbId, 112);
    expect(result.titles.single.type, DiscoverType.movie);
    expect(result.totalPages, 2);
  });

  test('TV networks filter originals, no false streaming claim', () async {
    final uris = <Uri>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      uris.add(uri);
      return http.Response(jsonEncode({
        'page': 1, 'total_pages': 1, 'total_results': 1,
        'results': [
          {'id': 443, 'name': 'Mystery show',
            'first_air_date': '2020-01-01'},
        ],
      }), 200);
    };
    const showtime = NetworkChoice(id: 389, name: 'Showtime',
        source: NetworkSource.tvNetwork);
    final query = NetworkDiscoverQuery(
      choice: showtime, type: DiscoverType.series,
      region: 'US', feed: NetworkFeed.hot,
      now: DateTime.utc(2026, 10, 27),
    );
    expect(query.toQuery()['with_networks'], '389');
    expect(query.toQuery()['vote_count.gte'], '100');
    expect(query.toQuery()['sort_by'], 'vote_average.desc');
    expect(query.toQuery().containsKey('with_watch_providers'), isFalse);
    final result = await NetworkDiscoverService.instance.browse(query);
    expect(uris.single.path, '/3/discover/tv');
    expect(result.titles.single.type, DiscoverType.series);
  });

  test('network queries do not accept impossible combinations', () {
    const showtime = NetworkChoice(id: 389, name: 'Showtime',
        source: NetworkSource.tvNetwork);
    expect(() => NetworkDiscoverQuery(
      choice: showtime, type: DiscoverType.movie, region: 'US',
      feed: NetworkFeed.popular, now: DateTime.utc(2026, 10, 27),
    ).toQuery(), throwsFormatException);
    const invalid = NetworkChoice(
      id: 8, name: 'Netflix', source: NetworkSource.streaming);
    expect(() => NetworkDiscoverQuery(
      choice: invalid, type: DiscoverType.movie, region: 'invalid',
      feed: NetworkFeed.popular, now: DateTime.utc(2026, 10, 27),
    ).toQuery(), throwsFormatException);
  });

  test('missing TMDB key makes no network API requests', () async {
    await TmdbDiscoverService.instance.saveKey('');
    var calls = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      calls++; return http.Response('{}', 200);
    };
    await expectLater(NetworkDiscoverService.instance.loadStreaming('US'),
        throwsFormatException);
    expect(calls, 0);
  });

  test('429 cooldown prevents provider discover retries', () async {
    var calls = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      calls++; return http.Response('{}', 429, headers: {'retry-after':'90'});
    };
    const choice = NetworkChoice(
      id: 8, name: 'Netflix', source: NetworkSource.streaming);
    final q = NetworkDiscoverQuery(
      choice: choice, type: DiscoverType.series,
      region: 'SG', feed: NetworkFeed.popular,
      now: DateTime.utc(2026, 10, 27),
    );
    await expectLater(NetworkDiscoverService.instance.browse(q),
        throwsFormatException);
    await expectLater(NetworkDiscoverService.instance.browse(q),
        throwsFormatException);
    expect(calls, 1);
  });
}
