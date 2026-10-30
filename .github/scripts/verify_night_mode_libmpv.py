#!/usr/bin/env python3
"""Fail-closed Windows test of the *packaged* libmpv audio compressor.

Invokes libmpv-2.dll itself through the public mpv client ABI. The bundled
standalone FFmpeg executable is only used to make a synthetic E-AC3 sample;
testing ffmpeg.exe filters alone would NOT prove libmpv contains acompressor.
"""
from __future__ import annotations

import argparse
import ctypes
import math
import os
from pathlib import Path
import struct
import sys
import time
import wave

COMPRESSOR_CHAIN = (
    "scaletempo2=max-speed=8,lavfi=[acompressor=threshold=0.10:"
    "ratio=4:attack=15:release=260:makeup=1.25:knee=2.5,"
    "alimiter=limit=0.95:level=0]"
)
MPV_EVENT_LOG_MESSAGE = 2
MPV_EVENT_END_FILE = 7
MPV_EVENT_AUDIO_RECONFIG = 18
MPV_END_FILE_REASON_EOF = 0


class MpvEvent(ctypes.Structure):
    _fields_ = [
        ("event_id", ctypes.c_int),
        ("error", ctypes.c_int),
        ("reply_userdata", ctypes.c_uint64),
        ("data", ctypes.c_void_p),
    ]


class MpvEventLogMessage(ctypes.Structure):
    _fields_ = [
        ("prefix", ctypes.c_char_p),
        ("level", ctypes.c_char_p),
        ("text", ctypes.c_char_p),
        ("log_level", ctypes.c_int),
    ]


class MpvEventEndFile(ctypes.Structure):
    _fields_ = [
        ("reason", ctypes.c_int),
        ("error", ctypes.c_int),
        ("playlist_entry_id", ctypes.c_int64),
        ("playlist_insert_id", ctypes.c_int64),
        ("playlist_insert_num_entries", ctypes.c_int),
    ]


def synthesize_wav(destination: Path) -> None:
    """A local two-second, noncopyright test tone; no real stream required."""
    rate = 48000
    with wave.open(str(destination), "wb") as target:
        target.setnchannels(2)
        target.setsampwidth(2)
        target.setframerate(rate)
        frames = bytearray()
        for index in range(rate * 2):
            gain = 0.12 if index < rate else 0.82
            tone = int(gain * math.sin(2.0 * math.pi * 440 * index / rate) * 32767)
            frames.extend(struct.pack("<hh", tone, tone))
        target.writeframes(frames)


def assert_project_chain(repo_root: Path) -> None:
    source = (repo_root / "lib/services/player/player_picture_audio.dart").read_text(
        encoding="utf-8"
    )
    for expected in (
        "scaletempo2=max-speed=8",
        "acompressor=threshold=0.10:ratio=4:attack=15:",
        "release=260:makeup=1.25:knee=2.5,alimiter=limit=0.95:level=0",
    ):
        if expected not in source:
            raise RuntimeError("Native smoke chain differs from Flutter player policy")


def _decode(raw: bytes | None) -> str:
    return raw.decode("utf-8", errors="replace") if raw else ""


