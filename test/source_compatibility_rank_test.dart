import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/stream/source_compatibility_rank.dart';

void main() {
  StreamSource source(String title, {String? url}) =>
      StreamSource(addonName: 'Comet', title: title, url: url);

  test('compatible direct source beats unknown or pending source', () {
    final ready = source('Movie.1080p.H264', url: 'https://example.test/v');
    final unknown = source('Movie.1080p', url: 'https://example.test/v');
    expect(SourceCompatibilityRank.score(ready, isIOS: true),
        greaterThan(SourceCompatibilityRank.score(unknown, isIOS: true)));
  });

  test('older iPad fallback prioritizes H264 over AV1 and DV-only', () {
    final avc = source('Movie.H264', url: 'https://example.test/v');
    final av1 = source('Movie.AV1', url: 'https://example.test/v');
    final dv = source('Movie.Dolby Vision', url: 'https://example.test/v');
    expect(SourceCompatibilityRank.score(avc, isIOS: true),
        greaterThan(SourceCompatibilityRank.score(av1, isIOS: true)));
    expect(SourceCompatibilityRank.score(avc, isIOS: true),
        greaterThan(SourceCompatibilityRank.score(dv, isIOS: true)));
  });

  test('unknown metadata remains neutral, not rejected', () {
    expect(SourceCompatibilityRank.score(source('Unknown'), isIOS: true), 0);
  });
}
