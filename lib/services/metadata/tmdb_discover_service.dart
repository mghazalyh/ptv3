import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/movie/movie.dart';
import 'metadata_service.dart';

enum DiscoverType { movie, series }

class DiscoverFilters {
  final DiscoverType type;
  final int? fromYear;
  final int? toYear;
  final String? country;
  final String? originalLanguage;
  final String sort;
  final int page;
  const DiscoverFilters({
    this.type = DiscoverType.movie,
    this.fromYear,
    this.toYear,
    this.country,
    this.originalLanguage,
    this.sort = 'popularity.desc',
    this.page = 1,
  });

  Map<String, String> toQuery() {
    final first = fromYear ?? toYear;
    final last = toYear ?? fromYear;
    if (first != null && (first < 1900 || first > 2100) ||
        last != null && (last < 1900 || last > 2100)) {
      throw const FormatException('Years must be between 1900 and 2100.');
    }
    if (first != null && last != null && first > last) {
      throw const FormatException('Start year must not exceed end year.');
    }
    if (page < 1 || page > 500) {
      throw const FormatException('Invalid page number.');
    }
    if (!const ['popularity.desc','vote_average.desc','vote_count.desc']
        .contains(sort)) {
      throw const FormatException('Invalid sort order.');
    }
    final params = <String, String>{
      'page': '$page',
      'language': 'en-US',
      'include_adult': 'false',
      'sort_by': sort,
      if (sort == 'vote_average.desc') 'vote_count.gte': '100',
    };
    if (first != null && last != null) {
      // A series from 2023 remains eligible if an episode aired in 2026.
      // first_air_date would incorrectly remove all older shows.
      if (type == DiscoverType.series) {
        params['air_date.gte'] = '$first-01-01';
        params['air_date.lte'] = '$last-12-31';
      } else {
        params['primary_release_date.gte'] = '$first-01-01';
        params['primary_release_date.lte'] = '$last-12-31';
      }
    }
    if (country != null && country!.isNotEmpty) {
      params['with_origin_country'] = country!;
    }
    if (originalLanguage != null && originalLanguage!.isNotEmpty) {
      params['with_original_language'] = originalLanguage!;
    }
    return params;
  }

  Uri buildUri() => Uri.https('api.themoviedb.org',
      type == DiscoverType.series ? '/3/discover/tv' : '/3/discover/movie',
      toQuery());
}

class DiscoverTitle {
  final int tmdbId;
  final String title;
  final DiscoverType type;
  final String? poster;
  final int? premiereYear;
  final double rating;
  final String overview;

  const DiscoverTitle({
    required this.tmdbId,
    required this.title,
    required this.type,
    this.poster,
    this.premiereYear,
    this.rating = 0,
    this.overview = '',
  });

  factory DiscoverTitle.parse(Map<String, dynamic> json, DiscoverType type) {
    final tv = type == DiscoverType.series;
    final date = (tv ? json['first_air_date'] : json['release_date'])
            ?.toString() ?? '';
    final posterPath = json['poster_path']?.toString() ?? '';
    return DiscoverTitle(
      tmdbId: (json['id'] as num?)?.toInt() ?? 0,
      title: (tv ? json['name'] : json['title'])?.toString() ?? 'Untitled',
      type: type,
      premiereYear: date.length >= 4
          ? int.tryParse(date.substring(0, 4)) : null,
      poster: posterPath.isEmpty
          ? null : 'https://image.tmdb.org/t/p/w342$posterPath',
      rating: (json['vote_average'] as num?)?.toDouble() ?? 0,
      overview: json['overview']?.toString() ?? '',
    );
  }
}

class DiscoverResults {
  final List<DiscoverTitle> titles;
  final int page;
  final int totalPages;
  final int totalResults;
  const DiscoverResults(this.titles, this.page, this.totalPages, this.totalResults);
}

