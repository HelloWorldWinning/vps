#!/usr/bin/env python3
"""markmap.py — Render markdown to interactive markmap HTML.

Pure-Python replacement for markmap.sh. All markdown patching, filename
sanitization, frontmatter manipulation and HTML post-processing happens in
this single process; we only shell out to ``markmap`` (the npm CLI) and
optionally ``npm install -g markmap-cli`` when the CLI is missing.

Run as::

    python3 markmap.py
"""

from __future__ import annotations

import hashlib
import re
import select
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from datetime import datetime
from pathlib import Path
from typing import List, Optional, TextIO, Tuple

# ─────────────────────────────────────────────────────────────────────
# ANSI: bold + red (matches the original markmap.sh formatting)
# ─────────────────────────────────────────────────────────────────────
BR = "\033[1;31m"
RS = "\033[0m"

# ─────────────────────────────────────────────────────────────────────
# NEW_CODE — keyboard-control script appended before </body>.
#
# Paste your <script>...</script> block between the triple quotes below.
# If left empty/whitespace, no injection is performed.
# ─────────────────────────────────────────────────────────────────────
NEW_CODE = r"""<script>
(() => {
  function walk(node, fn, depth = 1) {
    if (!node) return;

    fn(node, depth);

    if (node.children) {
      node.children.forEach(child => walk(child, fn, depth + 1));
    }
  }

  function getMaxDepth(root) {
    let maxDepth = 1;

    walk(root, (_, depth) => {
      maxDepth = Math.max(maxDepth, depth);
    });

    return maxDepth;
  }

  function getVisibleDepth(node, depth = 1) {
    if (!node) return 1;

    let maxVisible = depth;

    if (!node.payload?.fold && node.children) {
      for (const child of node.children) {
        maxVisible = Math.max(maxVisible, getVisibleDepth(child, depth + 1));
      }
    }

    return maxVisible;
  }

  function setVisibleDepth(mm, visibleDepth) {
    const data = mm.state.data;
    const maxDepth = getMaxDepth(data);

    visibleDepth = Math.max(1, Math.min(visibleDepth, maxDepth));

    walk(data, (node, depth) => {
      if (!node.children || node.children.length === 0) return;

      node.payload = {
        ...node.payload,
        fold: depth >= visibleDepth ? 1 : 0
      };
    });

    mm.renderData(data);
  }

  function expandAll(mm) {
    const data = mm.state.data;

    walk(data, node => {
      if (!node.children || node.children.length === 0) return;

      node.payload = {
        ...node.payload,
        fold: 0
      };
    });

    mm.renderData(data);
  }

  function fit(mm) {
    mm.fit();
  }

  function decodeHtml(value) {
    const textarea = document.createElement("textarea");
    textarea.innerHTML = String(value || "");
    return textarea.value;
  }

  function stripHtml(value) {
    const div = document.createElement("div");
    div.innerHTML = String(value || "");
    return div.textContent || div.innerText || "";
  }

  function normalizeText(value) {
    return stripHtml(decodeHtml(value))
      .normalize("NFKC")
      .replace(/[\u200B-\u200D\uFEFF]/g, "")
      .replace(/\u00A0/g, " ")
      .replace(/\s+/g, " ")
      .toLowerCase()
      .trim();
  }

  function normalizeTextCompact(value) {
    return normalizeText(value).replace(/\s+/g, "");
  }

  function getNodeText(node) {
    return [
      node.content,
      node.payload?.text,
      node.payload?.label,
      node.payload?.title
    ]
      .filter(Boolean)
      .map(normalizeText)
      .join(" ");
  }

  function textIncludes(text, keyword) {
    const source = normalizeText(text);
    const target = normalizeText(keyword);

    if (!target) return false;
    if (source.includes(target)) return true;

    return normalizeTextCompact(source).includes(normalizeTextCompact(target));
  }

  function findPaths(root, keyword) {
    const results = [];

    function dfs(node, path) {
      if (!node) return;

      const currentPath = [...path, node];
      const text = getNodeText(node);

      if (textIncludes(text, keyword)) {
        results.push(currentPath);
      }

      if (node.children) {
        node.children.forEach(child => dfs(child, currentPath));
      }
    }

    dfs(root, []);
    return results;
  }

  function clearFindHighlight() {
    document
      .querySelectorAll(".mm-find-box")
      .forEach(el => el.remove());

    document
      .querySelectorAll(".mm-find-hit")
      .forEach(el => el.classList.remove("mm-find-hit"));
  }

  function drawFindBoxes() {
    const SVG_NS = "http://www.w3.org/2000/svg";

    document.querySelectorAll(".mm-find-hit").forEach(el => {
      // Remove old box first so repeated redraws do not stack or overlap.
      el.querySelectorAll(".mm-find-box").forEach(box => box.remove());

      const target = el.querySelector("foreignObject, text");
      if (!target || typeof target.getBBox !== "function") return;

      let box;
      try {
        box = target.getBBox();
      } catch {
        return;
      }

      const padX = 5;
      const padY = 4;

      const rect = document.createElementNS(SVG_NS, "rect");
      rect.setAttribute("class", "mm-find-box");
      rect.setAttribute("x", box.x - padX);
      rect.setAttribute("y", box.y - padY);
      rect.setAttribute("width", box.width + padX * 2);
      rect.setAttribute("height", box.height + padY * 2);
      rect.setAttribute("rx", 6);
      rect.setAttribute("ry", 6);

      el.insertBefore(rect, el.firstChild);
    });
  }

  function highlightRenderedNodes(keyword) {
    clearFindHighlight();

    document.querySelectorAll(".markmap-node").forEach(el => {
      if (textIncludes(el.textContent, keyword)) {
        el.classList.add("mm-find-hit");
      }
    });

    drawFindBoxes();

    return document.querySelectorAll(".mm-find-hit").length;
  }

  function highlightRenderedNodesWhenReady(keyword) {
    let tries = 0;
    let foundCount = 0;
    const maxTries = 45;

    function retry() {
      const hits = highlightRenderedNodes(keyword);

      if (hits > 0) {
        foundCount += 1;
      }

      tries += 1;

      // Keep refreshing after first hit so boxes remain correct after expansion/layout animation.
      if (tries < maxTries && foundCount < 8) {
        setTimeout(() => requestAnimationFrame(retry), 80);
      }
    }

    requestAnimationFrame(retry);
  }

  function ensureFindStyle() {
    if (document.getElementById("mm-find-style")) return;

    const style = document.createElement("style");
    style.id = "mm-find-style";

    style.textContent = `
      .mm-find-hit text {
        fill: #000 !important;
        font-weight: 700;
      }

      .mm-find-hit circle {
        fill: #ff3d00 !important;
        stroke: #ffffff !important;
        stroke-width: 2px !important;
      }

      .mm-find-hit foreignObject {
        outline: none !important;
        box-shadow: none !important;
        background: transparent !important;
      }

      .mm-find-box {
        fill: rgba(255, 193, 7, 0.18);
        stroke: #ff3d00;
        stroke-width: 2.5px;
        vector-effect: non-scaling-stroke;
        filter: drop-shadow(0 0 5px rgba(255, 152, 0, 0.75));
        pointer-events: none;
        animation: mmFindBoxPulse 1s ease-in-out infinite alternate;
      }

      @keyframes mmFindBoxPulse {
        from {
          stroke-opacity: 0.75;
          filter: drop-shadow(0 0 3px rgba(255, 152, 0, 0.55));
        }
        to {
          stroke-opacity: 1;
          filter: drop-shadow(0 0 8px rgba(255, 61, 0, 0.85));
        }
      }
    `;

    document.head.appendChild(style);
  }

  function openMatchedPaths(matches) {
    matches.forEach(path => {
      path.slice(0, -1).forEach(node => {
        if (node.children && node.children.length > 0) {
          node.payload = {
            ...node.payload,
            fold: 0
          };
        }
      });
    });
  }

  function findInMap(mm) {
    const keyword = prompt("Find in map:");

    if (!keyword || !keyword.trim()) return;

    ensureFindStyle();

    const data = mm.state.data;
    const matches = findPaths(data, keyword);

    if (matches.length === 0) {
      clearFindHighlight();
      alert(`No match: ${keyword}`);
      return;
    }

    openMatchedPaths(matches);
    mm.renderData(data);

    highlightRenderedNodesWhenReady(keyword);

    setTimeout(() => {
      mm.fit();
    }, 200);
  }

  document.addEventListener("keydown", e => {
    const mm = window.mm;
    if (!mm || !mm.state?.data) return;

    const tag = e.target?.tagName?.toLowerCase();

    if (
      tag === "input" ||
      tag === "textarea" ||
      tag === "select" ||
      e.target?.isContentEditable
    ) {
      return;
    }

    const data = mm.state.data;
    const visibleDepth = getVisibleDepth(data);
    const maxDepth = getMaxDepth(data);

    if (e.key === " " || e.key === "0") {
      e.preventDefault();
      fit(mm);
      return;
    }

    if (e.key === "f") {
      e.preventDefault();
      findInMap(mm);
      return;
    }

    if (e.key === "g" || e.key === "Enter") {
      e.preventDefault();
      expandAll(mm);
      setTimeout(() => fit(mm), 330);
      return;
    }

    if (e.key === "d") {
      e.preventDefault();
      setVisibleDepth(mm, Math.min(visibleDepth + 1, maxDepth));
      setTimeout(() => fit(mm), 330);
      return;
    }

    if (e.key === "s") {
      e.preventDefault();
      setVisibleDepth(mm, Math.max(visibleDepth - 1, 1));
      setTimeout(() => fit(mm), 330);
      return;
    }

    if (e.key === "a") {
      e.preventDefault();
      setVisibleDepth(mm, 1);
      setTimeout(() => fit(mm), 330);
      return;
    }

    if (/^[1-9]$/.test(e.key)) {
      e.preventDefault();
      setVisibleDepth(mm, Number(e.key));
      setTimeout(() => fit(mm), 330);
      return;
    }



  });
})();
</script>

"""

