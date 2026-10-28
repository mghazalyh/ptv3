import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/series_run_service.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'test-only-key',
    });
    TmdbDiscoverService.instance.resetForTesting(spacing: Duration.zero);
    SeriesRunService.instance.resetForTesting();
  });

  tearDown(() {
    TmdbDiscoverService.instance.resetForTesting();
    SeriesRunService.instance.resetForTesting();
  });

  test('ended series uses real first and last airing years', () {
    final run = SeriesRun.fromTmdb({
      'first_air_date': '2006-09-20',
      'last_air_date': '2011-11-18',
      'status': 'Ended',
    });
    expect(run.displayYear(fallbackYear: '2026'), '2006 - 2011');
  });

  test('cancelled and canceled series both show their actual end year', () {
    for (final status in ['Canceled', 'Cancelled']) {
      final run = SeriesRun.fromTmdb({
        'first_air_date': '2019-01-01',
        'last_air_date': '2021-05-10',
        'status': status,
      });
      expect(run.displayYear(fallbackYear: '2026'), '2019 - 2021');
    }
  });

  test('returning series shows debut only even with last episode date', () {
    final run = SeriesRun.fromTmdb({
      'first_air_date': '2006-01-01',
      'last_air_date': '2026-01-01',
      'status': 'Returning Series',
    });
    expect(run.displayYear(fallbackYear: '2025'), '2006');
  });

  test('missing/invalid dates never invent a run or use filter years', () {
    expect(SeriesRun.fromTmdb({
      'status': 'Ended',
      'first_air_date': '2006-01-01',
    }).displayYear(), '2006');
    expect(SeriesRun.fromTmdb({
      'status': 'Ended',
      'first_air_date': '2015-01-01',
      'last_air_date': '2011-01-01',
    }).displayYear(), '2015');
    expect(SeriesRun.fromTmdb({
      'status': 'Ended',
      'first_air_date': '',
      'last_air_date': '',
    }).displayYear(), 'Year unknown');
    expect(SeriesRun.fromTmdb({
      'status': 'Ended',
      'first_air_date': '2006-01-01',
      'last_air_date': '2006-05-01',
    }).displayYear(), '2006 - 2006');
  });

  test('uses verified TMDB ID and caches repeat series detail requests',
      () async {
    final paths = <String>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      paths.add(uri.path);
      if (uri.path == '/3/tv/123') {
        return http.Response(jsonEncode({
          'first_air_date': '2006-01-01',
          'last_air_date': '2011-01-01',
          'status': 'Ended',
        }), 200);
      }
      throw StateError('Unexpected endpoint');
    };

    final first = await SeriesRunService.instance.resolve(tmdbId: 123);
    final second = await SeriesRunService.instance.resolve(tmdbId: 123);
    expect(first?.displayYear(), '2006 - 2011');
    expect(second?.displayYear(), '2006 - 2011');
    expect(paths, ['/3/tv/123']);
  });

  test('no verified ID makes no TMDB network request', () async {
    var requests = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      requests++;
      return http.Response('{}', 200);
    };
    final run = await SeriesRunService.instance.resolve(imdbId: 'unverified');
    expect(run, isNull);
    expect(requests, 0);
  });

  test('without TMDB key keeps the existing provider year', () async {
    SharedPreferences.setMockInitialValues({});
    final run = await SeriesRunService.instance.resolve(tmdbId: 123);
    expect(run, isNull);
  });
}
