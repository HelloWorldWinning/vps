#!/usr/bin/env python3
"""
kk / km  --  ls -laF style listing with a tiktoken (gpt-4o) token count column.

  kk   sort by mtime, OLDEST first  -> newest modified file at the BOTTOM
  km   sort by name, A-Z ascending

Install:
  sudo install -m 0755 kk.py /usr/local/bin/kk
  sudo ln -sf kk /usr/local/bin/km          # same script, behaviour from argv[0]

Behaviour is chosen by the program name, so the symlink is all you need.
"""

from __future__ import annotations

# ===========================================================================
# WARNING 1 -- only these are tokenized (pure text / string-content files).
#              Everything else (mp4, jpg, zip, pdf, .so, ...) shows "-".
#              EDIT THIS LIST FREELY.
# ===========================================================================
TEXT_EXTS = {
    # plain text / docs
    "txt",
    "text",
    "md",
    "markdown",
    "rst",
    "org",
    "adoc",
    "asciidoc",
    "tex",
    "log",
    "csv",
    "tsv",
    "srt",
    "vtt",
    # config / data
    "yaml",
    "yml",
    "toml",
    "ini",
    "cfg",
    "conf",
    "config",
    "properties",
    "json",
    "json5",
    "jsonl",
    "ndjson",
    "xml",
    "env",
    "editorconfig",
    # code
    "py",
    "pyi",
    "ipynb",
    "sh",
    "bash",
    "zsh",
    "fish",
    "ps1",
    "bat",
    "c",
    "h",
    "cc",
    "cpp",
    "hpp",
    "cxx",
    "hxx",
    "rs",
    "go",
    "java",
    "kt",
    "kts",
    "scala",
    "swift",
    "m",
    "mm",
    "cs",
    "vb",
    "lua",
    "vim",
    "el",
    "js",
    "mjs",
    "cjs",
    "jsx",
    "ts",
    "tsx",
    "vue",
    "svelte",
    "html",
    "htm",
    "css",
    "scss",
    "sass",
    "less",
    "sql",
    "graphql",
    "gql",
    "proto",
    "thrift",
    "r",
    "jl",
    "rb",
    "pl",
    "pm",
    "php",
    "hs",
    "ml",
    "ex",
    "exs",
    "erl",
    "nim",
    "zig",
    "dart",
    "clj",
    "cljs",
    "f90",
    "f95",
    "for",
    # build / infra
    "make",
    "mk",
    "cmake",
    "gradle",
    "sbt",
    "bzl",
    "bazel",
    "nix",
    "dockerfile",
    "tf",
    "tfvars",
    "hcl",
    "service",
    "desktop",
    "patch",
    "diff",
    "lock",
    "gitignore",
    "gitattributes",
}

# Extensionless files that are still text (matched on the full lowercase name).
TEXT_NAMES = {
    "makefile",
    "gnumakefile",
    "dockerfile",
    "containerfile",
    "jenkinsfile",
    "rakefile",
    "gemfile",
    "procfile",
    "vagrantfile",
    "cmakelists.txt",
    "readme",
    "license",
    "licence",
    "copying",
    "authors",
    "changelog",
    "notice",
    "todo",
    "install",
    "news",
    "manifest",
    ".bashrc",
    ".bash_profile",
    ".bash_aliases",
    ".zshrc",
    ".profile",
    ".vimrc",
    ".gitconfig",
    ".gitignore",
    ".inputrc",
    ".tmux.conf",
}

# ===========================================================================
# WARNING 2 -- files larger than this are never read/tokenized (shows ">50M").
# ===========================================================================
MAX_BYTES = 50 * 1024 * 1024  # 50 MiB

# ---- other knobs ----------------------------------------------------------
MODEL = "gpt-4o"  # tiktoken encoding_for_model target
FALLBACK_ENCODING = "o200k_base"  # used if the model lookup fails
CACHE_PATH = "~/.cache/kk/tokens.json"
CACHE_MAX_ENTRIES = 20000
SHOW_TOTAL = True  # print a total-tokens footer
BATCH = 16  # files encoded per tiktoken batch call
# ===========================================================================

import json
import os
import pwd
import stat
import sys
from datetime import datetime

# ------------------------------------------------------------------ helpers


def is_text_candidate(name: str) -> bool:
    low = name.lower()
    if low in TEXT_NAMES:
        return True
    root, dot, ext = low.rpartition(".")
    if dot and ext in TEXT_EXTS:
        return True
    # things like "file.tar.gz" already fail above; extensionless non-listed -> no
    return False


