import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/live_tv/live_playback_coordinator.dart';
import 'package:playtorrio/services/player/live_tv/live_tv_matrix_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> plan({int count = 50}) => {
    'runId': 'matrix_trial_2026',
    'seed': 19,
    'repeats': 1,
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
    var elapsedMs = 0;
    var currentId = '';
    final runner = LiveTvMatrixRunner(wait: (duration) async {
      elapsedMs += duration.inMilliseconds;
    });
    final result = await runner.start(plan(),
      open: (id, title, sourceIndex) async {
        elapsedMs = 0;
        currentId = id;
        return {'accepted': true, 'sourceCount': 1,
          'selectedIndex': sourceIndex, 'sourceHost': 'example.test'};
      },
      inspect: () async {
        return {'live': {
          'channelId': currentId,
          'playing': true, 'buffering': false, 'videoDimensionsReady': true,
          'videoWidth': 1280, 'videoHeight': 720, 'trackCount': 3,
          'positionMs': elapsedMs, 'activeSourceHost': 'example.test',
          'activeSourceIndex': 0,
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
  test('Tests every advertised backup source without conflating providers',
      () async {
    final runner = LiveTvMatrixRunner(wait: (_) async {});
    var index = 0;
    var channel = '';
    var pos = 0;
    final results = <String, Map<String, Object?>>{};
    final started = await runner.start(plan(),
      open: (id, title, sourceIndex) async {
        channel = id;
        index = sourceIndex;
        pos = 0;
        return {
          'accepted': true, 'sourceCount': 3,
          'selectedIndex': sourceIndex,
          'sourceHost': 'source' + sourceIndex.toString() + '.test',
        };
      },
      inspect: () async {
        pos += 70000;
        return {'live': {
          'channelId': channel, 'playing': true,
          'buffering': index != 1, 'videoDimensionsReady': index == 1,
          'videoWidth': index == 1 ? 1280 : null,
          'videoHeight': index == 1 ? 720 : null,
          'trackCount': index == 1 ? 3 : 0,
          'positionMs': index == 1 ? pos : 0,
          'activeSourceHost': 'source' + index.toString() + '.test',
          'activeSourceIndex': index,
        }};
      },
      publish: (runId, key, payload) async {
        if (key != 'status') results[key] = payload;
      },
    );
    expect(started['accepted'], true);
    await runner.whenComplete;
    expect(runner.status()['sourcesDone'], 150);
    expect(runner.status()['verifiedSources'], 50);
    expect(results['candidate_0_0']?['sustainedPlayback'], false);
    expect(results['candidate_0_1']?['requestedSourceVerified'], true);
    expect(results['candidate_0_2']?['sustainedPlayback'], false);
  });

  test('Rejects player evidence accidentally belonging to old channel',
      () async {
    final runner = LiveTvMatrixRunner(wait: (_) async {});
    await runner.start(plan(),
      open: (id, title, sourceIndex) async =>
          {'accepted': true, 'sourceCount': 1},
      inspect: () async => {'live': {
        'channelId': 'nltv:us:PreviousChannel',
        'playing': true, 'buffering': false,
        'videoWidth': 1280, 'videoHeight': 720, 'trackCount': 3,
        'positionMs': 123456,
      }},
      publish: (a, b, c) async {},
    );
    await runner.whenComplete;
    expect(runner.status()['verifiedSources'], 0);
  });

  test('Per-source network failures do not abort the remaining matrix',
      () async {
    final runner = LiveTvMatrixRunner(wait: (_) async {});
    await runner.start(plan(),
      open: (id, title, sourceIndex) async {
        if (id.endsWith('Channel0')) throw const FormatException('unavailable');
        return {'accepted': false, 'sourceCount': 1};
      },
      inspect: () async => {},
      publish: (a, b, c) async {},
    );
    await runner.whenComplete;
    expect(runner.status()['phase'], 'completed');
    expect(runner.status()['channelsDone'], 50);
    expect(runner.status()['verifiedSources'], 0);
  });

  test('Source indexes distinguish streams sharing a CDN hostname', () {
    final original = <StreamSource>[
      StreamSource(addonName: 'One', url: 'https://cdn.test/one.m3u8'),
      StreamSource(addonName: 'One', url: 'https://cdn.test/two.m3u8'),
      StreamSource(addonName: 'Two', url: 'https://cdn.test/one.m3u8'),
    ];
    expect(LivePlaybackCoordinator.originalSourceIndex(
        original, original[1]), 1);
    expect(LivePlaybackCoordinator.originalSourceIndex(
        original, original[2]), 2);
    expect(LivePlaybackCoordinator.originalSourceIndex(original,
        StreamSource(addonName: 'One', url: 'https://cdn.test/new.m3u8')),
        isNull);
    expect(LivePlaybackCoordinator.originalSourceIndex(
        <StreamSource>[original[0], original[0]], original[0]), isNull);
  });

  test('Same-host backup playing must not verify the requested source',
      () async {
    final results = <String, Map<String, Object?>>{};
    var elapsedMs = 0;
    var channel = '';
    var sourceIndex = 0;
    final runner = LiveTvMatrixRunner(wait: (duration) async {
      elapsedMs += duration.inMilliseconds;
    });
    await runner.start(plan(),
      open: (id, title, requestedIndex) async {
        channel = id;
        sourceIndex = requestedIndex;
        elapsedMs = 0;
        return {
          'accepted': true, 'sourceCount': 2,
          'selectedIndex': requestedIndex, 'sourceHost': 'shared.cdn.test',
        };
      },
      inspect: () async => {'live': {
        'channelId': channel, 'playing': true, 'buffering': false,
        'videoDimensionsReady': true, 'videoWidth': 1280,
        'videoHeight': 720, 'trackCount': 3,
        'positionMs': elapsedMs, 'activeSourceHost': 'shared.cdn.test',
        'activeSourceIndex': sourceIndex == 0 ? 1 : sourceIndex,
      }},
      publish: (runId, key, payload) async {
        if (key != 'status') results[key] = payload;
      },
    );
    await runner.whenComplete;
    expect(results['candidate_0_0']?['sustainedPlayback'], true);
    expect(results['candidate_0_0']?['sourceSwitchedBeforeSample'], true);
    expect(results['candidate_0_0']?['requestedSourceVerified'], false);
    expect(results['candidate_0_1']?['requestedSourceVerified'], true);
  });

  test('Failover during sustained playback revokes source attribution',
      () async {
    final results = <String, Map<String, Object?>>{};
    var elapsedMs = 0;
    var channel = '';
    var sourceIndex = 0;
    var observations = 0;
    final runner = LiveTvMatrixRunner(wait: (duration) async {
      elapsedMs += duration.inMilliseconds;
    });
    await runner.start(plan(),
      open: (id, title, requestedIndex) async {
        channel = id;
        sourceIndex = requestedIndex;
        elapsedMs = 0;
        observations = 0;
        return {
          'accepted': true, 'sourceCount': 2,
          'selectedIndex': requestedIndex, 'sourceHost': 'shared.cdn.test',
        };
      },
      inspect: () async {
        observations++;
        return {'live': {
          'channelId': channel, 'playing': true, 'buffering': false,
          'videoDimensionsReady': true, 'videoWidth': 1280,
          'videoHeight': 720, 'trackCount': 3,
          'positionMs': elapsedMs, 'activeSourceHost': 'shared.cdn.test',
          'activeSourceIndex': sourceIndex == 0 && observations > 3
              ? 1 : sourceIndex,
        }};
      },
      publish: (runId, key, payload) async {
        if (key != 'status') results[key] = payload;
      },
    );
    await runner.whenComplete;
    expect(results['candidate_0_0']?['sustainedPlayback'], true);
    expect(results['candidate_0_0']?['sourceSwitchedBeforeSample'], false);
    expect(results['candidate_0_0']?['requestedSourceVerified'], false);
    expect(results['candidate_0_1']?['requestedSourceVerified'], true);
  });

  test('Default full matrix repeats each distinct channel three times',
      () async {
    final runner = LiveTvMatrixRunner(wait: (_) async {});
    final repeatedPlan = plan()..remove('repeats');
    final started = await runner.start(repeatedPlan,
      open: (id, title, sourceIndex) async =>
          {'accepted': false, 'sourceCount': 1,
           'sourceHost': 'provider.test'},
      inspect: () async => {},
      publish: (a, b, c) async {},
    );
    expect(started['accepted'], true);
    await runner.whenComplete;
    expect(runner.status()['phase'], 'completed');
    expect(runner.status()['uniqueChannels'], 50);
    expect(runner.status()['repeatCount'], 3);
    expect(runner.status()['totalChannels'], 150);
    expect(runner.status()['channelsDone'], 150);
    expect(runner.status()['sourcesDone'], 150);
    expect(runner.status()['distinctSourceHosts'], 1);
    expect(runner.status()['hostDiversityTargetMet'], false);
  });

}
