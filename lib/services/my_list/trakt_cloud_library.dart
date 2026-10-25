import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/my_list/my_list_item.dart';
import '../trakt/trakt_service.dart';
import 'trakt_merge_plan.dart';

enum TraktSyncState { disconnected, syncing, synced, partial, failed }

/// Injectable transport keeps merge/error behavior testable without an actual
/// Trakt account or publishing any personal access tokens.
class TraktSyncGateway {
  const TraktSyncGateway();

  Future<bool> connected() => TraktService.instance.isAuthenticated();
  Future<String?> username() => TraktService.instance.getUsername();
  Future<List<dynamic>?> fetch(String type) =>
      TraktService.instance.fetchWholeWatchlistOrNull(type);
  Future<bool> upload(List<Map<String, dynamic>> movies,
      List<Map<String, dynamic>> shows) =>
      TraktService.instance.addManyToWatchlist(movies, shows);
  Future<bool> remove(MyListItem item) =>
      TraktService.instance.removeFromWatchlist(item.imdbId ?? '', item.type,
          tmdbId: item.tmdbId, traktId: item.traktId);
  Future<bool> add(MyListItem item) =>
      TraktService.instance.addToWatchlist(item.imdbId ?? '', item.type,
          tmdbId: item.tmdbId, traktId: item.traktId);
}

class TraktCloudLibrary {
  TraktCloudLibrary({TraktSyncGateway? gateway})
      : gateway = gateway ?? const TraktSyncGateway();

  final TraktSyncGateway gateway;
  final ValueNotifier<TraktSyncState> state =
      ValueNotifier<TraktSyncState>(TraktSyncState.disconnected);
  final ValueNotifier<DateTime?> lastSuccessfulSync =
      ValueNotifier<DateTime?>(null);
  static const _addedKey = 'playtorrio_trakt_pending_add_v1';
  static const _removedKey = 'playtorrio_trakt_pending_remove_v1';
  static const _seenPrefix = 'playtorrio_trakt_remote_seen_v1_';
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
      List<MyListItem> values) async {
    await prefs.setString(key,
      jsonEncode(values.map((x) => x.toJson()).toList()));
  }

  /// Serialize journal writes so fast add/remove actions are not overwritten.
  Future<void> _journal(MyListItem item, {required bool add,
      bool acknowledge = false}) {
    final task = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final adds = _read(prefs, _addedKey);
      final removes = _read(prefs, _removedKey);
      if (acknowledge) {
        (add ? adds : removes).removeWhere((x) => x.matches(item));
      } else if (add) {
        removes.removeWhere((x) => x.matches(item));
        if (!adds.any((x) => x.matches(item))) adds.add(item);
      } else {
        adds.removeWhere((x) => x.matches(item));
        if (!removes.any((x) => x.matches(item))) removes.add(item);
      }
      await _write(prefs, _addedKey, adds);
      await _write(prefs, _removedKey, removes);
    });
    _writes = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  /// Save locally before trying to contact Trakt. Failed or offline writes
  /// remain in the journal and are retried during the next library refresh.
  Future<void> localChange(MyListItem item, {required bool added}) async {
    try {
      await _journal(item, add: added);
      if (!TraktMergePlan.hasCloudId(item) || !await gateway.connected()) return;
      final ok = added ? await gateway.add(item) : await gateway.remove(item);
      if (ok) {
        await _journal(item, add: added, acknowledge: true);
      } else {
        state.value = TraktSyncState.partial;
      }
    } catch (_) {
      state.value = TraktSyncState.partial;
    }
  }

  /// A successful full remote snapshot is a prerequisite for all merging.
  /// Account-specific remote history prevents stale watchlist items from
  /// being silently re-uploaded after deletion on another device.
  Future<bool> reconcile({
    required List<MyListItem> Function() readLocal,
    required Future<void> Function(List<MyListItem>) persistMerged,
  }) async {
    if (_running) return false;
    _running = true;
    try {
      if (!await gateway.connected()) {
        state.value = TraktSyncState.disconnected;
        return false;
      }
      state.value = TraktSyncState.syncing;
      await _writes;
      final fetched = await Future.wait([
        gateway.fetch('movies'), gateway.fetch('shows'),
      ]);
      // Never treat network/auth/JSON errors as an empty remote watchlist.
      if (fetched.any((x) => x == null)) {
        state.value = TraktSyncState.failed;
        return false;
      }
      final remote = <MyListItem>[];
      for (final record in [...fetched[0]!, ...fetched[1]!]) {
        if (record is Map<String, dynamic>) {
          remote.add(MyListItem.fromTraktJson(record));
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final account = (await gateway.username())?.trim().toLowerCase();
      // Do not apply deletion history if account identity is unavailable.
      final seenKey = account != null && account.isNotEmpty
          ? '$_seenPrefix${Uri.encodeComponent(account)}' : null;
      final previous = seenKey == null ? <MyListItem>[]
          : _read(prefs, seenKey);
      final pendingAdds = _read(prefs, _addedKey);
      final pendingRemoves = _read(prefs, _removedKey);
      final plan = TraktMergePlan.create(
        local: readLocal(), remote: remote, previouslySeen: previous,
        pendingAdds: pendingAdds, pendingRemoves: pendingRemoves,
      );
      // Remote removals are only applied when the same account was previously
      // observed, while first sign-in uploads *local* saves, not vice versa.
      await persistMerged(plan.merged);
      var fullySynced = true;
      final confirmed = <MyListItem>[...remote];

      for (final item in plan.toRemoveRemotely) {
        final ok = await gateway.remove(item);
        if (ok) {
          confirmed.removeWhere((x) => x.matches(item));
          await _journal(item, add: false, acknowledge: true);
        } else {
          fullySynced = false;
          break; // Do not hammer a failing or rate-limited Trakt API.
        }
      }

      if (fullySynced) {
        for (var i = 0; i < plan.toUpload.length; i += 50) {
          final count = (i + 50).clamp(0, plan.toUpload.length).toInt();
          final chunk = plan.toUpload.sublist(i, count);
          final movies = <Map<String, dynamic>>[];
          final shows = <Map<String, dynamic>>[];
          for (final item in chunk) {
            final entry = TraktMergePlan.toTraktEntry(item);
            if (entry == null) continue;
            if (item.type == 'series' || item.type == 'anime') {
              shows.add(entry);
            } else {
              movies.add(entry);
            }
          }
          final ok = await gateway.upload(movies, shows);
          if (!ok) {
            fullySynced = false;
            break; // Leave the unsent titles safely in the local journal.
          }
          for (final item in chunk) {
            if (!confirmed.any((x) => x.matches(item))) confirmed.add(item);
            await _journal(item, add: true, acknowledge: true);
          }
          if (count < plan.toUpload.length) {
            await Future<void>.delayed(const Duration(milliseconds: 450));
          }
        }
      }
      if (seenKey != null) await _write(prefs, seenKey, confirmed);
      if (fullySynced && plan.unsyncableCount == 0) {
        state.value = TraktSyncState.synced;
        lastSuccessfulSync.value = DateTime.now();
      } else {
        state.value = TraktSyncState.partial;
      }
      return fullySynced && plan.unsyncableCount == 0;
    } catch (e) {
      debugPrint('Trakt library synchronization failed (${e.runtimeType})');
      state.value = TraktSyncState.failed;
      return false;
    } finally {
      _running = false;
    }
  }
}
