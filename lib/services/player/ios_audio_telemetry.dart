import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/stream/stream_model.dart';
import '../my_list/github_library_cloud.dart';
import 'audio_language_priority.dart';
import '../stream/source_content_identity.dart';
import '../stream/watch_source_preferences.dart';
import 'player_diagnostic_codes.dart';
import 'playback_metric_sanitizer.dart';
import 'private_diagnostic_log_path.dart';

/// Owner-enabled diagnostics for named media, ranked streams and native audio.
/// Authentication secrets and signed URLs are not needed for diagnosis.
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
  static const maxSourceTrace = 160;
  static const maxRankedSources = 300;
  static const playbackSampleSeconds = 5;
  static const _minUploadInterval = Duration(seconds: 30);

  /// Non-identifying display class, never a hardware ID or model.
  @visibleForTesting
  static String deviceClass() {
    try {
      final views = ui.PlatformDispatcher.instance.views;
      if (views.isEmpty) return 'unknown';
      final view = views.first;
      final ratio = view.devicePixelRatio;
      if (!ratio.isFinite || ratio <= 0) return 'unknown';
      final side = view.physicalSize.shortestSide / ratio;
      if (!side.isFinite || side <= 0) return 'unknown';
      return side < 600 ? 'phone' : 'tablet';
    } catch (_) {
      return 'unknown';
    }
  }
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
  final List<Map<String, Object?>> _sourceTrace = [];
  final Map<String, Object?> _mediaContext = {};
  String? _sourceSessionId;
  bool _loaded = false;
  bool _uploading = false;
  DateTime? _lastUpload;
  int _counter = 0;

  bool get isActive => (Platform.isIOS || forceTestPlatform) && enabled.value;
  @visibleForTesting
  List<Map<String, Object?>> get capturedSourceTrace => List.unmodifiable(_sourceTrace);
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
      _sourceTrace.clear();
      _mediaContext.clear();
      _sourceSessionId = null;
      status.value = 'iOS audio telemetry OFF';
    } else {
      status.value = 'Ready to send private Night Mode diagnostics';
    }
  }


  /// Preserve actual titles and release filenames; omit authenticated links.
  static String? _safeText(String? raw, {int limit = 1500}) {
    if (raw == null || raw.trim().isEmpty) return null;
    final text = raw
        .replaceAll(RegExp(r'(?:https?://|magnet:\?)[^\s\r\n]+',
            caseSensitive: false), '[url-omitted]')
        .replaceAll(RegExp(
            r'(?:(?:token|api[_-]?key|password|secret|authorization|cookie)'
            r'\s*[:=]\s*)[^\s\r\n]+', caseSensitive: false),
            '[credential-omitted]')
        .trim();
    return text.length <= limit ? text : text.substring(0, limit);
  }

  void _trace(String action, Map<String, Object?> details) {
    if (!isActive) return;
    _sourceSessionId ??= DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    if (_sourceTrace.length >= maxSourceTrace) _sourceTrace.removeAt(0);
    _sourceTrace.add(<String, Object?>{
      'utc': DateTime.now().toUtc().toIso8601String(),
      'sessionId': _sourceSessionId,
      'action': action,
      ...details,
    });
  }

  void beginSourceSession({
    required String title, required String mediaId, required String type,
    String? episodeTitle, int? year, int? season, int? episode,
  }) {
    if (!isActive) return;
    _sourceSessionId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    _sourceTrace.clear();
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
    _trace('source_session_started',
        <String, Object?>{'media': Map<String, Object?>.of(_mediaContext)});
  }

  Map<String, Object?> _sourceDetails(StreamSource source,
      {Map<String, bool> verified = const {}, int? season, int? episode}) {
    final languages = source.behaviorHints?['audioLanguages'];
    return <String, Object?>{
      'addon': _safeText(source.addonName),
      'releaseFilename': _safeText(source.title),
      'sourceName': _safeText(source.name),
      'description': _safeText(source.description),
      'infoHash': _safeText(source.infoHash),
      'fileIndex': source.fileIdx,
      'resolution': source.quality,
      'codec': source.codec,
      'fileSizeBytes': source.sizeBytes,
      'declaredAudioLanguages': languages is List
          ? languages.take(30).map((v) => _safeText(v.toString(), limit: 40))
              .whereType<String>().toList()
          : <String>[],
      'inferredAudioRank': AudioLanguagePriority.sourceAudioRank(source),
      'audioEvidence': 'stremio_release_and_audio_hints',
      'cacheTier': WatchSourceEngine.cacheTier(source, verified,
          season: season, episode: episode),
    };
  }

  void captureSourceRanking({
    required List<StreamSource> sources,
    required List<StreamSource> sorted,
    required String title,
    required WatchSourceProfile profile,
    Map<String, bool> verified = const {},
    int? year, int? season, int? episode,
    String? sizeFilter, String? addonFilter,
  }) {
    if (!isActive) return;
    final ranked = <Map<String, Object?>>[];
    for (var i = 0; i < sorted.length && i < maxRankedSources; i++) {
      final source = sorted[i];
      ranked.add(<String, Object?>{
        'rank': i + 1,
        'identityVerdict': SourceContentIdentity.assess(source,
            title: title, year: year, season: season, episode: episode).name,
        ..._sourceDetails(source, verified: verified,
            season: season, episode: episode),
      });
    }
    final rejected = sources.where((source) =>
        SourceContentIdentity.assess(source, title: title,
            year: year, season: season, episode: episode) ==
        SourceIdentityVerdict.rejected).toList();
    _trace('source_ranking_completed', <String, Object?>{
      'requireEnglishAudio': profile.requireEnglishAudio,
      'requestedTitle': _safeText(title),
      'candidateCount': sources.length,
      'visibleCount': sorted.length,
      'reportedRankCount': ranked.length,
      'rejectedCount': rejected.length,
      'preferEnglishAudio': profile.preferEnglishAudio,
      'cachePolicy': profile.cachePolicy,
      'allowUnknown': profile.allowUnknown,
      'sorting': profile.sorting.map((rule) => rule.toJson()).toList(),
      'sizeFilter': sizeFilter,
      'addonFilter': _safeText(addonFilter),
      'rankedSources': ranked,
      'rejectedSources': rejected.take(100).map((source) =>
          _sourceDetails(source, verified: verified,
              season: season, episode: episode)).toList(),
    });
  }

  void captureSourceSelection({
    required String action, required StreamSource source,
    required String title, String? mediaId, String? episodeTitle,
    int? year, int? season, int? episode, int? visibleRank,
  }) {
    if (!isActive) return;
    if (_mediaContext.isEmpty) {
      beginSourceSession(title: title, mediaId: mediaId ?? title,
          type: season == null ? 'movie' : 'series',
          year: year, season: season, episode: episode,
          episodeTitle: episodeTitle);
    }
    _trace(action, <String, Object?>{
      'requestedTitle': _safeText(title),
      'mediaId': _safeText(mediaId),
      'episodeTitle': _safeText(episodeTitle),
      'year': year, 'season': season, 'episode': episode,
      'visibleRank': visibleRank,
      'identityVerdict': SourceContentIdentity.assess(source,
          title: title, year: year, season: season, episode: episode).name,
      ..._sourceDetails(source, season: season, episode: episode),
    });
  }

  void captureAudioTracks({
    required String stage, required List<Map<String, Object?>> tracks,
    int? selectedTrackId, bool manual = false, bool loading = false,
  }) {
    if (!isActive) return;
    _trace('audio_tracks_observed', <String, Object?>{
      'stage': stage, 'selectedTrackId': selectedTrackId,
      'manualSelection': manual, 'playerLoading': loading,
      'trackCount': tracks.length,
      'tracks': tracks.take(40).map((item) {
        final id = item['id'];
        final number = id is int ? id : int.tryParse(id?.toString() ?? '');
        final language = _safeText(item['language']?.toString(), limit: 80);
        final title = _safeText(item['title']?.toString(), limit: 400);
        return <String, Object?>{
          'id': number,
          'language': language, 'title': title,
          'channels': item['channels'],
          'codec': _safeText(item['codec']?.toString(), limit: 80),
          'isDefault': item['isDefault'] == true,
          'selected': selectedTrackId != null && number == selectedTrackId,
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
    _trace(action, <String, Object?>{
      'requestedTrackId': requestedTrackId,
      'actualTrackId': actualTrackId,
      'manual': manual,
      'reason': _safeText(reason, limit: 120),
    });
  }

  /// Convert native errors to bounded diagnostic codes.
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
    ...PlayerDiagnosticCodes.events,
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
    Map<String, Object?> properties, {
      bool buffering = false, int? selectedAudioTrackId,
    }
  ) {
    if (!isActive) return;
    final sample = <String, Object>{
      'utc': DateTime.now().toUtc().toIso8601String(),
      'buffering': buffering,
      if (selectedAudioTrackId != null) 'selectedAudioTrackId': selectedAudioTrackId,
    };
    sample.addAll(PlaybackMetricSanitizer.fromProperties(properties));
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
    }
    // A single severe raster stall is perceptible even when no video frame
    // drops. Repeated slow Flutter builds also disrupt iPad composition.
    // Diagnostics remain strictly opt-in; don't apply Windows GPU scaling.
    final slowRaster = sample['flutterSlowRasterFrames'] as int? ?? 0;
    final worstRasterMs = sample['flutterWorstRasterMs'] as int? ?? 0;
    final slowBuild = sample['flutterSlowBuildFrames'] as int? ?? 0;
    if (slowRaster >= 2 ||
        (slowRaster >= 1 && worstRasterMs >= 75) ||
        slowBuild >= 3) {
      captureCode('flutter_frame_stutter');
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
      PrivateDiagnosticLogPath.forTimestamp(
        prefix: prefix, timestamp: time, sequence: sequence);

  Future<String?> _accessToken() async {
    if (_tokenProvider != null) return _tokenProvider();
    await GitHubLibraryCloud.instance.initialize();
    return GitHubLibraryCloud.instance.progressAccessToken;
  }

  /// Owner-enabled private upload of named source, audio and MPV diagnostics.
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
    if (_events.isEmpty && _performanceSamples.isEmpty && _sourceTrace.isEmpty) {
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
      'playback_sample', 'sync_failure', 'subtitle_failure', 'source_failure',
      'addon_failure', 'source_discovery', 'source_selected',
    }.contains(reason) ? reason : 'manual';
    final sourceTraceAtUpload = List<Map<String, Object?>>.from(_sourceTrace);
    final report = <String, Object>{
      'schema': 2,
      'kind': 'ios_playback_source_audio_developer_diagnostic',
      'timestampUtc': now.toIso8601String(),
      'platform': 'ios',
      'deviceClass': deviceClass(),
      'appVersion': '1.1.15',
      'buildRun': buildRun,
      'buildCommit': buildCommit,
      'reason': safeReason,
      'filterCandidates': const ['acompressor', 'compand'],
      'nativeErrorCodes': List<String>.from(_events),
      'audio': safeAudioFields(audio),
      'sourceSessionId': _sourceSessionId ?? '',
      'mediaContext': Map<String, Object?>.from(_mediaContext),
      'sourceTrace': sourceTraceAtUpload,
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
          'message': 'diagnostics(ios): named source and audio language trace',
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
      // Preserve events recorded while an upload was in progress.
      _sourceTrace.removeWhere((entry) => sourceTraceAtUpload.contains(entry));
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
