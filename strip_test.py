#!/usr/bin/env python3
"""
strip_main.py

step 0: create a folder named `no_test_d` in the current path
step 1: find all .py files in the current folder and its sub-folders
step 2: remove every top-level `if __name__ == "__main__":` block
        from each file, then save the result into `no_test_d`
        (preserving the original sub-folder structure)

Usage:
    python strip_main.py            # process current working directory
    python strip_main.py /some/dir  # process another directory
"""

import ast
import os
import sys

OUT_DIR_NAME = "strip_test_d"


def is_main_guard(node):
    """Return True if `node` is an `if __name__ == "__main__":` statement."""
    if not isinstance(node, ast.If):
        return False

    test = node.test
    if not isinstance(test, ast.Compare):
        return False

    # left side must be the name `__name__`
    if not (isinstance(test.left, ast.Name) and test.left.id == "__name__"):
        return False

    # single `==` comparison
    if len(test.ops) != 1 or not isinstance(test.ops[0], ast.Eq):
        return False

    # right side must be the string "__main__"
    comparator = test.comparators[0]
    if isinstance(comparator, ast.Constant) and comparator.value == "__main__":
        return True

    return False


def strip_main_blocks(source):
    """
    Remove all top-level `if __name__ == "__main__":` blocks from `source`.
    Returns the cleaned source as a string.

    Falls back to returning the original source unchanged if the file
    cannot be parsed (e.g. syntax error / Python 2 code).
    """
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return source, False

    # Collect 1-based line ranges of every main-guard at module level.
    ranges = []
    for node in tree.body:
        if is_main_guard(node):
            start = node.lineno
            # end_lineno is available on Python 3.8+
            end = getattr(node, "end_lineno", start)
            ranges.append((start, end))

    if not ranges:
        return source, False

    lines = source.splitlines(keepends=True)
    drop = set()
    for start, end in ranges:
        # convert to 0-based indices
        for i in range(start - 1, end):
            drop.add(i)

    kept = [ln for idx, ln in enumerate(lines) if idx not in drop]
    cleaned = "".join(kept)

    # tidy up trailing blank lines, keep a single newline at EOF
    cleaned = cleaned.rstrip("\n") + "\n" if cleaned.strip() else ""
    return cleaned, True


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    root = os.path.abspath(root)
    out_root = os.path.join(root, OUT_DIR_NAME)

    # step 0: create the output folder
    os.makedirs(out_root, exist_ok=True)

    processed = 0
    stripped = 0

    # step 1: walk through current + sub folders
    for dirpath, dirnames, filenames in os.walk(root):
        # don't descend into the output folder itself
        dirnames[:] = [d for d in dirnames if os.path.join(dirpath, d) != out_root]

        for name in filenames:
            if not name.endswith(".py"):
                continue

            src_path = os.path.join(dirpath, name)

            # skip this script if it happens to live in the tree
            if os.path.abspath(src_path) == os.path.abspath(__file__):
                continue

            with open(src_path, "r", encoding="utf-8") as f:
                source = f.read()

            # step 2: remove the __main__ blocks
            cleaned, changed = strip_main_blocks(source)

            # mirror the original sub-folder structure under no_test_d
            rel = os.path.relpath(src_path, root)
            dst_path = os.path.join(out_root, rel)
            os.makedirs(os.path.dirname(dst_path), exist_ok=True)

            with open(dst_path, "w", encoding="utf-8") as f:
                f.write(cleaned)

            processed += 1
            if changed:
                stripped += 1
            tag = "stripped" if changed else "copied  "
            print(f"[{tag}] {rel}")

    print(
        f"\nDone. {processed} file(s) written to {out_root!r} "
        f"({stripped} had a __main__ block removed)."
    )


if __name__ == "__main__":
    main()
