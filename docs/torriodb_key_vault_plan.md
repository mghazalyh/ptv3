# Torriodb — complete cross-device PlayTorrio restore specification

Status: **requirements and security design only**, 2026-10-27 Singapore. No credential, PIN, token, settings snapshot, completed-watch history, or likes database was uploaded in this work unit. The app does **not yet** fully restore all settings/credentials from Torriodb.

## Confirmed identity and existing source of truth

- **Verified GitHub API:** `mghazalyh/torriodb` exists, **private=true**, user can access it, default branch **main**.
- **Verified Torriodb `main` tree:** `playtorrio/watchlist-v1.json` and `playtorrio/continue-watching-v1.json` already exist. Do not accidentally overwrite or migrate these without conflict-aware merge and backups.
- Current app's `GitHubLibraryCloud` already syncs `watchlist-v1.json` (My List) and `GitHubProgressCloud` syncs `continue-watching-v1.json`. The **default** app repo `mghazalyh/ptv3`, branch `library-data`, is a separate public fallback: it is NOT Torriodb. On actual user devices the repo/branch can be configured to Torriodb through **Settings → GitHub Library Sync**. Never silently change an already configured device's source.
- The existing `GitHub Library Sync` form already accepts repository, branch and a GitHub fine-grained PAT, stored in local FlutterSecureStorage. **The current Connect & Sync Now action does NOT restore all API keys, likes, complete watched history or every app setting.** Do not claim that it does.

## Non-negotiable target: ONE connection form, complete restore

The user explicitly wants all useful PlayTorrio data centralized in their **private Torriodb**, so moving to a fresh iPhone/iPad/Windows device requires **only** entering the GitHub Library repository, branch and GitHub access token once, then choosing **Connect & Restore**. The same connection also supports weekly central API-key rotation without entering individual provider keys on every device.

Data families required:

1. **My List/watchlist, saved favorites, liked/hearts status:** retain existing watchlist merge/tombstones; implement separate likes/favorites if these statuses cannot be represented without conflating watchlist and Simkl hearts. Keep original provider history safe; watchlist != liked status.
2. **Continue Watching playback progress:** reuse existing conflict-aware episode/movie progress sync; preserve last watched position, season, episode, device-safe resume.
3. **Completed/watched viewing history:** must persist separately because current Continue Watching logic filters and purges completed (≥90%) entries. Preserve movies marked watched, watched episodes, date/time and explicit user actions. Never infer watched merely from adding a title to My List.
4. **Cross-device app preferences:** discovery filters/saved searches, UI appearance and layout, language and subtitle preferences, playback behaviors, selected addon order and enabled providers, relevant profile user preferences, associated account configuration and provider selections. Apply a **reviewed allow-list** and versioned schema; do not blindly import ephemeral caches, local file paths, hardware-specific player/window settings, downloaded files or the GitHub connection itself.
5. **All user-controlled provider and addon credentials:** TMDB, TVDB v4 and subscriber PIN, debrid/TorBox, Trakt/Simkl auth where exportable and licensed, other configured API keys, addon manifest URLs containing secret installation identifiers. Put them **only in the authenticated encrypted vault**, never in plain settings JSON, committed public app code, CI, logs, or watchlist/history files. Don't upload unrelated OS credentials or refresh tokens when the provider terms prohibit replication.
6. **Consistent multi-device sync state:** first-setup pull on fresh device; explicit Download/Restore and Sync Now; optional low-frequency refresh on app launch/screen return and after a saved configuration/key change; cache and offline behavior. Existing device local configuration stays available if Torriodb is unreachable. Per-file merges or timestamp+revision CAS on remote writes, never last-writer-wins overwrites of fresh remote settings/keys.

Proposed private `Torriodb/main` layout, keeping existing files untouched:
```text
playtorrio/watchlist-v1.json                 # existing / conflict merged
playtorrio/continue-watching-v1.json         # existing / conflict merged
playtorrio/likes-v1.json                     # future structured likes / tombstones
playtorrio/watched-history-v1.json           # future completed shows/episodes
playtorrio/settings-v1.enc.json              # future AEAD encrypted portable settings
playtorrio/credentials-v1.enc.json           # future AEAD encrypted provider/addon secrets
```
Structured JSON names are proposed; they do not yet exist in the repository.

## Single GitHub credential vs encryption: explicit trade-off

