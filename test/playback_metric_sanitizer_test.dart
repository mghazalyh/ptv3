import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/playback_metric_sanitizer.dart';

void main() {
  test('preserves bounded useful metrics only', () {
    final fields = PlaybackMetricSanitizer.fromProperties({
      'first-frame-ms': 1530, 'video-params/w': 3840,
      'video-params/h': 2160, 'video-codec': 'HEVC',
      'estimated-vf-fps': 23.976,
      'stream-open-filename': 'https://private.example/media?key=secret',
      'title': 'Private movie', 'headers': 'Bearer secret',
    });
    expect(fields['firstFrameMs'], 1530);
    expect(fields['videoWidth'], 3840);
    expect(fields['videoHeight'], 2160);
    expect(fields['videoCodec'], 'hevc');
    expect(fields['videoFps'], 23.98);
    expect(fields.containsKey('title'), isFalse);
    expect(fields.containsKey('headers'), isFalse);
    expect(fields.containsKey('stream-open-filename'), isFalse);
  });

  test('rejects unknown codecs, NaN and unbounded values', () {
    expect(PlaybackMetricSanitizer.fromProperties({
      'first-frame-ms': 999999, 'video-params/w': -1,
      'video-params/h': 100000, 'estimated-vf-fps': 'NaN',
      'video-codec': 'private/video.mp4',
    }), isEmpty);
  });
}
