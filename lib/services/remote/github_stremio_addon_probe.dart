import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Direct, read-only diagnostics for an already-installed Stremio addon.
///
/// This probes manifest.json and one stream/tv resource from the same device
/// that plays the video. It never returns signed URLs, headers, payloads,
/// cookies, bearer tokens, raw exceptions, or playlist contents to GitHub.
class GithubStremioAddonProbe {
  const GithubStremioAddonProbe._();

  static Future<Map<String, Object?>> check({
    required String baseUrl,
    required String addonName,
    required String channelId,
    http.Client? client,
  }) async {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null || base.scheme != 'https' || base.host.isEmpty ||
        base.userInfo.isNotEmpty || channelId.isEmpty ||
        channelId.length > 180) {
      return <String, Object?>{
        'accepted': false,
        'reason': 'invalid_installed_addon_endpoint',
      };
    }

    final ownClient = client == null;
    final transport = client ?? http.Client();
    final cleanBase = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final summary = <String, Object?>{
      'accepted': true,
      'addonName': addonName,
      'addonHost': base.host,
      'channelId': channelId,
    };

    try {
      try {
        final response = await transport.get(
          Uri.parse(cleanBase + '/manifest.json'),
          headers: const <String, String>{'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 12));
        summary['manifestHttpStatus'] = response.statusCode;
        summary['manifestBodyKind'] = _bodyKind(response);
        if (response.bodyBytes.length > 524288) {
          summary['manifestOutcome'] = 'oversized';
        } else if (response.statusCode != 200) {
          summary['manifestOutcome'] = 'http_status';
        } else {
          try {
            final manifest = jsonDecode(response.body);
            final valid = manifest is Map &&
                manifest['id'] is String &&
                (manifest['id'] as String).isNotEmpty &&
                manifest['resources'] is List &&
                manifest['types'] is List;
            summary['manifestValid'] = valid;
            summary['manifestOutcome'] =
                valid ? 'ok' : 'invalid_manifest';
            if (valid) {
              final resources = manifest['resources'] as List;
              final types = manifest['types'] as List;
              final hasStream = resources.any((resource) =>
                  resource == 'stream' ||
                  resource is Map && resource['name'] == 'stream');
              final hasTv = types.contains('tv');
              final prefixes = manifest['idPrefixes'];
              final prefixMatches = prefixes is! List ||
                  prefixes.isEmpty ||
                  prefixes.any((prefix) =>
                      prefix is String && channelId.startsWith(prefix));
              summary['declaresTvStream'] =
                  hasStream && hasTv && prefixMatches;
              summary['declaresStreamResource'] = hasStream;
              summary['declaresTvType'] = hasTv;
              summary['idPrefixMatches'] = prefixMatches;
            }
          } catch (_) {
            summary['manifestValid'] = false;
            summary['manifestOutcome'] = 'invalid_json';
          }
        }
      } on TimeoutException {
        summary['manifestOutcome'] = 'timeout';
      } catch (_) {
        summary['manifestOutcome'] = 'network_error';
      }

      try {
        final response = await transport.get(
          Uri.parse(cleanBase + '/stream/tv/' +
              Uri.encodeComponent(channelId) + '.json'),
          headers: const <String, String>{'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 15));
        summary['streamHttpStatus'] = response.statusCode;
        summary['streamBodyKind'] = _bodyKind(response);
        if (response.bodyBytes.length > 1048576) {
          summary['streamOutcome'] = 'oversized';
        } else if (response.statusCode != 200) {
          summary['streamOutcome'] = 'http_status';
        } else {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is! Map || decoded['streams'] is! List) {
              summary['streamOutcome'] = 'invalid_payload';
            } else {
              final entries = decoded['streams'] as List;
              var urls = 0;
              var torrents = 0;
              var invalid = 0;
              var hls = 0;
              var contextHeaders = 0;
              // Bounded, privacy-safe per-index metadata helps distinguish
              // oversized signed requests from missing playback headers.
              final sources = <Map<String, Object?>>[];
              for (var index = 0; index < entries.length; index++) {
                final entry = entries[index];
                if (entry is! Map) {
                  invalid++;
                  continue;
                }
                final url = entry['url'];
                final hash = entry['infoHash'];
                if (url is String && url.isNotEmpty) {
                  final mediaUri = Uri.tryParse(url);
                  if (mediaUri == null ||
                      (mediaUri.scheme != 'http' &&
                          mediaUri.scheme != 'https') ||
                      mediaUri.host.isEmpty) {
                    invalid++;
                    continue;
                  }
                  urls++;
                  final isHls = mediaUri.path.toLowerCase().endsWith('.m3u8');
                  if (isHls) hls++;
                  final hints = entry['behaviorHints'];
                  final proxy = hints is Map ? hints['proxyHeaders'] : null;
                  final request = proxy is Map ? proxy['request'] : null;
                  final directHeaders = entry['headers'];
                  final hasContext = directHeaders is Map &&
                      directHeaders.isNotEmpty ||
                      request is Map && request.isNotEmpty;
                  if (hasContext) contextHeaders++;
                  if (sources.length < 8) {
                    sources.add(<String, Object?>{
                      'index': index,
                      'host': mediaUri.host,
                      'isHls': isHls,
                      'urlChars': url.length,
                      'pathChars': mediaUri.path.length,
                      'queryChars': mediaUri.query.length,
                      'hasRequestHeaders': hasContext,
                    });
                  }
                } else if (hash is String && hash.isNotEmpty) {
                  torrents++;
                } else {
                  invalid++;
                }
              }
              summary.addAll(<String, Object?>{
                'streamOutcome': 'ok',
                'streamCount': entries.length,
                'directHttpCount': urls,
                'directHlsCount': hls,
                'torrentCount': torrents,
                'invalidSourceCount': invalid,
                'sourcesWithRequestHeaders': contextHeaders,
                'sourceDiagnostics': sources,
              });
            }
          } catch (_) {
            summary['streamOutcome'] = 'invalid_json';
          }
        }
      } on TimeoutException {
        summary['streamOutcome'] = 'timeout';
      } catch (_) {
        summary['streamOutcome'] = 'network_error';
      }
      return summary;
    } finally {
      if (ownClient) transport.close();
    }
  }

  static String _bodyKind(http.Response response) {
    final type = (response.headers['content-type'] ?? '').toLowerCase();
    if (type.contains('json')) return 'json';
    if (type.contains('html')) return 'html';
    if (type.contains('text/plain')) return 'text';
    return 'other';
  }
}
