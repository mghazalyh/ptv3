import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/my_list/my_list_item.dart';
import 'simkl_hearts_cloud.dart';
import 'github_library_cloud.dart';
import 'trakt_cloud_library.dart';

abstract final class MyListService {
  static const _storageKey = 'my_list_v1';
  static const int maxItems = 2500;
  static final TraktCloudLibrary traktCloud = TraktCloudLibrary();
  static final SimklHeartsCloud simklCloud = SimklHeartsCloud();
  static DateTime? _lastAutoRefresh;
  static Timer? _syncDebounce;
  static GitHubLibraryCloud get githubCloud => GitHubLibraryCloud.instance;

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
    await githubCloud.initialize();
    unawaited(syncAll());
  }

  /// My List is owned by GitHub sync only. Trakt and Simkl remain available
  /// for their separate playback/history features but cannot overwrite it.
  static Future<void> syncAll({bool force = false}) async {
    if (!githubCloud.configured || isSyncing.value) return;
    if (!force && _lastAutoRefresh != null &&
        DateTime.now().difference(_lastAutoRefresh!) <
            const Duration(seconds: 60)) return;
    _lastAutoRefresh = DateTime.now();
    isSyncing.value = true;
    try {
      await githubCloud.sync(
        readLocal: () => List<MyListItem>.from(items.value),
        persistMerged: (merged) async {
          items.value = merged;
          await _persist();
        },
      );
    } finally {
      isSyncing.value = false;
    }
  }

  static void _queueGitHubEdit(MyListItem item, {required bool added}) {
    githubCloud.recordEdit(item, added: added);
    if (!githubCloud.configured) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 5), () {
      unawaited(syncAll(force: true));
    });
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

    _queueGitHubEdit(item, added: true);
  }

  static void remove(MyListItem item) {
    final current = items.value;
    final next = current.where((candidate) =>
        candidate.uniqueKey != item.uniqueKey && !candidate.matches(item)).toList();
    if (next.length == current.length) return;
    items.value = next;
    unawaited(_persist());
    _queueGitHubEdit(item, added: false);
  }

  static void toggle(MyListItem item) {
    if (isInList(item)) {
      remove(item);
    } else {
      add(item);
    }
  }
}
