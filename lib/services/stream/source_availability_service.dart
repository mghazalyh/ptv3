import 'dart:async';

import '../../models/stream/stream_model.dart';
import '../addon/addon_manager.dart';
import '../player/debrid_source_readiness.dart';
import 'stream_service.dart';
import 'watch_source_preferences.dart';

/// Same stream discovery used by Watch, but called ONLY from an opened details
/// page. Never invoke this service while building search or Discover results.
typedef SourceAvailabilityLoader = Stream<StreamSource> Function({
  required String type,
  required String id,
  required String title,
  int? year,
  int? season,
  int? episode,
});

class SourceAvailabilityResult {
  const SourceAvailabilityResult({
    required this.sources,
    required this.complete,
  });

  /// Unverified candidates, not independently checked playable links.
  final List<StreamSource> sources;
  final bool complete;
  int get count => sources.length;
}

class _AvailabilityCacheEntry {
  const _AvailabilityCacheEntry(this.result, this.checkedAt);
  final SourceAvailabilityResult result;
  final DateTime checkedAt;
}

/// Short-lived, in-memory and in-flight-deduplicated detail-page source probe.
/// No TorBox API verification, no persistent URLs, no background catalog scans.
class SourceAvailabilityService {
  SourceAvailabilityService({
    SourceAvailabilityLoader? loader,
    DateTime Function()? clock,
    Duration ttl = const Duration(seconds: 45),
    Duration deadline = const Duration(seconds: 18),
  })  : _loader = loader ?? StreamService.fetchStreams,
        _clock = clock ?? DateTime.now,
        _ttl = ttl,
        _deadline = deadline;

  static final SourceAvailabilityService instance =
      SourceAvailabilityService();

  final SourceAvailabilityLoader _loader;
  final DateTime Function() _clock;
  final Duration _ttl;
  final Duration _deadline;
  final Map<String, _AvailabilityCacheEntry> _cache = {};
  final Map<String, Future<SourceAvailabilityResult>> _inFlight = {};

  String _key({
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) {
    // Only stored in memory, never logged or sent to diagnostics. A change to
    // configured addon endpoints invalidates the short-lived cached result.
    final addonEndpoints = AddonManager.instance.activeStreamAddons
        .map((addon) => addon.baseUrl)
        .toList()..sort();
    return <String>[
      type, id, title, year?.toString() ?? '',
      season?.toString() ?? '', episode?.toString() ?? '',
      ...addonEndpoints,
    ].join('|');
  }

  static String identityOf(StreamSource source) {
    final url = source.url?.trim();
    if (url != null && url.isNotEmpty) {
      return 'url|' + source.addonName + '|' + url;
    }
    final hash = WatchSourceEngine.hashOf(source);
    if (hash != null) {
      return 'hash|' + source.addonName + '|' + hash +
          '|' + (source.fileIdx?.toString() ?? '');
    }
    return 'external|' + source.addonName + '|' +
        (source.externalUrl ?? '') + '|' + (source.title ?? '');
  }

  static bool isCandidate(StreamSource source) {
    if (DebridSourceReadiness.isExplicitlyPending(source)) return false;
    if (WatchSourceEngine.isPlayableDirectStream(source)) return true;
    if (WatchSourceEngine.hashOf(source) != null) return true;
    final external = Uri.tryParse(source.externalUrl ?? '');
    return external != null &&
        (external.scheme == 'https' || external.scheme == 'http') &&
        external.host.isNotEmpty;
  }

  SourceAvailabilityResult? peek({
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) {
    final key = _key(type: type, id: id, title: title, year: year,
        season: season, episode: episode);
    final cached = _cache[key];
    if (cached == null) return null;
    if (_clock().difference(cached.checkedAt) >= _ttl) {
      _cache.remove(key);
      return null;
    }
    return cached.result;
  }

  /// Let the Watch screen reuse the detail check (including one in progress),
  /// instead of issuing the exact same addon requests a second time.
  Future<SourceAvailabilityResult>? existing({
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) {
    final key = _key(type: type, id: id, title: title, year: year,
        season: season, episode: episode);
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final cached = peek(type: type, id: id, title: title, year: year,
        season: season, episode: episode);
    return cached == null ? null : Future.value(cached);
  }

  Future<SourceAvailabilityResult> inspect({
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
    List<StreamSource> embedded = const [],
    bool refresh = false,
  }) {
    final key = _key(type: type, id: id, title: title, year: year,
        season: season, episode: episode);
    final pending = _inFlight[key];
    if (pending != null) return pending;
    if (!refresh) {
      final cached = peek(type: type, id: id, title: title, year: year,
          season: season, episode: episode);
      if (cached != null) return Future.value(cached);
    }

    final request = _collect(type: type, id: id, title: title, year: year,
        season: season, episode: episode, embedded: embedded);
    _inFlight[key] = request;
    // _collect absorbs lookup failures and resolves to an incomplete result.
    request.then((result) {
      if (result.complete || result.count > 0) {
        _cache[key] = _AvailabilityCacheEntry(result, _clock());
        while (_cache.length > 32) {
          _cache.remove(_cache.keys.first);
        }
      }
    }).whenComplete(() => _inFlight.remove(key));
    return request;
  }

  Future<SourceAvailabilityResult> _collect({
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
    required List<StreamSource> embedded,
  }) async {
    final found = <StreamSource>[];
    final identities = <String>{};
    void add(StreamSource source) {
      if (found.length >= 250 || !isCandidate(source)) return;
      if (identities.add(identityOf(source))) found.add(source);
    }
    for (final source in embedded) {
      add(source);
    }

    final finished = Completer<void>();
    StreamSubscription<StreamSource>? subscription;
    var timedOut = false;
    var hadError = false;
    try {
      subscription = _loader(type: type, id: id, title: title,
          year: year, season: season, episode: episode).listen(
        add,
        onError: (Object _, StackTrace __) {
          hadError = true;
        },
        onDone: () {
          if (!finished.isCompleted) finished.complete();
        },
      );
      await finished.future.timeout(_deadline);
    } on TimeoutException {
      timedOut = true;
    } catch (_) {
      hadError = true;
    } finally {
      await subscription?.cancel();
    }

    return SourceAvailabilityResult(
      sources: List<StreamSource>.unmodifiable(found),
      complete: !timedOut && !hadError,
    );
  }
}
