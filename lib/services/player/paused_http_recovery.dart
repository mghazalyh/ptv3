/// Recovery policy for iPadOS on-demand HTTP VOD connections.
/// FFmpeg can hold a stale TCP socket during a long pause.
abstract final class PausedHttpRecovery {
  static const longPause = Duration(seconds: 90);
  static const resumeErrorWindow = Duration(seconds: 45);
  static const maxAttempts = 2;

  static bool needsReopen(bool isHttpVod, DateTime? pausedAt, DateTime now) =>
      isHttpVod && pausedAt != null && !now.isBefore(pausedAt) &&
      now.difference(pausedAt) >= longPause;

  static bool isReadFailure(String text) {
    final error = text.toLowerCase();
    return error.contains('ffurl_read') ||
        error.contains('connection reset') ||
        error.contains('broken pipe') ||
        error.contains('connection timed out') ||
        error.contains('connection closed') ||
        error.contains('network is unreachable') ||
        error.contains('connection aborted');
  }

  static bool canRetryError(String message, bool isHttpVod, DateTime? resumedAt,
      DateTime now, int attempts) =>
      isHttpVod && resumedAt != null && !now.isBefore(resumedAt) &&
      now.difference(resumedAt) <= resumeErrorWindow &&
      attempts < maxAttempts && isReadFailure(message);

  static Duration safePosition(Duration current, Duration total) {
    if (current <= Duration.zero) return Duration.zero;
    if (total <= Duration.zero) return current;
    final lastSafe = total - const Duration(seconds: 3);
    if (lastSafe <= Duration.zero) return Duration.zero;
    return current < lastSafe ? current : lastSafe;
  }
}
