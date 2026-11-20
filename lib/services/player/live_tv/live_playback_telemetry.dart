import 'dart:async';

import '../../../models/stream/stream_model.dart';
import '../ios_audio_telemetry.dart';
import '../player_debug_telemetry.dart';
import '../player_diagnostic_codes.dart';
import '../windows_playback_telemetry.dart';
import 'live_stream_detector.dart';

/// Live-only owner-enabled diagnostics. The channel/programme identity,
/// provider and source labels are retained, not raw tokens or stream URLs.
abstract final class LivePlaybackTelemetry {
  static void event(
    String code, {
    required StreamSource source,
    required String channelId,
    required String title,
    String? programmeTitle,
    String? programmeKind,
  }) {
    if (!PlayerDiagnosticCodes.events.contains(code)) return;
    PlayerDebugTelemetry.record(code,
        failure: code == 'live_reconnect_failed' ||
            code == 'live_video_unavailable' ||
            code == 'live_source_exhausted');
    WindowsPlaybackTelemetry.instance.captureCode(code);
    IosAudioTelemetry.instance.captureCode(code);
    // A Live TV session must never inherit the preceding film's title.
    IosAudioTelemetry.instance.ensurePlaybackContext(
      title: title,
      mediaId: channelId,
      type: 'tv',
      episodeTitle: programmeTitle,
    );
    WindowsPlaybackTelemetry.instance.captureSourceSelection(
      action: code,
      source: source,
      title: title,
      mediaId: channelId,
      type: 'tv',
      episodeTitle: programmeTitle,
    );
    IosAudioTelemetry.instance.captureSourceSelection(
      action: code,
      source: source,
      title: title,
      mediaId: channelId,
      episodeTitle: programmeTitle,
    );
  }

  /// A bounded iPad diagnostic timeline. 10-second samples plus state-change
  /// events are enough to reconstruct startup failures, stalls and failovers.
  static void observation({
    required String event,
    required StreamSource source,
    required String channelId,
    required String title,
    String? programmeTitle,
    String? programmeKind,
    String? signalQuality,
    String? failureClass,
    required int attempts,
    required int candidateCount,
    required bool buffering,
    required bool playing,
    required bool videoReady,
    required bool reconnecting,
    int? startupElapsedMs,
    int? firstFrameElapsedMs,
    int? videoWidth,
    int? videoHeight,
    int? recoveryElapsedMs,
    int? positionMs,
    int? bufferedEndMs,
    int? motionAgeMs,
    int? feedAgeMs,
    int? playlistSequence,
    int? playlistTargetSeconds,
    int? playlistDiscontinuities,
  }) {
    if (!PlayerDiagnosticCodes.events.contains(event)) return;
    final uri = Uri.tryParse(source.url ?? '');
    final host = uri != null && uri.hasAuthority ? uri.host : null;
    IosAudioTelemetry.instance.captureLiveTvObservation(
      event: event,
      channelId: channelId,
      channelTitle: title,
      programmeTitle: programmeTitle,
      programmeKind: programmeKind,
      sourceAddon: source.addonName,
      sourceName: source.name,
      sourceDescription: source.description,
      sourceHost: host,
      sourceFormat: LiveStreamDetector.isHlsUrl(source.url)
          ? 'hls' : LiveStreamDetector.isHttpMedia(source.url)
          ? 'http' : 'other',
      sourceQuality: source.quality,
      signalQuality: signalQuality,
      failureClass: failureClass,
      recoveryAttempts: attempts,
      candidateCount: candidateCount,
      buffering: buffering,
      playing: playing,
      verifiedPlayback: videoReady,
      reconnecting: reconnecting,
      startupElapsedMs: startupElapsedMs,
      firstFrameElapsedMs: firstFrameElapsedMs,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      recoveryElapsedMs: recoveryElapsedMs,
      positionMs: positionMs,
      bufferedEndMs: bufferedEndMs,
      motionAgeMs: motionAgeMs,
      feedAgeMs: feedAgeMs,
      playlistSequence: playlistSequence,
      playlistTargetSeconds: playlistTargetSeconds,
      playlistDiscontinuities: playlistDiscontinuities,
    );
  }

  static void uploadRepeatedFailure() {
    unawaited(_upload());
  }

  static Future<void> _upload() async {
    try {
      await WindowsPlaybackTelemetry.instance.upload(
        reason: 'live_reconnect_failed', automatic: true,
      );
    } catch (_) {
      // Owner opt-in and telemetry throttling remain authoritative.
    }
    try {
      await IosAudioTelemetry.instance.upload(
        reason: 'live_reconnect_failed', automatic: true,
      );
    } catch (_) {
      // Telemetry failures must not disrupt the stream watchdog.
    }
  }
}
