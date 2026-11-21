# PlayTorrio pre-release code verification (2026-11-21)

The next iOS release must be consolidated and tested before it is installed.
Do not conflate GitHub code with iPad build 262. Do not trigger an IPA build
or platform packages without an explicit future owner request.

## Changes staged for the next IPA

* Correct native-verified backup ranking versus video that starts and stalls.
* Exact series episode selection for paired iPhone-to-iPad media handoff.
* Live TV iPad cast respects exact recent native-verified source preferences.
* Failed native scan exceptions invalidate remembered sources.
* Normal Live TV playback can teach in-memory exact source preference only
  after repeated decoded video progression with positive dimensions, tracks,
  unbuffered motion and at least five seconds of progression.
* Learning state resets on source switch, native reopen, backgrounding and stall.
* iOS release workflow fails before IPA packaging if the staged health
  scanner, source preference, learning gate, cast request or Torriodb queue
  regression tests fail.

## Source-only test workflow

`.github/workflows/ios-source-preflight-tests.yml` is test-only. It uses the
release's pinned Flutter 3.41.9 on a macOS runner. It is triggered solely by
an intentional update to `.github/ios-source-preflight-request.txt` or by a
manual workflow dispatch. It runs focused regression suites, then the complete
Flutter test directory. It never calls `flutter build`, `xcodebuild`, codesign,
IPA packing or platform delivery. It requires no private credentials.

Source-level tests are not substitutes for testing media_kit on real iPadOS.

## Current physical-device evidence boundary

Installed iPad: build 262, commit
`a74540388621ac820231ac77c1417cba15dc5115`.
Matrix: `matrix262_full50_20261121133315`, 50 unique channels times
three rounds. While the matrix remains active, read status and telemetry only.
Never infer playback health from HTTP 200/206 or provider descriptions.
Sustained native decoded video and exact source attribution are required.
Source metadata URLs, signed headers, diagnostic tokens and user credentials
are not included in this documentation.

The staged scanner, cast handoff, and normal-playback source learning are not
installed on build 262 and cannot be physically accepted until a later IPA is
explicitly requested and installed.

## Acceptance checklist for the first consolidated iOS installation

1. Verify all preflight regression suites pass on the **exact** release SHA.
2. On iPadOS 15, open Live TV See All. Verify pagination, progress, navigation
   cancellation, muted native checks and health-first ordering.
3. Confirm that a network-reachable but undecodable source is not labeled
   working. Confirm verified backups outrank stalled sources.
4. Watch a healthy channel long enough to establish source learning, then
   re-open it from the regular channel list. Check exact addon/URL preference.
5. Confirm stale/invalid signed URLs are not replayed from session cache.
6. Verify source failover preserves headers and does not blindly use HLS relay.
7. Test paired iPhone-to-iPad movie handoff and exact series S/E routing,
   including a missing or conflicting episode ID.
8. Test paired Live TV channel handoff via the iPad's installed Stremio addons.
9. Check Torrentio, TorBox, normal movie/series streams, subtitles, pause/resume,
   source preferences, controls, and the existing LAN remote navigation.
10. Confirm the Live TV top-right signal badge is absent while internal native
    recovery telemetry remains available.
11. Confirm the iPad stays responsive, does not leak audio from the scanning
    player and does not run multiple native source scans simultaneously.
12. Inspect heartbeat and diagnostic upload reliability, distinguishing absent
    reports from native playback failure.

No source analysis or CI test can guarantee that future iPad hardware runtime
checks pass. Preserve this distinction when determining release readiness.
