#!/usr/bin/env bash
set -euo pipefail

# ── ANSI: bold + red ──
BR='\033[1;31m'
RS='\033[0m'

# ── ensure markmap-cli is installed ──
if ! command -v markmap &>/dev/null; then
	echo "[*] markmap not found. Installing markmap-cli globally..."
	npm install -g markmap-cli
fi
# ── ensure python3 is available ──
if ! command -v python3 &>/dev/null; then
	echo "[!] python3 is required for markdown/html patching."
	exit 1
fi

# ── build robust output filename from title ──
make_outfile_path() {
	local title="${1:-}"
	local outdir="${2:-$(pwd)}"

	python3 - "$outdir" "$title" <<'PY'
from pathlib import Path
import hashlib
import re
import sys
import unicodedata

outdir = Path(sys.argv[1]).expanduser().resolve()
raw = sys.argv[2] if len(sys.argv) > 2 else ""

# Normalize full-width chars and other Unicode compatibility forms.
name = unicodedata.normalize("NFKC", raw)

# Linux only forbids "/" and NUL, but these chars are bad for shell, URLs,
# Windows compatibility, and general filename robustness.
bad_chars = '/\\:*?"<>|'

name = "".join(
    "_" if ch in bad_chars or ord(ch) < 32 or ord(ch) == 127 else ch
    for ch in name
)

# Replace all whitespace: spaces, tabs, newlines, NBSP, etc.
name = re.sub(r"\s+", "_", name, flags=re.UNICODE)

# Keep Unicode letters/numbers plus safe punctuation.
# Everything else becomes "_".
name = "".join(
    ch if ch.isalnum() or ch in "._-" else "_"
    for ch in name
)

# Collapse repeated underscores and trim ugly edge chars.
name = re.sub(r"_+", "_", name).strip("._- ")

# Fallback if title becomes empty after sanitizing.
if not name or name in {".", ".."}:
    digest = hashlib.sha256(raw.encode("utf-8", "ignore")).hexdigest()[:8]
    name = f"markmap_{digest}"

# Keep filename component safely below common 255-byte filesystem limit.
def truncate_utf8(value, max_bytes):
    encoded = value.encode("utf-8")
    if len(encoded) <= max_bytes:
        return value
    return encoded[:max_bytes].decode("utf-8", "ignore").rstrip("._- ")

#name = truncate_utf8(name, 180)
name = truncate_utf8(name, 90)   # roughly 30 chinese charactoers 
if not name:
    name = "markmap"

# Avoid overwriting existing files:
# title.html, title_2.html, title_3.html, ...
candidate = outdir / f"{name}.html"

if not candidate.exists():
    print(candidate)
    raise SystemExit

for i in range(2, 10000):
    suffix = f"_{i}"
    base = truncate_utf8(name, 180 - len(suffix))
    candidate = outdir / f"{base}{suffix}.html"

    if not candidate.exists():
        print(candidate)
        raise SystemExit

# Very unlikely fallback.
digest = hashlib.sha256(raw.encode("utf-8", "ignore")).hexdigest()[:12]
print(outdir / f"markmap_{digest}.html")
PY
}

# ── extract title from markdown content ──
extract_title() {
	local file="$1"
	local title=""
	title=$(grep -m1 '^# ' "$file" | sed 's/^# //' | xargs)
	if [[ -z "$title" ]]; then
		title=$(sed -n '/^---$/,/^---$/{ s/^title:[[:space:]]*//p }' "$file" | head -1 | xargs)
	fi
	if [[ -z "$title" ]]; then
		title="markmap_$(date +%Y%m%d_%H%M%S)"
	fi
	title=$(echo "$title" | sed 's/[\/\\:*?"<>|]/_/g' | sed 's/[[:space:]]*$//')
	echo "$title"
}

# ── check if content already has markmap frontmatter ──
has_pre_header() {
	local file="$1"
	# Match YAML frontmatter containing "markmap:" key
	sed -n '/^---$/,/^---$/p' "$file" | grep -q '^markmap:' 2>/dev/null
}

