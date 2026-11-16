#!/usr/bin/env python3
"""Remove literal curl/wget IPv4-only options from Bash files, with backups.

Dependencies (in an isolated venv): tree-sitter>=0.25,<0.27 and
tree-sitter-bash==0.25.1. Never executes the input scripts.
Usage: python remove_ipv4_only.py [--preview] goodv3.sh pre_tcpx.sh
Backs up ALL inputs before analysis, including in preview mode.
Comments, heredoc text, eval strings, aliases and global rc files are NOT edited.
Dynamic/unknown arguments stop analysis of that command; REVIEW is printed.
"""
import argparse
import datetime
import difflib
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile


ENV = {"PATH": "/usr/local/bin:/usr/bin:/bin", "LC_ALL": "C", "HOME": "/nonexistent"}


def run(argv, data=None):
    return subprocess.run(argv, input=data, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, env=ENV, timeout=30, check=True).stdout


def syntax(data):
    run(["/bin/bash", "--noprofile", "--norc", "-n"], data)


def walk(node):
    yield node
    for child in node.named_children:
        yield from walk(child)


def literal(raw):
    """Decode only static shell words; no expansion, globbing, eval, or execution."""
    s = raw.decode("utf-8", "surrogateescape")
    out, quote, i = [], None, 0
    while i < len(s):
        c = s[i]
        if quote == "'":
            if c == "'":
                quote = None
            else:
                out.append(c)
        elif c == "\\":
            i += 1
            if i == len(s):
                return None
            d = s[i]
            if d != "\n":
                if quote == '"' and d not in '$`"\\':
                    out.append("\\")
                out.append(d)
        elif c == quote:
            quote = None
        elif c in "\"'" and quote is None:
            quote = c
        elif c in "$`" or (quote is None and (c.isspace() or c in "*?[]{}~()<>|;&")):
            return None
        else:
            out.append(c)
        i += 1
    return None if quote else "".join(out)


def option_tables(tool):
    """Use the locally installed tool's help to distinguish options from values."""
    argv = [tool, "--help", "all"] if tool == "curl" else [tool, "--help"]
    help_text = run(argv).decode("utf-8", "replace")
    short, long = {}, {}
    pattern = r"^\s*(?:-([A-Za-z0-9#:\u0021]+),\s*)?--([\w-]+)([^\n]*)"
    for line in help_text.splitlines():
        match = re.match(pattern, line)
        if not match:
            continue
        abbr, name, tail = match.groups()
        takes = tail.startswith("=") if tool == "wget" else tail.lstrip().startswith(("<", "["))
        long[name] = takes
        if abbr:
            if len(abbr) == 1:
                short[abbr] = takes
            elif tool == "wget" and abbr.startswith("n"):
                # Wget's historical -nv/-nc/-np/-nd/-nH are -n plus a value.
                short["n"] = True
    if not short or long.get("ipv4" if tool == "curl" else "inet4-only") is not False:
        raise ValueError(f"cannot reliably read {tool} --help; no files modified")
    return short, long


