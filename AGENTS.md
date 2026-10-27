# Repository agent instructions — PlayTorrio

These repository instructions apply to the entire tree. The active product-development branch is **parity-floating-player-both**, while the repository default **main** may lag. Read **handover.md** before starting any change.

## CURRENT v1.1.11 — origin country and original language on every title (2026-10-27)

- New `lib/services/metadata/title_origin_language_service.dart` exposes production **Origin** and **Original language** on MovieCard/Home/See All/Search/Discover, Details including related row, Networks, cast credits, My List and Continue Watching. Existing Similar Content preserved. Differentiate **original production** from dubbed English audio/subtitle language.
- Use exact verified TMDB or IMDb IDs only (TMDB `/find`), no title guessing or invented country. Display `Not listed` if unknown; translate known ISO codes. Existing TMDB key/rate pace/cache/429 reused, max 24 new scrollable-card lookups/min, no card-wide unbounded polling, opened Details exempt. No key and no ID should work gracefully.
- Version `1.1.11+21`, new `test/title_origin_language_test.dart` and `test/origin_language_everywhere_test.dart` on Windows and iOS, paired CI **pending**. Last released **v1.1.10 Build #132**, Windows17 iOS30 Telegram actual IPA #30. No Torriodb or playback changes; keep root docs aligned and mirror docs-only to main with [skip ci], never merge divergent app source.

## Mandatory living handover rule

**Every application change or update must include a matching edit to root handover.md in the same work unit, ideally in the same commit/PR.** This includes source, UI, player, data schema, tests, dependency/config changes, GitHub Actions, releases, deployment, Telegram behavior, bug fixes and meaningful validation status. Never finish an implementation while leaving the handover stale.

When updating handover.md:
1. Refresh the top **CURRENT STATUS** (app version/build, exact branch SHA, latest completed Windows+iOS paired release vs partial builds) using GitHub's current data.
2. Update feature behavior and affected source/test/workflow file paths; include design constraints and edge cases.
3. Add a dated **Update log** row: goal, commits, tests, workflow run IDs and conclusions, releases only if verified, Telegram direct attachment vs fallback, blockers and next steps.
4. Keep it comprehensive, usable from a cold start and honest about missing real-device validation.
5. Mirror handover.md and AGENTS.md to the default main branch as documentation **when appropriate**. Do not merge stale main application code into the development branch to accomplish this. Avoid needless CI rebuilds purely for docs if infrastructure supports documentation-only filtering.

## User constraints and release standards

- Maintain **non-floating player** behavior; do not reintroduce floating picture-in-picture or floating player implementations.
- Preserve English-preferred audio, automatic English subtitles when available, Next Episode and same-addon stream preferences, private GitHub My List/Continue Watching sync, and Show Details navigation preserving playback.
- Target matched **Windows x64 installer + portable ZIP** and **ad hoc signed iOS 15 TrollStore IPA** from the same commit. Main paired workflow: **.github/workflows/windows-advanced-discover.yml**.
- The final user-facing answer should prominently show **semantic version and GitHub build number**, exact feature entry point, CI status/step counts, **verified** download links, release and Telegram IPA delivery status, and explicit limitations. Never fabricate sandbox paths, GitHub release assets or Telegram success.
- The current preferred private DB is **mghazalyh/torriodb**, branch main, with two versioned JSON files. Device PATs are independently provisioned and securely stored. **Never log, commit, paste, or repeat token values, private media history, Telegram credentials, or private group identifiers in public documentation**.
- Avoid repeated questioning on already settled preferences, repetitive credential warnings or claims of physical-device testing without evidence.
- The user's separate request for feature parity with another ptv repository remains uncompleted; compare features before implementing, not blind code copying.

## CURRENT CI FIX — Build #131 See All paging (2026-10-27)

Build #131 failed the pagination regression because the test expected an implicit fetch from a grid scroll; request count stayed 0. No release. Runtime improved: `CatalogPage` now exposes explicit **Load more** only for original source catalogs with `supportsSkip`; no auto fetch on scroll. Maintains exact row first, no synthetic/invalid provider fallback, correct skip and dedup. Test now taps the button and checks source, one request and replay-stop. v1.1.10+20 unchanged, third run pending. Preserve all docs and docs-only main mirror.

## CI REGRESSION CHECKPOINT — v1.1.10 Build #130 failure and correction