# ── ensure markdown has markmap.initialExpandLevel: 2 before rendering ──
ensure_initial_expand_level() {
	local file="$1"
	local cfl="${2:-}"

	python3 - "$file" "$cfl" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
cfl = sys.argv[2] if len(sys.argv) > 2 else ""

text = path.read_text(encoding="utf-8")
lines = text.splitlines(True)

def find_frontmatter(lines):
    if not lines or lines[0].strip() != "---":
        return None

    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return 0, i

    return None

fm = find_frontmatter(lines)

if fm is None:
    block = [
        "---\n",
        "markmap:\n",
    ]

    if cfl:
        block.append(f"  colorFreezeLevel: {cfl}\n")

    block.extend([
        "  initialExpandLevel: 2\n",
        "---\n",
    ])

    lines = block + lines

else:
    start, end = fm
    fm_lines = lines[start + 1:end]

    markmap_index = None
    for i, line in enumerate(fm_lines):
        if re.match(r"^markmap\s*:\s*(?:#.*)?$", line):
            markmap_index = i
            break

    if markmap_index is None:
        insert = [
            "markmap:\n",
        ]

        if cfl:
            insert.append(f"  colorFreezeLevel: {cfl}\n")

        insert.append("  initialExpandLevel: 2\n")

        lines = lines[:end] + insert + lines[end:]

    else:
        section_start = start + 1 + markmap_index
        section_end = end

        for j in range(section_start + 1, end):
            line = lines[j]

            if line.strip() == "":
                continue

            if re.match(r"^[A-Za-z0-9_-]+\s*:", line):
                section_end = j
                break

        updated = False

        for j in range(section_start + 1, section_end):
            if re.match(r"^\s*initialExpandLevel\s*:", lines[j]):
                lines[j] = re.sub(
                    r"^(\s*initialExpandLevel\s*:).*$",
                    r"\1 2",
                    lines[j].rstrip("\r\n"),
                ) + "\n"
                updated = True
                break

        if not updated:
            lines = (
                lines[:section_start + 1]
                + ["  initialExpandLevel: 2\n"]
                + lines[section_start + 1:]
            )

path.write_text("".join(lines), encoding="utf-8")
PY
}

# ── append custom keyboard-control script before exactly </body> ──
append_new_code_to_html() {
	local html="$1"
	local codefile
	codefile=$(mktemp)

	cat >"$codefile" <<'NEW_CODE'
<script>
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

NEW_CODE

	python3 - "$html" "$codefile" <<'PY'
from pathlib import Path
import sys

html_path = Path(sys.argv[1])
code_path = Path(sys.argv[2])

html = html_path.read_text(encoding="utf-8")
code = code_path.read_text(encoding="utf-8")

marker = "</body>"

if marker not in html:
    raise SystemExit(f"[!] </body> not found in {html_path}")

html = html.replace(marker, code + "\n" + marker, 1)
html_path.write_text(html, encoding="utf-8")
PY

	rm -f "$codefile"
}

# ── content-driven mode selection ──
# Always start by asking for markdown content. If the user enters nothing
# (empty, or just a filler char like n / N / 呢 / 你 / 能), fall back to file mode.
echo "=== Markmap Renderer ==="
echo "Type/paste your markdown below. Press Ctrl-D when done."
echo "(Leave empty — or type only n / N / 呢 / 你 / 能 — to switch to file mode)"
echo "---"

tmpfile=$(mktemp /tmp/markmap_input_XXXXXX.md)
cat >"$tmpfile"
echo ""

# Strip all whitespace to detect "empty or filler" content
trimmed=$(tr -d '[:space:]' <"$tmpfile")

case "$trimmed" in
"" | n | N | 呢 | 你 | 能)
	file_mode=1
	;;
*)
	file_mode=0
	;;
esac

if [[ "$file_mode" -eq 1 ]]; then
	# ── File mode: ask for .md file paths ──
	rm -f "$tmpfile"
	echo "→ No content detected. Switching to file mode."
	echo "Enter .md file paths, one per line."
	echo "Press Ctrl-D or empty line to finish."
	echo "  files ↓"
	files=()
	while IFS= read -r f; do
		[[ -z "$f" ]] && break
		if [[ ! -f "$f" ]]; then
			echo "  ⚠  File not found: $f (skipped)"
			continue
		fi
		files+=("$(realpath "$f")")
	done

	if [[ ${#files[@]} -eq 0 ]]; then
		echo "No valid files provided. Exiting."
		exit 1
	fi

	for f in "${files[@]}"; do
		ensure_initial_expand_level "$f"
		outfile="${f%.md}.html"
		markmap "$f" -o "$outfile" --no-open
		append_new_code_to_html "$outfile"
		echo -e "[✓] ${f} → ${BR}${outfile}${RS}"
	done
else
	# ── Content mode: render the captured markdown ──
	if has_pre_header "$tmpfile"; then
		ensure_initial_expand_level "$tmpfile"
	else
		# No pre_header detected — ask for colorFreezeLevel
		echo -n "colorFreezeLevel [3] (2s timeout): "
		if read -rt 2 cfl; then
			cfl="${cfl:-3}"
		else
			cfl=3
			echo ""
		fi

		ensure_initial_expand_level "$tmpfile" "$cfl"
	fi

	title=$(extract_title "$tmpfile")
	#outfile="$(pwd)/${title}.html"
	#outfile=$(build_outfile "$title" html)
	outfile=$(make_outfile_path "$title")
	markmap "$tmpfile" -o "$outfile" --no-open
	append_new_code_to_html "$outfile"
	rm -f "$tmpfile"
	echo -e "[✓] Rendered → ${BR}${outfile}${RS}"
fi
