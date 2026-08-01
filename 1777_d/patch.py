#!/usr/bin/env python3
"""
patch.py — fix query-flag parsing in 1777.py

Problem
-------
    ip:1777/path/to/a_folder?t?md      -> did not work

Starlette parses the query string "t?md" as ONE key ("t?md") with an empty
value, so the old tolerant code (which only split the *value* on "?") never
saw "t" or "md".

Fix
---
Parse the RAW query string instead of the already-parsed key/value pairs, and
split it on every plausible separator.  After the patch all of these work and
mean exactly the same thing:

    ?t?md   ?t&md   ?md?t   ?md&t   ?t;md   ?t,md   ?T?MD   ?t=1&md
    ?s?raw  ?raw?s  ?t?raw  ?md?s   ...

Semantics kept as before:
    s / t   -> sort (size / time); s wins if both are given
    raw     -> serve as plain text (wins over md)
    md      -> force markdown rendering
Flags keep propagating into child links as a normalised "?t&md" suffix.

How it works
------------
This is NOT a text/regex patch.  The file is parsed with `ast`, the two
flag-collection statement blocks are located in the syntax tree (by shape, not
by exact text), and only those exact line ranges are rewritten.  The result is
re-parsed before anything is written to disk, and a timestamped backup is kept.
Running it twice is a no-op.

Usage
-----
    python3 patch.py 1777.py
    python3 patch.py 1777.py --dry-run
"""

import argparse
import ast
import io
import os
import shutil
import sys
import time

MARKER = "_collect_flags"

HELPER_SRC = '''\
# --- patched: robust query-flag parsing -------------------------------------
def _collect_flags(request) -> set:
    """
    Turn the RAW query string into a flat set of lowercase flags.

    Starlette hands "?t?md" to us as a single key "t?md" (no "=" -> no value),
    which is why per-key/value parsing used to lose the second flag.  Working
    from request.url.query instead makes every separator equivalent:

        ?t&md   ?t?md   ?md?t   ?t;md   ?t,md   ?T?MD   ?t=1&md
    """
    try:
        raw = request.url.query or ""
    except Exception:
        try:
            raw = request.scope.get("query_string", b"") or b""
        except Exception:
            raw = ""

    if isinstance(raw, (bytes, bytearray)):
        raw = raw.decode("utf-8", "ignore")

    try:
        raw = unquote(str(raw))
    except Exception:
        raw = str(raw)

    # every separator (and "=", so "?t=1&md" also yields "t") is equivalent
    for ch in "?;,&=+":
        raw = raw.replace(ch, " ")

    flags = set()
    for token in raw.split():
        token = token.strip().lower()
        if token:
            flags.add(token)
    return flags
# --- end patch --------------------------------------------------------------


'''


def die(msg):
    sys.stderr.write("patch.py: error: %s\n" % msg)
    sys.exit(1)


def iter_bodies(node):
    """Yield every statement-list found anywhere in the tree."""
    for n in ast.walk(node):
        for field in ("body", "orelse", "finalbody"):
            body = getattr(n, field, None)
            if isinstance(body, list) and body and isinstance(body[0], ast.stmt):
                yield body


def is_set_call(node):
    return (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "set"
        and not node.args
        and not node.keywords
    )


def find_flag_blocks(tree):
    """
    Locate:   <name> = set()
              for k, v in request.query_params.multi_items():
                  ...
    Returns a list of (start_lineno, end_lineno, varname).
    """
    found = []
    for body in iter_bodies(tree):
        for i, stmt in enumerate(body[:-1]):
            if not isinstance(stmt, ast.Assign):
                continue
            if len(stmt.targets) != 1 or not isinstance(stmt.targets[0], ast.Name):
                continue
            name = stmt.targets[0].id
            if not is_set_call(stmt.value):
                continue
            nxt = body[i + 1]
            if not isinstance(nxt, ast.For):
                continue
            iter_dump = ast.dump(nxt.iter)
            body_dump = ast.dump(nxt)
            if "multi_items" not in iter_dump:
                continue
            if ("'%s'" % name) not in body_dump and ('"%s"' % name) not in body_dump:
                continue
            found.append((stmt.lineno, nxt.end_lineno, name))
    # de-duplicate (ast.walk can reach the same body more than once)
    return sorted(set(found))


