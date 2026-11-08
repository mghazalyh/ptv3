import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/addon/connected_catalog_history_bridge.dart';
import 'package:playtorrio/services/continue_watching/watched_history_service.dart';

void main() {
  final at = DateTime.utc(2026, 11, 8);
  WatchedPlaybackPosition position(bool complete) => WatchedPlaybackPosition(
      positionSeconds: complete ? 900 : 10, totalDurationSeconds: 1000,
      updatedAt: at, completed: complete);

  test('only actual completed titles and independently timed episodes upload', () {
    final titles = [
      WatchedTitle(id: 'tt1234567', title: 'Movie', type: 'movie',
          lastWatchedAt: at, completed: true),
      WatchedTitle(id: 'tt2345678', title: 'Series', type: 'series',
          lastWatchedAt: at, playbackPositions: {
            'tt2345678:1:2': position(true),
            'tt2345678:1:3': position(false),
          }),
      WatchedTitle(id: 'tt3456789', title: 'Unwatched', type: 'movie',
          lastWatchedAt: at),
    ];
    final events = ConnectedCatalogHistoryBridge.plan(titles);
    final data = ConnectedCatalogHistoryBridge.payload(events);
    expect(events.length, 2);
    expect((data['movies'] as List).length, 1);
    expect((data['shows'] as List).length, 1);
    expect((data['shows'] as List).single['seasons'].single['episodes']
        .single['number'], 2);
  });

  test('no fabricated episode dates from legacy imports', () {
    final row = WatchedTitle(id: 'tt1234567', title: 'Legacy', type: 'series',
        lastWatchedAt: at, completedEpisodeIds: ['tt1234567:2:4']);
    expect(ConnectedCatalogHistoryBridge.plan([row]), isEmpty);
  });

  test('unknown IDs, unfinished watches and duplicates are rejected', () {
    final rows = [
      WatchedTitle(id: 'private-stream-id', title: 'Private', type: 'movie',
          completed: true, lastWatchedAt: at),
      WatchedTitle(id: 'tt2345678', title: 'Partial', type: 'movie',
          lastWatchedAt: at,
          playbackPositions: {'movie': position(false)}),
      WatchedTitle(id: 'tmdb_movie_42', title: 'Complete', type: 'movie',
          completed: true, lastWatchedAt: at),
    ];
    final events = ConnectedCatalogHistoryBridge.plan([...rows, rows.last]);
    expect(events.length, 1);
    expect(events.single.value['ids'], {'tmdb': 42});
    expect(events.single.value.containsKey('title'), isFalse);
  });
}
