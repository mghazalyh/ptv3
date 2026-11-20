import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/live_tv/live_recovery_policy.dart';
import 'package:playtorrio/services/player/live_tv/live_source_manager.dart';
import 'package:playtorrio/services/player/live_tv/live_stream_detector.dart';

StreamSource source(String url, {String addon = 'Live TV',
    String description = ''}) => StreamSource(
      url: url,
      addonName: addon,
      description: description,
      name: '● LIVE',
    );

void main() {
  group('Stremio live identification is isolated from VOD', () {
    test('tv and Horizon channel IDs classify as live', () {
      expect(LiveStreamDetector.isLiveChannel(
          mediaType: 'tv', mediaId: 'nltv:us:Channel.us'), isTrue);
      expect(LiveStreamDetector.isLiveChannel(
          mediaId: 'nltv:us:Channel.us'), isTrue);
    });
    test('movies and episodes never classify by URL or conflicting hints', () {
      expect(LiveStreamDetector.isLiveChannel(
          mediaType: 'movie', streamHints: {'isLive': true}), isFalse);
      expect(LiveStreamDetector.isLiveChannel(
          mediaType: 'series', mediaId: 'nltv:us:Channel.us'),
          isFalse);
      expect(LiveStreamDetector.isLiveChannel(
          mediaType: 'tv', hasEpisode: true), isFalse);
      expect(LiveStreamDetector.isLiveChannel(
          mediaType: 'movie'), isFalse);
    });
    test('other addons can identify live streams explicitly', () {
      expect(LiveStreamDetector.isLiveChannel(
          streamHints: {'isLive': true}), isTrue);
    });
    test('detects signed HLS URLs without trusting URL as media type', () {
      expect(LiveStreamDetector.isHlsUrl(
          'https://cdn.example/live/master.m3u8?token=abc'), isTrue);
      expect(LiveStreamDetector.isHlsUrl(
          'https://cdn.example/movie.mp4?live=true'), isFalse);
      expect(LiveStreamDetector.isHttpMedia('file:///secret/video.mp4'),
          isFalse);
    });
  });

  group('HLS playlist updates', () {
    const one = '#EXTM3U\n#EXT-X-TARGETDURATION:4\n'
        '#EXT-X-MEDIA-SEQUENCE:501\n#EXTINF:4,\n501.ts\n'
        '#EXTINF:4,\n502.ts\n';
    const two = '#EXTM3U\n#EXT-X-TARGETDURATION:4\n'
        '#EXT-X-MEDIA-SEQUENCE:502\n#EXTINF:4,\n502.ts\n'
        '#EXTINF:4,\n503.ts\n';
    test('recognizes stale playlist and sequence advancement', () {
      final previous = LivePlaylistSnapshot.parse(one);
      final unchanged = LivePlaylistSnapshot.parse(one);
      final newer = LivePlaylistSnapshot.parse(two);
      expect(previous, isNotNull);
      expect(previous!.sameMediaAs(unchanged!), isTrue);
      expect(previous.sameMediaAs(newer!), isFalse);
      expect(previous.targetDurationSeconds, 4);
    });
    test('handles ended, malformed and discontinuous playlists', () {
      expect(LivePlaylistSnapshot.parse('<html>expired</html>'), isNull);
      final parsed = LivePlaylistSnapshot.parse(
          one + '#EXT-X-DISCONTINUITY\n#EXT-X-ENDLIST');
      expect(parsed?.ended, isTrue);
      expect(parsed?.discontinuities, 1);
    });
  });

  group('Live recovery policy', () {
    final t0 = DateTime.utc(2026, 11, 21, 0, 0);
    LiveHealthEvent sample(
      LiveRecoveryPolicy policy,
      int at,
      int position,
      int buffered, {
      bool playing = true,
      bool buffering = false,
      int? duration,
      bool videoReady = true,
    }) => policy.observe(
      at: t0.add(Duration(seconds: at)),
      position: Duration(seconds: position),
      buffered: Duration(seconds: buffered),
      duration: Duration(seconds: duration ?? buffered),
      playing: playing,
      buffering: buffering,
      videoReady: videoReady,
    );

    test('detects starvation before the last video frame is exhausted', () {
      final p = LiveRecoveryPolicy();
      expect(sample(p, 0, 0, 15), LiveHealthEvent.none);
      expect(sample(p, 6, 6, 21), LiveHealthEvent.started);
      expect(sample(p, 17, 17, 21),
          LiveHealthEvent.feedStarvation);
    });

    test('initial native open with zero playback and no buffering still stalls', () {
      final p = LiveRecoveryPolicy();
      expect(sample(p, 0, 0, 0, playing: false),
          LiveHealthEvent.none);
      expect(sample(p, 16, 0, 0, playing: false),
          LiveHealthEvent.bufferingStall);
    });

    test('only unbuffered video motion confirms first playback', () {
      final p = LiveRecoveryPolicy();
      sample(p, 0, 0, 0, buffering: true);
      expect(sample(p, 4, 3, 8, buffering: true),
          LiveHealthEvent.none);
      expect(p.everPlayed, isFalse);
      expect(sample(p, 6, 6, 12),
          LiveHealthEvent.started);
      expect(p.everPlayed, isTrue);
    });

    test('rejects audio-only source even if its timeline is advancing', () {
      final p = LiveRecoveryPolicy();
      expect(sample(p, 0, 0, 0, videoReady: false),
          LiveHealthEvent.none);
      expect(sample(p, 6, 6, 12, videoReady: false),
          LiveHealthEvent.none);
      expect(p.everPlayed, isFalse);
      expect(sample(p, 21, 18, 24, videoReady: false),
          LiveHealthEvent.videoUnavailable);
      expect(p.everPlayed, isFalse);
    });

    test('rejects unverified replacement after a previously healthy source', () {
      final p = LiveRecoveryPolicy();
      sample(p, 0, 0, 5);
      expect(sample(p, 5, 5, 15), LiveHealthEvent.started);
      p.beginReopen(t0.add(const Duration(seconds: 6)));
      p.reopened(t0.add(const Duration(seconds: 7)));
      sample(p, 9, 3, 8, videoReady: false);
      expect(sample(p, 28, 20, 30, videoReady: false),
          LiveHealthEvent.videoUnavailable);
    });

    test('detects indefinitely stalled buffering', () {
      final p = LiveRecoveryPolicy();
      expect(sample(p, 0, 0, 0, buffering: true),
          LiveHealthEvent.none);
      expect(sample(p, 16, 0, 0, buffering: true),
          LiveHealthEvent.bufferingStall);
    });

    test('intentional pause never triggers source reopening', () {
      final p = LiveRecoveryPolicy();
      sample(p, 0, 60, 70);
      expect(sample(p, 40, 60, 70, playing: false),
          LiveHealthEvent.none);
      expect(sample(p, 100, 60, 70, playing: false),
          LiveHealthEvent.none);
      expect(sample(p, 101, 60, 70), LiveHealthEvent.none);
    });

    test('reopening reports recovery only after real progress', () {
      final p = LiveRecoveryPolicy();
      sample(p, 0, 0, 0, buffering: true);
      expect(sample(p, 16, 0, 0, buffering: true),
          LiveHealthEvent.bufferingStall);
      p.beginReopen(t0.add(const Duration(seconds: 16)));
      expect(p.canAttempt(t0.add(const Duration(seconds: 18))), isFalse);
      p.reopened(t0.add(const Duration(seconds: 17)));
      expect(sample(p, 19, 0, 4, buffering: true),
          LiveHealthEvent.none);
      expect(sample(p, 20, 3, 15),
          LiveHealthEvent.recovered);
    });

    test('retry backoff grows and buffer policy remains bounded', () {
      final p = LiveRecoveryPolicy();
      p.reset(t0);
      for (var i = 0; i < 8; i++) {
        final time = t0.add(Duration(minutes: i * 2));
        p.beginReopen(time);
        p.reopenFailed(time);
      }
      expect(p.retryCooldown, const Duration(seconds: 60));
      expect(p.recommendedCacheSeconds, 30);
    });

    test('timeline discontinuity does not count as a normal stall', () {
      final p = LiveRecoveryPolicy();
      sample(p, 0, 100, 120, duration: 140);
      expect(sample(p, 15, 50, 70, duration: 70),
          LiveHealthEvent.timelineDiscontinuity);
    });
  });

  group('Source ranking, refresh and circuit breaker', () {
    const primaryUrl = 'https://live.example/primary.m3u8';
    const backupUrl = 'https://backup.example/channel.m3u8';
    final t0 = DateTime.utc(2026, 11, 21);
    test('backup sources are scoped to the current Stremio addon', () {
      final primary = source(primaryUrl);
      final backup = source(backupUrl,
          description: 'Pluto · ✓ tested working');
      final manager = LiveSourceManager(
        channelId: 'nltv:us:channel',
        addonName: 'Live TV',
        initial: primary,
        initialSources: [
          backup,
          source('https://other.example/unrelated.m3u8',
              addon: 'Torrentio'),
          source('javascript:alert(1)'),
        ],
      );
      expect(manager.sourceCount, 2);
      expect(manager.backups(primary, t0).first.url, backupUrl);
      manager.failed(backup, t0);
      manager.failed(backup, t0);
      expect(manager.backups(primary, t0), isEmpty);
      manager.recovered(backup);
      expect(manager.backups(primary, t0), isNotEmpty);
    });

    test('refresh uses newest signed same-channel streams', () async {
      final manager = LiveSourceManager(
        channelId: 'nltv:us:channel',
        addonName: 'Live TV',
        initial: source(primaryUrl),
        refreshOverride: () async => [
          source('https://cdn.example/channel.m3u8?new_token=2'),
        ],
      );
      expect(await manager.refresh(), 1);
      expect(manager.backups(source(primaryUrl), t0).single.url,
          contains('new_token=2'));
    });
  });
}
