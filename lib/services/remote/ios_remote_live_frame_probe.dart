import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../models/stream/stream_model.dart';
import '../player_settings.dart';
import 'live_source_manager.dart';
import 'live_stream_detector.dart';
import 'live_native_channel_verifier.dart';

/// Called only by the opt-in content inspection command. Never uploads bytes
/// itself, mutates the visible player or changes the existing matrix verifier.
typedef LiveVisualFrameObserver = Future<bool> Function(
    Uint8List png, int playbackPositionMs);

/// A separate, silent MPV Player used only for explicit visual observation.
/// Does not modify the existing unattended LiveNativeChannelVerifier.
/// Native checks are sequential. No visual player route, audio, seek, or
/// modification to the user's primary media_kit Player is involved.
abstract final class IosRemoteLiveFrameProbe {
  @visibleForTesting
  static Future<LiveNativeSourceResult> Function(
    String channelId,
    StreamSource source,
    bool Function() isCancelled,
  )? probeOverride;

  static bool get isSupported => Platform.isIOS || probeOverride != null;

  static Future<LiveNativeSourceResult> probe({
    required String channelId,
    required StreamSource source,
    required bool Function() isCancelled,
    LiveVisualFrameObserver? onFrame,
    int maxFrames = 0,
  }) async {
    final override = probeOverride;
    if (override != null) return override(channelId, source, isCancelled);
    if (!Platform.isIOS ||
        !LiveStreamDetector.isHttpMedia(source.url) ||
        isCancelled()) {
      return const LiveNativeSourceResult(
        renderedVideo: false,
        timelineAdvanceMs: 0,
        buffering: false,
        cancelled: true,
      );
    }

    Player? player;
    VideoController? controller;
    var firstFrameRendered = false;
    var videoWidth = 0;
    var videoHeight = 0;
    var trackCount = 0;
    var movementMs = 0;
    int? firstPositionMs;
    int? startupMs;
    var stalled = true;
    var capturedFrames = 0;
    var nextCaptureMs = 1000;
    final frameLimit = onFrame == null ? 0 : maxFrames.clamp(0, 2).toInt();
    final clock = Stopwatch()..start();

    try {
      player = Player(
        configuration: PlayerSettings.getMediaKitPlayerConfiguration(),
      );
      controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          width: 320,
          height: 180,
          enableHardwareAcceleration: true,
        ),
      );
      // A separate controller creates the native video output. Do not
      // accept audio-only MPV clock movement as a rendered TV picture.
      unawaited(controller.waitUntilFirstFrameRendered.then(
        (_) { firstFrameRendered = true; },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[LiveVisualProbe] Frame: ' +
              error.runtimeType.toString());
        },
      ));

      // Mute BEFORE opening, preventing any audio from a scanned channel.
      await player.setVolume(0.0);
      if (isCancelled()) {
        return const LiveNativeSourceResult(
          renderedVideo: false, timelineAdvanceMs: 0,
          buffering: false, cancelled: true,
        );
      }
      final headers = LiveSourceManager.requestHeaders(
        source, channelId: channelId,
      );
      await PlayerSettings.applyPreOpenProperties(player,
        isLive: true,
        isHlsLive: LiveStreamDetector.isHlsUrl(source.url),
      );
      // Properties applied above may change MPV audio state; mute again.
      await player.setVolume(0.0);
      await player.open(
        Media(source.url!, httpHeaders: headers),
        play: true,
      ).timeout(const Duration(seconds: 9));

      // Observe real iOS media_kit state for up to 16 seconds. Require a
      // rendered frame, video parameters, native tracks and moving timeline.
      // A reachable HLS segment alone never counts as verified.
      for (var tick = 0; tick < 48; tick++) {
        if (isCancelled()) {
          return LiveNativeSourceResult(
            renderedVideo: firstFrameRendered,
            timelineAdvanceMs: movementMs,
            buffering: stalled,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
            trackCount: trackCount,
            startupMs: startupMs,
            cancelled: true,
          );
        }
        await Future<void>.delayed(
            const Duration(milliseconds: 350));
        stalled = player.state.buffering || !player.state.playing;
        final currentPosition = player.state.position.inMilliseconds;
        if (firstPositionMs == null && player.state.playing &&
            !player.state.buffering) {
          firstPositionMs = currentPosition;
        }
        if (firstPositionMs != null &&
            currentPosition > firstPositionMs) {
          final advanced = currentPosition - firstPositionMs;
          if (advanced > movementMs) movementMs = advanced;
        }

        if (tick % 4 == 0) {
          try {
            final dynamic native = player.platform;
            videoWidth = int.tryParse(
              (await native.getProperty('video-params/w'))
                  ?.toString() ?? '',
            ) ?? 0;
            videoHeight = int.tryParse(
              (await native.getProperty('video-params/h'))
                  ?.toString() ?? '',
            ) ?? 0;
            trackCount = int.tryParse(
              (await native.getProperty('track-list/count'))
                  ?.toString() ?? '',
            ) ?? 0;
          } catch (error) {
            debugPrint('[LiveVisualProbe] Properties: ' +
                error.runtimeType.toString());
          }
        }

        // A screenshot is a fallback for native integrations where
        // first-frame notification is delayed until a Video widget mounts.
        if (!firstFrameRendered && videoWidth > 0 &&
            videoHeight > 0 && trackCount > 0 && tick % 8 == 0) {
          try {
            final bytes = await player.screenshot()
                .timeout(const Duration(seconds: 2));
            firstFrameRendered = bytes != null && bytes.isNotEmpty;
          } catch (error) {
            debugPrint('[LiveVisualProbe] Screenshot: ' +
                error.runtimeType.toString());
          }
        }

        if (firstFrameRendered && startupMs == null &&
            videoWidth > 0 && videoHeight > 0 && trackCount > 0) {
          startupMs = clock.elapsedMilliseconds;
        }
        if (frameLimit > capturedFrames && firstFrameRendered &&
            videoWidth > 0 && videoHeight > 0 && trackCount > 0 &&
            !stalled && movementMs >= nextCaptureMs && !isCancelled()) {
          try {
            final png = await player.screenshot()
                .timeout(const Duration(seconds: 2));
            if (png != null && png.isNotEmpty &&
                png.length <= 8 * 1024 * 1024) {
              final accepted = await onFrame!(png, currentPosition)
                  .timeout(const Duration(seconds: 5));
              if (accepted) capturedFrames++;
            }
          } catch (error) {
            debugPrint('[LiveVisualProbe] Snapshot: ' +
                error.runtimeType.toString());
          } finally {
            nextCaptureMs += 3000;
          }
        }

        if (firstFrameRendered && movementMs >= 5000 &&
            videoWidth > 0 && videoHeight > 0 &&
            trackCount > 0 && !stalled) {
          return LiveNativeSourceResult(
            renderedVideo: true,
            timelineAdvanceMs: movementMs,
            buffering: false,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
            trackCount: trackCount,
            startupMs: startupMs,
          );
        }
      }
    } catch (error) {
      // Intentionally never log signed media URLs or header values.
      debugPrint('[LiveVisualProbe] Decode attempt: ' +
          error.runtimeType.toString());
    } finally {
      try {
        await player?.dispose()
            .timeout(const Duration(seconds: 5));
      } catch (error) {
        debugPrint('[LiveVisualProbe] Cleanup: ' +
            error.runtimeType.toString());
      }
      // The VideoController is owned by its Player and native implementation.
      controller = null;
    }
    return LiveNativeSourceResult(
      renderedVideo: firstFrameRendered,
      timelineAdvanceMs: movementMs,
      buffering: stalled,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      trackCount: trackCount,
      startupMs: startupMs,
    );
  }
}
