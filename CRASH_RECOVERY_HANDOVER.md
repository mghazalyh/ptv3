# PlayTorrio crash-recovery handover

> **Status: Build #163 delivered, verified, and CLOSED.** This is a ChatGPT/session crash-recovery checkpoint, not evidence of an app crash. Do not trigger a native build just because a new chat begins.

## Repository and authoritative context

- GitHub repo: [mghazalyh/ptv3](https://github.com/mghazalyh/ptv3), branch `parity-floating-player-both`.
- The latest full detailed handover is [handover.md](./handover.md), with an abbreviated summary in [CURRENT_SESSION_HANDOVER.md](./CURRENT_SESSION_HANDOVER.md), release rules in [.github/RELEASE_DELIVERY_POLICY.md](./.github/RELEASE_DELIVERY_POLICY.md), and session entrypoints in [AGENTS.md](./AGENTS.md) and [NEXT_SESSION.md](./NEXT_SESSION.md).
- This file created from branch state `a6a2169a80dfd3f55752bdf9f69be0737750cecc` after release delivery notes were already committed. Only documentation changes are required for this handover.
- Never create a second native build for an already-completed release unless the user explicitly asks after new test results.

## Latest user issue and outcome

On Windows the user selected a Torrentio + Torbox source for *Locke & Key* S01E01. The player displayed a failed-to-open resolver URL and required manual source switching even though more sources were visible. User stated some sources load on the second attempt and requested retry + automatic fallback. They synced private Windows telemetry, and asked to solve the issue. Previous user preference: continue gaming while watching, never recommend stopping the game.

Private `mghazalyh/torriodb` files `playtorrio/diagnostics/windows/player/2026-10-31T14-24-05-400821Z-1.json` and `14-24-35-401144Z-2.json` showed that Windows Build #162 could play a source normally with `d3d11va-copy`, 0 output drops and a healthy ~15-second cache. Later reports `14-25-37-193202Z-3.json` through `14-27-06-638175Z-6.json` captured persistent buffering with no active video decoder. The screenshot displayed an unsuccessful Torrentio/Torbox resolver open. This does **not** prove a Torbox server outage, HTTP status, or general origin instability.

**Implemented source repair** on common Flutter source, Windows platform guarded: Windows direct-HTTP TV episode source failures now retry the same source once, then can try up to four distinct direct-HTTP alternatives for **the same episode**, prioritizing the same addon and quality. A 30-second initial no-progress watchdog detects silent startup failures. Recovery avoids P2P, live, local-file and external sources; de-duplicates failed URLs; serializes native open errors; yields manual source picker after exhaustion; keeps opt-in diagnostics allowlisted and removes signed resolver URLs from affected opening logs/error UI. Source selection, game, audio, subtitles, iOS native behavior and existing renderer remain unchanged.

Key code:
- `lib/services/player/playback_source_recovery.dart` pure bounded recovery policy.
- `lib/pages/player/player_screen.dart` native error/watchdog and retry/fallback orchestration.
- `lib/pages/player/watch_screen.dart` passes available stream candidates from watch list.
- `lib/services/player/windows_playback_telemetry.dart` opt-in `source_retry_requested`, `source_fallback_attempted`, `source_recovery_exhausted`.
- `test/playback_source_recovery_test.dart` source retry, quality priority, bound/exhaustion, no P2P/live/local and de-duplication.
- `.github/workflows/playtorrio-fast-checks.yml` and `.github/workflows/windows-advanced-discover.yml` run new regression tests.

**Final tested application source SHA:** `a64013afef267e235a32ff00f247f198a3a33d91`. Both Linux Flutter analyzer/tests and Windows compatibility succeeded in [fast gate 41210878574](https://github.com/mghazalyh/ptv3/actions/runs/41210878574). Intermediate commits `95eebf...` and `f31e66...` had an analyzer warning (unused stack catch); final SHA fixed it, so do not release intermediate revisions.

## Final release and confirmed delivery

Exactly one native [Build #163 workflow 41211431295](https://github.com/mghazalyh/ptv3/actions/runs/41211431295) was triggered and ended **FULL SUCCESS**. Release-request SHA `4b4a071594d5cc3c8363023483ed13cd633cb92d`; [published Build #163](https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.15-b163), release ID `430000925`, published `2026-10-31T14:57:29Z`, not draft or prerelease. Files and actual GitHub API SHA256 digests were verified:

| Asset | Size, bytes | SHA256 |
| --- | ---: | --- |
| [Windows Setup EXE](https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.15-b163/PlayTorrio-v1.1.15-build163-Windows-Setup.exe) | 110670218 | `9ef3bf02d5a60a0960bdd73acfacc76b880a88e794e03e5d3664e5c044486ec9` |
| [Windows x64 Portable ZIP](https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.15-b163/PlayTorrio-v1.1.15-build163-Windows-x64-Portable.zip) | 154815659 | `605b46906f7b8831b3ad7f15b0ccf87ff8a01ddaca850170afa2fec14f828862` |
| [Signed iOS 15 TrollStore IPA](https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.15-b163/PlayTorrio-v1.1.15-build163-iOS15-TrollStore.ipa) | 47656327 | `a41c5c81f96d033cc59b556a80debfc0006aeda9615c4ec420e972a0735642c9` |
| [SHA256SUMS.txt](https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.15-b163/SHA256SUMS.txt) | 346 | `8421d6cf6bf93c0e223630d6aac943a88f3716327af15ba7c8879bbcc4d9e417` (digest of checksum asset) |

Windows Telegram `sendMessage` release download link **ID 93** succeeded; signed iOS IPA `sendDocument` **ID 94** succeeded. The workflow unexpectedly ran a paired iOS build even though Windows-only was desired: the workflow iOS job uses `!contains(github.event.head_commit.message, '[windows-only]')`; the release-request COMMIT MESSAGE omitted literal `[windows-only]`. Record for *future* Windows-only release requests: include the marker in the commit message. **Do not rerun this successful build.**

## Previous performance fix

Earlier Windows user telemetry Build #161 established sustained MPV presentation drops, Flutter GPU raster stalls and severe reported A/V drift during concurrent game+show. Windows-only [Build #162 release](https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.15-b162) succeeded with an adaptive video texture pressure guard (native → 720p → 540p under sustained pressure) and guarded A/V resync while retaining GPU hardware decoding. User subsequently saw a different source-opening issue, solved in source in Build #163. Previous [paired Build #161](https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.15-b161) is immutable.

## What is and isn't verified; next-session rule

- **Verified:** app source implementation, new automated tests, two OS fast gates, native Windows and signed iOS packages, permanent downloads and digests, Telegram deliveries, release success.
- **Not verified:** actual user PC successfully retrying or falling back after a Torbox open failure in Build #163; no owner on-device feedback was observed after release. Do **not** claim real streaming reliability proved or that every network error is repaired.
- **No pending native build, no pending task.** Wait for the user's actual Build #163 test result before proposing new code, telemetry retrieval or another release.
- On new bug report, examine only NEW uploaded TorriODB telemetry and version info, inspect latest `parity-floating-player-both` branch, preserve user preferences (no stopping games), and follow release policy. Private telemetry must not leak signed URL/token values.
