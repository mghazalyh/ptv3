# CURRENT SESSION HANDOVER — PlayTorrio
**Verified 29 October 2026 (SGT) · READY FOR THE OWNER'S NEXT CHOSEN TASK · No open native release obligation**

**READ THIS FIRST IN EVERY NEW SESSION.** This is the most current, comprehensive operating checkpoint. Historical sections in AGENTS.md, NEXT_SESSION.md, and handover.md contain superseded release numbers, prior open tasks and earlier Windows subtitle-matching logic. Current information below takes precedence; verify live GitHub before further work.

## 1. Repo, branch, owner agreements

- GitHub repo: https://github.com/mghazalyh/ptv3
- **SINGLE default/working branch: parity-floating-player-both**. Windows and iOS are one Flutter/Dart project and player implementation. Never create a separate platform branch/codebase, duplicate player, or Windows-only fork. Native differences go behind platform guards (Swift/Apple Speech is iOS-only, Whisper/FFmpeg Windows-only).
- Work directly in the owner repository with connected GitHub tooling. Do not confuse an old attached document or previous conversational snapshot with latest branch/release state.
- Owner wants concrete implementation, verification and native delivery when a fix/feature is authorized, clear concise status, and Singapore/SGT timestamps. Owner explicitly required feature scope recorded in handover.md BEFORE code changes for the prior task; honor this again when requested.
- When user asks to implement/fix a native feature, normally finish with exactly **one** appropriate native release, unless explicitly "source only" or "do not build." Use an iOS-only release for iOS-only work and a **paired iOS+Windows** release when both requested. Standalone documentation/handover edits do NOT authorize native builds.
- NEVER schedule background releases or duplicate active workflows. Query all GitHub Actions running/queued jobs before any release. Do not start a second release because a Telegram attachment is too large.
- Do not expose private media URLs, auth headers, provider tokens, Telegram credentials or .env. CI completion is not physical-device testing.
- **At the end of this handover task no work is pending**. Wait for the owner's NEXT user-selected feature; do not infer authorization from brainstorming.

## 2. Fresh verified state and installable packages

- Prior to this handover-only docs commit, default branch HEAD: **c576b136679024847d18f1606c16a564b64d0a58** (documentation). This handover commit will move HEAD again; fetch it live. Crucially, the compiled source is not HEAD once docs advance.
- **LATEST PAIRED NATIVE RELEASE: PlayTorrio v1.1.15 Build #149**, published **2026-10-29 20:47:04 SGT**.
- Exact common Windows+iOS native release commit **066bdff6fd0e84e8adfc03e9216fbe5eddcf0133**.
- Native Actions **40873582907**, all required jobs **COMPLETED/SUCCESS**: https://github.com/mghazalyh/ptv3/actions/runs/40873582907
- Final preflight Linux + Windows CI **40872664851**, both passed; subsequent post-commit checks **40873582994** passed.
- Permanent GitHub release: https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.15-b149
- Verified release assets (all four exist and are nonempty):
  - Signed iOS 15 TrollStore IPA **47,618,181 bytes**: https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.15-b149/PlayTorrio-v1.1.15-build149-iOS15-TrollStore.ipa
  - Windows x64 Setup EXE **88,834,843 bytes**: https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.15-b149/PlayTorrio-v1.1.15-build149-Windows-Setup.exe
  - Windows x64 Portable ZIP **122,714,814 bytes**: https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.15-b149/PlayTorrio-v1.1.15-build149-Windows-x64-Portable.zip
  - Checksums: https://github.com/mghazalyh/ptv3/releases/download/build-v1.1.15-b149/SHA256SUMS.txt
- Windows native Flutter executable, Whisper CPU CLI, bundled FFmpeg, portable ZIP and Setup EXE succeeded. Signed iOS 15 IPA / ad hoc TrollStore signature / minimum OS / archive verification succeeded. Published matching release from same commit.
- **TELEGRAM HONESTY:** iOS IPA sent as actual **sendDocument message 76**. Windows Setup EXE exceeds Telegram's bot file size; workflow sent the **permanent GitHub download URL** as **sendMessage 75**. It did **not** send an EXE document. This is an expected link fallback, NOT a reason to rebuild.
- A separate older **iOS-only Apple Speech** release also has numeric Build #149: ios-speech-v1.1.15-run4. Its independent workflow counter and source differ from the newer paired Build #149. Verify commit and tag; never assume a same-number IPA is the same app revision.
- As of the session handover check, GitHub Actions showed **zero queued, in_progress, waiting, requested or pending runs**. This is time-specific, so re-check before future native release requests.
- There is **NO outstanding Build #149 task** and no authorization to trigger additional native workflows solely because this handover is updated.

