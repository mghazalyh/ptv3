import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/addon/addon.dart';
import '../../models/movie/movie_section.dart';
import '../config/torriodb_portable_sync.dart';
import 'home_page_settings.dart';

@immutable
class HomeSectionOrderChoice {
  final String id;
  final String title;
  final String subtitle;
  const HomeSectionOrderChoice({
    required this.id,
    required this.title,
    required this.subtitle,
  });
}

/// Orders individual Home rows without putting credential-bearing addon URLs
/// into preference keys. Missing catalogs retain their saved positions.
abstract final class HomeSectionOrderService {
  static const storageKey = 'home_section_order_v1';
  static const continueWatchingId = 'fixed:continue_watching';
  static const maxKeys = 250;
  static final orderedKeys = ValueNotifier<List<String>>(const <String>[]);
  static bool _initialized = false;

  static String recommendationId(String id) =>
      'recommendation:${Uri.encodeComponent(id)}';

  static String catalogId(String addonId, String type, String catalogId) =>
      'catalog:${Uri.encodeComponent(addonId)}:'
      '${Uri.encodeComponent(type)}:${Uri.encodeComponent(catalogId)}';

  static String idForSection(MovieSection section) {
    if (section.isCurated ||
        (section.sourceAddonId == null &&
            HomePageSettings.isRecommendationSection(section))) {
      return recommendationId(section.catalog.id);
    }
    // The addon manager attaches the stable manifest ID at catalog fetch.
    // Legacy items use a one-way fingerprint, not the private manifest URL.
    final source = section.sourceAddonId ??
        'unknown-${_fingerprint(section.addonBaseUrl)}';
    return catalogId(source, section.catalog.type, section.catalog.id);
  }

  static String _fingerprint(String value) {
    var hash = 0xcbf29ce484222325;
    for (final code in value.codeUnits) {
      hash = ((hash ^ code) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  static List<String> normalize(Object? raw) {
    if (raw is! List || raw.length > maxKeys) {
      throw const FormatException('Invalid Home section order');
    }
    final found = <String>{};
    final normalized = <String>[];
    for (final item in raw) {
      if (item is! String || item.isEmpty || item.length > 512 ||
          item.contains('\n')) {
        throw const FormatException('Invalid Home section identifier');
      }
      if (found.add(item)) normalized.add(item);
    }
    return normalized;
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList(storageKey);
      if (values != null) orderedKeys.value = normalize(values);
    } catch (error) {
      debugPrint('[HomeOrder] Invalid saved preference (${error.runtimeType})');
      orderedKeys.value = const <String>[];
    }
    _initialized = true;
  }

  static List<T> apply<T>(List<T> source, String Function(T) idOf) {
    if (source.length < 2 || orderedKeys.value.isEmpty) {
      return List<T>.of(source);
    }
    final ranks = <String, int>{
      for (var i = 0; i < orderedKeys.value.length; i++)
        orderedKeys.value[i]: i,
    };
    final indexed = source.asMap().entries.toList();
    indexed.sort((a, b) {
      final aRank = ranks[idOf(a.value)] ?? 1073741824;
      final bRank = ranks[idOf(b.value)] ?? 1073741824;
      final comparison = aRank.compareTo(bRank);
      return comparison == 0 ? a.key.compareTo(b.key) : comparison;
    });
    return [for (final entry in indexed) entry.value];
  }

  static Future<void> saveVisibleOrder(List<String> visible) async {
    final selected = normalize(visible);
    final displayed = selected.toSet();
    await _save(normalize([
      ...selected,
      for (final existing in orderedKeys.value)
        if (!displayed.contains(existing)) existing,
    ]), fromCloud: false);
  }

  static Future<void> reset() =>
      _save(const <String>[], fromCloud: false);

  static Future<void> restoreFromCloud(List<String> order) =>
      _save(normalize(order), fromCloud: true);

  static Future<void> _save(List<String> order,
      {required bool fromCloud}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(storageKey, order);
    orderedKeys.value = List<String>.unmodifiable(order);
    _initialized = true;
    if (!fromCloud) {
      try {
        await TorriodbPortableSync.instance.markChanged('homeOrder');
      } catch (error) {
        debugPrint('[HomeOrder] Sync queued locally (${error.runtimeType})');
      }
    }
  }

  static List<HomeSectionOrderChoice> choices({
    required List<InstalledAddon> addons,
    required List<MovieSection> loaded,
  }) {
    final all = <String, HomeSectionOrderChoice>{};

    void add(String id, String title, String subtitle) {
      all.putIfAbsent(id,
          () => HomeSectionOrderChoice(id: id, title: title, subtitle: subtitle));
    }

    add(continueWatchingId, 'Continue Watching', 'Your active playback');
    if (HomePageSettings.enableWatchingSimilar.value) {
      for (var index = 1; index <= 3; index++) {
        add(recommendationId('bestsimilar_watching_$index'),
            'Because You Watched / Are Watching · $index',
            'Based on playback history');
      }
    }
    if (HomePageSettings.enableSimilar.value) {
      add(recommendationId('bestsimilar_list'),
          'Because You Have It on Your List', 'My List recommendations');
    }
    if (HomePageSettings.enableTraktRecommendations.value) {
      add(recommendationId('trakt_recommendations'),
          'Recommended for You (Trakt)', 'Personalized Trakt recommendations');
    }
    if (HomePageSettings.enableSimklRecommendations.value) {
      add(recommendationId('simkl_recommendations'),
          'Top Rated on Simkl', 'Simkl recommendations');
    }

    for (final addon in addons) {
      if (!addon.isCatalogsActive) continue;
      for (final catalog in addon.manifest.catalogs) {
        // Stremio manifests may omit catalog.name or provide whitespace.
        // Fall back to the stable catalog ID without a nullable dereference.
        final title = catalog.name?.trim();
        add(
          catalogId(addon.manifest.id, catalog.type, catalog.id),
          title == null || title.isEmpty ? catalog.id : title,
          addon.manifest.name,
        );
      }
    }
    for (final section in loaded) {
      final id = idForSection(section);
      all[id] = HomeSectionOrderChoice(
        id: id, title: section.title, subtitle: section.subtitle,
      );
    }
    return apply(all.values.toList(), (choice) => choice.id);
  }
}
