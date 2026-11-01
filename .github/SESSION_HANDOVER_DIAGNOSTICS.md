# Update: replacement Windows #168 + iOS #162 RUNNING, 2026-11-01 SGT

Owner asked "progress?" after prior release request, and authorized builds earlier. Both initial native release workflows failed during prebuild Flutter test compilation BEFORE native compilation: Windows #167 run 41273349520 and iOS Run #12 Build #161 run 41273398260. Exact same syntax error: `lib/services/player/windows_playback_telemetry.dart:284` contained `'playback_sample',, 'sync_failure'`. Fixed in source commit `fa1a1037229957a4ab9342d0d716c4b60b1fb0c3` to one comma.

New replacement native release requests accepted and started:
- Windows **Build #168** Run **41274584648**, https://github.com/mghazalyh/ptv3/actions/runs/41274584648, [windows-only] trigger commit `cdf45959c1001f41cedd1707c9496c55f1f629bc`.
- iOS **Run #13 / Build #162** Run **41274623547**, https://github.com/mghazalyh/ptv3/actions/runs/41274623547, trigger commit `9c858bfd865344e9bce0eb6b292860accb3208c7`.
- Both were **in_progress**, and no successful release, checksum or Telegram delivery is yet claimed. User expressly requested **no ongoing monitoring**; avoid polling and duplicate native builds. Check final status only when owner returns.
- Source commits `cff5f6ebd0044f4205598f9630651ac45ea918c3` etc contain shared stage allowlist and automatic failure uploads under platform existing opt-in, Windows track correction, iOS oversized Telegram link fallback. iOS audio compressor preserved.

## Earlier handover follows

# Active build handover — 2026-11-01 SGT

User explicitly requested: trigger both native builds and do NOT wait to monitor them. Both requested workflows HAVE STARTED and are running; do not trigger duplicates.

## Source changes and delivery

- Source commit `cff5f6ebd0044f4205598f9630651ac45ea918c3` adds shared fixed-value, opt-in diagnostic events, automatic throttled uploads on failure for both Windows and iOS, cross-platform subtitle Auto Sync stage records, Windows non-default audio track mpv extraction instead of FFmpeg first-track mismatch, regression tests, and iOS oversized IPA Telegram GitHub-link delivery.
- Commit `981a1758ad44ff8cc7dc83f814477c598d8995ad` fixed an invalid self-dependency in iOS workflow YAML. Previous workflow parse-only Run #11 `41273194305` failed and produced NO IPA.
- Windows-only native Build **#167**, workflow `41273349520`, triggered by `b5a1de33ea7e2eb3c5d98ed6a82cb27432553234` with `[windows-only]` release policy. URL: https://github.com/mghazalyh/ptv3/actions/runs/41273349520
- iOS-only signed TrollStore release Run **#12**, IPA Build **#161** (149+12), workflow `41273398260`, triggered by `9871da6dc31fdc0944bc15eab89a599312542e5e`. URL: https://github.com/mghazalyh/ptv3/actions/runs/41273398260
- Both workflows were **in progress** when this handover was saved. DO NOT claim compilation, signing, checksum, Telegram or runtime verification success yet. The owner will check Telegram and contact again if any workflow fails.
- Existing Windows #166 and iOS #159 remain distinct earlier releases. iOS libmpv 0.6.8 encodersgpl filter fix preserved.
- Existing telemetry permissions remain explicitly opt-in (Windows Debug Mode and iOS Private Audio Diagnostics). Upload is fixed-code only, media URLs/transcripts/user secrets never included.
- For follow-up: check real run jobs and release tags first, then handle a **delivery-only** recovery if signing/publication already passed. Never re-run successful native builds merely for oversized Telegram attachments.

## Original request

# Emergency session handover: diagnostics and dual release

Owner requested automatic privacy-safe opt-in diagnostics uploads on Windows and iOS and new native releases for both platforms. First address Windows subtitle Auto Sync; FFmpeg uses 0:a:0 regardless of player-selected audio track and telemetry does not record extractor, recognition, matcher or timing errors. Add bounded stage codes and automatic uploads while diagnostics permission is enabled, with no subtitle text, URLs, tokens or transcripts. Preserve Windows Build 166 and iOS Build 159's filter-enabled libmpv fix. Analyze/test, request Windows and iOS builds separately, verify GitHub assets and Telegram. Check existing run status before retries.
