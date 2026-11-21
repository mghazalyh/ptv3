import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/movie/movie.dart';
import '../player/live_tv/live_channel_health_scanner.dart';

/// Foreground-only, bounded and cancellable health testing. Requests return
/// immediately; the native test proceeds without keeping a Torriodb poll open.
/// Network reachability and native decoding remain distinct evidence levels.
class IosRemoteLiveScan {
  IosRemoteLiveScan();

  static final IosRemoteLiveScan instance = IosRemoteLiveScan();

  Future<void>? _job;
  String? _runId;
  String _phase = 'idle';
  bool _cancelRequested = false;
  bool _native = false;
  int _total = 0;
  int _tested = 0;
  int _verified = 0;
  String? _errorClass;
  DateTime? _started;
  DateTime? _finished;
  final List<Map<String, Object?>> _results = [];

  bool get isRunning => _phase == 'running' || _phase == 'cancelling';

  @visibleForTesting
  Future<void> get whenComplete => _job ?? Future<void>.value();

  Map<String, Object?> status() => <String, Object?>{
    'accepted': true,
    'runId': _runId,
    'phase': _phase,
    'nativeVerificationRequested': _native,
    'total': _total,
    'tested': _tested,
    'nativeVerified': _verified,
    'cancelRequested': _cancelRequested,
    'errorClass': _errorClass,
    'startedAtUtc': _started?.toIso8601String(),
    'finishedAtUtc': _finished?.toIso8601String(),
    'results': _results.take(30).toList(),
    'resultTruncated': _results.length > 30,
  };

  Map<String, Object?> cancel() {
    if (!isRunning) return <String, Object?>{
      'accepted': false, 'reason': 'no_active_live_scan',
    };
    _cancelRequested = true;
    _phase = 'cancelling';
    return status();
  }

  Future<Map<String, Object?>> start(Map<String, dynamic> args, {
    required bool Function() deviceIdle,
    Future<LiveChannelHealthResult> Function(Movie)? inspect,
    Future<LiveChannelHealthResult> Function(
        Movie, LiveChannelHealthResult, bool Function())? verify,
  }) async {
    if (isRunning) return <String, Object?>{
      'accepted': false, 'reason': 'live_scan_already_running',
    };
    const keys = <String>{'runId', 'channels', 'verifyNative'};
    final runId = args['runId'];
    final raw = args['channels'];
    final native = args['verifyNative'] ?? false;
    if (args.keys.any((key) => !keys.contains(key)) ||
        runId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{8,50}$').hasMatch(runId) ||
        raw is! List || raw.isEmpty || raw.length > 25 ||
        native is! bool) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_live_scan_request',
      };
    }
    final seen = <String>{};
    final channels = <Movie>[];
    for (final entry in raw) {
      if (entry is! Map ||
          entry.keys.any((key) => key != 'id' && key != 'title')) {
        return <String, Object?>{
          'accepted': false, 'reason': 'invalid_live_scan_channel',
        };
      }
      final id = entry['id'];
      final title = entry['title'];
      if (id is! String || id.length < 4 || id.length > 180 ||
          !(id.startsWith('nltv:') || id.startsWith('iptv:')) ||
          title is! String || title.trim().isEmpty ||
          title.length > 120 || !seen.add(id)) {
        return <String, Object?>{
          'accepted': false, 'reason': 'invalid_or_duplicate_channel',
        };
      }
      channels.add(Movie(
        id: id, name: title.trim(), type: 'tv', addonBaseUrl: '',
      ));
    }
    if (!deviceIdle()) return <String, Object?>{
      'accepted': false, 'reason': 'device_busy_or_not_foreground',
    };

    _runId = runId;
    _phase = 'running';
    _native = native;
    _cancelRequested = false;
    _total = channels.length;
    _tested = 0;
    _verified = 0;
    _errorClass = null;
    _started = DateTime.now().toUtc();
    _finished = null;
    _results.clear();
    _job = _execute(channels, deviceIdle,
        inspect ?? LiveChannelHealthScanner.inspect,
        verify ?? ((channel, result, cancelled) =>
          LiveChannelHealthScanner.verifyNative(
            channel, result, isCancelled: cancelled,
          )));
    return status();
  }

  Future<void> _execute(
    List<Movie> channels,
    bool Function() deviceIdle,
    Future<LiveChannelHealthResult> Function(Movie) inspect,
    Future<LiveChannelHealthResult> Function(
        Movie, LiveChannelHealthResult, bool Function()) verify,
  ) async {
    bool cancelled() => _cancelRequested || !deviceIdle();
    try {
      for (final channel in channels) {
        if (cancelled()) break;
        try {
          var result = await inspect(channel);
          if (cancelled()) break;
          if (_native) {
            result = await verify(channel, result, cancelled);
          }
          if (cancelled()) break;
          final nativeVerified = result.nativeVerified;
          _tested++;
          if (nativeVerified) _verified++;
          _results.add(<String, Object?>{
            'id': channel.id,
            'title': channel.name,
            'health': result.health.name,
            'reason': result.reason,
            'sourcesChecked': result.sourcesChecked,
            'nativeChecked': result.nativeChecked,
            'nativeVerified': nativeVerified,
            'nativeAttempts': result.nativeAttempts,
            'playableSourceIndex': result.playableSourceIndex,
            'startupMs': result.startupMs,
            'videoWidth': result.videoWidth,
            'videoHeight': result.videoHeight,
            'checkedAtUtc': result.checkedAt?.toUtc().toIso8601String(),
          });
        } catch (error) {
          _tested++;
          _results.add(<String, Object?>{
            'id': channel.id,
            'title': channel.name,
            'health': 'unknown',
            'nativeVerified': false,
            'reason': 'scan_exception',
            'errorClass': error.runtimeType.toString(),
          });
        }
      }
      _phase = cancelled() ? 'cancelled' : 'completed';
    } catch (error) {
      _phase = 'failed';
      _errorClass = error.runtimeType.toString();
      debugPrint('[IosRemoteLiveScan] Failure: ${error.runtimeType}');
    } finally {
      _finished = DateTime.now().toUtc();
    }
  }
}
