import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/playback_source_recovery.dart';

void main() {
  StreamSource source(String url, String name, String title,
      {String addon = 'Torrentio TB', bool live = false}) => StreamSource(
        url: url, name: name, title: title, addonName: addon,
        behaviorHints: live ? {'isLive': true} : null,
      );
  final a = source('https://torrentio.example/resolve/torbox/1',
      '[TB+] Torrentio', 'Locke & Key 2160p x265');
  final b = source('https://torrentio.example/resolve/torbox/2',
      '[TB+] Torrentio', 'Locke & Key 2160p x265');
  final c = source('https://torrentio.example/resolve/torbox/3',
      '[TB+] Torrentio', 'Locke & Key 1080p x265');
  final d = source('https://other.example/video/4',
      'Other', 'Locke & Key 2160p x265', addon: 'Other');

  test('retries the identical tokenized Torbox URL exactly once', () {
    final policy = PlaybackSourceRecovery();
    final first = policy.next(a, [a, b, c]);
    expect(first?.retrySameSource, true);
    expect(identical(first?.source, a), true);
    final second = policy.next(a, [a, b, c]);
    expect(second?.retrySameSource, false);
    expect(identical(second?.source, b), true);
    expect(policy.failedKeys, contains(PlaybackSourceRecovery.key(a)));
  });

  test('favors same addon and same quality before other providers', () {
    final policy = PlaybackSourceRecovery();
    policy.next(a, [d, c, b]);
    expect(policy.next(a, [d, c, b])?.source, same(b));
    policy.next(b, [d, c, b]);
    expect(policy.next(b, [d, c, b])?.source, same(c));
  });

  test('caps failed source switching without looping or reusing failed URLs', () {
    final policy = PlaybackSourceRecovery();
    final all = [a, b, c, d,
      source('https://torrentio.example/resolve/torbox/5','X','1080p'),
      source('https://torrentio.example/resolve/torbox/6','Y','1080p')];
    var active = a;
    var switches = 0;
    for (var i = 0; i < 20; i++) {
      final step = policy.next(active, all);
      if (step == null) break;
      if (!step.retrySameSource) {
        active = step.source;
        switches++;
      }
    }
    expect(switches, PlaybackSourceRecovery.maxAutomaticFallbacks);
    expect(policy.next(active, all), isNull);
    policy.reset();
    expect(policy.next(a, all)?.retrySameSource, true);
  });

  test('skips P2P, file, external and live sources automatically', () {
    final magnet = source('magnet:?xt=urn:btih:abc','torrent','2160p');
    final live = source('https://live.example/stream','Live','2160p', live: true);
    final file = source('file:///Users/movie.mp4','File','2160p');
    expect(PlaybackSourceRecovery.isHttpCandidate(a), true);
    expect(PlaybackSourceRecovery.isHttpCandidate(magnet), false);
    expect(PlaybackSourceRecovery.isHttpCandidate(live), false);
    expect(PlaybackSourceRecovery.isHttpCandidate(file), false);
    final policy = PlaybackSourceRecovery();
    policy.next(a, [a, magnet, live, file]);
    expect(policy.next(a, [a, magnet, live, file]), isNull);
  });

  test('de-duplicates URLs and excludes exhausted items', () {
    final policy = PlaybackSourceRecovery();
    final duplicate = source(a.url!, a.name!, a.title!);
    policy.next(a, [a, duplicate]);
    expect(policy.next(a, [a, duplicate]), isNull);
    expect(PlaybackSourceRecovery.hasAlternative(a, [a, duplicate, b],
      attemptedKeys: policy.failedKeys), true);
    expect(PlaybackSourceRecovery.hasAlternative(a, [a, duplicate],
      attemptedKeys: policy.failedKeys), false);
  });
}
