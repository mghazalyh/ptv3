import 'package:flutter/foundation.dart';

import 'tmdb_discover_service.dart';

/// A television run is determined from the show's own TMDB details, not
/// from the years selected in the Discover search form.
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
    return SeriesRun(
      startYear: _parseYear(details['first_air_date']),
      endYear: _parseYear(details['last_air_date']),
      finished: finished,
    );
  }

  String displayYear({String? fallbackYear}) {
    final fallback = fallbackYear?.trim() ?? '';
    final fallbackStart = RegExp(r'^\d{4}').firstMatch(fallback);
    final fallbackNumber = fallbackStart == null
        ? null : int.tryParse(fallbackStart.group(0)!);
    final first = startYear ??
        (fallbackNumber != null &&
                fallbackNumber >= 1900 && fallbackNumber <= 2100
            ? fallbackNumber : null);

    if (finished && first != null && endYear != null && endYear! >= first) {
      return '$first - $endYear';
    }
    if (first != null) return '$first';
    return fallback.isNotEmpty ? fallback : 'Year unknown';
  }
}

/// Only visible, verifiably identified series cards request details. A bounded
/// shared budget avoids turning a large Search/Discover grid into bulk TMDB
/// traffic. TMDB's service also paces/deduplicates/caches the actual requests.
class SeriesRunService {
  SeriesRunService._();
  static final SeriesRunService instance = SeriesRunService._();

  final Map<String, Future<SeriesRun?>> _inFlightOrCached = {};
  final List<DateTime> _cardRequests = [];

  Future<SeriesRun?> resolve({int? tmdbId, String? imdbId}) async {
    final imdb = imdbId?.trim() ?? '';
    if ((tmdbId == null || tmdbId <= 0) &&
        !RegExp(r'^tt\d+$').hasMatch(imdb)) {
      return null;
    }
    final id = tmdbId != null && tmdbId > 0 ? 'tmdb:$tmdbId' : 'imdb:$imdb';
    final existing = _inFlightOrCached[id];
    if (existing != null) return existing;

    // Search outside Advanced Discover may not have a configured TMDB key.
    // Do not spend the request allowance or hide provider years in that case.
    if ((await TmdbDiscoverService.instance.readKey()).trim().isEmpty) {
      return null;
    }
    // Two cards may have reached the asynchronous key lookup together.
    // Recheck before charging the request budget or starting a second lookup.
    final pending = _inFlightOrCached[id];
    if (pending != null) return pending;

    final now = DateTime.now();
    _cardRequests.removeWhere((time) =>
        now.difference(time) >= const Duration(minutes: 1));
    if (_cardRequests.length >= 24) return null;
    _cardRequests.add(now);

    final future = TmdbDiscoverService.instance.titleOriginLanguage(
      imdbId: imdb,
      tmdbId: tmdbId,
      isSeries: true,
    ).then((details) => details.isEmpty
        ? null : SeriesRun.fromTmdb(details)).catchError((Object error) {
      debugPrint('SeriesRunService: series detail unavailable: ${error.runtimeType}');
      return null;
    });

    _inFlightOrCached[id] = future;
    if (_inFlightOrCached.length > 180) {
      _inFlightOrCached.remove(_inFlightOrCached.keys.first);
    }
    return future;
  }

  @visibleForTesting
  void resetForTesting() {
    _inFlightOrCached.clear();
    _cardRequests.clear();
  }
}
