# Cloudflare-hosted Horizon TV addon: iPad live verification

Date: 2026-11-21 (Singapore). Tested **before** editing the failed iOS build.

## What was tested

The owner-enabled iPad client used its installed Stremio TV addon to perform fresh `StreamService.fetchStreams(type: 'tv', id: ..., title: ...)` requests for three known channel IDs. These requests call the installed addon's `/stream/tv/{id}.json` resource and parse returned Stremio stream objects. Results were obtained from private, device-written GitHub command receipts.

| Channel ID | Candidate count | Device result |
| --- | ---: | --- |
| `nltv:us:NFLChannel.us` | 3 | `accepted: true` |
| `nltv:us:SYFY.us` | 2 | `accepted: true` |
| `nltv:us:ParamountPlusPicks.us` | 1 | `accepted: true` |

These observations establish that the installed addon returned streams to the iPad for each request. They do **not** confirm that the configured addon host is the historically documented `playtorrio-livetv.playtorrio-ptv3.workers.dev`, that its manifest and catalogs currently conform to all Stremio requirements, or that any returned stream will decode.

The external web-fetch tool could not retrieve the documented Worker's `manifest.json`. The isolated runtime's DNS is disabled. This inability to reach the endpoint from the tooling is **not evidence** that the Worker itself is offline. The deployed Cloudflare Worker source code is not present in the PlayTorrio `ptv3` Git tree, so no Cloudflare deployment was modified.

A subsequent iPad `probe_live` command following a channel change returned `no_active_player`, consistent with the already diagnosed old-screen callback-unregistration defect. Thus the additional Paramount+ media/segment result is **unverified**, rather than incorrectly reported as failing upstream.

## Prior playback evidence (same iPad build)

- NFL Channel main HLS playlist HTTP 403, alternate stream no playback, third HLS variant HTTP 414.
- SYFY media segment HTTP 206 and valid-looking media playlist, yet no initial MPV tracks or video frames.
- Public HLS reference stream successfully decoded in the same iPad MPV environment. This does not validate the SYFY original feed.

## Source and build follow-up

The iOS release workflow Run 54 failed `test/live_tv_stream_isolation_test.dart` at line 73. That test expected an HLS source to be accepted on `HEAD 405` while the GET returned an HTML error body with HTTP 200. The newer source manager correctly rejects the invalid GET manifest; update the obsolete test expectation, **not** the safer production logic. The shared-code fast-check workflow succeeded.

The next iOS build adds an opt-in `probe_addon` cloud command. It reads an already-installed addon manifest and stream JSON directly on the iPad, returns only HTTP/manifest/stream classification and counts, and never serializes signed URLs, request headers, tokens or response bodies. It will allow direct Cloudflare Worker manifest and stream-resource verification without relying on the external web-fetch tool during the next installed-build test cycle.

No Cloudflare Worker code, DNS settings, or infrastructure configuration has been changed.