## 3. Most recently completed owner request: Audio Night Mode + Extra Brightness

Owner explicitly requested (a) an optional globally remembered **Night Mode automatic audio compression** toggle as a **small button in the same in-player control row as Audio Tracks and Subtitles**, and (b) a **video-only extra brightness slider** for dim movies when display hardware brightness is already maxed. Both Windows and iOS; one paired build. A write-ahead requirement was committed into handover.md **BEFORE code edits** (commit **88f397c0859987aaa9bd20a2348409a45483f7e2**). This is fully delivered in paired #149.

**Night Mode implementation**
- Small on/off Night Mode icon on player_transport.dart next to Audio/Subtitles; visible active state; default OFF. Persists per app installation across media, player lifecycles, and app restarts until manually disabled.
- SharedPreferences key **player_global_night_mode**; PlayerSettings.nightModeEnabled ValueNotifier, setNightMode(), applyPictureAudio().
- Native libmpv **af** filter chain: keep **scaletempo2=max-speed=8** for playback-rate behavior and append **lavfi=[acompressor=threshold=0.10:ratio=3:attack=20:release=300:makeup=1.4:knee=2.5]** when enabled. No separate audio engine, microphone or system volume changes.
- Implementation: lib/services/player/player_picture_audio.dart, lib/services/player/player_settings.dart, lib/widgets/player/player_transport.dart, lib/pages/player/player_screen.dart.

**Extra Brightness implementation**
- Compact button in player control row opens lib/widgets/player/player_brightness_menu.dart. Slider **0 (normal) to +80**, live update, numeric level, Reset to zero. Value persists globally (SharedPreferences **player_global_extra_brightness**) across sessions.
- MPV video **brightness** property operates on decoded video pixels, NOT iPad display backlight/Windows physical monitor luminance. High boost can wash out highlights. Value is clamped; playback/app lifecycle reapplies the saved property.
- Tests: test/player_picture_audio_test.dart checks compressor/speed chain, MPV property writes, stored preferences/reload, button position/interaction, slider/reset. Native output on individual devices is not yet tested.

**Prior feature code chain:** 7289a9902a126ab25c45de0e299081d00215f598 (MPV effects/preferences); 20575d05cb9f11ccb42daf4f3d4e83ed2b62865b (player controls/UI); 06754a91a1a73812395b2bcade9c602fc6d97abc (player integration); 43f61e4b4ef908d5ca98be77d7cce410f7e6dcb6 (tests/CI); one paired release-request commit 066bdff6fd0e84e8adfc03e9216fbe5eddcf0133; workflow 40873582907 succeeded. Longer proof at TOP of handover.md. **Do not resurrect the historical OPEN task there; it is CLOSED.**

## 4. Subtitle Auto Sync architecture (already implemented; not a new task)

**Shared matching:** lib/services/player/speech_subtitle_alignment.dart compares timestamped recognized spoken words to existing **external text subtitle cues**. Requires at least two independently consistent matching phrases/cues and a tight offset cluster (max spread ~1.8 seconds). Uses an **absolute subtitle delay offset**, not a playback-rate/stretch transformation. No guess applied when speech is unclear or source unsupported; manual subtitle delay still available.

**iOS:** digital movie-stream audio (NOT microphone or listening to device speaker) -> Apple Speech SFSpeechURLRecognitionRequest in ios/Runner/AppDelegate.swift via guarded iOS channel. lib/services/player/ios_speech_transcriber.dart exports bounded <=55-second excerpt via AVFoundation and optional secondary MPV/WAV extraction (mpv_speech_audio_capture.dart). Offline recognition preferred. Apple network-assisted recognition requires user Allow, which is remembered under SharedPreferences **ios_apple_speech_network_allowed**; user can revoke in Settings -> Apple Speech Online. Subsequent five-minute checks MAY upload a <=55-second excerpt to Apple when on-device speech is unavailable/explicitly routed online; this is accurately disclosed in UI. iOS device permission, audio decoder, internet or speech engine can fail separately. Owner previously confirmed iOS Auto Sync worked on their device, but not all movie sources are verified.

