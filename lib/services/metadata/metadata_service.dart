import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/addon/addon.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_detail.dart';
import '../player/player_debug_telemetry.dart';

class ResolvedAddonMetadata {
  final MovieDetail detail;
  final String baseUrl;
  final String type;

  const ResolvedAddonMetadata({
    required this.detail,
    required this.baseUrl,
    required this.type,
  });
}

/// Generic service for any Stremio-protocol addon.
/// All methods are static — provide the addon's base URL and they hit the
/// standard Stremio endpoints (catalog, meta, search).
class MetadataService {
  MetadataService._();

  @visibleForTesting
  static Future<http.Response> Function(Uri)? catalogGetOverride;

  @visibleForTesting
  static Future<http.Response> Function(Uri)? manifestGetOverride;

  @visibleForTesting
  static Future<http.Response> Function(Uri)? metaGetOverride;

  static final Map<String, List<Movie>> _catalogCache = {};
  static final Map<String, MovieDetail> _metaCache = {};

  /// Clear the memory cache (e.g. when addons change)
  static void clearCache() {
    _catalogCache.clear();
    _metaCache.clear();
  }

  // ── Manifest ──────────────────────────────────────────────────────────

  /// Fetch and parse a manifest from any Stremio addon.
  static Future<AddonManifest> fetchManifest(String baseUrl) async {
    final url = '$baseUrl/manifest.json';
    final uri = Uri.parse(url);
    final response = await (manifestGetOverride == null
        ? http.get(uri, headers: {'Accept': 'application/json'})
        : manifestGetOverride!(uri)).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch manifest (${response.statusCode})',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return AddonManifest.fromJson(json);
  }

  // ── Catalog ───────────────────────────────────────────────────────────