# Filler tokens (typed in place of real markdown) that should still be
# treated as "no content" and trigger file-mode.
FILLER_TOKENS = {"", "n", "N", "呢", "你", "能"}


# ─────────────────────────────────────────────────────────────────────
# CLI bootstrap
# ─────────────────────────────────────────────────────────────────────
def ensure_markmap_cli() -> None:
    """Install markmap-cli globally via npm if the CLI is not on PATH."""
    if shutil.which("markmap") is not None:
        return

    if shutil.which("npm") is None:
        sys.stderr.write("[!] npm is required to install markmap-cli.\n")
        sys.exit(1)

    print("[*] markmap not found. Installing markmap-cli globally...")
    subprocess.run(["npm", "install", "-g", "markmap-cli"], check=True)


# ─────────────────────────────────────────────────────────────────────
# Filename helpers
# ─────────────────────────────────────────────────────────────────────
def _truncate_utf8(value: str, max_bytes: int) -> str:
    """Truncate ``value`` so its UTF-8 encoding is at most ``max_bytes``."""
    encoded = value.encode("utf-8")
    if len(encoded) <= max_bytes:
        return value
    return encoded[:max_bytes].decode("utf-8", "ignore").rstrip("._- ")


def make_outfile_path(title: str, outdir: Optional[Path] = None) -> Path:
    """Build a robust output filename from a (possibly Unicode) title.

    Mirrors the inline Python helper from the original bash script.
    """
    outdir = (outdir or Path.cwd()).expanduser().resolve()

    raw = title or ""
    name = unicodedata.normalize("NFKC", raw)

    bad_chars = '/\\:*?"<>|'
    name = "".join(
        "_" if ch in bad_chars or ord(ch) < 32 or ord(ch) == 127 else ch for ch in name
    )

    # Replace all whitespace classes (spaces, tabs, NBSP, …) with "_".
    name = re.sub(r"\s+", "_", name, flags=re.UNICODE)

    # Keep Unicode letters/digits + safe punctuation; everything else → "_".
    name = "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in name)

    name = re.sub(r"_+", "_", name).strip("._- ")

    if not name or name in {".", ".."}:
        digest = hashlib.sha256(raw.encode("utf-8", "ignore")).hexdigest()[:8]
        name = f"markmap_{digest}"

    name = _truncate_utf8(name, 90)  # ~30 Chinese characters
    if not name:
        name = "markmap"

    candidate = outdir / f"{name}.html"
    if not candidate.exists():
        return candidate

    for i in range(2, 10000):
        suffix = f"_{i}"
        base = _truncate_utf8(name, 180 - len(suffix))
        candidate = outdir / f"{base}{suffix}.html"
        if not candidate.exists():
            return candidate

    digest = hashlib.sha256(raw.encode("utf-8", "ignore")).hexdigest()[:12]
    return outdir / f"markmap_{digest}.html"


