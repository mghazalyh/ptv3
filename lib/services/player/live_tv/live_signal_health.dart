/// Conservative estimate of real media delivery, not Wi-Fi RSSI.
/// A successful Media.open is never evidence of usable video.
enum LiveSignalLevel { connecting, strong, unstable, critical, reconnecting, unavailable }

class LiveSignalSnapshot {
  const LiveSignalSnapshot({
    required this.level, required this.bufferSeconds,
    required this.attempts, this.hasPlayed = false,
  });
  final LiveSignalLevel level;
  final double? bufferSeconds;
  final int attempts;
  final bool hasPlayed;

  bool get isConnecting => level == LiveSignalLevel.connecting ||
      level == LiveSignalLevel.reconnecting ||
      level == LiveSignalLevel.unavailable;

  bool get isPlayable => hasPlayed &&
      (level == LiveSignalLevel.strong ||
       level == LiveSignalLevel.unstable ||
       level == LiveSignalLevel.critical);

  static LiveSignalSnapshot evaluate({
    required bool hasPlayed,
    required bool reconnecting,
    required bool buffering,
    required bool playing,
    required int attempts,
    required Duration position,
    required Duration bufferEnd,
    required Duration feedAge,
  }) {
    final diff = bufferEnd - position;
    final seconds = bufferEnd > Duration.zero &&
            diff >= Duration.zero &&
            diff <= const Duration(minutes: 10)
        ? diff.inMilliseconds / 1000
        : null;
    if (reconnecting) {
      return LiveSignalSnapshot(
        level: attempts >= 5 ? LiveSignalLevel.unavailable
            : LiveSignalLevel.reconnecting,
        bufferSeconds: seconds, attempts: attempts, hasPlayed: hasPlayed,
      );
    }
    if (!hasPlayed) {
      return LiveSignalSnapshot(
        level: attempts >= 5 ? LiveSignalLevel.unavailable
            : LiveSignalLevel.connecting,
        bufferSeconds: seconds, attempts: attempts, hasPlayed: false,
      );
    }
    if (!playing && !buffering) {
      return LiveSignalSnapshot(
        level: LiveSignalLevel.unstable, bufferSeconds: seconds,
        attempts: attempts, hasPlayed: true,
      );
    }
    if (buffering || (seconds != null && seconds < 5) ||
        (feedAge > const Duration(seconds: 10) &&
         seconds != null && seconds < 8)) {
      return LiveSignalSnapshot(
        level: LiveSignalLevel.critical, bufferSeconds: seconds,
        attempts: attempts, hasPlayed: true,
      );
    }
    if ((seconds != null && seconds < 12) ||
        feedAge > const Duration(seconds: 8)) {
      return LiveSignalSnapshot(
        level: LiveSignalLevel.unstable, bufferSeconds: seconds,
        attempts: attempts, hasPlayed: true,
      );
    }
    return LiveSignalSnapshot(
      level: LiveSignalLevel.strong, bufferSeconds: seconds,
      attempts: attempts, hasPlayed: true,
    );
  }
}

/// Native open completion and a decoder-ready video stream are not identical.
abstract final class LivePlaybackAcceptance {
  static bool confirmed({
    required bool buffering, required bool playing,
    required Duration before, required Duration after,
  }) => playing && !buffering &&
      after >= before + const Duration(milliseconds: 450);

  static bool shouldAttemptBackup({
    required int attempts, required bool hasConfirmedPlayback,
  }) => attempts >= (hasConfirmedPlayback ? 2 : 1);
}
