import 'dart:async';
import 'dart:io';

import 'ios_audio_telemetry.dart';
import 'player_diagnostic_codes.dart';
import 'windows_playback_telemetry.dart';

/// Shared opt-in, privacy-bounded event recorder. Failure events trigger a
/// throttled upload to the existing private repository, without raw log text.
abstract final class PlayerDebugTelemetry {
  static Timer? _delayedFlush;

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
    unawaited(_flush());
    _delayedFlush?.cancel();
    _delayedFlush = Timer(const Duration(seconds: 36), () {
      _delayedFlush = null;
      unawaited(_flush());
    });
  }

  static Future<void> _flush() async {
    try {
      if (Platform.isWindows) {
        await WindowsPlaybackTelemetry.instance.upload(
          reason: 'sync_failure', automatic: true);
      } else if (Platform.isIOS) {
        await IosAudioTelemetry.instance.upload(
          reason: 'sync_failure', automatic: true);
      }
    } catch (_) {
      // Diagnostic delivery is best effort and never interrupts playback.
    }
  }
}
