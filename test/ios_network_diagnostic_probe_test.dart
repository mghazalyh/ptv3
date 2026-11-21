import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/ios_network_diagnostic_probe.dart';

void main() {
  test('HTTP probe captures status, headers, body and timings', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.set('X-Diagnostic', 'mpv');
      request.response.statusCode = 206;
      request.response.write('segment-data');
      await request.response.close();
    });
    final result = await IosNetworkDiagnosticProbe.run({
      'url': 'http://127.0.0.1:${server.port}/segment',
      'maxBytes': 128,
    });
    expect(result['accepted'], true);
    expect(result['status'], 206);
    expect(result['bodyPreview'], 'segment-data');
    expect(result['dnsMs'], isA<int>());
    expect(result['responseHeaders'], isA<Map>());
    expect(result['bytesRead'], 12);
  });

  test('HTTP probe rejects invalid URLs and parameters', () async {
    expect((await IosNetworkDiagnosticProbe.run({
      'url': 'file:///private/etc/hosts'
    }))['accepted'], false);
    expect((await IosNetworkDiagnosticProbe.run({
      'url': 'http://example.com', 'maxBytes': 20000,
    }))['accepted'], false);
    expect((await IosNetworkDiagnosticProbe.run({
      'url': 'https://example.com', 'method': 'DELETE',
    }))['accepted'], false);
    expect((await IosNetworkDiagnosticProbe.run({
      'url': 'https://example.com', 'headers': {'x-test': 33},
    }))['accepted'], false);
  });
}
