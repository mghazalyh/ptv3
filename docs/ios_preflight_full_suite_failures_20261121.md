# First macOS source-only preflight: full-suite failures

Run: https://github.com/mghazalyh/ptv3/actions/runs/44917839107
Source SHA: `32d52c785b7e2bc9cc7f60f3ec7e1cb19e2bb1f1`.

Verified CI status (21 November 2026):
* Flutter 3.41.9 setup: passed.
* Selected static analysis: passed.
* 29 focused media, addon, Live TV, LAN and iOS tests: passed.
* Full `flutter test --no-pub test`: **729 passed, 13 failed**.
* No IPA was built, signed or installed.

Failure groups observed in the runner log:

1. External network-dependent tests:
   * `anime_extractors_test.dart`: live Anime scraper timed out.
   * `vadapav_and_stremio_scheme_test.dart`: one stream scrape and
     one live addon manifest fetch failed due to host DNS resolution.
   * `services/movy_scraper_test.dart`: live ciphertext decode assertion.
   * `services/recommendation_sliders_test.dart`: external-dependent
     recommendation assertion.
2. Existing model contract mismatches:
   * `models/movie_test.dart`: expected default movie, got unknown.
   * `models/my_list_item_test.dart`: five tests expected keys without
     media type or Trakt precedence; implementation prefers IMDb and uses
     type-scoped keys.
   * `download_service_test.dart`: expected serialized transfer speed
     of 5.00 MB/s, got 0 KB/s.
3. `widget_test.dart`: app render smoke test timed out after ten minutes.

The failure descriptions above are observations of the first CI log, not
a root-cause determination. Some may be test fixture/environment failures,
and some may reveal real regressions. Do not silently mark the entire suite
green, ignore failures, or change production semantics merely to satisfy
outdated expected strings.

The next-release Torriodb command inventory and iOS status banner were
committed **after** that test run and are not validated by this result. A
subsequent source-only preflight must analyze/test the exact newer source SHA.
Full native decoder and iPad UI acceptance cannot be established by macOS
unit tests.

## Follow-up source-only run and investigated failures (21 November 2026)

Second source-only run:
https://github.com/mghazalyh/ptv3/actions/runs/44918670682
source commit `732d3498fed7087fd8f3294eddaac3e4bccfedf7`.
It completed with **732 tests passing and 14 failing**. Flutter SDK setup,
selected analyzer, and focused source tests passed. The full-suite failure
count increased by one because *Demon Slayer* live scraping also returned
no sources (upstream HTTP 403). The previously observed failures persisted.
No IPA or application package was built.

The current branch corrections made **after** that run:
* `cd286bc6397f3e47901e9425620103d6041e8f48`: correct eight deterministic
  expectations/fixture problems without turning untyped Stremio media into
  movies, without confusing movie/series identities, and without serializing
  transient download speed; isolate the local widget smoke test from cloud
  synchronization. Includes additional exact media identity regression tests.
* `cf2e945d0a996301b682621c14bd67220ad2e8a8`: sanitize exported addon
  manifest inventory labels/types/resources with adversarial regression tests.
* `3732349d6ed21d36a376af7245048c20a5c7c818`: bounded retry of
  transient GitHub GET/PUT transport failures during Torriodb uploads with
  an SHA re-read, preserving non-retryable 4xx errors and adding tests.
* `4668a96f28d98843f89f73784fc74ad326c57cfe`: separate attempted source
  count, successfully uploaded candidate reports, candidate report upload
  failures and general upload failures; add regression tests. This is
  source-only instrumentation and NOT running on build 262.

Third preflight:
https://github.com/mghazalyh/ptv3/actions/runs/44919779598
was in progress at the last check, tied to earlier commit
`1400460f55b926746dc98c4ec9460ebc9bce885a`.
Its results do not validate the four later corrections above. Do not
trigger another duplicate run while it remains active.

Five historical first-run failures require independent deterministic
fixtures or verified changes to external providers: three external scraper
checks (anime, Vadapav, Movy count as four tests including two Vadapav
failures) and one recommendation integration assertion. On the second
run, an additional anime scraper case failed due to HTTP 403. These
externally dependent failures have NOT been declared resolved or hidden.
No complete suite has been verified green on the newest source.
