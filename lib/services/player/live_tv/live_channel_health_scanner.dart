import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/movie/movie.dart';
import '../../../models/stream/stream_model.dart';
import '../../stream/stream_service.dart';
import 'live_native_channel_verifier.dart';
import 'live_source_manager.dart';
import 'live_stream_detector.dart';
import 'live_verified_source_preference.dart';

/// These states must distinguish network connectivity from native decoding.
enum LiveChannelHealth {
  checking,
  verified,
  unstable,
  likelyReachable,
  poor,
  unknown,
}

class LiveChannelHealthResult {
  const LiveChannelHealthResult(
    this.health,
    this.sourcesChecked,
    this.reason, {
    this.checkedAt,
    this.sources = const <StreamSource>[],
    this.nativeChecked = false,
    this.nativeAttempts = 0,
    this.playableSourceIndex,
    this.videoWidth,
    this.videoHeight,
    this.startupMs,
  });

  final LiveChannelHealth health;
  final int sourcesChecked;
  final String reason;
  final DateTime? checkedAt;

  /// In-memory only. Stream URLs, headers and tokens are never uploaded.
  final List<StreamSource> sources;
  final bool nativeChecked;
  final int nativeAttempts;
  final int? playableSourceIndex;
  final int? videoWidth;
  final int? videoHeight;
  final int? startupMs;

  String get label => switch (health) {
    LiveChannelHealth.checking => 'Checking',
    LiveChannelHealth.verified => 'Working',
    LiveChannelHealth.unstable =>
      playableSourceIndex != null && playableSourceIndex! > 0
          ? 'Works via backup'
          : 'Unstable',
    LiveChannelHealth.likelyReachable => 'Reachable',
    LiveChannelHealth.poor => 'Poor',
    LiveChannelHealth.unknown => 'Unverified',
  };

  bool get nativeVerified =>
      (health == LiveChannelHealth.verified ||
       (health == LiveChannelHealth.unstable &&
        playableSourceIndex != null)) &&
      nativeChecked;
}

/// Source resolution / HLS reachability followed by actual iOS decoding.
/// Stage one is fast and concurrent. Stage two is sequential and muted.
abstract final class LiveChannelHealthScanner {
  @visibleForTesting
  static Future<List<StreamSource>> Function(Movie)? resolveOverride;
  @visibleForTesting
  static Future<LiveSourceProbe?> Function(
      String, StreamSource)? probeOverride;

  /// A stable sort: never scramble equally ranked channels, and never put
  /// an HTTP-only success ahead of confirmed decoded video.
  static List<Movie> sortedByHealth(
    Iterable<Movie> channels,
    Map<String, LiveChannelHealthResult> results,
  ) {
    final indexed = <({Movie movie, int index})>[];
    var index = 0;
    for (final movie in channels) {
      indexed.add((movie: movie, index: index++));
    }
    indexed.sort((a, b) {
      final ar = results[a.movie.id];
      final br = results[b.movie.id];
      final byHealth = healthPriority(ar?.health)
          .compareTo(healthPriority(br?.health));
      if (byHealth != 0) return byHealth;
      // Both a working backup and a rendered-but-stalled source use the
      // unstable grade. Only the former has verified moving native video.
      // Rank the proven backup ahead of the stalled channel, regardless of
      // its original catalog position.
      final aVerified = ar?.nativeVerified == true;
      final bVerified = br?.nativeVerified == true;
      if (aVerified != bVerified) return aVerified ? -1 : 1;
      if (aVerified && bVerified) {
        final byStartup = (ar?.startupMs ?? 999999)
            .compareTo(br?.startupMs ?? 999999);
        if (byStartup != 0) return byStartup;
      }
      return a.index.compareTo(b.index);
    });
    return indexed.map((entry) => entry.movie).toList();
  }

  static int healthPriority(LiveChannelHealth? health) => switch (health) {
    LiveChannelHealth.verified => 0,
    LiveChannelHealth.unstable => 1,
    LiveChannelHealth.likelyReachable => 2,
    LiveChannelHealth.unknown => 3,
    LiveChannelHealth.poor => 4,
    LiveChannelHealth.checking || null => 5,
  };

