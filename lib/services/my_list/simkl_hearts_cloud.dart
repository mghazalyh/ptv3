import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/my_list/my_list_item.dart';
import '../simkl/simkl_service.dart';
import 'trakt_merge_plan.dart';

enum SimklHeartState { disconnected, syncing, synced, partial, failed }

/// Only the user's Plan to Watch entries are represented by ❤️ My List.
/// Other Simkl statuses (watching/completed/dropped/hold) are independent
/// viewing activity, not "favorites" and must not be overwritten by hearts.
class SimklHeartGateway {
  const SimklHeartGateway();

  Future<bool> connected() => SimklService.instance.isAuthenticated();
  Future<String?> username() => SimklService.instance.getUsername();
  Future<Map<String, dynamic>?> activities() =>
      SimklService.instance.fetchSyncActivitiesOrNull();
  Future<Map<String, dynamic>?> snapshot() =>
      SimklService.instance.fetchHeartsSnapshotOrNull();
  Future<bool> addBatch(List<Map<String, dynamic>> movies,
      List<Map<String, dynamic>> shows) =>
      SimklService.instance.addPlanToWatchBatch(movies, shows);
  Future<bool> remove(MyListItem item) =>
      SimklService.instance.removeUnwatchedPlanToWatch(
        item.imdbId ?? '', item.type, tmdbId: item.tmdbId,
        simklId: item.simklId);
}

class SimklHeartsCloud {
  SimklHeartsCloud({SimklHeartGateway? gateway})
      : gateway = gateway ?? const SimklHeartGateway();

  final SimklHeartGateway gateway;
  final ValueNotifier<SimklHeartState> state =
      ValueNotifier<SimklHeartState>(SimklHeartState.disconnected);
  final ValueNotifier<DateTime?> lastSuccessfulSync =
      ValueNotifier<DateTime?>(null);

  static const _adds = 'simkl_mylist_pending_adds_v1';
  static const _removes = 'simkl_mylist_pending_removes_v1';
  static const _seenPrefix = 'simkl_mylist_seen_v1_';
  static const _activityPrefix = 'simkl_mylist_activities_v1_';
  Future<void> _writes = Future<void>.value();
  bool _running = false;

