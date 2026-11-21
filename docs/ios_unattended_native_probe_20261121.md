# One-shot unattended native channel verification (next iOS release)

This diagnostic action is added to future code; **it is not available on
installed iPad build 262**. It allows the opt-in existing Torriodb command
inbox to request a single native decode trial without opening PlayerScreen,
altering settings or replacing current media.

Action: `probe_native_channel`, with arguments:

```json
{
  "channelId": "nltv:us:CineRomantico.us",
  "addonHost": "ptv3-livetv-addon.pages.dev",
  "sourceIndex": 0
}
```

The device validates a channel ID, an exact **installed and enabled** Stremio
addon host and a source index between 0 and 7. Signed URLs, HTTP headers,
login tokens and arbitrary endpoints are not accepted. Eligible direct-HTTP
sources are resolved by the device from that one addon.

A strict idle guard refuses the request if the matrix is running, the app is
backgrounded, a playback controller is active or a non-root route is visible.
Once allowed, a separate muted media_kit player attempts native decoding and
is disposed afterward. The guard is rechecked while the trial runs. If the
user starts viewing media, the probe cancels.

A receipt includes a sanitized source hostname, native-video confirmation,
width/height, number of tracks, playback position advance, buffering and
startup duration. No media URL, raw response, headers or credentials are
uploaded. HTTP reachability alone cannot pass.

The existing `probe_addon` command remains the lightweight check for active
matrix sessions. Do not issue `probe_native_channel` until the user has
explicitly requested a scoped test and the iPad is idle. Do not schedule
recurring probes. Future real iPad decoder validation remains necessary.
