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

## Active development checkpoint (2026-10-27 SGT)

- **v1.1.4 candidate on `parity-floating-player-both`**: title-details **Similar Content** now shows Movie/Series/Title instead of genre, based on the same provider type evidence as Home. Individual BestSimilar autocomplete checks are capped and cached, no extra TMDB/TVDB requests. Click-through uses each item's own media type. Regression tests updated and already included in Windows+iOS workflow. Release/test status remains pending until CI proves it.
- **Embedded English subtitles first** is the existing preserved policy: embedded forced, then embedded regular, then external auto fallback; manual selection wins. No change to subtitle service behavior.
- **All future meaningful edits or verification MUST update `handover.md` and `NEXT_SESSION.md`**. User specifically reinforced this tradition. Do not announce v1.1.4 download links without completed build/release evidence. Previous working Windows candidate is v1.1.3 Build #120, paired release is v1.1.0 Build #90.

## Historical delivery checkpoint (2026-10-27 SGT)

- Application source is **v1.1.3**, development branch `parity-floating-player-both`, verified application commit **`05ebf6e263e1df9d4a47b8cb187b3cfa81c0ba7e`**. Root `handover.md` is the operational source of truth and must be updated **for every meaningful change or test/delivery status update**, with `NEXT_SESSION.md` kept in sync.
- **Windows Build #120**: [workflow](https://github.com/mghazalyh/ptv3/actions/runs/40361913589) completed Windows **17/17 steps successfully** and generated Windows Actions artifact **PlayTorrio-Windows-v1.1.3-build-120** (ID **12668423291**) with a portable ZIP and installer EXE. The extracted portable ZIP passed integrity testing. **The user reported that everything works with the downloaded Windows portable build**, a user confirmation rather than exhaustive independent device testing.
- The **iOS 15 job was canceled** in Build #120; Telegram IPA and publish jobs were **skipped**, making the paired run **overall failure**. There is **no verified v1.1.3 paired GitHub release or iOS IPA**. The last fully successful paired release is [v1.1.0 Build #90](https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.0-b90), with Windows 17/17, iOS 22/22 and Telegram document.
- Preserve current behavior and prior requirements. All changes in this checkpoint are **documentation only [skip ci]**. Do not rebuild or reset working Windows source merely for documentation. Do not confuse Actions artifacts with release assets.

See **handover.md** for full timeline, file map, run history, data contracts and known issues.
