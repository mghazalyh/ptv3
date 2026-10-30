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
  bool _loaded = false;
  bool _uploading = false;
  DateTime? _lastUpload;
  int _counter = 0;

  bool get isActive => (Platform.isIOS || forceTestPlatform) && enabled.value;
  @visibleForTesting
  List<String> get capturedCodes => List.unmodifiable(_events);

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

  @visibleForTesting
  void captureCode(String code) {
    if (!enabled.value || !RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(code)) return;
    if (_events.length >= maxEvents) _events.removeAt(0);
    _events.add(code);
  }

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
    if (_events.isEmpty) {
      status.value = 'No Night Mode errors captured yet';
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