def extract_title(file: Path) -> str:
    """Pull a title from the markdown: first ``# H1``, else YAML ``title:``."""
    text = file.read_text(encoding="utf-8")

    title = ""
    m = re.search(r"^#\s+(.+)$", text, flags=re.MULTILINE)
    if m:
        title = m.group(1).strip()

    if not title:
        lines = text.splitlines()
        if lines and lines[0].strip() == "---":
            for i in range(1, len(lines)):
                if lines[i].strip() == "---":
                    break
                tm = re.match(r"^title:\s*(.+)$", lines[i])
                if tm:
                    title = tm.group(1).strip()
                    break

    if not title:
        title = "markmap_" + datetime.now().strftime("%Y%m%d_%H%M%S")

    title = re.sub(r'[\\/:*?"<>|]', "_", title).rstrip()
    return title


def md_to_html_path(p: Path) -> Path:
    """Strip a trailing ``.md`` and append ``.html`` (matches bash ``${f%.md}.html``)."""
    s = str(p)
    if s.endswith(".md"):
        return Path(s[:-3] + ".html")
    return Path(s + ".html")


# ─────────────────────────────────────────────────────────────────────
# Frontmatter parsing
# ─────────────────────────────────────────────────────────────────────
def _find_frontmatter(lines: List[str]) -> Optional[Tuple[int, int]]:
    """Return ``(start, end)`` for ``lines[start] == lines[end] == '---'`` or None."""
    if not lines or lines[0].strip() != "---":
        return None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return 0, i
    return None