**Windows:** separately packaged CPU **whisper.cpp v1.9.5** / whisper-cli.exe, no microphone, cloud transcription, Python, or GPU requirement. One-time manually authorized English base model **ggml-base.en.bin**, exact **147,964,211 bytes**, SHA-256 verification; cached in app support (not included in installer). Recent Windows Torrentio/MKV audio extraction fix: bundled pinned LGPL FFmpeg via lib/services/player/ffmpeg_speech_audio_capture.dart extracts a seeked, mono 16 kHz s16 WAV from the actual media source; if FFmpeg fails, try the separate MPV decoder in mpv_speech_audio_capture.dart. lib/services/player/windows_whisper_transcriber.dart invokes CLI, reads word-timed JSON, and feeds shared matcher. Never call Apple Speech on Windows. The Build #149 workflow includes native FFmpeg decode and real-English-speech Whisper timestamped JSON tests. Unseekable/DRM/provider-restricted streams can still fail.

**Automatic recurring behavior:** lib/services/player/subtitle_auto_sync_policy.dart and player_screen.dart use a **five-minute Timer.periodic** only while actively playing with a valid source and loaded external text cues; skip pauses, loading, busy recognition, unapproved model/network permission and unsupported platforms. Runs are silent; NO consent dialogs or model downloads from an automatic check; cancel/reset at lifecycle transitions. No constant microphone capture.

**Important limitation:** user reported subtitle drift; five-minute periodic offset rechecks were requested and implemented, but **true linear/nonlinear subtitle timing-rate or frame-rate drift correction is NOT implemented**. It was merely suggested as a possible future feature; do not silently implement without the owner's selection.

## 5. App code map and cross-platform architecture