def find_helper_anchor(tree, lines):
    """Line number (1-based) to insert the helper before."""
    best = None
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if node.name in ("root", "navigate"):
                start = node.lineno
                for dec in node.decorator_list:
                    start = min(start, dec.lineno)
                start = min(start, getattr(node, "lineno", start))
                # include any leading decorator '@' line
                if best is None or start < best:
                    best = start
    if best is not None:
        # back up over a contiguous comment block directly above
        i = best - 2
        while i >= 0 and lines[i].lstrip().startswith("#"):
            i -= 1
        return i + 2
    # fallback: after the last top-level import
    last_import = 0
    for node in tree.body:
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            last_import = max(last_import, node.end_lineno)
    return last_import + 1 if last_import else 1


def main():
    ap = argparse.ArgumentParser(description="Patch 1777.py query-flag parsing")
    ap.add_argument("target", help="path to 1777.py")
    ap.add_argument("--dry-run", action="store_true", help="show what would change")
    ap.add_argument("--no-backup", action="store_true")
    args = ap.parse_args()

    path = args.target
    if not os.path.isfile(path):
        die("no such file: %s" % path)

    with io.open(path, "r", encoding="utf-8") as f:
        src = f.read()

    try:
        tree = ast.parse(src, filename=path)
    except SyntaxError as e:
        die("%s does not parse as Python: %s" % (path, e))

    if MARKER in src:
        print("Already patched (found %s). Nothing to do." % MARKER)
        return 0

    lines = src.splitlines(keepends=True)

    blocks = find_flag_blocks(tree)
    if not blocks:
        die(
            "could not locate the flag-collection blocks "
            "(`flags = set()` / `file_flags = set()` followed by a "
            "`for k, v in request.query_params.multi_items():` loop). "
            "Is this the right file?"
        )

    print("Found %d flag block(s):" % len(blocks))
    for start, end, name in blocks:
        print("  lines %4d-%-4d  %s" % (start, end, name))

    # 1) rewrite the blocks, bottom-up so earlier line numbers stay valid
    for start, end, name in sorted(blocks, reverse=True):
        indent = lines[start - 1][: len(lines[start - 1]) - len(lines[start - 1].lstrip())]
        replacement = "%s%s = _collect_flags(request)\n" % (indent, name)
        lines[start - 1 : end] = [replacement]

    # 2) insert the helper (recompute anchor against the edited buffer)
    new_src = "".join(lines)
    try:
        new_tree = ast.parse(new_src, filename=path)
    except SyntaxError as e:
        die("internal: rewritten source failed to parse: %s" % e)

    anchor = find_helper_anchor(new_tree, lines)
    lines[anchor - 1 : anchor - 1] = [HELPER_SRC]
    new_src = "".join(lines)

    # 3) final safety net: it must still be valid Python
    try:
        compile(new_src, path, "exec")
    except SyntaxError as e:
        die("refusing to write: patched file would not compile: %s" % e)

    if new_src == src:
        print("Nothing changed.")
        return 0

    if args.dry_run:
        import difflib

        sys.stdout.writelines(
            difflib.unified_diff(
                src.splitlines(keepends=True),
                new_src.splitlines(keepends=True),
                fromfile=path,
                tofile=path + " (patched)",
            )
        )
        print("\n[dry-run] no files written.")
        return 0

    if not args.no_backup:
        backup = "%s.bak.%s" % (path, time.strftime("%Y%m%d-%H%M%S"))
        shutil.copy2(path, backup)
        print("Backup: %s" % backup)

    with io.open(path, "w", encoding="utf-8") as f:
        f.write(new_src)

    print("Patched: %s" % path)
    print("Helper _collect_flags() inserted at line %d." % anchor)
    print("Now ?t?md, ?md?t, ?t&md, ?t;md, ?T?MD ... all work.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
