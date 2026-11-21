import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/movie/movie.dart';
import '../../../models/stream/stream_model.dart';
import '../../stream/stream_service.dart';
import 'live_source_manager.dart';
import 'live_stream_detector.dart';

/// An HTTP-based catalogue preflight, not a native decoded-video test.
/// Only the on-device MPV matrix may claim playback verification.
enum LiveChannelHealth { checking, likelyReachable, poor, unknown }

class LiveChannelHealthResult {
  const LiveChannelHealthResult(this.health, this.sourcesChecked,
      this.reason, {this.checkedAt});
  final LiveChannelHealth health;
  final int sourcesChecked;
  final String reason;
  final DateTime? checkedAt;

  String get label => switch (health) {
    LiveChannelHealth.checking => 'Checking',
    LiveChannelHealth.likelyReachable => 'Likely healthy',
    LiveChannelHealth.poor => 'Poor',
    LiveChannelHealth.unknown => 'Unverified',
  };
}

class LiveChannelHealthScanner {
  LiveChannelHealthScanner._();

  @visibleForTesting
  static Future<List<StreamSource>> Function(Movie)? resolveOverride;
  @visibleForTesting
  static Future<LiveSourceProbe?> Function(
      String, StreamSource)? probeOverride;

  static Future<LiveChannelHealthResult> inspect(Movie channel) async {
    if (!LiveStreamDetector.isLiveChannel(
        mediaType: channel.type, mediaId: channel.id)) {
      return const LiveChannelHealthResult(
          LiveChannelHealth.unknown, 0, 'not_live_tv');
    }
    var checked = 0;
    try {
      final sources = await (resolveOverride?.call(channel) ??
          StreamService.fetchStreams(
            type: 'tv', id: channel.id, title: channel.name,
          ).take(12).toList()).timeout(const Duration(seconds: 22));
      if (sources.isEmpty) {
        return LiveChannelHealthResult(
            LiveChannelHealth.poor, 0, 'no_stream_sources',
            checkedAt: DateTime.now());
      }
      var inconclusive = false;
      for (final source in sources.take(4)) {
        if (!LiveStreamDetector.isHttpMedia(source.url)) continue;
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
                checkedAt: DateTime.now());
          }
          if (probe == null || probe.outcome == 'network_error' ||
              probe.outcome == 'timeout' || probe.outcome == 'invalid_manifest') {
            inconclusive = true;
          }
        } catch (error) {
          debugPrint('[LiveHealthScan] Candidate probe: ${error.runtimeType}');
          inconclusive = true;
        }
      }
      return LiveChannelHealthResult(
          inconclusive || checked == 0
              ? LiveChannelHealth.unknown : LiveChannelHealth.poor,
          checked, inconclusive ? 'inconclusive_http' : 'sources_failed_http',
          checkedAt: DateTime.now());
    } catch (error) {
      debugPrint('[LiveHealthScan] Channel inspect: ${error.runtimeType}');
      return LiveChannelHealthResult(
          LiveChannelHealth.unknown, checked, 'discovery_unavailable',
          checkedAt: DateTime.now());
    }
  }

  /// Four workers cap network load and let the list update continuously.
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
        concurrency.clamp(1, 6), (_) => worker()));
  }
}
