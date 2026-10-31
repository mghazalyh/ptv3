import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../my_list/github_library_cloud.dart';

/// Explicitly opt-in, strictly allowlisted MPV filter diagnostics for the
/// owner's PRIVATE GitHub database. Never uploads raw MPV lines, media URLs,
/// HTTP headers, tokens, titles, subtitles, or user/device identifiers.
class IosAudioTelemetry {
  IosAudioTelemetry._({http.Client? client, Future<String?> Function()? tokenProvider})
      : _client = client ?? http.Client(),
        _tokenProvider = tokenProvider;

  @visibleForTesting
  factory IosAudioTelemetry.forTesting({
    required http.Client client,
    required Future<String?> Function() tokenProvider,
  }) => IosAudioTelemetry._(client: client, tokenProvider: tokenProvider);

  static final IosAudioTelemetry instance = IosAudioTelemetry._();
  static const preferenceKey = 'ios_private_audio_diagnostics_optin_v1';
  static const repository = 'mghazalyh/torriodb';
  static const branch = 'main';
  static const prefix = 'playtorrio/diagnostics/ios/night-mode';
  static const maxEvents = 24;
  static const maxPlaybackSamples = 24;
  static const playbackSampleSeconds = 5;
  static const _minUploadInterval = Duration(seconds: 30);
  static const buildCommit = String.fromEnvironment(
      'PLAYTORRIO_COMMIT', defaultValue: 'unknown');
  static const buildRun = String.fromEnvironment(
      'PLAYTORRIO_RUN', defaultValue: 'unknown');

  @visibleForTesting
  bool forceTestPlatform = false;

  final http.Client _client;
  final Future<String?> Function()? _tokenProvider;
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<String> status =
      ValueNotifier<String>('iOS audio telemetry OFF');
  final List<String> _events = [];
  final List<Map<String, Object>> _performanceSamples = [];
  final Map<String, int> _previousFrameCounters = {};
  bool _loaded = false;
  bool _uploading = false;
  DateTime? _lastUpload;
  int _counter = 0;

  bool get isActive => (Platform.isIOS || forceTestPlatform) && enabled.value;
  @visibleForTesting
  List<String> get capturedCodes => List.unmodifiable(_events);

  @visibleForTesting
  List<Map<String, Object>> get capturedPerformanceSamples =>
      List.unmodifiable(_performanceSamples);

