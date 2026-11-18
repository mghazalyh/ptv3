import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/audio_language_priority.dart';

StreamSource sample(String title, {String addon = 'Torrentio'}) =>
    StreamSource(addonName: addon, title: title, url: 'https://example.org/a.mkv');

void main() {
  test('MPV prefers English', () {
    expect(AudioLanguagePriority.mpvPreferredLanguages, contains('eng'));
  });
  test('language tags do not confuse French with English', () {
    expect(AudioLanguagePriority.isEnglish(language: 'eng'), isTrue);
    expect(AudioLanguagePriority.isEnglish(language: 'en-US'), isTrue);
    expect(AudioLanguagePriority.isEnglish(language: 'EN'), isTrue);
    expect(AudioLanguagePriority.isEnglish(language: 'fr', title: 'English'), isFalse);
    expect(AudioLanguagePriority.isEnglish(language: 'french'), isFalse);
    expect(AudioLanguagePriority.isEnglish(title: 'English 5.1'), isTrue);
  });
  test('explicit English sorts before multi and unknown', () {
    expect(AudioLanguagePriority.torrentioAudioRank(sample('English Audio 1080p')), 0);
    expect(AudioLanguagePriority.torrentioAudioRank(sample('🇬🇧 4K')), 0);
    expect(AudioLanguagePriority.torrentioAudioRank(sample('MULTI audio 4K')), 1);
    expect(AudioLanguagePriority.torrentioAudioRank(sample('Dual-Audio WEB-DL')), 1);
    expect(AudioLanguagePriority.torrentioAudioRank(sample('WEB-DL 4K')), 2);
    expect(AudioLanguagePriority.torrentioAudioRank(sample('Japanese Audio 4K')), 3);
  });
  test('English subtitles do not count as English audio', () {
    expect(AudioLanguagePriority.torrentioAudioRank(sample('Japanese Audio | Subs: English')), 3);
    expect(AudioLanguagePriority.torrentioAudioRank(sample('French Audio English subtitles')), 3);
  });
  test('Comet and other Stremio addons classify their audio equally', () {
    expect(AudioLanguagePriority.sourceAudioRank(
        sample('Marshals.S02E01.1080p.WEB-DL.HEVC.Rus.mkv',
            addon: 'Comet | ElfHosted | TB')), 3);
    expect(AudioLanguagePriority.sourceAudioRank(
        sample('Marshals.S02E01.1080p.PMTP.WEB-DL.ENG.Atmos.ITA.mkv',
            addon: 'Comet | ElfHosted | TB')), 0);
    expect(AudioLanguagePriority.sourceAudioRank(
        sample('Marshals.S02E01.1080p.WEB-DL.Rus.Eng.mkv',
            addon: 'MediaFusion')), 0);
    expect(AudioLanguagePriority.sourceAudioRank(
        sample('Marshals.S02E01.1080p.WEBRip', addon: 'Comet')), 2);
  });

  test('English subtitle labels never become audio evidence', () {
    expect(AudioLanguagePriority.sourceAudioRank(StreamSource(
      addonName: 'Comet',
      title: 'Film.1080p.Rus | Subs: English',
      subtitles: const [{'lang': 'en', 'url': 'https://example.test/sub'}],
    )), 3);
    expect(AudioLanguagePriority.sourceAudioRank(sample(
      'Film.1080p.French Audio English subtitles', addon: 'Comet')), 3);
  });

  test('structured audio hints are distinct from subtitle languages', () {
    expect(AudioLanguagePriority.sourceAudioRank(StreamSource(
      addonName: 'Custom Stremio',
      title: 'Film.1080p',
      behaviorHints: const {'audioLanguages': ['eng', 'rus']},
      subtitles: const [{'lang': 'ru'}],
    )), 0);
  });

  test('strict mode only confirms native non-English audio when known', () {
    expect(AudioLanguagePriority.isConfirmedNonEnglishTrack(
        language: 'rus', title: 'MVO LostFilm'), isTrue);
    expect(AudioLanguagePriority.isConfirmedNonEnglishTrack(
        language: 'und', title: 'Track 1'), isFalse);
    expect(AudioLanguagePriority.isConfirmedNonEnglishTrack(
        language: 'eng', title: 'English'), isFalse);
  });
}
