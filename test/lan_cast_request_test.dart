import 'package:flutter_test/flutter_test.dart';
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
}
