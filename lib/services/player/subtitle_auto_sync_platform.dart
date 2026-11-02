/// Shared Flutter player: Apple Speech on iOS, offline whisper.cpp on
/// Windows; other platforms retain release-name matching and manual timing.
enum SubtitleAutoSyncMode { speechTiming, releaseMatching }

abstract final class SubtitleAutoSyncPlatform {
  /// Maps only known Apple Speech / local decoder error codes to fixed,
  /// privacy-safe categories. Never persist the native exception message,
  /// raw NSError details, media URL, transcript or a platform error code.
  static String failureEventForCode(String? code) => switch (code) {
    'speech_permission' => 'sync_apple_permission_denied',
    'speech_unavailable' || 'speech_service_unavailable' =>
      'sync_apple_service_unavailable',
    'network_required' || 'offline_recognition_failed' =>
      'sync_apple_offline_unavailable',
    'recognition_failed' || 'no_speech' =>
      'sync_apple_recognition_failed',
    'timeout' => 'sync_apple_recognition_timeout',
    'busy' => 'sync_apple_busy',
    'unsupported_media' || 'audio_extract_failed' =>
      'sync_apple_audio_extract_failed',
    'decoder_audio_extract_failed' || 'invalid_audio_excerpt' =>
      'sync_apple_decoder_extract_failed',
    'invalid_args' || 'invalid_range' || 'unsupported_source' =>
      'sync_apple_invalid_excerpt',
    _ => 'sync_apple_unknown_failure',
  };

  static SubtitleAutoSyncMode modeFor({required bool isIOS, bool isWindows = false}) =>
      isIOS || isWindows ? SubtitleAutoSyncMode.speechTiming
          : SubtitleAutoSyncMode.releaseMatching;

  static String tooltipFor({required bool isIOS, bool isWindows = false}) =>
      isIOS ? 'Auto Sync subtitles to spoken English (iOS Apple Speech)'
      : isWindows ? 'Auto Sync subtitles to spoken English (offline Windows Whisper)'
      : 'Find better release-matched subtitles (manual timing available)';
}
