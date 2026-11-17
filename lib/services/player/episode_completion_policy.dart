/// A native EOF is not proof that the requested TV episode finished.
///
/// Auto-advance is allowed only when episode/show runtime metadata confirms
/// that the source and playback position are close to the genuine ending.
class EpisodeCompletionAssessment {
  final bool allowAutoplay;
  final String reason;
  final Duration? expectedRuntime;

  const EpisodeCompletionAssessment({
    required this.allowAutoplay,
    required this.reason,
    required this.expectedRuntime,
  });
}

abstract final class EpisodeCompletionPolicy {
  static const double minimumExpectedFraction = 0.90;
  static const Duration nearNativeEnd = Duration(seconds: 90);

  static Duration? parseRuntime(String? value) {
    if (value == null) return null;
    final input = value.trim().toLowerCase();
    if (input.isEmpty || input.contains(RegExp(r'\d\s*[-–]\s*\d'))) {
      return null;
    }
    int? minutes;
    final numeric = RegExp(r'^(\d{1,3})$').firstMatch(input);
    if (numeric != null) {
      minutes = int.tryParse(numeric.group(1) ?? '');
    } else {
      final clock = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2})$')
          .firstMatch(input);
      if (clock != null) {
        final h = int.tryParse(clock.group(1) ?? '');
        final m = int.tryParse(clock.group(2) ?? '');
        final s = int.tryParse(clock.group(3) ?? '');
        if (h != null && m != null && s != null && m < 60 && s < 60) {
          minutes = h * 60 + m + (s >= 30 ? 1 : 0);
        }
      } else {
        final iso = RegExp(r'^pt(?:(\d{1,2})h)?(?:(\d{1,3})m)?$')
            .firstMatch(input);
        final words = RegExp(
          r'^(?:(\d{1,2})\s*(?:hours?|hrs?|h)\s*)?'
          r'(?:(\d{1,3})\s*(?:minutes?|mins?|min|m)\s*)?$',
        ).firstMatch(input);
        final match = iso ?? words;
        if (match != null) {
          final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
          final mins = int.tryParse(match.group(2) ?? '0') ?? 0;
          minutes = hours * 60 + mins;
        }
      }
    }
    if (minutes == null || minutes < 8 || minutes > 480) return null;
    return Duration(minutes: minutes);
  }

  static Duration? expectedRuntime({
    String? episodeRuntime,
    String? seriesRuntime,
  }) => parseRuntime(episodeRuntime) ?? parseRuntime(seriesRuntime);

  static Duration effectiveProgressDuration({
    required Duration nativeDuration,
    String? episodeRuntime,
    String? seriesRuntime,
  }) {
    final expected = expectedRuntime(
        episodeRuntime: episodeRuntime, seriesRuntime: seriesRuntime);
    if (expected == null || nativeDuration >= expected) return nativeDuration;
    return expected;
  }

  static EpisodeCompletionAssessment assess({
    required Duration position,
    required Duration nativeDuration,
    String? episodeRuntime,
    String? seriesRuntime,
    bool buffering = false,
    bool recentSeek = false,
    Duration? recentSeekFrom,
  }) {
    final expected = expectedRuntime(
        episodeRuntime: episodeRuntime, seriesRuntime: seriesRuntime);
    EpisodeCompletionAssessment block(String reason) =>
        EpisodeCompletionAssessment(
            allowAutoplay: false, reason: reason, expectedRuntime: expected);

    if (position <= Duration.zero || nativeDuration <= Duration.zero) {
      return block('invalid_playback_timing');
    }
    if (buffering) return block('buffering_at_native_completion');
    if (expected == null) return block('trusted_runtime_unavailable');

    final minimum = expected.inMilliseconds * minimumExpectedFraction;
    if (nativeDuration.inMilliseconds < minimum) {
      return block('source_shorter_than_expected_episode');
    }
    if (position.inMilliseconds < minimum) {
      return block('playback_before_expected_episode_end');
    }
    if (position + nearNativeEnd < nativeDuration) {
      return block('native_completion_before_source_end');
    }
    if (recentSeek && recentSeekFrom != null &&
        recentSeekFrom.inMilliseconds < minimum) {
      return block('recent_seek_from_early_position');
    }
    return EpisodeCompletionAssessment(
        allowAutoplay: true,
        reason: 'trusted_episode_end_verified',
        expectedRuntime: expected);
  }
}