  static Future<LiveChannelHealthResult> inspect(Movie channel) async {
    if (!LiveStreamDetector.isLiveChannel(
        mediaType: channel.type, mediaId: channel.id)) {
      return const LiveChannelHealthResult(
          LiveChannelHealth.unknown, 0, 'not_live_tv');
    }
    var checked = 0;
    try {
      final all = await (resolveOverride?.call(channel) ??
          StreamService.fetchStreams(
            type: 'tv', id: channel.id, title: channel.name,
          ).take(12).toList()).timeout(const Duration(seconds: 22));
      final sources = all.where((source) =>
        LiveStreamDetector.isHttpMedia(source.url) &&
        !(source.infoHash?.trim().isNotEmpty ?? false),
      ).take(4).toList(growable: false);

      if (sources.isEmpty) {
        return LiveChannelHealthResult(
          LiveChannelHealth.poor, 0, 'no_http_stream_sources',
          checkedAt: DateTime.now(),
        );
      }

      var inconclusive = false;
      for (final source in sources) {
        checked++;
        if (!LiveStreamDetector.isHlsUrl(source.url)) {
          inconclusive = true;
          continue;
        }
        try {
          final probe = await (probeOverride?.call(channel.id, source) ??
              LiveSourceManager(
                channelId: channel.id,
                addonName: source.addonName,
                initial: source,
              ).inspectFirstSegment(source))
              .timeout(const Duration(seconds: 18));
          if (probe?.outcome == 'ok' &&
              (probe?.httpStatus == 200 || probe?.httpStatus == 206)) {
            return LiveChannelHealthResult(
              LiveChannelHealth.likelyReachable,
              checked, 'segment_reachable_not_decoded',
              checkedAt: DateTime.now(),
              sources: sources,
            );
          }
          if (probe == null || probe.outcome == 'network_error' ||
              probe.outcome == 'timeout' ||
              probe.outcome == 'invalid_manifest') {
            inconclusive = true;
          }
        } catch (error) {
          debugPrint('[LiveHealthScan] HTTP candidate: ' +
              error.runtimeType.toString());
          inconclusive = true;
        }
      }
      return LiveChannelHealthResult(
        inconclusive ? LiveChannelHealth.unknown : LiveChannelHealth.poor,
        checked, inconclusive ? 'inconclusive_http' : 'sources_failed_http',
        checkedAt: DateTime.now(),
        sources: sources,
      );
    } catch (error) {
      debugPrint('[LiveHealthScan] Discovery: ' +
          error.runtimeType.toString());
      return LiveChannelHealthResult(
        LiveChannelHealth.unknown, checked, 'discovery_unavailable',
        checkedAt: DateTime.now(),
      );
    }
  }

  /// Only a real iOS MPV picture, native tracks and an advancing unbuffered
  /// timeline can receive a high confidence grade. A reachable HTTP segment
  /// can never be promoted by itself.
  static Future<LiveChannelHealthResult> verifyNative(
    Movie channel,
    LiveChannelHealthResult preflight, {
    required bool Function() isCancelled,
  }) async {
    if (!LiveNativeChannelVerifier.isSupported ||
        isCancelled() || preflight.sources.isEmpty) {
      return preflight;
    }

    var attempts = 0;
    var sawRenderedButUnstable = false;
    for (var index = 0; index < preflight.sources.length; index++) {
      if (isCancelled()) return preflight;
      final source = preflight.sources[index];
      attempts++;
      try {
        final native = await LiveNativeChannelVerifier.probe(
          channelId: channel.id,
          source: source,
          isCancelled: isCancelled,
        );
        if (native.cancelled || isCancelled()) return preflight;
        if (native.sustainedStart) {
          LiveVerifiedSourcePreference.remember(
            channelId: channel.id, verifiedSource: source,
          );
          return LiveChannelHealthResult(
            index == 0
                ? LiveChannelHealth.verified
                : LiveChannelHealth.unstable,
            preflight.sourcesChecked,
            index == 0
                ? 'native_video_verified'
                : 'native_backup_verified',
            checkedAt: DateTime.now(),
            sources: preflight.sources,
            nativeChecked: true,
            nativeAttempts: attempts,
            playableSourceIndex: index,
            videoWidth: native.videoWidth,
            videoHeight: native.videoHeight,
            startupMs: native.startupMs,
          );
        }
        // A source that just failed native decoding must not retain a
        // preference from an earlier successful scan.
        LiveVerifiedSourcePreference.invalidate(channel.id, source);
        if (native.renderedVideo) sawRenderedButUnstable = true;
      } catch (error) {
        // A native decoder exception is a failed attempt too. A formerly
        // verified URL must not remain preferred after this failure.
        LiveVerifiedSourcePreference.invalidate(channel.id, source);
        debugPrint('[LiveHealthScan] MPV candidate: ' +
            error.runtimeType.toString());
      }
    }

    return LiveChannelHealthResult(
      sawRenderedButUnstable
          ? LiveChannelHealth.unstable
          : LiveChannelHealth.poor,
      preflight.sourcesChecked,
      sawRenderedButUnstable
          ? 'native_rendered_but_stalled'
          : 'native_no_playable_sources',
      checkedAt: DateTime.now(),
      sources: preflight.sources,
      nativeChecked: true,
      nativeAttempts: attempts,
    );
  }

  /// Four HTTP workers cap network load and report every result independently.
  static Future<void> scan(
    List<Movie> channels, {
    required bool Function() isCancelled,
    required void Function(Movie, LiveChannelHealthResult) onResult,
    int concurrency = 4,
  }) async {
    var cursor = 0;
    Future<void> worker() async {
      while (!isCancelled()) {
        final position = cursor++;
        if (position >= channels.length) return;
        final channel = channels[position];
        final result = await inspect(channel);
        if (isCancelled()) return;
        onResult(channel, result);
      }
    }
    await Future.wait(List.generate(
        concurrency.clamp(1, 6).toInt(), (_) => worker()));
  }
}
