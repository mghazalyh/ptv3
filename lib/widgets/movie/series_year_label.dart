import 'package:flutter/material.dart';

import '../../services/metadata/series_run_service.dart';

/// Uses the original release year immediately, then supplies the verified
/// end year for ended/cancelled series without changing card dimensions.
class SeriesYearLabel extends StatefulWidget {
  final int? tmdbId;
  final String? imdbId;
  final String? fallbackYear;
  final TextStyle? style;
  final bool showUnreleased;

  const SeriesYearLabel({
    super.key,
    this.tmdbId,
    this.imdbId,
    this.fallbackYear,
    this.style,
    this.showUnreleased = false,
  });

  @override
  State<SeriesYearLabel> createState() => _SeriesYearLabelState();
}

class _SeriesYearLabelState extends State<SeriesYearLabel> {
  late Future<SeriesRun?> _details;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant SeriesYearLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tmdbId != widget.tmdbId ||
        oldWidget.imdbId != widget.imdbId) {
      _resolve();
    }
  }

  void _resolve() {
    _details = SeriesRunService.instance.resolve(
      tmdbId: widget.tmdbId,
      imdbId: widget.imdbId,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SeriesRun?>(
    future: _details,
    builder: (context, snapshot) {
      final fallback = widget.fallbackYear?.trim() ?? '';
      final label = snapshot.data?.displayYear(fallbackYear: fallback) ??
          (fallback.isEmpty ? 'Year unknown' : fallback);
      final year = Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
      if (!widget.showUnreleased || snapshot.data?.unreleased != true) {
        return year;
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          year,
          const Text('UNRELEASED',
            key: ValueKey('discover-unreleased-verified'),
            style: TextStyle(color: Color(0xFFFBBF24),
                fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      );
    },
  );
}
