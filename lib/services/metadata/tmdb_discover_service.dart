import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
  final List<int> genreIds;

  const DiscoverTitle({
    required this.tmdbId,
    required this.title,
    required this.type,
    this.poster,
    this.premiereYear,
    this.rating = 0,
    this.overview = '',
    this.genreIds = const [],
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
      genreIds: (json['genre_ids'] as List<dynamic>? ?? const [])
          .whereType<num>().map((n) => n.toInt()).toList(),
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

  // Conservative local policy: well below TMDB's variable API ceiling.
  // No polling, background prefetch or automatic 429 retries.
  Duration _spacing = const Duration(milliseconds: 700);
  Duration _fallbackCooldown = const Duration(seconds: 60);
  Future<void> _paceQueue = Future<void>.value();
  DateTime? _lastRequestAt;
  DateTime? _blockedUntil;
  int _credentialRevision = 0;

  final Map<String, _DiscoverCacheEntry> _cache = {};
  final Map<String, Future<Map<String, dynamic>>> _inFlight = {};

  @visibleForTesting
  Future<http.Response> Function(Uri, Map<String, String>)? httpGetOverride;

  @visibleForTesting
  void resetForTesting({Duration? spacing, Duration? cooldown}) {
    _spacing = spacing ?? const Duration(milliseconds: 700);
    _fallbackCooldown = cooldown ?? const Duration(seconds: 60);
    _lastRequestAt = null;
    _blockedUntil = null;
    _paceQueue = Future<void>.value();
    _cache.clear();
    _inFlight.clear();
    _credentialRevision++;
    httpGetOverride = null;
  }

  /// Serializes only *start times*, not HTTP responses, so requests are paced
  /// without queueing dozens of overlapping requests on the same second.
  Future<void> _paceRequest() async {
    final turn = _paceQueue.then((_) async {
      final blocked = _blockedUntil;
      if (blocked != null && DateTime.now().isBefore(blocked)) {
        throw const FormatException(
          'TMDB requested a cooldown (HTTP 429). Please try again later.');
      }
      final last = _lastRequestAt;
      if (last != null) {
        final elapsed = DateTime.now().difference(last);
        if (elapsed < _spacing) {
          await Future<void>.delayed(_spacing - elapsed);
        }
      }
      final recentBlock = _blockedUntil;
      if (recentBlock != null && DateTime.now().isBefore(recentBlock)) {
        throw const FormatException(
          'TMDB requested a cooldown (HTTP 429). Please try again later.');
      }
      _lastRequestAt = DateTime.now();
    });
    _paceQueue = turn.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    await turn;
  }

  Duration _retryAfter(String? value) {
    if (value == null || value.trim().isEmpty) return _fallbackCooldown;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) {
      return Duration(seconds: seconds.clamp(1, 1800).toInt());
    }
    try {
      final date = HttpDate.parse(value.trim());
      final delta = date.difference(DateTime.now().toUtc());
      return delta.isNegative ? _fallbackCooldown
          : Duration(seconds: delta.inSeconds.clamp(1, 1800).toInt());
    } catch (_) {
      return _fallbackCooldown;
    }
  }

  void _remember(String cacheKey, Map<String, dynamic> response, Duration ttl) {
    // Cache only success bodies, not credentials or URLs including API keys.
    // Keep at most 100 items in the short-lived in-memory cache.
    if (_cache.length >= 100) _cache.remove(_cache.keys.first);
    _cache[cacheKey] = _DiscoverCacheEntry(
      response, DateTime.now().add(ttl));
  }

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
    // Never mix results between different accounts or credentials.
    _credentialRevision++;
    _cache.clear();
    _inFlight.clear();
  }

  Future<Map<String, dynamic>> _request(
      String endpoint, Map<String, String> params, String storedKey) async {
    // Query-parameter cache keys never contain a TMDB credential.
    final id = '$_credentialRevision:$endpoint:${Uri(queryParameters: params).query}';
    final cached = _cache[id];
    if (cached != null) {
      if (DateTime.now().isBefore(cached.expires)) return cached.value;
      _cache.remove(id);
    }
    final pending = _inFlight[id];
    if (pending != null) return pending;

    final ttl = endpoint.startsWith('discover/')
        ? const Duration(minutes: 15) : const Duration(hours: 24);
    final request = _sendRequest(endpoint, params, storedKey);
    _inFlight[id] = request;
    try {
      final data = await request;
      if (id.startsWith('$_credentialRevision:')) _remember(id, data, ttl);
      return data;
    } finally {
      if (identical(_inFlight[id], request)) _inFlight.remove(id);
    }
  }

  Future<Map<String, dynamic>> _sendRequest(
      String endpoint, Map<String, String> params, String storedKey) async {
    await _paceRequest();
    final bearer = storedKey.startsWith('eyJ') ||
        storedKey.startsWith('Bearer ');
    final key = storedKey.startsWith('Bearer ')
        ? storedKey.substring(7).trim() : storedKey;
    final query = <String, String>{...params};
    if (!bearer) query['api_key'] = key;
    final uri = Uri.https('api.themoviedb.org', '/3/$endpoint', query);
    http.Response response;
    try {
      response = await (httpGetOverride == null
          ? http.get(uri, headers: {
              'Accept': 'application/json',
              if (bearer) 'Authorization': 'Bearer $key',
            })
          : httpGetOverride!(uri, {
              'Accept': 'application/json',
              if (bearer) 'Authorization': 'Bearer $key',
            })).timeout(const Duration(seconds: 20));
    } catch (_) {
      // Never include credentials, headers, request URL or trace in errors.
      throw const FormatException('Cannot connect to TMDB. Check internet access.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FormatException('TMDB API key rejected. Check Discover settings.');
    }
    if (response.statusCode == 429) {
      final until = DateTime.now().add(
        _retryAfter(response.headers['retry-after']));
      if (_blockedUntil == null || until.isAfter(_blockedUntil!)) {
        _blockedUntil = until;
      }
      // No automatic retries; obey TMDB's advice to stop and cool down.
      throw const FormatException(
        'TMDB requested fewer requests (HTTP 429). Try again after cooldown.');
    }
    if (response.statusCode != 200) {
      throw FormatException('TMDB returned HTTP ${response.statusCode}.');
    }
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) return parsed;
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
      ((response['total_pages'] as num?)?.toInt() ?? 1).clamp(1, 500).toInt(),
      (response['total_results'] as num?)?.toInt() ?? 0,
    );
  }

  /// Match the selected show without guessing on ambiguous same-name results.
  /// Exact title and starting year are required when available.
  @visibleForTesting
  static int? selectSeriesId(
      List<dynamic> results, String requestedTitle, int? startYear) {
    String normalized(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    final wanted = normalized(requestedTitle);
    for (final raw in results) {
      if (raw is! Map) continue;
      final id = (raw['id'] as num?)?.toInt();
      final name = raw['name']?.toString() ?? '';
      final date = raw['first_air_date']?.toString() ?? '';
      final firstYear = date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;
      if (id == null || id <= 0 || normalized(name) != wanted) continue;
      if (startYear != null && firstYear != startYear) continue;
      return id;
    }
    return null;
  }

  /// A bounded, user-initiated fallback when BestSimilar did not find shows.
  /// Every request reuses the same TMDB spacing, caching and 429 cooldown.
  Future<List<DiscoverTitle>> relatedSeries({
    required String title,
    int? startYear,
    String? imdbId,
    int? tmdbId,
    int? verifiedTvdbTmdbId,
    int minimumResults = 6,
  }) async {
    final key = await readKey();
    if (key.trim().isEmpty) return const [];

    int? id = tmdbId != null && tmdbId > 0 ? tmdbId : verifiedTvdbTmdbId;
    if (id == null && imdbId != null &&
        RegExp(r'^tt\d+$').hasMatch(imdbId)) {
      final found = await _request('find/$imdbId',
          const {'external_source': 'imdb_id'}, key);
      final tv = (found['tv_results'] as List<dynamic>?) ?? const [];
      id = selectSeriesId(tv, title, startYear);
    }
    if (id == null) {
      final results = await _request('search/tv', {
        'query': title,
        if (startYear != null) 'first_air_date_year': '$startYear',
      }, key);
      id = selectSeriesId(
        results['results'] as List<dynamic>? ?? const [], title, startYear);
    }
    if (id == null) return const [];

    final seen = <int>{id};
    final rows = <DiscoverTitle>[];
    void collect(Map<String, dynamic> response) {
      final candidates = response['results'] as List<dynamic>? ?? const [];
      for (final raw in candidates) {
        if (raw is! Map<String, dynamic>) continue;
        final candidate = DiscoverTitle.parse(raw, DiscoverType.series);
        if (candidate.tmdbId <= 0 ||
            candidate.title.trim().isEmpty ||
            candidate.poster == null ||
            !seen.add(candidate.tmdbId)) continue;
        rows.add(candidate);
        if (rows.length >= 18) break;
      }
    }

    collect(await _request('tv/$id/recommendations', const {'page': '1'}, key));
    if (rows.length < minimumResults) {
      collect(await _request('tv/$id/similar', const {'page': '1'}, key));
    }
    return rows.take(18).toList();
  }

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

class _DiscoverCacheEntry {
  final Map<String, dynamic> value;
  final DateTime expires;
  const _DiscoverCacheEntry(this.value, this.expires);
}
).hasMatch(imdbId)) {
      final found = await _request('find/$imdbId',
          const {'external_source': 'imdb_id'}, key);
      final tv = (found['tv_results'] as List<dynamic>?) ?? const [];
      id = selectSeriesId(tv, title, startYear);
    }
    if (id == null) {
      final results = await _request('search/tv', {
        'query': title,
        if (startYear != null) 'first_air_date_year': '$startYear',
      }, key);
      id = selectSeriesId(
        results['results'] as List<dynamic>? ?? const [], title, startYear);
    }
    if (id == null) return const [];

    final seen = <int>{id};
    final rows = <DiscoverTitle>[];
    void collect(Map<String, dynamic> response) {
      final candidates = response['results'] as List<dynamic>? ?? const [];
      for (final raw in candidates) {
        if (raw is! Map<String, dynamic>) continue;
        final candidate = DiscoverTitle.parse(raw, DiscoverType.series);
        if (candidate.tmdbId <= 0 ||
            candidate.title.trim().isEmpty ||
            candidate.poster == null ||
            !seen.add(candidate.tmdbId)) continue;
        rows.add(candidate);
        if (rows.length >= 18) break;
      }
    }

    collect(await _request('tv/$id/recommendations', const {'page': '1'}, key));
    if (rows.length < minimumResults) {
      collect(await _request('tv/$id/similar', const {'page': '1'}, key));
    }
    return rows.take(18).toList();
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

class _DiscoverCacheEntry {
  final Map<String, dynamic> value;
  final DateTime expires;
  const _DiscoverCacheEntry(this.value, this.expires);
}
