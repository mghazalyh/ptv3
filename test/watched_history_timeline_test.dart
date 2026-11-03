import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/continue_watching/watched_history_service.dart';
import 'package:playtorrio/services/continue_watching/watched_history_timeline.dart';

void main() {
  final morning = DateTime.utc(2026, 11, 3, 8);
  final noon = DateTime.utc(2026, 11, 3, 12);
  final evening = DateTime.utc(2026, 11, 3, 18);

  WatchedPlaybackPosition progress({
    required DateTime at,
    int watched = 900,
    bool completed = false,
  }) => WatchedPlaybackPosition(
    positionSeconds: watched,
    totalDurationSeconds: 1200,
    updatedAt: at,
    completed: completed,
  );

  group('Watched movie and episode history', () {
    test('one movie plus each TV episode produces separate history entries', () {
      final film = WatchedTitle(
        id: 'tt100', title: 'Film', type: 'movie',
        lastWatchedAt: noon, completed: true,
        playbackPositions: {'movie': progress(at: noon, completed: true)},
      );
      final show = WatchedTitle(
        id: 'tt200', title: 'Series', type: 'series',
        lastWatchedAt: evening,
        completedEpisodeIds: const ['tt200:1:1'],
        playbackPositions: {
          'tt200:1:1': progress(at: morning, completed: true),
          'tt200:1:2': progress(at: evening),
        },
      );
      final rows = WatchedHistoryTimeline.fromTitles([film, show]);
      expect(rows, hasLength(3));
      expect(rows.map((row) => row.title.title),
          ['Series', 'Film', 'Series']);
      expect(rows.first.isEpisode, isTrue);
      expect(rows.first.season, 1);
      expect(rows.first.episode, 2);
      expect(rows.first.completed, isFalse);
      expect(rows[1].isMovie, isTrue);
      expect(rows[1].completed, isTrue);
      expect(rows[2].episode, 1);
      expect(rows[2].completed, isTrue);
      expect(rows[2].progress, 1.0);
    });

    test('completed movie remains in History without Continue Watching', () {
      final film = WatchedTitle(
        id: 'tt777', title: 'Finished Movie', type: 'movie',
        lastWatchedAt: morning, completed: true,
      );
      final entries = WatchedHistoryTimeline.fromTitles([film]);
      expect(entries, hasLength(1));
      expect(entries.single.completed, isTrue);
      expect(entries.single.typeLabel, 'MOVIE');
      expect(entries.single.progress, 1.0);
    });

    test('old title-only series stays visible without fabricated episode', () {
      final show = WatchedTitle(
        id: 'tt300', title: 'Older Series', type: 'series',
        lastWatchedAt: morning,
        completedEpisodeIds: const ['tt300:1:1', 'tt300:1:2'],
      );
      final entries = WatchedHistoryTimeline.fromTitles([show]);
      expect(entries, hasLength(1));
      expect(entries.single.isEpisode, isFalse);
      expect(entries.single.episodeLabel, 'Series watched');
      expect(entries.single.watchedAt, morning);
    });

    test('single known imported episode number is identified safely', () {
      final show = WatchedTitle(
        id: 'tt400', title: 'Imported Show', type: 'series',
        lastWatchedAt: morning,
        completedEpisodeIds: const ['tt400:2:3'],
      );
      final entry = WatchedHistoryTimeline.fromTitles([show]).single;
      expect(entry.episodeLabel, 'Season 2 · Episode 3');
      expect(entry.completed, isTrue);
    });

    test('unknown provider episode key is never guessed', () {
      final show = WatchedTitle(
        id: 'tt500', title: 'Alternate Episode', type: 'series',
        lastWatchedAt: noon,
        playbackPositions: {'arbitrary_episode': progress(at: noon)},
      );
      final entry = WatchedHistoryTimeline.fromTitles([show]).single;
      expect(entry.isEpisode, isTrue);
      expect(entry.season, isNull);
      expect(entry.episode, isNull);
      expect(entry.episodeLabel, 'Episode watched');
    });

    test('a newer title-only activity remains alongside episode positions', () {
      final show = WatchedTitle(
        id: 'tt501', title: 'Mixed History', type: 'series',
        lastWatchedAt: evening,
        playbackPositions: {'tt501:1:1': progress(at: morning)},
      );
      final entries = WatchedHistoryTimeline.fromTitles([show]);
      expect(entries, hasLength(2));
      expect(entries.first.isEpisode, isFalse);
      expect(entries.last.episode, 1);
    });

    test('search works on title and season/episode code', () {
      final show = WatchedTitle(
        id: 'tt700', title: 'The Mystery', type: 'series',
        year: '2026', lastWatchedAt: noon,
        playbackPositions: {'tt700:3:6': progress(at: noon)},
      );
      final film = WatchedTitle(
        id: 'tt701', title: 'The Film', type: 'movie',
        lastWatchedAt: morning,
      );
      final all = WatchedHistoryTimeline.fromTitles([show, film]);
      expect(WatchedHistoryTimeline.filter(all, query: 'mystery'),
          hasLength(1));
      expect(WatchedHistoryTimeline.filter(all, query: 's03 e06'),
          hasLength(1));
      expect(WatchedHistoryTimeline.filter(all, kind: 'movies'),
          hasLength(1));
      expect(WatchedHistoryTimeline.filter(all, kind: 'series'),
          hasLength(1));
      expect(WatchedHistoryTimeline.filter(all, query: 'unknown'), isEmpty);
    });

    test('recent entries are ordered and bounded', () {
      final items = List.generate(15, (i) => WatchedTitle(
        id: 'tt' + i.toString(), title: 'Title ' + i.toString(),
        type: 'movie', lastWatchedAt:
            morning.add(Duration(minutes: i)),
      ));
      final rows = WatchedHistoryTimeline.fromTitles(items, limit: 5);
      expect(rows, hasLength(5));
      expect(rows.first.title.title, 'Title 14');
      expect(rows.last.title.title, 'Title 10');
      expect(WatchedHistoryTimeline.fromTitles(items, limit: 0), isEmpty);
    });
  });
}
