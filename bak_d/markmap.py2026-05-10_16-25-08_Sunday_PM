#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path
import html as html_lib

try:
    import select
except ImportError:  # Windows fallback
    select = None


BR = "\033[1;31m"
RS = "\033[0m"

# MARKMAP_FAVICON_URL = "https://markmap.js.org/favicon.png"
MARKMAP_FAVICON_URL = (
    "https://raw.githubusercontent.com/HelloWorldWinning/vps/main/icon/markmap_z7a.png"
)


DEFAULT_MAX_WIDTH = "380"
DEFAULT_COLOR_FREEZE_LEVEL = "3"
INITIAL_EXPAND_LEVEL = "2"

FILLER_INPUTS = {"", "n", "N", "呢", "你", "能"}


# Paste your generated/custom <script>...</script> here.
# Intentionally empty per request.
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


def replace_html_title(html_path: Path, title: str) -> None:
    safe_title = html_lib.escape((title or "markmap").strip() or "markmap", quote=False)

    html_text = read_text(html_path)

    html_text, count = re.subn(
        r"<title>.*?</title>",
        lambda _: f"<title>{safe_title}</title>",
        html_text,
        count=1,
        flags=re.IGNORECASE | re.DOTALL,
    )

    if count == 0:
        raise SystemExit(f"[!] <title>...</title> not found in {html_path}")

    write_text(html_path, html_text)


# ─────────────────────────────────────────────────────────────
# Dependency checks
# ─────────────────────────────────────────────────────────────


def command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def ensure_markmap_cli() -> None:
    if command_exists("markmap"):
        return

    print("[*] markmap not found. Installing markmap-cli globally...")

    if not command_exists("npm"):
        raise SystemExit("[!] npm is required to install markmap-cli.")

    subprocess.run(
        ["npm", "install", "-g", "markmap-cli"],
        check=True,
    )


# ─────────────────────────────────────────────────────────────
# Filename handling
# ─────────────────────────────────────────────────────────────


def ensure_html_favicon(
    html_path: Path,
    favicon_url: str = MARKMAP_FAVICON_URL,
) -> None:
    html = read_text(html_path)

    safe_url = html_lib.escape(favicon_url, quote=True)
    favicon_link = f'<link rel="icon" href="{safe_url}">'

    link_tag_pattern = re.compile(
        r"<link\b[^>]*>",
        flags=re.IGNORECASE | re.DOTALL,
    )

    def is_icon_link(tag: str) -> bool:
        return (
            re.search(
                r'\brel\s*=\s*["\'][^"\']*(?:shortcut\s+icon|icon)[^"\']*["\']',
                tag,
                flags=re.IGNORECASE,
            )
            is not None
        )

    link_tags = list(link_tag_pattern.finditer(html))
    icon_tags = [match for match in link_tags if is_icon_link(match.group(0))]

    if icon_tags:
        first = icon_tags[0]
        html = html[: first.start()] + favicon_link + html[first.end() :]

        # Remove duplicate favicon links after replacing the first one.
        html = link_tag_pattern.sub(
            lambda match: "" if is_icon_link(match.group(0)) else match.group(0),
            html,
            count=len(icon_tags) - 1,
        )

        write_text(html_path, html)
        return

    if re.search(r"<head\b[^>]*>", html, flags=re.IGNORECASE):
        html = re.sub(
            r"(<head\b[^>]*>)",
            rf"\1\n{favicon_link}",
            html,
            count=1,
            flags=re.IGNORECASE,
        )
        write_text(html_path, html)
        return

    raise SystemExit(f"[!] <head> not found in {html_path}")


def truncate_utf8(value: str, max_bytes: int) -> str:
    encoded = value.encode("utf-8")

    if len(encoded) <= max_bytes:
        return value

    return encoded[:max_bytes].decode("utf-8", "ignore").rstrip("._- ")


