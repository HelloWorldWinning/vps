#!/usr/bin/env python3
"""
mermaid.py — Convert Mermaid code → standalone HTML with custom CSS.

Usage:
    python mermaid.py

  Content mode : paste mermaid code, press Ctrl-D
  File mode    : press Ctrl-D on empty input (or type n/N/呢/你/能),
                 then enter file paths one per line
"""

import sys
import os
import re

# ═══════════════════════════════════════════════════════════════
#  ✏️  CUSTOM CSS — edit / append freely.
#     Everything here is injected into every generated HTML.
# ═══════════════════════════════════════════════════════════════
CUSTOM_CSS = r"""
html * {
    font-family: "SF Pro", -apple-system, BlinkMacSystemFont,
                 "PingFang SC", "FZFangJunHeiS", sans-serif !important;
}
""".strip()


# ═══════════════════════════════════════════════════════════════
#  HTML skeleton — uses __PLACEHOLDERS__ so mermaid braces stay
#  intact (no .format() escaping headaches).
# ═══════════════════════════════════════════════════════════════
_HTML = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">

<link rel="icon" type="image/svg+xml" href="https://mermaid.js.org/favicon.svg">

<title>__TITLE__</title>
<style>
__CSS__
</style>
</head>
<body>
<pre class="mermaid">
__MERMAID__
</pre>
<script type="module">
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@latest/dist/mermaid.esm.min.mjs';
mermaid.initialize({ startOnLoad: true });
</script>
</body>
</html>
"""

# Words that are mermaid keywords, not meaningful node names
_KEYWORDS = frozenset(
    "style class click subgraph end direction classDef linkStyle "
    "note loop alt else opt par rect activate deactivate".split()
)

# Friendly aliases for diagram-type identifiers
_TYPE_ALIAS = {
    "sequenceDiagram": "sequence",
    "classDiagram": "class_diagram",
    "classDiagram-v2": "class_diagram",
    "stateDiagram": "state_diagram",
    "stateDiagram-v2": "state_diagram",
    "erDiagram": "er_diagram",
    "gantt": "gantt",
    "pie": "pie_chart",
    "journey": "journey",
    "gitgraph": "gitgraph",
    "mindmap": "mindmap",
    "timeline": "timeline",
    "quadrantChart": "quadrant",
    "requirementDiagram": "requirements",
    "C4Context": "c4_context",
    "sankey-beta": "sankey",
    "xychart-beta": "xychart",
    "block-beta": "block",
    "zenuml": "zenuml",
    "packet-beta": "packet",
}


# ───────────────────── helpers ─────────────────────────────────


def _strip_frontmatter(lines):
    """
    Consume an optional YAML front-matter block delimited by '---' lines.

    Rules
    -----
    * If the very first non-empty line is '---', we are inside front-matter.
    * We scan forward for a closing '---'.  The first 'title: ...' we find
      becomes the canonical title for the diagram.
    * If the closing '---' is never found (malformed block), we return the
      original lines unchanged so the rest of extract_name can still run.
    * Quoting around the title value is stripped (' and " both).

    Returns
    -------
    (title_or_None, remaining_lines)
        title_or_None : str | None
        remaining_lines : list[str]  — everything after the closing '---'
    """
    if not lines or lines[0].strip() != "---":
        return None, lines

    title = None
    for i, ln in enumerate(lines[1:], 1):
        if ln.strip() == "---":
            # Found closing fence — return everything after it
            return title, lines[i + 1 :]
        m = re.match(r"\s*title\s*:\s*(.+)", ln)
        if m:
            title = m.group(1).strip().strip("\"'")

    # Unclosed front-matter — treat whole content as body
    return None, lines


def _is_directive_line(ln):
    """Return True for lines that carry no node content."""
    s = ln.strip()
    return (
        not s  # blank
        or s.startswith("%%")  # mermaid comment
        or re.match(
            r"(classDef|class|linkStyle|style" r"|click|direction)\b", s
        )  # style/meta directives
    )


def _first_node_label(lines):
    """Return the label of the first real node in a graph / flowchart."""
    for ln in lines:
        if _is_directive_line(ln):
            continue

        # ── quoted label, possibly multi-line via \n ──────────────────────
        # Matches: ID["..."]  ID("...")  ID{"..."}  ID[/"..."/]
        # We want the LAST segment after a literal \n inside the quotes,
        # e.g. `"x : [B, N, T, F]\nHistorical stock features"` → last segment
        m = re.search(r'(\w+)\s*[\[\(\{/]+\s*"([^"]+)"', ln)
        if m and m.group(1) not in _KEYWORDS:
            raw = m.group(2)
            # split on escaped newline sequences and take the last non-empty part
            parts = [p.strip() for p in re.split(r"\\n|\n", raw) if p.strip()]
            if parts:
                return parts[-1]

        # ── unquoted: ID[label] ───────────────────────────────────────────
        m = re.search(r"(\w+)\s*\[([^\]]+)\]", ln)
        if m and m.group(1) not in _KEYWORDS:
            return m.group(2).strip()

        # ── rounded: ID(label)  — skip (( double-paren circles ───────────
        m = re.search(r"(\w+)\s*\(([^()]+)\)", ln)
        if m and m.group(1) not in _KEYWORDS:
            return m.group(2).strip()

        # ── diamond: ID{label} ───────────────────────────────────────────
        m = re.search(r"(\w+)\s*\{([^{}]+)\}", ln)
        if m and m.group(1) not in _KEYWORDS:
            return m.group(2).strip()

        # ── bare indented node ID ─────────────────────────────────────────
        m = re.match(r"\s+(\w+)\s*$", ln)
        if m and m.group(1) not in _KEYWORDS:
            return m.group(1)

    return None


def _mindmap_root(lines):
    """Return root text from a mindmap body."""
    for ln in lines:
        s = ln.strip()
        if not s:
            continue
        # strip shape wrappers: ((text)), [text], (text), etc.
        s = re.sub(r"^[\[\(\{]+|[\]\)\}]+$", "", s).strip()
        s = re.sub(r'^"(.*)"$', r"\1", s)
        if s:
            return s
    return None


def extract_name(code):
    """Pick a short human-readable name from mermaid source."""
    lines = [l for l in code.strip().splitlines()]

    # ── 1. YAML frontmatter title ──
    fm_title, body = _strip_frontmatter(lines)
    if fm_title:
        return fm_title

    # ── 2. title directive (gantt, pie, journey …) ──
    for ln in body:
        s = ln.strip()
        m = re.match(r"title\s+(.+)", s, re.IGNORECASE)
        if m and not re.match(r"title\s*:", s, re.IGNORECASE):
            return m.group(1).strip()

    # non-empty body lines
    body = [l for l in body if l.strip()]
    if not body:
        return "mermaid"
    first = body[0].strip()

    # ── 3. graph / flowchart → first node label ──
    if re.match(r"(graph|flowchart)\s", first, re.IGNORECASE):
        label = _first_node_label(body[1:])
        if label:
            return label

    # ── 4. mindmap → root label ──
    if first.lower().startswith("mindmap"):
        root = _mindmap_root(body[1:])
        if root:
            return root

    # ── 5. fall back to diagram-type keyword ──
    m = re.match(r"([\w-]+)", first)
    if m:
        return _TYPE_ALIAS.get(m.group(1), m.group(1))

    return "mermaid"


def sanitize(name, maxlen=48):
    """Turn an arbitrary string into a safe Linux filename (no extension)."""
    name = name.strip()
    name = re.sub(r"[\s/\\:*?\"<>|&;!@#$%^()+=,\[\]{}]+", "_", name)
    # keep word chars, CJK, hyphen
    name = re.sub(r"[^\w\u4e00-\u9fff\u3400-\u4dbf\-]", "", name)
    name = re.sub(r"[_\-]{2,}", "_", name)
    name = name.strip("_-").lower()
    if len(name) > maxlen:
        name = name[:maxlen].rstrip("_-")
    return name or "mermaid"


def unique_path(base_name):
    """Return base_name.html, appending _1 _2 … to avoid overwrites."""
    path = f"{base_name}.html"
    if not os.path.exists(path):
        return path
    i = 1
    while os.path.exists(f"{base_name}_{i}.html"):
        i += 1
    return f"{base_name}_{i}.html"


def generate(mermaid_code):
    """Write one HTML file from mermaid source; return the path."""
    name = extract_name(mermaid_code)
    fname = unique_path(sanitize(name))
    html = (
        _HTML.replace("__TITLE__", name)
        .replace("__CSS__", CUSTOM_CSS)
        .replace("__MERMAID__", mermaid_code.strip())
    )
    with open(fname, "w", encoding="utf-8") as fh:
        fh.write(html)
    return fname


# ───────────────────── I/O modes ───────────────────────────────

_FILE_MODE_TRIGGERS = frozenset(("", "n", "N", "呢", "你", "能"))


def read_block():
    """Read from stdin until EOF (Ctrl-D). Returns stripped text."""
    parts = []
    try:
        for line in sys.stdin:
            parts.append(line.rstrip("\n"))
    except (EOFError, KeyboardInterrupt):
        pass
    return "\n".join(parts).strip()


def run_content_mode(code):
    """Process one pasted mermaid block."""
    path = generate(code)
    abs_path = os.path.abspath(path)
    print(f"✅  \033[1;31m{abs_path}\033[0m")


def run_file_mode():
    """Prompt for file paths from /dev/tty, generate one HTML each."""
    try:
        tty = open("/dev/tty", "r")
    except OSError:
        print("Error: cannot reopen terminal for file mode.", file=sys.stderr)
        sys.exit(1)

    print(
        "\n📂  File mode — enter file paths (one per line).\n"
        "    Empty line or Ctrl-D to finish.\n"
    )

    files = []
    try:
        while True:
            line = tty.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                break
            files.append(line)
    except (EOFError, KeyboardInterrupt):
        pass
    finally:
        tty.close()

    if not files:
        print("No files provided — nothing to do.")
        return

    for fpath in files:
        if not os.path.isfile(fpath):
            print(f"  ⚠️  not found: {fpath}")
            continue
        with open(fpath, "r", encoding="utf-8") as fh:
            code = fh.read().strip()
        if not code:
            print(f"  ⚠️  empty: {fpath}")
            continue
        path = generate(code)
        abs_path = os.path.abspath(path)
        print(f"✅  \033[1;31m{abs_path}\033[0m")


# ───────────────────── main ────────────────────────────────────


def main():
    print(
        "Type/paste your mermaid code below. Press Ctrl-D when done.\n"
        "(Leave empty — or type only  n / N / 呢 / 你 / 能  — to switch to file mode)\n"
    )

    content = read_block()

    if content in _FILE_MODE_TRIGGERS:
        run_file_mode()
    else:
        run_content_mode(content)


if __name__ == "__main__":
    main()
