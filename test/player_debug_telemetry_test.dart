import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/player_debug_telemetry.dart';
import 'package:playtorrio/services/player/player_diagnostic_codes.dart';

void main() {
  test('pause/reconnect failures are categorized as source failures', () {
    expect(PlayerDebugTelemetry.failureReasonFor(
        'pause_resume_stall_detected'), 'source_failure');
    expect(PlayerDebugTelemetry.failureReasonFor(
        'pause_resume_reopen_failed'), 'source_failure');
    expect(PlayerDebugTelemetry.failureReasonFor(
        'subtitle_attach_failed'), 'subtitle_failure');
    expect(PlayerDebugTelemetry.failureReasonFor(
        'sync_timeout'), 'sync_failure');
  });

  test('new diagnostics are allowlisted and contain no media values', () {
    for (final code in [
      'pause_resume_existing_connection', 'pause_resume_stall_detected',
      'pause_resume_reopened', 'pause_resume_reopen_failed',
      'playback_first_frame_slow', 'subtitle_background_sync_scheduled',
    ]) {
      expect(PlayerDiagnosticCodes.events, contains(code));
      expect(code.contains('https://'), isFalse);
    }
  });
}
