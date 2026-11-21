# PlayTorrio live television resilience

This subsystem is isolated under lib/services/player/live_tv/. It is activated
only for Stremio type "tv", explicitly live metadata, or a known IPTV channel ID,
and never for a movie, a series or a selected episode.

## Runtime
- LiveStreamDetector owns Stremio channel classification and HLS playlist parsing.
- LiveRecoveryPolicy is a pure clock-driven stall and buffer-starvation policy.
- LiveSourceManager keeps per-channel backups, short-lived circuit breakers,
  original provider headers and optional HEAD/playlist validation.
- LivePlaybackCoordinator keeps one media_kit Player and the same channel screen
  while reopening the current live URL or using a refreshed addon stream.
- LivePlaybackTelemetry emits fixed, non-identifying codes through the existing
  opt-in Windows/iOS private Torriodb diagnostics.

## Detection and reconnection
- Sample every two seconds while foreground playback is active.
- Give initial startup 14 seconds; if buffering and motion is absent for 13
  seconds, reopen. If the cache is under six seconds and incoming media has not
  advanced for nine seconds, reopen before the last frame is consumed.
- Reopen at the current live edge, never with an old position or seek.
- Try the same URL once. On subsequent interruptions fetch fresh sources from
  the installed Stremio addon using the identical channel ID and provider.
- Prefer stable tested HLS alternatives. Never cross to a different addon,
  channel or torrent. Keep request headers attached to each source.
- Circuit-break links after repeated failures. Retry on bounded exponential
  intervals (4, 8, 16, 32, 60 seconds); the viewer remains on the channel.
- After a reconnect, wait for genuine position advancement before declaring
  success. A minute of healthy playback resets the retry budget.
- Use 15 seconds normal cache, 20 seconds after interruptions, up to 30 seconds
  after repeated failures. These are bounded to avoid excessive live latency.
- Detect stagnant media-sequence/segment updates, HLS end lists and timeline
  discontinuities when an HLS media playlist is inspectable. Unknown playlists
  or HEAD-blocking servers fail open; observed playback always takes precedence.
- Recheck network interface changes periodically; reconnect only when playback
  is already buffering. Resume from sleep does not unpause user-paused media.
- Retain volume and restore matching audio/subtitle track IDs when available.
  If track layouts change across sources, avoid forcing invalid track indexes.

## VOD isolation
PlayerScreen creates the supervisor only for a verified live channel. Existing
episode source recovery, pause/resume HTTP VOD reconnect, position resume,
Trakt/Simkl scrobble and completion/autoplay are not reused for live TV. The
live channel suppresses VOD progress timer/scrobble and native completion logic.

## Torriodb events
live_stall_detected, live_feed_starvation, live_reconnect_started,
live_reconnect_opened, live_reconnect_failed, live_recovered,
live_backup_selected, live_sources_refreshed, live_source_rejected,
live_playlist_stale, live_playlist_ended, live_playlist_discontinuity,
live_network_changed, live_session_resumed, live_source_exhausted.

All events use the existing private, opt-in diagnostics. No signed stream URLs,
authorization headers, token material, playlist contents or raw native error
messages are transmitted by this feature.

## Validation
Run:
  flutter analyze --no-fatal-infos lib/services/player/live_tv lib/pages/player/player_screen.dart
  flutter test test/live_tv_recovery_test.dart

Test both Windows and iPadOS in live playback: network unplug/replug, VPN
changes, upstream HLS playlist stalls, expiring stream URLs, exhausted backup
streams and extended continuous sessions. Also test movie/series seeks and
resume regression. Source failure can still prevent playback if every provider
link is unavailable; the player cannot manufacture new broadcast media.


## iPad startup failures and preventive safeguards (November 2026)

iOS Build 248 telemetry showed one Cine Romantico stream recovered through a
Roku backup but FIFA+ Women, Paramount+ Picks and Pluto TV Drama repeatedly
returned from Media.open without delivering playable video. A successful open
has never been sufficient to declare an upstream stream healthy.

The revised live-only controller now:

- Confirms both native video dimensions and actual advancing playback before
  marking a channel started or recovered. A stream that merely connects,
  buffers indefinitely or delivers audio without video fails video readiness.
