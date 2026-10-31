import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import 'series_year_label.dart';

/// Details recommendations use the same verified TV run as Search/Discover.
/// Only series with an exact TMDB ID can request an end year; films and
/// unresolved recommendations keep their original premiere-year display.
class SimilarYearTypeLabel extends StatelessWidget {
  final String mediaType;
  final int? premiereYear;
  final int? tmdbId;

  const SimilarYearTypeLabel({
    super.key,
    required this.mediaType,
    this.premiereYear,
    this.tmdbId,
  });

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white70, fontSize: 11);
    final year = premiereYear?.toString();
    final type = Movie.typeLabel(mediaType);

    if (mediaType != 'series' || tmdbId == null || tmdbId! <= 0) {
      return Text(
        [if (year != null) year, type].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return Row(
      children: [
        Flexible(
          child: SeriesYearLabel(
            key: ValueKey('similar-series-run-$tmdbId'),
            tmdbId: tmdbId,
            fallbackYear: year,
            style: style,
          ),
        ),
        Text(
          ' · $type',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ],
    );
  }
}
