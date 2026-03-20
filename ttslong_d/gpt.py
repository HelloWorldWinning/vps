#!/usr/bin/env python3
"""
ttsws.py - Long-text TTS over Volcano Engine / ByteDance WebSocket V3.

What it does:
- Uses the V3 *unidirectional* WebSocket API.
- Reuses a single WS connection across many chunks.
- Keeps chunking for long text (WebSocket unidirectional still sends one full text
  per synthesis request; it is not an unlimited streaming-text API).
- For TTS 2.0 voices, passes the previous chunk's session_id as `section_id`
  to improve cross-chunk consistency.
- Defaults to WAV output by requesting PCM from the API and wrapping the final
  concatenated PCM with one WAV header.

Why this version is better for your case:
- HTTP chunking makes every chunk a brand-new synthesis request with no context,
  so prosody / identity can drift.
- This script keeps one WS connection alive and chains chunks with section_id,
  which is the closest thing the API exposes for long-form continuity.

Usage:
    python ttsws.py story.txt
    python ttsws.py story.txt --mp3
    python ttsws.py story.txt --maxchars 350
    python ttsws.py story.txt --speaker zh_female_vv_uranus_bigtts
    python ttsws.py story.txt --explicit-language zh-cn

Requirements:
    pip install websocket-client

Environment variables (first non-empty value wins):
    VOLC_APP_ID / BYTEDANCE_APP_ID / BYTEDANCE_TTS_APPID
    VOLC_ACCESS_TOKEN / BYTEDANCE_ACCESS_KEY / BYTEDANCE_TTS_ACCESS_TOKEN / BYTEDANCE_TTS_KEY
    VOLC_RESOURCE_ID / BYTEDANCE_RESOURCE_ID / BYTEDANCE_TTS_RESOURCE_ID   (default: seed-tts-2.0)
    VOLC_SPEAKER / BYTEDANCE_TTS_SPEAKER                                  (default: zh_female_vv_uranus_bigtts)

Notes:
- The WS API auth headers are App-Id + Access-Key / Access-Token style.
- Default output is WAV. Internally this requests PCM, because requesting WAV per
  chunk would produce repeated WAV headers.
- If your voice still drifts, try smaller chunks (e.g. --maxchars 250) and, when
  appropriate, set --explicit-language zh-cn or en.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import struct
import sys
import time
import uuid
from pathlib import Path
from typing import Any

try:
    import websocket  # websocket-client
except ImportError as exc:
    raise SystemExit(
        "Missing dependency: websocket-client\n"
        "Install it with: pip install websocket-client"
    ) from exc


WS_URL = "wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream"
DEFAULT_RESOURCE_ID = (
    os.environ.get("VOLC_RESOURCE_ID")
    or os.environ.get("BYTEDANCE_RESOURCE_ID")
    or os.environ.get("BYTEDANCE_TTS_RESOURCE_ID")
    or "seed-tts-2.0"
)
DEFAULT_SPEAKER = (
    os.environ.get("VOLC_SPEAKER")
    or os.environ.get("BYTEDANCE_TTS_SPEAKER")
    or "zh_female_vv_uranus_bigtts"
)
DEFAULT_SAMPLE_RATE = 24000
DEFAULT_MAX_CHARS = 480
DEFAULT_UID = "work100100"

# Event codes documented in the WS V3 doc.
EVENT_CONNECTION_FINISHED = 52
EVENT_SESSION_FINISHED = 152
EVENT_TTS_SENTENCE_START = 350
EVENT_TTS_SENTENCE_END = 351
EVENT_TTS_RESPONSE = 352
EVENT_TTS_SUBTITLE = 354  # not shown in some tables, but used when subtitle is enabled


def env_first(*names: str, default: str = "") -> str:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return default


APP_ID = env_first("VOLC_APP_ID", "BYTEDANCE_APP_ID", "BYTEDANCE_TTS_APPID")
ACCESS_KEY = env_first(
    "VOLC_ACCESS_TOKEN",
    "BYTEDANCE_ACCESS_KEY",
    "BYTEDANCE_TTS_ACCESS_TOKEN",
    "BYTEDANCE_TTS_KEY",
)


# ----------------------------- text splitting ----------------------------- #


def split_text(text: str, max_len: int = DEFAULT_MAX_CHARS) -> list[str]:
    """
    Split text at sentence boundaries when possible.
    Keeps punctuation, prefers paragraph/sentence breaks, then commas, then hard cut.
    """
    text = text.strip()
    if not text:
        return []

    # Preserve separators by splitting *after* them.
    parts = re.split(r"(?<=[。！？；\n.!?;])", text)

    chunks: list[str] = []
    buf = ""

    for part in parts:
        if not part:
            continue

        if buf and len(buf) + len(part) > max_len:
            chunks.append(buf.strip())
            buf = ""

        buf += part

        # Oversized single sentence: try commas/pauses, otherwise hard split.
        while len(buf) > max_len:
            cut = -1
            for sep in ["\n", "，", ",", "、", "：", ":"]:
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


# ------------------------------- WAV helper ------------------------------- #


def make_wav_header(
    data_size: int,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
    bits_per_sample: int = 16,
    channels: int = 1,
) -> bytes:
    byte_rate = sample_rate * channels * bits_per_sample // 8
    block_align = channels * bits_per_sample // 8
    header_size = 44
    file_size = header_size - 8 + data_size

    hdr = bytearray()
    hdr += b"RIFF"
    hdr += struct.pack("<I", file_size)
    hdr += b"WAVE"
    hdr += b"fmt "
    hdr += struct.pack("<I", 16)
    hdr += struct.pack("<H", 1)
    hdr += struct.pack("<H", channels)
    hdr += struct.pack("<I", sample_rate)
    hdr += struct.pack("<I", byte_rate)
    hdr += struct.pack("<H", block_align)
    hdr += struct.pack("<H", bits_per_sample)
    hdr += b"data"
    hdr += struct.pack("<I", data_size)
    return bytes(hdr)


# ---------------------------- WS frame helpers ---------------------------- #


def be_u32(data: bytes) -> int:
    return struct.unpack(">I", data)[0]


def build_ws_frame(payload_json: dict[str, Any], finish: bool = False) -> bytes:
    payload = json.dumps(
        payload_json, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")

    # Byte 0: version=1, header_size=1 (4 bytes)
    b0 = (0x1 << 4) | 0x1
    # Byte 1: message_type=1 (client request), flags=0 for sendText, 4 for finishConnection
    b1 = (0x1 << 4) | (0x4 if finish else 0x0)
    # Byte 2: serialization=JSON(1), compression=none(0)
    b2 = (0x1 << 4) | 0x0
    b3 = 0x00

    return bytes([b0, b1, b2, b3]) + struct.pack(">I", len(payload)) + payload


def parse_server_frame(frame: bytes) -> dict[str, Any]:
    if len(frame) < 4:
        raise RuntimeError(f"Frame too short: {len(frame)} bytes")

    b0, b1, b2, _ = frame[:4]
    header_words = b0 & 0x0F
    header_size = header_words * 4
    if len(frame) < header_size:
        raise RuntimeError("Invalid header size in frame")

    message_type = (b1 >> 4) & 0x0F
    flags = b1 & 0x0F
    serialization = (b2 >> 4) & 0x0F
    compression = b2 & 0x0F
    pos = header_size

    out: dict[str, Any] = {
        "message_type": message_type,
        "flags": flags,
        "serialization": serialization,
        "compression": compression,
    }

    # Error frame.
    if b1 == 0xF0 or message_type == 0x0F:
        if len(frame) < pos + 4:
            raise RuntimeError("Malformed error frame")
        error_code = be_u32(frame[pos : pos + 4])
        payload = frame[pos + 4 :]
        out["error_code"] = error_code
        out["payload_raw"] = payload
        out["payload_text"] = safe_decode(payload)
        return out

    # Normal response frames use event number when flags == 0x4.
    if flags != 0x04:
        out["payload_raw"] = frame[pos:]
        return out

    if len(frame) < pos + 4:
        raise RuntimeError("Missing event number")
    event = be_u32(frame[pos : pos + 4])
    pos += 4
    out["event"] = event

    if len(frame) < pos + 4:
        raise RuntimeError("Missing session_id length")
    session_id_len = be_u32(frame[pos : pos + 4])
    pos += 4

    if len(frame) < pos + session_id_len:
        raise RuntimeError("Incomplete session_id bytes")
    session_id_bytes = frame[pos : pos + session_id_len]
    pos += session_id_len
    out["session_id"] = safe_decode(session_id_bytes)

    payload = b""
    if len(frame) >= pos + 4:
        payload_len = be_u32(frame[pos : pos + 4])
        pos += 4
        payload = frame[pos : pos + payload_len]
        out["payload_len"] = payload_len
    else:
        payload = frame[pos:]

    out["payload_raw"] = payload
    out["payload_text"] = safe_decode(payload)
    out["payload_json"] = try_parse_json(out["payload_text"])
    return out


# ------------------------------- misc utils ------------------------------- #


def safe_decode(data: bytes) -> str:
    if not data:
        return ""
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("utf-8", errors="replace")


def try_parse_json(text: str) -> Any:
    if not text:
        return None
    try:
        return json.loads(text)
    except Exception:
        return None


def short_preview(text: str, width: int = 40) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= width else text[:width] + "…"


# ------------------------------ WS TTS client ----------------------------- #


class WSLongTTS:
    def __init__(
        self,
        app_id: str,
        access_key: str,
        resource_id: str,
        speaker: str,
        sample_rate: int = DEFAULT_SAMPLE_RATE,
        uid: str = DEFAULT_UID,
        verbose: bool = True,
    ) -> None:
        if not app_id:
            raise ValueError("Missing APP ID. Set VOLC_APP_ID or BYTEDANCE_TTS_APPID.")
        if not access_key:
            raise ValueError(
                "Missing access token/key. Set VOLC_ACCESS_TOKEN or BYTEDANCE_TTS_ACCESS_TOKEN."
            )

        self.app_id = app_id
        self.access_key = access_key
        self.resource_id = resource_id
        self.speaker = speaker
        self.sample_rate = sample_rate
        self.uid = uid
        self.verbose = verbose
        self.ws: websocket.WebSocket | None = None

    def connect(self) -> None:
        headers = [
            f"X-Api-App-Id: {self.app_id}",
            f"X-Api-Access-Key: {self.access_key}",
            f"X-Api-Resource-Id: {self.resource_id}",
            f"X-Api-Request-Id: {uuid.uuid4()}",
            "X-Control-Require-Usage-Tokens-Return: *",
        ]

        if (
            "tts_async" in self.resource_id
            or self.resource_id == "volc.tts_async.default"
        ):
            raise ValueError(
                "This resource_id looks like the async long-text service, not WS V3 TTS. "
                "Use a WS V3 TTS resource_id such as seed-tts-2.0 / seed-tts-1.0 / seed-icl-2.0."
            )

        self.ws = websocket.create_connection(
            WS_URL,
            header=headers,
            timeout=180,
            enable_multithread=False,
        )

    def close(self) -> None:
        if self.ws is None:
            return
        try:
            finish_payload: dict[str, Any] = {}
            self.ws.send_binary(build_ws_frame(finish_payload, finish=True))
            # Read until the connection-finished response or timeout.
            deadline = time.time() + 5
            while time.time() < deadline:
                frame = self.ws.recv()
                if not isinstance(frame, (bytes, bytearray)):
                    continue
                parsed = parse_server_frame(bytes(frame))
                if parsed.get("event") == EVENT_CONNECTION_FINISHED:
                    break
        except Exception:
            pass
        finally:
            try:
                self.ws.close()
            finally:
                self.ws = None

    def synthesize_once(
        self,
        text: str,
        fmt: str,
        *,
        model: str = "",
        speech_rate: int = 0,
        loudness_rate: int = 0,
        emotion: str = "",
        emotion_scale: int = 4,
        explicit_language: str = "",
        context_text: str = "",
        previous_session_id: str = "",
        use_section_id: bool = True,
        disable_markdown_filter: bool = True,
        enable_language_detector: bool = True,
        enable_latex_tn: bool = True,
        use_cache: bool = False,
    ) -> tuple[bytes, str, dict[str, Any] | None]:
        if self.ws is None:
            raise RuntimeError("WebSocket is not connected")

        additions: dict[str, Any] = {
            "disable_markdown_filter": disable_markdown_filter,
            "enable_language_detector": enable_language_detector,
            "enable_latex_tn": enable_latex_tn,
            "max_length_to_filter_parenthesis": 0,
        }
        if use_cache:
            additions["cache_config"] = {"text_type": 1, "use_cache": True}
        if explicit_language:
            additions["explicit_language"] = explicit_language
        if use_section_id and previous_session_id:
            additions["section_id"] = previous_session_id
        if context_text:
            additions["context_texts"] = [context_text]

        req_params: dict[str, Any] = {
            "text": text,
            "speaker": self.speaker,
            "audio_params": {
                "format": fmt,
                "sample_rate": self.sample_rate,
                "speech_rate": speech_rate,
                "loudness_rate": loudness_rate,
            },
            # WS V3 expects req_params.additions as a JSON string, not an object.
            "additions": json.dumps(
                additions, ensure_ascii=False, separators=(",", ":")
            ),
        }
        if model:
            req_params["model"] = model
        if emotion:
            req_params["audio_params"]["emotion"] = emotion
            req_params["audio_params"]["emotion_scale"] = emotion_scale

        payload = {
            "user": {"uid": self.uid},
            "req_params": req_params,
        }

        self.ws.send_binary(build_ws_frame(payload, finish=False))

        audio_parts: list[bytes] = []
        session_id = ""
        final_meta: dict[str, Any] | None = None

        while True:
            raw = self.ws.recv()
            if not isinstance(raw, (bytes, bytearray)):
                continue

            parsed = parse_server_frame(bytes(raw))

            if "error_code" in parsed:
                raise RuntimeError(
                    f"WS error {parsed['error_code']}: {parsed.get('payload_text') or parsed.get('payload_raw')}"
                )

            event = parsed.get("event")
            frame_session_id = parsed.get("session_id") or ""
            if frame_session_id and not session_id:
                session_id = frame_session_id

            if event == EVENT_TTS_RESPONSE:
                audio_parts.append(parsed.get("payload_raw", b""))
                continue

            if event == EVENT_TTS_SENTENCE_START:
                continue

            if event == EVENT_TTS_SENTENCE_END:
                continue

            if event == EVENT_TTS_SUBTITLE:
                continue

            if event == EVENT_SESSION_FINISHED:
                final_meta = parsed.get("payload_json")
                if final_meta is None:
                    final_meta = {"raw": parsed.get("payload_text", "")}
                break

        return b"".join(audio_parts), session_id, final_meta


# ------------------------------ orchestration ----------------------------- #


def synthesize_long(
    client: WSLongTTS,
    text: str,
    output_format: str = "wav",
    max_chars: int = DEFAULT_MAX_CHARS,
    model: str = "",
    speech_rate: int = 0,
    loudness_rate: int = 0,
    emotion: str = "",
    emotion_scale: int = 4,
    explicit_language: str = "",
    use_section_id: bool = True,
    disable_markdown_filter: bool = True,
    enable_language_detector: bool = True,
    enable_latex_tn: bool = True,
    use_cache: bool = False,
    verbose: bool = True,
) -> bytes:
    chunks = split_text(text, max_chars)
    if not chunks:
        raise ValueError("Input text is empty after stripping")

    total = len(chunks)
    api_format = "pcm" if output_format == "wav" else output_format

    if verbose:
        print(f"  Split into {total} chunk(s)  (max {max_chars} chars/chunk)")

    all_audio: list[bytes] = []
    previous_session_id = ""

    client.connect()
    try:
        for idx, chunk in enumerate(chunks, 1):
            if verbose:
                print(f"  [{idx}/{total}] {len(chunk)} chars: {short_preview(chunk)}")

            t0 = time.time()
            audio, session_id, meta = client.synthesize_once(
                chunk,
                api_format,
                model=model,
                speech_rate=speech_rate,
                loudness_rate=loudness_rate,
                emotion=emotion,
                emotion_scale=emotion_scale,
                explicit_language=explicit_language,
                previous_session_id=previous_session_id,
                use_section_id=use_section_id,
                disable_markdown_filter=disable_markdown_filter,
                enable_language_detector=enable_language_detector,
                enable_latex_tn=enable_latex_tn,
                use_cache=use_cache,
            )
            dt = time.time() - t0

            previous_session_id = session_id or previous_session_id
            all_audio.append(audio)

            if verbose:
                usage = None
                if isinstance(meta, dict):
                    usage = meta.get("usage")
                usage_text = f" usage={usage}" if usage else ""
                sid_text = f" session_id={session_id}" if session_id else ""
                print(
                    f"      -> {len(audio):,} bytes  ({dt:.1f}s){sid_text}{usage_text}"
                )
    finally:
        client.close()

    combined = b"".join(all_audio)
    if output_format == "wav":
        combined = make_wav_header(len(combined), client.sample_rate) + combined
    return combined


# ---------------------------------- CLI ---------------------------------- #


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Long-text TTS via Volcano WS V3 (default WAV)."
    )
    parser.add_argument("text_file", type=Path, help="UTF-8 text file to synthesize")

    fmt = parser.add_mutually_exclusive_group()
    fmt.add_argument("--mp3", action="store_true", help="Output MP3 instead of WAV")
    fmt.add_argument("--wav", action="store_true", help="Output WAV (default)")

    parser.add_argument("--appid", default=APP_ID, help="Volcano APP ID")
    parser.add_argument(
        "--access-token", default=ACCESS_KEY, help="Volcano Access Token / Access Key"
    )
    parser.add_argument(
        "--resource-id",
        default=DEFAULT_RESOURCE_ID,
        help=f"Resource ID (default: {DEFAULT_RESOURCE_ID})",
    )
    parser.add_argument(
        "--speaker",
        default=DEFAULT_SPEAKER,
        help=f"Speaker ID (default: {DEFAULT_SPEAKER})",
    )
    parser.add_argument(
        "--uid", default=DEFAULT_UID, help=f"User UID (default: {DEFAULT_UID})"
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        default=DEFAULT_SAMPLE_RATE,
        help=f"Sample rate (default: {DEFAULT_SAMPLE_RATE})",
    )
    parser.add_argument(
        "--maxchars",
        type=int,
        default=DEFAULT_MAX_CHARS,
        help=f"Max chars per chunk (default: {DEFAULT_MAX_CHARS})",
    )

    parser.add_argument(
        "--model", default="", help="Optional model name to pass through"
    )
    parser.add_argument(
        "--speech-rate", type=int, default=0, help="speech_rate in [-50,100]"
    )
    parser.add_argument(
        "--loudness-rate", type=int, default=0, help="loudness_rate in [-50,100]"
    )
    parser.add_argument("--emotion", default="", help="Optional emotion name")
    parser.add_argument(
        "--emotion-scale", type=int, default=4, help="emotion_scale in [1,5]"
    )
    parser.add_argument(
        "--explicit-language",
        default="",
        help="Optional explicit_language, e.g. zh-cn or en",
    )

    parser.add_argument(
        "--no-section-id",
        action="store_true",
        help="Do not chain chunks with previous session_id",
    )
    parser.add_argument(
        "--disable-markdown-filter",
        action="store_true",
        help="Parse/filter markdown syntax",
    )
    parser.add_argument(
        "--disable-language-detector",
        action="store_true",
        help="Disable auto language detector",
    )
    parser.add_argument(
        "--disable-latex-tn", action="store_true", help="Disable LaTeX TN support"
    )
    parser.add_argument(
        "--use-cache",
        action="store_true",
        help="Enable server cache for identical text",
    )
    parser.add_argument("--quiet", action="store_true", help="Reduce console output")

    return parser


def main() -> None:
    parser = build_arg_parser()
    args = parser.parse_args()

    if not args.text_file.is_file():
        raise SystemExit(f"Error: file not found: {args.text_file}")

    text = args.text_file.read_text(encoding="utf-8").strip()
    if not text:
        raise SystemExit("Error: input file is empty")

    output_format = "mp3" if args.mp3 else "wav"
    out_path = args.text_file.with_suffix(f".{output_format}")
    verbose = not args.quiet

    if verbose:
        print(
            f"[ttsws] {output_format.upper()} <- {args.text_file}  ({len(text):,} chars)"
        )
        print(f"[ttsws] resource_id={args.resource_id} speaker={args.speaker}")

    client = WSLongTTS(
        app_id=args.appid,
        access_key=args.access_token,
        resource_id=args.resource_id,
        speaker=args.speaker,
        sample_rate=args.sample_rate,
        uid=args.uid,
        verbose=verbose,
    )

    audio = synthesize_long(
        client,
        text,
        output_format=output_format,
        max_chars=args.maxchars,
        model=args.model,
        speech_rate=args.speech_rate,
        loudness_rate=args.loudness_rate,
        emotion=args.emotion,
        emotion_scale=args.emotion_scale,
        explicit_language=args.explicit_language,
        use_section_id=not args.no_section_id,
        disable_markdown_filter=not args.disable_markdown_filter,
        enable_language_detector=not args.disable_language_detector,
        enable_latex_tn=not args.disable_latex_tn,
        use_cache=args.use_cache,
        verbose=verbose,
    )

    out_path.write_bytes(audio)
    if verbose:
        print(f"[ttsws] Saved {out_path}  ({len(audio):,} bytes)")


if __name__ == "__main__":
    main()
