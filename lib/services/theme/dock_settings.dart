import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/torriodb_portable_sync.dart';

enum DockItemKey {
  home(
    key: 'home',
    label: 'Home',
    icon: Icons.home_rounded,
    isRemovable: false,
    description: 'Explore trending, continue watching, and catalog recommendations.',
  ),
  networks(
    key: 'networks',
    label: 'Networks',
    icon: Icons.hub_rounded,
    isRemovable: true,
    description: 'Trending, Hot and Popular shows by streaming service or TV network.',
  ),
  manga(
    key: 'manga',
    label: 'Manga',
    icon: Icons.auto_stories_rounded,
    isRemovable: true,
    description: 'Browse, search, and read manga and webtoons.',
  ),
  books(
    key: 'books',
    label: 'Books',
    icon: Icons.menu_book_rounded,
    isRemovable: true,
    description: 'Read EPUB and PDF eBooks with custom themes.',
  ),
  audiobooks(
    key: 'audiobooks',
    label: 'Audiobooks',
    icon: Icons.headphones_rounded,
    isRemovable: true,
    description: 'Listen to narrated audiobooks with chapter bookmarks.',
  ),
  music(
    key: 'music',
    label: 'Music',
    icon: Icons.music_note_rounded,
    isRemovable: true,
    description: 'High-res lossless streaming, visualizer, and studio playback.',
  ),
  anime(
    key: 'anime',
    label: 'Anime',
    icon: Icons.animation_rounded,
    isRemovable: true,
    description: 'Discover trending seasonal anime, Arabic/Eng subs, and episodes.',
  ),
  liveTv(
    key: 'livetv',
    label: 'Live TV',
    icon: Icons.live_tv_rounded,
    isRemovable: true,
    description: 'Watch worldwide live television channels and sports streams.',
  ),
  addons(
    key: 'addons',
    label: 'Addons',
    icon: Icons.extension_rounded,
    isRemovable: true,
    description: 'Manage installed Stremio add-ons, catalogs, and scrapers.',
  ),
  downloads(
    key: 'downloads',
    label: 'Downloads',
    icon: Icons.download_rounded,
    isRemovable: true,
    description: 'View active torrent and direct media download tasks.',
  ),
  myList(
    key: 'mylist',
    label: 'My List',
    icon: Icons.favorite_rounded,
    isRemovable: true,
    description: 'Access your saved bookmarks, watchlist, and favorites.',
  ),
  settings(
    key: 'settings',
    label: 'Settings',
    icon: Icons.settings_rounded,
    isRemovable: false,
    description: 'App preferences, accounts, appearance, and player options.',
  ),
  search(
    key: 'search',
    label: 'Search',
    icon: Icons.search_rounded,
    isRemovable: true,
    description: 'Global search across all catalog metadata and addons.',
  );

  final String key;
  final String label;
  final IconData icon;
  final bool isRemovable;
  final String description;

  const DockItemKey({
    required this.key,
    required this.label,
    required this.icon,
    required this.isRemovable,
    required this.description,
  });
}

abstract final class DockSettings {
  static const String _prefPrefix = 'dock_item_enabled_';
  static const String _visibleKey = 'dock_visible_v1';
  static final ValueNotifier<bool> visibleNotifier = ValueNotifier<bool>(true);
  static bool get isVisible => visibleNotifier.value;

  /// Reactive notifier containing the map of enabled dock item keys.
  static final ValueNotifier<Map<String, bool>> enabledNotifier =
      ValueNotifier<Map<String, bool>>({
    for (final item in DockItemKey.values) item.key: true,
  });

  /// Initialize and load saved state from SharedPreferences.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    visibleNotifier.value = prefs.getBool(_visibleKey) ?? true;
    final map = <String, bool>{};

    for (final item in DockItemKey.values) {
      if (!item.isRemovable) {
        // Home and Settings are strictly non-removable
        map[item.key] = true;
      } else {
        map[item.key] = prefs.getBool('$_prefPrefix${item.key}') ?? true;
      }
    }

    enabledNotifier.value = map;
  }

  /// Check whether a specific item key is currently enabled.
  static bool isEnabled(String key) {
    if (key == 'home' || key == 'settings') return true;
    return enabledNotifier.value[key] ?? true;
  }

  /// Toggle or update the enabled status of an item.
  static Future<void> setItemEnabled(String key, bool enabled) async {
    // Prevent disabling non-removable essential items
    if (key == 'home' || key == 'settings') return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefPrefix$key', enabled);

    final updated = Map<String, bool>.from(enabledNotifier.value);
    updated[key] = enabled;
    enabledNotifier.value = updated;
    await TorriodbPortableSync.instance.markChanged('dock');
  }

  /// Reset all dock item toggles to enabled default.
  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    for (final item in DockItemKey.values) {
      if (item.isRemovable) {
        await prefs.remove('$_prefPrefix${item.key}');
      }
    }

    enabledNotifier.value = {
      for (final item in DockItemKey.values) item.key: true,
    };
    await setDockVisible(true);
    await TorriodbPortableSync.instance.markChanged('dock');
  }

  static Future<void> setDockVisible(bool visible, {bool fromCloud = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_visibleKey, visible);
    visibleNotifier.value = visible;
    if (!fromCloud) await TorriodbPortableSync.instance.markChanged('dock');
  }

  static Map<String, dynamic> snapshot() => {
    'visible': isVisible,
    'items': {for (final entry in enabledNotifier.value.entries) entry.key: entry.value},
  };

  static Map<String, dynamic> normalize(Object? raw) {
    if (raw is! Map || raw['visible'] is! bool || raw['items'] is! Map) {
      throw const FormatException('Invalid dock configuration');
    }
    final items = Map<String, dynamic>.from(raw['items'] as Map);
    final allowed = DockItemKey.values.map((e) => e.key).toSet();
    if (items.keys.any((key) => !allowed.contains(key)) ||
        items.values.any((value) => value is! bool)) {
      throw const FormatException('Invalid dock icon preference');
    }
    return {'visible': raw['visible'], 'items': items};
  }

  static Future<void> restoreFromCloud(Object? raw) async {
    final parsed = normalize(raw);
    final items = Map<String, dynamic>.from(parsed['items'] as Map);
    final prefs = await SharedPreferences.getInstance();
    final updated = Map<String, bool>.from(enabledNotifier.value);
    for (final item in DockItemKey.values) {
      if (!item.isRemovable) continue;
      if (items[item.key] is bool) {
        await prefs.setBool('$_prefPrefix${item.key}', items[item.key] as bool);
        updated[item.key] = items[item.key] as bool;
      }
    }
    enabledNotifier.value = updated;
    await setDockVisible(parsed['visible'] as bool, fromCloud: true);
  }
}
