import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/stream/watch_source_preferences.dart';

void main() {
  StreamSource source(String title, {String addon = 'Comet', String? hash,
      int? fileIndex}) =>
      StreamSource(title: title, name: addon, addonName: addon,
          infoHash: hash, fileIdx: fileIndex);

  test('missing preferences always retain safe Balanced defaults', () {
    final empty = WatchSourcePreferences.fromJson(null);
    expect(empty.movie.resolutions, ['4K', '1080p']);
    expect(empty.episode.sorting.length, 3);
    expect(empty.movie.allowUnknown, isTrue);
    expect(WatchSourcePreferences.fromJson({'movie': 'invalid'}).movie.sorting.length, 3);
  });

  test('resolutions and size parse across multiple addons', () {
    final entries = [
      source('Example.2160p.WEB-DL.3.5GB', addon: 'MediaFusion'),
      source('Example.1080p.WEB-DL.10GB', addon: 'Torrentio'),
      source('Example.720p.WEBRip.2GB', addon: 'Comet'),
    ];
    final chosen = WatchSourceEngine.process(entries, const WatchSourceProfile());
    expect(chosen.length, 2);
    expect(chosen.first.quality, '4K');
    expect(chosen.last.quality, '1080p');
  });

  test('unknown or too-strict filters never remove every playback choice', () {
    final unknown = source('Unlabeled playable source');
    expect(WatchSourceEngine.process([unknown], const WatchSourceProfile()),
        [unknown]);
    final fallback = source('Only 720p available');
    expect(WatchSourceEngine.process([fallback], const WatchSourceProfile(
        resolutions: ['4K'], allowUnknown: false)), [fallback]);
  });

  test('verified TorBox cache outranks unknown metadata', () {
    const cached = '0123456789012345678901234567890123456789';
    final a = source('Film.1080p.3GB', addon: 'Torrentio', hash: cached);
    final b = source('Film.4K.4GB', addon: 'Comet');
    final result = WatchSourceEngine.process([b, a],
        const WatchSourceProfile(), verified: {cached: true});
    expect(result.first, same(a));
    expect(WatchSourceEngine.cacheTier(a, {cached: true}), 'verified');
    expect(WatchSourceEngine.cacheTier(a, {}), 'unknown');
  });

  test('deduplicates identical hash and file index, not similar names', () {
    const hash = 'abcdefabcdefabcdefabcdefabcdefabcdefabcd';
    final originals = [
      source('Film.4K', hash: hash, fileIndex: 0),
      source('Film.4K', hash: hash, fileIndex: 0, addon: 'Torrentio'),
      source('Film.4K', hash: hash, fileIndex: 1, addon: 'MediaFusion'),
      source('Film.4K', addon: 'Other'),
    ];
    final result = WatchSourceEngine.process(originals,
        const WatchSourceProfile());
    expect(result.length, 3);
  });

  test('subtitles and audio formats require explicit metadata', () {
    final subtitled = StreamSource(
      title: 'Film.1080p.TrueHD.5.1', addonName: 'Comet',
      subtitles: const [{'lang': 'en', 'url': 'https://example.test/sub.srt'}],
    );
    expect(WatchSourceEngine.hasSubtitles(subtitled), isTrue);
    expect(WatchSourceEngine.audioFormat(subtitled), 'TrueHD');
    expect(WatchSourceEngine.audioChannels(subtitled), '5.1');
    expect(WatchSourceEngine.process([subtitled], const WatchSourceProfile(
      subtitlePolicy: 'require', audioFormats: ['TrueHD'],
    )), [subtitled]);
  });

  test('three-level sorting rules and provider order roundtrip', () {
    const profile = WatchSourceProfile(
      addonPriority: ['MediaFusion', 'Comet', 'Torrentio'],
      sorting: [
        SourceSortRule('provider', true),
        SourceSortRule('resolution', true),
        SourceSortRule('size', false),
      ],
    );
    final result = WatchSourceEngine.process([
      source('A.1080p.4GB', addon: 'Torrentio'),
      source('A.1080p.4GB', addon: 'MediaFusion'),
    ], profile);
    expect(result.first.addonName, 'MediaFusion');
    final restored = WatchSourceProfile.fromJson(profile.toJson());
    expect(restored.sorting[0].criterion, 'provider');
    expect(restored.addonPriority.first, 'MediaFusion');
  });

  test('verified cached only never restores uncached or unknown sources', () {
    const hash = '0123456789012345678901234567890123456789';
    final cached = source('Movie.1080p', hash: hash);
    final unknown = source('Movie.4K', addon: 'MediaFusion');
    final uncached = source('Movie.1080p', addon: 'Comet',
        hash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    const profile = WatchSourceProfile(cachePolicy: 'cachedOnly');

    expect(WatchSourceEngine.process([unknown, uncached], profile,
        verified: {hash: true}), isEmpty);
    expect(WatchSourceEngine.process([unknown, uncached, cached], profile,
        verified: {hash: true}), [cached]);
    expect(WatchSourceEngine.process([cached], profile), isEmpty);
    expect(WatchSourceEngine.process([cached], profile,
        verified: {hash: false}), isEmpty);
  });

  test('TorBox object results verify cached torrents, not addon labels', () {
    const hash = '0123456789012345678901234567890123456789';
    const other = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final matched = source('Show.S01E02.1080p', hash: hash, fileIndex: 2);
    final unmatched = source('Show.S01E03.1080p', hash: hash, fileIndex: 4);
    final uncached = source('Episode.1080p', hash: other);
    final payload = {
      'success': true,
      'data': {
        hash: {
          'name': 'Example torrent',
          'hash': hash,
          'size': 123456,
          'files': [
            {'id': 2, 'name': 'S01E02.mkv', 'size': 120000},
          ],
        },
      },
    };

    final parsed = TorBoxCacheVerifier.parseCacheResponse(payload,
        [matched, unmatched, uncached]);
    expect(parsed[WatchSourceEngine.cacheKeyOf(matched)], isTrue);
    expect(parsed[WatchSourceEngine.cacheKeyOf(unmatched)], isFalse);
    expect(parsed[WatchSourceEngine.cacheKeyOf(uncached)], isFalse);
    expect(WatchSourceEngine.process([matched, unmatched, uncached],
        const WatchSourceProfile(cachePolicy: 'cachedOnly'),
        verified: parsed), [matched]);
  });

  test('unrecognized cache responses cannot invent verified matches', () {
    const hash = '0123456789012345678901234567890123456789';
    final indexed = source('Episode.1080p', hash: hash, fileIndex: 0);
    final noIndex = source('Movie.1080p', hash: hash);
    const boolPayload = {
      'success': true,
      'data': {hash: true},
    };
    final parsed = TorBoxCacheVerifier.parseCacheResponse(boolPayload,
        [indexed, noIndex]);
    // A raw torrent-level boolean cannot validate a specific episode file.
    expect(parsed.containsKey(WatchSourceEngine.cacheKeyOf(indexed)), isFalse);
    expect(parsed[WatchSourceEngine.cacheKeyOf(noIndex)], isTrue);

    final malformed = TorBoxCacheVerifier.parseCacheResponse({
      'success': true, 'data': {hash: {'unexpected': 'data'}},
    }, [indexed, noIndex]);
    expect(malformed, isEmpty);
    expect(TorBoxCacheVerifier.parseCacheResponse({
      'success': false, 'data': {hash: true},
    }, [noIndex]), isEmpty);
  });

  test('a TorBox direct HTTPS link is addon ready, not API verified', () {
    final torboxLink = StreamSource(
      title: 'Show.S01E02.1080p',
      name: '[TB+] Show',
      addonName: 'Torrentio TB',
      url: 'https://cdn.example.org/video.mkv',
    );
    final cometLink = StreamSource(
      title: 'Show.S01E02.1080p',
      addonName: 'Comet | ElfHosted | TB',
      url: 'https://cdn.example.org/video.mkv',
    );
    final generic = StreamSource(
      title: 'Show.1080p',
      addonName: 'Unrelated HTTP',
      url: 'https://cdn.example.org/video.mkv',
    );
    final pending = StreamSource(
      name: '[TB Download] Show',
      addonName: 'Torrentio TB',
      url: 'https://cdn.example.org/not-ready',
    );

    expect(WatchSourceEngine.isTorBoxAddonReady(torboxLink), isTrue);
    expect(WatchSourceEngine.cacheTier(torboxLink, {}), 'reported');
    expect(WatchSourceEngine.cacheTier(cometLink, {}), 'reported');
    expect(WatchSourceEngine.cacheTier(generic, {}), 'unknown');
    expect(WatchSourceEngine.cacheTier(pending, {}), 'pending');
    expect(WatchSourceEngine.process([torboxLink],
        const WatchSourceProfile(cachePolicy: 'readyOnly')), [torboxLink]);
    expect(WatchSourceEngine.process([torboxLink],
        const WatchSourceProfile(cachePolicy: 'cachedOnly')), isEmpty);
  });

  test('Stremio dht source hints retain usable torrent hashes', () {
    const hash = '0123456789012345678901234567890123456789';
    final stream = StreamSource.fromJson({
      'name': 'Show',
      'sources': ['tracker:https://tracker.example.org', 'dht:$hash'],
      'fileIdx': 1,
    }, 'Torrentio TB');
    expect(stream.infoHash, hash);
    expect(WatchSourceEngine.hashOf(stream), hash);
    expect(WatchSourceEngine.cacheKeyOf(stream), '$hash:1');
    expect(WatchSourceEngine.cacheTier(stream, {}), 'unknown');
  });

  test('episode context verifies by filename despite different TorBox IDs', () {
    const hash = '0123456789012345678901234567890123456789';
    final stream = source('Generic.1080p', hash: hash, fileIndex: 7);
    final payload = {
      'success': true,
      'data': {
        hash: {
          'name': 'Full Season',
          'hash': hash,
          'files': [
            {'id': 401, 'name': 'Show.S01E01.mkv'},
            {'id': 402, 'name': 'Show.S01E02.mkv'},
          ],
        },
      },
    };
    final episode2 = TorBoxCacheVerifier.parseCacheResponse(
        payload, [stream], season: 1, episode: 2);
    final episode3 = TorBoxCacheVerifier.parseCacheResponse(
        payload, [stream], season: 1, episode: 3);
    expect(episode2[WatchSourceEngine.cacheKeyOf(stream,
        season: 1, episode: 2)], isTrue);
    expect(episode3[WatchSourceEngine.cacheKeyOf(stream,
        season: 1, episode: 3)], isFalse);
    expect(WatchSourceEngine.process([stream],
        const WatchSourceProfile(cachePolicy: 'cachedOnly'),
        verified: episode2, season: 1, episode: 2), [stream]);
    expect(WatchSourceEngine.process([stream],
        const WatchSourceProfile(cachePolicy: 'cachedOnly'),
        verified: episode2, season: 1, episode: 3), isEmpty);
  });

  test('ambiguous file IDs remain unverified, not a false cache miss', () {
    const hash = '0123456789012345678901234567890123456789';
    final stream = source('Generic.1080p', hash: hash, fileIndex: 5);
    final payload = {
      'success': true,
      'data': {
        hash: {'hash': hash, 'files': [
          {'id': 0, 'name': 'video-a.mkv'},
          {'id': 1, 'name': 'video-b.mkv'},
        ]},
      },
    };
    expect(TorBoxCacheVerifier.parseCacheResponse(payload, [stream]), isEmpty);
  });

  test('invalid configuration values fall back without throwing', () {
    final parsed = WatchSourceProfile.fromJson({
      'cachePolicy': 'impossible',
      'maxSizeGb': -10,
      'sorting': [{'criterion': 'unknown'}],
      'resolutions': [null],
    });
    expect(parsed.cachePolicy, 'prefer');
    expect(parsed.maxSizeGb, 0);
    expect(parsed.sorting.length, 3);
    expect(parsed.resolutions, ['4K', '1080p']);
  });
}
