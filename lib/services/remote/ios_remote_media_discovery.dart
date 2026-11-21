import 'package:flutter/foundation.dart';

import '../addon/addon_manager.dart';
import '../metadata/tmdb_discover_service.dart';

/// Shared, typed interface to the SAME discovery services used by the UI.
/// Command documents never carry provider URLs, credentials or arbitrary code.
@immutable
class IosRemoteMediaQuery {
  const IosRemoteMediaQuery({
    required this.filters,
    required this.limit,
  });

  final DiscoverFilters filters;
  final int limit;

  static IosRemoteMediaQuery parse(Map<String, dynamic> args) {
    const keys = <String>{
      'type', 'query', 'fromYear', 'toYear', 'language', 'country',
      'genreId', 'sort', 'page', 'limit',
    };
    if (args.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('unknown_discovery_option');
    }
    final type = args['type'] ?? 'movie';
    final query = args['query'] ?? '';
    final from = args['fromYear'];
    final to = args['toYear'];
    final language = args['language'];
    final country = args['country'];
    final genre = args['genreId'];
    final sort = args['sort'] ?? 'popularity.desc';
    final page = args['page'] ?? 1;
    final limit = args['limit'] ?? 20;

    if (type != 'movie' && type != 'series' ||
        query is! String || query.length > 120 ||
        from != null && (from is! int || from < 1900 || from > 2100) ||
        to != null && (to is! int || to < 1900 || to > 2100) ||
        from is int && to is int && from > to ||
        language != null && (language is! String ||
            !RegExp(r'^[a-z]{2}$').hasMatch(language)) ||
        country != null && (country is! String ||
            !RegExp(r'^[A-Z]{2}$').hasMatch(country)) ||
        genre != null && (genre is! int || genre < 1 || genre > 99999) ||
        sort is! String ||
        page is! int || page < 1 || page > 500 ||
        limit is! int || limit < 1 || limit > 40) {
      throw const FormatException('invalid_discovery_filters');
    }

    final filters = DiscoverFilters(
      type: type == 'series' ? DiscoverType.series : DiscoverType.movie,
      titleQuery: query.trim(),
      fromYear: from is int ? from : null,
      toYear: to is int ? to : null,
      originalLanguage: language is String ? language : null,
      country: country is String ? country : null,
      genreId: genre is int ? genre : null,
      sort: sort,
      page: page,
    );
    // Validate genre, sorting and date policies using the existing UI service.
    filters.toQuery();
    return IosRemoteMediaQuery(filters: filters, limit: limit);
  }
}

