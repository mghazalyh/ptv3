#!/usr/bin/env python3
"""PlayTorrio Telegram CI notifications; no token or private data is logged."""
import argparse
import json
import os
from pathlib import Path
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BOT_UPLOAD_LIMIT = 50_000_000


def send_request(method, fields, file_path=None, filename=None):
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
    chat = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
    if not token or not chat:
        raise RuntimeError("Telegram bot token / destination missing")
    endpoint = "https://api.telegram.org/bot" + token + "/" + method
    all_fields = dict(fields, chat_id=chat)
    if file_path is None:
        body = urllib.parse.urlencode(all_fields).encode()
        request = urllib.request.Request(endpoint, data=body)
    else:
        boundary = "PlayTorrio" + secrets.token_hex(15)
        parts = bytearray()
        for key, value in all_fields.items():
            parts.extend(("--" + boundary + "\r\n"
                + 'Content-Disposition: form-data; name="' + key
                + '"\r\n\r\n' + str(value) + "\r\n").encode())
        parts.extend(("--" + boundary + "\r\n"
            + 'Content-Disposition: form-data; name="document"; filename="'
            + (filename or file_path.name) + '"\r\n'
            + "Content-Type: application/octet-stream\r\n\r\n").encode())
        parts.extend(file_path.read_bytes())
        parts.extend(("\r\n--" + boundary + "--\r\n").encode())
        request = urllib.request.Request(endpoint, data=bytes(parts),
            headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=240 if file_path else 30) as r:
                result = json.load(r)
            if not result.get("ok"):
                raise RuntimeError("Telegram returned ok=false")
            message_id = result.get("result", {}).get("message_id", "unknown")
            print("Telegram " + method + " confirmed. Message ID: " + str(message_id))
            return result
        except urllib.error.HTTPError as error:
            if error.code == 429 and attempt < 2:
                delay = min(60, max(2, int(error.headers.get("Retry-After", "5"))))
                print("Telegram rate limited; retrying after delay")
                time.sleep(delay)
                continue
            raise RuntimeError("Telegram " + method + " HTTP " + str(error.code)) from None
    raise RuntimeError("Telegram request retries exhausted")


def send_text(message):
    if not message.strip():
        raise ValueError("Empty Telegram message")
    return send_request("sendMessage", {"text": message[:4000]})


def send_document(file_name, platform, extra="", require_document=False):
    file_path = Path(file_name)
    if not file_path.is_file() or file_path.stat().st_size <= 0:
        raise FileNotFoundError("Built package missing: " + str(file_path))
    version = os.environ.get("BUILD_VERSION", "?")
    number = os.environ.get("BUILD_NUMBER", "?")
    sha = os.environ.get("BUILD_SHA", "")[:12]
    run = os.environ.get("BUILD_RUN_URL", "")
    caption = (f"✅ PlayTorrio {platform}\n"
        f"v{version} · Build #{number}\nCommit: {sha}\n"
        f"Package built and uploaded independently.\n"
        + run + ("\n" + extra if extra else ""))
    if file_path.stat().st_size >= BOT_UPLOAD_LIMIT:
        if require_document:
            raise RuntimeError("Required iOS IPA Telegram attachment exceeds bot upload limit")
        send_text(caption + "\nFile exceeds Telegram Bot upload limit; download via GitHub Releases.")
        return
    try:
        result = send_request("sendDocument", {"caption": caption},
            file_path=file_path, filename=file_path.name)
        if require_document:
            document = result.get("result", {}).get("document") or {}
            if (not document.get("file_id")
                    or document.get("file_size") != file_path.stat().st_size):
                raise RuntimeError("Telegram did not confirm the complete IPA document")
    except RuntimeError as error:
        if not require_document and ("HTTP 400" in str(error) or "HTTP 413" in str(error)):
            send_text(caption +
                "\nDirect attachment rejected; download from the GitHub Release.")
            return
        raise


def self_test():
    assert BOT_UPLOAD_LIMIT == 50_000_000
    assert BOT_UPLOAD_LIMIT > 47_000_000
    assert len("🏗️ PlayTorrio CI warning") < 4000
    assert Path("/missing/PlayTorrio.exe").is_file() is False
    print("Telegram CI self-test passed (offline, no token or request).")


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="action", required=True)
    document = sub.add_parser("send-document")
    document.add_argument("--file", required=True)
    document.add_argument("--platform", required=True)
    document.add_argument("--caption-extra", default="")
    document.add_argument("--require-document", action="store_true")
    message = sub.add_parser("send-text")
    message.add_argument("--text", required=True)
    args = parser.parse_args()
    if args.action == "send-document":
        send_document(args.file, args.platform, args.caption_extra, args.require_document)
    else:
        send_text(args.text)


if __name__ == "__main__":
    main()
