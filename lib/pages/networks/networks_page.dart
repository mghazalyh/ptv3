import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/metadata/network_discover_service.dart';
import '../../services/metadata/tmdb_discover_service.dart';
import '../../services/theme/dock_settings.dart';
import '../../widgets/common/app_liquid_dock.dart';
import '../details/details_page.dart';
import '../../services/metadata/title_origin_language_service.dart';
import '../search/advanced_discover_page.dart';

class NetworksPage extends StatefulWidget {
  const NetworksPage({super.key});
  @override
  State<NetworksPage> createState() => _NetworksPageState();
}

class _NetworksPageState extends State<NetworksPage> {
  static const regions = <String, String>{
    'SG':'Singapore', 'US':'United States', 'GB':'United Kingdom',
    'CA':'Canada', 'AU':'Australia', 'IN':'India', 'JP':'Japan',
    'KR':'South Korea', 'FR':'France', 'DE':'Germany', 'IT':'Italy',
    'ES':'Spain', 'BR':'Brazil', 'MX':'Mexico', 'ID':'Indonesia',
    'TH':'Thailand', 'PH':'Philippines', 'MY':'Malaysia',
    'NZ':'New Zealand', 'ZA':'South Africa',
  };
  final api = NetworkDiscoverService.instance;
  final tmdb = TmdbDiscoverService.instance;
  String region = 'SG';
  NetworkSource source = NetworkSource.streaming;
  DiscoverType type = DiscoverType.series;
  NetworkFeed feed = NetworkFeed.popular;
  List<NetworkChoice> providers = [];
  NetworkChoice? selected;
  List<DiscoverTitle> titles = [];
  bool catalogLoading = true, loading = false;
  String? error, catalogError;
  int page = 0, totalPages = 0, generation = 0, catalogGeneration = 0;
  int? openingId;

  List<NetworkChoice> get choices =>
      source == NetworkSource.tvNetwork ? NetworkChoice.tvNetworks :
      providers.where((p) => type == DiscoverType.series
          ? p.series : p.movies).toList();

