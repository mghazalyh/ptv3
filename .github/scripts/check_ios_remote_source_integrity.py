#!/usr/bin/env python3
"""Fail quickly when a remote-control patch damages Dart file structure.

This is a fast structural guard, not a Dart parser. CI must ALSO run Flutter
analysis and tests before compiling, signing or publishing the iOS IPA.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]
FILES = {
    "lib/services/remote/github_diagnostic_control.dart": {
        "class GithubDiagnosticControl": 1,
        "Future<void> publishVisualFile(": 1,
        "Future<void> publishMatrixFile(": 1,
        "Future<void> publishJournalFile(": 1,
        "Future<void> publishJournalFile(": 1,
        "Future<void> _persistPending(": 1,
        "Future<void> pollNow(": 1,
        "void dispose()": 1,
    },
    "lib/services/remote/ios_remote_live_visual_scan.dart": {
        "class IosRemoteLiveVisualScan": 1,
        "Future<Map<String, Object?>> start(": 1,
        "Future<void> _execute(": 1,
    },
    "lib/services/remote/ios_remote_live_frame_probe.dart": {
        "abstract final class IosRemoteLiveFrameProbe": 1,
        "static Future<LiveNativeSourceResult> probe(": 1,
    },
}


def syntax_delimiters(text: str) -> None:
    """Validate lexical quotes/comments and balanced (), [] and {}."""
    stack: list[tuple[str, int]] = []
    pairs = {")": "(", "]": "[", "}": "{"}
    i = 0
    line = 1
    length = len(text)
    while i < length:
        char = text[i]
        nxt = text[i + 1] if i + 1 < length else ""
        if char == "\n":
            line += 1
            i += 1
            continue
        if char == "/" and nxt == "/":
            i += 2
            while i < length and text[i] != "\n":
                i += 1
            continue
        if char == "/" and nxt == "*":
            level = 1
            i += 2
            while i < length and level:
                if text[i:i + 2] == "/*":
                    level += 1
                    i += 2
                elif text[i:i + 2] == "*/":
                    level -= 1
                    i += 2
                else:
                    if text[i] == "\n":
                        line += 1
                    i += 1
            if level:
                raise ValueError(f"unterminated block comment at line {line}")
            continue
        if char in ("'", '"'):
            quote = char
            raw = i > 0 and text[i - 1] in ("r", "R") and (
                i < 2 or not (text[i - 2].isalnum() or text[i - 2] == "_")
            )
            triple = text[i:i + 3] == quote * 3
            width = 3 if triple else 1
            i += width
            closed = False
            while i < length:
                if text[i] == "\n":
                    line += 1
                if not raw and text[i] == "\\":
                    i += 2
                    continue
                if text[i:i + width] == quote * width:
                    i += width
                    closed = True
                    break
                i += 1
            if not closed:
                raise ValueError(f"unterminated string at line {line}")
            continue
        if char in "([{":
            stack.append((char, line))
        elif char in ")]}":
            if not stack or stack[-1][0] != pairs[char]:
                raise ValueError(f"mismatched delimiter {char!r} at line {line}")
            stack.pop()
        i += 1
    if stack:
        raise ValueError(f"unclosed delimiter {stack[-1][0]!r} at line {stack[-1][1]}")


def check() -> None:
    for relative, needles in FILES.items():
        file = ROOT / relative
        text = file.read_text(encoding="utf-8")
        if not text.rstrip().endswith("}"):
            raise ValueError(f"{relative}: unexpected content after Dart class")
        for needle, expected in needles.items():
            found = text.count(needle)
            if found != expected:
                raise ValueError(
                    f"{relative}: expected {expected} instance(s) of {needle!r}, "
                    f"found {found}"
                )
        syntax_delimiters(text)
        print(f"PASS {relative}: unique methods and balanced Dart delimiters")
    control = (ROOT / "lib/services/remote/github_diagnostic_control.dart").read_text(
        encoding="utf-8"
    )
    if not re.search(
        r"publishVisualFile\([\s\S]*?\$root/visual/\$_deviceId/\$runId/\$key\.json",
        control,
    ):
        raise ValueError("Visual upload path or method missing")
    print("PASS remote visual evidence publication guard")


if __name__ == "__main__":
    try:
        check()
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"FAIL iOS remote source structural guard: {exc}", file=sys.stderr)
        raise SystemExit(1)
