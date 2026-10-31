import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/series_run_service.dart';
import 'package:playtorrio/widgets/movie/similar_year_type_label.dart';
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

  test('card enrichment budget limits unique lookups per minute', () async {
    var requests = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      requests++;
      return http.Response(jsonEncode({
        'first_air_date': '2006-01-01',
        'last_air_date': '2011-01-01',
        'status': 'Ended',
      }), 200);
    };

    // The 25th card must WAIT for a free slot, not be permanently skipped.
    SeriesRunService.instance.resetForTesting(
      maxPerWindow: 24,
      window: const Duration(milliseconds: 40),
    );
    final pending = [
      for (var id = 1; id <= 25; id++)
        SeriesRunService.instance.resolve(tmdbId: id),
    ];
    final runs = await Future.wait(pending);
    expect(requests, 25);
    expect(runs.map((r) => r?.displayYear()).toSet(), {'2006 - 2011'});
  });

  test('The Mentalist shows 2008 - 2015 via exact IMDb metadata without '
      'a local TMDB key', () async {
    SharedPreferences.setMockInitialValues({});
    var lookedUp = 0;
    SeriesRunService.instance.cinemetaGetOverride = (uri) async {
      lookedUp++;
      expect(uri.host, 'v3-cinemeta.strem.io');
      expect(uri.path, '/meta/series/tt1196946.json');
      return http.Response(jsonEncode({
        'meta': {
          'id': 'tt1196946',
          'name': 'The Mentalist',
          'releaseInfo': '2008-2015',
        }
      }), 200);
    };
    final first = await SeriesRunService.instance.resolve(
        imdbId: 'tt1196946');
    final again = await SeriesRunService.instance.resolve(
        imdbId: 'tt1196946');
    expect(first?.displayYear(fallbackYear: '2008'), '2008 - 2015');
    expect(again?.displayYear(fallbackYear: '2008'), '2008 - 2015');
    expect(lookedUp, 1);
  });

  test('Cinemeta will not attach another show\'s run to an IMDb ID', () async {
    SharedPreferences.setMockInitialValues({});
    SeriesRunService.instance.cinemetaGetOverride = (uri) async =>
        http.Response(jsonEncode({'meta': {
          'id': 'tt9999999',
          'releaseInfo': '2008-2015',
        }}), 200);
    final found = await SeriesRunService.instance.resolve(
        imdbId: 'tt1196946');
    expect(found, isNull);
  });

  test('ended TMDB detail can use verified last episode air date', () {
    final run = SeriesRun.fromTmdb({
      'status': 'Ended',
      'first_air_date': '2008-09-23',
      'last_air_date': '',
      'last_episode_to_air': {'air_date': '2015-02-18'},
    });
    expect(run.displayYear(), '2008 - 2015');
  });

  test('open-ended provider releaseInfo does not claim an end year', () {
    expect(SeriesRun.fromCinemeta({
      'releaseInfo': '2008-',
    }).displayYear(), '2008');
    expect(SeriesRun.fromCinemeta({
      'releaseInfo': '2008-2015',
    }).displayYear(), '2008 - 2015');
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

  testWidgets('related TMDB ended series shows verified end year and type',
      (tester) async {
    final paths = <String>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      paths.add(uri.path);
      return http.Response(jsonEncode({
        'first_air_date': '2006-09-25',
        'last_air_date': '2010-02-08',
        'status': 'Ended',
      }), 200);
    };

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 160,
          child: SimilarYearTypeLabel(
            mediaType: 'series',
            premiereYear: 2006,
            tmdbId: 101,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2006 - 2010'), findsOneWidget);
    expect(find.text(' · Series'), findsOneWidget);
    expect(paths, ['/3/tv/101']);
  });

  testWidgets('related TMDB ongoing series does not invent ending year',
      (tester) async {
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      return http.Response(jsonEncode({
        'first_air_date': '2016-07-15',
        'last_air_date': '2026-10-01',
        'status': 'Returning Series',
      }), 200);
    };

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 160,
          child: SimilarYearTypeLabel(
            mediaType: 'series',
            premiereYear: 2016,
            tmdbId: 102,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2016'), findsOneWidget);
    expect(find.text(' · Series'), findsOneWidget);
    expect(find.textContaining('2016 -'), findsNothing);
  });

  testWidgets('related films and unresolved IDs retain existing labels',
      (tester) async {
    var requests = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      requests++;
      return http.Response('{}', 200);
    };
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SimilarYearTypeLabel(
              mediaType: 'movie',
              premiereYear: 2021,
              tmdbId: 222,
            ),
            SimilarYearTypeLabel(
              mediaType: 'series',
              premiereYear: 2020,
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2021 · Movie'), findsOneWidget);
    expect(find.text('2020 · Series'), findsOneWidget);
    expect(requests, 0);
  });
}
