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
  test('other addons retain ordinary ranking', () {
    expect(AudioLanguagePriority.torrentioAudioRank(sample('English', addon: 'OtherAddon')), 2);
  });
}
