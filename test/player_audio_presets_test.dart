import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:playtorrio/widgets/player/player_audio_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/player_audio_presets.dart';
import 'package:playtorrio/services/player/player_picture_audio.dart';

void main() {
  test('audio presets remain bounded for native shelving filters', () {
    for (final preset in PlayerAudioPresets.values) {
      expect(PlayerPictureAudio.toneDb(preset.bassDb), preset.bassDb);
      expect(PlayerPictureAudio.toneDb(preset.trebleDb), preset.trebleDb);
    }
    expect(PlayerAudioPresets.flat.matches(0, 0), isTrue);
    expect(PlayerAudioPresets.dialogue.matches(-2, 3), isTrue);
    expect(PlayerAudioPresets.cinema.matches(-2, 3), isFalse);
  });

  test('preset output is deterministic and neutral path unchanged', () {
    expect(PlayerPictureAudio.audioFilterChain(false,
            bassDb: PlayerAudioPresets.flat.bassDb,
            trebleDb: PlayerAudioPresets.flat.trebleDb),
        PlayerPictureAudio.normalAudioFilter);
    expect(PlayerPictureAudio.audioFilterChain(false,
            bassDb: PlayerAudioPresets.dialogue.bassDb,
            trebleDb: PlayerAudioPresets.dialogue.trebleDb),
        contains('lavfi='));
  });

  testWidgets('Windows shared audio menu exposes Flat, Dialogue, Cinema and Warm', (tester) async {
    int? chosenBass;
    int? chosenTreble;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlayerAudioMenu(
              audioTracks: const [],
              selectedIndex: 0,
              delaySec: 0,
              bassDb: 0,
              trebleDb: 0,
              onEqualizerChanged: (bass, treble) {
                chosenBass = bass;
                chosenTreble = treble;
              },
              onTrackSelected: (_) {},
              onDelayChanged: (_) {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );

    for (final preset in PlayerAudioPresets.values) {
      expect(find.widgetWithText(ChoiceChip, preset.label), findsOneWidget);
    }

    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Flat')).selected,
      isTrue,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dialogue'));
    await tester.pump();

    expect(chosenBass, PlayerAudioPresets.dialogue.bassDb);
    expect(chosenTreble, PlayerAudioPresets.dialogue.trebleDb);
    final layoutError = tester.takeException();
    if (layoutError != null) {
      debugPrint('[AudioPresetLayout] Render tree for failing layout:');
      debugDumpRenderTree();
    }
    expect(layoutError, isNull);
  });

  testWidgets('Windows shared audio menu highlights the persisted preset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlayerAudioMenu(
              audioTracks: const [],
              selectedIndex: 0,
              delaySec: 0,
              bassDb: PlayerAudioPresets.warm.bassDb,
              trebleDb: PlayerAudioPresets.warm.trebleDb,
              onEqualizerChanged: (_, __) {},
              onTrackSelected: (_) {},
              onDelayChanged: (_) {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Warm')).selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
