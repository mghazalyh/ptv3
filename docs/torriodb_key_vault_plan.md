# Torriodb API key vault — preparation (no credentials stored)

Status: **design only**, 2026-10-27. No app uploads, private databases,
credentials, repo secrets or GitHub Actions environment were changed as part
of this feature. No API keys or tokens were requested in chat or added here.

## User goal
Change rotating provider keys in **one private Torriodb location** once per
week and have PlayTorrio Windows and iOS pick up the updates. Supported
initial families: TMDB v3 key or v4 token, TVDB v4 key and optional
subscriber PIN; later explicitly approved providers only. Maintain existing
device-local credentials until migration is fully tested.

## Important security properties
1. **Private repository is not sufficient by itself.** Verify Torriodb is
   genuinely private, the authenticated GitHub token has least-privilege
   Contents read/write only on that repository, and the network transport is
   HTTPS. Never use the default public ptv3 repository or its library-data
   branch for secrets. If Torriodb privacy cannot be verified, hard-fail and
   keep keys local.
2. Store **only client-encrypted ciphertext** in the remote private database.
   Use modern authenticated encryption (AES-256-GCM or equivalent), with a
   random nonce per update and a locally controlled encryption secret,
   never committed to the repository or saved in the same JSON. Choose and
   document an audited cross-platform KDF with unique random salt if a
   passphrase is used. A device needs the unlock secret independently.
   The authenticated encryption additional data should bind to the schema
   version and user/vault ID to detect swapped blobs.
3. **Do not put the GitHub personal access token in its own encrypted vault**:
   clients need their locally stored fine-grained GitHub token to read the
   remote file. A private read-only token is preferable for devices that
   never edit. Use existing FlutterSecureStorage for access tokens and the
   local decrypted cache.
4. Support explicit **Upload/Replace Keys**, **Download/Sync Keys**,
   **Remove Remote Keys**, **Lock Vault**, and safe **Rotate Encryption
   Secret** actions. Never automatically overwrite keys from a stale
   device. Check document version/ETag or Git blob SHA before writes and
   show a conflict-resolution screen. Do not log values, ciphertext-bearing
   request URLs, bearer headers, PIN or decrypted fields.
5. **Weekly rotation:** type or paste a new key in one Settings screen,
   validate its format when possible without credential leaks, encrypt it,
   commit as one update to the private vault. Other devices explicitly sync
   (or, later, poll at a conservative interval if enabled), verify the tag,
   update on-device secure storage and invalidate provider caches/tokens
   before use.
6. Distinguish TVDB subscriber PIN, TMDB API read token, movie-provider
   tokens, addon manifests that contain secrets; never unintentionally back
   up configured Torrentio URL/debrid key to the vault without approval.
7. Privacy/access: token compromise or GitHub account access still creates
   risk; encryption limits contents exposure but cannot make it impossible.
   Document license rules for storing/distributing third-party API keys,
   especially if a credential is user-bound or has seat restrictions.

## Proposed encrypted record structure (example, *not* live keys)

```json
{
  "schemaVersion": 1,
  "vaultId": "<opaque random identifier>",
  "revision": 1,
  "updatedAt": "<ISO8601 timestamp>",
  "algorithm": "AES-256-GCM",
  "kdf": "<approved implementation and parameters>",
  "saltBase64": "<random salt>",
  "nonceBase64": "<random nonce>",
  "ciphertextBase64": "<ciphertext and authenticated tag>"
}
```

The decrypted data contains a versioned map of explicitly opted-in providers,
not library/watchlist/progress data. A remote JSON document contains zero
plaintext provider keys, subscriber PINs or PATs.

## Prerequisites for implementation
- Confirm actual Torriodb repository identity, private status, and current
  access/authentication architecture on the user's device. The current source
  has **GitHubLibraryCloud.defaultRepo = mghazalyh/ptv3**, and its Settings UI
  explicitly warns that default repository is PUBLIC. Do not assume the
  private vault is configured just because library sync exists.
- Select a supported audited Flutter crypto library and migration plan that
  works on **iOS 15 and Windows x64**. Do not invent custom crypto.
- Add a new `TorriodbKeyVaultService` and one Settings screen with
  explicit opt-in. Keep legacy local keys as fallback until successful,
  authenticated and encrypted sync is verified on both devices.
- Test mocked private/404/403/conflict/wrong passphrase/replayed nonce,
  corrupted ciphertext, GitHub rate limits, offline, two-device rotation,
  privacy-safe logs, key removal, and no regression to movie/TV/stream logic.
- Verify repository is private before the *first* outbound key write.

This document makes the single-place key rotation feature ready for a
separate security-reviewed implementation; it does **not** enable storage
or imply any user's actual keys have been uploaded.
