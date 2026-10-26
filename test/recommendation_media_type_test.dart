import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/movie/movie.dart';
import 'package:playtorrio/services/metadata/bestsimilar_scraper.dart';

BSItem related(int id, String title, {bool? serial, int? year,
    String slug = 'unnamed', String? duration}) {
  return BSItem(
    id: id,
    slug: slug,
    title: title,
    year: year,
    rating: null,
    voteCount: null,
    thumbUrl: '',
    similarityPercent: 95,
    genre: null,
    country: null,
    duration: duration,
    story: null,
    styleTags: const [],
    plotTags: const [],
    audienceTags: const [],
    timeTags: const [],
    placeTags: const [],
    sourceIsTv: serial,
  );
}

BSAutocompleteHit hit(int id, String title, {required bool isTv, int? year}) {
  return BSAutocompleteHit(
    id: id, slug: '$id-test', label: title, title: title,
    year: year, isTv: isTv, url: '/movies/$id-test',
  );
}

void main() {
  test('HTML TV markers identify series but unverified HTML film markers stay neutral', () {
    final jackRyan = related(14, 'Tom Clancy\'s Jack Ryan', serial: true);
    final berlin = related(15, 'Berlin Station', serial: true);
    final film = related(16, 'Tinker Tailor Soldier Spy', serial: false);
    expect(jackRyan.knownIsTv, isTrue);
    expect(berlin.knownIsTv, isTrue);
    expect(film.knownIsTv, isNull);

    // BestSimilar can mark series as film in its mixed recommendation HTML.
    // Only a verified provider autocomplete result can establish film type.
    film.autocompleteIsTv = BestSimilarScraper.classifyFromAutocomplete(
      film,
      [hit(16, 'Tinker Tailor Soldier Spy', isTv: false)],
    );
    expect(film.knownIsTv, isFalse);
    expect(Movie.typeLabel('movie'), 'Movie');
  });

  test('verified series overrides a misleading negative HTML series marker', () {
    final series = related(17, 'Mislabelled Show', serial: false, year: 2022);
    expect(series.knownIsTv, isNull);
    series.autocompleteIsTv = BestSimilarScraper.classifyFromAutocomplete(
      series,
      [hit(17, 'Mislabelled Show', isTv: true, year: 2022)],
    );
    expect(series.knownIsTv, isTrue);
    expect(Movie.typeLabel('series'), 'Series');
  });

  test('autocomplete serial parsing never treats missing metadata as film', () {
    expect(BestSimilarScraper.parseAutocompleteSerial('1'), isTrue);
    expect(BestSimilarScraper.parseAutocompleteSerial(1), isTrue);
    expect(BestSimilarScraper.parseAutocompleteSerial('0'), isFalse);
    expect(BestSimilarScraper.parseAutocompleteSerial(0), isFalse);
    expect(BestSimilarScraper.parseAutocompleteSerial(false), isFalse);
    expect(BestSimilarScraper.parseAutocompleteSerial(null), isNull);
    expect(BestSimilarScraper.parseAutocompleteSerial(''), isNull);
    expect(BestSimilarScraper.parseAutocompleteSerial('unknown'), isNull);
  });

  test('unverified recommendation is NOT automatically a Movie', () {
    final unknown = related(44, 'Mystery Title');
    expect(unknown.knownIsTv, isNull);
    expect(Movie.typeLabel('unknown'), 'Title');
  });

  test('autocomplete serial type resolves only matching provider title', () {
    final redElection = related(207, 'Red Election', year: 2021);
    final hits = [
      hit(99, 'Unrelated Movie', isTv: false),
      hit(207, 'Red Election', isTv: true, year: 2021),
    ];
    expect(BestSimilarScraper.classifyFromAutocomplete(redElection, hits), isTrue);
    redElection.autocompleteIsTv =
        BestSimilarScraper.classifyFromAutocomplete(redElection, hits);
    expect(redElection.knownIsTv, isTrue);
    expect(Movie.typeLabel(redElection.knownIsTv! ? 'series' : 'movie'), 'Series');
  });

  test('same title with wrong year cannot force a media type', () {
    final entry = related(500, 'The Enemy Within', year: 2019);
    expect(BestSimilarScraper.classifyFromAutocomplete(entry, [
      hit(333, 'The Enemy Within', isTv: false, year: 2006),
    ]), isNull);
  });

  test('when provider item ID changes, exact title AND year can verify', () {
    final entry = related(500, 'Liaison', year: 2023);
    expect(BestSimilarScraper.classifyFromAutocomplete(entry, [
      hit(333, 'Liaison', isTv: true, year: 2023),
    ]), isTrue);
    expect(BestSimilarScraper.classifyFromAutocomplete(entry, [
      hit(333, 'Liaison', isTv: true, year: 2023),
      hit(334, 'Liaison', isTv: false, year: 2023),
    ]), isNull);
  });

  test('source TV/film markers and known TMDB type take priority', () {
    final show = related(101, 'Station', serial: true);
    show.tmdbMediaType = 'movie';
    expect(show.knownIsTv, isFalse);
    expect(related(50, 'Episodic', duration: '8 episodes').knownIsTv, isTrue);
  });

  test('normalize TV alias labels and retain missing Stremio catalog type', () {
    for (final alias in ['series', 'tv', 'show', 'shows', 'tv_series', 'tv-series']) {
      expect(Movie.canonicalType(alias), 'series');
      expect(Movie.typeLabel(alias), 'Series');
    }
    expect(Movie.typeLabel('film'), 'Movie');
    expect(Movie.typeLabel('movie'), 'Movie');
    expect(Movie.typeLabel('unknown'), 'Title');
    expect(Movie.fromJson({'id': 'tt123', 'name': 'A show'},
        'https://v3-cinemeta.strem.io', fallbackType: 'series').type, 'series');
    expect(Movie.fromJson({'id': 'tt123', 'name': 'A film', 'type': 'movie'},
        'https://v3-cinemeta.strem.io', fallbackType: 'series').type, 'movie');
  });
}
