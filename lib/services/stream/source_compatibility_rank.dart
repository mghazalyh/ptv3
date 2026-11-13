import '../../models/stream/stream_model.dart';
import '../player/debrid_source_readiness.dart';

/// Bounded, deterministic compatibility evidence. Unknown features are
/// neutral: never falsely call a stream incompatible or API-verified cached.
abstract final class SourceCompatibilityRank {
  static int score(StreamSource source, {required bool isIOS}) {
    if (DebridSourceReadiness.isExplicitlyPending(source)) return -1000;
    var score = 0;
    final url = source.url ?? '';
    if (url.startsWith('https://')) {
      score += 25;
    } else if (url.startsWith('http://')) {
      score += 10;
    }
    final codec = source.codec?.toLowerCase() ?? '';
    if (codec.contains('h264') || codec.contains('h.264') ||
        codec.contains('avc')) score += 12;
    if (codec.contains('h265') || codec.contains('hevc')) score += 10;
    if (codec.contains('av1')) score += isIOS ? -25 : 2;
    final title = '${source.title ?? ''} ${source.name ?? ''}'.toLowerCase();
    // Capability varies by iPad generation. Prefer fallback-compatible
    // streams over an unverified Dolby Vision-only presentation.
    if (isIOS &&
        (title.contains('dolby vision') ||
            RegExp(r'(^|[^a-z0-9])dv([^a-z0-9]|$)').hasMatch(title)) &&
        !title.contains('hdr10')) {
      score -= 12;
    }
    if (isIOS && source.quality == '4K' &&
        (source.sizeBytes ?? 0) > 18 * 1024 * 1024 * 1024) {
      score -= 12;
    }
    return score;
  }
}
