#!/usr/bin/env python3
"""
kk / kkk  --  ls -laF style listing with a tiktoken (gpt-4o) token count column,
              themed to look like `eza --icons -laF --sort=modified` (the `l` alias).

  kk    sort by mtime, OLDEST first  -> newest modified file at the BOTTOM
  kkk   sort by name, A-Z ascending

Options:
  --color=auto|always|never   default auto (honors NO_COLOR); use `always` when piping to `less -R`
  --icons / --no-icons        default on (KK_ICONS=0 disables permanently)
  -h, --help

Install:
  sudo install -m 0755 kk.py /usr/local/bin/kk
  sudo ln -sf /usr/local/bin/kk /usr/local/bin/kkk   # same script, behaviour from argv[0]

Behaviour is chosen by the program name, so the symlink is all you need.
"""

from __future__ import annotations

import json
import os
import pwd
import re
import stat
import sys
from datetime import datetime

C_FOOTER_TOKENS = "1;31"  # bold red
C_FOOTER_FILES = "1;34"  # bold blue

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
# WARNING 3 -- THEME. Everything below is cosmetic; edit freely.
#              File-name colours come from $LS_COLORS (same source eza uses),
#              falling back to DEFAULT_LS_COLORS when it is unset.
# ===========================================================================
HONOR_LS_COLORS = True
ICONS_DEFAULT = os.environ.get("KK_ICONS", "1") != "0"

# eza-ish colours for the metadata columns (SGR codes, no \033[ ... m wrapper)
C_TYPE = {
    "d": "1;34",
    "l": "1;36",
    "p": "33",
    "s": "1;35",
    "b": "1;33",
    "c": "1;33",
    ".": "2;37",
}
C_READ = "1;33"  # r
C_WRITE = "1;31"  # w
C_EXEC = "1;32"  # x
C_DASH = "2;37"  # -
C_SIZE_NUM = "32"  # 9.6 in "9.6k"
C_SIZE_UNIT = "2;32"  # k  in "9.6k"
C_USER_ME = "1;33"
C_USER_OTHER = "2;33"
C_DATE = "34"
# C_TOKENS = "36"
C_TOKENS = "1;31"
C_ARROW = "2;37"  # the -> of a symlink
C_BROKEN = "1;31"
C_FOOTER = "2"


# Used only when $LS_COLORS is empty (GNU dircolors defaults + a few extras).
DEFAULT_LS_COLORS = (
    "di=01;34:ln=01;36:so=01;35:pi=40;33:ex=01;32:bd=40;33;01:cd=40;33;01:"
    "su=37;41:sg=30;43:tw=30;42:ow=34;42:st=37;44:or=40;31;01:"
    "*.tar=01;31:*.tgz=01;31:*.zip=01;31:*.gz=01;31:*.bz2=01;31:*.xz=01;31:"
    "*.zst=01;31:*.7z=01;31:*.rar=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:"
    "*.jpg=01;35:*.jpeg=01;35:*.png=01;35:*.gif=01;35:*.bmp=01;35:*.svg=01;35:"
    "*.webp=01;35:*.tif=01;35:*.tiff=01;35:*.ico=01;35:"
    "*.mp4=01;35:*.mkv=01;35:*.webm=01;35:*.avi=01;35:*.mov=01;35:*.flv=01;35:"
    "*.mp3=00;36:*.flac=00;36:*.wav=00;36:*.ogg=00;36:*.m4a=00;36:"
    "*.pdf=00;35:*.doc=00;35:*.docx=00;35:*.xls=00;35:*.xlsx=00;35:"
    "*.ppt=00;35:*.pptx=00;35:*.epub=00;35:"
    "*.py=00;33:*.rs=00;33:*.go=00;33:*.c=00;33:*.h=00;33:*.cpp=00;33:"
    "*.hpp=00;33:*.js=00;33:*.ts=00;33:*.tsx=00;33:*.jsx=00;33:*.rb=00;33:"
    "*.java=00;33:*.lua=00;33:*.jl=00;33:*.r=00;33:"
    "*.sh=00;32:*.bash=00;32:*.zsh=00;32:*.fish=00;32:"
    "*.md=00;36:*.rst=00;36:*.txt=00;37:*.ipynb=00;33:"
    "*.json=00;33:*.yml=00;33:*.yaml=00;33:*.toml=00;33:*.ini=00;33:*.cfg=00;33:"
    "*.log=00;90:*.bak=00;90:*.tmp=00;90:*.swp=00;90:*.o=00;90:*.pyc=00;90:"
    "*.lock=00;90:*.class=00;90:*.so=01;31:*.a=01;31:"
)

