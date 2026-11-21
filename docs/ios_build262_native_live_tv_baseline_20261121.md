# iPad iOS Build 262: Real-device Live TV playback baseline (2026-11-21)

## Scope and constraints

This is a point-in-time report of **physical iPad observations** obtained through the existing opted-in private Torriodb command channel. The native iOS installation is build **262**, source commit `a74540388621ac820231ac77c1417cba15dc5115`.

Do not confuse the newer branch commit `263354782111c3e12de29ddadf1c3cc9c17f4a36` (source-index attribution fix) with the code installed on the iPad. That fix is not part of build 262. **No additional IPA has been requested or installed.**

## Verified remote controller and addon discovery

* Device heartbeat reported enabled, ready, build 262, and the expected source commit.
* `live_experiment_status` was accepted. No policy was active initially.
* `discover_live_matrix` identified **120** eligible `nltv:`/Stremio TV entries from the installed `ptv3-livetv-addon.pages.dev` addon, inspecting one eligible TV catalog.
* `probe_addon` for `nltv:us:NFLChannel.us` confirmed a valid manifest and stream resource (HTTP 200), three direct HTTP sources, two advertised as HLS, and no malformed entries.
* `probe_addon` for `nltv:us:CineRomantico.us` confirmed three direct HTTP sources, two HLS, and two sources supplying request headers.

These checks establish catalog/discovery compatibility for this installed addon, **not** a universal claim of 100% Stremio compliance or successful MPV decoding.

## Native playback control: Cine Romántico

1. Requested `nltv:us:CineRomantico.us`, original Stremio source index **2**, a CloudFront host.
2. Subsequent native player diagnostic reported recovery attempts **1** and active host **jmp2.uk**. This is source switching; the originally requested CloudFront source must not be credited with the resulting video.
3. Native MPV reported 1280 × 720 video dimensions, **11 tracks**, format `hls`, active playing, `buffering=false`, and `positionMs=8733`.
4. A Dart segment probe reported HTTP **206** and `probeOutcome=ok`, but that HTTP status was not used as evidence of decoding. Native video and a moving timeline are the positive indicators.
5. This was an observation, **not a completed five-minute sustained verification**.

## Reproduced NFL playback failure under defaults

1. Opened `nltv:us:NFLChannel.us`, source index **0**, originally an Akamai host.
2. After recovery, active source host was **jmp2.uk**; the original Akamai source must not be credited with subsequent behavior.
3. Three recovery attempts, one native manifest failure, a native error, relay already attempted, but not active at inspection.
4. `videoDimensionsReady=false`, no video dimensions, `trackCount=0`, `positionMs=0`, `buffering=true`.
5. Dart returned HTTP **206** while probing the active source's media segment. This proves transport reachability, not decoded playback.

## NFL-only runtime experiment and rollback

The iPad accepted the schema-1 policy `nfl_relay_browser_20261121133142` scoped only to `nltv:us:NFLChannel.us`:

* `relayMode=prefer`
* `headerMode=browser`
* `sourceOrder=ranked`
* `failoverEnabled=true`
* `relayAfterAttempts=0`
* `cacheSeconds=20`
* Default startup/stall/feed thresholds preserved.

After reopening NFL source 0 in a fresh player session, native inspection confirmed the experiment's ID and revision **1**. However, three recovery attempts still yielded zero playable video, `positionMs=0`, `buffering=true`. Native failure categories included HTTP authorization, manifest and segment failures. The Dart probe reached MPEG-TS data with HTTP 206, but MPV still did not decode video.

**Conclusion:** this specific configuration is not a verified NFL fix. Explicit `rollback_live_experiment` succeeded with `active=false`, revision **2** and last rollback `owner`.

Do not silently reapply this unsuccessful experiment.

## Started 50-channel, three-repeat real-device matrix

Command: `start_live_matrix_catalog`, accepted by iPad with:

```json
{
  "runId": "matrix262_full50_20261121133315",
  "addonHost": "ptv3-livetv-addon.pages.dev",
  "pages": 4,
  "limit": 50,
  "seed": 1207,
  "sampleSeconds": 10,
  "sustainSeconds": 300,
  "maxSources": 36,
  "repeats": 3
}
```

Initial receipt: `accepted=true`, `phase=running`, `uniqueChannels=50`, `totalChannels=150`. At the last inspected status, the first channel was Cine Romántico, one distinct source host had been observed, and no candidate source round had yet completed.

**Critical evidence-publishing issue:** the first status upload failed (reported `uploadFailures=1`); the run's private Torriodb status document was not initially present. A status document was created manually under the established private matrix directory to initialize the destination path. At the last inspection, publication of actual candidate files had **not** been confirmed. Do not call the run completed or successful until files and final phase support it.

The foreground-only runner may take hours. Device suspension, network problems, iOS termination, GitHub limits, or private upload failures can interrupt it. Any incomplete run must be reported as incomplete.

### Attribution limitation in installed build