def looks_binary(data: bytes) -> bool:
    return b"\x00" in data[:8192]


def human_size(n: int) -> str:
    """eza-ish: 512, 9.6k, 26k, 1.2M, 112M, 3.4G"""
    if n < 1024:
        return str(n)
    v = float(n)
    for unit in ("k", "M", "G", "T", "P"):
        v /= 1024.0
        if v < 1024.0:
            return f"{v:.1f}{unit}" if v < 10 else f"{v:.0f}{unit}"
    return f"{v:.0f}E"


def mode_string(st: os.stat_result) -> str:
    m = st.st_mode
    if stat.S_ISDIR(m):
        head = "d"
    elif stat.S_ISLNK(m):
        head = "l"
    elif stat.S_ISFIFO(m):
        head = "p"
    elif stat.S_ISSOCK(m):
        head = "s"
    elif stat.S_ISBLK(m):
        head = "b"
    elif stat.S_ISCHR(m):
        head = "c"
    else:
        head = "."  # eza style for regular files
    bits = ""
    for who, r, w, x in (
        ("u", stat.S_IRUSR, stat.S_IWUSR, stat.S_IXUSR),
        ("g", stat.S_IRGRP, stat.S_IWGRP, stat.S_IXGRP),
        ("o", stat.S_IROTH, stat.S_IWOTH, stat.S_IXOTH),
    ):
        bits += "r" if m & r else "-"
        bits += "w" if m & w else "-"
        bits += "x" if m & x else "-"
    return head + bits


def owner_name(uid: int) -> str:
    try:
        return pwd.getpwuid(uid).pw_name
    except KeyError:
        return str(uid)


def fmt_time(ts: float, now_year: int) -> str:
    d = datetime.fromtimestamp(ts)
    if d.year == now_year:
        return f"{d.day:>2} {d:%b} {d:%H:%M}"
    return f"{d.day:>2} {d:%b}  {d.year}"


def classify_suffix(st: os.stat_result, path: str) -> str:
    m = st.st_mode
    if stat.S_ISLNK(m):
        return "@"
    if stat.S_ISDIR(m):
        return "/"
    if stat.S_ISFIFO(m):
        return "|"
    if stat.S_ISSOCK(m):
        return "="
    if m & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
        return "*"
    return ""


# ------------------------------------------------------------------- cache


