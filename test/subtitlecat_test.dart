import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/subtitles/subtitlecat_service.dart';

/// The release suite must be deterministic and independent of SubtitleCat or
/// Google Translate uptime. Explicit manual integration testing can be enabled
/// with --dart-define=PLAYTORRIO_RUN_LIVE_SUBTITLECAT=true.
/// Never enable this flag in the iOS signing/release workflow.
const bool _runLiveSubtitleCat = bool.fromEnvironment(
  'PLAYTORRIO_RUN_LIVE_SUBTITLECAT',
  defaultValue: false,
);

void main() {
  group('SubtitleCat deterministic query contract', () {
    test('movie query includes the exact positive release year', () {
      expect(
        SubtitleCatService.buildQuery(title: 'Inception', year: 2010),
        'Inception 2010',
      );
    });

    test('normalizes whitespace without changing title identity', () {
      expect(
        SubtitleCatService.buildQuery(
          title: '  The   Walking\tDead  ',
          year: 2010,
        ),
        'The Walking Dead 2010',
      );
    });

    test('episode identity supersedes movie year', () {
      expect(
        SubtitleCatService.buildQuery(
          title: 'The Walking Dead',
          year: 2010,
          season: 2,
          episode: 12,
        ),
        'The Walking Dead S02E12',
      );
    });

    test('preserves large season and episode numbers', () {
      expect(
        SubtitleCatService.buildQuery(
          title: 'Show',
          season: 125,
          episode: 104,
        ),
        'Show S125E104',
      );
    });

    test('unknown or nonpositive release years are omitted', () {
      expect(SubtitleCatService.buildQuery(title: 'Inception'), 'Inception');
      expect(
        SubtitleCatService.buildQuery(title: 'Inception', year: 0),
        'Inception',
      );
      expect(
        SubtitleCatService.buildQuery(title: 'Inception', year: -1),
        'Inception',
      );
    });

    test('partial episode identity does not invent an episode', () {
      expect(
        SubtitleCatService.buildQuery(
          title: 'Show',
          year: 2020,
          season: 2,
        ),
        'Show 2020',
      );
    });
  });

  // Live web scraping and machine translation are integration checks, not
  // deterministic release gates. A provider HTTP 500 must not break iOS IPA
  // compilation, signing, artifact publication or unrelated functionality.
  test(
    'SubtitleCat scraper, source fetch and translation (live opt-in only)',
    () async {
      final savedOverrides = HttpOverrides.current;
      try {
        // Flutter's test HTTP overrides deliberately prevent external calls.
        // Lift them only for an explicitly enabled provider integration run.
        HttpOverrides.global = null;
        final entries = await SubtitleCatService.instance.searchAndExtract(
          title: 'Inception',
          year: 2010,
        );

        expect(entries, isNotEmpty);
        final directEntries =
            entries.where((entry) => !entry.isTranslated).toList();
        final translatedEntries =
            entries.where((entry) => entry.isTranslated).toList();
        expect(directEntries, isNotEmpty);
        expect(translatedEntries, isNotEmpty);

        final translated = await SubtitleCatService.instance.translateSrt(
          origUrl: translatedEntries.first.origUrl,
          targetLang: translatedEntries.first.code,
        );
        expect(translated, isNotEmpty);
        expect(translated, contains('-->'));
      } finally {
        HttpOverrides.global = savedOverrides;
      }
    },
    skip: !_runLiveSubtitleCat,
  );
}
