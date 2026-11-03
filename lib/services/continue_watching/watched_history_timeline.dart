import 'watched_history_service.dart';

/// A privacy-preserving projection of existing synced watched-history v1 data.
/// No external calls, no change to stored cloud records and no new telemetry.
class WatchedHistoryEntry {
  final WatchedTitle title;
  final DateTime watchedAt;
  final int? season;
  final int? episode;
  final String? episodeId;
  final WatchedPlaybackPosition? position;

  const WatchedHistoryEntry({
    required this.title,
    required this.watchedAt,
    this.season,
    this.episode,
    this.episodeId,
    this.position,
  });

  bool get isMovie => title.type == 'movie';
  bool get isEpisode => episode != null || episodeId != null;
  bool get completed =>
      (position?.completed == true) ||
      (isMovie && title.completed) ||
      (!isMovie && episodeId != null &&
          title.completedEpisodeIds.contains(episodeId));
  String get typeLabel => isMovie ? 'MOVIE' :
      title.type == 'anime' ? 'ANIME' : 'SERIES';
  String get episodeLabel {
    if (season != null && episode != null) {
      return 'Season ' + season.toString() + ' · Episode ' + episode.toString();
    }
    return isEpisode ? 'Episode watched' : 'Series watched';
  }
  double get progress => position?.fraction ?? (completed ? 1.0 : 0.0);
  String get uniqueKey => title.identity + ':' + (episodeId ?? 'title');
}

abstract final class WatchedHistoryTimeline {
  /// Only stable season/episode IDs are decoded; unknown IDs are never
  /// misrepresented as a guessed episode number.
  static (int?, int?) episodeNumbers(String titleId, String key) {
    final match = RegExp(
        '^' + RegExp.escape(titleId) + r':(\d+):(\d+)$').firstMatch(key);
    if (match == null) return (null, null);
    final season = int.tryParse(match.group(1) ?? '');
    final episode = int.tryParse(match.group(2) ?? '');
    if (season == null || episode == null ||
        season < 0 || episode <= 0) {
      return (null, null);
    }
    return (season, episode);
  }

  /// Each movie and each recorded episode has its own time-ordered row.
  /// Legacy title-only entries remain discoverable without fabricated dates.
  static List<WatchedHistoryEntry> fromTitles(
      Iterable<WatchedTitle> titles, {int limit = 600}) {
    if (limit <= 0) return const [];
    final result = <WatchedHistoryEntry>[];
    for (final title in titles) {
      if (title.id.trim().isEmpty || title.title.trim().isEmpty) continue;
      if (title.type == 'movie') {
        final position = title.playbackPositions['movie'];
        result.add(WatchedHistoryEntry(
          title: title,
          watchedAt: position != null &&
              position.updatedAt.isAfter(title.lastWatchedAt)
              ? position.updatedAt : title.lastWatchedAt,
          position: position,
        ));
        continue;
      }
      var latestEpisode = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final episodes = title.playbackPositions.entries
          .where((entry) => entry.key != 'movie').toList();
      for (final episodeEntry in episodes) {
        final key = episodeEntry.key;
        final position = episodeEntry.value;
        final numbers = episodeNumbers(title.id, key);
        result.add(WatchedHistoryEntry(
          title: title,
          watchedAt: position.updatedAt,
          season: numbers.$1,
          episode: numbers.$2,
          episodeId: key,
          position: position,
        ));
        if (position.updatedAt.isAfter(latestEpisode)) {
          latestEpisode = position.updatedAt;
        }
      }
      if (episodes.isEmpty) {
        // An imported history record may carry a known single episode ID.
        String? key;
        int? season;
        int? episode;
        if (title.completedEpisodeIds.length == 1) {
          final candidate = title.completedEpisodeIds.single;
          final numbers = episodeNumbers(title.id, candidate);
          if (numbers.$1 != null && numbers.$2 != null) {
            key = candidate;
            season = numbers.$1;
            episode = numbers.$2;
          }
        }
        result.add(WatchedHistoryEntry(
          title: title,
          watchedAt: title.lastWatchedAt,
          season: season,
          episode: episode,
          episodeId: key,
        ));
      } else if (title.lastWatchedAt.difference(latestEpisode) >
          const Duration(minutes: 2)) {
        // Preserve recent playback that arrived without an episode ID.
        result.add(WatchedHistoryEntry(
          title: title,
          watchedAt: title.lastWatchedAt,
        ));
      }
    }
    result.sort((a, b) {
      final time = b.watchedAt.compareTo(a.watchedAt);
      return time != 0 ? time : a.uniqueKey.compareTo(b.uniqueKey);
    });
    return result.take(limit).toList(growable: false);
  }

  static List<WatchedHistoryEntry> filter(
    Iterable<WatchedHistoryEntry> entries, {
    String query = '',
    String kind = 'all',
  }) {
    final term = query.trim().toLowerCase();
    return entries.where((entry) {
      if (kind == 'movies' && !entry.isMovie) return false;
      if (kind == 'series' && entry.isMovie) return false;
      if (term.isEmpty) return true;
      final seasonText = entry.isEpisode
          ? 's' + (entry.season ?? 0).toString().padLeft(2, '0') +
            ' e' + (entry.episode ?? 0).toString().padLeft(2, '0') +
            ' ' + entry.episodeLabel
          : '';
      return entry.title.title.toLowerCase().contains(term) ||
          (entry.title.year ?? '').toLowerCase().contains(term) ||
          seasonText.toLowerCase().contains(term);
    }).toList(growable: false);
  }
}