  static List<MyListItem> _read(SharedPreferences prefs, String key) {
    try {
      return ((jsonDecode(prefs.getString(key) ?? '[]')) as List)
          .whereType<Map<String, dynamic>>()
          .map(MyListItem.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(SharedPreferences prefs, String key,
      List<MyListItem> items) async {
    await prefs.setString(key,
      jsonEncode(items.map((x) => x.toJson()).toList()));
  }

  static bool _matches(Iterable<MyListItem> list, MyListItem item) =>
      list.any((other) => other.matches(item));

  static Map<String, dynamic>? _entry(MyListItem item) {
    final ids = <String, dynamic>{};
    if (item.imdbId?.startsWith('tt') ?? false) ids['imdb'] = item.imdbId;
    if (item.tmdbId != null) ids['tmdb'] = item.tmdbId;
    if (item.simklId != null) ids['simkl'] = item.simklId;
    if (ids.isEmpty) return null;
    return {'ids': ids};
  }

  Future<void> _journal(MyListItem item, {required bool added,
      bool acknowledge = false}) {
    final task = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final adds = _read(prefs, _adds);
      final removes = _read(prefs, _removes);
      if (acknowledge) {
        (added ? adds : removes).removeWhere((x) => x.matches(item));
      } else if (added) {
        removes.removeWhere((x) => x.matches(item));
        if (!_matches(adds, item)) adds.add(item);
      } else {
        adds.removeWhere((x) => x.matches(item));
        if (!_matches(removes, item)) removes.add(item);
      }
      await _write(prefs, _adds, adds);
      await _write(prefs, _removes, removes);
    });
    _writes = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  /// Retain local edits across offline periods and Simkl failures. Cloud
  /// mutation is reconciled on next refresh, not in a burst per heart tap.
  Future<void> localChange(MyListItem item, {required bool added}) async {
    await _journal(item, added: added);
  }

  /// Simkl's only documented whole-title removal also deletes watch history.
  /// Never call it for a title with any sign of prior watching or a status
  /// other than plantowatch; hold/dropped are not equivalent to unheart.
  static bool safeToDeleteUnwatched(Map<String, dynamic> raw, String type) {
    if (raw['status'] != 'plantowatch') return false;
    for (final key in ['watched_at', 'last_watched_at']) {
      final v = raw[key];
      if (v != null && v.toString().isNotEmpty) return false;
    }
    for (final key in ['watched_count', 'watched_episodes_count',
        'episodes_watched']) {
      final v = raw[key];
      if (v is num && v > 0) return false;
    }
    // Be conservative: unknown watched episode count could conceal history.
    if (type != 'movie' && raw['watched_episodes_count'] is! num) return false;
    return true;
  }

  /// Full snapshots are gated by /sync/activities. Per-account seen lists
  /// prevent deleted remote hearts from silently reappearing locally.
  /// The first pairing merges both libraries non-destructively.
  Future<bool> reconcile({
    required List<MyListItem> Function() readLocal,
    required Future<void> Function(List<MyListItem>) persistMerged,
  }) async {
    if (_running) return false;
    _running = true;
    try {
      if (!await gateway.connected()) {
        state.value = SimklHeartState.disconnected;
        return false;
      }
      state.value = SimklHeartState.syncing;
      await _writes;
      final account = (await gateway.username())?.trim().toLowerCase();
      final accountKey = (account != null && account.isNotEmpty)
          ? Uri.encodeComponent(account) : null;
      final prefs = await SharedPreferences.getInstance();
      final seenKey = accountKey == null ? null : '$_seenPrefix$accountKey';
      final activityKey = accountKey == null ? null :
          '$_activityPrefix$accountKey';
      final latest = await gateway.activities();
      if (latest == null) {
        state.value = SimklHeartState.failed;
        return false;
      }
      final earlierActivity = activityKey == null
          ? null : prefs.getString(activityKey);
      final marker = latest['all']?.toString();
      await _writes;
      final pendingAdds = _read(prefs, _adds);
      final pendingRemoves = _read(prefs, _removes);
      // No new activity, no pending edits: one GET, no watchlist fetch.
      if (marker != null && earlierActivity == marker &&
          pendingAdds.isEmpty && pendingRemoves.isEmpty) {
        state.value = SimklHeartState.synced;
        lastSuccessfulSync.value = DateTime.now();
        return true;
      }

      final snapshot = await gateway.snapshot();
      if (snapshot == null) {
        state.value = SimklHeartState.failed;
        return false;
      }

      final remote = <MyListItem>[];
      final rawById = <String, Map<String, dynamic>>{};
      for (final type in ['movies', 'shows', 'anime']) {
        final records = snapshot[type];
        if (records is! List) {
          state.value = SimklHeartState.failed;
          return false;
        }
        for (final data in records) {
          if (data is! Map<String, dynamic> ||
              data['status'] != 'plantowatch') continue;
          final entry = MyListItem.fromSimklJson(data);
          remote.add(entry);
          rawById[entry.uniqueKey] = data;
        }
      }

      final prior = seenKey == null ? <MyListItem>[] :
          _read(prefs, seenKey);
      final plan = TraktMergePlan.create(
        local: readLocal(), remote: remote,
        previouslySeen: prior, pendingAdds: pendingAdds,
        pendingRemoves: pendingRemoves,
      );
      // Simkl IDs, not Trakt IDs, control whether a title can be uploaded.
      final candidates = <MyListItem>[];
      for (final item in plan.merged) {
        if (!_matches(remote, item) &&
            (!_matches(prior, item) || _matches(pendingAdds, item)) &&
            _entry(item) != null) candidates.add(item);
      }
      await persistMerged(plan.merged);
      var succeeded = true;
      var protectedHistory = false;
      final confirmed = List<MyListItem>.from(remote);
      for (final item in pendingRemoves) {
        if (!_matches(remote, item)) {
          await _journal(item, added: false, acknowledge: true);
          continue;
        }
        final idx = remote.indexWhere((x) => x.matches(item));
        final raw = idx < 0 ? null : rawById[remote[idx].uniqueKey];
        if (raw == null || !safeToDeleteUnwatched(raw, item.type)) {
          // Leave local heart removed. Explicitly show partial sync and
          // never destroy a user's actual watch history as a side effect.
          protectedHistory = true;
          continue;
        }
        final ok = await gateway.remove(remote[idx]);
        if (!ok) {
          succeeded = false;
          break; // Stop on failures / rate limits.
        }
        confirmed.removeWhere((x) => x.matches(item));
        await _journal(item, added: false, acknowledge: true);
        await Future<void>.delayed(const Duration(milliseconds: 1250));
      }

      if (succeeded) {
        for (var offset = 0; offset < candidates.length; offset += 50) {
          final end = (offset + 50).clamp(0, candidates.length).toInt();
          final chunk = candidates.sublist(offset, end);
          final movies = <Map<String, dynamic>>[];
          final shows = <Map<String, dynamic>>[];
          for (final item in chunk) {
            final entry = _entry(item);
            if (entry == null) continue;
            (item.type == 'series' || item.type == 'anime' ? shows : movies)
              .add(entry);
          }
          if (!await gateway.addBatch(movies, shows)) {
            succeeded = false;
            break; // Failed entries stay in local My List / pending journal.
          }
          for (final item in chunk) {
            if (!_matches(confirmed, item)) confirmed.add(item);
            await _journal(item, added: true, acknowledge: true);
          }
          if (end < candidates.length) {
            await Future<void>.delayed(const Duration(milliseconds: 1250));
          }
        }
      }

      if (seenKey != null) await _write(prefs, seenKey, confirmed);
      // Activity timestamp was read before any writes; do NOT save if
      // uploading caused a change that could mask other-device edits.
      // Next refresh gates on activities again and rereads the delta.
      if (succeeded && !protectedHistory && activityKey != null &&
          candidates.isEmpty && pendingRemoves.isEmpty &&
          marker != null) {
        await prefs.setString(activityKey, marker);
      }
      final hasUnsupported = plan.merged.any((item) =>
          !_matches(remote, item) && _entry(item) == null);
      if (succeeded && !protectedHistory && !hasUnsupported) {
        state.value = SimklHeartState.synced;
        lastSuccessfulSync.value = DateTime.now();
      } else {
        state.value = SimklHeartState.partial;
      }
      return state.value == SimklHeartState.synced;
    } catch (e) {
      debugPrint('Simkl heart reconciliation error (${e.runtimeType})');
      state.value = SimklHeartState.failed;
      return false;
    } finally {
      _running = false;
    }
  }
}