  Future<void> initialize() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(preferenceKey) ?? false;
    status.value = enabled.value
        ? 'Ready to send private Night Mode diagnostics'
        : 'iOS audio telemetry OFF';
    _loaded = true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(preferenceKey, value);
    enabled.value = value;
    if (!value) {
      _events.clear();
      _performanceSamples.clear();
      _previousFrameCounters.clear();
      status.value = 'iOS audio telemetry OFF';
    } else {
      status.value = 'Ready to send private Night Mode diagnostics';
    }
  }

  /// Convert untrusted native logs to fixed, non-identifying error codes.
  /// Unrecognized messages are DROPPED rather than imperfectly redacted.
  @visibleForTesting
  static String? classify(String message) {
    final lower = message.toLowerCase();
    for (final filter in const ['acompressor', 'compand', 'scaletempo2']) {
      if (lower.contains('no such filter') && lower.contains(filter)) {
        return 'missing_filter_$filter';
      }
    }
    if (lower.contains('audio filter initialized failed') ||
        lower.contains('error initializing audio filters')) {
      return 'audio_filter_init_failed';
    }
    if (lower.contains('parsing the filter graph failed') ||
        lower.contains('error creating filters')) {
      return 'filter_graph_failed';
    }
    if (lower.contains('creating filter') && lower.contains('lavfi') &&
        lower.contains('failed')) {
      return 'lavfi_create_failed';
    }
    if (lower.contains('audio filter') && lower.contains('unsupported')) {
      return 'audio_filter_unsupported';
    }
    return null;
  }

  void captureNativeLog(String message) {
    if (!isActive) return;
    final code = classify(message);
    if (code != null) captureCode(code);
  }

  static const allowedCodes = <String>{
    'missing_filter_acompressor',
    'missing_filter_compand',
    'missing_filter_scaletempo2',
    'audio_filter_init_failed',
    'filter_graph_failed',
    'lavfi_create_failed',
    'audio_filter_unsupported',
    'ios_filter_preflight_failed',
    'acompressor_supported',
    'compand_supported',
    'ios_probe_audio_error',
    'ios_probe_downmix_setter_failed',
    'ios_probe_filter_setter_failed',
    'ios_probe_open_failed',
    'ios_probe_timeout',
    'ios_probe_unexpected_error',
    'flutter_frame_stutter',
    'playback_frame_drops',
    'playback_buffering',
  };

  void captureCode(String code) {
    if (!enabled.value || !allowedCodes.contains(code)) return;
    // A single failure can be observed by preflight AND its caller. Preserve
    // distinct error reasons instead of duplicating the same status code.
    if (_events.contains(code)) return;
    if (_events.length >= maxEvents) _events.removeAt(0);
    _events.add(code);
  }

  /// Capture actual libmpv performance counters at most every five seconds
  /// when iOS private diagnostics opt-in is enabled. Never forward raw native
  /// logs, untrusted property names, URLs, paths or media metadata.
  void capturePlaybackSample(
    Map<String, Object?> properties, {bool buffering = false}
  ) {
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
      final previous = _previousFrameCounters[property];
      final delta = previous == null || value < previous ? 0 : value - previous;
      sample['${key}Delta'] = delta;
      _previousFrameCounters[property] = value;
      if ((property == 'frame-drop-count' ||
              property == 'decoder-frame-drop-count' ||
              property == 'vo-delayed-frame-count') && delta >= 2) {
        captureCode('playback_frame_drops');
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
    // All reported values are fixed booleans/enums, not arbitrary native text.
    final hwdec = properties['hwdec-current']?.toString().toLowerCase();
    if (hwdec != null && const {
      'no', 'videotoolbox', 'videotoolbox-copy', 'auto', 'unknown'
    }.contains(hwdec)) {
      sample['hardwareDecoder'] = hwdec;
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
    if (buffering) captureCode('playback_buffering');
    if (_performanceSamples.length >= maxPlaybackSamples) {
      _performanceSamples.removeAt(0);
    }
    _performanceSamples.add(sample);
  }

  void resetPlaybackCounters() => _previousFrameCounters.clear();

  /// Report only whitelisted facts, never arbitrary native property values.
  static Map<String, String> safeAudioFields(Map<String, Object?> source) {
    final filtered = <String, String>{};
    final codec = source['codec']?.toString().toLowerCase();
    if (codec != null &&
        const ['aac', 'eac3', 'ac3', 'mp3', 'flac', 'opus', 'alac',
          'pcm_s16le', 'unknown'].contains(codec)) {
      filtered['codec'] = codec;
    }
    final channels = source['channels']?.toString().toLowerCase();
    if (channels != null &&
        const ['mono', 'stereo', '2.1', '3.0', '4.0', '5.1', '5.1(side)',
          '7.1', 'unknown'].contains(channels)) {
      filtered['channels'] = channels;
    }
    final rate = int.tryParse(source['sampleRate']?.toString() ?? '');
    if (rate != null && rate >= 8000 && rate <= 192000) {
      filtered['sampleRate'] = '$rate';
    }
    return filtered;
  }

  /// Returns a private GitHub Contents API report path. A random ID or user
  /// account ID is deliberately not part of the payload or path.
  @visibleForTesting
  static String fileName(DateTime time, int sequence) =>
      '$prefix/${time.toUtc().toIso8601String().replaceAll(':', '-').replaceAll('.', '-')}-'
      '$sequence.json';

  Future<String?> _accessToken() async {
    if (_tokenProvider != null) return _tokenProvider();
    await GitHubLibraryCloud.instance.initialize();
    return GitHubLibraryCloud.instance.progressAccessToken;
  }

  /// Manual submit or one automatic submit per active Night Mode failure.
  /// An uploaded report contains only enum codes and whitelisted audio facts.
  Future<bool> upload({
    String reason = 'manual',
    Map<String, Object?> audio = const {},
    bool automatic = false,
  }) async {
    await initialize();
    if (!isActive) {
      status.value = 'Enable iOS audio telemetry in Settings first';
      return false;
    }
    if (_uploading) return false;
    if (automatic && _lastUpload != null &&
        DateTime.now().difference(_lastUpload!) < _minUploadInterval) return false;
    if (_events.isEmpty && _performanceSamples.isEmpty) {
      status.value = 'No audio or playback diagnostics captured yet';
      return false;
    }
    final token = await _accessToken();
    if (token == null || token.isEmpty) {
      status.value = 'Connect GitHub Library with Torriodb Contents write access';
      return false;
    }

    _uploading = true;
    _lastUpload = DateTime.now();
    final now = DateTime.now().toUtc();
    final safeReason = const {
      'night_mode_failed', 'preflight_failed', 'native_error', 'manual',
      'playback_sample',
    }.contains(reason) ? reason : 'manual';
    final report = <String, Object>{
      'schema': 1,
      'kind': 'ios_night_mode_filter_diagnostic',
      'timestampUtc': now.toIso8601String(),
      'platform': 'ios',
      'appVersion': '1.1.15',
      'buildRun': buildRun,
      'buildCommit': buildCommit,
      'reason': safeReason,
      'filterCandidates': const ['acompressor', 'compand'],
      'nativeErrorCodes': List<String>.from(_events),
      'audio': safeAudioFields(audio),
      'sampleIntervalSeconds': playbackSampleSeconds,
      'performanceSamples': List<Map<String, Object>>.from(_performanceSamples),
    };
    final remote = fileName(now, ++_counter);
    final uri = Uri.https('api.github.com',
        '/repos/$repository/contents/$remote');
    try {
      final response = await _client.put(uri,
        headers: <String, String>{
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'User-Agent': 'PlayTorrio-iOS-audio-diagnostics',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        body: jsonEncode(<String, String>{
          'message': 'diagnostics(ios): redacted Night Mode filter report',
          'branch': branch,
          'content': base64Encode(utf8.encode(jsonEncode(report))),
        }),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 201) {
        status.value = 'Private upload failed (HTTP ${response.statusCode}); check GitHub permissions';
        return false;
      }
      _events.clear();
      _performanceSamples.clear();
      status.value = 'Uploaded to private Torriodb: $remote';
      return true;
    } catch (_) {
      status.value = 'Private upload unavailable; check network and retry';
      return false;
    } finally {
      _uploading = false;
    }
  }

  void dispose() {
    _client.close();
    enabled.dispose();
    status.dispose();
  }
}
