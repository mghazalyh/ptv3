import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/movie/movie.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/live_tv/live_channel_health_scanner.dart';
import 'package:playtorrio/services/player/live_tv/live_source_manager.dart';
import 'package:playtorrio/services/player/live_tv/live_native_channel_verifier.dart';
import 'package:playtorrio/services/player/live_tv/live_verified_source_preference.dart';

void main() {
  tearDown(() {
    LiveChannelHealthScanner.resolveOverride = null;
    LiveChannelHealthScanner.probeOverride = null;
    LiveNativeChannelVerifier.probeOverride = null;
    LiveVerifiedSourcePreference.clearForTesting();
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
  test('Health sort puts actual decoded channels before HTTP successes', () {
    Movie movie(String id) => Movie(
      id: 'nltv:us:$id.us', name: id, type: 'tv',
      addonBaseUrl: 'https://example.test',
    );
    final originals = [
      movie('Poor'), movie('Checking'), movie('Reachable'),
      movie('Backup'), movie('Native'), movie('Unknown'),
    ];
    final sorted = LiveChannelHealthScanner.sortedByHealth(
      originals, <String, LiveChannelHealthResult>{
        originals[0].id: const LiveChannelHealthResult(
          LiveChannelHealth.poor, 2, 'native_no_playable_sources'),
        originals[2].id: const LiveChannelHealthResult(
          LiveChannelHealth.likelyReachable, 1,
          'segment_reachable_not_decoded'),
        originals[3].id: const LiveChannelHealthResult(
          LiveChannelHealth.unstable, 2, 'native_backup_verified',
          nativeChecked: true, playableSourceIndex: 1),
        originals[4].id: const LiveChannelHealthResult(
          LiveChannelHealth.verified, 1, 'native_video_verified',
          nativeChecked: true, playableSourceIndex: 0),
        originals[5].id: const LiveChannelHealthResult(
          LiveChannelHealth.unknown, 0, 'discovery_unavailable'),
      },
    );
    expect(sorted.map((m) => m.name).toList(), [
      'Native', 'Backup', 'Reachable', 'Unknown', 'Poor', 'Checking',
    ]);
  });

  test('Verified backup ranks before stalled video in the unstable tier', () {
    Movie channel(String name) => Movie(
      id: 'nltv:us:${name}.us', name: name, type: 'tv',
      addonBaseUrl: 'https://example.test',
    );
    final stalled = channel('Stalled');
    final slowBackup = channel('SlowBackup');
    final fastBackup = channel('FastBackup');
    final reachable = channel('Reachable');
    final sorted = LiveChannelHealthScanner.sortedByHealth(
      [stalled, slowBackup, reachable, fastBackup],
      {
        stalled.id: const LiveChannelHealthResult(
          LiveChannelHealth.unstable, 1, 'native_rendered_but_stalled',
          nativeChecked: true),
        slowBackup.id: const LiveChannelHealthResult(
          LiveChannelHealth.unstable, 2, 'native_backup_verified',
          nativeChecked: true, playableSourceIndex: 1, startupMs: 4200),
        fastBackup.id: const LiveChannelHealthResult(
          LiveChannelHealth.unstable, 2, 'native_backup_verified',
          nativeChecked: true, playableSourceIndex: 1, startupMs: 2100),
        reachable.id: const LiveChannelHealthResult(
          LiveChannelHealth.likelyReachable, 1,
          'segment_reachable_not_decoded'),
      },
    );
    expect(sorted.map((movie) => movie.name).toList(),
      ['FastBackup', 'SlowBackup', 'Stalled', 'Reachable']);
  });

  test('Equal native grades are ordered by startup then original order', () {
    final a = Movie(id: 'nltv:us:A.us', name: 'A', type: 'tv',
      addonBaseUrl: 'https://example.test');
    final b = Movie(id: 'nltv:us:B.us', name: 'B', type: 'tv',
      addonBaseUrl: 'https://example.test');
    final c = Movie(id: 'nltv:us:C.us', name: 'C', type: 'tv',
      addonBaseUrl: 'https://example.test');
    final sorted = LiveChannelHealthScanner.sortedByHealth([a, b, c], {
      a.id: const LiveChannelHealthResult(
        LiveChannelHealth.verified, 1, 'native_video_verified',
        nativeChecked: true, playableSourceIndex: 0, startupMs: 5000),
      b.id: const LiveChannelHealthResult(
        LiveChannelHealth.verified, 1, 'native_video_verified',
        nativeChecked: true, playableSourceIndex: 0, startupMs: 2500),
      c.id: const LiveChannelHealthResult(
        LiveChannelHealth.verified, 1, 'native_video_verified',
        nativeChecked: true, playableSourceIndex: 0, startupMs: 2500),
    });
    expect(sorted.map((m) => m.name).toList(), ['B', 'C', 'A']);
  });

  test('Native MPV verification upgrades only true decoded moving video',
      () async {
    final candidate = StreamSource(
      url: 'https://example.test/live.m3u8', addonName: 'TV');
    final preflight = LiveChannelHealthResult(
      LiveChannelHealth.likelyReachable, 1,
      'segment_reachable_not_decoded', sources: [candidate]);
    LiveNativeChannelVerifier.probeOverride = (_, __, ___) async =>
      const LiveNativeSourceResult(
        renderedVideo: true, timelineAdvanceMs: 6800, buffering: false,
        videoWidth: 1920, videoHeight: 1080, trackCount: 11, startupMs: 1100,
      );
    final result = await LiveChannelHealthScanner.verifyNative(
      channel, preflight, isCancelled: () => false);
    expect(result.health, LiveChannelHealth.verified);
    expect(result.nativeVerified, true);
    expect(result.videoWidth, 1920);
    expect(result.playableSourceIndex, 0);
    // A native decoded-video success, not a successful HTTP range request,
    // is allowed to promote that exact StreamSource for actual playback.
    final unrelated = StreamSource(
      url: 'https://example.test/unrelated.m3u8', addonName: 'TV');
    final ordered = LiveVerifiedSourcePreference.prioritize(
        channel.id, [unrelated, candidate]);
    expect(ordered.first.url, candidate.url);
  });

  test('First source fails but a decoded backup is explicitly lower ranked',
      () async {
    final first = StreamSource(
      url: 'https://example.test/dead.m3u8', addonName: 'TV');
    final backup = StreamSource(
      url: 'https://example.test/backup.m3u8', addonName: 'TV');
    final preflight = LiveChannelHealthResult(
      LiveChannelHealth.likelyReachable, 2,
      'segment_reachable_not_decoded', sources: [first, backup]);
    LiveNativeChannelVerifier.probeOverride = (_, source, __) async =>
      source.url!.contains('backup')
          ? const LiveNativeSourceResult(
              renderedVideo: true, timelineAdvanceMs: 6200,
              buffering: false, videoWidth: 1280, videoHeight: 720,
              trackCount: 8)
          : const LiveNativeSourceResult(
              renderedVideo: false, timelineAdvanceMs: 0, buffering: true);
    final result = await LiveChannelHealthScanner.verifyNative(
      channel, preflight, isCancelled: () => false);
    expect(result.health, LiveChannelHealth.unstable);
    expect(result.label, 'Works via backup');
    expect(result.nativeAttempts, 2);
    expect(result.playableSourceIndex, 1);
    expect(result.nativeVerified, true);
  });

  test('HTTP 206 plus an audio clock without video does not pass MPV',
      () async {
    final candidate = StreamSource(
      url: 'https://example.test/partial.m3u8', addonName: 'TV');
    final preflight = LiveChannelHealthResult(
      LiveChannelHealth.likelyReachable, 1,
      'segment_reachable_not_decoded', sources: [candidate]);
    LiveNativeChannelVerifier.probeOverride = (_, __, ___) async =>
      const LiveNativeSourceResult(
        renderedVideo: false, timelineAdvanceMs: 7000,
        buffering: false, trackCount: 1,
      );
    final result = await LiveChannelHealthScanner.verifyNative(
      channel, preflight, isCancelled: () => false);
    expect(result.health, LiveChannelHealth.poor);
    expect(result.nativeChecked, true);
    expect(result.nativeVerified, false);
    final unrelated = StreamSource(
      url: 'https://example.test/other.m3u8', addonName: 'TV');
    expect(LiveVerifiedSourcePreference.prioritize(
      channel.id, [unrelated, candidate]).first.url, unrelated.url);
  });

  test('A rendered but stalled channel is unstable, not verified', () async {
    final candidate = StreamSource(
      url: 'https://example.test/stall.m3u8', addonName: 'TV');
    final preflight = LiveChannelHealthResult(
      LiveChannelHealth.unknown, 1,
      'inconclusive_http', sources: [candidate]);
    LiveNativeChannelVerifier.probeOverride = (_, __, ___) async =>
      const LiveNativeSourceResult(
        renderedVideo: true, timelineAdvanceMs: 0,
        buffering: true, videoWidth: 1280, videoHeight: 720, trackCount: 11,
      );
    final result = await LiveChannelHealthScanner.verifyNative(
      channel, preflight, isCancelled: () => false);
    expect(result.health, LiveChannelHealth.unstable);
    expect(result.nativeVerified, false);
    expect(result.label, 'Unstable');
  });

  test('Cancelled native scan preserves provisional result', () async {
    final candidate = StreamSource(
      url: 'https://example.test/one.m3u8', addonName: 'TV');
    final preflight = LiveChannelHealthResult(
      LiveChannelHealth.likelyReachable, 1,
      'segment_reachable_not_decoded', sources: [candidate]);
    var calls = 0;
    LiveNativeChannelVerifier.probeOverride = (_, __, ___) async {
      calls++;
      return const LiveNativeSourceResult(
        renderedVideo: true, timelineAdvanceMs: 6000,
        buffering: false, videoWidth: 1920, videoHeight: 1080, trackCount: 8);
    };
    final result = await LiveChannelHealthScanner.verifyNative(
      channel, preflight, isCancelled: () => true);
    expect(result, same(preflight));
    expect(calls, 0);
  });

}
