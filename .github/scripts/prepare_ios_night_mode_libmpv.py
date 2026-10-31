#!/usr/bin/env python3
"""Pin the actual iOS media-kit FFmpeg filter-capable libmpv binary.

The upstream "default" and "full" profiles omit acompressor, compand
and alimiter. "encodersgpl" explicitly enables all FFmpeg filters.
Only the iOS CocoaPods package is patched, not the shared Flutter player
or native Windows packaging. Fail closed on version or SHA drift.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlparse

VERSION = "0.6.8"
DEFAULT_SHA256 = "d428641cc6c100de8234eae04e229966e46949eb73fcabd526a008a02e9bf968"
FILTER_SHA256 = "b6b6458e796b8dea24c7eb827a61ccd3302c6cde435cc600815be19e2005542b"
DEFAULT_ARCHIVE = "libmpv-xcframeworks_${MPV_XCFRAMEWORKS_VERSION}_ios-universal-video-default.tar.gz"
FILTER_ARCHIVE = "libmpv-xcframeworks_${MPV_XCFRAMEWORKS_VERSION}_ios-universal-video-encodersgpl.tar.gz"
PACKAGE_NAME = "media_kit_libs_ios_video"
REQUIRED_FILTERS = ("acompressor", "compand", "alimiter")


def find_ios_package(package_config: Path) -> Path:
    config = json.loads(package_config.read_text(encoding="utf-8"))
    matches = [item for item in config.get("packages", [])
               if item.get("name") == PACKAGE_NAME]
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one {PACKAGE_NAME} in {package_config}")
    root_uri = matches[0].get("rootUri")
    if not isinstance(root_uri, str) or not root_uri:
        raise RuntimeError("Missing iOS package rootUri")
    parsed = urlparse(root_uri)
    if parsed.scheme == "file":
        root = Path(unquote(parsed.path))
    elif parsed.scheme == "":
        root = package_config.parent / unquote(root_uri)
    else:
        raise RuntimeError(f"Unsupported package URI scheme: {parsed.scheme}")
    package = root.resolve(strict=True)
    if package.name != PACKAGE_NAME:
        raise RuntimeError(f"Unexpected package directory: {package}")
    return package


def patch_makefile(value: str) -> str:
    if f"MPV_XCFRAMEWORKS_VERSION={VERSION}" not in value:
        raise RuntimeError("Unexpected upstream libmpv version; refusing unpinned patch")
    old_digest = "MPV_XCFRAMEWORKS_SHA256SUM=" + DEFAULT_SHA256
    new_digest = "MPV_XCFRAMEWORKS_SHA256SUM=" + FILTER_SHA256
    if old_digest in value and DEFAULT_ARCHIVE in value:
        return value.replace(old_digest, new_digest).replace(DEFAULT_ARCHIVE, FILTER_ARCHIVE)
    if new_digest in value and FILTER_ARCHIVE in value and DEFAULT_ARCHIVE not in value:
        return value
    raise RuntimeError("Unknown iOS libmpv Makefile; refusing unsafe replacement")


def prepare(package: Path) -> Path:
    makefile = package / "ios" / "Makefile"
    original = makefile.read_text(encoding="utf-8")
    updated = patch_makefile(original)
    if updated != original:
        makefile.write_text(updated, encoding="utf-8")
        print("Pinned iOS libmpv FFmpeg-filter-enabled 0.6.8 SHA256:", FILTER_SHA256)
    return makefile.parent


def native_filter_check(package: Path) -> None:
    root = package / "ios" / "Frameworks" / "Avfilter.xcframework"
    if not root.is_dir():
        raise RuntimeError(f"Native FFmpeg Avfilter framework missing: {root}")
    files = list(root.rglob("Avfilter.framework/Avfilter"))
    devices = [p for p in files if "ios-arm64" in str(p).lower() and
               "simulator" not in str(p).lower()]
    if not devices:
        raise RuntimeError("Native iOS arm64 Avfilter binary missing")
    for binary in devices:
        strings = subprocess.run(
            ["strings", "-a", str(binary)], check=True,
            capture_output=True, text=True, timeout=90).stdout.lower()
        symbols = subprocess.run(
            ["nm", "-g", str(binary)], check=False,
            capture_output=True, text=True, timeout=90).stdout.lower()
        missing = [name for name in REQUIRED_FILTERS
                   if name not in strings and f"ff_af_{name}" not in symbols]
        if missing:
            raise RuntimeError("Packaged iOS Avfilter is missing " +
                               ", ".join(missing) + "; refusing IPA build")
        print("Verified bundled iOS arm64 FFmpeg filter symbols:",
              ", ".join(REQUIRED_FILTERS))


def self_test() -> None:
    original = (f"MPV_XCFRAMEWORKS_VERSION={VERSION}\n"
                f"MPV_XCFRAMEWORKS_SHA256SUM={DEFAULT_SHA256}\n"
                f"url=https://github.com/Predidit/libmpv-darwin-build/releases/"
                f"download/{VERSION}/{DEFAULT_ARCHIVE}\n")
    patched = patch_makefile(original)
    assert FILTER_SHA256 in patched and FILTER_ARCHIVE in patched
    assert DEFAULT_SHA256 not in patched and DEFAULT_ARCHIVE not in patched
    assert patch_makefile(patched) == patched
    for bad in (original.replace(VERSION, "0.0.0"),
                original.replace(DEFAULT_SHA256, "unknown")):
        try:
            patch_makefile(bad)
        except RuntimeError:
            pass
        else:
            raise AssertionError("Unexpected package configuration accepted")
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        package = root / PACKAGE_NAME
        (package / "ios").mkdir(parents=True)
        (package / "ios" / "Makefile").write_text(original, encoding="utf-8")
        cfg = root / "package_config.json"
        cfg.write_text(json.dumps({"packages": [
            {"name": PACKAGE_NAME, "rootUri": package.as_uri()}
        ]}), encoding="utf-8")
        assert find_ios_package(cfg) == package.resolve()
        prepare(package)
        assert (package / "ios" / "Makefile").read_text(encoding="utf-8") == patched
    print("iOS Night Mode native libmpv pin self-test PASSED")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-config", type=Path,
                        default=Path(".dart_tool/package_config.json"))
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            return 0
        package = find_ios_package(args.package_config)
        if args.verify:
            native_filter_check(package)
        else:
            ios = prepare(package)
            subprocess.run(["make", "clean"], cwd=ios, check=True, timeout=120)
            subprocess.run(["make"], cwd=ios, check=True, timeout=600)
            native_filter_check(package)
        return 0
    except Exception as exc:
        print(f"[iOS Night Mode libmpv] {type(exc).__name__}: {exc}",
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
