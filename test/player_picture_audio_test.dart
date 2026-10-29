import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/player/player_picture_audio.dart';
import 'package:playtorrio/services/player/player_settings.dart';
import 'package:playtorrio/services/player/night_mode_diagnostics.dart';
import 'package:playtorrio/widgets/player/player_brightness_menu.dart';
import 'package:playtorrio/widgets/player/player_night_mode_recovery.dart';
import 'package:playtorrio/widgets/player/player_transport.dart';

void _noOperation() {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => NightModeDiagnostics.debugModeEnabled.value = false);
  tearDown(() => NightModeDiagnostics.debugModeEnabled.value = false);

  test('MPV runtime filter initialization errors are recognized', () {
    expect(PlayerPictureAudio.isNightModeFilterError(
        'Playback error: Audio filter initialized failed!'), isTrue);
    expect(PlayerPictureAudio.isNightModeFilterError(
        'Error initializing audio filters'), isTrue);
    expect(PlayerPictureAudio.isNightModeFilterError(
        'Failed to initialize audio filter'), isTrue);
    expect(PlayerPictureAudio.isNightModeFilterError(
        'Playback error: unsupported media format'), isFalse);
    expect(PlayerPictureAudio.isNightModeFilterError(
        'Failed to load subtitle'), isFalse);
  });

  test('Safe audio fallback retains speed filter and handles setter failure',
      () async {
    final written = <String>[];
    await PlayerPictureAudio.restoreNormalAudio((key, value) async {
      written.add('$key=$value');
    });
    expect(written, ['audio-normalize-downmix=no', 'af=scaletempo2=max-speed=8']);

    written.clear();
    await PlayerPictureAudio.restoreNormalAudio((key, value) async {
      written.add('$key=$value');
      if (value == PlayerPictureAudio.normalAudioFilter) {
        throw StateError('filter unsupported');
      }
    });
    expect(written, ['audio-normalize-downmix=no', 'af=scaletempo2=max-speed=8', 'af=']);
  });

  test('Late native error disables persisted Night Mode even on setter error',
      () async {
    SharedPreferences.setMockInitialValues({
      'player_global_night_mode': true,
      'player_global_extra_brightness': 35.0,
    });
    await PlayerSettings.initialize();
    expect(PlayerSettings.nightModeEnabled.value, isTrue);
    final written = <String>[];
    await PlayerSettings.recoverFailedNightMode(
      setProperty: (key, value) async {
        written.add('$key=$value');
        if (value == PlayerPictureAudio.normalAudioFilter) {
          throw StateError('native speed filter also unavailable');
        }
      },
    );
    expect(written, ['audio-normalize-downmix=no', 'af=scaletempo2=max-speed=8', 'af=']);
    expect(PlayerSettings.nightModeEnabled.value, isFalse);
    expect(PlayerSettings.extraBrightness.value, 35.0);
    await PlayerSettings.initialize();
    expect(PlayerSettings.nightModeEnabled.value, isFalse);
  });

  testWidgets('Emergency Night Mode button works without transport',
      (tester) async {
    var retried = false;
    var logCopied = false;
    NightModeDiagnostics.debugModeEnabled.value = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: PlayerNightModeRecovery(
              isRecovering: false,
              onRetry: () => retried = true,
              onCopyLogPath: () => logCopied = true,
            ),
          ),
        ]),
      ),
    ));
    final button = find.byKey(
        const ValueKey('player-night-mode-emergency-retry'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    expect(retried, isTrue);
    expect(find.byKey(const ValueKey('player-night-mode-copy-log')), findsNothing);
    NightModeDiagnostics.debugModeEnabled.value = true;
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('player-night-mode-copy-log')));
    expect(logCopied, isTrue);
    NightModeDiagnostics.debugModeEnabled.value = false;
    await tester.pump();
    expect(find.byKey(const ValueKey('player-night-mode-copy-log')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Recovery action is disabled while restoring audio',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PlayerNightModeRecovery(
        isRecovering: true,
        onRetry: _noOperation,
      )),
    ));
    final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('player-night-mode-emergency-retry')));
    expect(button.onPressed, isNull);
    expect(find.text('Restoring normal audio...'), findsOneWidget);
  });

  test('Night Mode preserves speed filter and adds exactly one compressor', () {
    expect(PlayerPictureAudio.audioFilterChain(false), 'scaletempo2=max-speed=8');
    final chain = PlayerPictureAudio.audioFilterChain(true);
    expect(chain, startsWith('scaletempo2=max-speed=8,lavfi=[acompressor='));
    expect('acompressor'.allMatches(chain).length, 1);
    expect(chain, contains('ratio=3'));
    expect(chain, contains('release=300'));
    expect(chain, contains('makeup=1.0'));
    expect(chain, isNot(contains('makeup=1.4')));
    expect(PlayerPictureAudio.downmixNormalization(true), 'yes');
    expect(PlayerPictureAudio.downmixNormalization(false), 'no');
  });

  test('Native MPV property updates address audio and video independently', () async {
    final calls = <String>[];
    Future<void> write(String property, String value) async =>
        calls.add('$property=$value');
    await PlayerPictureAudio.applyAudio(write, true);
    await PlayerPictureAudio.applyBrightness(write, 47.6);
    await PlayerPictureAudio.applyAudio(write, false);
    expect(calls, [
      'audio-normalize-downmix=yes',
      'af=${PlayerPictureAudio.audioFilterChain(true)}',
      'brightness=48',
      'audio-normalize-downmix=no',
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
    bool logPathCopied = false;
    NightModeDiagnostics.debugModeEnabled.value = false;
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
          onCopyNightModeLogPath: () => logPathCopied = true,
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
    expect(find.byKey(const ValueKey('player-night-mode-log-path')), findsNothing);
    expect(find.byTooltip('Audio Tracks'), findsOneWidget);
    expect(find.byTooltip('Subtitles'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player-night-mode')));
    await tester.pump();
    expect(night, true);
    await tester.tap(find.byKey(const ValueKey('player-extra-brightness')));
    await tester.pump();
    expect(brightness, true);
    NightModeDiagnostics.debugModeEnabled.value = true;
    await tester.pump();
    expect(find.byKey(const ValueKey('player-night-mode-log-path')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player-night-mode-log-path')));
    expect(logPathCopied, isTrue);
    NightModeDiagnostics.debugModeEnabled.value = false;
    await tester.pump();
    expect(find.byKey(const ValueKey('player-night-mode-log-path')), findsNothing);
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
