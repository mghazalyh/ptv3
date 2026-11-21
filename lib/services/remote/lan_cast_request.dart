/// Identity-only media handoff between already paired PlayTorrio devices.
/// No stream URLs, login credentials, or executable input cross the LAN.
class LanCastRequest {
  const LanCastRequest({
    required this.type,
    required this.mediaId,
    required this.title,
    this.addonBaseUrl,
    this.episodeId,
    this.season,
    this.episode,
  });

  final String type;
  final String mediaId;
  final String title;
  final String? addonBaseUrl;
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
    final base = raw['addonBaseUrl']?.toString().trim();
    if (base != null && base.isNotEmpty) {
      final uri = Uri.tryParse(base);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
          uri.userInfo.isNotEmpty || uri.query.isNotEmpty ||
          uri.fragment.isNotEmpty || base.length > 240) return null;
    }
    return LanCastRequest(
      type: type,
      mediaId: mediaId,
      title: title,
      addonBaseUrl: base == null || base.isEmpty ? null : base,
      episodeId: episodeId == null || episodeId.isEmpty ? null : episodeId,
      season: season as int?,
      episode: episode as int?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'mediaId': mediaId,
    'title': title,
    if (addonBaseUrl != null) 'addonBaseUrl': addonBaseUrl,
    if (episodeId != null) 'episodeId': episodeId,
    if (season != null) 'season': season,
    if (episode != null) 'episode': episode,
  };
}
