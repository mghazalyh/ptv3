import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/debrid_source_readiness.dart';
import 'package:playtorrio/services/player/playback_source_recovery.dart';

void main() {
  StreamSource source(
    String name, String url, {
    String description = '4.3 GB',
    String addon = 'Torrentio',
    bool live = false,
    String? externalUrl,
  }) => StreamSource(
    name: name,
    title: 'Goosebumps S01E01 2160p 4K',
    description: description,
    url: url,
    addonName: addon,
    externalUrl: externalUrl,
    behaviorHints: live ? <String, dynamic>{'isLive': true} : null,
  );

  final pending = source(
    '[TB download] Torrentio',
    'https://resolver.example/download/id1',
  );
  final cached = source(
    '[TB+] Torrentio',
    'https://resolver.example/cached/id2',
  );
  final next = source(
    '[TB+] Torrentio',
    'https://resolver.example/cached/id3',
  );

  test('provider-declared download is deferred, not mistaken for ready', () {
    expect(DebridSourceReadiness.isExplicitlyPending(pending), true);
    expect(DebridSourceReadiness.isExplicitlyPending(cached), false);
    expect(DebridSourceReadiness.sortTier(cached), 0);
    expect(DebridSourceReadiness.sortTier(pending), 1);
    expect(
      DebridSourceReadiness.isExplicitlyPending(source(
        '[TB+] Torrentio', 'https://video.example/path/download.mkv',
      )),
      false,
    );
    expect(DebridSourceReadiness.isExplicitlyPending(source(
      '[RD downloading] Torrentio', 'https://resolver.example/uncached',
    )), true);
  });

  test('29 second status video cannot pass as a multi-GB TV episode', () {
    expect(DebridSourceReadiness.isShortStatusClip(
      source: pending,
      duration: const Duration(seconds: 29),
      isEpisode: true,
    ), true);
    expect(DebridSourceReadiness.isShortStatusClip(
      source: cached,
      duration: const Duration(seconds: 29),
      isEpisode: true,
    ), true);
    expect(DebridSourceReadiness.isShortStatusClip(
      source: cached,
      duration: const Duration(minutes: 45),
      isEpisode: true,
    ), false);
    expect(DebridSourceReadiness.isShortStatusClip(
      source: cached,
      duration: const Duration(seconds: 29),
      isEpisode: false,
    ), false);
    expect(DebridSourceReadiness.isShortStatusClip(
      source: source('[TB+] Torrentio', 'https://video.example/clip',
        description: '35 MB'),
      duration: const Duration(seconds: 29),
      isEpisode: true,
    ), false);
  });

  test('never flags local, P2P, live or external links as placeholders', () {
    for (final candidate in [
      source('[TB+] Torrentio', 'file:///movie.mkv'),
      source('[TB+] Torrentio', 'magnet:?xt=urn:btih:abc'),
      source('[TB+] Torrentio', 'https://example.com/live', live: true),
      source('[TB+] Torrentio', 'https://example.com/file',
        externalUrl: 'https://external.example'),
    ]) {
      expect(DebridSourceReadiness.isShortStatusClip(
        source: candidate,
        duration: const Duration(seconds: 29),
        isEpisode: true,
      ), false);
    }
  });

  test('explicit download immediately advances to next visible stream', () {
    final policy = PlaybackSourceRecovery();
    final first = policy.next(
      pending,
      [cached, pending, next],
      skipCurrentRetry: true,
      followPickerOrder: true,
    );
    expect(first?.retrySameSource, false);
    expect(first?.source, same(next));
    expect(policy.failedKeys, contains(PlaybackSourceRecovery.key(pending)));
  });

  test('skips all pending entries even if they appear immediately next', () {
    final anotherPending = source(
      '[TB download] Torrentio', 'https://resolver.example/download/id4');
    final policy = PlaybackSourceRecovery();
    final first = policy.next(
      pending, [pending, anotherPending, cached, next],
      skipCurrentRetry: true, followPickerOrder: true,
    );
    expect(first?.source, same(cached));
    final second = policy.next(
      cached, [pending, anotherPending, cached, next],
      skipCurrentRetry: true, followPickerOrder: true,
    );
    expect(second?.source, same(next));
    expect(policy.next(next, [pending, anotherPending, cached, next],
      skipCurrentRetry: true, followPickerOrder: true), isNull);
  });

  test('pending sources never count as playable alternatives', () {
    final anotherPending = source(
      '[TB download] Torrentio', 'https://resolver.example/download/id6');
    expect(PlaybackSourceRecovery.hasAlternative(
      pending, [pending, anotherPending],
      attemptedKeys: <String>{},
    ), isFalse);
    expect(PlaybackSourceRecovery.hasAlternative(
      pending, [pending, cached],
      attemptedKeys: <String>{},
    ), isTrue);
  });

  test('no looping when only uncached debrid jobs exist', () {
    final secondPending = source(
      '[TB download] Torrentio', 'https://resolver.example/download/id5');
    final policy = PlaybackSourceRecovery();
    expect(policy.next(pending, [pending, secondPending],
      skipCurrentRetry: true, followPickerOrder: true), isNull);
    expect(policy.next(pending, [pending, secondPending],
      skipCurrentRetry: true, followPickerOrder: true), isNull);
  });

  test('ordinary unknown-ready errors keep the single retry policy', () {
    final policy = PlaybackSourceRecovery();
    expect(policy.next(cached, [cached, next])?.retrySameSource, true);
    expect(policy.next(cached, [cached, next])?.source, same(next));
  });
}