abstract final class IosRemoteMediaDiscovery {
  /// Read-only discover/search. Does not imply a playable source exists.
  static Future<Map<String, Object?>> discover(
      Map<String, dynamic> args) async {
    try {
      final request = IosRemoteMediaQuery.parse(args);
      final results = await TmdbDiscoverService.instance
          .browse(request.filters).timeout(const Duration(seconds: 35));
      return <String, Object?>{
        'accepted': true,
        'source': 'tmdb_discover',
        'type': request.filters.type == DiscoverType.series
            ? 'series' : 'movie',
        'page': results.page,
        'totalPages': results.totalPages,
        'totalResults': results.totalResults,
        'returnedCount': results.titles.take(request.limit).length,
        'requiresStreamResolution': true,
        'items': results.titles.take(request.limit).map((item) =>
          <String, Object?>{
            'tmdbId': item.tmdbId,
            'type': item.type == DiscoverType.series ? 'series' : 'movie',
            'title': item.title,
            'year': item.premiereYear,
            'rating': item.rating,
            'originalLanguage': item.originalLanguage,
            'genreIds': item.genreIds.take(8).toList(),
            'releaseDate': item.premiereDate,
          }).toList(),
      };
    } on FormatException catch (error) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_or_unavailable_discovery',
        'errorClass': error.runtimeType.toString(),
      };
    } catch (error) {
      debugPrint('[IosRemoteMediaDiscovery] Discover: ${error.runtimeType}');
      return <String, Object?>{
        'accepted': false, 'reason': 'discovery_unavailable',
        'errorClass': error.runtimeType.toString(),
      };
    }
  }

  /// Search enabled installed Stremio addons, without remote-supplied URLs.
  static Future<Map<String, Object?>> searchAddons(
      Map<String, dynamic> args) async {
    const keys = <String>{'query', 'type', 'limit'};
    final query = args['query'];
    final type = args['type'] ?? 'all';
    final limit = args['limit'] ?? 20;
    if (args.keys.any((key) => !keys.contains(key)) ||
        query is! String || query.trim().length < 2 ||
        query.length > 120 ||
        !const {'all', 'movie', 'series', 'tv'}.contains(type) ||
        limit is! int || limit < 1 || limit > 40) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_addon_search',
      };
    }
    try {
      final sections = await AddonManager.instance.searchAll(query.trim())
          .timeout(const Duration(seconds: 40));
      final found = <String, Map<String, Object?>>{};
      for (final section in sections) {
        for (final movie in section.movies) {
          if (movie.id.isEmpty || movie.name.isEmpty) continue;
          if (type != 'all' && movie.type != type) continue;
          final identity = '${movie.type}:${movie.id}';
          found.putIfAbsent(identity, () => <String, Object?>{
            'id': movie.id,
            'type': movie.type,
            'title': movie.name,
            'year': movie.year,
            'tmdbId': movie.tmdbId,
            'language': movie.originalLanguage,
          });
          if (found.length >= limit) break;
        }
        if (found.length >= limit) break;
      }
      return <String, Object?>{
        'accepted': true,
        'query': query.trim(),
        'type': type,
        'returnedCount': found.length,
        'items': found.values.toList(),
      };
    } catch (error) {
      debugPrint('[IosRemoteMediaDiscovery] Addon search: ${error.runtimeType}');
      return <String, Object?>{
        'accepted': false, 'reason': 'addon_search_unavailable',
        'errorClass': error.runtimeType.toString(),
      };
    }
  }

  /// Resolve a specific TMDB result into the playback ID expected by Stremio.
  /// The caller must provide both the exact TMDB record and visible title.
  static Future<Map<String, Object?>> resolve(
      Map<String, dynamic> args) async {
    const keys = <String>{'type', 'tmdbId', 'title', 'year'};
    final type = args['type'];
    final id = args['tmdbId'];
    final title = args['title'];
    final year = args['year'];
    if (args.keys.any((key) => !keys.contains(key)) ||
        !const {'movie', 'series'}.contains(type) ||
        id is! int || id <= 0 ||
        title is! String || title.trim().length < 2 ||
        title.length > 220 ||
        year != null && (year is! int || year < 1900 || year > 2100)) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_media_identity',
      };
    }
    try {
      final resolved = await TmdbDiscoverService.instance.resolveMovie(
        DiscoverTitle(
          tmdbId: id, title: title.trim(),
          type: type == 'series' ? DiscoverType.series : DiscoverType.movie,
          premiereYear: year is int ? year : null,
        ),
      ).timeout(const Duration(seconds: 35));
      if (resolved == null || resolved.id.trim().isEmpty ||
          resolved.type != type) {
        return <String, Object?>{
          'accepted': false, 'reason': 'media_identity_not_resolved',
        };
      }
      return <String, Object?>{
        'accepted': true,
        'type': resolved.type,
        'id': resolved.id,
        'title': resolved.name,
        'year': year,
        'tmdbId': id,
        'identitySource': resolved.id.startsWith('tt')
            ? 'imdb_compatible' : 'metadata_resolution',
      };
    } catch (error) {
      debugPrint('[IosRemoteMediaDiscovery] Resolve: ${error.runtimeType}');
      return <String, Object?>{
        'accepted': false, 'reason': 'media_resolution_unavailable',
        'errorClass': error.runtimeType.toString(),
      };
    }
  }
}
