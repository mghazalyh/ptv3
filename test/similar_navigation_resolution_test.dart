import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/bestsimilar_scraper.dart';
import 'package:playtorrio/services/metadata/metadata_service.dart';
import 'package:playtorrio/services/metadata/similar_recommendations_service.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';
import 'package:playtorrio/services/player/player_diagnostic_codes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmdb = TmdbDiscoverService.instance;

  BSItem makeCard() => SimilarRecommendationsService.fromTmdbTitles([
    const DiscoverTitle(
      tmdbId: 42, title: 'Example Series', type: DiscoverType.series,
      poster: 'https://example.invalid/poster.png', premiereYear: 2020,
    ),
  ], 'Another Series').single;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'fake-for-tests',
    });
    tmdb.resetForTesting(spacing: Duration.zero);
    MetadataService.clearCache();
    MetadataService.catalogGetOverride = null;
  });

  tearDown(() {
    tmdb.resetForTesting();
    MetadataService.catalogGetOverride = null;
    MetadataService.clearCache();
  });

  test('TMDB external IMDb ID opens the selected series', () async {
    final requests = <String>[];
    tmdb.httpGetOverride = (uri, headers) async {
      requests.add(uri.path);
      return http.Response(jsonEncode({'imdb_id': 'tt1234567'}), 200);
    };
    MetadataService.catalogGetOverride = (uri) async {
      fail('Cinemeta should not be queried with a valid IMDb ID');
    };
    final movie = await SimilarRecommendationsService.resolveForNavigation(
      makeCard(),
    );
    expect(movie?.id, 'tt1234567');
    expect(movie?.type, 'series');
    expect(requests, ['/3/tv/42/external_ids']);
  });

  test('TMDB missing IMDb ID uses Cinemeta metadata', () async {
    tmdb.httpGetOverride = (uri, headers) async {
      return http.Response(jsonEncode({'imdb_id': null}), 200);
    };
    final requests = <Uri>[];
    MetadataService.catalogGetOverride = (uri) async {
      requests.add(uri);
      return http.Response(jsonEncode({
        'metas': uri.path.contains('/series/') ? [
          {'id': 'tt7654321', 'name': 'Example Series',
           'type': 'series', 'releaseInfo': '2020'},
        ] : [],
      }), 200);
    };
    final movie = await SimilarRecommendationsService.resolveForNavigation(
      makeCard(),
    );
    expect(movie?.id, 'tt7654321');
    expect(requests.any((u) => u.host == 'v3-cinemeta.strem.io'), isTrue);
  });

  test('temporarily missing TMDB key does not disable Cinemeta fallback',
      () async {
    SharedPreferences.setMockInitialValues({});
    tmdb.resetForTesting(spacing: Duration.zero);
    var tmdbCalls = 0;
    tmdb.httpGetOverride = (uri, headers) async {
      tmdbCalls++;
      return http.Response('{}', 503);
    };
    MetadataService.catalogGetOverride = (uri) async {
      return http.Response(jsonEncode({
        'metas': uri.path.contains('/series/') ? [
          {'id': 'tt5555555', 'name': 'Example Series',
           'type': 'series', 'releaseInfo': '2020'},
        ] : [],
      }), 200);
    };
    final movie = await SimilarRecommendationsService.resolveForNavigation(
      makeCard(),
    );
    expect(movie?.id, 'tt5555555');
    expect(tmdbCalls, 0);
  });

  test('original addon is tried after primary and Cinemeta fail', () async {
    tmdb.httpGetOverride = (uri, headers) async {
      return http.Response('{}', 503);
    };
    MetadataService.catalogGetOverride = (uri) async {
      if (uri.host == 'addon.example.invalid' &&
          uri.path.contains('/series/')) {
        return http.Response(jsonEncode({
          'metas': [
            {'id': 'tt9999999', 'name': 'Example Series',
             'type': 'series', 'releaseInfo': '2020'},
          ],
        }), 200);
      }
      return http.Response(jsonEncode({'metas': []}), 200);
    };
    final movie = await SimilarRecommendationsService.resolveForNavigation(
      makeCard(), preferredBaseUrl: 'https://addon.example.invalid',
    );
    expect(movie?.id, 'tt9999999');
  });

  test('no candidates return null with fixed diagnostic vocabulary', () async {
    tmdb.httpGetOverride = (uri, headers) async {
      return http.Response('{}', 503);
    };
    MetadataService.catalogGetOverride = (uri) async {
      return http.Response(jsonEncode({'metas': []}), 200);
    };
    final movie = await SimilarRecommendationsService.resolveForNavigation(
      makeCard(),
    );
    expect(movie, isNull);
    for (final code in [
      'similar_card_tapped',
      'similar_card_primary_resolved',
      'similar_card_fallback_resolved',
      'similar_card_resolution_failed',
      'similar_card_opened',
      'similar_card_navigation_error',
    ]) {
      expect(PlayerDiagnosticCodes.events.contains(code), isTrue);
    }
  });
}
