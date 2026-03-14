#!/usr/bin/env python3
"""
ttslong.py – Long-text TTS via auto-splitting + HTTP streaming.

Automatically splits long text at sentence boundaries, calls the
ByteDance Seed-TTS HTTP Chunked API for each chunk (with TCP
connection reuse), and concatenates the audio output.

This bypasses the single-request text length limit without needing
the complex binary WebSocket protocol.

Usage:
    python ttslong.py <text_file>              # -> MP3 (default)
    python ttslong.py <text_file> --wav        # -> WAV (use pcm internally)
    python ttslong.py <text_file> --maxchars 600

Requirements:
    pip install requests

Environment:
    BYTEDANCE_TTS_KEY   - API key (required)
"""

import sys
import os
import json
import base64
import re
import time
import struct
from pathlib import Path

import requests

# ── Config (same as your working tts.py) ─────────────────────────────────────

API_URL = "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
API_KEY = os.environ.get("BYTEDANCE_TTS_KEY", "my_key")
RESOURCE_ID = "seed-tts-2.0"
SPEAKER = "zh_female_vv_uranus_bigtts"

SAMPLE_RATE = 24000
PITCH = 0
SPEED = 0
VOLUME = 0

ADDITIONS = json.dumps(
    {
        "disable_markdown_filter": True,
        "enable_language_detector": True,
        "enable_latex_tn": True,
        "disable_default_bit_rate": True,
        "max_length_to_filter_parenthesis": 0,
        "cache_config": {"text_type": 1, "use_cache": True},
    }
)

# Max chars per API call.  The server limit is ~4000+ chars for TTS2.0,
# but shorter chunks give lower latency and safer margin.
DEFAULT_MAX_CHARS = 500


# ── Text splitter ─────────────────────────────────────────────────────────────


def split_text(text: str, max_len: int = DEFAULT_MAX_CHARS) -> list[str]:
    """
    Split text at natural sentence boundaries.
    Respects Chinese (。！？；) and Western (.!?;) punctuation + newlines.
    Never splits mid-sentence unless a single sentence exceeds max_len.
    """
    # Split AFTER sentence-ending punctuation
    parts = re.split(r"(?<=[。！？；\n.!?;])", text)

    chunks: list[str] = []
    buf = ""

    for p in parts:
        if not p:
            continue
        # If adding this part exceeds limit, flush buffer first
        if buf and len(buf) + len(p) > max_len:
            chunks.append(buf.strip())
            buf = ""
        buf += p

        # Handle oversized single sentence: force-split at commas or max_len
        while len(buf) > max_len:
            # Try to split at a comma within max_len
            cut = -1
            for sep in ["，", ",", "、", "："]:
                idx = buf.rfind(sep, 0, max_len)
                if idx > 0:
                    cut = idx + len(sep)
                    break
            if cut <= 0:
                cut = max_len  # hard cut
            chunks.append(buf[:cut].strip())
            buf = buf[cut:]

    if buf.strip():
        chunks.append(buf.strip())

    return [c for c in chunks if c]


# ── WAV helpers ───────────────────────────────────────────────────────────────


def make_wav_header(
    data_size: int,
    sample_rate: int = 24000,
    bits_per_sample: int = 16,
    channels: int = 1,
) -> bytes:
    """Create a WAV file header for raw PCM data."""
    byte_rate = sample_rate * channels * bits_per_sample // 8
    block_align = channels * bits_per_sample // 8
    header_size = 44
    file_size = header_size - 8 + data_size

    hdr = bytearray()
    hdr += b"RIFF"
    hdr += struct.pack("<I", file_size)
    hdr += b"WAVE"
    hdr += b"fmt "
    hdr += struct.pack("<I", 16)  # fmt chunk size
    hdr += struct.pack("<H", 1)  # PCM format
    hdr += struct.pack("<H", channels)
    hdr += struct.pack("<I", sample_rate)
    hdr += struct.pack("<I", byte_rate)
    hdr += struct.pack("<H", block_align)
    hdr += struct.pack("<H", bits_per_sample)
    hdr += b"data"
    hdr += struct.pack("<I", data_size)
    return bytes(hdr)


