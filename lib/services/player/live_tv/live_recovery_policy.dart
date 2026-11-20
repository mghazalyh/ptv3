/// Pure, clock-injected TV-only recovery policy. No dependency on Flutter,
/// media_kit, the shared VOD player, or platform services.
enum LiveHealthEvent {
  none,
  recovered,
  bufferingStall,
  feedStarvation,
  timelineDiscontinuity,
}

class LiveRecoveryPolicy {
  LiveRecoveryPolicy({
    this.startupGrace = const Duration(seconds: 14),
    this.stallThreshold = const Duration(seconds: 13),
    this.feedThreshold = const Duration(seconds: 9),
  });

  final Duration startupGrace;
  final Duration stallThreshold;
  final Duration feedThreshold;

  DateTime? _startedAt;
  DateTime? _lastMotionAt;
  DateTime? _lastFeedAt;
  DateTime? _lastAttemptAt;
  DateTime? _healthySince;
  Duration _lastPosition = Duration.zero;
  Duration _lastBuffered = Duration.zero;
  Duration _lastDuration = Duration.zero;
  bool _awaitingRecovery = false;
  bool _reopening = false;
  bool _wasPaused = false;
  int attempts = 0;

  Duration get retryCooldown {
    if (attempts <= 0) return Duration.zero;
    final seconds = 4 * (1 << ((attempts - 1).clamp(0, 4).toInt()));
    return Duration(seconds: seconds.clamp(4, 60).toInt());
  }

  int get recommendedCacheSeconds =>
      attempts >= 3 ? 30 : attempts > 0 ? 20 : 15;

  bool get awaitingRecovery => _awaitingRecovery;

  void reset(DateTime at, {
    Duration position = Duration.zero,
    Duration buffered = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    _startedAt = at;
    _lastMotionAt = at;
    _lastFeedAt = at;
    _lastPosition = position;
    _lastBuffered = buffered;
    _lastDuration = duration;
    _awaitingRecovery = false;
    _reopening = false;
    _wasPaused = false;
    _healthySince = null;
    attempts = 0;
    _lastAttemptAt = null;
  }

  void beginReopen(DateTime at) {
    attempts++;
    _lastAttemptAt = at;
    _reopening = true;
    _awaitingRecovery = true;
    _healthySince = null;
  }

  void reopened(DateTime at, {
    Duration position = Duration.zero,
    Duration buffered = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    _startedAt = at;
    _lastMotionAt = at;
    _lastFeedAt = at;
    _lastPosition = position;
    _lastBuffered = buffered;
    _lastDuration = duration;
    _reopening = false;
  }

  void reopenFailed(DateTime at) {
    _lastAttemptAt = at;
    _startedAt = at;
    _reopening = false;
  }

  bool canAttempt(DateTime at) =>
      !_reopening &&
      (_lastAttemptAt == null ||
          !at.isBefore(_lastAttemptAt!.add(retryCooldown)));

  bool get isFeedStale => _lastFeedAt != null && _startedAt != null;

  Duration feedAge(DateTime at) =>
      _lastFeedAt == null ? Duration.zero : at.difference(_lastFeedAt!);

  Duration motionAge(DateTime at) =>
      _lastMotionAt == null ? Duration.zero : at.difference(_lastMotionAt!);

  LiveHealthEvent observe({
    required DateTime at,
    required Duration position,
    required Duration? buffered,
    required Duration duration,
    required bool playing,
    required bool buffering,
  }) {
    final end = buffered ?? Duration.zero;
    if (_startedAt == null) {
      reset(at, position: position, buffered: end, duration: duration);
      return LiveHealthEvent.none;
    }
    if (!playing && !buffering) {
      // An intentional pause must never trigger a live reconnect.
      _wasPaused = true;
      _lastMotionAt = at;
      _lastFeedAt = at;
      _startedAt = at;
      _lastPosition = position;
      _lastBuffered = end;
      _lastDuration = duration;
      return LiveHealthEvent.none;
    }
    if (_wasPaused) {
      _wasPaused = false;
      _startedAt = at;
      _lastMotionAt = at;
      _lastFeedAt = at;
    }

    final moved = position > _lastPosition +
        const Duration(milliseconds: 400);
    final fed = end > _lastBuffered +
            const Duration(milliseconds: 400) ||
        duration > _lastDuration + const Duration(milliseconds: 400);
    final timelineJump = duration + const Duration(seconds: 10) <
            _lastDuration ||
        position + const Duration(seconds: 10) < _lastPosition;

    if (moved) {
      _lastMotionAt = at;
      _healthySince ??= at;
    } else if (!buffering) {
      _healthySince = null;
    }
    if (fed) _lastFeedAt = at;
    _lastPosition = position;
    _lastBuffered = end;
    _lastDuration = duration;

    if (timelineJump) {
      _startedAt = at;
      _lastMotionAt = at;
      _lastFeedAt = at;
      return LiveHealthEvent.timelineDiscontinuity;
    }

    if (_awaitingRecovery && moved && !_reopening) {
      _awaitingRecovery = false;
      _healthySince = at;
      return LiveHealthEvent.recovered;
    }

    // A full minute of successful viewing resets exponential backoff.
    if (!_awaitingRecovery && attempts > 0 && _healthySince != null &&
        at.difference(_healthySince!) >= const Duration(minutes: 1)) {
      attempts = 0;
      _lastAttemptAt = null;
    }

    if (_reopening || !canAttempt(at) ||
        at.difference(_startedAt!) < startupGrace) {
      return LiveHealthEvent.none;
    }

    final ahead = end - position;
    if (buffering && motionAge(at) >= stallThreshold) {
      return LiveHealthEvent.bufferingStall;
    }
    // Recover while some video remains, instead of waiting for a zero cache.
    if (playing && !buffering && end > Duration.zero &&
        end >= position && ahead <= const Duration(seconds: 6) &&
        feedAge(at) >= feedThreshold) {
      return LiveHealthEvent.feedStarvation;
    }
    return LiveHealthEvent.none;
  }
}
