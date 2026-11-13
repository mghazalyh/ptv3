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
}
