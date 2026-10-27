import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import 'tmdb_discover_service.dart';

/// Production metadata, NEVER audio/dubbing/subtitle availability.
class TitleOriginLanguage {
  final List<String> countries;
  final String? language;
  const TitleOriginLanguage({this.countries = const [], this.language});

  static const empty = TitleOriginLanguage();

  static String languageName(String? code) {
    const known = <String, String>{
      'en': 'English', 'ko': 'Korean', 'ja': 'Japanese',
      'zh': 'Chinese', 'fr': 'French', 'de': 'German',
      'es': 'Spanish', 'hi': 'Hindi', 'ta': 'Tamil',
      'te': 'Telugu', 'th': 'Thai', 'tr': 'Turkish',
      'ar': 'Arabic', 'pt': 'Portuguese', 'id': 'Indonesian',
      'it': 'Italian', 'ru': 'Russian', 'tl': 'Filipino',
      'ms': 'Malay', 'vi': 'Vietnamese', 'bn': 'Bengali',
      'pl': 'Polish', 'sv': 'Swedish', 'da': 'Danish',
      'nl': 'Dutch', 'no': 'Norwegian', 'he': 'Hebrew',
      'fa': 'Persian', 'uk': 'Ukrainian',
    };
    final value = code?.trim() ?? '';
    if (value.isEmpty) return 'Not listed';
    if (value.length > 3) return value; // Already a language name.
    return known[value.toLowerCase()] ?? value.toUpperCase();
  }

  static String countryName(String code) {
    const countries = <String, String>{
      'KR': 'South Korea', 'KP': 'North Korea',
      'US': 'United States', 'GB': 'United Kingdom',
      'JP': 'Japan', 'CN': 'China', 'TW': 'Taiwan',
      'HK': 'Hong Kong', 'SG': 'Singapore', 'IN': 'India',
      'MY': 'Malaysia', 'ID': 'Indonesia', 'TH': 'Thailand',
      'PH': 'Philippines', 'VN': 'Vietnam', 'AU': 'Australia',
      'NZ': 'New Zealand', 'CA': 'Canada', 'FR': 'France',
      'DE': 'Germany', 'ES': 'Spain', 'IT': 'Italy',
      'BR': 'Brazil', 'MX': 'Mexico', 'TR': 'Turkey',
      'RU': 'Russia', 'UA': 'Ukraine', 'SE': 'Sweden',
      'DK': 'Denmark', 'NO': 'Norway', 'NL': 'Netherlands',
      'BE': 'Belgium', 'PL': 'Poland', 'AR': 'Argentina',
      'ZA': 'South Africa', 'EG': 'Egypt', 'AE': 'UAE',
      'SA': 'Saudi Arabia', 'IL': 'Israel', 'IR': 'Iran',
    };
    return countries[code.toUpperCase()] ?? code;
  }

  String get countryLabel => countries.isEmpty ? 'Not listed' :
      countries.map(countryName).join(', ');

  String get languageLabel => languageName(language);

  /// English is the ORIGINAL production language, not a dubbed audio track.
  static TitleOriginLanguage fromTmdb(Map<String, dynamic> data,
      {required bool series}) {
    final countryList = series
        ? data['origin_country'] : data['production_countries'];
    final countries = <String>[];
    if (countryList is List) {
      for (final value in countryList) {
        final code = (value is Map
                ? value['iso_3166_1'] ?? value['name'] : value)
            ?.toString().trim() ?? '';
        if (code.isNotEmpty && !countries.contains(code)) {
          countries.add(code);
        }
      }
    }
    final lang = data['original_language']?.toString();
    return TitleOriginLanguage(
      countries: countries.take(3).toList(),
      language: lang?.isNotEmpty == true ? lang : null,
    );
  }
}

/// Shared future cache and global request budget for scrollable title cards.
/// TMDB additionally handles spacing, 429 cooldown and 24h response caching.
/// At most 24 on-demand card enrichments/minute; detailed pages bypass the
/// card budget and do not wait for a Home grid to finish.
class TitleOriginLanguageService {
  TitleOriginLanguageService._();
  static final instance = TitleOriginLanguageService._();
  final Map<String, Future<TitleOriginLanguage>> _pending = {};
  final List<DateTime> _cardRequests = [];

