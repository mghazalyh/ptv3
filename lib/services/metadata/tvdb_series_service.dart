import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'tmdb_discover_service.dart';

/// Optional TheTVDB v4 metadata used to improve series identification and
/// gently prioritize TMDB recommendations; TVDB has no documented native
/// per-series recommendation endpoint.
class TvdbSeriesInfo {
  final int id;
  final String title;
  final int? premiereYear;
  final int? tmdbId;
  final List<String> genres;

  const TvdbSeriesInfo({
    required this.id,
    required this.title,
    this.premiereYear,
    this.tmdbId,
    this.genres = const [],
  });

  @visibleForTesting
  static TvdbSeriesInfo? fromExtended(
      Map<String, dynamic> json, String title, int? year) {
    final id = (json['id'] as num?)?.toInt();
    if (id == null || id <= 0) return null;
    final genres = <String>[];
    for (final raw in (json['genres'] as List<dynamic>?) ?? const []) {
      if (raw is! Map) continue;
      final name = raw['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) genres.add(name);
    }
    int? tmdbId;
    for (final raw in (json['remoteIds'] as List<dynamic>?) ?? const []) {
      if (raw is! Map) continue;
      final provider = raw['sourceName']?.toString().toLowerCase() ?? '';
      if (!provider.contains('tmdb') &&
          !provider.contains('the movie database')) continue;
      tmdbId = int.tryParse(raw['id']?.toString() ?? '');
      if (tmdbId != null && tmdbId > 0) break;
    }
    return TvdbSeriesInfo(
      id: id, title: title, premiereYear: year,
      tmdbId: tmdbId, genres: genres,
    );
  }

  /// TVDB and TMDB use different genre identifiers. Only compare the genre
  /// names we actually recognize, never assume their numeric IDs match.
  int genreOverlap(DiscoverTitle candidate) {
    const tmdbGenres = <int, String>{
      10759: 'action', 16: 'animation', 35: 'comedy', 80: 'crime',
      99: 'documentary', 18: 'drama', 10751: 'family',
      10762: 'kids', 9648: 'mystery', 10763: 'news',
      10764: 'reality', 10765: 'fantasy', 10766: 'soap',
      10767: 'talk', 10768: 'war', 37: 'western',
    };
    final names = genres.map((g) => g.toLowerCase()).toList();
    var overlap = 0;
    for (final genreId in candidate.genreIds) {
      final name = tmdbGenres[genreId];
      if (name == null) continue;
      if (names.any((g) => g.contains(name) ||
          (name == 'fantasy' && (g.contains('supernatural') ||
              g.contains('science fiction'))) ||
          (name == 'action' && g.contains('adventure')))) overlap++;
    }
    return overlap;
  }

  /// Boost compatible titles slightly, preserving the source's main ranking.
  List<DiscoverTitle> prioritize(List<DiscoverTitle> candidates) {
    final ranked = candidates.asMap().entries.toList();
    ranked.sort((a, b) {
      final left = a.key - genreOverlap(a.value) * 2;
      final right = b.key - genreOverlap(b.value) * 2;
      return left.compareTo(right);
    });
    return ranked.map((entry) => entry.value).toList();
  }
}

class TvdbSeriesService {
  TvdbSeriesService._();
  static final TvdbSeriesService instance = TvdbSeriesService._();

  static const _apiKeyName = 'tvdb_v4_api_key';
  static const _pinName = 'tvdb_v4_subscriber_pin';
  static const _base = 'https://api4.thetvdb.com/v4';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _token;
  DateTime? _tokenExpires;
  DateTime? _blockedUntil;
  DateTime? _lastRequestAt;
  final Map<String, TvdbSeriesInfo?> _cache = {};

  @visibleForTesting
  Future<http.Response> Function(Uri, Map<String, String>)? getOverride;
  @visibleForTesting
  Future<http.Response> Function(Uri, Map<String, String>, String)? postOverride;

  Future<bool> get hasCredentials async {
    try {
      return ((await _storage.read(key: _apiKeyName)) ?? '').trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveCredentials(String key, String pin) async {
    final normalized = key.trim();
    if (normalized.isEmpty) {
      await _storage.delete(key: _apiKeyName);
      await _storage.delete(key: _pinName);
    } else {
      await _storage.write(key: _apiKeyName, value: normalized);
      if (pin.trim().isEmpty) {
        await _storage.delete(key: _pinName);
      } else {
        await _storage.write(key: _pinName, value: pin.trim());
      }
    }
    _token = null;
    _tokenExpires = null;
    _cache.clear();
  }

  Future<void> _pace() async {
    final blocked = _blockedUntil;
    if (blocked != null && DateTime.now().isBefore(blocked)) {
      throw const FormatException('TVDB requested a cooldown.');
    }
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < const Duration(milliseconds: 800)) {
        await Future<void>.delayed(
            const Duration(milliseconds: 800) - elapsed);
      }
    }
    _lastRequestAt = DateTime.now();
  }

