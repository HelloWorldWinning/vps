#!/usr/bin/env python3
# tws.py
"""Convert massive plain text files to WAV/MP3 using ByteDance TTS API.

Usage:
    python tws.py <text_file>          # -> WAV (default)
    python tws.py <text_file> --mp3    # -> MP3

This script automatically handles long text limits by chunking the text 
at natural punctuation boundaries and seamlessly stitching the audio stream.
"""

import sys
import os
import json
import base64
import re
import struct
from pathlib import Path
import requests

API_URL = "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
API_KEY = os.environ.get("BYTEDANCE_TTS_KEY", "my_key")
RESOURCE_ID = "seed-tts-2.0"
SPEAKER = "zh_female_vv_uranus_bigtts"
SAMPLE_RATE = 24000

ADDITIONS = json.dumps(
    {
        "disable_markdown_filter": True,
        "enable_language_detector": True,
        "enable_latex_tn": True,
        "disable_default_bit_rate": True,
        "cache_config": {"text_type": 1, "use_cache": True},
    }
)


def chunk_text(text: str, max_len: int = 300) -> list[str]:
    """Automatically split long text by punctuation to respect API limits."""
    sentences = re.split(r"([。！？.!?\n]+)", text)
    chunks = []
    current_chunk = ""
    for part in sentences:
        if len(current_chunk) + len(part) > max_len:
            if current_chunk.strip():
                chunks.append(current_chunk.strip())
            current_chunk = part
        else:
            current_chunk += part
    if current_chunk.strip():
        chunks.append(current_chunk.strip())
    return [c for c in chunks if c]


def make_wav_header(
    sample_rate: int, num_channels: int, bits_per_sample: int, data_size: int
) -> bytes:
    """Creates a standard WAV header for raw PCM data."""
    byte_rate = sample_rate * num_channels * (bits_per_sample // 8)
    block_align = num_channels * (bits_per_sample // 8)
    return struct.pack(
        "<4sI4s4sIHHIIHH4sI",
        b"RIFF",
        36 + data_size,
        b"WAVE",
        b"fmt ",
        16,
        1,
        num_channels,
        sample_rate,
        byte_rate,
        block_align,
        bits_per_sample,
        b"data",
        data_size,
    )


def tts_chunk(text: str, fmt: str, session: requests.Session) -> bytes:
    """Fetches binary audio for a single text chunk."""
    headers = {
        "x-api-key": API_KEY,
        "X-Api-Resource-Id": RESOURCE_ID,
        "Content-Type": "application/json",
    }
    req_params = {
        "text": text,
        "speaker": SPEAKER,
        "additions": ADDITIONS,
        "audio_params": {"format": fmt, "sample_rate": SAMPLE_RATE},
    }

    resp = session.post(
        API_URL,
        headers=headers,
        json={"req_params": req_params},
        stream=True,
        timeout=120,
    )
    resp.raise_for_status()

    audio_chunks = []
    for line in resp.iter_lines():
        if line:
            msg = json.loads(line)
            if msg.get("code") not in (0, 20000000):
                print(f"\nAPI Error on chunk: {msg}", file=sys.stderr)
            elif msg.get("data"):
                audio_chunks.append(base64.b64decode(msg["data"]))

    return b"".join(audio_chunks)


def main() -> None:
    args = sys.argv[1:]
    if not args or "--help" in args or "-h" in args:
        print(__doc__)
        sys.exit(0)

    src = Path(args[0])
    if not src.is_file():
        print(f"Error: {src} not found", file=sys.stderr)
        sys.exit(1)

    is_mp3 = "--mp3" in args
    # If WAV is requested, we ask API for raw PCM and build a perfect unified WAV header at the end.
    api_fmt = "mp3" if is_mp3 else "pcm"
    ext = "mp3" if is_mp3 else "wav"

    text = src.read_text(encoding="utf-8").strip()
    if not text:
        sys.exit("Error: file is empty")

    chunks = chunk_text(text)
    print(
        f"Generating {ext.upper()} from {src} (Auto-split into {len(chunks)} chunks)..."
    )

    final_audio = bytearray()

    # Use Session to keep TCP connection alive across chunks (best practice from docs)
    with requests.Session() as session:
        for i, chunk in enumerate(chunks, 1):
            print(f"  -> Processing chunk {i}/{len(chunks)}...", end="\r", flush=True)
            audio_bytes = tts_chunk(chunk, api_fmt, session)
            final_audio.extend(audio_bytes)

    print()  # Clear line

    if not final_audio:
        sys.exit("No audio data generated.")

    out = src.with_suffix(f".{ext}")

    # Write output
    with open(out, "wb") as f:
        if not is_mp3:
            # Prepend unified WAV header to raw PCM data
            f.write(make_wav_header(SAMPLE_RATE, 1, 16, len(final_audio)))
        f.write(final_audio)

    print(f"Saved {out} ({len(final_audio):,} bytes)")


if __name__ == "__main__":
    main()
