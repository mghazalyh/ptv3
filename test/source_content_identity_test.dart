import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/stream/source_content_identity.dart';
import 'package:playtorrio/services/stream/watch_source_preferences.dart';
import 'package:playtorrio/services/player/playback_autoselection.dart';

void main() {
  StreamSource stream(String label, {String addon = 'Torrentio'}) =>
      StreamSource(title: label, addonName: addon,
          url: 'https://example.test/movie.mkv');

  test('unrelated anime is excluded, despite its better quality', () {
    final wrong = stream('Attack.On.Titan.S01E01.2160p', addon: 'Comet');
    final correct = stream('Nocturne.S01E01.1080p.WEB-DL');
    expect(SourceContentIdentity.assess(wrong, title: 'Nocturne',
        season: 1, episode: 1), SourceIdentityVerdict.rejected);
    expect(WatchSourceEngine.process([wrong, correct],
        const WatchSourceProfile(), title: 'Nocturne',
        season: 1, episode: 1), [correct]);
  });

  test('rejects conflicting show and episode numbering', () {
    expect(SourceContentIdentity.assess(
        stream('Nocturne.Of.Shadows.S01E01.2160p'),
        title: 'Nocturne', season: 1, episode: 1),
        SourceIdentityVerdict.rejected);
    expect(SourceContentIdentity.assess(stream('Nocturne.S01E02.2160p'),
        title: 'Nocturne', season: 1, episode: 1),
        SourceIdentityVerdict.rejected);
    expect(SourceContentIdentity.assess(stream('Nocturne.2x01.1080p'),
        title: 'Nocturne', season: 1, episode: 1),
        SourceIdentityVerdict.rejected);
  });

  test('supports exact episode and multi-episode ranges', () {
    expect(SourceContentIdentity.assess(
        stream('[TB+] Nocturne.S01E01-E02.1080p.WEB-DL'),
        title: 'Nocturne', season: 1, episode: 2),
        SourceIdentityVerdict.verified);
    expect(SourceContentIdentity.assess(stream('Nocturne.1x03.1080p'),
        title: 'Nocturne', season: 1, episode: 3),
        SourceIdentityVerdict.verified);
    expect(SourceContentIdentity.assess(stream('Nocturne.S01.Pack.1080p'),
        title: 'Nocturne', season: 1, episode: 2),
        SourceIdentityVerdict.unknown);
  });

  test('exact episode outranks unknown cache-ready addon labels', () {
    final unknown = stream('4K HDR Torrentio [TB+]');
    final correct = stream('Nocturne.S01E01.1080p.WEB-DL');
    final ranked = WatchSourceEngine.process([unknown, correct],
        const WatchSourceProfile(), title: 'Nocturne',
        season: 1, episode: 1);
    expect(ranked.first, same(correct));
    expect(ranked, contains(unknown));
  });

  test('Balanced fallback never restores known incorrect releases', () {
    final wrong = stream('Other.Series.S01E01.2160p');
    expect(WatchSourceEngine.process([wrong],
        const WatchSourceProfile(resolutions: ['1080p']),
        title: 'Nocturne', season: 1, episode: 1), isEmpty);
  });

  test('strict cache settings remain strict', () {
    final generic = stream('4K HDR');
    expect(WatchSourceEngine.process([generic],
        const WatchSourceProfile(cachePolicy: 'cachedOnly'),
        title: 'Nocturne', season: 1, episode: 1), isEmpty);
  });

  test('movie title and year guard are independent of codec quality', () {
    expect(SourceContentIdentity.assess(stream('Wrong.Movie.2024.1080p'),
        title: 'Nocturne', year: 2024),
        SourceIdentityVerdict.rejected);
    expect(SourceContentIdentity.assess(stream('Nocturne.2021.1080p'),
        title: 'Nocturne', year: 2024),
        SourceIdentityVerdict.rejected);
    expect(SourceContentIdentity.assess(stream('Nocturne.2024.1080p'),
        title: 'Nocturne', year: 2024),
        SourceIdentityVerdict.verified);
  });

  test('next-episode autoplay never selects known mismatches', () {
    final previous = stream('Nocturne.S01E01.1080p');
    final wrong = stream('Nocturne.S01E01.2160p');
    final anime = stream('Attack.On.Titan.S01E02.2160p');
    final good = stream('Nocturne.S01E02.720p');
    expect(PlaybackAutoselection.preferredSource(
        [wrong, anime, good], previous, title: 'Nocturne',
        season: 1, episode: 2), same(good));
  });

  test('opaque provider labels remain eligible but unverified', () {
    final generic = stream('4K HDR [TB+]');
    expect(SourceContentIdentity.assess(generic, title: 'Nocturne',
        season: 1, episode: 1), SourceIdentityVerdict.unknown);
  });
}
