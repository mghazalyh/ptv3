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

  /// Resolver-generated error slates are valid MP4 video to the native
  /// decoder: opening and advancing playback do not prove a full TV episode
  /// exists. Comet and TorBox slates also omit size or run for two minutes,
  /// so neither a 200 MB label nor the old 90 second limit is dependable.
  ///
  /// Requires a TV episode, a real HTTP URL, an explicit debrid badge or
  /// a known debrid resolver, and a duration implausible for a full episode.
  /// A small declared file is left alone because it may be a genuine clip.
  /// Movies, P2P, local files, live streams and externally launched media
  /// never qualify. This only selects alternatives already identity-checked.
  static bool isShortStatusClip({
    required StreamSource source,
    required Duration duration,
    required bool isEpisode,
  }) {
    if (!isEpisode ||
        duration < const Duration(seconds: 8) ||
        duration > const Duration(minutes: 10)) {
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
    final name = source.addonName.toLowerCase();
    final hasDebridBadge = _debridBadge.hasMatch(source.name ?? '');
    final knownDebridResolver =
        name.contains('comet') || name.contains('torrentio');
    if (!hasDebridBadge && !knownDebridResolver) return false;
    final size = source.sizeBytes;
    if (size != null && size < 200 * 1024 * 1024) return false;
    // Absent size is NOT proof of playable content. A Comet/TorBox source
    // advertising a full episode but decoding as a short clip is rejected.
    return true;
  }
}
