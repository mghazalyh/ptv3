import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/playback_frame_health.dart';

void main() {
  test('distinguishes smooth frames from concurrent-load raster stalls', () {
    final health = PlaybackFrameHealth();
    health.recordDurations(const Duration(milliseconds: 4),
        const Duration(milliseconds: 5));
    health.recordDurations(const Duration(milliseconds: 40),
        const Duration(milliseconds: 84));
    final first = health.takeSnapshot();
    expect(first['flutter-frame-count'], 2);
    expect(first['flutter-slow-build-count'], 1);
    expect(first['flutter-slow-raster-count'], 1);
    expect(first['flutter-worst-raster-ms'], 84);
    expect(health.takeSnapshot()['flutter-frame-count'], 0);
  });

  test('33ms boundary is not a stutter and counters remain bounded', () {
    final health = PlaybackFrameHealth();
    health.recordDurations(const Duration(milliseconds: 33),
        const Duration(milliseconds: 33));
    final result = health.takeSnapshot();
    expect(result['flutter-slow-build-count'], 0);
    expect(result['flutter-slow-raster-count'], 0);
  });
}
