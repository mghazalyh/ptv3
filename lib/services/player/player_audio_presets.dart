/// Safe stereo tone presets. Settings are stored locally per device via the
/// existing PlayerSettings equalizer keys. No new native audio filters.
enum PlayerAudioPresets {
  flat('Flat', 0, 0),
  dialogue('Dialogue', -2, 3),
  cinema('Cinema', 2, 1),
  warm('Warm', 2, -2);

  final String label;
  final int bassDb;
  final int trebleDb;
  const PlayerAudioPresets(this.label, this.bassDb, this.trebleDb);

  bool matches(int bass, int treble) =>
      bassDb == bass && trebleDb == treble;
}
