import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/ios_audio_telemetry.dart';
import 'package:playtorrio/services/stream/watch_source_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Marshals source ranking and actual audio track choice are recorded',
      () async {
    SharedPreferences.setMockInitialValues({});
    final reports = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.url.host, 'api.github.com');
      final wrapper = jsonDecode(request.body) as Map<String, dynamic>;
      expect(wrapper['branch'], 'main');
      reports.add(jsonDecode(utf8.decode(
        base64Decode(wrapper['content'] as String))) as Map<String, dynamic>);
      return http.Response('{}', 201);
    });
    final telemetry = IosAudioTelemetry.forTesting(
      client: client,
      tokenProvider: () async => 'TEST_ONLY_ACCESS_TOKEN',
    )..forceTestPlatform = true;
    addTearDown(telemetry.dispose);
    await telemetry.initialize();
    await telemetry.setEnabled(true);

    final russian = StreamSource(
      addonName: 'Comet',
      name: '[TB+] 4K',
      title: 'Marshals.S01E01.2160p.WEB-DL.RUS.6GB.mkv',
      description: 'Russian audio; https://signed.invalid/media?token=SECRET',
      url: 'https://signed.invalid/stream?token=SECRET',
      infoHash: '0123456789012345678901234567890123456789',
      fileIdx: 4,
    );
    final english = StreamSource(
      addonName: 'Torrentio TB',
      title: 'Marshals.S01E01.1080p.WEB-DL.English.2GB.mkv',
      url: 'https://signed.invalid/english?token=SECRET',
    );
    telemetry.beginSourceSession(
      title: 'Marshals', mediaId: 'tt10020030:1:1',
      type: 'series', season: 1, episode: 1, episodeTitle: 'Pilot',
    );
    telemetry.captureSourceRanking(
      sources: [russian, english],
      sorted: [russian, english],
      title: 'Marshals', season: 1, episode: 1,
      profile: const WatchSourceProfile(),
    );
    telemetry.captureSourceSelection(
      action: 'watch_source_tapped', source: russian,
      title: 'Marshals', season: 1, episode: 1, visibleRank: 1,
    );
    telemetry.captureAudioTracks(
      stage: 'native_mpv_track_list',
      selectedTrackId: 1,
      tracks: [
        {'id': 1, 'language': 'rus', 'title': 'Russian 5.1',
          'channels': 6},
      ],
    );
    telemetry.captureAudioSelection(
      action: 'no_english_track_detected',
      actualTrackId: 1,
    );
    telemetry.capturePlaybackSample(
      {'avsync': '0.0'}, selectedAudioTrackId: 1,
    );

    expect(await telemetry.upload(reason: 'playback_sample'), isTrue);
    expect(reports, hasLength(1));
    final report = reports.single;
    expect(report['schema'], 2);
    expect(report['kind'], 'ios_playback_source_audio_developer_diagnostic');
    expect(report['mediaContext']['title'], 'Marshals');
    expect(report['mediaContext']['episode'], 1);
    expect(report['sourceSessionId'], isNotEmpty);
    final trace = (report['sourceTrace'] as List).cast<Map<String, dynamic>>();
    final ranking = trace.firstWhere((e) =>
        e['action'] == 'source_ranking_completed');
    expect(ranking['preferEnglishAudio'], true);
    expect(ranking['rankedSources'], hasLength(2));
    final first = (ranking['rankedSources'] as List).first;
    expect(first['addon'], 'Comet');
    expect(first['releaseFilename'], contains('RUS'));
    expect(first['cacheTier'], isNotNull);
    final tapped = trace.firstWhere((e) => e['action'] == 'watch_source_tapped');
    expect(tapped['visibleRank'], 1);
    expect(tapped['releaseFilename'], contains('Marshals'));
    final tracks = trace.firstWhere((e) => e['action'] == 'audio_tracks_observed');
    expect((tracks['tracks'] as List).first['language'], 'rus');
    expect((tracks['tracks'] as List).first['selected'], true);
    expect((tracks['tracks'] as List).first['englishLabel'], false);
    expect(trace.any((e) => e['action'] == 'no_english_track_detected'), true);
    expect(report['performanceSamples'][0]['selectedAudioTrackId'], 1);

    final json = jsonEncode(report);
    expect(json, contains('Marshals.S01E01'));
    expect(json, isNot(contains('SECRET')));
    expect(json, isNot(contains('signed.invalid')));
    expect(json, isNot(contains('TEST_ONLY_ACCESS_TOKEN')));
    expect(telemetry.capturedSourceTrace, isEmpty);
  });

  test('source and audio trace are never uploaded when diagnostics are off',
      () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final telemetry = IosAudioTelemetry.forTesting(
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 201);
      }),
      tokenProvider: () async => 'TEST_ONLY_ACCESS_TOKEN',
    )..forceTestPlatform = true;
    addTearDown(telemetry.dispose);
    await telemetry.initialize();
    final sample = StreamSource(
      addonName: 'Comet', title: 'Marshals.S01E01.RUS.mkv');
    telemetry.beginSourceSession(
      title: 'Marshals', mediaId: 'test:1:1', type: 'series');
    telemetry.captureSourceSelection(
      action: 'source_open_attempt', source: sample, title: 'Marshals');
    telemetry.captureAudioTracks(
      stage: 'native', tracks: [{'id': 1, 'language': 'rus'}]);
    expect(telemetry.capturedSourceTrace, isEmpty);
    expect(await telemetry.upload(), false);
    expect(calls, 0);
  });
  test('iOS performance upload retries GitHub branch contention', () async {
    SharedPreferences.setMockInitialValues({});
    var writes = 0;
    final telemetry = IosAudioTelemetry.forTesting(
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        writes++;
        if (writes == 1) return http.Response('{}', 409);
        return http.Response('{}', 201);
      }),
      tokenProvider: () async => 'TEST_ONLY_ACCESS_TOKEN',
    )..forceTestPlatform = true;
    addTearDown(telemetry.dispose);
    await telemetry.initialize();
    await telemetry.setEnabled(true);
    telemetry.beginSourceSession(
      title: 'Live Test', mediaId: 'nltv:us:LiveTest.us', type: 'tv');
    expect(await telemetry.upload(reason: 'playback_sample'), true);
    expect(writes, 2);
  });

}
