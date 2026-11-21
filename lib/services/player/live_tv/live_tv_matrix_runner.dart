import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

typedef LiveMatrixOpen = Future<Map<String, Object?>> Function(
    String channelId, String title, int sourceIndex);
typedef LiveMatrixInspect = Future<Map<String, Object?>> Function();
typedef LiveMatrixPublish = Future<void> Function(
    String runId, String key, Map<String, Object?> payload);
typedef LiveMatrixWait = Future<void> Function(Duration duration);

@immutable
class LiveMatrixChannel {
  const LiveMatrixChannel(this.id, this.title);
  final String id;
  final String title;

  static LiveMatrixChannel parse(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid channel entry');
    if (raw.keys.any((key) => key != 'id' && key != 'title')) {
      throw const FormatException('Unexpected channel field');
    }
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || id.length < 4 || id.length > 180 ||
        !(id.startsWith('nltv:') || id.startsWith('iptv:')) ||
        title is! String || title.trim().isEmpty || title.length > 120) {
      throw const FormatException('Invalid TV channel');
    }
    return LiveMatrixChannel(id, title);
  }
}

/// Long running, foreground-only playback audit controlled by Torriodb.
/// A receipt acknowledges START, not success. Each candidate gets its own
/// private result file; playback is proven by native tracks plus timeline
/// progress across samples and five minutes of sustained availability.
class LiveTvMatrixRunner {
  LiveTvMatrixRunner({LiveMatrixWait? wait})
      : _wait = wait ?? Future<void>.delayed;

  final LiveMatrixWait _wait;
  Future<void>? _job;
  bool _cancelled = false;
  String? _runId;
  String _phase = 'idle';
  int _channelsDone = 0;
  int _sourcesDone = 0;
  int _verifiedSources = 0;
  int _uploadFailures = 0;
  int _totalChannels = 0;
  String? _lastChannel;
  String? _lastFailure;

  Map<String, Object?> status() => <String, Object?>{
    'accepted': true,
    'runId': _runId,
    'phase': _phase,
    'channelsDone': _channelsDone,
    'totalChannels': _totalChannels,
    'sourcesDone': _sourcesDone,
    'verifiedSources': _verifiedSources,
    'uploadFailures': _uploadFailures,
    'lastChannel': _lastChannel,
    'lastFailure': _lastFailure,
  };

  @visibleForTesting
  Future<void> get whenComplete => _job ?? Future<void>.value();

  Map<String, Object?> cancel() {
    _cancelled = true;
    return status();
  }

