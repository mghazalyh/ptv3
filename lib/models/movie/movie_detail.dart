import 'link.dart';
import 'video.dart';

class MovieDetail {
  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? background;
  final String? logo;
  final String? description;
  final String? year;
  final String? imdbRating;
  final List<String> genres;
  final List<String> cast;
  final List<String> director;
  final String? runtime;
  final Map<String, dynamic> behaviorHints;
  bool get isLive => type == 'tv' || behaviorHints['isLive'] == true;
  bool get hasScheduledVideos => behaviorHints['hasScheduledVideos'] == true;
  String? get defaultVideoId => behaviorHints['defaultVideoId']?.toString();
  final List<Link> links;
  final List<Video> videos;
  final String? tmdbId;
  final List<String> originCountries;
  final String? originalLanguage;

  MovieDetail({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.logo,
    this.description,
    this.year,
    this.imdbRating,
    this.genres = const [],
    this.cast = const [],
    this.director = const [],
    this.runtime,
    this.behaviorHints = const {},
    this.links = const [],
    this.videos = const [],
    this.tmdbId,
    this.originCountries = const [],
    this.originalLanguage,
  });

  factory MovieDetail.fromJson(Map<String, dynamic> json) {
    return MovieDetail(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'movie',
      name: json['name']?.toString() ?? 'Unknown',
      poster: json['poster']?.toString(),
      background: json['background']?.toString(),
      logo: json['logo']?.toString(),
      description: json['description']?.toString(),
      year: json['releaseInfo']?.toString() ?? json['year']?.toString(),
      imdbRating: json['imdbRating']?.toString(),
      genres: _parseStringList(json['genres']),
      cast: _parseStringList(json['cast']),
      director: _parseStringList(json['director']),
      runtime: json['runtime']?.toString(),
      behaviorHints: json['behaviorHints'] is Map
          ? Map<String, dynamic>.from(json['behaviorHints'] as Map)
          : const {},
      links: _parseEntries(json['links'], Link.fromJson),
      videos: _parseEntries(json['videos'], Video.fromJson),
      tmdbId: json['moviedb_id']?.toString(),
      originCountries: [
        for (final value in (json['origin_country'] is List
            ? json['origin_country'] as List
            : json['country'] is String &&
              (json['country'] as String).trim().isNotEmpty
              ? [json['country']] : const []))
          if (value.toString().trim().isNotEmpty) value.toString(),
      ],
      originalLanguage:
          (json['original_language'] ?? json['originalLanguage'])?.toString(),
    );
  }
}

List<String> _parseStringList(dynamic value) {
  if (value == null) return [];
  if (value is String) return [value];
  if (value is List) return value.map((e) => e.toString()).toList();
  return [];
}

/// Optional addon fields must not invalidate an otherwise usable meta result.
/// Ignore malformed entries without leaking their content to diagnostics.
List<T> _parseEntries<T>(
    dynamic value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) return <T>[];
  final result = <T>[];
  for (final item in value) {
    if (item is! Map) continue;
    try {
      result.add(parse(Map<String, dynamic>.from(item)));
    } catch (_) {
      // A malformed optional episode/link is not a metadata-wide failure.
    }
  }
  return result;
}
