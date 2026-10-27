#!/usr/bin/env python3
"""Independent active-branch GitHub Actions watcher for user Telegram alerts.

Runs on standard Ubuntu GitHub Actions when a release is requested. Watches
the same native release workflow without relying on its success, including
queued/cancelled macOS jobs. Never triggers/restarts/cancels a build.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from telegram_ci import send_text

NATIVE_WORKFLOW = "windows-advanced-discover.yml"
CHECK_EVERY_SECONDS = 60
WAIT_FOR_QUEUE_SECONDS = 12 * 60
MAX_WATCH_SECONDS = 65 * 60
BAD = {"failure", "cancelled", "timed_out", "action_required", "startup_failure"}


def get_api(path):
    token = os.environ["GH_TOKEN"]
    request = urllib.request.Request(
        "https://api.github.com/" + path.lstrip("/"),
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "PlayTorrio-Release-Watchdog",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def choose_run(runs, sha, now):
    # The deliberate release request and watcher push normally share a SHA.
    for run in runs:
        if (run.get("head_sha") == sha and
                run.get("head_branch") == "parity-floating-player-both"):
            return run
    # On first installation of the watcher, attach to an ongoing release.
    for run in runs:
        if (run.get("status") in ("queued", "in_progress", "waiting",
                                 "requested", "pending") and
                run.get("head_branch") == "parity-floating-player-both"):
            return run
    return None


def classify(jobs):
    return {job.get("name", "unknown"): job.get("conclusion") or
            job.get("status", "unknown") for job in jobs}


def describe(jobs):
    return "\n".join("• " + name + ": " + state
                     for name, state in classify(jobs).items())


def self_test():
    now = 0
    x = [
        dict(id=7, head_sha="a", head_branch="parity-floating-player-both",
             status="completed"),
        dict(id=8, head_sha="b", head_branch="parity-floating-player-both",
             status="queued"),
    ]
    assert choose_run(x, "a", now)["id"] == 7
    assert choose_run(x, "anything", now)["id"] == 8
    assert choose_run(x[:1], "anything", now) is None
    assert classify([{"name": "iOS", "conclusion": "cancelled"},
                     {"name": "Windows", "conclusion": "success"}]) == {
                        "iOS": "cancelled", "Windows": "success"}
    assert "cancelled" in describe([{"name": "iOS", "conclusion": "cancelled"}])
    print("Independent build watchdog self-test passed (offline).")


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    initial = time.monotonic()
    run = None
    while time.monotonic() - initial < 240:
        payload = get_api("repos/" + repo + "/actions/workflows/"
                          + NATIVE_WORKFLOW + "/runs?per_page=15")
        run = choose_run(payload.get("workflow_runs", []), sha, time.time())
        if run is not None:
            break
        print("Native release run not yet registered; checking again.")
        time.sleep(20)
    if run is None:
        print("No active or SHA-matching native release; no alert required.")
        return

    run_id = run["id"]
    run_url = run.get("html_url") or (
        f"https://github.com/{repo}/actions/runs/{run_id}")
    print("Watchdog attached to native run", run_id, "attempt",
          run.get("run_attempt"), "without modifying it.")
    queued_notice = False
    issue_notice = False
    last_state = None
    while time.monotonic() - initial < MAX_WATCH_SECONDS:
        run = get_api(f"repos/{repo}/actions/runs/{run_id}")
        payload = get_api(f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100")
        jobs = payload.get("jobs", [])
        statuses = classify(jobs)
        ios = next((job for job in jobs
                    if job.get("name", "").startswith("iOS 15 —")), None)
        age = time.monotonic() - initial
        state = (run.get("status"), run.get("conclusion"),
                 run.get("run_attempt"))
        if state != last_state:
            print("Release state:", state, "job states:", statuses)
            last_state = state
        bad_jobs = [j for j in jobs if j.get("conclusion") in BAD]
        if bad_jobs and not issue_notice:
            send_text("🚨 PlayTorrio build problem\n"
                      f"Build run {run_id}, attempt {run.get('run_attempt')}\n"
                      + describe(jobs) + "\n" + run_url +
                      "\nCheck in with ChatGPT for diagnosis. "
                      "This alert does not cancel or retry the build.")
            issue_notice = True
        if (not queued_notice and ios is not None and
                ios.get("status") == "queued" and
                age >= WAIT_FOR_QUEUE_SECONDS):
            send_text("⏳ PlayTorrio iOS runner delay\n"
                      "The macOS/iOS build has been queued for 12+ minutes. "
                      "Windows may already be complete; no automatic "
                      "cancellation/restart was requested.\n" + run_url)
            queued_notice = True
        if run.get("status") == "completed":
            if run.get("conclusion") in BAD and not issue_notice:
                send_text("🚨 PlayTorrio paired release did not complete\n"
                          f"Outcome: {run.get('conclusion')}\n"
                          + describe(jobs) + "\n" + run_url +
                          "\nCheck in with ChatGPT for repair.")
            elif run.get("conclusion") == "success":
                print("Native release succeeded; per-platform Telegram "
                      "document messages are handled by its jobs.")
            return
        time.sleep(CHECK_EVERY_SECONDS)
    send_text("⚠️ PlayTorrio build monitor timeout\n"
              "The native workflow is still not confirmed successful "
              "after 65 minutes; check job state.\n" + run_url)


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    else:
        main()
