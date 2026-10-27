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
  final String titleQuery;
  final int? fromYear;
  final int? toYear;
  final String? country;
  final String? originalLanguage;
  final String sort;
  final int page;
  const DiscoverFilters({
    this.type = DiscoverType.movie,
    this.titleQuery = '',
    this.fromYear,
    this.toYear,
    this.country,
    this.originalLanguage,
    this.sort = 'popularity.desc',
    this.page = 1,
  });

  /// A non-empty title uses TMDB's dedicated /search API rather than
  /// adding an unsupported query parameter to the /discover endpoint.
  bool get hasTitleQuery => titleQuery.trim().isNotEmpty;

  DiscoverFilters withPage(int requestedPage) => DiscoverFilters(
    type: type,
    titleQuery: titleQuery,
    fromYear: fromYear,
    toYear: toYear,
    country: country,
    originalLanguage: originalLanguage,
    sort: sort,
    page: requestedPage,
  );

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
    // TMDB search supports text and paging, but not discover-only
    // sort/country/language filters. Enforce those on the returned rows.
    // TV search's "year" includes episode-airing years (unlike first_air_date).
    if (hasTitleQuery) {
      return <String, String>{
        'page': '$page',
        'language': 'en-US',
        'include_adult': 'false',
        'query': titleQuery.trim(),
        if (first != null && last == first)
          if (type == DiscoverType.series) 'year': '$first'
          else 'primary_release_year': '$first',
      };
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
      hasTitleQuery
        ? (type == DiscoverType.series ? '/3/search/tv' : '/3/search/movie')
        : (type == DiscoverType.series ? '/3/discover/tv' : '/3/discover/movie'),
      toQuery());
}

/// A real TMDB person, not a movie title containing an actor's name.
class TmdbPerson {
  final int id;
  final String name;
  final String? photo;
  final String department;
  const TmdbPerson({
    required this.id,
    required this.name,
    this.photo,
    this.department = '',
  });

  factory TmdbPerson.parse(Map<String, dynamic> row) {
    final path = row['profile_path']?.toString() ?? '';
    return TmdbPerson(
      id: (row['id'] as num?)?.toInt() ?? 0,
      name: row['name']?.toString() ?? '',
      photo: path.isEmpty ? null : 'https://image.tmdb.org/t/p/w185$path',
      department: row['known_for_department']?.toString() ?? '',
    );
  }
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
  final List<String> originCountries;
  final String? originalLanguage;

