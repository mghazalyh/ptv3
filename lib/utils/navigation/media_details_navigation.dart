import 'package:flutter/material.dart';

import '../../models/anime/anime_media.dart';
import '../../models/movie/movie.dart';
import '../../pages/anime/anime_details_page.dart';
import '../../pages/anime_arabic/anime_arabic_details_page.dart';
import '../../pages/details/details_page.dart';
import '../../services/anime_arabic/anime_arabic_service.dart';
import 'route_transitions.dart';

/// Opens the correct title information page from Continue Watching or player.
/// Never opens a stream or changes the episode watched.
abstract final class MediaDetailsNavigation {
  static Future<void> open(
    BuildContext context, {
    required String id,
    required String title,
    required String type,
    String? poster,
    String? backdrop,
    String? year,
    String? addonName,
    int? episode,
    Offset? tapPosition,
  }) async {
    if (id.isEmpty) return;

    if (id.startsWith('arabic_anime:') || addonName == 'ArabicAnime') {
      final card = ArabicAnimeCard(
        slug: id.replaceFirst('arabic_anime:', ''),
        title: title,
        cover: poster ?? backdrop,
      );
      await Navigator.push(
        context,
        CinematicSlideRoute(
          page: AnimeArabicDetailsPage(
            anime: card,
            initialEpisodeNumber: episode,
          ),
        ),
      );
      return;
    }

    if (type == 'anime' || id.startsWith('anilist:')) {
      final anilistId = int.tryParse(id.replaceFirst('anilist:', '')) ?? 0;
      final anime = AnimeMedia(
        id: anilistId,
        titleEnglish: title,
        titleRomaji: title,
        titleNative: '',
        titleUserPreferred: title,
        coverImageLarge: poster ?? '',
        coverImageExtraLarge: poster ?? '',
        bannerImage: backdrop ?? '',
        description: '',
        seasonYear: int.tryParse(year ?? '') ?? 0,
        averageScore: 0,
        genres: const [],
        format: 'TV',
        status: 'RELEASING',
        totalEpisodes: 0,
      );
      await Navigator.push(
        context,
        CinematicSlideRoute(page: AnimeDetailsPage(anime: anime)),
      );
      return;
    }

    final movie = Movie(
      id: id,
      name: title,
      poster: poster ?? backdrop,
      year: year,
      type: type == 'tv' ? 'series' : type,
      // DetailsPage uses Cinemeta as a fallback and fetches cast, synopsis,
      // seasons and episodes by IMDb ID where metadata is available.
      addonBaseUrl: 'https://v3-cinemeta.strem.io',
    );
    await Navigator.push(
      context,
      LiquidRevealRoute(
        page: DetailsPage(movie: movie),
        tapPosition: tapPosition,
      ),
    );
  }
}