# Nerd Font glyphs (needs a Nerd Font in your terminal, same as `eza --icons`).
ICON_DEFAULT = "\uf15b"  #
ICON_DIR = "\uf07b"  #
ICON_LINK = "\uf0c1"  #
ICON_EXEC = "\uf489"  #
ICON_PIPE = "\ufce3"  #
ICON_SOCK = "\uf6ff"  #
ICON_DEV = "\ue266"  #

ICON_EXTS = {
    "py": "\ue73c",
    "pyi": "\ue73c",
    "pyc": "\ue73c",
    "ipynb": "\ue678",
    "js": "\ue74e",
    "mjs": "\ue74e",
    "cjs": "\ue74e",
    "jsx": "\ue7ba",
    "ts": "\ue628",
    "tsx": "\ue7ba",
    "vue": "\ufd42",
    "svelte": "\ue697",
    "json": "\ue60b",
    "json5": "\ue60b",
    "jsonl": "\ue60b",
    "ndjson": "\ue60b",
    "yml": "\uf481",
    "yaml": "\uf481",
    "toml": "\ue615",
    "ini": "\ue615",
    "cfg": "\ue615",
    "conf": "\ue615",
    "config": "\ue615",
    "properties": "\ue615",
    "env": "\uf462",
    "editorconfig": "\ue615",
    "md": "\uf48a",
    "markdown": "\uf48a",
    "rst": "\uf48a",
    "org": "\ue633",
    "txt": "\uf15c",
    "text": "\uf15c",
    "log": "\uf18d",
    "csv": "\uf1c3",
    "tsv": "\uf1c3",
    "tex": "\uf034",
    "adoc": "\uf48a",
    "asciidoc": "\uf48a",
    "srt": "\uf02d",
    "vtt": "\uf02d",
    "sh": "\uf489",
    "bash": "\uf489",
    "zsh": "\uf489",
    "fish": "\uf489",
    "ps1": "\uf489",
    "bat": "\uf489",
    "c": "\ue61e",
    "h": "\uf0fd",
    "cc": "\ue61d",
    "cpp": "\ue61d",
    "cxx": "\ue61d",
    "hpp": "\uf0fd",
    "hxx": "\uf0fd",
    "rs": "\ue7a8",
    "go": "\ue627",
    "java": "\ue738",
    "class": "\ue738",
    "kt": "\ue634",
    "kts": "\ue634",
    "scala": "\ue737",
    "swift": "\ue755",
    "cs": "\uf81a",
    "vb": "\uf81a",
    "m": "\ue61e",
    "mm": "\ue61d",
    "lua": "\ue620",
    "vim": "\ue62b",
    "el": "\ue632",
    "rb": "\ue739",
    "pl": "\ue769",
    "pm": "\ue769",
    "php": "\ue73d",
    "hs": "\ue777",
    "ml": "\ue7a7",
    "ex": "\ue62d",
    "exs": "\ue62d",
    "erl": "\ue7b1",
    "nim": "\uf6a4",
    "zig": "\uf0e7",
    "dart": "\ue798",
    "clj": "\ue768",
    "cljs": "\ue76a",
    "jl": "\ue624",
    "r": "\uf25d",
    "f90": "\uf121",
    "f95": "\uf121",
    "for": "\uf121",
    "html": "\uf13b",
    "htm": "\uf13b",
    "css": "\ue749",
    "scss": "\ue749",
    "sass": "\ue74b",
    "less": "\ue758",
    "sql": "\uf1c0",
    "db": "\uf1c0",
    "sqlite": "\uf1c0",
    "sqlite3": "\uf1c0",
    "graphql": "\ue662",
    "gql": "\ue662",
    "proto": "\uf1e6",
    "thrift": "\uf1e6",
    "xml": "\ue619",
    "svg": "\uf1c5",
    "make": "\ue673",
    "mk": "\ue673",
    "cmake": "\ue673",
    "gradle": "\ue660",
    "sbt": "\ue737",
    "bzl": "\ue673",
    "bazel": "\ue673",
    "nix": "\uf313",
    "dockerfile": "\uf308",
    "tf": "\uf0e7",
    "tfvars": "\uf0e7",
    "hcl": "\uf0e7",
    "service": "\uf013",
    "desktop": "\uf108",
    "patch": "\uf440",
    "diff": "\uf440",
    "lock": "\uf023",
    "gitignore": "\ue702",
    "gitattributes": "\ue702",
    "jpg": "\uf1c5",
    "jpeg": "\uf1c5",
    "png": "\uf1c5",
    "gif": "\uf1c5",
    "bmp": "\uf1c5",
    "webp": "\uf1c5",
    "tif": "\uf1c5",
    "tiff": "\uf1c5",
    "ico": "\uf1c5",
    "mp3": "\uf001",
    "flac": "\uf001",
    "wav": "\uf001",
    "ogg": "\uf001",
    "m4a": "\uf001",
    "opus": "\uf001",
    "mp4": "\uf03d",
    "mkv": "\uf03d",
    "webm": "\uf03d",
    "avi": "\uf03d",
    "mov": "\uf03d",
    "flv": "\uf03d",
    "zip": "\uf410",
    "tar": "\uf410",
    "gz": "\uf410",
    "tgz": "\uf410",
    "bz2": "\uf410",
    "xz": "\uf410",
    "zst": "\uf410",
    "7z": "\uf410",
    "rar": "\uf410",
    "deb": "\uf306",
    "rpm": "\uf17c",
    "jar": "\ue738",
    "pdf": "\uf1c1",
    "doc": "\uf1c2",
    "docx": "\uf1c2",
    "xls": "\uf1c3",
    "xlsx": "\uf1c3",
    "ppt": "\uf1c4",
    "pptx": "\uf1c4",
    "epub": "\ue28b",
    "so": "\uf471",
    "a": "\uf471",
    "o": "\uf471",
    "bin": "\uf471",
    "iso": "\uf7c9",
    "img": "\uf7c9",
    "key": "\uf43d",
    "pem": "\uf43d",
    "crt": "\uf43d",
    "pub": "\uf43d",
    "ttf": "\uf031",
    "otf": "\uf031",
    "woff": "\uf031",
    "woff2": "\uf031",
}

