import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/my_list/my_list_item.dart';
import 'simkl_hearts_cloud.dart';
import 'trakt_cloud_library.dart';

abstract final class MyListService {
  static const _storageKey = 'my_list_v1';
  static const int maxItems = 500;
  static final TraktCloudLibrary traktCloud = TraktCloudLibrary();
  static final SimklHeartsCloud simklCloud = SimklHeartsCloud();
  static DateTime? _lastAutoRefresh;

  static final ValueNotifier<List<MyListItem>> items = ValueNotifier<List<MyListItem>>([]);
  static final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored != null) {
      try {
        final list = (jsonDecode(stored) as List)
            .map((e) => MyListItem.fromJson(e as Map<String, dynamic>))
            .toList();
        items.value = list;
      } catch (_) {
        items.value = [];
      }
    }
    syncAll();
  }

  /// Automatic refresh on startup and opening My List is intentionally
  /// throttled; the refresh button can force another sync at any time.
  static Future<void> syncAll({bool force = false}) async {
    if (isSyncing.value) return;
    if (!force && _lastAutoRefresh != null &&
        DateTime.now().difference(_lastAutoRefresh!) <
            const Duration(seconds: 90)) return;
    _lastAutoRefresh = DateTime.now();
    isSyncing.value = true;
    try {
      await syncWithTrakt();
      // Serialize both cloud providers: avoid concurrent writes to My List.
      await syncWithSimkl();
    } finally {
      isSyncing.value = false;
    }
  }

  static Future<void> syncWithTrakt() async {
    await traktCloud.reconcile(
      readLocal: () => List<MyListItem>.from(items.value),
      persistMerged: (merged) async {
        final visible = merged.take(maxItems).toList();
        items.value = visible;
        await _persist();
      },
    );
  }

  static Future<void> syncWithSimkl() async {
    await simklCloud.reconcile(
      readLocal: () => List<MyListItem>.from(items.value),
      persistMerged: (merged) async {
        items.value = merged.take(maxItems).toList();
        await _persist();
      },
    );
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(items.value.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  static bool isInList(MyListItem item) {
    return items.value.any((i) => i.uniqueKey == item.uniqueKey || i.matches(item));
  }

  static void add(MyListItem item) {
    if (isInList(item)) return;

    final newList = <MyListItem>[...items.value, item];
    newList.sort((a, b) => b.addedAt.compareTo(a.addedAt));

    if (newList.length > maxItems) {
      newList.removeRange(maxItems, newList.length);
    }

    items.value = newList;
    unawaited(_persist());

    // Journal before sending to Trakt; failed/offline edits retry on refresh.
    unawaited(traktCloud.localChange(item, added: true));
    unawaited(_syncSimklEdit(item, added: true));
  }

  static Future<void> _syncSimklEdit(MyListItem item,
      {required bool added}) async {
    await simklCloud.localChange(item, added: added);
    // A forced refresh performs one activities-gated reconciliation, not
    // a separate Simkl POST for each rapid heart tap.
    unawaited(syncAll(force: true));
  }

  static void remove(MyListItem item) {
    final current = items.value;
    final next = current.where((candidate) =>
        candidate.uniqueKey != item.uniqueKey && !candidate.matches(item)).toList();
    if (next.length == current.length) return;
    items.value = next;
    unawaited(_persist());
    unawaited(traktCloud.localChange(item, added: false));
    unawaited(_syncSimklEdit(item, added: false));
  }

  static void toggle(MyListItem item) {
    if (isInList(item)) {
      remove(item);
    } else {
      add(item);
    }
  }
}
