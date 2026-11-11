import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/stream/stream_model.dart';
import '../config/torriodb_portable_sync.dart';
import '../debrid/providers/torbox_service.dart';
import '../player/audio_language_priority.dart';
import '../player/debrid_source_readiness.dart';

/// All optional fields are fail-open. Missing metadata must not hide playback.
class SourceSortRule {
  final String criterion;
  final bool descending;
  const SourceSortRule(this.criterion, this.descending);

  static const criteria = <String>[
    'cache', 'resolution', 'size', 'provider', 'seeders', 'release',
    'codec', 'hdr', 'audio', 'subtitles', 'original',
  ];

  factory SourceSortRule.parse(Object? raw, SourceSortRule fallback) {
    if (raw is! Map) return fallback;
    final criterion = raw['criterion'];
    if (criterion is! String || !criteria.contains(criterion)) return fallback;
    return SourceSortRule(
      criterion,
      raw['descending'] is bool ? raw['descending'] as bool : fallback.descending,
    );
  }
  Map<String, Object> toJson() => {
    'criterion': criterion, 'descending': descending,
  };
}

class WatchSourceProfile {
  final List<String> resolutions;
  final List<String> addons;
  final List<String> codecs;
  final List<String> hdrFormats;
  final List<String> releaseTypes;
  final double minSizeGb;
  final double maxSizeGb;
  final int minSeeders;
  final String cachePolicy;
  final String subtitlePolicy;
  final String subtitleLanguage;
  final bool preferEnglishAudio;
  final bool allowUnknown;
  final bool deduplicate;
  final List<SourceSortRule> sorting;

  const WatchSourceProfile({
    this.resolutions = const ['4K', '1080p'],
    this.addons = const [],
    this.codecs = const [],
    this.hdrFormats = const [],
    this.releaseTypes = const [],
    this.minSizeGb = 0,
    this.maxSizeGb = 0,
    this.minSeeders = 0,
    this.cachePolicy = 'prefer',
    this.subtitlePolicy = 'prefer',
    this.subtitleLanguage = 'English',
    this.preferEnglishAudio = true,
    this.allowUnknown = true,
    this.deduplicate = true,
    this.sorting = const [
      SourceSortRule('cache', true),
      SourceSortRule('resolution', true),
      SourceSortRule('size', false),
    ],
  });

  static const allResolutions = <String>['4K', '1440p', '1080p', '720p', '480p'];
  static const allCodecs = <String>['HEVC', 'H.264', 'AV1'];
  static const allHdr = <String>['Dolby Vision', 'HDR10+', 'HDR10', 'SDR'];
  static const allReleases = <String>['REMUX', 'BluRay', 'WEB-DL', 'WEBRip', 'HDTV'];
  static const cachePolicies = <String>['prefer', 'cachedOnly', 'all'];
  static const subtitlePolicies = <String>['prefer', 'require', 'none', 'all'];

  WatchSourceProfile copyWith({
    List<String>? resolutions, List<String>? addons, List<String>? codecs,
    List<String>? hdrFormats, List<String>? releaseTypes,
    double? minSizeGb, double? maxSizeGb, int? minSeeders,
    String? cachePolicy, String? subtitlePolicy, String? subtitleLanguage,
    bool? preferEnglishAudio, bool? allowUnknown, bool? deduplicate,
    List<SourceSortRule>? sorting,
  }) => WatchSourceProfile(
    resolutions: resolutions ?? this.resolutions,
    addons: addons ?? this.addons,
    codecs: codecs ?? this.codecs,
    hdrFormats: hdrFormats ?? this.hdrFormats,
    releaseTypes: releaseTypes ?? this.releaseTypes,
    minSizeGb: minSizeGb ?? this.minSizeGb,
    maxSizeGb: maxSizeGb ?? this.maxSizeGb,
    minSeeders: minSeeders ?? this.minSeeders,
    cachePolicy: cachePolicy ?? this.cachePolicy,
    subtitlePolicy: subtitlePolicy ?? this.subtitlePolicy,
    subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
    preferEnglishAudio: preferEnglishAudio ?? this.preferEnglishAudio,
    allowUnknown: allowUnknown ?? this.allowUnknown,
    deduplicate: deduplicate ?? this.deduplicate,
    sorting: sorting ?? this.sorting,
  );

  static List<String> _strings(Object? raw, List<String> allowed,
      List<String> fallback) {
    if (raw is! List || raw.length > 100) return fallback;
    if (raw.any((v) => v is! String || (v as String).length > 128)) {
      return fallback;
    }
    return (raw.cast<String>().where(allowed.contains).toSet()).toList();
  }

