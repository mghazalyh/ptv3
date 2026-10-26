import '../addon/addon.dart';
import 'movie.dart';

class MovieSection {
  final String title;
  final String subtitle;
  final String contentType;
  final String addonBaseUrl;
  final AddonCatalog catalog;
  final List<Movie> movies;

  /// True for personalized/curated sections assembled in memory (for example
  /// BestSimilar, Trakt, Simkl). They are not Stremio addon catalogs: See All
  /// must show these exact items instead of fetching a synthetic catalog ID.
  final bool isCurated;

  MovieSection({
    required this.title,
    required this.subtitle,
    required this.contentType,
    required this.addonBaseUrl,
    required this.catalog,
    required this.movies,
    this.isCurated = false,
  });
}
