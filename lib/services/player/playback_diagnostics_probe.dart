import 'dart:async';

/// Safe, read-only player properties. Never inspect URLs, headers or hashes.
class PlaybackDiagnosticsProbe {
  static const properties = <String>[
    'video-codec',
    'video-params/w',
    'video-params/h',
    'estimated-vf-fps',
    'video-bitrate',
    'video-params/gamma',
    'video-params/primaries',
    'video-params/colormatrix',
    'video-params/pixelformat',
    'video-params/bits-per-component',
    'audio-codec',
    'audio-codec-name',
    'audio-bitrate',
    'audio-params/samplerate',
    'audio-params/channels',
    'audio-params/channel-count',
    'current-tracks/audio/lang',
    'current-tracks/audio/title',
    'aid',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'vo-delayed-frame-count',
    'hwdec-current',
    'avsync',
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

  static String audioSampleRate(Map<String, String> data) {
    final n = int.tryParse(data['audio-params/samplerate'] ?? '');
    if (n == null || n < 8000 || n > 384000) return 'Unavailable';
    return '${(n / 1000).toStringAsFixed(1)} kHz';
  }

  static String readable(String? value) =>
      safeValue(value?.trim() ?? '') ?? 'Unavailable';

  /// Report decoder dimensions, not the resolution advertised by an addon.
  static ({int width, int height})? dimensions(Map<String, String> data) {
    final width = int.tryParse(data['video-params/w'] ?? '');
    final height = int.tryParse(data['video-params/h'] ?? '');
    if (width == null || height == null || width < 1 || height < 1 ||
        width > 16384 || height > 16384) return null;
    return (width: width, height: height);
  }

  static String qualityTier(Map<String, String> data) {
    final dimensions = PlaybackDiagnosticsProbe.dimensions(data);
    if (dimensions == null) return 'Resolution unknown';
    final w = dimensions.width;
    final h = dimensions.height;
    if (w >= 3800 && h >= 2000) {
      return w >= 4096 ? '4K DCI' : '4K UHD';
    }
    if (w >= 3800 && h >= 1550) return '4K-width · cropped';
    if (w >= 2560 && h >= 1250) return '1440p · QHD';
    if (w >= 2560 && h >= 990) return '1440p-class · cropped';
    if (w >= 1900 && h >= 1000) return '1080p · Full HD';
    if (w >= 1900 && h >= 750) return '1080p-class · cropped';
    if (w >= 1250 && h >= 700) return '720p · HD';
    if (w >= 1250 && h >= 500) return '720p-class · cropped';
    if (w >= 840 && h >= 450) return 'SD / 480p-class';
    return 'Low resolution';
  }

  static String fourKStatus(Map<String, String> data) {
    final dimensions = PlaybackDiagnosticsProbe.dimensions(data);
    if (dimensions == null) return 'Cannot verify without decoded resolution';
    return dimensions.width >= 3800 && dimensions.height >= 1550
        ? '4K-class decoded video'
        : 'Not 4K · decoded video';
  }

  static String dynamicRange(Map<String, String> data) {
    final gamma = (data['video-params/gamma'] ?? '').toLowerCase();
    if (const {'pq', 'smpte2084', 'smpte-st-2084', 'st2084'}
        .contains(gamma)) return 'HDR · PQ';
    if (const {'hlg', 'arib-std-b67', 'arib-std-b67-hlg'}
        .contains(gamma)) return 'HDR · HLG';
    if (const {'bt.1886', 'bt1886', 'srgb', 'gamma2.2', 'gamma2.8',
      'linear', 'bt.709', 'bt709'}.contains(gamma)) return 'SDR';
    return 'Unknown · HDR not confirmed';
  }

  static String videoCodec(Map<String, String> data) {
    final codec = (data['video-codec'] ?? '').toLowerCase();
    if (codec.contains('h264') || codec.contains('avc'))
      return 'H.264 / AVC';
    if (codec.contains('hevc') || codec.contains('h265'))
      return 'H.265 / HEVC';
    if (codec.contains('av1')) return 'AV1';
    if (codec.contains('vp9')) return 'VP9';
    return readable(data['video-codec']);
  }

  static String audioCodec(Map<String, String> data) {
    final raw = readable(data['audio-codec-name'] ?? data['audio-codec']);
    switch (raw.toLowerCase()) {
      case 'eac3': return 'Dolby Digital Plus (E-AC-3)';
      case 'ac3': return 'Dolby Digital (AC-3)';
      case 'truehd': return 'Dolby TrueHD';
      case 'dts': return 'DTS';
      case 'aac': return 'AAC';
      case 'opus': return 'Opus';
      case 'flac': return 'FLAC';
      case 'mp3': return 'MP3';
      default: return raw;
    }
  }

  static String colorDepth(Map<String, String> data) {
    final bits = int.tryParse(data['video-params/bits-per-component'] ?? '');
    return bits == null || bits < 6 || bits > 16
        ? 'Unavailable' : '$bits-bit';
  }

  static String colorPrimaries(Map<String, String> data) =>
      readable(data['video-params/primaries']);

  static String pixelFormat(Map<String, String> data) =>
      readable(data['video-params/pixelformat']);

  static String audioChannels(Map<String, String> data,
      {int? selectedChannelCount}) {
    final count = int.tryParse(data['audio-params/channel-count'] ?? '');
    final raw = data['audio-params/channels']?.trim();
    if (raw != null && raw.isNotEmpty) {
      if (raw == 'stereo' || raw == '2.0') return 'Stereo (2.0)';
      if (raw == 'mono' || raw == '1.0') return 'Mono (1.0)';
      if (raw == '5.1' || raw == '7.1') return '$raw surround';
      return readable(raw);
    }
    final available = count ?? selectedChannelCount;
    if (available == null || available < 1 || available > 64)
      return 'Unavailable';
    if (available == 1) return 'Mono';
    if (available == 2) return 'Stereo';
    return '$available channels';
  }

  static String audioLanguage(Map<String, String> data,
      {String? selectedLanguage}) {
    final raw = (data['current-tracks/audio/lang'] ?? selectedLanguage ?? '')
        .toLowerCase().trim();
    switch (raw) {
      case 'en':
      case 'eng':
      case 'english': return 'English';
      case 'ru':
      case 'rus':
      case 'russian': return 'Russian';
      case 'es':
      case 'spa':
      case 'spanish': return 'Spanish';
      case 'it':
      case 'ita':
      case 'italian': return 'Italian';
      case 'fr':
      case 'fra':
      case 'fre':
      case 'french': return 'French';
      case 'ja':
      case 'jpn':
      case 'japanese': return 'Japanese';
      default: return raw.isEmpty || raw == 'und'
          ? 'Unknown · track not tagged' : readable(raw);
    }
  }

  static String selectedTrack(Map<String, String> data) =>
      readable(data['aid']);

  static String avSync(Map<String, String> data) {
    final seconds = double.tryParse(data['avsync'] ?? '');
    if (seconds == null || !seconds.isFinite || seconds.abs() > 10) {
      return 'Unavailable';
    }
    return '${(seconds * 1000).round()} ms';
  }

  static String bufferingAhead(Duration position, Duration? buffered) {
    if (buffered == null || buffered <= Duration.zero) return 'Unavailable';
    final remaining = buffered - position;
    if (remaining <= Duration.zero) return '0.0 s';
    return '${(remaining.inMilliseconds / 1000).toStringAsFixed(1)} s';
  }

  /// A bitrate-based indication is not a subjective image-quality score.
  /// Codec efficiency varies and actual perceived sharpness cannot be
  /// established from bitrate alone.
  static String bitrateIndication(Map<String, String> data) {
    final dimensions = PlaybackDiagnosticsProbe.dimensions(data);
    final bitsPerSecond = double.tryParse(data['video-bitrate'] ?? '');
    if (dimensions == null || bitsPerSecond == null ||
        !bitsPerSecond.isFinite || bitsPerSecond <= 0) return 'Unavailable';
    final mbps = bitsPerSecond / 1000000;
    final codec = videoCodec(data);
    final efficient = codec.contains('HEVC') ||
        codec == 'AV1' || codec == 'VP9';
    final relative = dimensions.width >= 3800 ? 4.0
        : dimensions.width >= 2500 ? 2.0
        : dimensions.width >= 1800 ? 1.0
        : dimensions.width >= 1200 ? 0.6 : 0.3;
    final medium = (efficient ? 2.5 : 4.0) * relative;
    final high = (efficient ? 5.0 : 8.0) * relative;
    if (mbps < medium) return 'Low bitrate for resolution · indicative';
    if (mbps < high) return 'Moderate bitrate · indicative';
    return 'High bitrate · indicative';
  }

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
