import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/movie/movie.dart';
import 'package:playtorrio/services/player/live_tv/live_channel_health_scanner.dart';
import 'package:playtorrio/services/remote/ios_remote_live_scan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Unattended scan produces distinct HTTP and native evidence', () async {
    final scan = IosRemoteLiveScan();
    final started = await scan.start({
      'runId': 'scan_native_2026',
      'channels': [
        {'id': 'nltv:us:SportsOne.us', 'title': 'Sports One'},
      ],
      'verifyNative': true,
    },
      deviceIdle: () => true,
      inspect: (Movie channel) async => const LiveChannelHealthResult(
        LiveChannelHealth.likelyReachable, 1,
        'segment_reachable_not_decoded',
      ),
      verify: (Movie channel, LiveChannelHealthResult preflight,
          bool Function() cancelled) async => LiveChannelHealthResult(
        LiveChannelHealth.verified, 1, 'native_video_verified',
        nativeChecked: true, nativeAttempts: 1,
        playableSourceIndex: 0, videoWidth: 1280, videoHeight: 720,
        startupMs: 400,
      ),
    );
    expect(started['accepted'], true);
    await scan.whenComplete;
    final state = scan.status();
    expect(state['phase'], 'completed');
    expect(state['tested'], 1);
    expect(state['nativeVerified'], 1);
    expect((state['results'] as List).single['nativeVerified'], true);
  });

  test('Active user playback blocks background scan', () async {
    final scan = IosRemoteLiveScan();
    final result = await scan.start({
      'runId': 'scan_busy_2026',
      'channels': [
        {'id': 'nltv:us:SportsOne.us', 'title': 'Sports One'},
      ],
    }, deviceIdle: () => false);
    expect(result['accepted'], false);
    expect(result['reason'], 'device_busy_or_not_foreground');
  });
}
