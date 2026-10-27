import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';
import 'package:playtorrio/services/metadata/title_origin_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'dummy-for-unit-tests',
    });
    TmdbDiscoverService.instance.resetForTesting(spacing: Duration.zero);
    TitleOriginLanguageService.instance.resetForTesting();
  });
  tearDown(() {
    TmdbDiscoverService.instance.resetForTesting();
    TitleOriginLanguageService.instance.resetForTesting();
  });

  test('production country and original language are distinct from dubbing',
      () {
    const known = TitleOriginLanguage(
        countries: ['KR'], language: 'ko');
    expect(known.countryLabel, 'South Korea');
    expect(known.languageLabel, 'Korean');
    expect(TitleOriginLanguage.languageName('en'), 'English');
    expect(TitleOriginLanguage.empty.countryLabel, 'Not listed');
    expect(TitleOriginLanguage.empty.languageLabel, 'Not listed');
    final movie = TitleOriginLanguage.fromTmdb({
      'production_countries': [{'iso_3166_1': 'FR'}],
      'original_language': 'fr',
    }, series: false);
    expect(movie.countryLabel, 'France');
    expect(movie.languageLabel, 'French');
    final tv = TitleOriginLanguage.fromTmdb({
      'origin_country': ['JP'], 'original_language': 'ja',
    }, series: true);
    expect(tv.countryLabel, 'Japan');
    expect(tv.languageLabel, 'Japanese');
  });

  test('known language+country avoids network requests entirely', () async {
    var calls = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      calls++;
      return http.Response('{}', 200);
    };
    final r = await TitleOriginLanguageService.instance.resolve(
      titleId: 'tt1000', type: 'series',
      knownCountries: ['KR'], knownLanguage: 'ko',
    );
    expect(r.countryLabel, 'South Korea');
    expect(r.languageLabel, 'Korean');
    expect(calls, 0);
  });

  test('verified TMDB TV ID supplies accurate origin and language', () async {
    final urls = <Uri>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      urls.add(uri);
      return http.Response(jsonEncode({
        'origin_country': ['KR'], 'original_language': 'ko',
        'networks': [{'name': 'tvN'}],
      }), 200);
    };
    final r = await TitleOriginLanguageService.instance.resolve(
      titleId: '', tmdbId: 242, type: 'series',
    );
    expect(r.countryLabel, 'South Korea');
    expect(r.languageLabel, 'Korean');
    await TitleOriginLanguageService.instance.resolve(
      titleId: '', tmdbId: 242, type: 'series',
    );
    expect(urls.map((x) => x.path), ['/3/tv/242']);
  });

  test('IMDb lookup maps EXACT ID to movie metadata (no title guessing)',
      () async {
    final paths = <String>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      paths.add(uri.path);
      if (uri.path == '/3/find/tt1234567') {
        return http.Response(jsonEncode({
          'movie_results': [{'id': 123}], 'tv_results': [],
        }), 200);
      }
      if (uri.path == '/3/movie/123') {
        return http.Response(jsonEncode({
          'production_countries': [{'iso_3166_1': 'US'}],
          'original_language': 'en',
        }), 200);
      }
      throw StateError('Unexpected \${uri.path}');
    };
    final result = await TitleOriginLanguageService.instance.resolve(
      titleId: 'tt1234567', type: 'movie',
    );
    expect(paths, ['/3/find/tt1234567', '/3/movie/123']);
    expect(result.countryLabel, 'United States');
    expect(result.languageLabel, 'English');
  });

  test('unverified addon title never triggers a guessed TMDB result', () async {
    var calls = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      calls++;
      return http.Response('{}', 200);
    };
    final result = await TitleOriginLanguageService.instance.resolve(
      titleId: 'bestsimilar_some_slug', type: 'series',
    );
    expect(result.countryLabel, 'Not listed');
    expect(calls, 0);
  });

  test('missing key never launches a credential-free TMDB request', () async {
    await TmdbDiscoverService.instance.saveKey('');
    var calls = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      calls++; return http.Response('{}', 200);
    };
    final result = await TitleOriginLanguageService.instance.resolve(
      titleId: '', tmdbId: 42, type: 'movie',
    );
    expect(result.languageLabel, 'Not listed');
    expect(calls, 0);
  });

  test('24 lookups per minute is the bounded Home-card budget', () async {
    var requests = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      requests++;
      return http.Response(jsonEncode({
        'original_language': 'en', 'origin_country': ['US'],
      }), 200);
    };
    final futures = <Future<TitleOriginLanguage>>[];
    for (var i = 1; i <= 30; i++) {
      futures.add(TitleOriginLanguageService.instance.resolve(
        titleId: '', tmdbId: i, type: 'series',
      ));
    }
    await Future.wait(futures);
    expect(requests, 24);
  });
}
