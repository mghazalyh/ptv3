import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/playback_diagnostics_probe.dart';
import 'package:playtorrio/widgets/player/player_diagnostics_overlay.dart';
import 'package:playtorrio/widgets/player/player_transport.dart';

void main() {
  test('probe shows only allowlisted player properties, not stream URLs', () async {
    final called = <String>[];
    final values = await PlaybackDiagnosticsProbe.sample((name) async {
      called.add(name);
      if (name == 'video-codec') return 'h264';
      if (name == 'video-params/w') return '1920';
      if (name == 'video-params/h') return '1080';
      if (name == 'audio-codec') return 'https://private.example/token?key=ABC';
      if (name == 'estimated-vf-fps') throw StateError('unsupported');
      return null;
    });
    expect(values['video-codec'], 'h264');
    expect(PlaybackDiagnosticsProbe.resolution(values), '1920 × 1080');
    expect(values.containsKey('audio-codec'), false);
    expect(called, PlaybackDiagnosticsProbe.properties);
    expect(called.any((p) => p.contains('path') ||
        p.contains('url') || p.contains('header')), false);
    expect(PlaybackDiagnosticsProbe.frameRate(values), 'Unavailable');
  });

  test('unavailable stats are not fabricated', () {
    expect(PlaybackDiagnosticsProbe.resolution({}), 'Unavailable');
    expect(PlaybackDiagnosticsProbe.bitrate({}, 'video-bitrate'), 'Unavailable');
    expect(PlaybackDiagnosticsProbe.frameRate({}), 'Unavailable');
    expect(PlaybackDiagnosticsProbe.cacheAhead({}), 'Unavailable');
    expect(PlaybackDiagnosticsProbe.bitrate(
        {'video-bitrate': '4000000'}, 'video-bitrate'), '4.00 Mbps');
    expect(PlaybackDiagnosticsProbe.time(const Duration(seconds: 63)), '01:03');
    expect(PlaybackDiagnosticsProbe.time(const Duration(hours: 2, seconds: 3)), '2:00:03');
  });

  testWidgets('small transport-row button toggles stats on and off',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var visible = false;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(
      builder: (context, update) => Scaffold(body: Stack(children: [
        Positioned(bottom: 0, left: 0, right: 0, child: PlayerTransport(
          isPlaying: true,
          position: Duration.zero,
          duration: const Duration(minutes: 44),
          volume: 1.0, isMuted: false, playbackRate: 1.0,
          isSubtitlesActive: false, isSubSyncActive: false,
          isAudioActive: false, isFullscreen: false,
          isDiagnosticsActive: visible,
          onToggleDiagnostics: () => update(() => visible = !visible),
          onPlayPause: () {}, onSeek: (_) {},
          onSeekBack10: () {}, onSeekForward10: () {},
          onVolumeChanged: (_) {}, onToggleMute: () {},
          onToggleAspectMenu: () {}, onToggleSpeedMenu: () {},
          onToggleAudioMenu: () {}, onToggleSubtitleMenu: () {},
          onToggleSubSync: () {}, onToggleFullscreen: () {},
        )),
        if (visible) const Positioned(top: 20, right: 20,
          child: PlayerDiagnosticsOverlay(
            properties: {}, isPlaying: true, isBuffering: false,
            position: Duration.zero, duration: Duration(minutes: 44),
            buffered: null, playbackRate: 1.0, sourceKind: 'HTTP stream',
          )),
      ])),
    )));
    final toggle = find.byTooltip('Playback diagnostics');
    expect(toggle, findsOneWidget);
    expect(find.byType(PlayerDiagnosticsOverlay), findsNothing);
    await tester.tap(toggle);
    await tester.pump();
    expect(find.byType(PlayerDiagnosticsOverlay), findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(find.byType(PlayerDiagnosticsOverlay), findsNothing);
  });

  testWidgets('compact diagnostics overlay shows real values',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(
      child: PlayerDiagnosticsOverlay(
        properties: {'video-codec': 'hevc', 'audio-codec': 'aac',
          'video-params/w': '1920', 'video-params/h': '1080',
          'estimated-vf-fps': '23.98'},
        isPlaying: true, isBuffering: false,
        position: Duration(minutes: 5), duration: Duration(minutes: 45),
        buffered: Duration(minutes: 8), playbackRate: 1.0,
        sourceKind: 'HTTP stream',
      ),
    ))));
    expect(find.text('Playback diagnostics'), findsOneWidget);
    expect(find.text('1920 × 1080'), findsOneWidget);
    expect(find.text('23.98 fps'), findsOneWidget);
    expect(find.textContaining('http://'), findsNothing);
    // The panel is scrollable and does not claim unavailable codec data.
    expect(find.text('Unavailable'), findsWidgets);
  });
}
