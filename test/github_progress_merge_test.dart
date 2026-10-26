import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/continue_watching/continue_watching_item.dart';
import 'package:playtorrio/services/continue_watching/github_progress_cloud.dart';

ContinueWatchingItem item(String id, {
  int season = 1,
  int episode = 1,
  int position = 900,
  int total = 3000,
  int minutes = 1,
}) => ContinueWatchingItem(
  id: id,
  title: 'Example show',
  type: 'series',
  season: season,
  episode: episode,
  episodeId: '$id:$season:$episode',
  positionSeconds: position,
  totalDurationSeconds: total,
  lastWatchedAt: DateTime.utc(2026, 10, 26, 12, minutes),
  addonName: 'Torrentio',
  rawUrl: 'https://example.org/stream?api_key=secret',
  headers: const {'Authorization': 'Bearer secret'},
  infoHash: 'private_hash',
  magnetUrl: 'magnet:?secret',
  isTorrent: true,
);

void main() {
  test('private progress file has a strict versioned envelope', () {
    expect(GitHubProgressMerge.decode('{"version":1,"records":{}}'), isEmpty);
    expect(() => GitHubProgressMerge.decode('{"version":9,"records":{}}'),
        throwsFormatException);
    expect(() => GitHubProgressMerge.decode('not-json'),
        throwsFormatException);
  });

  test('session preserves episode, position and duration only', () {
    final serialized = GitHubProgressMerge.toRecord(item('tt123'));
    final encoded = jsonEncode(serialized);
    expect(encoded, contains('"positionSeconds":900'));
    expect(encoded, contains('"totalDurationSeconds":3000'));
    expect(encoded, contains('"episode":1'));
    expect(encoded, isNot(contains('api_key')));
    expect(encoded, isNot(contains('Authorization')));
    expect(encoded, isNot(contains('private_hash')));
    expect(encoded, isNot(contains('magnet:')));
    final recovered = GitHubProgressMerge.visible({'tt123': serialized});
    expect(recovered.single.positionSeconds, 900);
    expect(recovered.single.episode, 1);
  });

  test('newest action on same show wins, not largest playback position', () {
    final older = GitHubProgressMerge.toRecord(item('tt42', position: 2000),
        changedAt: DateTime.utc(2026, 10, 26, 9));
    final newer = GitHubProgressMerge.toRecord(item('tt42', position: 300),
        changedAt: DateTime.utc(2026, 10, 26, 10));
    final merged = GitHubProgressMerge.merge({'tt42': newer}, {'tt42': older});
    expect(GitHubProgressMerge.visible(merged).single.positionSeconds, 300);
  });

  test('later episode for same series replaces earlier episode', () {
    final one = GitHubProgressMerge.toRecord(item('tt42', episode: 1),
        changedAt: DateTime.utc(2026, 10, 26, 9));
    final two = GitHubProgressMerge.toRecord(item('tt42', episode: 2),
        changedAt: DateTime.utc(2026, 10, 26, 10));
    final merged = GitHubProgressMerge.merge({'tt42': one}, {'tt42': two});
    expect(GitHubProgressMerge.visible(merged).single.episode, 2);
  });

  test('completed episodes create a tombstone and disappear across devices', () {
    final done = GitHubProgressMerge.toRecord(item('tt42', position: 2800),
        changedAt: DateTime.utc(2026, 10, 26, 11));
    expect(done['deleted'], isTrue);
    final old = GitHubProgressMerge.toRecord(item('tt42', position: 400),
        changedAt: DateTime.utc(2026, 10, 26, 9));
    final merged = GitHubProgressMerge.merge({'tt42': done}, {'tt42': old});
    expect(GitHubProgressMerge.visible(merged), isEmpty);
  });

  test('manual Continue Watching removal persists across device imports', () {
    final removed = GitHubProgressMerge.toRecord(item('tt42'),
      removed: true, changedAt: DateTime.utc(2026, 10, 26, 12));
    final merged = GitHubProgressMerge.merge(
      {'tt42': removed}, {},
      firstImport: [item('tt42'), item('tt77')],
    );
    expect(GitHubProgressMerge.visible(merged).map((i) => i.id), ['tt77']);
  });

  test('concurrent changes to different shows preserve both records', () {
    final existing = {'tt1': GitHubProgressMerge.toRecord(item('tt1'))};
    final own = {'tt2': GitHubProgressMerge.toRecord(item('tt2'))};
    final merged = GitHubProgressMerge.merge(existing, own);
    expect(GitHubProgressMerge.visible(merged).map((i) => i.id),
        containsAll(['tt1', 'tt2']));
  });

  test('damaged session is ignored without hiding valid sessions', () {
    final records = {
      'bad': {'deleted': false, 'item': 'not-a-session'},
      'tt2': GitHubProgressMerge.toRecord(item('tt2')),
    };
    expect(GitHubProgressMerge.visible(records).single.id, 'tt2');
  });
}
