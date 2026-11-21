import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../../models/stream/stream_model.dart';
import '../player_settings.dart';
import 'live_playback_telemetry.dart';
import 'live_recovery_policy.dart';
import 'live_signal_health.dart';
import 'live_source_manager.dart';
import 'live_stream_detector.dart';

typedef LiveStatusCallback = void Function(String message, bool reconnecting);
typedef LiveSourceCallback = void Function(StreamSource source);
typedef LiveHealthCallback = void Function(LiveSignalSnapshot snapshot);

/// Session-scoped supervisor used ONLY for Stremio live TV channels.
///
/// Movie/series recovery, resume positions, seeking, and source selection are
/// deliberately excluded. This class never opens media with a past timestamp.
class LivePlaybackCoordinator {
  LivePlaybackCoordinator({
    required Player player,
    required StreamSource initialSource,
    required this.channelId,
    required this.title,
    this.programmeTitle,
    this.programmeKind,
    required Iterable<StreamSource> availableSources,
    required this.onStatus,
    required this.onSourceChanged,
    this.onHealthChanged,
    LiveRecoveryPolicy? policy,
    LiveSourceManager? sourceManager,
  })  : _player = player,
        _source = initialSource,
        _policy = policy ?? LiveRecoveryPolicy(),
        _sources = sourceManager ?? LiveSourceManager(
          channelId: channelId,
          addonName: initialSource.addonName,
          initial: initialSource,
          initialSources: availableSources,
        );

  final Player _player;
  final String channelId;
  final String title;
  final String? programmeTitle;
  final String? programmeKind;
  final LiveStatusCallback onStatus;
  final LiveSourceCallback onSourceChanged;
  final LiveHealthCallback? onHealthChanged;
  final LiveRecoveryPolicy _policy;
  final LiveSourceManager _sources;

  StreamSource _source;
  Timer? _monitor;
  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _opening = false;
  bool _checkingNetwork = false;
  bool _checkingPlaylist = false;
  DateTime? _lastNetworkProbe;
  DateTime? _lastPlaylistProbe;
  DateTime? _previousPlaylistAt;
  String? _networkSignature;
  LivePlaylistSnapshot? _previousPlaylist;
  int _generation = 0;
  bool _reportedExhaustion = false;
  int _unverifiedConsecutive = 0;
  bool _nativeVideoReady = false;
  bool _checkingVideo = false;
  int? _nativeVideoWidth;
  int? _nativeVideoHeight;
  DateTime? _sessionStartedAt = DateTime.now();
  DateTime? _lastRecoveryStartedAt;
  DateTime? _firstVideoAt;
  DateTime? _lastTelemetryAt;
  String? _lastPlaylistProbeIssue;
  int? _nativeTrackCount;
  String? _nativeFormat;
  int _nativeProbeErrors = 0;
  int _nativeErrorCount = 0;
  DateTime? _lastNativeErrorEventAt;
  final Map<String, DateTime> _nativeFailureLastAt = {};
  final Map<String, int> _nativeFailureCounts = {};

  bool get isActive => _started && !_disposed;
  int get recoveryAttempts => _policy.attempts;

  /// Extra native verification: a moving audio clock alone cannot prove
  /// usable Live TV. A decoded video stream must expose MPV video dimensions.
  Future<void> _probeNativeVideo() async {
    if (_disposed || _checkingVideo || _nativeVideoReady) return;
    _checkingVideo = true;
    final generation = _generation;
    try {
      final dynamic native = _player.platform;
      final width = int.tryParse(
        (await native.getProperty('video-params/w'))?.toString() ?? '',
      );
      final height = int.tryParse(
        (await native.getProperty('video-params/h'))?.toString() ?? '',
      );
      if (_disposed || _opening || generation != _generation) return;
      try {
        _nativeTrackCount = int.tryParse(
            (await native.getProperty('track-list/count'))?.toString() ?? '');
        final format = (await native.getProperty('file-format'))
            ?.toString().toLowerCase() ?? '';
        _nativeFormat = format.contains('hls') ? 'hls' :
            format.contains('mpegts') ? 'mpegts' :
            format.contains('mp4') ? 'mp4' :
            format.isEmpty ? 'unknown' : 'other';
      } catch (_) {
        _nativeProbeErrors++;
      }
      if (width != null && height != null &&
          width > 0 && height > 0 && width <= 16384 && height <= 16384) {
        _nativeVideoWidth = width;
        _nativeVideoHeight = height;
        _nativeVideoReady = true;
        _event('live_video_ready');
      }
    } catch (_) {
      _nativeProbeErrors++;
      // Native failures are classified, not uploaded verbatim.
    } finally {
      _checkingVideo = false;
    }
  }

