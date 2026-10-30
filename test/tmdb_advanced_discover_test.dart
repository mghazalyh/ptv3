import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';

void main() {
  group('TMDB structured discovery', () {
    test('TV date filters match actual episode airings regardless of premiere', () {
      final filters = DiscoverFilters(
        type: DiscoverType.series,
        fromYear: 2026,
        toYear: 2026,
        country: 'US',
        originalLanguage: 'en',
      );
      final q = filters.toQuery();
      expect(q['air_date.gte'], '2026-01-01');
      expect(q['air_date.lte'], '2026-12-31');
      expect(q.containsKey('first_air_date.gte'), isFalse);
      expect(q.containsKey('first_air_date_year'), isFalse);
      expect(q['with_origin_country'], 'US');
      expect(q['with_original_language'], 'en');
      expect(filters.buildUri().path, '/3/discover/tv');
    });

    test('movie range 2000–2003 uses release dates', () {
      final filters = DiscoverFilters(
        type: DiscoverType.movie,
        fromYear: 2000,
        toYear: 2003,
      );
      final q = filters.toQuery();
      expect(q['primary_release_date.gte'], '2000-01-01');
      expect(q['primary_release_date.lte'], '2003-12-31');
      expect(q.containsKey('air_date.gte'), isFalse);
      expect(filters.buildUri().path, '/3/discover/movie');
    });

    test('TV episode range 2020–2026 covers both endpoints', () {
      final q = const DiscoverFilters(
        type: DiscoverType.series,
        fromYear: 2020,
        toYear: 2026,
      ).toQuery();
      expect(q['air_date.gte'], '2020-01-01');
      expect(q['air_date.lte'], '2026-12-31');
    });

    test('start-only exact year equals end-only exact year', () {
      final q1 = const DiscoverFilters(fromYear: 2026).toQuery();
      final q2 = const DiscoverFilters(toYear: 2026).toQuery();
      expect(q1['primary_release_date.gte'], '2026-01-01');
      expect(q1['primary_release_date.lte'], '2026-12-31');
      expect(q2['primary_release_date.gte'], '2026-01-01');
      expect(q2['primary_release_date.lte'], '2026-12-31');
    });

    test('no text or year is required to browse', () {
      final q = const DiscoverFilters().toQuery();
      expect(q.containsKey('query'), isFalse);
      expect(q.containsKey('air_date.gte'), isFalse);
      expect(q.containsKey('primary_release_date.gte'), isFalse);
      expect(q['page'], '1');
    });

    test('invalid ranges are rejected', () {
      expect(() => const DiscoverFilters(
        fromYear: 2027, toYear: 2020).toQuery(), throwsFormatException);
      expect(() => const DiscoverFilters(
        fromYear: 1800).toQuery(), throwsFormatException);
      expect(() => const DiscoverFilters(
        page: 501).toQuery(), throwsFormatException);
    });

    test('movie and TV genre IDs are optional and type-specific', () {
      expect(DiscoverGenres.movies['28'], 'Action');
      expect(DiscoverGenres.series['10759'], 'Action & Adventure');
      expect(const DiscoverFilters(
        type: DiscoverType.movie, genreId: 28,
      ).toQuery()['with_genres'], '28');
      expect(const DiscoverFilters(
        type: DiscoverType.series, genreId: 10759,
      ).toQuery()['with_genres'], '10759');
      expect(const DiscoverFilters().toQuery().containsKey('with_genres'),
          isFalse);
      expect(() => const DiscoverFilters(
        type: DiscoverType.series, genreId: 28,
      ).toQuery(), throwsFormatException);
    });

    test('text search enforces genre from genre_ids, even without discover API', () {
      const filters = DiscoverFilters(
        type: DiscoverType.series,
        titleQuery: 'the mentalist',
        genreId: 80,
      );
      final query = filters.toQuery();
      expect(query['query'], 'the mentalist');
      expect(query.containsKey('with_genres'), isFalse,
          reason: 'TMDB /search/tv cannot accept Discover-only genre params');
      expect(TmdbDiscoverService.matchesTitleFilters({
        'name': 'The Mentalist', 'genre_ids': [80, 18, 9648],
      }, filters), isTrue);
      expect(TmdbDiscoverService.matchesTitleFilters({
        'name': 'Comedy show', 'genre_ids': [35],
      }, filters), isFalse);
      expect(filters.withPage(2).genreId, 80);
    });

    test('top-rated filters out very few vote shows', () {
      final q = const DiscoverFilters(
        sort: 'vote_average.desc').toQuery();
      expect(q['vote_count.gte'], '100');
    });

    test('show retains premiere year for 2026-season browsing label', () {
      final item = DiscoverTitle.parse({
        'id': 123,
        'name': 'Example returning series',
        'first_air_date': '2023-07-01',
        'poster_path': '/poster.jpg',
        'vote_average': 8.5,
      }, DiscoverType.series);
      expect(item.premiereYear, 2023);
      expect(item.type, DiscoverType.series);
      expect(item.premiereDate, '2023-07-01');
      expect(item.poster, contains('/t/p/w342/poster.jpg'));
    });
  });
}
