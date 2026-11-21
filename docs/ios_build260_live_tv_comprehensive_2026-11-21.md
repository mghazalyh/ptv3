# PlayTorrio iPad Build 260: comprehensive unattended Live TV cycle

Report generated (SGT): 2026-11-21 19:53:14
Device build: 260, commit `b78acc1565d12eb04101f4f646637331086bcdc2`
Addon host: `ptv3-livetv-addon.pages.dev`
Testing: real installed iPadOS 15.6.1 player, Torriodb command receipts, native MPV properties and HLS probes.

## Ground rules

A stream counts as playable only with native video tracks, decoded video dimensions, non-buffering and an advancing timeline. A Stremio `streams[]` response, HEAD 200, playlist 200, HTTP 206 segment or `playing:true` alone does not count. Source switching during recovery is noted, so a failure cannot automatically be assigned to the original source index.

## Stremio addon results

- Manifest 200 and valid TV stream declarations for the inspected IDs.
- NFL Channel: three source candidates; one HTTP-header-bearing URL.
- SYFY: two candidates; no declared headers.
- Paramount+ Picks: one candidate; no declared headers.
- Cine Romántico: three candidates; two with request headers.
- Bloomberg TV: three candidates on multiple CloudFront and Wurl providers.
- Free Speech TV: one candidate.
- Pluto TV Drama: one candidate.
- Guess `nltv:us:NASATV.us` returned zero sources, not grounds for a general NASA TV verdict.
- All tested responses were from the configured Cloudflare Pages addon. There is no verified change to its deployment code.

## Actual on-device playback observations

| Channel/source | Network and native evidence | Outcome |
| --- | --- | --- |
| NFL index 0 | Navigation accepted; auto-recovery switched to jmp2.uk; native tracks 0, position 0 | No verified playback |
| NFL index 1 | Navigation accepted; auto-recovery switched to jmp2.uk; native tracks 0, position 0 | No verified playback |
| NFL index 2 | jmp2.uk HLS Range 206, 825 bytes, signature unknown; native tracks 0 | No verified playback |
| SYFY index 0 | Main playlist network error, source 23.237.104.106; tracks 0 | No verified playback |
| SYFY index 1 | tvsen7.aynascope.net playlist timeout after 6002ms; tracks 0 | No verified playback |
| Paramount+ Picks index 0 | jmp2.uk Range 206, unknown segment signature, tracks 0 | No verified playback |
| Cine Romántico index 0 | jmp2.uk non-HLS link; tracks 0, position 0 | No verified playback |
| Cine Romántico index 1 | jmp2.uk HLS redirect through aka-live1050.delivery.roku.com; native HLS, 11 tracks, H264/AAC, 1280x720, timeline advanced to more than 84 seconds, buffering false | **VERIFIED PLAYING** |
| Cine Romántico index 2 | CloudFront first TS segment Range 206, valid MPEG-TS signature, but native TLS/segment errors and no tracks | No verified playback |
| Bloomberg index 0 | Recovery selected d8975dc3.wurl.com after original CloudFront; TS 206, native tracks 0 | No verified playback |
| Bloomberg index 2 | Wurl source with native TLS/segment failures, fallback to d8975dc3.wurl.com; tracks 0 | No verified playback |
| Bloomberg index 1 | Observed through recovery as an alternate, with MPEG-TS probe 206 and no native video; not manually opened as its own source | No verified playback in observed recovery |
| Free Speech TV index 0 | na.linear.zype.com playlist valid, TS Range 206 4096 bytes, yet no tracks across recoveries | No verified playback |
| Pluto TV Drama index 0 | jmp2.uk 206 and unknown signature, native TLS and segment errors, tracks 0 | No verified playback |

**Important:** An `unknown` signature on the small sampled byte range does not prove the entire segment is invalid. The actual working Cine Romántico Roku source sometimes had this signature while native HLS playback succeeded.

## Working channel acceptance detail

Cine Romántico index 1 was observed at positions 24.533s, 48.033s, 72.133s and 84.033s, with 11 native tracks and 1280×720 dimensions. The video was not buffering. The recovery attempt counter returned to zero after stable playback. The remote Pause action made `playing:false` with no unwanted recovery. Play resumed with `playing:true`, native video dimensions retained and timeline advancement verified.

This is a real configured TV source through PlayTorrio's ordinary player path, **not** the public Mux reference-media diagnostic.

## Consolidated root-cause direction

1. The Cloudflare addon returns valid Stremio TV stream objects but does not guarantee each remote source is playable from Singapore.
2. Some upstreams are simply rejecting or timing out, as demonstrated by SYFY and historical NFL 403/404 cases. A Flutter change cannot make a permanently rejected upstream broadcast available.
3. Multiple independent providers serve playlists and recognizable media segments through Dart HTTP, while iOS native MPV reports TLS and segment failures. This deserves an alternate transport experiment rather than endless live supervisor retries.
4. The open `media-kit` issue https://github.com/media-kit/media-kit/issues/1437 describes bundled iOS native MbedTLS client limitations on TLS-1.3-only CDNs. This is **relevant supporting evidence**, not proof that each tested provider uses that exact TLS configuration.
5. HTTP 414 was previously observed on nested HLS redirects. Build 260's redirect resolution change let Paramount reach a media segment; that does **not** prove broadcast playback.
6. The working Roku stream proves that native media decoding, Live TV navigation, buffer supervision, pause/resume and normal Stremio integration are capable of functioning on this installed iPad.

## Changes prepared for next consolidated build

- Add a **Live TV-only, on-device loopback HLS relay**, activated only after a native TLS failure with an accessible playlist or a second unverified recovery attempt with an accessible playlist.
- Use Dart's working HTTPS stack for upstream playlists, keys and media bytes while MPV connects to a short-lived localhost endpoint.
- Preserve provider headers and Range requests, follow bounded redirects, resolve relative HLS paths against the final destination, rewrite playlist URI attributes, and preserve upstream HTTP error statuses.
- Keep normal direct native playback as first priority, preserving the working Roku stream.
- Limit relay usage to one attempt per source per session and shut it down on player disposal.
- Add regression coverage for redirects, HLS encryption-key references, segment Range bytes, HTTP 403 and redirect loops.
- Add Linux quality-gate tests **before** the iOS build so fixture or compiler failures do not waste a signed-IPA workflow.

## Acceptance and outstanding limitations

The newly prepared relay requires prebuild validation and an installed-build playback test before any channel can be declared fixed. The deployed Cloudflare addon was not modified. This testing cycle is meaningful even without another IPA because it produced a verified working real channel, an explicit source/provider matrix and reproducible native transport fault categories.

Do not label a new iOS build as successful or call upstream sources fixed without native iPad evidence. Always stop immediately after the eventual iOS-only trigger push.
