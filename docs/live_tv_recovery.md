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