  /// Fetch catalog items from any addon.
  static Future<List<Movie>> fetchCatalog({
    required String baseUrl,
    required String type,
    required String catalogId,
    String? genre,
    int? skip,
    String? searchTerm,
    Map<String, String> extra = const {},
    bool forceRefresh = false,
  }) async {
    final effectiveBaseUrl = (baseUrl.trim().isEmpty || !baseUrl.startsWith('http'))
        ? 'https://v3-cinemeta.strem.io'
        : (baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);

    // Stremio's extra arguments form a path segment, not URI query params.
    final extras = <String, String>{};
    if (genre != null && genre.isNotEmpty) extras['genre'] = genre;
    if (searchTerm != null && searchTerm.isNotEmpty) extras['search'] = searchTerm;
    if (skip != null && skip > 0) extras['skip'] = '$skip';
    extras.addAll(extra);
    final extraPath = extras.isEmpty
        ? ''
        : '/${extras.entries.map((entry) =>
            '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}').join('&')}';
    final url = '$effectiveBaseUrl/catalog/${Uri.encodeComponent(type)}/${Uri.encodeComponent(catalogId)}$extraPath.json';

    if (!forceRefresh && _catalogCache.containsKey(url)) {
      return List.from(_catalogCache[url]!);
    }

    final uri = Uri.parse(url);
    final request = catalogGetOverride == null
        ? http.get(uri, headers: {'Accept': 'application/json'})
        : catalogGetOverride!(uri);
    // Personalized feeds refresh on each Home visit without blocking forever.
    final response = await request.timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Catalog fetch failed (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final metas = decoded['metas'] is List
        ? decoded['metas']
        : decoded['metasDetailed'];
    final result = <Movie>[];
    if (metas is List) {
      for (final entry in metas) {
        if (entry is! Map) continue;
        try {
          final movie = Movie.fromJson(
              Map<String, dynamic>.from(entry), effectiveBaseUrl,
              fallbackType: type);
          if (movie.id.trim().isNotEmpty && movie.name.trim().isNotEmpty &&
              movie.name != 'Unknown') {
            result.add(movie);
          }
        } catch (_) {
          // Ignore malformed preview entries instead of dropping the catalog.
        }
      }
    }

    _catalogCache[url] = result;
    return List.from(result);
  }

  /// Get full Native EPG metadata, retaining each channel's programme videos.
  /// Live stream requests use the channel ID, never a programme ID.
  static Future<List<MovieDetail>> fetchGuideCatalog({
    required String baseUrl,
    required String catalogId,
    required DateTime utcDay,
    int skip = 0,
  }) async {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/+

  /// Search is an optional catalog extra, not a separate Stremio resource.
  static Future<List<Movie>> search({
    required String baseUrl,
    required String type,
    required String catalogId,
    required String query,
  }) async {
    if (query.trim().isEmpty) return const [];
    try {
      return await fetchCatalog(
        baseUrl: baseUrl,
        type: type,
        catalogId: catalogId,
        searchTerm: query.trim(),
      );
    } catch (_) {
      // Not every provider implements search, even with a valid catalog.
      return const [];
    }
  }

  // ── Meta (full details) ───────────────────────────────────────────────

  /// Fetch detailed metadata (background, description, rating, genres, etc.)
  static Future<MovieDetail?> fetchMeta({
    required String baseUrl,
    required String type,
    required String imdbId,
  }) async {
    final effectiveBaseUrl = (baseUrl.trim().isEmpty || !baseUrl.startsWith('http'))
        ? 'https://v3-cinemeta.strem.io'
        : (baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);

    final encodedId = Uri.encodeComponent(imdbId);
    final url = '$effectiveBaseUrl/meta/$type/$encodedId.json';

    if (_metaCache.containsKey(url)) {
      return _metaCache[url];
    }

    PlayerDebugTelemetry.record('addon_meta_fetch_started');
    http.Response response;
    try {
      response = await (metaGetOverride == null
              ? http.get(Uri.parse(url), headers: {'Accept': 'application/json'})
              : metaGetOverride!(Uri.parse(url)))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      PlayerDebugTelemetry.record('addon_meta_request_failed', failure: true);
      return null;
    }
    if (response.statusCode != 200) {
      PlayerDebugTelemetry.record('addon_meta_not_found', failure: true);
      return null;
    }
    final bodyStr = response.body.trim();
    if (bodyStr.isEmpty) {
      PlayerDebugTelemetry.record('addon_meta_empty', failure: true);
      return null;
    }
    try {
      final decoded = jsonDecode(bodyStr) as Map<String, dynamic>;
      final payload = decoded['meta'] as Map<String, dynamic>?;
      if (payload == null) {
        PlayerDebugTelemetry.record('addon_meta_empty', failure: true);
        return null;
      }
      final result = MovieDetail.fromJson(payload);
      if (result.id.trim().isEmpty || result.name.trim().isEmpty ||
          result.name == 'Unknown') {
        PlayerDebugTelemetry.record('addon_meta_invalid', failure: true);
        return null;
      }
      _metaCache[url] = result;
      PlayerDebugTelemetry.record('addon_meta_loaded');
      return result;
    } catch (_) {
      PlayerDebugTelemetry.record('addon_meta_invalid', failure: true);
      return null;
    }
  }

  /// A catalog addon may not implement meta, or may return an incomplete
  /// metadata payload. Resolve from the authoritative IMDb ID first, and only
  /// then use a conservative title/year match. Never guess a stream ID.
  static Future<ResolvedAddonMetadata?> resolveCatalogMeta({
    required String baseUrl,
    required String type,
    required String id,
    required String title,
    int? year,
    bool sourceSupportsMeta = true,
    List<String> compatibleMetaProviders = const [],
  }) async {
    const cinemeta = 'https://v3-cinemeta.strem.io';

    Future<ResolvedAddonMetadata?> load(String source, String mediaType,
        String mediaId) async {
      final detail = await fetchMeta(
        baseUrl: source,
        type: mediaType,
        imdbId: mediaId,
      );
      return detail == null
          ? null
          : ResolvedAddonMetadata(
              detail: detail,
              baseUrl: source,
              type: detail.type.trim().isNotEmpty ? detail.type : mediaType,
            );
    }

    if (sourceSupportsMeta) {
      final primary = await load(baseUrl, type, id);
      if (primary != null) return primary;
    }

    PlayerDebugTelemetry.record('addon_meta_fallback_started');
    try {
      final canonicalType = Movie.canonicalType(type);
      final fallbackType = canonicalType == 'anime'
          ? 'series'
          : (canonicalType == 'unknown' ? 'movie' : canonicalType);

      // An IMDb identifier is portable between catalog and metadata addons.
      // A provider-specific identifier is not; never send it to Cinemeta.
      if (RegExp(r'^tt[0-9]+$').hasMatch(id) &&
          baseUrl.replaceAll(RegExp(r'/+$'), '') != cinemeta) {
        final byId = await load(cinemeta, fallbackType, id);
        if (byId != null && byId.detail.id == id) {
          PlayerDebugTelemetry.record('addon_meta_fallback_resolved');
          return byId;
        }
      }

      // A declared resource-specific idPrefix makes even custom IDs
      // eligible for another metadata addon. The caller has already filtered
      // providers through each manifest's supportsRequest('meta', type, id).
      for (final provider in compatibleMetaProviders) {
        if (provider == baseUrl || provider == cinemeta) continue;
        final byId = await load(provider, fallbackType, id);
        if (byId != null && byId.detail.id == id) {
          PlayerDebugTelemetry.record('addon_meta_fallback_resolved');
          return byId;
        }
      }

      final match = await findMovieByTitle(
        title: title,
        type: fallbackType,
        year: year,
      );
      if (match == null) return null;

      String normalize(String value) =>
          value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
      final requestedName = normalize(title);
      if (requestedName.isEmpty || normalize(match.name) != requestedName ||
          Movie.canonicalType(match.type) != fallbackType) {
        return null;
      }
      final matchedYear = RegExp(r'[0-9]{4}').firstMatch(match.year ?? '');
      if (year != null && matchedYear != null &&
          int.tryParse(matchedYear.group(0)!) != year) {
        return null;
      }

      final resolved = await load(match.addonBaseUrl, match.type, match.id);
      if (resolved != null) {
        PlayerDebugTelemetry.record('addon_meta_fallback_resolved');
      }
      return resolved;
    } catch (_) {
      // Provider search may be offline or unsupported; Details handles null.
      return null;
    }
  }

  /// Searches active addons (or Cinemeta fallback) to resolve a title into a real Movie
  static Future<Movie?> findMovieByTitle({
    required String title,
    String? type,
    int? year,
    String? preferredBaseUrl,
  }) async {
    final query = title.trim();
    if (query.isEmpty) return null;

    final targetBaseUrl = (preferredBaseUrl != null &&
            preferredBaseUrl.startsWith('http') &&
            !preferredBaseUrl.contains('bestsimilar'))
        ? preferredBaseUrl
        : 'https://v3-cinemeta.strem.io';

    final isPreferredTv = (type == 'series' || type == 'tv' || type == 'anime');
    final firstType = isPreferredTv ? 'series' : 'movie';
    final secondType = isPreferredTv ? 'movie' : 'series';

    // Search both types to compare candidates across series and movie catalogs
    final results = await Future.wait([
      search(baseUrl: targetBaseUrl, type: firstType, catalogId: 'top', query: query)
          .catchError((_) => <Movie>[]),
      search(baseUrl: targetBaseUrl, type: secondType, catalogId: 'top', query: query)
          .catchError((_) => <Movie>[]),
    ]);

    final allCandidates = <Movie>[...results[0], ...results[1]];
    if (allCandidates.isEmpty) return null;

    final qLower = query.toLowerCase();

    // Scoring:
    // +100 for exact title match
    // +60 for exact year match (or year in range e.g. 2013-2018)
    // +20 for matching preferred type
    // +30 for title startsWith
    Movie? bestMatch;
    int highestScore = -1;

    for (final c in allCandidates) {
      int score = 0;
      final cName = c.name.toLowerCase().trim();
      final cYear = (c.year ?? '').trim();

      if (cName == qLower) {
        score += 100;
      } else if (cName.startsWith(qLower)) {
        score += 30;
      }

      if (year != null && cYear.isNotEmpty) {
        if (cYear.startsWith('$year') || cYear.contains('$year')) {
          score += 60;
        }
      }

      if (type != null) {
        final isCTv = (c.type == 'series' || c.type == 'tv' || c.type == 'anime');
        if (isCTv == isPreferredTv) {
          score += 20;
        }
      }

      if (score > highestScore) {
        highestScore = score;
        bestMatch = c;
      }
    }

    return bestMatch ?? allCandidates.first;
  }
}
), '');
    final parsed = Uri.tryParse(root);
    if (parsed == null || (parsed.scheme != 'https' && parsed.scheme != 'http') ||
        parsed.host.isEmpty) {
      throw const FormatException('Invalid Stremio guide addon URL');
    }
    final day = utcDay.toUtc().toIso8601String().substring(0, 10);
    final extras = <String, String>{'date': day, if (skip > 0) 'skip': '$skip'};
    final segment = extras.entries.map((e) =>
        '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
    final uri = Uri.parse(
        '$root/catalog/tv/${Uri.encodeComponent(catalogId)}/$segment.json');
    final response = await (catalogGetOverride == null
            ? http.get(uri, headers: {'Accept': 'application/json'})
            : catalogGetOverride!(uri))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Guide fetch failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body);
    if (payload is! Map || payload['metasDetailed'] is! List) return [];
    final result = <MovieDetail>[];
    for (final entry in payload['metasDetailed'] as List) {
      if (entry is! Map) continue;
      try {
        final detail = MovieDetail.fromJson(Map<String, dynamic>.from(entry));
        if (detail.id.trim().isNotEmpty && detail.name.trim().isNotEmpty) {
          result.add(detail);
        }
      } catch (_) {
        // Malformed guide rows must not discard valid channels.
      }
    }
    return result;
  }

  // ── Search ────────────────────────────────────────────────────────────

  /// Search is an optional catalog extra, not a separate Stremio resource.
  static Future<List<Movie>> search({
    required String baseUrl,
    required String type,
    required String catalogId,
    required String query,
  }) async {
    if (query.trim().isEmpty) return const [];
    try {
      return await fetchCatalog(
        baseUrl: baseUrl,
        type: type,
        catalogId: catalogId,
        searchTerm: query.trim(),
      );
    } catch (_) {
      // Not every provider implements search, even with a valid catalog.
      return const [];
    }
  }

  // ── Meta (full details) ───────────────────────────────────────────────

  /// Fetch detailed metadata (background, description, rating, genres, etc.)
  static Future<MovieDetail?> fetchMeta({
    required String baseUrl,
    required String type,
    required String imdbId,
  }) async {
    final effectiveBaseUrl = (baseUrl.trim().isEmpty || !baseUrl.startsWith('http'))
        ? 'https://v3-cinemeta.strem.io'
        : (baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);

    final encodedId = Uri.encodeComponent(imdbId);
    final url = '$effectiveBaseUrl/meta/$type/$encodedId.json';

    if (_metaCache.containsKey(url)) {
      return _metaCache[url];
    }

    PlayerDebugTelemetry.record('addon_meta_fetch_started');
    http.Response response;
    try {
      response = await (metaGetOverride == null
              ? http.get(Uri.parse(url), headers: {'Accept': 'application/json'})
              : metaGetOverride!(Uri.parse(url)))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      PlayerDebugTelemetry.record('addon_meta_request_failed', failure: true);
      return null;
    }
    if (response.statusCode != 200) {
      PlayerDebugTelemetry.record('addon_meta_not_found', failure: true);
      return null;
    }
    final bodyStr = response.body.trim();
    if (bodyStr.isEmpty) {
      PlayerDebugTelemetry.record('addon_meta_empty', failure: true);
      return null;
    }
    try {
      final decoded = jsonDecode(bodyStr) as Map<String, dynamic>;
      final payload = decoded['meta'] as Map<String, dynamic>?;
      if (payload == null) {
        PlayerDebugTelemetry.record('addon_meta_empty', failure: true);
        return null;
      }
      final result = MovieDetail.fromJson(payload);
      if (result.id.trim().isEmpty || result.name.trim().isEmpty ||
          result.name == 'Unknown') {
        PlayerDebugTelemetry.record('addon_meta_invalid', failure: true);
        return null;
      }
      _metaCache[url] = result;
      PlayerDebugTelemetry.record('addon_meta_loaded');
      return result;
    } catch (_) {
      PlayerDebugTelemetry.record('addon_meta_invalid', failure: true);
      return null;
    }
  }

  /// A catalog addon may not implement meta, or may return an incomplete
  /// metadata payload. Resolve from the authoritative IMDb ID first, and only
  /// then use a conservative title/year match. Never guess a stream ID.
  static Future<ResolvedAddonMetadata?> resolveCatalogMeta({
    required String baseUrl,
    required String type,
    required String id,
    required String title,
    int? year,
    bool sourceSupportsMeta = true,
    List<String> compatibleMetaProviders = const [],
  }) async {
    const cinemeta = 'https://v3-cinemeta.strem.io';

    Future<ResolvedAddonMetadata?> load(String source, String mediaType,
        String mediaId) async {
      final detail = await fetchMeta(
        baseUrl: source,
        type: mediaType,
        imdbId: mediaId,
      );
      return detail == null
          ? null
          : ResolvedAddonMetadata(
              detail: detail,
              baseUrl: source,
              type: detail.type.trim().isNotEmpty ? detail.type : mediaType,
            );
    }

    if (sourceSupportsMeta) {
      final primary = await load(baseUrl, type, id);
      if (primary != null) return primary;
    }

    PlayerDebugTelemetry.record('addon_meta_fallback_started');
    try {
      final canonicalType = Movie.canonicalType(type);
      final fallbackType = canonicalType == 'anime'
          ? 'series'
          : (canonicalType == 'unknown' ? 'movie' : canonicalType);

      // An IMDb identifier is portable between catalog and metadata addons.
      // A provider-specific identifier is not; never send it to Cinemeta.
      if (RegExp(r'^tt[0-9]+$').hasMatch(id) &&
          baseUrl.replaceAll(RegExp(r'/+$'), '') != cinemeta) {
        final byId = await load(cinemeta, fallbackType, id);
        if (byId != null && byId.detail.id == id) {
          PlayerDebugTelemetry.record('addon_meta_fallback_resolved');
          return byId;
        }
      }

      // A declared resource-specific idPrefix makes even custom IDs
      // eligible for another metadata addon. The caller has already filtered
      // providers through each manifest's supportsRequest('meta', type, id).
      for (final provider in compatibleMetaProviders) {
        if (provider == baseUrl || provider == cinemeta) continue;
        final byId = await load(provider, fallbackType, id);
        if (byId != null && byId.detail.id == id) {
          PlayerDebugTelemetry.record('addon_meta_fallback_resolved');
          return byId;
        }
      }

      final match = await findMovieByTitle(
        title: title,
        type: fallbackType,
        year: year,
      );
      if (match == null) return null;

      String normalize(String value) =>
          value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
      final requestedName = normalize(title);
      if (requestedName.isEmpty || normalize(match.name) != requestedName ||
          Movie.canonicalType(match.type) != fallbackType) {
        return null;
      }
      final matchedYear = RegExp(r'[0-9]{4}').firstMatch(match.year ?? '');
      if (year != null && matchedYear != null &&
          int.tryParse(matchedYear.group(0)!) != year) {
        return null;
      }

      final resolved = await load(match.addonBaseUrl, match.type, match.id);
      if (resolved != null) {
        PlayerDebugTelemetry.record('addon_meta_fallback_resolved');
      }
      return resolved;
    } catch (_) {
      // Provider search may be offline or unsupported; Details handles null.
      return null;
    }
  }

  /// Searches active addons (or Cinemeta fallback) to resolve a title into a real Movie
  static Future<Movie?> findMovieByTitle({
    required String title,
    String? type,
    int? year,
    String? preferredBaseUrl,
  }) async {
    final query = title.trim();
    if (query.isEmpty) return null;

    final targetBaseUrl = (preferredBaseUrl != null &&
            preferredBaseUrl.startsWith('http') &&
            !preferredBaseUrl.contains('bestsimilar'))
        ? preferredBaseUrl
        : 'https://v3-cinemeta.strem.io';

    final isPreferredTv = (type == 'series' || type == 'tv' || type == 'anime');
    final firstType = isPreferredTv ? 'series' : 'movie';
    final secondType = isPreferredTv ? 'movie' : 'series';

    // Search both types to compare candidates across series and movie catalogs
    final results = await Future.wait([
      search(baseUrl: targetBaseUrl, type: firstType, catalogId: 'top', query: query)
          .catchError((_) => <Movie>[]),
      search(baseUrl: targetBaseUrl, type: secondType, catalogId: 'top', query: query)
          .catchError((_) => <Movie>[]),
    ]);

    final allCandidates = <Movie>[...results[0], ...results[1]];
    if (allCandidates.isEmpty) return null;

    final qLower = query.toLowerCase();

    // Scoring:
    // +100 for exact title match
    // +60 for exact year match (or year in range e.g. 2013-2018)
    // +20 for matching preferred type
    // +30 for title startsWith
    Movie? bestMatch;
    int highestScore = -1;

    for (final c in allCandidates) {
      int score = 0;
      final cName = c.name.toLowerCase().trim();
      final cYear = (c.year ?? '').trim();

      if (cName == qLower) {
        score += 100;
      } else if (cName.startsWith(qLower)) {
        score += 30;
      }

      if (year != null && cYear.isNotEmpty) {
        if (cYear.startsWith('$year') || cYear.contains('$year')) {
          score += 60;
        }
      }

      if (type != null) {
        final isCTv = (c.type == 'series' || c.type == 'tv' || c.type == 'anime');
        if (isCTv == isPreferredTv) {
          score += 20;
        }
      }

      if (score > highestScore) {
        highestScore = score;
        bestMatch = c;
      }
    }

    return bestMatch ?? allCandidates.first;
  }
}
