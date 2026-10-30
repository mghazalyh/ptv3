import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/player/ios_audio_telemetry.dart';
import 'package:playtorrio/services/player/ios_night_mode_preflight.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Allowlist drops private movie, stream URL, headers, tokens and titles', () {
    expect(IosAudioTelemetry.classify(
      "AVFilterGraph: No such filter: 'acompressor'"),
      'missing_filter_acompressor');
    expect(IosAudioTelemetry.classify(
      "AVFilterGraph: No such filter: 'compand'"),
      'missing_filter_compand');
    expect(IosAudioTelemetry.classify(
      'Playback error: Audio filter initialized failed!'),
      'audio_filter_init_failed');
    for (final raw in [
      'https://secret.example/video?token=redacted',
      'Authorization: Bearer something',
      'The Legend of Vox Machina',
      '/private/var/mobile/some-file.mkv',
      'Cookie: abc123',
      'A completely different codec error',
    ]) {
      expect(IosAudioTelemetry.classify(raw), isNull);
    }
    expect(IosAudioTelemetry.safeAudioFields({
      'codec':'eac3', 'channels':'5.1', 'sampleRate':'48000',
      'title': 'PRIVATE_TITLE',
      'url': 'https://private/',
      'secret': 'PRIVATE_TOKEN',
    }), {'codec':'eac3','channels':'5.1','sampleRate':'48000'});
    expect(IosAudioTelemetry.safeAudioFields({
      'codec':'something private','channels':'A-Private-Name',
      'sampleRate':'-1'
    }), isEmpty);
  });

  test('Diagnostic preference defaults OFF and no HTTPS request is sent', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 201);
    });
    final telemetry = IosAudioTelemetry.forTesting(
      client: client, tokenProvider: () async => 'FAKE_TEST_TOKEN',
    )..forceTestPlatform = true;
    addTearDown(telemetry.dispose);
    await telemetry.initialize();
    expect(telemetry.enabled.value, isFalse);
    telemetry.captureNativeLog("No such filter: 'acompressor'");
    expect(telemetry.capturedCodes, isEmpty);
    expect(await telemetry.upload(), isFalse);
    expect(calls, 0);
  });

  test('With explicit opt-in, upload targets only private Torriodb and is redacted',
      () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{"content":{}}', 201);
    });
    final telemetry = IosAudioTelemetry.forTesting(
      client: client, tokenProvider: () async => 'FAKE_TEST_TOKEN',
    )..forceTestPlatform = true;
    addTearDown(telemetry.dispose);
    await telemetry.initialize();
    await telemetry.setEnabled(true);
    telemetry.captureNativeLog(
      "No such filter: 'acompressor' https://secret.invalid/?token=SECRET");
    telemetry.captureCode('private_user_title'); // Never accepted as a report field.
    expect(telemetry.capturedCodes, isNot(contains('private_user_title')));
    telemetry.captureNativeLog(
      "Playback error: Audio filter initialized failed! The Legend of Vox Machina");
    final ok = await telemetry.upload(
      reason: 'night_mode_failed',
      audio: {'codec': 'eac3','channels': '5.1','sampleRate': 48000,
        'title': 'PRIVATE_TITLE', 'url': 'https://source.invalid/private'},
    );
    expect(ok, isTrue);
    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.method, 'PUT');
    expect(request.url.host, 'api.github.com');
    expect(request.url.path, startsWith(
      '/repos/mghazalyh/torriodb/contents/playtorrio/diagnostics/ios/night-mode/'));
    final wrapper = jsonDecode(request.body) as Map<String, dynamic>;
    expect(wrapper['branch'], 'main');
    final report = jsonDecode(utf8.decode(
      base64Decode(wrapper['content'] as String))) as Map<String, dynamic>;
    expect(report['platform'], 'ios');
    expect(report['reason'], 'night_mode_failed');
    expect(report['nativeErrorCodes'],
      ['missing_filter_acompressor', 'audio_filter_init_failed']);
    expect(report['audio'], {'codec':'eac3','channels':'5.1','sampleRate':'48000'});
    final text = jsonEncode(report);
    for (final private in [
      'SECRET', 'secret.invalid', 'PRIVATE_TITLE',
      'source.invalid', 'Legend of Vox Machina', 'FAKE_TEST_TOKEN'
    ]) {
      expect(text, isNot(contains(private)));
    }
    expect(telemetry.capturedCodes, isEmpty);
    await telemetry.setEnabled(false);
    expect(telemetry.enabled.value, isFalse);
    telemetry.captureNativeLog("No such filter: 'compand'");
    expect(telemetry.capturedCodes, isEmpty);
    expect(await telemetry.upload(), isFalse);
    expect(requests, hasLength(1));
  });

  test('iOS performance sampling remains strictly OFF without opt in', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final telemetry = IosAudioTelemetry.forTesting(
      client: MockClient((_) async {
        calls++;
        return http.Response('', 201);
      }),
      tokenProvider: () async => 'FAKE_TEST_TOKEN',
    )..forceTestPlatform = true;
    addTearDown(telemetry.dispose);
    await telemetry.initialize();
    telemetry.capturePlaybackSample({
      'frame-drop-count': '59', 'avsync': '1.5',
      'filename': 'private-show.mkv',
    }, buffering: true);
    expect(telemetry.capturedCodes, isEmpty);
    expect(telemetry.capturedPerformanceSamples, isEmpty);
    expect(await telemetry.upload(reason: 'playback_sample'), isFalse);
    expect(calls, 0);
  });

  test('iOS samples real frame-drop deltas and uploads only allowlisted metrics',
      () async {
    SharedPreferences.setMockInitialValues({});
    Map<String, dynamic>? uploaded;
    final telemetry = IosAudioTelemetry.forTesting(
      client: MockClient((request) async {
        expect(request.url.host, 'api.github.com');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        uploaded = jsonDecode(utf8.decode(
            base64Decode(payload['content'] as String))) as Map<String, dynamic>;
        return http.Response('{}', 201);
      }),
      tokenProvider: () async => 'FAKE_TEST_TOKEN',
    )..forceTestPlatform = true;
    addTearDown(telemetry.dispose);
    await telemetry.initialize();
    await telemetry.setEnabled(true);
    telemetry.capturePlaybackSample({
      'frame-drop-count': '120',
      'decoder-frame-drop-count': '3',
      'vo-delayed-frame-count': '20',
      'avsync': '0.025',
      'demuxer-cache-duration': '12.5',
      'hwdec-current': 'videotoolbox',
      'path': '/private/var/mobile/movie.mkv',
      'url': 'https://private.invalid/video?token=SECRET',
      'title': 'PRIVATE_MOVIE',
    });
    telemetry.capturePlaybackSample({
      'frame-drop-count': '131',
      'decoder-frame-drop-count': '4',
      'vo-delayed-frame-count': '25',
      'avsync': '0.15',
      'demuxer-cache-duration': '0.5',
      'hwdec-current': 'videotoolbox',
    }, buffering: true);
    expect(telemetry.capturedPerformanceSamples.last['voDroppedDelta'], 11);
    expect(telemetry.capturedPerformanceSamples.last['decoderDroppedDelta'], 1);
    expect(telemetry.capturedPerformanceSamples.last['lateFramesDelta'], 5);
    expect(await telemetry.upload(reason: 'playback_sample', automatic: true), true);
    expect(uploaded!['platform'], 'ios');
    expect(uploaded!['reason'], 'playback_sample');
    expect(uploaded!['sampleIntervalSeconds'], 5);
    final samples = uploaded!['performanceSamples'] as List<dynamic>;
    expect(samples, hasLength(2));
    expect(samples.last['buffering'], true);
    expect(samples.last['cacheSeconds'], 0.5);
    expect(samples.last['hardwareDecoder'], 'videotoolbox');
    expect(uploaded!['nativeErrorCodes'],
        containsAll(['playback_frame_drops', 'playback_buffering']));
    final json = jsonEncode(uploaded);
    for (final forbidden in [
      'PRIVATE_MOVIE', 'private.invalid', 'SECRET',
      'private/var', 'FAKE_TEST_TOKEN',
    ]) {
      expect(json, isNot(contains(forbidden)));
    }
    expect(telemetry.capturedPerformanceSamples, isEmpty);
    expect(telemetry.capturedCodes, isEmpty);
  });

  test('iOS playback sample cap and toggle OFF clear samples and counters',
      () async {
    SharedPreferences.setMockInitialValues({});
    final telemetry = IosAudioTelemetry.forTesting(
      client: MockClient((_) async => http.Response('{}', 201)),
      tokenProvider: () async => 'FAKE_TEST_TOKEN',
    )..forceTestPlatform = true;
    addTearDown(telemetry.dispose);
    await telemetry.initialize();
    await telemetry.setEnabled(true);
    for (var i = 0; i < 40; i++) {
      telemetry.capturePlaybackSample({
        'frame-drop-count': '$i',
        'avsync': 'NaN',
        'demuxer-cache-duration': '-5000000000',
      });
    }
    expect(telemetry.capturedPerformanceSamples,
        hasLength(IosAudioTelemetry.maxPlaybackSamples));
    expect(telemetry.capturedPerformanceSamples.first['voDropped'], 16);
    expect(telemetry.capturedPerformanceSamples.last['voDropped'], 39);
    expect(telemetry.capturedPerformanceSamples.last.containsKey('avsyncSeconds'), false);
    expect(telemetry.capturedPerformanceSamples.last.containsKey('cacheSeconds'), false);
    await telemetry.setEnabled(false);
    expect(telemetry.capturedPerformanceSamples, isEmpty);
    await telemetry.setEnabled(true);
    telemetry.capturePlaybackSample({'frame-drop-count': '1'});
    expect(telemetry.capturedPerformanceSamples.last['voDroppedDelta'], 0);
  });

  test('Missing token never makes a remote call; reports useful status', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final telemetry = IosAudioTelemetry.forTesting(
      client: MockClient((_) async {
        calls++;
        return http.Response('', 201);
      }),
      tokenProvider: () async => null,
    )..forceTestPlatform = true;
    addTearDown(telemetry.dispose);
    await telemetry.initialize();
    await telemetry.setEnabled(true);
    telemetry.captureCode('ios_filter_preflight_failed');
    expect(await telemetry.upload(), isFalse);
    expect(calls, 0);
    expect(telemetry.status.value, contains('GitHub Library'));
    expect(telemetry.capturedCodes, isNotEmpty);
  });

  test('iOS preflight alternative preserves speed and actual compression', () {
    expect(IosNightModePreflight.compand, contains('compand='));
    expect(IosNightModePreflight.compand, contains('points='));
    expect(IosNightModePreflight.compand, isNot(contains('acompressor')));
  });
}
