import '../addon/addon.dart';
import 'movie.dart';

class MovieSection {
  final String title;
  final String subtitle;
  final String contentType;
  final String addonBaseUrl;
  final String? sourceAddonId; // Stable manifest ID, not a secret URL.
  final AddonCatalog catalog;
  final List<Movie> movies;

  /// True for personalized/curated sections assembled in memory (for example
  /// BestSimilar, Trakt, Simkl). They are not Stremio addon catalogs: See All
  /// must show these exact items instead of fetching a synthetic catalog ID.
  final bool isCurated;

  /// Exact source identity for expanding TMDB curated recommendations.
  /// Never treat these as a Stremio catalog or paginate generic addons.
  final String? relatedSourceTitle;
  final int? relatedSourceYear;
  final String? relatedSourceImdbId;
  final int? relatedSourceTmdbId;

  MovieSection({
    required this.title,
    required this.subtitle,
    required this.contentType,
    required this.addonBaseUrl,
    this.sourceAddonId,
    required this.catalog,
    required this.movies,
    this.isCurated = false,
    this.relatedSourceTitle,
    this.relatedSourceYear,
    this.relatedSourceImdbId,
    this.relatedSourceTmdbId,
  });
}
