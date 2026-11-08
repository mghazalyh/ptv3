# iPad trial: Xperience and BingeCat personalized catalogs

**Scope:** iOS/iPadOS only. This trial does not add a new player, tracker sync, or AI engine to PlayTorrio. Xperience and BingeCat already generate catalogs as user-specific Stremio addon manifests.

Sources: [Xperience's guide](https://xperience-app.com/guide), [BingeCat](https://bingecat.com/), and the public Stremio addon `manifest.json` protocol.

## Test on iPad

1. Open **Settings → Addons → iPad Personalized Catalogs (Experimental)**.
2. Select **Configure in Safari** for Xperience or BingeCat, sign in and configure a catalog or personalized list on the provider's own website.
3. Copy the private Stremio `https://.../manifest.json` install URL. Never paste provider credentials into PlayTorrio. The link itself may contain a token.
4. Return to PlayTorrio, tap **Import manifest** for that provider and paste the generated HTTPS link.
5. Return to Home to see the provider's movie and TV catalog rows. Use the existing movie/TV details and source picker.
6. To update the **row definitions** after editing the provider's lists, tap the refresh icon on the newly installed provider's Addons card, then reopen Home. List content itself is fetched from the provider when Home loads.

The experiment is opt-in; no new addons or account connections are installed automatically. Existing addon settings are preserved. New personalized imports start with streams, subtitles and general search disabled, but do provide movie/TV catalog content. A manifest with no catalogs or a refresh whose addon ID unexpectedly changes is rejected without replacing the existing installation.

URL requirements: HTTPS; final path segment `manifest.json`; no userinfo, query or fragment. Standard `stremio://` links convert to HTTPS. This is a limitation of PlayTorrio's current generic Stremio base-URL client, not a statement that every provider link uses this exact form.

## Validation limits

The test suite uses mocked manifests for both providers and verifies the existing Home catalog route and refresh failure protection. No private provider URLs, customer credentials or watch history are committed, logged or transmitted to TorriODB. No live private provider manifests or physical iPad behavior have been verified. Compatibility for metadata that lacks standard Stremio IDs is not guaranteed.

The request file `.github/ios-speech-release-request.txt` triggers the existing **iOS-only** signed TrollStore workflow. The release is marked as a prerelease for this trial and the iOS-only build-number offset is raised above the latest documented paired builds, with all workflow assertions updated together. The workflow still runs existing native iOS player tests and includes built-in signing checks. Lightweight Flutter CI may run, but no Windows or PS4 native package is requested. Do not check the new build status; the owner verifies it.
