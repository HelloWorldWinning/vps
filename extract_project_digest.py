#!/usr/bin/env python3
"""
extract_project_digest.py
─────────────────────────
Extracts a high-density, token-efficient digest of a Python project for LLM consumption.

Strategy (per function/method):
  1. Full signature (name + typed parameters + return annotation)
  2. Docstring (first paragraph only, to cap length)
  3. All `return` statements (what is actually returned)
  4. Shape-comment lines (lines with # [B,N,…] or → patterns — the "data-flow comments")
  5. Raise statements (what errors to expect)

For classes: class signature + class docstring + above for every method.
For module level: imports summary (unique top-level modules only) + top-level constants.

Output modes:
  --mode digest   (default)  single markdown file for LLM context window
  --mode outline             terse outline only (minimum tokens, max files covered)
  --mode focus <file>        full detail for one file + outline for rest

Usage:
  python extract_project_digest.py /data/trading_system_v2 --mode digest --out digest.md
  python extract_project_digest.py /data/trading_system_v2 --mode outline --out outline.md
"""

from __future__ import annotations

import ast
import argparse
import os
import re
import sys
import textwrap
import tokenize
import io
from pathlib import Path
from typing import List, Optional, Tuple


# ── Helpers ──────────────────────────────────────────────────────────────────

def _unparse(node: ast.AST) -> str:
    """Safe ast.unparse with fallback for older Python."""
    try:
        return ast.unparse(node)
    except Exception:
        return "..."


def _first_paragraph(docstring: str, max_lines: int = 4) -> str:
    """Return first non-empty paragraph of a docstring, capped at max_lines."""
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


def _shape_comments(source_lines: List[str], lineno_start: int, lineno_end: int) -> List[str]:
    """
    Extract lines that look like shape/flow annotations, e.g.:
      # [B, N, H]    → …    OUTPUT:    reshape    unsqueeze
    These are extremely dense info for LLM — keep them.
    """
    pattern = re.compile(
        r"#.*(\[.*\]|→|OUTPUT|INPUT|reshape|unsqueeze|squeeze|→|shape|dim)"
        r"|#\s*\w+\s*:\s*\[",
        re.IGNORECASE,
    )
    results = []
    for i in range(lineno_start - 1, min(lineno_end, len(source_lines))):
        line = source_lines[i].rstrip()
        stripped = line.strip()
        if stripped.startswith("#") and pattern.search(stripped):
            results.append(stripped)
    return results


def _collect_returns(func_node: ast.FunctionDef | ast.AsyncFunctionDef) -> List[str]:
    """Collect all `return expr` inside a function (non-recursive into nested funcs)."""
    returns = []
    for node in ast.walk(func_node):
        if node is func_node:
            continue
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            # Don't descend into nested functions
            continue
        if isinstance(node, ast.Return) and node.value is not None:
            returns.append(_unparse(node.value))
    return returns


def _collect_raises(func_node: ast.FunctionDef | ast.AsyncFunctionDef) -> List[str]:
    raises = []
    for node in ast.walk(func_node):
        if isinstance(node, ast.Raise) and node.exc is not None:
            raises.append(_unparse(node.exc))
    return raises


def _format_args(args: ast.arguments) -> str:
    """Format function arguments with type annotations."""
    parts = []

    # Positional / regular args
    num_defaults = len(args.defaults)
    num_args = len(args.args)
    for i, arg in enumerate(args.args):
        default_offset = i - (num_args - num_defaults)
        ann = f": {_unparse(arg.annotation)}" if arg.annotation else ""
        if default_offset >= 0:
            dflt = f" = {_unparse(args.defaults[default_offset])}"
        else:
            dflt = ""
        parts.append(f"{arg.arg}{ann}{dflt}")

    # *args
    if args.vararg:
        ann = f": {_unparse(args.vararg.annotation)}" if args.vararg.annotation else ""
        parts.append(f"*{args.vararg.arg}{ann}")
    elif args.kwonlyargs:
        parts.append("*")

    # Keyword-only args
    kw_defaults = {k: v for k, v in zip(args.kwonlyargs, args.kw_defaults) if v is not None}
    for arg in args.kwonlyargs:
        ann = f": {_unparse(arg.annotation)}" if arg.annotation else ""
        dflt = f" = {_unparse(kw_defaults[arg])}" if arg in kw_defaults else ""
        parts.append(f"{arg.arg}{ann}{dflt}")

    # **kwargs
    if args.kwarg:
        ann = f": {_unparse(args.kwarg.annotation)}" if args.kwarg.annotation else ""
        parts.append(f"**{args.kwarg.arg}{ann}")

    return ", ".join(parts)


