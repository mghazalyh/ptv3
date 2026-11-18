import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/windows_settings_recovery.dart';
import '../my_list/github_library_cloud.dart';
import 'night_mode_diagnostics.dart';
import 'player_diagnostic_codes.dart';
import 'playback_metric_sanitizer.dart';
import 'private_diagnostic_log_path.dart';
import '../../models/stream/stream_model.dart';
import '../stream/source_content_identity.dart';
import '../stream/watch_source_preferences.dart';

/// Windows developer diagnostics capture media and release identities.
/// Authentication tokens and streaming URLs are excluded.
class WindowsPlaybackTelemetry {
  WindowsPlaybackTelemetry._({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(), _tokenProvider = tokenProvider;

  factory WindowsPlaybackTelemetry.forTesting({
    required http.Client client,
    required Future<String?> Function() tokenProvider,
  }) => WindowsPlaybackTelemetry._(
      client: client, tokenProvider: tokenProvider);

  static final WindowsPlaybackTelemetry instance = WindowsPlaybackTelemetry._();
  static const prefix = 'playtorrio/diagnostics/windows/player';
  static const repository = 'mghazalyh/torriodb';
  static const branch = 'main';
  static const maxEvents = 24;
  static const maxSamples = 24;
  static const maxSourceTrace = 240;
  static const automaticUploadInterval = Duration(seconds: 30);

  final http.Client _client;
  final Future<String?> Function()? _tokenProvider;
  final ValueNotifier<String> status =
      ValueNotifier<String>('Windows diagnostics OFF');
  final List<String> _events = [];
  final Map<String, Object> _facts = {};
  final List<Map<String, Object>> _samples = [];
  final List<Map<String, Object?>> _sourceTrace = [];
  final Map<String, Object?> _mediaContext = {};
  String? _sourceSessionId;
  final Map<String, int> _previousFrameCounts = {};
  final Map<String, DateTime> _lastAudioWarningAt = {};
  bool _exclusiveAudioReported = false;
  bool _outputRateMismatchReported = false;
  DateTime? _lastUpload;
  bool _uploading = false;
  int _counter = 0;

  @visibleForTesting
  bool forceTestPlatform = false;

  bool get isActive =>
      (Platform.isWindows || forceTestPlatform) &&
      NightModeDiagnostics.debugModeEnabled.value;

  @visibleForTesting
  Map<String, Object> get capturedFacts => Map.unmodifiable(_facts);

  @visibleForTesting
  List<Map<String, Object>> get capturedSamples =>
      List.unmodifiable(_samples);

  @visibleForTesting
  List<String> get capturedCodes => List.unmodifiable(_events);

  @visibleForTesting
  List<Map<String, Object?>> get capturedSourceTrace =>
      List.unmodifiable(_sourceTrace);

  static String? _safeText(String? raw, {int limit = 400}) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw
        .replaceAll(RegExp(r'(?:https?://|magnet:\?)[^\s\r\n]+',
            caseSensitive: false), '[redacted-url]')
        .replaceAll(RegExp(
            r'(?:(?:token|api[_-]?key|password|secret|authorization)'
            r'\s*[:=]\s*)[^\s\r\n]+', caseSensitive: false),
            '[redacted-secret]')
        .trim();
    return value.length <= limit ? value : value.substring(0, limit);
  }

  void _trace(Map<String, Object?> data) {
    if (!isActive) return;
    _sourceSessionId ??= DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    if (_sourceTrace.length >= maxSourceTrace) _sourceTrace.removeAt(0);
    _sourceTrace.add(<String, Object?>{
      'utc': DateTime.now().toUtc().toIso8601String(),
      'sessionId': _sourceSessionId,
      ...data,
    });
  }

  Map<String, Object?> _details(StreamSource source) => <String, Object?>{
    'addon': _safeText(source.addonName),
    'releaseFilename': _safeText(source.title),
    'sourceName': _safeText(source.name),
    'description': _safeText(source.description),
    'infoHash': _safeText(source.infoHash),
    'fileIdx': source.fileIdx,
    'resolution': source.quality,
    'fileSizeBytes': source.sizeBytes,
  };

  void beginSourceSession({
    required String title, required String mediaId, required String type,
    String? episodeTitle, int? year, int? season, int? episode,
  }) {
    if (!isActive) return;
    _sourceSessionId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    _mediaContext
      ..clear()
      ..addAll(<String, Object?>{
        'title': _safeText(title),
        'mediaId': _safeText(mediaId),
        'type': _safeText(type),
        'year': year,
        'season': season,
        'episode': episode,
        'episodeTitle': _safeText(episodeTitle),
      });
    _trace(<String, Object?>{
      'action': 'source_session_started',
      'media': Map<String, Object?>.of(_mediaContext),
    });
  }

  void captureSourceCandidate({
    required String stage, required StreamSource source,
    required String title, required String mediaId,
    required String type, required String verdict,
    int? year, int? season, int? episode,
  }) {
    if (!isActive) return;
    _trace(<String, Object?>{
      'action': stage,
      'requestedTitle': _safeText(title),
      'requestedMediaId': _safeText(mediaId),
      'requestedType': _safeText(type),
      'requestedYear': year,
      'requestedSeason': season,
      'requestedEpisode': episode,
      'identityVerdict': verdict,
      ..._details(source),
    });
  }

  void captureSourceRanking({
    required List<StreamSource> sources,
    required List<StreamSource> sorted,
    required String title,
    int? year, int? season, int? episode,
    Map<String, bool> verified = const {},
  }) {
    if (!isActive) return;
    final mismatched = sources.where((source) =>
        SourceContentIdentity.assess(source, title: title,
            year: year, season: season, episode: episode)
        == SourceIdentityVerdict.rejected).toList();
    _trace(<String, Object?>{
      'action': 'source_ranking_completed',
      'requestedTitle': _safeText(title),
      'candidateCount': sources.length,
      'visibleCount': sorted.length,
      'rejectedCount': mismatched.length,
      'sorting': WatchSourcePreferencesService.current.value
          .forEpisode(season != null && episode != null)
          .sorting.map((r) => r.toJson()).toList(),
    });
    for (final source in mismatched.take(30)) {
      _trace(<String, Object?>{
        'action': 'source_excluded',
        'reason': 'wrong_media_identity',
        ..._details(source),
      });
    }
    for (var index = 0; index < sorted.length && index < 50; index++) {
      final source = sorted[index];
      _trace(<String, Object?>{
        'action': 'source_ranked',
        'rank': index + 1,
        'identityVerdict': SourceContentIdentity.assess(source,
            title: title, year: year, season: season, episode: episode).name,
        'cacheTier': WatchSourceEngine.cacheTier(source, verified,
            season: season, episode: episode),
        ..._details(source),
      });
    }
  }

  void captureSourceSelection({
    required String action,
    required StreamSource source,
    required String title,
    String? episodeTitle,
    int? year, int? season, int? episode,
  }) {
    if (!isActive) return;
    _trace(<String, Object?>{
      'action': action,
      'requestedTitle': _safeText(title),
      'requestedYear': year,
      'requestedSeason': season,
      'requestedEpisode': episode,
      'episodeTitle': _safeText(episodeTitle),
      'identityVerdict': SourceContentIdentity.assess(source,
          title: title, year: year, season: season, episode: episode).name,
      ..._details(source),
    });
  }

  /// Actual MediaKit/MPV audio track metadata is more reliable than labels
  /// embedded in addon release filenames.
  void captureAudioTracks({
    required String stage,
    required List<Map<String, Object?>> tracks,
    int? selectedTrackId,
    bool manual = false,
    bool loading = false,
  }) {
    if (!isActive) return;
    final allowedStage = const {
      'media_kit_tracks', 'native_mpv_raw_track_list',
      'native_mpv_track_list', 'after_audio_switch',
    }.contains(stage) ? stage : 'other';
    _trace(<String, Object?>{
      'action': 'audio_tracks_observed',
      'stage': allowedStage,
      'selectedTrackId': selectedTrackId,
      'manualSelection': manual,
      'playerLoading': loading,
      'trackCount': tracks.length,
      'tracks': tracks.take(64).map((track) {
        final rawId = track['id'];
        final id = rawId is int ? rawId
            : int.tryParse(rawId?.toString() ?? '');
        final language = _safeText(track['language']?.toString(), limit: 64);
        final title = _safeText(track['title']?.toString(), limit: 256);
        return <String, Object?>{
          'id': id,
          'language': language,
          'title': title,
          'channels': track['channels'],
          'codec': _safeText(track['codec']?.toString(), limit: 64),
          'isDefault': track['isDefault'] == true,
          'selected': selectedTrackId != null && selectedTrackId == id,
          'englishLabel': AudioLanguagePriority.isEnglish(
              language: language, title: title),
        };
      }).toList(),
    });
  }

  void captureAudioSelection({
    required String action, int? requestedTrackId, int? actualTrackId,
    bool manual = false, String? reason,
  }) {
    if (!isActive) return;
    if (!const {
      'audio_switch_requested', 'audio_switch_completed',
      'audio_switch_failed', 'native_track_probe_failed',
    }.contains(action)) return;
    _trace(<String, Object?>{
      'action': action,
      'requestedTrackId': requestedTrackId,
      'actualTrackId': actualTrackId,
      'manual': manual,
      'reason': _safeText(reason, limit: 120),
    });
  }

  /// Native completion and its verdict are traceable to actual media metadata.
  void captureEpisodeCompletion({
    required String action,
    required String reason,
    required StreamSource source,
    required String requestedTitle,
    required Duration position,
    required Duration nativeDuration,
    required bool isBuffering,
    String? episodeTitle,
    int? season,
    int? episode,
    int? nextSeason,
    int? nextEpisode,
    Duration? bufferedPosition,
    Duration? expectedRuntime,
    Duration? recentSeekFrom,
  }) {
    if (!isActive) return;
    final ahead = bufferedPosition == null
        ? null : bufferedPosition.inMilliseconds - position.inMilliseconds;
    _trace(<String, Object?>{
      'action': action,
      'reason': reason,
      'requestedTitle': _safeText(requestedTitle),
      'episodeTitle': _safeText(episodeTitle),
      'season': season,
      'episode': episode,
      'nextSeason': nextSeason,
      'nextEpisode': nextEpisode,
      'positionMs': position.inMilliseconds,
      'nativeDurationMs': nativeDuration.inMilliseconds,
      'expectedRuntimeMs': expectedRuntime?.inMilliseconds,
      'bufferedPositionMs': bufferedPosition?.inMilliseconds,
      'bufferAheadMs': ahead == null ? null : ahead < 0 ? 0 : ahead,
      'buffering': isBuffering,
      'recentSeekFromMs': recentSeekFrom?.inMilliseconds,
      ..._details(source),
    });
    if (action == 'automatic_next_episode_blocked') {
      captureCode('episode_autoplay_blocked');
    }
  }

  static const allowedEvents = <String>{
    'brightness_changed',
    'brightness_vf_fallback',
    'night_mode_enabled',
    'night_mode_disabled',
    'audio_filter_failure',
    'settings_profile_recovered',
    'render_stutter_detected',
    'flutter_frame_stutter',
    'texture_pressure_reduced',
    'video_resync_requested',
    'source_retry_requested',
    'source_fallback_attempted',
    'source_recovery_exhausted',
    'playback_buffering',
    'windows_subtitle_only_settings_applied',
    'windows_audio_filter_preserved',
    'windows_audio_preopen_preserved',
    'windows_audio_preopen_reset',
    'windows_audio_output_rate_mismatch',
    'windows_shared_audio_requested',
    'windows_shared_audio_unavailable',
    'windows_audio_output_underrun',
    'windows_audio_device_interrupted',
    'windows_audio_output_reinitialized',
    'windows_audio_exclusive_detected',
    ...PlayerDiagnosticCodes.events,
  };

  void captureCode(String code) {
    if (!isActive || !allowedEvents.contains(code)) return;
    if (_events.length >= maxEvents) _events.removeAt(0);
    _events.add(code);
  }

  /// Turn a native warning into a fixed category without ever retaining its
  /// text, audio endpoint name, path or other potentially identifying content.
  /// Absence of this warning does not establish glitch-free audible playback.
  static String? classifyNativeAudioWarning({
    required String prefix, required String message,
  }) {
    if (message.isEmpty || message.length > 1024) return null;
    final source = prefix.toLowerCase();
    final value = message.toLowerCase();
    final isOutput = source == 'ao' || source.startsWith('ao/') ||
        source.contains('wasapi') || value.contains('audio device') ||
        value.contains('audio output') || value.contains('wasapi');
    if (!isOutput) return null;
    if (value.contains('underrun') || value.contains('underflow')) {
      return 'windows_audio_output_underrun';
    }
    if (value.contains('disconnected') || value.contains('invalidated') ||
        value.contains('device lost')) {
      return 'windows_audio_device_interrupted';
    }
    if (value.contains('reinitializ') || value.contains('re-init') ||
        value.contains('reopen') || value.contains('re-open')) {
      return 'windows_audio_output_reinitialized';
    }
    return null;
  }

  void captureNativeAudioLog({
    required String prefix, required String message, DateTime? now,
  }) {
    if (!isActive) return;
    final code = classifyNativeAudioWarning(
        prefix: prefix, message: message);
    if (code == null) return;
    final instant = now ?? DateTime.now();
    final last = _lastAudioWarningAt[code];
    if (last != null && !instant.isBefore(last) &&
        instant.difference(last) < const Duration(seconds: 30)) return;
    _lastAudioWarningAt[code] = instant;
    captureCode(code);
  }

  void captureStorageState() {
    if (!isActive) return;
    final audit = WindowsSettingsRecovery.lastAudit;
    if (audit == null) return;
    _facts['storageProfile'] = const <String>{
      'recovered-from-existing-profile', 'existing-profile', 'empty-profile',
      'roaming-appdata-unavailable',
    }.contains(audit.state) ? audit.state : 'unavailable';
    _facts['preferenceCount'] = audit.preferenceCount.clamp(0, 5000);
    if (audit.recovered) captureCode('settings_profile_recovered');
  }

  void captureProperty(String name, Object? value) {
    if (!isActive || value == null) return;
    // Never include the original value unless it belongs to a fixed enum.
    final text = value.toString().toLowerCase();
    switch (name) {
      case 'brightness':
        final number = double.tryParse(text);
        if (number != null && number.isFinite && number >= -100 && number <= 100) {
          _facts['nativeBrightness'] = number;
        }
        break;
      case 'vf':
        _facts['videoEqFilterActive'] = text.contains('eq=brightness=');
        break;
      case 'af':
        _facts['audioCompressorActive'] = text.contains('acompressor=');
        _facts['audioLimiterActive'] = text.contains('alimiter=');
        break;
      case 'audio-normalize-downmix':
        if (const {'yes', 'no', 'true', 'false'}.contains(text)) {
          _facts['downmixNormalized'] = text == 'yes' || text == 'true';
        }
        break;
      case 'vo':
        if (const {'gpu', 'gpu-next', 'libmpv', 'null', 'null,', 'unknown'}.contains(text)) {
          _facts['videoOutput'] = text;
        } else {
          _facts['videoOutput'] = 'other';
        }
        break;
      case 'hwdec-current':
        if (const {'no', 'd3d11va', 'd3d11va-copy', 'dxva2', 'dxva2-copy',
          'nvdec', 'nvdec-copy', 'auto', 'unknown'}.contains(text)) {
          _facts['hardwareDecoder'] = text;
        } else {
          _facts['hardwareDecoder'] = 'other';
        }
        break;
      case 'framedrop':
        if (const {'vo', 'decoder', 'decoder+vo', 'no'}.contains(text)) {
          _facts['frameDropMode'] = text;
        }
        break;
      case 'video-sync':
        if (const {'audio', 'display-resample', 'display-vdrop',
          'display-adrop', 'display-desync'}.contains(text)) {
          _facts['videoSync'] = text;
        }
        break;
      case 'video-texture-tier':
        if (const {'native', 'hd', 'sd', 'low'}.contains(text)) {
          _facts['videoTextureTier'] = text;
        }
        break;
      case 'brightness-pipeline':
        if (text == 'flutter-color-matrix') {
          _facts['brightnessPipeline'] = text;
          _facts['videoEqFilterActive'] = false;
        }
        break;
      case 'audio-codec-name':
        if (const {'aac', 'eac3', 'ac3', 'mp3', 'flac', 'opus', 'alac',
          'pcm_s16le', 'dts', 'truehd'}.contains(text)) {
          _facts['audioCodec'] = text;
        }
        break;
      default:
        break;
    }
  }

  /// Record only numeric, allowlisted native mpv playback performance
  /// properties. Never transmit the media filename, URL, title or log output.
  /// Cumulative frame counters are converted to per-sample deltas so it is
  /// clear whether the game caused fresh missed frames.
  void capturePlaybackSample(
      Map<String, Object?> properties, {
      bool buffering = false,
      Duration? position,
      Duration? duration,
      Duration? bufferedPosition,
      }) {
    if (!isActive) return;
    final sample = <String, Object>{
      'utc': DateTime.now().toUtc().toIso8601String(),
      'buffering': buffering,
    };
    sample.addAll(PlaybackMetricSanitizer.fromProperties(properties));
    if (position != null && position >= Duration.zero) {
      sample['positionMs'] = position.inMilliseconds;
    }
    if (duration != null && duration >= Duration.zero) {
      sample['nativeDurationMs'] = duration.inMilliseconds;
    }
    if (bufferedPosition != null && bufferedPosition >= Duration.zero) {
      sample['bufferedPositionMs'] = bufferedPosition.inMilliseconds;
    }

    for (final property in const <String>[
      'frame-drop-count', 'decoder-frame-drop-count',
      'vo-delayed-frame-count', 'mistimed-frame-count',
    ]) {
      final value = int.tryParse(properties[property]?.toString() ?? '');
      if (value == null || value < 0 || value > 1000000000) continue;
      final key = switch (property) {
        'frame-drop-count' => 'voDropped',
        'decoder-frame-drop-count' => 'decoderDropped',
        'vo-delayed-frame-count' => 'lateFrames',
        _ => 'mistimedFrames',
      };
      sample[key] = value;
      final previous = _previousFrameCounts[property];
      final delta = previous == null || value < previous ? 0 : value - previous;
      sample['${key}Delta'] = delta;
      _previousFrameCounts[property] = value;
      if ((property == 'frame-drop-count' ||
          property == 'decoder-frame-drop-count' ||
          property == 'vo-delayed-frame-count') && delta >= 2) {
        captureCode('render_stutter_detected');
      }
    }

    for (final property in const <String>[
      'avsync', 'demuxer-cache-duration',
    ]) {
      final value = double.tryParse(properties[property]?.toString() ?? '');
      if (value == null || !value.isFinite || value.abs() > 3600) continue;
      sample[property == 'avsync' ? 'avsyncSeconds' : 'cacheSeconds'] =
          (value * 1000).round() / 1000;
    }

    // Output-device and decoded-audio rates provide a narrow audio-specific
    // health signal. Missing properties stay absent, never false zeros.
    for (final entry in const <String, String>{
      'audio-params/samplerate': 'audioDecodedSampleRateHz',
      'audio-out-params/samplerate': 'audioOutputSampleRateHz',
    }.entries) {
      final rate = int.tryParse(properties[entry.key]?.toString() ?? '');
      if (rate != null && rate >= 8000 && rate <= 384000) {
        sample[entry.value] = rate;
      }
    }
    // Report only a fixed category for decoded/output sample-rate differences;
    // never retain a Windows endpoint name, identifier or private log entry.
    final decodedRate = sample['audioDecodedSampleRateHz'];
    final outputRate = sample['audioOutputSampleRateHz'];
    if (!_outputRateMismatchReported && decodedRate is int &&
        outputRate is int && decodedRate != outputRate) {
      _outputRateMismatchReported = true;
      captureCode('windows_audio_output_rate_mismatch');
    }
    final bufferSeconds = double.tryParse(
        properties['audio-buffer']?.toString() ?? '');
    if (bufferSeconds != null && bufferSeconds.isFinite &&
        bufferSeconds >= 0 && bufferSeconds <= 3) {
      sample['audioBufferMs'] = (bufferSeconds * 1000).round();
    }
    final exclusive = properties['audio-exclusive']?.toString().toLowerCase();
    if (exclusive == 'yes' || exclusive == 'no') {
      sample['audioExclusive'] = exclusive == 'yes';
      if (exclusive == 'yes' && !_exclusiveAudioReported) {
        _exclusiveAudioReported = true;
        captureCode('windows_audio_exclusive_detected');
      }
    }

    for (final property in const <String>[
      'flutter-frame-count', 'flutter-slow-build-count',
      'flutter-slow-raster-count', 'flutter-worst-raster-ms',
    ]) {
      final value = int.tryParse(properties[property]?.toString() ?? '');
      if (value == null || value < 0 || value > 100000) continue;
      final name = switch (property) {
        'flutter-frame-count' => 'flutterFrames',
        'flutter-slow-build-count' => 'flutterSlowBuildFrames',
        'flutter-slow-raster-count' => 'flutterSlowRasterFrames',
        _ => 'flutterWorstRasterMs',
      };
      sample[name] = value;
      if (property == 'flutter-slow-raster-count' && value >= 2) {
        captureCode('flutter_frame_stutter');
      }
    }
    for (final property in const <String>[
      'hwdec-current', 'vf', 'framedrop', 'video-sync',
    ]) {
      captureProperty(property, properties[property]);
    }

    if (buffering) captureCode('playback_buffering');
    if (_samples.length >= maxSamples) _samples.removeAt(0);
    _samples.add(sample);
  }

  void resetPlaybackCounters() {
    _previousFrameCounts.clear();
    _lastAudioWarningAt.clear();
    _exclusiveAudioReported = false;
    _outputRateMismatchReported = false;
  }

  Future<String?> _accessToken() async {
    if (_tokenProvider != null) return _tokenProvider();
    await GitHubLibraryCloud.instance.initialize();
    return GitHubLibraryCloud.instance.progressAccessToken;
  }

  /// Explicit manual send or throttled auto diagnostic send after owner opt-in.
  Future<bool> upload({
    String reason = 'manual',
    bool automatic = false,
  }) async {
    if (!isActive) {
      status.value = 'Enable Windows Debug Mode to send diagnostics';
      return false;
    }
    if (_uploading) return false;
    if (automatic && _lastUpload != null &&
        DateTime.now().difference(_lastUpload!) < automaticUploadInterval) {
      return false;
    }
    captureStorageState();
    if (_facts.isEmpty && _events.isEmpty && _samples.isEmpty && _sourceTrace.isEmpty) {
      status.value = 'No playback diagnostics captured yet';
      return false;
    }
    String? token;
    try {
      token = await _accessToken();
    } catch (_) {
      status.value = 'GitHub Library credentials unavailable';
      return false;
    }
    if (token == null || token.isEmpty) {
      status.value = 'Connect GitHub Library to TorriODB with Contents write access';
      return false;
    }

    _uploading = true;
    _lastUpload = DateTime.now();
    final now = DateTime.now().toUtc();
    final approvedReason = const {
      'manual', 'brightness_changed', 'night_mode_changed',
      'audio_filter_failure', 'playback_sample', 'sync_failure',
       'subtitle_failure', 'source_failure', 'addon_failure',
    }.contains(reason) ? reason : 'manual';
    final file = PrivateDiagnosticLogPath.forTimestamp(
      prefix: prefix, timestamp: now, sequence: ++_counter);
    final data = <String, Object>{
      'schema': 2,
      'kind': 'windows_playback_developer_diagnostic',
      'timestampUtc': now.toIso8601String(),
      'platform': 'windows',
      'appVersion': '1.1.15',
      'buildCommit': const String.fromEnvironment(
          'PLAYTORRIO_COMMIT', defaultValue: 'unknown'),
      'buildRun': const String.fromEnvironment(
          'PLAYTORRIO_RUN', defaultValue: 'unknown'),
      'reason': approvedReason,
      'codes': List<String>.from(_events),
      'capabilities': Map<String, Object>.from(_facts),
      'sampleIntervalSeconds': 5,
      'performanceSamples': List<Map<String, Object>>.from(_samples),
      'sourceSessionId': _sourceSessionId ?? '',
      'mediaContext': Map<String, Object?>.from(_mediaContext),
      'sourceTrace': List<Map<String, Object?>>.from(_sourceTrace),
    };

    try {
      final response = await _client.put(
        Uri.https('api.github.com', '/repos/$repository/contents/$file'),
        headers: <String, String>{
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'User-Agent': 'PlayTorrio-Windows-private-diagnostics',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        body: jsonEncode(<String, String>{
          'message': 'diagnostics(windows): allowlisted player capability report',
          'branch': branch,
          'content': base64Encode(utf8.encode(jsonEncode(data))),
        }),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 201) {
        status.value = 'Private diagnostics upload failed (HTTP ${response.statusCode})';
        return false;
      }
      _events.clear();
      _samples.clear();
      _sourceTrace.clear();
      status.value = 'Uploaded private diagnostics: $file';
      return true;
    } catch (_) {
      status.value = 'Private diagnostics upload unavailable';
      return false;
    } finally {
      _uploading = false;
    }
  }

  void dispose() {
    _client.close();
    status.dispose();
  }
}
