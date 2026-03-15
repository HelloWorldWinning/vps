#!/usr/bin/env python3
"""
ttsws.py – TTS via ByteDance Seed-TTS V3 WebSocket unidirectional streaming.

The WebSocket API accepts full text in a single request and streams
audio back sentence-by-sentence, so the server handles sentence
splitting internally — no client-side chunking is needed for typical
texts.  For extremely long texts (>10k chars), optional chunking with
section_id keeps the voice consistent across chunks.

This avoids the "voice-switching" artefact that HTTP chunk-and-concat
approaches can produce, because the server maintains a single acoustic
session across all internal sentences.

Usage:
    python ttsws.py <text_file>                  # -> WAV (default)
    python ttsws.py <text_file> --mp3            # -> MP3
    python ttsws.py <text_file> --maxchars 5000  # force chunking at N chars

Requirements:
    pip install websockets

Environment:
    BYTEDANCE_APP_ID      – App ID  (from 火山引擎控制台)
    BYTEDANCE_ACCESS_KEY  – Access Token
"""

import sys
import os
import json
import re
import time
import struct
import asyncio
import gzip
import uuid
from pathlib import Path

try:
    import websockets
except ImportError:
    sys.exit("Error: pip install websockets")

# ── Config ────────────────────────────────────────────────────────────────────

WS_URL = "wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream"

APPID = os.environ.get("BYTEDANCE_APP_ID", "your-app-id")
ACCESS_KEY = os.environ.get("BYTEDANCE_ACCESS_KEY", "your-access-key")
RESOURCE_ID = "seed-tts-2.0"
SPEAKER = "zh_female_vv_uranus_bigtts"

SAMPLE_RATE = 24000

ADDITIONS = {
    "disable_markdown_filter": True,
    "enable_language_detector": True,
    "enable_latex_tn": True,
    "disable_default_bit_rate": True,
    "max_length_to_filter_parenthesis": 0,
    "cache_config": {"text_type": 1, "use_cache": True},
}

# 0 = no chunking (let the server handle everything in one shot).
# Set to e.g. 5000 to force client-side chunking for very long texts.
DEFAULT_MAX_CHARS = 0

# ── Event codes ───────────────────────────────────────────────────────────────

EVT_FINISH_CONNECTION = 2
EVT_CONNECTION_FINISHED = 52
EVT_SESSION_FINISHED = 152
EVT_SENTENCE_START = 350
EVT_SENTENCE_END = 351
EVT_TTS_RESPONSE = 352

# ── Binary protocol helpers ───────────────────────────────────────────────────
#
# Frame layout (V3 binary protocol):
#   Byte 0:  [version 4-bit][header_size/4 4-bit]   always 0x11
#   Byte 1:  [message_type 4-bit][flags 4-bit]
#   Byte 2:  [serialization 4-bit][compression 4-bit]
#   Byte 3:  reserved = 0x00
#   Bytes 4+: optional event number (uint32 BE) if flags & 0x04,
#             then payload-length (uint32 BE) + payload.
#
# Request message types:
#   0x1 = Full-client request (sendText / finishConnection)
# Response message types:
#   0x9 = Server response (JSON metadata)
#   0xB = Audio-only response
#   0xF = Error response


def _build_send_text_frame(payload_dict: dict) -> bytes:
    """Build a sendText binary frame (msg_type=0x1, flags=0x0, JSON, no compression)."""
    payload = json.dumps(payload_dict, ensure_ascii=False).encode("utf-8")
    header = bytes([0x11, 0x10, 0x10, 0x00])
    return header + struct.pack(">I", len(payload)) + payload


def _build_finish_frame() -> bytes:
    """Build a FinishConnection binary frame (msg_type=0x1, flags=0x4, event=2)."""
    payload = b"{}"
    header = bytes([0x11, 0x14, 0x10, 0x00])
    return (
        header
        + struct.pack(">I", EVT_FINISH_CONNECTION)
        + struct.pack(">I", len(payload))
        + payload
    )


