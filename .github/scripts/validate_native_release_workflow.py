#!/usr/bin/env python3
"""Offline release-graph invariants: test recovery without any native builds."""
from pathlib import Path
import re


WORKFLOW = Path(".github/workflows/windows-advanced-discover.yml")


def check(workflow):
    assert "'.github/release-request.txt'" in workflow
    assert "cancel-in-progress: false" in workflow
    assert workflow.count("steps: &ios_build_steps") == 1
    assert workflow.count("steps: *ios_build_steps") == 2
    assert workflow.count("ios_runner_fallback_guard.py") == 2
    assert workflow.count("continue-on-error: true") >= 1
    assert "if: steps.ios_checkout.outcome == 'failure'" in workflow

    jobs_text = workflow.split("\njobs:\n", 1)[1]
    matches = list(re.finditer(r"(?m)^  ([a-z][a-z0-9-]+):\s*$",
                               jobs_text))
    jobs = {}
    for i, item in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(jobs_text)
        jobs[item.group(1)] = jobs_text[item.end():end]
    required = (
        "windows", "ios15", "ios15-allocation-check", "ios15-rescue-intel",
        "ios15-rescue-allocation-check", "ios15-rescue-arm",
        "telegram-windows", "telegram-ipa", "publish-paired",
        "prune-release-artifacts",
    )
    assert all(name in jobs for name in required)
    assert "runs-on: macos-15-intel" in jobs["ios15"]
    assert "runs-on: macos-26-intel" in jobs["ios15-rescue-intel"]
    assert "runs-on: macos-15" in jobs["ios15-rescue-arm"]
    assert "needs: [windows, ios15]" in jobs["ios15-allocation-check"]
    assert "needs: [windows, ios15-rescue-intel]" in jobs[
        "ios15-rescue-allocation-check"]
    assert "needs: [windows, ios15, ios15-allocation-check]" in jobs[
        "ios15-rescue-intel"]
    assert ("needs: [windows, ios15-rescue-intel, ios15-rescue-allocation-check]"
            in jobs["ios15-rescue-arm"])

    for candidate in ("ios15-allocation-check",
                      "ios15-rescue-allocation-check"):
        body = jobs[candidate]
        assert "always() && !cancelled()" in body
        assert "result == 'cancelled'" in body
        assert "needs.windows.result == 'success'" in body
        assert ("eligible: " + chr(36) + "{{ steps.guard.outputs.eligible }}"
                in body)
    for candidate in ("ios15-rescue-intel", "ios15-rescue-arm"):
        body = jobs[candidate]
        assert "always() && !cancelled()" in body
        assert ".outputs.eligible == 'true'" in body
        assert "steps: *ios_build_steps" in body
    for candidate in ("telegram-ipa", "publish-paired"):
        body = jobs[candidate]
        assert "always() && !cancelled()" in body
        for ios in ("ios15", "ios15-rescue-intel", "ios15-rescue-arm"):
            assert f"needs.{ios}.result == 'success'" in body
        assert "name: PlayTorrio-iOS15-TrollStore-v1.1.15-build-" in body
    assert "needs.windows.result == 'success'" in jobs["publish-paired"]
    assert workflow.count("  telegram-ipa:\n") == 1
    assert workflow.count("  publish-paired:\n") == 1
    assert workflow.count("  windows:\n") == 1
    assert "needs: [publish-paired, telegram-ipa, telegram-windows]" in jobs[
        "prune-release-artifacts"]


if __name__ == "__main__":
    check(WORKFLOW.read_text(encoding="utf-8"))
    print("Paired release and two-stage iOS runner fallback: self-test passed")
