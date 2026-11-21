import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/movie/movie.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/live_tv/live_channel_health_scanner.dart';
import 'package:playtorrio/services/player/live_tv/live_source_manager.dart';

void main() {
  tearDown(() {
    LiveChannelHealthScanner.resolveOverride = null;
    LiveChannelHealthScanner.probeOverride = null;
  });

  final channel = Movie(
    id: 'nltv:us:Example.us', name: 'Example', type: 'tv',
    addonBaseUrl: 'https://example.test',
  );

  test('Successful segment means likely reachable, not native verified', () async {
    LiveChannelHealthScanner.resolveOverride = (_) async => [
      StreamSource(url: 'https://example.test/live.m3u8', addonName: 'TV'),
    ];
    LiveChannelHealthScanner.probeOverride = (_, __) async =>
        const LiveSourceProbe(phase: 'segment', outcome: 'ok',
            httpStatus: 206, elapsedMs: 1, headerCount: 0);
    final result = await LiveChannelHealthScanner.inspect(channel);
    expect(result.health, LiveChannelHealth.likelyReachable);
    expect(result.reason, 'segment_reachable_not_decoded');
  });

  test('HTTP 403 candidate is poor, not healthy', () async {
    LiveChannelHealthScanner.resolveOverride = (_) async => [
      StreamSource(url: 'https://example.test/live.m3u8', addonName: 'TV'),
    ];
    LiveChannelHealthScanner.probeOverride = (_, __) async =>
        const LiveSourceProbe(phase: 'segment', outcome: 'http_status',
            httpStatus: 403, elapsedMs: 1, headerCount: 0);
    final result = await LiveChannelHealthScanner.inspect(channel);
    expect(result.health, LiveChannelHealth.poor);
  });

  test('Bounded workers stop publishing on cancellation', () async {
    LiveChannelHealthScanner.resolveOverride = (_) async => [];
    var published = 0;
    await LiveChannelHealthScanner.scan([channel, channel],
      isCancelled: () => published > 0,
      onResult: (_, __) => published++,
      concurrency: 1,
    );
    expect(published, 1);
  });
}
