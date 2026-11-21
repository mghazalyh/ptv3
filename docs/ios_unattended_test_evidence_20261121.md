# PlayTorrio unattended iPad evidence and pre-release validation

Captured 2026-11-21 (SGT). This is an evidence snapshot, not proof that
the unfinished source matrix or new GitHub code has passed on a real device.

## Physical iPad baseline

* Device: iPadOS 15, installed PlayTorrio **build 262**, source commit
  `a74540388621ac820231ac77c1417cba15dc5115`.
* Cloud diagnostic bridge: opt-in Torriodb, heartbeat confirmed healthy.
* Native matrix: `matrix262_full50_20261121133315`.
* Last sampled status: running; **20/150 channel rounds**, **48 source
  attempts**, **14 sustained viewing sessions**, 24 observed CDN hostnames,
  six result/status upload failures.
* The installed version's `verifiedSources` field counts sustained sessions
  even if a different source took over via failover. Never treat it as 14
  independently proven original URLs. Individual `requestedSourceVerified`
  fields are authoritative for exact-source attribution.
* Existing candidate reports may be absent when an upload failed; a missing
  file is not equivalent to an unavailable channel.

## Completed unattended addon probes (read-only)

The installed action `probe_addon` checked real manifest.json and stream/tv
resources, using the iPad's installed and enabled Live TV addon. It returns
only sanitized hostnames, counts, status codes and format hints.

* First batch `unattended_probe_20261121151425`: Cine Romántico,
  Pluto TV Sci-Fi, NFL Channel and Tennis Channel.
* Expanded batch `unattended_expanded_20261121151547`: Charge, This Old
  House, Cops, The Walking Dead Universe, FTF Sports, Racer Select,
  On Patrol Live, and Degrassi.
* **All 12** individual channel probes returned valid manifests and
  structurally valid stream arrays. In the expanded eight, both endpoints
  returned HTTP 200. Most tested channels advertised two or three direct HTTP
  sources; Charge advertised one.
* A manifest/stream response is **not** proof of decoded video. The matrix
  separately confirms several of those channels fail native playback.

Important observed contrasts:

| Channel | Addon source result | Physical MPV evidence |
| --- | --- | --- |
| Cine Romántico | 3 advertised HTTP sources | Two requested links verified; another session succeeded only after failover |
| Tennis Channel | 3 advertised sources | Second source verified, others failed in observed round |
| FTF Sports | 3 HLS sources | All three requested links achieved sustained video in observed round |
| On Patrol Live | 2 HLS sources | Backup verified; first request only sustained playback after switching |
| Pluto TV Sci-Fi | 3 HLS sources | No sustained native video in observed round |
| Cops | 3 sources | No sustained native video in observed round |
| The Walking Dead Universe | 3 sources | No sustained native video in observed round |
| Charge | 1 HLS source | Native TLS/segment errors and repeated missing-HTTP errors |
| This Old House | 3 sources | At least one session played via backup; another showed TLS, manifest, segment, missing-HTTP errors |
| NFL Channel | 3 sources | Valid addon resources; earlier native decode failures despite HLS transport |

Other observed failure categories included TLS/certificate, HLS manifest,
segment, HTTP 401/403/404, and startup-without-decoded-video.
A same-host CDN and an HTTP 200 response do not establish playable source
identity. The localhost HLS relay does not fix invalid or region-blocked
upstream streams by itself.

The device's periodic diagnostics reported actual **1920 x 1080 video**
with progressing timestamps and healthy buffering on Racer Select between
15:09 and 15:14 UTC, while the matrix remained in the running state.

## Unattended CI source-only verification

Source-only macOS workflow:
`.github/workflows/ios-source-preflight-tests.yml`.

First run: https://github.com/mghazalyh/ptv3/actions/runs/44917839107

* Code SHA: `32d52c785b7e2bc9cc7f60f3ec7e1cb19e2bb1f1`.
* Flutter 3.41.9 setup, dependency resolution, and targeted static analysis:
  passed when inspected.
* 29 focused media/Stremio/Live TV/LAN regression files: passed when inspected.
* The full suite remained in progress at the time of this snapshot.
* The first run does not cover subsequent GitHub changes, including the
  next-release idle-only native command and new test attribution counters.

