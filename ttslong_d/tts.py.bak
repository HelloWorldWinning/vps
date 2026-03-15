#!/usr/bin/env python3
# BigTTS2000000652178241314
"""Convert plain text file to WAV/MP3 using ByteDance TTS API.

Usage:
    python tts.py <text_file>          # -> WAV (default)
    python tts.py <text_file> --mp3    # -> MP3

Notes:
- Plain text only. No SSML support.
- To encourage pauses / emphasis, shape the input with punctuation,
  spaces, and line breaks.
"""

import sys
import os
import json
import base64
from pathlib import Path

import requests

API_URL = "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
API_KEY = os.environ.get("BYTEDANCE_TTS_KEY", "my_key")

RESOURCE_ID = "seed-tts-2.0"
SPEAKER = "zh_female_vv_uranus_bigtts"

PITCH = 0
SPEED = 0
VOLUME = 0
SAMPLE_RATE = 24000

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


def tts(text: str, fmt: str = "wav") -> bytes:
    """Send plain text to TTS API and return audio bytes."""
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

    resp = requests.post(
        API_URL,
        headers=headers,
        json={"req_params": req_params},
        stream=True,
        timeout=120,
    )
    resp.raise_for_status()

    audio_chunks = []
    for line in resp.iter_lines():
        if not line:
            continue

        msg = json.loads(line)
        if msg.get("code") not in (0, 20000000):
            raise RuntimeError(f"API error: {msg}")

        data = msg.get("data")
        if data:
            audio_chunks.append(base64.b64decode(data))

    if not audio_chunks:
        raise RuntimeError("No audio data received")

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

    fmt = "mp3" if "--mp3" in args else "wav"

    text = src.read_text(encoding="utf-8").strip()
    if not text:
        print("Error: file is empty", file=sys.stderr)
        sys.exit(1)

    out = src.with_suffix(f".{fmt}")
    print(f"Generating {fmt.upper()} [plain text] from {src} ...")

    audio = tts(text, fmt=fmt)
    out.write_bytes(audio)

    print(f"Saved {out}  ({len(audio):,} bytes)")


if __name__ == "__main__":
    main()