def _find_markmap_section(
    lines: List[str], fm_start: int, fm_end: int
) -> Optional[Tuple[int, int]]:
    """Find the ``markmap:`` block inside frontmatter ``[fm_start, fm_end]``.

    Returns ``(section_start, section_end)`` where ``section_start`` is the
    line containing ``markmap:`` and ``section_end`` is the line *after* the
    last property of the block (exclusive).
    """
    markmap_index: Optional[int] = None
    for i in range(fm_start + 1, fm_end):
        if re.match(r"^markmap\s*:\s*(?:#.*)?$", lines[i]):
            markmap_index = i
            break
    if markmap_index is None:
        return None

    section_end = fm_end
    for j in range(markmap_index + 1, fm_end):
        line = lines[j]
        if line.strip() == "":
            continue
        # New top-level YAML key (no leading indent) terminates the block.
        if re.match(r"^[A-Za-z0-9_-]+\s*:", line):
            section_end = j
            break

    return markmap_index, section_end


def has_color_freeze_level(file: Path) -> bool:
    """True iff ``markmap.colorFreezeLevel`` is explicitly set in frontmatter.

    This is the corrected check: the original bash version asked
    ``has_pre_header`` (does a ``markmap:`` block exist?), which falsely
    suppressed the prompt for inputs that had ``markmap:`` but no
    ``colorFreezeLevel``.
    """
    text = file.read_text(encoding="utf-8")
    lines = text.splitlines(True)

    fm = _find_frontmatter(lines)
    if fm is None:
        return False

    sec = _find_markmap_section(lines, *fm)
    if sec is None:
        return False

    section_start, section_end = sec
    for j in range(section_start + 1, section_end):
        if re.match(r"^\s*colorFreezeLevel\s*:", lines[j]):
            return True
    return False


