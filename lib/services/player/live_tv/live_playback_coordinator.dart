import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../../models/stream/stream_model.dart';
import '../player_settings.dart';
import 'live_playback_telemetry.dart';
import 'live_recovery_policy.dart';
import 'live_source_manager.dart';
import 'live_stream_detector.dart';

typedef LiveStatusCallback = void Function(String message, bool reconnecting);
typedef LiveSourceCallback = void Function(StreamSource source);

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
    required Iterable<StreamSource> availableSources,
    required this.onStatus,
    required this.onSourceChanged,
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
  final LiveStatusCallback onStatus;
  final LiveSourceCallback onSourceChanged;
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

  bool get isActive => _started && !_disposed;
  int get recoveryAttempts => _policy.attempts;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _policy.reset(DateTime.now(),
      position: _player.state.position,
      buffered: _player.state.buffer,
      duration: _player.state.duration,
    );
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
    start();
    unawaited(_recover('native_error'));
  }

  void onNativeCompleted() {
    if (_disposed) return;
    start();
    unawaited(_recover('live_ended'));
  }

  void _event(String code, [StreamSource? source]) {
    LivePlaybackTelemetry.event(code,
        source: source ?? _source, channelId: channelId, title: title);
  }

  Future<void> _tick() async {
    if (_disposed || !_started || !_foreground || _opening) return;
    final at = DateTime.now();
    try {
      final event = _policy.observe(
        at: at,
        position: _player.state.position,
        buffered: _player.state.buffer,
        duration: _player.state.duration,
        playing: _player.state.playing,
        buffering: _player.state.buffering,
      );
      switch (event) {
        case LiveHealthEvent.recovered:
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
        case LiveHealthEvent.none:
          break;
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
      if (_disposed || _opening || original.url != _source.url ||
          current == null) {
        return;
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

  Future<void> _recover(String reason) async {
    if (_disposed || !_foreground || _opening) return;
    final now = DateTime.now();
    if (!_policy.canAttempt(now)) return;
    _opening = true;
    final generation = ++_generation;
    _policy.beginReopen(now);
    _event('live_reconnect_started');
    onStatus(reason == 'network'
        ? 'Network changed. Reconnecting live TV...'
        : 'Reconnecting live TV...', true);

    StreamSource selected = _source;
    try {
      _sources.failed(_source, now);
      // First recovery reopens the current URL at the live edge. Later
      // recoveries fetch new signed links and consider same-channel backups.
      if (_policy.attempts > 1) {
        final refreshed = await _sources.refresh();
        if (refreshed > 0) _event('live_sources_refreshed');
        final options = _sources.backups(_source, DateTime.now());
        for (final candidate in options.take(6)) {
          if (await _sources.seemsPlayable(candidate)) {
            selected = candidate;
            break;
          }
          _sources.failed(candidate, DateTime.now());
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
        _event('live_source_exhausted');
      }

      // Reuse the existing Player and keep the existing channel screen.
      // Never seek to a stale position for a live stream.
      final volume = _player.state.volume;
      final previousAudioId = _player.state.track.audio.id;
      final previousSubtitleId = _player.state.track.subtitle.id;
      await PlayerSettings.applyPreOpenProperties(_player, isLive: true);
      try {
        final dynamic platform = _player.platform;
        final cache = _policy.recommendedCacheSeconds.toString();
        await platform.setProperty('cache-secs', cache);
        await platform.setProperty('demuxer-readahead-secs', cache);
      } catch (_) {
        // Native MPV options are best-effort across iOS/Windows versions.
      }
      await _player.open(
        Media(selected.url!, httpHeaders: selected.headers),
        play: true,
      ).timeout(const Duration(seconds: 22));
      if (_disposed || generation != _generation) return;
      await _player.setVolume(volume);
      await PlayerSettings.applyPostOpenProperties(_player);
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
      _event('live_reconnect_opened');
      // Wait for tracks to become visible; restore only matching IDs. A
      // different provider can have different track indexes, so fail open.
      unawaited(_restoreTracks(
        generation: generation,
        audioId: previousAudioId,
        subtitleId: previousSubtitleId,
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
    }
  }

  Future<void> _restoreTracks({
    required int generation,
    required String audioId,
    required String subtitleId,
  }) async {
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_disposed || generation != _generation) return;
      final audioMatches = _player.state.tracks.audio
          .where((track) => track.id == audioId);
      if (audioMatches.isNotEmpty) {
        await _player.setAudioTrack(audioMatches.first);
      }
      final subtitleMatches = _player.state.tracks.subtitle
          .where((track) => track.id == subtitleId);
      if (subtitleMatches.isNotEmpty) {
        await _player.setSubtitleTrack(subtitleMatches.first);
      }
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