  static List<String> _addonNames(Object? raw) {
    if (raw is! List || raw.length > 50) return const [];
    final values = <String>[];
    for (final name in raw) {
      if (name is! String || name.length > 100 || name.trim().isEmpty) continue;
      values.add(name.trim());
    }
    return values.toSet().toList();
  }

  factory WatchSourceProfile.fromJson(Object? raw) {
    if (raw is! Map) return const WatchSourceProfile();
    const fallback = WatchSourceProfile();
    double number(Object? value, double defaultValue) {
      if (value is! num || !value.isFinite || value < 0 || value > 10000) {
        return defaultValue;
      }
      return value.toDouble();
    }
    final rawSorts = raw['sorting'];
    final sortRules = rawSorts is List && rawSorts.length == 3
        ? [
            for (var i = 0; i < 3; i++)
              SourceSortRule.parse(rawSorts[i], fallback.sorting[i]),
          ]
        : fallback.sorting;
    final unique = sortRules.map((r) => r.criterion).toSet();
    return WatchSourceProfile(
      resolutions: _strings(raw['resolutions'], allResolutions, fallback.resolutions),
      addons: _addonNames(raw['addons']),
      codecs: _strings(raw['codecs'], allCodecs, fallback.codecs),
      hdrFormats: _strings(raw['hdrFormats'], allHdr, fallback.hdrFormats),
      releaseTypes: _strings(raw['releaseTypes'], allReleases, fallback.releaseTypes),
      minSizeGb: number(raw['minSizeGb'], 0),
      maxSizeGb: number(raw['maxSizeGb'], 0),
      minSeeders: raw['minSeeders'] is int
          ? ((raw['minSeeders'] as int).clamp(0, 100000)).toInt() : 0,
      cachePolicy: cachePolicies.contains(raw['cachePolicy'])
          ? raw['cachePolicy'] as String : 'prefer',
      subtitlePolicy: subtitlePolicies.contains(raw['subtitlePolicy'])
          ? raw['subtitlePolicy'] as String : 'prefer',
      subtitleLanguage: raw['subtitleLanguage'] is String &&
              (raw['subtitleLanguage'] as String).length < 32
          ? raw['subtitleLanguage'] as String : 'English',
      preferEnglishAudio: raw['preferEnglishAudio'] is bool
          ? raw['preferEnglishAudio'] as bool : true,
      allowUnknown: raw['allowUnknown'] is bool
          ? raw['allowUnknown'] as bool : true,
      deduplicate: raw['deduplicate'] is bool
          ? raw['deduplicate'] as bool : true,
      sorting: unique.length == 3 ? sortRules : fallback.sorting,
    );
  }

  Map<String, dynamic> toJson() => {
    'resolutions': resolutions, 'addons': addons, 'codecs': codecs,
    'hdrFormats': hdrFormats, 'releaseTypes': releaseTypes,
    'minSizeGb': minSizeGb, 'maxSizeGb': maxSizeGb,
    'minSeeders': minSeeders, 'cachePolicy': cachePolicy,
    'subtitlePolicy': subtitlePolicy, 'subtitleLanguage': subtitleLanguage,
    'preferEnglishAudio': preferEnglishAudio, 'allowUnknown': allowUnknown,
    'deduplicate': deduplicate,
    'sorting': [for (final rule in sorting) rule.toJson()],
  };

  factory WatchSourceProfile.preset(String name) {
    switch (name) {
      case 'Best Quality':
        return const WatchSourceProfile(
          sorting: [
            SourceSortRule('resolution', true),
            SourceSortRule('release', true),
            SourceSortRule('size', true),
          ],
        );
      case 'Fast Playback':
        return const WatchSourceProfile(
          sorting: [
            SourceSortRule('cache', true),
            SourceSortRule('provider', true),
            SourceSortRule('size', false),
          ],
        );
      case 'Small Files':
        return const WatchSourceProfile(
          sorting: [
            SourceSortRule('size', false),
            SourceSortRule('cache', true),
            SourceSortRule('resolution', true),
          ],
        );
      default:
        return const WatchSourceProfile();
    }
  }
}

class WatchSourcePreferences {
  final WatchSourceProfile movie;
  final WatchSourceProfile episode;
  final String preset;
  const WatchSourcePreferences({
    this.movie = const WatchSourceProfile(),
    this.episode = const WatchSourceProfile(),
    this.preset = 'Balanced',
  });

