import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// On-device, Live-TV-only HLS transport fallback.
///
/// Some iOS libmpv builds cannot negotiate a CDN's TLS settings even when
/// Dart's native HTTPS stack can fetch that CDN's playlist and media segments.
/// This relay is not used for normal playback: the Live TV coordinator starts
/// it only after a native failure and a successful Dart-side HLS probe.
///
/// URLs and per-source headers remain in memory. MPV sees only a temporary
/// loopback URL; the relay requests playlists, keys and segments through Dart.
class LiveHlsHttpRelay {
  LiveHlsHttpRelay({HttpClient? upstream})
      : _upstream = upstream ?? HttpClient() {
    _upstream.connectionTimeout = const Duration(seconds: 12);
    _upstream.idleTimeout = const Duration(seconds: 25);
    _upstream.autoUncompress = false;
  }

  final HttpClient _upstream;
  final Map<String, _LiveRelayTarget> _targets =
      <String, _LiveRelayTarget>{};
  final String _secret = List<int>.generate(
    20, (_) => Random.secure().nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  HttpServer? _server;
  bool _closed = false;
  int _nextId = 0;

  /// A temporary localhost URL representing the selected origin HLS stream.
  Future<Uri> expose(Uri original, Map<String, String> headers) async {
    if (_closed) throw StateError('Live HLS relay is closed');
    if (!_isHttp(original)) {
      throw const FormatException('Live HLS URL must use HTTP or HTTPS');
    }
    if (_server == null) {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4, 0, shared: false,
      );
      if (_closed) {
        await server.close(force: true);
        throw StateError('Live HLS relay was closed during startup');
      }
      _server = server;
      server.listen((request) {
        unawaited(_serve(request));
      }, onError: (Object error, StackTrace stack) {
        // A remote network failure never brings down the player process.
      });
    }
    return _register(original, headers);
  }

  static bool _isHttp(Uri uri) =>
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty && uri.userInfo.isEmpty;

  Uri _register(Uri target, Map<String, String> headers,
      {String? extensionHint}) {
    if (!_isHttp(target)) {
      throw const FormatException('Unsupported HLS child URI');
    }
    final id = (++_nextId).toRadixString(36);
    _targets[id] = _LiveRelayTarget(
      target, Map<String, String>.unmodifiable(headers),
    );
    // Keep enough entries for an entire lengthy live session, but prevent
    // a playlist that changes indefinitely from growing memory without bound.
    while (_targets.length > 8192) {
      _targets.remove(_targets.keys.first);
    }
    final basename = target.pathSegments.isNotEmpty
        ? target.pathSegments.last.toLowerCase() : '';
    final suffix = basename.contains('.')
        ? basename.split('.').last : '';
    const permitted = <String>{
      'm3u8', 'm3u', 'ts', 'm4s', 'mp4', 'aac', 'mp3', 'm4a',
      'vtt', 'webvtt', 'ac3', 'eac3', 'bin', 'key',
    };
    final extension = permitted.contains(suffix) ? suffix :
        permitted.contains(extensionHint) ? extensionHint! : 'ts';
    // FFmpeg HLS demuxers inspect segment extensions even for media fetched
    // from HTTP. Keep a safe local suffix while hiding the upstream URL.
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: _server!.port,
      pathSegments: <String>['live-hls', _secret, '$id.$extension'],
    );
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final parts = request.uri.pathSegments;
      if (parts.length != 3 || parts[0] != 'live-hls' ||
          parts[1] != _secret || _closed) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final token = parts[2].split('.').first;
      final target = _targets[token];
      if (target == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }

      final fetched = await _fetch(
        target.uri, target.headers, request,
      );
      final upstream = fetched.response;
      response.statusCode = upstream.statusCode;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final range = upstream.headers.value(HttpHeaders.contentRangeHeader);
      if (range != null) {
        response.headers.set(HttpHeaders.contentRangeHeader, range);
      }
      final acceptRanges =
          upstream.headers.value(HttpHeaders.acceptRangesHeader);
      if (acceptRanges != null) {
        response.headers.set(HttpHeaders.acceptRangesHeader, acceptRanges);
      }
      final type = upstream.headers.value(HttpHeaders.contentTypeHeader);
      response.headers.set(HttpHeaders.contentTypeHeader,
          type ?? 'application/octet-stream');

