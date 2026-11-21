import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/scraper/sites/movy.dart';

const _liveProviderTests = bool.fromEnvironment(
  'PLAYTORRIO_LIVE_PROVIDER_TESTS',
  defaultValue: false,
);

// Fixed ciphertext produced independently using the Movy mvm1 / FNV
// keystream algorithm. Provider availability is not part of cipher correctness.
const _knownCipher =
    's3s2FKRv9j-u9ctvoDunby8aEDWGA1pVbkOtXjBlzBnVwf1cMbhJKsL5cFmJKxvGzS8QqqnUZXGt7fU6nD1w2Jo-41Sbrh7J-R4ug4hnqpp_CtMTta6uWH3MkNMBOZFugAT3xWR-zi6DTRTlytbYneON48GVKGVo_rKJTCqEe0j3P9XWEKo';

void main() {
  test('Movy decryptor restores exact fixed stream ciphertext offline', () {
    final plain = MovyScraper.decryptFixtureForTest(
      _knownCipher,
      'fixed-test-seed',
      550,
    );
    expect(plain, isNotNull, reason: 'Known Movy mvm1 vector must decrypt');

    final decoded = jsonDecode(plain!) as Map<String, dynamic>;
    final sources = decoded['sources'] as List<dynamic>;
    expect(sources, hasLength(2));
    expect(sources.first['url'], 'https://video.example/film.m3u8');
    expect(sources.first['quality'], '1080p');
    expect(sources.last['url'], 'https://video.example/sd.m3u8');
    expect(sources.last['quality'], '720p');
  });

  test('Movy rejects incorrect seeds, TMDB identities and ciphertext', () {
    expect(MovyScraper.decryptFixtureForTest(
      _knownCipher, 'wrong-seed', 550), isNull);
    expect(MovyScraper.decryptFixtureForTest(
      _knownCipher, 'fixed-test-seed', 551), isNull);
    expect(MovyScraper.decryptFixtureForTest(
      'invalid-not-cipher', 'fixed-test-seed', 550), isNull);
    expect(MovyScraper.decryptFixtureForTest(
      '', 'fixed-test-seed', 550), isNull);
  });

  test('Movy live seed and sources integration (explicit opt-in)', () async {
    final streams = await MovyScraper().scrape(
      type: 'movie',
      title: 'Fight Club',
      year: 1999,
      imdbId: 'tt0137523',
    );
    expect(streams, isNotEmpty,
        reason: 'Movy live provider returned no playable sources');
    for (final source in streams) {
      expect(source.url, startsWith('http'));
      expect(source.addonName, 'PlayTorrioHTTP');
    }
  },
      skip: !_liveProviderTests,
      timeout: const Timeout(Duration(seconds: 120)));
}
