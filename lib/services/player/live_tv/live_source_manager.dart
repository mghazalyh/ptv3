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
    this.segmentKind,
    this.requestHost,
    this.requestUrlChars,
    this.requestPathChars,
    this.requestQueryChars,
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
  /// Safe media signature category (no payload bytes or URL are stored).
  final String? segmentKind;
  /// Safe request metadata for diagnosing HTTP 414 without exposing URLs,
  /// signed query values, cookies, or authentication tokens.
  final String? requestHost;
  final int? requestUrlChars;
  final int? requestPathChars;
  final int? requestQueryChars;
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

  void _captureProbe(StreamSource source, LiveSourceProbe probe, {
    Uri? requestUri,
  }) {
    // A master playlist can succeed while its child request returns 414.
    // Report only the destination host and URL component lengths, never
    // the actual signed request URI or any credential-bearing query value.
    final target = requestUri ?? Uri.tryParse(source.url ?? '');
    final safeTarget = target != null &&
            (target.scheme == 'https' || target.scheme == 'http')
        ? target : null;
    _lastProbeSource = source.url; // In memory only; never serialized.
    _lastProbe = LiveSourceProbe(
      phase: probe.phase,
      outcome: probe.outcome,
      elapsedMs: probe.elapsedMs,
      headerCount: probe.headerCount,
      httpStatus: probe.httpStatus,
      bodyBytes: probe.bodyBytes,
      mimeKind: probe.mimeKind,
      isMaster: probe.isMaster,
      segmentCount: probe.segmentCount,
      segmentKind: probe.segmentKind,
      requestHost: safeTarget?.host,
      requestUrlChars: safeTarget?.toString().length,
      requestPathChars: safeTarget?.path.length,
      requestQueryChars: safeTarget?.query.length,
    );
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

  @visibleForTesting
  static String segmentSignature(List<int> bytes) {
    if (bytes.isEmpty) return 'empty';
    if (bytes.length >= 8) {
      final marker = String.fromCharCodes(bytes.sublist(4, 8));
      if (marker == 'ftyp' || marker == 'styp' ||
          marker == 'moof' || marker == 'moov') {
        return 'fmp4';
      }
    }
    if (bytes.length >= 188 && bytes.first == 0x47 &&
        (bytes.length < 376 || bytes[188] == 0x47)) return 'mpegts';
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
      return 'id3';
    }
    if (bytes.length >= 2 &&
        bytes[0] == 0xff && (bytes[1] & 0xf0) == 0xf0) return 'aac';
    final prefix = String.fromCharCodes(bytes.take(80))
        .trimLeft().toLowerCase();
    if (prefix.startsWith('<!doctype html') ||
        prefix.startsWith('<html')) return 'html';
    if (prefix.startsWith('{') || prefix.startsWith('[')) return 'json';
    if (prefix.startsWith('#extm3u')) return 'playlist';
    return 'unknown';
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

  /// HLS child paths must be resolved against the final redirected playlist.
  /// http.get() does not expose that URI to callers in all http versions.
  Future<({http.Response response, Uri uri})> _fetchHls(
      Uri initialUri, Map<String, String> headers, Duration timeout) async {
    final client = probeClientOverride ?? http.Client();
    final ownsClient = probeClientOverride == null;
    var current = initialUri;
    final visited = <Uri>{};
    try {
      for (var redirectCount = 0; redirectCount < 6; redirectCount++) {
        if (!visited.add(current)) {
          throw const FormatException('HLS redirect loop');
        }
        final request = http.Request('GET', current)
          ..followRedirects = false
          ..headers.addAll(headers);
        final streamed = await client.send(request).timeout(timeout);
        final status = streamed.statusCode;
        if (status == 301 || status == 302 || status == 303 ||
            status == 307 || status == 308) {
          final location = streamed.headers['location'];
          await streamed.stream.drain<void>().timeout(timeout);
          if (location == null || location.trim().isEmpty) {
            throw const FormatException('HLS redirect without location');
          }
          final destination = current.resolve(location.trim());
          if (!LiveStreamDetector.isHttpMedia(destination.toString())) {
            throw const FormatException('Unsupported HLS redirect');
          }
          current = destination;
          continue;
        }
        return (
          response: await http.Response.fromStream(streamed).timeout(timeout),
          uri: current,
        );
      }
      throw const FormatException('Too many HLS redirects');
    } finally {
      if (ownsClient) client.close();
    }
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
      // HEAD 405/501 only means the method is unsupported; a GET-only
      // channel can still play. Other 4xx (including 414) and 5xx must
      // never be treated as a verified, playable source.
      final methodUnsupported = code == 405 || code == 501;
      final blocked = (code >= 400 && !methodUnsupported) ||
          (code == 200 && mime == 'html');
      // A 200 HEAD still says nothing about a master playlist's children.
      // Validate the HLS media playlist when possible before failover.
      if (LiveStreamDetector.isHlsUrl(source.url) &&
          (blocked || code == 200 || methodUnsupported)) {
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
    // Never declare an HLS link playable on an unverified HEAD failure.
    // A working GET-only provider is still accepted if its manifest parses.
    if (LiveStreamDetector.isHlsUrl(source.url)) {
      return await inspectPlaylist(source) != null;
    }
    return true;
  }

  Future<LivePlaylistSnapshot?> inspectPlaylist(StreamSource source) async {
    if (!LiveStreamDetector.isHlsUrl(source.url)) return null;
    final uri = Uri.tryParse(source.url ?? '');
    if (uri == null) return null;
    final timer = Stopwatch()..start();
    final headers = requestHeaders(source);
    try {
      final fetched = await _fetchHls(
          uri, headers, const Duration(seconds: 6));
      final response = fetched.response;
      final playlistUri = fetched.uri;
      final bytes = response.bodyBytes.length;
      final mime = _mimeKind(response.headers['content-type']);
      if (response.statusCode != 200 || bytes > 262144) {
        _captureProbe(source, LiveSourceProbe(
          phase: 'playlist',
          outcome: response.statusCode != 200 ? 'http_status' : 'oversized',
          httpStatus: response.statusCode, bodyBytes: bytes,
          mimeKind: mime, elapsedMs: timer.elapsedMilliseconds,
          headerCount: headers.length), requestUri: playlistUri);
        return null;
      }
      final snapshot = LivePlaylistSnapshot.parse(response.body);
      if (snapshot == null) {
        _captureProbe(source, LiveSourceProbe(
          phase: 'playlist', outcome: 'invalid_manifest',
          httpStatus: response.statusCode, bodyBytes: bytes,
          mimeKind: mime, elapsedMs: timer.elapsedMilliseconds,
          headerCount: headers.length), requestUri: playlistUri);
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
          final child = playlistUri.resolve(variant);
          if (child.scheme != 'https' && child.scheme != 'http') continue;
          try {
            final nestedFetch = await _fetchHls(
                child, headers, const Duration(seconds: 5));
            final nested = nestedFetch.response;
            final effectiveChild = nestedFetch.uri;
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
              headerCount: headers.length), requestUri: effectiveChild);
            if (childSnapshot != null && !childSnapshot.isMaster) {
              _rememberFirstSegment(source, effectiveChild, nested.body);
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
      _rememberFirstSegment(source, playlistUri, response.body);
      _captureProbe(source, LiveSourceProbe(
        phase: 'playlist', outcome: 'ok',
        httpStatus: response.statusCode, bodyBytes: bytes,
        mimeKind: mime, isMaster: false,
        segmentCount: response.body.split('\n').where((line) {
          final clean = line.trim();
          return clean.isNotEmpty && !clean.startsWith('#');
        }).length,
        elapsedMs: timer.elapsedMilliseconds,
        headerCount: headers.length), requestUri: playlistUri);
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
        initial = (await response.stream.first
            .timeout(const Duration(seconds: 5))).take(4096).toList();
      } on StateError {
        // Empty segment response.
      }
      final signature = segmentSignature(initial);
      final statusOk = response.statusCode == 200 ||
          response.statusCode == 206;
      final payloadOk = initial.isNotEmpty &&
          signature != 'html' && signature != 'json' &&
          signature != 'playlist';
      final probe = LiveSourceProbe(
        phase: 'segment', outcome: !statusOk ? 'http_status' :
            initial.isEmpty ? 'empty_segment' :
            payloadOk ? 'ok' : 'invalid_segment',
        httpStatus: response.statusCode,
        bodyBytes: initial.length,
        mimeKind: _mimeKind(response.headers['content-type']),
        segmentKind: signature,
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
