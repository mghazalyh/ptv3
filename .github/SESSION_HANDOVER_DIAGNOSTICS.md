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
