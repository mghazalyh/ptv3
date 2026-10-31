import 'package:flutter/scheduler.dart';

/// Low-cost per-frame UI build/raster timing aggregation. This measures Flutter
/// compositor work (which native MPV frame-drop counters cannot observe).
/// Collection is OFF unless the user opts into private platform telemetry.
/// Never stores titles, video frames, device data or media URLs.
class PlaybackFrameHealth {
  static const int stallThresholdMicros = 33000;

  int _frames = 0;
  int _slowBuildFrames = 0;
  int _slowRasterFrames = 0;
  int _maxRasterMicros = 0;

  void observe(List<FrameTiming> timings) {
    for (final timing in timings) {
      recordDurations(timing.buildDuration, timing.rasterDuration);
    }
  }

  void recordDurations(Duration build, Duration raster) {
    // Protect diagnostics memory/counters from pathological scheduler input.
    if (_frames >= 100000) return;
    _frames++;
    final buildMicros = build.inMicroseconds;
    final rasterMicros = raster.inMicroseconds;
    if (buildMicros > stallThresholdMicros) _slowBuildFrames++;
    if (rasterMicros > stallThresholdMicros) _slowRasterFrames++;
    if (rasterMicros > _maxRasterMicros) _maxRasterMicros = rasterMicros;
  }

  Map<String, Object?> takeSnapshot() {
    final result = <String, Object?>{
      'flutter-frame-count': _frames,
      'flutter-slow-build-count': _slowBuildFrames,
      'flutter-slow-raster-count': _slowRasterFrames,
      'flutter-worst-raster-ms': (_maxRasterMicros / 1000).round().clamp(0, 100000),
    };
    reset();
    return result;
  }

  void reset() {
    _frames = 0;
    _slowBuildFrames = 0;
    _slowRasterFrames = 0;
    _maxRasterMicros = 0;
  }
}
