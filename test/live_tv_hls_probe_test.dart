import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/live_tv/live_source_manager.dart';
import 'package:playtorrio/services/player/live_tv/live_playback_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('A 403 HEAD and a 403 HLS GET reject the dead backup', () async {
    final requests = <String>[];
    LiveSourceManager.probeClientOverride = MockClient((request) async {
      requests.add(request.method);
      return http.Response('denied', 403,
          headers: const <String, String>{'content-type': 'text/html'});
    });
    addTearDown(() => LiveSourceManager.probeClientOverride = null);
    final source = StreamSource(
      addonName: 'Live TV',
      url: 'https://cdn.example/master.m3u8?token=NEVER_REPORTED');
    final manager = LiveSourceManager(
      channelId: 'nltv:us:Channel.us',
      addonName: 'Live TV', initial: source);
    expect(await manager.seemsPlayable(source), isFalse);
    expect(requests, <String>['HEAD', 'GET']);
    final probe = manager.latestProbeFor(source)!;
    expect(probe.phase, 'playlist');
    expect(probe.httpStatus, 403);
    expect(probe.outcome, 'http_status');
    expect(probe.toString(), isNot(contains('NEVER_REPORTED')));
  });

  test('A 200 master is not accepted if every child playlist fails', () async {
    LiveSourceManager.probeClientOverride = MockClient((request) async {
      if (request.url.path.endsWith('/master.m3u8')) {
        return http.Response(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000\n'
          '720/playlist.m3u8\n', 200,
          headers: const {'content-type': 'application/vnd.apple.mpegurl'});
      }
      return http.Response('expired', 403,
          headers: const {'content-type': 'text/html'});
    });
    addTearDown(() => LiveSourceManager.probeClientOverride = null);
    final source = StreamSource(addonName: 'Live TV',
        url: 'https://cdn.example/master.m3u8');
    final manager = LiveSourceManager(channelId: 'nltv:us:Channel.us',
        addonName: 'Live TV', initial: source);
    expect(await manager.inspectPlaylist(source), isNull);
    final result = manager.latestProbeFor(source)!;
    expect(result.phase, 'variant');
    expect(result.httpStatus, 403);
  });

  test('Master with decodable media-playlist shape reports media sequence',
      () async {
    LiveSourceManager.probeClientOverride = MockClient((request) async {
      if (request.url.path.endsWith('/master.m3u8')) {
        return http.Response(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000\n'
          '720/playlist.m3u8\n', 200);
      }
      return http.Response(
          '#EXTM3U\n#EXT-X-TARGETDURATION:6\n'
          '#EXT-X-MEDIA-SEQUENCE:100\n#EXTINF:6,\nsegment100.ts\n',
          200);
    });
    addTearDown(() => LiveSourceManager.probeClientOverride = null);
    final source = StreamSource(addonName: 'Live TV',
        url: 'https://cdn.example/master.m3u8');
    final manager = LiveSourceManager(channelId: 'nltv:us:Channel.us',
        addonName: 'Live TV', initial: source);
    final result = await manager.inspectPlaylist(source);
    expect(result?.isMaster, false);
    expect(result?.mediaSequence, 100);
    final probe = manager.latestProbeFor(source)!;
    expect(probe.phase, 'variant');
    expect(probe.outcome, 'ok');
    expect(probe.segmentCount, 1);
  });

  test('Deep HLS diagnosis requests a bounded media-segment range', () async {
    final requests = <http.Request>[];
    LiveSourceManager.probeClientOverride = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('master.m3u8')) {
        return http.Response(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000\n'
          'video/media.m3u8\n', 200);
      }
      if (request.url.path.endsWith('media.m3u8')) {
        return http.Response(
          '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:1\n'
          '#EXTINF:6,\nsegment001.ts\n', 200);
      }
      // A real MPEG-TS segment begins with a sync byte every 188 bytes.
      // The previous mock returned a stringified Dart list starting with '['
      // and was correctly rejected as JSON-like, non-media content.
      final transportStream = List<int>.filled(376, 0)
        ..[0] = 0x47
        ..[188] = 0x47;
      return http.Response.bytes(transportStream, 206);
    });
    addTearDown(() => LiveSourceManager.probeClientOverride = null);
    final source = StreamSource(addonName: 'Live TV',
        url: 'https://cdn.example/master.m3u8');
    final manager = LiveSourceManager(channelId: 'nltv:us:Channel.us',
        addonName: 'Live TV', initial: source);
    final probe = await manager.inspectFirstSegment(source);
    expect(probe?.phase, 'segment');
    expect(probe?.httpStatus, 206);
    expect(probe?.outcome, 'ok');
    expect(probe?.segmentKind, 'mpegts');
    expect(requests, hasLength(3));
    expect(requests.last.headers['range'], 'bytes=0-4095');
  });

  test('HEAD 414 and HLS variant 414 must not become playable backups',
      () async {
    LiveSourceManager.probeClientOverride = MockClient((request) async {
      if (request.method == 'HEAD') return http.Response('', 414);
      if (request.url.path.endsWith('/master.m3u8')) {
        return http.Response(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000\n'
          'nested/media.m3u8\n', 200);
      }
      return http.Response('Request URI Too Long', 414);
    });
    addTearDown(() => LiveSourceManager.probeClientOverride = null);
    final source = StreamSource(addonName: 'Live TV',
        url: 'https://cdn.example/master.m3u8');
    final manager = LiveSourceManager(channelId: 'nltv:us:Channel.us',
        addonName: 'Live TV', initial: source);
    expect(await manager.seemsPlayable(source), false);
    final probe = manager.latestProbeFor(source)!;
    expect(probe.phase, 'variant');
    expect(probe.httpStatus, 414);
    // Inspect the actual failing child URI structure, not the master URL,
    // without exposing any signed query contents.
    expect(probe.requestHost, 'cdn.example');
    expect(probe.requestPathChars, '/nested/media.m3u8'.length);
    expect(probe.requestQueryChars, 0);
    expect(probe.requestUrlChars,
        'https://cdn.example/nested/media.m3u8'.length);
  });

  test('HEAD 405 allows valid GET-only HLS channel', () async {
    LiveSourceManager.probeClientOverride = MockClient((request) async {
      if (request.method == 'HEAD') return http.Response('', 405);
      if (request.url.path.endsWith('/master.m3u8')) {
        return http.Response(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000\n'
          'nested/media.m3u8\n', 200);
      }
      return http.Response(
          '#EXTM3U\n#EXT-X-TARGETDURATION:6\n'
          '#EXT-X-MEDIA-SEQUENCE:100\n#EXTINF:6,\npart.ts\n', 200);
    });
    addTearDown(() => LiveSourceManager.probeClientOverride = null);
    final source = StreamSource(addonName: 'Live TV',
        url: 'https://cdn.example/master.m3u8');
    final manager = LiveSourceManager(channelId: 'nltv:us:Channel.us',
        addonName: 'Live TV', initial: source);
    expect(await manager.seemsPlayable(source), true);
    expect(manager.latestProbeFor(source)?.outcome, 'ok');
    expect(manager.latestProbeFor(source)?.phase, 'variant');
  });

  test('HLS media signatures distinguish real bytes from deceptive HTML', () {
    final transportStream = List<int>.filled(376, 0)
      ..[0] = 0x47
      ..[188] = 0x47;
    expect(LiveSourceManager.segmentSignature(transportStream), 'mpegts');
    expect(LiveSourceManager.segmentSignature(
      <int>[0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0, 0, 0, 0],
    ), 'fmp4');
    expect(LiveSourceManager.segmentSignature(
        '<html>Access denied</html>'.codeUnits), 'html');
    expect(LiveSourceManager.segmentSignature(
        '{"code":403}'.codeUnits), 'json');
    expect(LiveSourceManager.segmentSignature(const <int>[]), 'empty');
  });

  test('HLS CDN redirects preserve final base for variants and segments',
      () async {
    final requested = <String>[];
    final headersUsed = <Map<String, String>>[];
    LiveSourceManager.probeClientOverride = MockClient((request) async {
      requested.add(request.url.toString());
      headersUsed.add(Map<String, String>.from(request.headers));
      if (request.url.host == 'entry.example') {
        return http.Response('', 302, headers: const {
          'location': 'https://cdn.example/live/master.m3u8?session=1',
        });
      }
      if (request.url.path == '/live/master.m3u8') {
        return http.Response(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000\n'
          'variants/720.m3u8\n', 200);
      }
      if (request.url.path == '/live/variants/720.m3u8') {
        return http.Response('', 307, headers: const {
          'location': 'https://other-cdn.example/hls/media.m3u8',
        });
      }
      if (request.url.path == '/hls/media.m3u8') {
        return http.Response(
          '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:88\n'
          '#EXTINF:6,\nsegment.ts\n', 200);
      }
      if (request.url.path == '/hls/segment.ts') {
        final bytes = List<int>.filled(376, 0)
          ..[0] = 0x47
          ..[188] = 0x47;
        return http.Response.bytes(bytes, 206);
      }
      return http.Response('unexpected URL', 404);
    });
    addTearDown(() => LiveSourceManager.probeClientOverride = null);
    final source = StreamSource(
      addonName: 'Live TV', url: 'https://entry.example/play.m3u8',
      headers: const {'Referer': 'https://player.example/'},
    );
    final manager = LiveSourceManager(
      channelId: 'nltv:us:Channel.us', addonName: 'Live TV',
      initial: source);
    final probe = await manager.inspectFirstSegment(source);
    expect(probe?.outcome, 'ok');
    expect(probe?.segmentKind, 'mpegts');
    expect(requested, <String>[
      'https://entry.example/play.m3u8',
      'https://cdn.example/live/master.m3u8?session=1',
      'https://cdn.example/live/variants/720.m3u8',
      'https://other-cdn.example/hls/media.m3u8',
      'https://other-cdn.example/hls/segment.ts',
    ]);
    expect(headersUsed.every((headers) => headers.entries.any((entry) =>
        entry.key.toLowerCase() == 'referer' &&
        entry.value == 'https://player.example/')), isTrue);
  });

  test('HLS variant redirect HTTP 414 identifies final destination', () async {
    const finalUrl = 'https://cdn.example/signed/media.m3u8?signature=abc';
    LiveSourceManager.probeClientOverride = MockClient((request) async {
      if (request.url.path == '/master.m3u8') {
        return http.Response(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\n'
          'child.m3u8\n', 200);
      }
      if (request.url.path == '/child.m3u8') {
        return http.Response('', 302,
            headers: const {'location': finalUrl});
      }
      return http.Response('Request URI Too Long', 414);
    });
    addTearDown(() => LiveSourceManager.probeClientOverride = null);
    final source = StreamSource(
        addonName: 'Live TV', url: 'https://entry.example/master.m3u8');
    final manager = LiveSourceManager(
        channelId: 'nltv:us:Channel.us', addonName: 'Live TV',
        initial: source);
    expect(await manager.inspectPlaylist(source), isNull);
    final probe = manager.latestProbeFor(source)!;
    expect(probe.phase, 'variant');
    expect(probe.httpStatus, 414);
    expect(probe.requestHost, 'cdn.example');
    expect(probe.requestPathChars, '/signed/media.m3u8'.length);
    expect(probe.requestUrlChars, finalUrl.length);
  });

  test('HLS redirect loops terminate without accepting source', () async {
    var calls = 0;
    LiveSourceManager.probeClientOverride = MockClient((request) async {
      calls++;
      return http.Response('', 302,
          headers: const {'location': '/same.m3u8'});
    });
    addTearDown(() => LiveSourceManager.probeClientOverride = null);
    final source = StreamSource(
        addonName: 'Live TV', url: 'https://cdn.example/same.m3u8');
    final manager = LiveSourceManager(
        channelId: 'nltv:us:Channel.us', addonName: 'Live TV',
        initial: source);
    expect(await manager.inspectPlaylist(source), isNull);
    expect(calls, 1);
    expect(manager.latestProbeFor(source)?.outcome, 'network_error');
  });

  test('Native HLS log diagnosis uses only fixed categories', () {
    expect(LivePlaybackCoordinator.classifyNativeFailure(
        'HTTP error 403 Forbidden'), 'live_native_http_auth');
    expect(LivePlaybackCoordinator.classifyNativeFailure(
        'Failed to open segment 0'), 'live_native_segment_failure');
    expect(LivePlaybackCoordinator.classifyNativeFailure(
        'TLS certificate error'), 'live_native_tls_failure');
    expect(LivePlaybackCoordinator.classifyNativeFailure(
        'invalid data found when processing input'),
        'live_native_demux_failure');
    expect(LivePlaybackCoordinator.classifyNativeFailure(
        'user clicked pause'), isNull);
  });
}
