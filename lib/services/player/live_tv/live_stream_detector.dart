/// Classifies Stremio television channels without changing movie or episode
/// semantics. Never infer that a movie is live from its CDN URL alone.
abstract final class LiveStreamDetector {
  static bool isLiveChannel({
    String? mediaType,
    String? mediaId,
    Map<String, dynamic>? metaHints,
    Map<String, dynamic>? streamHints,
    bool hasEpisode = false,
  }) {
    final type = (mediaType ?? '').trim().toLowerCase();
    if (hasEpisode) return false;
    final id = (mediaId ?? '').trim().toLowerCase();
    // These IDs are reserved for broadcast channels. A navigation screen may
    // label one as 'movie' before its Stremio tv metadata finishes loading.
    if (id.startsWith('nltv:') || id.startsWith('iptv:')) return true;
    if (type == 'movie' || type == 'series' || type == 'anime') return false;
    if (type == 'tv') return true;
    return metaHints?['isLive'] == true || streamHints?['isLive'] == true;
  }

  static bool isHlsUrl(String? value) {
    if (value == null || value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    return path.endsWith('.m3u8') || path.endsWith('.m3u');
  }

  static bool isHttpMedia(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return false;
    return uri.scheme.toLowerCase() == 'http' ||
        uri.scheme.toLowerCase() == 'https';
  }
}

/// No raw playlists, signed URLs or channel identifiers are persisted.
class LivePlaylistSnapshot {
  final int? mediaSequence;
  final int targetDurationSeconds;
  final bool ended;
  final bool isMaster;
  final int discontinuities;
  final String mediaFingerprint;

  const LivePlaylistSnapshot({
    required this.mediaSequence,
    required this.targetDurationSeconds,
    required this.ended,
    required this.isMaster,
    required this.discontinuities,
    required this.mediaFingerprint,
  });

  static LivePlaylistSnapshot? parse(String body) {
    if (body.length > 262144 || !body.trimLeft().startsWith('#EXTM3U')) {
      return null;
    }
    int? sequence;
    var targetDuration = 6;
    var ended = false;
    var master = false;
    var discontinuities = 0;
    final segments = <String>[];
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.tryParse(line.split(':').last);
      } else if (line.startsWith('#EXT-X-TARGETDURATION:')) {
        targetDuration = int.tryParse(line.split(':').last) ?? 6;
      } else if (line == '#EXT-X-ENDLIST') {
        ended = true;
      } else if (line.startsWith('#EXT-X-STREAM-INF:')) {
        master = true;
      } else if (line == '#EXT-X-DISCONTINUITY') {
        discontinuities++;
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        // Only kept in memory for playlist comparison, never logged.
        segments.add(line);
      }
    }
    return LivePlaylistSnapshot(
      mediaSequence: sequence,
      targetDurationSeconds: targetDuration.clamp(2, 60).toInt(),
      ended: ended,
      isMaster: master,
      discontinuities: discontinuities,
      mediaFingerprint: segments.skip(segments.length > 5
          ? segments.length - 5 : 0).join('|'),
    );
  }

  bool sameMediaAs(LivePlaylistSnapshot other) {
    if (isMaster || other.isMaster || mediaSequence == null ||
        other.mediaSequence == null) {
      return false;
    }
    return mediaSequence == other.mediaSequence &&
        mediaFingerprint == other.mediaFingerprint;
  }
}
