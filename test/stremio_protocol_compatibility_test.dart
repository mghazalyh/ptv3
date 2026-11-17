import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:playtorrio/models/addon/addon.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/metadata/metadata_service.dart';
import 'package:playtorrio/services/stream/stream_service.dart';

void main() {
  setUp(() {
    MetadataService.clearCache();
    MetadataService.catalogGetOverride = null;
    MetadataService.metaGetOverride = null;
    StreamService.streamGetOverride = null;
  });

  tearDown(() {
    MetadataService.clearCache();
    MetadataService.catalogGetOverride = null;
    MetadataService.metaGetOverride = null;
    StreamService.streamGetOverride = null;
  });

  test('advanced resource filters override manifest-wide types and prefixes',
      () {
    final manifest = AddonManifest.fromJson({
      'id': 'example.advanced',
      'name': 'Advanced',
      'version': '1.0.0',
      'resources': [
        {'name': 'meta', 'types': ['series'], 'idPrefixes': ['tt']},
        {'name': 'stream', 'types': ['movie']},
        'subtitles',
        'catalog',
      ],
      'types': ['movie', 'series'],
      'idPrefixes': ['tt'],
      'catalogs': [
        {'type': 'movie', 'id': 'home', 'name': 'Home'},
      ],
    });

    expect(manifest.supportsMeta, isTrue);
    expect(manifest.supportsRequest('meta', 'series', 'tt12345'), isTrue);
    expect(manifest.supportsRequest('meta', 'movie', 'tt12345'), isFalse);
    expect(manifest.supportsRequest('meta', 'series', 'custom:45'), isFalse);
    expect(manifest.supportsRequest('stream', 'movie', 'custom:45'), isTrue);
    expect(manifest.supportsRequest('stream', 'series', 'tt12345'), isFalse);
    expect(manifest.supportsRequest('subtitles', 'movie', 'tt12345'), isTrue);
    expect(manifest.supportsRequest('subtitles', 'movie', 'custom:45'), isFalse);
    expect(manifest.supportsRequest('catalog', 'movie', 'custom:45'), isTrue);

    final roundTrip = AddonManifest.fromJson(manifest.toJson());
    expect(roundTrip.supportsRequest('meta', 'series', 'custom:45'), isFalse);
    expect(roundTrip.supportsRequest('stream', 'movie', 'custom:45'), isTrue);
  });

  test('legacy extraSupported and extraRequired are not discarded', () {
    final catalog = AddonCatalog.fromJson({
      'id': 'older-search',
      'type': 'movie',
      'extraSupported': ['search', 'skip'],
      'extraRequired': ['search'],
    });
    expect(catalog.supportsSearch, isTrue);
    expect(catalog.supportsSkip, isTrue);
    expect(catalog.hasRequiredExtra('search'), isTrue);
    expect(catalog.isHomeEligible, isFalse);
    expect(AddonCatalog.fromJson(catalog.toJson()).isHomeEligible, isFalse);
  });

  test('catalog-only addons are valid without metadata or stream resource', () {
    final manifest = AddonManifest.fromJson({
      'id': 'example.catalog-only',
      'name': 'Catalog Only',
      'version': '1.0.0',
      'resources': ['catalog'],
      'types': ['movie', 'series'],
      'idPrefixes': ['tt'],
      'catalogs': [
        {'type': 'movie', 'id': 'provider'},
      ],
    });
    expect(manifest.supportsCatalog, isTrue);
    expect(manifest.supportsMeta, isFalse);
    expect(manifest.supportsStream, isFalse);
    expect(manifest.supportsRequest('meta', 'movie', 'tt12345'), isFalse);
    expect(manifest.catalogs.single.isHomeEligible, isTrue);
  });

  test('required search extra prevents a search-only catalog home request', () {
    final catalog = AddonCatalog.fromJson({
      'id': 'search-only',
      'type': 'series',
      'name': 'Search',
      'extra': [
        {'name': 'search', 'isRequired': true},
        {'name': 'skip'},
        {
          'name': 'genre',
          'options': ['Drama', 'Comedy'],
          'optionsLimit': 1,
        },
      ],
    });
    expect(catalog.hasRequiredExtra('search'), isTrue);
    expect(catalog.isHomeEligible, isFalse);
    expect(catalog.supportsSearch, isTrue);
    expect(catalog.supportsSkip, isTrue);
    expect(catalog.genres, ['Drama', 'Comedy']);
    final restored = AddonCatalog.fromJson(catalog.toJson());
    expect(restored.hasRequiredExtra('search'), isTrue);
    expect(restored.isHomeEligible, isFalse);
  });

  test('catalog query extras are URL-encoded into Stremio path segments',
      () async {
    Uri? requested;
    MetadataService.catalogGetOverride = (uri) async {
      requested = uri;
      return http.Response(jsonEncode({
        'metas': [
          {'id': 'tt100', 'name': 'Dark City', 'type': 'movie'},
          null,
          'garbage',
          {
            'id': 'tt101',
            'name': 'Second Film',
            'type': 'movie',
          },
        ],
      }), 200);
    };
    final movies = await MetadataService.fetchCatalog(
      baseUrl: 'https://catalog.example',
      type: 'movie',
      catalogId: 'my-catalog',
      searchTerm: 'Dark City & Co',
      genre: 'Sci-Fi',
      skip: 100,
    );
    expect(movies.length, 2);
    expect(movies.first.name, 'Dark City');
    expect(requested, isNotNull);
    final url = requested.toString();
    expect(url, contains('/catalog/movie/my-catalog/'));
    expect(url, contains('search=Dark%20City%20%26%20Co'));
    expect(url, contains('genre=Sci-Fi'));
    expect(url, contains('skip=100.json'));
  });

  test('invalid catalog entries do not poison a valid catalog', () async {
    MetadataService.catalogGetOverride = (_) async => http.Response(
      '{"metas":[false,{"id":"tt12","name":"Valid","type":"movie"}]}',
      200,
    );
    final items = await MetadataService.fetchCatalog(
      baseUrl: 'https://catalog.example',
      type: 'movie',
      catalogId: 'home',
    );
    expect(items.length, 1);
    expect(items.single.id, 'tt12');
  });

  test('stream requests only contact resource-compatible addons', () async {
    final manifest = AddonManifest.fromJson({
      'id': 'example.streams',
      'name': 'Stream Provider',
      'version': '1.0.0',
      'resources': [
        {'name': 'stream', 'types': ['series'], 'idPrefixes': ['tt']}
      ],
      'types': ['movie', 'series'],
      'catalogs': [],
    });
    final addon = InstalledAddon(
        baseUrl: 'https://streams.example', manifest: manifest);
    var requests = 0;
    StreamService.streamGetOverride = (_) async {
      requests++;
      return http.Response('{"streams":[]}', 200);
    };
    final wrongType =
        await StreamService.fetchAddonStreamsForTesting(addon, 'movie', 'tt11');
    final wrongId = await StreamService.fetchAddonStreamsForTesting(
        addon, 'series', 'custom:11');
    expect(wrongType, isEmpty);
    expect(wrongId, isEmpty);
    expect(requests, 0);

    await StreamService.fetchAddonStreamsForTesting(
        addon, 'series', 'tt11:1:1');
    expect(requests, 1);
  });

  test('malformed stream items do not discard other playable stream results',
      () async {
    final addon = InstalledAddon(
        baseUrl: 'https://streams.example',
        manifest: AddonManifest.fromJson({
          'id': 'example.streams',
          'name': 'Stream Provider',
          'version': '1.0.0',
          'resources': ['stream'],
          'types': ['movie'],
          'catalogs': [],
        }));
    StreamService.streamGetOverride = (_) async => http.Response(
        jsonEncode({
          'streams': [
            null,
            'invalid',
            {'name': 'broken', 'streams': 'invalid'},
            {'name': 'HTTP', 'url': 'https://video.example/film.mp4'},
            {'name': 'YT', 'ytId': 'abcdefghijk'},
            {'name': 'torrent', 'infoHash': 'abcde'},
          ],
        }),
        200);
    final items =
        await StreamService.fetchAddonStreamsForTesting(addon, 'movie', 'tt11');
    expect(items.length, 3);
    expect(items.any((entry) => entry.url == 'https://video.example/film.mp4'),
        isTrue);
    expect(items.any((entry) =>
        entry.externalUrl ==
        'https://www.youtube.com/watch?v=abcdefghijk'), isTrue);
  });

  test('Stremio stream behavior hints preserve proxy request headers', () {
    final stream = StreamSource.fromJson({
      'url': 'https://video.example/movie.m3u8',
      'behaviorHints': {
        'notWebReady': true,
        'proxyHeaders': {
          'request': {'Referer': 'https://video.example/'}
        }
      }
    }, 'Provider');
    expect(stream.headers?['Referer'], 'https://video.example/');
  });
}
