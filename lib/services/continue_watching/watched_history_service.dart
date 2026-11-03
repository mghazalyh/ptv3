import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../trakt/trakt_service.dart';
import 'github_watched_history_cloud.dart';

/// A single movie or episode playback position kept in the existing private
/// watched-history cloud record. No stream URLs or per-device identifiers.
class WatchedPlaybackPosition {
  final int positionSeconds;
  final int totalDurationSeconds;
  final DateTime updatedAt;
  final bool completed;

  const WatchedPlaybackPosition({
    required this.positionSeconds,
    required this.totalDurationSeconds,
    required this.updatedAt,
    required this.completed,
  });

  double get fraction => completed ? 1.0 :
      (totalDurationSeconds <= 0 ? 0.0 :
          (positionSeconds / totalDurationSeconds).clamp(0.0, 1.0));

  Map<String, dynamic> toJson() => {
    'positionSeconds': positionSeconds,
    'totalDurationSeconds': totalDurationSeconds,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'completed': completed,
  };

  static WatchedPlaybackPosition? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final position = int.tryParse(raw['positionSeconds']?.toString() ?? '');
    final duration = int.tryParse(raw['totalDurationSeconds']?.toString() ?? '');
    final at = DateTime.tryParse(raw['updatedAt']?.toString() ?? '');
    if (position == null || duration == null || at == null ||
        position < 0 || duration < 120) return null;
    return WatchedPlaybackPosition(
      positionSeconds: position.clamp(0, duration).toInt(),
      totalDurationSeconds: duration, updatedAt: at,
      completed: raw['completed'] == true || position / duration >= 0.90,
    );
  }
}

/// Privacy-minimal on-device history of titles the user actually played.
/// Completed titles stay here after Continue Watching removes their sessions.
/// No stream URLs, torrent hashes, API keys or GitHub writes are stored.
class WatchedTitle {
  final String id;
  final String title;
  final String type;
  final String? year;
  final DateTime lastWatchedAt;
  final bool completed;
  /// Episodes fully played, distinct from completion of the entire series.
  final List<String> completedEpisodeIds;
  /// Independent positions for each episode, plus key 'movie' for films.
  final Map<String, WatchedPlaybackPosition> playbackPositions;

  static String episodeKey(String showId, int season, int episode) =>
      '$showId:$season:$episode';

  static Map<String, WatchedPlaybackPosition> mergePlaybackPositions(
      Map<String, WatchedPlaybackPosition> a,
      Map<String, WatchedPlaybackPosition> b) {
    final merged = Map<String, WatchedPlaybackPosition>.from(a);
    for (final entry in b.entries) {
      final prior = merged[entry.key];
      if (prior == null) {
        merged[entry.key] = entry.value;
      } else {
        final newest = entry.value.updatedAt.isAfter(prior.updatedAt)
            ? entry.value : prior;
        merged[entry.key] = WatchedPlaybackPosition(
          positionSeconds: newest.positionSeconds,
          totalDurationSeconds: newest.totalDurationSeconds,
          updatedAt: newest.updatedAt,
          completed: prior.completed || entry.value.completed,
        );
      }
    }
    // A history record must remain bounded even for exceptionally long shows.
    if (merged.length > 800) {
      final sorted = merged.entries.toList()
        ..sort((x, y) => y.value.updatedAt.compareTo(x.value.updatedAt));
      return {for (final row in sorted.take(800)) row.key: row.value};
    }
    return merged;
  }

  const WatchedTitle({
    required this.id,
    required this.title,
    required this.type,
    this.year,
    required this.lastWatchedAt,
    this.completed = false,
    this.completedEpisodeIds = const [],
    this.playbackPositions = const {},
  });

  String get identity => type.toLowerCase() + ':' + id.toLowerCase();

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'type': type, 'year': year,
    'lastWatchedAt': lastWatchedAt.toUtc().toIso8601String(),
    'completed': completed,
    if (completedEpisodeIds.isNotEmpty) 'completedEpisodeIds': completedEpisodeIds,
    if (playbackPositions.isNotEmpty)
      'playbackPositions': {
        for (final entry in playbackPositions.entries)
          entry.key: entry.value.toJson(),
      },
  };

  static WatchedTitle? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final title = raw['title']?.toString().trim() ?? '';
    final type = raw['type']?.toString().trim() ?? '';
    final date = DateTime.tryParse(raw['lastWatchedAt']?.toString() ?? '');
    if (id.isEmpty || title.isEmpty || date == null ||
        !{'movie', 'series', 'anime'}.contains(type)) return null;
    return WatchedTitle(id: id, title: title, type: type,
        year: raw['year']?.toString(), lastWatchedAt: date,
        completed: raw['completed'] == true,
        completedEpisodeIds: (raw['completedEpisodeIds'] as List<dynamic>? ?? const [])
            .whereType<String>().where((e) => e.trim().isNotEmpty)
            .toSet().toList(),
        playbackPositions: {
          if (raw['playbackPositions'] is Map)
            for (final entry in (raw['playbackPositions'] as Map).entries)
              if (entry.key is String &&
                  WatchedPlaybackPosition.fromJson(entry.value) != null)
                entry.key as String:
                    WatchedPlaybackPosition.fromJson(entry.value)!,
        });
  }
}

