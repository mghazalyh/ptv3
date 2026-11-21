import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../../../models/stream/stream_model.dart';
import '../../addon/addon_manager.dart';
import '../player_settings.dart';
import 'live_stream_detector.dart';

typedef LiveSourceRefresh = Future<List<StreamSource>> Function();

/// Privacy-safe HTTP/HLS probe categories. No request URL, playlist text,
/// token, header value, response body, or raw exception is ever stored.
class LiveSourceProbe {
  const LiveSourceProbe({
    required this.phase,
    required this.outcome,
    required this.elapsedMs,
    required this.headerCount,
    this.httpStatus,
    this.bodyBytes,
    this.mimeKind,
    this.isMaster,
    this.segmentCount,
  });

  final String phase;
  final String outcome;
  final int elapsedMs;
  final int headerCount;
  final int? httpStatus;
  final int? bodyBytes;
  final String? mimeKind;
  final bool? isMaster;
  final int? segmentCount;
}

class _LiveSourceHealth {
  int failures = 0;
  int recoveries = 0;
  DateTime? blockedUntil;
}

/// Manages backup links only for a single Stremio live channel. This does not
/// modify global stream ranking or movie/episode source selection.
class LiveSourceManager {
  LiveSourceManager({
    required this.channelId,
    required this.addonName,
    required StreamSource initial,
    Iterable<StreamSource> initialSources = const <StreamSource>[],
    LiveSourceRefresh? refreshOverride,
  }) : _refreshOverride = refreshOverride {
    addSources(<StreamSource>[initial, ...initialSources]);
  }

  @visibleForTesting
  static http.Client? probeClientOverride;

  LiveSourceProbe? _lastProbe;
  String? _lastProbeSource;
  String? _lastSegmentSource;
  Uri? _lastSegmentUri;

  LiveSourceProbe? latestProbeFor(StreamSource source) =>
      source.url == _lastProbeSource ? _lastProbe : null;

  void _captureProbe(StreamSource source, LiveSourceProbe probe) {
    _lastProbeSource = source.url; // In memory only; not serialized.
    _lastProbe = probe;
  }

