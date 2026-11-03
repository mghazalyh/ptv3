#!/usr/bin/env python3
"""PlayTorrio Telegram CI notifications: release URLs only, never binary uploads."""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

RELEASE_RE = re.compile(
    r"^https://github[.]com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/"
    r"releases/tag/(build-v[0-9]+[.][0-9]+[.][0-9]+-b[0-9]+)$"
)

def send_request(method, fields, file_path=None, filename=None):
    """Explicitly deny all attachment APIs, even for legacy script callers."""
    if method != "sendMessage" or file_path is not None or filename is not None:
        raise RuntimeError("Telegram file uploads disabled: send release links only")
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
    chat = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
    if not token or not chat:
        raise RuntimeError("Telegram bot token / destination missing")
    endpoint = "https://api.telegram.org/bot" + token + "/sendMessage"
    request = urllib.request.Request(
        endpoint, data=urllib.parse.urlencode(dict(fields, chat_id=chat)).encode())
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                result = json.load(response)
            if not result.get("ok"):
                raise RuntimeError("Telegram sendMessage returned ok=false")
            print("Telegram sendMessage confirmed. Message ID: " +
                  str(result.get("result", {}).get("message_id", "unknown")))
            return result
        except urllib.error.HTTPError as error:
            if error.code in (429, 500, 502, 503, 504) and attempt < 2:
                delay = error.headers.get("Retry-After", "")
                delay = min(60, max(2, int(delay) if delay.isdigit()
                                    else 3 * (attempt + 1)))
                print("Telegram text request temporarily unavailable; retrying")
                time.sleep(delay)
                continue
            raise RuntimeError("Telegram sendMessage HTTP " + str(error.code)) from None
        except urllib.error.URLError:
            if attempt < 2:
                print("Telegram text request network error; retrying")
                time.sleep(3 * (attempt + 1))
                continue
            raise RuntimeError("Telegram sendMessage network error") from None
    raise RuntimeError("Telegram message retries exhausted")

def send_text(message):
    if not isinstance(message, str) or not message.strip():
        raise ValueError("Empty Telegram notification")
    if len(message) > 4000:
        raise RuntimeError("Telegram text notification exceeds limit")
    return send_request("sendMessage", {"text": message})

def read_release_highlights(filename):
    if not filename:
        return ""
    notes = Path(filename).read_text(encoding="utf-8").strip()
    if not notes or len(notes) > 500:
        raise RuntimeError("Telegram release notes missing or exceed 500 characters")
    if re.search(r"https?://|github[.]com/|api[.]telegram[.]org|gh[pousr]_[A-Za-z0-9]+",
                 notes, re.I):
        raise RuntimeError("Telegram release notes must contain no links or credentials")
    return notes

def validated_release(release_url, version, number):
    match = RELEASE_RE.fullmatch(release_url)
    if not match:
        raise RuntimeError("Invalid permanent GitHub Release URL")
    owner, repo, tag = match.groups()
    if tag != "build-v" + version + "-b" + number:
        raise RuntimeError("Release tag does not match build number/version")
    expected_repo = os.environ.get("GITHUB_REPOSITORY", "").strip()
    if expected_repo and expected_repo != owner + "/" + repo:
        raise RuntimeError("Release repository does not match workflow repository")
    return release_url

def asset_url(release_url, filename):
    if not RELEASE_RE.fullmatch(release_url):
        raise RuntimeError("Invalid GitHub Release download URL")
    if not filename or "/" in filename or chr(92) in filename:
        raise RuntimeError("Invalid GitHub Release asset filename")
    return release_url.replace("/releases/tag/", "/releases/download/") + "/" + urllib.parse.quote(filename)

def release_link_fallback(caption, reason, release_url=""):
    if not release_url or not RELEASE_RE.fullmatch(release_url):
        raise RuntimeError("Validated permanent GitHub Release URL is required")
    return caption + "\n\n" + reason + "\nGitHub Release: " + release_url

