import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/telemetry/telemetry_insights_repository.dart';

void main() {
  test('telemetry metrics use actual observations and failure codes', () {
    final data = TelemetryInsightsData();
    data.discovered = 1;
    data.ingest({
      'timestampUtc': '2026-11-18T15:37:11Z',
      'platform': 'windows',
      'reason': 'addon_failure',
      'buildRun': '198',
      'codes': ['addon_meta_unresolved', 'addon_meta_fallback_started'],
      'mediaContext': {'title': 'The Dog Stars'},
      'capabilities': {'audioCodec': 'aac'},
      'performanceSamples': [
        {
          'videoWidth': 1920, 'videoHeight': 800, 'videoFps': 24,
          'cacheSeconds': 15, 'avsyncSeconds': 0.005,
          'buffering': false, 'voDroppedDelta': 1,
          'decoderDroppedDelta': 0, 'lateFramesDelta': 1,
        },
        {
          'videoWidth': 3840, 'videoHeight': 2160, 'videoFps': 24,
          'cacheSeconds': 5, 'avsyncSeconds': 0,
          'buffering': true, 'voDroppedDelta': 0,
          'decoderDroppedDelta': 1, 'lateFramesDelta': 0,
        },
      ],
      'sourceTrace': [
        {'action': 'source_ranked', 'addon': 'Comet', 'resolution': '4K'},
        {'action': 'source_identity_rejected', 'addon': 'Torrentio',
         'identityVerdict': 'rejected'},
      ],
    });
    expect(data.loaded, 1);
    expect(data.failureReports, 1);
    expect(data.events['addon_meta_unresolved'], 1);
    expect(data.sampleCount, 2);
    expect(data.bufferingPercent, 50);
    expect(data.averageCache, 10);
    expect(data.averageFps, 24);
    expect(data.droppedFrames, 1);
    expect(data.decoderDrops, 1);
    expect(data.lateFrames, 1);
    expect(data.identityRejections, 1);
    expect(data.sources['Comet'], 1);
    expect(data.platforms['windows'], 1);
    expect(data.resolutions['1080p'], 1);
    expect(data.resolutions['4K'], 2);
  });

  test('missing telemetry never creates synthetic data', () {
    final data = TelemetryInsightsData();
    expect(data.loaded, 0);
    expect(data.averageFps, 0);
    expect(data.averageCache, 0);
    expect(data.bufferingPercent, 0);
    expect(data.insights, isNotEmpty);
  });
}
