import '../../models/stream/stream_model.dart';
import 'debrid_source_readiness.dart';

/// Pure, session-local bounded opening recovery. No IO, URL logs, upload or P2P.
class SourceRecoveryAction {
  final StreamSource source;
  final bool retrySameSource;
  const SourceRecoveryAction(this.source, {required this.retrySameSource});
}

class PlaybackSourceRecovery {
  static const maxRetriesPerSource = 1; // Two total openings per URL.
  static const maxAutomaticFallbacks = 4;
  final Set<String> failedKeys = <String>{};
  final Map<String, int> _retryCount = <String, int>{};
  int _fallbacks = 0;
  bool hasQueriedAlternatives = false;

  static bool isHttpCandidate(StreamSource source) {
    final url = source.url;
    if (source.behaviorHints?['isLive'] == true || url == null) return false;
    final uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty && (source.externalUrl?.isEmpty ?? true);
  }

  static String key(StreamSource s) => '${s.addonName.toLowerCase()}|'
      '${s.url ?? ''}|${s.fileIdx ?? ''}';

  static bool hasAlternative(StreamSource active, List<StreamSource> sources,
      {required Set<String> attemptedKeys}) => sources.any((source) =>
        isHttpCandidate(source) &&
        !DebridSourceReadiness.isExplicitlyPending(source) &&
        key(source) != key(active) &&
        !attemptedKeys.contains(key(source)));

  SourceRecoveryAction? next(
    StreamSource active,
    List<StreamSource> sources, {
    bool skipCurrentRetry = false,
    bool followPickerOrder = false,
  }) {
    if (!isHttpCandidate(active)) return null;
    final activeKey = key(active);
    if (!failedKeys.contains(activeKey)) {
      final tries = _retryCount[activeKey] ?? 0;
      // Reopening an explicitly unready source returns another placeholder.
      if (!skipCurrentRetry &&
          !DebridSourceReadiness.isExplicitlyPending(active) &&
          tries < maxRetriesPerSource) {
        _retryCount[activeKey] = tries + 1;
        return SourceRecoveryAction(active, retrySameSource: true);
      }
      failedKeys.add(activeKey);
    }
    if (_fallbacks >= maxAutomaticFallbacks) return null;

    // De-duplicate at the source URL level; a provider can repeat the same
    // resolver URL with different labels or entries in several lists.
    final seen = <String>{};
    final valid = sources.where((source) =>
        isHttpCandidate(source) &&
        !DebridSourceReadiness.isExplicitlyPending(source) &&
        !failedKeys.contains(key(source)) &&
        key(source) != activeKey &&
        seen.add(key(source))).toList();
    if (valid.isEmpty) return null;

    StreamSource chosen;
    if (followPickerOrder) {
      // Use the exact ordered list passed from Watch Sources. Start after
      // the selected entry and wrap once, skipping known download stubs.
      final chosenIndex = sources.indexWhere((s) => key(s) == activeKey);
      final ordered = <StreamSource>[
        if (chosenIndex >= 0) ...sources.skip(chosenIndex + 1),
        if (chosenIndex >= 0) ...sources.take(chosenIndex),
        if (chosenIndex < 0) ...sources,
      ];
      final validKeys = valid.map(key).toSet();
      chosen = ordered.firstWhere((s) => validKeys.contains(key(s)));
    } else {
      // Preserve the existing direct-HTTP error preference, but never pick
      // another known-uncached debrid item.
      int rank(StreamSource source) {
        var score = 0;
        if (source.addonName.toLowerCase() == active.addonName.toLowerCase()) {
          score += 10;
        }
        if (source.quality == active.quality) score += 5;
        if (source.codec == active.codec) score += 1;
        return score;
      }
      valid.sort((a, b) => rank(b).compareTo(rank(a)));
      chosen = valid.first;
    }
    _fallbacks++;
    return SourceRecoveryAction(chosen, retrySameSource: false);
  }

  void reset() {
    failedKeys.clear();
    _retryCount.clear();
    _fallbacks = 0;
    hasQueriedAlternatives = false;
  }
}
