import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/stream/stream_service.dart';
import 'package:playtorrio/services/player/player_settings.dart';
import 'package:playtorrio/services/player/live_tv/live_source_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Live TV channel routing is isolated from title-based VOD scraping', () {
    expect(StreamService.isLiveStreamRequest(
        type: 'tv', id: 'nltv:us:GhostHunters.us'), isTrue);
    expect(StreamService.isLiveStreamRequest(
        type: 'movie', id: 'nltv:us:GhostHunters.us'), isTrue);
    expect(StreamService.isLiveStreamRequest(
        type: 'movie', id: 'tt12345'), isFalse);
    expect(StreamService.isLiveStreamRequest(
        type: 'series', id: 'tt12345', season: 16, episode: 3), isFalse);
    expect(StreamService.isLiveStreamRequest(
        type: 'tv', id: 'nltv:us:GhostHunters.us', episode: 3), isFalse);
  });

  test('An on-demand torrent with a matching channel title is rejected', () {
    expect(StreamService.isEligibleLiveStreamSource(StreamSource(
        addonName: 'PlayTorrio', title: 'Ghost Hunters S16E03',
        infoHash: 'abc123')), isFalse);
    expect(StreamService.isEligibleLiveStreamSource(StreamSource(
        addonName: 'Live TV', title: 'Ghost Hunters',
        url: 'https://cdn.example/master.m3u8?token=NOT_LOGGED')), isTrue);
    expect(StreamService.isEligibleLiveStreamSource(StreamSource(
        addonName: 'Live TV', infoHash: 'abc123',
        url: 'https://cdn.example/hls.m3u8')), isFalse);
  });

  test('iOS HLS live mode avoids FFmpeg reconnect without altering VOD', () {
    expect(PlayerSettings.streamLavfOptions(
        isLive: true, isHlsLive: true, isIOS: true), isEmpty);
    expect(PlayerSettings.streamLavfOptions(
        isLive: false, isHlsLive: true, isIOS: true), isEmpty);
    expect(PlayerSettings.streamLavfOptions(
        isLive: true, isHlsLive: false, isIOS: true), contains('reconnect=1'));
    expect(PlayerSettings.streamLavfOptions(
        isLive: true, isHlsLive: true, isIOS: false), contains('reconnect=1'));
  });

  test('HEAD and HLS probes share auth headers and classify a bad manifest',
      () async {
    final seen = <http.Request>[];
    LiveSourceManager.probeClientOverride = MockClient((request) async {
      seen.add(request);
      if (request.method == 'HEAD') {
        return http.Response('', 405, headers: {'content-type': 'text/plain'});
      }
      return http.Response('<html>expired</html>', 200,
          headers: {'content-type': 'text/html'});
    });
    addTearDown(() => LiveSourceManager.probeClientOverride = null);
    final candidate = StreamSource(
      addonName: 'Live TV',
      url: 'https://cdn.example/master.m3u8?token=HIDDEN',
      headers: {'Referer': 'https://valid.example/'},
      behaviorHints: {
        'proxyHeaders': {'request': {'Origin': 'https://valid.example'}},
      },
    );
    final manager = LiveSourceManager(
      channelId: 'nltv:us:GhostHunters.us',
      addonName: 'Live TV',
      initial: candidate,
    );
    // A HEAD 405 is not proof that a stream works. A valid GET is required.
    // This fixture deliberately serves HTTP 200 with an HTML error page;
    // the failed build previously expected an unsafe false positive.
    expect(await manager.seemsPlayable(candidate), isFalse);
    final probe = manager.latestProbeFor(candidate)!;
    expect(probe.phase, 'playlist');
    expect(probe.outcome, 'invalid_manifest');
    expect(probe.httpStatus, 200);
    expect(probe.mimeKind, 'html');
    expect(seen, hasLength(2));
    expect(seen.first.headers['referer'], 'https://valid.example/');
    expect(seen.last.headers['origin'], 'https://valid.example');
    expect(probe.headerCount, greaterThanOrEqualTo(2));
  });

  test('Playlist inspection classifies HTTP failures without storing URLs',
      () async {
    LiveSourceManager.probeClientOverride =
        MockClient((_) async => http.Response('forbidden', 403));
    addTearDown(() => LiveSourceManager.probeClientOverride = null);
    final candidate = StreamSource(
      addonName: 'Live TV', url: 'https://cdn.example/live.m3u8?key=SECRET');
    final manager = LiveSourceManager(
      channelId: 'nltv:us:Channel.us',
      addonName: 'Live TV', initial: candidate);
    expect(await manager.inspectPlaylist(candidate), isNull);
    final probe = manager.latestProbeFor(candidate)!;
    expect(probe.outcome, 'http_status');
    expect(probe.httpStatus, 403);
    expect(probe.toString(), isNot(contains('SECRET')));
  });
}
