#!/usr/bin/env python3
"""Permanently archive successful signed iOS IPAs as GitHub Releases.

This is independent of Windows success. Re-run safely for an individual native
run or use "all" to backfill still-downloadable historical Actions artifacts.
Never delete an existing Release or its assets; never publish an unsigned IPA.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import zipfile

PATTERN = re.compile(
    r"^PlayTorrio-iOS15-TrollStore-v(\d+\.\d+\.\d+)-build-(\d+)$"
)
ACTIVE_BRANCH = "parity-floating-player-both"


def gh(*args, allow_missing=False):
    proc = subprocess.run(["gh", *args], capture_output=True, text=True)
    if proc.returncode:
        if allow_missing and "HTTP 404" in proc.stderr:
            return None
        raise RuntimeError(
            "GitHub API command failed (" + " ".join(args[:3]) + "): "
            + proc.stderr.strip()[:600]
        )
    return proc.stdout.strip()


def api(repo, path, allow_missing=False):
    body = gh("api", f"repos/{repo}/{path}", allow_missing=allow_missing)
    return json.loads(body) if body is not None else None


def artifact_candidates(repo, run_id):
    if run_id != "all":
        if not run_id.isdigit() or int(run_id) <= 0:
            raise ValueError("A positive workflow run ID or 'all' is required")
        batches = [api(repo, f"actions/runs/{run_id}/artifacts?per_page=100")]
    else:
        batches = []
        # The API returns most recent first. Expired binaries cannot be rescued.
        for page in range(1, 7):
            batch = api(repo, f"actions/artifacts?per_page=100&page={page}")
            batches.append(batch)
            if len(batch.get("artifacts", [])) < 100:
                break
    candidates = {}
    for batch in batches:
        for artifact in batch.get("artifacts", []):
            match = PATTERN.fullmatch(artifact.get("name", ""))
            workflow = artifact.get("workflow_run") or {}
            rid = str(workflow.get("id", ""))
            if match and rid and not artifact.get("expired") and artifact.get("size_in_bytes", 0) > 0:
                if run_id != "all" and rid != run_id:
                    continue
                candidates[(int(match.group(2)), rid)] = (artifact, match.group(1))
    return [candidates[key] for key in sorted(candidates)]


def verified_ios_run(repo, artifact):
    run_id = artifact["workflow_run"]["id"]
    run = api(repo, f"actions/runs/{run_id}")
    if (run.get("head_branch") != ACTIVE_BRANCH
            or run.get("status") != "completed"
            or run.get("head_sha") != artifact["workflow_run"].get("head_sha")):
        raise RuntimeError(f"Unsafe/mismatched workflow metadata for run {run_id}")
    jobs = api(repo, f"actions/runs/{run_id}/jobs?per_page=100").get("jobs", [])
    if not any(job.get("name") == "iOS 15 — build and sign TrollStore IPA"
               and job.get("conclusion") == "success" for job in jobs):
        raise RuntimeError(f"No successful signed iOS job in run {run_id}")
    return run


def asset_is_present(release, name):
    return any(a.get("name") == name and a.get("size", 0) > 0
               for a in release.get("assets", []))


def verify_ipa(ipa):
    if not ipa.is_file() or ipa.stat().st_size < 1_000_000:
        raise RuntimeError("Missing or unexpectedly small signed IPA")
    with zipfile.ZipFile(ipa) as z:
        if z.testzip() is not None:
            raise RuntimeError("Corrupted iOS IPA archive")
        names = set(z.namelist())
        if "Payload/Runner.app/_CodeSignature/CodeResources" not in names:
            raise RuntimeError("Unsigned IPA: CodeResources missing")
        info = plistlib.loads(z.read("Payload/Runner.app/Info.plist"))
        if 2 not in info.get("UIDeviceFamily", []):
            raise RuntimeError("IPA does not support iPad")
        minimum = tuple(int(x) for x in info["MinimumOSVersion"].split("."))
        # 15.0 and 15.0.0 are equivalent.
        major, minor = minimum[0], minimum[1] if len(minimum) > 1 else 0
        if (major, minor) > (15, 0):
            raise RuntimeError("IPA minimum OS newer than iOS 15")


def archive_one(repo, artifact, version):
    run_id = artifact["workflow_run"]["id"]
    number = PATTERN.fullmatch(artifact["name"]).group(2)
    run = verified_ios_run(repo, artifact)
    sha = run["head_sha"]
    tag = f"build-v{version}-b{number}"
    ipa_name = f"PlayTorrio-v{version}-build{number}-iOS15-TrollStore.ipa"
    release = api(repo, f"releases/tags/{tag}", allow_missing=True)
    if release and release.get("target_commitish") != sha:
        raise RuntimeError(f"Release {tag} points to a different source SHA")
    if release and asset_is_present(release, ipa_name):
        print(f"{tag}: signed IPA already permanently retained")
        return False

    with tempfile.TemporaryDirectory(prefix="ptv-ios-archive-") as folder:
        root = Path(folder)
        gh("run", "download", str(run_id), "--repo", repo, "--name",
           artifact["name"], "--dir", str(root))
        downloaded = root / "PlayTorrio-iOS15-TrollStore.ipa"
        verify_ipa(downloaded)
        ipa = root / ipa_name
        downloaded.rename(ipa)
        digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
        checksums = root / "IOS-SHA256SUMS.txt"
        checksums.write_text(f"{digest}  {ipa_name}\n")
        description = (
            f"PlayTorrio v{version} (Build {number}) — signed iOS 15 TrollStore IPA.\n\n"
            f"Source revision: {sha}\n"
            f"Native build: https://github.com/{repo}/actions/runs/{run_id}\n\n"
            "The IPA is verified as an iPad-compatible, ad-hoc-signed archive. "
            "This iOS release is independent of Windows packaging: a Windows "
            "installer will be attached only if the matching Windows build succeeds."
        )
        if release:
            gh("release", "upload", tag, str(ipa), str(checksums), "--repo", repo)
        else:
            gh("release", "create", tag, str(ipa), str(checksums),
               "--repo", repo, "--target", sha, "--title",
               f"PlayTorrio v{version} (Build {number}) — iOS 15",
               "--notes", description, "--latest")
        published = api(repo, f"releases/tags/{tag}")
        if (published.get("target_commitish") != sha
                or not asset_is_present(published, ipa_name)):
            raise RuntimeError(f"Publication verification failed for {tag}")
        print(f"ARCHIVED {tag} sha={sha} size={ipa.stat().st_size} "
              f"sha256={digest} url={published['html_url']}")
    return True


def self_test():
    assert PATTERN.fullmatch("PlayTorrio-iOS15-TrollStore-v1.1.15-build-140")
    assert PATTERN.fullmatch("PlayTorrio-Windows-v1.1.15-build-140") is None
    assert not asset_is_present({"assets": [{"name": "x.ipa", "size": 0}]}, "x.ipa")
    assert asset_is_present({"assets": [{"name": "x.ipa", "size": 10}]}, "x.ipa")
    assert not PATTERN.fullmatch("PlayTorrio-iOS15-TrollStore-v1.1.15-build-140.zip")
    print("iOS release archive self-test passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    repo = os.environ["GITHUB_REPOSITORY"]
    run_id = args.run_id or ""
    candidates = artifact_candidates(repo, run_id)
    if not candidates and run_id != "all":
        raise RuntimeError(f"No unexpired, signed iOS IPA artifact for run {run_id}")
    print(f"iOS archive: found {len(candidates)} downloadable candidate(s)")
    archived = 0
    errors = []
    for artifact, version in candidates:
        try:
            archived += int(archive_one(repo, artifact, version))
        except Exception as exc:
            errors.append(f"{artifact['name']}: {exc}")
            print(f"ERROR: {errors[-1]}")
    print(f"iOS archive: {archived} newly published, {len(errors)} failed")
    if errors:
        raise RuntimeError("; ".join(errors))


if __name__ == "__main__":
    main()
