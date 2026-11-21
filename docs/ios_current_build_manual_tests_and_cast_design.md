# PlayTorrio iPad: installation freeze, manual diagnostics, Live TV scan, media handoff

## Owner requirements (2026-11-21)

1. Installed iPad is iOS **build 262**, code commit `a74540388621ac820231ac77c1417cba15dc5115`. New Dart code committed to GitHub **does not appear in that installed app**. A new IPA cannot be installed at short notice. Do not base current live-device diagnosis on code that is not installed.
2. **Do not trigger a new iOS IPA build or installation.** Do not change `.github/ios-speech-release-request.txt` unless the owner explicitly requests a release.
3. **No scheduled ChatGPT tests, no background monitor, and no automation.** The owner manually initiates tests from ChatGPT. The previous PlayTorrio iPad Matrix Watch automation was disabled on 2026-11-21.
4. Preserve the existing paired, opt-in LAN remote for iPhone navigation. The new iPhone-to-iPad media handoff should be additive, not a replacement.
5. Preserve all Stremio TV/movie/series/resource compatibility, Torrentio, TorBox, existing playback preferences and source identity checks. No arbitrary stream URLs from the sender.

## Real installed-device counts and progress

* The installed Live TV addon is `ptv3-livetv-addon.pages.dev`.
* 2026-11-21: A Torriodb `discover_live_matrix` call with `limit:120` returned 120 entries; a follow-up with `pages:6,limit:150` returned **150 distinct entries** and hit the cap. Thus **at least 150 channels** are available; neither result establishes the exact total.
* The manually started native matrix `matrix262_full50_20261121133315` uses 50 unique channels and three repeats for 150 channel rounds, each source up to 36, 300-second sustained observations for video candidates.
* At 2026-11-21 14:20 UTC the status showed `phase=running`, 6 completed channel rounds, 17 completed source attempts, 7 sustained video-verified attempts, 14 distinct observed source hosts, and 5 evidence upload failures. This is a **partial** run.
* The successful Cine Romántico and Unbeaten observations include actual 720p/1080p native video, 11 tracks, moving timelines and five-minute sustained playback.
* NFL playback remained blocked at native MPV decoding despite HLS transport reachability and a bounded browser-header/preferred-relay runtime policy. That policy was explicitly rolled back. Distinguish HTTP reachability from actual native decode.

## New source code for a future installation (NOT present on iPad build 262)

### Asynchronous Live TV See All health scan

* `CatalogPage` starts a bounded, four-worker catalogue preflight when a Live TV section's **See All** list opens.
* Pages through the exact installed Stremio catalog using its declared `skip` extra, until exhausted or the safety cap (2000 items / 30 pages). Lists and badges render incrementally without requiring every scan to finish.
* Each channel resolves streams through the app's installed addon integration and checks only a few HTTP/HLS candidates and segment signatures. Results are `Checking`, `Likely healthy`, `Poor`, or `Unverified`. Manual rescan is available. Errors and cancellation are contained.
* This is **not** a full native decoder test. Our on-device NFL evidence proves HTTP 200/206 can accompany zero tracks. The interface labels the result `HTTP check`, and explicitly warns that playback is not confirmed. Never claim a "likely healthy" badge certifies native video.
* Avoid unattended native MPV playback of 150 channels while the user is trying to watch something. It is resource heavy and can compete with the active video/audio session.

### Paired iPhone Play on iPad handoff

* Reuses `LanRemoteService` PIN-paired receiver and in-memory 256-bit bearer token, now with `POST /cast` accepting a strict `LanCastRequest`.
* The handoff contains only Stremio media type, media ID, title, optional exact episode ID and season/episode numbers. **Never transmit addon URLs** (they can contain configured credentials), stream URLs, info hashes, cookies, or player headers.
* The iPad resolves compatible metadata/stream sources itself via installed addons, honors the user's existing Watch Source preferences, and opens `PlayerScreen` for a compatible playable stream; otherwise it opens the normal `WatchScreen` source chooser. For TV, direct HTTP streams only.
* iPhone poster cards, episodes, Home hero Watch Now, and Details Play button receive a long-press. A visible "Hold · Play on iPad" / "Hold · iPad" cue advertises it; long-press opens a bottom sheet targeting the paired iPad. The existing tap behavior remains unchanged.
* Pairing survives normal in-app navigation in memory, not restarts, and the app must remain foreground on the iPad. Users can pair through the existing Remote Control page.
* `PlayerScreen` no longer renders the top-right `LiveTvSignalBadge`; internal native signal health and loading/status recovery still operate.

## Release/testing discipline

* Ordinary Dart commits trigger only lightweight GitHub CI, not an IPA build. Tests may validate algorithms but cannot establish iPad runtime behavior until a release is installed.
* Keep the current build 262 matrix and user-triggered scoped experiments separate from this code. Do not inject unsupported commands into it.
* Do not create scheduled tasks. Future testing only when the owner explicitly starts it in ChatGPT.
* When the eventual installation becomes possible, perform targeted real-device validation of the new catalog preflight labels, long-press targeting, exact episode routing, pairing lifetime, automatic playback, and removal of the top-right badge. Until then, treat them as source-code changes only.
