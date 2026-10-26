import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';
import 'package:playtorrio/services/metadata/similar_recommendations_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'fake-for-tests',
    });
    TmdbDiscoverService.instance.resetForTesting(spacing: Duration.zero);
  });
  tearDown(() => TmdbDiscoverService.instance.resetForTesting());

  test('TV recommended cards carry country and original language immediately',
      () {
    final item = SimilarRecommendationsService.fromTmdbTitles([
      const DiscoverTitle(
        tmdbId: 14, title: 'Foreign fantasy', type: DiscoverType.series,
        poster: 'https://example.test/p.jpg',
        originCountries: ['KR'], originalLanguage: 'ko',
      ),
    ], 'Other Show').single;
    expect(item.country, 'KR');
    expect(item.originalLanguage, 'ko');
    expect(SimilarRecommendationsService.displayLanguage(item.originalLanguage),
        'Korean');
    expect(item.network, isNull);
  });

  test('bounded enrich loads TV network and movie studio from real details',
      () async {
    final paths = <String>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      paths.add(uri.path);
      if (uri.path == '/3/tv/14') {
        return http.Response(jsonEncode({
          'origin_country': ['KR'], 'original_language': 'ko',
          'networks': [{'name': 'tvN'}],
        }), 200);
      }
      return http.Response('{}', 404);
    };
    final card = SimilarRecommendationsService.fromTmdbTitles([
      const DiscoverTitle(
        tmdbId: 14, title: 'Foreign fantasy', type: DiscoverType.series,
        poster: 'https://example.test/p.jpg',
      ),
    ], 'Other Show').single;
    await SimilarRecommendationsService.enrichVisibleCards([card]);
    expect(paths, ['/3/tv/14']);
    expect(card.country, 'KR');
    expect(card.originalLanguage, 'ko');
    expect(card.network, 'tvN');
    expect(SimilarRecommendationsService.displayLanguage('ja'), 'Japanese');
    expect(SimilarRecommendationsService.displayLanguage(null), 'Not listed');
    await SimilarRecommendationsService.enrichVisibleCards([card]);
    expect(paths, ['/3/tv/14'], reason: 'TMDB 24-hour cache is reused');
  });

  test('enrichment is optional when no TMDB credentials are configured',
      () async {
    await TmdbDiscoverService.instance.saveKey('');
    var calls = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      calls++;
      return http.Response('{}', 200);
    };
    final cards = SimilarRecommendationsService.fromTmdbTitles([
      const DiscoverTitle(
        tmdbId: 9, title: 'Another show', type: DiscoverType.series,
        poster: 'https://example.test/p.jpg',
      ),
    ], 'Original');
    await SimilarRecommendationsService.enrichVisibleCards(cards);
    expect(calls, 0);
  });
}
