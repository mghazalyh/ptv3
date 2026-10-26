# PlayTorrio — comprehensive project handover

> **Canonical living handover.** Established 2026-10-26 (UTC) from the full working session, repository source and GitHub Actions/release state. This is deliberately detailed so development can be resumed after a context reset.  
> **Read [AGENTS.md](AGENTS.md) before changing code.** Every future functional, build, release, test, or configuration change must update this handover in the same work unit.  
> **Important:** Statuses below are an *as-of-2026-10-26* snapshot, not a claim that GitHub will remain unchanged. Always check the latest commit/run/release when resuming.

## 0. Quick-start / what the next developer needs to know

1. **Application source:** public GitHub repository [mghazalyh/ptv3](https://github.com/mghazalyh/ptv3).
2. **Active development branch:** [parity-floating-player-both](https://github.com/mghazalyh/ptv3/tree/parity-floating-player-both); at the handover checkpoint its HEAD is **f0e095a7a99af3faf340f04774fd987651507dac**. This branch is **148 commits ahead of** default branch **main** at this snapshot. **Do not assume main contains these changes.** The handover and AGENTS files are intentionally mirrored on main for discoverability; this does **not** merge feature code.
3. **Private database:** [mghazalyh/torriodb](https://github.com/mghazalyh/torriodb), default branch **main**. GitHub connection has read/write access; application devices independently authenticate with their own fine-grained token. Do not put that token, any Telegram credentials, actual private titles, or viewing-history records in the public source repo or in this document.
4. **Latest completely verified paired Windows+iOS15 release:** **PlayTorrio v1.1.0 (Build 90)**, tag [build-v1.1.0-b90](https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.0-b90), workflow [40331619688](https://github.com/mghazalyh/ptv3/actions/runs/40331619688), commit **1052394a439e63556b674517a2b350e9070bf131**. Windows 17 steps successful; iOS15 22 steps successful; GitHub paired release created; IPA was sent to Telegram as an actual document, message **#17**.
5. **Newest implemented source version:** **v1.1.1**, whose notable addition is **always-visible “Show Details” from Continue Watching and in-player navigation back to full title details with playback preservation**. Flutter pubspec version is **1.1.1+11**. Its workflow **Build #97**, [40336345197](https://github.com/mghazalyh/ptv3/actions/runs/40336345197), **did NOT produce a paired release**: Windows passed 17 steps and generated a Windows Actions artifact, but the iOS job was canceled while waiting in the queue; dependent Telegram and publish jobs were skipped, and the overall workflow concluded **failure**. **Do not advertise a v1.1.1 GitHub release, IPA, or Telegram delivery until a new successful paired run proves they exist.**
6. **Immediate follow-up:** Get the v1.1.1 iOS/macOS runner to finish, validate the new navigation on physical devices, confirm artifact/version consistency, publish a versioned paired release, and verify a real Telegram IPA document. The latest source changes and Windows build are already committed; no need to reimplement them.
7. **Non-negotiable product constraints:** Keep the player **non-floating** (do not reintroduce picture-in-picture/floating-player behavior), preserve English-first audio and subtitles, next-episode navigation/autoplay and preferred addon selection, local+private-GitHub My List and Continue Watching sync, signed iOS 15 TrollStore IPA, matching Windows portable ZIP and installer, and Telegram IPA delivery.
8. **Communication preference:** Clear, compact shipping report with **version/build** at top; what changed and where the UI lives; direct verified downloads when available; Windows+iOS CI step counts; Telegram delivery confirmation; and explicit distinction between automated CI validation and real-device playback validation. Do not call an artifact a release until it actually exists. Do not repeatedly ask questions for known project choices or deliver repetitive boilerplate warnings.

## 1. Repositories, branches, privacy and environment

| Purpose | Repository / ref | Notes |
| --- | --- | --- |
| Source and CI | mghazalyh/ptv3, branch parity-floating-player-both | Primary worktree and build branch; public |
| Default source | mghazalyh/ptv3, branch main | Behind active development. At this snapshot only the older general build workflow is present; do not build intended features from this branch |
| Original simple public database | mghazalyh/ptv3, branch library-data | playtorrio/watchlist-v1.json, initialized empty for early prototype; not the preferred current user database |
| Actual private database | mghazalyh/torriodb, branch main | Two JSON v1 files; independently writable by the installed apps |
| GitHub releases | mghazalyh/ptv3/releases | Distinct release tags named build-vVERSION-bRUNNUMBER |
| GitHub Actions | .github/workflows/windows-advanced-discover.yml | Paired Windows/iOS15 tests, builds, Telegram sendDocument, versioned release |
| Extra workflows | .github/workflows/build.yml; ios15-cache.yml; publish-ios15-ipa.yml; telegram-channel-test.yml; ps4-telegram-first-package.yml | Historical/special-purpose; avoid confusing results with the paired production workflow |

Private database files:
- **playtorrio/watchlist-v1.json**: versioned JSON watchlist.
- **playtorrio/continue-watching-v1.json**: versioned JSON playback sessions.

The private database was created and initialized using the connected GitHub tool. Its contents were confirmed readable. At the handover checkpoint, the private JSON files contained **6 watchlist records and 12 Continue Watching records** (none marked deleted); counts are diagnostic only and may change immediately when devices sync. **Never copy the title identifiers, watch progress, or private records into public documentation.**

The user's connected GitHub account had repository read/write access to both repositories, but **agent/Codex GitHub authorization is not the same thing as a device token**. Each PlayTorrio installation needs a GitHub fine-grained personal access token authorized for the private database repository with Contents read/write. The user has already configured the private repository on at least one device and indicated completion. The token remains on-device (Flutter secure storage); **the GitHub-backed app should never ship a token embedded in source, installer, IPA, release notes, test fixtures or handover**. No token is needed by the agent to inspect or modify the repository through the connected GitHub integration.

The app's *code defaults* for sync remain **mghazalyh/ptv3** and **library-data**; the actual preferred private target is selected in **Settings → GitHub Library Sync** by setting repository **mghazalyh/torriodb** and branch **main**. **Do not claim the defaults were changed** without checking source.

The repo is a Flutter/Dart multi-format media application (movies, series, Stremio-compatible addons, torrents/debrid, manga, audiobooks, music). The active build focuses on **Windows x64** and **ad hoc-signed iOS 15/iPad TrollStore**, not App Store signing. CI uses Flutter **3.41.9**. The player uses locally patched **media_kit**, **media_kit_video**, platform native components and a bundled/verified TorrServer binary/framework.

## 2. Chronology of this working session (verified history and decisions)

### 2.1 Initial paired iOS 15 + Windows automation and player requirements
- Preserved the user's **non-floating** video player and explicitly did not reintroduce floating player.
- Built coordinated Windows portable ZIP, Windows setup EXE and iOS 15 TrollStore IPA from the *same exact Git commit*.
- Added/maintained a Telegram job that posts the **actual IPA file as a document** when under the supported size threshold, rather than just a link; link fallback is available when direct upload cannot be done.
- The Telegram chat was upgraded from an ordinary group to a supergroup. Early run **40285555868** had functioning Windows/iOS binaries and GitHub release but its Telegram step returned HTTP 400. A diagnostic workflow established a Telegram upgrade message. The fallback destination in the paired workflow was updated to the upgraded supergroup. **Never revert to the obsolete group destination**, and do not publish private IDs or authentication secrets in docs.
- Final correction commit **a9ae513efcc0c30bf983141fa32dd7a84c0fe6bc** produced successful run [40286832395](https://github.com/mghazalyh/ptv3/actions/runs/40286832395): Windows 17 successful steps, iOS 21, paired release success and Telegram document **message #4**.

### 2.2 English-first subtitles and audio
- Source: **lib/services/player/playback_autoselection.dart**, **lib/services/player/audio_language_priority.dart**, **lib/pages/player/player_screen.dart**.
- On loading a new source, default to **English-labeled audio** if a usable English track is identified; if none is labeled English, use the available/default audio rather than blocking playback. Includes late/native audio-track detection in MPV.
- **Automatically enable English subtitles** when available. Prefer **forced embedded English tracks**, then other embedded English tracks. If no embedded English is available, check external subtitle providers, prioritize forced English and **OpenSubtitles** when available, then other English options.
- Avoid source/track switching races with media epochs; users' **manual subtitle selection or disabling** must not be overwritten by automatic selection.
- Playback setup includes media_kit language preference and subtitle styling; tests: **test/playback_autoselection_test.dart**, **test/audio_language_priority_test.dart**.
- This is best-effort based on language labels and provider availability, not a guarantee every stream has English audio or subtitles.

### 2.3 Next Episode button, autoplay and addon continuity
- Source: **lib/pages/player/player_screen.dart**, **lib/widgets/player/player_transport.dart**, **lib/services/player/playback_autoselection.dart**, **lib/services/metadata/metadata_service.dart**.
- Autoplay uses player completion to attempt **_goToNextEpisode()** and provides a manual Next Episode action.
- Episodes are ordered chronologically and can cross season boundaries **when a complete episode catalog is available**; show metadata may be fetched from Cinemeta for Continue Watching launches lacking complete videos.
- For incomplete metadata, **nextEpisodeCandidate** can construct a numbered same-season candidate. This is a guess, **not a guarantee the episode exists**. The source lookup must succeed; on failure, provide a source chooser.
- Source preference: try the **same addon/source**, especially Torrentio/TorBox where possible, then fetch other sources. Preserve resume behavior when switching; do not apply the old episode's original initial position to the next episode.
- Visibility fix: initial small skip icon was hidden on compact Windows windows and missing when episode metadata was absent. It was replaced with a **visible labeled button**, e.g. **“Next Episode · S1E2”**, above the bottom controls, including compact width.
- Tested via **test/playback_autoselection_test.dart**; real-world provider behavior remains device/network dependent.

### 2.4 Replaced Trakt/Simkl My List ownership with GitHub-backed JSON
- User wanted easy free sync across **three or more devices**, disliked Trakt/Simkl for the large library and preferred an owned database. SQLite was considered but **versioned JSON on GitHub Contents API** was chosen because serialized SHA-based text updates are simpler, easier to merge and debug than sharing a binary SQLite file in Git.
- A private repository **mghazalyh/torriodb** was granted to the connected GitHub integration and initialized with **playtorrio/watchlist-v1.json** on **main**. The former public database branch **library-data** in ptv3 is historical, not the preferred user store.
- Source: **lib/models/my_list/my_list_item.dart**, **lib/services/my_list/my_list_service.dart**, **lib/services/my_list/github_library_cloud.dart**, **lib/pages/settings/github_library_settings_page.dart**, **lib/pages/my_list/my_list_page.dart**.
- App reads/writes through GitHub REST Contents API. **GET** obtains versioned JSON and its **blob SHA**. A **PUT** includes that SHA; 409/422 conflicts refetch and retry (up to six attempts). Merge local offline additions/deletions over remote; explicit deletion **tombstones** stop removed titles from reappearing.
- Offline edits are **journaled with SharedPreferences** and uploaded when available; token is kept separately in **flutter_secure_storage**. Failed network fetches must **not** be interpreted as empty libraries. First device import preserves already-existing remote records/tombstones.
- Changes are debounced approximately **5 seconds** after add/remove; periodic My List refresh approximately **every 2 minutes while open**. Startup and manual **Sync Now / Refresh** supported; normal automatic refresh has a ~60s throttle.
- Lifted legacy My List **500-item cap entirely**, not merely increased it to 2,500. Old integration tests assumed truncation and were fixed to verify 600-title persistence.
- When GitHub sync is configured, **automatic** My List sync goes through GitHub instead of Trakt/Simkl. Legacy Trakt/Simkl services and explicitly callable sync methods remain in the code for other functionality; do **not** claim every legacy integration was deleted.
- Initial attempts at portable CI needed regression-test updates. Final paired build [40294543521](https://github.com/mghazalyh/ptv3/actions/runs/40294543521) passed Windows 17 and iOS 22 steps, released matched packages and sent Telegram IPA **message #5**.
- Tests: **test/github_library_merge_test.dart**, **test/services/my_list_service_test.dart**, **test/integration/my_list_flow_test.dart** and associated UI tests.

### 2.5 GitHub-backed Continue Watching / cross-device playback position
- User explicitly asked to sync episode progress and have shows appear in **Continue Watching** across Windows/iOS devices. This is implemented as a **separate JSON file** in the same **private database repo**, using the **same on-device credential**.
- Data file: **playtorrio/continue-watching-v1.json**. Source: **lib/models/continue_watching/continue_watching_item.dart**, **lib/services/continue_watching/github_progress_cloud.dart**, **lib/services/continue_watching/continue_watching_service.dart**, **lib/widgets/home/continue_watching_slider.dart**, **lib/pages/player/player_screen.dart**.
- Each session stores the title/show ID, type, current season+episode, playback position seconds, duration, last watched timestamp, source/addon label and presentation metadata, with an update timestamp and deletion/completion marker. **One Continue Watching entry per show** (session key is title/show ID); this is **not** a complete event-by-event watch-history database.
- **Never upload streaming URLs, magnet URLs, info hashes, per-stream headers or torrent file indexes.** The cloud merge strips rawUrl, magnetUrl, infoHash, headers and fileIdx. Another device can look up a new stream by the title/episode and try to resume at the saved position.
- Pending local updates are journaled offline and committed approximately **every 60 seconds during playback**, plus best-effort flush when exiting the player. Continue Watching shelf polls approximately **every 2 minutes** while open and updates on startup or explicit sync; progress manual refresh is available in GitHub Library Sync settings.
- A completed session or manual removal becomes a **tombstone**, hiding the card on other devices. The merge favors **newer timestamped actions**, not necessarily higher position, to respect episode changes or intentional rewatches. SHA mismatch retries on concurrent writes. First import includes existing local sessions without reviving previously deleted remote sessions.
- With GitHub configured, GitHub is the preferred cloud owner of Continue Watching; Trakt/Simkl can still exist for other legacy contexts when GitHub is disabled. Local media state must survive network errors.
- Tests: **test/github_progress_merge_test.dart**, plus existing library and player tests. Paired [40302516038](https://github.com/mghazalyh/ptv3/actions/runs/40302516038) completed Windows 17, iOS 22, matched release and actual Telegram IPA **message #7**.
- Known limits: based on device clocks (clock skew could affect last-write-wins); no push transport, only polling; GitHub write/read quotas; remote media sources can expire or differ; two physical device end-to-end tests have **not yet** been recorded as passing. GitHub has a writable versioned JSON file, not a server-hosted running SQLite database.

### 2.6 Versions, Next Episode discoverability and unique GitHub releases
- The user could not find Next Episode on Windows and also asked to know **the exact installed version** in app, GitHub workflow titles, Windows installers and releases.
- Versioning code: **lib/services/config/build_identity.dart**, **pubspec.yaml**, **lib/pages/settings/settings_page.dart**, **about_settings_page.dart**, **updates_settings_page.dart**, **installer/windows/setup.iss**, **windows/runner/Runner.rc**, **lib/services/updater/app_updater_service.dart**.
- On build the CI supplies a semantic **build name**, a numerical **GitHub run number** as build number, and compile-time **PLAYTORRIO_COMMIT** / **PLAYTORRIO_RUN**. About/App Updates display the actual installed version/build and short Git revision. Windows executable and installer metadata and GitHub artifact names/release title include matching version identifiers.
- Update checker was pointing at another upstream repository; it now checks **mghazalyh/ptv3/releases/latest** and parses tags of the form **build-v1.1.0-b90** (also traditional **v1.1.0**), comparing both semantic version and numerical build. A previous edit corrupted the updater file; its original source was restored and a clean smaller modification was made. **Do not reintroduce the malformed updater file**, and keep it covered by analysis.
- Unique release tag format **build-vVERSION-bGITHUB_RUN_NUMBER**. Unique download filename prefix **PlayTorrio-vVERSION-buildRUNNUMBER**; the paired workflow verifies both platforms' artifacts, uploads ZIP, installer, TrollStore IPA and **SHA256SUMS.txt**. Older dated release/tag formats exist for historical builds but should not be reused for new packages.
- Verified release: **v1.1.0 Build 90**, [build-v1.1.0-b90](https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.0-b90), [successful run 40331619688](https://github.com/mghazalyh/ptv3/actions/runs/40331619688), Windows 17/17, iOS 22/22, Telegram actual document **message #17**. This remains latest *paired verified* release as of checkpoint.
- Build 89 **40330530174** failed analysis because of the updater edit, then was canceled/superseded; Build 90 passed after restoration.

### 2.7 Always-visible Show Details from Continue Watching and video player — v1.1.1
- User said when resuming a show via **Continue Watching**, there was no clear way to get back to the show's main page to read synopsis, actors and related details.
- Root cause: an existing tiny info icon on the Continue Watching card was **hover-only on Windows**, and the full video player had **no details navigation action**.
- New central route helper: **lib/utils/navigation/media_details_navigation.dart**. Routes regular movie/series to **DetailsPage** with Cinemeta metadata lookup, anime to **AnimeDetailsPage**, Arabic anime to **AnimeArabicDetailsPage**, using appropriate content IDs. Provides synopsis, cast/actors, seasons/episodes where upstream metadata exists.
- **lib/widgets/home/continue_watching_slider.dart** now always renders a clearly labeled **“Show Details”** button **without hover**, while keeping the card's main click as **Resume Playback**. The card height was adjusted to fit the CTA.
- **lib/widgets/player/player_top_bar.dart** renders **“Show Details”** (short “Details” on compact widths) with an info icon, when a media title identifier exists.
- **lib/pages/player/player_screen.dart**, method **_openShowDetails()**: persist current position, pause if playing, leave fullscreen temporarily if active, open the details route **without removing the player from the navigation stack**, then on return restore fullscreen and resume if previously playing. The intent is to preserve the player, stream, episode and position rather than rescrape the stream.
- Widget tests **test/show_details_navigation_test.dart** cover always-visible details on a Continue Watching card, player's details callback, and disabled controls when no title context. Tests are **not** a substitute for a physical-device navigation/resume check.
- Build definitions bumped to **v1.1.1**, **pubspec version 1.1.1+11**, uniquely labeled GitHub **Build #97**; main feature implementation commits include **a916dacc**, **3761dc56**, **68a650c9**, **0ea21d07**, **5c0bb166**, **f7ae59e7**, and v1.1.1 release/workflow commit **f0e095a7a99af3faf340f04774fd987651507dac**.
- **CRITICAL INCOMPLETE DELIVERY:** [40336345197](https://github.com/mghazalyh/ptv3/actions/runs/40336345197) was **completed with failure**. Windows **121619557367**, 17 successful steps, produced artifact **PlayTorrio-Windows-v1.1.1-build-97** (artifact ID **12657138590**, about 111 MB as GitHub Actions archive); **iOS job 121619557805 was canceled before running on a macOS runner**; Telegram and paired publication jobs were skipped. As of this handover **there is NO verified v1.1.1 IPA or GitHub Release**. Don't fabricate release download URLs.
- Primary next step: rerun or otherwise finish a *matching* iOS15 build, then publish and verify versioned release and actual Telegram document; validate playback/resume navigation in Windows and iOS.

## 3. File map: where to work and what not to break

| File / directory | Responsibility |
| --- | --- |
| lib/pages/player/player_screen.dart | media_kit video controller, playback progress, audio/subtitle choice, Next Episode, Show Details pause/return |
| lib/widgets/player/player_top_bar.dart | Player back/title, Show Details, Episodes, screenshot/download/cast actions |
| lib/widgets/player/player_transport.dart | Transport bar, prominent Next Episode button, seeking, fullscreen, playback menus |
| lib/services/player/playback_autoselection.dart | Pure English subtitle and next-episode/source preference functions |
| lib/services/player/audio_language_priority.dart | English language classification and audio preference |
| lib/services/metadata/metadata_service.dart | Title metadata from Stremio/Cinemeta, episode catalogs and metadata fallback |
| lib/pages/details/details_page.dart | Main details page, synopsis, cast and seasons; navigation uses push, **not pushReplacement** |
| lib/utils/navigation/media_details_navigation.dart | Common detail navigation for conventional and anime content |
| lib/pages/player/watch_screen.dart | Stream source chooser; opens PlayerScreen from chosen source |
| lib/models/movie/ / lib/models/stream/ | Movie/MovieDetail/Video/stream models |
| lib/models/my_list/my_list_item.dart | My List local JSON model/unique key |
| lib/services/my_list/my_list_service.dart | Local My List, debounce, persistence and GitHub merge coordination |
| lib/services/my_list/github_library_cloud.dart | GitHub Contents API, optimistic SHA writes, offline queue, token on device |
| lib/pages/my_list/my_list_page.dart | Library UI and manual/periodic sync status |
| lib/pages/settings/github_library_settings_page.dart | One-screen repo, branch, secure token, Connect & Sync, sync status |
| lib/models/continue_watching/continue_watching_item.dart | Per-title playback session model and completion calculation |
| lib/services/continue_watching/continue_watching_service.dart | Load, journal, save/remove/resume sessions, expose activeItems notifier |
| lib/services/continue_watching/github_progress_cloud.dart | Same private repo credentials, versioned progress JSON and conflict handling |
| lib/widgets/home/continue_watching_slider.dart | Resume cards, always-visible Show Details, remove, progress bar and refresh |
| lib/services/config/build_identity.dart | Compiled Git SHA/run and installed package version helpers |
| lib/services/updater/app_updater_service.dart | Look up own versioned releases; compare versions/build numbers |
| lib/pages/settings/about_settings_page.dart; updates_settings_page.dart | Show installed version/build/commit |
| pubspec.yaml; windows/runner/Runner.rc; installer/windows/setup.iss | Semantic version, Windows PE version and installer labels |
| .github/workflows/windows-advanced-discover.yml | Full paired Windows/iOS 15 CI and publishing |
| .github/workflows/telegram-channel-test.yml | Limited diagnostic Telegram workflow (historical) |
| .github/workflows/ps4-telegram-first-package.yml | Separate PS4 workflow, **not** a substitute for paired Windows/iOS release |
| test/github_library_merge_test.dart | My List import/delete/merge/offline/corrupt JSON regression |
| test/github_progress_merge_test.dart | Cross-device progress, session completion and timestamp merge |
| test/playback_autoselection_test.dart | English subtitle, next episode, season and preferred source |
| test/audio_language_priority_test.dart | Audio English-language preference |
| test/show_details_navigation_test.dart | Show Details actions from home shelf/player |
| test/services/my_list_service_test.dart; test/integration/my_list_flow_test.dart | Local list behavior; validates no 500-title truncation |
| test/tmdb_rate_limit_test.dart; test/tmdb_advanced_discover_test.dart | API politeness, advanced discovery filters and date range |
| test/trakt_merge_plan_test.dart; test/trakt_cloud_library_test.dart; test/simkl_hearts_cloud_test.dart | Legacy integration guards retained in CI |

**Earlier branch features** covered by existing integration checks: TMDB Advanced Discover, pagination/scroll restoration using **_discoverScroll** and **oldMaxExtent + 160.0**, nested Details navigation using **Navigator.push** instead of replacing history, API rate limits, TorBox Quick Settings/config transfer and source discovery. Avoid regressing these when changing details or player navigation. Prior dated IPA release **ios15-advanced-discover-20261025** is historical.

**Unfinished request:** User also mentioned general **feature parity with a separate “mghazaly ptv” repository** (features, not copying code). The task was superseded by cross-device Continue Watching work, and **no systematic feature-by-feature comparison / port is confirmed complete**. Inspect and confirm source repository identity/access before claiming parity.

## 4. Database contracts and synchronization details

### 4.1 Why GitHub JSON, not shared SQLite
GitHub repositories expose files, not a managed multi-device writable SQLite service. A SQLite file repeatedly downloaded/overwritten would cause hard-to-merge binary conflicts. Two small, human-inspectable JSON documents with optimistic locking are a practical no-server compromise for watchlists and progress on a few devices.

### 4.2 Watchlist v1
Top-level: **version: 1**, **records: mapping of stable media uniqueKey to record**. Each record includes **item** (MyListItem JSON) and **deleted** boolean; deletion entries survive sync. The merger: fetch newest remote, merge first-device local only if no remote record exists, overlay pending local operations, PUT with remote blob SHA; on 409/422 refetch up to six times. On success, acknowledge only operations matching the snapshotted values, so edits made while uploading are not silently cleared; persist the merged view locally. No shared event history.

### 4.3 Progress v1
Top-level: **version: 1**, **records: mapping from show ID / sessionKey to record**. Each record includes **updatedAt** in UTC, **deleted**, and **item** with the non-streaming ContinueWatchingItem fields (title, type, poster/year, episode, position/duration, last watched, safe source labels). Media URLs, magnet/infoHash, file index and HTTP headers excluded. Merge timestamped recent edits over remote and preserve remote tombstones during first-device import. Remove/complete => tombstone. Session UI generally shows items past 10 seconds and below the completion threshold (**90%**).

### 4.4 Trigger matrix

| Action | My List | Continue Watching |
| --- | --- | --- |
| Local add/remove | Queue and autosync after ~5s debounce | N/A |
| Playback progress | N/A | Local persist during playback, GitHub batch after ~60s |
| Player exit | N/A | Save final timestamp, best-effort immediate cloud flush |
| Open home / Continue Watching | N/A | Cloud refresh at startup / shelf appearance |
| Leave screen open | My List refresh ~every 2 min | Continue Watching shelf refresh ~every 2 min |
| Manual Settings sync | Immediate | Immediate |
| Disconnected/network failure | Keep local list and pending journal | Keep local progress and pending journal |
| Concurrent edits from devices | SHA conflict retry, deletion tombstones | SHA retry, timestamp arbitration, tombstones |

**Caution:** GitHub is not a push notification service; foreground screen refresh and upload throttling determine freshness. Offline saved state and cross-device tests should be checked before making stronger guarantees. Rate limits, token permissions, network failures, clock skew, merged updates and incomplete metadata are expected failure modes.

## 5. Builds, packaging, artifacts, releases and Telegram

### 5.1 Production paired workflow
File **.github/workflows/windows-advanced-discover.yml** (despite the legacy basename, this is the main *paired* pipeline).
- Trigger: push to branches (pattern **), v* tags and manual dispatch; concurrency group keyed by git ref with **cancel-in-progress: true**. A second commit while a build is running can cancel that build. Prefer batching source changes and starting verification only after the final tested commit.
- Windows: **windows-latest**, Flutter 3.41.9; key-free .env; targeted Flutter unit/widget tests and analyzer; official TorrServer binary downloaded and checked against expected SHA256; Windows x64 release; portable ZIP; Inno Setup EXE; published Actions artifact includes both.
- iOS 15: **macos-latest**, Flutter 3.41.9, local TorrServerKit iOS arm64 framework; Flutter tests and analyzer; flutter build ios --release --no-codesign; minimum iOS 15 check; **ad hoc codesign**; package **Payload/Runner.app** into TrollStore-compatible IPA; validate archive, iPad family, signature and minimum OS; publish Actions artifact.
- Telegram IPA job depends on successful **iOS** build, reads the packaged IPA and attempts **sendDocument**; has a link fallback when attachment is not feasible. The destination was updated after Telegram upgraded the group to a supergroup. The job's success must be checked from logs to distinguish **actual file** from **fallback link**; no secret values belong in handover.
- Paired release job depends on **both Windows and iOS**. It downloads Actions artifacts **from the same run**, verifies non-empty packages, calculates hashes, and creates/upserts tag **build-vVERSION-bRUNNUMBER**, unique release title and package filenames, plus SHA256SUMS.
- The app build version is **the real CI run number**, not just pubspec's local development suffix. Check both **Settings → About PlayTorrio** and **Settings → App Updates** for installed version/revision.

### 5.2 Release and run history worth preserving

| Milestone | CI / release | Outcome |
| --- | --- | --- |
| Initial player autoplay/English tracks; Telegram group migration fixed | [40286832395](https://github.com/mghazalyh/ptv3/actions/runs/40286832395) | Windows, iOS, paired release and Telegram document #4 successful |
| Github My List + no legacy cap | [40294543521](https://github.com/mghazalyh/ptv3/actions/runs/40294543521) | Windows 17, iOS 22, release, Telegram document #5 successful |
| Private Continue Watching progress | [40302516038](https://github.com/mghazalyh/ptv3/actions/runs/40302516038) | Windows 17, iOS 22, release, Telegram document #7 successful |
| Clearly labeled Next Episode, installed build identity and unique releases | [40331619688](https://github.com/mghazalyh/ptv3/actions/runs/40331619688) | **v1.1.0 Build 90**, Windows 17, iOS 22, paired release and Telegram document #17 successful |
| Show Details from shelf and player | [40336345197](https://github.com/mghazalyh/ptv3/actions/runs/40336345197) | **v1.1.1 Build 97**: Windows 17 succeeded, iOS job canceled, downstream Telegram/release skipped. **Not fully shipped.** |

**Verified v1.1.0 Build 90 release links** (not v1.1.1):
- Release overview: https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.0-b90
- Windows installer: https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.0-b90/PlayTorrio-v1.1.0-build90-Windows-Setup.exe
- Windows portable ZIP: https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.0-b90/PlayTorrio-v1.1.0-build90-Windows-x64-Portable.zip
- TrollStore IPA: https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.0-b90/PlayTorrio-v1.1.0-build90-iOS15-TrollStore.ipa
- Checksums: https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.0-b90/SHA256SUMS.txt

**Windows-only v1.1.1 Build 97 artifact:** [workflow run 40336345197](https://github.com/mghazalyh/ptv3/actions/runs/40336345197) → artifact named **PlayTorrio-Windows-v1.1.1-build-97**, ID **12657138590**. This is an Actions artifact, **NOT** a GitHub release download. The run failed as a whole because iOS was canceled; treat this as a testable Windows candidate, not fully published paired version. **Never invent a v1.1.1 IPA or release URL.**

### 5.3 Releasing future changes safely
1. Fetch the current HEAD of **parity-floating-player-both**, inspect any concurrent upstream edits; do not overwrite unreviewed changes.
2. Implement the feature; update unit/widget tests and both platform CI test/analyze lists when relevant.
3. Bump semantic **version** coherently (pubspec, workflow display/title/labels/build names/release environment, Windows runner/installer, fallback about/settings) if it is a user-facing release; **build number is supplied by GitHub run_number**.
4. Update **handover.md in the same commit/change** documenting behavior, source files, tests, hazards and pending work (this rule is also in AGENTS.md).
5. Let a **single final commit** trigger the paired workflow. Avoid repeated small workflow commits while runners are active; the concurrency rule cancels older runs.
6. Verify all four jobs: Windows, iOS15, Telegram, publish-paired. Read Telegram logs for direct document confirmation vs fallback. Independently fetch the new release assets and compare names/commit/build.
7. Only then give the user direct download links to confirmed published packages, including Windows installer, portable ZIP and TrollStore IPA; disclose physical-device test status.
8. Update the handover's status matrix/run history to reflect that actual verified state; mirror the living handover and AGENTS guidance to **main** so newly started development tools find it. A doc-only push on the development branch can trigger CI because the workflow watches all branches; distinguish such a doc-run from a code release.

## 6. Known bugs, caveats and outstanding work

**P0 — latest release blocked:** v1.1.1 **Build 97** has **Windows green but iOS canceled**; paired publication and Telegram were skipped. Investigate macOS queue/runner cancellation or retry the matching commit. **Build 90** remains latest fully verified matched Windows+iOS release. Do not announce v1.1.1 as delivered until a future successful run verifies all outputs.

**P1 — on-device Show Details regression:** Verify Windows and TrollStore: from a Continue Watching show card choose Show Details → view synopsis/cast/episodes → Back; from playing video choose Show Details → playback pauses, navigates, restores fullscreen when applicable and resumes from the saved position. Check small Windows widths and anime routes. Current tests cover CTA visibility/callback, not a full remote source playback session.

**P1 — actual 2+ device GitHub sync:** Verify same movie/show appears and removes correctly in both My List and Continue Watching, including offline edits, concurrent updates, completed episode, cross-season behavior and device clock differences. CI tests cover pure merge rules but **not** user-device runtime behavior.

**P1 — episode metadata and source fallback:** Continue Watching may only have minimal episode metadata; Cinemeta episode fetch can time out, fall back to guessed next episode, or select another source when preferred Torrentio/TorBox stream is unavailable. The app should always offer an actionable source picker rather than silently failing.

**P1 — credentials and privacy:** The private database belongs in **torriodb/main**, not a public branch. No credentials or user playback metadata should be committed in the source repo, public logs, release summaries or test fixtures. Never publish secret values in handover. The source still retains historical public database defaults, so installation settings matter.

**P2 — external dependencies:** English subtitles depend on embedded tracks and external providers; MPV audio labels are not always present. The updater depends on correct release tag parser and public GitHub release metadata; GitHub API has limits. No real-time push sync. Legacy Trakt/Simkl remains available but should not override GitHub-owned My List.

**P2 — feature parity with another ptv repo:** User asked to synchronize **features**, not literally copy source, from a separately named “mghazaly ptv” repository. A formal feature comparison and selective port have not been completed in this session. Inspect and confirm repository identity before work.

**P2 — docs drift:** README.md and CHANGELOG.md largely describe the older upstream foundation and are not comprehensive/fully current for the working 2026 branch. The living **handover.md** is the operational source of truth; consider updating README/CHANGELOG for user-facing documentation after release status is stable.

**Do not** mark a feature “verified on device” merely because Flutter tests pass, do not mark a run “successful” when a required job was canceled/skipped, do not mark Telegram “file sent” if logs show only link fallback, and do not bring back floating-player behavior.

## 7. Session-specific product and communication decisions

- User values **autonomous implementation**, functional deliverables and release verification over repeated setup questions. Make best effort using connected private GitHub repos and CI.
- User wants **free, easy, independent ownership** of watchlists and watch progress on 3+ devices; GitHub private JSON chosen instead of Trakt/Simkl as the primary cloud state for those features.
- User wants **English on automatically where available**, no blocking if missing; **same source/addon next episode** preferred; non-floating video controls retained.
- User wants access to a title's **main details page (synopsis, actors/cast, episodes)** directly from Continue Watching and also the player, and wants uninterrupted resumption after returning.
- User wants **clear installed versions** and obvious matching version/build across in-app About, App Updates, GitHub Actions, Windows installer and all release filenames.
- User wants the **actual TrollStore IPA uploaded to Telegram** when possible, with matched Windows packages.
- User strongly prefers the release-update answer format: success/failure icon, **version/build** headline, clear feature location, explicit Windows/iOS CI step status, **direct verified download links**, Telegram document message status, and truthful caveats about what has not been physically tested. See actual v1.1.0 Build 90 communication for shape.
- User explicitly requested **“every update, always update the handover.md”** and for the initial handover to include *all work from the session*. Keep this file durable, comprehensive and current. Do not merely mention that it should be updated: **actually commit its revision with future work**.
- The user asked not to be repeatedly reminded about previous credential housekeeping. Avoid repetitive warnings. Nevertheless, never leak or embed tokens.

## 8. Update log for this living handover

| Date (UTC) | Changes / checkpoint | Proof / next action |
| --- | --- | --- |
| 2026-10-26 | Initial comprehensive session reconstruction; documented public source/private DB, all GitHub sync and playback changes, versioning, exact verified Build 90, incomplete v1.1.1 Build 97, test coverage and delivery history. Added a root AGENTS.md rule requiring updates to this file for every substantive future repository change. | Read [Build 97 run](https://github.com/mghazalyh/ptv3/actions/runs/40336345197) and [last verified paired release](https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.0-b90). The initial handover is mirrored on main and parity-floating-player-both. |

### Required format for every future handover update
For every meaningful new edit, append a dated entry including: **user request/goal; files and design changes; branch + commit; tests/analysis results; Windows/iOS build IDs and conclusions; release and asset links only if verified; actual Telegram document/fallback result; anything not tested; remaining risks and next steps.** Update top-of-file status so it does not become contradictory. If only documentation changed, explicitly say “documentation-only, no new application release.”

The content of this file is intentionally operational; keep it source-backed. This document is a record of what was done and what was verified, **not** authorization to guess future releases, expose private data, or turn incomplete work into a success claim.
