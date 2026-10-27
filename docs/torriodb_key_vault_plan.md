# Torriodb — editable private JSON and full-device restore

**Design decision confirmed by user: 2026-10-27 SGT.** The user expressly does **not** want the TMDB, TVDB or other provider API keys encrypted in Torriodb: the core workflow is editing one **human-readable JSON file** in their **private GitHub repository** each week when rotating keys, then having PlayTorrio on iOS and Windows sync those updates. Do not implement the previous AES-GCM/HKDF or PAT-derived-encryption design for this requirement. Do not introduce a second vault password or recovery prompt.

**STATUS: design only.** This document does not mean app code already reads or writes the proposed configuration/keys. No actual credentials were requested, transmitted or committed, and no existing Torriodb records were edited in this documentation work unit.

## Verified current repository and functionality

- Repository: `mghazalyh/torriodb`, **private** confirmed via GitHub API, default branch **`main`**. This is separate from public app-code repository `mghazalyh/ptv3`.
- Torriodb currently contains `playtorrio/watchlist-v1.json` and `playtorrio/continue-watching-v1.json`. Keep their existing merge formats and contents intact.
- `GitHubLibraryCloud` and `GitHubProgressCloud` already sync My List and Continue Watching when the device is configured with the correct private repo/branch and GitHub fine-grained access token in **Settings → GitHub Library Sync**.
- **Not yet implemented:** separate liked/favorite states, completed/watched titles and episodes history, syncing general preferences/addons, syncing all provider API keys, a full new-device restore workflow, remote key rotation refresh. Do not tell users it already works.
- The app's legacy default sync location is `mghazalyh/ptv3`/`library-data` (PUBLIC fallback). **Never place credentials there.** New-user defaults should lead explicitly to private Torriodb only after verifying authenticated access; do not override an existing user's chosen repository.

## One connection, full restore

On a fresh iPhone/iPad/Windows device, the user should only need to enter **GitHub repository, branch, and GitHub PAT** under GitHub Library Sync. One **Connect & Restore** action must fetch and apply the following compatible data, then show per-category successes/failures:

1. My List/watchlist and saved titles.
2. Continue Watching resume position, series season/episode and timestamp.
3. Distinct **completed/watched movies and episodes** history (currently excluded/purged from Continue Watching; never equate “saved” with “watched”).
4. Separate **likes/hearts/favorites** and removals, preserving distinct Trakt/Simkl behaviors and not overwriting provider histories.
5. **Portable settings**: Advanced Discover search/filter preferences, appearance, playback/subtitles preferences, addon order and enablement, selected services, and other transferable configuration via reviewed allow-list.
6. **All user-managed API credentials and eligible addon connection details**: TMDB, TVDB API key and optional PIN, TorBox/debrid keys, applicable Trakt/Simkl/app-specific provider credentials, and opt-in addon manifest URLs containing secret tokens. Store exactly in **private Torriodb editable JSON**, never public code or CI.
7. Keep hardware-specific paths, downloads, device caches, OS keychain artifacts and GitHub PAT **device-local**; GitHub PAT must remain local because it is required to access the repository in the first place.

When an external provider's terms restrict exporting or sharing a token, mark that field device-only or handle through the provider's authorized re-login flow rather than quietly breaking its terms.

## Proposed private Torriodb/main layout

```text
playtorrio/watchlist-v1.json            # existing; don't replace
playtorrio/continue-watching-v1.json    # existing; don't replace
playtorrio/likes-v1.json                # future explicit likes, removals, IDs
playtorrio/watched-history-v1.json      # future completed films/episodes
playtorrio/settings-v1.json             # future editable portable settings
playtorrio/api-keys-v1.json             # future EDITABLE PLAINTEXT provider keys
```

Example of the **intended human-editable private JSON**, with placeholders, **not real keys**:

```json
{
  "schemaVersion": 1,
  "updatedAt": "2026-10-27T00:00:00Z",
  "providers": {
    "tmdb": {
      "apiKey": "REPLACE_WITH_TMDB_KEY"
    },
    "tvdb": {
      "apiKey": "REPLACE_WITH_TVDB_KEY",
      "subscriberPin": ""
    },
    "torbox": {
      "apiKey": "REPLACE_WITH_TORBOX_KEY"
    }
  }
}
```