Build #130 failed both Windows and iOS **only** in the new `see_all_source_integrity_test.dart` scrolling positive case. Narrow 340×245 test screen exposed `MovieCard` Row overflow; `pumpAndSettle` timed out because progress spinner never stops animating. Fix both properly: make MovieCard type Text Flexible/ellipsized, use 720×380 scrollable test viewport and bounded 250ms pump. No rollback of source-bound See All code. Publish **no v1.1.10** until replacement paired CI and real release succeed. Maintain docs-only main mirror, Torriodb shelved.

## CURRENT FIX — v1.1.10 preserve See All section source (2026-10-27)

- User reports “See All” remains unrelated/generic in some places. `CatalogPage` must **seed from exact originating MovieSection.movies** on navigation, not refetch first page from a synthetic or invalid addon catalog. Do not silently default empty/invalid addonBaseUrl to Cinemeta. Only real HTTP(S) addon source with declared `supportsSkip` may page, using its original catalog URL/type/id and offset, dedup + stop when skip ignored. Curated and known synthetic BestSimilar/Trakt/Simkl recommendation IDs, or any catalog with no valid source/skip, **never** network-fetch generic results. Search them locally; do not display irrelevant fallback titles.
- `BestSimilarScraper` must verify exact normalized source work title, correct type and close year before recommending; HomePageSettings validates matched detail title/year too. Do not accept fuzzy same-word/year matches as the user's favorite.
- New `test/see_all_source_integrity_test.dart` and existing curated regression on Windows + iOS CI, version **1.1.10+20**. CI/release pending at edit time. Last successful published v1.1.9 Build #129. Torriodb shelved. Update root handover/NEXT_SESSION/AGENTS and docs-only mirror to divergent main [skip ci], no main source merges.

## RELEASED v1.1.9 Build #129 — Networks tab

Actions #129 (https://github.com/mghazalyh/ptv3/actions/runs/40436914158) fully passed: Windows 17/17, iOS TrollStore 30 steps, Telegram real IPA document #29, paired release ZIP/EXE/IPA and checksums. Source commit c359716088c2d3457b1fef52d8a67047210ba396. CI verified new provider region and dock tests; physical device validation outstanding. Torriodb project shelved. Docs-only [skip ci], no new app source modification.

## HISTORICAL IMPLEMENTATION — v1.1.9 Networks tab

- User shelved Torriodb; do not implement keys/config sync now. Add visible Networks Dock destination with TMDB regional watch-providers, searchable many-services picker, separate TV-origin network list including Showtime/HBO/FX. Movie+Series where appropriate, country selection SG default, Trending=recent popular, Hot=rating with minimum 100 votes, Popular=overall. These are Discover proxies, not true per-platform trending feeds. Normal Stremio Details navigation and English audio/subtitle preferences preserved.
- v1.1.9+19 with new `lib/services/metadata/network_discover_service.dart`, `lib/pages/networks/networks_page.dart`, updated TMDB client and Liquid Dock, mock tests `test/network_discover_service_test.dart`, `test/networks_navigation_ui_test.dart` added to Windows/iOS CI. Latest fully released v1.1.8 Build #128; 1.1.9 CI and actual assets pending validation.
- Update handover.md and NEXT_SESSION.md with actual release state in each future source/CI work unit. Documentation-only mirror to divergent main, do not merge application source from main.

## HISTORICAL / SHELVED DECISION — private Torriodb plaintext credentials (2026-10-27 SGT)

- **User explicitly does NOT want encryption.** Rotated TMDB/TVDB/TorBox/other API keys must live in manually editable **`playtorrio/api-keys-v1.json` plaintext** in their **private `mghazalyh/torriodb` repo**, so weekly GitHub edits can be synced across new/current iOS/Windows devices. Prior encrypted/PAT-derived vault specification in older notes is **superseded**; do not implement it or require identical PATs/a second unlock.
- New canonical plan: `docs/torriodb_key_vault_plan.md`, plus proposed `settings-v1.json`, `likes-v1.json`, `watched-history-v1.json`; preserve existing `watchlist-v1.json` and `continue-watching-v1.json`. Single repo/branch/PAT device connection should eventually restore all. **Not currently coded** beyond watchlist and Continue Watching. Protect remote edits from stale device overwrites, verify repo remains private before syncing plaintext credentials, and never commit GitHub PAT itself or credentials to public ptv3. Private visibility does NOT prevent access by collaborators/compromised PAT; past keys remain in git history even after rotation.
- **Documentation only [skip ci]** in this requirement correction, no remote credentials or app source modified. Latest fully released v1.1.8 Build #128. Keep canonical root docs aligned and mirror docs only to divergent main.

