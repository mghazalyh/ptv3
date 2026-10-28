import 'dart:async';

/// Safe, read-only player properties. Never inspect URLs, headers or hashes.
class PlaybackDiagnosticsProbe {
  static const properties = <String>[
    'video-codec',
    'video-params/w',
    'video-params/h',
    'estimated-vf-fps',
    'video-bitrate',
    'audio-codec',
    'audio-bitrate',
    'audio-params/samplerate',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'hwdec-current',
    'demuxer-cache-duration',
  ];

  static Future<Map<String, String>> sample(
      Future<Object?> Function(String property) read) async {
    final result = <String, String>{};
    for (final property in properties) {
      try {
        final value = await read(property)
            .timeout(const Duration(milliseconds: 350));
        final text = value?.toString().trim() ?? '';
        if (safeValue(text) != null) result[property] = text;
      } catch (_) {
        // Not every mpv build supports all properties.
      }
    }
    return result;
  }

  static String? safeValue(String value) {
    if (value.isEmpty || value.length > 48 ||
        value == 'no' || value == 'N/A' ||
        value.toLowerCase() == 'unavailable' ||
        !RegExp(r'^[A-Za-z0-9._+\- /]+$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  static String resolution(Map<String, String> data) {
    final w = int.tryParse(data['video-params/w'] ?? '');
    final h = int.tryParse(data['video-params/h'] ?? '');
    if (w == null || h == null || w < 1 || h < 1 ||
        w > 16384 || h > 16384) return 'Unavailable';
    return '${w} × ${h}';
  }

  static String frameRate(Map<String, String> data) {
    final n = double.tryParse(data['estimated-vf-fps'] ?? '');
    if (n == null || n <= 0 || !n.isFinite || n > 1000) {
      return 'Unavailable';
    }
    return '${n.toStringAsFixed(2)} fps';
  }

  static String bitrate(Map<String, String> data, String key) {
    final n = double.tryParse(data[key] ?? '');
    if (n == null || n <= 0 || !n.isFinite) return 'Unavailable';
    return '${(n / 1000000).toStringAsFixed(2)} Mbps';
  }

  static String cacheAhead(Map<String, String> data) {
    final n = double.tryParse(data['demuxer-cache-duration'] ?? '');
    if (n == null || n < 0 || !n.isFinite) return 'Unavailable';
    return '${n.toStringAsFixed(1)} s';
  }

  static String readable(String? value) =>
      safeValue(value?.trim() ?? '') ?? 'Unavailable';

  static String time(Duration position) {
    final secs = position.inSeconds < 0 ? 0 : position.inSeconds;
    final hours = secs ~/ 3600;
    final mins = (secs ~/ 60) % 60;
    final sec = secs % 60;
    return hours > 0
        ? '$hours:${mins.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
        : '${mins.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
