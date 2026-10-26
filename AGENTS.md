# Repository agent instructions — PlayTorrio

These repository instructions apply to the entire tree. The active product-development branch is **parity-floating-player-both**, while the repository default **main** may lag. Read **handover.md** before starting any change.

## Mandatory living handover rule

**Every application change or update must include a matching edit to root handover.md in the same work unit, ideally in the same commit/PR.** This includes source, UI, player, data schema, tests, dependency/config changes, GitHub Actions, releases, deployment, Telegram behavior, bug fixes and meaningful validation status. Never finish an implementation while leaving the handover stale.

When updating handover.md:
1. Refresh the top **CURRENT STATUS** (app version/build, exact branch SHA, latest completed Windows+iOS paired release vs partial builds) using GitHub's current data.
2. Update feature behavior and affected source/test/workflow file paths; include design constraints and edge cases.
3. Add a dated **Update log** row: goal, commits, tests, workflow run IDs and conclusions, releases only if verified, Telegram direct attachment vs fallback, blockers and next steps.
4. Keep it comprehensive, usable from a cold start and honest about missing real-device validation.
5. Mirror handover.md and AGENTS.md to the default main branch as documentation **when appropriate**. Do not merge stale main application code into the development branch to accomplish this. Avoid needless CI rebuilds purely for docs if infrastructure supports documentation-only filtering.

## User constraints and release standards

- Maintain **non-floating player** behavior; do not reintroduce floating picture-in-picture or floating player implementations.
- Preserve English-preferred audio, automatic English subtitles when available, Next Episode and same-addon stream preferences, private GitHub My List/Continue Watching sync, and Show Details navigation preserving playback.
- Target matched **Windows x64 installer + portable ZIP** and **ad hoc signed iOS 15 TrollStore IPA** from the same commit. Main paired workflow: **.github/workflows/windows-advanced-discover.yml**.
- The final user-facing answer should prominently show **semantic version and GitHub build number**, exact feature entry point, CI status/step counts, **verified** download links, release and Telegram IPA delivery status, and explicit limitations. Never fabricate sandbox paths, GitHub release assets or Telegram success.
- The current preferred private DB is **mghazalyh/torriodb**, branch main, with two versioned JSON files. Device PATs are independently provisioned and securely stored. **Never log, commit, paste, or repeat token values, private media history, Telegram credentials, or private group identifiers in public documentation**.
- Avoid repeated questioning on already settled preferences, repetitive credential warnings or claims of physical-device testing without evidence.
- The user's separate request for feature parity with another ptv repository remains uncompleted; compare features before implementing, not blind code copying.

## Present delivery checkpoint (2026-10-26 UTC)

- Latest fully successful paired release: **v1.1.0 Build 90**, https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.0-b90, workflow https://github.com/mghazalyh/ptv3/actions/runs/40331619688 (Windows 17/17, iOS 22/22; Telegram document #17).
- Latest implemented source version: **v1.1.1**, HEAD f0e095a7a99af3faf340f04774fd987651507dac, Show Details navigation.
- Build #97: https://github.com/mghazalyh/ptv3/actions/runs/40336345197 — Windows 17/17 success; iOS runner canceled, Telegram/publish skipped, overall workflow failure. Windows Actions artifact **PlayTorrio-Windows-v1.1.1-build-97** exists, but **no verified v1.1.1 paired GitHub release or TrollStore IPA** at this checkpoint.
- **Refresh these statuses every time you work; do not perpetuate stale historical values.**

See **handover.md** for full timeline, file map, run history, data contracts and known issues.