  @override
  void initState() { super.initState(); _restore(); }
  @override
  void dispose() { generation++; catalogGeneration++; super.dispose(); }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        final r = prefs.getString('networks_region');
        if (regions.containsKey(r)) region = r!;
        source = prefs.getString('networks_source') == 'tvNetwork'
            ? NetworkSource.tvNetwork : NetworkSource.streaming;
        type = prefs.getString('networks_type') == 'movie' &&
            source == NetworkSource.streaming
            ? DiscoverType.movie : DiscoverType.series;
        feed = NetworkFeed.values.firstWhere(
          (x) => x.name == prefs.getString('networks_feed'),
          orElse: () => NetworkFeed.popular);
      });
    } catch (_) { /* Use defaults if local preferences cannot be read. */ }
    await _loadProviders();
  }
  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('networks_region', region);
      await p.setString('networks_source', source.name);
      await p.setString('networks_type', type.name);
      await p.setString('networks_feed', feed.name);
    } catch (_) { /* Network browsing should work without persistence. */ }
  }
  void _chooseDefault() {
    final available = choices;
    final previous = selected;
    selected = available.isEmpty ? null : available.first;
    if (previous != null) {
      for (final c in available) {
        if (c.uniqueKey == previous.uniqueKey) { selected = c; break; }
      }
    }
  }
  Future<void> _loadProviders() async {
    final id = ++catalogGeneration;
    generation++;
    setState(() { catalogLoading = source == NetworkSource.streaming;
      catalogError = null; });
    if (source == NetworkSource.streaming) {
      try {
        final fetched = await api.loadStreaming(region);
        if (!mounted || id != catalogGeneration) return;
        setState(() { providers = fetched; catalogLoading = false;
          _chooseDefault(); });
      } catch (_) {
        if (!mounted || id != catalogGeneration) return;
        setState(() { catalogLoading = false; providers = []; selected = null;
          catalogError = 'Could not load TMDB providers. Check your TMDB key '
              'under Discover and your internet connection.'; });
        return;
      }
    } else {
      setState(() { catalogLoading = false; _chooseDefault(); });
    }
    await _browse(reset: true);
  }
  Future<void> _changeSource(NetworkSource next) async {
    if (source == next) return;
    setState(() {
      source = next; selected = null; titles = []; page = 0;
      if (next == NetworkSource.tvNetwork) type = DiscoverType.series;
    });
    await _save(); await _loadProviders();
  }
  Future<void> _changeType(DiscoverType next) async {
    if (type == next || source == NetworkSource.tvNetwork) return;
    setState(() { type = next; _chooseDefault(); });
    await _save(); await _browse(reset: true);
  }
  Future<void> _changeFeed(NetworkFeed next) async {
    if (feed == next) return;
    setState(() => feed = next);
    await _save(); await _browse(reset: true);
  }
  Future<void> _changeRegion(String next) async {
    if (region == next) return;
    setState(() => region = next);
    await _save(); await _loadProviders();
  }
  Future<void> _browse({required bool reset}) async {
    if (selected == null || (!reset && (loading || page >= totalPages))) return;
    final ticket = ++generation;
    final query = NetworkDiscoverQuery(
      choice: selected!, type: type, region: region, feed: feed,
      page: reset ? 1 : page + 1, now: DateTime.now().toUtc(),
    );
    setState(() {
      loading = true; error = null;
      if (reset) { titles = []; page = 0; totalPages = 0; }
    });
    try {
      final found = await api.browse(query);
      if (!mounted || ticket != generation) return;
      setState(() {
        final existing = <int>{...titles.map((x) => x.tmdbId)};
        titles = reset ? found.titles : [
          ...titles, ...found.titles.where((x) => existing.add(x.tmdbId)),
        ];
        page = found.page; totalPages = found.totalPages; loading = false;
      });
    } catch (e) {
      if (!mounted || ticket != generation) return;
      setState(() { loading = false; error = e is FormatException
          ? e.message : 'Could not load these titles. Try again.'; });
    }
  }
  Future<void> _open(DiscoverTitle title) async {
    if (openingId != null) return;
    setState(() => openingId = title.tmdbId);
    try {
      final movie = await tmdb.resolveMovie(title);
      if (!mounted) return;
      if (movie == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No IMDb/Stremio match for this title.')));
        return;
      }
      await Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => DetailsPage(movie: movie)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open title.')));
    } finally { if (mounted) setState(() => openingId = null); }
  }
  void _allProviders() {
    String term = '';
    final values = choices;
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true,
      backgroundColor: const Color(0xFF171A24),
      builder: (sheet) => StatefulBuilder(builder: (context, update) {
        final matches = values.where((x) =>
            x.name.toLowerCase().contains(term)).toList();
        return SafeArea(child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Find any service or TV network'),
                onChanged: (s) => update(() => term = s.trim().toLowerCase()),
              )),
            Text('${matches.length} providers',
              style: const TextStyle(color: Colors.white60)),
            Expanded(child: ListView.builder(
              itemCount: matches.length,
              itemBuilder: (_, i) {
                final c = matches[i];
                return ListTile(
                  leading: c.logo == null ? const Icon(Icons.live_tv)
                    : CachedNetworkImage(imageUrl: c.logo!, width: 38,
                        errorWidget: (_, __, ___) => const Icon(Icons.live_tv)),
                  title: Text(c.name),
                  subtitle: Text(c.source == NetworkSource.tvNetwork
                      ? 'Original TV network' : [
                      if (c.movies) 'Movies', if (c.series) 'Series'].join(' · ')),
                  onTap: () { Navigator.pop(sheet);
                    setState(() => selected = c); _browse(reset: true); },
                );
              },
            )),
          ]),
        ));
      }),
    );
  }
  Widget _poster(DiscoverTitle item) => Card(
    color: const Color(0xFF191D29), clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: openingId == null ? () => _open(item) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: item.poster == null
            ? const Center(child: Icon(Icons.movie_outlined))
            : CachedNetworkImage(imageUrl: item.poster!, fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined))),
        Padding(padding: const EdgeInsets.all(7), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.bold)),
            Text([
              if (item.premiereYear != null) '${item.premiereYear}',
              item.type == DiscoverType.movie ? 'Movie' : 'Series',
              if (item.rating > 0) '★ ${item.rating.toStringAsFixed(1)}',
            ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 10)),
            const SizedBox(height: 4),
            OriginLanguageLabel(
              titleId: '',
              tmdbId: item.tmdbId,
              type: item.type == DiscoverType.series ? 'series' : 'movie',
              knownCountries: item.originCountries,
              knownLanguage: item.originalLanguage,
            ),
          ],
        )),
      ]),
    ),
  );
  Widget _results() {
    if (catalogLoading || (loading && titles.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    final issue = catalogError ?? error;
    if (issue != null && titles.isEmpty) return Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.all(20), child: Text(issue,
            textAlign: TextAlign.center)),
        FilledButton(onPressed: catalogError == null
            ? () => _browse(reset: true) : _loadProviders,
            child: const Text('Retry')),
        TextButton(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) =>
                  const AdvancedDiscoverPage())),
          child: const Text('Configure TMDB in Discover'),
        ),
      ],
    ));
    if (selected == null) return const Center(child: Text(
        'No providers in this region. Choose another country or TV networks.'));
    if (titles.isEmpty) return const Center(child: Text(
        'No matching titles. Try a different category.'));
    return LayoutBuilder(builder: (context, size) {
      final cols = size.maxWidth > 1000 ? 7 :
          size.maxWidth > 750 ? 5 : size.maxWidth > 500 ? 4 : 2;
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 150),
        itemCount: titles.length + (page < totalPages ? 1 : 0),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols, mainAxisSpacing: 8,
          crossAxisSpacing: 8, childAspectRatio: 0.48),
        itemBuilder: (_, i) => i < titles.length ? _poster(titles[i])
            : Center(child: loading ? const CircularProgressIndicator()
                : TextButton(onPressed: () => _browse(reset: false),
                    child: const Text('Load more'))),
      );
    });
  }
  @override
  Widget build(BuildContext context) {
    final current = selected;
    final explanation = current == null ? '' : NetworkDiscoverQuery(
      choice: current, type: type, region: region, feed: feed,
      now: DateTime.now().toUtc()).explanation;
    return Scaffold(
      backgroundColor: const Color(0xFF0C1018),
      appBar: AppBar(title: const Text('Networks'),
        actions: [IconButton(icon: const Icon(Icons.refresh),
          tooltip: 'Refresh titles', onPressed: () => _browse(reset: true))]),
      body: Stack(children: [
        Column(children: [
          Padding(padding: const EdgeInsets.all(8), child: Wrap(
            spacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(label: const Text('Streaming'),
                selected: source == NetworkSource.streaming,
                onSelected: (_) => _changeSource(NetworkSource.streaming)),
              ChoiceChip(label: const Text('TV Networks'),
                selected: source == NetworkSource.tvNetwork,
                onSelected: (_) => _changeSource(NetworkSource.tvNetwork)),
              if (source == NetworkSource.streaming) DropdownButton<String>(
                value: region, items: regions.entries.map((x) =>
                  DropdownMenuItem(value: x.key, child: Text(x.value))).toList(),
                onChanged: (v) { if (v != null) _changeRegion(v); }),
            ],
          )),
          SizedBox(height: 44, child: ListView(
            scrollDirection: Axis.horizontal, children: [
              for (final c in choices.where((p) =>
                p.source == NetworkSource.tvNetwork ||
                NetworkChoice.featuredRank(p.name) < 1000).take(24))
                Padding(padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(label: Text(c.name),
                    selected: selected?.uniqueKey == c.uniqueKey,
                    onSelected: (_) {
                      setState(() => selected = c); _browse(reset: true);
                    })),
            ],
          )),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              Expanded(child: Text(current?.name ?? 'Choose a provider',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16,
                  fontWeight: FontWeight.bold))),
              OutlinedButton.icon(onPressed: choices.isEmpty ? null : _allProviders,
                icon: const Icon(Icons.apps, size: 16),
                label: Text('All (${choices.length})')),
            ])),
          if (source == NetworkSource.streaming) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              ChoiceChip(label: const Text('Movies'),
                selected: type == DiscoverType.movie,
                onSelected: (_) => _changeType(DiscoverType.movie)),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Series'),
                selected: type == DiscoverType.series,
                onSelected: (_) => _changeType(DiscoverType.series)),
            ]),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              for (final x in NetworkFeed.values) ...[
                ChoiceChip(label: Text(switch (x) {
                  NetworkFeed.trending => 'Trending',
                  NetworkFeed.hot => 'Hot',
                  NetworkFeed.popular => 'Popular',
                }), selected: feed == x,
                  onSelected: (_) => _changeFeed(x)),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Align(alignment: Alignment.centerLeft,
              child: Text([
                explanation,
                source == NetworkSource.streaming
                  ? 'Available in ${regions[region]}'
                  : 'Original network · not a streaming guarantee',
              ].join(' · '), style: const TextStyle(
                color: Colors.white60, fontSize: 11)))),
          Expanded(child: _results()),
        ]),
        Positioned(left: 0, right: 0,
          bottom: 8 + MediaQuery.paddingOf(context).bottom,
          child: AppLiquidDock(currentDestination: DockItemKey.networks)),
      ]),
    );
  }
}
