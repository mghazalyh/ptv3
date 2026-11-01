#!/usr/bin/env python3
"""Prevent a paired iOS release from silently dropping FFmpeg Night Mode filters.

Build #170 shipped the default iOS libmpv because the paired workflow omitted
the compressor-framework preparation present in the iOS-only workflow.
Check BOTH pipelines before any new native build is authorized. This is a
source-only quality gate and never starts packaging or accesses telemetry.
"""
from __future__ import annotations

import argparse
from pathlib import Path

PAIRED = Path(".github/workflows/windows-advanced-discover.yml")
IOS_ONLY = Path(".github/workflows/ios-speech-release.yml")
PREP = Path(".github/scripts/prepare_ios_night_mode_libmpv.py")

PREP_NAME = "- name: Prepare and verify real iOS FFmpeg audio compressor framework"
VERIFY_NAME = "- name: Reverify FFmpeg compressor framework inside BUILT iOS app before signing"

REQUIRED_SEQUENCE = (
    "- name: Setup Flutter dependencies",
    PREP_NAME,
    "- name: Restore iOS TorrServerKit framework",
    "- name: Build unsigned iOS 15 release",
    VERIFY_NAME,
    "- name: Verify minimum iOS 15",
    "- name: Ad hoc sign for TrollStore",
)
PREPARATION_COMMANDS = (
    "python3 .github/scripts/prepare_ios_night_mode_libmpv.py --self-test",
    "python3 .github/scripts/prepare_ios_night_mode_libmpv.py\n",
    "python3 .github/scripts/prepare_ios_night_mode_libmpv.py --verify",
)
VERIFY_COMMANDS = (
    "python3 .github/scripts/prepare_ios_night_mode_libmpv.py --verify",
    "python3 .github/scripts/prepare_ios_night_mode_libmpv.py --verify-app",
)
PINNED_ARCHIVE_SHA = "b6b6458e796b8dea24c7eb827a61ccd3302c6cde435cc600815be19e2005542b"


def require(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


def step_body(text: str, label: str) -> str:
    marker = "      " + label
    require(text.count(marker) == 1, f"Expected one {label!r}")
    start = text.index(marker) + len(marker)
    next_step = text.find("\n      - name:", start)
    if next_step == -1:
        raise AssertionError(f"No subsequent step after {label!r}")
    return text[start:next_step]


def check_workflow(text: str, label: str, anchor: str) -> None:
    require(f"steps: &{anchor}" in text, f"{label}: missing shared runner steps anchor")
    require(f"steps: *{anchor}" in text, f"{label}: backup runner does not reuse native steps")

    positions = []
    for name in REQUIRED_SEQUENCE:
        marker = "      " + name
        require(text.count(marker) == 1, f"{label}: {name} must occur exactly once")
        positions.append(text.index(marker))
    require(positions == sorted(positions), f"{label}: release step order is invalid")

    preparation = step_body(text, PREP_NAME)
    for command in PREPARATION_COMMANDS:
        require(command in preparation,
                f"{label}: missing native filter preparation command {command.strip()}")

    build_step = step_body(text, "- name: Build unsigned iOS 15 release")
    require("flutter build ios --no-pub --release" in build_step,
            f"{label}: Flutter pub get could overwrite prepared native libmpv")

    pre_sign = step_body(text, VERIFY_NAME)
    for command in VERIFY_COMMANDS:
        require(command in pre_sign, f"{label}: missing pre-sign command {command}")

    sign = step_body(text, "- name: Ad hoc sign for TrollStore")
    require("codesign --force --deep --sign -" in sign,
            f"{label}: missing signed iOS TrollStore build step")


def check_script(text: str) -> None:
    require(PINNED_ARCHIVE_SHA in text, "Unexpected pinned iOS libmpv archive checksum")
    for item in ("acompressor", "compand", "alimiter",
                 "def native_filter_check(", "def built_app_filter_check(",
                 "check_filter_binary(matches[0])", 'parser.add_argument("--verify-app"'):
        require(item in text, f"Missing required native binary verifier: {item}")


def self_test(paired: str, ios: str, script: str) -> None:
    check_workflow(paired, "paired", "ios_build_steps")
    check_workflow(ios, "iOS only", "speech_ios_steps")
    check_script(script)

    failures = [
        (paired.replace(PREP_NAME, "- name: OMITTED", 1), ios, script),
        (paired.replace(" --no-pub --release", " --release", 1), ios, script),
        (paired.replace("prepare_ios_night_mode_libmpv.py --verify-app",
                        "prepare_ios_night_mode_libmpv.py --verify", 1), ios, script),
        (paired.replace("steps: *ios_build_steps", "steps: [broken]", 1), ios, script),
        (paired, ios.replace(PREP_NAME, "- name: OMITTED", 1), script),
        (paired, ios.replace("prepare_ios_night_mode_libmpv.py --verify-app",
                             "prepare_ios_night_mode_libmpv.py --verify", 1), script),
        (paired, ios, script.replace(PINNED_ARCHIVE_SHA, "badsha", 1)),
    ]
    for i, (changed_paired, changed_ios, changed_script) in enumerate(failures):
        try:
            check_workflow(changed_paired, "paired", "ios_build_steps")
            check_workflow(changed_ios, "iOS only", "speech_ios_steps")
            check_script(changed_script)
        except AssertionError:
            continue
        raise AssertionError(f"Regression mutation {i + 1} unexpectedly passed")
    print("iOS Night Mode workflow regression mutations: PASSED")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        paired = PAIRED.read_text(encoding="utf-8")
        ios = IOS_ONLY.read_text(encoding="utf-8")
        script = PREP.read_text(encoding="utf-8")
        check_workflow(paired, "paired", "ios_build_steps")
        check_workflow(ios, "iOS only", "speech_ios_steps")
        check_script(script)
        if args.self_test:
            self_test(paired, ios, script)
        print("Both iOS release paths include pinned compressor and BUILT-app pre-sign checks")
        return 0
    except (AssertionError, OSError) as exc:
        print(f"iOS Night Mode release safety FAILED: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
