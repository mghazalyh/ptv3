#!/usr/bin/env python3
"""Post-release artifact housekeeping for PlayTorrio; NEVER delete Releases.

Only delete artifacts when:
  - the newly published release already exists,
  - two newest verified releases are retained,
  - each older artifact has an exact known PlayTorrio naming convention,
  - the matching release has all four published assets,
  - the release target commit matches the artifact's workflow source SHA.
Do not touch unrelated workflows, failure diagnostics or unknown artifacts.
"""
import json
import os
import re
import subprocess
import sys

ARTIFACT = re.compile(
    r"^PlayTorrio-(?:Windows|iOS15-TrollStore)-v(\d+\.\d+\.\d+)-build-(\d+)$"
)
MAX_DELETIONS = 40
MAX_PAGES = 5


def release_tag(artifact):
    match = ARTIFACT.fullmatch(artifact.get("name", ""))
    if match is None:
        return None
    return f"build-v{match.group(1)}-b{match.group(2)}"


def fully_published(release):
    if release.get("draft") or release.get("prerelease"):
        return False
    tag = release.get("tag_name", "")
    match = re.fullmatch(r"build-v(\d+\.\d+\.\d+)-b(\d+)", tag)
    if match is None:
        return False
    stem = f"PlayTorrio-v{match.group(1)}-build{match.group(2)}"
    names = {
        entry["name"] for entry in release.get("assets", [])
        if entry.get("size", 0) > 0
    }
    return {
        stem + "-iOS15-TrollStore.ipa",
        stem + "-Windows-Setup.exe",
        stem + "-Windows-x64-Portable.zip",
        "SHA256SUMS.txt",
    }.issubset(names) and bool(release.get("target_commitish"))


def candidates(artifacts, releases, current_run):
    published = {
        release["tag_name"]: release
        for release in releases if fully_published(release)
    }
    newest = sorted(published.values(),
                    key=lambda release: release.get("published_at") or "",
                    reverse=True)
    if not newest or str(current_run) not in {
        str(a.get("workflow_run", {}).get("id", ""))
        for a in artifacts if release_tag(a) == newest[0]["tag_name"]
    }:
        # Conservative: don't delete unless the newest release belongs
        # to THIS just-verified workflow run.
        return []
    protected = {release["tag_name"] for release in newest[:2]}
    selected = []
    for artifact in artifacts:
        tag = release_tag(artifact)
        release = published.get(tag)
        if not release or tag in protected or artifact.get("expired"):
            continue
        workflow_run = artifact.get("workflow_run") or {}
        if workflow_run.get("head_sha") != release.get("target_commitish"):
            continue
        if str(workflow_run.get("id")) == str(current_run):
            continue
        selected.append(artifact["id"])
    return selected[:MAX_DELETIONS]


def api(path, *, delete=False):
    arguments = ["gh", "api"]
    if delete:
        arguments += ["-X", "DELETE"]
    arguments.append(path)
    output = subprocess.run(arguments, capture_output=True, text=True, check=True)
    return {} if delete else json.loads(output.stdout)


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    run_id = os.environ["GITHUB_RUN_ID"]
    version = os.environ.get("APP_VERSION", "1.1.13")
    number = os.environ["GITHUB_RUN_NUMBER"]
    current_tag = f"build-v{version}-b{number}"
    expected = api(f"repos/{repo}/releases/tags/{current_tag}")
    if not fully_published(expected):
        raise RuntimeError("Current release is incomplete; cleanup skipped")
    releases = api(f"repos/{repo}/releases?per_page=100")
    artifacts = []
    for page in range(1, MAX_PAGES + 1):
        result = api(f"repos/{repo}/actions/artifacts?per_page=100&page={page}")
        batch = result.get("artifacts", [])
        artifacts.extend(batch)
        if len(batch) < 100:
            break
    chosen = candidates(artifacts, releases, run_id)
    print(f"PlayTorrio cleanup: {len(chosen)} older, release-verified "
          f"artifact(s) eligible; preserving the two newest releases.")
    for artifact_id in chosen:
        api(f"repos/{repo}/actions/artifacts/{artifact_id}", delete=True)
        print(f"Deleted redundant Actions artifact ID {artifact_id}")
    print("Published GitHub Releases and all other artifacts left untouched.")


def self_test():
    def release(tag, sha, ts):
        ver, run = re.fullmatch(r"build-v(.+)-b(\d+)", tag).groups()
        stem = f"PlayTorrio-v{ver}-build{run}"
        return dict(tag_name=tag, target_commitish=sha, published_at=ts,
                    draft=False, prerelease=False, assets=[
                        dict(name=stem + suffix, size=50)
                        for suffix in ("-iOS15-TrollStore.ipa",
                            "-Windows-Setup.exe", "-Windows-x64-Portable.zip")
                    ] + [dict(name="SHA256SUMS.txt", size=370)])
    releases = [release(f"build-v1.1.13-b{n}", f"sha{n}",
                        f"2026-10-{n-100:02d}T00:00:00Z")
                for n in (137, 136, 135)]
    artifacts = []
    for n in (137, 136, 135):
        for platform in ("Windows", "iOS15-TrollStore"):
            artifacts.append(dict(id=n * 10 + len(artifacts),
                name=f"PlayTorrio-{platform}-v1.1.13-build-{n}",
                workflow_run=dict(id=n, head_sha=f"sha{n}")))
    # Keep current and previous, delete only two older release-verified files.
    assert len(candidates(artifacts, releases, 137)) == 2
    # A mismatched SHA cannot lead to deletion.
    artifacts[-1]["workflow_run"]["head_sha"] = "unrelated"
    assert len(candidates(artifacts, releases, 137)) == 1
    # No published release or missing current artifacts means no deletion.
    assert candidates(artifacts, releases[:1], 137) == []
    assert release_tag(dict(name="other-workflow-output")) is None
    print("Pruning policy self-test passed: two-release safety, SHA match, "
          "published assets, no unrelated artifacts.")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    else:
        main()
