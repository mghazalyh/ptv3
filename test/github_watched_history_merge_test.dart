import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/continue_watching/watched_history_service.dart';
import 'package:playtorrio/services/continue_watching/github_watched_history_cloud.dart';

WatchedTitle watched(String id, DateTime at, {
  bool completed = false,
  List<String> episodes = const [],
  String title = 'Example Series',
}) => WatchedTitle(
  id: id, title: title, type: 'series',
  lastWatchedAt: at, completed: completed,
  completedEpisodeIds: episodes,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('v1 watched history has a strict, backwards-compatible envelope', () {
    expect(GitHubWatchedHistoryMerge.decode('{"version":1,"records":{}}'), isEmpty);
    expect(() => GitHubWatchedHistoryMerge.decode('{"version":2,"records":{}}'),
        throwsFormatException);
    expect(() => GitHubWatchedHistoryMerge.decode('broken'),
        throwsFormatException);
  });

  test('episodes completed on two devices are unioned, not overwritten', () {
    final older = watched('tt100', DateTime.utc(2026, 10, 27, 8),
        episodes: ['tt100:1:1']);
    final newer = watched('tt100', DateTime.utc(2026, 10, 27, 9),
        episodes: ['tt100:1:2']);
    final merged = GitHubWatchedHistoryMerge.merge(
      {'series:tt100': GitHubWatchedHistoryMerge.toRecord(older)},
      {'series:tt100': GitHubWatchedHistoryMerge.toRecord(newer)},
    );
    expect(GitHubWatchedHistoryMerge.visible(merged).single.completedEpisodeIds,
        ['tt100:1:1', 'tt100:1:2']);
  });

  test('older offline device cannot erase newer title or completed episodes', () {
    final newer = watched('tt100', DateTime.utc(2026, 10, 27, 10),
        episodes: ['tt100:1:3'], title: 'Fresh Title');
    final old = watched('tt100', DateTime.utc(2026, 10, 27, 8),
        episodes: ['tt100:1:1'], title: 'Stale Title');
    final merged = GitHubWatchedHistoryMerge.merge(
      {'series:tt100': GitHubWatchedHistoryMerge.toRecord(newer)},
      {'series:tt100': GitHubWatchedHistoryMerge.toRecord(old)},
    );
    final result = GitHubWatchedHistoryMerge.visible(merged).single;
    expect(result.title, 'Fresh Title');
    expect(result.completedEpisodeIds, ['tt100:1:1', 'tt100:1:3']);
  });

  test('first import to an existing repo merges newer local records', () {
    final remote = watched('tt100', DateTime.utc(2026, 10, 26, 8),
        title: 'Old name');
    final local = watched('tt100', DateTime.utc(2026, 10, 27, 8),
        title: 'Correct name');
    final merged = GitHubWatchedHistoryMerge.merge(
      {'series:tt100': GitHubWatchedHistoryMerge.toRecord(remote)},
      {}, firstImport: [local]);
    expect(GitHubWatchedHistoryMerge.visible(merged).single.title, 'Correct name');
  });

  test('a completed movie is never undone by a second device rewatch', () {
    final remote = {
      'movie:tt11': {
        'updatedAt': '2026-10-27T10:00:00Z', 'deleted': false,
        'item': {
          'id':'tt11','title':'Movie','type':'movie',
          'lastWatchedAt':'2026-10-27T10:00:00Z','completed':true,
        },
      },
    };
    final newer = {
      'movie:tt11': {
        'updatedAt': '2026-10-27T11:00:00Z', 'deleted': false,
        'item': {
          'id':'tt11','title':'Movie','type':'movie',
          'lastWatchedAt':'2026-10-27T11:00:00Z','completed':false,
        },
      },
    };
    final finalState = GitHubWatchedHistoryMerge.merge(remote, newer);
    expect(GitHubWatchedHistoryMerge.visible(finalState).single.completed, isTrue);
  });

  test('a finished episode does not complete an entire TV series', () async {
    await WatchedHistoryService.initialize();
    await WatchedHistoryService.recordProgress(
      id:'tt200', title:'Series', type:'series',
      positionSeconds:2800, totalDurationSeconds:3000,
      episodeId:'tt200:2:8',
    );
    final entry = WatchedHistoryService.items.value.single;
    expect(entry.completed, isFalse);
    expect(entry.completedEpisodeIds, ['tt200:2:8']);
  });

  test('30-second provisional duration is ignored; short accidental playback too', () async {
    await WatchedHistoryService.initialize();
    await WatchedHistoryService.recordProgress(
      id:'tt300', title:'Series', type:'series',
      positionSeconds:5, totalDurationSeconds:30,
      episodeId:'tt300:1:1',
    );
    await WatchedHistoryService.recordProgress(
      id:'tt301', title:'Series Two', type:'series',
      positionSeconds:15, totalDurationSeconds:1500,
      episodeId:'tt301:1:1',
    );
    expect(WatchedHistoryService.items.value, isEmpty);
  });

  test('malformed item does not hide other valid watched titles', () {
    final rows = GitHubWatchedHistoryMerge.visible({
      'bad': {'deleted':false, 'item':'broken'},
      'series:good': GitHubWatchedHistoryMerge.toRecord(
          watched('good', DateTime.utc(2026,10,27))),
    });
    expect(rows.length, 1);
    expect(rows.single.id, 'good');
  });
}
