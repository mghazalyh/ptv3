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
  final List<String> audioFormats;
  final List<String> audioChannels;
  final List<String> addonPriority;
  final String subtitleSource;
  final bool excludeLowQuality;
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
    this.audioFormats = const [],
    this.audioChannels = const [],
    this.addonPriority = const ['Torrentio', 'Comet', 'MediaFusion'],
    this.subtitleSource = 'any',
    this.excludeLowQuality = true,
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
  static const allAudioFormats = <String>['Atmos', 'TrueHD', 'DTS', 'EAC3', 'AAC'];
  static const allAudioChannels = <String>['Stereo', '5.1', '7.1'];
  static const subtitleSources = <String>['any', 'embedded', 'external'];
  static const cachePolicies = <String>['prefer', 'cachedOnly', 'readyOnly', 'all'];
  static const subtitlePolicies = <String>['prefer', 'require', 'none', 'all'];

  WatchSourceProfile copyWith({
    List<String>? resolutions, List<String>? addons, List<String>? codecs,
    List<String>? hdrFormats, List<String>? releaseTypes,
    List<String>? audioFormats, List<String>? audioChannels,
    List<String>? addonPriority, String? subtitleSource, bool? excludeLowQuality,
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
    audioFormats: audioFormats ?? this.audioFormats,
    audioChannels: audioChannels ?? this.audioChannels,
    addonPriority: addonPriority ?? this.addonPriority,
    subtitleSource: subtitleSource ?? this.subtitleSource,
    excludeLowQuality: excludeLowQuality ?? this.excludeLowQuality,
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
    if (raw.any((v) => v is! String || v.length > 128)) {
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
      audioFormats: _strings(raw['audioFormats'], allAudioFormats, fallback.audioFormats),
      audioChannels: _strings(raw['audioChannels'], allAudioChannels, fallback.audioChannels),
      addonPriority: _addonNames(raw['addonPriority']).isNotEmpty
          ? _addonNames(raw['addonPriority']) : fallback.addonPriority,
      subtitleSource: subtitleSources.contains(raw['subtitleSource'])
          ? raw['subtitleSource'] as String : 'any',
      excludeLowQuality: raw['excludeLowQuality'] is bool
          ? raw['excludeLowQuality'] as bool : true,
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
    'audioFormats': audioFormats, 'audioChannels': audioChannels,
    'addonPriority': addonPriority, 'subtitleSource': subtitleSource,
    'excludeLowQuality': excludeLowQuality,
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
    if (match != null) return match.group(1)?.toLowerCase();
    // Stremio may provide the torrent only in its P2P source hints.
    for (final hint in source.sources ?? const <String>[]) {
      final candidate = RegExp(r'(?:dht:|btih:)([0-9a-f]{40})(?![0-9a-f])',
          caseSensitive: false).firstMatch(hint);
      if (candidate != null) return candidate.group(1)?.toLowerCase();
    }
    return null;
  }

  /// Cache verification is scoped to the requested torrent file when supplied.
  /// A cached torrent hash alone cannot verify another episode's file index.
  static String? cacheKeyOf(StreamSource source,
      {int? season, int? episode}) {
    final hash = hashOf(source);
    if (hash == null) return null;
    final index = source.fileIdx;
    // A season pack without a fileIdx must not reuse another episode's hit.
    if (season != null && episode != null) {
      return '${hash}:s${season}e${episode}:${index}';
    }
    return index == null ? hash : '${hash}:${index}';
  }

  /// A playable HTTP link cannot by itself prove a TorBox torrent cache hit.
  static bool isPlayableDirectStream(StreamSource source) {
    final uri = Uri.tryParse(source.url ?? '');
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        !uri.host.endsWith('.invalid') &&
        !DebridSourceReadiness.isExplicitlyPending(source);
  }

  /// Only explicitly TorBox-configured playable addon links are reported
  /// ready. They MUST NOT be displayed as TorBox API verified.
  static bool isTorBoxAddonReady(StreamSource source) {
    if (!isPlayableDirectStream(source)) return false;
    final provider = source.addonName;
    final label = source.name ?? '';
    return RegExp(r'\b(torbox|tb|trb)\b', caseSensitive: false)
            .hasMatch(provider) ||
        RegExp(r'^\s*\[tb\+?\]', caseSensitive: false)
            .hasMatch(label);
  }

  static bool isAddonReportedReady(StreamSource source) {
    if (!isPlayableDirectStream(source)) return false;
    if (isTorBoxAddonReady(source)) return true;
    return RegExp(r'^\s*\[(rd|ad|pm)\+?\]', caseSensitive: false)
        .hasMatch(source.name ?? '');
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

  static String? audioFormat(StreamSource source) {
    final raw = ((source.name ?? '') + ' ' + (source.title ?? '')).toLowerCase();
    if (raw.contains('atmos')) return 'Atmos';
    if (raw.contains('truehd')) return 'TrueHD';
    if (raw.contains('dts')) return 'DTS';
    if (raw.contains('eac3') || raw.contains('ddp')) return 'EAC3';
    if (raw.contains('aac')) return 'AAC';
    return null;
  }

  static String? audioChannels(StreamSource source) {
    final raw = ((source.name ?? '') + ' ' + (source.title ?? '')).toLowerCase();
    if (RegExp(r'\b7[.]1\b').hasMatch(raw)) return '7.1';
    if (RegExp(r'\b5[.]1\b').hasMatch(raw)) return '5.1';
    if (RegExp(r'\bstereo\b|\b2[.]0\b').hasMatch(raw)) return 'Stereo';
    return null;
  }

  static String? subtitleSource(StreamSource source) {
    if (source.subtitles != null && source.subtitles!.isNotEmpty) return 'external';
    final raw = ((source.name ?? '') + ' ' + (source.title ?? '') +
        ' ' + (source.description ?? '')).toLowerCase();
    if (raw.contains('embedded subs') || raw.contains('internal subs')) {
      return 'embedded';
    }
    if (raw.contains('external subs')) return 'external';
    return null;
  }

  static bool isLowQuality(StreamSource source) {
    final raw = ((source.name ?? '') + ' ' + (source.title ?? '')).toLowerCase();
    return raw.contains('hdcam') ||
        RegExp(r'\b(cam|telesync|dvdscr|screener)\b').hasMatch(raw);
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

  static String cacheTier(StreamSource source, Map<String, bool> verified,
      {int? season, int? episode}) {
    if (DebridSourceReadiness.isExplicitlyPending(source)) return 'pending';
    final key = cacheKeyOf(source, season: season, episode: episode);
    if (key != null && verified.containsKey(key)) {
      return verified[key] == true ? 'verified' : 'uncached';
    }
    if (isAddonReportedReady(source)) return 'reported';
    return 'unknown';
  }

  static bool _match(String? value, List<String> allowed, bool unknown) =>
      allowed.isEmpty || (value == null ? unknown : allowed.contains(value));

  static bool _allowed(StreamSource source, WatchSourceProfile profile,
      Map<String, bool> verified, {int? season, int? episode}) {
    if (profile.addons.isNotEmpty &&
        !profile.addons.any((name) =>
            source.addonName.toLowerCase().contains(name.toLowerCase()))) return false;
    if (!_match(resolution(source), profile.resolutions, profile.allowUnknown)) return false;
    if (!_match(source.codec, profile.codecs, profile.allowUnknown)) return false;
    if (!_match(hdr(source), profile.hdrFormats, profile.allowUnknown)) return false;
    if (!_match(release(source), profile.releaseTypes, profile.allowUnknown)) return false;
    if (!_match(audioFormat(source), profile.audioFormats, profile.allowUnknown)) return false;
    if (!_match(audioChannels(source), profile.audioChannels, profile.allowUnknown)) return false;
    if (!_match(subtitleSource(source),
        profile.subtitleSource == 'any' ? const [] : [profile.subtitleSource],
        profile.allowUnknown)) return false;
    if (profile.excludeLowQuality && isLowQuality(source)) return false;
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
        cacheTier(source, verified,
            season: season, episode: episode) != 'verified') return false;
    if (profile.cachePolicy == 'readyOnly' &&
        !['verified', 'reported'].contains(cacheTier(source, verified,
            season: season, episode: episode))) return false;
    final subs = hasSubtitles(source);
    if (profile.subtitlePolicy == 'require' && subs != true) return false;
    if (profile.subtitlePolicy == 'none' && subs == true) return false;
    return true;
  }

  static double? _rank(StreamSource s, String criterion,
      Map<String, bool> verified, int original, WatchSourceProfile profile,
      {int? season, int? episode}) {
    switch (criterion) {
      case 'cache':
        switch (cacheTier(s, verified, season: season, episode: episode)) {
          case 'verified': return 4;
          case 'reported': return 3;
          case 'unknown': return 2;
          case 'pending': return 1;
          case 'uncached': return 0;
        }
        return null;
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
        for (var i = 0; i < profile.addonPriority.length; i++) {
          if (name.contains(profile.addonPriority[i].toLowerCase())) {
            return (profile.addonPriority.length - i).toDouble();
          }
        }
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
      WatchSourceProfile profile, {
      Map<String, bool> verified = const {},
      int? season,
      int? episode,
    }) {
    try {
      var selected = sources.where((s) => _allowed(s, profile, verified,
          season: season, episode: episode)).toList();
      // Fail open when a missing provider field or strict setting eliminates all
      // results. Do not silently leave users without a playback choice.
      if (selected.isEmpty && sources.isNotEmpty &&
          profile.cachePolicy != 'cachedOnly') {
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
          final ar = _rank(a, rule.criterion, verified, original[a] ?? 0, profile,
              season: season, episode: episode);
          final br = _rank(b, rule.criterion, verified, original[b] ?? 0, profile,
              season: season, episode: episode);
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
      // Strict cache filtering must fail closed even when sorting fails.
      if (profile.cachePolicy == 'cachedOnly') {
        return sources.where((source) =>
            cacheTier(source, verified,
                season: season, episode: episode) == 'verified').toList();
      }
      return List<StreamSource>.of(sources);
    }
  }
}

/// Cache lookups return a typed outcome so network and schema failures can be
/// distinguished from a genuine successful negative cache result.
class TorBoxCacheVerification {
  final Map<String, bool> statuses;
  final bool completed;
  final String? failureCode;

  const TorBoxCacheVerification(this.statuses,
      {required this.completed, this.failureCode});
}

/// Never marks a source verified from an addon title alone.
/// This is a bounded, read-only GET to TorBox's published checkcached endpoint.
class TorBoxCacheVerifier {
  TorBoxCacheVerifier._();
  static final instance = TorBoxCacheVerifier._();

  final Map<String, bool> _resultCache = <String, bool>{};
  DateTime? _cachedAt;

  /// Stremio fileIdx and TorBox file IDs need not use the same numbering.
  /// Use episode filenames as positive evidence when selecting TV episodes.
  static String? _episodeCode(String? text) {
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'\bs(\d{1,2})[ ._-]*e(\d{1,3})\b',
        caseSensitive: false).firstMatch(text) ??
        RegExp(r'\b(\d{1,2})x(\d{1,3})\b',
            caseSensitive: false).firstMatch(text);
    if (match == null) return null;
    final season = int.tryParse(match.group(1) ?? '');
    final episode = int.tryParse(match.group(2) ?? '');
    if (season == null || episode == null) return null;
    return '${season}:${episode}';
  }

  static bool _isVideoFile(String name) => RegExp(
    r'\.(mkv|mp4|m4v|avi|mov|wmv|ts|webm)$',
    caseSensitive: false,
  ).hasMatch(name);

  static bool? _fileAvailability(StreamSource source, Object? rawFiles,
      {int? season, int? episode}) {
    if (rawFiles is! List) return null;
    final videos = <String>[];
    for (final file in rawFiles) {
      if (file is! Map) continue;
      final filename = file['name']?.toString() ?? '';
      if (_isVideoFile(filename)) videos.add(filename);
    }
    if (videos.isEmpty) return null;

    final wantedEpisode = season != null && episode != null
        ? '${season}:${episode}'
        : _episodeCode('${source.title ?? ''} ${source.description ?? ''}');

    if (wantedEpisode != null) {
      final presentEpisodes = videos.map(_episodeCode).toList();
      if (presentEpisodes.contains(wantedEpisode)) return true;
      // A complete, explicitly numbered TV file list can prove absence.
      if (presentEpisodes.every((code) => code != null)) return false;
      // Ambiguous filenames cannot prove which episode is available.
      return null;
    }

    // A torrent with one video file is unambiguous. Multiple files whose
    // ordering cannot be matched remain unknown, not incorrectly uncached.
    if (videos.length == 1) return true;
    return null;
  }

  /// TorBox's object response maps hashes to cached torrent metadata.
  /// A true torrent-level hit does not automatically certify a TV file.
  static Map<String, bool> parseCacheResponse(
      Object? document, Iterable<StreamSource> sources,
      {int? season, int? episode}) {
    if (document is! Map ||
        document['success'] != true ||
        document['data'] is! Map) {
      return const <String, bool>{};
    }
    final entries = <String, Object?>{
      for (final entry in (document['data'] as Map).entries)
        entry.key.toString().toLowerCase(): entry.value,
    };
    final parsed = <String, bool>{};
    for (final source in sources) {
      final hash = WatchSourceEngine.hashOf(source);
      final key = WatchSourceEngine.cacheKeyOf(source,
          season: season, episode: episode);
      if (hash == null || key == null) continue;
      if (!entries.containsKey(hash)) {
        parsed[key] = false;
        continue;
      }
      final value = entries[hash];
      bool? cached;
      if (value is bool) {
        cached = value;
      } else if (value == null) {
        cached = false;
      } else if (value is Map) {
        if (value['cached'] is bool) {
          cached = value['cached'] as bool;
        } else if (value['is_cached'] is bool) {
          cached = value['is_cached'] as bool;
        } else if (value['hash']?.toString().toLowerCase() == hash ||
            value.containsKey('name') ||
            value.containsKey('files')) {
          cached = true;
        }
      }

      // A torrent-level yes is insufficient if a specific episode or file
      // was selected. Check actual video filenames from TorBox's file list.
      if (cached == true &&
          (source.fileIdx != null || (season != null && episode != null))) {
        cached = _fileAvailability(source,
            value is Map ? value['files'] : null,
            season: season, episode: episode);
      }
      if (cached != null) parsed[key] = cached;
    }
    return parsed;
  }

  Future<Map<String, bool>> verify(List<StreamSource> sources,
      {int? season, int? episode}) async {
    return (await verifyWithStatus(sources,
        season: season, episode: episode)).statuses;
  }

  Future<TorBoxCacheVerification> verifyWithStatus(
      List<StreamSource> sources, {int? season, int? episode}) async {
    if (_cachedAt != null &&
        DateTime.now().difference(_cachedAt!) > const Duration(minutes: 45)) {
      _resultCache.clear();
      _cachedAt = null;
    }
    final unique = <String, StreamSource>{};
    for (final source in sources) {
      final key = WatchSourceEngine.cacheKeyOf(source,
          season: season, episode: episode);
      if (key != null) unique.putIfAbsent(key, () => source);
    }
    if (unique.isEmpty) {
      return const TorBoxCacheVerification({}, completed: true);
    }
    final missing = unique.entries
        .where((entry) => !_resultCache.containsKey(entry.key))
        .take(80)
        .map((entry) => entry.value)
        .toList();
    if (missing.isEmpty) {
      return TorBoxCacheVerification({
        for (final cacheKey in unique.keys)
          if (_resultCache.containsKey(cacheKey))
            cacheKey: _resultCache[cacheKey]!,
      }, completed: true);
    }
    try {
      final apiKey = await TorBoxService().getKey();
      if (apiKey == null || apiKey.trim().isEmpty) {
        return TorBoxCacheVerification({
          for (final cacheKey in unique.keys)
            if (_resultCache.containsKey(cacheKey))
              cacheKey: _resultCache[cacheKey]!,
        }, completed: false, failureCode: 'missing_key');
      }

      final hashes = missing.map(WatchSourceEngine.hashOf)
          .whereType<String>().toSet().toList();
      final uri = Uri.https('api.torbox.app',
          '/v1/api/torrents/checkcached', {
        'hash': hashes.join(','),
        'format': 'object',
        'list_files': 'true',
      });
      final response = await http.get(uri,
          headers: {'Authorization': 'Bearer $apiKey'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[WatchSources] Cache lookup HTTP ${response.statusCode}');
        return TorBoxCacheVerification({
          for (final cacheKey in unique.keys)
            if (_resultCache.containsKey(cacheKey))
              cacheKey: _resultCache[cacheKey]!,
        }, completed: false, failureCode: 'http_error');
      }

      final parsed = parseCacheResponse(jsonDecode(response.body), missing,
          season: season, episode: episode);
      _resultCache.addAll(parsed);
      if (parsed.isNotEmpty) _cachedAt = DateTime.now();
      final complete = missing.every((source) =>
          _resultCache.containsKey(WatchSourceEngine.cacheKeyOf(source,
              season: season, episode: episode)));

      return TorBoxCacheVerification({
        for (final cacheKey in unique.keys)
          if (_resultCache.containsKey(cacheKey))
            cacheKey: _resultCache[cacheKey]!,
      }, completed: complete,
          failureCode: complete ? null : 'file_unverified');
    } catch (error) {
      debugPrint('[WatchSources] Cache lookup unavailable: '
          '${error.runtimeType}');
      return TorBoxCacheVerification({
        for (final cacheKey in unique.keys)
          if (_resultCache.containsKey(cacheKey))
            cacheKey: _resultCache[cacheKey]!,
      }, completed: false, failureCode: 'network_error');
    }
  }
}
