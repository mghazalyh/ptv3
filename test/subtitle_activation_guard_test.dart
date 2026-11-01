import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/subtitle_activation_guard.dart';
import 'package:playtorrio/services/player/player_diagnostic_codes.dart';
import 'package:playtorrio/services/subtitles/subtitle_parser.dart';

void main() {
  test('Rejects HTML and empty downloaded subtitles', () {
    expect(
      SubtitleActivationGuard.hasRenderableCues(
        SubtitleParser.parse('<html>Access denied</html>')),
      isFalse,
    );
    expect(
      SubtitleActivationGuard.hasRenderableCues(
        SubtitleParser.parse('WEBVTT\n\nNo timed cues here')),
      isFalse,
    );
  });

  test('Accepts timed SRT and WebVTT cues', () {
    expect(
      SubtitleActivationGuard.hasRenderableCues(SubtitleParser.parse(
        '1\n00:00:01,000 --> 00:00:03,000\nHello\n')),
      isTrue,
    );
    expect(
      SubtitleActivationGuard.hasRenderableCues(SubtitleParser.parse(
        'WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nHello\n')),
      isTrue,
    );
  });

  test('Does not mistake inactive MPV sid values for selection', () {
    for (final sid in ['no', 'auto', '0', 0, '-1']) {
      expect(SubtitleActivationGuard.classifySid(sid),
          SubtitleTrackReadiness.inactive);
    }
    expect(SubtitleActivationGuard.classifySid(3),
        SubtitleTrackReadiness.selected);
    expect(SubtitleActivationGuard.classifySid('7'),
        SubtitleTrackReadiness.selected);
    expect(SubtitleActivationGuard.classifySid(null),
        SubtitleTrackReadiness.unknown);
  });

  test('Allows delayed native track activation', () async {
    var attempts = 0;
    final result = await SubtitleActivationGuard.waitForSelection(() async {
      attempts++;
      return attempts < 3 ? 'no' : '2';
    }, interval: Duration.zero);
    expect(result, SubtitleTrackReadiness.selected);
    expect(attempts, 3);
  });

  test('Preserves inactive versus unobservable native selection', () async {
    expect(
      await SubtitleActivationGuard.waitForSelection(
        () async => 'no', attempts: 2, interval: Duration.zero),
      SubtitleTrackReadiness.inactive,
    );
    expect(
      await SubtitleActivationGuard.waitForSelection(
        () async => throw StateError('not supported'),
        interval: Duration.zero),
      SubtitleTrackReadiness.unknown,
    );
  });

  test('Telemetry records only predefined subtitle stage codes', () {
    const stages = [
      'subtitle_download_started', 'subtitle_download_failed',
      'subtitle_downloaded', 'subtitle_parse_failed', 'subtitle_parsed',
      'subtitle_attach_started', 'subtitle_attach_failed',
      'subtitle_track_unselected', 'subtitle_track_selected',
      'subtitle_track_unknown', 'subtitle_native_renderer_active',
      'subtitle_flutter_renderer_active', 'subtitle_renderer_hidden',
      'subtitle_renderer_unknown',
    ];
    for (final stage in stages) {
      expect(PlayerDiagnosticCodes.events.contains(stage), isTrue);
    }
    expect(PlayerDiagnosticCodes.events.contains('subtitle_url'), isFalse);
    expect(PlayerDiagnosticCodes.events.contains('subtitle_text'), isFalse);
  });
}
