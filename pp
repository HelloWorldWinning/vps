#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pp — multi-level Python project distiller for LLM context windows.

Distills .py files into token-efficient digests at levels -0 … -5, or dumps
files verbatim with -raw. Level flags are *sticky*: they apply to every
following path until the next flag. A file-level assignment always overrides
a folder-derived one; same-specificity duplicates keep the higher level.

    pp some_folder                     # everything at -0 (cheapest map)
    pp -3 src/ -5 src/model.py         # src at -3, model.py overridden to -5
    pp -0 projA -4 projB train.py      # projB and train.py at -4
    pp -raw config.yaml notes.md       # verbatim dump (any file type)

Levels (strictly additive — each includes everything above it):
  -0  MAP        file tree · per-file one-liner · internal import graph
  -1  API        + signatures (classes, funcs, methods, decorators, class
                   attrs, __all__, __main__ / argparse CLI surface)
  -2  INTENT     + docstrings (module: first paragraph; defs: first line)
  -3  CONTRACTS  + return exprs · raises · constants · dataclass fields ·
                   self.* state extracted from __init__
  -4  DATAFLOW   + shape/flow comments · per-function call sets · fuller
                   docstrings · raised caps
  -5  BODY       compressed full source (blank lines stripped, docstrings
                   truncated to first line — semantically lossless)
  -raw           verbatim file content (the only mode that accepts non-.py)

Output file (written to CWD):
  pp one_file.py      ->  one_file_summary_<ts>.txt
  pp one_folder       ->  one_folder_summary_<ts>.txt
  pp many things      ->  summary_<ts>.txt

Token counts: gpt-4o (o200k_base via tiktoken, exact) and a Claude estimate
(o200k x CLAUDE_TOKEN_FACTOR — tiktoken has no real Claude encoding, and
gpt-4o's encoding IS o200k_base, so an adjustment factor is the only way to
get two distinct numbers). Counts are embedded in the summary footer
(accepted tiny recursion: the footer line itself is not re-counted) and
echoed to the terminal together with a uniform-level cost table.
"""

from __future__ import annotations

import ast
import datetime
import os
import re
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union

# ── Configuration ────────────────────────────────────────────────────────────

# Directories never entered (junk / vendored / caches). Hidden dirs are also
# always pruned.
EXCLUDE_DIR_NAMES = {
    "__pycache__",
    ".git",
    ".hg",
    ".svn",
    ".venv",
    "venv",
    "env",
    "node_modules",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".tox",
    ".ipynb_checkpoints",
    "build",
    "dist",
    "site-packages",
    ".idea",
    ".vscode",
}

# Non-.py files worth *listing* in the tree (never distilled). Everything else
# non-.py is folded into a "+N more files" line per directory.
TREE_NONPY_NAMES = {
    "README",
    "Makefile",
    "Dockerfile",
    "docker-compose.yml",
    "pyproject.toml",
    "requirements.txt",
    "setup.py",
    "setup.cfg",
}
TREE_NONPY_EXTS = {
    ".md",
    ".rst",
    ".toml",
    ".yaml",
    ".yml",
    ".json",
    ".cfg",
    ".ini",
    ".sh",
    ".txt",
}
TREE_NONPY_PER_DIR_CAP = 6

# Claude ≈ o200k x factor. gpt-4o's tokenizer *is* o200k_base, so without a
# factor both counts would always be identical. ~1.15 matches typical
# Claude-vs-o200k inflation on code. Set to 1.0 for raw o200k.
CLAUDE_TOKEN_FACTOR = 1.15

# Calls too generic to be informative in "calls →" lines.
SKIP_CALL_NAMES = {
    "len",
    "range",
    "print",
    "isinstance",
    "issubclass",
    "str",
    "int",
    "float",
    "bool",
    "list",
    "dict",
    "set",
    "tuple",
    "enumerate",
    "zip",
    "super",
    "min",
    "max",
    "sum",
    "abs",
    "sorted",
    "reversed",
    "getattr",
    "setattr",
    "hasattr",
    "type",
    "repr",
    "format",
    "id",
    "map",
    "filter",
    "any",
    "all",
    "open",
    "vars",
    "iter",
    "next",
    "round",
}

RAW = "raw"  # sentinel level


@dataclass(frozen=True)
class LevelSpec:
    """Feature flags + caps for one distillation level (monotone by design)."""

    signatures: bool = False
    doc: str = "none"  # none | line | para   (defs; module gets para from L2)
    returns: int = 0  # max return exprs shown per function
    raises: int = 0
    shapes: int = 0  # max shape/flow comment lines per function
    calls: int = 0  # max unique call names per function
    constants: bool = False  # top-level constants with values
    self_state: int = 0  # max self.* assignments shown from __init__
    body: bool = False  # L5: compressed full source


SPECS: Dict[int, LevelSpec] = {
    0: LevelSpec(),
    1: LevelSpec(signatures=True),
    2: LevelSpec(signatures=True, doc="line"),
    3: LevelSpec(
        signatures=True, doc="line", returns=3, raises=2, constants=True, self_state=24
    ),
    4: LevelSpec(
        signatures=True,
        doc="para",
        returns=6,
        raises=3,
        shapes=10,
        calls=12,
        constants=True,
        self_state=40,
    ),
    5: LevelSpec(signatures=True, doc="para", body=True),
}

LEGEND = """\
LEVEL LEGEND (what each per-file level includes / OMITS):
  -0 MAP       one-liner + import graph only. Bodies, signatures, docs OMITTED.
  -1 API       all signatures. Bodies and docstrings OMITTED.
  -2 INTENT    + docstring first lines. Bodies OMITTED.
  -3 CONTRACTS + returns/raises/constants/self.* state. Bodies OMITTED.
  -4 DATAFLOW  + shape comments and per-function call sets. Bodies OMITTED.
  -5 BODY      full source, blank lines stripped, docstrings truncated.
  raw          verbatim.
