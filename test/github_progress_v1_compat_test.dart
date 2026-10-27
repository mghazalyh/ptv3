import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/continue_watching/continue_watching_item.dart';
import 'package:playtorrio/services/continue_watching/github_progress_cloud.dart';

void main() {
  test('legacy v1 local lastWatchedAt uses corresponding UTC updatedAt', () {
    final rows = GitHubProgressMerge.decode('''
{"version":1,"records":{"tt123":{"updatedAt":"2026-10-27T13:43:31.725183Z","deleted":false,"item":{"id":"tt123","title":"Example","type":"series","season":1,"episode":1,"positionSeconds":1304,"totalDurationSeconds":2958,"lastWatchedAt":"2026-10-27T21:43:31.723481","isTorrent":false}}}}
''');
    final entry = GitHubProgressMerge.visible(rows).single;
    expect(entry.lastWatchedAt.isUtc, isTrue);
    expect(entry.lastWatchedAt.hour, 13);
    expect(entry.positionSeconds, 1304);
  });

  test('new v1 entries keep UTC timestamps, compact source hints and true progress', () {
    final item = ContinueWatchingItem(
      id:'tt999', title:'Example', type:'series', season:2, episode:1,
      episodeId:'tt999:2:1', positionSeconds:300, totalDurationSeconds:2000,
      lastWatchedAt: DateTime.utc(2026,10,27,14),
      addonName:'Torrentio TB', streamName:'1080p',
      streamTitle:'A very long provider filename',
      isTorrent:false,
    );
    final record = GitHubProgressMerge.toRecord(item);
    final data = record['item'] as Map;
    expect(data['streamTitle'], isNull);
    expect(data['streamName'], '1080p');
    expect(data['quality'], isNull);
    expect(data['lastWatchedAt'], '2026-10-27T14:00:00.000Z');
    expect(record['deleted'], isFalse);
    expect(record['updatedAt'], '2026-10-27T14:00:00.000Z');
  });

  test('older position on another device cannot override more recent action', () {
    final newer = {
      'updatedAt':'2026-10-27T10:00:00Z','deleted':false,
      'item':{'id':'tt9','title':'X','type':'series',
        'positionSeconds':100, 'totalDurationSeconds':1000},
    };
    final older = {
      'updatedAt':'2026-10-27T09:00:00Z','deleted':false,
      'item':{'id':'tt9','title':'X','type':'series',
        'positionSeconds':950, 'totalDurationSeconds':1000},
    };
    final merged = GitHubProgressMerge.merge({'tt9':newer}, {'tt9':older});
    expect((merged['tt9'] as Map)['item'], newer['item']);
  });
}
