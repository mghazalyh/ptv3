import 'package:flutter/foundation.dart';

import '../../models/movie/movie_detail.dart';
import 'bestsimilar_scraper.dart';
import 'tmdb_discover_service.dart';
import 'tvdb_series_service.dart';

class SimilarRecommendationsResult {
  final List<BSItem> items;
  final bool fromTmdb;
  final int? tvdbId;

  const SimilarRecommendationsResult(
      this.items, {this.fromTmdb = false, this.tvdbId});
}

/// On-demand related titles for the opened details page. No polling, no
/// catalog-wide lookups. Existing BestSimilar data always has first priority.
abstract final class SimilarRecommendationsService {
  /// Some addons return "2019–2020" or "2019–" for a series. Extract the
  /// premiere year, never parse concatenated years as an enormous number.
  @visibleForTesting
  static int? firstReleaseYear(String? value) {
    if (value == null) return null;
    final match = RegExp(r'\b(?:19|20)\d{2}\b').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  @visibleForTesting
  static List<BSItem> fromTmdbTitles(
      List<DiscoverTitle> titles, String requestedTitle) {
    final result = <BSItem>[];
    final normalized = TvdbSeriesService.normalizeTitle(requestedTitle);
    final unique = <int>{};
    for (final title in titles) {
      if (title.type != DiscoverType.series ||
          title.tmdbId <= 0 ||
          title.poster == null ||
          title.poster!.isEmpty ||
          !unique.add(title.tmdbId) ||
          TvdbSeriesService.normalizeTitle(title.title) == normalized) continue;
      final item = BSItem(
        id: -title.tmdbId,
        slug: 'tmdb-${title.tmdbId}',
        title: title.title,
        year: title.premiereYear,
        rating: title.rating > 0 ? title.rating : null,
        voteCount: null,
        thumbUrl: title.poster!,
        similarityPercent: null,
        genre: null,
        country: null,
        duration: null,
        story: title.overview,
        styleTags: const [],
        plotTags: const [],
        audienceTags: const [],
        timeTags: const [],
        placeTags: const [],
        sourceIsTv: true,
      );
      item.tmdbId = title.tmdbId;
      item.tmdbMediaType = 'tv';
      result.add(item);
      if (result.length >= 18) break;
    }
    return result;
  }

  static Future<SimilarRecommendationsResult> load({
    required MovieDetail detail,
    required bool isSeries,
  }) async {
    final year = firstReleaseYear(detail.year);
    try {
      final match = await BestSimilarScraper.findBest(
        title: detail.name, year: year, isTv: isSeries,
      );
      if (match != null) {
        final page = await BestSimilarScraper.fetchDetails(
          id: match.id, slug: match.slug,
        );
        final related = page?.similar ?? const <BSItem>[];
        if (related.isNotEmpty) {
          // Existing provider caching; no TMDB/TVDB lookups when this works.
          await BestSimilarScraper.classifySimilar(
            related, maxConcurrent: 2, maxLookups: 18,
          );
          return SimilarRecommendationsResult(related);
        }
      }
    } catch (error) {
      debugPrint('[Similar] BestSimilar unavailable: $error');
    }

    // TVDB is optional, never sends a user's key through query strings.
    // Only query when the BestSimilar series lookup genuinely found nothing.
    if (!isSeries) return const SimilarRecommendationsResult([]);
    TvdbSeriesInfo? tvdb;
    try {
      tvdb = await TvdbSeriesService.instance.matchSeries(detail.name, year);
    } catch (_) {
      // A missing/invalid TVDB credential must never block other providers.
    }

    try {
      final tmdb = TmdbDiscoverService.instance;
      final suggestions = await tmdb.relatedSeries(
        title: detail.name,
        startYear: year,
        imdbId: detail.id.startsWith('tt') ? detail.id : null,
        tmdbId: int.tryParse(detail.tmdbId ?? ''),
        verifiedTvdbTmdbId: tvdb?.tmdbId,
      );
      final sorted = tvdb == null ? suggestions : tvdb.prioritize(suggestions);
      return SimilarRecommendationsResult(
        fromTmdbTitles(sorted, detail.name),
        fromTmdb: sorted.isNotEmpty,
        tvdbId: tvdb?.id,
      );
    } catch (error) {
      // Honor TMDB cooldown and avoid noisy automatic retries.
      debugPrint('[Similar] Optional series fallback unavailable: ${error.runtimeType}');
      return const SimilarRecommendationsResult([]);
    }
  }
}