def ensure_markmap_options(file: Path, cfl: str = "") -> None:
    """Ensure ``markmap.initialExpandLevel: 2`` and (optionally) ``colorFreezeLevel``.

    - If no frontmatter: prepend a fresh ``markmap:`` block.
    - If frontmatter without a ``markmap:`` key: insert one before closing ``---``.
    - If ``markmap:`` block exists: update or insert the two keys in place.

    ``cfl`` is only written when truthy. ``initialExpandLevel`` is *always* set.
    """
    text = file.read_text(encoding="utf-8")
    lines = text.splitlines(True)

    fm = _find_frontmatter(lines)

    # Case 1: no frontmatter at all.
    if fm is None:
        block = ["---\n", "markmap:\n"]
        if cfl:
            block.append(f"  colorFreezeLevel: {cfl}\n")
        block += ["  initialExpandLevel: 2\n", "---\n"]
        lines = block + lines
        file.write_text("".join(lines), encoding="utf-8")
        return

    fm_start, fm_end = fm
    sec = _find_markmap_section(lines, fm_start, fm_end)

    # Case 2: frontmatter exists but has no markmap: block.
    if sec is None:
        insert: List[str] = ["markmap:\n"]
        if cfl:
            insert.append(f"  colorFreezeLevel: {cfl}\n")
        insert.append("  initialExpandLevel: 2\n")
        lines = lines[:fm_end] + insert + lines[fm_end:]
        file.write_text("".join(lines), encoding="utf-8")
        return

    # Case 3: markmap: block already exists — patch it.
    section_start, section_end = sec

    # ── initialExpandLevel: always force to 2 ──
    iel_idx: Optional[int] = None
    for j in range(section_start + 1, section_end):
        if re.match(r"^\s*initialExpandLevel\s*:", lines[j]):
            iel_idx = j
            break

    if iel_idx is not None:
        lines[iel_idx] = (
            re.sub(
                r"^(\s*initialExpandLevel\s*:).*$",
                r"\1 2",
                lines[iel_idx].rstrip("\r\n"),
            )
            + "\n"
        )
    else:
        lines.insert(section_start + 1, "  initialExpandLevel: 2\n")
        section_end += 1

    # ── colorFreezeLevel: only patch when caller supplied a value ──
    if cfl:
        cfl_idx: Optional[int] = None
        for j in range(section_start + 1, section_end):
            if re.match(r"^\s*colorFreezeLevel\s*:", lines[j]):
                cfl_idx = j
                break

        if cfl_idx is not None:
            lines[cfl_idx] = (
                re.sub(
                    r"^(\s*colorFreezeLevel\s*:).*$",
                    rf"\1 {cfl}",
                    lines[cfl_idx].rstrip("\r\n"),
                )
                + "\n"
            )
        else:
            lines.insert(section_start + 1, f"  colorFreezeLevel: {cfl}\n")

    file.write_text("".join(lines), encoding="utf-8")


# ─────────────────────────────────────────────────────────────────────
# HTML / markmap CLI
# ─────────────────────────────────────────────────────────────────────
def append_new_code_to_html(html_path: Path) -> None:
    """Inject ``NEW_CODE`` immediately before ``</body>``.

    No-op if ``NEW_CODE`` is empty or whitespace, so you can leave the slot
    blank and the script still produces a working (un-augmented) HTML.
    """
    if not NEW_CODE.strip():
        return

    html = html_path.read_text(encoding="utf-8")
    marker = "</body>"
    if marker not in html:
        raise SystemExit(f"[!] </body> not found in {html_path}")

    html = html.replace(marker, NEW_CODE + "\n" + marker, 1)
    html_path.write_text(html, encoding="utf-8")


def render_markmap(md_file: Path, out_file: Path) -> None:
    """Run the ``markmap`` npm CLI."""
    subprocess.run(
        ["markmap", str(md_file), "-o", str(out_file), "--no-open"],
        check=True,
    )


# ─────────────────────────────────────────────────────────────────────
# Interactive helpers — read from /dev/tty so prompts still work after
# ``sys.stdin.read()`` consumed the markdown body.
# ─────────────────────────────────────────────────────────────────────
def _open_tty() -> Optional[TextIO]:
    try:
        return open("/dev/tty", "r")
    except OSError:
        return None