def build_links(platform, version, number, sha, run_url, release_url, notes="", extra=""):
    validated_release(release_url, version, number)
    base = "PlayTorrio-v" + version + "-build" + number
    platform_name = platform.lower()
    if "windows" in platform_name:
        assets = [
            ("Windows Setup EXE", base + "-Windows-Setup.exe"),
            ("Windows portable ZIP", base + "-Windows-x64-Portable.zip"),
            ("SHA256 checksums", "SHA256SUMS.txt"),
        ]
    elif "ios" in platform_name or "trollstore" in platform_name:
        assets = [
            ("Signed iOS 15 TrollStore IPA", base + "-iOS15-TrollStore.ipa"),
            ("SHA256 checksums", "SHA256SUMS.txt"),
        ]
    else:
        raise RuntimeError("Unsupported release platform")
    lines = [
        "✅ PlayTorrio " + platform,
        "v" + version + " · Release Build #" + number,
        "Commit: " + sha[:12],
        "GitHub Release published. Links only: no Telegram attachments.",
        "Release: " + release_url,
    ]
    for label, filename in assets:
        lines.append(label + ": " + asset_url(release_url, filename))
    if run_url:
        if not re.fullmatch(
                r"https://github[.]com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/[0-9]+",
                run_url):
            raise RuntimeError("Invalid GitHub workflow run URL")
        lines.append("Workflow: " + run_url)
    if notes:
        lines.append("What's new / Fixed:\n" + notes)
    if extra:
        lines.append(extra)
    return "\n".join(lines)

def send_release_links(platform, release_notes_file="", extra=""):
    version = os.environ.get("BUILD_VERSION", "").strip()
    number = os.environ.get("BUILD_NUMBER", "").strip()
    sha = os.environ.get("BUILD_SHA", "").strip()
    release_url = os.environ.get("BUILD_RELEASE_URL", "").strip()
    run_url = os.environ.get("BUILD_RUN_URL", "").strip()
    if not re.fullmatch(r"[0-9]+[.][0-9]+[.][0-9]+", version):
        raise RuntimeError("Invalid BUILD_VERSION")
    if not re.fullmatch(r"[0-9]+", number):
        raise RuntimeError("Invalid BUILD_NUMBER")
    if not re.fullmatch(r"[0-9a-fA-F]{40}", sha):
        raise RuntimeError("Invalid BUILD_SHA")
    msg = build_links(platform, version, number, sha, run_url, release_url,
                      read_release_highlights(release_notes_file), extra)
    return send_text(msg)

def self_test():
    url = "https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.15-b177"
    validated_release(url, "1.1.15", "177")
    example = build_links(
        "Windows", "1.1.15", "177", "a" * 40,
        "https://github.com/mghazalyh/ptv3/actions/runs/123", url)
    assert "Windows-Setup.exe" in example
    assert "Windows-x64-Portable.zip" in example
    assert "SHA256SUMS.txt" in example
    ios = build_links("iOS 15 TrollStore", "1.1.15", "177", "a" * 40, "", url)
    assert "iOS15-TrollStore.ipa" in ios
    assert "sendDocument" not in ios
    assert "GitHub Release" in release_link_fallback("Build", "Download", url)
    assert len(read_release_highlights(".github/release-notes.txt")) <= 500
    for invalid in ("https://example.invalid", 
                    "https://github.com/mghazalyh/ptv3/releases/tag/build-v1.1.15-b178"):
        try:
            validated_release(invalid, "1.1.15", "177")
            raise AssertionError("Invalid release link accepted")
        except RuntimeError:
            pass
    try:
        send_request("sendDocument", {"caption": "blocked"})
        raise AssertionError("Binary upload was not blocked")
    except RuntimeError:
        pass
    print("Telegram link-only self-test passed offline without network calls.")

def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="action", required=True)
    links = sub.add_parser("send-release-links")
    links.add_argument("--platform", required=True)
    links.add_argument("--release-notes-file", default="")
    links.add_argument("--caption-extra", default="")
    # Compatibility action. File is deliberately never read or uploaded.
    legacy = sub.add_parser("send-document")
    legacy.add_argument("--file", required=True)
    legacy.add_argument("--platform", required=True)
    legacy.add_argument("--caption-extra", default="")
    legacy.add_argument("--release-notes-file", default="")
    legacy.add_argument("--require-document", action="store_true")
    message = sub.add_parser("send-text")
    message.add_argument("--text", required=True)
    args = parser.parse_args()
    if args.action == "send-text":
        send_text(args.text)
    else:
        if args.action == "send-document":
            print("Telegram attachment delivery disabled; sending GitHub links only.")
        send_release_links(args.platform, args.release_notes_file,
                           args.caption_extra)

if __name__ == "__main__":
    main()