If a detail you need is omitted at a file's level, ask for the file at a
higher level instead of guessing its contents."""


# ── Token counting ───────────────────────────────────────────────────────────


class TokenCounter:
    def __init__(self) -> None:
        self.enc = None
        self.exact = False
        try:
            import tiktoken  # type: ignore

            # encoding_for_model("gpt-4o") == o200k_base
            self.enc = tiktoken.encoding_for_model("gpt-4o")
            self.enc.encode("warmup", disallowed_special=())
            self.exact = True
        except Exception:
            self.enc = None
            self.exact = False

    def count(self, text: str) -> Tuple[int, int]:
        """Return (gpt_tokens, claude_tokens_estimate)."""
        if self.enc is not None:
            n = len(self.enc.encode(text, disallowed_special=()))
        else:
            n = max(1, len(text) // 3)  # heuristic fallback (~3 chars/token)
        return n, int(round(n * CLAUDE_TOKEN_FACTOR))

    @property
    def label(self) -> str:
        base = (
            #   "tiktoken o200k_base (exact)"
            ""
            if self.exact
            else "heuristic len//3 (tiktoken unavailable — pip install tiktoken)"
        )
        return base


# ── AST helpers ──────────────────────────────────────────────────────────────


def _unparse(node: ast.AST) -> str:
    try:
        return ast.unparse(node)
    except Exception:
        return "..."


def _trim(s: str, n: int) -> str:
    return s if len(s) <= n else s[: n - 3] + "..."


def _first_line(docstring: str, max_chars: int = 110) -> str:
    for line in textwrap.dedent(docstring).strip().splitlines():
        if line.strip():
            return _trim(line.strip(), max_chars)
    return ""


def _first_paragraph(docstring: str, max_lines: int = 4) -> str:
    if not docstring:
        return ""
    lines = textwrap.dedent(docstring).strip().splitlines()
    para: List[str] = []
    for line in lines:
        if line.strip() == "" and para:
            break
        para.append(line.rstrip())
        if len(para) >= max_lines:
            break
    return "\n".join(para)


def _first_sentence(docstring: str, max_chars: int = 90) -> str:
    fl = _first_line(docstring, max_chars=300)
    m = re.split(r"(?<=[.!?])\s", fl, maxsplit=1)
    return _trim(m[0], max_chars)


SHAPE_PATTERN = re.compile(
    r"#.*(\[.*\]|→|->|OUTPUT|INPUT|reshape|unsqueeze|squeeze|shape|dim)"
    r"|#\s*\w+\s*:\s*\[",
    re.IGNORECASE,
)


def _shape_comments(source_lines: List[str], lo: int, hi: int) -> List[str]:
    out = []
    for i in range(lo - 1, min(hi, len(source_lines))):
        stripped = source_lines[i].strip()
        if stripped.startswith("#") and SHAPE_PATTERN.search(stripped):
            out.append(stripped)
    return out


def _collect_returns(fn) -> List[str]:
    out = []
    for node in ast.walk(fn):
        if node is fn:
            continue
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue  # don't descend into nested defs
        if isinstance(node, ast.Return) and node.value is not None:
            out.append(_unparse(node.value))
    return list(dict.fromkeys(out))


def _collect_raises(fn) -> List[str]:
    out = []
    for node in ast.walk(fn):
        if isinstance(node, ast.Raise) and node.exc is not None:
            out.append(_unparse(node.exc))
    return list(dict.fromkeys(out))


def _collect_calls(fn) -> List[str]:
    out = []
    for node in ast.walk(fn):
        if isinstance(node, ast.Call):
            name = _unparse(node.func)
            if name in SKIP_CALL_NAMES:
                continue
            out.append(_trim(name, 60))
    return list(dict.fromkeys(out))


def _collect_self_state(cls: ast.ClassDef) -> List[str]:
    """self.x = ... assignments inside __init__ — the object's state layer."""
    for item in cls.body:
        if (
            isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef))
            and item.name == "__init__"
        ):
            out = []
            for node in ast.walk(item):
                targets = []
                if isinstance(node, ast.Assign):
                    targets = node.targets
                    value = node.value
                elif isinstance(node, ast.AnnAssign) and node.value is not None:
                    targets = [node.target]
                    value = node.value
                else:
                    continue
                for t in targets:
                    if (
                        isinstance(t, ast.Attribute)
                        and isinstance(t.value, ast.Name)
                        and t.value.id == "self"
                    ):
                        out.append(f"self.{t.attr} = {_trim(_unparse(value), 110)}")
            return out
    return []