      if (request.method == 'HEAD') {
        await upstream.drain<void>();
        return;
      }
      final isPlaylist = upstream.statusCode == HttpStatus.ok &&
          (_isPlaylistUri(fetched.uri) ||
              request.uri.path.toLowerCase().endsWith('.m3u8') ||
              (type?.toLowerCase().contains('mpegurl') ?? false));
      if (isPlaylist) {
        final bytes = await _readPlaylist(upstream);
        final raw = utf8.decode(bytes, allowMalformed: true);
        if (!raw.trimLeft().startsWith('#EXTM3U')) {
          // Do not forge a valid playlist from HTML or CDN error bodies.
          response.add(bytes);
          return;
        }
        response.headers.set(HttpHeaders.contentTypeHeader,
            'application/vnd.apple.mpegurl');
        response.add(utf8.encode(_rewrite(raw, fetched.uri, target.headers)));
      } else {
        // Segment bytes, encryption keys, and partial Range responses must
        // remain binary identical to what the provider returned.
        await response.addStream(upstream);
      }
    } catch (error) {
      try {
        response.statusCode = HttpStatus.badGateway;
        response.headers.set(HttpHeaders.contentTypeHeader, 'text/plain');
        response.write('Live source unavailable');
      } catch (_) {
        // A disconnected native player may have already closed the socket.
      }
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  static bool _isPlaylistUri(Uri uri) {
    final path = uri.path.toLowerCase();
    return path.endsWith('.m3u8') || path.endsWith('.m3u');
  }

  Future<Uint8List> _readPlaylist(HttpClientResponse source) async {
    final result = BytesBuilder(copy: false);
    await for (final bytes in source) {
      if (result.length + bytes.length > 524288) {
        throw const FormatException('HLS playlist is too large');
      }
      result.add(bytes);
    }
    return result.takeBytes();
  }

  String _rewrite(
      String playlist, Uri base, Map<String, String> headers) {
    final tagUri = RegExp(r'URI="([^"]+)"');
    final lines = playlist.split('\n');
    var nextUriIsPlaylist = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      if (line.startsWith('#')) {
        if (line.startsWith('#EXT-X-STREAM-INF:')) {
          nextUriIsPlaylist = true;
        }
        final tagHint = line.startsWith('#EXT-X-MEDIA:') ||
                line.startsWith('#EXT-X-I-FRAME-STREAM-INF:')
            ? 'm3u8'
            : line.startsWith('#EXT-X-KEY:') ||
                    line.startsWith('#EXT-X-SESSION-KEY:')
                ? 'bin'
                : line.startsWith('#EXT-X-MAP:')
                    ? 'mp4' : null;
        lines[i] = line.replaceAllMapped(tagUri, (match) {
          final raw = match.group(1);
          if (raw == null) return match.group(0)!;
          final resolved = base.resolve(raw);
          return _isHttp(resolved)
              ? 'URI="${_register(resolved, headers,
                    extensionHint: tagHint)}"'
              : match.group(0)!;
        });
      } else {
        final raw = line.trim();
        final resolved = base.resolve(raw);
        if (_isHttp(resolved)) {
          lines[i] = _register(resolved, headers,
              extensionHint: nextUriIsPlaylist ? 'm3u8' : 'ts').toString();
        }
        nextUriIsPlaylist = false;
      }
    }
    return lines.join('\n');
  }

  Future<({HttpClientResponse response, Uri uri})> _fetch(
    Uri initial, Map<String, String> headers, HttpRequest local,
  ) async {
    var current = initial;
    final visited = <Uri>{};
    for (var i = 0; i < 7; i++) {
      if (!visited.add(current)) {
        throw const FormatException('HLS redirect cycle');
      }
      final outgoing = await _upstream
          .openUrl(local.method, current)
          .timeout(const Duration(seconds: 12));
      outgoing.followRedirects = false;
      headers.forEach((key, value) {
        final lower = key.toLowerCase();
        if (lower == 'host' || lower == 'connection' ||
            lower == 'content-length' || lower == 'transfer-encoding' ||
            lower == 'accept-encoding') return;
        outgoing.headers.set(key, value);
      });
      outgoing.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      for (final name in <String>[
        HttpHeaders.rangeHeader,
        HttpHeaders.ifRangeHeader,
        HttpHeaders.ifNoneMatchHeader,
        HttpHeaders.ifModifiedSinceHeader,
      ]) {
        final value = local.headers.value(name);
        if (value != null) outgoing.headers.set(name, value);
      }
      final received = await outgoing.close()
          .timeout(const Duration(seconds: 18));
      if (<int>{301, 302, 303, 307, 308}
          .contains(received.statusCode)) {
        final location = received.headers.value(HttpHeaders.locationHeader);
        await received.drain<void>();
        if (location == null || location.trim().isEmpty) {
          throw const FormatException('HLS redirect without destination');
        }
        final destination = current.resolve(location.trim());
        if (!_isHttp(destination)) {
          throw const FormatException('Unsupported HLS redirect');
        }
        current = destination;
        continue;
      }
      return (response: received, uri: current);
    }
    throw const FormatException('HLS exceeded redirect limit');
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _targets.clear();
    await _server?.close(force: true);
    _server = null;
    _upstream.close(force: true);
  }
}

class _LiveRelayTarget {
  const _LiveRelayTarget(this.uri, this.headers);

  final Uri uri;
  final Map<String, String> headers;
}
