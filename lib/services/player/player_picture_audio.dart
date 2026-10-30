/// Native mpv picture/audio effects used by the shared iOS + Windows player.
///
/// The compressor operates on decoded playback audio, not the OS output or the
/// microphone. Keep the original scaletempo2 filter so speed changes continue
/// to work. The settings never modify system-wide audio or display hardware.
abstract final class PlayerPictureAudio {
  static const String normalAudioFilter = 'scaletempo2=max-speed=8';

  // FFmpeg acompressor threshold is LINEAR amplitude (0.10 ~ -20 dB).
  // No post-compressor makeup amplification: leave headroom for transient peaks
  // and for subsequent multichannel-to-stereo remixing.
  static const String nightCompressor =
      'lavfi=[acompressor=threshold=0.10:ratio=3:attack=20:'
      'release=300:makeup=1.0:knee=2.5]';

  // Physical Windows Build #154 E-AC3 feedback: dialogue becomes quieter
  // even with acompressor + limiter active. Use gentler compression, lift
  // dialogue with +6dB makeup, and retain a hard final limiter.
  // This remains independent from the iOS native preflight chain.
  static const String windowsNightCompressor =
      'lavfi=[acompressor=threshold=0.15:ratio=2.5:attack=15:'
      'release=220:makeup=2.0:knee=2.5,alimiter=limit=0.95:level=0]';

  static String audioFilterChain(bool nightMode, {bool windows = false}) =>
      !nightMode ? normalAudioFilter :
      '$normalAudioFilter,${windows ? windowsNightCompressor : nightCompressor}';

  /// libmpv can accept an `af` option and only fail when audio starts. The
  /// media_kit error stream is therefore the source of truth for runtime
  /// filter graph initialization failures.
  static bool isNightModeFilterError(String error) {
    final value = error.toLowerCase();
    return value.contains('audio filter initialized failed') ||
        value.contains('audio filter initialization failed') ||
        value.contains('error initializing audio filters') ||
        value.contains('failed to initialize audio filter') ||
        value.contains('cannot initialize audio filter');
  }

  /// Restore the original speed filter. If even this is unavailable, remove
  /// all audio filters rather than allowing playback to remain unusable.
  static Future<void> restoreNormalAudio(
    Future<void> Function(String, String) setProperty,
  ) async {
    // Return to default downmix behavior when a filter fails or Night Mode
    // is turned OFF. A missing optional MPV property must not block recovery.
    try {
      await setProperty('audio-normalize-downmix', 'no');
    } catch (_) {}
    try {
      await setProperty('af', normalAudioFilter);
    } catch (_) {
      await setProperty('af', '');
    }
  }

  /// MPV brightness property is in -100..100. Only expose positive values.
  /// This adjusts video pixels, NOT the physical display backlight.
  static const int maxExtraBrightness = 80;
  static int brightnessValue(double value) {
    if (!value.isFinite) return 0;
    return value.round().clamp(0, maxExtraBrightness).toInt();
  }

  /// MPV's native surround-to-stereo remix can otherwise exceed full scale.
  /// Keep the normal listening path unchanged when Night Mode is disabled.
  static String downmixNormalization(bool nightMode, {bool windows = false}) =>
      nightMode && !windows ? 'yes' : 'no';

  static Future<void> applyAudio(
    Future<void> Function(String, String) setProperty, bool nightMode, {
    String? verifiedFilterChain,
    bool windows = false,
  }) async {
    await setProperty('audio-normalize-downmix',
        downmixNormalization(nightMode, windows: windows));
    await setProperty('af', nightMode && verifiedFilterChain != null
        ? verifiedFilterChain : audioFilterChain(nightMode, windows: windows));
  }

  /// Windows applies brightness on the Flutter video texture using a GPU
  /// color matrix. Unlike FFmpeg eq in MPV's vf chain, this preserves the
  /// native decode path and avoids a CPU-side per-frame filter under GPU load.
  /// The matrix offset uses 0..255 channels and leaves alpha unchanged.
  static List<double> windowsBrightnessColorMatrix(double brightness) {
    final value = brightnessValue(brightness) / maxExtraBrightness;
    final gain = 1.0 + 0.08 * value;
    final lift = 42.0 * value;
    return <double>[
      gain, 0, 0, 0, lift,
      0, gain, 0, 0, lift,
      0, 0, gain, 0, lift,
      0, 0, 0, 1, 0,
    ];
  }

  /// Compatibility helper: never add a CPU video filter on Windows.
  static String windowsBrightnessFilter(double brightness) => '';

  static Future<void> applyBrightness(
    Future<void> Function(String, String) setProperty, double brightness, {
    bool windows = false,
  }) async {
    if (!windows) {
      await setProperty('brightness', brightnessValue(brightness).toString());
      return;
    }
    // Brightness is composited on the Flutter video surface, not in MPV.
    // Clear older v154-v159 FFmpeg video filters when upgrading while a
    // source is already open, and keep normal MPV brightness neutral.
    await setProperty('brightness', '0');
    await setProperty('vf', '');
  }
}