def _format_args(args: ast.arguments) -> str:
    parts = []
    num_defaults = len(args.defaults)
    num_args = len(args.args)
    for i, arg in enumerate(args.args):
        off = i - (num_args - num_defaults)
        ann = f": {_unparse(arg.annotation)}" if arg.annotation else ""
        dflt = f" = {_unparse(args.defaults[off])}" if off >= 0 else ""
        parts.append(f"{arg.arg}{ann}{dflt}")
    if args.vararg:
        ann = f": {_unparse(args.vararg.annotation)}" if args.vararg.annotation else ""
        parts.append(f"*{args.vararg.arg}{ann}")
    elif args.kwonlyargs:
        parts.append("*")
    kw_defaults = {
        k: v for k, v in zip(args.kwonlyargs, args.kw_defaults) if v is not None
    }
    for arg in args.kwonlyargs:
        ann = f": {_unparse(arg.annotation)}" if arg.annotation else ""
        dflt = f" = {_unparse(kw_defaults[arg])}" if arg in kw_defaults else ""
        parts.append(f"{arg.arg}{ann}{dflt}")
    if args.kwarg:
        ann = f": {_unparse(args.kwarg.annotation)}" if args.kwarg.annotation else ""
        parts.append(f"**{args.kwarg.arg}{ann}")
    return ", ".join(parts)


def _func_signature(node, indent: str = "") -> str:
    prefix = "async def " if isinstance(node, ast.AsyncFunctionDef) else "def "
    ret = f" -> {_unparse(node.returns)}" if node.returns else ""
    dec = "".join(f"{indent}@{_unparse(d)}\n" for d in node.decorator_list)
    return f"{dec}{indent}{prefix}{node.name}({_format_args(node.args)}){ret}:"


# ── Per-file distiller ───────────────────────────────────────────────────────


