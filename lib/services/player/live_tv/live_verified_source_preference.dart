import 'package:flutter/foundation.dart';

import '../../../models/stream/stream_model.dart';

/// Remembers only native-video-verified Live TV sources for this app session.
/// In particular, HTTP 200/206 alone must NEVER populate this cache.
///
/// Exact addon + URL matching prevents one stream from being confused with
/// another using the same CDN hostname. URLs stay in memory only, and expire
/// after 20 minutes. Signed URLs are never persisted or uploaded.
abstract final class LiveVerifiedSourcePreference {
  static const Duration maxAge = Duration(minutes: 20);

  static final Map<String, _VerifiedLiveSource> _entries =
      <String, _VerifiedLiveSource>{};

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static void remember({
    required String channelId,
    required StreamSource verifiedSource,
  }) {
    final id = channelId.trim();
    final url = verifiedSource.url?.trim();
    final addon = verifiedSource.addonName.trim();
    if (id.isEmpty || url == null || url.isEmpty || addon.isEmpty) {
      debugPrint('[LiveSourcePreference] Ignored invalid source identity');
      return;
    }
    _entries[id] = _VerifiedLiveSource(
      url: url,
      addonName: addon,
      verifiedAt: clock(),
    );
  }

  static List<StreamSource> prioritize(
    String channelId,
    Iterable<StreamSource> sources,
  ) {
    final ordered = sources.toList();
    final id = channelId.trim();
    final cached = _entries[id];
    if (cached == null || ordered.length < 2) return ordered;

    final age = clock().difference(cached.verifiedAt);
    if (age.isNegative || age > maxAge) {
      _entries.remove(id);
      return ordered;
    }

    final match = ordered.indexWhere((source) =>
        source.url == cached.url &&
        source.addonName == cached.addonName);
    if (match <= 0) return ordered;

    final best = ordered.removeAt(match);
    ordered.insert(0, best);
    return ordered;
  }

  /// A failed playback must no longer be promoted by an earlier scan.
  static void invalidate(String channelId, StreamSource failedSource) {
    final id = channelId.trim();
    final stored = _entries[id];
    if (stored == null) return;
    if (stored.url == failedSource.url &&
        stored.addonName == failedSource.addonName) {
      _entries.remove(id);
    }
  }

  @visibleForTesting
  static void clearForTesting() {
    _entries.clear();
    clock = DateTime.now;
  }
}

@immutable
class _VerifiedLiveSource {
  const _VerifiedLiveSource({
    required this.url,
    required this.addonName,
    required this.verifiedAt,
  });

  final String url;
  final String addonName;
  final DateTime verifiedAt;
}