def smoke(libmpv: Path, audio: Path) -> None:
    if sys.platform != "win32":
        raise RuntimeError("Native MPV smoke must run on Windows x64")
    if not libmpv.is_file() or not audio.is_file():
        raise FileNotFoundError("Packaged libmpv or synthetic test audio missing")

    libdir = libmpv.resolve().parent
    # Keep the search-directory handle open for the entire MPV instance life.
    dll_directory = os.add_dll_directory(str(libdir))
    try:
        mpv = ctypes.WinDLL(str(libmpv.resolve()))
    except Exception:
        dll_directory.close()
        raise

    def bind(name, restype, *args):
        fn = getattr(mpv, name)
        fn.restype = restype
        fn.argtypes = list(args)
        return fn

    create = bind("mpv_create", ctypes.c_void_p)
    destroy = bind("mpv_terminate_destroy", None, ctypes.c_void_p)
    option = bind(
        "mpv_set_option_string",
        ctypes.c_int,
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
    )
    initialize = bind("mpv_initialize", ctypes.c_int, ctypes.c_void_p)
    set_property = bind(
        "mpv_set_property_string", ctypes.c_int,
        ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p
    )
    command = bind(
        "mpv_command", ctypes.c_int, ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_char_p)
    )
    logs = bind(
        "mpv_request_log_messages", ctypes.c_int,
        ctypes.c_void_p, ctypes.c_char_p,
    )
    wait_event = bind(
        "mpv_wait_event", ctypes.POINTER(MpvEvent),
        ctypes.c_void_p, ctypes.c_double,
    )

    handle = create()
    if not handle:
        dll_directory.close()
        raise RuntimeError("libmpv could not create an MPV instance")
    errors = []
    compressor_seen = False
    limiter_seen = False
    audio_reconfigured = False
    completed = False
    try:
        for key, value in (
            ("config", "no"),
            ("vo", "null"),
            ("ao", "null"),
            ("audio-normalize-downmix", "yes"),
            ("af", COMPRESSOR_CHAIN),
        ):
            result = option(handle, key.encode("ascii"), value.encode("utf-8"))
            if result < 0:
                raise RuntimeError(f"libmpv rejected {key} option ({result})")
        result = initialize(handle)
        if result < 0:
            raise RuntimeError(f"libmpv initialization failed ({result})")
        # Flutter writes this MPV option on a live player when toggling.
        # Successful startup-only options are insufficient for that code path.
        for requested in (b"no", b"yes"):
            result = set_property(
                handle, b"audio-normalize-downmix", requested
            )
            if result < 0:
                raise RuntimeError(
                    f"Live audio-normalize-downmix setter failed ({result})"
                )
        result = logs(handle, b"v")
        if result < 0:
            raise RuntimeError(f"libmpv log subscription failed ({result})")
        # mpv_command() is asynchronous; success only means the command parsed.
        args = (ctypes.c_char_p * 3)(
            b"loadfile", str(audio.resolve()).encode("utf-8"), None
        )
        result = command(handle, args)
        if result < 0:
            raise RuntimeError(f"libmpv rejected test file ({result})")
        deadline = time.monotonic() + 30.0
        while time.monotonic() < deadline:
            event = wait_event(handle, 0.5).contents
            if event.event_id == MPV_EVENT_LOG_MESSAGE and event.data:
                log = ctypes.cast(
                    event.data, ctypes.POINTER(MpvEventLogMessage)
                ).contents
                prefix = _decode(log.prefix)
                message = _decode(log.text).strip()
                if "acompressor" in message:
                    compressor_seen = True
                    print(f"[{prefix}] {message[:240]}")
                if "alimiter" in message:
                    limiter_seen = True
                    print(f"[{prefix}] {message[:240]}")
                if any(pattern in message.lower() for pattern in (
                    "no such filter", "audio filter initialized failed",
                    "creating filter 'lavfi' failed",
                    "parsing the filter graph failed",
                    "error initializing filter",
                )):
                    errors.append(f"{prefix}: {message[:240]}")
            elif event.event_id == MPV_EVENT_AUDIO_RECONFIG:
                audio_reconfigured = True
            elif event.event_id == MPV_EVENT_END_FILE and event.data:
                end = ctypes.cast(
                    event.data, ctypes.POINTER(MpvEventEndFile)
                ).contents
                if end.reason != MPV_END_FILE_REASON_EOF:
                    errors.append(
                        f"mpv_end_file: reason={end.reason} error={end.error}"
                    )
                completed = True
                break

        if errors:
            raise RuntimeError("libmpv native Night Mode failed: " + " | ".join(errors))
        if not completed:
            raise RuntimeError("libmpv Night Mode sample never completed")
        if not audio_reconfigured:
            raise RuntimeError("No libmpv audio reconfiguration event occurred")
        if not compressor_seen:
            raise RuntimeError("No evidence that MPV configured acompressor")
        if not limiter_seen:
            raise RuntimeError("No evidence that MPV configured alimiter")
        print(
            "PASS: packaged libmpv decoded synthetic audio using "
            "scaletempo2 + acompressor + alimiter without an FFmpeg filter error"
        )
    finally:
        try:
            destroy(handle)
        finally:
            dll_directory.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--libmpv", type=Path)
    parser.add_argument("--sample", type=Path)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--generate-sample", type=Path)
    args = parser.parse_args()
    assert_project_chain(args.repo)
    if args.self_test:
        print("PASS: libmpv native test filter matches Flutter Night Mode")
        return
    if args.generate_sample is not None:
        synthesize_wav(args.generate_sample)
        print("PASS: generated local synthetic Windows audio sample")
        return
    if args.libmpv is None or args.sample is None:
        parser.error("--libmpv and --sample are required for Windows smoke")
    smoke(args.libmpv, args.sample)


if __name__ == "__main__":
    main()
