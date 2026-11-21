# iPad Live TV unattended diagnosis — 2026-11-21

## Scope and build

Owner-enabled remote control was exercised through the private Torriodb GitHub command inbox, from the iPad's foreground PlayTorrio build created after commit 12d1a91fd91d04797ae90838f45528d15ce97ca5. Commands were delivered without further on-device interaction. Results were collected from private device receipts and opt-in iOS telemetry. No raw signed stream URL, secret, authentication header or device-specific ID is reproduced here.

## Reproduced failures

1. **NFL Channel / source 0:** source discovery succeeded with three candidates, but the main Akamai-hosted HLS playlist returned HTTP 403. Native MPV recorded `live_native_http_auth` and `live_native_manifest_failure`; `core-idle` remained true, native video tracks zero and playback position zero. Reopening the known 403 source did not help.
2. **NFL Channel / source 1:** switching directly to the second (Samsung TV Plus / HTTP backup) produced no verified playback; no decoded tracks and no moving timeline. The app's old player screen disposed after the replacement screen mounted, **clearing the new screen's globally registered remote player handler**. The command inbox remained online, but `player` commands returned `no_active_player` and the top-level app state had an empty `player` object. A separate Home navigation and subsequent channel open restored remote control.
3. **NFL Channel / source 2:** the third alternative returned HTTP 414 at the HLS media playlist probe; native video tracks and timeline remained absent.
4. **SYFY / source 0:** an explicit HLS segment HTTP Range request returned 206, and the media playlist returned 200. Despite reachable bytes, native MPV initially reported `core-idle=yes`, `track-list/count=0`, no codec, no video output and zero timeline. More than 2,000 raw native error callbacks were counted during attempts; they were already deduplicated in telemetry events. A 206 result for arbitrary bytes is not proof that a segment contains valid video data.
5. **Public reference HLS media:** a deliberately issued native MPV `loadfile` of the public Mux Big Buck Bunny HLS sample succeeded using the exact same iPad media_kit/MPV player. Playback reached 22 seconds with 1080p video, HLS format, 30 seconds of buffer ahead and no buffering. This proves general HLS decoding works on this iPad; the failures are more specific to channel source accessibility/content and recovery. That test bypassed the Live TV StreamSource, but the old coordinator still reported its previous SYFY context as `verifiedPlayback` after the reference video started. The source-attribution defect is fixed in this patch.

## Changes following the live reproduction

- PlayerScreen owns its LAN/cloud callbacks and only unregisters them on disposal if the callback still belongs to that screen. Old route disposal cannot detach the replacement player's handlers.
- A direct native MPV `loadfile` during a Live TV session suspends the old Live TV watchdog and replaces the telemetry playback context with a fixed diagnostic reference identity. The external test stream is no longer falsely attributed as a recovered broadcast.
- Live HLS source recovery probes the current source before reopening when no working alternative was selected; explicit HTTP failures are recorded rather than repeatedly opening the same provably failed URL.
- The deep segment probe classifies small bounded response bytes as MPEG-TS, fragmented MP4, ID3, AAC, HTML, JSON, playlist, empty or unknown. HTML, JSON and manifest responses masquerading as media are flagged as invalid. No raw segment bytes are serialized.
- Native diagnostic receipts now include probe outcome, segment kind, number of bytes and timing.

## Remaining limitations

HTTP 403 and 414 are responses from source/provider endpoints; local player changes alone cannot convert an inaccessible or rejected feed into a functional television broadcast. Playlist HTTP 200 and byte-range HTTP 206 only establish partial reachability, not valid or decodable segments. A further on-device test after installing the new iOS build is needed before claiming the particular channels play successfully.

The iPad was returned to PlayTorrio Home at the end of the diagnostic session. The unattended channel requires the application to remain in the foreground because ordinary iOS suspension pauses Flutter polling.