class PyFile:
    def __init__(self, path: Path):
        self.path = path
        try:
            self.source = path.read_text(encoding="utf-8", errors="replace")
        except Exception as e:
            self.source = ""
            self.tree = None
            self.parse_ok = False
            self.parse_error = f"unreadable: {e}"
            self.source_lines: List[str] = []
            return
        self.source_lines = self.source.splitlines()
        try:
            self.tree = ast.parse(self.source, filename=str(path))
            self.parse_ok = True
            self.parse_error = ""
        except SyntaxError as e:
            self.tree = None
            self.parse_ok = False
            self.parse_error = str(e)

    # -- small facts ---------------------------------------------------------

    def is_effectively_empty(self) -> bool:
        return self.parse_ok and not self.tree.body

    def import_modules(self) -> List[str]:
        if not self.parse_ok:
            return []
        mods = set()
        for node in ast.walk(self.tree):
            if isinstance(node, ast.Import):
                for a in node.names:
                    mods.add(a.name.split(".")[0])
            elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
                mods.add(node.module.split(".")[0])
        return sorted(mods)

    def def_counts(self) -> Tuple[int, int]:
        n_cls = n_fun = 0
        for node in ast.walk(self.tree):
            if isinstance(node, ast.ClassDef):
                n_cls += 1
            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                n_fun += 1
        return n_cls, n_fun

    def one_liner(self, label: str) -> str:
        if not self.parse_ok:
            return f"{label} — PARSE ERROR: {self.parse_error}"
        n_cls, n_fun = self.def_counts()
        bits = [f"{label} — {n_cls}c/{n_fun}f/{len(self.source_lines)}L"]
        mods = self.import_modules()
        if mods:
            bits.append("imports: " + ", ".join(mods[:8]))
        doc = ast.get_docstring(self.tree)
        if doc:
            bits.append(f'"{_first_sentence(doc)}"')
        return "  |  ".join(bits)

    # -- section pieces ------------------------------------------------------

    def _entry_points(self) -> Tuple[bool, List[str]]:
        has_main, cli = False, []
        for node in ast.walk(self.tree):
            if isinstance(node, ast.If) and "__main__" in _unparse(node.test):
                has_main = True
            if (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == "add_argument"
            ):
                if node.args and isinstance(node.args[0], ast.Constant):
                    cli.append(str(node.args[0].value))
        return has_main, cli[:14]

    def _dunder_all(self) -> str:
        for node in self.tree.body:
            if isinstance(node, ast.Assign):
                for t in node.targets:
                    if isinstance(t, ast.Name) and t.id == "__all__":
                        return _trim(_unparse(node.value), 200)
        return ""

    def _top_constants(self) -> List[str]:
        out = []
        for node in self.tree.body:
            if isinstance(node, ast.Assign):
                for t in node.targets:
                    name = _unparse(t)
                    if name == "__all__":
                        continue
                    if name.isupper() or len(name) <= 20:
                        val = _unparse(node.value)
                        if len(val) <= 90:
                            out.append(f"{name} = {val}")
            elif isinstance(node, ast.AnnAssign):
                name = _unparse(node.target)
                val = f" = {_trim(_unparse(node.value), 90)}" if node.value else ""
                out.append(f"{name}: {_unparse(node.annotation)}{val}")
        return out[:14]

    def _func_digest(self, node, spec: LevelSpec, indent: str) -> str:
        lines = [_func_signature(node, indent)]
        pad = indent + "    "
        doc = ast.get_docstring(node)
        if doc and spec.doc != "none":
            txt = _first_line(doc) if spec.doc == "line" else _first_paragraph(doc, 4)
            for ln in txt.splitlines():
                lines.append(f"{pad}# {ln}")
        if spec.shapes:
            shapes = _shape_comments(self.source_lines, node.lineno, node.end_lineno)
            if shapes:
                lines.append(f"{pad}# ── shape/flow ──")
                for s in shapes[: spec.shapes]:
                    lines.append(f"{pad}{s}")
        if spec.returns:
            for r in _collect_returns(node)[: spec.returns]:
                lines.append(f"{pad}return {_trim(r, 120)}")
        if spec.raises:
            for r in _collect_raises(node)[: spec.raises]:
                lines.append(f"{pad}# raises: {_trim(r, 100)}")
        if spec.calls:
            calls = _collect_calls(node)[: spec.calls]
            if calls:
                lines.append(f"{pad}# calls → {', '.join(calls)}")
        return "\n".join(lines)

    def _class_digest(self, node: ast.ClassDef, spec: LevelSpec) -> str:
        bases = ", ".join(_unparse(b) for b in node.bases)
        dec = "".join(f"@{_unparse(d)}\n" for d in node.decorator_list)
        lines = [
            f"{dec}class {node.name}({bases}):" if bases else f"{dec}class {node.name}:"
        ]
        doc = ast.get_docstring(node)
        if doc and spec.doc != "none":
            txt = _first_line(doc) if spec.doc == "line" else _first_paragraph(doc, 5)
            for ln in txt.splitlines():
                lines.append(f"    # {ln}")
        # class-level (dataclass) fields
        for item in node.body:
            if isinstance(item, ast.AnnAssign):
                name = _unparse(item.target)
                ann = _unparse(item.annotation)
                val = ""
                if spec.constants and item.value is not None:
                    val = f" = {_trim(_unparse(item.value), 90)}"
                lines.append(f"    {name}: {ann}{val}")
        # object state from __init__
        if spec.self_state:
            state = _collect_self_state(node)
            if state:
                lines.append("    # ── state (__init__) ──")
                for s in state[: spec.self_state]:
                    lines.append(f"    {s}")
        lines.append("")
        for item in node.body:
            if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                lines.append(self._func_digest(item, spec, "    "))
                lines.append("")
        return "\n".join(lines).rstrip()

    def _compressed_source(self) -> str:
        """L5: full source, blank lines stripped, multi-line docstrings
        truncated to their first physical line."""
        spans: List[Tuple[int, int]] = []
        for node in ast.walk(self.tree):
            body = getattr(node, "body", None)
            if not isinstance(
                node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)
            ):
                continue
            if (
                body
                and isinstance(body[0], ast.Expr)
                and isinstance(body[0].value, ast.Constant)
                and isinstance(body[0].value.value, str)
            ):
                e = body[0]
                if e.end_lineno is not None and e.end_lineno - e.lineno >= 2:
                    spans.append((e.lineno, e.end_lineno))
        starts = {lo: hi for lo, hi in spans}
        inside: set = set()
        for lo, hi in spans:
            inside.update(range(lo + 1, hi + 1))
        out = []
        for i, line in enumerate(self.source_lines, 1):
            if i in starts:
                head = line.rstrip()
                if not head.rstrip().endswith(('"""', "'''")):
                    head += ' ..."""'
                out.append(head)
                continue
            if i in inside:
                continue
            if not line.strip():
                continue
            out.append(line.rstrip())
        return "\n".join(out)

    # -- render --------------------------------------------------------------

    def render(self, level: Union[int, str]) -> str:
        if level == RAW:
            return self.source
        if not self.parse_ok:
            return f"PARSE ERROR: {self.parse_error}"
        spec = SPECS[int(level)]
        if spec.body:
            return self._compressed_source()

        out: List[str] = []
        doc = ast.get_docstring(self.tree)
        if doc and spec.doc != "none":
            out.append("# module: " + _first_paragraph(doc, 5).replace("\n", " ⏎ "))
        mods = self.import_modules()
        if mods:
            out.append("# imports: " + ", ".join(mods))
        da = self._dunder_all()
        if da:
            out.append(f"__all__ = {da}")
        has_main, cli = self._entry_points()
        if has_main or cli:
            entry = "# entry: __main__"
            if cli:
                entry += " · cli: " + " ".join(cli)
            out.append(_trim(entry, 240))
        if spec.constants:
            consts = self._top_constants()
            if consts:
                out.append("# ── constants/globals ──")
                out.extend(consts)
        out.append("")
        for node in self.tree.body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                out.append(self._func_digest(node, spec, ""))
                out.append("")
            elif isinstance(node, ast.ClassDef):
                out.append(self._class_digest(node, spec))
                out.append("")
        return "\n".join(out).strip("\n")


