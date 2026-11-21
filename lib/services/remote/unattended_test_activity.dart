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
    this.indicatorEnabled = true,
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
  final bool indicatorEnabled;

  bool get isRunning => phase == 'running';
  bool get isVisible => isRunning && indicatorEnabled;
  UnattendedTestSnapshot withIndicatorEnabled(bool enabled) =>
      UnattendedTestSnapshot(
        phase: phase,
        runId: runId,
        channelsDone: channelsDone,
        totalChannels: totalChannels,
        sourcesDone: sourcesDone,
        sustainedPlaybackSessions: sustainedPlaybackSessions,
        requestedSourcesVerified: requestedSourcesVerified,
        failoverPlaybackSessions: failoverPlaybackSessions,
        uploadFailures: uploadFailures,
        cancelRequested: cancelRequested,
        indicatorEnabled: enabled,
      );

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
    'indicatorEnabled': indicatorEnabled,
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
      final next = UnattendedTestSnapshot.fromMatrix(status);
      final previous = snapshot.value;
      final sameRun = next.isRunning && previous.isRunning &&
          next.runId != null && next.runId == previous.runId;
      snapshot.value = sameRun
          ? next.withIndicatorEnabled(previous.indicatorEnabled)
          : next;
    } catch (error) {
      debugPrint('[UnattendedTestActivity] Status update failed: '
          '${error.runtimeType}');
    }
  }

  /// UI preference only. This never cancels, pauses or changes playback.
  void setIndicatorEnabled(bool enabled) {
    snapshot.value = snapshot.value.withIndicatorEnabled(enabled);
  }

  void beginNativeProbe(String channelId) {
    snapshot.value = UnattendedTestSnapshot(
      phase: 'running',
      runId: channelId,
    );
  }

  void endNativeProbe() {
    if (snapshot.value.isRunning && snapshot.value.totalChannels == 0) {
      snapshot.value = const UnattendedTestSnapshot();
    }
  }
}
