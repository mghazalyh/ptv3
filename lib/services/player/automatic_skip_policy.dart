import '../../models/player/skip_segment_model.dart';

/// Safe, episode-only automatic skipping for verified IntroDB timestamps.
///
/// Skips an intro or credits *only* when its start and destination are
/// explicitly usable. Movies, recaps, previews and unknown segments keep their
/// existing manual skip buttons. No guessed offsets or episode-end heuristics.
class AutomaticSkipPolicy {
  static const Duration countdown = Duration(seconds: 3);

  static bool eligible({
    required bool isSeriesEpisode,
    required MediaSkipSegment segment,
    required Duration mediaDuration,
  }) {
    if (!isSeriesEpisode) return false;
    final kind = segment.type.trim().toLowerCase();
    // Credits must never auto-advance an episode based on untrusted timestamps.
    // A manual skip remains available for valid end-of-episode credits.
    if (kind != 'intro') return false;
    final start = segment.startMs;
    if (start == null || start < 0) return false;
    if (mediaDuration > Duration.zero &&
        start >= mediaDuration.inMilliseconds) return false;
    final target = destination(segment, mediaDuration);
    return target != null && target.inMilliseconds > start;
  }

  /// If credits have no explicit end timestamp, the *known* player duration
  /// is a safe completion point. Without duration, never auto-skip blindly.
  static Duration? destination(
      MediaSkipSegment segment, Duration mediaDuration) {
    final end = segment.endMs;
    if (end != null) {
      if (end <= 0) return null;
      if (mediaDuration > Duration.zero &&
          end > mediaDuration.inMilliseconds + 2000) return null;
      return Duration(milliseconds: end);
    }
    if (segment.type.trim().toLowerCase() == 'credits' &&
        mediaDuration > Duration.zero) {
      return mediaDuration;
    }
    return null;
  }

  static String countdownLabel(MediaSkipSegment segment, int seconds) {
    final label = segment.type.toLowerCase() == 'credits'
        ? 'Credits' : 'Intro';
    return 'Skipping $label in ${seconds.clamp(1, 3)}s';
  }
}
