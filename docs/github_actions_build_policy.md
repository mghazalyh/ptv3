# PlayTorrio GitHub Actions build policy

**Reason:** frequent edits previously started full Windows + macOS builds on
*every branch push* and cancelled already-running native work. This wasted
computing resources and produced unnecessary retained build packages. Source
and workflow documentation is in root handover.md.

## Standard edits

Push application changes to `parity-floating-player-both`. A Linux-only
`playtorrio-fast-checks.yml` runs Flutter static checks and key regressions.
Documentation-only commits and release request edits are ignored by this quick
gate. Nothing builds a new Windows EXE or signed iOS IPA automatically from
ordinary pushes, nor from `main` mirrors.

## Deliberate matched release

On `parity-floating-player-both`, **create or modify only**
`.github/release-request.txt`, containing the proposed version, source SHA,
and reason for the release. Changing that file starts
`.github/workflows/windows-advanced-discover.yml` on the active branch.
Alternatively, dispatch that workflow manually on that branch when supported
by the GitHub Actions UI. Do not run release builds on divergent `main`.

**Important:** Only update `release-request.txt` AFTER the quick gate for
the app source has succeeded; include the tested source SHA in the request.
The request change itself becomes part of the release source commit, so all
native packages remain matched to the requested source. The native workflow
runs its full platform tests again, then publishes iOS/Windows from a single
matching commit and only after both succeed. It no longer cancels an expensive
in-progress build simply because another push occurred. Avoid overlapping
release requests: queued builds can still be wasteful.

Do not mistake a green quick gate for verified native installers or an IPA.

## Artifact retention and cleanup

New upload-artifact archives expire after **3 days** instead of 90. GitHub
Releases remain available separately (IPA, Windows EXE/ZIP, SHA256SUMS).
After a successful paired release and Telegram step, the optional clean-up
job attempts to delete only older workflow artifacts that have a matching
fully published GitHub Release with verified asset names/sizes and matching
source SHA; the two newest verified releases are protected. The pruning job
cannot alter GitHub Release assets, unknown artifacts or unrelated workflows.
If GitHub denies artifact deletion, cleanup reports a warning but does not
falsely invalidate the already published app release. Existing artifacts are
eligible only on a later successful release; there is no immediate destructive
cleanup from this workflow-only change.

## Billing

The owner's observed GitHub billing shows gross $41, discounts $41, apparent
net $0; actual account billing must be checked in GitHub Billing. Public
repositories on standard GitHub-hosted runners receive usage discounts.
Settings > Billing and licensing > Budgets and alerts provides included
usage alerts and optional budget limits. A restrictive hard-stop budget can
block workflows; avoid setting a zero hard-stop without understanding that.
