import '../../../models/stream/stream_model.dart';

/// Requires repeated native-video progress before normal Live TV playback
/// can teach the in-memory exact-source preference cache.
///
/// The recovery policy must already have accepted decoded playback. A single
/// frame, audio-only clock, HTTP response, seek jump, or transient reopen is
/// never enough. This object does not retain or upload playable URLs.
class LiveVerifiedSourceLearningGate {
  LiveVerifiedSourceLearningGate({
    this.minimumAdvanceMs = 5000,
    this.minimumMotionSamples = 3,
  });

  final int minimumAdvanceMs;
  final int minimumMotionSamples;

  String? _identity;
  int? _firstPositionMs;
  int? _previousPositionMs;
  int _movingSamples = 0;
  bool _published = false;

  void reset() {
    _identity = null;
    _firstPositionMs = null;
    _previousPositionMs = null;
    _movingSamples = 0;
    _published = false;
  }

  bool observe({
    required StreamSource source,
    required bool policyAccepted,
    required bool videoReady,
    required int? videoWidth,
    required int? videoHeight,
    required int? trackCount,
    required bool playing,
    required bool buffering,
    required Duration position,
  }) {
    final url = source.url?.trim();
    final addon = source.addonName.trim();
    if (url == null || url.isEmpty || addon.isEmpty ||
        !policyAccepted || !videoReady ||
        (videoWidth ?? 0) <= 0 || (videoHeight ?? 0) <= 0 ||
        (trackCount ?? 0) <= 0 ||
        !playing || buffering) {
      reset();
      return false;
    }
    // The exact addon + URL matters: a shared hostname is not identity.
    final identity = '${addon.length}:$addon$url';
    if (_identity != identity) {
      reset();
      _identity = identity;
    }
    if (_published) return false;
    final current = position.inMilliseconds;
    if (_firstPositionMs == null) {
      _firstPositionMs = current;
      _previousPositionMs = current;
      return false;
    }
    final previous = _previousPositionMs ?? current;
    if (current <= previous + 400) {
      // Do not count motion before a stall or a discontinuity as sustained.
      _firstPositionMs = current;
      _previousPositionMs = current;
      _movingSamples = 0;
      return false;
    }
    _previousPositionMs = current;
    _movingSamples++;
    if (_movingSamples < minimumMotionSamples ||
        current - _firstPositionMs! < minimumAdvanceMs) return false;
    _published = true;
    return true;
  }
}
