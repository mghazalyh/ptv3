import 'dart:async';

import '../../../models/stream/stream_model.dart';
import '../ios_audio_telemetry.dart';
import '../player_debug_telemetry.dart';
import '../player_diagnostic_codes.dart';
import '../windows_playback_telemetry.dart';

/// All event names are fixed and private telemetry is opt-in. Do not record
/// request headers, signed source URLs, playlist text or raw native errors.
abstract final class LivePlaybackTelemetry {
  static void event(
    String code, {
    required StreamSource source,
    required String channelId,
    required String title,
  }) {
    if (!PlayerDiagnosticCodes.events.contains(code)) return;
    PlayerDebugTelemetry.record(code,
        failure: code == 'live_reconnect_failed' ||
            code == 'live_source_exhausted');
    WindowsPlaybackTelemetry.instance.captureCode(code);
    IosAudioTelemetry.instance.captureCode(code);
    WindowsPlaybackTelemetry.instance.captureSourceSelection(
      action: code,
      source: source,
      title: title,
      mediaId: channelId,
      type: 'tv',
    );
    IosAudioTelemetry.instance.captureSourceSelection(
      action: code,
      source: source,
      title: title,
      mediaId: channelId,
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
      // Owner opt-in, throttling, and credentials are handled by telemetry.
    }
    try {
      await IosAudioTelemetry.instance.upload(
        reason: 'live_reconnect_failed', automatic: true,
      );
    } catch (_) {
      // Never prevent playback recovery because reporting failed.
    }
  }
}
