import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/subtitle_auto_sync_platform.dart';

void main() {
  test('native speech failures map to safe bounded categories', () {
    const cases = <String, String>{
      'speech_permission': 'sync_apple_permission_denied',
      'speech_service_unavailable': 'sync_apple_service_unavailable',
      'speech_unavailable': 'sync_apple_service_unavailable',
      'network_required': 'sync_apple_offline_unavailable',
      'offline_recognition_failed': 'sync_apple_offline_unavailable',
      'recognition_failed': 'sync_apple_recognition_failed',
      'no_speech': 'sync_apple_recognition_failed',
      'timeout': 'sync_apple_recognition_timeout',
      'busy': 'sync_apple_busy',
      'audio_extract_failed': 'sync_apple_audio_extract_failed',
      'unsupported_media': 'sync_apple_audio_extract_failed',
      'decoder_audio_extract_failed': 'sync_apple_decoder_extract_failed',
      'invalid_audio_excerpt': 'sync_apple_decoder_extract_failed',
      'invalid_args': 'sync_apple_invalid_excerpt',
      'invalid_range': 'sync_apple_invalid_excerpt',
      'unsupported_source': 'sync_apple_invalid_excerpt',
    };
    for (final entry in cases.entries) {
      expect(SubtitleAutoSyncPlatform.failureEventForCode(entry.key),
          entry.value);
    }
    const privateValue = 'https://private.invalid/?token=secret';
    expect(SubtitleAutoSyncPlatform.failureEventForCode(privateValue),
        'sync_apple_unknown_failure');
    expect(SubtitleAutoSyncPlatform.failureEventForCode(null),
        'sync_apple_unknown_failure');
  });

  test('iOS invokes spoken-audio alignment in the shared player', () {
    expect(SubtitleAutoSyncPlatform.modeFor(isIOS: true),
        SubtitleAutoSyncMode.speechTiming);
    expect(SubtitleAutoSyncPlatform.tooltipFor(isIOS: true),
        contains('spoken English'));
  });

  test('Non-Windows platforms retain release-matched subtitle selection',
      () {
    expect(SubtitleAutoSyncPlatform.modeFor(isIOS: false),
        SubtitleAutoSyncMode.releaseMatching);
    final tooltip = SubtitleAutoSyncPlatform.tooltipFor(isIOS: false);
    expect(tooltip, contains('release-matched'));
    expect(tooltip, isNot(contains('spoken')));
    expect(tooltip, contains('manual timing'));
  });

  test('Other platform fallback is stable across repeated Auto Sync taps',
      () {
    for (var attempt = 0; attempt < 5; attempt++) {
      expect(SubtitleAutoSyncPlatform.modeFor(isIOS: false),
          SubtitleAutoSyncMode.releaseMatching);
    }
  });
}