# ── Single-chunk TTS (reuses your working approach) ──────────────────────────


def tts_chunk(session: requests.Session, text: str, fmt: str) -> bytes:
    """Call the HTTP Chunked API for one chunk of text. Returns raw audio bytes."""
    headers = {
        "x-api-key": API_KEY,
        "X-Api-Resource-Id": RESOURCE_ID,
        "Connection": "keep-alive",
        "Content-Type": "application/json",
    }

    req_params = {
        "text": text,
        "speaker": SPEAKER,
        "additions": ADDITIONS,
        "audio_params": {
            "format": fmt,
            "sample_rate": SAMPLE_RATE,
            "pitch": PITCH,
            "speed": SPEED,
            "volume": VOLUME,
        },
    }

    resp = session.post(
        API_URL,
        headers=headers,
        json={"req_params": req_params},
        stream=True,
        timeout=180,
    )
    resp.raise_for_status()

    audio_chunks = []
    for line in resp.iter_lines():
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        code = msg.get("code", -1)
        if code == 20000000:
            # Session finished successfully
            usage = msg.get("usage", {})
            if usage:
                print(f"      usage: {usage}")
            break
        if code not in (0, 20000000):
            raise RuntimeError(f"API error: {msg}")

        data = msg.get("data")
        if data:
            audio_chunks.append(base64.b64decode(data))

    return b"".join(audio_chunks)


# ── Main orchestrator ─────────────────────────────────────────────────────────


def tts_long(text: str, fmt: str = "wav", max_chars: int = DEFAULT_MAX_CHARS) -> bytes:
    """
    Synthesize arbitrarily long text by auto-splitting + concatenation.

    For WAV output, internally uses PCM format (to avoid WAV headers in
    each chunk) and wraps the final concatenated PCM with a single WAV header.
    """
    chunks = split_text(text, max_chars)
    total = len(chunks)

    # For WAV output, request PCM from API to avoid per-chunk WAV headers
    api_fmt = "pcm" if fmt == "wav" else fmt

    print(f"  Split into {total} chunks  (max {max_chars} chars/chunk)")

    session = requests.Session()  # TCP connection reuse (keep-alive)
    all_audio: list[bytes] = []

    for idx, chunk in enumerate(chunks, 1):
        print(
            f"  [{idx}/{total}] {len(chunk)} chars: "
            f"{chunk[:40]}{'…' if len(chunk) > 40 else ''}"
        )

        t0 = time.time()
        audio = tts_chunk(session, chunk, api_fmt)
        dt = time.time() - t0

        all_audio.append(audio)
        print(f"      → {len(audio):,} bytes  ({dt:.1f}s)")

    session.close()

    combined = b"".join(all_audio)

    # Wrap PCM in WAV header if needed
    if fmt == "wav":
        combined = make_wav_header(len(combined), SAMPLE_RATE) + combined

    return combined


# ── CLI ───────────────────────────────────────────────────────────────────────


def main() -> None:
    args = sys.argv[1:]

    if not args or "--help" in args or "-h" in args:
        print(__doc__)
        sys.exit(0)

    src = Path(args[0])
    if not src.is_file():
        print(f"Error: {src} not found", file=sys.stderr)
        sys.exit(1)

    # Parse options
    #   fmt = "wav" if "--wav" in args else "mp3"
    fmt = "wav" if "--mp3" in args else "wav"
    max_chars = DEFAULT_MAX_CHARS
    if "--maxchars" in args:
        i = args.index("--maxchars")
        if i + 1 < len(args):
            max_chars = int(args[i + 1])

    text = src.read_text(encoding="utf-8").strip()
    if not text:
        print("Error: file is empty", file=sys.stderr)
        sys.exit(1)

    out = src.with_suffix(f".{fmt}")
    print(f"[ttslong] {fmt.upper()} ← {src}  ({len(text):,} chars)")

    audio = tts_long(text, fmt=fmt, max_chars=max_chars)
    out.write_bytes(audio)

    print(f"[ttslong] Saved {out}  ({len(audio):,} bytes)")


if __name__ == "__main__":
    main()
