/// Bounded, content-free MPV playback metrics for opt-in diagnostics.
/// Never forwards source IDs, file names, headers or arbitrary native strings.
abstract final class PlaybackMetricSanitizer {
  static Map<String, Object> fromProperties(
      Map<String, Object?> properties) {
    final sample = <String, Object>{};
    final firstFrame = int.tryParse(
        properties['first-frame-ms']?.toString() ?? '');
    if (firstFrame != null && firstFrame >= 0 && firstFrame <= 120000) {
      sample['firstFrameMs'] = firstFrame;
    }
    for (final entry in const <String, String>{
      'video-params/w': 'videoWidth',
      'video-params/h': 'videoHeight',
    }.entries) {
      final size = int.tryParse(properties[entry.key]?.toString() ?? '');
      if (size != null && size > 0 && size <= 16384) {
        sample[entry.value] = size;
      }
    }
    final codec = properties['video-codec']?.toString().toLowerCase();
    if (codec != null && const <String>{
      'h264', 'hevc', 'h265', 'av1', 'vp9', 'mpeg2video',
      'mpeg4', 'prores', 'vc1',
    }.contains(codec)) {
      sample['videoCodec'] = codec;
    }
    final fps = double.tryParse(
        properties['estimated-vf-fps']?.toString() ?? '');
    if (fps != null && fps.isFinite && fps > 0 && fps <= 240) {
      sample['videoFps'] = (fps * 100).round() / 100;
    }
    return sample;
  }
}
