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
    expect(PlayerDebugTelemetry.failureReasonFor(
        'addon_meta_request_failed'), 'addon_failure');
    expect(PlayerDebugTelemetry.failureReasonFor(
        'addon_watch_sources_filtered'), 'addon_failure');
  });

  test('new diagnostics are allowlisted and contain no media values', () {
    for (final code in [
      'pause_resume_existing_connection', 'pause_resume_stall_detected',
      'pause_resume_reopened', 'pause_resume_reopen_failed',
      'playback_first_frame_slow', 'subtitle_background_sync_scheduled',
      'addon_catalog_ready', 'addon_catalog_empty', 'addon_catalog_failed',
      'addon_details_opened', 'addon_meta_fetch_started', 'addon_meta_loaded',
      'addon_meta_not_found', 'addon_meta_empty', 'addon_meta_invalid',
      'addon_meta_request_failed', 'addon_meta_fallback_started',
      'addon_meta_fallback_resolved',
      'addon_meta_unresolved', 'addon_watch_requested',
      'addon_watch_sources_available', 'addon_watch_no_sources',
      'addon_watch_search_failed', 'addon_watch_sources_filtered',
      'addon_stream_response_failed', 'addon_stream_empty',
      'addon_stream_invalid', 'addon_stream_request_failed',
      'addon_stream_unsupported_id', 'addon_stream_unsupported_type',
      'addon_stream_ready',
    ]) {
      expect(PlayerDiagnosticCodes.events, contains(code));
      expect(code.contains('https://'), isFalse);
    }
  });
}
