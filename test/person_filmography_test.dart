import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'test-only-credential',
    });
    TmdbDiscoverService.instance.resetForTesting(spacing: Duration.zero);
  });
  tearDown(() => TmdbDiscoverService.instance.resetForTesting());

  test('cast click searches PERSON, never movie titles containing their name',
      () async {
    final paths = <String>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      paths.add(uri.path);
      return http.Response(jsonEncode({
        'results': [
          {'id': 44, 'name': 'Alex Somebody', 'known_for_department': 'Acting'},
          {'id': 55, 'name': 'Chris Actor', 'known_for_department': 'Acting'},
          {'id': 56, 'name': 'Chris Actor', 'known_for_department': 'Acting'},
        ],
      }), 200);
    };
    final matches = await TmdbDiscoverService.instance.searchPeople('Chris Actor');
    expect(paths, ['/3/search/person']);
    expect(matches.map((x) => x.name).take(2),
        ['Chris Actor', 'Chris Actor']);
    expect(matches.map((x) => x.id).toSet().length, 3);
  });

  test('combined credits return actual movies and shows for chosen person',
      () async {
    final paths = <String>[];
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      paths.add(uri.path);
      return http.Response(jsonEncode({
        'cast': [
          {'id': 1, 'media_type': 'movie', 'title': 'A Thriller',
           'release_date': '2024-01-01', 'poster_path': '/one.jpg'},
          {'id': 2, 'media_type': 'tv', 'name': 'A TV Drama',
           'first_air_date': '2025-01-01', 'poster_path': '/two.jpg'},
          {'id': 3, 'media_type': 'person', 'name': 'Wrong type'},
          {'id': 1, 'media_type': 'movie', 'title': 'A Thriller',
           'release_date': '2024-01-01'},
          {'id': 4, 'media_type': 'movie', 'title': 'Adult',
           'adult': true},
        ],
      }), 200);
    };
    final credits = await TmdbDiscoverService.instance.personCombinedCredits(55);
    expect(paths, ['/3/person/55/combined_credits']);
    expect(credits.map((x) => x.title), ['A TV Drama', 'A Thriller']);
    expect(credits.first.type, DiscoverType.series);
    expect(credits.last.type, DiscoverType.movie);
  });

  test('empty key means no cast search network request', () async {
    await TmdbDiscoverService.instance.saveKey('');
    var requests = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      requests++;
      return http.Response('{}', 200);
    };
    await expectLater(TmdbDiscoverService.instance.searchPeople('Some Person'),
        throwsFormatException);
    expect(requests, 0);
  });

  test('cast search respects TMDB 429 and avoids repeated traffic', () async {
    var calls = 0;
    TmdbDiscoverService.instance.httpGetOverride = (uri, headers) async {
      calls++;
      return http.Response('{}', 429, headers: {'retry-after': '90'});
    };
    await expectLater(TmdbDiscoverService.instance.searchPeople('A'),
        throwsFormatException);
    await expectLater(TmdbDiscoverService.instance.searchPeople('B'),
        throwsFormatException);
    expect(calls, 1);
  });
}
