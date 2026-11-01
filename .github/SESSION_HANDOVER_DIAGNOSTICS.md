## VERIFIED iOS-ONLY NATIVE REPAIR #171 TRIGGERED ONCE — 2026-11-01 SGT

**Owner task:** Fix real Night Mode failure in installed paired #170, then build ONE iOS-only signed IPA. **Night Mode root cause:** paired iOS pipeline omitted checksum-pinned `encodersgpl` FFmpeg `acompressor`/`compand` filters that iOS-only workflow already used; exact private opt-in #170 telemetry 2026-11-01T07:36:39Z shows both filters missing and `ios_filter_preflight_failed`. Source repaired through SHA **`c717e387aeb0d7b15e1db27585a60ed0b3918a09`** with paired/native filter preparation; BOTH workflows now verify built Runner.app Avfilter before signing, and CI regression tests assert one primary + two backup runners with pinned compressor path. Final [Linux + Windows source gates **41286494025**](https://github.com/mghazalyh/ptv3/actions/runs/41286494025) BOTH COMPLETED SUCCESS. Earlier #374 guard-mutation test failure was fixed; do not confuse it with final success.

**ONE AND ONLY ONE iOS-only release request ACCEPTED:** `.github/ios-speech-release-request.txt` trigger SHA **`efd04d10af04f90fa95daa90bd51a83bf29540d0`** accepted as [**iOS-only Run #14, expected signed Build #171**](https://github.com/mghazalyh/ptv3/actions/runs/41286808046), observed **IN PROGRESS**, primary Intel Mac job checking out source. New iOS-only numbering 157+run14=171 > paired #170. Updated accurate 443-character `.github/release-notes.txt`. **DO NOT RETRIGGER OR RECOMPILE DUPLICATE.** Windows paired Build #170 remains published unchanged, release https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.15-b170 with Windows Setup/portable/iOS #170 and checksum, Telegram Windows link #104 and iOS sendDocument #105. #170 iOS Night Mode still failed on owner's iPad, so do not recommend that old IPA as a fix.

**NEXT STEPS:** Inspect SAME iOS Run14 actual native jobs. Verify prebuild libmpv 0.6.8 `encodersgpl` SHA256 pin, `acompressor`/`compand`/`alimiter` symbols in actual built Runner.app, unsigned build, iOS15 iPad family, ad hoc TrollStore signature, IPA zip integrity, published permanent iOS-only GitHub Release with byte sizes/SHA256 and Telegram actual attachment or >=50 MB link fallback. If publishing fails, diagnose permissions and try delivery-only recovery without recompiling successful IPA. No fresh #171 hardware Night Mode acceptance yet; only newly installed IPA plus positive opt-in telemetry and owner hearing can confirm. **MANDATORY at end of EVERY PlayTorrio response:** updated, copyable full emergency handover prompt with this status and a DYNAMIC Singapore timestamp; persist this instruction inside handover docs. Main remains historical documentation mirror; shared branch is `parity-floating-player-both`. Read `SESSION_RECOVERY_PROMPT.md`, TOP `handover.md`, `AGENTS.md`, `NEXT_SESSION.md`, `CURRENT_SESSION_HANDOVER.md`, and `.github/RELEASE_DELIVERY_POLICY.md`.

## OWNER NIGHT MODE REGRESSION — BUILD #170 (2026-11-01 SGT)

Mandatory copyable recovery handover prompt at END of EVERY PlayTorrio assistant response, including dynamically sampled SGT time, must survive session crash and be persisted in `SESSION_RECOVERY_PROMPT.md`, `handover.md`, and other leading docs. Actual private TorriODB opt-in Build #170 iOS Night Mode report at 2026-11-01T07:36:39Z confirms missing native `acompressor`, `compand`, MPV filter graph and preflight failure. Paired workflow omitted iOS-only pinned compressor framework preparation; Build #170 native release SUCCESS nonetheless, but night mode NOT working on device. Source fixed through app/workflow SHA `afa6f75ab7a2f556eeee89255763e12a87ef0b11`: both native pathways now prepare/verify pinned compressor library, verify built app before signing; static parity regression guard in Linux CI/native builds. Owner requested ONE iOS-only repair, expected upcoming Run #14/Build #171; check final source gates `41286196027` and no active native builds before one request via `.github/ios-speech-release-request.txt`. Preserve Windows Build #170; no iOS hardware acceptance or new IPA release yet.

## OWNER-MANDATED PER-RESPONSE HANDOVER PROMPT (2026-11-01 SGT)

**MUST:** End EVERY PlayTorrio assistant response with an up-to-date, copyable **Handover prompt**, including short answers and status replies. It must tell a new session the repository + active branch, current verified builds, latest user issue, uncertainties, required reading and next owner-authorized work. Keep the latest prompt in [SESSION_RECOVERY_PROMPT.md](SESSION_RECOVERY_PROMPT.md); read/update that file and this handover after material changes. This rule applies across subsequent sessions and is mirrored to `main`. Do not expose telemetry secrets or invent device acceptance. A handover-only/documentation edit authorizes NO new native build.

**Latest verified checkpoint superseding older entries:** Windows Build **#168** (run 41274584648) and signed iOS Build **#162** (run 41274623547) both completed SUCCESS and were published with checksums and successful Telegram jobs. The NEW unresolved user issue is Windows #168 five-minute subtitle Auto Sync: subtitles progressively drift and require manual resync. Prior conversation reported a 13:55 SGT `sync_alignment_no_match` despite completed audio capture/Whisper transcription; successive sync events are not yet provably automatic rather than manually triggered, and no rate-drift cause is proven. Preserve this problem in future handovers. See the standalone recovery prompt for safe investigation and release rules.

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
