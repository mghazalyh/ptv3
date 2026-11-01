#!/usr/bin/env python3
"""Monitor exactly one owner-requested iOS-only release and notify Telegram.

This process runs within GitHub Actions, never launches or retries native builds.
It transmits only workflow status codes, run URL, and source revision.
"""
import json
import os
import sys
import time
import urllib.request
from telegram_ci import send_text

WORKFLOW = "ios-speech-release.yml"
BRANCH = "parity-floating-player-both"
POLL_SECONDS = 180
HEARTBEAT_SECONDS = 900
MAX_SECONDS = 4 * 3600
FAILED = {"failure", "cancelled", "timed_out", "startup_failure", "action_required"}


def github_api(path):
    request = urllib.request.Request(
        "https://api.github.com/" + path.lstrip("/"),
        headers={
            "Authorization": "Bearer " + os.environ["GH_TOKEN"],
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "PlayTorrio-iOS-Only-Notifier",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def select_run(runs, source_sha):
    """Match a release request first; allow standalone notifier repair to attach
    only to one currently active iOS release on the same shared branch."""
    candidates = [
        run for run in runs
        if run.get("head_branch") == BRANCH
        and str(run.get("path") or "").endswith("/" + WORKFLOW)
    ]
    for run in candidates:
        if run.get("head_sha") == source_sha:
            return run
    active = [
        run for run in candidates
        if run.get("status") in ("queued", "in_progress", "waiting", "pending")
    ]
    return active[0] if len(active) == 1 else None


def state_counts(jobs):
    counts = {"queued": 0, "in_progress": 0, "success": 0,
              "failure": 0, "cancelled": 0, "skipped": 0, "other": 0}
    for job in jobs:
        state = job.get("conclusion") or job.get("status") or "other"
        key = state if state in counts else "other"
        counts[key] += 1
    return " ".join(f"{key}={value}" for key, value in counts.items() if value)


def safe_notify(text):
    try:
        send_text(text)
        return True
    except Exception as error:
        print("Telegram notification failed:", type(error).__name__, flush=True)
        return False


def self_test():
    runs = [
        {"id": 1, "head_sha": "a", "head_branch": BRANCH,
         "path": ".github/workflows/" + WORKFLOW},
        {"id": 2, "head_sha": "b", "head_branch": BRANCH,
         "path": ".github/workflows/" + WORKFLOW},
    ]
    assert select_run(runs, "a")["id"] == 1
    assert select_run(runs, "notfound") is None
    assert select_run(runs[:1], "b") is None
    assert "failure=1" in state_counts([{"conclusion": "failure"}])
    assert "queued=1" in state_counts([{"status": "queued"}])
    print("iOS-only status notifier self-test passed", flush=True)


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    started = time.monotonic()
    run = None
    while time.monotonic() - started < 300:
        try:
            result = github_api(
                f"repos/{repo}/actions/workflows/{WORKFLOW}/runs?per_page=35"
            )
            run = select_run(result.get("workflow_runs", []), sha)
            if run:
                break
        except Exception as error:
            print("Waiting for matching workflow:", type(error).__name__, flush=True)
        time.sleep(20)

    if run is None:
        safe_notify(
            "⚠️ PlayTorrio iOS-only release request: GitHub run not found "
            "within 5 minutes. Check Actions. No duplicate build requested. "
            f"https://github.com/{repo}/actions"
        )
        return

    run_id = run["id"]
    url = f"https://github.com/{repo}/actions/runs/{run_id}"
    safe_notify(
        "📲 PlayTorrio iOS-only build requested. "
        "Native release and signing are not yet verified. "
        "GitHub will send status every 15 minutes and alert on failures. "
        "No Windows build requested.\n" + url
    )
    last_progress = time.monotonic()
    warned = set()
    api_errors = 0

    while time.monotonic() - started < MAX_SECONDS:
        try:
            current = github_api(f"repos/{repo}/actions/runs/{run_id}")
            jobs_response = github_api(
                f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100"
            )
            jobs = jobs_response.get("jobs", [])
            api_errors = 0
        except Exception as error:
            api_errors += 1
            print("iOS release status read failed:", type(error).__name__, flush=True)
            if api_errors == 3:
                safe_notify("⚠️ PlayTorrio iOS build notifier cannot read GitHub "
                            "status. The build has not been retriggered.\n" + url)
            time.sleep(POLL_SECONDS)
            continue

        for job in jobs:
            conclusion = job.get("conclusion")
            job_id = job.get("id")
            if conclusion in FAILED and job_id not in warned:
                warned.add(job_id)
                label = job.get("name") or "unknown job"
                safe_notify(
                    f"⚠️ PlayTorrio iOS workflow job {label}: {conclusion}. "
                    "Other fallback/delivery jobs may still complete. "
                    "No automatic retrigger.\n" + url
                )

        if current.get("status") == "completed":
            outcome = current.get("conclusion") or "unknown"
            if outcome == "success":
                safe_notify(
                    "✅ PlayTorrio iOS-only workflow SUCCESS, including "
                    "GitHub release publication and Telegram delivery. "
                    "Check the published IPA checksum before installation.\n" + url
                )
            else:
                safe_notify(
                    f"🚨 PlayTorrio iOS-only workflow finished: {outcome}. "
                    "Check failed job. No duplicate native build launched.\n" + url
                )
            return

        if time.monotonic() - last_progress >= HEARTBEAT_SECONDS:
            last_progress = time.monotonic()
            safe_notify(
                "⏳ PlayTorrio iOS-only release still running. "
                "GitHub job states: " + state_counts(jobs)
                + ". No duplicate build requested.\n" + url
            )
        time.sleep(POLL_SECONDS)

    safe_notify(
        "⚠️ PlayTorrio iOS-only status monitor reached its 4-hour limit. "
        "Build outcome is unknown; inspect GitHub Actions. "
        "No automatic retrigger.\n" + url
    )


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    else:
        main()