- Selects channel-scoped backups on the FIRST unverified startup failure,
  instead of retrying the same failed URL before considering alternatives.
- Maintains bounded provider-scoped candidate lists and quarantines bad links.
- Refreshes signed links using the same Stremio channel ID and addon, keeping
  required HTTP CDN headers on each reconnect.
- Continues bounded backoff when providers are exhausted instead of claiming
  an unverified reopen is a success.
- Keeps all recovery state scoped to one logical live channel. VOD seeking,
  playback completion, subtitles, and episode autoplay use separate code.

## Live TV user interface

A small persistent top-right signal badge reports Strong, Unstable, Critical,
Reconnecting or Unavailable based on media-buffer and progress telemetry. It
is NOT a Wi-Fi RSSI meter or a guarantee that the broadcaster is available.
The connecting/reconnecting overlay shows an indeterminate progress bar and
a human-readable state instead of a fabricated percentage. Live channels
disable embedded/external subtitles, auto-downloads and speech alignment,
and hide subtitle-related transport controls. Movies and series are unchanged.

## iPad Torriodb telemetry (opt-in private diagnostics)

The existing iOS diagnostic writer now emits a `liveTvSummary` object and
time-series `sourceTrace` observations during live playback, approximately
every 10 seconds and on relevant state changes.

It identifies the Stremio channel title, channel ID, provider, stream source
label, approximate advertised quality, source hostname and HLS/HTTP format.
The actual programme or movie title and programme type are included ONLY
when supplied explicitly by addon metadata/EPG hints. If no programme guide
is provided the title remains null instead of making up a film name.

Additional fields include:
- Initial session start delay, recovery elapsed time and first-video elapsed
  time, retry attempt count, candidate availability and signal status.
- Video-track dimensions and verified playback readiness, buffering/playing
  flags, position and buffered-end milliseconds, feed/motion staleness.
- HLS media sequence, target duration and discontinuity count where available.
- Stall/startup/no-video, candidate rejection, reconnect, network-change,
  playlist and confirmed playback events.
- Existing MPV performance snapshots include decoder, dropped frames, cache
  and audio/video sync when supported by the native backend.

Source URLs, signed query parameters, HTTP header values, credentials,
playlist segments, private user IDs and arbitrary native error strings are
NOT exported. Live telemetry uses the existing user-controlled opt-in and
Torriodb private upload mechanism and keeps its event history bounded.

## Focused regressions

```sh
flutter analyze --no-pub --no-fatal-infos lib/services/player/live_tv lib/widgets/player/live_tv_overlay.dart lib/pages/player/player_screen.dart lib/widgets/player/player_transport.dart lib/services/player/ios_audio_telemetry.dart
flutter test test/live_tv_recovery_test.dart
flutter test test/live_tv_quality_of_life_test.dart
flutter test test/live_tv_diagnostics_test.dart
```

Field acceptance should test real iPadOS HLS streams, slow startup, audio-only
responses, CDN headers, expired signed links, zero-buffer stalls and successful
fallback while verifying that movies/series remain unchanged.

## Physical-device Build 250 follow-up

* Live `tv` stream requests now only contact installed Stremio addon resources that advertise support for the requested channel ID. Built-in title-matched torrent/HTTP scrapers cannot supply a live channel; targeted fetch and player initialization enforce the same rule.
* iOS HLS Live TV avoids generic FFmpeg streamed-reconnect flags that may interfere with playlist/segment initialization. The existing bounded supervisor handles failures. VOD and Windows playback settings are unchanged.
* Live HEAD and HLS manifest probes use the same resolved request headers as MPV reconnection, including Stremio proxy-request headers. HEAD acceptance remains provisional and must not be confused with actual video readiness.
* Opt-in iOS diagnostics now categorize probe phase, outcome, HTTP status, MIME family, response bytes, elapsed milliseconds, header count, HLS master/media distinction and segment count. Native diagnostics also categorize track count, media format, property access errors and error callbacks. No raw URL, signed query, playlist content, header values or native exceptions are uploaded.
* Physical-device validation is required: passing a unit test or an HTTP HEAD/playlist probe does not prove that an HLS segment decoded or the correct programme is playing.