def make_outfile_path(title: str, outdir: Path | None = None) -> Path:
    outdir = (outdir or Path.cwd()).expanduser().resolve()
    raw = title or ""

    name = unicodedata.normalize("NFKC", raw)

    bad_chars = '/\\:*?"<>|'

    name = "".join(
        "_" if ch in bad_chars or ord(ch) < 32 or ord(ch) == 127 else ch for ch in name
    )

    name = re.sub(r"\s+", "_", name, flags=re.UNICODE)

    name = "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in name)

    name = re.sub(r"_+", "_", name).strip("._- ")

    if not name or name in {".", ".."}:
        digest = hashlib.sha256(raw.encode("utf-8", "ignore")).hexdigest()[:8]
        name = f"markmap_{digest}"

    name = truncate_utf8(name, 90)

    if not name:
        name = "markmap"

    candidate = outdir / f"{name}.html"

    if not candidate.exists():
        return candidate

    for i in range(2, 10000):
        suffix = f"_{i}"
        base = truncate_utf8(name, 90 - len(suffix))
        candidate = outdir / f"{base}{suffix}.html"

        if not candidate.exists():
            return candidate

    digest = hashlib.sha256(raw.encode("utf-8", "ignore")).hexdigest()[:12]
    return outdir / f"markmap_{digest}.html"


# ─────────────────────────────────────────────────────────────
# Markdown / frontmatter helpers
# ─────────────────────────────────────────────────────────────


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def find_frontmatter(lines: list[str]) -> tuple[int, int] | None:
    if not lines or lines[0].strip() != "---":
        return None

    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return 0, i

    return None


def find_markmap_section(
    lines: list[str],
    frontmatter: tuple[int, int],
) -> tuple[int, int, str] | None:
    start, end = frontmatter

    for i in range(start + 1, end):
        line = lines[i].rstrip("\r\n")

        match = re.match(r"^markmap\s*:\s*(.*?)\s*(?:#.*)?$", line)

        if not match:
            continue

        inline_value = match.group(1).strip()
        section_end = end

        for j in range(i + 1, end):
            candidate = lines[j]

            if candidate.strip() == "" or candidate.lstrip().startswith("#"):
                continue

            is_top_level = not candidate.startswith((" ", "\t"))
            is_key = re.match(r"^[A-Za-z0-9_-]+\s*:", candidate) is not None

            if is_top_level and is_key:
                section_end = j
                break

        return i, section_end, inline_value

    return None


def strip_surrounding_quotes(value: str) -> str:
    value = value.strip()

    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]

    return value


def extract_title(path: Path) -> str:
    text = read_text(path)

    for line in text.splitlines():
        match = re.match(r"^#\s+(.+?)\s*$", line)

        if match:
            title = match.group(1).strip()

            if title:
                return title

    lines = text.splitlines(True)
    frontmatter = find_frontmatter(lines)

    if frontmatter:
        start, end = frontmatter

        for line in lines[start + 1 : end]:
            match = re.match(r"^title\s*:\s*(.*?)\s*(?:#.*)?$", line.rstrip("\r\n"))

            if match:
                title = strip_surrounding_quotes(match.group(1))

                if title:
                    return title

    return "markmap"


def yaml_section_has_key(
    lines: list[str],
    section_start: int,
    section_end: int,
    key: str,
    inline_value: str = "",
) -> bool:
    if inline_value:
        inline_pattern = rf"(?:^|[{{,\s]){re.escape(key)}\s*:"

        if re.search(inline_pattern, inline_value):
            return True

    pattern = re.compile(rf"^\s*{re.escape(key)}\s*:")

    for i in range(section_start + 1, section_end):
        if pattern.match(lines[i]):
            return True

    return False


