import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/ios_remote_playback_verification.dart';

void main() {
  test('VOD playback requires advancement and no buffering', () {
    final result = IosRemotePlaybackVerification.compare(
      {'playing': true, 'positionMs': 12000, 'buffering': false},
      {'playing': true, 'positionMs': 15000, 'buffering': false,
       'nativeOpening': false},
      sampleMs: 3000,
    );
    expect(result['verified'], true);
    expect(result['positionAdvanceMs'], 3000);
  });

  test('Accepted but stalled playback is not verified', () {
    final result = IosRemotePlaybackVerification.compare(
      {'playing': true, 'positionMs': 12000, 'buffering': false},
      {'playing': true, 'positionMs': 12000, 'buffering': false},
      sampleMs: 3000,
    );
    expect(result['verified'], false);
    expect(result['reason'], 'timeline_not_advancing');
  });

  test('Live TV requires actual native video evidence', () {
    final first = {
      'playing': true, 'buffering': false, 'isLive': true,
      'live': <String, Object?>{
        'positionMs': 1000, 'videoWidth': 1280, 'videoHeight': 720,
        'trackCount': 2,
      },
    };
    final withoutVideo = IosRemotePlaybackVerification.compare(
      first,
      {
        'playing': true, 'buffering': false, 'isLive': true,
        'live': <String, Object?>{
          'positionMs': 4000, 'videoWidth': 0,
          'videoHeight': 0, 'trackCount': 0,
        },
      },
      sampleMs: 3000,
    );
    expect(withoutVideo['verified'], false);
    expect(withoutVideo['reason'], 'native_video_not_verified');
  });
}
