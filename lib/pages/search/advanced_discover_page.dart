import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/metadata/tmdb_discover_service.dart';
import '../details/details_page.dart';

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
  };
  final service = TmdbDiscoverService.instance;
  final fromController = TextEditingController();
  final toController = TextEditingController();
  final ScrollController _resultsScrollController = ScrollController();
  DiscoverType type = DiscoverType.movie;
  String country = '', language = '', order = 'popularity.desc';
  List<DiscoverTitle> titles = [];
  int page = 0, totalPages = 0, totalResults = 0, serial = 0;
  int? openingId, appliedStart, appliedEnd;
  bool loading = false, hasKey = false, applied = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    serial++;
    fromController.dispose();
    toController.dispose();
    _resultsScrollController.dispose();
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
      filters = DiscoverFilters(
        type: type,
        fromYear: _year(fromController),
        toYear: _year(toController),
        country: country.isEmpty ? null : country,
        originalLanguage: language.isEmpty ? null : language,
        sort: order,
        page: reset ? 1 : page + 1,
      );
      filters.toQuery();
    } catch (e) {
      setState(() => error = e.toString());
      return;
    }
    if (!reset && (page == 0 || page >= totalPages)) return;
    final request = ++serial;
    // Remember the exact page boundary before adding more results. We scroll
    // forward only a little afterwards, not to the far end of the new page.
    final previousOffset = _resultsScrollController.hasClients
        ? _resultsScrollController.offset : 0.0;
    setState(() {
      loading = true;
      error = null;
      if (reset) {
        titles = [];
        page = 0;
        applied = false;
      }
    });
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      if (reset) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('adv_discover_type',
            type == DiscoverType.series ? 'series' : 'movie');
        await prefs.setString('adv_discover_country', country);
        await prefs.setString('adv_discover_language', language);
        await prefs.setString('adv_discover_from', fromController.text.trim());
        await prefs.setString('adv_discover_to', toController.text.trim());
        await prefs.setString('adv_discover_sort', order);
      }
      final response = await service.browse(filters);
      if (!mounted || request != serial) return;
      final known = <int>{...titles.map((item) => item.tmdbId)};
      final incoming = response.titles
          .where((item) => known.add(item.tmdbId)).toList();
      setState(() {
        titles = [...titles, ...incoming];
        page = response.page;
        totalPages = response.totalPages;
        totalResults = response.totalResults;
        applied = true;
        appliedStart = filters.fromYear ?? filters.toYear;
        appliedEnd = filters.toYear ?? filters.fromYear;
      });
      if (!reset && incoming.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || request != serial ||
              !_resultsScrollController.hasClients) return;
          final position = _resultsScrollController.position;
          // Move into the first new rows while keeping the previous page
          // partly visible for orientation. Never jump to the very bottom.
          final advance = (position.viewportDimension * 0.38)
              .clamp(100.0, 260.0);
          final target = (previousOffset + advance)
              .clamp(0.0, position.maxScrollExtent).toDouble();
          _resultsScrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
          );
        });
      }
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
      await Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => DetailsPage(
            movie: movie,
            navigationTrail: const ['Discover'],
          )));
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
    final yearLabel = item.type == DiscoverType.series &&
        appliedStart != null && appliedEnd != null
      ? 'Started $debut · Episodes ${appliedStart == appliedEnd
          ? appliedStart : '$appliedStart–$appliedEnd'}'
      : debut;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF171A24),
      child: InkWell(
        onTap: openingId == null ? () => _open(item) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: item.poster == null
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
                Text(yearLabel, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 10)),
                if (item.rating > 0)
                  Text('★ ${item.rating.toStringAsFixed(1)}',
                      style: const TextStyle(color: Color(0xFFFFD166),
                          fontSize: 11)),
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
        key: const PageStorageKey<String>('advanced-discover-results'),
        controller: _resultsScrollController,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Browse without typing a title. Filter by year range, '
              'country and language.'),
          const SizedBox(height: 14),
          SegmentedButton<DiscoverType>(
            segments: const [
              ButtonSegment(value: DiscoverType.movie,
                  label: Text('Movies'), icon: Icon(Icons.movie)),
              ButtonSegment(value: DiscoverType.series,
                  label: Text('TV Series'), icon: Icon(Icons.tv)),
            ],
            selected: {type},
            onSelectionChanged: (v) => setState(() => type = v.first),
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
            label: const Text('Discover Titles'),
          ),
          if (!hasKey) Card(child: ListTile(
            title: const Text('Add TMDB API key to get started'),
            subtitle: const Text('Use your existing TMDB key. TVDB is not needed.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _keyDialog,
          )),
          const SizedBox(height: 12),
          Text(type == DiscoverType.series
              ? 'TV years use episodes airing during the selected range, '
                'not the original premiere year. Older series returning '
                'in 2026 can appear when TMDB lists those episodes.'
              : 'Movie years use TMDB primary release dates.',
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 5),
          const Text('Country = production origin; language = original '
              'language, not English dubbed-audio availability.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
          if ((loading && !applied) || openingId != null) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 20),
          if (applied) ...[
            Text(totalResults == 0
                ? 'No matches; try different filters'
                : '$totalResults matches · Page $page/$totalPages',
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
            if (loading) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
            if (page < totalPages)
              OutlinedButton.icon(
                onPressed: loading ? null : () => _browse(reset: false),
                icon: const Icon(Icons.expand_more),
                label: const Text('Load More'),
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
