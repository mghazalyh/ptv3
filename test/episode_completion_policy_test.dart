import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/episode_completion_policy.dart';

void main() {
  test('accepts recognized runtime metadata without guessing ranges', () {
    expect(EpisodeCompletionPolicy.parseRuntime('1h 2m')?.inMinutes, 62);
    expect(EpisodeCompletionPolicy.parseRuntime('1 hour 2 minutes')?.inMinutes, 62);
    expect(EpisodeCompletionPolicy.parseRuntime('62 min')?.inMinutes, 62);
    expect(EpisodeCompletionPolicy.parseRuntime('62')?.inMinutes, 62);
    expect(EpisodeCompletionPolicy.parseRuntime('01:02:00')?.inMinutes, 62);
    expect(EpisodeCompletionPolicy.parseRuntime('PT1H2M')?.inMinutes, 62);
    expect(EpisodeCompletionPolicy.parseRuntime('45-55 minutes'), isNull);
    expect(EpisodeCompletionPolicy.parseRuntime(null), isNull);
    expect(EpisodeCompletionPolicy.parseRuntime(''), isNull);
  });

  test('Nocturne S01E01 62-minute runtime blocks 29-minute EOF', () {
    final decision = EpisodeCompletionPolicy.assess(
      position: const Duration(minutes: 29),
      nativeDuration: const Duration(minutes: 29),
      episodeRuntime: '1h 2m',
    );
    expect(decision.allowAutoplay, isFalse);
    expect(decision.reason, 'source_shorter_than_expected_episode');
    expect(decision.expectedRuntime?.inMinutes, 62);
  });

  test('Nocturne stream cannot advance when native EOF is early', () {
    final decision = EpisodeCompletionPolicy.assess(
      position: const Duration(minutes: 29),
      nativeDuration: const Duration(minutes: 62),
      seriesRuntime: '62 min',
    );
    expect(decision.allowAutoplay, isFalse);
    expect(decision.reason, 'playback_before_expected_episode_end');
  });

  test('unknown runtime never silently jumps to episode two', () {
    final decision = EpisodeCompletionPolicy.assess(
      position: const Duration(minutes: 29),
      nativeDuration: const Duration(minutes: 29),
    );
    expect(decision.allowAutoplay, isFalse);
    expect(decision.reason, 'trusted_runtime_unavailable');
  });

  test('verified natural episode completion allows normal autoplay', () {
    final decision = EpisodeCompletionPolicy.assess(
      position: const Duration(minutes: 61, seconds: 56),
      nativeDuration: const Duration(minutes: 62),
      episodeRuntime: '62 minutes',
    );
    expect(decision.allowAutoplay, isTrue);
    expect(decision.reason, 'trusted_episode_end_verified');
  });

  test('23-minute anime advances only with valid 23-minute metadata', () {
    expect(EpisodeCompletionPolicy.assess(
      position: const Duration(minutes: 22, seconds: 52),
      nativeDuration: const Duration(minutes: 23),
      episodeRuntime: '23 min',
    ).allowAutoplay, isTrue);
    expect(EpisodeCompletionPolicy.assess(
      position: const Duration(minutes: 22, seconds: 52),
      nativeDuration: const Duration(minutes: 23),
      episodeRuntime: '42 min',
    ).allowAutoplay, isFalse);
  });

  test('network buffering at native completion blocks autoplay', () {
    final decision = EpisodeCompletionPolicy.assess(
      position: const Duration(minutes: 61, seconds: 56),
      nativeDuration: const Duration(minutes: 62),
      episodeRuntime: '62m',
      buffering: true,
    );
    expect(decision.reason, 'buffering_at_native_completion');
  });

  test('seeking from early playback to EOF does not advance', () {
    final decision = EpisodeCompletionPolicy.assess(
      position: const Duration(minutes: 61, seconds: 59),
      nativeDuration: const Duration(minutes: 62),
      episodeRuntime: '62 minutes',
      recentSeek: true,
      recentSeekFrom: const Duration(minutes: 29),
    );
    expect(decision.reason, 'recent_seek_from_early_position');
  });

  test('source completion before its native duration is rejected', () {
    final decision = EpisodeCompletionPolicy.assess(
      position: const Duration(minutes: 56),
      nativeDuration: const Duration(minutes: 62),
      episodeRuntime: '62 min',
    );
    expect(decision.allowAutoplay, isFalse);
  });

  test('progress duration uses metadata to prevent false watched marks', () {
    expect(EpisodeCompletionPolicy.effectiveProgressDuration(
      nativeDuration: const Duration(minutes: 29),
      seriesRuntime: '1h 2m',
    ).inMinutes, 62);
    expect(EpisodeCompletionPolicy.effectiveProgressDuration(
      nativeDuration: const Duration(minutes: 62),
      seriesRuntime: '1h',
    ).inMinutes, 62);
  });
}
