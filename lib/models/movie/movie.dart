class Movie {
  /// Normalize common provider names to Stremio's movie/series/anime types.
  /// Do not turn unknown formats into movies: a missing label is not proof.
  static String canonicalType(String? input) {
    switch (input?.trim().toLowerCase()) {
      case 'series':
      case 'tv':
      case 'tvshow':
      case 'tv_show':
      case 'tv-series':
      case 'tv_series':
      case 'shows':
      case 'show':
      case 'serial':
        return 'series';
      case 'movie':
      case 'movies':
      case 'film':
        return 'movie';
      case 'anime':
        return 'anime';
      default:
        return 'unknown';
    }
  }

  static String typeLabel(String? input) {
    switch (canonicalType(input)) {
      case 'series': return 'Series';
      case 'movie': return 'Movie';
      case 'anime': return 'Anime';
      default: return 'Title';
    }
  }
  final String id;
  final String name;
  final String? poster;
  final String? year;
  final String type;
  final String addonBaseUrl;
  final String? imdbRating;

  Movie({
    required this.id,
    required this.name,
    this.poster,
    this.year,
    required this.type,
    required this.addonBaseUrl,
    this.imdbRating,
  });

  factory Movie.fromJson(Map<String, dynamic> json, String addonBaseUrl, {String? fallbackType}) {
    String? ratingStr;
    if (json['imdbRating'] != null) {
      ratingStr = json['imdbRating'].toString();
    } else if (json['rating'] != null) {
      ratingStr = json['rating'].toString();
    } else if (json['imdb_rating'] != null) {
      ratingStr = json['imdb_rating'].toString();
    } else if (json['vote_average'] != null) {
      ratingStr = json['vote_average'].toString();
    }

    return Movie(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      poster: json['poster']?.toString(),
      year: json['releaseInfo']?.toString() ?? json['year']?.toString(),
      type: canonicalType(json['type']?.toString() ?? fallbackType),
      addonBaseUrl: addonBaseUrl,
      imdbRating: ratingStr,
    );
  }
}