def read_with_timeout(
    prompt: str,
    timeout: float,
    default: str,
    tty: Optional[TextIO] = None,
) -> str:
    """Read one line within ``timeout`` seconds; return ``default`` otherwise."""
    sys.stdout.write(prompt)
    sys.stdout.flush()

    fd = tty if tty is not None else _open_tty()
    own_fd = (tty is None) and (fd is not None)

    if fd is None:
        sys.stdout.write("\n")
        sys.stdout.flush()
        return default

    try:
        rlist, _, _ = select.select([fd], [], [], timeout)
        if not rlist:
            sys.stdout.write("\n")
            sys.stdout.flush()
            return default

        line = fd.readline().rstrip("\n")
        value = line.strip()
        return value if value else default
    finally:
        if own_fd:
            fd.close()


def read_lines_until_blank(tty: Optional[TextIO]) -> List[str]:
    """Read non-empty lines until EOF or a blank line."""
    src: TextIO = tty if tty is not None else sys.stdin
    out: List[str] = []
    while True:
        try:
            line = src.readline()
        except KeyboardInterrupt:
            break
        if not line:  # EOF
            break
        line = line.rstrip("\n")
        if not line.strip():
            break
        out.append(line)
    return out


# ─────────────────────────────────────────────────────────────────────
# Per-file pipeline
# ─────────────────────────────────────────────────────────────────────
def process_file(
    md_file: Path,
    outfile: Path,
    tty: Optional[TextIO],
    prompt_label: str,
) -> None:
    """Patch frontmatter, render markmap, inject NEW_CODE, print success line."""
    if has_color_freeze_level(md_file):
        # User already pinned colorFreezeLevel — respect it.
        ensure_markmap_options(md_file)
    else:
        cfl = read_with_timeout(
            f"colorFreezeLevel {prompt_label}[3] (2s timeout): ",
            2.0,
            "3",
            tty=tty,
        )
        ensure_markmap_options(md_file, cfl)

    render_markmap(md_file, outfile)
    append_new_code_to_html(outfile)
    print(f"[\u2713] {md_file} \u2192 {BR}{outfile}{RS}")


# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────
def main() -> int:
    ensure_markmap_cli()

    print("=== Markmap Renderer ===")
    print("Type/paste your markdown below. Press Ctrl-D when done.")
    print("(Leave empty — or type only n / N / 呢 / 你 / 能 — to switch to file mode)")
    print("---")

    raw = sys.stdin.read()
    print()

    trimmed = re.sub(r"\s+", "", raw)
    file_mode = trimmed in FILLER_TOKENS

    tty = _open_tty()

    try:
        if file_mode:
            print("→ No content detected. Switching to file mode.")
            print("Enter .md file paths, one per line.")
            print("Press Ctrl-D or empty line to finish.")
            print("  files ↓")

            files: List[Path] = []
            for line in read_lines_until_blank(tty):
                p = Path(line).expanduser()
                if not p.is_file():
                    print(f"  ⚠  File not found: {line} (skipped)")
                    continue
                files.append(p.resolve())

            if not files:
                print("No valid files provided. Exiting.")
                return 1

            for f in files:
                outfile = md_to_html_path(f)
                process_file(f, outfile, tty, prompt_label=f"for {f.name} ")
            return 0

        # ── Content mode ──
        tmp = tempfile.NamedTemporaryFile(
            mode="w",
            prefix="markmap_input_",
            suffix=".md",
            delete=False,
            encoding="utf-8",
        )
        tmp_path = Path(tmp.name)
        try:
            tmp.write(raw)
            tmp.flush()
            tmp.close()

            # We need the title before deciding the output path, but the
            # title can come from a body line (# H1) that exists regardless
            # of frontmatter mutation, so order doesn't matter much. Patch
            # frontmatter first to keep the file canonical, then extract.
            if has_color_freeze_level(tmp_path):
                ensure_markmap_options(tmp_path)
            else:
                cfl = read_with_timeout(
                    "colorFreezeLevel [3] (2s timeout): ",
                    2.0,
                    "3",
                    tty=tty,
                )
                ensure_markmap_options(tmp_path, cfl)

            title = extract_title(tmp_path)
            outfile = make_outfile_path(title)

            render_markmap(tmp_path, outfile)
            append_new_code_to_html(outfile)
            print(f"[\u2713] Rendered \u2192 {BR}{outfile}{RS}")
        finally:
            try:
                tmp_path.unlink()
            except OSError:
                pass

        return 0
    finally:
        if tty is not None:
            tty.close()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.stderr.write("\nAborted.\n")
        sys.exit(130)
