import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A configurable on-device HTTP/DNS probe. No third-party proxy is involved.
/// It captures the actual iPad's DNS lookup, headers, redirect chain, status,
/// timings and a bounded response excerpt for debugging Stremio/HLS endpoints.
abstract final class IosNetworkDiagnosticProbe {
  static const maxResponseBytes = 4096;

  static Future<Map<String, Object?>> run(Map<String, dynamic> args,
      {HttpClient? transport}) async {
    final total = Stopwatch()..start();
    if (args.keys.any((key) => !const <String>{
      'url', 'method', 'headers', 'timeoutSeconds', 'maxBytes',
      'followRedirects',
    }.contains(key))) {
      return {'accepted': false, 'reason': 'unknown_http_probe_option'};
    }
    final url = args['url'];
    final method = args['method'] ?? 'GET';
    final timeout = args['timeoutSeconds'] ?? 12;
    final limit = args['maxBytes'] ?? 2048;
    final followRedirects = args['followRedirects'] ?? true;
    final rawHeaders = args['headers'];
    if (url is! String || url.length > 4096 ||
        !const <String>{'GET', 'HEAD'}.contains(method) ||
        timeout is! int || timeout < 1 || timeout > 30 ||
        limit is! int || limit < 0 || limit > maxResponseBytes ||
        followRedirects is! bool ||
        rawHeaders != null && rawHeaders is! Map) {
      return {'accepted': false, 'reason': 'invalid_http_probe_request'};
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const <String>{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return {'accepted': false, 'reason': 'invalid_http_probe_url'};
    }
    final headers = <String, String>{};
    if (rawHeaders != null) {
      if (rawHeaders.length > 24) {
        return {'accepted': false, 'reason': 'too_many_request_headers'};
      }
      for (final pair in rawHeaders.entries) {
        if (pair.key is! String || pair.value is! String ||
            (pair.key as String).length > 100 ||
            (pair.value as String).length > 2000) {
          return {'accepted': false, 'reason': 'invalid_request_header'};
        }
        headers[pair.key as String] = pair.value as String;
      }
    }
    final client = transport ?? HttpClient();
    final ownsClient = transport == null;
    client.connectionTimeout = Duration(seconds: timeout);
    final deadline = Duration(seconds: timeout);
    var dnsMs = -1;
    List<String> addresses = [];
    try {
      final dns = Stopwatch()..start();
      try {
        addresses = (await InternetAddress.lookup(uri.host)
            .timeout(deadline)).take(8).map((a) => a.address).toList();
      } catch (error) {
        // DNS failures are useful observations even when a network client
        // can resolve through a different resolver.
        addresses = ['lookup_failed:${error.runtimeType}'];
      }
      dns.stop();
      dnsMs = dns.elapsedMilliseconds;
      final request = await client.openUrl(method as String, uri)
          .timeout(deadline);
      final openedMs = total.elapsedMilliseconds;
      request.followRedirects = followRedirects;
      request.maxRedirects = 7;
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close().timeout(deadline);
      final firstByteMs = total.elapsedMilliseconds;
      final responseHeaders = <String, Object?>{};
      response.headers.forEach((name, values) {
        if (responseHeaders.length >= 32) return;
        responseHeaders[name] = values.take(6).map(
            (value) => value.length > 600 ? value.substring(0, 600) : value)
            .toList();
      });
      final bytes = <int>[];
      if (method == 'GET' && limit > 0) {
        await for (final part in response.timeout(deadline)) {
          final remaining = limit - bytes.length;
          if (remaining <= 0) break;
          bytes.addAll(part.take(remaining));
          if (bytes.length >= limit) break;
        }
      }
      return <String, Object?>{
        'accepted': true,
        'url': url,
        'method': method,
        'status': response.statusCode,
        'reasonPhrase': response.reasonPhrase,
        'contentLength': response.contentLength,
        'contentType': response.headers.contentType?.toString(),
        'responseHeaders': responseHeaders,
        'redirects': response.redirects.map((redirect) =>
            <String, Object?>{
              'status': redirect.statusCode,
              'method': redirect.method,
              'url': redirect.location.toString(),
            }).toList(),
        'finalUri': response.redirects.isEmpty
            ? uri.toString() : response.redirects.last.location.toString(),
        'resolvedAddresses': addresses,
        'dnsMs': dnsMs,
        'connectMs': openedMs,
        'responseHeadersMs': firstByteMs,
        'totalMs': total.elapsedMilliseconds,
        'bytesRead': bytes.length,
        'bodyBase64': base64Encode(bytes),
        'bodyPreview': utf8.decode(bytes.take(1500).toList(),
            allowMalformed: true),
        'responseLimited': limit > 0 && bytes.length >= limit,
      };
    } catch (error) {
      debugPrint('[IosNetworkProbe] ${error.runtimeType}: $error');
      return <String, Object?>{
        'accepted': false,
        'url': url,
        'errorClass': error.runtimeType.toString(),
        'error': error.toString(),
        'dnsMs': dnsMs,
        'resolvedAddresses': addresses,
        'totalMs': total.elapsedMilliseconds,
      };
    } finally {
      if (ownsClient) client.close(force: true);
    }
  }
}
