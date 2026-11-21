# iOS Live TV See All: health-first scan and native verification

## Behavior

Opening **Live TV → See All** first fetches the entire compatible installed
Stremio TV catalog (up to the existing safety limits) and runs four concurrent
HTTP preflight workers. The grid waits for this quick preflight to finish, then
sorts channels by observed health. Once sorted, a **single, muted native MPV**
worker verifies channels sequentially and upgrades genuine successes to the
top as results arrive.

## Health-first ranking

1. **Working · MPV**: requested source rendered actual video with native
   dimensions and tracks, advanced its playback clock at least 5 seconds,
   and exited buffering.
2. **Works via backup · MPV**: original source failed, but a later source met
   the same native decoding requirement. This is lower than direct playback.
3. **Unstable · MPV**: video rendered but could not sustain the minimum
   advancing, unbuffered playback interval.
4. **Reachable · HTTP only**: playlist/segment worked, but there is **no native
   decoding proof**. Never label this as verified playback.
5. **Unverified · HTTP only**: network or resolution was inconclusive.
6. **Poor · MPV / HTTP only**: no successful candidate; a native outcome is
   distinguished from preliminary network classification.
7. **Checking**: not yet inspected.

Within the same verified tier, shorter startup latency comes first. All ties
retain their original catalog order instead of alphabetical or random
reordering.

## Native testing safety

- Uses only the app's own enabled Stremio TV stream sources, no supplied URLs.
- A new dedicated `Player` and `VideoController` are created for each
  candidate so a prior channel cannot leak decoded frame evidence.
- The probe's video output uses a low-resolution 320×180 texture, while
  recording **native source video dimensions** (not texture dimensions).
- Mutes before opening and again after applying player settings.
- Uses the same MPV pre-open properties and request headers as Live TV.
- Samples native video-params, track-list, first rendered frame or screenshot,
  nonbuffering state and progressing timeline. HTTP 200/206 does not pass.
- Limits each candidate to an initial open timeout and a bounded observation
  window; tests at most four sources per channel.
- Disposes its dedicated MPV player after each candidate, never reuses or
  seeks the user's main video player. Tests run sequentially on iOS only.
- Cancels on page navigation, lifecycle backgrounding or disposal.
- No credentials, signed URLs, screenshot data, or stream headers are uploaded.

## User experience and limitations

- The grid is held until the quick HTTP catalog scan is complete.
- The native pass runs sequentially and may take substantially longer when
  many sources fail; its progress and verified count are visible on screen.
- The grid automatically reorders as actual native results arrive. It is
  possible for a source to expire or stop transmitting after verification.
- This scan verifies a **playable startup sample**, not five-minute stability.
  The unattended 300-second matrix remains the stronger sustained test.
- This work is GitHub source-only and **does not change installed iOS build
  262**. No native installation or non-iOS release build was triggered.
- Only explicit manual ChatGPT interactions initiate new Torriodb iPad tests;
  the former scheduled PlayTorrio task remains disabled.

## Testing

`test/live_channel_health_scanner_test.dart` exercises HTTP-only
classification, stable health sorting, startup ordering, real decoded-video
eligibility, confirmed fallback ranking, misleading audio-only timelines,
stalls, and cancellation. GitHub's normal lightweight quality gate executes
these tests, without producing a Windows/Linux/Android release artifact.