  const DiscoverTitle({
    required this.tmdbId,
    required this.title,
    required this.type,
    this.poster,
    this.premiereYear,
    this.rating = 0,
    this.overview = '',
    this.genreIds = const [],
    this.originCountries = const [],
    this.originalLanguage,
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
      originCountries: (json['origin_country'] as List<dynamic>? ?? const [])
          .map((x) => x.toString()).toList(),
      originalLanguage: json['original_language']?.toString(),
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

    final ttl = (endpoint.startsWith('discover/') ||
        endpoint.startsWith('search/'))
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

  /// Search results contain the language and premiere date, and TV search
  /// results also contain origin_country. For movies, origin country may
  /// require an individual /movie/{id} metadata lookup (only if selected).
  @visibleForTesting
  static bool matchesTitleFilters(
      Map<String, dynamic> item, DiscoverFilters filters,
      {Map<String, dynamic>? movieDetails}) {
    if (filters.originalLanguage != null &&
        filters.originalLanguage!.isNotEmpty &&
        item['original_language']?.toString() != filters.originalLanguage) {
      return false;
    }
    if (filters.sort == 'vote_average.desc' &&
        ((item['vote_count'] as num?)?.toInt() ?? 0) < 100) {
      return false;
    }

    final first = filters.fromYear ?? filters.toYear;
    final last = filters.toYear ?? filters.fromYear;
    // With exactly one TV year, /search/tv?year= filters against premiere
    // AND episode-airing dates. Never discard returning older series because
    // their first_air_date precedes the year the user searched.
    if (first != null && last != null &&
        !(filters.type == DiscoverType.series && first == last)) {
      final field = filters.type == DiscoverType.series
          ? 'first_air_date' : 'release_date';
      final date = item[field]?.toString() ?? '';
      final year = date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;
      if (year == null || year < first || year > last) return false;
    }

    final country = filters.country;
    if (country != null && country.isNotEmpty) {
      if (filters.type == DiscoverType.series) {
        final origins = item['origin_country'];
        if (origins is! List || !origins.contains(country)) return false;
      } else {
        final origins = item['origin_country'];
        final details = movieDetails;
        final direct = origins is List && origins.contains(country);
        final detailOrigins = details?['origin_country'];
        final verifiedOrigin = detailOrigins is List &&
            detailOrigins.contains(country);
        final production = details?['production_countries'];
        final verifiedProduction = production is List &&
            production.any((x) => x is Map && x['iso_3166_1'] == country);
        if (!direct && !verifiedOrigin && !verifiedProduction) return false;
      }
    }
    return true;
  }

  @visibleForTesting
  static List<Map<String, dynamic>> sortSearchedTitles(
      List<Map<String, dynamic>> items, String sort) {
    final result = List<Map<String, dynamic>>.of(items);
    final field = switch (sort) {
      'vote_average.desc' => 'vote_average',
      'vote_count.desc' => 'vote_count',
      _ => 'popularity',
    };
    result.sort((a, b) {
      final left = (a[field] as num?)?.toDouble() ?? 0;
      final right = (b[field] as num?)?.toDouble() ?? 0;
      final comparison = right.compareTo(left);
      // Stable for equal scores, preserving TMDB's relative relevance.
      return comparison;
    });
    return result;
  }

  Future<DiscoverResults> browse(DiscoverFilters filters) async {
    final key = await readKey();
    if (key.isEmpty) {
      throw const FormatException('Enter your TMDB key in Discover settings.');
    }

    final type = filters.type == DiscoverType.movie ? 'movie' : 'tv';
    final endpoint = filters.hasTitleQuery ? 'search/$type' : 'discover/$type';
    final response = await _request(endpoint, filters.toQuery(), key);
    final allRows = (response['results'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>().toList();
    List<Map<String, dynamic>> rows;
    if (!filters.hasTitleQuery) {
      rows = allRows;  // Existing server-filtered Discover remains untouched.
    } else {
      rows = [];
      for (final item in allRows) {
        // Skip country-only metadata requests for movies already excluded by
        // language, premiere year, or minimum vote-count.
        final preCountry = DiscoverFilters(
          type: filters.type, titleQuery: filters.titleQuery,
          fromYear: filters.fromYear, toYear: filters.toYear,
          originalLanguage: filters.originalLanguage,
          sort: filters.sort, page: filters.page,
        );
        if (!matchesTitleFilters(item, preCountry)) continue;
        Map<String, dynamic>? details;
        if (filters.type == DiscoverType.movie &&
            filters.country != null && filters.country!.isNotEmpty &&
            item['origin_country'] is! List) {
          final id = (item['id'] as num?)?.toInt();
          if (id == null || id <= 0) continue;
          // Only paid-for by deliberate movie+country+text intersection.
          // Maximum one paced/cached details lookup per search result (20).
          details = await _request('movie/$id', const {}, key);
        }
        if (matchesTitleFilters(item, filters, movieDetails: details)) {
          rows.add(item);
        }
      }
      rows = sortSearchedTitles(rows, filters.sort);
    }
    final titles = rows
        .map((item) => DiscoverTitle.parse(item, filters.type))
        .where((item) => item.tmdbId > 0).toList();
    return DiscoverResults(
      titles,
      (response['page'] as num?)?.toInt() ?? filters.page,
      ((response['total_pages'] as num?)?.toInt() ?? 1).clamp(1, 500).toInt(),
      (response['total_results'] as num?)?.toInt() ?? 0,
    );
  }

  /// Resolve a clicked actor/actress to TMDB PERSON records (never a
  /// title search); show multiple choices when names are ambiguous.
  Future<List<TmdbPerson>> searchPeople(String name) async {
    if (name.trim().isEmpty) return const [];
    final key = await readKey();
    if (key.isEmpty) {
      throw const FormatException('Configure your TMDB key in Discover first.');
    }
    final response = await _request('search/person', {
      'query': name.trim(), 'page': '1', 'include_adult': 'false',
    }, key);
    final rows = (response['results'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TmdbPerson.parse)
        .where((p) => p.id > 0 && p.name.isNotEmpty)
        .toList();
    final normalizedName = name.trim().toLowerCase();
    rows.sort((a, b) {
      final aExact = a.name.toLowerCase() == normalizedName ? 0 : 1;
      final bExact = b.name.toLowerCase() == normalizedName ? 0 : 1;
      return aExact.compareTo(bExact);
    });
    return rows.take(10).toList();
  }

  /// TMDB combined_credits includes credited MOVIES and TV series, sorted
  /// by recency rather than title hits or actors with similar names.
  Future<List<DiscoverTitle>> personCombinedCredits(int personId) async {
    if (personId <= 0) return const [];
    final key = await readKey();
    if (key.isEmpty) {
      throw const FormatException('Configure your TMDB key in Discover first.');
    }
    final data = await _request('person/$personId/combined_credits',
        const {'language': 'en-US'}, key);
    final rows = <DiscoverTitle>[];
    final seen = <String>{};
    for (final raw in (data['cast'] as List<dynamic>? ?? const [])) {
      if (raw is! Map<String, dynamic> || raw['adult'] == true) continue;
      final medium = raw['media_type']?.toString();
      if (medium != 'movie' && medium != 'tv') continue;
      final item = DiscoverTitle.parse(raw,
          medium == 'tv' ? DiscoverType.series : DiscoverType.movie);
      final key = '$medium:${item.tmdbId}';
      if (item.tmdbId <= 0 || !seen.add(key)) continue;
      rows.add(item);
    }
    rows.sort((a, b) {
      final dateOrder = (b.premiereYear ?? 0).compareTo(a.premiereYear ?? 0);
      return dateOrder != 0 ? dateOrder : b.rating.compareTo(a.rating);
    });
    return rows.take(120).toList();
  }

  /// Card-level metadata. Only called for a tiny, visible group of similar
  /// titles; uses the existing paced/429-safe/24h cached TMDB requests.
  Future<Map<String, dynamic>> similarCardDetails({
    required String title,
    required int? year,
    required String mediaType,
    int? tmdbId,
  }) async {
    final key = await readKey();
    if (key.isEmpty) return const {};
    final type = mediaType == 'series' ? 'tv' :
        mediaType == 'movie' ? 'movie' : null;
    if (type == null) return const {};
    int? id = tmdbId;
    if (id == null || id <= 0) {
      final search = await _request('search/$type', {
        'query': title,
        if (year != null)
          if (type == 'tv') 'first_air_date_year': '$year'
          else 'primary_release_year': '$year',
        'page': '1',
      }, key);
      final items = search['results'] as List<dynamic>? ?? const [];
      final normalized = title.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'), ' ').trim();
      for (final candidate in items) {
        if (candidate is! Map<String, dynamic>) continue;
        final candidateTitle = (type == 'tv' ? candidate['name'] :
            candidate['title'])?.toString() ?? '';
        if (candidateTitle.toLowerCase().replaceAll(
            RegExp(r'[^a-z0-9]+'), ' ').trim() != normalized) continue;
        final date = (type == 'tv' ? candidate['first_air_date'] :
            candidate['release_date'])?.toString() ?? '';
        final firstYear = date.length >= 4
            ? int.tryParse(date.substring(0, 4)) : null;
        if (year != null && firstYear != year) continue;
        id = (candidate['id'] as num?)?.toInt();
        break;
      }
    }
    if (id == null || id <= 0) return const {};
    return _request('$type/$id', const {}, key);
  }

  /// Provider catalogs are requested only when Networks is opened and
  /// cached using this service's normal 24h provider-response cache.
  Future<Map<String, dynamic>> networkProviderCatalog(DiscoverType type) async {
    final key = await readKey();
    if (key.trim().isEmpty) {
      throw const FormatException('Configure your TMDB key in Discover first.');
    }
    final mediaType = type == DiscoverType.movie ? 'movie' : 'tv';
    return _request('watch/providers/$mediaType',
        const {'language': 'en-US'}, key);
  }

  /// A single provider/network-filtered Discover page. Reuses normal
  /// TMDB 700ms pacing, 429 cooldown, caching and request deduplication.
  Future<DiscoverResults> networkDiscover(
      DiscoverType type, Map<String, String> parameters) async {
    final key = await readKey();
    if (key.trim().isEmpty) {
      throw const FormatException('Configure your TMDB key in Discover first.');
    }
    if (parameters['with_watch_providers'] == null &&
        parameters['with_networks'] == null) {
      throw const FormatException('Select a real streaming provider or TV network.');
    }
    final mediaType = type == DiscoverType.movie ? 'movie' : 'tv';
    final data = await _request('discover/$mediaType', parameters, key);
    final rows = data['results'] as List<dynamic>? ?? const [];
    final seen = <int>{};
    final titles = <DiscoverTitle>[];
    for (final raw in rows) {
      if (raw is! Map<String, dynamic>) continue;
      final title = DiscoverTitle.parse(raw, type);
      if (title.tmdbId > 0 && seen.add(title.tmdbId)) titles.add(title);
    }
    return DiscoverResults(
      titles,
      (data['page'] as num?)?.toInt() ?? 1,
      ((data['total_pages'] as num?)?.toInt() ?? 1).clamp(1, 500).toInt(),
      (data['total_results'] as num?)?.toInt() ?? 0,
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