def _parse_frame(raw: bytes) -> dict:
    """Parse a binary response frame into a dict."""
    if len(raw) < 4:
        return {"type": "unknown", "raw": raw}

    msg_type = (raw[1] >> 4) & 0x0F
    flags = raw[1] & 0x0F
    serial = (raw[2] >> 4) & 0x0F
    compress = raw[2] & 0x0F
    header_sz = (raw[0] & 0x0F) * 4  # 4

    pos = header_sz

    # ── Error frame (msg_type 0xF) ────────────────────────────────────────
    if msg_type == 0x0F:
        err_code = 0
        if len(raw) >= pos + 4:
            err_code = struct.unpack(">I", raw[pos : pos + 4])[0]
            pos += 4
        err_msg = raw[pos:]
        if compress == 1:
            err_msg = gzip.decompress(err_msg)
        # The error payload may itself be JSON with payload-length prefix
        try:
            # Try parsing as length-prefixed JSON
            if len(err_msg) >= 4:
                pl_len = struct.unpack(">I", err_msg[:4])[0]
                if pl_len <= len(err_msg) - 4:
                    err_msg = err_msg[4 : 4 + pl_len]
            err_msg = json.loads(err_msg)
        except Exception:
            err_msg = err_msg.decode("utf-8", errors="replace")
        return {"type": "error", "code": err_code, "detail": err_msg}

    # ── Normal frame ──────────────────────────────────────────────────────
    event = None
    session_id = None

    if flags & 0x04:  # has event number
        event = struct.unpack(">I", raw[pos : pos + 4])[0]
        pos += 4
        # session_id (length-prefixed)
        sid_len = struct.unpack(">I", raw[pos : pos + 4])[0]
        pos += 4
        session_id = raw[pos : pos + sid_len].decode("utf-8", errors="replace")
        pos += sid_len

    # payload (length-prefixed)
    if pos + 4 > len(raw):
        return {
            "type": "audio" if msg_type == 0x0B else "json",
            "event": event,
            "sid": session_id,
            "payload": b"",
        }

    pl_len = struct.unpack(">I", raw[pos : pos + 4])[0]
    pos += 4
    payload = raw[pos : pos + pl_len]

    if compress == 1:
        payload = gzip.decompress(payload)

    # Audio-only frame → return raw bytes
    if msg_type == 0x0B:
        return {"type": "audio", "event": event, "sid": session_id, "data": payload}

    # JSON frame
    if serial == 0x01 and payload:
        try:
            payload = json.loads(payload)
        except json.JSONDecodeError:
            payload = payload.decode("utf-8", errors="replace")

    return {"type": "json", "event": event, "sid": session_id, "payload": payload}


# ── Text splitter (only used when max_chars > 0) ─────────────────────────────


def _split_text(text: str, max_len: int) -> list[str]:
    """Split at sentence boundaries.  Returns [text] unchanged if max_len <= 0."""
    if max_len <= 0 or len(text) <= max_len:
        return [text]

    parts = re.split(r"(?<=[。！？；\n.!?;])", text)
    chunks: list[str] = []
    buf = ""

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


# ── WAV header ────────────────────────────────────────────────────────────────


def _wav_header(data_size: int, sr: int = 24000) -> bytes:
    hdr = bytearray()
    hdr += b"RIFF"
    hdr += struct.pack("<I", 36 + data_size)
    hdr += b"WAVE"
    hdr += b"fmt "
    hdr += struct.pack("<I", 16)
    hdr += struct.pack("<H", 1)  # PCM
    hdr += struct.pack("<H", 1)  # mono
    hdr += struct.pack("<I", sr)
    hdr += struct.pack("<I", sr * 2)  # byte_rate = sr * channels * bps/8
    hdr += struct.pack("<H", 2)  # block_align
    hdr += struct.pack("<H", 16)  # bits_per_sample
    hdr += b"data"
    hdr += struct.pack("<I", data_size)
    return bytes(hdr)


# ── Core: synthesize one text over an open WS ────────────────────────────────


