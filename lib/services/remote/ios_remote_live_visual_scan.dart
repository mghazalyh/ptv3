import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../models/movie/movie.dart';
import '../../models/stream/stream_model.dart';
import '../player/live_tv/live_native_channel_verifier.dart';
import '../player/live_tv/live_stream_detector.dart';
import '../stream/stream_service.dart';
import 'ios_remote_visual_frame_encoder.dart';

typedef LiveVisualSourceResolver = Future<List<StreamSource>> Function(
    Movie channel);
typedef LiveVisualProbe = Future<LiveNativeSourceResult> Function({
  required String channelId,
  required StreamSource source,
  required bool Function() isCancelled,
  LiveNativeFrameObserver? onFrame,
  int maxFrames,
});
typedef LiveVisualPublish = Future<void> Function(
    String runId, String key, Map<String, Object?> payload);
typedef LiveVisualEncode = Future<Uint8List?> Function(Uint8List frame);

@immutable
class LiveVisualScanChannel {
  const LiveVisualScanChannel(this.id, this.title);
  final String id;
  final String title;

  static LiveVisualScanChannel parse(Object? value) {
    if (value is! Map ||
        value.keys.any((key) => key != 'id' && key != 'title')) {
      throw const FormatException('invalid_channel_entry');
    }
    final id = value['id'];
    final title = value['title'];
    if (id is! String || id.length < 4 || id.length > 180 ||
        !(id.startsWith('nltv:') || id.startsWith('iptv:')) ||
        title is! String || title.trim().isEmpty || title.length > 120) {
      throw const FormatException('invalid_channel_identity');
    }
    return LiveVisualScanChannel(id, title.trim());
  }
}

class _CapturedVisualFrame {
  const _CapturedVisualFrame(this.png, this.atUtc, this.positionMs);
  final Uint8List png;
  final String atUtc;
  final int positionMs;
}

/// Native video observation, not an on-device vision classifier.
///
/// The ChatGPT operator can inspect the resulting PNG files in Torriodb,
/// compare multiple timestamps and infer whether basketball is on screen.
/// No content assertion can be made from titles, EPG or HTTP success alone.
/// Scans are foreground-only, opt-in, silent, sequential and never navigate.
class IosRemoteLiveVisualScan {
  IosRemoteLiveVisualScan();

  static final IosRemoteLiveVisualScan instance =
      IosRemoteLiveVisualScan();

  Future<void>? _job;
  bool _cancelRequested = false;
  String _phase = 'idle';
  String? _runId;
  String? _requestedContent;
  String? _startedAtUtc;
  String? _finishedAtUtc;
  int _done = 0;
  int _total = 0;
  int _verified = 0;
  int _publishedFrames = 0;
  int _uploadFailures = 0;
  final List<Map<String, Object?>> _results = [];

  bool get isRunning => _phase == 'running' || _phase == 'cancelling';

  @visibleForTesting
  Future<void> get whenComplete => _job ?? Future<void>.value();

  Map<String, Object?> status() => <String, Object?>{
    'accepted': true,
    'phase': _phase,
    'runId': _runId,
    'requestedContent': _requestedContent,
    'startedAtUtc': _startedAtUtc,
    'finishedAtUtc': _finishedAtUtc,
    'channelsDone': _done,
    'totalChannels': _total,
    'nativeVerifiedChannels': _verified,
    'publishedFrames': _publishedFrames,
    'uploadFailures': _uploadFailures,
    'cancelRequested': _cancelRequested,
    'classificationPerformed': false,
    'classification': 'requires_chatgpt_image_inspection',
    'evidenceType': 'actual_native_decoded_video_frames',
    'results': _results.take(15).toList(),
  };

  Map<String, Object?> cancel() {
    if (!isRunning) return <String, Object?>{
      'accepted': false, 'reason': 'no_active_visual_scan',
    };
    _cancelRequested = true;
    _phase = 'cancelling';
    return status();
  }