# ── Internal import graph ────────────────────────────────────────────────────


def _dotted(root: Path, f: Path) -> str:
    parts = list(f.relative_to(root).with_suffix("").parts)
    if parts and parts[-1] == "__init__":
        parts = parts[:-1]
    return ".".join(parts)


def import_graph(root: Path, files: List[Path], cache: Dict[Path, PyFile]) -> List[str]:
    mods = {_dotted(root, f): f for f in files}
    edges: Dict[Path, set] = {}

    def match(name: str) -> Optional[Path]:
        best = None
        for m, f in mods.items():
            if m and (name == m or name.startswith(m + ".")):
                if best is None or len(m) > len(best[0]):
                    best = (m, f)
        return best[1] if best else None

    for f in files:
        pf = cache[f]
        if not pf.parse_ok:
            continue
        my_parts = _dotted(root, f).split(".") if _dotted(root, f) else []
        for node in ast.walk(pf.tree):
            names: List[str] = []
            if isinstance(node, ast.Import):
                names = [a.name for a in node.names]
            elif isinstance(node, ast.ImportFrom):
                if node.level == 0:
                    base = node.module or ""
                else:
                    pkg = my_parts if f.name == "__init__.py" else my_parts[:-1]
                    up = node.level - 1
                    pkg = pkg[: len(pkg) - up] if up > 0 else pkg
                    base = ".".join(pkg + ([node.module] if node.module else []))
                if base:
                    names = [base] + [f"{base}.{a.name}" for a in node.names]
                else:
                    names = [a.name for a in node.names]
            for name in names:
                tgt = match(name)
                if tgt is not None and tgt != f:
                    edges.setdefault(f, set()).add(tgt)
    lines = []
    for f in sorted(edges):
        tgts = ", ".join(str(t.relative_to(root)) for t in sorted(edges[f]))
        lines.append(f"{f.relative_to(root)} → {tgts}")
    return lines


