/// Correct legacy first-release years and escaped titles without changing
/// the v1 watchlist file's underlying identifiers or schema.
abstract final class MyListNormalize {
  static int? releaseYear(Object? raw) {
    if (raw == null) return null;
    final m = RegExp(r'(?:18|19|20|21)\d{2}').firstMatch(raw.toString());
    if (m == null) return null;
    final year = int.tryParse(m.group(0)!);
    return year != null && year <= DateTime.now().year + 5 ? year : null;
  }

  static String title(String source) {
    var text = source;
    const values = <String, String>{
      '&quot;': '"', '&amp;': '&', '&apos;': "'",
      '&#39;': "'", '&lt;': '<', '&gt;': '>', '&nbsp;': ' ',
    };
    for (final entry in values.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text.replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|\d+);'), (match) {
      final digits = match.group(1)!;
      final code = digits.startsWith('x')
          ? int.tryParse(digits.substring(1), radix: 16) : int.tryParse(digits);
      if (code == null || code < 32 || code > 0x10ffff ||
          (code >= 0xd800 && code <= 0xdfff)) return match.group(0)!;
      return String.fromCharCode(code);
    });
  }

  /// Legacy zone-less date strings cannot reveal the original device's zone.
  /// Treat them deterministically as UTC on both devices. New dates carry Z.
  static DateTime? legacyDate(Object? raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    final zoned = RegExp(r'(?:Z|[+-]\d{2}:\d{2})$', caseSensitive: false)
        .hasMatch(text);
    return DateTime.tryParse(zoned ? text : text + 'Z')?.toUtc();
  }
}

enum MyListSource { local, trakt, simkl }

class MyListItem {
  final int? traktId;
  final int? simklId;
  final String? imdbId;
  final int? tmdbId;
  final String title;
  final int? year;
  final String type;
  final String? poster;
  final DateTime addedAt;
  final MyListSource source;

  const MyListItem({
    this.traktId,
    this.simklId,
    this.imdbId,
    this.tmdbId,
    required this.title,
    this.year,
    required this.type,
    this.poster,
    required this.addedAt,
    this.source = MyListSource.local,
  });

  String get uniqueKey {
    if (imdbId != null && imdbId!.isNotEmpty) return 'imdb:$imdbId';
    if (tmdbId != null) return 'tmdb:$type:$tmdbId';
    if (traktId != null) return 'trakt:$traktId';
    if (simklId != null) return 'simkl:$simklId';
    final clean = title.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
    return 'title:$type:$clean:${year ?? 0}';
  }

  bool matches(MyListItem other) {
    if (imdbId != null && other.imdbId != null && imdbId!.isNotEmpty && other.imdbId!.isNotEmpty) {
      return imdbId == other.imdbId;
    }
    if (tmdbId != null && other.tmdbId != null) {
      return tmdbId == other.tmdbId && type == other.type;
    }
    if (traktId != null && other.traktId != null) {
      return traktId == other.traktId;
    }
    if (simklId != null && other.simklId != null) {
      return simklId == other.simklId;
    }

    // Don't fallback to title if there are conflicting IDs of the same authority
    final hasConflictingIds = (imdbId != null && other.imdbId != null && imdbId != other.imdbId) ||
        (tmdbId != null && other.tmdbId != null && tmdbId != other.tmdbId) ||
        (traktId != null && other.traktId != null && traktId != other.traktId) ||
        (simklId != null && other.simklId != null && simklId != other.simklId);

    if (hasConflictingIds) return false;

    final cleanA = title.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
    final cleanB = other.title.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
    if (cleanA.isNotEmpty && cleanA == cleanB && (year == null || other.year == null || (year! - other.year!).abs() <= 1)) {
      return type == other.type;
    }
    return false;
  }

  MyListItem mergeWith(MyListItem other) {
    return copyWith(
      traktId: other.traktId ?? traktId,
      simklId: other.simklId ?? simklId,
      imdbId: (other.imdbId != null && other.imdbId!.isNotEmpty) ? other.imdbId : imdbId,
      tmdbId: other.tmdbId ?? tmdbId,
      poster: poster ?? other.poster,
      source: other.source != MyListSource.local ? other.source : source,
    );
  }

  factory MyListItem.fromMovie({
    required String id,
    required String name,
    String? poster,
    String? year,
    required String type,
    String? imdbId,
    int? tmdbId,
    int? traktId,
    int? simklId,
  }) {
    return MyListItem(
      imdbId: id.startsWith('tt') ? id : imdbId,
      tmdbId: tmdbId ?? (int.tryParse(id) != null && !id.startsWith('tt') ? int.tryParse(id) : null),
      traktId: traktId,
      simklId: simklId,
      title: name,
      poster: poster,
      year: MyListNormalize.releaseYear(year),
      type: type == 'series' || type == 'anime' ? 'series' : 'movie',
      addedAt: DateTime.now(),
      source: MyListSource.local,
    );
  }

