import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/live_tv/live_hls_http_relay.dart';

Future<String> fetchText(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  final response = await request.close();
  expect(response.statusCode, HttpStatus.ok);
  return utf8.decoder.bind(response).join();
}

void main() {
  // This suite uses a real localhost HttpServer and HttpClient. Do not
  // initialize TestWidgetsFlutterBinding: it overrides HTTP with status 400.

  test('Redirected HLS variants, keys, segments and headers survive relay',
      () async {
    final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4, 0);
    final hits = <String>[];
    final cookies = <String?>[];
    final ranges = <String?>[];
    server.listen((request) async {
      hits.add(request.uri.path);
      cookies.add(request.headers.value(HttpHeaders.cookieHeader));
      ranges.add(request.headers.value(HttpHeaders.rangeHeader));
      final output = request.response;
      switch (request.uri.path) {
        case '/master.m3u8':
          output.statusCode = HttpStatus.found;
          output.headers.set(HttpHeaders.locationHeader, '/cdn/master.m3u8');
        case '/cdn/master.m3u8':
          output.write('#EXTM3U\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=1200000\n'
              'video/media.m3u8\n');
        case '/cdn/video/media.m3u8':
          output.statusCode = HttpStatus.temporaryRedirect;
          output.headers.set(HttpHeaders.locationHeader, '/live/media.m3u8');
        case '/live/media.m3u8':
          output.write('#EXTM3U\n#EXT-X-TARGETDURATION:6\n'
              '#EXT-X-KEY:METHOD=AES-128,URI="keys/key.bin?sig=123"\n'
              '#EXTINF:6,\nsegment.ts\n');
        case '/live/keys/key.bin':
          output.add(List<int>.filled(16, 15));
        case '/live/segment.ts':
          if (request.headers.value(HttpHeaders.rangeHeader) ==
              'bytes=0-375') {
            output.statusCode = HttpStatus.partialContent;
            output.headers.set(HttpHeaders.contentRangeHeader,
                'bytes 0-375/376');
          }
          final media = List<int>.filled(376, 0)
            ..[0] = 0x47
            ..[188] = 0x47;
          output.add(media);
        default:
          output.statusCode = HttpStatus.notFound;
      }
      await output.close();
    });
    addTearDown(() async {
      await server.close(force: true);
    });

    final relay = LiveHlsHttpRelay();
    addTearDown(() async {
      await relay.close();
    });
    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final original = Uri(scheme: 'http',
        host: '127.0.0.1', port: server.port, path: '/master.m3u8');
    final local = await relay.expose(original, const {
      'Cookie': 'channel=test',
      'Referer': 'https://player.example/',
    });
    expect(local.host, InternetAddress.loopbackIPv4.address);
    expect(local.path.endsWith('.m3u8'), isTrue);
    final master = await fetchText(client, local);
    expect(master, startsWith('#EXTM3U\n'));
    expect(master, isNot(contains('video/media.m3u8')));
    final variant = Uri.parse(master.split('\n')
        .firstWhere((line) => line.startsWith('http://')));
    expect(variant.path.endsWith('.m3u8'), isTrue);
    final nested = await fetchText(client, variant);
    expect(nested, contains('#EXT-X-KEY:METHOD=AES-128,URI="http://'));
    final keyMatch = RegExp(r'URI="([^"]+)"').firstMatch(nested)!;
    final keyUri = Uri.parse(keyMatch.group(1)!);
    final segmentUri = Uri.parse(nested.split('\n')
        .firstWhere((line) => line.startsWith('http://')));
    expect(keyUri.path.endsWith('.bin'), isTrue);
    expect(segmentUri.path.endsWith('.ts'), isTrue);

    final keyRequest = await client.getUrl(keyUri);
    final keyResponse = await keyRequest.close();
    final key = await keyResponse.fold<List<int>>(
        <int>[], (data, bytes) => data..addAll(bytes));
    expect(keyResponse.statusCode, HttpStatus.ok);
    expect(key, hasLength(16));

    final mediaRequest = await client.getUrl(segmentUri);
    mediaRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=0-375');
    final mediaResponse = await mediaRequest.close();
    final bytes = await mediaResponse.fold<List<int>>(
        <int>[], (data, chunk) => data..addAll(chunk));
    expect(mediaResponse.statusCode, HttpStatus.partialContent);
    expect(mediaResponse.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 0-375/376');
    expect(bytes, hasLength(376));
    expect(bytes[0], 0x47);
    expect(bytes[188], 0x47);
    expect(hits, <String>[
      '/master.m3u8', '/cdn/master.m3u8',
      '/cdn/video/media.m3u8', '/live/media.m3u8',
      '/live/keys/key.bin', '/live/segment.ts',
    ]);
    expect(cookies.every((cookie) => cookie == 'channel=test'), isTrue);
    expect(ranges.last, 'bytes=0-375');
  });

  test('Redirect loops return 502 without opening a random URL',
      () async {
    final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4, 0);
    var hits = 0;
    server.listen((request) async {
      hits++;
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader, '/loop.m3u8');
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
    });
    final relay = LiveHlsHttpRelay();
    addTearDown(() async {
      await relay.close();
    });
    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });
    final local = await relay.expose(
      Uri(scheme: 'http', host: '127.0.0.1',
          port: server.port, path: '/loop.m3u8'), const {},
    );
    final request = await client.getUrl(local);
    final response = await request.close();
    expect(response.statusCode, HttpStatus.badGateway);
    await response.drain<void>();
    expect(hits, 1);
  });

  test('Upstream 403 remains 403 instead of fake playable playlist',
      () async {
    final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write('Forbidden');
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
    });
    final relay = LiveHlsHttpRelay();
    addTearDown(() async {
      await relay.close();
    });
    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });
    final local = await relay.expose(
      Uri(scheme: 'http', host: '127.0.0.1',
          port: server.port, path: '/denied.m3u8'), const {},
    );
    final request = await client.getUrl(local);
    final response = await request.close();
    expect(response.statusCode, HttpStatus.forbidden);
    expect(await utf8.decoder.bind(response).join(), 'Forbidden');
  });
  test('Extensionless HLS variants and audio renditions keep playlist type',
      () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((request) async {
      final path = request.uri.path;
      if (path == '/master.m3u8') {
        request.response.write('#EXTM3U\n'
            '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",URI="audio?sig=x"\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=10000,AUDIO="aud"\n'
            'variant?sig=y\n');
      } else if (path == '/variant' || path == '/audio') {
        request.response.headers.contentType = ContentType.text;
        request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:6\n'
            '#EXTINF:6,\nsegment?sig=z\n');
      } else if (path == '/segment') {
        final bytes = List<int>.filled(376, 0);
        bytes[0] = 0x47;
        bytes[188] = 0x47;
        request.response.add(bytes);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async => origin.close(force: true));
    final relay = LiveHlsHttpRelay();
    addTearDown(() => relay.close());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final masterUrl = await relay.expose(Uri(
        scheme: 'http', host: '127.0.0.1', port: origin.port,
        path: '/master.m3u8'), const {});
    final master = await fetchText(client, masterUrl);
    final audioUri = Uri.parse(RegExp(r'URI="([^"]+)"')
        .firstMatch(master)!.group(1)!);
    final variantUri = Uri.parse(master.split('\n')
        .firstWhere((line) => line.startsWith('http://')));
    expect(audioUri.path.endsWith('.m3u8'), isTrue);
    expect(variantUri.path.endsWith('.m3u8'), isTrue);
    final nested = await fetchText(client, variantUri);
    final audio = await fetchText(client, audioUri);
    expect(audio, contains('#EXTINF'));
    final mediaUri = Uri.parse(nested.split('\n')
        .firstWhere((line) => line.startsWith('http://')));
    expect(mediaUri.path.endsWith('.ts'), isTrue);
    final request = await client.getUrl(mediaUri);
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    final bytes = await response.fold<List<int>>(
        <int>[], (data, chunk) => data..addAll(chunk));
    expect(bytes[0], 0x47);
    expect(bytes[188], 0x47);
  });

}
