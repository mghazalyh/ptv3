import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playtorrio/services/remote/github_stremio_addon_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Live addon probe fetches manifest and Stremio tv streams', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/manifest.json')) {
        return http.Response(jsonEncode(<String, Object?>{
          'id': 'org.example.livetv',
          'version': '1.0.0',
          'name': 'Live TV',
          'resources': <Object>['stream', 'catalog', 'meta'],
          'types': <String>['tv'],
          'idPrefixes': <String>['nltv:'],
        }), 200, headers: const {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(<String, Object?>{
        'streams': <Object?>[
          <String, Object?>{
            'url': 'https://media.example/master.m3u8?token=NEVER_LOG_THIS',
            'behaviorHints': <String, Object?>{
              'proxyHeaders': <String, Object?>{
                'request': <String, Object?>{'Referer': 'https://example.org/'},
              },
            },
          },
          <String, Object?>{'infoHash': 'abc123'},
          <String, Object?>{'title': 'missing-url'},
        ],
      }), 200, headers: const {'content-type': 'application/json'});
    });
    final result = await GithubStremioAddonProbe.check(
      baseUrl: 'https://worker.example/config/sample',
      addonName: 'Live TV',
      channelId: 'nltv:us:NFLChannel.us',
      client: client,
    );
    expect(result['accepted'], true);
    expect(result['addonHost'], 'worker.example');
    expect(result['manifestHttpStatus'], 200);
    expect(result['manifestOutcome'], 'ok');
    expect(result['manifestValid'], true);
    expect(result['declaresTvStream'], true);
    expect(result['streamHttpStatus'], 200);
    expect(result['streamOutcome'], 'ok');
    expect(result['streamCount'], 3);
    expect(result['directHttpCount'], 1);
    expect(result['directHlsCount'], 1);
    expect(result['torrentCount'], 1);
    expect(result['invalidSourceCount'], 1);
    expect(result['sourcesWithRequestHeaders'], 1);
    expect(requests, hasLength(2));
    expect(requests.first.url.path, '/config/sample/manifest.json');
    expect(requests.last.url.path,
        '/config/sample/stream/tv/nltv:us:NFLChannel.us.json');
    expect(requests.every((r) =>
        r.headers['accept'] == 'application/json'), true);
    expect(jsonEncode(result), isNot(contains('NEVER_LOG_THIS')));
    client.close();
  });

  test('Manifest works while upstream stream resource returns HTTP 403',
      () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/manifest.json')) {
        return http.Response(jsonEncode({
          'id': 'live.tv', 'resources': ['stream'], 'types': ['tv'],
          'idPrefixes': ['nltv:'],
        }), 200);
      }
      return http.Response('Forbidden signed media route', 403,
          headers: {'content-type': 'text/html'});
    });
    final result = await GithubStremioAddonProbe.check(
      baseUrl: 'https://worker.example',
      addonName: 'Live TV',
      channelId: 'nltv:us:SYFY.us',
      client: client,
    );
    expect(result['manifestOutcome'], 'ok');
    expect(result['declaresTvStream'], true);
    expect(result['streamHttpStatus'], 403);
    expect(result['streamBodyKind'], 'html');
    expect(result['streamOutcome'], 'http_status');
    expect(result.containsKey('streamCount'), false);
    expect(result.toString(), isNot(contains('signed media route')));
    client.close();
  });

  test('HTML returned as manifest is rejected even with HTTP 200',
      () async {
    final client = MockClient((request) async => request.url.path
        .endsWith('/manifest.json')
        ? http.Response('<html>Access denied</html>', 200,
            headers: {'content-type': 'text/html'})
        : http.Response('{"streams":[]}', 200));
    final result = await GithubStremioAddonProbe.check(
      baseUrl: 'https://worker.example',
      addonName: 'Live TV',
      channelId: 'nltv:us:Channel.us',
      client: client,
    );
    expect(result['manifestOutcome'], 'invalid_json');
    expect(result['manifestValid'], false);
    expect(result['streamOutcome'], 'ok');
    expect(result['streamCount'], 0);
    client.close();
  });

  test('Refuses untrusted non-HTTPS addon base URL', () async {
    final result = await GithubStremioAddonProbe.check(
      baseUrl: 'http://127.0.0.1:8080',
      addonName: 'Live TV',
      channelId: 'nltv:us:Channel.us',
    );
    expect(result['accepted'], false);
    expect(result['reason'], 'invalid_installed_addon_endpoint');
  });
}
