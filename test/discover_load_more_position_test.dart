import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/pages/search/advanced_discover_page.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Load More appends results and scrolls forward without losing the previous page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 860));
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'fake-unit-test-key',
    });
    final service = TmdbDiscoverService.instance;
    service.resetForTesting(spacing: Duration.zero);
    var requests = 0;
    service.httpGetOverride = (uri, headers) async {
      requests++;
      final page = int.parse(uri.queryParameters['page'] ?? '1');
      return http.Response(jsonEncode({
        'page': page,
        'total_pages': 3,
        'total_results': 60,
        'results': List.generate(20, (i) => {
          'id': page * 100 + i,
          'title': 'Film $page - $i',
          'release_date': '2026-01-01',
          'poster_path': null,
          'vote_average': 7.5,
        }),
      }), 200);
    };

    try {
      await tester.pumpWidget(const MaterialApp(home: AdvancedDiscoverPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('60 matches'), findsOneWidget);
      expect(find.textContaining('Page 1/3'), findsOneWidget);

      final results = find.byKey(const Key('advanced-discover-results'));
      final outerScrollable = find.descendant(
        of: results, matching: find.byType(Scrollable)).first;
      final scroll = tester.state<ScrollableState>(outerScrollable);
      await tester.ensureVisible(find.text('Load More'));
      await tester.pumpAndSettle();
      final oldOffset = scroll.position.pixels;
      expect(oldOffset, greaterThan(0));

      await tester.tap(find.text('Load More'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(requests, 2);
      expect(find.textContaining('Page 2/3'), findsOneWidget);
      expect(scroll.position.pixels, greaterThan(oldOffset),
        reason: 'Advance smoothly into new titles rather than staying stuck.');
      expect(scroll.position.pixels, lessThan(scroll.position.maxScrollExtent),
        reason: 'Do not jump to the far bottom and lose context.');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      service.resetForTesting();
      await tester.binding.setSurfaceSize(null);
    }
  });
}