def transform(data, parser, tables):
    tree = parser.parse(data)
    if tree.root_node.has_error:
        raise ValueError("Bash parser reported an error; no files modified")
    edits, reviews = [], []

    def review(node, reason):
        reviews.append(f"line {node.start_point[0] + 1}: {reason}")

    for node in walk(tree.root_node):
        if node.type != "command":
            continue
        ancestor = node.parent
        in_heredoc = False
        while ancestor is not None:
            if ancestor.type == "heredoc_body":
                in_heredoc = True
                break
            ancestor = ancestor.parent
        if in_heredoc:
            continue
        name = node.child_by_field_name("name")
        if name is None:
            continue
        command = literal(data[name.start_byte:name.end_byte])
        args = [(c.start_byte, c.end_byte) for i, c in enumerate(node.children)
                if node.field_name_for_child(i) == "argument"]
        # Tree-sitter splits an unquoted word at a backslash-newline: rejoin it.
        merged = []
        for start, end in args:
            if merged and re.fullmatch(rb"(?:\\\n)+", data[merged[-1][1]:start]):
                merged[-1] = (merged[-1][0], end)
            else:
                merged.append((start, end))
        args = merged
        # A plain `command curl`, `sudo curl`, or `env curl` is unambiguous.
        # Wrappers with their own flags/assignments are left for manual review.
        while command in ("command", "sudo", "env") and args:
            start, end = args[0]
            value = literal(data[start:end])
            if value is None or value.startswith("-") or "=" in value:
                break
            command, args = value, args[1:]
        tool = os.path.basename(command or "")
        if tool not in ("curl", "wget"):
            continue
        if tool not in tables:
            tables[tool] = option_tables(tool)
        short, long = tables[tool]
        pending, stop = None, False
        for start, end in args:
            value = literal(data[start:end])
            if pending is not None:
                if tool == "wget" and pending == "execute" and value is not None:
                    new = re.sub(r"^(\s*inet4_only\s*=\s*)(?:on|yes|1|true)(\s*)$",
                                 r"\g<1>off\2", value, flags=re.I)
                    if new != value:
                        edits.append((start, end, shlex.quote(new).encode("utf-8", "surrogateescape")))
                pending = None
                continue
            if value is None:
                review(node, "dynamic/complex argument: remaining arguments left unchanged")
                break
            if value == "--":
                break
            if value.startswith("--"):
                key, sep, attached = value[2:].partition("=")
                target = "ipv4" if tool == "curl" else "inet4-only"
                if key == target and not sep:
                    edits.append((start, end, b""))
                    continue
                if tool == "wget" and key == target and sep and attached.lower() in ("on", "yes", "true", "1"):
                    edits.append((start, end, b""))
                    continue
                takes = long.get(key)
                if takes is None and tool == "curl" and key.startswith("no-"):
                    # curl allows --no-BOOL; do not infer value-taking variants.
                    if long.get(key[3:]) is False:
                        takes = False
                if takes is None:
                    review(node, f"unknown/abbreviated option --{key}: remaining arguments unchanged")
                    break
                if takes and not sep:
                    pending = "execute" if key == "execute" else "value"
                elif tool == "wget" and key == "execute" and sep:
                    new = re.sub(r"^(\s*inet4_only\s*=\s*)(?:on|yes|1|true)(\s*)$",
                                 r"\g<1>off\2", attached, flags=re.I)
                    if new != attached:
                        edits.append((start, end, shlex.quote("--execute=" + new).encode()))
                continue
            if not value.startswith("-") or value == "-":
                continue
            chars, j, removed = list(value), 1, []
            while j < len(value):
                ch = value[j]
                if ch not in short:
                    review(node, f"unknown short option -{ch}: argument and remaining arguments unchanged")
                    stop = True
                    break
                if ch == "4":
                    removed.append(j)
                if short[ch]:
                    if j + 1 == len(value):
                        pending = "execute" if tool == "wget" and ch == "e" else "value"
                    elif tool == "wget" and ch == "e":
                        attached = value[j + 1:]
                        changed = re.sub(r"^(\s*inet4_only\s*=\s*)(?:on|yes|1|true)(\s*)$",
                                         r"\g<1>off\2", attached, flags=re.I)
                        if changed != attached:
                            new = "".join(c for k, c in enumerate(value[:j + 1]) if k not in removed) + changed
                            edits.append((start, end, shlex.quote(new).encode()))
                            removed = []
                    break
                j += 1
            if stop:
                break
            if removed:
                new = "".join(ch for j, ch in enumerate(chars) if j not in removed)
                new = b"" if new == "-" else shlex.quote(new).encode("utf-8", "surrogateescape")
                edits.append((start, end, new))
    # All offsets refer to the original bytes. No formatting pass is performed.
    result = data
    for start, end, replacement in sorted(edits, reverse=True):
        result = result[:start] + replacement + result[end:]
    if parser.parse(result).root_node.has_error:
        raise ValueError("edited Bash failed parsing; no files modified")
    syntax(result)
    return result, edits, reviews


