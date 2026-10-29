import 'dart:math' as math;

import '../subtitles/subtitle_parser.dart';

/// Timestamped words recognized from a short sample of the media's actual
/// audio. These times are absolute on the playback timeline (not clip-relative).
class SpeechTimedWord {
  final String text;
  final double startSeconds;

  const SpeechTimedWord({required this.text, required this.startSeconds});
}

class SpeechSubtitleOffset {
  /// The absolute mpv sub-delay that aligns raw subtitle cues to speech.
  final double delaySeconds;
  final int supportingCues;
  final double spreadSeconds;

  const SpeechSubtitleOffset({
    required this.delaySeconds,
    required this.supportingCues,
    required this.spreadSeconds,
  });
}

/// Conservative spoken-word alignment: no "best guess" offset is applied when
/// the transcript lacks multiple independent, time-consistent phrase matches.
///
/// The algorithm compares normalized 3-7 word subtitle phrases with the
/// recognized speech words and takes a median of agreeing cue offsets.
/// This protects against recurring dialogue, music, silence, credits and
/// wrongly matched subtitle releases.
abstract final class SpeechSubtitleAlignment {
  static const double maxAdjustmentSeconds = 150.0;
  static final RegExp _wordChars = RegExp(r"[a-z0-9]+");

  static List<String> normalize(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'\{[^}]*\}'), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .toLowerCase();
    return _wordChars.allMatches(cleaned)
        .map((m) => m.group(0)!)
        .toList(growable: false);
  }

  static SpeechSubtitleOffset? estimate({
    required List<SubCue> cues,
    required List<SpeechTimedWord> speech,
    required double sampleStartSeconds,
    required double sampleEndSeconds,
  }) {
    if (speech.length < 12 || cues.length < 2 ||
        !sampleStartSeconds.isFinite || !sampleEndSeconds.isFinite ||
        sampleEndSeconds <= sampleStartSeconds) return null;

    final words = <String>[];
    final timestamps = <double>[];
    for (final spoken in speech) {
      if (!spoken.startSeconds.isFinite ||
          spoken.startSeconds < sampleStartSeconds - 1 ||
          spoken.startSeconds > sampleEndSeconds + 1) continue;
      for (final token in normalize(spoken.text)) {
        words.add(token);
        timestamps.add(spoken.startSeconds);
      }
    }
    if (words.length < 12) return null;

    // Each cue contributes at most one alignment vote, even if many of its
    // overlapping phrases matched. Do not let one long caption dominate.
    final offsets = <double>[];
    for (final cue in cues) {
      if (!cue.start.isFinite || !cue.end.isFinite || cue.end <= cue.start ||
          cue.start < sampleStartSeconds - maxAdjustmentSeconds ||
          cue.start > sampleEndSeconds + maxAdjustmentSeconds) continue;
      final caption = normalize(cue.text);
      if (caption.length < 3 || caption.length > 38) continue;

      double? bestOffset;
      int bestLength = 0;
      double bestDistance = double.infinity;
      for (var prefix = 0; prefix <= caption.length - 3; prefix++) {
        final length = math.min(7, caption.length - prefix);
        if (length < 3) continue;
        final phrase = caption.sublist(prefix, prefix + length);
        // Require sufficiently distinct speech; common filler phrases are
        // especially prone to accidental matches.
        if (phrase.toSet().length < 3 ||
            phrase.where((w) => w.length >= 4).length < 2) continue;

        for (var j = 0; j <= words.length - length; j++) {
          var same = true;
          for (var k = 0; k < length; k++) {
            if (words[j + k] != phrase[k]) {
              same = false;
              break;
            }
          }
          if (!same) continue;
          // A subtitle caption can span multiple words. A phrase that begins
          // later in that cue has no reliable word-level subtitle timestamp.
          // Anchor only the START of the caption to the first spoken word.
          if (prefix != 0) continue;
          final offset = timestamps[j] - cue.start;
          if (offset.abs() > maxAdjustmentSeconds) continue;
          if (length > bestLength ||
              (length == bestLength && offset.abs() < bestDistance)) {
            bestLength = length;
            bestDistance = offset.abs();
            bestOffset = offset;
          }
        }
      }
      if (bestOffset != null) offsets.add(bestOffset);
    }
    if (offsets.length < 2) return null;

    // Find the tightest agreeing group, not the median of possibly unrelated
    // matches. Multiple occurrences of a phrase cannot force a large shift.
    offsets.sort();
    List<double> bestCluster = [];
    for (var i = 0; i < offsets.length; i++) {
      final cluster = offsets.skip(i).takeWhile(
          (value) => value - offsets[i] <= 1.8).toList();
      if (cluster.length > bestCluster.length) bestCluster = cluster;
    }
    if (bestCluster.length < 2 ||
        bestCluster.length * 2 < offsets.length) return null;
    final median = bestCluster[bestCluster.length ~/ 2];
    final spread = bestCluster.last - bestCluster.first;
    if (spread > 1.8 || median.abs() > maxAdjustmentSeconds) return null;
    return SpeechSubtitleOffset(
      delaySeconds: median,
      supportingCues: bestCluster.length,
      spreadSeconds: spread,
    );
  }
}