def detect_child_indent(
    lines: list[str],
    section_start: int,
    section_end: int,
) -> str:
    for i in range(section_start + 1, section_end):
        line = lines[i]

        if not line.strip() or line.lstrip().startswith("#"):
            continue

        match = re.match(r"^(\s+)[A-Za-z0-9_-]+\s*:", line)

        if match:
            return match.group(1)

    return "  "


def normalize_inline_markmap_if_possible(
    lines: list[str],
    section_start: int,
    inline_value: str,
) -> bool:
    raw = inline_value.strip()

    if not raw:
        return False

    if raw == "{}":
        lines[section_start] = "markmap:\n"
        return True

    if not (raw.startswith("{") and raw.endswith("}")):
        return False

    inner = raw[1:-1].strip()
    entries: list[str] = []

    if inner:
        for part in inner.split(","):
            part = part.strip()

            if not part or ":" not in part:
                continue

            key, value = part.split(":", 1)
            key = key.strip()
            value = value.strip()

            if key:
                entries.append(f"  {key}: {value}\n")

    lines[section_start] = "markmap:\n"
    lines[section_start + 1 : section_start + 1] = entries

    return True


def has_markmap_color_freeze_level(path: Path) -> bool:
    text = read_text(path)
    lines = text.splitlines(True)

    frontmatter = find_frontmatter(lines)

    if not frontmatter:
        return False

    section = find_markmap_section(lines, frontmatter)

    if not section:
        return False

    section_start, section_end, inline_value = section

    return yaml_section_has_key(
        lines,
        section_start,
        section_end,
        "colorFreezeLevel",
        inline_value,
    )


def sanitize_max_width(value: str | None) -> str:
    value = (value or "").strip()

    if not value:
        return DEFAULT_MAX_WIDTH

    if not re.fullmatch(r"\d+", value):
        print(f"[!] Invalid maxWidth {value!r}; using {DEFAULT_MAX_WIDTH}.")
        return DEFAULT_MAX_WIDTH

    return str(int(value))


def sanitize_color_freeze_level(value: str | None) -> str:
    value = (value or "").strip()

    if not value:
        return DEFAULT_COLOR_FREEZE_LEVEL

    if not re.fullmatch(r"\d+", value):
        print(
            f"[!] Invalid colorFreezeLevel {value!r}; "
            f"using {DEFAULT_COLOR_FREEZE_LEVEL}."
        )
        return DEFAULT_COLOR_FREEZE_LEVEL

    return str(int(value))


