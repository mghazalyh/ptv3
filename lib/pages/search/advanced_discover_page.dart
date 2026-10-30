import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/metadata/tmdb_discover_service.dart';
import '../details/details_page.dart';
import '../../services/metadata/title_origin_language_service.dart';
import '../../widgets/movie/series_year_label.dart';

class AdvancedDiscoverPage extends StatefulWidget {
  const AdvancedDiscoverPage({super.key});
  @override
  State<AdvancedDiscoverPage> createState() => _AdvancedDiscoverPageState();
}

class _AdvancedDiscoverPageState extends State<AdvancedDiscoverPage> {
  static const countries = <String, String>{
    '': 'Any country', 'US': 'United States', 'GB': 'United Kingdom',
    'CA': 'Canada', 'AU': 'Australia', 'IN': 'India', 'JP': 'Japan',
    'KR': 'South Korea', 'FR': 'France', 'DE': 'Germany',
    'ES': 'Spain', 'IT': 'Italy', 'BR': 'Brazil', 'MX': 'Mexico',
    'CN': 'China', 'TR': 'Türkiye', 'TH': 'Thailand',
    'ID': 'Indonesia', 'PH': 'Philippines', 'SE': 'Sweden',
    'NO': 'Norway', 'DK': 'Denmark', 'ZA': 'South Africa',
  };
  static const languages = <String, String>{
    '': 'Any language', 'en': 'English', 'es': 'Spanish',
    'fr': 'French', 'de': 'German', 'it': 'Italian',
    'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese',
    'hi': 'Hindi', 'ta': 'Tamil', 'te': 'Telugu',
    'ar': 'Arabic', 'pt': 'Portuguese', 'tr': 'Turkish',
    'th': 'Thai', 'id': 'Indonesian', 'tl': 'Filipino',
    'sv': 'Swedish', 'no': 'Norwegian', 'da': 'Danish',
    'ru': 'Russian',
  };
  static const sortOptions = <String, String>{
    'popularity.desc': 'Most popular',
    'vote_average.desc': 'Top rated',
    'vote_count.desc': 'Most reviewed',
    'trending.week': 'Trending this week (TMDB)',
  };
  final service = TmdbDiscoverService.instance;
  final ScrollController _discoverScroll = ScrollController();
  final titleController = TextEditingController();
  final fromController = TextEditingController();
  final toController = TextEditingController();
  DiscoverType type = DiscoverType.movie;
  String country = '', language = '', genre = '', order = 'popularity.desc';
  List<DiscoverTitle> titles = [];
  int page = 0, totalPages = 0, totalResults = 0, serial = 0;
  int? openingId;
  bool loading = false, hasKey = false, applied = false;
  String? error;
  DiscoverFilters? _appliedFilters;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    serial++;
    _discoverScroll.dispose();
    titleController.dispose();
    fromController.dispose();
    toController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await service.readKey();
      if (!mounted) return;
      setState(() {
        type = prefs.getString('adv_discover_type') == 'series'
            ? DiscoverType.series : DiscoverType.movie;
        final c = prefs.getString('adv_discover_country') ?? '';
        final l = prefs.getString('adv_discover_language') ?? '';
        country = countries.containsKey(c) ? c : '';
        language = languages.containsKey(l) ? l : '';
        final g = prefs.getString('adv_discover_genre') ?? '';
        genre = DiscoverGenres.options(type).containsKey(g) ? g : '';
        titleController.text = prefs.getString('adv_discover_query') ?? '';
        fromController.text = prefs.getString('adv_discover_from') ?? '';
        toController.text = prefs.getString('adv_discover_to') ?? '';
        final s = prefs.getString('adv_discover_sort') ?? '';
        order = sortOptions.containsKey(s) ? s : 'popularity.desc';
        hasKey = key.isNotEmpty;
      });
      if (hasKey) await _browse(reset: true);
    } catch (_) {
      if (mounted) setState(() => error = 'Cannot restore saved filters.');
    }
  }

  int? _year(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 1900 || value > 2100) {
      throw const FormatException('Enter a valid year between 1900 and 2100.');
    }
    return value;
  }

  Future<void> _browse({required bool reset}) async {
    if (loading || !hasKey) return;
    DiscoverFilters filters;
    try {
      // Paging must continue the APPLIED search, even if the user has
      // edited title or filters without pressing Search again.
      filters = !reset && _appliedFilters != null
        ? _appliedFilters!.withPage(page + 1)
        : DiscoverFilters(
            type: type,
            titleQuery: titleController.text.trim(),
            fromYear: _year(fromController),
            toYear: _year(toController),
            country: country.isEmpty ? null : country,
            originalLanguage: language.isEmpty ? null : language,
            genreId: genre.isEmpty ? null : int.parse(genre),
            sort: order,
            page: 1,
          );
      filters.toQuery();
    } catch (e) {
      setState(() => error = e.toString());
      return;
    }
    if (!reset && (page == 0 || page >= totalPages)) return;
    // Pagination must leave the user's scroll offset exactly where it is.
    // An explicitly new search returns to the form at the top.
    if (reset && _discoverScroll.hasClients) _discoverScroll.jumpTo(0);
    final request = ++serial;
    setState(() {
      loading = true;
      error = null;
      if (reset) {
        titles = [];
        page = 0;
        applied = false;
      }
    });
    if (reset) FocusManager.instance.primaryFocus?.unfocus();
    try {
      if (reset) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('adv_discover_query',
            titleController.text.trim());
        await prefs.setString('adv_discover_type',
            type == DiscoverType.series ? 'series' : 'movie');
        await prefs.setString('adv_discover_country', country);
        await prefs.setString('adv_discover_language', language);
        await prefs.setString('adv_discover_genre', genre);
        await prefs.setString('adv_discover_from', fromController.text.trim());
        await prefs.setString('adv_discover_to', toController.text.trim());
        await prefs.setString('adv_discover_sort', order);
      }
      final response = await service.browse(filters);
      if (!mounted || request != serial) return;
      final known = <int>{...titles.map((item) => item.tmdbId)};
      setState(() {
        titles = [...titles,
          ...response.titles.where((item) => known.add(item.tmdbId))];
        page = response.page;
        totalPages = response.totalPages;
        totalResults = response.totalResults;
        applied = true;
        _appliedFilters = filters;
      });

    } catch (e) {
      if (mounted && request == serial) {
        setState(() => error = e.toString().replaceFirst('FormatException: ', ''));
      }
    } finally {
      if (mounted && request == serial) setState(() => loading = false);
    }
  }

  Future<void> _keyDialog() async {
    final controller = TextEditingController(text: await service.readKey());
    if (!mounted) {
      controller.dispose();
      return;
    }
    final result = await showDialog<String>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('TMDB API Key'),
        content: SizedBox(width: 440, child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            const Text('Use your TMDB v3 API key or API read-access token. '
                'The key stays on this iPad, never in the GitHub repository.'),
            const SizedBox(height: 12),
            TextField(controller: controller, obscureText: true,
              autocorrect: false, enableSuggestions: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'TMDB key or token')),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('Remove key')),
          FilledButton(onPressed: () => Navigator.pop(
              dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || result == null) return;
    await service.saveKey(result);
    if (!mounted) return;
    setState(() {
      hasKey = result.isNotEmpty;
      titles = [];
      applied = false;
      error = null;
    });
    if (hasKey) await _browse(reset: true);
  }

  Future<void> _open(DiscoverTitle title) async {
    if (openingId != null) return;
    setState(() => openingId = title.tmdbId);
    try {
      final movie = await service.resolveMovie(title);
      if (!mounted) return;
      if (movie == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No IMDb/Stremio match exists for this title.')));
        return;
      }
      final offset = _discoverScroll.hasClients ? _discoverScroll.offset : null;
      await Navigator.push(context, PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) =>
            DetailsPage(movie: movie, disableEntranceAnimation: true),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ));
      if (mounted && offset != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_discoverScroll.hasClients) return;
          _discoverScroll.jumpTo(offset.clamp(
              0.0, _discoverScroll.position.maxScrollExtent).toDouble());
        });
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cannot open title. Check your connection.')));
    } finally {
      if (mounted) setState(() => openingId = null);
    }
  }

  void _preset(String start, String end) {
    setState(() {
      fromController.text = start;
      toController.text = end;
    });
    _browse(reset: true);
  }

  Widget _selector(String label, String value, Map<String, String> options,
      ValueChanged<String?> change) => DropdownButtonFormField<String>(
    value: value, isExpanded: true, onChanged: change,
    decoration: InputDecoration(
        border: const OutlineInputBorder(), labelText: label, isDense: true),
    items: options.entries.map((entry) => DropdownMenuItem(
      value: entry.key,
      child: Text(entry.value, overflow: TextOverflow.ellipsis),
    )).toList(),
  );

  Widget _yearInput(String label, TextEditingController controller) =>
      TextField(
        controller: controller, keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        decoration: InputDecoration(
          border: const OutlineInputBorder(), labelText: label, hintText: '2026',
          isDense: true),
        onSubmitted: (_) => _browse(reset: true),
      );

  Widget _card(DiscoverTitle item) {
    final debut = item.premiereYear?.toString() ?? 'Year unknown';
    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF171A24),
      child: InkWell(
        onTap: openingId == null ? () => _open(item) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: openingId == item.tmdbId
                ? const Center(child: CircularProgressIndicator(
                    key: ValueKey('discover-card-opening'),
                    strokeWidth: 2.5))
                : item.poster == null
                ? const Center(child: Icon(Icons.movie_creation_outlined,
                    size: 40))
                : CachedNetworkImage(
                    imageUrl: item.poster!, fit: BoxFit.cover,
                    placeholder: (_, __) => const ColoredBox(
                        color: Color(0xFF202632)),
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.broken_image_outlined))),
            Padding(padding: const EdgeInsets.all(9), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 3),
                if (item.type == DiscoverType.series)
                  SeriesYearLabel(
                    key: ValueKey('series-run-${item.tmdbId}'),
                    tmdbId: item.tmdbId,
                    fallbackYear: item.premiereYear?.toString(),
                    showUnreleased: !item.isUnreleased,
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 10),
                  )
                else
                  Text(debut, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 10)),
                if (item.isUnreleased)
                  const Text('UNRELEASED',
                      key: ValueKey('discover-unreleased-badge'),
                      style: TextStyle(color: Color(0xFFFBBF24),
                          fontSize: 10, fontWeight: FontWeight.bold)),
                if (item.rating > 0)
                  Text('★ ${item.rating.toStringAsFixed(1)}',
                      style: const TextStyle(color: Color(0xFFFFD166),
                          fontSize: 11)),
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 1100 ? 6 : width > 800 ? 5
        : width > 540 ? 4 : width > 350 ? 3 : 2;
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        title: const Text('Discover Movies & Series'),
        backgroundColor: const Color(0xFF080A0F),
        actions: [IconButton(
          tooltip: 'Configure TMDB API key',
          onPressed: _keyDialog,
          icon: const Icon(Icons.key_outlined),
        )],
      ),
      body: SafeArea(child: ListView(
        key: const PageStorageKey<String>('advanced-discover-scroll'),
        controller: _discoverScroll,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Optionally enter a title, then combine it with your '
              'year, genre, country, language and sort filters. Leave the title '
              'blank to browse everything.'),
          const SizedBox(height: 14),
          SegmentedButton<DiscoverType>(
            segments: const [
              ButtonSegment(value: DiscoverType.movie,
                  label: Text('Movies'), icon: Icon(Icons.movie)),
              ButtonSegment(value: DiscoverType.series,
                  label: Text('TV Series'), icon: Icon(Icons.tv)),
            ],
            selected: {type},
            onSelectionChanged: (v) => setState(() {
              type = v.first;
              // TMDB's genre IDs differ between movies and TV series.
              if (!DiscoverGenres.options(type).containsKey(genre)) {
                genre = '';
              }
            }),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: titleController,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Movie or TV show title (optional)',
              hintText: 'e.g. The Order',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: titleController.text.isEmpty ? null : IconButton(
                tooltip: 'Clear title and browse with filters',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => titleController.clear()),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _browse(reset: true),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _yearInput('From year', fromController)),
            const SizedBox(width: 12),
            Expanded(child: _yearInput('To year', toController)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 7, runSpacing: 4, children: [
            ActionChip(label: const Text('2026'),
                onPressed: () => _preset('2026', '2026')),
            ActionChip(label: const Text('2020–2026'),
                onPressed: () => _preset('2020', '2026')),
            ActionChip(label: const Text('2000–2003'),
                onPressed: () => _preset('2000', '2003')),
            ActionChip(label: const Text('Any year'),
                onPressed: () => _preset('', '')),
          ]),
          const SizedBox(height: 13),
          _selector('Genre (optional)', genre, DiscoverGenres.options(type),
              (v) => setState(() => genre = v ?? '')),
          const SizedBox(height: 12),
          _selector('Country of origin', country, countries,
              (v) => setState(() => country = v ?? '')),
          const SizedBox(height: 12),
          _selector('Original language', language, languages,
              (v) => setState(() => language = v ?? '')),
          const SizedBox(height: 12),
          _selector('Sort by', order, sortOptions,
              (v) => setState(() => order = v ?? 'popularity.desc')),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: hasKey && !loading
                ? () => _browse(reset: true) : null,
            icon: const Icon(Icons.tune),
            label: Text(titleController.text.trim().isEmpty
                ? 'Discover Titles' : 'Search Titles & Apply Filters'),
          ),
          if (!hasKey) Card(child: ListTile(
            title: const Text('Add TMDB API key to get started'),
            subtitle: const Text('Use your existing TMDB key. TVDB is not needed.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _keyDialog,
          )),
          const SizedBox(height: 12),
          Text(type == DiscoverType.series
              ? 'TV years filter by series premiere, not later episodes or '
                'specials. Weekly trending results come from TMDB.'
              : 'Movie years use original release dates. Weekly trending '
                'results come from TMDB.',
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 5),
          const Text('Country = production origin; language = original '
              'language, not English dubbed-audio availability.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
          if (loading && !applied) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 20),
          if (applied) ...[
            Text((_appliedFilters?.sort == 'trending.week')
                ? '${titles.length} matches on TMDB weekly trending '
                  'page $page/$totalPages'
                : _appliedFilters?.hasTitleQuery == true
                    ? (titles.isEmpty
                        ? 'No matching titles on this search page'
                        : '${titles.length} filtered titles · '
                          'Search page $page/$totalPages')
                    : (totalResults == 0
                        ? 'No matches; try different filters'
                        : '$totalResults candidates · ${titles.length} '
                          'matching cards loaded · Page $page/$totalPages'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: titles.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns, mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: width > 800 ? 0.64 : 0.59,
              ),
              itemBuilder: (_, i) => _card(titles[i]),
            ),
            if (page < totalPages)
              OutlinedButton.icon(
                onPressed: loading ? null : () => _browse(reset: false),
                icon: Icon(loading ? Icons.hourglass_top : Icons.expand_more),
                label: Text(loading ? 'Loading...' : 'Load More'),
              ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Metadata and poster images from TMDB. This product uses '
            'the TMDB API but is not endorsed or certified by TMDB.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
        ],
      )),
    );
  }
}
