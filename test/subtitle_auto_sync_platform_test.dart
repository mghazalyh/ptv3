import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/subtitle_auto_sync_platform.dart';

void main() {
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
