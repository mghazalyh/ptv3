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

## Required next validation

1. Read private Torriodb matrix `status.json` and per-candidate evidence, distinguishing manually seeded placeholders from native device uploads.
2. Check live `live_matrix_status` for upload failures, interruption, cancellation or completion.
3. Verify at least 50 unique channel IDs, three rounds per channel, attempt counts, and five-minute sustained decode evidence where sources initially play.
4. Examine failures per host, HTTP status, HLS/playlist transport, track count, video dimensions and timeline; do not equate HTTP reachability with playback.
5. Reconcile source failover attribution, especially when different stream URLs share a hostname.
6. Only use scoped, expiring, rollback-capable runtime policies for already-installed behavior. Do not promise that new Dart code will reach this IPA without an installation.
7. Preserve movie/series/Torrentio/TorBox behavior and the existing GitHub-only iOS release workflow. **Do not trigger another iOS build**.
