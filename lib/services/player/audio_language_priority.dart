import '../../models/stream/stream_model.dart';

/// Language preferences apply to every Stremio addon, never just one provider.
/// Release metadata is advisory; MPV's actual tracks remain authoritative.
abstract final class AudioLanguagePriority {
  static const String mpvPreferredLanguages = 'eng,en,en-US,en-GB';

  static final RegExp _english = RegExp(
    r'(^|[^a-z])(english|eng|en-us|en-gb)([^a-z]|$)',
    caseSensitive: false,
  );
  static final RegExp _otherLanguage = RegExp(
    r'(^|[^a-z])([0-9]+x)?(japanese|jpn|ja|russian|rus|ru|french|fra|fre|fr|german|deu|ger|de|hindi|hin|spanish|spa|es|korean|kor|ko|italian|ita|it|arabic|ara|ar|chinese|chi|zho|tamil|tam|telugu|tel|turkish|tur|tr|portuguese|por|pt|ukrainian|ukr)([^a-z]|$)',
    caseSensitive: false,
  );
  static final RegExp _multiAudio = RegExp(
    r'(^|[^a-z])(multi(?:-?audio)?|dual(?:-?audio)?|multi\s*lang(?:uage)?)([^a-z]|$)',
    caseSensitive: false,
  );

  static bool isEnglish({String? language, String? title}) {
    final code = (language ?? '').trim().toLowerCase().replaceAll('_', '-');
    if (code == 'en' || code == 'eng' || code == 'english' ||
        code.startsWith('en-') || code.startsWith('eng-')) {
      return true;
    }
    if (code.isNotEmpty && code != 'und' && code != 'unknown') return false;
    return _english.hasMatch(title ?? '');
  }

  /// Only a recognized, explicit non-English language is conclusive. Unknown
  /// MPV track codes must not cause English-required playback to be rejected.
  static bool isConfirmedNonEnglishTrack({String? language, String? title}) {
    final code = (language ?? '').trim().toLowerCase().replaceAll('_', '-');
    if (isEnglish(language: language, title: title)) return false;
    if (code.isNotEmpty && code != 'und' && code != 'unknown') {
      return _otherLanguage.hasMatch(code);
    }
    return _otherLanguage.hasMatch(title ?? '');
  }

  /// Rank 0: explicit English track metadata (including dual-language English).
  /// Rank 1: unspecified multi-audio; 2: unknown; 3: explicitly non-English.
  /// Do not infer audio from subtitle tracks or subtitle-only labels.
  static int sourceAudioRank(StreamSource source) {
    final hints = source.behaviorHints;
    final declared = <String>[];
    for (final key in const ['audioLanguages', 'audioLanguage', 'audioTracks']) {
      final value = hints?[key];
      if (value is String) {
        declared.add(value);
      } else if (value is List) {
        for (final item in value) {
          if (item is String) {
            declared.add(item);
          } else if (item is Map && item['language'] is String) {
            declared.add(item['language'] as String);
          }
        }
      }
    }

    final metadataLines = <String>[
      source.name ?? '',
      source.title ?? '',
      source.description ?? '',
    ].expand((s) => s.split(RegExp(r'[\r\n]+'))).where((line) {
      // Standalone subtitle lines and links are never audio declarations.
      return !RegExp(
        r'^\s*(?:subs?|subtitles?|subtitle\s*languages?|cc)\s*[:=\-]',
        caseSensitive: false,
      ).hasMatch(line.trim()) &&
          !RegExp(r'^\s*(?:subtitles?|subs)\b', caseSensitive: false)
              .hasMatch(line.trim());
    }).map((line) => line
        .replaceAll(RegExp(
          r'(?:english|eng|en|🇬🇧|🇺🇸)\s+(?:subtitles?|subs)\b',
          caseSensitive: false,
        ), '')
        .replaceAll(RegExp(
          r'(?:subtitles?|subs)\s*[:=\-]\s*[^|•]+',
          caseSensitive: false,
        ), '')
        .replaceAll(RegExp(
          r'(?:subtitles?|subs)\s+(?:english|eng|en)\b',
          caseSensitive: false,
        ), '')).toList();

    final text = [...declared, ...metadataLines].join('\n');
    final explicitEnglish = declared.any((code) =>
        isEnglish(language: code)) || _english.hasMatch(text) ||
        text.contains('🇬🇧') || text.contains('🇺🇸');
    if (explicitEnglish) return 0;
    if (_multiAudio.hasMatch(text)) return 1;
    if (declared.any((code) =>
        isConfirmedNonEnglishTrack(language: code)) ||
        _otherLanguage.hasMatch(text) ||
        text.contains('🇷🇺') || text.contains('🇯🇵') ||
        text.contains('🇫🇷') || text.contains('🇪🇸')) {
      return 3;
    }
    return 2;
  }

  /// Kept for existing callers and diagnostics; no longer Torrentio-specific.
  static int torrentioAudioRank(StreamSource source) => sourceAudioRank(source);
}
