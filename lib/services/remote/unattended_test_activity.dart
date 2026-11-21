import 'package:flutter/foundation.dart';

/// Device-local progress for a real, currently running native test.
/// GitHub CI is deliberately excluded: a remote build cannot be represented
/// as running on the physical iPad without explicit verified status data.
@immutable
class UnattendedTestSnapshot {
  const UnattendedTestSnapshot({
    this.phase = 'idle',
    this.runId,
    this.channelsDone = 0,
    this.totalChannels = 0,
    this.sourcesDone = 0,
    this.sustainedPlaybackSessions = 0,
    this.requestedSourcesVerified = 0,
    this.failoverPlaybackSessions = 0,
    this.uploadFailures = 0,
    this.cancelRequested = false,
  });

  final String phase;
  final String? runId;
  final int channelsDone;
  final int totalChannels;
  final int sourcesDone;
  final int sustainedPlaybackSessions;
  final int requestedSourcesVerified;
  final int failoverPlaybackSessions;
  final int uploadFailures;
  final bool cancelRequested;

  bool get isRunning => phase == 'running';
  bool get isVisible => isRunning;
  double? get progress => totalChannels > 0
      ? (channelsDone / totalChannels).clamp(0.0, 1.0).toDouble()
      : null;

  static int safeCount(Object? value) =>
      value is int && value >= 0 ? value : 0;

  factory UnattendedTestSnapshot.fromMatrix(
      Map<String, Object?> raw) {
    final phase = raw['phase'];
    final runId = raw['runId'];
    return UnattendedTestSnapshot(
      phase: phase is String ? phase : 'idle',
      runId: runId is String && runId.isNotEmpty ? runId : null,
      channelsDone: safeCount(raw['channelsDone']),
      totalChannels: safeCount(raw['totalChannels']),
      sourcesDone: safeCount(raw['sourcesDone']),
      sustainedPlaybackSessions: safeCount(
          raw['sustainedPlaybackSessions'] ?? raw['verifiedSources']),
      requestedSourcesVerified: safeCount(raw['requestedSourcesVerified']),
      failoverPlaybackSessions: safeCount(raw['failoverPlaybackSessions']),
      uploadFailures: safeCount(raw['uploadFailures']),
      cancelRequested: raw['cancelRequested'] == true,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'phase': phase,
    'runId': runId,
    'visible': isVisible,
    'channelsDone': channelsDone,
    'totalChannels': totalChannels,
    'sourcesDone': sourcesDone,
    'sustainedPlaybackSessions': sustainedPlaybackSessions,
    'requestedSourcesVerified': requestedSourcesVerified,
    'failoverPlaybackSessions': failoverPlaybackSessions,
    'uploadFailures': uploadFailures,
    'cancelRequested': cancelRequested,
  };
}

class UnattendedTestActivity {
  UnattendedTestActivity._();

  static final UnattendedTestActivity instance =
      UnattendedTestActivity._();

  final ValueNotifier<UnattendedTestSnapshot> snapshot =
      ValueNotifier<UnattendedTestSnapshot>(
          const UnattendedTestSnapshot());

  void updateMatrix(Map<String, Object?> status) {
    try {
      snapshot.value = UnattendedTestSnapshot.fromMatrix(status);
    } catch (error) {
      debugPrint('[UnattendedTestActivity] Status update failed: '
          '${error.runtimeType}');
    }
  }
}
