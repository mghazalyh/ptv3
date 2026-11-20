import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../models/stream/stream_model.dart';
import '../../addon/addon_manager.dart';
import 'live_stream_detector.dart';

typedef LiveSourceRefresh = Future<List<StreamSource>> Function();

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

  final String channelId;
  final String addonName;
  final LiveSourceRefresh? _refreshOverride;
  final Map<String, StreamSource> _sources = <String, StreamSource>{};
  final Map<String, _LiveSourceHealth> _health = <String, _LiveSourceHealth>{};

  String? keyOf(StreamSource source) {
    if (!LiveStreamDetector.isHttpMedia(source.url)) return null;
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
    if (uri == null || !LiveStreamDetector.isHttpMedia(source.url)) {
      return false;
    }
    if (uri.path.toLowerCase().endsWith('.html')) return false;
    try {
      final response = await http.head(uri, headers: source.headers ?? const {})
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 404 || response.statusCode == 410) {
        return false;
      }
      final mime = response.headers['content-type']?.toLowerCase() ?? '';
      if (response.statusCode == 200 && mime.contains('text/html')) {
        return false;
      }
    } catch (_) {
      // HEAD unsupported or geographically unavailable: let MPV decide.
    }
    return true;
  }

  Future<LivePlaylistSnapshot?> inspectPlaylist(StreamSource source) async {
    if (!LiveStreamDetector.isHlsUrl(source.url)) return null;
    final uri = Uri.tryParse(source.url ?? '');
    if (uri == null) return null;
    try {
      final response = await http.get(
        uri, headers: source.headers ?? const <String, String>{},
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 262144) {
        return null;
      }
      return LivePlaylistSnapshot.parse(response.body);
    } catch (_) {
      return null;
    }
  }
}