def ensure_markmap_options(
    path: Path,
    color_freeze_level: str | None = None,
    initial_expand_level: str = INITIAL_EXPAND_LEVEL,
    max_width: str | None = DEFAULT_MAX_WIDTH,
) -> None:
    text = read_text(path)
    lines = text.splitlines(True)

    frontmatter = find_frontmatter(lines)

    if frontmatter is None:
        block = [
            "---\n",
            "markmap:\n",
        ]

        if color_freeze_level is not None:
            block.append(
                f"  colorFreezeLevel: {sanitize_color_freeze_level(color_freeze_level)}\n"
            )

        if max_width is not None:
            block.append(f"  maxWidth: {sanitize_max_width(max_width)}\n")

        block.extend(
            [
                f"  initialExpandLevel: {initial_expand_level}\n",
                "---\n",
            ]
        )

        write_text(path, "".join(block + lines))
        return

    start, end = frontmatter
    section = find_markmap_section(lines, frontmatter)

    if section is None:
        insert = ["markmap:\n"]

        if color_freeze_level is not None:
            insert.append(
                f"  colorFreezeLevel: {sanitize_color_freeze_level(color_freeze_level)}\n"
            )

        if max_width is not None:
            insert.append(f"  maxWidth: {sanitize_max_width(max_width)}\n")

        insert.append(f"  initialExpandLevel: {initial_expand_level}\n")

        lines = lines[:end] + insert + lines[end:]
        write_text(path, "".join(lines))
        return

    section_start, section_end, inline_value = section

    if normalize_inline_markmap_if_possible(lines, section_start, inline_value):
        frontmatter = find_frontmatter(lines)

        if frontmatter is None:
            raise SystemExit(
                "[!] Failed to re-read frontmatter after normalizing inline markmap config."
            )

        section = find_markmap_section(lines, frontmatter)

        if section is None:
            raise SystemExit(
                "[!] Failed to re-read markmap section after normalizing inline config."
            )

        section_start, section_end, inline_value = section

    indent = detect_child_indent(lines, section_start, section_end)

    has_color_freeze_level = yaml_section_has_key(
        lines,
        section_start,
        section_end,
        "colorFreezeLevel",
        inline_value,
    )

    has_max_width = yaml_section_has_key(
        lines,
        section_start,
        section_end,
        "maxWidth",
        inline_value,
    )

    has_initial_expand_level = False

    for i in range(section_start + 1, section_end):
        if re.match(r"^\s*initialExpandLevel\s*:", lines[i]):
            lines[i] = (
                re.sub(
                    r"^(\s*initialExpandLevel\s*:).*$",
                    rf"\1 {initial_expand_level}",
                    lines[i].rstrip("\r\n"),
                )
                + "\n"
            )
            has_initial_expand_level = True
            break

    insertions: list[str] = []

    if color_freeze_level is not None and not has_color_freeze_level:
        insertions.append(
            f"{indent}colorFreezeLevel: {sanitize_color_freeze_level(color_freeze_level)}\n"
        )

    if max_width is not None and not has_max_width:
        insertions.append(f"{indent}maxWidth: {sanitize_max_width(max_width)}\n")

    if not has_initial_expand_level:
        insertions.append(f"{indent}initialExpandLevel: {initial_expand_level}\n")

    if insertions:
        lines = lines[: section_start + 1] + insertions + lines[section_start + 1 :]

    write_text(path, "".join(lines))


# ─────────────────────────────────────────────────────────────
# Interactive input helpers
# ─────────────────────────────────────────────────────────────


def open_tty():
    if os.name == "posix" and Path("/dev/tty").exists():
        reader = open("/dev/tty", "r", encoding="utf-8", errors="replace")
        writer = open("/dev/tty", "w", encoding="utf-8", errors="replace")
        return reader, writer, True

    return sys.stdin, sys.stdout, False


def prompt_with_timeout(
    prompt: str,
    default: str,
    timeout_seconds: int = 2,
) -> str:
    reader, writer, should_close = open_tty()

    try:
        writer.write(prompt)
        writer.flush()

        if select is not None and hasattr(reader, "fileno") and reader.isatty():
            ready, _, _ = select.select([reader], [], [], timeout_seconds)

            if not ready:
                writer.write("\n")
                writer.flush()
                return default

        line = reader.readline()

        if line == "":
            return default

        value = line.rstrip("\n").strip()

        return value if value else default

    finally:
        if should_close:
            reader.close()
            writer.close()


def read_file_paths_interactive() -> list[Path]:
    reader, writer, should_close = open_tty()

    paths: list[Path] = []

    try:
        writer.write("→ No content detected. Switching to file mode.\n")
        writer.write("Enter .md file paths, one per line.\n")
        writer.write("Press Ctrl-D or empty line to finish.\n")
        writer.write("  files ↓\n")
        writer.flush()

        while True:
            line = reader.readline()

            if line == "":
                break

            raw = line.strip()

            if not raw:
                break

            path = Path(raw).expanduser()

            if not path.is_file():
                writer.write(f"  ⚠  File not found: {raw} (skipped)\n")
                writer.flush()
                continue

            paths.append(path.resolve())

    finally:
        if should_close:
            reader.close()
            writer.close()

    return paths


# ─────────────────────────────────────────────────────────────
# HTML patching
# ─────────────────────────────────────────────────────────────


