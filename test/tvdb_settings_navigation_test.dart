import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard: v1.1.5 shipped the TVDB credential screen but omitted
/// the Settings tile that opened it, making the user's API key impossible
/// to configure. Assert BOTH the visible entry and destination.
void main() {
  test('main Settings exposes TVDB key page, on iOS and Windows', () {
    final settings = File('lib/pages/settings/settings_page.dart')
        .readAsStringSync();
    final destination = File('lib/pages/settings/tvdb_settings_page.dart')
        .readAsStringSync();

    expect(settings, contains("import 'tvdb_settings_page.dart';"));
    expect(
      RegExp(
        r"title: 'TVDB Series Metadata',[\s\S]*?"
        r'onTap: \(\) => _navigateTo\(const TvdbSettingsPage\(\)\),',
      ).hasMatch(settings),
      isTrue,
      reason: 'The TVDB key page must have a clickable entry in Settings.',
    );
    expect(destination, contains("labelText: 'TVDB v4 project API key'"));
    expect(destination, contains('Save TVDB credentials'));
    expect(destination, contains('TvdbSeriesService.instance.saveCredentials('));
    expect(destination, contains('Subscriber PIN (only if your key requires it)'));
  });
}
