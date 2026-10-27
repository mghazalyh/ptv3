import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Shared pacing and rate-limit behavior for PlayTorrio's *progress/history*
/// GitHub Contents uploads. Watchlist sync is deliberately out of scope.
/// A secondary limit is never treated as a normal edit conflict.
class GitHubSyncDeferred implements Exception {
  final DateTime retryAt;
  final String message;
  const GitHubSyncDeferred(this.retryAt, this.message);
  @override
  String toString() => message;
}

abstract final class GitHubSyncGate {
  static DateTime? _blockedUntil;
  static DateTime? _lastWrite;
  static Future<void> _writeQueue = Future<void>.value();
  static const mutationSpacing = Duration(milliseconds: 1200);

  static DateTime? get blockedUntil => _blockedUntil;

  static void checkAllowed() {
    if (_blockedUntil != null && DateTime.now().isBefore(_blockedUntil!)) {
      throw GitHubSyncDeferred(
          _blockedUntil!, 'GitHub asked us to pause; progress saved locally');
    }
  }

  /// Includes primary reset and secondary Retry-After, as documented by
  /// GitHub. Never blindly retry HTTP 422 (which can be a validation error).
  static void inspect(http.Response response) {
    final code = response.statusCode;
    final remaining = response.headers['x-ratelimit-remaining'];
    final body = response.body.toLowerCase();
    final limited = code == 429 ||
        (code == 403 && (remaining == '0' ||
            body.contains('rate limit') || body.contains('abuse detection')));
    if (!limited) return;

    final now = DateTime.now();
    DateTime? until;
    final retryHeader = response.headers['retry-after'];
    final seconds = int.tryParse(retryHeader ?? '');
    if (seconds != null && seconds > 0) {
      until = now.add(Duration(seconds: seconds));
    } else if (retryHeader != null) {
      try {
        final date = HttpDate.parse(retryHeader);
        if (date.isAfter(now)) until = date;
      } on FormatException {
        // Ignore a malformed Retry-After and apply the safe one-minute rule.
      }
    }
    final reset = int.tryParse(response.headers['x-ratelimit-reset'] ?? '');
    if (until == null && remaining == '0' && reset != null) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
          reset * 1000, isUtc: true).toLocal();
      if (timestamp.isAfter(now)) until = timestamp;
    }
    until ??= now.add(const Duration(minutes: 1));
    // Respect a later existing cooldown from an earlier request.
    if (_blockedUntil == null || until.isAfter(_blockedUntil!)) {
      _blockedUntil = until;
    }
    throw GitHubSyncDeferred(
        _blockedUntil!, 'GitHub is rate limiting; changes remain queued locally');
  }

  static Future<http.Response> write(
      Future<http.Response> Function() operation) {
    final run = _writeQueue.then((_) async {
      checkAllowed();
      if (_lastWrite != null) {
        final wait = mutationSpacing -
            DateTime.now().difference(_lastWrite!);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      checkAllowed();
      _lastWrite = DateTime.now();
      final response = await operation();
      inspect(response);
      return response;
    });
    // A failed write must not poison the future queue.
    _writeQueue = run.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return run;
  }

  /// Tests do not make real requests or bypass the production cooldown.
  static void resetForTesting() {
    _blockedUntil = null;
    _lastWrite = null;
    _writeQueue = Future<void>.value();
  }
}