- One Flutter/Dart codebase with media_kit / libmpv. Main video: **lib/pages/player/player_screen.dart**; watch/source selection: **lib/pages/player/watch_screen.dart**; shared native properties/preferences: **lib/services/player/player_settings.dart**.
- Player widgets: **lib/widgets/player/player_transport.dart**, player_audio_menu.dart, player_subtitle_menu.dart, player_brightness_menu.dart, player_seek_bar.dart, player_top_bar.dart, player_diagnostics_overlay.dart, player_skip_button.dart, text_sync_overlay.dart. Preserve compact controls on iPad/Windows/fullscreen.
- Player logic: lib/services/player/player_picture_audio.dart, ios_speech_transcriber.dart, windows_whisper_transcriber.dart, ffmpeg_speech_audio_capture.dart, mpv_speech_audio_capture.dart, speech_subtitle_alignment.dart, subtitle_auto_sync_platform.dart, subtitle_auto_sync_policy.dart, playback_autoselection.dart, audio_language_priority.dart, paused_http_recovery.dart, skip_segments_service.dart, automatic_skip_policy.dart.
- Subtitle parsing/download/sync: **lib/services/subtitles/**; user content/progress, Stremio compatible addons, stream sources, scraper infrastructure, libtorrent, movies/series, manga, audiobooks and music are in **lib/services/{stream,p2p,subtitles,addon,scraper,continue_watching,my_list,metadata,manga,audiobook,music,download}**. Browse source rather than trusting README; README may be old.
- Existing critical tests: test/player_picture_audio_test.dart, windows_whisper_transcriber_test.dart, ffmpeg_speech_audio_capture_test.dart, mpv_speech_audio_capture_test.dart, ios_speech_network_consent_test.dart, speech_subtitle_alignment_test.dart, subtitle_auto_sync_platform_test.dart, subtitle_auto_sync_policy_test.dart, plus general playback regression tests. Add focused test coverage for each new feature, including persistence and platform behavior.
- Do not replace native media_kit player with parallel audio/video engines for small features. Retain playback speed, subtitles, selected audio track, seek/torrent handling, and player disposal/reinitialization semantics.

## 6. Release/test/delivery runbook — FOLLOW EXACTLY WHEN NEW TASK AUTHORIZES IT

1. FIRST read **CURRENT_SESSION_HANDOVER.md**, the TOP of handover.md and **.github/RELEASE_DELIVERY_POLICY.md**. Verify live branch HEAD, intended source SHA, previous workflow statuses, release assets and any fresh owner device feedback. Don't start a build from history alone.
2. If user selects a new feature/fix, write a clearly identified **OPEN request checkpoint at the top of handover.md BEFORE code** when handover-first was requested (or as prudent for complex changes). Use current branch only. Do not confuse "proposed suggestions" with authorization.
3. Implement with platform guards, update unit/widget/native tests. Existing **.github/workflows/playtorrio-fast-checks.yml** runs Linux Flutter analysis and Windows shared-player smoke tests on code changes. Docs-only changes are excluded. Wait for tests to finish and fix failures; don't ship blindly.
4. Check GitHub Actions **queued/in_progress/waiting/requested** workflow runs for any native build before creating a release. Do NOT launch duplicate/overlapping workflows. Consider separately the iOS-only workflow counters versus paired.
5. On a legitimate release request update **.github/release-notes.txt** first, accurate Telegram-safe notes **<=500 characters**. Then make **ONE deliberate change** to **.github/release-request.txt** for paired iOS/Windows -> **.github/workflows/windows-advanced-discover.yml**. For iOS-only fixes, instead update **.github/ios-speech-release-request.txt** -> **.github/workflows/ios-speech-release.yml**. Never trigger both simultaneously; don't manually dispatch extras for same fix.
6. Verify actual native Windows build + Windows packaged Whisper/FFmpeg, Setup EXE and ZIP; native iOS release compile/signature/minimum iOS 15/IPA archive; both independent Telegram jobs; permanent GitHub Release, checksums and nonempty downloadable assets. On failed jobs inspect logs and recover selectively without recompiling already-successful platform outputs, per release policy.
7. **Telegram size fallback:** document can exceed bot upload limits (Build #149 Windows EXE did). sendMessage with the exact release URL is a valid fallback; describe it honestly rather than claiming an attached EXE. iOS IPA was an attached sendDocument for #149.
8. On success, update top-of-handover and THIS handover with exact SHA, workflows, release assets, Telegram outcomes, tests, unknown device results and any remaining blocker. Include direct downloads and SGT timestamp. CI success != user-device proof. No background promise or automated schedule.

**Sources of truth for release operations:** .github/RELEASE_DELIVERY_POLICY.md; .github/workflows/playtorrio-fast-checks.yml; .github/workflows/windows-advanced-discover.yml; .github/workflows/ios-speech-release.yml. GitHub Actions contains platform-specific native runners, rescue lanes and signing credentials. Do not disclose signing secrets, .env values or user stream URLs.

## 7. Known real-device uncertainties and open questions — NOT unfinished coding requests

- Night Mode subjective compression/voice loudness on owner hardware and connected audio outputs; MPV filter availability across iOS device/output types.
- Extra Brightness visibility on iPad rendering pipeline, real Windows monitor and HDR streams; software brightness does not increase the backlight and may wash out highlights.
- Windows Whisper/FFmpeg access to specific owner torrent/HTTP streams beyond native CI fixtures; iOS Apple Speech recognition/audio sampling and online speech permissions on every source.
- Five-minute periodic Auto Sync uses absolute offset matching; frame-rate mismatch/rate drift between check points is not solved.
- Installing paired Build #149 over a separate older iOS-only Build #149 has **not** been installation-upgrade-tested; independent workflows have distinct numbering.
- Subtitle matching on embedded-image subtitle tracks, live/DRM/restricted/non-English/silent sources may be skipped; preserve fail-safe behavior.
- Telegram Windows upload limit and successful link fallback are expected, NOT a failed release.

## 8. Immediate next-session instructions

- Check live repo HEAD and latest Actions statuses; at this checkpoint **there were no active runs** and **no remaining release obligation**. The current GitHub release to test is the **paired Build #149**, not an older independent iOS-only #149.
- **WAIT FOR USER'S NEW TASK.** Prior optional brainstorm suggestions — intelligent subtitle rate-drift correction, automatic stream failover, speech-verified subtitle selection, sync cache, GPU Whisper, adaptive buffering — were **ideas only**, NOT authorized work.
- Implement only the new request the owner chooses, within the single shared branch, observing the handover-first/release/test/no-duplicate rules.
- Keep response actionable, concise despite comprehensive technical notes, with current SGT timestamp.

**END: Project is handed over in a verified, released, idle state and is ready for any new task the owner chooses.**