  Future<TitleOriginLanguage> resolve({
    required String titleId,
    required String type,
    int? tmdbId,
    List<String> knownCountries = const [],
    String? knownLanguage,
    bool detailPage = false,
  }) {
    final known = TitleOriginLanguage(
      countries: knownCountries.where((x) => x.trim().isNotEmpty).toList(),
      language: knownLanguage,
    );
    if (known.countries.isNotEmpty && known.language != null &&
        known.language!.trim().isNotEmpty) {
      return Future.value(known);
    }
    final media = Movie.canonicalType(type);
    if (media != 'movie' && media != 'series' && media != 'anime') {
      return Future.value(known);
    }
    final id = titleId.trim();
    if ((tmdbId == null || tmdbId <= 0) &&
        !RegExp(r'^tt\d+$').hasMatch(id)) {
      return Future.value(known);
    }
    final key = '${media == 'movie' ? 'movie' : 'tv'}:'
        '${tmdbId != null && tmdbId > 0 ? tmdbId : id}';
    final current = _pending[key];
    if (current != null) {
      return current.then((found) => TitleOriginLanguage(
        countries: known.countries.isNotEmpty
            ? known.countries : found.countries,
        language: known.language?.isNotEmpty == true
            ? known.language : found.language,
      ));
    }

    final now = DateTime.now();
    _cardRequests.removeWhere((value) =>
        now.difference(value) >= const Duration(minutes: 1));
    if (!detailPage && _cardRequests.length >= 24) {
      return Future.value(known);
    }
    if (!detailPage) _cardRequests.add(now);
    final future = TmdbDiscoverService.instance.titleOriginLanguage(
      imdbId: id, tmdbId: tmdbId,
      isSeries: media != 'movie',
    ).then((data) => TitleOriginLanguage.fromTmdb(
      data, series: media != 'movie',
    )).catchError((Object _) => TitleOriginLanguage.empty);
    // No sensitive fields are used as cache keys.
    _pending[key] = future;
    if (_pending.length > 180) _pending.remove(_pending.keys.first);
    return future.then((found) => TitleOriginLanguage(
      countries: known.countries.isNotEmpty
          ? known.countries : found.countries,
      language: known.language?.isNotEmpty == true
          ? known.language : found.language,
    ));
  }

  @visibleForTesting
  void resetForTesting() {
    _pending.clear();
    _cardRequests.clear();
  }
}

/// Reuse across the shared MovieCard, Discover/Networks/person results,
/// My List, Continue Watching, and the main Details page.
class OriginLanguageLabel extends StatefulWidget {
  final String titleId;
  final String type;
  final int? tmdbId;
  final List<String> knownCountries;
  final String? knownLanguage;
  final bool detailPage;
  final bool compact;

  const OriginLanguageLabel({
    super.key,
    required this.titleId,
    required this.type,
    this.tmdbId,
    this.knownCountries = const [],
    this.knownLanguage,
    this.detailPage = false,
    this.compact = true,
  });

  @override
  State<OriginLanguageLabel> createState() => _OriginLanguageLabelState();
}

class _OriginLanguageLabelState extends State<OriginLanguageLabel> {
  late Future<TitleOriginLanguage> _future;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(covariant OriginLanguageLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.titleId != oldWidget.titleId ||
        widget.tmdbId != oldWidget.tmdbId ||
        widget.type != oldWidget.type ||
        widget.knownLanguage != oldWidget.knownLanguage ||
        widget.knownCountries.join('|') != oldWidget.knownCountries.join('|')) {
      _lookup();
    }
  }

  void _lookup() {
    _future = TitleOriginLanguageService.instance.resolve(
      titleId: widget.titleId,
      tmdbId: widget.tmdbId,
      type: widget.type,
      knownCountries: widget.knownCountries,
      knownLanguage: widget.knownLanguage,
      detailPage: widget.detailPage,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TitleOriginLanguage>(
    future: _future,
    builder: (context, snapshot) {
      final details = snapshot.data ?? TitleOriginLanguage(
        countries: widget.knownCountries,
        language: widget.knownLanguage,
      );
      final size = widget.compact ? 10.5 : 13.0;
      final style = TextStyle(
        color: Colors.white.withValues(alpha: widget.compact ? 0.62 : 0.75),
        fontSize: size, height: 1.25,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Origin: ${details.countryLabel}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          Text('Original language: ${details.languageLabel}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ],
      );
    },
  );
}
