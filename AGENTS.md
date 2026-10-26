# Repository agent instructions — PlayTorrio

These repository instructions apply to the entire tree. The active product-development branch is **parity-floating-player-both**, while the repository default **main** may lag. Read **handover.md** before starting any change.

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

## Current v1.1.6 source fix — TVDB Settings entry missing on iOS (2026-10-27 SGT)

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