  void _observe(String code, [StreamSource? reportedSource]) {
    if (_disposed) return;
    final now = DateTime.now();
    final signal = LiveSignalSnapshot.evaluate(
      hasPlayed: _policy.everPlayed,
      reconnecting: _opening || _policy.awaitingRecovery,
      buffering: _player.state.buffering,
      playing: _player.state.playing,
      attempts: _policy.attempts,
      position: _player.state.position,
      bufferEnd: _player.state.buffer,
      feedAge: _policy.feedAge(now),
    );
    final probe = _sources.latestProbeFor(reportedSource ?? _source);
    LivePlaybackTelemetry.observation(
      event: code,
      source: reportedSource ?? _source,
      channelId: channelId,
      title: title,
      programmeTitle: programmeTitle,
      programmeKind: programmeKind,
      signalQuality: signal.level.name,
      failureClass: switch (code) {
        'live_stall_detected' => 'buffering_stall',
        'live_feed_starvation' => 'buffer_starvation',
        'live_video_unavailable' => 'no_video_track',
        'live_playlist_stale' => 'hls_media_sequence_stale',
        'live_playlist_ended' => 'hls_endlist',
        'live_no_backup_available' => 'backup_unavailable',
        'live_reconnect_failed' => 'native_open_failure',
        _ => null,
      },
      attempts: _policy.attempts,
      candidateCount: _sources.sourceCount,
      buffering: _player.state.buffering,
      playing: _player.state.playing,
      videoReady: _nativeVideoReady && _policy.everPlayed,
      reconnecting: _opening || _policy.awaitingRecovery,
      startupElapsedMs: _sessionStartedAt == null ? null
          : now.difference(_sessionStartedAt!).inMilliseconds,
      recoveryElapsedMs: _lastRecoveryStartedAt == null ? null
          : now.difference(_lastRecoveryStartedAt!).inMilliseconds,
      firstFrameElapsedMs: _firstVideoAt == null ||
          _sessionStartedAt == null ? null
          : _firstVideoAt!.difference(_sessionStartedAt!).inMilliseconds,
      videoWidth: _nativeVideoWidth,
      videoHeight: _nativeVideoHeight,
      positionMs: _player.state.position.inMilliseconds,
      bufferedEndMs: _player.state.buffer.inMilliseconds,
      motionAgeMs: _policy.motionAge(now).inMilliseconds,
      feedAgeMs: _policy.feedAge(now).inMilliseconds,
      playlistSequence: _previousPlaylist?.mediaSequence,
      playlistTargetSeconds: _previousPlaylist?.targetDurationSeconds,
      playlistDiscontinuities: _previousPlaylist?.discontinuities,
      probePhase: probe?.phase,
      probeOutcome: probe?.outcome,
      probeHttpStatus: probe?.httpStatus,
      probeElapsedMs: probe?.elapsedMs,
      probeBytes: probe?.bodyBytes,
      probeMimeKind: probe?.mimeKind,
      probeHeaderCount: probe?.headerCount,
      probeIsMaster: probe?.isMaster,
      probeSegmentCount: probe?.segmentCount,
      nativeTrackCount: _nativeTrackCount,
      nativeFormat: _nativeFormat,
      nativeProbeErrors: _nativeProbeErrors,
      nativeErrorCount: _nativeErrorCount,
    );
  }

  void _notifyHealth() {
    if (_disposed) return;
    onHealthChanged?.call(LiveSignalSnapshot.evaluate(
      hasPlayed: _policy.everPlayed,
      reconnecting: _opening || _policy.awaitingRecovery,
      buffering: _player.state.buffering,
      playing: _player.state.playing,
      attempts: _policy.attempts,
      position: _player.state.position,
      bufferEnd: _player.state.buffer,
      feedAge: _policy.feedAge(DateTime.now()),
    ));
  }