- Because the user wants **no second unlock prompt**, a sensible design uses the **same fine-grained GitHub access token entered in GitHub Library settings** for GitHub authentication **and as high-entropy key material** to derive an encryption key using an audited, documented KDF (e.g. HKDF-SHA256) with a separate random per-vault salt, domain-separation label, repository/branch identity. Use audited **AES-256-GCM** with fresh random 96-bit nonces and AEAD associated data binding schema/vault ID. Encryption/decryption happens locally before HTTPS GitHub API transfer; only ciphertext is committed.
- **Same GitHub PAT must be entered on other devices** for a true one-form, end-to-end encrypted restore. Different fine-grained PATs for the same repo are *not* interchangeable vault decryption keys, even if both can access the private repo. Warn clearly on different-token failure; do not silently reset/rewrite an unreadable vault. Offer an optional **recovery phrase/export** if the user wishes to use different GitHub PATs, otherwise re-encrypt while an existing device remains unlocked **before rotating the GitHub PAT**.
- A stolen GitHub PAT would permit both repository access **and local derivation of the vault key**, so token-derived encryption is NOT a second factor. Use repository-scoped least-privilege PAT, store locally in FlutterSecureStorage, do not log it, and disclose this risk in Settings. Private repository permissions still matter. If stronger separation is desired later, require a second passphrase or device-to-device transfer—which conflicts with the one-form requirement. Do not misrepresent encryption as absolute protection from PAT compromise.
- **Never store the GitHub PAT inside the repo**; it is needed to access the repo in the first place. Do not commit provider API keys in cleartext even though Torriodb is private. Never create a GitHub Actions secret or workflow environment variable for these values.
- When GitHub PAT changes, old-vault encryption does **not** remain decryptable from the new PAT; support an authenticated re-key/rotation operation that reads the old vault first, encrypts under new PAT, and atomically writes with expected remote SHA. Keep recoverable backups under explicit user control.

## First-run restore sequence (future app behavior)

1. User opens GitHub Library Sync on a fresh device. Repository defaults to private `mghazalyh/torriodb`, branch defaults to `main` for **new users only**, never rewriting existing saved connection. They enter their GitHub fine-grained PAT once.
2. Validate token permissions and repository privacy by authenticated `GET /repos/{owner}/{repo}`. Require `private=true` for credential sync; for nonprivate repositories only nonsecret legacy My List/Progress functions may run (with a warning).
3. Fetch + merge the existing watchlist and Continue Watching in their current formats, then fetch optional likes and watched-history files. Missing future files are treated as empty, NOT errors that block legacy sync.
4. Fetch encrypted settings/credentials. Derive the vault key from the locally entered **same** PAT (or optional recovery unlock, if implemented); verify authenticated tag; reject corrupt, wrong-key or swapped vaults before applying **anything**. Never default to a fresh empty vault on failure.
5. Preview/merge cross-device settings conservatively and apply allow-listed values; update SharedPreferences and OS secure storage through existing save functions to invalidate TMDB/TVDB and other provider caches. Keep local device-only paths/hardware settings. Automatically reload affected services and UI after successful restore.
6. Show separate statuses `Library synced`, `Progress synced`, `Likes/history synced`, `Settings synced`, `Credentials synced` and explicit warning if a subset fails. **Never say "Everything synced" until every configured family is verified.**

## Updates and conflict handling

- Key changes made from any device upload an entire encrypted credential snapshot through GitHub Contents API using the expected remote blob SHA; on 409/422, refetch, decrypt and merge **per provider + update revision**, never overwrite blindly. Add single-flight/coalescing and retry with capped backoff, no logging secrets.
- Portable preferences and credentials should be **independent encrypted snapshots** so changing theme cannot race weekly TVDB key replacement.
- Likes/watched history must use append/tombstones/merge strategies just as watchlist/progress do; no reset of watched histories on reconnect.
- Allow user to turn off cloud credentials syncing without disabling watchlist/progress. Disconnect keeps local keys and preferences but removes local GitHub PAT if requested.

## Implementation and testing gates

- Inspect and inventory all SharedPreferences and FlutterSecureStorage keys first; explicitly identify API key vs device-only cache. Token handling for externally managed services may need secure refresh.
- Choose an audited Flutter/Dart cross-platform AEAD/KDF library for iOS15 and Windows x64 and pin dependencies; no home-grown encryption. Mock repo private/public checks, auth errors, 404 new files, 409/422 concurrent edits, missing/rotated/different PAT, tag tampering, offline, per-provider cache invalidation, Windows/iOS secure storage behavior.
- Test two-device onboarding from empty local state, weekly TMDB/TVDB key rotation, likes and completed-history merging, changed settings and old/current installs. Rollout should **not** silently migrate legacy cloud watchlists or unencrypted backups.
- No real credentials should ever be supplied in chat or embedded in public handover, tests, screenshots, GitHub workflows, or assistant-generated source.

This file is a **design/requirement checkpoint only**, not a shipped full-sync capability. Current authenticated GitHub Library sync still covers only My List and Continue Watching; all other families require future implementation and paired CI/device verification.
