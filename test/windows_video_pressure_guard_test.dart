import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/windows_video_pressure_guard.dart';

void main() {
  Map<String, Object?> sample(
    int drop,
    int raster, [
    double sync = 0,
    int worstRaster = 0,
  ]) => <String, Object?>{
    'frame-drop-count': drop,
    'flutter-slow-raster-count': raster,
    'flutter-worst-raster-ms': worstRaster,
    'avsync': sync,
    'media-title': 'never-persisted',
  };

  final t = DateTime.utc(2026, 10, 31);
  WindowsVideoPressureAction check(
    WindowsVideoPressureGuard guard,
    int seconds,
    int drop,
    int raster,
    double sync, {
    bool buffering = false,
    bool seekable = false,
    int worstRaster = 0,
    bool playing = true,
  }) => guard.evaluate(
    sample(drop, raster, sync, worstRaster),
    now: t.add(Duration(seconds: seconds)),
    playing: playing,
    buffering: buffering,
    seekable: seekable,
  );

  test('healthy frames never lower quality', () {
    final guard = WindowsVideoPressureGuard();
    for (var i = 0; i < 20; i++) {
      expect(check(guard, i * 5, i, 0, 0, worstRaster: 19),
          WindowsVideoPressureAction.none);
    }
    expect(guard.textureTier, 0);
  });

  test('seven dropped frames and an 81 ms stall lower texture immediately', () {
    final guard = WindowsVideoPressureGuard();
    expect(check(guard, 0, 0, 0, 0), WindowsVideoPressureAction.none);
    expect(check(guard, 5, 7, 1, 0, worstRaster: 81),
        WindowsVideoPressureAction.hdTexture);
    for (var second = 10; second <= 50; second += 5) {
      expect(check(guard, second, 7, 0, 0, worstRaster: 10),
          WindowsVideoPressureAction.none);
    }
    expect(guard.textureTier, 1);
  });

  test('raster stalls trigger downscaling even without native frame drops', () {
    final guard = WindowsVideoPressureGuard();
    expect(check(guard, 0, 0, 0, 0), WindowsVideoPressureAction.none);
    expect(check(guard, 5, 0, 1, 0, worstRaster: 81),
        WindowsVideoPressureAction.hdTexture);
    expect(guard.textureTier, 1);
  });

  test('recurring moderate misses need two samples', () {
    final guard = WindowsVideoPressureGuard();
    expect(check(guard, 0, 0, 0, 0), WindowsVideoPressureAction.none);
    expect(check(guard, 5, 2, 0, 0), WindowsVideoPressureAction.none);
    expect(check(guard, 10, 4, 0, 0), WindowsVideoPressureAction.hdTexture);
  });

  test('recurring severe drops progressively limit texture to 360p', () {
    final guard = WindowsVideoPressureGuard();
    expect(check(guard, 0, 0, 0, 0), WindowsVideoPressureAction.none);
    expect(check(guard, 5, 7, 0, 0), WindowsVideoPressureAction.hdTexture);
    expect(check(guard, 10, 14, 0, 0), WindowsVideoPressureAction.none);
    expect(check(guard, 20, 21, 0, 0), WindowsVideoPressureAction.sdTexture);
    expect(check(guard, 25, 28, 0, 0), WindowsVideoPressureAction.none);
    expect(check(guard, 35, 35, 0, 0), WindowsVideoPressureAction.lowTexture);
    expect(check(guard, 50, 45, 0, 0), WindowsVideoPressureAction.none);
    expect(guard.textureTier, 3);
  });

  test('buffering and pause never resize despite bad metrics', () {
    final guard = WindowsVideoPressureGuard();
    expect(check(guard, 0, 0, 0, 0), WindowsVideoPressureAction.none);
    expect(check(guard, 5, 20, 10, 9, buffering: true),
        WindowsVideoPressureAction.none);
    expect(check(guard, 10, 40, 10, 9, playing: false),
        WindowsVideoPressureAction.none);
    expect(check(guard, 15, 40, 0, 0), WindowsVideoPressureAction.none);
    expect(guard.textureTier, 0);
  });

  test('A/V resync requires repeated severe error and minute cooldown', () {
    final guard = WindowsVideoPressureGuard();
    expect(check(guard, 0, 0, 0, 9, buffering: true, seekable: true),
        WindowsVideoPressureAction.none);
    expect(check(guard, 5, 0, 0, 9, seekable: true),
        WindowsVideoPressureAction.none);
    expect(check(guard, 10, 0, 0, 9, seekable: true),
        WindowsVideoPressureAction.hdTexture);
    expect(check(guard, 15, 0, 0, 9, seekable: true),
        WindowsVideoPressureAction.none);
    expect(check(guard, 23, 0, 0, 9, seekable: true),
        WindowsVideoPressureAction.resync);
    expect(check(guard, 36, 0, 0, 9, seekable: true),
        WindowsVideoPressureAction.none);
    expect(check(guard, 49, 0, 0, 9, seekable: true),
        WindowsVideoPressureAction.sdTexture);
    expect(check(guard, 60, 0, 0, 9, seekable: true),
        WindowsVideoPressureAction.none);
    expect(check(guard, 85, 0, 0, 9, seekable: true),
        WindowsVideoPressureAction.resync);
  });

  test('failed native resize rolls back each tier for another safe attempt', () {
    final guard = WindowsVideoPressureGuard();
    expect(check(guard, 0, 0, 0, 0), WindowsVideoPressureAction.none);
    var action = check(guard, 5, 7, 0, 0);
    expect(action, WindowsVideoPressureAction.hdTexture);
    guard.actionFailed(action);
    expect(guard.textureTier, 0);

    action = check(guard, 20, 14, 0, 0);
    expect(action, WindowsVideoPressureAction.hdTexture);
    action = check(guard, 35, 21, 0, 0);
    expect(action, WindowsVideoPressureAction.sdTexture);
    action = check(guard, 50, 28, 0, 0);
    expect(action, WindowsVideoPressureAction.lowTexture);
    guard.actionFailed(action);
    expect(guard.textureTier, 2);
    expect(check(guard, 65, 35, 0, 0),
        WindowsVideoPressureAction.lowTexture);
  });
}
