import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/detached_playback_service.dart';
import 'package:playtorrio/services/player/floating_playback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persistent player session survives minimization and restore', () {
    final session = FloatingPlaybackSession(
      source: StreamSource(
        url: 'https://example.org/stream.m3u8',
        addonName: 'Test',
      ),
      title: 'Test Show',
    );
    FloatingPlaybackService.play(session);
    expect(FloatingPlaybackService.current.value, same(session));
    expect(FloatingPlaybackService.isMini.value, false);

    FloatingPlaybackService.minimize();
    expect(FloatingPlaybackService.current.value, same(session));
    expect(FloatingPlaybackService.isMini.value, true);

    FloatingPlaybackService.expand();
    expect(FloatingPlaybackService.current.value, same(session));
    expect(FloatingPlaybackService.isMini.value, false);

    FloatingPlaybackService.stop();
    expect(FloatingPlaybackService.current.value, isNull);
  });

  test('second-monitor handoff keeps stream headers and playback position', () {
    final original = DetachedPlaybackRequest(
      title: 'Episode 3',
      url: 'https://cdn.example.org/show/episode.mp4?token=one',
      headers: {'Referer': 'https://example.org'},
      position: const Duration(minutes: 28, seconds: 17),
    );
    final decoded = DetachedPlaybackRequest.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
    expect(decoded.title, original.title);
    expect(decoded.position, original.position);
    expect(decoded.toSource().url, original.url);
    expect(decoded.toSource().headers!['Referer'], 'https://example.org');
  });
}
