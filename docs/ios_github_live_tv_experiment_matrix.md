# PlayTorrio GitHub-only Live TV experiments and unattended matrix

## Purpose

This is an iOS-only owner-operated development workflow. It reuses the
**existing private Torriodb command inbox**; it does not use Shorebird,
SentinelX, OpenCode, an external server, or a permanent Mac mini.

**This is not arbitrary Dart hot reload.** It is a validated runtime policy
engine that changes only prebuilt Live TV behavior. Native frameworks,
entitlements, Swift and unimplemented algorithms still require an IPA.
The currently installed Build 260 cannot execute these *new* commands until
a version containing them is installed. GitHub tests cannot prove iPad decoding.

## Safety and compatibility

- All commands use the existing opt-in, device-scoped, expiring Torriodb
  control channel. The app must be foregrounded; iOS suspension stops polling.
- Policy schema 1 accepts only explicit, bounded fields, never source URLs,
  arbitrary HTTP headers, scripts, shell commands, Dart/JS snippets or plugins.
- Policies expire after no more than 24 hours and persist locally so app
  restarts do not unexpectedly lose an active short-lived experiment.
- A rollback command restores defaults. Automatic rollback occurs after
  3 trial-era recovery failures **only when video had previously been
  verified within that Live TV session**. Known-dead channels do not falsely
  trigger rollback.
- Movie, series, torrents, VOD subtitles and global stream ranking are never
  affected by Live TV-specific policy switches.
- The Live TV relay remains opt-in or failure-triggered; upstream 403/404
  cannot be repaired by a local relay.
- Native tracks, video dimensions, a moving timeline, nonbuffering state and
  sustained playback are required for success. HTTP 200/206 is not success.
- Matrix result files contain only channel IDs/titles, source hostnames,
  playback states and error categories. No signed stream URLs or cookies.

## Remote configuration commands

All command objects are written to:

`playtorrio/control/ios/commands/<deviceId>.json`

using the existing envelope with unique `id`, current `createdAtUtc`,
`deviceId`, `action` and `args`. Read its matching receipt before
overwriting the inbox. Use `main` in private `mghazalyh/torriodb`.

### Inspect

```json
{"action":"live_experiment_status","args":{}}
```

### Apply a 2-hour scoped experiment

```json
{
  "action": "apply_live_experiment",
  "args": {
    "schema": 1,
    "id": "nfl_relay_trial_001",
    "channelId": "nltv:us:NFLChannel.us",
    "expiresAtUtc": "REPLACE_WITH_FRESH_UTC_TIME_WITHIN_24_HOURS",
    "relayMode": "prefer",
    "headerMode": "browser",
    "sourceOrder": "ranked",
    "failoverEnabled": true,
    "relayAfterAttempts": 0,
    "startupGraceSeconds": 14,
    "stallSeconds": 13,
    "feedSeconds": 9,
    "cacheSeconds": 20
  }
}
```

Do not literally submit the expiry placeholder. Generate an ISO-8601 UTC
expiry in the future. Omit `channelId` to apply to all Stremio TV channels.
Known options:

| Field | Accepted options |
| --- | --- |
| relayMode | `auto`, `never`, `prefer` |
| headerMode | `addon`, `browser`, `minimal` |
| sourceOrder | `ranked`, `original`, `reversed` |
| failoverEnabled | Boolean |
| relayAfterAttempts | 0–6 |
| startupGraceSeconds | 5–90 |
| stallSeconds | 5–90 |
| feedSeconds | 3–60 |
| cacheSeconds | 0–90 (0 = adaptive default) |

The selected policy is evaluated on each coordinator tick and before
recovery, so changing settings does not require reinstalling. A currently
playing stream may need the existing remote `player/retry_live` command
to reopen with new headers or relay strategy.

To revoke immediately:

```json
{"action":"rollback_live_experiment","args":{}}
```

### Discover installed Live TV catalog channels

```json
{"action":"discover_live_matrix","args":{
  "addonHost":"ptv3-livetv-addon.pages.dev","pages":4,"limit":120
}}
```

This uses only the installed addon catalog endpoints and returns eligible
`nltv:`/`iptv:` entries. It skips catalogs that require extra arguments,
invalid IDs and channels not supported by the same installed stream addon.

### Start automatic broad matrix

```json
{"action":"start_live_matrix_catalog","args":{
  "runId":"livetv_matrix_001",
  "addonHost":"ptv3-livetv-addon.pages.dev",
  "pages":4,
  "limit":120,
  "seed":1207,
  "sampleSeconds":15,
  "sustainSeconds":300,
  "maxSources":36,
  "repeats":3
}}
```

At least 50 distinct **real installed-addon** channel IDs are required. By default each channel is opened for **three separate attempts**; within each attempt, every advertised source is checked (up to the cap). The 50 unique channel IDs therefore produce at least 150 channel rounds. Source provider diversity is reported as observed distinct source hostnames. Hostname diversity is not absolute provider diversity.
The runner randomizes the audit order deterministically, with Cine Romántico
as a working-source regression control when found. It opens every selected
source up to the configured max, samples decoded media state three times,
and monitors preliminarily working streams for five further minutes.
Actual recovery can change provider between samples, so each sample
includes the active source host.

A successful START receipt only acknowledges orchestration.
Retrieve `live_matrix_status` and individual result files; never claim the
channels played merely because the job was accepted.

```json
{"action":"live_matrix_status","args":{}}
```

```json
{"action":"cancel_live_matrix","args":{}}
```

Private results are written to:

`playtorrio/control/ios/matrix/<deviceId>/<runId>/status.json`

`playtorrio/control/ios/matrix/<deviceId>/<runId>/candidate_<channelIndex>_<sourceIndex>.json`

The foreground runner is not designed to bypass iOS background restrictions.
Unexpected app termination can interrupt a run. Resume by issuing a new
run ID, preserving earlier results in GitHub; do not assume a completed
full 50-channel matrix from a partial progress marker.

## Validation and release policy

1. Run Flutter analysis and the new policy/matrix regression tests on GitHub.
2. Test redirected HLS, upstream errors, TLS/relay selection, source ranking,
   header policies, recovery, movie/series isolation and compatibility.
3. Validate the existing installed build remotely as far as its commands allow.
4. Do **not** request repeated manual experimental IPA installations.
5. When a final release is warranted, update only the existing iOS release
   trigger `.github/ios-speech-release-request.txt`.
6. **Stop immediately once that release trigger push succeeds.** Do not
   poll the newly triggered iOS workflow.
7. After the owner installs that eventual version, verify the installed
   commit via the Torriodb heartbeat and perform genuine on-device testing.
8. If a defect requires new native or Dart implementation code after that
   final installation, the runtime switches alone cannot guarantee an
   install-free repair. No engineering process can truthfully guarantee
   a final IPA is bug-free without on-device verification first.
