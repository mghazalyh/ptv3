import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/movie/movie.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/live_tv/live_native_channel_verifier.dart';
import 'package:playtorrio/services/remote/ios_remote_live_visual_scan.dart';
import 'package:playtorrio/services/remote/ios_remote_visual_frame_encoder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final png = Uint8List.fromList(<int>[
    137, 80, 78, 71, 13, 10, 26, 10,
    ...List<int>.filled(32, 0),
  ]);

  LiveNativeSourceResult nativeSuccess() => const LiveNativeSourceResult(
    renderedVideo: true,
    timelineAdvanceMs: 6500,
    buffering: false,
    videoWidth: 1280,
    videoHeight: 720,
    trackCount: 2,
    startupMs: 800,
  );

  test('Accepts metadata-free channel for real native frame inspection',
      () async {
    final scan = IosRemoteLiveVisualScan();
    final outputs = <String, Map<String, Object?>>{};
    var encodedCount = 0;
    final start = await scan.start({
      'runId': 'basketball_visual_01',
      'contentHint': 'basketball',
      'channels': [
        {
          'id': 'nltv:us:OpaqueChannel.us',
          'title': 'Mystery Channel 12',
        },
      ],
      'framesPerChannel': 2,
    },
      deviceIdle: () => true,
      resolveSources: (Movie channel) async => <StreamSource>[
        StreamSource(
          name: 'Unlabelled stream', addonName: 'Installed Stremio Addon',
          url: 'https://media.example.test/live.m3u8',
        ),
      ],
      probe: ({
        required String channelId,
        required StreamSource source,
        required bool Function() isCancelled,
        Future<bool> Function(Uint8List, int)? onFrame,
        required int maxFrames,
      }) async {
        expect(channelId, 'nltv:us:OpaqueChannel.us');
        expect(maxFrames, 2);
        final observe = onFrame;
        if (observe == null) {
          throw StateError('Expected a native video frame observer');
        }
        await observe(png, 2500);
        await observe(png, 6000);
        return nativeSuccess();
      },
      encodeFrame: (Uint8List frame) async {
        return Uint8List.fromList(<int>[
          ...png,
          ++encodedCount,
        ]);
      },
      publish: (runId, key, payload) async {
        outputs[key] = Map<String, Object?>.from(payload);
      },
    );
    expect(start['accepted'], true);
    await scan.whenComplete;
    final status = scan.status();
    expect(status['phase'], 'completed');
    expect(status['nativeVerifiedChannels'], 1);
    expect(status['classificationPerformed'], false);
    expect(status['publishedFrames'], 2);
    expect(outputs.containsKey('frame_0_0'), true);
    expect(outputs.containsKey('frame_0_1'), true);
    final first = outputs['frame_0_0']!;
    expect(first['mimeType'], 'image/png');
    expect(first['nativeVerified'], true);
    expect(base64Decode(first['imageBase64'] as String), isNotEmpty);
    expect(jsonEncode(outputs), isNot(contains('media.example.test')));
    expect((outputs['channel_0']!['classification']), 'unclassified');
  });

  test('Native stall cannot publish frames as working evidence', () async {
    final scan = IosRemoteLiveVisualScan();
    final written = <String>[];
    await scan.start({
      'runId': 'basketball_visual_02',
      'channels': [
        {'id': 'iptv:us:Unknown.us', 'title': 'Unknown'},
      ],
    },
      deviceIdle: () => true,
      resolveSources: (channel) async => <StreamSource>[
        StreamSource(
          name: 'Test', addonName: 'Installed',
          url: 'https://media.example.test/channel.m3u8',
        ),
      ],
      probe: ({
        required String channelId,
        required StreamSource source,
        required bool Function() isCancelled,
        Future<bool> Function(Uint8List, int)? onFrame,
        required int maxFrames,
      }) async {
        final observe = onFrame;
        if (observe == null) {
          throw StateError('Expected a native video frame observer');
        }
        await observe(png, 2000);
        return const LiveNativeSourceResult(
          renderedVideo: true, timelineAdvanceMs: 0,
          buffering: true, videoWidth: 1280, videoHeight: 720,
          trackCount: 2,
        );
      },
      encodeFrame: (frame) async => png,
      publish: (runId, key, payload) async => written.add(key),
    );
    await scan.whenComplete;
    expect(scan.status()['nativeVerifiedChannels'], 0);
    expect(scan.status()['publishedFrames'], 0);
    expect(written.where((key) => key.startsWith('frame_')), isEmpty);
  });

  test('Busy device refuses visual scan before spawning an MPV player',
      () async {
    final scan = IosRemoteLiveVisualScan();
    final outcome = await scan.start({
      'runId': 'basketball_visual_03',
      'channels': [
        {'id': 'nltv:us:OpaqueChannel.us', 'title': 'Unknown'},
      ],
    },
      deviceIdle: () => false,
      publish: (runId, key, payload) async {},
    );
    expect(outcome['accepted'], false);
    expect(outcome['reason'], 'device_busy_or_not_foreground');
  });

  test('Malformed or excessive visual scans cannot start', () async {
    final scan = IosRemoteLiveVisualScan();
    for (final input in <Map<String, dynamic>>[
      {'runId': '../bad', 'channels': []},
      {
        'runId': 'basketball_visual_04',
        'channels': List.generate(16, (i) => {
          'id': 'nltv:us:$i', 'title': 'Unknown $i',
        }),
      },
      {
        'runId': 'basketball_visual_05',
        'channels': [
          {'id': 'nltv:us:Same.us', 'title': 'Unknown'},
          {'id': 'nltv:us:Same.us', 'title': 'Unknown'},
        ],
      },
    ]) {
      final result = await scan.start(
        input, deviceIdle: () => true,
        publish: (runId, key, payload) async {},
      );
      expect(result['accepted'], false);
    }
  });

  test('PNG validator rejects oversized or non-PNG evidence', () {
    expect(IosRemoteVisualFrameEncoder.isBoundedPng(png), true);
    expect(IosRemoteVisualFrameEncoder.isBoundedPng(
        Uint8List.fromList(List<int>.filled(40, 0))), false);
    expect(IosRemoteVisualFrameEncoder.isBoundedPng(
        Uint8List(64001)), false);
  });
}
