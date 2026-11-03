/// Stable, timezone-explicit folder layout for private playback diagnostics.
/// The filename and JSON report remain unchanged; only folder placement differs.
abstract final class PrivateDiagnosticLogPath {
  static String forTimestamp({
    required String prefix,
    required DateTime timestamp,
    required int sequence,
  }) {
    if (prefix.trim().isEmpty || sequence < 1) {
      throw ArgumentError('Invalid diagnostic location or sequence');
    }
    final utc = timestamp.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final fileTimestamp = utc.toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return '$prefix/${utc.year}/$month/$day/$fileTimestamp-$sequence.json';
  }
}
