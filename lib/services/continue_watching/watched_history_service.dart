import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../trakt/trakt_service.dart';

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

  const WatchedTitle({
    required this.id,
    required this.title,
    required this.type,
    this.year,
    required this.lastWatchedAt,
    this.completed = false,
  });

  String get identity => type.toLowerCase() + ':' + id.toLowerCase();

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'type': type, 'year': year,
    'lastWatchedAt': lastWatchedAt.toUtc().toIso8601String(),
    'completed': completed,
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
        completed: raw['completed'] == true);
  }
}

abstract final class WatchedHistoryService {
  static const storageKey = 'watched_history_v1';
  static final ValueNotifier<List<WatchedTitle>> items =
      ValueNotifier<List<WatchedTitle>>([]);

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        items.value = [];
        unawaited(importRecentTraktHistory());
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
    return WatchedTitle(id: id, title: title, type: type,
        year: media['year']?.toString(), lastWatchedAt: date,
        completed: type == 'movie');
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
        } else if (candidate.lastWatchedAt.isAfter(existing.lastWatchedAt)) {
          old[candidate.identity] = WatchedTitle(
            id: candidate.id, title: candidate.title, type: candidate.type,
            year: candidate.year, lastWatchedAt: candidate.lastWatchedAt,
            completed: candidate.completed || existing.completed,
          );
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
  }) async {
    if (id.trim().isEmpty || title.trim().isEmpty ||
        totalDurationSeconds <= 0 || positionSeconds < 0) return;
    final fraction = positionSeconds / totalDurationSeconds;
    if (positionSeconds < 60 && fraction < 0.10) return;
    final normalized = type == 'tv' ? 'series' : type;
    if (!{'movie', 'series', 'anime'}.contains(normalized)) return;
    final completed = fraction >= 0.90;
    final current = List<WatchedTitle>.from(items.value);
    final identity = normalized.toLowerCase() + ':' + id.toLowerCase();
    final existing = current.where((item) => item.identity == identity);
    final wasCompleted = existing.isNotEmpty && existing.first.completed;
    current.removeWhere((item) => item.identity == identity);
    current.insert(0, WatchedTitle(id: id, title: title, type: normalized,
        year: year, lastWatchedAt: DateTime.now(),
        completed: completed || wasCompleted));
    current.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    final updated = current.take(200).toList();
    items.value = updated;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey,
          jsonEncode(updated.map((item) => item.toJson()).toList()));
    } catch (_) {
      // Playback must never fail because optional local history write failed.
    }
  }
}
