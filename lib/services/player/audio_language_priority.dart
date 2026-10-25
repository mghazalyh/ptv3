import '../../models/stream/stream_model.dart';

/// English-first playback without hiding tracks in other languages.
abstract final class AudioLanguagePriority {
  static const String mpvPreferredLanguages = 'eng,en,en-US,en-GB';

  static bool isEnglish({String? language, String? title}) {
    final code = (language ?? '').trim().toLowerCase().replaceAll('_', '-');
    if (code == 'en' || code == 'eng' || code == 'english' ||
        code.startsWith('en-') || code.startsWith('eng-')) {
      return true;
    }
    if (code.isNotEmpty && code != 'und' && code != 'unknown') {
      return false;
    }
    return RegExp(
      r'(^|[^a-z])(english|eng|en-us|en-gb)([^a-z]|$)',
      caseSensitive: false,
    ).hasMatch(title ?? '');
  }

  /// Rank zero: explicit English; one: multilingual; two: unknown; three:
  /// explicit non-English. Never assume a subtitle label is audio metadata.
  static int torrentioAudioRank(StreamSource source) {
    if (!source.addonName.toLowerCase().contains('torrentio')) return 2;
    final raw = [
      source.name ?? '',
      source.title ?? '',
      source.description ?? '',
    ].join('\n').toLowerCase();
    final clean = raw
        .replaceAll(RegExp(
          r'(?:subtitles?|subs|subbed)\s*[:=\-]\s*[^\n|•]+',
          caseSensitive: false,
        ), '')
        .replaceAll(RegExp(
          r'(?:english|eng|en)\s+subtitles?',
          caseSensitive: false,
        ), '');

    if (RegExp(
      r'(^|[^a-z])(english|eng|en-us|en-gb)([^a-z]|$)',
      caseSensitive: false,
    ).hasMatch(clean) ||
        clean.contains('🇬🇧') || clean.contains('🇺🇸')) {
      return 0;
    }
    if (RegExp(
      r'(^|[^a-z])(multi(?:-?audio)?|dual(?:-?audio)?|multi\s*lang(?:uage)?)([^a-z]|$)',
      caseSensitive: false,
    ).hasMatch(clean)) {
      return 1;
    }
    if (RegExp(
      r'(^|[^a-z])(japanese|jpn|russian|rus|french|fra|german|deu|hindi|hin|spanish|spa|korean|kor|italian|ita|arabic|ara|chinese|chi|tamil|telugu|turkish|tur|portuguese|por)([^a-z]|$)',
      caseSensitive: false,
    ).hasMatch(clean)) {
      return 3;
    }
    return 2;
  }
}
