/// A single, independently matched dialogue anchor. Times are in seconds
/// on the original subtitle timeline and media's spoken-audio timeline.
class SubtitleTimingAnchor {
  final double cueSeconds;
  final double spokenSeconds;
  final int supportingCues;
  final double spreadSeconds;

  const SubtitleTimingAnchor({
    required this.cueSeconds,
    required this.spokenSeconds,
    required this.supportingCues,
    required this.spreadSeconds,
  });

  bool get isReliable =>
      cueSeconds.isFinite &&
      spokenSeconds.isFinite &&
      cueSeconds >= 0 &&
      spokenSeconds >= 0 &&
      supportingCues >= 2 &&
      spreadSeconds.isFinite &&
      spreadSeconds >= 0 &&
      spreadSeconds <= 1.0;
}

/// MPV applies sub-speed to original subtitle event timestamps, then sub-delay.
/// Derive both only from two distant, independently verified dialogue samples.
/// Never infer a subtitle playback rate from a single successful Auto Sync.
class SubtitleRateCorrection {
  final double speed;
  final double delaySeconds;

  const SubtitleRateCorrection({
    required this.speed,
    required this.delaySeconds,
  });

  static const minSeparationSeconds = 180.0;
  static const minDriftSeconds = 1.5;
  static const maxRateError = 0.055;
  static const maxDelaySeconds = 150.0;

  static SubtitleRateCorrection? estimate(
      SubtitleTimingAnchor earlier, SubtitleTimingAnchor later) {
    if (!earlier.isReliable || !later.isReliable) return null;
    final cueDistance = later.cueSeconds - earlier.cueSeconds;
    final spokenDistance = later.spokenSeconds - earlier.spokenSeconds;
    if (!cueDistance.isFinite || !spokenDistance.isFinite ||
        cueDistance < minSeparationSeconds || spokenDistance <= 0) {
      return null;
    }

    final drift = spokenDistance - cueDistance;
    if (drift.abs() < minDriftSeconds) return null;

    final speed = spokenDistance / cueDistance;
    final delaySeconds = earlier.spokenSeconds - speed * earlier.cueSeconds;
    if (!speed.isFinite || !delaySeconds.isFinite ||
        (speed - 1.0).abs() > maxRateError ||
        delaySeconds.abs() > maxDelaySeconds) {
      return null;
    }
    return SubtitleRateCorrection(speed: speed, delaySeconds: delaySeconds);
  }
}
