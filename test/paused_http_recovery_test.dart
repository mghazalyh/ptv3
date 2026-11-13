import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/paused_http_recovery.dart';

void main() {
  final now = DateTime.utc(2026, 10, 28, 12);
  test('long pause eligible VOD only', () {
    expect(PausedHttpRecovery.needsReopen(true,
        now.subtract(const Duration(seconds: 91)), now), isTrue);
    expect(PausedHttpRecovery.needsReopen(true,
        now.subtract(const Duration(seconds: 30)), now), isFalse);
    expect(PausedHttpRecovery.needsReopen(false,
        now.subtract(const Duration(hours: 2)), now), isFalse);
    expect(PausedHttpRecovery.needsReopen(true, null, now), isFalse);
  });
  test('resume should reuse a healthy connection', () {
    bool stalled(Duration after, {bool http = true, bool playing = true,
        int attempts = 0}) => PausedHttpRecovery.stalledAfterResume(
      isHttpVod: http, requestedPlayback: playing,
      before: const Duration(minutes: 31), after: after,
      attempts: attempts);
    expect(stalled(const Duration(minutes: 31, seconds: 2)), isFalse);
    expect(stalled(const Duration(minutes: 31)), isTrue);
    expect(stalled(const Duration(minutes: 31), http: false), isFalse);
    expect(stalled(const Duration(minutes: 31), playing: false), isFalse);
    expect(stalled(const Duration(minutes: 31),
        attempts: PausedHttpRecovery.maxAttempts), isFalse);
  });
  test('real iPad ffurl_read error: only recent resume and bounded attempts', () {
    const error = 'Playback error: tcp: ffurl_read returned 0xfffffcf7';
    expect(PausedHttpRecovery.canRetryError(error, true,
        now.subtract(const Duration(seconds: 10)), now, 0), isTrue);
    expect(PausedHttpRecovery.canRetryError(error, true,
        now.subtract(const Duration(minutes: 3)), now, 0), isFalse);
    expect(PausedHttpRecovery.canRetryError(error, false, now, now, 0), isFalse);
    expect(PausedHttpRecovery.canRetryError(
        error, true, now, now, PausedHttpRecovery.maxAttempts), isFalse);
  });
  test('only transient network read failures trigger reconnection', () {
    expect(PausedHttpRecovery.isReadFailure('tcp: connection reset'), isTrue);
    expect(PausedHttpRecovery.isReadFailure('Broken pipe'), isTrue);
    expect(PausedHttpRecovery.isReadFailure('codec unsupported'), isFalse);
    expect(PausedHttpRecovery.isReadFailure('subtitle .srt error'), isFalse);
  });
  test('resume time preserved, never seeks past duration', () {
    expect(PausedHttpRecovery.safePosition(
        const Duration(minutes: 19), const Duration(minutes: 42)),
        const Duration(minutes: 19));
    expect(PausedHttpRecovery.safePosition(
        const Duration(seconds: 600), const Duration(seconds: 600)),
        const Duration(seconds: 597));
    expect(PausedHttpRecovery.safePosition(
        const Duration(seconds: 12), Duration.zero),
        const Duration(seconds: 12));
  });
}
