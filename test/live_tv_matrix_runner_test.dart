import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/live_tv/live_tv_matrix_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> plan({int count = 50}) => {
    'runId': 'matrix_trial_2026',
    'seed': 19,
    'channels': List.generate(count, (index) => {
      'id': 'nltv:us:Channel' + index.toString(),
      'title': 'Channel ' + index.toString(),
    }),
  };

  test('Reject plans with fewer than 50 channels and duplicates', () async {
    final runner = LiveTvMatrixRunner(wait: (_) async {});
    Future<Map<String, Object?>> open(String a,String b,int c) async => {};
    Future<Map<String, Object?>> inspect() async => {};
    Future<void> publish(String a,String b,Map<String,Object?> c) async {}
    expect((await runner.start(plan(count: 49), open: open,
        inspect: inspect, publish: publish))['accepted'], false);
    final duplicated = plan();
    (duplicated['channels'] as List)[1] =
        (duplicated['channels'] as List).first;
    expect((await runner.start(duplicated, open: open,
        inspect: inspect, publish: publish))['accepted'], false);
  });

  test('Audits 50 channels with 3 native samples and sustained video', () async {
    final published = <String, Map<String, Object?>>{};
    var tick = 0;
    var currentId = '';
    final runner = LiveTvMatrixRunner(wait: (_) async {});
    final result = await runner.start(plan(),
      open: (id, title, sourceIndex) async {
        tick = 0;
        currentId = id;
        return {'accepted': true, 'sourceCount': 1, 'sourceHost': 'example.test'};
      },
      inspect: () async {
        tick++;
        return {'live': {
          'channelId': currentId,
          'playing': true, 'buffering': false, 'videoDimensionsReady': true,
          'videoWidth': 1280, 'videoHeight': 720, 'trackCount': 3,
          'positionMs': tick * 2000, 'activeSourceHost': 'example.test',
          'nativeFormat': 'hls',
        }};
      },
      publish: (runId, key, payload) async {
        published[key] = Map<String, Object?>.from(payload);
      },
    );
    expect(result['accepted'], true);
    await runner.whenComplete;
    expect(runner.status()['phase'], 'completed');
    expect(runner.status()['channelsDone'], 50);
    expect(runner.status()['sourcesDone'], 50);
    expect(runner.status()['verifiedSources'], 50);
    expect(published['candidate_0_0']?['sustainedPlayback'], true);
  });

  test('Does not count HTTP reachability as decoded video', () async {
    final runner = LiveTvMatrixRunner(wait: (_) async {});
    final result = await runner.start(plan(),
      open: (id, title, sourceIndex) async =>
          {'accepted': true, 'sourceCount': 1},
      inspect: () async => {'live': {
        'playing': true, 'buffering': true,
        'trackCount': 0, 'positionMs': 0,
      }},
      publish: (a, b, c) async {},
    );
    expect(result['accepted'], true);
    await runner.whenComplete;
    expect(runner.status()['verifiedSources'], 0);
  });
}
