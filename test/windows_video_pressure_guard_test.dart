import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/windows_video_pressure_guard.dart';

void main() {
  Map<String, Object?> sample(int drop, int raster, [double sync = 0]) => {
    'frame-drop-count': drop,
    'flutter-slow-raster-count': raster,
    'avsync': sync,
    'media-title': 'never-persisted',
  };
  final t = DateTime.utc(2026, 10, 31);
  WindowsVideoPressureAction check(WindowsVideoPressureGuard guard,
      int seconds, int drop, int raster, double sync, {bool buffering = false,
      bool seekable = false}) => guard.evaluate(sample(drop, raster, sync),
      now: t.add(Duration(seconds: seconds)), playing: true,
      buffering: buffering, seekable: seekable);

  test('healthy frames never lower quality', () {
    final guard = WindowsVideoPressureGuard();
    for (var i = 0; i < 20; i++) {
      expect(check(guard, i * 5, i, 0, 0), WindowsVideoPressureAction.none);
    }
    expect(guard.textureTier, 0);
  });

  test('sustained GPU raster/MPV misses scale texture at most twice', () {
    final guard = WindowsVideoPressureGuard();
    expect(check(guard, 0, 10, 10, 0), WindowsVideoPressureAction.none);
    expect(check(guard, 5, 20, 10, 0), WindowsVideoPressureAction.hdTexture);
    expect(check(guard, 10, 30, 10, 0), WindowsVideoPressureAction.none);
    expect(check(guard, 20, 40, 10, 0), WindowsVideoPressureAction.sdTexture);
    for (var s = 30; s < 100; s += 5) {
      expect(check(guard, s, 40 + s, 40, 0), WindowsVideoPressureAction.none);
    }
    expect(guard.textureTier, 2);
  });

  test('resync requires repeated severe A/V error and a full minute cooldown', () {
    final guard = WindowsVideoPressureGuard();
    expect(check(guard, 0, 10, 10, 9, buffering: true, seekable: true),
        WindowsVideoPressureAction.none);
    expect(check(guard, 5, 20, 10, 9, seekable: true),
        WindowsVideoPressureAction.none);
    expect(check(guard, 10, 30, 10, 9, seekable: true),
        WindowsVideoPressureAction.hdTexture);
    expect(check(guard, 23, 40, 10, 9, seekable: true),
        WindowsVideoPressureAction.resync);
    expect(check(guard, 36, 50, 10, 9, seekable: true),
        WindowsVideoPressureAction.none);
    expect(check(guard, 49, 60, 10, 0, seekable: true),
        WindowsVideoPressureAction.sdTexture);
    expect(check(guard, 65, 70, 0, 9, seekable: true),
        WindowsVideoPressureAction.none);
    expect(check(guard, 85, 80, 0, 9, seekable: true),
        WindowsVideoPressureAction.resync);
  });

  test('failed native resize rolls tier back for another safe attempt', () {
    final guard = WindowsVideoPressureGuard();
    check(guard, 0, 10, 10, 0);
    final action = check(guard, 5, 20, 10, 0);
    expect(action, WindowsVideoPressureAction.hdTexture);
    guard.actionFailed(action);
    expect(guard.textureTier, 0);
    expect(check(guard, 20, 30, 10, 0), WindowsVideoPressureAction.none);
    expect(check(guard, 25, 40, 10, 0), WindowsVideoPressureAction.hdTexture);
  });
}
