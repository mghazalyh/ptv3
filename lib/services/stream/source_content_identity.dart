import '../../models/stream/stream_model.dart';

/// Verify known release filenames before applying caching or quality preferences.
/// Opaque streams are retained, but explicitly conflicting releases are rejected.
enum SourceIdentityVerdict { verified, unknown, rejected }

abstract final class SourceContentIdentity {
  static final _releaseMarker = RegExp(
    r'\b(?:s\d{1,2}[. _-]*e\d{1,3}|s\d{1,2}[. _-]*(?:complete|pack)|'
    r'\d{1,2}x\d{1,3}|season[. _-]*\d{1,2}|(?:19|20)\d{2}|'
    r'2160p|1440p|1080p|720p|480p|web[. _-]?dl|web[. _-]?rip|'
    r'bluray|brrip|dvdrip|remux|hdtv|x264|x265|h264|h265|hevc|av1)\b',
    caseSensitive: false,
  );
  static final _episode = RegExp(
    r'\bs(\d{1,2})[. _-]*e(\d{1,3})(?:[. _-]*e?(\d{1,3}))?\b',
    caseSensitive: false,
  );
  static final _alternateEpisode = RegExp(
    r'\b(\d{1,2})x(\d{1,3})\b', caseSensitive: false,
  );
  static final _seasonPack = RegExp(
    r'\b(?:s|season[. _-]*)(\d{1,2})[. _-]*(?:complete|pack|full)\b',
    caseSensitive: false,
  );
  static final _yearTag = RegExp(r'\b((?:19|20)\d{2})\b');
  static final _technicalPrefix = RegExp(
    r'^(?:(?:tb|torbox|torrentio|comet|mediafusion|playtorrio|'
    r'cached|ready|stream|source|file|video|quality|english|multi|'
    r'en|hdr|uhd|fhd|hd|4k|1080p|720p|hevc|x265|x264)\s+)+',
  );
  static const _generic = {
    'tb', 'torbox', 'torrentio', 'comet', 'mediafusion', 'playtorrio',
    'cached', 'stream', 'source', 'video', 'file', 'unknown',
    'en', 'english', 'multi', 'quality', 'hdr', 'uhd', 'fhd',
    'hd', '4k', '1080p', '720p',
  };

  static String _canonical(String s) => s.toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceFirst(RegExp(r'^(?:the|an|a)\s+'), '');

  static String? _releaseTitle(String line) {
    final raw = line.trim();
    if (raw.isEmpty || raw.startsWith('http') ||
        raw.startsWith('magnet:')) return null;
    final noTags = raw.replaceFirst(
        RegExp(r'^(?:\s*\[[^\]]{1,40}\]\s*)+'), '');
    final marker = _releaseMarker.firstMatch(noTags);
    if (marker == null) return null;
    var stem = _canonical(noTags.substring(0, marker.start));
    stem = stem.replaceFirst(_technicalPrefix, '').trim();
    if (stem.isEmpty || stem.length > 110 || _generic.contains(stem)) {
      return null;
    }
    return stem;
  }

  static ({int season, int first, int last})? _episodeOf(String line) {
    final scene = _episode.firstMatch(line);
    if (scene != null) {
      final season = int.tryParse(scene.group(1) ?? '');
      final first = int.tryParse(scene.group(2) ?? '');
      final last = int.tryParse(scene.group(3) ?? '') ?? first;
      if (season != null && first != null && last != null) {
        return (season: season, first: first, last: last);
      }
    }
    final alternate = _alternateEpisode.firstMatch(line);
    if (alternate != null) {
      final season = int.tryParse(alternate.group(1) ?? '');
      final number = int.tryParse(alternate.group(2) ?? '');
      if (season != null && number != null) {
        return (season: season, first: number, last: number);
      }
    }
    return null;
  }

  static SourceIdentityVerdict assess(StreamSource source, {
    required String title, int? year, int? season, int? episode,
  }) {
    final expected = _canonical(title);
    if (expected.isEmpty) return SourceIdentityVerdict.unknown;
    try {
      for (final label in [source.title, source.name, source.description]) {
        if (label == null || label.isEmpty) continue;
        for (final line in label.split(RegExp(r'[\r\n|]+'))) {
          if (line.length > 320) continue;
          final extracted = _releaseTitle(line);
          if (extracted == null) continue;
          if (extracted != expected) return SourceIdentityVerdict.rejected;
          if (season != null && episode != null) {
            final tagged = _episodeOf(line);
            if (tagged != null) {
              if (tagged.season != season ||
                  episode < tagged.first || episode > tagged.last) {
                return SourceIdentityVerdict.rejected;
              }
              return SourceIdentityVerdict.verified;
            }
            final pack = _seasonPack.firstMatch(line);
            if (pack != null &&
                int.tryParse(pack.group(1) ?? '') != season) {
              return SourceIdentityVerdict.rejected;
            }
            return SourceIdentityVerdict.unknown;
          }
          if (year != null) {
            final releaseYear = int.tryParse(
                _yearTag.firstMatch(line)?.group(1) ?? '');
            if (releaseYear != null && (releaseYear - year).abs() > 1) {
              return SourceIdentityVerdict.rejected;
            }
          }
          return SourceIdentityVerdict.verified;
        }
      }
    } catch (_) {
      // Unknown metadata cannot prove content is incorrect.
    }
    return SourceIdentityVerdict.unknown;
  }

  static bool isEligible(StreamSource source, {
    required String title, int? year, int? season, int? episode,
  }) => assess(source, title: title, year: year,
      season: season, episode: episode) != SourceIdentityVerdict.rejected;

  static int priority(StreamSource source, {
    required String title, int? year, int? season, int? episode,
  }) => switch (assess(source, title: title, year: year,
      season: season, episode: episode)) {
    SourceIdentityVerdict.verified => 2,
    SourceIdentityVerdict.unknown => 1,
    SourceIdentityVerdict.rejected => 0,
  };
  static int compare(StreamSource a, StreamSource b, {
    required String title, int? year, int? season, int? episode,
  }) => priority(b, title: title, year: year,
          season: season, episode: episode)
      .compareTo(priority(a, title: title, year: year,
          season: season, episode: episode));
}
