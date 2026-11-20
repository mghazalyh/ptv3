import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/player/ios_audio_telemetry.dart';
import 'package:playtorrio/services/player/live_tv/live_programme_metadata.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Live guide metadata distinguishes channel from programme title', () {
    final guide = LiveProgrammeMetadata.resolve(
      metaHints: <String, dynamic>{
        'nowPlaying': <String, dynamic>{'title': 'The Great Escape'},
        'programmeType': 'movie',
      },
    );
    expect(guide.title, 'The Great Escape');
    expect(guide.kind, 'movie');
    final noGuide = LiveProgrammeMetadata.resolve(
      metaHints: <String, dynamic>{'isLive': true},
    );
    expect(noGuide.title, isNull);
    expect(noGuide.kind, isNull);
    final unsafe = LiveProgrammeMetadata.resolve(
      metaHints: <String, dynamic>{
        'nowPlaying': 'https://signed.example/a?token=SECRET',
      },
    );
    expect(unsafe.title, isNull);
  });

  test('iPad Live TV diagnostics include named channel, programme and metrics',
      () async {
    SharedPreferences.setMockInitialValues({});
    final reports = <Map<String, dynamic>>[];
    final telemetry = IosAudioTelemetry.forTesting(
      client: MockClient((request) async {
        final wrapper = jsonDecode(request.body) as Map<String, dynamic>;
        reports.add(jsonDecode(utf8.decode(
          base64Decode(wrapper['content'] as String))) as Map<String, dynamic>);
        return http.Response('{}', 201);
      }),
      tokenProvider: () async => 'TEST_SECRET_ACCESS',
    )..forceTestPlatform = true;
    addTearDown(telemetry.dispose);
    await telemetry.initialize();
    await telemetry.setEnabled(true);
    telemetry.ensurePlaybackContext(
      title: 'Cine Romantico',
      mediaId: 'nltv:us:CineRomantico.us',
      type: 'tv',
      episodeTitle: 'The Great Escape',
    );
    telemetry.captureLiveTvObservation(
      event: 'live_health_sample',
      channelId: 'nltv:us:CineRomantico.us',
      channelTitle: 'Cine Romantico',
      programmeTitle: 'The Great Escape',
      programmeKind: 'movie',
      sourceAddon: 'Live TV',
      sourceName: '● LIVE HD',
      sourceDescription:
          'Roku https://cdn.example/hls/master.m3u8?token=SECRET',
      sourceHost: 'cdn.example',
      sourceFormat: 'hls',
      sourceQuality: '720p',
      signalQuality: 'unstable',
      recoveryAttempts: 2,
      candidateCount: 3,
      buffering: true,
      playing: false,
      verifiedPlayback: false,
      reconnecting: true,
      positionMs: 7000,
      bufferedEndMs: 9000,
      motionAgeMs: 16000,
      feedAgeMs: 30000,
      startupElapsedMs: 55000,
      recoveryElapsedMs: 8000,
      firstFrameElapsedMs: 20000,
      videoWidth: 1280,
      videoHeight: 720,
      playlistSequence: 12345,
      playlistTargetSeconds: 6,
      playlistDiscontinuities: 1,
      failureClass: 'buffer_starvation',
    );
    expect(telemetry.capturedLiveTvSummary['channelTitle'], 'Cine Romantico');
    expect(telemetry.capturedLiveTvSummary['programmeTitle'], 'The Great Escape');
    expect(await telemetry.upload(reason: 'live_health'), isTrue);
    expect(reports, hasLength(1));
    final report = reports.single;
    expect(report['reason'], 'live_health');
    expect(report['mediaContext']['title'], 'Cine Romantico');
    expect(report['mediaContext']['episodeTitle'], 'The Great Escape');
    final summary = report['liveTvSummary'] as Map<String, dynamic>;
    expect(summary['sourceHost'], 'cdn.example');
    expect(summary['programmeTitle'], 'The Great Escape');
    expect(summary['sourceFormat'], 'hls');
    expect(summary['recoveryAttempts'], 2);
    expect(summary['positionMs'], 7000);
    expect(summary['playlistSequence'], 12345);
    expect(summary['videoWidth'], 1280);
    expect(summary['verifiedPlayback'], false);
    final trace = (report['sourceTrace'] as List).cast<Map<String, dynamic>>();
    expect(trace.last['action'], 'live_health_sample');
    expect(trace.last['channelTitle'], 'Cine Romantico');
    final raw = jsonEncode(report);
    expect(raw, isNot(contains('SECRET')));
    expect(raw, isNot(contains('signed.example')));
    expect(raw, isNot(contains('TEST_SECRET_ACCESS')));
    expect(raw, isNot(contains('/hls/master.m3u8')));
  });

  test('Live TV observations do not run without owner opt-in', () async {
    SharedPreferences.setMockInitialValues({});
    final telemetry = IosAudioTelemetry.forTesting(
      client: MockClient((_) async => http.Response('{}', 201)),
      tokenProvider: () async => 'fake',
    )..forceTestPlatform = true;
    addTearDown(telemetry.dispose);
    await telemetry.initialize();
    telemetry.captureLiveTvObservation(
      event: 'live_health_sample',
      channelId: 'nltv:us:test',
      channelTitle: 'Private Channel',
      sourceAddon: 'Live TV',
      recoveryAttempts: 0,
      candidateCount: 1,
      buffering: true,
      playing: false,
      verifiedPlayback: false,
      reconnecting: false,
    );
    expect(telemetry.capturedLiveTvSummary, isEmpty);
    expect(telemetry.capturedSourceTrace, isEmpty);
  });
}