  Future<String?> _getToken() async {
    if (_token != null && _tokenExpires != null &&
        DateTime.now().isBefore(_tokenExpires!)) return _token;
    String key;
    String pin;
    try {
      key = (await _storage.read(key: _apiKeyName))?.trim() ?? '';
      pin = (await _storage.read(key: _pinName))?.trim() ?? '';
    } catch (_) {
      return null;
    }
    if (key.isEmpty) return null;
    await _pace();
    final uri = Uri.parse('$_base/login');
    final body = jsonEncode({
      'apikey': key,
      if (pin.isNotEmpty) 'pin': pin,
    });
    final headers = <String, String>{
      'Content-Type': 'application/json', 'Accept': 'application/json',
    };
    final response = await (postOverride == null
        ? http.post(uri, headers: headers, body: body)
        : postOverride!(uri, headers, body))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 429) {
      _blockedUntil = DateTime.now().add(const Duration(minutes: 2));
      throw const FormatException('TVDB requested fewer requests.');
    }
    if (response.statusCode != 200) {
      throw const FormatException('TVDB login was unsuccessful. Check API key / PIN.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final data = decoded['data'];
    if (data is! Map) return null;
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) return null;
    _token = token;
    // TVDB documents up to one month; renew well before expiry.
    _tokenExpires = DateTime.now().add(const Duration(days: 20));
    return token;
  }

  Future<Map<String, dynamic>> _get(
      String endpoint, Map<String, String> params, String token) async {
    await _pace();
    final uri = Uri.https('api4.thetvdb.com', '/v4/$endpoint', params);
    final headers = <String, String>{
      'Accept': 'application/json', 'Authorization': 'Bearer $token',
    };
    final response = await (getOverride == null
        ? http.get(uri, headers: headers)
        : getOverride!(uri, headers))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 429) {
      _blockedUntil = DateTime.now().add(const Duration(minutes: 2));
      throw const FormatException('TVDB requested fewer requests.');
    }
    if (response.statusCode != 200) {
      throw const FormatException('TVDB metadata unavailable.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid TVDB response.');
    }
    return decoded;
  }

  @visibleForTesting
  static String normalizeTitle(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Up to 2 TVDB metadata GETs per new show, only on a BestSimilar miss.
  /// No automatic provider-wide queries or speculative candidate lookups.
  Future<TvdbSeriesInfo?> matchSeries(String title, int? year) async {
    if (title.trim().isEmpty || !(await hasCredentials)) return null;
    final cacheKey = '${normalizeTitle(title)}:${year ?? ''}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];
    try {
      final token = await _getToken();
      if (token == null) return null;
      final searched = await _get('search', {
        'query': title.trim(),
        'type': 'series',
      }, token);
      final options = searched['data'] as List<dynamic>? ?? const [];
      Map? matched;
      for (final raw in options) {
        if (raw is! Map) continue;
        final name = raw['name']?.toString() ?? '';
        final firstAired = raw['first_air_time']?.toString() ??
            raw['firstAired']?.toString() ?? raw['year']?.toString() ?? '';
        final foundYear = firstAired.length >= 4
            ? int.tryParse(firstAired.substring(0, 4)) : null;
        if (normalizeTitle(name) != normalizeTitle(title)) continue;
        if (year != null && foundYear != null && foundYear != year) continue;
        matched = raw;
        break;
      }
      if (matched == null) {
        _cache[cacheKey] = null;
        return null;
      }
      final id = int.tryParse(
          matched['tvdb_id']?.toString() ?? matched['id']?.toString() ?? '');
      if (id == null || id <= 0) return null;
      final extended = await _get('series/$id/extended', {
        'short': 'true',
      }, token);
      final data = extended['data'];
      if (data is! Map<String, dynamic>) return null;
      final result = TvdbSeriesInfo.fromExtended(data, title, year);
      _cache[cacheKey] = result;
      if (_cache.length > 60) _cache.remove(_cache.keys.first);
      return result;
    } catch (_) {
      // TVDB is optional; never leak tokens, credential details or request URLs.
      return null;
    }
  }
}
