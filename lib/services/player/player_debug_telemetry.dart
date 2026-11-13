import 'dart:async';
import 'dart:io';

import 'ios_audio_telemetry.dart';
import 'player_diagnostic_codes.dart';
import 'windows_playback_telemetry.dart';

/// Shared opt-in, privacy-bounded event recorder. Failure events trigger a
/// throttled upload to the existing private repository, without raw log text.
abstract final class PlayerDebugTelemetry {
  static Timer? _delayedFlush;

  /// Safe failure grouping. Pause/reconnect failures belong to source issues.
  static String failureReasonFor(String stage) {
    if (stage.startsWith('subtitle_')) return 'subtitle_failure';
    if (stage.startsWith('source_') || stage.startsWith('pause_')) {
      return 'source_failure';
    }
    return 'sync_failure';
  }

  static void record(String stage, {bool? failure}) {
    if (!PlayerDiagnosticCodes.events.contains(stage)) return;
    if (Platform.isWindows) {
      final diagnostics = WindowsPlaybackTelemetry.instance;
      if (!diagnostics.isActive) return;
      diagnostics.captureCode(stage);
    } else if (Platform.isIOS) {
      final diagnostics = IosAudioTelemetry.instance;
      if (!diagnostics.isActive) return;
      diagnostics.captureCode(stage);
    } else {
      return;
    }
    if (failure != true) return;
    final reason = failureReasonFor(stage);
    unawaited(_flush(reason));
    _delayedFlush?.cancel();
    _delayedFlush = Timer(const Duration(seconds: 36), () {
      _delayedFlush = null;
      unawaited(_flush(reason));
    });
  }

  static Future<void> _flush(String reason) async {
    try {
      if (Platform.isWindows) {
        await WindowsPlaybackTelemetry.instance.upload(
          reason: reason, automatic: true);
      } else if (Platform.isIOS) {
        await IosAudioTelemetry.instance.upload(
          reason: reason, automatic: true);
      }
    } catch (_) {
      // Diagnostic delivery is best effort and never interrupts playback.
    }
  }
}
