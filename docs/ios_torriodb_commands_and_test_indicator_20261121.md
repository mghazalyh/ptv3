# Torriodb iOS diagnostics commands and visible test indicator

## Installed build boundary

The currently installed iPad build 262 (commit
`a74540388621ac820231ac77c1417cba15dc5115`) has the existing
Torriodb diagnostic inbox, Live TV matrix, addon probe and player diagnostic
overlay. It **does not** have a persistent on-screen test-progress banner.
Sending an unsupported command cannot inject new Flutter UI into the
already-installed IPA.

The new status indicator and four new read-only commands below are staged in
the development branch for the *next owner-authorized iOS IPA*. They are
not active on build 262. No workflow here requests an IPA build.

## Visual test indicator

The iOS `MaterialApp.builder` renders a compact badge with a close button
above the navigator. It follows the **actual local matrix runner** and thus
survives playback route transitions. It never changes playback; only its
close button captures taps. The rest of the player remains interactive. It appears only for a running native matrix or one idle-only native
source test.

For a matrix it shows:
- LIVE TV TEST RUNNING, completed / total channel rounds, visual progress,
  completed source attempts, sustained playback sessions, and upload errors.
- STOPPING LIVE TV TEST while an in-process cancellation is requested.
- It disappears on completion, cancellation, failure or process restart.
- Completion is *not* inferred from a heartbeat, GitHub CI status or remote
  request receipt.

For a one-source idle native probe it shows NATIVE SOURCE TEST RUNNING without
a bogus matrix progress percentage. The indicator clears in a finally block.

GitHub source-only CI runs are not reported as on-device activity. This
prevents claiming that an iPad is running tests when CI is on a Mac runner.

## Read-only Torriodb commands added to next IPA

Use the existing envelope with exact deviceId, unique command id and a fresh
createdAtUtc timestamp. The inbox is:
`playtorrio/control/ios/commands/<deviceId>.json`.

```json
{
  "id": "querystatus_20261121_001",
  "deviceId": "<registered-device-id>",
  "createdAtUtc": "<current-UTC-timestamp>",
  "action": "test_status",
  "args": {}
}
```

| Action | Output | Side effects |
| --- | --- | --- |
| `test_status` | Local indicator phase plus matrix counters and exact-source attribution | None |
| `diagnostic_snapshot` | IPA build SHA/run, foreground, paired control status, navigator and player presence, limited matrix summary | None |
| `addon_inventory` | Up to 32 installed addons with names, declared Stremio types/resources, enablement flags, catalog counts, and host only | None |
| `diagnostic_capabilities` | Diagnostic command schema, supported actions classified by impact and 12-second polling configuration | None |

Existing read-only actions include `state`, `live_matrix_status`,
`live_experiment_status`, `discover_live_matrix`, `probe_addon`, and
`player` with the specific `state` / `probe_live` subcommands. The
`player` action itself can mutate playback and must not be represented as
read-only as a whole.

Existing playback-changing operations `open_channel`, `remote`,
`player`, `start_live_matrix`, and `cancel_live_matrix` must be
requested only intentionally, especially while a lengthy native matrix runs.
The new `probe_native_channel` is strictly idle-only, muted and one source
at a time; it refuses to start alongside a matrix or active playback.

## Other high-value commands for future consideration

These are *not yet implemented* and should never be sent to build 262:

* `validate_test_plan`: dry-run bounded source/channel selection and check
  eligible installed Stremio resources without opening video.
* `pause_after_candidate` and `resume_test`: safe user-controlled pause
  and resume that preserve counters and release the foreground player.
* `diagnostic_report_summary`: aggregate redacted error categories and
  requested-source versus fallback success across one full matrix run.
* `verify_torriodb_uploads`: report local failed queue commits and file
  delivery receipts, without retrying or mutating the private repository.
* `test_media_handoff`: simulate exact movie/series/episode selection with
  installed addon metadata, without opening playback or using sender URLs.

## Security and release guidance

No command should accept arbitrary Dart/JS, shell, MPV commands, signed
stream URLs, credentials, raw headers or arbitrary new remote endpoints.
The command protocol remains opt-in, device-scoped, bounded and
receipt-based. Source-only test runners must validate the exact next-release
commit before IPA packaging. Physical iPad verification is still required
after the owner installs that release.

## Owner-requested control redesign, staged only

The global iPad test indicator now has a close button. Dismissing it hides
the display without cancelling or pausing the test. A later progress callback
cannot unexpectedly reopen the dismissed indicator for the same run.
A fresh native matrix/probe run shows the indicator again by default.
The new `test_indicator` action accepts exactly `{"visible":true}` or
`{"visible":false}` and can toggle it while the matrix is running;
`test_status` shows the actual `indicatorEnabled` state.

