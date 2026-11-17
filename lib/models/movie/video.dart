import '../stream/stream_model.dart';

class Video {
  final String id;
  final String title;
  final int? season;
  final int? episode;
  final String? released;
  final String? thumbnail;
  final String? overview;
  final List<StreamSource> streams;

  Video({
    required this.id,
    required this.title,
    this.season,
    this.episode,
    this.released,
    this.thumbnail,
    this.overview,
    this.streams = const [],
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    int? parseNum(dynamic val) {
      if (val == null) return null;
      if (val is int) return val;
      return int.tryParse(val.toString());
    }

    final rawStreams = json['streams'];
    final parsedStreams = <StreamSource>[];
    if (rawStreams is List) {
      for (final value in rawStreams) {
        if (value is! Map) continue;
        try {
          parsedStreams.add(StreamSource.fromJson(
              Map<String, dynamic>.from(value), 'TorBox'));
        } catch (_) {
          // A malformed optional embedded stream must not hide the episode.
        }
      }
    }

    return Video(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['name']?.toString() ?? 'Episode',
      season: parseNum(json['season']),
      episode: parseNum(json['episode'] ?? json['number']),
      released: json['released']?.toString(),
      thumbnail: json['thumbnail']?.toString(),
      overview: json['overview']?.toString() ?? json['description']?.toString(),
      streams: parsedStreams,
    );
  }
}