Build 262 still uses hostname-based requested-source attribution for the matrix. A backup on the same CDN hostname could be mistaken for the requested stream. The follow-up source commit `26335478` improves this but is **not installed**. For current matrix results, use `sourceSwitchedBeforeSample` and original vs. final host where distinguishable. Never assume a requested source succeeded if same-host switching cannot be ruled out.

## First device-published five-minute matrix result

After initialization of the private matrix destination, the iPad **successfully updated** the private `status.json` and first candidate result `candidate_0_0.json` with authentic data. The candidate file no longer contains the explicit `pending` placeholder marker.

Observed candidate:

* Channel: `nltv:us:CineRomantico.us` (Cine Romántico).
* `requestedSourceIndex=0`; requested, active and final source host `jmp2.uk`.
* `sourceSwitchedBeforeSample=false`.
* `candidateVideo=true`, `sustainedPlayback=true`, `requestedSourceVerified=true`.
* Native format HLS; video dimensions **1280×720**; **11 tracks**; `buffering=false`.
* `sustainedSamples=5`, `sustainedObservedSeconds=300`.
* Timeline progressed from a sampled `positionEndMs=6333` to `finalPositionMs=317033`.
* `httpRelayActive=false`, with no recorded native failure categories.
* At this checkpoint, the matrix status reported `sourcesDone=1`, `verifiedSources=1`, `channelsDone=0`, `uploadFailures=1`, `phase=running`.

**Interpretation:** One source has now passed the requested full five-minute native decoding standard, and its private result upload succeeded. The original first-upload failure remains counted, and neither the initial failure's root cause nor general ability to create new candidate paths has yet been conclusively proven. Do not extrapolate one success to the remaining matrix.

## Required next validation

1. Read private Torriodb matrix `status.json` and per-candidate evidence, distinguishing manually seeded placeholders from native device uploads.
2. Check live `live_matrix_status` for upload failures, interruption, cancellation or completion.
3. Verify at least 50 unique channel IDs, three rounds per channel, attempt counts, and five-minute sustained decode evidence where sources initially play.
4. Examine failures per host, HTTP status, HLS/playlist transport, track count, video dimensions and timeline; do not equate HTTP reachability with playback.
5. Reconcile source failover attribution, especially when different stream URLs share a hostname.
6. Only use scoped, expiring, rollback-capable runtime policies for already-installed behavior. Do not promise that new Dart code will reach this IPA without an installation.
7. Preserve movie/series/Torrentio/TorBox behavior and the existing GitHub-only iOS release workflow. **Do not trigger another iOS build**.

## Follow-up, 21:51 SGT: three control-source results are published

Evidence root: `mghazalyh/torriodb/playtorrio/control/ios/matrix/8e223bb3c7c337facbbccd69aaeb762f/matrix262_full50_20261121133315/`.

All three Cine Romántico candidates sustained five minutes (300 seconds) of native 1280 x 720 video, with 11 native tracks, nonbuffering active playback and ongoing timeline progression. This validates that the installed iPad MPV decoder and installed addon can play video through the `jmp2.uk` delivery path.

| Candidate | Requested host | Active/final host | Final position | Sustained video | Requested-source verified by build 262 |
| --- | --- | --- | ---: | --- | --- |
| 0_0 | jmp2.uk | jmp2.uk | 317033 ms | true | true |
| 0_1 | jmp2.uk | jmp2.uk | 337633 ms | true | true |
| 0_2 | d1si3n1st4nkgb.cloudfront.net | jmp2.uk | 318266 ms | true | **false** |

The second candidate recorded one native TLS error but still decoded video for five minutes. This shows native error events are not sufficient evidence of playback failure. The third candidate proves successful backup playback; it does **not** prove the original CloudFront source played. Because build 262 lacks source-index attribution, the two same-host results may still contain undetected same-host switching. Consult the source-index fix in uninstalled `26335478`.

At the last observed iPad status after these candidates, `sourcesDone=3`, `verifiedSources=3`, `distinctSourceHosts=2`, `uploadFailures=2`, `phase=running`. The status document lagged behind a completed candidate when a GitHub write failed, then caught up. The candidate JSON files, not stale aggregate counters, are the primary ground truth.

### Torriodb GitHub write contention and source-only repair

Device status and command receipts and per-candidate matrix files are all committed to the same Torriodb main branch. Two matrix status uploads failed around concurrent activity; an exact HTTP failure status was not recorded, so branch races are a plausible diagnosis rather than a proven exclusive cause.

Source commit `a10a6120b7a0239546fec58c5d43495bd3e315a1` introduces:
* A per-controller queue to serialize its GitHub Contents API writes;
* Bounded retry for 409 conflicts and transient upstream service errors;
* New file SHA read before each retry;
* Coverage for write conflicts, concurrent uploads and queue recovery;
* Inclusion of the controller tests in the lightweight GitHub quality gate.

This correction is **not installed on iOS build 262**. It does not justify a new IPA against the owner's instruction. Operational mitigation on build 262 is to minimize concurrent Torriodb command writes while matrix evidence uploads continue.

### Planned supported runtime A/B/A experiment

