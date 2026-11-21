import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/live_tv/live_verified_source_learning_gate.dart';

void main() {
  final first = StreamSource(
      url: 'https://cdn.example.net/channelA.m3u8', addonName: 'Live TV');
  final sameHostOther = StreamSource(
      url: 'https://cdn.example.net/channelB.m3u8', addonName: 'Live TV');
  final sameUrlDifferentAddon = StreamSource(
      url: 'https://cdn.example.net/channelA.m3u8', addonName: 'Other TV');

  bool sample(
    LiveVerifiedSourceLearningGate gate,
    StreamSource source,
    int positionMs, {
    bool accepted = true,
    bool video = true,
    bool playing = true,
    bool buffering = false,
    int tracks = 11,
  }) => gate.observe(
    source: source,
    policyAccepted: accepted,
    videoReady: video,
    videoWidth: video ? 1280 : 0,
    videoHeight: video ? 720 : 0,
    trackCount: tracks,
    playing: playing,
    buffering: buffering,
    position: Duration(milliseconds: positionMs),
  );

  test('Promotes only after three moving native samples and five seconds', () {
    final gate = LiveVerifiedSourceLearningGate();
    expect(sample(gate, first, 3000), false);
    expect(sample(gate, first, 5000), false);
    expect(sample(gate, first, 7000), false);
    expect(sample(gate, first, 9500), true);
    expect(sample(gate, first, 11500), false);
  });

  test('HTTP, audio-only, stopped and buffering playback never teach source',
      () {
    final gate = LiveVerifiedSourceLearningGate();
    expect(sample(gate, first, 0, accepted: false), false);
    expect(sample(gate, first, 2000, video: false), false);
    expect(sample(gate, first, 4000, tracks: 0), false);
    expect(sample(gate, first, 6000, playing: false), false);
    expect(sample(gate, first, 8000, buffering: true), false);
    expect(sample(gate, first, 10000), false);
    expect(sample(gate, first, 12000), false);
    expect(sample(gate, first, 14000), false);
    expect(sample(gate, first, 16000), true);
  });

  test('A stall resets progress instead of granting an eventual false pass',
      () {
    final gate = LiveVerifiedSourceLearningGate();
    expect(sample(gate, first, 0), false);
    expect(sample(gate, first, 2000), false);
    expect(sample(gate, first, 2000), false);
    expect(sample(gate, first, 4000), false);
    expect(sample(gate, first, 6000), false);
    expect(sample(gate, first, 8000), true);
  });

  test('Shared CDN hostname and different addon reset exact-source evidence',
      () {
    final gate = LiveVerifiedSourceLearningGate();
    expect(sample(gate, first, 0), false);
    expect(sample(gate, first, 2000), false);
    expect(sample(gate, first, 4000), false);
    expect(sample(gate, sameHostOther, 6000), false);
    expect(sample(gate, sameHostOther, 8000), false);
    expect(sample(gate, sameHostOther, 10000), false);
    expect(sample(gate, sameUrlDifferentAddon, 12000), false);
    expect(sample(gate, sameUrlDifferentAddon, 14000), false);
    expect(sample(gate, sameUrlDifferentAddon, 16000), false);
    expect(sample(gate, sameUrlDifferentAddon, 18000), true);
  });

  test('Reopen and background reset require fresh verification', () {
    final gate = LiveVerifiedSourceLearningGate();
    expect(sample(gate, first, 0), false);
    expect(sample(gate, first, 2000), false);
    expect(sample(gate, first, 4000), false);
    gate.reset();
    expect(sample(gate, first, 6000), false);
    expect(sample(gate, first, 8000), false);
    expect(sample(gate, first, 10000), false);
    expect(sample(gate, first, 12000), true);
  });
}