def cache_load() -> dict:
    p = os.path.expanduser(CACHE_PATH)
    try:
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def cache_save(cache: dict) -> None:
    if len(cache) > CACHE_MAX_ENTRIES:
        # cheap prune: keep the newest half by insertion order
        items = list(cache.items())[-CACHE_MAX_ENTRIES // 2 :]
        cache = dict(items)
    p = os.path.expanduser(CACHE_PATH)
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        tmp = p + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(cache, f)
        os.replace(tmp, p)
    except Exception:
        pass


# ---------------------------------------------------------------- encoder

_ENC = None
_ENC_TRIED = False


def get_encoder():
    global _ENC, _ENC_TRIED
    if _ENC_TRIED:
        return _ENC
    _ENC_TRIED = True
    try:
        import tiktoken

        try:
            _ENC = tiktoken.encoding_for_model(MODEL)
        except Exception:
            _ENC = tiktoken.get_encoding(FALLBACK_ENCODING)
    except Exception as e:
        print(f"kk: tiktoken unavailable ({e}); token column disabled", file=sys.stderr)
        _ENC = None
    return _ENC


# ------------------------------------------------------------------ listing


class Entry:
    __slots__ = ("name", "path", "st", "tok", "note")

    def __init__(self, name, path, st):
        self.name = name
        self.path = path
        self.st = st
        self.tok = None  # int token count
        self.note = "-"  # shown when tok is None


def collect(paths):
    entries = []
    for p in paths:
        try:
            st = os.lstat(p)
        except OSError as e:
            print(f"kk: {p}: {e.strerror}", file=sys.stderr)
            continue
        if stat.S_ISDIR(st.st_mode) and not os.path.islink(p):
            try:
                names = os.listdir(p)
            except OSError as e:
                print(f"kk: {p}: {e.strerror}", file=sys.stderr)
                continue
            for n in names:
                full = os.path.join(p, n)
                try:
                    entries.append(Entry(n, full, os.lstat(full)))
                except OSError:
                    pass
        else:
            entries.append(Entry(os.path.basename(p) or p, p, st))
    return entries


def count_tokens(entries, cache):
    pending = []  # (entry, text)
    for e in entries:
        st = e.st
        if not stat.S_ISREG(st.st_mode):
            e.note = "-"
            continue
        if not is_text_candidate(e.name):
            e.note = "-"
            continue
        if st.st_size > MAX_BYTES:
            e.note = ">" + human_size(MAX_BYTES)
            continue
        if st.st_size == 0:
            e.tok = 0
            continue
        key = f"{os.path.realpath(e.path)}|{st.st_mtime_ns}|{st.st_size}"
        hit = cache.get(key)
        if isinstance(hit, int):
            e.tok = hit
            continue
        try:
            with open(e.path, "rb") as f:
                data = f.read(MAX_BYTES + 1)
        except OSError:
            e.note = "err"
            continue
        if looks_binary(data):
            e.note = "-"
            continue
        pending.append((e, key, data.decode("utf-8", errors="replace")))

    if not pending:
        return

    enc = get_encoder()
    if enc is None:
        for e, _k, _t in pending:
            e.note = "?"
        return

    for i in range(0, len(pending), BATCH):
        chunk = pending[i : i + BATCH]
        texts = [t for _e, _k, t in chunk]
        try:
            # encode_ordinary_* never raises on "<|endoftext|>"-like strings
            toks = enc.encode_ordinary_batch(texts, num_threads=8)
        except Exception:
            toks = []
            for t in texts:
                try:
                    toks.append(enc.encode_ordinary(t))
                except Exception:
                    toks.append(None)
        for (e, key, _t), out in zip(chunk, toks):
            if out is None:
                e.note = "err"
            else:
                e.tok = len(out)
                cache[key] = e.tok


def render(entries, use_color):
    now_year = datetime.now().year
    rows = []
    for e in entries:
        st = e.st
        tok = f"{e.tok:,}" if e.tok is not None else e.note
        name = e.name + classify_suffix(st, e.path)
        if stat.S_ISLNK(st.st_mode):
            try:
                name += " -> " + os.readlink(e.path)
            except OSError:
                pass
        rows.append(
            (
                mode_string(st),
                human_size(st.st_size),
                owner_name(st.st_uid),
                fmt_time(st.st_mtime, now_year),
                tok,
                name,
                st.st_mode,
            )
        )

    if not rows:
        return

    w_mode = max(len(r[0]) for r in rows)
    w_size = max(len(r[1]) for r in rows)
    w_user = max(len(r[2]) for r in rows)
    w_date = max(len(r[3]) for r in rows)
    w_tok = max(len(r[4]) for r in rows)

    B, D, C, R = (
        ("\033[34;1m", "\033[2m", "\033[36m", "\033[0m")
        if use_color
        else ("", "", "", "")
    )

    out = []
    for mode, size, user, date, tok, name, m in rows:
        nm = f"{B}{name}{R}" if stat.S_ISDIR(m) else name
        out.append(
            f"{mode:<{w_mode}} {size:>{w_size}} {D}{user:<{w_user}}{R} "
            f"{date:>{w_date}} {C}{tok:>{w_tok}}{R}  {nm}"
        )
    sys.stdout.write("\n".join(out) + "\n")

    if SHOW_TOTAL:
        total = sum(e.tok for e in entries if e.tok is not None)
        counted = sum(1 for e in entries if e.tok is not None)
        sys.stdout.write(f"{D}-- {total:,} tokens in {counted} file(s){R}\n")


def main(argv):
    prog = os.path.basename(argv[0])
    args = [a for a in argv[1:] if a not in ("--",)]
    if any(a in ("-h", "--help") for a in args):
        print(__doc__)
        return 0
    paths = [a for a in args if not a.startswith("-")] or ["."]

    entries = collect(paths)
    if not entries:
        return 0

    cache = cache_load()
    before = len(cache)
    count_tokens(entries, cache)
    if len(cache) != before:
        cache_save(cache)

    if prog.startswith("km"):
        entries.sort(key=lambda e: (e.name.lower().lstrip("."), e.name))
    else:  # kk: oldest first -> newest at the bottom
        entries.sort(key=lambda e: e.st.st_mtime_ns)

    render(entries, use_color=sys.stdout.isatty())
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except BrokenPipeError:
        os._exit(0)
    except KeyboardInterrupt:
        sys.exit(130)
