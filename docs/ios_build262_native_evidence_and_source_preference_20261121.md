# iPad Build 262: source verification, source preference, and manual-only testing

## Evidence snapshot, 2026-11-21 14:44 UTC (22:44 SGT)

* Installed device: iPad build **262**, source commit
  `a74540388621ac820231ac77c1417cba15dc5115`.
* Running native matrix: `matrix262_full50_20261121133315`.
* 50 distinct channels configured across 3 repeats = 150 channel rounds.
* **17/150 channel rounds**, **41 source attempts**, **9 sustained
  successes** and **6 upload failures** at the saved snapshot.
* Distinct reported source hosts: **19**. A host is not a unique source.
* An independent catalog query reached its requested limit of 150 channels;
  **at least 150**, not an authoritative complete total.
* Newer candidate files may appear after this snapshot. The matrix is not
  finished and missing candidate files must never be counted as failures.

### Evidence-backed observations

1. **Cine Romántico** sustained native video using `jmp2.uk`.
   One requested CloudFront source succeeded only after switching to a
   different source. Build 262 uses host-based source attribution, so two
   different URLs using `jmp2.uk` cannot be distinguished accurately.
2. **Unbeaten** sustained 1080p native video when directly using
   `unbeaten-tcl.amagi.tv`; a relayed backup attempt did not render.
3. **Tennis Channel** sustained native playback on
   `cdn-uw2-prod.tsv2.amagi.tv`, while another source failed.
4. **On Patrol: Live** sustained video with `a-cdn.klowdtv.com`.
5. **RacerNetwork, PlutoTVSciFi, HappyDays and Cops** had missing native
   video on tested candidates. Failure responses included inaccessible
   segments, TLS, HLS manifest, and access errors. Network 200/206 alone
   does not prove actual playback.
6. `jmp2.uk` occurs on both successful and failed tests. **Never globally
   block or promote an entire hostname** based on this small sample.
7. Relay activation is frequently observed on failing candidates, but this
   is **correlation, not proof of causation**. It does not justify
   disabling relay globally or disturbing the active baseline matrix.

## Implementation committed for a later iOS release

* A successful **real MPV** scan records the precise Live TV source identity
  (channel ID, addon name, full URL) in a private in-memory cache.
* When the user opens the matching channel's Watch source list, PlayTorrio
  promotes the verified source only when the addon and URL still match the
  fresh Stremio results. Same-host backups do not falsely inherit credit.
* Entries expire in 20 minutes. No URL is persisted, sent to GitHub, or
  treated as valid after the addon rotates signed URLs.
* A failed native scan or confirmed playback recovery invalidates the
  corresponding exact identity, allowing other sources to take precedence.
* No movie, series or episode ranking is changed.
* The existing HTTP-only scan may not generate a verified preference:
  only native decoded frame, dimensions, tracks and timeline progression can.
* The already implemented See All sorting and native scan remain independent
  of the current app. They require future installation to operate.

## Deployment and testing restrictions

* **No new IPA, no signing, no release marker and no installation** are
  triggered by these commits.
* The previously started matrix remains running on **installed Build 262**.
  A GitHub Dart source change has no effect on this installed runtime.
* The PlayTorrio hourly scheduled task remains disabled. Further starts,
  changes, and remote tests are authorized manually from chat.
* `.github/workflows/playtorrio-fast-checks.yml` has been changed to
  `workflow_dispatch` only, so source pushes do not start Linux/Windows
  quality-gate runners while the user has suspended non-iOS builds.
* Regression tests for exact-source selection, same-host false attribution,
  addon identity, expiry, invalidation and native-only promotion are staged
  for a later explicitly authorized test run.
