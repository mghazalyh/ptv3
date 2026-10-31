/// Local, nonpersistent Windows texture-pressure policy. Never sends metrics.
/// Decrease texture workload only when measured presentation pressure warrants
/// it; never disable hardware decoding or alter another process.
enum WindowsVideoPressureAction {
  none,
  hdTexture,
  sdTexture,
  lowTexture,
  resync,
}

class WindowsVideoPressureGuard {
  static const minActionInterval = Duration(seconds: 12);
  static const minResyncInterval = Duration(seconds: 60);
  int? _lastDrops;
  int _pressureSamples = 0;
  int _syncSamples = 0;
  int _tier = 0;
  DateTime? _lastAction;
  DateTime? _lastResync;

  /// 0 = native, 1 = 720p, 2 = 540p, 3 = 360p.
  int get textureTier => _tier;

  WindowsVideoPressureAction evaluate(Map<String, Object?> data, {
    required DateTime now,
    required bool playing,
    required bool buffering,
    required bool seekable,
  }) {
    final count = int.tryParse(data['frame-drop-count']?.toString() ?? '');
    var recentDrops = 0;
    if (count != null && count >= 0 && count <= 1000000000) {
      if (_lastDrops != null && count >= _lastDrops!) {
        recentDrops = count - _lastDrops!;
      }
      _lastDrops = count;
    }

    if (!playing || buffering) {
      _pressureSamples = 0;
      _syncSamples = 0;
      return WindowsVideoPressureAction.none;
    }

    final raster = int.tryParse(
          data['flutter-slow-raster-count']?.toString() ?? '',
        ) ??
        0;
    final worstRaster = int.tryParse(
          data['flutter-worst-raster-ms']?.toString() ?? '',
        ) ??
        0;
    final number = double.tryParse(data['avsync']?.toString() ?? '');
    final sync = number != null && number.isFinite && number.abs() <= 3600
        ? number.abs()
        : 0.0;

    // A short burst can be visible to the owner, but used to be discarded
    // before two consecutive five-second samples crossed the old threshold.
    // Large bursts trigger one bounded reduction; milder pressure must recur.
    final severe = recentDrops >= 6 ||
        (raster >= 4 && raster <= 100000) ||
        (worstRaster >= 75 && worstRaster <= 100000);
    final pressured = severe ||
        recentDrops >= 2 ||
        (raster >= 2 && raster <= 100000) ||
        (worstRaster >= 50 && worstRaster <= 100000) ||
        sync >= 1.5;
    if (severe) {
      _pressureSamples = 2;
    } else if (pressured) {
      if (_pressureSamples < 100) _pressureSamples++;
    } else {
      _pressureSamples = 0;
    }

    if (sync >= 3) {
      if (_syncSamples < 100) _syncSamples++;
    } else {
      _syncSamples = 0;
    }

    if (_lastAction != null &&
        now.difference(_lastAction!) < minActionInterval) {
      return WindowsVideoPressureAction.none;
    }

    if (_pressureSamples >= 2 && _tier == 0) {
      _tier = 1;
      _pressureSamples = 0;
      _lastAction = now;
      return WindowsVideoPressureAction.hdTexture;
    }

    if (seekable &&
        _syncSamples >= 2 &&
        (_lastResync == null ||
            now.difference(_lastResync!) >= minResyncInterval)) {
      _lastResync = now;
      _lastAction = now;
      _syncSamples = 0;
      _pressureSamples = 0;
      return WindowsVideoPressureAction.resync;
    }

    if (_pressureSamples >= 2 && _tier == 1) {
      _tier = 2;
      _pressureSamples = 0;
      _lastAction = now;
      return WindowsVideoPressureAction.sdTexture;
    }

    if (_pressureSamples >= 2 && _tier == 2) {
      _tier = 3;
      _pressureSamples = 0;
      _lastAction = now;
      return WindowsVideoPressureAction.lowTexture;
    }

    return WindowsVideoPressureAction.none;
  }

  void actionFailed(WindowsVideoPressureAction action) {
    switch (action) {
      case WindowsVideoPressureAction.hdTexture:
        if (_tier == 1) _tier = 0;
        break;
      case WindowsVideoPressureAction.sdTexture:
        if (_tier == 2) _tier = 1;
        break;
      case WindowsVideoPressureAction.lowTexture:
        if (_tier == 3) _tier = 2;
        break;
      case WindowsVideoPressureAction.resync:
        _lastResync = null;
        _syncSamples = 0;
        break;
      case WindowsVideoPressureAction.none:
        break;
    }
  }
}
