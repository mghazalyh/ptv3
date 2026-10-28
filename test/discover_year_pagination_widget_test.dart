import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/pages/search/advanced_discover_page.dart';
import 'package:playtorrio/services/metadata/series_run_service.dart';
import 'package:playtorrio/widgets/movie/series_year_label.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';

/// Finite pumps are required: image/cursor/loading animations can keep
/// scheduling frames, so pumpAndSettle is unsuitable for this page.
Future<void> pumpDiscoverFrames(WidgetTester tester) async {
  // SharedPreferences and TMDB's serialized request queue use real async
  // futures; pumping fake frame time alone never advances those futures.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  });
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'unit-test-key',
      'adv_discover_type': 'movie',
    });
    TmdbDiscoverService.instance.resetForTesting(spacing: Duration.zero);
    SeriesRunService.instance.resetForTesting();
  });

  tearDown(() {
    TmdbDiscoverService.instance.resetForTesting();
    SeriesRunService.instance.resetForTesting();
  });

  testWidgets('Load More appends exactly once without moving the scroll offset',
      (tester) async {
    tester.view.physicalSize = const Size(820, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requestedPages = <int>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      expect(uri.path, '/3/discover/movie');
      final page = int.parse(uri.queryParameters['page'] ?? '0');
      requestedPages.add(page);
      return http.Response(jsonEncode({
        'page': page,
        'total_pages': 2,
        'total_results': 40,
        'results': List.generate(20, (index) {
          final id = (page - 1) * 20 + index + 1;
          return {
            'id': id,
            'title': 'Movie $id',
            'release_date': '2006-01-01',
            'original_language': 'en',
            'origin_country': ['US'],
          };
        }),
      }), 200);
    };

    await tester.pumpWidget(const MaterialApp(home: AdvancedDiscoverPage()));
    await pumpDiscoverFrames(tester);
    final dynamic pageState = tester.state(find.byType(AdvancedDiscoverPage));
    expect(pageState.applied, isTrue,
        reason: 'Load state: key=${pageState.hasKey}, loading=${pageState.loading}, '
            'error=${pageState.error}, requested=$requestedPages');
    expect(requestedPages, [1]);

    final outerScroll = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    ).position;
    outerScroll.jumpTo(outerScroll.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Load More'), findsOneWidget);
    final before = outerScroll.pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.text('Load More'));
    await tester.pump();
    expect(outerScroll.pixels, closeTo(before, 0.5));

    await pumpDiscoverFrames(tester);
    expect(outerScroll.pixels, closeTo(before, 0.5));
    expect(requestedPages, [1, 2]);
    expect(find.text('Load More'), findsNothing);
  });

  testWidgets('ended TV result shows real airing years, not search year',
      (tester) async {
    tester.view.physicalSize = const Size(820, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'unit-test-key',
      'adv_discover_type': 'series',
      'adv_discover_from': '2026',
      'adv_discover_to': '2026',
    });

    final paths = <String>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      paths.add(uri.path);
      if (uri.path == '/3/discover/tv') {
        return http.Response(jsonEncode({
          'page': 1,
          'total_pages': 1,
          'total_results': 1,
          'results': [{
            'id': 123,
            'name': 'Finished drama',
            'first_air_date': '2006-01-01',
            'original_language': 'en',
            'origin_country': ['US'],
          }],
        }), 200);
      }
      if (uri.path == '/3/tv/123') {
        return http.Response(jsonEncode({
          'status': 'Ended',
          'first_air_date': '2006-01-01',
          'last_air_date': '2011-01-01',
        }), 200);
      }
      throw StateError('Unexpected TMDB request: ${uri.path}');
    };

    await tester.pumpWidget(const MaterialApp(home: AdvancedDiscoverPage()));
    await pumpDiscoverFrames(tester);
    final dynamic pageState = tester.state(find.byType(AdvancedDiscoverPage));
    expect(pageState.applied, isTrue,
        reason: 'TV state: key=${pageState.hasKey}, loading=${pageState.loading}, '
            'error=${pageState.error}, requested=$paths');
    final outerScroll = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    ).position;
    outerScroll.jumpTo(outerScroll.maxScrollExtent);
    await pumpDiscoverFrames(tester);
    expect(find.text('Finished drama'), findsOneWidget);
    expect(find.text('2006 - 2011'), findsOneWidget);
    expect(find.textContaining('Started 2006'), findsNothing);
    expect(paths, ['/3/discover/tv', '/3/tv/123']);
  });
  testWidgets('The Mentalist Search label resolves ended range without '
      'a TMDB key', (tester) async {
    SharedPreferences.setMockInitialValues({});
    SeriesRunService.instance.cinemetaGetOverride = (uri) async {
      expect(uri.path, '/meta/series/tt1196946.json');
      return http.Response(jsonEncode({'meta': {
        'id': 'tt1196946',
        'name': 'The Mentalist',
        'releaseInfo': '2008-2015',
      }}), 200);
    };
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SeriesYearLabel(
        imdbId: 'tt1196946', fallbackYear: '2008',
      )),
    ));
    expect(find.text('2008'), findsOneWidget);
    await pumpDiscoverFrames(tester);
    expect(find.text('2008 - 2015'), findsOneWidget);
  });


}
