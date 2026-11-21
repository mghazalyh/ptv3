# iPad Build 257: unattended Cloudflare Live TV validation

Date: 2026-11-21. The iPad was running PlayTorrio commit `ed907cbf93401c7e7dfd8220cf47baabf9d3a3f2`, Build 257. All commands below were issued through the owner's existing opt-in private Torriodb in-app command channel. No on-device taps, raw stream URLs, signed tokens, cookies, authentication headers, private device ID, or request bodies are included here.

## Direct Stremio addon test, not just player claims

The installed addon's **actual host** was `ptv3-livetv-addon.pages.dev` (Cloudflare Pages), rather than the previously discussed `playtorrio-livetv.playtorrio-ptv3.workers.dev` hostname. The deployment may have Worker functionality behind Pages. Do not assume the app uses the older Worker hostname, or attribute a failing CDN request to the Cloudflare Pages service without evidence.

The new `probe_addon` action issued actual HTTPS GETs to the installed addon's manifest and `/stream/tv/{id}.json` endpoint from the iPad. All three requests returned a parseable manifest advertising compatible TV stream resources and an HTTP 200 Stremio stream payload:

| Channel ID | Direct HTTP sources | HLS sources | Sources with declared request headers |
| --- | ---: | ---: | ---: |
| `nltv:us:NFLChannel.us` | 3 | 2 | 1 |
| `nltv:us:SYFY.us` | 2 | 2 | 0 |
| `nltv:us:ParamountPlusPicks.us` | 1 | 1 | 0 |

These results establish **addon discovery and serialization**, not stream availability. Horizon TV's server-side health checks may be accurate from a different machine, region, time, header context, or playback client, but do not substitute for video evidence on the iPad.

## Native iPad playback results

| Tested stream | iPad HLS/network probe | MPV track/video evidence | Outcome |
| --- | --- | --- | --- |
| NFL Channel, source index 0 | Master HLS HTTP 403 | 0 tracks, position 0, buffering | Upstream rejected playlist |
| NFL Channel, source index 1 | HEAD HTTP 404 | 0 tracks, position 0, buffering | Alternate URL unavailable |
| SYFY, source index 0 | HLS playlist network error on deep probe | 0 tracks, position 0, buffering after retry | Not playable in this test |
| SYFY, source index 1 | Playlist probe timed out at 6 seconds | 0 tracks, position 0, buffering | Not playable in this test |
| Paramount+ Picks, source index 0 | Referenced HLS child HTTP 414 | 0 tracks, position 0, buffering | Child playlist rejected |
| Public Mux HLS reference, native `loadfile` | File format HLS | 10 native tracks, timeline >34 seconds, not buffering | Actual playback confirmed |

NFL source index 2 was not retested in this Build 257 session; an earlier iPad session recorded HTTP 414 for that alternate. Avoid conflating earlier and current observations.

### Previous app regressions now confirmed fixed

1. Switching from one PlayerScreen to another no longer unregisters the newer route's cloud player callback. After NFL source selection changed, both `player state` and app `state` succeeded, rather than returning `no_active_player`.
2. Playing an unrelated public HLS control stream through native MPV no longer makes a failed channel look healthy: the Live TV supervisor reported `active=false`, and the uploaded telemetry context changed to `diagnostic:native-reference`, with `liveTvSummary=null`.

### Remaining issue and next-build diagnostic improvement

A Stremio addon returning `streams[]` does not prove that the source URI, nested HLS variant and its segments are playable. NFL's HTTP 403/404 and Paramount's nested HTTP 414 are source/provider responses, not Stremio manifest parsing failures. The current evidence cannot prove that the Cloudflare service assembled malformed URLs; deployed server code was not available in this repository.

The proposed next-build change exposes **host and numeric URI component lengths only** for the failing playlist/variant requests (especially HTTP 414), plus up to eight indexed source summaries with HLS flag and whether request headers were declared. No URI path text, query content, signed token, cookies or header values appear in results. Tests assert correct child-URI attribution and receipt redaction.

The iPad was asked to return to Home after the playback diagnostics. Continue testing only after the next iOS build is installed; do not poll the CI job once its trigger commit is pushed.
