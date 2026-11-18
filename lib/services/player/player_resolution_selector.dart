import '../../models/stream/stream_model.dart';
import '../player/debrid_source_readiness.dart';
import '../stream/source_content_identity.dart';
import '../stream/watch_source_preferences.dart';

/// One advertised resolution and its best eligible source for this episode.
/// Resolution labels are release metadata, not verified decoded dimensions.
class PlayerResolutionChoice {
  final String resolution;
  final StreamSource source;
  final int sourceCount;

  const PlayerResolutionChoice({
    required this.resolution,
    required this.source,
    required this.sourceCount,
  });
}

abstract final class PlayerResolutionSelector {
  static const priority = <String>[
    '8K', '6K', '4K', '1440p', '1080p', '720p', '480p', '360p',
  ];

  static final _fileName = RegExp(
    r'[^\r\n]{1,220}\.(?:mkv|mp4|m4v|avi|webm|ts)\b',
    caseSensitive: false,
  );
  static final _resolution = RegExp(
    r'(?<![a-z0-9])(?:'
    r'(8k|4320p|7680[\s]*[x×][\s]*4320)|'
    r'(6k|3240p|5760[\s]*[x×][\s]*3240)|'
    r'(4k|2160p|uhd|3840[\s]*[x×][\s]*2160|4096[\s]*[x×][\s]*2160)|'
    r'(1440p|qhd|2560[\s]*[x×][\s]*1440)|'
    r'(1080p|fhd|1920[\s]*[x×][\s]*1080)|'
    r'(720p|1280[\s]*[x×][\s]*720)|'
    r'(480p|854[\s]*[x×][\s]*480)|'
    r'(360p|640[\s]*[x×][\s]*360)'
    r')(?![a-z0-9])',
    caseSensitive: false,
  );

  static String? _fromText(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final match = _resolution.firstMatch(raw);
    if (match == null) return null;
    for (var i = 1; i <= priority.length; i++) {
      if (match.group(i) != null) return priority[i - 1];
    }
    return null;
  }

  static String? resolutionOf(StreamSource source) {
    // Filename metadata from Comet is more reliable than a generic
    // provider heading such as "[TB] Comet 1080p".
    final description = source.description ?? '';
    final filename = _fileName.firstMatch(description)?.group(0);
    return _fromText(filename) ??
        _fromText(source.title) ??
        _fromText(source.name) ??
        source.quality;
  }

  /// Quality changes retain the exact timestamp. Ordinary source failure
  /// recovery keeps its established five-second context rewind.
  static Duration? resumePosition({
    required Duration currentPosition,
    required bool sameEpisode,
    required bool deliberateQualityChange,
  }) {
    if (!sameEpisode) return null;
    if (deliberateQualityChange) return currentPosition;
    if (currentPosition > const Duration(seconds: 20)) {
      return currentPosition - const Duration(seconds: 5);
    }
    return null;
  }

  static bool isUsable(StreamSource source) {
    if (DebridSourceReadiness.isExplicitlyPending(source) ||
        source.behaviorHints?['isLive'] == true ||
        (source.externalUrl?.isNotEmpty ?? false)) return false;
    final raw = source.url?.trim() ?? '';
    final uri = Uri.tryParse(raw);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty && !uri.host.endsWith('.invalid')) return true;
    if (uri != null && uri.scheme == 'magnet') return true;
    return RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(source.infoHash ?? '');
  }

  static List<PlayerResolutionChoice> choices(
    Iterable<StreamSource> sources, {
    required String title,
    int? year,
    int? season,
    int? episode,
    required WatchSourceProfile profile,
    Map<String, bool> verified = const {},
  }) {
    final buckets = <String, List<StreamSource>>{};
    final seen = <String>{};
    for (final source in sources) {
      if (!isUsable(source)) continue;
      if (title.isNotEmpty && !SourceContentIdentity.isEligible(
        source, title: title, year: year, season: season, episode: episode,
      )) continue;
      final resolution = resolutionOf(source);
      if (resolution == null || !priority.contains(resolution)) continue;
      final key = '${source.addonName}|'
          '${source.url ?? source.infoHash ?? ""}|'
          '${source.fileIdx ?? ""}';
      if (!seen.add(key)) continue;
      (buckets[resolution] ??= <StreamSource>[]).add(source);
    }

    final selectionProfile = profile.copyWith(
      // The user deliberately chose the target resolution. Do not allow a
      // global 4K/1080p filter to hide 8K or 720p from this explicit picker.
      resolutions: const [],
      excludeLowQuality: false,
    );
    final result = <PlayerResolutionChoice>[];
    for (final resolution in priority) {
      final candidates = buckets[resolution];
      if (candidates == null || candidates.isEmpty) continue;
      // Uses the same verified identity, English language priority,
      // cache readiness and user sorting as Watch Sources.
      final ranked = WatchSourceEngine.process(
        candidates,
        selectionProfile,
        verified: verified,
        title: title,
        year: year,
        season: season,
        episode: episode,
      );
      if (ranked.isEmpty) continue;
      result.add(PlayerResolutionChoice(
        resolution: resolution,
        source: ranked.first,
        sourceCount: ranked.length,
      ));
    }
    return result;
  }
}
