# PlayTorrio release delivery: standing owner instruction

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

## Current specific authorized work (2026-10-29)

The owner previously asked to fix iOS speech-based subtitle alignment. Build #148 was signed, verified and delivered (run `40821991500`, Telegram document message 67, release `ios-speech-v1.1.15-run3`), but a follow-on fix was committed after #148: when offline recognition fails, explicit Apple-service consent must actually disable the native offline-only restriction. The source CI run `40831520647` passed. **The owner has now expressly reiterated that this follow-on fix should be built and delivered automatically. Trigger one iOS-only Build #149 from the validated latest source (after updating release notes and checking for active jobs), then verify Telegram and GitHub Release.** Never describe this fix as present in #148.
