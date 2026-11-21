import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/metadata/tmdb_discover_service.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/movie/movie_card.dart';
import '../../services/player/live_tv/live_channel_health_scanner.dart';
import '../../services/player/live_tv/live_native_channel_verifier.dart';
import '../../services/player/live_tv/live_stream_detector.dart';

class CatalogPage extends StatefulWidget {
  final MovieSection section;

  const CatalogPage({
    super.key,
    required this.section,
  });

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage>
    with WidgetsBindingObserver {
  final List<Movie> _items = [];
  bool _isLoading = false;
  bool _hasMore = false;
  int _remoteOffset = 0;
  int _relatedPage = 1;
  int _requestSerial = 0;
  final Map<String, LiveChannelHealthResult> _health = {};
  bool _scanRunning = false;
  bool _nativeScanRunning = false;
  bool _foreground = true;
  int _scanEpoch = 0;
  int _scannedCount = 0;
  int _scanTotal = 0;
  int _nativeScannedCount = 0;
  int _nativeScanTotal = 0;
  bool get _isLiveCatalog =>
      Movie.canonicalType(widget.section.contentType) == 'tv' ||
      Movie.canonicalType(widget.section.contentType) == 'channel' ||
      widget.section.movies.any((movie) =>
        LiveStreamDetector.isLiveChannel(
          mediaType: movie.type, mediaId: movie.id));

  // The Home row is the authoritative first page. A synthetic list, missing
  // addon URL or catalog without 'skip' never becomes a generic Cinemeta
  // request, even if a caller forgot to mark that section curated.
  bool get _isSynthetic => widget.section.isCurated ||
      const {
        'bestsimilar', 'bestsimilar_list', 'bestsimilar_watching',
        'trakt_recommendations', 'simkl_recommendations',
      }.contains(widget.section.catalog.id);

  bool get _hasValidSource {
    final url = Uri.tryParse(widget.section.addonBaseUrl.trim());
    return url != null && (url.scheme == 'https' || url.scheme == 'http') &&
        url.host.isNotEmpty;
  }

  bool get _canPage => !_isSynthetic &&
      _hasValidSource && widget.section.catalog.supportsSkip;
  // Only curated TMDB rows with the exact watched source may page TMDB.
  bool get _canRelatedPage => _isSynthetic &&
      widget.section.relatedSourceTitle?.trim().isNotEmpty == true &&
      widget.section.movies.any((m) => m.recommendationSource == 'TMDB');
  bool get _isSnapshot => !_canPage;
  String? _error;

  String? _selectedGenre;
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  final ScrollController _scrollController = ScrollController();
  final ScrollController _genreScrollController = ScrollController();

  bool _canScrollGenresLeft = false;
  bool _canScrollGenresRight = true;
  bool _isHoveringGenres = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _items.addAll(widget.section.movies);
    _remoteOffset = _items.length;
    _hasMore = _canPage || _canRelatedPage;
    _genreScrollController.addListener(_updateGenreScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateGenreScrollButtons();
    });
    // Avoid a duplicate initial fetch: See All first displays exactly
    // what the tapped section showed. Page two uses the same addon/catalog.
    if (_items.isEmpty && _canPage) _loadItems(refresh: true);
    if (_isLiveCatalog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startLiveScan());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _scanEpoch++;
      if (mounted) {
        setState(() {
          _scanRunning = false;
          _nativeScanRunning = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanEpoch++;
    _requestSerial++;
    _scrollController.dispose();
    _genreScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startLiveScan() async {
    if (!_isLiveCatalog || _scanRunning ||
        _nativeScanRunning || !mounted || !_foreground) return;
    final epoch = ++_scanEpoch;
    setState(() {
      _scanRunning = true;
      _scannedCount = 0;
      _scanTotal = _items.length;
      _nativeScannedCount = 0;
      _nativeScanTotal = 0;
      _health.clear();
    });
    final pending = <Movie>[];
    final ids = <String>{};
    void enqueue(Iterable<Movie> items) {
      for (final movie in items) {
        if (!LiveStreamDetector.isLiveChannel(
            mediaType: movie.type, mediaId: movie.id)) continue;
        if (ids.add(movie.id)) pending.add(movie);
      }
      if (mounted && epoch == _scanEpoch) {
        setState(() => _scanTotal = pending.length);
      }
    }
    enqueue(_items);
    var cursor = 0;
    var pagingFinished = false;
    bool cancelled() => !mounted || epoch != _scanEpoch ||
        !_foreground || ModalRoute.of(context)?.isCurrent != true;
    Future<void> worker() async {
      while (!cancelled()) {
        if (cursor >= pending.length) {
          if (pagingFinished) return;
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        final movie = pending[cursor++];
        final result = await LiveChannelHealthScanner.inspect(movie);
        if (cancelled()) return;
        setState(() {
          _health[movie.id] = result;
          _scannedCount++;
        });
      }
    }
    final workers = List.generate(4, (_) => worker());
    try {
      // Load subsequent Stremio catalog pages so the scan does not stop
      // at the Home row or an artificial 100-channel limit.
      var pages = 0;
      while (!cancelled() && _canPage && _hasMore &&
          !_isSearching && _selectedGenre == null &&
          _items.length < 2000 && pages < 30) {
        if (_isLoading) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          enqueue(_items);
          continue;
        }
        enqueue(_items);
        final priorCount = _items.length;
        await _loadItems();
        if (cancelled()) break;
        if (_items.length <= priorCount) break;
        enqueue(_items.skip(priorCount));
        pages++;
      }
    } catch (error) {
      debugPrint('[LiveHealthScan] Catalog paging: ${error.runtimeType}');
    } finally {
      pagingFinished = true;
      await Future.wait(workers);
      if (mounted && epoch == _scanEpoch) {
        setState(() => _scanRunning = false);
      }
    }

    // Only after every eligible catalog page has completed its HTTP
    // quickscan do we sort the grid. Then verify decoded native video on
    // the iPad, one muted Player at a time, upgrading trustworthy results.
    if (cancelled() || !LiveNativeChannelVerifier.isSupported) return;
    setState(() {
      _nativeScanRunning = true;
      _nativeScannedCount = 0;
      _nativeScanTotal = pending.length;
    });
    try {
      for (final movie in pending) {
        if (cancelled()) break;
        final prior = _health[movie.id];
        if (prior == null) continue;
        final verified = await LiveChannelHealthScanner.verifyNative(
          movie, prior, isCancelled: cancelled,
        );
        if (cancelled()) break;
        setState(() {
          _health[movie.id] = verified;
          _nativeScannedCount++;
        });
      }
    } catch (error) {
      debugPrint('[LiveHealthScan] Native batch: ' +
          error.runtimeType.toString());
    } finally {
      if (mounted && epoch == _scanEpoch) {
        setState(() => _nativeScanRunning = false);
      }
    }
  }

  void _updateGenreScrollButtons() {
    if (!_genreScrollController.hasClients) return;
    setState(() {
      _canScrollGenresLeft = _genreScrollController.position.pixels > 0;
      _canScrollGenresRight =
          _genreScrollController.position.pixels < _genreScrollController.position.maxScrollExtent;
    });
  }

  void _scrollGenres(double directionMultiplier) {
    if (!_genreScrollController.hasClients) return;
    final viewportWidth = _genreScrollController.position.viewportDimension;
    final target = _genreScrollController.offset + (viewportWidth * 0.7 * directionMultiplier);
    _genreScrollController.animateTo(
      target.clamp(0.0, _genreScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadItems({bool refresh = false}) async {
    if (!mounted) return;

    // Curated TMDB cards page only their original verified watched title.
    // The existing snapshot stays intact when the provider is unavailable.
    if (_canRelatedPage) {
      if (refresh) {
        ++_requestSerial;
        setState(() {
          _items..clear()..addAll(widget.section.movies);
          _relatedPage = 1;
          _hasMore = true;
          _isLoading = false;
          _error = null;
        });
        return;
      }
      if (!_hasMore || _isLoading) return;
      final serial = ++_requestSerial;
      setState(() { _isLoading = true; _error = null; });
      try {
        final known = _items.map((m) => 'tmdb:' +
            (m.tmdbId?.toString() ?? m.id)).toSet();
        final more = <Movie>[];
        var hasMore = false;
        var attempts = 0;
        do {
          final page = await TmdbDiscoverService.instance.moreRelatedTitles(
            title: widget.section.relatedSourceTitle!,
            startYear: widget.section.relatedSourceYear,
            imdbId: widget.section.relatedSourceImdbId,
            tmdbId: widget.section.relatedSourceTmdbId,
            type: Movie.canonicalType(widget.section.contentType) == 'series'
                ? DiscoverType.series : DiscoverType.movie,
            page: _relatedPage,
          );
          if (!mounted || serial != _requestSerial) return;
          ++_relatedPage;
          hasMore = page.hasMore;
          for (final item in page.items) {
            if (!known.add('tmdb:' + item.tmdbId.toString())) continue;
            more.add(Movie(
              id: 'tmdb_${item.tmdbId}', name: item.title,
              type: item.type == DiscoverType.series ? 'series' : 'movie',
              poster: item.poster, year: item.premiereYear?.toString(),
              addonBaseUrl: 'https://v3-cinemeta.strem.io',
              imdbRating: item.rating > 0
                  ? item.rating.toStringAsFixed(1) : null,
              tmdbId: item.tmdbId,
              originCountries: item.originCountries,
              originalLanguage: item.originalLanguage,
              recommendationSource: 'TMDB',
            ));
          }
          ++attempts;
          // Home shows 18 results; page 1 may be mostly duplicates.
        } while (more.isEmpty && hasMore && attempts < 2);
        if (!mounted || serial != _requestSerial) return;
        setState(() {
          _items.addAll(more);
          _hasMore = hasMore && _relatedPage <= 10;
          _isLoading = false;
        });
      } catch (error) {
        debugPrint('[Catalog] TMDB recommendation page: ${error.runtimeType}');
        if (!mounted || serial != _requestSerial) return;
        setState(() {
          _error = 'More recommendations are unavailable; existing titles are unchanged.';
          _isLoading = false;
        });
      }
      return;
    }

    // No network fallback to a "top" Cinemeta catalog, or to the wrong
    // addon, for recommendations and non-paginated source sections.
    if (_isSnapshot) {
      if (refresh) {
        setState(() {
          _items..clear()..addAll(widget.section.movies);
          _hasMore = false;
          _isLoading = false;
          _error = null;
        });
      }
      return;
    }

    if (refresh) {
      _requestSerial++;
      setState(() {
        // If no filter/search is applied, preserve the row's exact ranked
        // items as page 1. Never replace them with other generic results.
        _items.clear();
        if (!_isSearching && _selectedGenre == null) {
          _items.addAll(widget.section.movies);
        }
        _remoteOffset = _items.length;
        _hasMore = true;
        _isLoading = false; // Cancel stale searches/pages before starting new.
        _error = null;
      });
      if (_items.isNotEmpty) return;
    }
    if (!_hasMore || _isLoading) return;
    final serial = ++_requestSerial;
    setState(() => _isLoading = true);

    try {
      final List<Movie> fetched;
      if (_isSearching && _searchQuery.isNotEmpty &&
          widget.section.catalog.supportsSearch) {
        fetched = await MetadataService.search(
          baseUrl: widget.section.addonBaseUrl,
          type: widget.section.contentType,
          catalogId: widget.section.catalog.id,
          query: _searchQuery,
        );
      } else {
        fetched = await MetadataService.fetchCatalog(
          baseUrl: widget.section.addonBaseUrl,
          type: widget.section.contentType,
          catalogId: widget.section.catalog.id,
          genre: _selectedGenre,
          skip: _remoteOffset,
        );
      }
      if (!mounted || serial != _requestSerial) return;
      final seen = _items.map((m) => '${m.type}:${m.id}').toSet();
      final newItems = fetched.where((m) =>
          seen.add('${m.type}:${m.id}')).toList();
      setState(() {
        _remoteOffset += fetched.length;
        _items.addAll(newItems);
        // Do not loop infinitely when an addon ignores the skip parameter,
        // replays the first page, or doesn't implement a search offset.
        _hasMore = fetched.isNotEmpty && newItems.isNotEmpty &&
            !(_isSearching && _searchQuery.isNotEmpty);
        _isLoading = false;
      });

    } catch (_) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _error = 'Could not load more from this exact addon catalog. '
            'Your original titles are unchanged.';
        _hasMore = false;
        _isLoading = false;
      });
    }
  }

  void _onGenreSelected(String? genre) {
    if (_selectedGenre == genre) return;
    setState(() {
      _selectedGenre = genre;
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadItems(refresh: true);
  }

  void _onSearchSubmitted(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchQuery = '';
      });
      _loadItems(refresh: true);
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = query.trim();
      _selectedGenre = null; // Clear genre when searching
    });
    _loadItems(refresh: true);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchQuery = '';
    });
    _loadItems(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final sizing = MovieCardSizing.fromWidth(MediaQuery.sizeOf(context).width);
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;
    final filteredItems = _isSnapshot && _searchQuery.isNotEmpty
        ? _items.where((item) => item.name.toLowerCase()
            .contains(_searchQuery.toLowerCase())).toList()
        : _items;
    // Do not reorder on every HTTP callback: wait for the quickscan first.
    // Confirmed native decoding always outranks merely reachable segments.
    final visibleItems = _isLiveCatalog && !_scanRunning
        ? LiveChannelHealthScanner.sortedByHealth(filteredItems, _health)
        : filteredItems;
    final nativeVerifiedCount =
        _health.values.where((result) => result.nativeVerified).length;
    
    // Calculate safe top padding for grid based on if genres are available
    final hasGenres = _canPage &&
        widget.section.catalog.genres.isNotEmpty && !_isSearching;
    final gridTopPadding = topPadding + kToolbarHeight +
        (hasGenres ? 60 : 20) + 20 + (_isLiveCatalog ? 46 : 0);

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      body: Stack(
        children: [
          // ── Main Content Grid ──
          if (_isLiveCatalog && _scanRunning)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(
                    color: Color(0xFF7C5CFF)),
                  const SizedBox(height: 20),
                  Text('Quick-scanning Live TV: $_scannedCount / $_scanTotal',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                    'Checking the full channel catalog. Healthiest channels '
                    'will be sorted first when this pass finishes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70)),
                ]),
              ),
            )
          else if (_items.isEmpty && _isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
            )
          else if (_items.isEmpty && _error != null)
            ErrorView(
              error: _error,
              onRetry: () => _loadItems(refresh: true),
            )
          else if (visibleItems.isEmpty)
            const Center(
              child: Text(
                'No items found',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            )
          else
            GridView.builder(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                sizing.sidePadding,
                gridTopPadding,
                sizing.sidePadding,
                40 + MediaQuery.paddingOf(context).bottom, // Bottom padding
              ),
              physics: const BouncingScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: ((MediaQuery.sizeOf(context).width - sizing.sidePadding * 2 + sizing.spacing) / (sizing.cardWidth + sizing.spacing)).floor().clamp(2, 10),
                childAspectRatio: sizing.cardWidth / sizing.totalHeight,
                crossAxisSpacing: sizing.spacing,
                mainAxisSpacing: sizing.spacing,
              ),
              itemCount: visibleItems.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == visibleItems.length) {
                  return Center(
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: Color(0xFF7C5CFF))
                        : TextButton.icon(
                            onPressed: _hasMore ? () => _loadItems() : null,
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('Load more'),
                          ),
                  );
                }
                return Stack(fit: StackFit.expand, children: [
                  MovieCard(
                    movie: visibleItems[index],
                    showSeriesRunYears: _canRelatedPage,
                  ),
                  if (_isLiveCatalog)
                    Positioned(top: 6, left: 5, right: 5,
                      child: IgnorePointer(child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 5),
                        decoration: BoxDecoration(
                          color: _health[visibleItems[index].id]?.health ==
                              LiveChannelHealth.verified
                              ? const Color(0xDE0B6040)
                              : _health[visibleItems[index].id]?.health ==
                                  LiveChannelHealth.unstable
                                  ? const Color(0xDDAF7414)
                                  : _health[visibleItems[index].id]?.health ==
                                      LiveChannelHealth.poor
                                      ? const Color(0xDE9A2831)
                                      : const Color(0xE02D3044),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          (_health[visibleItems[index].id] ??
                              const LiveChannelHealthResult(
                                LiveChannelHealth.checking, 0, 'pending'))
                              .label +
                              (_health[visibleItems[index].id]?.nativeChecked ==
                                      true ? ' · MPV' : ' · HTTP only'),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white),
                        ),
                      )),
                    ),
                ]);
              },
            ),

          // ── App Bar & Filters ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  padding: EdgeInsets.only(top: topPadding),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF080A0F).withValues(alpha: 0.90),
                        const Color(0xFF080A0F).withValues(alpha: 0.60),
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Row
                      SizedBox(
                        height: kToolbarHeight,
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                              color: Colors.white,
                              onPressed: () => Navigator.pop(context),
                            ),
                            if (!_isSearching)
                              Expanded(
                                child: Text(
                                  widget.section.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (_isSearching)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: TextField(
                                    controller: _searchController,
                                    autofocus: true,
                                    style: const TextStyle(color: Colors.white, fontSize: 16),
                                    textInputAction: TextInputAction.search,
                                    onSubmitted: _onSearchSubmitted,
                                    decoration: InputDecoration(
                                      hintText: 'Search...',
                                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                                      border: InputBorder.none,
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 20),
                                        color: Colors.white70,
                                        onPressed: _clearSearch,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (!_isSearching &&
                                (_isSnapshot ||
                                    widget.section.catalog.supportsSearch))
                              IconButton(
                                icon: const Icon(Icons.search_rounded),
                                color: Colors.white70,
                                onPressed: () {
                                  setState(() {
                                    _isSearching = true;
                                  });
                                },
                              ),
                            if (!_isSearching)
                              const SizedBox(width: 8),
                          ],
                        ),
                      ),
                      
                      if (_isLiveCatalog)
                        SizedBox(height: 42,
                          child: Row(children: [
                            const SizedBox(width: 16),
                            const Icon(Icons.monitor_heart_outlined,
                                color: Color(0xFFAEA0FF), size: 18),
                            const SizedBox(width: 9),
                            Expanded(child: Text(
                              _scanRunning
                                  ? 'Quick scan: $_scannedCount / $_scanTotal '
                                    '· gathering channels'
                                  : _nativeScanRunning
                                      ? 'Native playback: '
                                        '$_nativeScannedCount / $_nativeScanTotal '
                                        '· $nativeVerifiedCount verified '
                                        '· healthiest first'
                                      : 'Sorted healthiest first · '
                                        '$nativeVerifiedCount native verified '
                                        '· others HTTP only',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70,
                                  fontSize: 12),
                            )),
                            IconButton(
                              tooltip: 'Rescan Live TV channels',
                              onPressed: _scanRunning || _nativeScanRunning
                                  ? null : () => unawaited(_startLiveScan()),
                              icon: const Icon(Icons.refresh_rounded,
                                  color: Colors.white70, size: 19),
                            ),
                            const SizedBox(width: 8),
                          ]),
                        ),
                      // Genres Row
                      if (hasGenres)
                        MouseRegion(
                          onEnter: (_) => setState(() => _isHoveringGenres = true),
                          onExit: (_) => setState(() => _isHoveringGenres = false),
                          child: Stack(
                            children: [
                              SizedBox(
                                height: 50,
                                child: ListView.separated(
                                  controller: _genreScrollController,
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: widget.section.catalog.genres.length + 1,
                                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    if (index == 0) {
                                      return _GenreChip(
                                        label: 'All',
                                        isSelected: _selectedGenre == null,
                                        onTap: () => _onGenreSelected(null),
                                      );
                                    }
                                    final genre = widget.section.catalog.genres[index - 1];
                                    return _GenreChip(
                                      label: genre,
                                      isSelected: _selectedGenre == genre,
                                      onTap: () => _onGenreSelected(genre),
                                    );
                                  },
                                ),
                              ),
                              if (isDesktop) ...[
                                if (_canScrollGenresLeft)
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: _buildScrollArrow(
                                      Icons.arrow_back_ios_new_rounded,
                                      () => _scrollGenres(-1),
                                      _isHoveringGenres,
                                    ),
                                  ),
                                if (_canScrollGenresRight)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: _buildScrollArrow(
                                      Icons.arrow_forward_ios_rounded,
                                      () => _scrollGenres(1),
                                      _isHoveringGenres,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollArrow(IconData icon, VoidCallback onTap, bool isVisible) {
    return Center(
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !isVisible,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenreChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7C5CFF) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected 
              ? const Color(0xFF7C5CFF) 
              : Colors.white.withValues(alpha: 0.12),
          ),
          boxShadow: isSelected 
            ? [BoxShadow(color: const Color(0xFF7C5CFF).withValues(alpha: 0.3), blurRadius: 8)] 
            : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.7),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
