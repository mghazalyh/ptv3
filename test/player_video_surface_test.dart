import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'package:playtorrio/services/theme/glass_settings.dart';
import 'package:playtorrio/widgets/player/player_glass.dart';
import 'package:playtorrio/widgets/player/player_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GlassSettings.enabled.value = true;
  });

  tearDown(() {
    GlassSettings.enabled.value = false;
  });

  testWidgets('hovering mini-player controls cannot activate glass video capture',
      (tester) async {
    var clicked = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayerVideoSurface(
          video: const ColoredBox(
            color: Colors.black,
            child: Center(child: Text('native video content')),
          ),
          controls: Align(
            alignment: Alignment.bottomRight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PlayerGlassCard(
                  padding: EdgeInsets.all(12),
                  child: Text('Player menu'),
                ),
                PlayerIconButton(
                  tooltip: 'Keep playing while browsing (mini-player)',
                  icon: const Icon(Icons.picture_in_picture_alt_rounded),
                  onPressed: () => clicked = true,
                ),
              ],
            ),
          ),
        ),
      ),
    ));

    expect(find.text('native video content'), findsOneWidget);
    expect(find.byType(PlayerVideoSurfaceScope), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsAtLeastNWidgets(2));
    expect(find.byType(LiquidGlassView), findsNothing);
    expect(find.byType(LiquidGlassLens), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byType(PlayerIconButton)));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('native video content'), findsOneWidget);
    expect(find.byType(LiquidGlassView), findsNothing);
    expect(find.byType(LiquidGlassLens), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.tap(find.byType(PlayerIconButton));
    expect(clicked, isTrue);
    await mouse.removePointer();
  });

  testWidgets('playback transport hover stays in the texture-safe layer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var paused = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayerVideoSurface(
          video: const ColoredBox(color: Colors.black),
          controls: Align(
            alignment: Alignment.bottomCenter,
            child: PlayerTransport(
              isPlaying: true,
              position: const Duration(minutes: 20),
              duration: const Duration(minutes: 60),
              volume: 1,
              isMuted: false,
              playbackRate: 1,
              isSubtitlesActive: false,
              isSubSyncActive: false,
              isAudioActive: false,
              isFullscreen: false,
              onPlayPause: () => paused = true,
              onSeek: (_) {},
              onSeekBack10: () {},
              onSeekForward10: () {},
              onVolumeChanged: (_) {},
              onToggleMute: () {},
              onToggleAspectMenu: () {},
              onToggleSpeedMenu: () {},
              onToggleAudioMenu: () {},
              onToggleSubtitleMenu: () {},
              onToggleSubSync: () {},
              onToggleFullscreen: () {},
            ),
          ),
        ),
      ),
    ));

    final play = find.byIcon(Icons.pause_rounded);
    expect(play, findsWidgets);
    expect(find.byType(LiquidGlassLens), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(play.first));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(LiquidGlassView), findsNothing);
    expect(find.byType(LiquidGlassLens), findsNothing);
    await tester.tap(play.first);
    expect(paused, isTrue);
    await mouse.removePointer();
  });
}