## HISTORICAL / SUPERSEDED ENCRYPTION PROPOSAL — Torriodb private full-device restore (2026-10-27 SGT)

- **Verified private** `mghazalyh/torriodb`, branch **main**, with existing watchlist and Continue Watching files. User requires **single GitHub Library repo/branch/PAT entry** on new iOS/Windows device restores watchlist, liked/favorited, fully watched history, Continue Watching episode progress, portable app/settings/addon choices, ALL eligible API keys/TVDB PIN, and synchronizes weekly rotations. Existing code only handles watchlist/progress; do **not** claim complete sync or store secrets before implementation.
- `docs/torriodb_key_vault_plan.md` now has full design and privacy constraints: independent likes and watched records; app settings allow-list; separate AES-GCM authenticated encrypted credentials/settings; GitHub Contents SHA CAS; authenticated **private** repo check; derive encryption key from same PAT only when user wants no second password; different PAT cannot decrypt, and rotation/recovery requires old token or extra unlock; PAT compromise decrypts the vault, so explain tradeoff.
- **Latest released v1.1.8 Build #128** is fully paired [workflow](https://github.com/mghazalyh/ptv3/actions/runs/40393028750), Windows 17/17, iOS15 29 steps, Telegram actual IPA document #28, GitHub matched Windows ZIP/EXE and TrollStore IPA. Build #128 has cast filmography and enriched recommendation cards but no newly implemented Torriodb vault. Documentation-only [skip ci] checkpoint.
- Maintain living `handover.md`, `NEXT_SESSION.md`, `AGENTS.md` and mirror docs only to divergent main. Never expose PAT, TMDB/TVDB keys, subscriber PIN or addon secrets via source/CI/logs/docs. Do not merge main source into active `parity-floating-player-both`.

## HISTORICAL IMPLEMENTATION — v1.1.8 cast credits / Similar cards / Torriodb key vault prep (2026-10-27 SGT)

- Details Cast chip should open **`PersonCreditsPage`**, which uses authenticated TMDB `/search/person` and `/person/{id}/combined_credits` (not title search), supporting actor identity choice and movie/series credits. Recommendation cards show bounded TMDB-backed **country origin, original production language, network/studio** metadata or "Not listed", never fabricate English audio availability. First six only, paced/cached, no TMDB key means no optional calls. Preserve existing type, similarity score and subtitle/player rules.
- `docs/torriodb_key_vault_plan.md` is **security preparation, not an implementation or permission to store raw API keys**. Confirm actual repo private status, authenticated encryption and device-only unlock before implementing any central key sync. Default `mghazalyh/ptv3` repo is public, so never put secrets there. Keep user credentials local for now.
- Confirmed Torrentio sorting already prioritizes explicitly English-audio/dub tagged sources before multi-audio, unknown or foreign audio, preserving non-English sources. Do not confuse English subs with dub or overclaim filenames as proof.
- Source version 1.1.8+18 and Windows/iOS CI tests pending. Last verified paired release **v1.1.7 Build #127**. Update `handover.md`, `NEXT_SESSION.md`, `AGENTS.md` in every meaningful work unit; docs-only mirror to main with [skip ci], no source merges.

## HISTORICAL VERIFIED RELEASE — v1.1.7 Build #127 (2026-10-27 SGT)

