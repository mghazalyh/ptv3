import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'tmdb_discover_service.dart';

/// A verified TV series' complete run. The selected Discover year filter is
/// NEVER used as the end year.
@immutable
class SeriesRun {
  final int? startYear;
  final int? endYear;
  final bool finished;

  const SeriesRun({
    this.startYear,
    this.endYear,
    this.finished = false,
  });

  static int? _parseYear(Object? value) {
    final text = value?.toString() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
    final year = int.tryParse(text.substring(0, 4));
    return year != null && year >= 1900 && year <= 2100 ? year : null;
  }

  factory SeriesRun.fromTmdb(Map<String, dynamic> details) {
    final status = details['status']?.toString().trim().toLowerCase();
    final finished = status == 'ended' ||
        status == 'canceled' || status == 'cancelled';
    final lastEpisode = details['last_episode_to_air'];
    final lastEpisodeDate = lastEpisode is Map
        ? lastEpisode['air_date'] : null;
    return SeriesRun(
      startYear: _parseYear(details['first_air_date']),
      endYear: _parseYear(details['last_air_date']) ??
          _parseYear(lastEpisodeDate),
      finished: finished,
    );
  }

  /// Cinemeta supplies a bounded releaseInfo such as "2008-2015" for many
  /// ended shows. Use it only when it belongs to this exact IMDb series.
  /// An open-ended "2008-" never proves that a show has finished.
  factory SeriesRun.fromCinemeta(Map<String, dynamic> meta) {
    final release = meta['releaseInfo']?.toString().trim() ?? '';
    final match = RegExp(r'^(\d{4})\s*[-–]\s*(\d{4})$').firstMatch(release);
    if (match == null) {
      final first = RegExp(r'^(\d{4})').firstMatch(release);
      final year = first == null ? null : int.tryParse(first.group(1)!);
      return SeriesRun(
        startYear: year != null && year >= 1900 && year <= 2100 ? year : null);
    }
    final first = int.parse(match.group(1)!);
    final last = int.parse(match.group(2)!);
    if (first < 1900 || last > 2100 || last < first) {
      return const SeriesRun();
    }
    return SeriesRun(startYear: first, endYear: last, finished: true);
  }

  String displayYear({String? fallbackYear}) {
    final fallback = fallbackYear?.trim() ?? '';
    // A source-provided completed releaseInfo is more informative than a
    // premiere-only field, and is already displayed by older Stremio cards.
    final providerRange = RegExp(r'^(\d{4})\s*[-–]\s*(\d{4})$')
        .firstMatch(fallback);
    final providerStart = providerRange == null
        ? null : int.parse(providerRange.group(1)!);
    final providerEnd = providerRange == null
        ? null : int.parse(providerRange.group(2)!);
    final firstMatch = RegExp(r'^\d{4}').firstMatch(fallback);
    final fallbackNumber = firstMatch == null
        ? null : int.tryParse(firstMatch.group(0)!);
    final first = startYear ??
        (fallbackNumber != null &&
                fallbackNumber >= 1900 && fallbackNumber <= 2100
            ? fallbackNumber : null);

    if (finished && first != null && endYear != null && endYear! >= first) {
      return '$first - $endYear';
    }
    if (providerStart != null && providerEnd != null &&
        providerStart >= 1900 && providerEnd <= 2100 &&
        providerEnd >= providerStart &&
        (first == null || first == providerStart)) {
      return '$providerStart - $providerEnd';
    }
    if (first != null) return '$first';
    return fallback.isNotEmpty ? fallback : 'Year unknown';
  }
}

/// Resolve only exact TMDB/IMDb IDs. Never guess by a similar title.
///
/// Requests are bounded to 24 new series per minute, but EXCESS requests
/// WAIT for a free slot. The previous implementation returned null for card
/// 25+ permanently, so popular ended shows unpredictably lacked end years.
///
/// If no TMDB credential is stored, a verified IMDb series can use its
/// existing public Stremio/Cinemeta releaseInfo (e.g. 2008-2015).
class SeriesRunService {
  SeriesRunService._();
  static final SeriesRunService instance = SeriesRunService._();

