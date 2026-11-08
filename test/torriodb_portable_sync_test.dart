import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/config/torriodb_portable_sync.dart';

void main() {
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
