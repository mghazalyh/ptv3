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

The iOS `MaterialApp.builder` renders a compact, pointer-transparent badge
above the navigator. It follows the **actual local matrix runner** and thus
survives playback route transitions. It never changes playback or captures
touches. It appears only for a running native matrix or one idle-only native
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