ICON_NAMES = {
    "makefile": "\ue673",
    "gnumakefile": "\ue673",
    "cmakelists.txt": "\ue673",
    "dockerfile": "\uf308",
    "containerfile": "\uf308",
    "docker-compose.yml": "\uf308",
    "docker-compose.yaml": "\uf308",
    "jenkinsfile": "\ue767",
    "rakefile": "\ue739",
    "gemfile": "\ue739",
    "procfile": "\uf0e7",
    "vagrantfile": "\uf0e7",
    "readme": "\uf48a",
    "readme.md": "\uf48a",
    "license": "\uf718",
    "licence": "\uf718",
    "copying": "\uf718",
    "authors": "\uf0c0",
    "changelog": "\uf48a",
    "notice": "\uf48a",
    "todo": "\uf0ae",
    "install": "\uf48a",
    "news": "\uf48a",
    "manifest": "\uf48a",
    ".bashrc": "\uf489",
    ".bash_profile": "\uf489",
    ".bash_aliases": "\uf489",
    ".zshrc": "\uf489",
    ".profile": "\uf489",
    ".vimrc": "\ue62b",
    ".gitconfig": "\ue702",
    ".gitignore": "\ue702",
    ".git": "\ue702",
    ".github": "\uf408",
    ".inputrc": "\ue615",
    ".tmux.conf": "\uebc8",
    ".ssh": "\uf023",
    ".cache": "\uf49b",
    ".config": "\ue5fc",
    ".venv": "\ue73c",
    "venv": "\ue73c",
    "node_modules": "\ue718",
    ".DS_Store": "\uf179",
}
# ===========================================================================

RESET = "\033[0m"


# ------------------------------------------------------------------ helpers


def is_text_candidate(name: str) -> bool:
    low = name.lower()
    if low in TEXT_NAMES:
        return True
    root, dot, ext = low.rpartition(".")
    if dot and ext in TEXT_EXTS:
        return True
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


def split_size(s: str):
    m = re.match(r"^([\d.]+)(\D*)$", s)
    return (m.group(1), m.group(2)) if m else (s, "")


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


# -------------------------------------------------------------------- theme