  Future<Map<String, Object?>> start(
    Map<String, dynamic> args, {
    required LiveMatrixOpen open,
    required LiveMatrixInspect inspect,
    required LiveMatrixPublish publish,
  }) async {
    if (_job != null && _phase == 'running') {
      return <String, Object?>{...status(),
          'accepted': false, 'reason': 'matrix_already_running'};
    }
    try {
      if (args.keys.any((key) => !const <String>{
            'runId', 'channels', 'seed', 'sampleSeconds',
            'sustainSeconds', 'maxSources',
          }.contains(key))) throw const FormatException('Unknown option');
      final rawRun = args['runId'];
      if (rawRun is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{8,50}$').hasMatch(rawRun)) {
        throw const FormatException('Invalid run ID');
      }
      final raw = args['channels'];
      if (raw is! List || raw.length < 50 || raw.length > 150) {
        throw const FormatException('At least 50 distinct TV channels required');
      }
      final channels = raw.map(LiveMatrixChannel.parse).toList();
      if (channels.map((item) => item.id).toSet().length != channels.length) {
        throw const FormatException('Duplicate TV channels');
      }
      int bounded(String name, int fallback, int min, int max) {
        final value = args[name] ?? fallback;
        if (value is! int || value < min || value > max) {
          throw FormatException('Invalid matrix option ' + name);
        }
        return value;
      }
      final seed = bounded('seed', 1207, 0, 0x7fffffff);
      final sampleSeconds = bounded('sampleSeconds', 15, 10, 90);
      final sustainSeconds = bounded('sustainSeconds', 300, 300, 900);
      final maxSources = bounded('maxSources', 36, 1, 36);
      final random = Random(seed);
      // Stable shuffling, with known-good control always first if provided.
      final control = channels.where((item) =>
          item.id == 'nltv:us:CineRomantico.us').toList();
      final other = channels.where((item) =>
          item.id != 'nltv:us:CineRomantico.us').toList()..shuffle(random);
      final ordered = <LiveMatrixChannel>[...control, ...other];
      _runId = rawRun;
      _phase = 'running';
      _cancelled = false;
      _channelsDone = 0;
      _sourcesDone = 0;
      _verifiedSources = 0;
      _uploadFailures = 0;
      _totalChannels = channels.length;
      _lastChannel = null;
      _lastFailure = null;
      _job = _run(ordered, sampleSeconds, sustainSeconds, maxSources,
          open, inspect, publish);
      return status();
    } catch (error) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_matrix_plan',
        'errorClass': error.runtimeType.toString(),
      };
    }
  }

  Future<void> _publishSafe(LiveMatrixPublish publish,
      String key, Map<String, Object?> result) async {
    try {
      await publish(_runId!, key, result);
    } catch (error) {
      _uploadFailures++;
      debugPrint('[LiveMatrix] Result upload: ' +
          error.runtimeType.toString());
    }
  }

  Future<void> _run(
      List<LiveMatrixChannel> channels,
      int sampleSeconds,
      int sustainSeconds,
      int maxSources,
      LiveMatrixOpen open,
      LiveMatrixInspect inspect,
      LiveMatrixPublish publish) async {
    try {
      await _publishSafe(publish, 'status', status());
      for (var index = 0; index < channels.length && !_cancelled; index++) {
        final channel = channels[index];
        _lastChannel = channel.id;
        var sourceCount = 1;
        for (var sourceIndex = 0;
            sourceIndex < sourceCount && sourceIndex < maxSources &&
                !_cancelled;
            sourceIndex++) {
          final result = <String, Object?>{
            'schema': 1,
            'runId': _runId,
            'channelId': channel.id,
            'title': channel.title,
            'channelIndex': index,
            'requestedSourceIndex': sourceIndex,
          };
          try {
            final opened = await open(channel.id, channel.title, sourceIndex);
            final accepted = opened['accepted'] == true;
            if (sourceIndex == 0 && opened['sourceCount'] is int) {
              sourceCount = (opened['sourceCount'] as int).clamp(1, 36).toInt();
            }
            result['accepted'] = accepted;
            result['requestedSourceHost'] = opened['sourceHost'];
            result['availableSources'] = sourceCount;
            if (accepted) {
              final samples = <Map<String, Object?>>[];
              for (var n = 0; n < 3 && !_cancelled; n++) {
                await _wait(Duration(seconds: sampleSeconds));
                if (_cancelled) break;
                final answer = await inspect();
                final live = answer['live'];
                samples.add(live is Map
                    ? Map<String, Object?>.from(live)
                    : <String, Object?>{});
              }
              if (!_cancelled && samples.length == 3) {
                final first = samples.first;
                final last = samples.last;
                final width = last['videoWidth'];
                final height = last['videoHeight'];
                final tracks = last['trackCount'];
                final pos = last['positionMs'];
                final previous = first['positionMs'];
                final wasMoving = pos is int && previous is int &&
                    pos > previous + 1000;
                final decoded = width is int && width > 0 &&
                    height is int && height > 0 &&
                    tracks is int && tracks > 0;
                final prelim = decoded && wasMoving &&
                    last['channelId'] == channel.id &&
                    last['playing'] == true && last['buffering'] == false;
                result['candidateVideo'] = prelim;
                result['activeSourceHost'] = last['activeSourceHost'];
                result['httpRelayActive'] = last['httpRelayActive'];
                result['httpRelayAttempted'] = last['httpRelayAttempted'];
                result['nativeFormat'] = last['nativeFormat'];
                result['nativeFailureCounts'] = last['nativeFailureCounts'];
                result['videoWidth'] = width;
                result['videoHeight'] = height;
                result['trackCount'] = tracks;
                result['positionStartMs'] = previous;
                result['positionEndMs'] = pos;
                result['buffering'] = last['buffering'];
                result['experimentId'] = last['experimentId'];
                if (prelim) {
                  await _wait(Duration(seconds: sustainSeconds));
                  if (!_cancelled) {
                    final finalAnswer = await inspect();
                    final finalLive = finalAnswer['live'];
                    final ending = finalLive is Map
                        ? Map<String, Object?>.from(finalLive)
                        : <String, Object?>{};
                    final finalPos = ending['positionMs'];
                    final verified = ending['channelId'] == channel.id &&
                        ending['videoDimensionsReady'] == true &&
                        ending['trackCount'] is int &&
                        (ending['trackCount'] as int) > 0 &&
                        ending['playing'] == true &&
                        ending['buffering'] == false &&
                        finalPos is int && finalPos > pos + 1000;
                    result['sustainedPlayback'] = verified;
                    result['finalPositionMs'] = finalPos;
                    result['finalSourceHost'] = ending['activeSourceHost'];
                    if (verified) _verifiedSources++;
                  }
                } else {
                  result['sustainedPlayback'] = false;
                }
              }
            }
          } catch (error) {
            result['accepted'] = false;
            result['errorClass'] = error.runtimeType.toString();
            _lastFailure = error.runtimeType.toString();
          }
          if (_cancelled) break;
          _sourcesDone++;
          await _publishSafe(publish,
              'candidate_' + index.toString() + '_' + sourceIndex.toString(),
              result);
          await _publishSafe(publish, 'status', status());
        }
        if (_cancelled) break;
        _channelsDone++;
      }
      _phase = _cancelled ? 'cancelled' : 'completed';
    } catch (error) {
      _phase = 'failed';
      _lastFailure = error.runtimeType.toString();
    } finally {
      await _publishSafe(publish, 'status', status());
    }
  }
}
