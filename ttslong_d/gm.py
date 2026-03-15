#!/usr/bin/env python3
"""
ttsws.py – Long-text TTS via WebSocket + Context Linking.

Automatically splits long text, reuses a single WebSocket connection, 
and chains `section_id` across chunks to ensure the voice NEVER changes
between sentences (fixes the TTS 2.0 voice instability).

Usage:
    python ttsws.py <text_file>              # -> WAV (default, uses pcm internally)
    python ttsws.py <text_file> --mp3        # -> MP3

Environment:
    BYTEDANCE_APP_ID     - Volcengine App ID (Required)
    BYTEDANCE_ACCESS_KEY - Volcengine Access Token (Required)
"""

import sys
import os
import json
import uuid
import struct
import asyncio
import re
import time
from pathlib import Path

import websockets

# ── Config ────────────────────────────────────────────────────────────────────

API_URL = "wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream"

# Volcengine WS API strictly requires both App ID and Access Key in headers
APP_ID = os.environ.get("BYTEDANCE_APP_ID", "your_app_id")
ACCESS_KEY = os.environ.get(
    "BYTEDANCE_ACCESS_KEY", os.environ.get("BYTEDANCE_TTS_KEY", "your_access_key")
)

RESOURCE_ID = "seed-tts-2.0"
SPEAKER = "zh_female_vv_uranus_bigtts"

SAMPLE_RATE = 24000
DEFAULT_MAX_CHARS = 400

# ── Text splitter ─────────────────────────────────────────────────────────────


def split_text(text: str, max_len: int = DEFAULT_MAX_CHARS) -> list[str]:
    """Splits text at natural sentence boundaries without exceeding max_len."""
    parts = re.split(r"(?<=[。！？；\n.!?;])", text)
    chunks, buf = [], ""

    for p in parts:
        if not p:
            continue
        if buf and len(buf) + len(p) > max_len:
            chunks.append(buf.strip())
            buf = ""
        buf += p

        while len(buf) > max_len:
            cut = -1
            for sep in ["，", ",", "、", "："]:
                idx = buf.rfind(sep, 0, max_len)
                if idx > 0:
                    cut = idx + len(sep)
                    break
            if cut <= 0:
                cut = max_len
            chunks.append(buf[:cut].strip())
            buf = buf[cut:]

    if buf.strip():
        chunks.append(buf.strip())

    return [c for c in chunks if c]


# ── WAV helpers ───────────────────────────────────────────────────────────────


def make_wav_header(data_size: int, sample_rate: int = 24000) -> bytes:
    """Create a WAV file header for raw PCM data."""
    channels = 1
    bits_per_sample = 16
    byte_rate = sample_rate * channels * bits_per_sample // 8
    block_align = channels * bits_per_sample // 8
    file_size = 36 + data_size

    hdr = bytearray()
    hdr += b"RIFF" + struct.pack("<I", file_size) + b"WAVE"
    hdr += b"fmt " + struct.pack("<I", 16) + struct.pack("<H", 1)
    hdr += struct.pack("<H", channels) + struct.pack("<I", sample_rate)
    hdr += struct.pack("<I", byte_rate) + struct.pack("<H", block_align)
    hdr += struct.pack("<H", bits_per_sample)
    hdr += b"data" + struct.pack("<I", data_size)
    return bytes(hdr)


# ── Main WebSocket Orchestrator ───────────────────────────────────────────────


