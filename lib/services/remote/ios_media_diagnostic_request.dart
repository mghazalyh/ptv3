/// Media identity for remotely testing installed Stremio stream providers.
/// Exact series season and episode are encoded in the resource ID.
class IosMediaDiagnosticRequest {
  const IosMediaDiagnosticRequest({
    required this.type,
    required this.id,
    required this.streamId,
    required this.title,
    required this.sourceIndex,
    required this.maxSources,
    this.season,
    this.episode,
    this.year,
  });

  final String type;
  final String id;
  final String streamId;
  final String title;
  final int sourceIndex;
  final int maxSources;
  final int? season;
  final int? episode;
  final int? year;

  static IosMediaDiagnosticRequest parse(Map<String, dynamic> args) {
    if (args.keys.any((key) => !const <String>{
      'type', 'id', 'title', 'season', 'episode', 'year',
      'sourceIndex', 'maxSources',
    }.contains(key))) {
      throw const FormatException('Unknown media diagnostic argument');
    }
    final type = args['type'];
    final id = args['id'];
    final title = args['title'];
    final sourceIndex = args['sourceIndex'] ?? 0;
    final maxSources = args['maxSources'] ?? 30;
    if (type is! String || !const {'movie', 'series', 'tv'}.contains(type) ||
        id is! String || id.trim().length < 3 || id.length > 180 ||
        title is! String || title.trim().isEmpty || title.length > 220 ||
        sourceIndex is! int || sourceIndex < 0 || sourceIndex > 499 ||
        maxSources is! int || maxSources < 1 || maxSources > 500) {
      throw const FormatException('Invalid media diagnostic identity');
    }
    int? bounded(String field, int min, int max) {
      final value = args[field];
      if (value == null) return null;
      if (value is! int || value < min || value > max) {
        throw FormatException('Invalid $field');
      }
      return value;
    }
    final season = bounded('season', 0, 100);
    final episode = bounded('episode', 1, 1000);
    final year = bounded('year', 1900, 2100);
    if (type == 'series' && (season == null || episode == null)) {
      throw const FormatException('Series requires exact season and episode');
    }
    if (type != 'series' && (season != null || episode != null)) {
      throw const FormatException('Only series have episode coordinates');
    }
    if (type == 'tv' && !(id.startsWith('nltv:') ||
        id.startsWith('iptv:'))) {
      throw const FormatException('Unsupported TV channel ID');
    }
    var resourceId = id;
    if (type == 'series') {
      final suffix = ':$season:$episode';
      final existing = RegExp(r':([0-9]+):([0-9]+)$').firstMatch(id);
      if (existing != null &&
          (int.tryParse(existing.group(1) ?? '') != season ||
           int.tryParse(existing.group(2) ?? '') != episode)) {
        throw const FormatException('Episode ID does not match coordinates');
      }
      resourceId = existing == null ? '$id$suffix' : id;
    }
    return IosMediaDiagnosticRequest(
      type: type, id: id, streamId: resourceId, title: title,
      sourceIndex: sourceIndex, maxSources: maxSources,
      season: season, episode: episode, year: year,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'id': id,
    'streamId': streamId,
    'title': title,
    'sourceIndex': sourceIndex,
    'maxSources': maxSources,
    'season': season,
    'episode': episode,
    'year': year,
  };
}