  WatchSourceProfile forEpisode(bool isEpisode) => isEpisode ? episode : movie;

  WatchSourcePreferences copyWith({
    WatchSourceProfile? movie, WatchSourceProfile? episode, String? preset,
  }) => WatchSourcePreferences(
    movie: movie ?? this.movie,
    episode: episode ?? this.episode,
    preset: preset ?? this.preset,
  );

  factory WatchSourcePreferences.fromJson(Object? raw) {
    if (raw is! Map) return const WatchSourcePreferences();
    final namedPreset = raw['preset'];
    return WatchSourcePreferences(
      movie: WatchSourceProfile.fromJson(raw['movie']),
      episode: WatchSourceProfile.fromJson(raw['episode']),
      preset: namedPreset is String &&
              ['Balanced', 'Best Quality', 'Fast Playback', 'Small Files', 'Custom']
                  .contains(namedPreset)
          ? namedPreset : 'Balanced',
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'preset': preset,
    'movie': movie.toJson(),
    'episode': episode.toJson(),
  };
}

abstract final class WatchSourcePreferencesService {
  static const storageKey = 'watch_source_preferences_v1';
  static final ValueNotifier<WatchSourcePreferences> current =
      ValueNotifier(const WatchSourcePreferences());

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty && raw.length < 40000) {
        current.value = WatchSourcePreferences.fromJson(jsonDecode(raw));
      }
    } catch (error) {
      debugPrint('[WatchSources] Invalid preferences: ' + error.runtimeType.toString());
      current.value = const WatchSourcePreferences();
    }
  }

  static Future<void> save(WatchSourcePreferences preferences,
      {bool fromCloud = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(preferences.toJson()));
    current.value = preferences;
    if (!fromCloud) await TorriodbPortableSync.instance.markChanged('watchSources');
  }

  static Future<void> saveProfile(WatchSourceProfile profile,
      {required bool isEpisode, String preset = 'Custom'}) =>
      save(isEpisode
          ? current.value.copyWith(episode: profile, preset: preset)
          : current.value.copyWith(movie: profile, preset: preset));

  static Map<String, dynamic> normalize(Object? raw) {
    if (raw is! Map || jsonEncode(raw).length > 40000) {
      throw const FormatException('Invalid Watch Sources preference document');
    }
    return WatchSourcePreferences.fromJson(raw).toJson();
  }

  static Future<void> restoreFromCloud(Object? raw) async {
    await save(WatchSourcePreferences.fromJson(normalize(raw)), fromCloud: true);
  }
}

abstract final class WatchSourceEngine {
  static String? hashOf(StreamSource source) {
    final hash = source.infoHash?.trim().toLowerCase();
    if (hash != null && RegExp(r'^[0-9a-f]{40}$').hasMatch(hash)) return hash;
    final magnet = source.magnetUrl ?? '';
    final match = RegExp(r'btih:([0-9a-f]{40})', caseSensitive: false)
        .firstMatch(magnet);
    return match?.group(1)?.toLowerCase();
  }

  static String? resolution(StreamSource source) {
    if (source.quality == '4K') return '4K';
    if (source.quality == '1080p') return '1080p';
    if (source.quality == '720p') return '720p';
    if (source.quality == '480p') return '480p';
    final raw = ((source.title ?? '') + ' ' + (source.name ?? '')).toLowerCase();
    if (raw.contains('1440')) return '1440p';
    return null;
  }

  static String? hdr(StreamSource source) {
    final raw = ((source.name ?? '') + ' ' + (source.title ?? '')).toLowerCase();
    if (raw.contains('dolby vision') || RegExp(r'\bdv\b').hasMatch(raw)) {
      return 'Dolby Vision';
    }
    if (raw.contains('hdr10+')) return 'HDR10+';
    if (raw.contains('hdr10') || RegExp(r'\bhdr\b').hasMatch(raw)) return 'HDR10';
    if (RegExp(r'\bsdr\b').hasMatch(raw)) return 'SDR';
    return null;
  }

  static String? release(StreamSource source) {
    final raw = ((source.name ?? '') + ' ' + (source.title ?? '')).toLowerCase();
    if (raw.contains('remux')) return 'REMUX';
    if (raw.contains('bluray') || raw.contains('blu-ray')) return 'BluRay';
    if (raw.contains('web-dl') || raw.contains('webdl')) return 'WEB-DL';
    if (raw.contains('webrip') || raw.contains('web-rip')) return 'WEBRip';
    if (raw.contains('hdtv')) return 'HDTV';
    return null;
  }

