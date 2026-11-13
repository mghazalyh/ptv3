import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/config/torriodb_portable_sync.dart';

void main() {
  test('legacy portable settings gain monotonic validated revisions', () {
    expect(TorriodbPortableSync.nextSettingsRevision(null), 1);
    expect(TorriodbPortableSync.nextSettingsRevision(12), 13);
    expect(TorriodbPortableSync.nextSettingsRevision(2000000000),
        2000000000);
    final legacy = TorriodbPortableSync.parseSettings(jsonEncode({
      'schemaVersion': 1, 'initialized': true, 'addons': [],
    }));
    expect(legacy['syncRevision'], 0);
    final revised = TorriodbPortableSync.parseSettings(jsonEncode({
      'schemaVersion': 1, 'initialized': true, 'addons': [],
      'syncRevision': 4,
    }));
    expect(revised['syncRevision'], 4);
    for (final invalid in [-1, 'future', 2.5, 3000000000]) {
      expect(() => TorriodbPortableSync.parseSettings(jsonEncode({
        'schemaVersion': 1, 'initialized': true, 'addons': [],
        'syncRevision': invalid,
      })), throwsFormatException);
    }
  });

  test('portable settings preserve and validate section order', () {
    final doc = TorriodbPortableSync.parseSettings(jsonEncode({
      'schemaVersion': 1,
      'initialized': true,
      'addons': <Object>[],
      'homeSectionOrder': [
        'catalog:xperience:movie:movies',
        'recommendation:trakt_recommendations',
      ],
      'homeHiddenSections': ['catalog:xperience:movie:movies'],
    }));
    expect(doc['homeSectionOrder'], [
      'catalog:xperience:movie:movies',
      'recommendation:trakt_recommendations',
    ]);
    expect(doc['homeHiddenSections'],
      ['catalog:xperience:movie:movies']);
    expect(() => TorriodbPortableSync.parseSettings(jsonEncode({
      'schemaVersion': 1,
      'initialized': true,
      'addons': <Object>[],
      'homeSectionOrder': [null],
    })), throwsFormatException);
    expect(() => TorriodbPortableSync.parseSettings(jsonEncode({
      'schemaVersion': 1, 'initialized': true,
      'addons': <Object>[], 'homeHiddenSections': [null],
    })), throwsFormatException);
    expect(() => TorriodbPortableSync.parseSettings(jsonEncode({
      'schemaVersion': 1, 'initialized': true,
      'addons': <Object>[], 'homeHiddenSections': 'invalid',
    })), throwsFormatException);
    expect(TorriodbPortableSync.parseSettings(jsonEncode({
      'schemaVersion': 1, 'initialized': true, 'addons': <Object>[],
    })).containsKey('homeHiddenSections'), isFalse);
  });

  test('only exact authenticated private TorriODB may hold keys', () {
    const privateRepo = {
      'full_name': 'mghazalyh/torriodb',
      'private': true, 'default_branch': 'main',
    };
    expect(TorriodbPortableSync.isVerifiedPrivateRepository(privateRepo), isTrue);
    expect(TorriodbPortableSync.isVerifiedPrivateRepository({
      ...privateRepo, 'private': false,
    }), isFalse);
    expect(TorriodbPortableSync.isVerifiedPrivateRepository({
      ...privateRepo, 'full_name': 'mghazalyh/ptv3',
    }), isFalse);
    expect(TorriodbPortableSync.isVerifiedPrivateRepository({
      ...privateRepo, 'default_branch': 'other',
    }), isFalse);
  });

  test('accepts the private editable key vault schema', () {
    final doc = TorriodbPortableSync.parseKeys(jsonEncode({
      'schemaVersion': 1,
      'initialized': true,
      'providers': {
        'tmdb': {'apiKey': 'key-123'},
        'torbox': {'apiKey': ''},
      },
    }));
    expect((doc['providers'] as Map)['tmdb']['apiKey'], 'key-123');
    expect(TorriodbPortableSync.preferenceFields.containsKey('githubPat'),
        isFalse);
  });

  test('rejects bad schema, strange field types and oversized secrets', () {
    expect(() => TorriodbPortableSync.parseKeys('{}'), throwsFormatException);
    expect(() => TorriodbPortableSync.parseKeys(jsonEncode({
      'schemaVersion': 2, 'initialized': true, 'providers': {},
    })), throwsFormatException);
    expect(() => TorriodbPortableSync.parseKeys(jsonEncode({
      'schemaVersion': 1, 'initialized': true,
      'providers': {'tmdb': {'apiKey': []}},
    })), throwsFormatException);
    expect(() => TorriodbPortableSync.parseKeys(jsonEncode({
      'schemaVersion': 1, 'initialized': true,
      'providers': {'tmdb': {'apiKey': 'x' * 9000}},
    })), throwsFormatException);
  });

  test('concurrent/manual remote provider fields are retained', () {
    final merged = TorriodbPortableSync.mergeProviderEdits({
      'tmdb': {'apiKey': 'remote-manually-edited'},
      'torbox': {'apiKey': 'remote-torbox'},
      'futureProvider': {'apiKey': 'unknown-value'},
    }, {
      'tmdb': {'apiKey': 'device-edited'},
    }, {'tmdb'});
    expect((merged['tmdb'] as Map)['apiKey'], 'device-edited');
    expect((merged['torbox'] as Map)['apiKey'], 'remote-torbox');
    expect((merged['futureProvider'] as Map)['apiKey'], 'unknown-value');
  });

  test('backfills missing TorBox key without overwriting other cloud keys', () {
    final result = TorriodbPortableSync.backfillMissingProviderFields({
      'tmdb': {'apiKey': 'cloud-key'},
      'torbox': {'apiKey': ''},
    }, {
      'tmdb': {'apiKey': 'local-key'},
      'torbox': {'apiKey': 'local-torbox-key'},
    });
    expect((result['tmdb'] as Map)['apiKey'], 'cloud-key');
    expect((result['torbox'] as Map)['apiKey'], 'local-torbox-key');
  });

  test('portable settings normalize dock and source preferences', () {
    final parsed = TorriodbPortableSync.parseSettings(jsonEncode({
      'schemaVersion': 1, 'initialized': true, 'addons': [],
      'dockPreferences': {
        'visible': false, 'items': {'networks': false, 'manga': false},
      },
      'watchSourcePreferences': {
        'preset': 'Balanced',
        'movie': {'resolutions': ['4K','1080p']},
        'episode': {'resolutions': ['1080p']},
      },
    }));
    expect((parsed['dockPreferences'] as Map)['visible'], isFalse);
    expect((parsed['watchSourcePreferences'] as Map)['preset'], 'Balanced');
  });

  test('portable addons require a valid private manifest base URL', () {
    const manifest = {
      'id': 'user.catalog',
      'name': 'BingeCat',
      'version': '1.0',
      'resources': ['catalog'],
      'types': ['movie'],
      'idPrefixes': <String>[],
      'catalogs': <Object>[],
    };
    final data = jsonEncode({
      'schemaVersion': 1,
      'initialized': true,
      'addons': [
        {'baseUrl': 'https://bingecat.com/private/',
         'manifest': manifest, 'enableStreams': false,
         'personalizedCatalogTrial': true},
      ],
    });
    final parsed = TorriodbPortableSync.parseSettings(data);
    expect((parsed['addons'] as List).length, 1);
    expect(() => TorriodbPortableSync.parseSettings(jsonEncode({
      'schemaVersion': 1, 'initialized': true, 'addons': [
        {'baseUrl': 'http://invalid.local', 'manifest': manifest},
      ],
    })), throwsFormatException);
  });
}