Keep field names stable and document additional providers clearly; validate before import and support empty/remove entries. This file is **intentionally not encrypted**: the user can open it in GitHub's editor and update any key in a single commit. Do not copy tokens into app source code, test fixtures, release assets or handover docs.

## User workflow: update keys once in GitHub

1. Open private `mghazalyh/torriodb` on GitHub; navigate to `playtorrio/api-keys-v1.json`.
2. Use **Edit** to replace/clear any provider key or optional TVDB PIN and commit to `main`. For immediate rotation, revoke the old key at the provider when appropriate.
3. On each connected PlayTorrio device, **Sync Now** refreshes the authoritative Torriodb credentials. Once carefully implemented, an app-start/periodic refresh may update them without manual steps, honoring GitHub rate limits.
4. Validate JSON before changing local keys, then apply through existing provider setters/secure storage, invalidate stale auth tokens/caches, and display per-provider status with key values **never shown in logs, error telemetry or status messages**.
5. **Remote manual edits win** over an outdated device-local copy. Never automatically upload old keys merely because an existing device has not yet synced. App-originated writes must use GitHub blob SHA/conditional-write checks and conflict resolution instead of overwriting a newer GitHub edit.

A device without network must continue using its last known local settings; it should not delete them because Torriodb is temporarily unavailable.

## Explicit security trade-off user accepts

A PRIVATE repo is an access-control boundary, **not encryption**. Everyone with repository access, a compromised GitHub account or token, and any connected app with adequate Contents permission can read these plaintext API keys. **Git history retains prior key values after a rotation**, even when the current file is updated or deleted. Revoking rotated provider keys reduces the usefulness of old versions in that history.

Accordingly, before **any** remote credential read/write:
- Check authenticated repository identity `mghazalyh/torriodb` (or a user-specified allowed private repo) and GitHub API `private: true`, correct branch, and appropriate repo-scoped access token. Refuse plaintext **credential sync** if repo is public or cannot be verified private. Note that this check cannot prevent later repository visibility changes; warn about visibility changes.
- Use TLS, least-privilege repository Contents scopes, OS secure storage for the GitHub PAT, and avoid diagnostic output of credentials or Authorization headers.
- Use content validation and schema versioning, GitHub Contents expected-SHA updates, and failure-safe restore. Do not modify current Torriodb watchlist/progress files when bootstrapping key sync.
- Make credentials sync explicitly visible/configurable so the user knows private JSON is plaintext, not protected by client-side encryption. **No second encryption passphrase and no requirement to enter the same GitHub PAT on different devices.** Any appropriately authorized PAT for that private repo can access the same JSON.

## Implementation plan and acceptance criteria

1. Inventory all device preferences and credentials, identifying portable settings vs machine-only data; implement one reusable `TorriodbSettingsSyncService` with JSON validation, mocked GitHub Contents API and strict authenticated private-repo guard.
2. Implement new-device **Connect & Restore** to reuse existing watchlist/progress sync and additionally import likes, completed history, allow-listed settings and API keys. Apply local provider keys through existing setters, preserving caches/refresh behavior.
3. Implement safe **Sync Now** plus optional lightweight refresh on app startup or resume. GitHub-side manual edits take precedence; stale devices must never upload stale settings/keys unprompted. Preserve conflict-aware watchlist/progress merges.
4. Add native UI under GitHub Library Sync showing last successful sync and family-specific errors, the private repo path for editing keys, and a privacy notice.
5. Test Windows + iOS 15 with mocked private/public repo metadata; first-device vs new-device restoration, manual JSON edit followed by refresh, key rotation and removal, invalid JSON, 401/403/404, offline, 409/422 concurrent edit, rollback if partial import fails, preservation of local keys, likes/watch history, and no accidental credential logging.
6. CI-tested paired signed iOS TrollStore IPA and Windows portable/installer release only after the features meet these checks. Never claim full restoration or new-device readiness before tests and an actual device check.

**Important:** This document is the accepted **unencrypted** design. The previous encryption-dependent recovery/PAT rekey plan is superseded. This checkpoint makes no application-source change or Torriodb database edit.
