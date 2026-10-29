# PlayTorrio release delivery: standing owner instruction

## Mandatory: ONE Flutter codebase for Windows and iOS

The owner's explicit requirement is that **Windows and iOS coexist on the same `parity-floating-player-both` branch and in the same Flutter source tree**. Never fork a separate iOS app, Windows repository, product branch or duplicate player to implement a platform-only feature. Keep the Windows desktop entrypoint, dependencies, playback, manual subtitle timing and release-matched subtitle option functional when adding iOS-only native services. Put Apple Speech/Swift code under `ios/` and guard channel invocation with an iOS-only branch. Windows must never call the Apple Speech method channel; its Auto Sync button performs release-matching and provides an accurate Windows tooltip.

For every source change affecting shared playback, the Linux Flutter quality gate and the Windows-only **test/analyze** job in `.github/workflows/playtorrio-fast-checks.yml` must pass. The Windows job does NOT package or publish Windows binaries on ordinary code changes; a Windows native installer release only runs when the owner requests Windows/paired packaging. An iOS-only IPA may have a newer release/build number than Windows while the **shared codebase stays unified**. Subsequent paired releases must use that same branch/source commit on both platforms.


**Priority owner directive (2026-10-29): implementing an authorized app fix includes building and delivering its installable native app, not just committing code.**

This repository policy is read by every future assistant/developer working on PlayTorrio. It remains in version control across chat sessions and should be mirrored at the TOP of AGENTS.md, NEXT_SESSION.md, and handover.md. A new user instruction overrides this policy.

## When to build without asking again

When the owner asks to **fix, implement, or continue an already-authorized native app issue** (iOS or Windows), the task includes the **next verified native release** for the affected platform(s), unless the owner explicitly says "source only", "don't build", or equivalent. After implementing and checking the fix, automatically request exactly one appropriate signed native build **within the same task/turn**. Do NOT stop at a green Flutter CI check or a source commit, and do NOT make the owner repeat "build it". If an earlier answer promised to build after fixing, that is already authorization.

- If the owner asks for an **iOS fix**, use the iOS-only workflow `.github/workflows/ios-speech-release.yml` via one deliberate update to `.github/ios-speech-release-request.txt`. Do **not** rebuild Windows.
- For an owner-requested **paired Windows and iOS release**, update `.github/release-request.txt` once to run the paired workflow. Never trigger an extra iOS-only workflow in parallel.
- Update `.github/release-notes.txt` **before** triggering, with accurate "What's new / Fixed" notes including important limits for Telegram.
- After the source/test changes are committed, confirm the relevant checks pass. If checks fail, fix them first; the native release workflow also runs source/native tests and signing checks. Never knowingly ship a broken or unverified source revision.

## Hard constraints

1. **No overlapping or duplicate native builds.** Check GitHub Actions for ALL queued/in-progress Windows and iOS native workflows before requesting a release. If one exists, continue/inspect that same run; do not create a duplicate request. Do not trigger a second request for the same source fix after success.
2. **Do not enable automations or schedules.** This policy is task-scoped authorization when the owner asks for work; it does NOT authorize every ordinary push, documentation edit, background polling, or arbitrary new feature to trigger builds.
3. **A native build isn't finished until the artifact is actually signed, verified and delivered.** Verify iOS 15 deployment target, ad hoc TrollStore signature, a nonempty IPA; successful Telegram `sendDocument` containing useful feature/fix information; and a unique permanent GitHub Release with IPA/checksum (plus Windows installer/portable ZIP when requested). Provide direct links and clear status; don't equate passing CI with delivery.
4. **On a failure, inspect actual logs and fix the cause, then recover without recompiling successful platform artifacts.** Use bounded runner fallback if cancelled with no runner; never blindly rerun known app/compiler/signing failures. Do not overwrite prior releases. If service or tooling blocks completion, give exact run/error and the remaining blocker, not a false success.
5. **Do not overclaim functionality.** A signed build does not prove a speech subtitle decoder works on the owner's individual iPad/stream; preserve this caveat and use device feedback for device-specific failures. Avoid leaking private playback URLs, tokens, or file content.
6. **No empty future promises:** Do the currently available steps now; if a workflow is still running, report its current status and tracking link and say that no autonomous background notification will arrive from this chat.

## Current release status (2026-10-29)

**LATEST VERIFIED PAIRED RELEASE (2026-10-29):** PlayTorrio v1.1.15 **Build #147** on ONE shared Flutter source `7770f34dd709108dba9edd3ba30e5f33d04ae455` passed all native, publish and delivery jobs in Actions run `40861551340` (`https://github.com/mghazalyh/ptv3/actions/runs/40861551340`). Windows x64 Setup EXE and portable ZIP include a verified launchable offline whisper.cpp v1.9.5 CPU binary (English base.en model 148 MB is downloaded once with consent and SHA-256 validation); iOS 15 signed TrollStore IPA now saves Apple's online Speech permission and provides a Settings revocation switch. Both speech-based Auto Sync paths use the shared dialogue-to-subtitle alignment and attempt silent five-minute periodic rechecks only during playback with external text subtitle cues. Linux + Windows fast checks both passed (`40861032799`). GitHub Release `https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.15-b147` contains Windows installer, portable ZIP, signed iOS IPA and SHA256SUMS. Telegram actual Windows document **71** and signed iOS document **72**, both confirmed. No outstanding native build obligation for this request; do NOT trigger a duplicate paired build. Native release CI success does NOT establish subtitle timing on the owner's particular Windows machine or every stream.

The earlier iOS-only Build #149 and paired Build #146 remain archived; their workflow counters are independent, so Build #147 is the newly verified paired release using newer source. Do not split iOS and Windows codebases. Actual device runtime quality is not proven by native CI alone.
