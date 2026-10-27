import 'tmdb_discover_service.dart';

/// Streaming provider availability and broadcaster provenance are different:
/// watch-provider results are regional, whereas TV networks list originals.
enum NetworkSource { streaming, tvNetwork }
enum NetworkFeed { trending, hot, popular }

class NetworkChoice {
  final int id;
  final String name;
  final NetworkSource source;
  final String? logo;
  final bool movies;
  final bool series;
  final int sortPriority;

  const NetworkChoice({
    required this.id,
    required this.name,
    required this.source,
    this.logo,
    this.movies = true,
    this.series = true,
    this.sortPriority = 999999,
  });

  String get uniqueKey => '${source.name}:$id';

  /// Networks with both media types expose one choice, not duplicate chips.
  static List<NetworkChoice> parseStreaming(
    Map<String, dynamic> movieData,
    Map<String, dynamic> seriesData,
    String region,
  ) {
    final found = <int, NetworkChoice>{};
    for (final pair in <(Map<String, dynamic>, bool)>[
      (movieData, true), (seriesData, false),
    ]) {
      final rows = pair.$1['results'];
      if (rows is! List) continue;
      for (final item in rows) {
        if (item is! Map) continue;
        final id = (item['provider_id'] as num?)?.toInt();
        final name = item['provider_name']?.toString() ?? '';
        final priorities = item['display_priorities'];
        if (id == null || id <= 0 || name.isEmpty ||
            priorities is! Map || !priorities.containsKey(region)) continue;
        final priority = (priorities[region] as num?)?.toInt() ?? 999999;
        final logoPath = item['logo_path']?.toString() ?? '';
        final prior = found[id];
        found[id] = NetworkChoice(
          id: id, name: name, source: NetworkSource.streaming,
          logo: logoPath.isEmpty ? null
              : 'https://image.tmdb.org/t/p/w92$logoPath',
          movies: pair.$2 || (prior?.movies ?? false),
          series: !pair.$2 || (prior?.series ?? false),
          sortPriority: priority < (prior?.sortPriority ?? 999999)
              ? priority : (prior?.sortPriority ?? priority),
        );
      }
    }
    final choices = found.values.toList();
    choices.sort((a, b) {
      final featured = featuredRank(a.name).compareTo(featuredRank(b.name));
      if (featured != 0) return featured;
      final priority = a.sortPriority.compareTo(b.sortPriority);
      return priority != 0 ? priority
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return choices;
  }

  static const featureNames = <String>[
    'netflix', 'amazon prime video', 'disney plus',
    'hbo max', 'max', 'paramount plus', 'apple tv plus',
    'hulu', 'peacock', 'showtime', 'crunchyroll', 'mubi',
    'britbox', 'amc plus', 'starz', 'bbc iplayer',
    'viu', 'iqiyi', 'tubi', 'pluto tv', 'rakuten viki',
    'discovery plus', 'zee5', 'jiohotstar', 'hotstar',
  ];

  static int featuredRank(String name) {
    final normalized = name.toLowerCase()
        .replaceAll('+', ' plus ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    for (var i = 0; i < featureNames.length; i++) {
      if (normalized == featureNames[i]) return i;
    }
    return 1000;
  }

  static const tvNetworks = <NetworkChoice>[
    NetworkChoice(id: 213, name: 'Netflix', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 49, name: 'HBO', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 1899, name: 'Max', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 389, name: 'Showtime', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 67, name: 'Paramount+', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 1024, name: 'Prime Video', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 2739, name: 'Disney+', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 2552, name: 'Apple TV+', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 453, name: 'Hulu', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 2697, name: 'Peacock', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 88, name: 'FX', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 174, name: 'AMC', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 318, name: 'Starz', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 4, name: 'BBC One', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 6, name: 'NBC', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 16, name: 'CBS', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 2, name: 'ABC', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 19, name: 'FOX', source: NetworkSource.tvNetwork),
    NetworkChoice(id: 71, name: 'The CW', source: NetworkSource.tvNetwork),
  ];
}

class NetworkDiscoverQuery {
  final NetworkChoice choice;
  final DiscoverType type;
  final String region;
  final NetworkFeed feed;
  final int page;
  final DateTime now;

  const NetworkDiscoverQuery({
    required this.choice,
    required this.type,
    required this.region,
    required this.feed,
    this.page = 1,
    required this.now,
  });

  /// TMDB has no per-provider trending chart. Use explainable Discover
  /// proxies: recent popular premieres, well-rated, and broad popularity.
  String get explanation => switch (feed) {
    NetworkFeed.trending => 'Popular recent releases (past 12 months)',
    NetworkFeed.hot => 'Highly rated titles with 100+ votes',
    NetworkFeed.popular => 'Most popular titles overall',
  };

  Map<String, String> toQuery() {
    if (choice.id <= 0 || page <= 0 ||
        (choice.source == NetworkSource.tvNetwork &&
            type != DiscoverType.series)) {
      throw const FormatException('Invalid network discovery selection.');
    }
    final query = <String, String>{
      'page': '$page',
      'language': 'en-US',
      'include_adult': 'false',
      'sort_by': feed == NetworkFeed.hot
          ? 'vote_average.desc' : 'popularity.desc',
      if (feed == NetworkFeed.hot) 'vote_count.gte': '100',
    };
    if (choice.source == NetworkSource.streaming) {
      if (!RegExp(r'^[A-Z]{2}$').hasMatch(region)) {
        throw const FormatException('Choose a valid availability region.');
      }
      query['with_watch_providers'] = '${choice.id}';
      query['watch_region'] = region;
      // Allow subscription AND ad/free providers; do not silently exclude
      // free services or suggest streaming rights in another country.
    } else {
      query['with_networks'] = '${choice.id}';
    }
    if (feed == NetworkFeed.trending) {
      final start = DateTime.utc(now.year - 1, now.month, now.day);
      final date = '${start.year.toString().padLeft(4, '0')}-'
          '${start.month.toString().padLeft(2, '0')}-'
          '${start.day.toString().padLeft(2, '0')}';
      query[type == DiscoverType.movie
          ? 'primary_release_date.gte' : 'air_date.gte'] = date;
    }
    return query;
  }
}

class NetworkDiscoverService {
  NetworkDiscoverService._();
  static final NetworkDiscoverService instance = NetworkDiscoverService._();

  final TmdbDiscoverService _tmdb = TmdbDiscoverService.instance;

  Future<List<NetworkChoice>> loadStreaming(String region) async {
    final both = await Future.wait([
      _tmdb.networkProviderCatalog(DiscoverType.movie),
      _tmdb.networkProviderCatalog(DiscoverType.series),
    ]);
    return NetworkChoice.parseStreaming(both[0], both[1], region);
  }

  Future<DiscoverResults> browse(NetworkDiscoverQuery request) =>
      _tmdb.networkDiscover(request.type, request.toQuery());
}
