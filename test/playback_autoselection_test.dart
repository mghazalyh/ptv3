import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/movie/video.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/models/subtitle/subtitle_model.dart';
import 'package:playtorrio/services/player/playback_autoselection.dart';

SubtitleVariant external(String provider, String language,
    {String title = 'Normal'}) => SubtitleVariant(
  providerName: provider, language: language, title: title,
  downloadUrl: 'https://example.com/sub.srt', format: 'srt',
);
StreamSource stream(String addon, String label, {String? url}) =>
    StreamSource(addonName: addon, name: label, url: url);

void main() {
  test('English embedded forced is preferred over regular English', () {
    final tracks = <PlayerEmbeddedSubtitle>[
      const PlayerEmbeddedSubtitle(index: 1, title: 'French', language: 'fra'),
      const PlayerEmbeddedSubtitle(index: 2, title: 'English SDH', language: 'eng'),
      const PlayerEmbeddedSubtitle(index: 3, title: 'English forced', language: 'en'),
    ];
    expect(PlaybackAutoselection.preferredEmbedded(tracks)?.index, 3);
    expect(PlaybackAutoselection.preferredEmbedded([
      const PlayerEmbeddedSubtitle(index: 2, title: 'French forced', language: 'fr'),
      const PlayerEmbeddedSubtitle(index: 4, title: 'English full', language: 'en'),
    ])?.index, 4);
  });

  test('unknown subtitle language does not automatically enable foreign tracks', () {
    expect(PlaybackAutoselection.preferredEmbedded([
      const PlayerEmbeddedSubtitle(index: 7, title: 'Japanese', language: 'jpn'),
    ]), isNull);
    expect(PlaybackAutoselection.isEnglishSubtitle(
        language: 'fr', title: 'English forced'), isFalse);
    expect(PlaybackAutoselection.isEnglishSubtitle(
        language: 'und', title: 'English forced'), isTrue);
  });

  test('external English forced first, then OpenSubtitles, then other providers', () {
    final groups = <SubtitleLanguageGroup>[
      SubtitleLanguageGroup(language: 'Spanish',
          variants: [external('OpenSubtitles', 'Spanish')]),
      SubtitleLanguageGroup(language: 'English', variants: [
        external('Subdl', 'English'),
        external('OpenSubtitles', 'en'),
        external('Wyzie', 'English', title: 'English FORCED'),
      ]),
    ];
    final candidates = PlaybackAutoselection.preferredExternal(groups);
    expect(candidates.map((e) => e.providerName).toList(),
        ['Wyzie', 'OpenSubtitles', 'Subdl']);
  });

  test('next episode is numbered, including next season, not raw listing order', () {
    final e1 = Video(id: 'tt42:1:1', title: 'Pilot', season: 1, episode: 1);
    final e2 = Video(id: 'tt42:1:2', title: 'Second', season: 1, episode: 2);
    final e4 = Video(id: 'tt42:2:1', title: 'New Season', season: 2, episode: 1);
    final episodes = [e4, e2, e1];
    expect(PlaybackAutoselection.nextEpisode(episodes, e1), same(e2));
    expect(PlaybackAutoselection.nextEpisode(episodes, e2), same(e4));
    expect(PlaybackAutoselection.nextEpisode(episodes, e4), isNull);
    expect(PlaybackAutoselection.nextEpisode(episodes, null), isNull);
  });

  test('Continue Watching without episode metadata retains Next Episode', () {
    final current = Video(id: 'tt99:1:4', title: 'Episode 4', season: 1, episode: 4);
    final next = PlaybackAutoselection.nextEpisodeCandidate(
      knownEpisodes: const [],
      current: current,
      showId: 'tt99',
    );
    expect(next?.id, 'tt99:1:5');
    expect(next?.season, 1);
    expect(next?.episode, 5);
  });

  test('known next season is preferred over a guessed same-season episode', () {
    final current = Video(id: 'tt99:1:8', title: 'Finale', season: 1, episode: 8);
    final seasonTwo = Video(id: 'tt99:2:1', title: 'Return', season: 2, episode: 1);
    expect(PlaybackAutoselection.nextEpisodeCandidate(
      knownEpisodes: [current, seasonTwo],
      current: current,
      showId: 'tt99',
    ), same(seasonTwo));
    expect(PlaybackAutoselection.nextEpisodeCandidate(
      knownEpisodes: [current],
      current: current,
      showId: 'tt99',
      catalogComplete: true,
    ), isNull);
  });

  test('same TorBox or Torrentio source preferred; unusable streams ignored', () {
    final previous = stream('Torrentio', '1080p', url: 'https://old.example/a');
    final sources = [
      stream('Unknown', '4K', url: 'https://new.example/x'),
      stream('Torrentio', 'Bad', url: ''),
      stream('Torrentio', '1080p', url: 'https://new.example/y'),
    ];
    expect(PlaybackAutoselection.preferredSource(sources, previous)?.url,
        'https://new.example/y');
    expect(PlaybackAutoselection.preferredSource(
        [stream('Torrentio', 'No link')], previous), isNull);
  });

  test('fallback chooses first available when original addon is absent', () {
    final previous = stream('TorBox', '1080p', url: 'https://old.example/a');
    expect(PlaybackAutoselection.preferredSource(
      [stream('OtherAddon', '1080p', url: 'https://new.example/ep')],
      previous,
    )?.addonName, 'OtherAddon');
  });
}
