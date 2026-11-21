import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:playtorrio/models/addon/addon.dart';
import 'package:playtorrio/models/movie/movie.dart';
import 'package:playtorrio/models/movie/movie_detail.dart';
import 'package:playtorrio/services/subtitles/providers/stremio_subtitle_provider.dart';
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

  test('Unattended native probe resolves only one enabled TV addon', () async {
    final manifest = AddonManifest.fromJson({
      'id': 'example.tv', 'name': 'Direct TV', 'version': '1.0.0',
      'resources': [
        {'name': 'stream', 'types': ['tv'], 'idPrefixes': ['nltv:']}
      ],
      'types': ['tv'], 'catalogs': [],
    });
    final installed = InstalledAddon(
        baseUrl: 'https://installed.example', manifest: manifest);
    final requests = <String>[];
    StreamService.streamGetOverride = (uri) async {
      requests.add(uri.toString());
      return http.Response(jsonEncode({'streams': [
        {'url': 'https://cdn.example/direct.m3u8'},
        {'infoHash': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'},
        {'url': 'magnet:?xt=urn:btih:aaaaaaaa'},
      ]}), 200);
    };
    final live = await StreamService.fetchLiveStreamsFromAddon(
        installed, 'nltv:us:Example.us');
    expect(live, hasLength(1));
    expect(live.single.url, 'https://cdn.example/direct.m3u8');
    expect(requests.single,
        'https://installed.example/stream/tv/nltv%3Aus%3AExample.us.json');
    expect(await StreamService.fetchLiveStreamsFromAddon(
        installed, 'tt12345'), isEmpty);
    expect(requests, hasLength(1));
    installed.enableStreams = false;
    expect(await StreamService.fetchLiveStreamsFromAddon(
        installed, 'nltv:us:Example.us'), isEmpty);
    expect(requests, hasLength(1));
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

  test('custom IDs resolve through explicitly compatible meta addons',
      () async {
    final requests = <String>[];
    MetadataService.metaGetOverride = (uri) async {
      requests.add(uri.toString());
      if (uri.host != 'compatible.example') return http.Response('', 404);
      return http.Response(jsonEncode({
        'meta': {
          'id': 'custom:42',
          'name': 'Custom Film',
          'type': 'movie',
        }
      }), 200);
    };

    final resolved = await MetadataService.resolveCatalogMeta(
      baseUrl: 'https://catalog-only.example',
      type: 'movie',
      id: 'custom:42',
      title: 'Custom Film',
      sourceSupportsMeta: false,
      compatibleMetaProviders: ['https://compatible.example'],
    );
    expect(resolved, isNotNull);
    expect(resolved!.detail.id, 'custom:42');
    expect(resolved.baseUrl, 'https://compatible.example');
    expect(requests, hasLength(1));
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
  test('tv and channel types remain distinct from episodic series', () {
    expect(Movie.canonicalType('tv'), 'tv');
    expect(Movie.canonicalType('channel'), 'channel');
    final channel = Movie.fromJson(
        {'id': 'demo:news', 'type': 'tv', 'name': 'Demo News'},
        'https://demo.example');
    expect(channel.type, 'tv');
  });

  test('native EPG manifest and scheduled programme fields survive', () {
    final manifest = AddonManifest.fromJson({
      'id': 'demo.epg',
      'name': 'EPG',
      'version': '1.0.0',
      'types': ['tv'],
      'resources': ['catalog', 'meta', 'stream'],
      'catalogs': [
        {'id': 'channels', 'type': 'tv', 'extra': [{'name': 'date'}]}
      ],
      'behaviorHints': {'epgProvider': true},
    });
    expect(manifest.isEpgProvider, isTrue);
    expect(AddonManifest.fromJson(manifest.toJson()).isEpgProvider, isTrue);
    final channel = MovieDetail.fromJson({
      'id': 'demo:news',
      'type': 'tv',
      'name': 'News',
      'behaviorHints': {'isLive': true, 'hasScheduledVideos': true},
      'videos': [{
        'id': 'demo:news:epg:1',
        'title': 'Evening News',
        'startTime': '2026-09-12T18:00:00Z',
        'endTime': '2026-09-12T18:30:00Z',
      }]
    });
    expect(channel.isLive, isTrue);
    expect(channel.hasScheduledVideos, isTrue);
    expect(channel.videos.single.startTime, '2026-09-12T18:00:00Z');
    expect(channel.videos.single.endTime, '2026-09-12T18:30:00Z');
  });

  test('EPG metasDetailed uses date and skip path and retains programmes', () async {
    Uri? requestUri;
    MetadataService.catalogGetOverride = (uri) async {
      requestUri = uri;
      return http.Response(jsonEncode({
        'metasDetailed': [{
          'id': 'demo:news',
          'name': 'Demo News',
          'type': 'tv',
          'videos': [{
            'id': 'demo:news:1',
            'title': 'News',
            'startTime': '2026-09-12T18:00:00Z',
            'endTime': '2026-09-12T18:30:00Z'
          }]
        }]
      }), 200);
    };
    final guide = await MetadataService.fetchGuideCatalog(
        baseUrl: 'https://epg.example',
        catalogId: 'channels',
        utcDay: DateTime.utc(2026, 9, 12),
        skip: 100);
    expect(requestUri.toString(), contains(
        '/catalog/tv/channels/date=2026-09-12&skip=100.json'));
    expect(guide.single.type, 'tv');
    expect(guide.single.videos.single.title, 'News');
    final previews = await MetadataService.fetchCatalog(
        baseUrl: 'https://epg.example', type: 'tv', catalogId: 'channels');
    expect(previews.single.type, 'tv');
  });

  test('hash subtitles include videoID and videoSize with legacy fallback', () {
    final request = StremioSubtitleProvider.buildRequestUri(
        baseUrl: 'https://subs.example/',
        type: 'series',
        videoId: 'tt1234567:1:2',
        videoHash: 'ABCDEF0123456789',
        videoSize: 123456789);
    expect(request.toString(), contains(
        '/subtitles/series/abcdef0123456789/videoID=tt1234567%3A1%3A2&videoSize=123456789.json'));
    final fallback = StremioSubtitleProvider.buildRequestUri(
        baseUrl: 'https://subs.example',
        type: 'movie',
        videoId: 'tt1234567');
    expect(fallback.path, '/subtitles/movie/tt1234567.json');
  });

}