  void _rememberFirstSegment(
      StreamSource source, Uri mediaUri, String body) {
    _lastSegmentSource = source.url;
    _lastSegmentUri = null;
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final absolute = mediaUri.resolve(line);
      if (LiveStreamDetector.isHttpMedia(absolute.toString())) {
        _lastSegmentUri = absolute;
        break;
      }
    }
  }

  static String _mimeKind(String? raw) {
    final kind = (raw ?? '').toLowerCase();
    if (kind.contains('mpegurl') || kind.contains('m3u')) return 'hls';
    if (kind.contains('html')) return 'html';
    if (kind.contains('json')) return 'json';
    if (kind.contains('video')) return 'video';
    if (kind.contains('octet-stream')) return 'binary';
    return 'other';
  }

  /// Identical headers for initial probing and MPV reconnection.
  static Map<String, String> requestHeaders(StreamSource source) {
    final headers = PlayerSettings.resolveStreamHeaders(
        source.url ?? '', source.headers);
    final proxy = source.behaviorHints?['proxyHeaders'];
    if (proxy is Map && proxy['request'] is Map) {
      for (final entry in (proxy['request'] as Map).entries) {
        if (entry.value != null) {
          headers[entry.key.toString()] = entry.value.toString();
        }
      }
    }
    return headers;
  }

  final String channelId;
  final String addonName;
  final LiveSourceRefresh? _refreshOverride;
  final Map<String, StreamSource> _sources = <String, StreamSource>{};
  final Map<String, _LiveSourceHealth> _health = <String, _LiveSourceHealth>{};

  String? keyOf(StreamSource source) {
    if (!LiveStreamDetector.isHttpMedia(source.url) ||
        (source.infoHash?.trim().isNotEmpty ?? false)) return null;
    return source.url!.trim();
  }

  void addSources(Iterable<StreamSource> sources) {
    for (final source in sources) {
      // Only accept the same installed provider's live stream candidates.
      if (source.addonName.toLowerCase() != addonName.toLowerCase()) continue;
      final key = keyOf(source);
      if (key != null) {
        _sources[key] = source;
        // Signed live links can change on every refresh; bound in-memory
        // candidate growth without losing the current source on reopen.
        while (_sources.length > 36) {
          final oldest = _sources.keys.first;
          _sources.remove(oldest);
          _health.remove(oldest);
        }
      }
    }
  }

  int get sourceCount => _sources.length;

  bool hasViableBackup(StreamSource current, DateTime at) =>
      backups(current, at).isNotEmpty;

  void failed(StreamSource source, DateTime at) {
    final key = keyOf(source);
    if (key == null) return;
    final health = _health.putIfAbsent(key, _LiveSourceHealth.new);
    health.failures++;
    if (health.failures >= 2) {
      final duration = (health.failures * 20).clamp(40, 180);
      health.blockedUntil = at.add(Duration(seconds: duration.toInt()));
    }
  }

  void recovered(StreamSource source) {
    final key = keyOf(source);
    if (key == null) return;
    final health = _health.putIfAbsent(key, _LiveSourceHealth.new);
    health.recoveries++;
    health.failures = 0;
    health.blockedUntil = null;
  }

  List<StreamSource> backups(StreamSource current, DateTime at) {
    final currentKey = keyOf(current);
    final candidates = _sources.entries
        .where((e) => e.key != currentKey &&
            !(_health[e.key]?.blockedUntil?.isAfter(at) ?? false))
        .map((e) => e.value)
        .toList();
    candidates.sort((a, b) => _score(b).compareTo(_score(a)));
    return candidates;
  }

  int _score(StreamSource source) {
    final key = keyOf(source);
    final health = key == null ? null : _health[key];
    var score = (health?.recoveries ?? 0) * 18 -
        (health?.failures ?? 0) * 45;
    if (LiveStreamDetector.isHlsUrl(source.url)) score += 4;
    if ((source.description ?? '').contains('tested working')) score += 12;
    if ((source.description ?? '').contains('✓')) score += 6;
    return score;
  }

  Future<int> refresh() async {
    if (channelId.trim().isEmpty) return 0;
    try {
      List<StreamSource> refreshed;
      if (_refreshOverride != null) {
        refreshed = await _refreshOverride()
            .timeout(const Duration(seconds: 14));
      } else {
        final installed = AddonManager.instance.activeStreamAddons;
        final matching = installed.where((addon) =>
            addon.manifest.name.toLowerCase() == addonName.toLowerCase() &&
            addon.manifest.supportsRequest('stream', 'tv', channelId));
        if (matching.isEmpty) return 0;
        final addon = matching.first;
        final endpoint = Uri.parse(
            '${addon.baseUrl}/stream/tv/${Uri.encodeComponent(channelId)}.json');
        final response = await http.get(endpoint, headers: const {
          'Accept': 'application/json',
          'User-Agent': 'PlayTorrio-LiveTV/1.0',
          'Cache-Control': 'no-cache',
        }).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200 || response.bodyBytes.length > 1048576) {
          return 0;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['streams'] is! List) return 0;
        refreshed = <StreamSource>[];
        for (final raw in decoded['streams'] as List) {
          if (raw is! Map) continue;
          try {
            refreshed.add(StreamSource.fromJson(
                Map<String, dynamic>.from(raw), addon.manifest.name));
          } catch (_) {
            // One malformed candidate cannot invalidate the response.
          }
        }
      }
      addSources(refreshed);
      return refreshed.length;
    } catch (_) {
      // Network failure, expired addon link, and invalid JSON all fail open.
      return 0;
    }
  }

  /// HEAD is an optional sanity check. Many IPTV providers reject HEAD even
  /// when GET is valid, so only explicit absent/HTML responses are rejected.
  Future<bool> seemsPlayable(StreamSource source) async {
    final uri = Uri.tryParse(source.url ?? '');
    final timer = Stopwatch()..start();
    if (uri == null || !LiveStreamDetector.isHttpMedia(source.url) ||
        (source.infoHash?.trim().isNotEmpty ?? false) ||
        uri.path.toLowerCase().endsWith('.html')) {
      _captureProbe(source, LiveSourceProbe(
        phase: 'head', outcome: 'unsupported_source',
        elapsedMs: timer.elapsedMilliseconds, headerCount: 0));
      return false;
    }
    final headers = requestHeaders(source);
    try {
      final response = await (probeClientOverride?.head(uri, headers: headers) ??
          http.head(uri, headers: headers)).timeout(const Duration(seconds: 4));
      final mime = _mimeKind(response.headers['content-type']);
      final code = response.statusCode;
      final blocked = code == 401 || code == 403 ||
          code == 404 || code == 410 || code >= 500 ||
          (code == 200 && mime == 'html');
      // A 200 HEAD still says nothing about a master playlist's children.
      // Validate the HLS media playlist when possible before failover.
      if (LiveStreamDetector.isHlsUrl(source.url) &&
          (blocked || code == 200)) {
        final manifest = await inspectPlaylist(source);
        return manifest != null;
      }
      _captureProbe(source, LiveSourceProbe(
        phase: 'head', outcome: blocked ? 'rejected' : 'provisional',
        httpStatus: code, mimeKind: mime,
        elapsedMs: timer.elapsedMilliseconds, headerCount: headers.length));
      return !blocked;
    } on TimeoutException {
      _captureProbe(source, LiveSourceProbe(
        phase: 'head', outcome: 'timeout',
        elapsedMs: timer.elapsedMilliseconds, headerCount: headers.length));
    } catch (error) {
      debugPrint('[LiveTV] HEAD probe failed: ${error.runtimeType}');
      _captureProbe(source, LiveSourceProbe(
        phase: 'head', outcome: 'network_error',
        elapsedMs: timer.elapsedMilliseconds, headerCount: headers.length));
    }
    // HEAD unsupported: never reject a working GET-only stream.
    return true;
  }

  Future<LivePlaylistSnapshot?> inspectPlaylist(StreamSource source) async {
    if (!LiveStreamDetector.isHlsUrl(source.url)) return null;
    final uri = Uri.tryParse(source.url ?? '');
    if (uri == null) return null;
    final timer = Stopwatch()..start();
    final headers = requestHeaders(source);
    try {
      final response = await (probeClientOverride?.get(uri, headers: headers) ??
          http.get(uri, headers: headers)).timeout(const Duration(seconds: 6));
      final bytes = response.bodyBytes.length;
      final mime = _mimeKind(response.headers['content-type']);
      if (response.statusCode != 200 || bytes > 262144) {
        _captureProbe(source, LiveSourceProbe(
          phase: 'playlist',
          outcome: response.statusCode != 200 ? 'http_status' : 'oversized',
          httpStatus: response.statusCode, bodyBytes: bytes,
          mimeKind: mime, elapsedMs: timer.elapsedMilliseconds,
          headerCount: headers.length));
        return null;
      }
      final snapshot = LivePlaylistSnapshot.parse(response.body);
      if (snapshot == null) {
        _captureProbe(source, LiveSourceProbe(
          phase: 'playlist', outcome: 'invalid_manifest',
          httpStatus: response.statusCode, bodyBytes: bytes,
          mimeKind: mime, elapsedMs: timer.elapsedMilliseconds,
          headerCount: headers.length));
        return null;
      }
      if (snapshot.isMaster) {
        // HTTP 200 for an HLS master playlist does not imply its referenced
        // media playlists can be fetched. This was missing in Build 251.
        final variants = response.body.split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('#'))
            .take(3);
        for (final variant in variants) {
          final child = uri.resolve(variant);
          if (child.scheme != 'https' && child.scheme != 'http') continue;
          try {
            final nested = await (probeClientOverride?.get(
                child, headers: headers) ??
                http.get(child, headers: headers))
                .timeout(const Duration(seconds: 5));
            final childSnapshot = nested.statusCode == 200 &&
                    nested.bodyBytes.length <= 262144
                ? LivePlaylistSnapshot.parse(nested.body) : null;
            _captureProbe(source, LiveSourceProbe(
              phase: 'variant',
              outcome: childSnapshot != null && !childSnapshot.isMaster
                  ? 'ok' : nested.statusCode != 200
                  ? 'http_status' : 'invalid_manifest',
              httpStatus: nested.statusCode,
              bodyBytes: nested.bodyBytes.length,
              mimeKind: _mimeKind(nested.headers['content-type']),
              isMaster: childSnapshot?.isMaster,
              segmentCount: nested.body.split('\n').where((line) {
                final clean = line.trim();
                return clean.isNotEmpty && !clean.startsWith('#');
              }).length,
              elapsedMs: timer.elapsedMilliseconds,
              headerCount: headers.length));
            if (childSnapshot != null && !childSnapshot.isMaster) {
              _rememberFirstSegment(source, child, nested.body);
              return childSnapshot;
            }
          } on TimeoutException {
            _captureProbe(source, LiveSourceProbe(
              phase: 'variant', outcome: 'timeout',
              elapsedMs: timer.elapsedMilliseconds,
              headerCount: headers.length));
          } catch (error) {
            debugPrint('[LiveTV] Variant probe failed: ${error.runtimeType}');
            _captureProbe(source, LiveSourceProbe(
              phase: 'variant', outcome: 'network_error',
              elapsedMs: timer.elapsedMilliseconds,
              headerCount: headers.length));
          }
        }
        return null;
      }
      _rememberFirstSegment(source, uri, response.body);
      _captureProbe(source, LiveSourceProbe(
        phase: 'playlist', outcome: 'ok',
        httpStatus: response.statusCode, bodyBytes: bytes,
        mimeKind: mime, isMaster: false,
        segmentCount: response.body.split('\n').where((line) {
          final clean = line.trim();
          return clean.isNotEmpty && !clean.startsWith('#');
        }).length,
        elapsedMs: timer.elapsedMilliseconds,
        headerCount: headers.length));
      return snapshot;
    } on TimeoutException {
      _captureProbe(source, LiveSourceProbe(
        phase: 'playlist', outcome: 'timeout',
        elapsedMs: timer.elapsedMilliseconds, headerCount: headers.length));
      return null;
    } catch (error) {
      debugPrint('[LiveTV] Playlist probe failed: ${error.runtimeType}');
      _captureProbe(source, LiveSourceProbe(
        phase: 'playlist', outcome: 'network_error',
        elapsedMs: timer.elapsedMilliseconds, headerCount: headers.length));
      return null;
    }
  }
  /// Explicit deep diagnosis tests a small range of one media segment. This
  /// is not part of the periodic watchdog: it is invoked by the owner-controlled
  /// GitHub command and never stores segment URLs or authentication values.
  Future<LiveSourceProbe?> inspectFirstSegment(StreamSource source) async {
    final media = await inspectPlaylist(source);
    if (media == null || _lastSegmentSource != source.url ||
        _lastSegmentUri == null) return latestProbeFor(source);
    final started = Stopwatch()..start();
    final client = probeClientOverride ?? http.Client();
    final closeClient = probeClientOverride == null;
    final headers = requestHeaders(source);
    try {
      final request = http.Request('GET', _lastSegmentUri!)
        ..headers.addAll(headers)
        ..headers['Range'] = 'bytes=0-4095';
      final response = await client.send(request)
          .timeout(const Duration(seconds: 7));
      List<int> initial = const <int>[];
      try {
        initial = await response.stream.first
            .timeout(const Duration(seconds: 5));
      } on StateError {
        // Empty segment response.
      }
      final ok = (response.statusCode == 200 ||
          response.statusCode == 206) && initial.isNotEmpty;
      final probe = LiveSourceProbe(
        phase: 'segment', outcome: ok ? 'ok' :
            response.statusCode == 200 || response.statusCode == 206
            ? 'empty_segment' : 'http_status',
        httpStatus: response.statusCode,
        bodyBytes: initial.length,
        mimeKind: _mimeKind(response.headers['content-type']),
        elapsedMs: started.elapsedMilliseconds,
        headerCount: headers.length);
      _captureProbe(source, probe);
      return probe;
    } on TimeoutException {
      final probe = LiveSourceProbe(
        phase: 'segment', outcome: 'timeout',
        elapsedMs: started.elapsedMilliseconds, headerCount: headers.length);
      _captureProbe(source, probe);
      return probe;
    } catch (error) {
      debugPrint('[LiveTV] Segment diagnostic: ${error.runtimeType}');
      final probe = LiveSourceProbe(
        phase: 'segment', outcome: 'network_error',
        elapsedMs: started.elapsedMilliseconds, headerCount: headers.length);
      _captureProbe(source, probe);
      return probe;
    } finally {
      if (closeClient) client.close();
    }
  }

}