# ── Filesystem walking / tree ────────────────────────────────────────────────


def _dir_excluded(name: str) -> bool:
    return (
        name in EXCLUDE_DIR_NAMES or name.startswith(".") or name.endswith(".egg-info")
    )


def collect_py_files(root: Path) -> List[Path]:
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if not _dir_excluded(d))
        for fn in sorted(filenames):
            if fn.startswith("."):
                continue
            if fn.endswith(".py"):
                out.append(Path(dirpath) / fn)
    return out


def hsize(n: int) -> str:
    if n < 1024:
        return f"{n}B"
    if n < 10 * 1024:
        return f"{n / 1024:.1f}K"
    if n < 1024 * 1024:
        return f"{n // 1024}K"
    return f"{n / 1048576:.1f}M"


def build_tree(root: Path, level_of: Dict[Path, Union[int, str]]) -> List[str]:
    lines = [f"{root.name}/"]
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if not _dir_excluded(d))
        dp = Path(dirpath)
        depth = len(dp.relative_to(root).parts)
        indent = "  " * (depth + 1)
        if dp != root:
            lines.append("  " * depth + dp.name + "/")
        pys, keep, skipped = [], [], 0
        for fn in sorted(filenames):
            if fn.startswith("."):
                continue
            p = dp / fn
            if fn.endswith(".py"):
                pys.append(p)
            elif fn in TREE_NONPY_NAMES or p.suffix.lower() in TREE_NONPY_EXTS:
                keep.append(p)
            else:
                skipped += 1
        for p in pys:
            lvl = level_of.get(p.resolve())
            tag = (
                f"  [-{lvl}]"
                if isinstance(lvl, int)
                else ("  [raw]" if lvl == RAW else "")
            )
            lines.append(f"{indent}{p.name}  {hsize(p.stat().st_size)}{tag}")
        for p in keep[:TREE_NONPY_PER_DIR_CAP]:
            lines.append(f"{indent}{p.name}  {hsize(p.stat().st_size)}")
        extra = skipped + max(0, len(keep) - TREE_NONPY_PER_DIR_CAP)
        if extra:
            lines.append(f"{indent}(+{extra} more files)")
    return lines


# ── CLI parsing ──────────────────────────────────────────────────────────────

USAGE = __doc__


