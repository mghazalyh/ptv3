import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:playtorrio/services/addon/addon_manager.dart';
import 'package:playtorrio/services/metadata/metadata_service.dart';
import 'package:playtorrio/services/scraper/sites/vadapav.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _liveProviderTests = bool.fromEnvironment(
  'PLAYTORRIO_LIVE_PROVIDER_TESTS',
  defaultValue: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VadapavScraper.tmdbResolverOverride = ({
      String? imdbId,
      required String title,
      required String type,
      int? year,
    }) async => type == 'tv' ? 1396 : 550;
    VadapavScraper.httpGetOverride = null;
    MetadataService.manifestGetOverride = null;
  });

  tearDown(() {
    VadapavScraper.httpGetOverride = null;
    VadapavScraper.tmdbResolverOverride = null;
    MetadataService.manifestGetOverride = null;
    MetadataService.clearCache();
  });

  group('Vadapav deterministic Stremio contract', () {
    test('preserves movie identity and exact series season/episode', () async {
      final requested = <Uri>[];
      VadapavScraper.httpGetOverride = (uri) async {
        requested.add(uri);
        final filename = uri.path.contains('/series/')
            ? 's02e03.m3u8' : 'movie.m3u8';
        return http.Response(jsonEncode({
          'streams': [
            {
              'name': 'Direct HLS',
              'title': 'Verified episode-specific file',
              'url': 'https://video.example/' + filename,
              'behaviorHints': {'notWebReady': false},
            },
            {'name': 'Duplicate', 'url': 'https://video.example/' + filename},
            {'name': 'Invalid', 'url': 'magnet:?xt=urn:btih:invalid'},
          ],
        }), 200);
      };

      final scraper = VadapavScraper();
      final movies = await scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        imdbId: 'tt0137523',
        year: 1999,
      ).toList();
      final episodes = await scraper.scrapeStream(
        type: 'series',
        title: 'Breaking Bad',
        imdbId: 'tt0903747',
        year: 2008,
        season: 2,
        episode: 3,
      ).toList();

      expect(requested.map((uri) => uri.path), containsAll([
        '/stream/movie/tt0137523.json',
        '/stream/series/tt0903747:2:3.json',
      ]));
      expect(movies, hasLength(1));
      expect(episodes, hasLength(1));
      expect(movies.single.url, 'https://video.example/movie.m3u8');
      expect(episodes.single.url, 'https://video.example/s02e03.m3u8');
      expect(movies.single.addonName, 'PlayTorrioHTTP');
      expect(episodes.single.addonName, 'PlayTorrioHTTP');
      expect(episodes.single.behaviorHints?['notWebReady'], isFalse);
    });

    test('invalid primary URLs must not prevent usable TMDB fallback', () async {
      final requests = <Uri>[];
      VadapavScraper.httpGetOverride = (uri) async {
        requests.add(uri);
        if (uri.path.endsWith('/tt0137523.json')) {
          return http.Response(jsonEncode({
            'streams': [
              {'url': 'magnet:?xt=urn:btih:invalid'},
              {'url': null},
              {'url': ''},
            ],
          }), 200);
        }
        return http.Response(jsonEncode({
          'streams': [
            {'name': 'Fallback', 'url': 'https://video.example/fallback.mp4'},
          ],
        }), 200);
      };

      final sources = await VadapavScraper().scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        imdbId: 'tt0137523',
        year: 1999,
      ).toList();
      expect(requests.map((uri) => uri.path).toList(), [
        '/stream/movie/tt0137523.json',
        '/stream/movie/tmdb:550.json',
      ]);
      expect(sources, hasLength(1));
      expect(sources.single.url, 'https://video.example/fallback.mp4');
    });

    test('unavailable manifests and sources fail safely', () async {
      VadapavScraper.httpGetOverride = (_) async =>
          http.Response('{"streams":[]}', 503);
      final sources = await VadapavScraper().scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        imdbId: 'tt0137523',
      ).toList();
      expect(sources, isEmpty);
    });
  });

  test('stremio scheme normalization installs the correct manifest', () async {
    SharedPreferences.setMockInitialValues({});
    MetadataService.manifestGetOverride = (uri) async {
      expect(uri.scheme, 'https');
      return http.Response(jsonEncode({
        'id': uri.host == 'stremio.vadapav.mov'
            ? 'org.stremio.vadapav'
            : 'com.linvo.cinemeta',
        'version': '1.0.0',
        'name': uri.host == 'stremio.vadapav.mov'
            ? 'Vadapav'
            : 'Cinemeta',
        'description': 'Local deterministic fixture',
        'types': ['movie', 'series'],
        'resources': ['meta', 'stream'],
        'catalogs': [],
      }), 200);
    };

    final manager = AddonManager.instance;
    await manager.initialize();
    const url = 'stremio://stremio.vadapav.mov/manifest.json';
    final addon = await manager.addAddon(url);

    expect(addon.baseUrl, 'https://stremio.vadapav.mov');
    expect(addon.manifest.id, 'org.stremio.vadapav');
  });

  test('real Vadapav provider smoke test (explicit opt-in)', () async {
    VadapavScraper.tmdbResolverOverride = null;
    final scraper = VadapavScraper();
    final movieSources = await scraper.scrapeStream(
      type: 'movie',
      title: 'Fight Club',
      imdbId: 'tt0137523',
      year: 1999,
    ).toList();
    final tvSources = await scraper.scrapeStream(
      type: 'series',
      title: 'Breaking Bad',
      imdbId: 'tt0903747',
      year: 2008,
      season: 1,
      episode: 1,
    ).toList();
    expect(movieSources, isNotEmpty,
        reason: 'Live Vadapav movie sources unavailable');
    expect(tvSources, isNotEmpty,
        reason: 'Live Vadapav series sources unavailable');
  },
      skip: !_liveProviderTests,
      timeout: const Timeout(Duration(seconds: 120)));
}
