import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playtorrio/services/player/night_mode_diagnostics.dart';
import 'package:playtorrio/services/player/windows_playback_telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    NightModeDiagnostics.debugModeEnabled.value = false;
  });
  tearDown(() {
    NightModeDiagnostics.debugModeEnabled.value = false;
  });

  test('Windows telemetry is disabled without explicit Debug Mode opt in',
      () async {
    var networkRequests = 0;
    final telemetry = WindowsPlaybackTelemetry.forTesting(
      client: MockClient((request) async {
        networkRequests++;
        return http.Response('{}', 201);
      }),
      tokenProvider: () async => 'test-only-placeholder',
    )..forceTestPlatform = true;
    telemetry.captureProperty('vf', 'lavfi=[eq=brightness=0.250]');
    expect(telemetry.capturedFacts, isEmpty);
    expect(await telemetry.upload(), isFalse);
    expect(networkRequests, 0);
    telemetry.dispose();
  });

  test('Windows report contains only safe and allowlisted capabilities',
      () async {
    Map<String, dynamic>? report;
    final telemetry = WindowsPlaybackTelemetry.forTesting(
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, contains(
            '/repos/mghazalyh/torriodb/contents/playtorrio/diagnostics/windows/player/'));
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        final bytes = base64Decode(data['content'] as String);
        report = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        return http.Response('{}', 201);
      }),
      tokenProvider: () async => 'test-only-placeholder',
    )..forceTestPlatform = true;
    NightModeDiagnostics.debugModeEnabled.value = true;

    telemetry.captureCode('brightness_changed');
    telemetry.captureCode('invalid-arbitrary-code');
    telemetry.captureProperty('af', 'scaletempo2,lavfi=[acompressor=foo,alimiter=bar]');
    telemetry.captureProperty('vf', 'lavfi=[eq=brightness=0.25]');
    telemetry.captureProperty('brightness', '0');
    telemetry.captureProperty('vo', 'gpu-next');
    telemetry.captureProperty('audio-codec-name', 'eac3');
    telemetry.captureProperty('url', 'https://example.test/secret?token=abc');
    telemetry.captureProperty('audio-codec-name', 'https://attacker.example/key');
    expect(await telemetry.upload(), isTrue);
    final encoded = jsonEncode(report);
    expect(encoded, isNot(contains('example.test')));
    expect(encoded, isNot(contains('secret')));
    expect(encoded, isNot(contains('token=abc')));
    expect(report!['platform'], 'windows');
    expect(report!['codes'], ['brightness_changed']);
    final facts = report!['capabilities'] as Map<String, dynamic>;
    expect(facts['audioCompressorActive'], isTrue);
    expect(facts['audioLimiterActive'], isTrue);
    expect(facts['videoEqFilterActive'], isTrue);
    expect(facts['videoOutput'], 'gpu-next');
    expect(facts['audioCodec'], 'eac3');
    telemetry.dispose();
  });
}