The `diagnostic_plan` action accepts a JSON sequence of preinstalled
commands. This is a reusable capability installed *once*: future test recipes,
assertions, repetitions and order changes arrive through Torriodb, not an
IPA installation each time. It supports a dry run, up to 20 individual
steps, 30 executions, up to three repetitions per step, nested response-field
assertions, and a choice to stop after failure or collect later results.
New unsupported actions are rejected before execution. A busy native
matrix permits observational commands and UI toggling but rejects playback
controls. Playback-changing plans require
`"allowPlaybackChanges":true` and the matrix must remain idle.
`player` is read-only within a plan only for `state` and `probe_live`.
No nested plan or batch action is accepted.

Example observational plan:

```json
{
  "action": "diagnostic_plan",
  "args": {
    "dryRun": false,
    "stopOnFailure": false,
    "steps": [
      {"action": "live_matrix_status", "expect": {"phase": "running"}},
      {"action": "diagnostic_snapshot"},
      {"action": "test_indicator", "args": {"visible": false}}
    ]
  }
}
```

Actual Torriodb envelopes still require the existing `id`, `deviceId`
and fresh `createdAtUtc`. Plans can be changed remotely at any time without
changing app code, as long as the individual commands already exist.
Completely new native methods still require a later installation.
The additional addon-inventory privacy filter from commit `cf2e945d`
was reverted in `7ba96bad`.



## Next iOS test agent: full-fidelity diagnostics staged on source branch

The next authorized iOS IPA introduces these reusable Torriodb actions.
They are **not installed in physical build 262**; its running matrix is
not interrupted.

| Action | Function |
| --- | --- |
| `diagnostic_plan` | Start a nonblocking plan with 80 steps, 300 executions, waitMs, repeat, previous-result conditions, assertions and failure policy |
| `diagnostic_plan_status` | Active/completed plan phase, execution counts, last result, cancellation state |
| `diagnostic_plan_cancel` | Cancel future plan steps or a pending wait without cancelling the separate Live TV matrix |
| `diagnostic_media_sources` | Inspect installed Stremio movie, exact series episode or TV sources without opening playback |
| `diagnostic_open_media` | Open a selected real addon source through normal PlayerScreen with correct movie/episode identity |
| `diagnostic_open_reference` | Open provided HTTP/HTTPS or infoHash reference stream with explicit headers |
| `diagnostic_http_probe` | On-device DNS, request and response timings, redirects, HTTP status, headers and bounded response excerpt |
| `device_inventory` | Device identity, iOS hardware, displays and environment |
| `diagnostic_process_metrics` | Native getrusage CPU, memory high-water, faults, context switches, battery and thermal metrics |
| `diagnostic_journal_status` | Rolling journal size and write/fragment counters |
| `diagnostic_journal_tail` | Latest bounded local journal records |
| `diagnostic_export` | Resumable byte-range upload of current, previous or screenshot capture evidence |

The `player` subcommand gains `native_snapshot` (up to 64 libmpv
properties), `sources` (paged raw source inventory) and
`capture_frame` (native player PNG screenshot). Existing
`native_get`, `native_set` and `native_command` stay available.

The journal stores **raw** libmpv messages and matrix candidate
observations locally in two rolling 12-MiB JSONL segments.
Large diagnostic events are losslessly fragmented with numbered base64
parts; a native screenshot can be stored up to 8 MiB.
Exports are written to Torriodb at
`playtorrio/control/ios/artifacts/<device-id>/<run-id>/`, with
`nextOffset` to resume after upload failure.

### Example: nonblocking observational plan

```json
{
  "action": "diagnostic_plan",
  "args": {
    "runId": "ipad_evidence_20261122_a",
    "stopOnFailure": false,
    "steps": [
      {"action": "diagnostic_process_metrics"},
      {"action": "diagnostic_journal_status"},
      {"action": "diagnostic_http_probe",
       "args": {"url": "https://example.org/", "method": "HEAD"}},
      {"action": "diagnostic_process_metrics", "waitMs": 5000}
    ]
  }
}
```

The start receipt is immediate; a later `diagnostic_plan_status` reads
progress and `diagnostic_plan_cancel` stops subsequent steps.
Plans cannot change playback while a native Live TV matrix runs.

### Example: journal and screenshot export

```json
{
  "action": "diagnostic_export",
  "args": {
    "runId": "ipad_evidence_20261122_a",
    "segment": "current",
    "offset": 0,
    "maxChunks": 8
  }
}
```

For screenshot evidence, execute `player` with
`{"command":"capture_frame"}` then export segment `capture`.
Repeat with the returned `nextOffset` until `complete` is true.
The outer Torriodb envelope still requires exact deviceId, a fresh
command ID, and fresh createdAtUtc per existing protocol.

These are data-driven uses of precompiled native and Dart functionality,
not arbitrary shell execution or dynamic iPadOS native module loading.
Additional native frameworks, codecs, changed Swift code, entitlements
and new Flutter UI still require an authorized IPA installation.
No iOS build, signing or installation is triggered by these changes.
