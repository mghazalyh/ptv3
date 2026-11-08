import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../continue_watching/watched_history_service.dart';
import '../storage/storage_service.dart';
import '../trakt/trakt_service.dart';

/// Sends completed history only to the user's EXISTING authorized Trakt account.
/// A BingeCat/Xperience profile can read it only when separately linked to Trakt.
/// Never fabricates accounts, provider manifests or credentials.
class ConnectedCatalogHistoryBridge {
  ConnectedCatalogHistoryBridge._();

  static bool _busy = false;
  static DateTime? _lastFailure;

  /// Pure builder: do not invent episode watch times from legacy records.
  static List<ConnectedHistoryEvent> plan(
      Iterable<WatchedTitle> titles, {int limit = 500}) {
    final sorted = titles.toList()
      ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    final out = <ConnectedHistoryEvent>[];
    final seen = <String>{};
    for (final title in sorted) {
      final ids = _ids(title.id);
      if (ids == null) continue;
      final kind = title.type.toLowerCase();
      if (kind == 'movie') {
        final position = title.playbackPositions['movie'];
        if (!title.completed && position?.completed != true) continue;
        final at = (position?.updatedAt ?? title.lastWatchedAt)
            .toUtc().toIso8601String();
        final key = 'movie:${title.id.toLowerCase()}';
        if (!seen.add(key)) continue;
        out.add(ConnectedHistoryEvent(key: key, watchedAt: at,
          isMovie: true, value: {'ids': ids, 'watched_at': at}));
      } else if (kind == 'series') {
        for (final entry in title.playbackPositions.entries) {
          if (!entry.value.completed &&
              !title.completedEpisodeIds.contains(entry.key)) continue;
          final match = RegExp('^' + RegExp.escape(title.id) +
              r':(\d+):(\d+)$').firstMatch(entry.key);
          if (match == null) continue;
          final season = int.tryParse(match.group(1) ?? '');
          final episode = int.tryParse(match.group(2) ?? '');
          if (season == null || episode == null ||
              season < 0 || episode < 1) continue;
          final at = entry.value.updatedAt.toUtc().toIso8601String();
          final key = 'episode:${title.id.toLowerCase()}:$season:$episode';
          if (!seen.add(key)) continue;
          out.add(ConnectedHistoryEvent(key: key, watchedAt: at,
            isMovie: false, value: {'ids': ids, 'seasons': [
              {'number': season, 'episodes': [
                {'number': episode, 'watched_at': at}
              ]}
            ]}));
        }
      }
    }
    out.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    return out.take(limit.clamp(0, 500).toInt()).toList(growable: false);
  }

  static Map<String, dynamic>? _ids(String value) {
    final id = value.trim().toLowerCase();
    if (RegExp(r'^tt[0-9]{5,}$').hasMatch(id)) return {'imdb': id};
    final match = RegExp(r'^tmdb_(?:movie|series)_([0-9]+)$').firstMatch(id);
    final n = match == null ? null : int.tryParse(match.group(1) ?? '');
    if (n != null && n > 0) return {'tmdb': n};
    return null;
  }

  static Map<String, dynamic> payload(Iterable<ConnectedHistoryEvent> events) {
    return {
      'movies': [for (final e in events) if (e.isMovie) e.value],
      'shows': [for (final e in events) if (!e.isMovie) e.value],
    };
  }

  static String _hash(String input) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(input)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }

  /// Windows and iOS only. No authorized account = no upload.
  /// Successful Trakt batches are checkpointed to prevent repeat history writes.
  static Future<void> sync() async {
    if (!(Platform.isIOS || Platform.isWindows) || _busy) return;
    if (_lastFailure != null &&
        DateTime.now().difference(_lastFailure!) <
        const Duration(minutes: 30)) return;
    _busy = true;
    try {
      final trakt = TraktService.instance;
      if (!await trakt.isAuthenticated()) return;
      // Refresh private cloud history before calculating completed events. The
      // asynchronous startup merge can otherwise finish after Home's first
      // bridge attempt and leave eligible events unseeded until next launch.
      try {
        await WatchedHistoryService.syncGitHubHistory();
      } catch (error) {
        debugPrint('[CatalogBridge] Cloud refresh unavailable ('
            '${error.runtimeType}); using local history');
      }
      final token = await StorageService.getTraktAccessToken();
      if (token == null || token.isEmpty) return;
      final username = await StorageService.getTraktUsername();
      final scope = username?.trim().isNotEmpty == true ? username! : token;
      final prefs = await SharedPreferences.getInstance();
      final key = 'ios_external_catalog_history_v1_${_hash(scope)}';
      final known = <String, String>{};
      try {
        final raw = prefs.getString(key);
        final decoded = raw == null ? null : jsonDecode(raw);
        if (decoded is Map) {
          for (final pair in decoded.entries) {
            if (pair.key is String && pair.value is String) {
              known[pair.key as String] = pair.value as String;
            }
          }
        }
      } catch (_) {
        // Never overwrite the original watch-history records.
      }
      final pending = plan(WatchedHistoryService.items.value)
          .where((event) => known[event.key] != event.watchedAt).toList();
      for (var start = 0; start < pending.length; start += 70) {
        final chunk = pending.sublist(
          start, (start + 70).clamp(0, pending.length).toInt());
        if (!await trakt.importCompletedHistoryBatch(payload(chunk))) {
          _lastFailure = DateTime.now();
          debugPrint('[CatalogBridge] History import unavailable');
          return;
        }
        for (final event in chunk) {
          known[event.key] = event.watchedAt;
        }
        await prefs.setString(key, jsonEncode(known));
      }
      _lastFailure = null;
    } catch (error) {
      _lastFailure = DateTime.now();
      debugPrint('[CatalogBridge] Skipped: ${error.runtimeType}');
    } finally {
      _busy = false;
    }
  }
}

class ConnectedHistoryEvent {
  final String key;
  final String watchedAt;
  final bool isMovie;
  final Map<String, dynamic> value;

  const ConnectedHistoryEvent({
    required this.key,
    required this.watchedAt,
    required this.isMovie,
    required this.value,
  });
}