  void start() {
    if (_started || _disposed) return;
    _started = true;
    // Constructor-time timestamp includes initial native open latency.
    _policy.reset(DateTime.now(),
      position: _player.state.position,
      buffered: _player.state.buffer,
      duration: _player.state.duration,
    );
    _notifyHealth();
    _event('live_initial_open_pending');
    _monitor = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_tick());
    });
  }

  void onAppLifecycle(bool resumed) {
    if (_disposed) return;
    _foreground = resumed;
    if (!resumed) return;
    _event('live_session_resumed');
    if (_started && _player.state.buffering) {
      // Do not force a restart after a user-initiated pause.
      unawaited(_recover('lifecycle'));
    }
  }

  void onNativeError() {
    if (_disposed) return;
    if (_nativeErrorCount < 100000) _nativeErrorCount++;
    final now = DateTime.now();
    // Native FFmpeg can issue thousands of duplicate callbacks per second.
    // Count every occurrence but record/recover only once per cooldown.
    if (_lastNativeErrorEventAt != null &&
        now.difference(_lastNativeErrorEventAt!) <
            const Duration(seconds: 8)) return;
    _lastNativeErrorEventAt = now;
    _event('live_native_error_signaled');
    start();
    if (!_opening) unawaited(_recover('native_error'));
  }

  @visibleForTesting
  static String? classifyNativeFailure(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('403') || lower.contains('401') ||
        lower.contains('forbidden') || lower.contains('unauthorized')) {
      return 'live_native_http_auth';
    }
    if (lower.contains('404') || lower.contains('410') ||
        lower.contains('not found')) {
      return 'live_native_http_missing';
    }
    if (lower.contains('certificate') || lower.contains('tls') ||
        lower.contains('ssl handshake')) {
      return 'live_native_tls_failure';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'live_native_timeout';
    }
    if (lower.contains('segment') &&
        (lower.contains('fail') || lower.contains('error'))) {
      return 'live_native_segment_failure';
    }
    if (lower.contains('invalid data') || lower.contains('demux') ||
        lower.contains('cannot decode') || lower.contains('decoder error')) {
      return 'live_native_demux_failure';
    }
    if (lower.contains('m3u8') || lower.contains('playlist')) {
      if (lower.contains('fail') || lower.contains('error') ||
          lower.contains('invalid')) return 'live_native_manifest_failure';
    }
    return null;
  }

  void onNativeLog(String message) {
    if (_disposed || !_started) return;
    final code = classifyNativeFailure(message);
    if (code == null) return;
    _nativeFailureCounts[code] = (_nativeFailureCounts[code] ?? 0) + 1;
    final now = DateTime.now();
    if (_nativeFailureLastAt[code] != null &&
        now.difference(_nativeFailureLastAt[code]!) <
            const Duration(seconds: 8)) return;
    _nativeFailureLastAt[code] = now;
    _event(code);
  }

  Future<Map<String, Object?>> diagnosticState({bool inspect = false}) async {
    if (inspect && !_disposed) await _sources.inspectFirstSegment(_source);
    final probe = _sources.latestProbeFor(_source);
    return <String, Object?>{
      'active': isActive,
      'channel': title,
      'sourceAddon': _source.addonName,
      'sourceQuality': _source.quality ?? 'unknown',
      'sourceCount': _sources.sourceCount,
      'recoveryAttempts': _policy.attempts,
      'nativeErrors': _nativeErrorCount,
      'nativeFailureCounts': Map<String, int>.from(_nativeFailureCounts),
      'videoDimensionsReady': _nativeVideoReady,
      'videoWidth': _nativeVideoWidth,
      'videoHeight': _nativeVideoHeight,
      'trackCount': _nativeTrackCount,
      'nativeFormat': _nativeFormat,
      'positionMs': _player.state.position.inMilliseconds,
      'bufferedMs': _player.state.buffer.inMilliseconds,
      'buffering': _player.state.buffering,
      'probePhase': probe?.phase,
      'probeOutcome': probe?.outcome,
      'probeHttpStatus': probe?.httpStatus,
    };
  }

  Future<bool> diagnosticRetry({int? sourceIndex}) async {
    if (_disposed || _opening || !_foreground) return false;
    StreamSource? chosen;
    if (sourceIndex != null) {
      final choices = <StreamSource>[
        _source,
        ..._sources.backups(_source, DateTime.now()),
      ];
      if (sourceIndex < 0 || sourceIndex >= choices.length) return false;
      chosen = choices[sourceIndex];
    }
    await _recover('remote_diagnostic', force: true,
        overrideSource: chosen);
    return true;
  }

  void onNativeCompleted() {
    if (_disposed) return;
    _event('live_native_end_signaled');
    start();
    unawaited(_recover('live_ended'));
  }

  void _event(String code, [StreamSource? source]) {
    LivePlaybackTelemetry.event(code,
      source: source ?? _source,
      channelId: channelId,
      title: title,
      programmeTitle: programmeTitle,
      programmeKind: programmeKind,
    );
    _observe(code, source);
  }

  Future<void> _tick() async {
    if (_disposed || !_started || !_foreground || _opening) return;
    final at = DateTime.now();
    try {
      await _probeNativeVideo();
      if (_disposed || _opening) return;
      final event = _policy.observe(
        at: at,
        position: _player.state.position,
        buffered: _player.state.buffer,
        duration: _player.state.duration,
        playing: _player.state.playing,
        buffering: _player.state.buffering,
        videoReady: _nativeVideoReady,
      );
      switch (event) {
        case LiveHealthEvent.started:
          _firstVideoAt ??= at;
          _unverifiedConsecutive = 0;
          _reportedExhaustion = false;
          _sources.recovered(_source);
          _event('live_first_frame_confirmed');
          onStatus('Live TV', false);
          break;
        case LiveHealthEvent.recovered:
          _firstVideoAt ??= at;
          _unverifiedConsecutive = 0;
          _reportedExhaustion = false;
          _sources.recovered(_source);
          _event('live_recovered');
          onStatus('Live TV', false);
          break;
        case LiveHealthEvent.bufferingStall:
          _event('live_stall_detected');
          unawaited(_recover('buffering'));
          break;
        case LiveHealthEvent.feedStarvation:
          _event('live_feed_starvation');
          unawaited(_recover('starvation'));
          break;
        case LiveHealthEvent.timelineDiscontinuity:
          _event('live_playlist_discontinuity');
          break;
        case LiveHealthEvent.videoUnavailable:
          _event('live_video_unavailable');
          unawaited(_recover('no_video'));
          break;
        case LiveHealthEvent.none:
          break;
      }
      _notifyHealth();
      if (_lastTelemetryAt == null ||
          at.difference(_lastTelemetryAt!) >= const Duration(seconds: 10)) {
        _lastTelemetryAt = at;
        _observe('live_health_sample');
      }
      if (_lastNetworkProbe == null ||
          at.difference(_lastNetworkProbe!) >= const Duration(seconds: 10)) {
        _lastNetworkProbe = at;
        unawaited(_inspectNetwork());
      }
      if (LiveStreamDetector.isHlsUrl(_source.url) &&
          (_lastPlaylistProbe == null ||
          at.difference(_lastPlaylistProbe!) >= const Duration(seconds: 18))) {
        _lastPlaylistProbe = at;
        unawaited(_inspectPlaylist());
      }
    } catch (error) {
      debugPrint('[LiveTV] Health probe failed: ${error.runtimeType}');
    }
  }

  Future<void> _inspectNetwork() async {
    if (_checkingNetwork || _disposed) return;
    _checkingNetwork = true;
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false)
          .timeout(const Duration(seconds: 5));
      final endpoints = <String>[];
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          endpoints.add('${interface.name}:${address.address}');
        }
      }
      endpoints.sort();
      final fingerprint = endpoints.join('|');
      if (_networkSignature != null && _networkSignature != fingerprint) {
        _event('live_network_changed');
        if (_player.state.buffering && _foreground) {
          unawaited(_recover('network'));
        }
      }
      _networkSignature = fingerprint;
    } catch (_) {
      // Restricted platforms may not permit interface enumeration.
    } finally {
      _checkingNetwork = false;
    }
  }

  Future<void> _inspectPlaylist() async {
    if (_checkingPlaylist || _opening || _disposed) return;
    _checkingPlaylist = true;
    final original = _source;
    try {
      final current = await _sources.inspectPlaylist(original);
      if (_disposed || _opening || original.url != _source.url) return;
      final diagnostic = _sources.latestProbeFor(original);
      if (current == null) {
        if (diagnostic != null && diagnostic.outcome != 'ok' &&
            _lastPlaylistProbeIssue != diagnostic.outcome) {
          _lastPlaylistProbeIssue = diagnostic.outcome;
          _event('live_playlist_probe_failed');
        }
        return;
      }
      if (_lastPlaylistProbeIssue != null) {
        _lastPlaylistProbeIssue = null;
        _event('live_playlist_probe_recovered');
      }
      final at = DateTime.now();
      if (current.ended) {
        _event('live_playlist_ended');
        unawaited(_recover('playlist_ended'));
        return;
      }
      if (_previousPlaylist != null) {
        if (current.discontinuities != _previousPlaylist!.discontinuities &&
            !current.isMaster) {
          _event('live_playlist_discontinuity');
        }
        final staleDuration = Duration(seconds:
            (current.targetDurationSeconds * 2).clamp(12, 90).toInt());
        final ahead = _player.state.buffer - _player.state.position;
        if (_previousPlaylistAt != null &&
            at.difference(_previousPlaylistAt!) >= staleDuration &&
            current.sameMediaAs(_previousPlaylist!) &&
            ahead <= const Duration(seconds: 10)) {
          _event('live_playlist_stale');
          unawaited(_recover('playlist_stale'));
          return;
        }
        if (!current.sameMediaAs(_previousPlaylist!)) {
          _previousPlaylistAt = at;
        }
      } else {
        _previousPlaylistAt = at;
      }
      _previousPlaylist = current;
    } catch (_) {
      // A side-channel playlist probe cannot interrupt healthy playback.
    } finally {
      _checkingPlaylist = false;
    }
  }

  Future<void> _recover(String reason, {
    bool force = false,
    StreamSource? overrideSource,
  }) async {
    if (_disposed || !_foreground || _opening) return;
    final now = DateTime.now();
    if (!force && !_policy.canAttempt(now)) return;
    _opening = true;
    _lastRecoveryStartedAt = now;
    final generation = ++_generation;
    _policy.beginReopen(now);
    _event('live_reconnect_started');
    _notifyHealth();
    onStatus(reason == 'network'
        ? 'Network changed. Reconnecting live TV...'
        : 'Reconnecting live TV...', true);

    StreamSource selected = overrideSource ?? _source;
    try {
      _sources.failed(_source, now);
      // iPad telemetry showed repeated unverified "opened" states. On the
      // very first startup stall, try a real backup immediately instead of
      // consuming another full stall timeout on the same dead CDN.
      if (overrideSource == null && LivePlaybackAcceptance.shouldAttemptBackup(
        attempts: _policy.attempts,
        hasConfirmedPlayback: _policy.everPlayed,
      )) {
        final refreshed = await _sources.refresh();
        if (refreshed > 0) _event('live_sources_refreshed');
        final options = _sources.backups(_source, DateTime.now());
        for (final candidate in options.take(6)) {
          if (await _sources.seemsPlayable(candidate)) {
            selected = candidate;
            _event('live_failover_candidate_accepted', candidate);
            break;
          }
          _sources.failed(candidate, DateTime.now());
          _event('live_failover_candidate_rejected', candidate);
          _event('live_source_rejected', candidate);
        }
      }
      if (_disposed || generation != _generation) return;
      if (!LiveStreamDetector.isHttpMedia(selected.url)) {
        _event('live_source_exhausted');
        throw const FormatException('No supported live stream URL');
      }
      if (selected.url != _source.url) {
        _event('live_backup_selected', selected);
      } else if (_policy.attempts > 2 && !_reportedExhaustion) {
        _reportedExhaustion = true;
        // All fallback links were absent/quarantined. The retryable current
        // source is not proof that an entire channel has ceased broadcasting.
        _event('live_no_backup_available');
      }

      // Reuse the existing Player and keep the existing channel screen.
      // Never seek to a stale position for a live stream.
      final volume = _player.state.volume;
      final previousAudioId = _player.state.track.audio.id;
      await PlayerSettings.applyPreOpenProperties(_player,
          isLive: true,
          isHlsLive: LiveStreamDetector.isHlsUrl(selected.url));
      try {
        final dynamic platform = _player.platform;
        final cache = _policy.recommendedCacheSeconds.toString();
        await platform.setProperty('cache-secs', cache);
        await platform.setProperty('demuxer-readahead-secs', cache);
      } catch (_) {
        // Native MPV options are best-effort across iOS/Windows versions.
      }
      // Match initial PlayerScreen header resolution on every reconnect.
      // In particular preserve CDN Referer, Origin and User-Agent that may
      // otherwise be lost during failover on iPadOS.
      final headers = LiveSourceManager.requestHeaders(selected);
      // Each native media open resets video readiness. Old decoder metadata
      // must never make a new, dead source look healthy.
      _nativeVideoReady = false;
      _nativeVideoWidth = null;
      _nativeVideoHeight = null;
      _nativeTrackCount = null;
      _nativeFormat = null;
      _lastPlaylistProbeIssue = null;
      await _player.open(
        Media(selected.url!, httpHeaders: headers),
        play: true,
      ).timeout(const Duration(seconds: 22));
      if (_disposed || generation != _generation) return;
      await _player.setVolume(volume);
      await PlayerSettings.applyPostOpenProperties(_player);
      // Live channels never show or auto-download subtitles.
      await _disableLiveSubtitles();
      if (_disposed || generation != _generation) return;
      if (selected.url != _source.url) {
        _source = selected;
        _previousPlaylist = null;
        _previousPlaylistAt = null;
        onSourceChanged(selected);
      }
      _policy.reopened(DateTime.now(),
        position: _player.state.position,
        buffered: _player.state.buffer,
        duration: _player.state.duration,
      );
      // This only means Media.open returned. A real recovered event is
      // emitted later, after unbuffered media timeline progression.
      _unverifiedConsecutive++;
      _event('live_reconnect_opened');
      _event('live_startup_unverified');
      if (_unverifiedConsecutive >= 3 &&
          _unverifiedConsecutive % 3 == 0) {
        LivePlaybackTelemetry.uploadRepeatedFailure();
      }
      _notifyHealth();
      unawaited(_restoreAudioTrack(
        generation: generation,
        audioId: previousAudioId,
      ));
    } catch (error) {
      if (_disposed || generation != _generation) return;
      debugPrint('[LiveTV] Reopen failed: ${error.runtimeType}');
      _sources.failed(selected, DateTime.now());
      _policy.reopenFailed(DateTime.now());
      _event('live_reconnect_failed', selected);
      if (_policy.attempts >= 3 && _policy.attempts % 3 == 0) {
        LivePlaybackTelemetry.uploadRepeatedFailure();
      }
      onStatus('Live stream unavailable. Retrying...', true);
    } finally {
      _opening = false;
      _notifyHealth();
    }
  }

  Future<void> _disableLiveSubtitles() async {
    try {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    } catch (_) {
      // Keep video alive even when no subtitle track exists.
    }
    try {
      final dynamic platform = _player.platform;
      await platform.setProperty('sub-visibility', 'no');
    } catch (_) {
      // Optional MPV native property, safe on unsupported backends.
    }
  }

  Future<void> _restoreAudioTrack({
    required int generation,
    required String audioId,
  }) async {
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_disposed || generation != _generation) return;
      final audioMatches = _player.state.tracks.audio
          .where((track) => track.id == audioId);
      if (audioMatches.isNotEmpty) {
        await _player.setAudioTrack(audioMatches.first);
      }
      // Never restore subtitles on a live channel.
      await _disableLiveSubtitles();
    } catch (_) {
      // Invalid or absent track IDs must never block live playback.
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _monitor?.cancel();
    _monitor = null;
  }
}
