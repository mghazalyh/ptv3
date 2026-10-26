import '../../models/movie/video.dart';
import '../../models/stream/stream_model.dart';
import '../../models/subtitle/subtitle_model.dart';
import 'audio_language_priority.dart';

/// Deterministic per-media English subtitle and continuous episode defaults.
/// Does not modify user-selected audio or subtitles during an episode.
abstract final class PlaybackAutoselection {
  static bool isEnglishSubtitle({String? language, String? title}) {
    return AudioLanguagePriority.isEnglish(language: language, title: title);
  }

  static bool isForcedSubtitle(String label) =>
      RegExp(r'(^|[^a-z])forced([^a-z]|$)', caseSensitive: false)
          .hasMatch(label);

  /// Forced English tracks first, followed by any embedded English subtitles.
  static PlayerEmbeddedSubtitle? preferredEmbedded(
      List<PlayerEmbeddedSubtitle> tracks) {
    final english = tracks.where((track) => isEnglishSubtitle(
      language: track.language, title: track.title)).toList();
    english.sort((a, b) {
      final aForced = isForcedSubtitle(a.title) ? 0 : 1;
      final bForced = isForcedSubtitle(b.title) ? 0 : 1;
      return aForced.compareTo(bForced);
    });
    return english.firstOrNull;
  }

  /// External backup when no embedded English track is available.
  /// Prefer English forced tracks, then OpenSubtitles, then other providers.
  static List<SubtitleVariant> preferredExternal(
      List<SubtitleLanguageGroup> groups) {
    final english = groups
        .expand((group) => group.variants)
        .where((variant) => isEnglishSubtitle(
          language: variant.language, title: variant.title))
        .toList();
    int rank(SubtitleVariant variant) {
      if (isForcedSubtitle(variant.title)) return 0;
      if (variant.providerName.toLowerCase().contains('opensubtitles')) {
        return 1;
      }
      return 2;
    }
    english.sort((a, b) => rank(a).compareTo(rank(b)));
    return english;
  }

  /// The following numbered episode, including across season boundaries.
  /// Never assume that arbitrary metadata order is chronological.
  static Video? nextEpisode(List<Video> episodes, Video? current) {
    if (current?.episode == null || current?.season == null) return null;
    final upcoming = episodes.where((ep) {
      if (ep.season == null || ep.episode == null) return false;
      if (ep.season! > current!.season!) return true;
      return ep.season == current.season &&
          ep.episode! > current.episode!;
    }).toList();
    upcoming.sort((a, b) {
      final season = a.season!.compareTo(b.season!);
      return season != 0 ? season : a.episode!.compareTo(b.episode!);
    });
    return upcoming.firstOrNull;
  }

  static StreamSource? preferredSource(
      List<StreamSource> candidates, StreamSource previous) {
    if (candidates.isEmpty) return null;
    final usable = candidates.where((source) =>
        (source.url?.isNotEmpty ?? false) ||
        (source.infoHash?.isNotEmpty ?? false)).toList();
    if (usable.isEmpty) return null;
    final addon = previous.addonName.toLowerCase().trim();
    final previousLabel = previous.name?.toLowerCase().trim() ?? '';
    usable.sort((a, b) {
      int score(StreamSource source) {
        var value = 0;
        if (source.addonName.toLowerCase().trim() == addon) value += 100;
        if (previousLabel.isNotEmpty &&
            (source.name?.toLowerCase().trim() ?? '') == previousLabel) {
          value += 15;
        }
        if (source.url?.startsWith('https://') == true ||
            source.url?.startsWith('http://') == true) {
          value += 5;
        }
        value -= AudioLanguagePriority.torrentioAudioRank(source) * 2;
        return value;
      }
      return score(b).compareTo(score(a));
    });
    return usable.first;
  }
}