An existing saved PlayTorrio matrix monitor was updated to preserve the baseline first 50 channel rounds, then (only with appropriate fresh device evidence and no conflicting owner policy) apply a bounded relay-prefer/default-addon-header trial for second-repeat rounds, finally roll back to defaults for the third repeat. All transitions must check actual command receipts, preserve native-source attribution, and record intervention timing; hourly scheduling cannot guarantee an exact round boundary. If the sample fails, the experiment must be canceled. The previous failed NFL browser-header+preferred-relay trial should not be repeated.

**No new iOS build or IPA installation was triggered.**

## Follow-up: Amagi 1080p and cross-service write contention

Read-only inspection of the existing iOS telemetry reports at `playtorrio/diagnostics/ios/night-mode/2026/11/21/` provided detailed event-level information **without interrupting the running matrix**.

**Unbeaten:** The matrix opened `nltv:us:Unbeaten.us` source index 0 on `d1t5afz6qed3xk.cloudfront.net`. It changed to a fallback `unbeaten-tcl.amagi.tv` and successfully decoded 1920 × 1080 video with 11 native tracks. Candidate `candidate_1_0.json` confirmed five-minute sustained playback, final position 315954 ms, and `requestedSourceVerified=false`. Do **not** attribute this 1080p success to CloudFront. Historical telemetry confirmed live playlist updates and buffer-free timeline movement beyond 300 seconds on the actual Amagi host.

**NFL failure details from native event traces:** reports around 13:31 and 13:32 UTC show `nltv:us:NFLChannel.us` changing to `jmp2.uk`, valid playlist/variant responses (HTTP 200, media sequences advancing, five segments observed), while native decoded track count remained zero and position stayed at zero. Codes included native HTTP authorization, manifest and segment failures. Successful manifest retrieval and a moving playlist sequence do **not** mean the native HLS decode pipeline succeeded.

**Uploader collision confirmed by architecture inspection:** During the matrix, `IosAudioTelemetry.upload` independently wrote private source/debug reports every ~30–35 seconds on the same Torriodb `main` branch as `GithubDiagnosticControl.publishMatrixFile`, heartbeat and command receipts. Both used GitHub's Contents API, allowing concurrent commits to race. Exact HTTP errors for the two recorded matrix failures were not logged, so this is a strong architectural explanation, not proof each failure was an HTTP 409.

- Commit `a10a6120`: serialized `GithubDiagnosticControl` writes and retried 409/transient failures. Linux/Windows quality gate succeeded.
- Commit `11e7afee`: added a shared Torriodb upload queue across the diagnostic controller **and** native iOS telemetry uploader, plus bounded retries and tests. Lightweight CI validation was started.
- Both fixes are **uninstalled source changes**; build 262 remains in service. Do not claim that changing repository code repairs the active IPA.

For build 262, continue the matrix, avoid unnecessary command writes, read per-candidate JSON for actual playback verdicts, and reconcile the independent event traces when a matrix status write fails. No iOS release or new manual installation was requested.

## Follow-up: Unbeaten HLS relay escalation bug (14:01 UTC)

The real iPad's event-level telemetry for `nltv:us:Unbeaten.us` demonstrated a reproducible recovery-selection problem. Native event sequence from private telemetry `2026-11-21T13-57-53-479928Z-47.json`:

1. Initial request on `lukentvlive.vgcdn.net` failed with a native manifest issue and zero decoded video.
2. The controller switched to CloudFront; the HLS playlist probe returned `ok`, but native tracks stayed at zero and playback stalled.
3. At channel recovery attempt 2, the supervisor switched to `unbeaten-tcl.amagi.tv` and immediately selected the **local HLS relay**, despite this being the first attempt on that source. This relayed attempt stalled, again with zero native tracks.
4. At attempt 3, it switched back to the failing CloudFront source with relay and continued failing.
5. When the matrix directly opened `unbeaten-tcl.amagi.tv` on its own source attempt, MPV decoded 1920 × 1080, 11 native tracks within approximately 12 seconds, and the iPad reported growing playback timeline past two minutes without buffering.

The source-level bug: `LivePlaybackCoordinator.shouldUseHlsRelay` previously used total **channel** `recoveryAttempts >= 2` to enable the relay. That count accrued on different failed URLs. As a result, even a newly selected backup with no native direct failure was prematurely relayed. The successful direct Amagi session provides strong evidence that this unconditional escalation can make recovery worse.

**Source-only repair:** commit `c4ed4184808032da22e70dae946757fab19bd4f0` introduced a per-source direct-failure set, checked by the relay escalation predicate. Native TLS failures for the same URL remain eligible to trigger the relay immediately. The controller records a failed direct HLS source only during involuntary recoveries without confirmed video and removes the record after confirmed native video. New regression cases ensure high recovery counts cannot relay an unseen backup without URL-specific evidence.

This fix does **not** modify the installed build 262 and **no iOS release was triggered**. Its correctness must be established by GitHub lightweight CI, then (for this installed version) only supported runtime policies remain available. Do not claim this code-only change repaired the iPad.