class Theme:
    """Colours + icons, driven by $LS_COLORS the same way eza is."""

    def __init__(self, use_color: bool, use_icons: bool):
        self.on = use_color
        self.icons = use_icons
        raw = ""
        if HONOR_LS_COLORS:
            raw = os.environ.get("LS_COLORS", "") or ""
        if not raw.strip():
            raw = DEFAULT_LS_COLORS
        self.types: dict[str, str] = {}
        exts: dict[str, str] = {}
        for item in raw.split(":"):
            if not item or "=" not in item:
                continue
            key, _, val = item.partition("=")
            if key.startswith("*"):
                exts[key[1:].lower()] = val
            else:
                self.types[key] = val
        # longest suffix wins ("*.tar.gz" before "*.gz")
        self.exts = sorted(exts.items(), key=lambda kv: -len(kv[0]))

    # -- low level -------------------------------------------------------
    def paint(self, text: str, code: str) -> str:
        if not self.on or not code or code == "0" or code == "00":
            return text
        return f"\033[{code}m{text}{RESET}"

    # -- columns ---------------------------------------------------------
    def mode(self, s: str) -> str:
        if not self.on:
            return s
        out = [self.paint(s[0], C_TYPE.get(s[0], C_DASH))]
        for ch in s[1:]:
            if ch == "r":
                out.append(self.paint(ch, C_READ))
            elif ch == "w":
                out.append(self.paint(ch, C_WRITE))
            elif ch == "x":
                out.append(self.paint(ch, C_EXEC))
            else:
                out.append(self.paint(ch, C_DASH))
        return "".join(out)

    def size(self, s: str) -> str:
        num, unit = split_size(s)
        return self.paint(num, C_SIZE_NUM) + self.paint(unit, C_SIZE_UNIT)

    def user(self, name: str, uid: int) -> str:
        return self.paint(name, C_USER_ME if uid == os.geteuid() else C_USER_OTHER)

    def date(self, s: str) -> str:
        return self.paint(s, C_DATE)

    def tokens(self, s: str) -> str:
        return self.paint(s, C_TOKENS)

    def footer(self, s: str) -> str:
        return self.paint(s, C_FOOTER)

    # -- names -----------------------------------------------------------
    def name_code(self, name: str, st: os.stat_result, path: str) -> str:
        m = st.st_mode
        if stat.S_ISLNK(m):
            if not os.path.exists(path):  # dangling
                return self.types.get("or", C_BROKEN)
            code = self.types.get("ln", "01;36")
            if code == "target":
                try:
                    tgt = os.stat(path)
                    return self.name_code(
                        os.path.realpath(path), tgt, os.path.realpath(path)
                    )
                except OSError:
                    return C_BROKEN
            return code
        if stat.S_ISDIR(m):
            ow, sticky = bool(m & stat.S_IWOTH), bool(m & stat.S_ISVTX)
            if ow and sticky:
                return self.types.get("tw", "30;42")
            if ow:
                return self.types.get("ow", "34;42")
            if sticky:
                return self.types.get("st", "37;44")
            return self.types.get("di", "01;34")
        if stat.S_ISFIFO(m):
            return self.types.get("pi", "40;33")
        if stat.S_ISSOCK(m):
            return self.types.get("so", "01;35")
        if stat.S_ISBLK(m):
            return self.types.get("bd", "40;33;01")
        if stat.S_ISCHR(m):
            return self.types.get("cd", "40;33;01")
        if m & stat.S_ISUID:
            return self.types.get("su", "37;41")
        if m & stat.S_ISGID:
            return self.types.get("sg", "30;43")
        low = name.lower()
        for suffix, code in self.exts:
            if low.endswith(suffix):
                return code
        if m & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
            return self.types.get("ex", "01;32")
        return self.types.get("fi", "")

    def icon(self, name: str, st: os.stat_result) -> str:
        if not self.icons:
            return ""
        m = st.st_mode
        low = name.lower()
        if low in ICON_NAMES:
            return ICON_NAMES[low]
        if stat.S_ISLNK(m):
            return ICON_LINK
        if stat.S_ISDIR(m):
            return ICON_DIR
        if stat.S_ISFIFO(m):
            return ICON_PIPE
        if stat.S_ISSOCK(m):
            return ICON_SOCK
        if stat.S_ISBLK(m) or stat.S_ISCHR(m):
            return ICON_DEV
        _root, dot, ext = low.rpartition(".")
        if dot and ext in ICON_EXTS:
            return ICON_EXTS[ext]
        if m & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
            return ICON_EXEC
        return ICON_DEFAULT

    def entry_name(self, e) -> str:
        """icon + coloured name + classify char (+ -> target for symlinks)"""
        st = e.st
        code = self.name_code(e.name, st, e.path)
        text = self.paint(e.name, code) + classify_suffix(st, e.path)
        if self.icons:
            text = self.paint(self.icon(e.name, st), code) + " " + text
        if stat.S_ISLNK(st.st_mode):
            try:
                tgt = os.readlink(e.path)
            except OSError:
                return text
            text += self.paint(" -> ", C_ARROW)
            try:
                tst = os.stat(e.path)
                text += self.paint(
                    tgt, self.name_code(tgt, tst, os.path.realpath(e.path))
                )
            except OSError:
                text += self.paint(tgt, self.types.get("mi", C_BROKEN))
        return text


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
    pending = []  # (entry, key, text)
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


