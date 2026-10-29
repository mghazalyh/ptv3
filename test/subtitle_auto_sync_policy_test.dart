import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/subtitle_auto_sync_policy.dart';
import 'package:playtorrio/services/player/subtitle_auto_sync_platform.dart';

void main() {
  test('five-minute cadence with external cues, active playback', () {
    expect(SubtitleAutoSyncPolicy.interval, const Duration(minutes: 5));
    bool run({bool playing = true, bool loading = false, bool busy = false,
      bool cues = true, bool source = true, bool supported = true}) =>
        SubtitleAutoSyncPolicy.shouldRun(
          isPlaying: playing, isLoading: loading, isBusy: busy,
          hasExternalCues: cues, hasAudioSource: source,
          isSupported: supported);
    expect(run(), isTrue);
    expect(run(playing: false), isFalse);
    expect(run(loading: true), isFalse);
    expect(run(busy: true), isFalse);
    expect(run(cues: false), isFalse);
    expect(run(source: false), isFalse);
    expect(run(supported: false), isFalse);
  });

  test('Windows and iOS use speech timing; others retain release matching', () {
    expect(SubtitleAutoSyncPlatform.modeFor(isIOS: true),
        SubtitleAutoSyncMode.speechTiming);
    expect(SubtitleAutoSyncPlatform.modeFor(isIOS: false, isWindows: true),
        SubtitleAutoSyncMode.speechTiming);
    expect(SubtitleAutoSyncPlatform.modeFor(isIOS: false),
        SubtitleAutoSyncMode.releaseMatching);
    expect(SubtitleAutoSyncPlatform.tooltipFor(isIOS: false, isWindows: true),
        contains('Whisper'));
  });
}