  static int? seeders(StreamSource source) {
    final text = (source.title ?? '') + ' ' + (source.description ?? '');
    final match = RegExp(r'(?:seeders?\s*[:=]?\s*|👤\s*)(\d+)',
        caseSensitive: false).firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  /// Only explicit subtitle declarations count as confirmed.
  static bool? hasSubtitles(StreamSource source) {
    if (source.subtitles != null && source.subtitles!.isNotEmpty) return true;
    final raw = (source.title ?? '') + ' ' + (source.description ?? '');
    if (RegExp(r'\b(no subtitles|no subs|subtitles?:\s*none)\b',
        caseSensitive: false).hasMatch(raw)) return false;
    if (RegExp(r'\b(embedded subs|subtitles?:\s*[a-z]{2,}|subbed)\b',
        caseSensitive: false).hasMatch(raw)) return true;
    return null;
  }

  static String cacheTier(StreamSource source, Map<String, bool> verified) {
    final hash = hashOf(source);
    if (hash != null && verified.containsKey(hash)) {
      return verified[hash] == true ? 'verified' : 'uncached';
    }
    if (DebridSourceReadiness.isExplicitlyPending(source)) return 'pending';
    final name = (source.name ?? '').toLowerCase();
    if (RegExp(r'^\s*\[(tb|rd|ad|pm)\+?\]').hasMatch(name)) return 'reported';
    return 'unknown';
  }

  static bool _match(String? value, List<String> allowed, bool unknown) =>
      allowed.isEmpty || (value == null ? unknown : allowed.contains(value));

  static bool _allowed(StreamSource source, WatchSourceProfile profile,
      Map<String, bool> verified) {
    if (profile.addons.isNotEmpty &&
        !profile.addons.any((name) =>
            source.addonName.toLowerCase().contains(name.toLowerCase()))) return false;
    if (!_match(resolution(source), profile.resolutions, profile.allowUnknown)) return false;
    if (!_match(source.codec, profile.codecs, profile.allowUnknown)) return false;
    if (!_match(hdr(source), profile.hdrFormats, profile.allowUnknown)) return false;
    if (!_match(release(source), profile.releaseTypes, profile.allowUnknown)) return false;
    final size = source.sizeBytes;
    if (profile.minSizeGb > 0 &&
        (size == null ? !profile.allowUnknown : size < profile.minSizeGb * 1073741824)) {
      return false;
    }
    if (profile.maxSizeGb > 0 &&
        (size == null ? !profile.allowUnknown : size > profile.maxSizeGb * 1073741824)) {
      return false;
    }
    if (profile.minSeeders > 0) {
      final count = seeders(source);
      if (count == null ? !profile.allowUnknown : count < profile.minSeeders) {
        return false;
      }
    }
    if (profile.cachePolicy == 'cachedOnly' &&
        cacheTier(source, verified) != 'verified') return false;
    final subs = hasSubtitles(source);
    if (profile.subtitlePolicy == 'require' && subs != true) return false;
    if (profile.subtitlePolicy == 'none' && subs == true) return false;
    return true;
  }

  static double? _rank(StreamSource s, String criterion,
      Map<String, bool> verified, int original) {
    switch (criterion) {
      case 'cache':
        switch (cacheTier(s, verified)) {
          case 'verified': return 4;
          case 'reported': return 3;
          case 'unknown': return 2;
          case 'pending': return 1;
          case 'uncached': return 0;
        }
      case 'resolution':
        switch (resolution(s)) {
          case '4K': return 5;
          case '1440p': return 4;
          case '1080p': return 3;
          case '720p': return 2;
          case '480p': return 1;
        }
        return null;
      case 'size': return s.sizeBytes;
      case 'provider':
        final name = s.addonName.toLowerCase();
        if (name.contains('torrentio')) return 3;
        if (name.contains('comet')) return 2;
        if (name.contains('mediafusion')) return 1;
        return 0;
      case 'seeders': return seeders(s)?.toDouble();
      case 'release':
        switch (release(s)) {
          case 'REMUX': return 5;
          case 'BluRay': return 4;
          case 'WEB-DL': return 3;
          case 'WEBRip': return 2;
          case 'HDTV': return 1;
        }
        return null;
      case 'codec':
        switch (s.codec) {
          case 'HEVC': return 3;
          case 'AV1': return 2;
          case 'H.264': return 1;
        }
        return null;
      case 'hdr':
        switch (hdr(s)) {
          case 'Dolby Vision': return 4;
          case 'HDR10+': return 3;
          case 'HDR10': return 2;
          case 'SDR': return 1;
        }
        return null;
      case 'audio': return (3 - AudioLanguagePriority.torrentioAudioRank(s)).toDouble();
      case 'subtitles': return hasSubtitles(s) == true ? 1 : 0;
      case 'original': return original.toDouble();
    }
    return null;
  }

  static List<StreamSource> process(List<StreamSource> sources,
      WatchSourceProfile profile, {Map<String, bool> verified = const {}}) {
    try {
      var selected = sources.where((s) => _allowed(s, profile, verified)).toList();
      // Fail open when a missing provider field or strict setting eliminates all
      // results. Do not silently leave users without a playback choice.
      if (selected.isEmpty && sources.isNotEmpty) {
        selected = List<StreamSource>.of(sources);
      }
      if (profile.deduplicate) {
        final seen = <String>{};
        selected = selected.where((s) {
          final hash = hashOf(s);
          if (hash == null) return true;
          final key = hash + ':' + (s.fileIdx?.toString() ?? '');
          return seen.add(key);
        }).toList();
      }
      final original = <StreamSource, int>{
        for (var i = 0; i < selected.length; i++) selected[i]: i,
      };
      selected.sort((a, b) {
        for (final rule in profile.sorting) {
          final ar = _rank(a, rule.criterion, verified, original[a] ?? 0);
          final br = _rank(b, rule.criterion, verified, original[b] ?? 0);
          if (ar == null && br == null) continue;
          if (ar == null) return 1;
          if (br == null) return -1;
          final compare = ar.compareTo(br);
          if (compare != 0) return rule.descending ? -compare : compare;
        }
        if (profile.preferEnglishAudio) {
          final compare = AudioLanguagePriority.torrentioAudioRank(a)
              .compareTo(AudioLanguagePriority.torrentioAudioRank(b));
          if (compare != 0) return compare;
        }
        return (original[a] ?? 0).compareTo(original[b] ?? 0);
      });
      return selected;
    } catch (error) {
      debugPrint('[WatchSources] Sort/filter fallback: ' + error.runtimeType.toString());
      return List<StreamSource>.of(sources);
    }
  }
}

/// Never marks a source verified from an addon title alone.
/// This is a bounded, read-only GET to TorBox's published checkcached endpoint.
class TorBoxCacheVerifier {
  TorBoxCacheVerifier._();
  static final instance = TorBoxCacheVerifier._();
  final _resultCache = <String, bool>{};
  DateTime? _cachedAt;