  factory MyListItem.fromMovieDetail({
    required String id,
    required String name,
    String? poster,
    String? year,
    required String type,
    String? imdbId,
    int? tmdbId,
    int? traktId,
    int? simklId,
  }) {
    return MyListItem(
      imdbId: id.startsWith('tt') ? id : imdbId,
      tmdbId: tmdbId ?? (int.tryParse(id) != null && !id.startsWith('tt') ? int.tryParse(id) : null),
      traktId: traktId,
      simklId: simklId,
      title: name,
      poster: poster,
      year: MyListNormalize.releaseYear(year),
      type: type == 'series' || type == 'anime' ? 'series' : 'movie',
      addedAt: DateTime.now(),
      source: MyListSource.local,
    );
  }

  factory MyListItem.fromTraktJson(Map<String, dynamic> json) {
    final movie = json['movie'] as Map<String, dynamic>?;
    final show = json['show'] as Map<String, dynamic>?;
    final media = movie ?? show ?? json;
    final ids = media['ids'] as Map<String, dynamic>? ?? {};
    final imdbId = ids['imdb']?.toString();
    return MyListItem(
      traktId: ids['trakt'] as int?,
      imdbId: imdbId,
      tmdbId: ids['tmdb'] as int?,
      title: media['title']?.toString() ?? 'Unknown',
      year: media['year'] as int?,
      type: (media['type']?.toString() == 'show' || show != null) ? 'series' : 'movie',
      poster: imdbId != null ? 'https://images.metahub.space/poster/medium/$imdbId/img' : null,
      addedAt: json['listed_at'] != null
          ? DateTime.tryParse(json['listed_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      source: MyListSource.trakt,
    );
  }

  factory MyListItem.fromSimklJson(Map<String, dynamic> json) {
    final movie = json['movie'] as Map<String, dynamic>?;
    final show = json['show'] as Map<String, dynamic>? ?? json['anime'] as Map<String, dynamic>?;
    final media = movie ?? show ?? json;
    final ids = media['ids'] as Map<String, dynamic>? ?? {};
    final imdbId = ids['imdb']?.toString();
    final posterPath = media['poster'] as String?;
    final posterUrl = posterPath != null
        ? 'https://simkl.in/posters/${posterPath}_m.jpg'
        : (imdbId != null ? 'https://images.metahub.space/poster/medium/$imdbId/img' : null);

    return MyListItem(
      simklId: ids['simkl'] as int?,
      imdbId: imdbId,
      tmdbId: ids['tmdb'] as int?,
      title: media['title']?.toString() ?? 'Unknown',
      year: media['year'] as int?,
      type: (movie != null) ? 'movie' : 'series',
      poster: posterUrl,
      addedAt: json['last_watched_at'] != null
          ? DateTime.tryParse(json['last_watched_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      source: MyListSource.simkl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'traktId': traktId,
      'simklId': simklId,
      'imdbId': imdbId,
      'tmdbId': tmdbId,
      'title': title,
      'year': year,
      'type': type,
      'poster': poster,
      'addedAt': addedAt.toUtc().toIso8601String(),
      'source': source.name,
    };
  }

  factory MyListItem.fromJson(Map<String, dynamic> json) {
    MyListSource src = MyListSource.local;
    if (json['source'] == 'trakt') {
      src = MyListSource.trakt;
    } else if (json['source'] == 'simkl') {
      src = MyListSource.simkl;
    }
    return MyListItem(
      traktId: json['traktId'] as int?,
      simklId: json['simklId'] as int?,
      imdbId: json['imdbId']?.toString(),
      tmdbId: json['tmdbId'] as int?,
      title: MyListNormalize.title(json['title']?.toString() ?? 'Unknown'),
      year: MyListNormalize.releaseYear(json['year']),
      type: json['type']?.toString() ?? 'movie',
      poster: json['poster']?.toString(),
      addedAt: MyListNormalize.legacyDate(json['addedAt']) ?? DateTime.now().toUtc(),
      source: src,
    );
  }

  MyListItem copyWith({
    int? traktId,
    int? simklId,
    String? imdbId,
    int? tmdbId,
    String? title,
    int? year,
    String? type,
    String? poster,
    DateTime? addedAt,
    MyListSource? source,
  }) {
    return MyListItem(
      traktId: traktId ?? this.traktId,
      simklId: simklId ?? this.simklId,
      imdbId: imdbId ?? this.imdbId,
      tmdbId: tmdbId ?? this.tmdbId,
      title: title ?? this.title,
      year: year ?? this.year,
      type: type ?? this.type,
      poster: poster ?? this.poster,
      addedAt: addedAt ?? this.addedAt,
      source: source ?? this.source,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MyListItem && uniqueKey == other.uniqueKey;

  @override
  int get hashCode => uniqueKey.hashCode;
}
