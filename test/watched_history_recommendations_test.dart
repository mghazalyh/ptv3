import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/models/addon/addon.dart';
import 'package:playtorrio/models/movie/movie.dart';
import 'package:playtorrio/models/movie/movie_section.dart';
import 'package:playtorrio/services/continue_watching/watched_history_service.dart';
import 'package:playtorrio/services/home/home_page_settings.dart';

MovieSection section(String id, {int count = 1}) => MovieSection(
  title: 'Because you watched a show',
  subtitle: 'Personalized',
  contentType: 'series',
  addonBaseUrl: 'https://v3-cinemeta.strem.io',
  catalog: AddonCatalog(type: 'series', id: id, genres: const [],
      supportsSearch: false, supportsSkip: false),
  movies: List.generate(count, (index) => Movie(
      id: 'tt$index', name: 'Show $index', type: 'series',
      addonBaseUrl: 'https://v3-cinemeta.strem.io')),
  isCurated: true,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('completed movie remains watched after resume is cleared', () async {
    await WatchedHistoryService.initialize();
    expect(WatchedHistoryService.items.value, isEmpty);
    await WatchedHistoryService.recordProgress(
      id: 'tt101', title: 'Completed Movie', type: 'movie',
      year: '2020', positionSeconds: 270, totalDurationSeconds: 300);
    expect(WatchedHistoryService.items.value.single.completed, isTrue);
    expect(WatchedHistoryService.items.value.single.playbackPositions['movie']!
        .fraction, 1.0);
    await WatchedHistoryService.initialize(); // reload from prefs
    expect(WatchedHistoryService.items.value.single.title, 'Completed Movie');
    expect(WatchedHistoryService.items.value.single.completed, isTrue);
    // Rewatching a finished movie must not erase that fact.
    await WatchedHistoryService.recordProgress(
      id: 'tt101', title: 'Completed Movie', type: 'movie',
      positionSeconds: 61, totalDurationSeconds: 1000);
    expect(WatchedHistoryService.items.value.single.completed, isTrue);
  });

  test('episodes track independent cross-device progress and completion', () async {
    await WatchedHistoryService.initialize();
    await WatchedHistoryService.recordProgress(
      id: 'ttseries', title: 'TV', type: 'series',
      season: 2, episode: 3, episodeId: 'ttseries:2:3',
      positionSeconds: 420, totalDurationSeconds: 1200);
    await WatchedHistoryService.recordProgress(
      id: 'ttseries', title: 'TV', type: 'series',
      season: 2, episode: 4, episodeId: 'ttseries:2:4',
      positionSeconds: 1130, totalDurationSeconds: 1200);
    final item = WatchedHistoryService.items.value.single;
    expect(item.completed, false);
    expect(item.playbackPositions['ttseries:2:3']!.fraction, closeTo(0.35, 0.001));
    expect(item.playbackPositions['ttseries:2:4']!.fraction, 1);
    expect(item.completedEpisodeIds, contains('ttseries:2:4'));
    await WatchedHistoryService.initialize();
    expect(WatchedHistoryService.items.value.single.playbackPositions.length, 2);
  });

  test('never count a five-second accidental playback as watched', () async {
    await WatchedHistoryService.initialize();
    await WatchedHistoryService.recordProgress(
        id: 'tt1', title: 'Accidental', type: 'movie',
        positionSeconds: 5, totalDurationSeconds: 3600);
    expect(WatchedHistoryService.items.value, isEmpty);
  });

  test('separate titles and capped deduplication are retained', () async {
    await WatchedHistoryService.initialize();
    for (var i = 0; i < 4; i++) {
      await WatchedHistoryService.recordProgress(
          id: 'tt$i', title: 'Series $i', type: 'series',
          positionSeconds: 200, totalDurationSeconds: 1000);
    }
    expect(WatchedHistoryService.items.value.length, 4);
    await WatchedHistoryService.recordProgress(
        id: 'tt2', title: 'Series 2', type: 'series',
        positionSeconds: 300, totalDurationSeconds: 1000);
    expect(WatchedHistoryService.items.value.length, 4);
  });

  test('completed movies excluded; unfinished series and new films retained', () {
    final watched = [
      WatchedTitle(id: 'tt42', title: 'Finished Film', type: 'movie',
          completed: true, lastWatchedAt: DateTime.utc(2026, 11, 1)),
      WatchedTitle(id: 'tt63', title: 'Series', type: 'series',
          lastWatchedAt: DateTime.utc(2026, 11, 1)),
    ];
    final items = [
      Movie(id: 'tt42', name: 'Finished Film', type: 'movie',
          addonBaseUrl: ''),
      Movie(id: 'tt101', name: 'New Film', type: 'movie',
          addonBaseUrl: ''),
      Movie(id: 'different', name: 'New Film', type: 'movie',
          addonBaseUrl: ''),
      Movie(id: 'tt63', name: 'Series', type: 'series',
          addonBaseUrl: ''),
    ];
    expect(HomePageSettings.filterRecommendationItems(
        items, watched: watched).map((movie) => movie.name),
        ['New Film', 'Series']);
  });

  test('old recommendation row survives null/empty replacement', () {
    final original = section('bestsimilar_watching_1');
    final retained = HomePageSettings.retainValidRecommendations(
      [original], [], showList: true, showWatching: true,
      showTrakt: false, showSimkl: false,
    );
    expect(identical(retained.single, original), isTrue);
  });

  test('success atomically replaces same source, disabled sources vanish', () {
    final previous = section('bestsimilar_watching_1');
    final replacement = section('bestsimilar_watching_1', count: 3);
    final next = HomePageSettings.retainValidRecommendations(
      [previous], [replacement], showList: true, showWatching: true,
      showTrakt: false, showSimkl: false,
    );
    expect(identical(next.single, replacement), isTrue);
    expect(HomePageSettings.retainValidRecommendations(
      next, [], showList: true, showWatching: false,
      showTrakt: false, showSimkl: false,
    ), isEmpty);
  });

  test('connected Trakt history can seed older played shows safely', () {
    final source = WatchedHistoryService.parseTraktHistoryEntry({
      'watched_at': '2026-09-03T10:00:00Z',
      'show': {
        'title': 'Older Show', 'year': 2021,
        'ids': {'imdb': 'tt1234567', 'tmdb': 32},
      },
      'episode': {'season': 1, 'number': 4},
    });
    expect(source?.id, 'tt1234567');
    expect(source?.title, 'Older Show');
    expect(source?.completed, isFalse); // A single episode != whole series.
    expect(WatchedHistoryService.parseTraktHistoryEntry({
      'show': {'title': 'Missing ID', 'ids': {}},
    }), isNull);
  });

  test('similarity is NOT the IMDb rating and only valid percent is parsed', () {
    final movie = Movie.fromJson({
      'id': 'tt123', 'name': 'Test', 'type': 'series',
      'imdbRating': 8.4, 'similarityPercent': 93,
    }, 'https://v3-cinemeta.strem.io');
    expect(movie.imdbRating, '8.4');
    expect(movie.similarityPercent, 93);
    expect(Movie.fromJson({'id': 'tt2', 'name': 'No percentage',
      'similarityPercent': 150}, '').similarityPercent, isNull);
  });
}
