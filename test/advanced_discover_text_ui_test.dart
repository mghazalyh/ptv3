import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('advanced Discover has optional text and combined filter controls', () {
    final ui = File('lib/pages/search/advanced_discover_page.dart')
        .readAsStringSync();
    expect(ui, contains('Movie or TV show title (optional)'));
    expect(ui, contains('titleController.text.trim()'));
    expect(ui, contains('titleQuery: titleController.text.trim()'));
    expect(ui, contains("'adv_discover_query'"));
    expect(ui, contains('onSubmitted: (_) => _browse(reset: true)'));
    expect(ui, contains('_appliedFilters!.withPage(page + 1)'));
    expect(ui, contains('Search Titles & Apply Filters'));
    expect(ui, isNot(contains('Started $debut · Episodes')));
    expect(ui, isNot(contains('_discoverScroll.animateTo(')));
    expect(ui, contains('if ((loading && !applied) || openingId != null)'));
    final discover = File('lib/pages/discover/discover_page.dart')
        .readAsStringSync();
    expect(discover, contains('showSeriesRunYears: true'));
    final search = File('lib/pages/search/search_page.dart')
        .readAsStringSync();
    expect(search, contains('showSeriesRunYears: true'));
    expect(ui, contains("country: country.isEmpty ? null : country"));
    expect(ui, contains("originalLanguage: language.isEmpty ? null : language"));
    expect(ui, contains('fromYear: _year(fromController)'));
    expect(ui, contains('toYear: _year(toController)'));
  });
}
