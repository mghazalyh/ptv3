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

  // Windows Build #153 removed makeup gain completely and can therefore
  // sound much quieter than normal. The Windows-only bounded makeup and
  // final limiter increase quiet detail without allowing the filtered output
  // above 0.95 full-scale. iOS keeps its independent native preflight chain.
  static const String windowsNightCompressor =
      'lavfi=[acompressor=threshold=0.10:ratio=4:attack=15:'
      'release=260:makeup=1.25:knee=2.5,alimiter=limit=0.95:level=0]';

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
  static String downmixNormalization(bool nightMode) =>
      nightMode ? 'yes' : 'no';

  static Future<void> applyAudio(
    Future<void> Function(String, String) setProperty, bool nightMode, {
    String? verifiedFilterChain,
    bool windows = false,
  }) async {
    await setProperty('audio-normalize-downmix',
        downmixNormalization(nightMode));
    await setProperty('af', nightMode && verifiedFilterChain != null
        ? verifiedFilterChain : audioFilterChain(nightMode, windows: windows));
  }

  /// Native MPV brightness can be accepted but ignored by a video renderer.
  /// On Windows force the pixel-level lavfi eq filter when brightness is
  /// nonzero. Leave all other platforms on their existing MPV path.
  static String windowsBrightnessFilter(double brightness) {
    final level = brightnessValue(brightness);
    if (level == 0) return '';
    final amount = 0.25 * level / maxExtraBrightness;
    final gamma = 1.0 + 0.35 * level / maxExtraBrightness;
    return 'lavfi=[eq=brightness=${amount.toStringAsFixed(3)}:'
        'gamma=${gamma.toStringAsFixed(3)}]';
  }

  static Future<void> applyBrightness(
    Future<void> Function(String, String) setProperty, double brightness, {
    bool windows = false,
  }) async {
    if (!windows) {
      await setProperty('brightness', brightnessValue(brightness).toString());
      return;
    }
    // Avoid doubling MPV equalizer and the video filter in a renderer that
    // happens to support both. Reset filter on slider zero.
    await setProperty('brightness', '0');
    await setProperty('vf', windowsBrightnessFilter(brightness));
  }
}