async def _tts_one(
    ws,
    text: str,
    audio_fmt: str,
    section_id: str = "",
) -> tuple[bytes, str]:
    """
    Send one text payload and collect all audio frames until SessionFinished.
    Returns (audio_bytes, session_id).

    The returned session_id can be passed as section_id to the next call
    to maintain voice continuity (TTS 2.0 feature).
    """
    additions = dict(ADDITIONS)
    if section_id:
        additions["section_id"] = section_id

    payload = {
        "user": {"uid": uuid.uuid4().hex[:8]},
        "req_params": {
            "text": text,
            "speaker": SPEAKER,
            "additions": json.dumps(additions, ensure_ascii=False),
            "audio_params": {
                "format": audio_fmt,
                "sample_rate": SAMPLE_RATE,
            },
        },
    }

    await ws.send(_build_send_text_frame(payload))

    audio_parts: list[bytes] = []
    session_id = ""
    frame_count = 0

    while True:
        try:
            msg = await asyncio.wait_for(ws.recv(), timeout=120)
        except asyncio.TimeoutError:
            raise RuntimeError("Timeout waiting for TTS response")

        if isinstance(msg, str):
            print(f"      [text frame] {msg[:200]}", flush=True)
            continue

        frame_count += 1
        # Hex dump first 3 frames for protocol debugging
        if frame_count <= 3:
            hdr_hex = msg[: min(32, len(msg))].hex(" ")
            print(
                f"      [raw #{frame_count}] len={len(msg)}  hex={hdr_hex}", flush=True
            )

        frame = _parse_frame(msg)

        # Debug: show every frame type + event
        ftype = frame.get("type")
        fevt = frame.get("event")
        print(
            f"      [frame] type={ftype}  event={fevt}  raw_len={len(msg)}", flush=True
        )

        if ftype == "error":
            raise RuntimeError(f"Server error: {frame}")

        if ftype == "audio":
            data = frame.get("data", b"")
            if data:
                audio_parts.append(data)
                print(f"      [audio] +{len(data):,} bytes", flush=True)
            if frame.get("sid"):
                session_id = frame["sid"]

        elif ftype == "json":
            if frame.get("sid"):
                session_id = frame["sid"]

            # Debug: show JSON payload
            pl = frame.get("payload")
            print(f"      [json]  evt={fevt}  payload={pl}", flush=True)

            if fevt == EVT_SESSION_FINISHED:
                if isinstance(pl, dict):
                    code = pl.get("status_code", -1)
                    msg_text = pl.get("message", "")
                    # 20000000 = explicit success; 0/-1 = field missing (not an error)
                    if code not in (-1, 0, 20000000):
                        raise RuntimeError(f"SessionFinished error {code}: {msg_text}")
                    usage = pl.get("usage")
                    if usage:
                        print(f"      usage: {usage}")
                break  # done with this text

    result = b"".join(audio_parts)
    print(f"      [done] {len(audio_parts)} audio frames, {len(result):,} bytes total")
    return result, session_id


# ── Orchestrator ──────────────────────────────────────────────────────────────


async def tts_ws(
    text: str,
    fmt: str = "wav",
    max_chars: int = DEFAULT_MAX_CHARS,
) -> bytes:
    """
    Synthesize text via WebSocket.  Returns complete audio bytes.

    If max_chars > 0 and the text exceeds that limit, it will be split
    into chunks with section_id chaining for voice consistency.
    Otherwise the full text is sent in one shot.
    """
    api_fmt = "pcm" if fmt == "wav" else fmt
    chunks = _split_text(text, max_chars)
    total = len(chunks)

    if total > 1:
        print(f"  Split into {total} chunks  (max {max_chars} chars/chunk)")
    else:
        print(f"  Sending full text  ({len(text):,} chars, no chunking)")

    headers = {
        "X-Api-App-Id": APPID,
        "X-Api-Access-Key": ACCESS_KEY,
        "X-Api-Resource-Id": RESOURCE_ID,
        "X-Api-Request-Id": str(uuid.uuid4()),
    }

    all_audio: list[bytes] = []

    async with websockets.connect(
        WS_URL,
        additional_headers=headers,
        max_size=50 * 1024 * 1024,  # 50 MB max frame
        ping_interval=20,
        ping_timeout=60,
        close_timeout=10,
    ) as ws:
        section_id = ""

        for idx, chunk in enumerate(chunks, 1):
            label = chunk[:50] + ("…" if len(chunk) > 50 else "")
            print(f"  [{idx}/{total}] {len(chunk):,} chars: {label}")

            t0 = time.time()
            audio, sid = await _tts_one(ws, chunk, api_fmt, section_id)
            dt = time.time() - t0

            all_audio.append(audio)
            section_id = sid  # chain sessions for voice consistency
            print(f"      → {len(audio):,} bytes  ({dt:.1f}s)  sid={sid[:20]}…")

        # Graceful close
        try:
            await ws.send(_build_finish_frame())
            await asyncio.wait_for(ws.recv(), timeout=5)
        except Exception:
            pass

    combined = b"".join(all_audio)
    if fmt == "wav":
        combined = _wav_header(len(combined), SAMPLE_RATE) + combined

    return combined


# ── CLI ───────────────────────────────────────────────────────────────────────


def main() -> None:
    args = sys.argv[1:]

    if not args or "-h" in args or "--help" in args:
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

    t_start = time.time()
    audio = asyncio.run(tts_ws(text, fmt=fmt, max_chars=max_chars))
    t_total = time.time() - t_start

    out.write_bytes(audio)
    print(f"[ttsws] Saved {out}  ({len(audio):,} bytes)  total={t_total:.1f}s")


if __name__ == "__main__":
    main()
