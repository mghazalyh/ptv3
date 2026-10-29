import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/player/player_picture_audio.dart';
import 'package:playtorrio/services/player/player_settings.dart';
import 'package:playtorrio/widgets/player/player_brightness_menu.dart';
import 'package:playtorrio/widgets/player/player_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Night Mode preserves speed filter and adds exactly one compressor', () {
    expect(PlayerPictureAudio.audioFilterChain(false), 'scaletempo2=max-speed=8');
    final chain = PlayerPictureAudio.audioFilterChain(true);
    expect(chain, startsWith('scaletempo2=max-speed=8,lavfi=[acompressor='));
    expect('acompressor'.allMatches(chain).length, 1);
    expect(chain, contains('ratio=3'));
    expect(chain, contains('release=300'));
  });

  test('Native MPV property updates address audio and video independently', () async {
    final calls = <String>[];
    Future<void> write(String property, String value) async =>
        calls.add('$property=$value');
    await PlayerPictureAudio.applyAudio(write, true);
    await PlayerPictureAudio.applyBrightness(write, 47.6);
    await PlayerPictureAudio.applyAudio(write, false);
    expect(calls, [
      'af=${PlayerPictureAudio.audioFilterChain(true)}',
      'brightness=48',
      'af=scaletempo2=max-speed=8',
    ]);
    expect(PlayerPictureAudio.brightnessValue(-100), 0);
    expect(PlayerPictureAudio.brightnessValue(1000), 80);
    expect(PlayerPictureAudio.brightnessValue(double.nan), 0);
  });

  test('Night Mode and brightness survive preference reloads', () async {
    SharedPreferences.setMockInitialValues({});
    await PlayerSettings.initialize();
    expect(PlayerSettings.nightModeEnabled.value, false);
    expect(PlayerSettings.extraBrightness.value, 0);
    await PlayerSettings.setNightMode(true);
    await PlayerSettings.setExtraBrightness(37.7);
    PlayerSettings.nightModeEnabled.value = false;
    PlayerSettings.extraBrightness.value = 0;
    await PlayerSettings.initialize();
    expect(PlayerSettings.nightModeEnabled.value, true);
    expect(PlayerSettings.extraBrightness.value, 38);
    await PlayerSettings.setNightMode(false);
    await PlayerSettings.setExtraBrightness(0);
    await PlayerSettings.initialize();
    expect(PlayerSettings.nightModeEnabled.value, false);
    expect(PlayerSettings.extraBrightness.value, 0);
  });

  testWidgets('player row exposes Night Mode and Extra Brightness beside audio',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    bool night = false;
    bool brightness = false;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(
      builder: (context, update) => Scaffold(body: Stack(children: [
        Positioned(bottom: 0, left: 0, right: 0, child: PlayerTransport(
          isPlaying: true, position: Duration.zero,
          duration: const Duration(minutes: 44),
          volume: 1, isMuted: false, playbackRate: 1,
          isSubtitlesActive: false, isSubSyncActive: false,
          isAudioActive: true, isFullscreen: false,
          isNightModeEnabled: night,
          isBrightnessMenuActive: brightness,
          onToggleNightMode: () => update(() => night = !night),
          onToggleBrightnessMenu: () =>
              update(() => brightness = !brightness),
          onPlayPause: () {}, onSeek: (_) {},
          onSeekBack10: () {}, onSeekForward10: () {},
          onVolumeChanged: (_) {}, onToggleMute: () {},
          onToggleAspectMenu: () {}, onToggleSpeedMenu: () {},
          onToggleAudioMenu: () {}, onToggleSubtitleMenu: () {},
          onToggleSubSync: () {}, onToggleFullscreen: () {},
        )),
      ])),
    )));
    expect(find.byKey(const ValueKey('player-night-mode')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-extra-brightness')), findsOneWidget);
    expect(find.byTooltip('Audio Tracks'), findsOneWidget);
    expect(find.byTooltip('Subtitles'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player-night-mode')));
    await tester.pump();
    expect(night, true);
    await tester.tap(find.byKey(const ValueKey('player-extra-brightness')));
    await tester.pump();
    expect(brightness, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('brightness popup displays level and resets video signal',
      (tester) async {
    double value = 40;
    final events = <double>[];
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(
      builder: (context, update) => Scaffold(body: Center(
        child: PlayerBrightnessMenu(
          brightness: value,
          onChanged: (next) => update(() => value = next),
          onChangeEnd: events.add,
          onClose: () {},
        ),
      )),
    )));
    expect(find.text('Video +40'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-brightness-slider')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player-brightness-reset')));
    await tester.pump();
    expect(value, 0);
    expect(events, [0]);
    expect(find.text('Video +0'), findsOneWidget);
  });
}
