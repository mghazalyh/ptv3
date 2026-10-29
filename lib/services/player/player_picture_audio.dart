/// Native mpv picture/audio effects used by the shared iOS + Windows player.
///
/// The compressor operates on decoded playback audio, not the OS output or the
/// microphone. Keep the original scaletempo2 filter so speed changes continue
/// to work. The settings never modify system-wide audio or display hardware.
abstract final class PlayerPictureAudio {
  static const String normalAudioFilter = 'scaletempo2=max-speed=8';

  // FFmpeg acompressor threshold is LINEAR amplitude (0.10 ~ -20 dB).
  // Modest makeup gives quieter dialogue a lift without recreating loud peaks.
  static const String nightCompressor =
      'lavfi=[acompressor=threshold=0.10:ratio=3:attack=20:'
      'release=300:makeup=1.4:knee=2.5]';

  static String audioFilterChain(bool nightMode) =>
      nightMode ? '$normalAudioFilter,$nightCompressor' : normalAudioFilter;

  /// MPV brightness property is in -100..100. Only expose positive values.
  /// This adjusts video pixels, NOT the physical display backlight.
  static const int maxExtraBrightness = 80;
  static int brightnessValue(double value) {
    if (!value.isFinite) return 0;
    return value.round().clamp(0, maxExtraBrightness);
  }

  static Future<void> applyAudio(
    Future<void> Function(String, String) setProperty, bool nightMode,
  ) => setProperty('af', audioFilterChain(nightMode));

  static Future<void> applyBrightness(
    Future<void> Function(String, String) setProperty, double brightness,
  ) => setProperty('brightness', brightnessValue(brightness).toString());
}