def _func_signature(node: ast.FunctionDef | ast.AsyncFunctionDef, indent: str = "") -> str:
    prefix = "async def " if isinstance(node, ast.AsyncFunctionDef) else "def "
    ret = f" -> {_unparse(node.returns)}" if node.returns else ""
    args = _format_args(node.args)
    decorators = ""
    for d in node.decorator_list:
        decorators += f"{indent}@{_unparse(d)}\n"
    return f"{decorators}{indent}{prefix}{node.name}({args}){ret}:"


# ── Per-file digest ───────────────────────────────────────────────────────────

class FileDigest:
    """Produces a markdown digest of one Python source file."""

    def __init__(self, path: Path, project_root: Path, mode: str = "digest"):
        self.path = path
        self.rel = path.relative_to(project_root)
        self.mode = mode
        self.source = path.read_text(encoding="utf-8", errors="replace")
        self.source_lines = self.source.splitlines()
        try:
            self.tree = ast.parse(self.source, filename=str(path))
            self.parse_ok = True
        except SyntaxError as e:
            self.tree = None
            self.parse_ok = False
            self.parse_error = str(e)

    # ── Module-level items ────────────────────────────────────────────────

    def _imports_summary(self) -> str:
        """Unique top-level modules imported."""
        modules = set()
        for node in ast.walk(self.tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    modules.add(alias.name.split(".")[0])
            elif isinstance(node, ast.ImportFrom):
                if node.module:
                    modules.add(node.module.split(".")[0])
        return ", ".join(sorted(modules)) if modules else ""

    def _top_constants(self) -> List[str]:
        """Top-level simple assignments that look like constants (UPPER_CASE or typed)."""
        results = []
        for node in self.tree.body:
            if isinstance(node, ast.Assign):
                for t in node.targets:
                    name = _unparse(t)
                    if name.isupper() or len(name) <= 20:
                        val = _unparse(node.value)
                        if len(val) <= 80:
                            results.append(f"{name} = {val}")
            elif isinstance(node, ast.AnnAssign):
                name = _unparse(node.target)
                ann = _unparse(node.annotation)
                val = f" = {_unparse(node.value)}" if node.value else ""
                results.append(f"{name}: {ann}{val}")
        return results[:12]  # cap to avoid bloat

    # ── Function digest ───────────────────────────────────────────────────

    def _func_digest(
        self,
        node: ast.FunctionDef | ast.AsyncFunctionDef,
        indent: str = "  ",
        include_shapes: bool = True,
    ) -> str:
        lines = []
        sig = _func_signature(node, indent)
        lines.append(sig)

        # Docstring
        doc = ast.get_docstring(node)
        if doc:
            para = _first_paragraph(doc, max_lines=4)
            for ln in para.splitlines():
                lines.append(f"{indent}    # {ln}")

        if self.mode == "outline":
            return "\n".join(lines)

        # Shape/flow comments inside the body
        if include_shapes:
            shapes = _shape_comments(self.source_lines, node.lineno, node.end_lineno)
            if shapes:
                lines.append(f"{indent}    # ── shape/flow ──")
                for s in shapes[:8]:  # cap
                    lines.append(f"{indent}    {s}")

        # Return statements
        rets = _collect_returns(node)
        if rets:
            unique_rets = list(dict.fromkeys(rets))  # deduplicate preserving order
            for r in unique_rets[:4]:
                short = r if len(r) <= 120 else r[:117] + "..."
                lines.append(f"{indent}    return {short}")

        # Raises
        raises = _collect_raises(node)
        if raises:
            unique_raises = list(dict.fromkeys(raises))
            for r in unique_raises[:2]:
                lines.append(f"{indent}    # raises: {r}")

        return "\n".join(lines)

    # ── Class digest ──────────────────────────────────────────────────────

    def _class_digest(self, node: ast.ClassDef) -> str:
        lines = []

        # Class header + bases
        bases = ", ".join(_unparse(b) for b in node.bases) if node.bases else ""
        base_str = f"({bases})" if bases else ""
        decorators = "".join(f"@{_unparse(d)}\n" for d in node.decorator_list)
        lines.append(f"{decorators}class {node.name}{base_str}:")

        # Class docstring
        doc = ast.get_docstring(node)
        if doc:
            para = _first_paragraph(doc, max_lines=5)
            for ln in para.splitlines():
                lines.append(f"    # {ln}")

        # Class-level attributes (annotated assignments at class scope)
        for item in node.body:
            if isinstance(item, ast.AnnAssign):
                name = _unparse(item.target)
                ann = _unparse(item.annotation)
                val = f" = {_unparse(item.value)}" if item.value else ""
                lines.append(f"    {name}: {ann}{val}")

        lines.append("")

        # Methods
        for item in node.body:
            if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                lines.append(self._func_digest(item, indent="    "))
                lines.append("")

        return "\n".join(lines)

    # ── Full file render ──────────────────────────────────────────────────

    def render(self) -> str:
        if not self.parse_ok:
            return f"## {self.rel}\n⚠ Parse error: {self.parse_error}\n"

        out = [f"## `{self.rel}`"]

        # File-level docstring
        file_doc = ast.get_docstring(self.tree)
        if file_doc:
            para = _first_paragraph(file_doc, max_lines=5)
            out.append(f"> {para.replace(chr(10), '  ')}")

        # Imports
        imp = self._imports_summary()
        if imp:
            out.append(f"**imports:** `{imp}`")

        # Top constants
        consts = self._top_constants()
        if consts:
            out.append("**constants/globals:**")
            for c in consts:
                out.append(f"  {c}")

        out.append("")

        # Walk top-level nodes
        for node in self.tree.body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                out.append(self._func_digest(node, indent=""))
                out.append("")
            elif isinstance(node, ast.ClassDef):
                out.append(self._class_digest(node))
                out.append("")

        return "\n".join(out)


# ── Project-level digest ──────────────────────────────────────────────────────

def collect_py_files(root: Path) -> List[Path]:
    """Collect all .py files, excluding __pycache__ and hidden dirs."""
    files = []
    for p in sorted(root.rglob("*.py")):
        parts = p.parts
        if any(part.startswith(".") or part == "__pycache__" for part in parts):
            continue
        files.append(p)
    return files


def estimate_tokens(text: str) -> int:
    """Rough token estimate: ~3.5 chars per token for code."""
    return len(text) // 3


def render_project(root: Path, mode: str, focus_file: Optional[str] = None) -> str:
    root = Path(root).resolve()
    files = collect_py_files(root)

    sections = []
    sections.append(f"# Project Digest: `{root.name}`")
    sections.append(f"**mode:** {mode}  |  **files:** {len(files)}\n")

    # File tree
    sections.append("## File Tree")
    sections.append("```")
    for f in files:
        rel = f.relative_to(root)
        size_kb = f.stat().st_size / 1024
        sections.append(f"  {rel}  ({size_kb:.1f} KB)")
    sections.append("```\n")

    total_chars = 0
    for f in files:
        is_focus = focus_file and (focus_file in str(f) or focus_file in str(f.relative_to(root)))
        file_mode = "digest" if (mode == "digest" or is_focus) else "outline"
        digest = FileDigest(f, root, mode=file_mode)
        rendered = digest.render()
        sections.append(rendered)
        total_chars += len(rendered)

    body = "\n\n".join(sections)
    token_est = estimate_tokens(body)
    footer = f"\n\n---\n*Digest generated from {len(files)} files · ~{token_est:,} tokens estimated*"
    return body + footer


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Extract token-efficient LLM digest from a Python project."
    )
    parser.add_argument("project_dir", help="Root directory of the Python project")
    parser.add_argument(
        "--mode",
        choices=["digest", "outline"],
        default="digest",
        help=(
            "digest: signature + docstring + returns + shape comments (default); "
            "outline: signatures only (minimum tokens)"
        ),
    )
    parser.add_argument(
        "--focus",
        metavar="FILE",
        default=None,
        help="Give full digest treatment to this file; outline for everything else",
    )
    parser.add_argument(
        "--out",
        metavar="OUTPUT",
        default=None,
        help="Write output to file instead of stdout",
    )
    args = parser.parse_args()

    result = render_project(
        root=args.project_dir,
        mode=args.mode,
        focus_file=args.focus,
    )

    if args.out:
        Path(args.out).write_text(result, encoding="utf-8")
        token_est = estimate_tokens(result)
        print(f"✓ Wrote {args.out}  (~{token_est:,} tokens estimated)")
    else:
        print(result)


if __name__ == "__main__":
    main()
