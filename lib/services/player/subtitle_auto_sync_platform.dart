/// Shared Flutter player: Apple Speech on iOS, offline whisper.cpp on
/// Windows; other platforms retain release-name matching and manual timing.
enum SubtitleAutoSyncMode { speechTiming, releaseMatching }

abstract final class SubtitleAutoSyncPlatform {
  static SubtitleAutoSyncMode modeFor({required bool isIOS, bool isWindows = false}) =>
      isIOS || isWindows ? SubtitleAutoSyncMode.speechTiming
          : SubtitleAutoSyncMode.releaseMatching;

  static String tooltipFor({required bool isIOS, bool isWindows = false}) =>
      isIOS ? 'Auto Sync subtitles to spoken English (iOS Apple Speech)'
      : isWindows ? 'Auto Sync subtitles to spoken English (offline Windows Whisper)'
      : 'Find better release-matched subtitles (manual timing available)';
}
