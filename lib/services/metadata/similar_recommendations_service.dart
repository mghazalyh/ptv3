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
        country: title.originCountries.isEmpty
            ? null : title.originCountries.join(', '),
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
      item.originalLanguage = title.originalLanguage;
      result.add(item);
      if (result.length >= 18) break;
    }
    return result;
  }

  /// Enhance only the first handful of displayed recommendations. This
  /// runs after the initial cards appear; never scan entire lists or library.
  /// Metadata is cache-backed and all HTTP requests go through TMDB's
  /// existing pacing and 429 cooldown. Never fabricate language or networks.
  static Future<void> enrichVisibleCards(
      List<BSItem> cards, {int maxCards = 6}) async {
    final tmdb = TmdbDiscoverService.instance;
    if ((await tmdb.readKey()).trim().isEmpty) return;
    final cap = maxCards.clamp(0, 6);
    for (final card in cards.take(cap)) {
      try {
        final details = await tmdb.similarCardDetails(
          title: card.title, year: card.year,
          mediaType: card.mediaType, tmdbId: card.tmdbId,
        );
        if (details.isEmpty) continue;
        final origins = details['origin_country'];
        final productions = details['production_countries'];
        if (origins is List && origins.isNotEmpty) {
          card.country = origins.map((e) => e.toString()).join(', ');
        } else if (productions is List && productions.isNotEmpty) {
          card.country = productions.whereType<Map>()
              .map((e) => e['iso_3166_1']?.toString() ?? '')
              .where((e) => e.isNotEmpty).take(3).join(', ');
        }
        card.originalLanguage =
            details['original_language']?.toString() ?? card.originalLanguage;
        if (card.mediaType == 'series') {
          final networks = details['networks'];
          if (networks is List && networks.isNotEmpty) {
            card.network = networks.whereType<Map>()
                .map((e) => e['name']?.toString() ?? '')
                .where((e) => e.isNotEmpty).take(2).join(', ');
          }
        } else if (card.mediaType == 'movie') {
          final studios = details['production_companies'];
          if (studios is List && studios.isNotEmpty) {
            card.network = studios.whereType<Map>()
                .map((e) => e['name']?.toString() ?? '')
                .where((e) => e.isNotEmpty).take(2).join(', ');
          }
        }
      } catch (_) {
        // Continue displaying existing BestSimilar country metadata. A 429
        // inhibits new TMDB requests in _paceRequest; avoid attempting the
        // remaining lookups once a provider request failed.
        break;
      }
    }
  }

  /// Labels refer to ORIGINAL production language, not available dubs.
  static String displayLanguage(String? code) {
    const known = {
      'en': 'English', 'ko': 'Korean', 'ja': 'Japanese',
      'zh': 'Chinese', 'fr': 'French', 'de': 'German',
      'es': 'Spanish', 'hi': 'Hindi', 'ta': 'Tamil',
      'te': 'Telugu', 'th': 'Thai', 'tr': 'Turkish',
      'ar': 'Arabic', 'pt': 'Portuguese', 'id': 'Indonesian',
      'it': 'Italian', 'ru': 'Russian', 'tl': 'Filipino',
    };
    final s = code?.trim().toLowerCase() ?? '';
    if (s.isEmpty) return 'Not listed';
    return known[s] ?? s.toUpperCase();
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
