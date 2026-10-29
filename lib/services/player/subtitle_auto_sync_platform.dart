/// Cross-platform Auto Sync capabilities for the ONE shared Flutter codebase.
///
/// Apple Speech and the libmpv WAV transcription bridge belong to the iOS
/// runtime only. Windows, Linux and Android retain release-name matching and
/// manual subtitle delay without trying to invoke the iOS method channel.
enum SubtitleAutoSyncMode { speechTiming, releaseMatching }

abstract final class SubtitleAutoSyncPlatform {
  static SubtitleAutoSyncMode modeFor({required bool isIOS}) =>
      isIOS ? SubtitleAutoSyncMode.speechTiming
            : SubtitleAutoSyncMode.releaseMatching;

  static String tooltipFor({required bool isIOS}) => isIOS
      ? 'Auto Sync subtitles to spoken English (iOS)'
      : 'Find better release-matched subtitles (manual timing available)';
}