def render(entries, theme: Theme):
    now_year = datetime.now().year
    rows = []
    for e in entries:
        st = e.st
        rows.append(
            {
                "mode": mode_string(st),
                "size": human_size(st.st_size),
                "user": owner_name(st.st_uid),
                "date": fmt_time(st.st_mtime, now_year),
                "tok": f"{e.tok:,}" if e.tok is not None else e.note,
                "uid": st.st_uid,
                "e": e,
            }
        )

    if not rows:
        return

    w_mode = max(len(r["mode"]) for r in rows)
    w_size = max(len(r["size"]) for r in rows)
    w_user = max(len(r["user"]) for r in rows)
    w_date = max(len(r["date"]) for r in rows)
    w_tok = max(len(r["tok"]) for r in rows)

    def lpad(txt, plain, w):  # right-align
        return " " * max(0, w - len(plain)) + txt

    def rpad(txt, plain, w):  # left-align
        return txt + " " * max(0, w - len(plain))

    out = []
    for r in rows:
        out.append(
            rpad(theme.mode(r["mode"]), r["mode"], w_mode)
            + " "
            + lpad(theme.size(r["size"]), r["size"], w_size)
            + " "
            + rpad(theme.user(r["user"], r["uid"]), r["user"], w_user)
            + " "
            + lpad(theme.date(r["date"]), r["date"], w_date)
            + " "
            + lpad(theme.tokens(r["tok"]), r["tok"], w_tok)
            + "  "
            + theme.entry_name(r["e"])
        )
    sys.stdout.write("\n".join(out) + "\n")

    if SHOW_TOTAL:
        total = sum(e.tok for e in entries if e.tok is not None)
        counted = sum(1 for e in entries if e.tok is not None)
        sys.stdout.write(
            theme.paint("-- ", C_FOOTER)
            + theme.paint(f"{total:,}", C_FOOTER_TOKENS)
            + theme.paint(" tokens in ", C_FOOTER)
            + theme.paint(str(counted), C_FOOTER_FILES)
            + theme.paint(" file(s) --", C_FOOTER)
        )


def want_color(args) -> bool:
    mode = "auto"
    for a in args:
        if a in ("--color", "--colour", "--color=always", "--colour=always"):
            mode = "always"
        elif a in ("--color=never", "--colour=never", "--no-color", "--no-colour"):
            mode = "never"
        elif a in ("--color=auto", "--colour=auto"):
            mode = "auto"
    if mode == "always":
        return True
    if mode == "never":
        return False
    if os.environ.get("NO_COLOR") is not None:
        return False
    return sys.stdout.isatty()


def want_icons(args) -> bool:
    icons = ICONS_DEFAULT and sys.stdout.isatty()  # glyphs would pollute pipes
    for a in args:
        if a in ("--icons", "--icons=always"):
            icons = True
        elif a in ("--no-icons", "--icons=never"):
            icons = False
    return icons


def main(argv):
    prog = os.path.basename(argv[0])
    args = [a for a in argv[1:] if a != "--"]
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

    if prog.startswith("kkk"):
        entries.sort(key=lambda e: (e.name.lower().lstrip("."), e.name))
    else:  # kk: oldest first -> newest at the bottom
        entries.sort(key=lambda e: e.st.st_mtime_ns)

    render(entries, Theme(want_color(args), want_icons(args)))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except BrokenPipeError:
        os._exit(0)
    except KeyboardInterrupt:
        sys.exit(130)
