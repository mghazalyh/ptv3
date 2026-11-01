/// Skip background subtitle alignment unless playback is active and
/// readable external subtitle cues are already loaded.
abstract final class SubtitleAutoSyncPolicy {
  static const interval = Duration(minutes: 5);
  // Poll cheaply so a skipped five-minute deadline is retried when playback resumes.
  static const pollInterval = Duration(seconds: 30);
  static const failedRetryInterval = Duration(minutes: 2);

  static String? skipReason({
    required bool isPlaying, required bool isLoading, required bool isBusy,
    required bool hasExternalCues, required bool hasAudioSource,
    required bool isSupported,
  }) {
    if (!isSupported) return 'sync_timer_unsupported';
    if (!isPlaying) return 'sync_timer_paused';
    if (isLoading) return 'sync_timer_loading';
    if (isBusy) return 'sync_timer_busy';
    if (!hasExternalCues) return 'sync_timer_no_cues';
    if (!hasAudioSource) return 'sync_timer_no_source';
    return null;
  }


  static bool shouldRun({
    required bool isPlaying, required bool isLoading, required bool isBusy,
    required bool hasExternalCues, required bool hasAudioSource,
    required bool isSupported,
  }) => skipReason(
    isPlaying: isPlaying, isLoading: isLoading, isBusy: isBusy,
    hasExternalCues: hasExternalCues, hasAudioSource: hasAudioSource,
    isSupported: isSupported,
  ) == null;
}