  final Map<String, Future<SeriesRun?>> _inFlightOrCached = {};
  final List<DateTime> _cardRequests = [];
  int _maxPerWindow = 24;
  Duration _window = const Duration(minutes: 1);

  @visibleForTesting
  Future<http.Response> Function(Uri)? cinemetaGetOverride;

  Future<void> _reserveSlot() async {
    while (true) {
      final now = DateTime.now();
      _cardRequests.removeWhere((time) => now.difference(time) >= _window);
      if (_cardRequests.length < _maxPerWindow) {
        _cardRequests.add(now);
        return;
      }
      final until = _cardRequests.first.add(_window);
      final remaining = until.difference(now);
      await Future<void>.delayed(
          remaining > Duration.zero ? remaining : const Duration(milliseconds: 1));
    }
  }

  Future<SeriesRun?> _cinemeta(String imdb) async {
    if (!RegExp(r'^tt\d+$').hasMatch(imdb)) return null;
    final uri = Uri.https('v3-cinemeta.strem.io',
        '/meta/series/$imdb.json');
    try {
      final response = await (cinemetaGetOverride == null
              ? http.get(uri) : cinemetaGetOverride!(uri))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['meta'] is! Map) return null;
      final meta = Map<String, dynamic>.from(payload['meta'] as Map);
      if (meta['id']?.toString() != imdb) return null;
      final run = SeriesRun.fromCinemeta(meta);
      return run.startYear == null ? null : run;
    } catch (error) {
      debugPrint('SeriesRunService: verified Cinemeta data unavailable: '
          '${error.runtimeType}');
      return null;
    }
  }

  Future<SeriesRun?> _lookup(int? tmdbId, String imdb) async {
    final key = await TmdbDiscoverService.instance.readKey();
    // No key: never attempt a TMDB call, but don't lose completed ranges in
    // verified IMDb metadata from the existing Stremio provider.
    if (key.trim().isEmpty) {
      if (!RegExp(r'^tt\d+$').hasMatch(imdb)) return null;
      await _reserveSlot();
      return _cinemeta(imdb);
    }
    await _reserveSlot();
    try {
      final details = await TmdbDiscoverService.instance.titleOriginLanguage(
        imdbId: imdb,
        tmdbId: tmdbId,
        isSeries: true,
      );
      if (details.isNotEmpty) return SeriesRun.fromTmdb(details);
    } catch (error) {
      debugPrint('SeriesRunService: TMDB details unavailable: '
          '${error.runtimeType}');
    }
    // On an isolated TMDB failure, the exact IMDb ID can still supply a
    // genuine completed release range without title-based guesses.
    return _cinemeta(imdb);
  }

  Future<SeriesRun?> resolve({int? tmdbId, String? imdbId}) {
    final imdb = imdbId?.trim() ?? '';
    final verifiedImdb = RegExp(r'^tt\d+$').hasMatch(imdb);
    if ((tmdbId == null || tmdbId <= 0) && !verifiedImdb) {
      return Future.value(null);
    }
    final id = tmdbId != null && tmdbId > 0
        ? 'tmdb:$tmdbId' : 'imdb:$imdb';
    final existing = _inFlightOrCached[id];
    if (existing != null) return existing;

    // Insert before the asynchronous key read to deduplicate concurrent
    // cards for the same verified ID.
    final future = _lookup(tmdbId, verifiedImdb ? imdb : '');
    _inFlightOrCached[id] = future;
    if (_inFlightOrCached.length > 180) {
      _inFlightOrCached.remove(_inFlightOrCached.keys.first);
    }
    // Transient request failures and missing keys must be retryable when a
    // new card is later mounted, rather than cached forever as null.
    future.then((value) {
      if (value == null && identical(_inFlightOrCached[id], future)) {
        _inFlightOrCached.remove(id);
      }
    });
    return future;
  }

  @visibleForTesting
  void resetForTesting({
    int maxPerWindow = 24,
    Duration window = const Duration(minutes: 1),
  }) {
    _inFlightOrCached.clear();
    _cardRequests.clear();
    _maxPerWindow = maxPerWindow;
    _window = window;
    cinemetaGetOverride = null;
  }
}
