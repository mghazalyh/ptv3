#!/usr/bin/env python3
"""Fail-closed, read-only guard for bounded macOS runner recovery.

Called only by an explicitly requested paired release. A backup iOS build is
permitted when the named predecessor was CANCELLED before receiving a runner
and before executing a single step. It never retries app/test/signing failures.
The main workflow checks that the Windows job already succeeded.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request


def should_recover(jobs, artifacts, target_job, artifact_name, released_assets):
    """Return true only for exactly one cancelled, never-started iOS job."""
    matches = [j for j in jobs if j.get("name") == target_job]
    if len(matches) != 1:
        return False
    job = matches[0]
    if job.get("status") != "completed" or job.get("conclusion") != "cancelled":
        return False
    if job.get("runner_name") or job.get("runner_id"):
        return False
    if job.get("steps"):
        return False
    if any(a.get("name") == artifact_name and not a.get("expired", False)
           for a in artifacts):
        return False
    if any(name.endswith("-iOS15-TrollStore.ipa") for name in released_assets):
        return False
    return True


def api(path, *, missing_ok=False):
    token = os.environ["GH_TOKEN"]
    base = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
    req = urllib.request.Request(
        base + "/" + path.lstrip("/"),
        headers={"Authorization": "Bearer " + token,
                 "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        if missing_ok and exc.code == 404:
            return None
        raise RuntimeError("GitHub API runner guard failed: HTTP " +
                           str(exc.code)) from None


def self_test():
    name = "iOS 15 — build and sign TrollStore IPA"
    artifact = "PlayTorrio-iOS15-TrollStore-v1.1.15-build-146"
    bare = {"name": name, "status": "completed", "conclusion": "cancelled",
            "runner_name": "", "runner_id": None, "steps": []}
    assert should_recover([bare], [], name, artifact, [])
    assert not should_recover([], [], name, artifact, [])
    assert not should_recover([bare, bare], [], name, artifact, [])
    for mutation in (
        {"status": "in_progress"},
        {"conclusion": "failure"},
        {"conclusion": "success"},
        {"runner_name": "GitHub Actions runner"},
        {"runner_id": 42},
        {"steps": [{"name": "Checkout source", "conclusion": "failure"}]},
    ):
        assert not should_recover([dict(bare, **mutation)], [], name,
                                  artifact, [])
    assert not should_recover([bare], [{"name": artifact}], name, artifact, [])
    assert not should_recover([bare], [], name, artifact,
                              ["PlayTorrio-v1.1.15-build146-iOS15-TrollStore.ipa"])
    assert should_recover([bare], [{"name": "Windows-installer"}], name,
                          artifact, ["Windows Setup"])
    print("iOS runner allocation recovery guard: self-test passed")


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    if sys.argv[1:]:
        raise ValueError("Unexpected arguments")
    repo = os.environ["GITHUB_REPOSITORY"]
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
        raise RuntimeError("Invalid GitHub repository identifier")
    run_id = int(os.environ["GITHUB_RUN_ID"])
    build_no = int(os.environ["GITHUB_RUN_NUMBER"])
    target_job = os.environ["CANDIDATE_JOB_NAME"]
    version = os.environ.get("APP_VERSION", "1.1.15")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError("Invalid app version")
    artifact_name = f"PlayTorrio-iOS15-TrollStore-v{version}-build-{build_no}"
    tag = f"build-v{version}-b{build_no}"

    run = api(f"repos/{repo}/actions/runs/{run_id}")
    if (run.get("run_number") != build_no
            or run.get("head_branch") != "parity-floating-player-both"
            or run.get("head_sha") != os.environ["GITHUB_SHA"]
            or run.get("event") not in ("push", "workflow_dispatch")):
        raise RuntimeError("Not a verified explicit active-branch native release")

    jobs = api(f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100")["jobs"]
    artifacts = api(f"repos/{repo}/actions/runs/{run_id}/artifacts?per_page=100")[
        "artifacts"]
    release = api(f"repos/{repo}/releases/tags/{tag}", missing_ok=True)
    published_assets = [a["name"] for a in (release or {}).get("assets", [])]

    eligible = should_recover(jobs, artifacts, target_job,
                              artifact_name, published_assets)
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write("eligible=" + ("true" if eligible else "false") + "\n")
    print("iOS runner fallback eligibility: " +
          ("YES — previous job cancelled before runner allocation"
           if eligible else "NO — no unsafe/duplicate native retry"))


if __name__ == "__main__":
    main()