Later code introduces **idle-only** `probe_native_channel`: a single
source selected by exact installed addon hostname and source index is decoded
with a separate muted media_kit player. This action never executes on build
262; its first physical validation requires the next owner-authorized IPA.
It refuses to start while a player, the foreground matrix, or another page is
active and does not upload signed URLs or headers. Requests are one-shot
through the existing diagnostic inbox, not scheduled monitoring.

## Release acceptance and evidence boundaries

* Wait for the current matrix results without interrupting playback or
  silently restarting a failed channel.
* Use `requestedSourceVerified` rather than hostname or HTTP code to claim
  working original sources. A failover can make a channel playable while its
  first requested link remains bad.
* Rerun source-only preflight on the **latest** consolidated commit, not an
  earlier SHA. CI source tests cannot verify iPad native decoder behavior.
* After owner explicitly requests the next IPA and installs it, verify on
  actual iPad: exact episode cast handoff, muted idle-only native probe,
  Live TV See All scanner cancellation and source ordering, cache invalidation,
  video/audio stability, and the existing Torrentio/TorBox/Stremio VOD paths.
* Do not automatically trigger IPA builds or non-iOS platform builds.
* Do not create scheduled test tasks, an always-on monitor, or unrelated
  user-facing network activity without a fresh manual test request.

## Later read-only physical matrix snapshot (21 November 2026)

At approximately 23:50 Singapore time, the same installed build 262 and
uninterrupted run `matrix262_full50_20261121133315` reported:
* Phase: **running**; 26/150 channel rounds, 62 source attempts,
  18 legacy sustained playback sessions, 33 observed hostnames and
  six upload errors.
* The GitHub matrix directory contained 59 candidate files at that point.
  The difference from 62 attempts is **missing or in-flight evidence**,
  not three extra playback failures.
* FTF Sports: sources 0, 1 and 2 each showed distinct requested-source
  native 1280x720 video, active tracks, progressive timeline and 300-second
  playback, without a recorded source switch.
* Racer Select: sources 0 and 1 showed independently verified 1920x1080,
  300-second native video; requesting source 2 eventually played source 0,
  so its success is strictly a **failover** result.
* ACC Digital Network: source 0 reached stable 1080p only via source 1;
  independently requested sources 1 and 2 both achieved 1080p sustained
  native video for 300 seconds. Credit sources 1 and 2, not original 0.
* GREAT! Movies, Cheers, Swerve Combat, Made in Hollywood, the sampled
  NFL Network source and Charge lacked decoded moving video in their recorded
  candidate observations. No channel-wide or provider-wide blacklist follows
  from these samples.

There were no remote player commands, channel navigations, policy changes,
matrix restarts, new device probes or IPA actions in this continuation.

New GitHub-only code now includes Torriodb transient upload retry
improvements and separate candidate upload coverage counters. Neither
changes the already installed build 262 or retroactively repairs its
missing candidate uploads. Physical acceptance remains required after
an explicitly authorized future iOS-only IPA.



## Passive build 262 evidence for the next diagnostic IPA

Read-only Torriodb inspection of the running full native matrix
`matrix262_full50_20261121133315` observed 28/150 completed rounds,
68 source attempts, 21 legacy sustained playback sessions, 38 distinct
source hosts and six upload errors. These are **interim**, not final,
numbers. 65 candidate files were visible at the same instant. The
three-file difference from source attempts is a timing observation,
not proof of three playback failures.

* NFL Network candidate source 0 had native manifest, TLS and HTTP
  errors, while candidate 1 sustained after failover; original requested
  source 1 must not be counted verified.
* Fubo Sports Network source 0 had repeated native HTTP auth, HLS
  segment and manifest failures. Other candidates decoded 1080p but
  did not sustain, with active host/source changing during recovery.
* RightNow TV sources 0 and 1 both sustained native 720p playback on
  the requested source, with differing decoded track counts.
* Made in Hollywood source 0 buffered with no decoded frames,
  including an attempted HTTP relay; this is not a whole-channel
  blacklist decision.

These gaps motivated full raw native logs, per-request HTTP/DNS/redirect
diagnostics, frame captures, process metrics, exact source attribution
and resumable evidence uploads. New instrumentation is staged in
source only; physical build 262 and the running matrix were left intact.
