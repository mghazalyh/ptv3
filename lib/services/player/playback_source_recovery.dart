import '../../models/stream/stream_model.dart';

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
        isHttpCandidate(source) && key(source) != key(active) &&
        !attemptedKeys.contains(key(source)));

  SourceRecoveryAction? next(StreamSource active, List<StreamSource> sources) {
    if (!isHttpCandidate(active)) return null;
    final activeKey = key(active);
    if (!failedKeys.contains(activeKey)) {
      final tries = _retryCount[activeKey] ?? 0;
      if (tries < maxRetriesPerSource) {
        _retryCount[activeKey] = tries + 1;
        return SourceRecoveryAction(active, retrySameSource: true);
      }
      failedKeys.add(activeKey);
    }
    if (_fallbacks >= maxAutomaticFallbacks) return null;
    final valid = sources.where((source) => isHttpCandidate(source) &&
        !failedKeys.contains(key(source)) && key(source) != activeKey).toList();
    if (valid.isEmpty) return null;
    // Keep source-list order within addon and resolution; prefer not to jump
    // from the selected 4K/Torbox item to an unrelated lower-quality provider.
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
    _fallbacks++;
    return SourceRecoveryAction(valid.first, retrySameSource: false);
  }

  void reset() {
    failedKeys.clear();
    _retryCount.clear();
    _fallbacks = 0;
    hasQueriedAlternatives = false;
  }
}