def parse_argv(argv: List[str]):
    """Sticky level flags. Returns (raw_targets, error)."""
    level: Union[int, str] = 0
    targets: List[Tuple[Path, Union[int, str], bool]] = []  # (path, level, is_dir_arg)
    for tok in argv:
        if tok in ("-h", "--help"):
            print(USAGE)
            sys.exit(0)
        m = re.fullmatch(r"-([0-5])", tok)
        if m:
            level = int(m.group(1))
            continue
        if tok in ("-raw", "--raw"):
            level = RAW
            continue
        if tok.startswith("-") and not Path(tok).exists():
            return None, f"unknown option: {tok}  (see pp -h)"
        p = Path(tok).expanduser()
        if not p.exists():
            return None, f"path not found: {tok}"
        targets.append((p.resolve(), level, p.is_dir()))
    if not targets:
        return None, "no targets given  (see pp -h)"
    return targets, None


LEVEL_RANK = {RAW: 99}


def _rank(lvl: Union[int, str]) -> int:
    return LEVEL_RANK.get(lvl, lvl if isinstance(lvl, int) else 0)


def expand_targets(raw_targets):
    """Resolve folders to .py files; dedupe with (explicit-file > folder-derived,
    ties -> higher level). Returns (roots, file_levels, nonpy_notes)."""
    roots: List[Tuple[Path, Union[int, str]]] = []
    files: Dict[Path, Tuple[Union[int, str], bool]] = {}  # path -> (level, explicit)
    notes: List[str] = []

    def put(p: Path, lvl, explicit: bool):
        if p not in files:
            files[p] = (lvl, explicit)
            return
        old_lvl, old_exp = files[p]
        if explicit and not old_exp:
            files[p] = (lvl, True)
        elif explicit == old_exp and _rank(lvl) > _rank(old_lvl):
            files[p] = (lvl, old_exp)

    for p, lvl, is_dir in raw_targets:
        if is_dir:
            if not any(r == p for r, _ in roots):
                roots.append((p, lvl))
            for f in collect_py_files(p):
                put(f.resolve(), lvl, explicit=False)
        else:
            if p.suffix == ".py" or lvl == RAW:
                put(p, lvl, explicit=True)
            else:
                notes.append(f"skipped (non-.py, no -raw): {p}")
    return roots, {p: lv for p, (lv, _) in files.items()}, notes


# ── Assembly ─────────────────────────────────────────────────────────────────


def output_name(raw_targets) -> str:
    now = datetime.datetime.now()
    ts = (
        now.strftime("%Y-%m-%d_%H-%M-%S")
        + ("_AM" if now.hour < 12 else "_PM")
        + now.strftime("_%a")
    )
    if len(raw_targets) == 1:
        p, _, is_dir = raw_targets[0]
        name = p.name if is_dir else p.stem
        return f"{name}_summary_{ts}.txt"
    return f"summary_{ts}.txt"


