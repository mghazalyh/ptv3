import 'dart:ui';
import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';
import '../../services/metadata/metadata_service.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/movie/movie_card.dart';

class CatalogPage extends StatefulWidget {
  final MovieSection section;

  const CatalogPage({
    super.key,
    required this.section,
  });

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final List<Movie> _items = [];
  bool _isLoading = false;
  bool _hasMore = false;
  int _remoteOffset = 0;
  int _requestSerial = 0;

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
    _items.addAll(widget.section.movies);
    _remoteOffset = _items.length;
    _hasMore = _canPage;
    _scrollController.addListener(_onScroll);
    _genreScrollController.addListener(_updateGenreScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateGenreScrollButtons();
    });
    // Avoid a duplicate initial fetch: See All first displays exactly
    // what the tapped section showed. Page two uses the same addon/catalog.
    if (_items.isEmpty && _canPage) _loadItems(refresh: true);
  }

  @override
  void dispose() {
    _requestSerial++;
    _scrollController.dispose();
    _genreScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && _hasMore) {
        _loadItems();
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
      if (_hasMore && !_isLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          if (_scrollController.position.maxScrollExtent <= 0) {
            _loadItems();
          }
        });
      }
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
    final visibleItems = _isSnapshot && _searchQuery.isNotEmpty
        ? _items.where((item) => item.name.toLowerCase()
            .contains(_searchQuery.toLowerCase())).toList()
        : _items;
    
    // Calculate safe top padding for grid based on if genres are available
    final hasGenres = _canPage &&
        widget.section.catalog.genres.isNotEmpty && !_isSearching;
    final gridTopPadding = topPadding + kToolbarHeight + (hasGenres ? 60 : 20) + 20;

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      body: Stack(
        children: [
          // ── Main Content Grid ──
          if (_items.isEmpty && _isLoading)
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
                childAspectRatio: 1 / 1.48,
                crossAxisSpacing: sizing.spacing,
                mainAxisSpacing: sizing.spacing,
              ),
              itemCount: visibleItems.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == visibleItems.length) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
                  );
                }
                return MovieCard(movie: visibleItems[index]);
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
