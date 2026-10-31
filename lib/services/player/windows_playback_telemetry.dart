import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/windows_settings_recovery.dart';
import '../my_list/github_library_cloud.dart';
import 'night_mode_diagnostics.dart';

/// Strictly allowlisted Windows player capability diagnostics.
/// No MPV raw logs, paths, URLs, titles, credentials or library records.
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
  static const automaticUploadInterval = Duration(seconds: 30);

  final http.Client _client;
  final Future<String?> Function()? _tokenProvider;
  final ValueNotifier<String> status =
      ValueNotifier<String>('Windows diagnostics OFF');
  final List<String> _events = [];
  final Map<String, Object> _facts = {};
  final List<Map<String, Object>> _samples = [];
  final Map<String, int> _previousFrameCounts = {};
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
    'playback_buffering',
  };

  void captureCode(String code) {
    if (!isActive || !allowedEvents.contains(code)) return;
    if (_events.length >= maxEvents) _events.removeAt(0);
    _events.add(code);
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
        if (const {'native', 'hd', 'sd'}.contains(text)) {
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
      Map<String, Object?> properties, {bool buffering = false}) {
    if (!isActive) return;
    final sample = <String, Object>{
      'utc': DateTime.now().toUtc().toIso8601String(),
      'buffering': buffering,
    };

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

  void resetPlaybackCounters() => _previousFrameCounts.clear();

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
    if (_facts.isEmpty && _events.isEmpty && _samples.isEmpty) {
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
      'audio_filter_failure', 'playback_sample',
    }.contains(reason) ? reason : 'manual';
    final timestamp = now.toIso8601String()
        .replaceAll(':', '-').replaceAll('.', '-');
    final file = '$prefix/$timestamp-${++_counter}.json';
    final data = <String, Object>{
      'schema': 1,
      'kind': 'windows_playback_capability_diagnostic',
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