def main() -> None:
    raw_targets, err = parse_argv(sys.argv[1:])
    if err:
        print(f"pp: {err}", file=sys.stderr)
        sys.exit(2)

    roots, file_levels, notes = expand_targets(raw_targets)
    all_files = sorted(file_levels)
    if not all_files:
        print("pp: no .py files found in the given targets", file=sys.stderr)
        sys.exit(1)

    tk = TokenCounter()
    cache: Dict[Path, PyFile] = {p: PyFile(p) for p in all_files}
    cwd = Path.cwd().resolve()

    # a root nested inside another root would render a duplicate sub-tree
    roots = [
        (r, lv)
        for r, lv in roots
        if not any(o != r and o in r.parents for o, _ in roots)
    ]

    # ---- summary body ----
    S: List[str] = []
    S.append("# SUMMARY")
    S.append(
        f"- generated : {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S %a')}"
    )
    S.append(f"- cwd       : {cwd}")
    for p, lvl, is_dir in raw_targets:
        tag = "raw" if lvl == RAW else f"-{lvl}"
        S.append(f"- target    : [{tag}] {p}{'/' if is_dir else ''}")
    for n in notes:
        S.append(f"- note      : {n}")
    S.append("")
    S.append(LEGEND)
    S.append("")

    # trees + import graphs per folder root
    for root, _lvl in roots:
        S.append(f"## TREE: {root}")
        S.append("```")
        S.extend(build_tree(root, file_levels))
        S.append("```")
        root_files = [f for f in all_files if root in f.parents or f.parent == root]
        graph = import_graph(root, root_files, cache)
        if graph:
            S.append(f"## IMPORT GRAPH (internal): {root.name}")
            S.append("```")
            S.extend(graph)
            S.append("```")
        S.append("")

    loose = [p for p, _, is_dir in raw_targets if not is_dir]
    if loose:
        S.append("## FILES (given directly)")
        S.append("```")
        for p in dict.fromkeys(loose):
            S.append(f"{p}  {hsize(p.stat().st_size)}")
        S.append("```")
        S.append("")

    # level-0 one-liners (files whose level is 0 get no section)
    l0 = [p for p in all_files if file_levels[p] == 0]
    if l0:
        S.append("## FILE SUMMARIES [-0]")
        S.append("```")
        for p in l0:
            pf = cache[p]
            if pf.is_effectively_empty():
                S.append(f"{p} — (empty)")
            else:
                S.append(pf.one_liner(str(p)))
        S.append("```")
        S.append("")

    # per-file sections for level >= 1 and raw
    per_file_tokens: List[Tuple[int, str, str]] = []  # (gpt, label, path)
    for p in all_files:
        lvl = file_levels[p]
        if lvl == 0:
            continue
        pf = cache[p]
        if pf.is_effectively_empty() and lvl != RAW:
            continue  # empty __init__.py etc: tree line is enough
        body = pf.render(lvl)
        g, c = tk.count(body)
        tag = "raw" if lvl == RAW else f"-{lvl}"
        lang = "python" if p.suffix == ".py" else ""
        S.append(
            f"## {p}  [{tag}]  ({hsize(p.stat().st_size)} | gpt {g:,} "
            f"| claude ~{c:,} tok)"
        )
        S.append(f"```{lang}")
        S.append(body)
        S.append("```")
        S.append("")
        per_file_tokens.append((g, tag, str(p)))

    body_text = "\n".join(S)

    # ---- token totals (accepted recursion: footer itself not re-counted) ----
    g_total, c_total = tk.count(body_text)
    footer = (
        "\n---\n"
        f"TOKENS of this summary — gpt-4o(o200k): {g_total:,} | "
        f"claude(≈o200k×{CLAUDE_TOKEN_FACTOR}): {c_total:,}   "
        #       f"[{tk.label}]\n"
    )
    out_text = body_text + footer

    out_path = cwd / output_name(raw_targets)
    out_path.write_text(out_text, encoding="utf-8")

    # ---- terminal echo ----
    print("pwd")
    print(cwd)
    print()
    listing = sorted(all_files, key=lambda p: p.stat().st_size)
    for p in listing:
        lvl = file_levels[p]
        tag = "raw" if lvl == RAW else f"-{lvl}"
        print(f"{hsize(p.stat().st_size):>6}  [{tag:>4}]  {p}")
    print()
    if per_file_tokens:
        top = sorted(per_file_tokens, reverse=True)[:8]
        print("top token contributors (gpt):")
        for g, tag, path in top:
            print(f"{g:>8,}  [{tag:>4}]  {path}")
        print()

    # uniform-level cost table (distillable .py files only)
    try:
        est = []
        for lvl in range(6):
            chunks = []
            for p in all_files:
                if p.suffix != ".py":
                    continue
                pf = cache[p]
                if not pf.parse_ok:
                    continue
                if lvl == 0:
                    chunks.append(pf.one_liner(str(p)))
                else:
                    chunks.append(f"## {p}\n{pf.render(lvl)}")
            g, c = tk.count("\n".join(chunks))
            est.append(f"-{lvl} ~{g:,}")
        print("uniform-level cost (gpt tokens): " + "  |  ".join(est))
    except Exception:
        pass

    print()
    print(f"✓ wrote {out_path}")
    # print(
    #     f"  tokens — gpt-4o(o200k): {g_total:,} | "
    #     f"claude(≈×{CLAUDE_TOKEN_FACTOR}): {c_total:,}   [{tk.label}]"
    #     f"claude(≈×{CLAUDE_TOKEN_FACTOR}): {c_total:,}   [{tk.label}]"
    # )
    print(f"gpt: {g_total:,} | " f"claude: {c_total:,}   ")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except Exception:
            pass
        sys.exit(0)
