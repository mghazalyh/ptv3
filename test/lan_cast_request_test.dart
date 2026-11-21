import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/movie/video.dart';
import 'package:playtorrio/services/remote/lan_cast_request.dart';

void main() {
  test('Sends only Stremio media and exact episode identity', () {
    final item = LanCastRequest.parse({
      'type': 'series', 'mediaId': 'tt0944947',
      'title': 'A Show', 'episodeId': 'tt0944947:2:3',
      'season': 2, 'episode': 3,
    });
    expect(item, isNotNull);
    expect(item!.episodeId, 'tt0944947:2:3');
    expect(item.toJson()['episode'], 3);
    expect(item.toJson().containsKey('url'), false);
  });

  test('Rejects arbitrary URLs, invalid types and malformed identifiers', () {
    final base = <String, dynamic>{
      'type': 'tv', 'mediaId': 'nltv:us:CineRomantico.us',
      'title': 'Cine Romantico',
    };
    expect(LanCastRequest.parse({...base, 'addonBaseUrl':
      'https://some.addon/secret'}), isNull);
    expect(LanCastRequest.parse({...base, 'mediaId':
      '../../etc/passwd'}), isNull);
    expect(LanCastRequest.parse({...base, 'type': 'shell'}), isNull);
    expect(LanCastRequest.parse({...base, 'episodeId':
      'tt123:1:1'}), isNull);
    expect(LanCastRequest.parse({...base, 'title': ''}), isNull);
    expect(LanCastRequest.parse({...base, 'addonBaseUrl':
      'https://host.example?secret=1'}), isNull);
  });

  test('Channel normalizes to tv and accepts no stream URL', () {
    final request = LanCastRequest.parse({
      'type': 'channel', 'mediaId': 'iptv:channel_123',
      'title': 'Channel',
    });
    expect(request?.type, 'tv');
    expect(LanCastRequest.parse({
      ...request!.toJson(), 'type': 'movie', 'season': 1,
    }), isNull);
  });
  test('Season and episode without a Stremio ID choose the exact match', () {
    final request = LanCastRequest.parse({
      'type': 'series', 'mediaId': 'tt0944947',
      'title': 'A Show', 'season': 2, 'episode': 3,
    });
    expect(request, isNotNull);
    final episodes = [
      Video(id: 'tt0944947:1:1', title: 'Pilot', season: 1, episode: 1),
      Video(id: 'tt0944947:2:2', title: 'Previous', season: 2, episode: 2),
      Video(id: 'tt0944947:2:3', title: 'Requested', season: 2, episode: 3),
    ];
    expect(request!.resolveEpisode(episodes)?.id, 'tt0944947:2:3');
    expect(request.resolveEpisode(episodes.reversed)?.id, 'tt0944947:2:3');
    expect(request.resolveEpisode([episodes.first]), isNull);
  });

  test('Explicit episode ID is never replaced by a different episode', () {
    final episodes = [
      Video(id: 'series:1:1', title: 'First', season: 1, episode: 1),
      Video(id: 'series:2:3', title: 'Third', season: 2, episode: 3),
    ];
    final exact = LanCastRequest.parse({
      'type': 'anime', 'mediaId': 'series',
      'title': 'Anime', 'episodeId': 'series:2:3',
    });
    expect(exact?.resolveEpisode(episodes)?.id, 'series:2:3');
    final mismatch = LanCastRequest.parse({
      'type': 'series', 'mediaId': 'series', 'title': 'Show',
      'episodeId': 'series:2:3', 'season': 1, 'episode': 1,
    });
    expect(mismatch?.resolveEpisode(episodes), isNull);
    expect(exact?.resolveEpisode([episodes.first]), isNull);
  });

  test('Implicit first episode and incomplete numeric requests', () {
    final episodes = [
      Video(id: 'show:3:1', title: 'First', season: 3, episode: 1),
      Video(id: 'show:3:2', title: 'Second', season: 3, episode: 2),
    ];
    final request = LanCastRequest.parse({
      'type': 'series', 'mediaId': 'show', 'title': 'Show',
    });
    expect(request?.resolveEpisode(episodes)?.id, 'show:3:1');
    expect(request?.resolveEpisode([]), isNull);
    expect(LanCastRequest.parse({
      'type': 'series', 'mediaId': 'show', 'title': 'Show', 'season': 3,
    }), isNull);
    expect(LanCastRequest.parse({
      'type': 'series', 'mediaId': 'show', 'title': 'Show', 'episode': 1,
    }), isNull);
  });
}