- Paired GitHub Actions [Build #127](https://github.com/mghazalyh/ptv3/actions/runs/40388302974) from source commit `16a4143fd085973b9f103e1faa05b4ec95ad3269` succeeded: Windows **17/17**, iOS15 **28 successful steps**, Telegram actual IPA **document message 27**, published matched [v1.1.7 Build #127](https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.7-b127) with real ZIP/EXE/IPA/checksums. The prior v1.1.6 is historical; v1.1.7 includes TVDB settings UI plus new title+filters.
- New Advanced Discover optional text input is explicitly user-requested and tested: blank title retains existing `/discover` query and year filters; typed text uses `/search/movie|tv`, local year/country/language/sort intersection, Movie origin-country details only when explicitly selected, and prior applied filter paging. One TV year may match episode dates; multi-year TV title range uses premiere year with UI caveat. No per-keystroke network calls; existing TMDB rate pacing, caching, cooldown and API credentials unchanged.
- **No direct real-device screenshot or visual acceptance test yet**, despite paired Flutter CI passing. This is a documentation-only [skip ci] release checkpoint; source build SHA remains `16a4143fd085973b9f103e1faa05b4ec95ad3269`. Every future code, test, build, deploy or user verification must update living `handover.md`, `NEXT_SESSION.md` and `AGENTS.md`; mirror documents only to main, no cross-branch app source merges.

## HISTORICAL v1.1.7 Advanced Discover title+filters implementation (2026-10-27)

- Source implements optional title text in Advanced Discover with existing Movie/TV choice, year, country, language, sort and paginated results. Blank title must **keep old `/discover` endpoint and exact old filtering**. Text routes to `/search/movie|tv`, filters locally, country for movies uses paced/cached per-item origin-country detail calls only on deliberate selection. TV single year uses search `year` (episode-aware); multi-year TV title uses premiere-year interval and UI must disclose the difference. No automatic network calls on typing; local TMDB key only.
- UI source `lib/pages/search/advanced_discover_page.dart`, metadata `tmdb_discover_service.dart`, mock test `test/tmdb_text_filter_search_test.dart`, source UI test `test/advanced_discover_text_ui_test.dart` both included Windows/iOS CI. Version v1.1.7+17 and paired workflow version bumped, **CI/release not yet verified**. Latest fully paired published release was **v1.1.6 Build #126**, Windows 17/17, iOS27 steps, Telegram+GitHub matched assets and visible TVDB Settings tile; never confuse it with v1.1.7.
- Keep all behavior for player, Continue Watching, recommendations, English embedded-first subtitles and credential privacy. Mandatory living `handover.md`, `NEXT_SESSION.md`, `AGENTS.md` updates with source/status; docs-only mirrors to divergent main [skip ci].

## HISTORICAL: v1.1.6 TVDB Settings navigation fix (2026-10-27 SGT)

- User reported no TVDB key UI in iOS v1.1.5 Build #125. Confirmed the TVDB credential form existed but **main Settings did not import or link to it**. v1.1.6 fixes `lib/pages/settings/settings_page.dart` with a visible **TVDB Series Metadata** tile below Addons routing to `TvdbSettingsPage`. Masked TVDB v4 key and optional subscriber PIN are securely saved only on-device.
- Regression `test/tvdb_settings_navigation_test.dart` checks the Settings tile route and destination form. Added to Windows and iOS tests, analyzer checks main Settings. Bumped all app build/release identifiers to v1.1.6. No metadata provider logic or playback changes.
- **No new v1.1.6 release verified until successful paired CI**. Last fully verified release v1.1.5 Build #125 with Telegram actual IPA document message #25. Preserve `handover.md` and `NEXT_SESSION.md` in same source commit; mirror docs only to divergent main, never merge its application code.

## Historical release checkpoint (2026-10-27 SGT) — v1.1.5 Build #125

- **v1.1.5 Build #125** is successfully paired and **published**: [workflow](https://github.com/mghazalyh/ptv3/actions/runs/40380065374) source commit `ec88c73da57efc00eb35e54c77a9cfef0a6d72e7`, Windows **17/17**, iOS15 **26 successful steps**, Telegram IPA **actual document message ID 25**, and 6 successful matched publication steps. [Release](https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.5-b125) contains Windows portable ZIP, Setup EXE, iOS15 TrollStore IPA and SHA256SUMS. The Build #122–124 failures in older checkpoints are historical.
- Similar Content on series has fixed multi-year premiere dates and optional BestSimilar→polite TMDB recommendations fallback; opt-in TVDB v4 metadata under Settings → TVDB Series Metadata with device-secure key and optional subscriber PIN. No fabricated matches, no bulk watchlist polling, preserve embedded-English-first subtitle and other playback requirements. **Real-device user validation is still pending.**
- Documentation-only [skip ci] update after release. Every meaningful update must maintain `handover.md`, `NEXT_SESSION.md` and `AGENTS.md`. Mirror docs to `main` only without merging divergent feature code.

## Historical CI — v1.1.5 Build #124 analyzer warning repair (2026-10-27)

- Windows Build #124 executed new and existing tests **successfully**, but analyzer failed on two `invalid_use_of_visible_for_testing_member` warnings because production `SimilarRecommendationsService` calls `TvdbSeriesService.normalizeTitle` marked test-only. Removed **only the annotation**, no behavior changes. Follow-on CI must still confirm analyzer/packaging/iOS/Telegram/release. **Do not advertise a v1.1.5 download until verified**. Latest fully released paired version remains **v1.1.4 Build #121**.
- For every subsequent source or verification change, update root `handover.md` and `NEXT_SESSION.md` in same work unit; mirror documentation only to `main` with `[skip ci]`.

## Historical v1.1.5 paired CI verification checkpoint

- Build #123 failed test compilation because `tmdb_discover_service.dart` had a duplicated stale suffix and duplicate `_DiscoverCacheEntry`. Root-cause repair reconstructed it directly from last-good v1.1.4 TMDB service, adding only one `relatedSeries` and `selectSeriesId` block and verified all class/method occurrence counts. Source blob `70fa4f544731b14e6ab58568c8d57506982651c5`. Next paired CI tests/builds pending; **no new v1.1.5 release yet**.
- Preserve mandatory handover updates and documentation-only main mirror.



- Initial Build #122 failed Windows tests during Dart load because scripted JS replacement truncated `RegExp(r'^tt\\d+$')` in the new `TmdbDiscoverService.relatedSeries` method; source repair reconstructed the whole method and preserved the intended behavior. **No v1.1.5 build success or release at this checkpoint**. Next check new paired CI and update living handover. Do not give fabricated binary links or mark a failed test as passing; latest paired release remains **v1.1.4 Build #121**.
- Mandatory: include `handover.md` + `NEXT_SESSION.md` in the same work unit for all real edits, and docs-only mirror to main.

## Historical v1.1.5 TV recommendation implementation (2026-10-27)

- Details **Similar Content/Recommended Shows**: corrected first-year parsing; BestSimilar primary, limited/cached TMDB `recommendations` then `similar` fallback for series only on genuine miss; metadata can optionally come from TVDB v4 configured in **Settings → TVDB Series Metadata** using local secure key+optional subscriber PIN. No guessing unknown shows, no bulk library lookups, and no fabricated source similarity values. Native TVDB recommendations endpoint is not documented; TVDB enhances matching and genre order of real TMDB candidates, with attribution.
- New and modified metadata services, UI, tests, paired workflow and version **1.1.5+15** in same work unit. **CI build and release pending verification**; last fully paired release at start v1.1.4 Build #121. Preserve embedded English subtitle preference and all non-floating playback. **Update handover.md and NEXT_SESSION.md for every future code/build/result change**.

## Historical TVDB+TMDB recommendation investigation (2026-10-27)

- User favors adding optional TheTVDB support alongside TMDB. **Official TVDB v4 API documents metadata/people/genres/lists/search but not a dedicated per-series similarity/recommendations endpoint.** Assess relevance improvements using its metadata rather than inventing a native recommendation API; honor project licensing, optional subscriber PIN and required attribution. Never publish TVDB keys/bearer tokens or auto-query whole user libraries.
- **No code or credentials changed:** this is research-only docs [skip ci]. Open known deterministic bug: year `2019–2020` incorrectly parsed as `20192020` in Similar Content matching. Next candidate enhancement is optional, bounded/cached TMDB dedicated recommendations fallback with possible TVDB metadata enrichment. Last paired release **v1.1.4 Build #121** remains verified. All future work must update `handover.md` and `NEXT_SESSION.md`.

## Previous diagnosis and release status (2026-10-27 SGT)

- **v1.1.4 Build #121** is a fully completed paired Windows x64/iOS 15 TrollStore release, published at https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.4-b121; Telegram signed IPA uploaded as a document (message ID 24). Previous "iOS queued" entries are historical.
- **Open recommendation issue:** `The Order (2019–2020)` has no Similar Content row; `_fetchSimilarContent()` merges digits in the release range to `20192020`, likely blocking exact BestSimilar matching. The user asked for suggestions; **no implementation yet**. Recommended first-year regex helper/tests; then conservative optional TMDB fallback using existing authenticated, paced/cached Discover service only if BestSimilar empty. No new TVDB credentials, fabricated matches or unlimited scraping.
- All edits in this checkpoint are **documentation only [skip ci]**. Preserve mandatory updates to handover and session notes with every future meaningful change.

## Historical iOS progress (2026-10-27 SGT)

- **v1.1.4 Build #121 attempt 2 iOS job 121740141007 is running.** Seven initial setup, Flutter, and native-framework steps succeeded, with storage analysis ongoing at this checkpoint. No source compile or signing failure reported yet, but tests, signing, IPA archive, Telegram and release not completed. Prior retry queue issue ended when the runner started. [Workflow](https://github.com/mghazalyh/ptv3/actions/runs/40367298917).
- Build #121 Windows remains **17/17 success**. Last verified publicly downloadable iOS IPA remains **v1.1.0 Build #90**, not the unreleased v1.1.4. Document every meaningful change and status in handover and NEXT_SESSION; keep this documentation-only checkpoint [skip ci] to avoid interrupting the ongoing paired build.

## Historical iOS delivery checkpoint (2026-10-27 SGT)

- The latest publicly verified iOS 15 TrollStore IPA remains **v1.1.0 Build #90** (https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.0-b90/PlayTorrio-v1.1.0-build90-iOS15-TrollStore.ipa). v1.1.4 Build #121 passed Windows **17/17** (Actions artifact 12670718760), but iOS was **canceled before starting**. Telegram and paired publish were skipped.
- **The canceled iOS job was rerun independently** via GitHub Actions; Build #121 attempt **2**, iOS job **121740141007**, initially queued. Do not label a new iOS IPA built or sent until an actual signed artifact and delivery exist. No iOS compile error was observed because macOS jobs did not run.
- These are documentation-only updates [skip ci], not source changes. Keep handover and session notes updated on meaningful status changes without needlessly canceling queued builds.

## Active development checkpoint (2026-10-27 SGT)

- **v1.1.4 candidate on `parity-floating-player-both`**: title-details **Similar Content** now shows Movie/Series/Title instead of genre, based on the same provider type evidence as Home. Individual BestSimilar autocomplete checks are capped and cached, no extra TMDB/TVDB requests. Click-through uses each item's own media type. Regression tests updated and already included in Windows+iOS workflow. Release/test status remains pending until CI proves it.
- **Embedded English subtitles first** is the existing preserved policy: embedded forced, then embedded regular, then external auto fallback; manual selection wins. No change to subtitle service behavior.
- **All future meaningful edits or verification MUST update `handover.md` and `NEXT_SESSION.md`**. User specifically reinforced this tradition. Do not announce v1.1.4 download links without completed build/release evidence. Previous working Windows candidate is v1.1.3 Build #120, paired release is v1.1.0 Build #90.

## Historical delivery checkpoint (2026-10-27 SGT)

- Application source is **v1.1.3**, development branch `parity-floating-player-both`, verified application commit **`05ebf6e263e1df9d4a47b8cb187b3cfa81c0ba7e`**. Root `handover.md` is the operational source of truth and must be updated **for every meaningful change or test/delivery status update**, with `NEXT_SESSION.md` kept in sync.
- **Windows Build #120**: [workflow](https://github.com/mghazalyh/ptv3/actions/runs/40361913589) completed Windows **17/17 steps successfully** and generated Windows Actions artifact **PlayTorrio-Windows-v1.1.3-build-120** (ID **12668423291**) with a portable ZIP and installer EXE. The extracted portable ZIP passed integrity testing. **The user reported that everything works with the downloaded Windows portable build**, a user confirmation rather than exhaustive independent device testing.
- The **iOS 15 job was canceled** in Build #120; Telegram IPA and publish jobs were **skipped**, making the paired run **overall failure**. There is **no verified v1.1.3 paired GitHub release or iOS IPA**. The last fully successful paired release is [v1.1.0 Build #90](https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.0-b90), with Windows 17/17, iOS 22/22 and Telegram document.
- Preserve current behavior and prior requirements. All changes in this checkpoint are **documentation only [skip ci]**. Do not rebuild or reset working Windows source merely for documentation. Do not confuse Actions artifacts with release assets.

See **handover.md** for full timeline, file map, run history, data contracts and known issues.
