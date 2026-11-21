# PlayTorrio remote broadcast-content inspection

This capability enables an external ChatGPT operator to answer questions such
as "Which of my Live TV channels are showing basketball right now?" **without**
using channel names, descriptions or EPG entries as content evidence.

## Implementation and isolation

* `live_visual_scan` is an opt-in, bounded, owner-requested Torriodb command.
* It uses a **separate silent MPV Player** in
  `ios_remote_live_frame_probe.dart`. The production native channel verifier,
  Live TV playback coordinator and the existing 50×3-channel matrix are unchanged.
* It operates only while the iOS app is foreground and the device is idle.
  Existing video playback, dialogs and the native matrix take precedence.
* It resolves stream candidates through enabled installed Stremio addons.
  Remote requests never contain arbitrary stream URLs.
* It verifies actual video dimensions, tracks, decoded frames, and advancing
  unbuffered playback, then captures up to two time-separated native screenshots.
* Downscaled images are **bounded PNGs of at most 64 KB each**. The app publishes
  them to the owner's **private Torriodb**, not a third-party vision endpoint.
* No screenshots, stream URLs or HTTP headers are placed in command receipts.
  The result lists evidence filenames and observation timestamps.
* The app does **not** perform basketball recognition itself. ChatGPT reads the
  PNG evidence using the connected GitHub interface and visually classifies it.
* A single frame is only evidence of what was visible at that moment. Multiple
  frames, a visible scoreboard, gameplay, and live timestamps are stronger
  evidence of a live match. Never infer live status from a channel name.
* App lifecycle interruption or an occupied device cancels the scan.

## Commands

Discover actual addon channels through `live_channels` (or reuse recently
identified channel IDs). Choose at most 15 per `live_visual_scan` request:

```json
{
  "action": "live_visual_scan",
  "args": {
    "runId": "basketball_scan_001",
    "contentHint": "basketball",
    "channels": [
      {"id": "nltv:us:OpaqueChannel.us", "title": "Unknown Channel"}
    ],
    "framesPerChannel": 2,
    "maxSources": 2
  }
}
```

`live_visual_scan` acknowledges that the **asynchronous scan started**, not that
it found a basketball broadcast. Query `live_visual_scan_status` to inspect
progress and evidence availability. `live_visual_scan_cancel` requests a safe
stop. These operations are versioned under `command_contracts`.

## Evidence

The private files use:

```
playtorrio/control/ios/visual/<deviceId>/<runId>/status.json
playtorrio/control/ios/visual/<deviceId>/<runId>/channel_0.json
playtorrio/control/ios/visual/<deviceId>/<runId>/frame_0_0.json
playtorrio/control/ios/visual/<deviceId>/<runId>/frame_0_1.json
```

Each frame record includes an `imageBase64` field encoding PNG bytes plus
`channelId`, `capturedAtUtc`, `playbackPositionMs`, image hash and native
verification flag. ChatGPT can retrieve and decode the image and compare it with
the other frame. An external operator can then report:

* **Basketball visible:** court/hoop/players seen, with evidence timestamp.
* **Likely live basketball:** sustained gameplay and live-style scoreboard from
  multiple samples, while acknowledging that a replay can look identical.
* **Highlights or replay:** sporting footage without evidence of live coverage.
* **No basketball observed:** sampled content was different; later content may
  change.
* **Unverified:** channel could not sustain actual native video or frames could
  not be exported.

The `contentHint` is stored only as an operator instruction. It does not filter
or classify channels on the device. For larger collections, run multiple bounded
scans sequentially. The host should avoid issuing an overlapping command while
one is running, and avoid consuming evidence from stale prior runs.

## Constraints

This is **source functionality**, not something installed on the currently
running iPad until a newer iOS IPA is built and installed. The system cannot
automatically identify spoken commentary or OCR scoreboards without further
capabilities. ChatGPT visual inspection provides a content classification only
once the image artifacts are available in this conversation.
