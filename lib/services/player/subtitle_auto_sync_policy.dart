/// Skip background subtitle alignment unless playback is active and
/// readable external subtitle cues are already loaded.
abstract final class SubtitleAutoSyncPolicy {
  static const interval = Duration(minutes: 5);

  static bool shouldRun({
    required bool isPlaying, required bool isLoading, required bool isBusy,
    required bool hasExternalCues, required bool hasAudioSource,
    required bool isSupported,
  }) => isSupported && isPlaying && !isLoading && !isBusy &&
      hasExternalCues && hasAudioSource;
}
