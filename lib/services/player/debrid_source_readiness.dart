import '../../models/stream/stream_model.dart';

/// Only provider-advertised statuses are known before attempting playback.
/// Unknown source availability is never inferred from seed count or size.
abstract final class DebridSourceReadiness {
  static final RegExp _pendingBadge = RegExp(
    r'^\s*\[(?:tb|rd|ad|pm)\s+(?:download|downloading|uncached|pending)\b',
    caseSensitive: false,
  );

  static final RegExp _debridBadge = RegExp(
    r'^\s*\[(?:tb|rd|ad|pm)(?:\s|\+|\])',
    caseSensitive: false,
  );

  /// A 'download' source is an unready debrid job, not a playable movie.
  static bool isExplicitlyPending(StreamSource source) =>
      _pendingBadge.hasMatch(source.name ?? '');

  /// Lower is better. This does not certify the other sources as cached.
  static int sortTier(StreamSource source) =>
      isExplicitlyPending(source) ? 1 : 0;

  /// A gigabyte-scale TV episode resolving as a ~29-second video is almost
  /// certainly a provider-generated status clip, not the requested episode.
  /// This intentionally excludes short genuine clips, films without an episode
  /// context, local media and sources lacking explicit size/debrid signals.
  static bool isShortStatusClip({
    required StreamSource source,
    required Duration duration,
    required bool isEpisode,
  }) {
    if (!isEpisode ||
        duration < const Duration(seconds: 8) ||
        duration > const Duration(seconds: 90) ||
        (source.sizeBytes ?? 0) < 200 * 1024 * 1024) {
      return false;
    }
    final url = Uri.tryParse(source.url ?? '');
    if (url == null ||
        (url.scheme != 'http' && url.scheme != 'https') ||
        url.host.isEmpty ||
        source.behaviorHints?['isLive'] == true ||
        (source.externalUrl?.isNotEmpty ?? false)) {
      return false;
    }
    return _debridBadge.hasMatch(source.name ?? '') ||
        source.addonName.toLowerCase().contains('torrentio');
  }
}