abstract final class WatchedHistoryService {
  static const storageKey = 'watched_history_v1';
  static final ValueNotifier<List<WatchedTitle>> items =
      ValueNotifier<List<WatchedTitle>>([]);

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey,
        jsonEncode(items.value.map((entry) => entry.toJson()).toList()));
  }

  /// Cloud responses merge with any local playback that happened during the
  /// request. Never drop completed episodes or downgrade a completed movie.
  static Future<void> mergeFromCloud(List<WatchedTitle> cloud) async {
    final byId = <String, WatchedTitle>{
      for (final entry in items.value) entry.identity: entry,
    };
    for (final incoming in cloud) {
      final local = byId[incoming.identity];
      if (local == null) {
        byId[incoming.identity] = incoming;
        continue;
      }
      final freshest = incoming.lastWatchedAt.isAfter(local.lastWatchedAt)
          ? incoming : local;
      byId[incoming.identity] = WatchedTitle(
        id: freshest.id, title: freshest.title, type: freshest.type,
        year: freshest.year, lastWatchedAt: freshest.lastWatchedAt,
        completed: local.completed || incoming.completed,
        completedEpisodeIds: {
          ...local.completedEpisodeIds, ...incoming.completedEpisodeIds,
        }.toList()..sort(),
        playbackPositions: WatchedTitle.mergePlaybackPositions(
            local.playbackPositions, incoming.playbackPositions),
      );
    }
    final all = byId.values.toList()
      ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    items.value = all.take(200).toList();
    await _persist();
  }

  static Future<void> syncGitHubHistory({bool force = false}) async {
    await GitHubWatchedHistoryCloud.instance.sync(
      force: force, readLocal: () => List<WatchedTitle>.from(items.value),
      persist: mergeFromCloud,
    );
  }

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        items.value = [];
        unawaited(importRecentTraktHistory());
        unawaited(syncGitHubHistory(force: true));
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final byId = <String, WatchedTitle>{};
      for (final entry in decoded) {
        final title = WatchedTitle.fromJson(entry);
        if (title == null) continue;
        final older = byId[title.identity];
        if (older == null || title.lastWatchedAt.isAfter(older.lastWatchedAt)) {
          byId[title.identity] = title;
        }
      }
      items.value = byId.values.toList()
        ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
      unawaited(importRecentTraktHistory());
      unawaited(syncGitHubHistory(force: true));
    } catch (_) {
      // Never silently destroy the original persisted history on parse error.
    }
  }

  /// Optional one-page recent Trakt history import for accounts the user
  /// already connected. Never scan the full library, never remove local rows,
  /// and never ask Trakt for keys or credentials.
  @visibleForTesting
  static WatchedTitle? parseTraktHistoryEntry(Object? raw) {
    if (raw is! Map) return null;
    final media = raw['movie'] ?? raw['show'];
    if (media is! Map) return null;
    final title = media['title']?.toString().trim() ?? '';
    final ids = media['ids'];
    if (title.isEmpty || ids is! Map) return null;
    final type = raw['movie'] != null ? 'movie' : 'series';
    final imdb = ids['imdb']?.toString() ?? '';
    final tmdb = int.tryParse(ids['tmdb']?.toString() ?? '');
    final id = imdb.startsWith('tt') ? imdb
        : tmdb != null && tmdb > 0 ? 'tmdb_${type}_$tmdb' : '';
    final date = DateTime.tryParse(
        raw['watched_at']?.toString() ?? raw['last_watched_at']?.toString() ?? '');
    if (id.isEmpty || date == null) return null;
    final season = int.tryParse((raw['episode'] is Map
        ? (raw['episode'] as Map)['season'] : null)?.toString() ?? '');
    final episode = int.tryParse((raw['episode'] is Map
        ? (raw['episode'] as Map)['number'] : null)?.toString() ?? '');
    final completedEpisodeIds = type == 'series' &&
            season != null && episode != null
        ? <String>['$id:$season:$episode'] : <String>[];
    return WatchedTitle(id: id, title: title, type: type,
        year: media['year']?.toString(), lastWatchedAt: date,
        completed: type == 'movie', completedEpisodeIds: completedEpisodeIds);
  }

  static Future<void> importRecentTraktHistory() async {
    try {
      if (!await TraktService.instance.isAuthenticated()) return;
      final movies = await TraktService.instance.fetchListOrNull('history', 'movies');
      final shows = await TraktService.instance.fetchListOrNull('history', 'shows');
      if (movies == null && shows == null) return;
      final old = {for (final item in items.value) item.identity: item};
      for (final raw in <dynamic>[
        ...?movies?.take(30),
        ...?shows?.take(30),
      ]) {
        final candidate = parseTraktHistoryEntry(raw);
        if (candidate == null) continue;
        final existing = old[candidate.identity];
        if (existing == null) {
          old[candidate.identity] = candidate;
          GitHubWatchedHistoryCloud.instance.save(candidate);
        } else if (candidate.lastWatchedAt.isAfter(existing.lastWatchedAt)) {
          old[candidate.identity] = WatchedTitle(
            id: candidate.id, title: candidate.title, type: candidate.type,
            year: candidate.year, lastWatchedAt: candidate.lastWatchedAt,
            completed: candidate.completed || existing.completed,
            completedEpisodeIds: {
              ...candidate.completedEpisodeIds, ...existing.completedEpisodeIds,
            }.toList()..sort(),
            playbackPositions: WatchedTitle.mergePlaybackPositions(
                existing.playbackPositions, candidate.playbackPositions),
          );
          GitHubWatchedHistoryCloud.instance.save(old[candidate.identity]!);
        }
      }
      final merged = old.values.toList()
        ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
      items.value = merged.take(200).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey,
          jsonEncode(items.value.map((entry) => entry.toJson()).toList()));
    } catch (_) {
      // Online history is best-effort. Preserve existing local data.
    }
  }

  /// Called only after playback has progressed meaningfully. Retains the
  /// completed flag if an already-finished title is watched again.
  static Future<void> recordProgress({
    required String id,
    required String title,
    required String type,
    String? year,
    required int positionSeconds,
    required int totalDurationSeconds,
    String? episodeId,
    int? season,
    int? episode,
  }) async {
    if (id.trim().isEmpty || title.trim().isEmpty ||
        totalDurationSeconds < 120 || positionSeconds < 0) return;
    final fraction = positionSeconds / totalDurationSeconds;
    if (positionSeconds < 60 && fraction < 0.10) return;
    final normalized = type == 'tv' ? 'series' : type;
    if (!{'movie', 'series', 'anime'}.contains(normalized)) return;
    final completed = normalized == 'movie' && fraction >= 0.90;
    final current = List<WatchedTitle>.from(items.value);
    final identity = normalized.toLowerCase() + ':' + id.toLowerCase();
    final existing = current.where((item) => item.identity == identity);
    final wasCompleted = existing.isNotEmpty && existing.first.completed;
    final previousEpisodes = existing.isNotEmpty
        ? existing.first.completedEpisodeIds : const <String>[];
    final episodes = <String>{...previousEpisodes};
    final stableEpisodeId = season != null && episode != null
        ? WatchedTitle.episodeKey(id, season, episode) : null;
    if (normalized != 'movie' && fraction >= 0.90) {
      if (episodeId != null && episodeId.isNotEmpty) episodes.add(episodeId);
      if (stableEpisodeId != null) episodes.add(stableEpisodeId);
    }
    final now = DateTime.now();
    final previousPositions = existing.isNotEmpty
        ? existing.first.playbackPositions
        : const <String, WatchedPlaybackPosition>{};
    final progressKey = normalized == 'movie'
        ? 'movie' : (stableEpisodeId ?? episodeId);
    final positions = Map<String, WatchedPlaybackPosition>.from(previousPositions);
    if (progressKey != null && progressKey.isNotEmpty) {
      positions[progressKey] = WatchedPlaybackPosition(
        positionSeconds: positionSeconds.clamp(0, totalDurationSeconds).toInt(),
        totalDurationSeconds: totalDurationSeconds,
        updatedAt: now,
        completed: fraction >= 0.90 ||
            (positions[progressKey]?.completed ?? false),
      );
    }
    current.removeWhere((item) => item.identity == identity);
    current.insert(0, WatchedTitle(id: id, title: title, type: normalized,
        year: year, lastWatchedAt: now,
        completed: completed || wasCompleted,
        completedEpisodeIds: episodes.toList()..sort(),
        playbackPositions: WatchedTitle.mergePlaybackPositions(
            const {}, positions)));
    current.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    final updated = current.take(200).toList();
    items.value = updated;
    GitHubWatchedHistoryCloud.instance.save(updated.first);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey,
          jsonEncode(updated.map((item) => item.toJson()).toList()));
    } catch (_) {
      // Playback must never fail because optional local history write failed.
    }
  }
}
