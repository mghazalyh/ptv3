import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:playtorrio/models/movie/movie_detail.dart';
import 'package:playtorrio/services/metadata/metadata_service.dart';

void main() {
  setUp(() {
    MetadataService.clearCache();
    MetadataService.metaGetOverride = null;
    MetadataService.catalogGetOverride = null;
  });

  tearDown(() {
    MetadataService.metaGetOverride = null;
    MetadataService.catalogGetOverride = null;
    MetadataService.clearCache();
  });

  test('broken optional links and videos do not invalidate playable meta', () {
    final detail = MovieDetail.fromJson({
      'id': 'tt12345',
      'type': 'series',
      'name': 'Example Series',
      'links': {'unexpected': true},
      'videos': [
        'bad item',
        {'title': 'No ID'},
        {
          'id': 'tt12345:1:1',
          'title': 'Episode One',
          'season': 1,
          'episode': 1,
          'streams': {'unexpected': true},
        },
        {
          'id': 'tt12345:1:2',
          'title': 'Episode Two',
          'season': 1,
          'episode': 2,
          'streams': [
            'invalid',
            {'name': 'bad stream', 'sources': {'unexpected': true}},
          ],
        },
      ],
    });
    expect(detail.name, 'Example Series');
    expect(detail.links, isEmpty);
    expect(detail.videos.length, 3);
    expect(detail.videos[1].id, 'tt12345:1:1');
    expect(detail.videos[1].streams, isEmpty);
    expect(detail.videos[2].id, 'tt12345:1:2');
  });

  test('malformed optional fields still allow primary addon metadata', () async {
    MetadataService.metaGetOverride = (uri) async => http.Response(
          jsonEncode({
            'meta': {
              'id': 'tt12345',
              'type': 'movie',
              'name': 'Example Film',
              'videos': 'not-an-array',
              'links': 'not-an-array',
            }
          }),
          200,
        );

    final resolved = await MetadataService.resolveCatalogMeta(
      baseUrl: 'https://catalog.invalid',
      type: 'movie',
      id: 'tt12345',
      title: 'Example Film',
    );
    expect(resolved, isNotNull);
    expect(resolved!.baseUrl, 'https://catalog.invalid');
    expect(resolved.detail.id, 'tt12345');
    expect(resolved.detail.videos, isEmpty);
  });

  test('missing addon meta falls back to same IMDb ID in Cinemeta', () async {
    final requests = <String>[];
    MetadataService.metaGetOverride = (uri) async {
      requests.add(uri.toString());
      if (uri.host == 'catalog.invalid') {
        return http.Response('{"meta":[]}', 200);
      }
      return http.Response(jsonEncode({
        'meta': {
          'id': 'tt12345',
          'name': 'Example Film',
          'type': 'movie',
        }
      }), 200);
    };
    final resolved = await MetadataService.resolveCatalogMeta(
      baseUrl: 'https://catalog.invalid',
      type: 'movie',
      id: 'tt12345',
      title: 'Example Film',
    );
    expect(resolved, isNotNull);
    expect(resolved!.baseUrl, 'https://v3-cinemeta.strem.io');
    expect(resolved.detail.id, 'tt12345');
    expect(requests.length, 2);
    expect(requests.last, contains('/meta/movie/tt12345.json'));
  });

  test('provider-specific IDs recover only through matching title and year', () async {
    final metaRequests = <String>[];
    MetadataService.metaGetOverride = (uri) async {
      metaRequests.add(uri.toString());
      if (uri.host == 'catalog.invalid') return http.Response('', 404);
      return http.Response(jsonEncode({
        'meta': {
          'id': 'tt33333',
          'name': 'Matching Film',
          'type': 'movie',
          'releaseInfo': '2024',
        }
      }), 200);
    };
    MetadataService.catalogGetOverride = (uri) async {
      if (uri.path.contains('/movie/')) {
        return http.Response(jsonEncode({
          'metas': [
            {
              'id': 'tt33333',
              'name': 'Matching Film',
              'type': 'movie',
              'releaseInfo': '2024',
            }
          ]
        }), 200);
      }
      return http.Response('{"metas":[]}', 200);
    };
    final resolved = await MetadataService.resolveCatalogMeta(
      baseUrl: 'https://catalog.invalid',
      type: 'movie',
      id: 'provider:opaque-item',
      title: 'Matching Film',
      year: 2024,
    );
    expect(resolved, isNotNull);
    expect(resolved!.detail.id, 'tt33333');
    expect(metaRequests, hasLength(2));
    expect(metaRequests.last, isNot(contains('provider%3Aopaque-item')));
  });

  test('mismatched title cannot silently resolve to another film', () async {
    MetadataService.metaGetOverride = (_) async => http.Response('', 404);
    MetadataService.catalogGetOverride = (uri) async =>
        http.Response(jsonEncode({
          'metas': [
            {'id': 'tt99999', 'name': 'Different Film', 'type': 'movie'}
          ]
        }), 200);

    final resolved = await MetadataService.resolveCatalogMeta(
      baseUrl: 'https://catalog.invalid',
      type: 'movie',
      id: 'custom:123',
      title: 'Actual Film',
      year: 2024,
    );
    expect(resolved, isNull);
  });

  test('mismatched release year cannot silently resolve another release',
      () async {
    MetadataService.metaGetOverride = (_) async => http.Response('', 404);
    MetadataService.catalogGetOverride = (_) async =>
        http.Response(jsonEncode({
          'metas': [
            {
              'id': 'tt99999',
              'name': 'Same Film',
              'type': 'movie',
              'releaseInfo': '1998',
            }
          ]
        }), 200);
    final resolved = await MetadataService.resolveCatalogMeta(
      baseUrl: 'https://catalog.invalid',
      type: 'movie',
      id: 'custom:123',
      title: 'Same Film',
      year: 2024,
    );
    expect(resolved, isNull);
  });
}
