import '../subtitles/subtitle_parser.dart';

/// Pure subtitle validation and native track selection checks.
/// No filenames, media IDs, URLs, or cue text leave the player.
enum SubtitleTrackReadiness { selected, inactive, unknown }

abstract final class SubtitleActivationGuard {
  static bool hasRenderableCues(SubtitleParseResult parsed) =>
      parsed.cues.any((cue) =>
          cue.start.isFinite &&
          cue.end.isFinite &&
          cue.start >= 0 &&
          cue.end > cue.start &&
          cue.text.trim().isNotEmpty);

  static SubtitleTrackReadiness classifySid(Object? sid) {
    if (sid == null) return SubtitleTrackReadiness.unknown;
    final value = sid.toString().trim().toLowerCase();
    if (value.isEmpty) return SubtitleTrackReadiness.unknown;
    if (value == 'no' || value == 'auto' || value == '0') {
      return SubtitleTrackReadiness.inactive;
    }
    final id = int.tryParse(value);
    if (id == null) return SubtitleTrackReadiness.unknown;
    return id > 0
        ? SubtitleTrackReadiness.selected
        : SubtitleTrackReadiness.inactive;
  }

  /// MPV may select external subtitles asynchronously after an attach command.
  /// Native property failures are unknown, never falsely "selected".
  static Future<SubtitleTrackReadiness> waitForSelection(
    Future<Object?> Function() readSid, {
    int attempts = 5,
    Duration interval = const Duration(milliseconds: 200),
  }) async {
    var last = SubtitleTrackReadiness.unknown;
    for (var i = 0; i < attempts; i++) {
      try {
        last = classifySid(await readSid());
        if (last == SubtitleTrackReadiness.selected) return last;
      } catch (_) {
        return SubtitleTrackReadiness.unknown;
      }
      if (i + 1 < attempts) await Future<void>.delayed(interval);
    }
    return last;
  }
}