def append_new_code_to_html(html_path: Path) -> None:
    code = NEW_CODE

    if not code.strip():
        return

    html = read_text(html_path)
    marker = "</body>"

    if marker not in html:
        raise SystemExit(f"[!] </body> not found in {html_path}")

    html = html.replace(marker, code + "\n" + marker, 1)
    write_text(html_path, html)


# ─────────────────────────────────────────────────────────────
# Rendering
# ─────────────────────────────────────────────────────────────


def run_markmap(markdown_path: Path, outfile: Path) -> None:
    subprocess.run(
        [
            "markmap",
            str(markdown_path),
            "-o",
            str(outfile),
            "--no-open",
        ],
        check=True,
    )


def render_markdown_file(markdown_path: Path) -> None:
    markdown_path = markdown_path.expanduser().resolve()

    if not markdown_path.is_file():
        print(f"  ⚠  File not found: {markdown_path} (skipped)")
        return

    color_freeze_level = None

    if not has_markmap_color_freeze_level(markdown_path):
        color_freeze_level = DEFAULT_COLOR_FREEZE_LEVEL

    ensure_markmap_options(
        markdown_path,
        color_freeze_level=color_freeze_level,
    )

    if markdown_path.suffix.lower() == ".md":
        outfile = markdown_path.with_suffix(".html")
    else:
        outfile = Path(str(markdown_path) + ".html")

    #   run_markmap(markdown_path, outfile)
    #   append_new_code_to_html(outfile)
    title = extract_title(markdown_path)

    run_markmap(markdown_path, outfile)

    ensure_html_favicon(outfile)
    replace_html_title(outfile, title)

    append_new_code_to_html(outfile)

    print(f"[✓] {markdown_path} → {BR}{outfile}{RS}")


def render_markdown_content(markdown_text: str) -> None:
    tmp_path: Path | None = None

    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            suffix=".md",
            prefix="markmap_input_",
            delete=False,
            encoding="utf-8",
        ) as tmp:
            tmp.write(markdown_text)
            tmp_path = Path(tmp.name)

        color_freeze_level = None

        if not has_markmap_color_freeze_level(tmp_path):
            value = prompt_with_timeout(
                f"colorFreezeLevel [{DEFAULT_COLOR_FREEZE_LEVEL}] (2s timeout): ",
                default=DEFAULT_COLOR_FREEZE_LEVEL,
                timeout_seconds=2,
            )
            color_freeze_level = sanitize_color_freeze_level(value)

        ensure_markmap_options(
            tmp_path,
            color_freeze_level=color_freeze_level,
        )

        title = extract_title(tmp_path)
        outfile = make_outfile_path(title)

        run_markmap(tmp_path, outfile)
        ensure_html_favicon(outfile)
        replace_html_title(outfile, title)
        append_new_code_to_html(outfile)

        print(f"[✓] Rendered → {BR}{outfile}{RS}")

    finally:
        if tmp_path is not None:
            try:
                tmp_path.unlink()
            except FileNotFoundError:
                pass


# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────


def is_empty_or_filler(markdown_text: str) -> bool:
    trimmed = "".join(markdown_text.split())
    return trimmed in FILLER_INPUTS


def main() -> None:
    ensure_markmap_cli()

    if len(sys.argv) > 1:
        for raw in sys.argv[1:]:
            render_markdown_file(Path(raw))
        return

    print("=== Markmap Renderer ===")
    print("Type/paste your markdown below. Press Ctrl-D when done.")
    print("(Leave empty — or type only n / N / 呢 / 你 / 能 — to switch to file mode)")
    print("---")

    markdown_text = sys.stdin.read()
    print("")

    if is_empty_or_filler(markdown_text):
        files = read_file_paths_interactive()

        if not files:
            raise SystemExit("No valid files provided. Exiting.")

        for markdown_path in files:
            render_markdown_file(markdown_path)

        return

    render_markdown_content(markdown_text)


if __name__ == "__main__":
    main()