async def tts_long_ws(
    text: str, fmt: str = "wav", max_chars: int = DEFAULT_MAX_CHARS
) -> bytes:
    chunks = split_text(text, max_chars)
    total = len(chunks)
    api_fmt = "pcm" if fmt == "wav" else fmt

    print(f"  Split into {total} chunks  (max {max_chars} chars/chunk)")

    headers = {
        "X-Api-App-Id": APP_ID,
        "X-Api-Access-Key": ACCESS_KEY,
        "X-Api-Resource-Id": RESOURCE_ID,
        "X-Api-Request-Id": str(uuid.uuid4()),
    }

    all_audio = []
    current_section_id = ""  # MAGIC HAPPENS HERE: Context linking

    # Establish a single WS connection and reuse it for all chunks
    async with websockets.connect(API_URL, additional_headers=headers) as ws:
        for idx, chunk in enumerate(chunks, 1):
            print(
                f"  [{idx}/{total}] {len(chunk)} chars: {chunk[:40]}{'…' if len(chunk) > 40 else ''}"
            )
            t0 = time.time()

            additions = {
                "disable_markdown_filter": True,
                "enable_language_detector": True,
                "enable_latex_tn": True,
                "disable_default_bit_rate": True,
                "max_length_to_filter_parenthesis": 0,
                "cache_config": {"text_type": 1, "use_cache": True},
            }

            # Link to the previous chunk to maintain the exact same voice/tone
            if current_section_id:
                additions["section_id"] = current_section_id

            req = {
                "user": {"uid": "12345"},
                "req_params": {
                    "text": chunk,
                    "speaker": SPEAKER,
                    "additions": json.dumps(additions),
                    "audio_params": {
                        "format": api_fmt,
                        "sample_rate": SAMPLE_RATE,
                    },
                },
            }

            payload = json.dumps(req).encode("utf-8")

            # Construct binary frame: Header(v1, client req, JSON, reserved) + Length + Payload
            header = b"\x11\x10\x10\x00"
            frame = header + struct.pack(">I", len(payload)) + payload
            await ws.send(frame)

            chunk_audio = []

            # Receive loop for this specific chunk
            while True:
                res = await ws.recv()
                if isinstance(res, bytes):
                    msg_type = (res[1] & 0xF0) >> 4

                    # Handle API Error Frame
                    if msg_type == 0x0F:
                        err_code = struct.unpack(">I", res[4:8])[0]
                        raise RuntimeError(f"WebSocket API Error Code: {err_code}")

                    event_type = struct.unpack(">I", res[4:8])[0]
                    sid_len = struct.unpack(">I", res[8:12])[0]
                    session_id = res[12 : 12 + sid_len].decode("utf-8")

                    # Capture session_id to pass to the next chunk
                    if session_id:
                        current_section_id = session_id

                    # Handle TTSResponse (Audio Data)
                    if msg_type == 0x0B and event_type == 352:
                        audio_len = struct.unpack(
                            ">I", res[12 + sid_len : 16 + sid_len]
                        )[0]
                        audio_data = res[16 + sid_len : 16 + sid_len + audio_len]
                        chunk_audio.append(audio_data)

                    # Handle SessionFinished (Chunk Complete)
                    elif msg_type == 0x09 and event_type == 152:
                        break

            all_audio.append(b"".join(chunk_audio))
            dt = time.time() - t0
            print(f"      → {len(all_audio[-1]):,} bytes  ({dt:.1f}s)")

        # Graceful connection closure frame
        finish_payload = json.dumps({}).encode("utf-8")
        finish_frame = (
            b"\x11\x14\x10\x00"
            + struct.pack(">I", len(finish_payload))
            + finish_payload
        )
        await ws.send(finish_frame)

    combined = b"".join(all_audio)

    # Wrap PCM in a single WAV header
    if fmt == "wav":
        combined = make_wav_header(len(combined), SAMPLE_RATE) + combined

    return combined


# ── CLI ───────────────────────────────────────────────────────────────────────


async def main() -> None:
    args = sys.argv[1:]

    if not args or "--help" in args or "-h" in args:
        print(__doc__)
        sys.exit(0)

    src = Path(args[0])
    if not src.is_file():
        print(f"Error: {src} not found", file=sys.stderr)
        sys.exit(1)

    fmt = "mp3" if "--mp3" in args else "wav"
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
    print(f"[ttsws] {fmt.upper()} ← {src}  ({len(text):,} chars)")

    try:
        audio = await tts_long_ws(text, fmt=fmt, max_chars=max_chars)
        out.write_bytes(audio)
        print(f"[ttsws] Saved {out}  ({len(audio):,} bytes)")
    except Exception as e:
        print(f"Failed: {e}", file=sys.stderr)


if __name__ == "__main__":
    asyncio.run(main())