def atomic_write(path, data, original_stat):
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        shutil.copystat(path, tmp)
        current = os.stat(tmp)
        if (current.st_uid, current.st_gid) != (original_stat.st_uid, original_stat.st_gid):
            os.chown(tmp, original_stat.st_uid, original_stat.st_gid)
        os.chmod(tmp, stat.S_IMODE(original_stat.st_mode))
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--preview", action="store_true", help="back up and show diff; do not edit inputs")
    ap.add_argument("files", nargs="+", type=Path)
    opt = ap.parse_args()
    snapshots = []
    seen = set()
    for supplied in opt.files:
        path = supplied.absolute()
        st = path.lstat()
        if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
            raise ValueError(f"refusing non-regular, symlink or hard-linked file: {path}")
        if path in seen:
            raise ValueError(f"duplicate input: {path}")
        seen.add(path)
        snapshots.append((path, path.read_bytes(), st))
    # Back up every input BEFORE parsing or changing any target.
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    backups = []
    for path, data, st in snapshots:
        bak = Path(f"{path}.bak.{stamp}.{os.getpid()}")
        with bak.open("xb") as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        shutil.copystat(path, bak)
        if bak.read_bytes() != data:
            raise ValueError(f"backup verification failed: {bak}")
        backups.append(bak)
        print(f"BACKUP {bak}", flush=True)
    try:
        from tree_sitter import Language, Parser
        import tree_sitter_bash
    except ImportError:
        raise ValueError("missing dependencies: install tree-sitter and tree-sitter-bash in a venv")
    parser = Parser(Language(tree_sitter_bash.language()))
    tables, plans = {}, []
    for path, data, st in snapshots:
        syntax(data)
        result, edits, reviews = transform(data, parser, tables)
        print(f"\nFILE {path}: {len(edits)} argument edit(s)")
        for line in reviews:
            print(f"REVIEW {path}:{line}")
        if result != data:
            a, b = data.decode("utf-8", "replace"), result.decode("utf-8", "replace")
            sys.stdout.writelines(difflib.unified_diff(a.splitlines(True), b.splitlines(True),
                                                     fromfile=str(path), tofile=str(path) + " (new)"))
        plans.append((path, data, st, result))
    # Recheck every original before the first replacement.
    for path, data, st, result in plans:
        now = path.lstat()
        if (now.st_dev, now.st_ino, now.st_mtime_ns, now.st_ctime_ns) != (st.st_dev, st.st_ino, st.st_mtime_ns, st.st_ctime_ns) or path.read_bytes() != data:
            raise ValueError(f"input changed during analysis; no files modified: {path}")
    if opt.preview:
        print("\nPREVIEW ONLY: inputs unchanged; backups retained.")
        return
    written = []
    try:
        for path, data, st, result in plans:
            if result != data:
                atomic_write(path, result, st)
                written.append((path, data, st))
                print(f"UPDATED {path}")
    except Exception:
        for path, data, st in reversed(written):
            try:
                atomic_write(path, data, st)
                print(f"ROLLED BACK {path}")
            except Exception as rollback_error:
                print(f"ROLLBACK FAILED {path}: {rollback_error}; restore the printed backup", file=sys.stderr)
        raise
    print("\nDONE. Comments/embedded shell strings and global curl/wget rc files were not edited.")
    print("Check REVIEW notices and any aliases, variables, -K/--config, .curlrc, .wgetrc or /etc/wgetrc separately.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        detail = getattr(exc, "stderr", b"") or b""
        print(f"ERROR: {exc}", file=sys.stderr)
        if detail:
            print(detail.decode("utf-8", "replace"), file=sys.stderr)
        sys.exit(1)