  Future<Map<String, bool>> verify(List<StreamSource> sources) async {
    final hashes = sources.map(WatchSourceEngine.hashOf)
        .whereType<String>().toSet().toList();
    if (hashes.isEmpty) return const {};
    if (_cachedAt != null &&
        DateTime.now().difference(_cachedAt!) > const Duration(minutes: 45)) {
      _resultCache.clear();
    }
    final missing = hashes.where((h) => !_resultCache.containsKey(h)).take(80).toList();
    if (missing.isNotEmpty) {
      try {
        final key = await TorBoxService().getKey();
        if (key != null && key.isNotEmpty) {
          final uri = Uri.https('api.torbox.app',
              '/v1/api/torrents/checkcached',
              {'hash': missing.join(','), 'format': 'object'});
          final response = await http.get(uri,
              headers: {'Authorization': 'Bearer ' + key})
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final document = jsonDecode(response.body);
            if (document is Map && document['success'] == true) {
              final data = document['data'];
              if (data is Map) {
                for (final entry in data.entries) {
                  final hash = entry.key.toString().toLowerCase();
                  if (!missing.contains(hash)) continue;
                  final value = entry.value;
                  if (value is bool) {
                    _resultCache[hash] = value;
                  } else if (value is Map && value['cached'] is bool) {
                    _resultCache[hash] = value['cached'] as bool;
                  } else if (value is Map && value['is_cached'] is bool) {
                    _resultCache[hash] = value['is_cached'] as bool;
                  }
                }
              }
              _cachedAt = DateTime.now();
            }
          }
        }
      } catch (error) {
        debugPrint('[WatchSources] Cache check unavailable: ' +
            error.runtimeType.toString());
      }
    }
    return {for (final h in hashes) if (_resultCache.containsKey(h))
      h: _resultCache[h]!};
  }
}
