import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/continue_watching/github_watched_history_cloud.dart';
import '../../services/continue_watching/watched_history_service.dart';
import '../../services/continue_watching/watched_history_timeline.dart';
import '../../utils/navigation/media_details_navigation.dart';

/// Netflix-style, read-only recently watched library for Windows and iPad.
///
/// This page is deliberately separate from Continue Watching: completed films
/// and episodes remain here when resumable sessions disappear from the shelf.
class WatchedHistoryPage extends StatefulWidget {
  const WatchedHistoryPage({super.key});

  @override
  State<WatchedHistoryPage> createState() => _WatchedHistoryPageState();
}

class _WatchedHistoryPageState extends State<WatchedHistoryPage> {
  static const Color _background = Color(0xFF080A0F);
  static const Color _surface = Color(0xFF141824);
  static const Color _accent = Color(0xFF7C5CFF);

  final TextEditingController _search = TextEditingController();
  String _filter = 'all';
  String _searchTerm = '';
  bool _syncing = false;
  bool _syncFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_syncing || !mounted) return;
    setState(() {
      _syncing = true;
      _syncFailed = false;
    });
    try {
      await WatchedHistoryService.syncGitHubHistory(force: true);
    } catch (error) {
      debugPrint('[WatchedHistoryPage] History refresh failed: ' +
          error.runtimeType.toString());
      if (mounted) {
        setState(() => _syncFailed = true);
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openDetails(WatchedHistoryEntry entry) async {
    try {
      await MediaDetailsNavigation.open(
        context,
        id: entry.title.id,
        title: entry.title.title,
        type: entry.title.type,
        year: entry.title.year,
        episode: entry.episode,
      );
    } catch (error) {
      debugPrint('[WatchedHistoryPage] Open details failed: ' +
          error.runtimeType.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this title.')),
        );
      }
    }
  }

  String _dateHeading(BuildContext context, DateTime utc) {
    final date = utc.toLocal();
    final today = DateTime.now();
    if (DateUtils.isSameDay(date, today)) return 'Today';
    if (DateUtils.isSameDay(
        date, today.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

  String _time(BuildContext context, DateTime utc) {
    final local = utc.toLocal();
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    final contentPadding = compact ? 16.0 : 28.0;
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Watch History',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            key: const ValueKey('history-refresh'),
            tooltip: 'Sync watched history',
            onPressed: _syncing ? null : _refresh,
            icon: _syncing
                ? const SizedBox(width: 19, height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ValueListenableBuilder<List<WatchedTitle>>(
              valueListenable: WatchedHistoryService.items,
              builder: (context, titles, _) {
                final all = WatchedHistoryTimeline.fromTitles(titles);
                final visible = WatchedHistoryTimeline.filter(
                  all, query: _searchTerm, kind: _filter,
                );
                final movieCount = all.where((row) => row.isMovie).length;
                final showCount = all.length - movieCount;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          contentPadding, 22, contentPadding, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'YOUR RECENTLY WATCHED',
                            style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800,
                              color: _accent, letterSpacing: 2.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            all.isEmpty
                                ? 'Your viewing history'
                                : all.length.toString() + ' watched entries',
                            style: TextStyle(
                              fontSize: compact ? 26 : 34,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Movies, TV shows and individual episodes, '
                            'including titles no longer in Continue Watching.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.58),
                              fontSize: 13, height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const ValueKey('history-search'),
                            controller: _search,
                            onChanged: (value) =>
                                setState(() => _searchTerm = value),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: _surface,
                              prefixIcon: const Icon(Icons.search_rounded,
                                  color: Colors.white60),
                              hintText: 'Search watched titles or episodes',
                              hintStyle: const TextStyle(color: Colors.white38),
                              suffixIcon: _searchTerm.isEmpty ? null : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _searchTerm = '');
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              _filterChip('all', 'All', all.length),
                              const SizedBox(width: 8),
                              _filterChip('movies', 'Movies', movieCount),
                              const SizedBox(width: 8),
                              _filterChip('series', 'Series & episodes',
                                  showCount),
                            ]),
                          ),
                          const SizedBox(height: 12),
                          ValueListenableBuilder<String>(
                            valueListenable:
                                GitHubWatchedHistoryCloud.instance.status,
                            builder: (context, status, _) {
                              return Row(children: [
                                Icon(
                                  _syncFailed
                                      ? Icons.cloud_off_outlined
                                      : Icons.cloud_done_outlined,
                                  color: _syncFailed
                                      ? Colors.orangeAccent
                                      : Colors.white38,
                                  size: 15,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _syncFailed
                                        ? 'Showing saved local history. '
                                          'Cloud refresh unavailable.'
                                        : status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 11),
                                  ),
                                ),
                              ]);
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? _emptyState(all.isEmpty)
                          : RefreshIndicator(
                              color: _accent,
                              onRefresh: _refresh,
                              child: ListView.builder(
                                key: const PageStorageKey('watch-history-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.fromLTRB(contentPadding,
                                    8, contentPadding,
                                    MediaQuery.paddingOf(context).bottom + 28),
                                itemCount: visible.length,
                                itemBuilder: (context, index) {
                                  final entry = visible[index];
                                  final heading = index == 0 ||
                                      !DateUtils.isSameDay(
                                        entry.watchedAt.toLocal(),
                                        visible[index - 1].watchedAt.toLocal(),
                                      );
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (heading)
                                        Padding(
                                          padding: EdgeInsets.only(
                                              top: index == 0 ? 5 : 25,
                                              bottom: 13),
                                          child: Text(
                                            _dateHeading(
                                                context, entry.watchedAt),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      _historyCard(context, entry, compact),
                                      const SizedBox(height: 10),
                                    ],
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String id, String label, int count) {
    final selected = _filter == id;
    return ChoiceChip(
      key: ValueKey('history-filter-' + id),
      selected: selected,
      showCheckmark: false,
      label: Text(label + '  ' + count.toString()),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white70,
        fontSize: 12, fontWeight: FontWeight.w700,
      ),
      backgroundColor: _surface,
      selectedColor: const Color(0xFF44328D),
      side: BorderSide(
        color: selected
            ? _accent.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.09),
      ),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      onSelected: (_) => setState(() => _filter = id),
    );
  }

  Widget _historyCard(
      BuildContext context, WatchedHistoryEntry entry, bool compact) {
    final posterWidth = compact ? 77.0 : 96.0;
    final posterHeight = compact ? 113.0 : 133.0;
    final hasImdbPoster = RegExp(r'^tt\d+$').hasMatch(entry.title.id);
    final posterUrl = hasImdbPoster
        ? 'https://images.metahub.space/poster/medium/' +
            entry.title.id + '/img'
        : null;
    final ratio = entry.progress;
    final hasProgress = entry.position != null || entry.completed;
    final details = entry.isMovie
        ? 'Movie'
        : !entry.isEpisode && entry.title.completedEpisodeIds.isNotEmpty
            ? entry.episodeLabel + ' · ' +
                entry.title.completedEpisodeIds.length.toString() +
                ' completed episodes'
            : entry.episodeLabel;
    final status = entry.completed
        ? 'Completed'
        : entry.position != null
            ? (ratio * 100).round().toString() + '% watched'
            : 'Watched';
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('watched-history-' + entry.uniqueKey),
        onTap: () => _openDetails(entry),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(15),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: posterWidth,
                  height: posterHeight,
                  child: posterUrl == null
                      ? _posterPlaceholder(entry)
                      : CachedNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 240,
                          fadeInDuration:
                              const Duration(milliseconds: 180),
                          placeholder: (_, _) =>
                              _posterPlaceholder(entry),
                          errorWidget: (_, _, _) =>
                              _posterPlaceholder(entry),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.typeLabel +
                          (entry.title.year == null
                              ? '' : '  ·  ' + entry.title.year!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _accent, fontSize: 10,
                        fontWeight: FontWeight.w800, letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      entry.title.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 15 : 17,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      status + '  ·  ' + _time(context, entry.watchedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                    if (hasProgress) ...[
                      const SizedBox(height: 9),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: ratio.clamp(0.0, 1.0).toDouble(),
                          minHeight: 3,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(_accent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white54, size: 23),
            ],
          ),
        ),
      ),
    );
  }

  Widget _posterPlaceholder(WatchedHistoryEntry entry) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2C2352), Color(0xFF151A27)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(entry.isMovie
            ? Icons.movie_outlined : Icons.tv_outlined,
          color: Colors.white54, size: 32),
      ),
    );
  }

  Widget _emptyState(bool hasNoHistory) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_rounded,
                color: Colors.white30, size: 58),
            const SizedBox(height: 15),
            Text(
              hasNoHistory
                  ? 'Nothing watched yet'
                  : 'No matching watched titles',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w800, fontSize: 19),
            ),
            const SizedBox(height: 8),
            Text(
              hasNoHistory
                  ? 'Movies and episodes appear here once you watch them. '
                    'Your history remains separate from Continue Watching.'
                  : 'Try another title or change the history filter.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 15),
            TextButton.icon(
              onPressed: hasNoHistory
                  ? _refresh
                  : () {
                      _search.clear();
                      setState(() {
                        _filter = 'all';
                        _searchTerm = '';
                      });
                    },
              icon: Icon(hasNoHistory
                  ? Icons.sync_rounded : Icons.filter_alt_off_rounded),
              label: Text(hasNoHistory
                  ? 'Refresh history' : 'Clear filters'),
            ),
          ],
        ),
      ),
    );
  }
}
