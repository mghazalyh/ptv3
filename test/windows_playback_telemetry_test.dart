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

  test('per-frame Windows diagnostics are opt-in with zero sampling when off',
      () {
    final telemetry = WindowsPlaybackTelemetry.forTesting(
      client: MockClient((_) async => http.Response('{}', 201)),
      tokenProvider: () async => 'test-only-placeholder',
    )..forceTestPlatform = true;
    telemetry.capturePlaybackSample({
      'frame-drop-count': '25', 'avsync': '0.9',
      'filename': 'sensitive show title',
    }, buffering: true);
    expect(telemetry.capturedSamples, isEmpty);
    expect(telemetry.capturedFacts, isEmpty);
    telemetry.dispose();
  });

  test('gaming frame loss is reported as bounded deltas, not URLs or titles',
      () async {
    Map<String, dynamic>? report;
    final telemetry = WindowsPlaybackTelemetry.forTesting(
      client: MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        report = jsonDecode(utf8.decode(
            base64Decode(payload['content'] as String))) as Map<String, dynamic>;
        return http.Response('{}', 201);
      }),
      tokenProvider: () async => 'test-only-placeholder',
    )..forceTestPlatform = true;
    NightModeDiagnostics.debugModeEnabled.value = true;
    telemetry.captureProperty('brightness-pipeline', 'flutter-color-matrix');
    telemetry.capturePlaybackSample({
      'frame-drop-count': '200',
      'decoder-frame-drop-count': '1',
      'vo-delayed-frame-count': '5',
      'mistimed-frame-count': '0',
      'avsync': '0.025',
      'demuxer-cache-duration': '18.5',
      'hwdec-current': 'd3d11va-copy',
      'vf': '',
      'framedrop': 'vo',
      'video-sync': 'audio',
      'flutter-frame-count': '220',
      'flutter-slow-build-count': '2',
      'flutter-slow-raster-count': '7',
      'flutter-worst-raster-ms': '89',
      'path': 'private/movie/file.mkv',
      'title': 'Secret TV title',
    });
    telemetry.capturePlaybackSample({
      'frame-drop-count': '211',
      'decoder-frame-drop-count': '1',
      'vo-delayed-frame-count': '8',
      'avsync': '0.18',
      'demuxer-cache-duration': '0.2',
      'hwdec-current': 'd3d11va-copy',
      'vf': '',
      'framedrop': 'vo',
    }, buffering: true);
    expect(telemetry.capturedSamples.last['voDroppedDelta'], 11);
    expect(telemetry.capturedSamples.last['lateFramesDelta'], 3);
    expect(telemetry.capturedSamples.first['flutterSlowRasterFrames'], 7);
    expect(telemetry.capturedSamples.first['flutterWorstRasterMs'], 89);
    expect(telemetry.capturedSamples.last['cacheSeconds'], 0.2);
    expect(await telemetry.upload(reason: 'playback_sample'), isTrue);
    expect(report!['reason'], 'playback_sample');
    expect(report!['sampleIntervalSeconds'], 5);
    final samples = report!['performanceSamples'] as List<dynamic>;
    expect(samples, hasLength(2));
    final metrics = report!['capabilities'] as Map<String, dynamic>;
    expect(metrics['videoEqFilterActive'], false);
    expect(metrics['brightnessPipeline'], 'flutter-color-matrix');
    expect(metrics['hardwareDecoder'], 'd3d11va-copy');
    expect(metrics['frameDropMode'], 'vo');
    expect((report!['codes'] as List), contains('render_stutter_detected'));
    expect((report!['codes'] as List), contains('flutter_frame_stutter'));
    expect((report!['codes'] as List), contains('playback_buffering'));
    final json = jsonEncode(report);
    expect(json, isNot(contains('private/movie')));
    expect(json, isNot(contains('Secret TV title')));
    expect(telemetry.capturedSamples, isEmpty);
    telemetry.dispose();
  });

  test('Windows performance sampler retains at most 24 consecutive samples',
      () {
    final telemetry = WindowsPlaybackTelemetry.forTesting(
      client: MockClient((_) async => http.Response('{}', 201)),
      tokenProvider: () async => 'test-only-placeholder',
    )..forceTestPlatform = true;
    NightModeDiagnostics.debugModeEnabled.value = true;
    for (var i = 0; i < 40; i++) {
      telemetry.capturePlaybackSample({
        'frame-drop-count': '$i',
        'avsync': 'NaN',
        'demuxer-cache-duration': '-9999999999999',
      });
    }
    expect(telemetry.capturedSamples.length, WindowsPlaybackTelemetry.maxSamples);
    expect(telemetry.capturedSamples.first['voDropped'], 16);
    expect(telemetry.capturedSamples.last['voDropped'], 39);
    expect(telemetry.capturedSamples.last.containsKey('avsyncSeconds'), false);
    expect(telemetry.capturedSamples.last.containsKey('cacheSeconds'), false);
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
