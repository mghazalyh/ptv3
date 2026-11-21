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