/// TMDB key is entered on the iPad, stored locally, never in GitHub or
/// build arguments. Accepts either TMDB v3 API key or v4 read-access token.
class TmdbDiscoverService {
  TmdbDiscoverService._();
  static final TmdbDiscoverService instance = TmdbDiscoverService._();
  static const _keyName = 'local_tmdb_discover_api_key';

  Future<String> readKey() async =>
      (await SharedPreferences.getInstance()).getString(_keyName) ?? '';

  Future<void> saveKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final key = value.trim();
    if (key.isEmpty) {
      await prefs.remove(_keyName);
    } else {
      await prefs.setString(_keyName, key);
    }
  }

  Future<Map<String, dynamic>> _request(
      String endpoint, Map<String, String> params, String storedKey) async {
    final bearer = storedKey.startsWith('eyJ') ||
        storedKey.startsWith('Bearer ');
    final key = storedKey.startsWith('Bearer ')
        ? storedKey.substring(7).trim() : storedKey;
    final query = <String, String>{...params};
    if (!bearer) query['api_key'] = key;
    final url = Uri.https('api.themoviedb.org', '/3/$endpoint', query);
    http.Response response;
    try {
      response = await http.get(url, headers: {
        'Accept': 'application/json',
        if (bearer) 'Authorization': 'Bearer $key',
      }).timeout(const Duration(seconds: 20));
    } catch (_) {
      // Never include URL in errors: v3 keys can be query parameters.
      throw const FormatException('Cannot connect to TMDB. Check internet access.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FormatException('TMDB API key rejected. Check Discover settings.');
    }
    if (response.statusCode == 429) {
      throw const FormatException('TMDB is rate-limiting requests. Retry shortly.');
    }
    if (response.statusCode != 200) {
      throw FormatException('TMDB returned HTTP ${response.statusCode}.');
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const FormatException('TMDB returned invalid data.');
  }

  Future<DiscoverResults> browse(DiscoverFilters filters) async {
    final key = await readKey();
    if (key.isEmpty) {
      throw const FormatException('Enter your TMDB key in Discover settings.');
    }
    final type = filters.type == DiscoverType.movie ? 'movie' : 'tv';
    final response = await _request('discover/$type', filters.toQuery(), key);
    final rows = response['results'] as List<dynamic>? ?? [];
    final titles = rows.whereType<Map<String, dynamic>>()
        .map((item) => DiscoverTitle.parse(item, filters.type))
        .where((item) => item.tmdbId > 0).toList();
    return DiscoverResults(
      titles,
      (response['page'] as num?)?.toInt() ?? filters.page,
      ((response['total_pages'] as num?)?.toInt() ?? 1).clamp(1, 500),
      (response['total_results'] as num?)?.toInt() ?? 0,
    );
  }

  /// Convert a TMDB result to IMDb/Cinemeta for existing Torrentio playback.
  Future<Movie?> resolveMovie(DiscoverTitle title) async {
    final key = await readKey();
    if (key.isEmpty) return null;
    try {
      final type = title.type == DiscoverType.movie ? 'movie' : 'tv';
      final response = await _request(
        '$type/${title.tmdbId}/external_ids', const {}, key);
      final imdbId = response['imdb_id']?.toString() ?? '';
      if (RegExp(r'^tt\d+$').hasMatch(imdbId)) {
        return Movie(
          id: imdbId,
          name: title.title,
          poster: title.poster,
          year: title.premiereYear?.toString(),
          type: title.type == DiscoverType.movie ? 'movie' : 'series',
          addonBaseUrl: 'https://v3-cinemeta.strem.io',
          imdbRating: title.rating == 0 ? null :
              title.rating.toStringAsFixed(1),
        );
      }
    } catch (_) {
      // Search by title when TMDB has no IMDb ID; do not expose API URLs.
    }
    return MetadataService.findMovieByTitle(
      title: title.title,
      type: title.type == DiscoverType.movie ? 'movie' : 'series',
      year: title.premiereYear,
    );
  }
}
