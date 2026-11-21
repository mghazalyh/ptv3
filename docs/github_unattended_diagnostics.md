# Unattended PlayTorrio iPad diagnostics over private Torriodb

This is an owner-controlled **remote in-app diagnostic channel**, not a remote operating-system shell. It uses the GitHub Library credential already configured for private Torriodb telemetry. It never asks for a per-command approval.

## One-time iPad setup

1. Install the iOS release containing this feature.
2. Connect GitHub Library with read/write access to `mghazalyh/torriodb`.
3. In **Settings > Unattended GitHub Diagnostics**, enable the switch once. The full private 32-character device ID appears in the switch subtitle.
4. Leave PlayTorrio open on the iPad. iOS suspends ordinary background Flutter app work, so commands cannot be guaranteed to execute while PlayTorrio is backgrounded or the device is asleep.

When enabled, the iPad polls every 12 seconds using the existing GitHub token and publishes its readiness under:

```text
playtorrio/control/ios/devices/<deviceId>.json
```

Write the desired command as UTF-8 JSON to:

```text
playtorrio/control/ios/commands/<deviceId>.json
```

GitHub's Contents API accepts a base64-encoded document and the existing file's SHA for replacements. Every new request must have a new `id`, a matching `deviceId`, and `createdAtUtc` within one hour of delivery. The application persists the last processed ID across launches to avoid replay. Commands are processed serially; do not overwrite a pending command before it receives a receipt.

Each command result is written privately to:

```text
playtorrio/control/ios/receipts/<deviceId>.json
```

The command file is deliberately separate from telemetry JSON paths. No commands or credentials are written into general diagnostic logs.

## Command envelope

```json
{
  "id": "diagnose_20261121_0001",
  "deviceId": "<32-character iPad ID>",
  "createdAtUtc": "2026-11-21T02:00:00Z",
  "action": "open_channel",
  "args": {
    "channelId": "nltv:us:NFLChannel.us",
    "title": "NFL Channel",
    "sourceIndex": 0
  }
}
```

The timestamp above is illustrative only; each command must use its actual current UTC creation time.

## Supported unattended actions

* `state`: report whether the player/Flutter navigator is available.
* `open_channel`: discover a Stremio `nltv:` or `iptv:` channel and open its selected live source; accepts `channelId`, `title`, and `sourceIndex`.
* `remote`: use the existing player/navigation handlers with `args.command` equal to `home`, `back`, `up`, `down`, `left`, `right`, `select`, `playPause`, `seekBack`, or `seekForward`.
* `player`: `args.command` may be `state`, `play`, `pause`, `toggle_play`, `seek_ms`, `set_volume`, `retry_live`, `probe_live`, `restart_media`, `show_diagnostics`, `native_get`, `native_set`, `native_command`, or `audio_tracks`.
* `capture_telemetry`: upload current opt-in iOS playback diagnostics into the existing private Torriodb diagnostics tree.
* `batch`: execute up to twenty sequential in-app commands, each using `{"action":"...", "args":{}}`. Nested batches are ignored.

Examples:

```json
{"action":"player","args":{"command":"probe_live"}}
```

```json
{"action":"player","args":{"command":"retry_live","sourceIndex":1}}
```

```json
{"action":"player","args":{"command":"native_get","property":"track-list/count"}}
```

```json
{"action":"player","args":{"command":"native_set","property":"demuxer-readahead-secs","value":"20"}}
```

```json
{"action":"player","args":{"command":"native_command","arguments":["show-text","Live TV diagnostic"]}}
```

```json
{"action":"batch","args":{"commands":[{"action":"player","args":{"command":"probe_live"}},{"action":"capture_telemetry","args":{}}]}}
```

Native commands and properties are sent to the active media_kit player. Unsupported native commands return a failure receipt, not arbitrary code execution. Playback URL/header values are excluded from receipts.

## Reading the results

`player probe_live` performs an on-demand HLS master playlist, media playlist, and limited segment range check. The receipt reports HTTP status, probe phase and outcome, native track count, media format class, video readiness, buffer/position metrics, recovery attempts, and categorized native errors. Playback is only marked verified by the existing video/timeline watchdog, not merely by receiving HTTP 200 or `Media.open`.

## Disabling

Turn off the Settings switch whenever remote operation is no longer wanted. The client then stops executing GitHub command files; no per-command authorization dialogs appear when it is enabled.

## Boundaries

Control operates only inside the foreground PlayTorrio client. iOS does not permit unrestricted device-level process execution or reliable background polling by this Flutter app. Private Torriodb write access and the stable device ID serve as the command channel. GitHub credentials remain on the client and are never returned through receipts.