  Future<Map<String, Object?>> start(
    Map<String, dynamic> args, {
    required bool Function() deviceIdle,
    required LiveVisualPublish publish,
    LiveVisualSourceResolver? resolveSources,
    LiveVisualProbe? probe,
    LiveVisualEncode? encodeFrame,
  }) async {
    if (isRunning) return <String, Object?>{
      'accepted': false, 'reason': 'visual_scan_already_running',
    };
    const options = <String>{
      'runId', 'channels', 'contentHint', 'framesPerChannel', 'maxSources',
    };
    final run = args['runId'];
    final rawChannels = args['channels'];
    final hint = args['contentHint'] ?? '';
    final frames = args['framesPerChannel'] ?? 2;
    final maxSources = args['maxSources'] ?? 2;
    if (args.keys.any((key) => !options.contains(key)) ||
        run is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{8,50}$').hasMatch(run) ||
        rawChannels is! List || rawChannels.isEmpty ||
        rawChannels.length > 15 ||
        hint is! String || hint.length > 80 ||
        frames is! int || frames < 1 || frames > 2 ||
        maxSources is! int || maxSources < 1 || maxSources > 3) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_visual_scan_request',
      };
    }
    final channels = <LiveVisualScanChannel>[];
    final identities = <String>{};
    try {
      for (final item in rawChannels) {
        final channel = LiveVisualScanChannel.parse(item);
        if (!identities.add(channel.id)) {
          throw const FormatException('duplicate_channel');
        }
        channels.add(channel);
      }
    } on FormatException {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_or_duplicate_channel',
      };
    }
    if (!deviceIdle()) return <String, Object?>{
      'accepted': false, 'reason': 'device_busy_or_not_foreground',
    };

    _runId = run;
    _requestedContent = hint.trim();
    _startedAtUtc = DateTime.now().toUtc().toIso8601String();
    _finishedAtUtc = null;
    _phase = 'running';
    _cancelRequested = false;
    _total = channels.length;
    _done = 0;
    _verified = 0;
    _publishedFrames = 0;
    _uploadFailures = 0;
    _results.clear();

    _job = _execute(
      channels,
      deviceIdle: deviceIdle,
      publish: publish,
      resolve: resolveSources ?? _resolve,
      probe: probe ?? LiveNativeChannelVerifier.probe,
      encode: encodeFrame ?? IosRemoteVisualFrameEncoder.encode,
      framesPerChannel: frames,
      maxSources: maxSources,
    );
    return status();
  }

  Future<List<StreamSource>> _resolve(Movie channel) async {
    final streams = await StreamService.fetchStreams(
      type: 'tv', id: channel.id, title: channel.name,
    ).timeout(const Duration(seconds: 22),
        onTimeout: (sink) => sink.close()).take(12).toList();
    return streams.where((source) =>
      LiveStreamDetector.isHttpMedia(source.url) &&
      !(source.infoHash?.trim().isNotEmpty ?? false),
    ).take(3).toList(growable: false);
  }

  Future<void> _publishSafe(
    LiveVisualPublish publish, String key, Map<String, Object?> payload,
  ) async {
    try {
      await publish(_runId!, key, payload)
          .timeout(const Duration(seconds: 65));
    } catch (error) {
      _uploadFailures++;
      debugPrint('[IosRemoteLiveVisualScan] Upload: '
          '${error.runtimeType}');
      rethrow;
    }
  }

  Future<void> _execute(
    List<LiveVisualScanChannel> channels, {
    required bool Function() deviceIdle,
    required LiveVisualPublish publish,
    required LiveVisualSourceResolver resolve,
    required LiveVisualProbe probe,
    required LiveVisualEncode encode,
    required int framesPerChannel,
    required int maxSources,
  }) async {
    bool cancelled() => _cancelRequested || !deviceIdle();
    try {
      try {
        await _publishSafe(publish, 'status', status());
      } catch (_) {}
      for (var i = 0; i < channels.length; i++) {
        if (cancelled()) break;
        final channel = channels[i];
        final outcome = <String, Object?>{
          'schema': 1,
          'channelId': channel.id,
          'title': channel.title,
          'channelIndex': i,
          'classification': 'unclassified',
          'nativeVerified': false,
          'frames': <String>[],
        };
        try {
          final movie = Movie(
            id: channel.id, name: channel.title,
            type: 'tv', addonBaseUrl: '',
          );
          final candidates = await resolve(movie)
              .timeout(const Duration(seconds: 30));
          if (cancelled()) break;
          var sourceChecked = 0;
          var found = false;
          for (final source in candidates.take(maxSources)) {
            if (cancelled()) break;
            if (!LiveStreamDetector.isHttpMedia(source.url) ||
                (source.infoHash?.trim().isNotEmpty ?? false)) continue;
            sourceChecked++;
            final captured = <_CapturedVisualFrame>[];
            final fingerprints = <String>{};
            final tested = await probe(
              channelId: channel.id,
              source: source,
              isCancelled: cancelled,
              maxFrames: framesPerChannel,
              onFrame: (raw, positionMs) async {
                if (cancelled() || captured.length >= framesPerChannel) {
                  return false;
                }
                final encoded = await encode(raw);
                if (encoded == null ||
                    !IosRemoteVisualFrameEncoder.isBoundedPng(encoded)) {
                  return false;
                }
                final digest = sha256.convert(encoded).toString();
                if (!fingerprints.add(digest)) return false;
                captured.add(_CapturedVisualFrame(
                  encoded, DateTime.now().toUtc().toIso8601String(),
                  positionMs,
                ));
                return true;
              },
            );
            if (cancelled()) break;
            // Frames from a stalled/failed source cannot establish a working
            // current broadcast even if its manifest returned HTTP 200.
            if (!tested.sustainedStart) continue;
            outcome['nativeVerified'] = true;
            outcome['videoWidth'] = tested.videoWidth;
            outcome['videoHeight'] = tested.videoHeight;
            outcome['timelineAdvanceMs'] = tested.timelineAdvanceMs;
            outcome['startupMs'] = tested.startupMs;
            outcome['sourceOrdinal'] = sourceChecked - 1;
            _verified++;
            final frameKeys = <String>[];
            for (var j = 0; j < captured.length; j++) {
              if (cancelled()) break;
              final entry = captured[j];
              final key = 'frame_${i}_${j}';
              try {
                await _publishSafe(publish, key, <String, Object?>{
                  'schema': 1,
                  'runId': _runId,
                  'channelId': channel.id,
                  'channelIndex': i,
                  'frameIndex': j,
                  'capturedAtUtc': entry.atUtc,
                  'playbackPositionMs': entry.positionMs,
                  'nativeVerified': true,
                  'mimeType': 'image/png',
                  'imageSha256': sha256.convert(entry.png).toString(),
                  'byteLength': entry.png.length,
                  'imageBase64': base64Encode(entry.png),
                });
                frameKeys.add(key);
                _publishedFrames++;
              } catch (_) {}
            }
            outcome['frames'] = frameKeys;
            outcome['reason'] = frameKeys.isEmpty
                ? 'native_video_verified_but_no_exported_frame'
                : 'decoded_video_evidence_available_for_chatgpt';
            found = true;
            break;
          }
          outcome['sourcesChecked'] = sourceChecked;
          if (!found) outcome['reason'] = candidates.isEmpty
              ? 'no_supported_stream_sources' : 'native_video_not_verified';
        } catch (error) {
          outcome['reason'] = 'scan_failed';
          outcome['errorClass'] = error.runtimeType.toString();
          debugPrint('[IosRemoteLiveVisualScan] Candidate: '
              '${error.runtimeType}');
        }
        if (cancelled()) break;
        _done++;
        _results.add(outcome);
        try {
          await _publishSafe(publish, 'channel_$i', outcome);
        } catch (_) {}
        try {
          await _publishSafe(publish, 'status', status());
        } catch (_) {}
      }
      _phase = cancelled() ? 'cancelled' : 'completed';
    } catch (error) {
      _phase = 'failed';
      debugPrint('[IosRemoteLiveVisualScan] Run: ${error.runtimeType}');
    } finally {
      _finishedAtUtc = DateTime.now().toUtc().toIso8601String();
      try {
        await _publishSafe(publish, 'status', status());
      } catch (_) {}
    }
  }
}
