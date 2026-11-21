import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/ios_remote_media_discovery.dart';

void main() {
  test('Exact English movie discovery uses installed TMDB filter semantics', () {
    final query = IosRemoteMediaQuery.parse({
      'type': 'movie', 'fromYear': 2021, 'toYear': 2026,
      'language': 'en', 'sort': 'vote_average.desc',
      'genreId': 53, 'page': 2, 'limit': 10,
    });
    final params = query.filters.toQuery();
    expect(params['with_original_language'], 'en');
    expect(params['primary_release_date.gte'], '2021-01-01');
    expect(params['primary_release_date.lte'], '2026-12-31');
    expect(params['with_genres'], '53');
    expect(query.limit, 10);
  });

  test('Remote discovery rejects malformed or unsafe requests', () {
    for (final args in <Map<String, dynamic>>[
      {'type': 'channel'},
      {'language': 'english'},
      {'fromYear': 2026, 'toYear': 2021},
      {'genreId': 99999},
      {'page': 999},
      {'limit': 1000},
      {'url': 'https://untrusted.example/manifest.json'},
    ]) {
      expect(() => IosRemoteMediaQuery.parse(args),
          throwsA(isA<FormatException>()));
    }
  });

  test('Exact series query preserves media type', () {
    final query = IosRemoteMediaQuery.parse({
      'type': 'series', 'query': 'Doctor Who', 'fromYear': 2024,
    });
    expect(query.filters.type.name, 'series');
    expect(query.filters.toQuery()['query'], 'Doctor Who');
  });
}
