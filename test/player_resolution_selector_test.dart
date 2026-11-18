import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/player_resolution_selector.dart';
import 'package:playtorrio/services/stream/watch_source_preferences.dart';
import 'package:playtorrio/widgets/player/player_resolution_menu.dart';

StreamSource candidate(
  String release, {
  String addon = 'Torrentio TB',
  String? description,
  String? name,
  String? url,
}) => StreamSource(
  title: release,
  name: name ?? '[TB+] Torrentio',
  addonName: addon,
  description: description,
  url: url ?? 'https://media.example.test/${release.hashCode}.mkv',
);

void main() {
  test('resolution extraction understands release filenames and 8K', () {
    expect(PlayerResolutionSelector.resolutionOf(candidate(
      'Marshals.S02E01.4320p.HEVC.mkv')), '8K');
    expect(PlayerResolutionSelector.resolutionOf(candidate(
      'Marshals.S02E01.8K.HEVC.mkv')), '8K');
    expect(PlayerResolutionSelector.resolutionOf(candidate(
      'Marshals.S02E01.2160p.WEB-DL.mkv')), '4K');
    expect(PlayerResolutionSelector.resolutionOf(candidate(
      'Marshals.S02E01.1440p.mkv')), '1440p');
    expect(PlayerResolutionSelector.resolutionOf(candidate(
      'Marshals.S02E01.720p.mkv')), '720p');
    expect(PlayerResolutionSelector.resolutionOf(candidate(
      'Marshals.S02E01.360p.mkv')), '360p');

    final comet = StreamSource(
      name: '[TB⚡] Comet 1080p',
      addonName: 'Comet | ElfHosted | TB',
      url: 'https://example.test/4k.mkv',
      description:
          '📄 Marshals.S02E01.2160p.HEVC.ENG.mkv\n'
          '📹 hevc\n💾 4.2 GB',
    );
    expect(PlayerResolutionSelector.resolutionOf(comet), '4K');
  });

  test('picker only shows available eligible playable resolution tiers', () {
    final stream8k = candidate('Marshals.S02E01.4320p.ENG.mkv',
        url: 'https://example.test/8k');
    final stream4k = candidate('Marshals.S02E01.2160p.ENG.mkv',
        url: 'https://example.test/4k');
    final stream1080 = candidate('Marshals.S02E01.1080p.ENG.mkv',
        url: 'https://example.test/1080');
    final otherEpisode = candidate('Marshals.S02E02.2160p.ENG.mkv',
        url: 'https://example.test/incorrect');
    final pending = candidate('Marshals.S02E01.720p.mkv',
        name: '[TB downloading] Torrentio',
        url: 'https://example.test/pending');
    final foreignContent = candidate('Nocturne.S01E01.480p.mkv',
        url: 'https://example.test/wrong-show');

    final available = PlayerResolutionSelector.choices([
      stream1080, stream8k, stream4k, otherEpisode,
      pending, foreignContent, stream8k,
    ], title: 'Marshals', season: 2, episode: 1,
      profile: const WatchSourceProfile());
    expect(available.map((choice) => choice.resolution),
        ['8K', '4K', '1080p']);
    expect(available[0].source, same(stream8k));
    expect(available[0].sourceCount, 1);
    expect(available[1].source, same(stream4k));
  });

  test('best source of each tier honors English first even if larger', () {
    final russian = candidate(
      'Marshals.S02E01.2160p.Rus.mkv',
      url: 'https://example.test/russian',
      description: '💾 500 MB 🇷🇺',
    );
    final english = candidate(
      'Marshals.S02E01.2160p.ENG.mkv',
      url: 'https://example.test/english',
      description: '💾 4.0 GB 🇬🇧',
    );
    final buckets = PlayerResolutionSelector.choices(
      [russian, english],
      title: 'Marshals', season: 2, episode: 1,
      profile: const WatchSourceProfile(
        resolutions: ['1080p'],
        sorting: [
          SourceSortRule('size', false),
          SourceSortRule('cache', true),
          SourceSortRule('resolution', true),
        ],
      ),
    );
    expect(buckets.single.resolution, '4K');
    expect(buckets.single.source, same(english));
  });

  test('require English excludes explicit Russian-only choices', () {
    final russian = candidate('Marshals.S02E01.8K.Rus.mkv',
        url: 'https://example.test/russian');
    final english = candidate('Marshals.S02E01.1080p.ENG.mkv',
        url: 'https://example.test/english');
    final buckets = PlayerResolutionSelector.choices(
      [russian, english],
      title: 'Marshals', season: 2, episode: 1,
      profile: const WatchSourceProfile(requireEnglishAudio: true),
    );
    expect(buckets.map((choice) => choice.resolution), ['1080p']);
  });

  test('exact progress survives a quality change, even near the start', () {
    final position = const Duration(minutes: 39, seconds: 6);
    expect(PlayerResolutionSelector.resumePosition(
      currentPosition: position,
      sameEpisode: true,
      deliberateQualityChange: true,
    ), position);
    expect(PlayerResolutionSelector.resumePosition(
      currentPosition: const Duration(seconds: 6),
      sameEpisode: true,
      deliberateQualityChange: true,
    ), const Duration(seconds: 6));
    expect(PlayerResolutionSelector.resumePosition(
      currentPosition: Duration.zero,
      sameEpisode: true,
      deliberateQualityChange: true,
    ), Duration.zero);
    expect(PlayerResolutionSelector.resumePosition(
      currentPosition: position,
      sameEpisode: true,
      deliberateQualityChange: false,
    ), const Duration(minutes: 39, seconds: 1));
    expect(PlayerResolutionSelector.resumePosition(
      currentPosition: position,
      sameEpisode: false,
      deliberateQualityChange: true,
    ), isNull);
  });

  testWidgets('resolution list lets a viewer select 4K', (tester) async {
    final source = candidate('Marshals.S02E01.2160p.ENG.mkv',
        url: 'https://example.test/4k');
    PlayerResolutionChoice? chosen;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlayerResolutionMenu(
            resolutions: [
              PlayerResolutionChoice(
                resolution: '4K', source: source, sourceCount: 3),
              PlayerResolutionChoice(
                resolution: '1080p', source: candidate(
                  'Marshals.S02E01.1080p.ENG.mkv'),
                  sourceCount: 8),
            ],
            currentResolution: '1080p',
            isDiscovering: false,
            isSwitching: false,
            onSelected: (choice) => chosen = choice,
            onClose: () {},
          ),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('stream-resolution-4K')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('stream-resolution-1080p')),
        findsOneWidget);
    expect(find.text('8K'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('stream-resolution-4K')));
    expect(chosen?.source, same(source));
    expect(chosen?.resolution, '4K');
  });
}
