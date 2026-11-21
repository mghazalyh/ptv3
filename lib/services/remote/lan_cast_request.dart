import '../../models/movie/video.dart';

/// Identity-only media handoff between already paired PlayTorrio devices.
/// No stream URLs, login credentials, or executable input cross the LAN.
class LanCastRequest {
  const LanCastRequest({
    required this.type,
    required this.mediaId,
    required this.title,
    this.episodeId,
    this.season,
    this.episode,
  });

  final String type;
  final String mediaId;
  final String title;
  final String? episodeId;
  final int? season;
  final int? episode;

  static const types = <String>{'movie', 'series', 'anime', 'tv'};

  static String? normalizeType(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == 'channel') return 'tv';
    return types.contains(normalized) ? normalized : null;
  }

  static bool validId(String value) =>
      value.length >= 2 && value.length <= 180 &&
      RegExp(r'^[a-zA-Z0-9:_./%-]+$').hasMatch(value) &&
      !value.contains('..') && !value.contains('//');

  static LanCastRequest? parse(Map<String, dynamic> raw) {
    final type = normalizeType(raw['type']?.toString());
    final mediaId = raw['mediaId']?.toString().trim() ?? '';
    final title = raw['title']?.toString().trim() ?? '';
    if (type == null || !validId(mediaId) ||
        title.isEmpty || title.length > 160) return null;
    final episodeId = raw['episodeId']?.toString().trim();
    if (episodeId != null && episodeId.isNotEmpty &&
        (type != 'series' && type != 'anime' || !validId(episodeId))) {
      return null;
    }
    final season = raw['season'];
    final episode = raw['episode'];
    if ((season != null && (season is! int || season < 0 || season > 100)) ||
        (episode != null && (episode is! int || episode < 0 || episode > 9999))) {
      return null;
    }
    if ((season != null || episode != null) &&
        (type != 'series' && type != 'anime')) return null;
    // Numeric coordinates must travel together unless an exact Stremio
    // episode ID is supplied. Otherwise the receiver could silently play
    // a different episode.
    if ((episodeId == null || episodeId.isEmpty) &&
        ((season == null) != (episode == null))) return null;
    // A configured Stremio addon URL may itself contain private credentials.
    // Never transmit or accept one in a media handoff.
    if (raw.containsKey('addonBaseUrl') || raw.containsKey('url') ||
        raw.containsKey('streamUrl') || raw.containsKey('infoHash')) {
      return null;
    }
    return LanCastRequest(
      type: type,
      mediaId: mediaId,
      title: title,
      episodeId: episodeId == null || episodeId.isEmpty ? null : episodeId,
      season: season as int?,
      episode: episode as int?,
    );
  }

  /// Resolve only against the receiver's installed-addon metadata. An
  /// explicit request must never fall back to the first available episode.
  /// If no episode is selected, preserve the existing first-episode action.
  Video? resolveEpisode(Iterable<Video> episodes) {
    if (type != 'series' && type != 'anime') return null;
    final exactId = episodeId;
    for (final candidate in episodes) {
      if (exactId != null && candidate.id != exactId) continue;
      if (season != null && candidate.season != season) continue;
      if (episode != null && candidate.episode != episode) continue;
      return candidate;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'mediaId': mediaId,
    'title': title,
    if (episodeId != null) 'episodeId': episodeId,
    if (season != null) 'season': season,
    if (episode != null) 'episode': episode,
  };
}
