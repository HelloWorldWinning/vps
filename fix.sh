#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "Usage: bash fix.sh markmap.sh" >&2
}

if [[ $# -ne 1 ]]; then
	usage
	exit 2
fi

script="$1"

if [[ ! -f "$script" ]]; then
	echo "[!] File not found: $script" >&2
	exit 1
fi

if [[ ! -w "$script" ]]; then
	echo "[!] File is not writable: $script" >&2
	exit 1
fi

backup="${script}.bak.$(date +%Y%m%d_%H%M%S)"
cp -p "$script" "$backup"

python3 - "$script" <<'FIXPY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

new_func = r'''# ── ensure markdown has markmap options before rendering ──
ensure_initial_expand_level() {
  local file="$1"
  # Default to 3 even when caller omits the argument.
  # This fixes pasted markdown that already has frontmatter.
  local cfl="${2:-3}"

  python3 - "$file" "$cfl" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
cfl = sys.argv[2] if len(sys.argv) > 2 else "3"
cfl = cfl.strip() or "3"

text = path.read_text(encoding="utf-8")
lines = text.splitlines(True)

def find_frontmatter(lines):
    if not lines or lines[0].strip() != "---":
        return None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return 0, i
    return None

def find_markmap_section(lines, start, end):
    fm_lines = lines[start + 1:end]
    markmap_index = None

    for i, line in enumerate(fm_lines):
        if re.match(r"^markmap\s*:\s*(?:#.*)?$", line):
            markmap_index = i
            break

    if markmap_index is None:
        return None

    section_start = start + 1 + markmap_index
    section_end = end

    for j in range(section_start + 1, end):
        line = lines[j]

        if line.strip() == "":
            continue

        # Next top-level YAML key ends the markmap block.
        if re.match(r"^[A-Za-z0-9_-]+\s*:", line):
            section_end = j
            break

    return section_start, section_end

def upsert_key(lines, section_start, section_end, key, value, overwrite):
    pattern = rf"^\s*{re.escape(key)}\s*:"

    for j in range(section_start + 1, section_end):
        if re.match(pattern, lines[j]):
            if overwrite:
                lines[j] = re.sub(
                    rf"^(\s*{re.escape(key)}\s*:).*$",
                    rf"\1 {value}",
                    lines[j].rstrip("\r\n"),
                ) + "\n"
            return lines, section_end

    lines.insert(section_start + 1, f"  {key}: {value}\n")
    return lines, section_end + 1

fm = find_frontmatter(lines)

if fm is None:
    lines = [
        "---\n",
        "markmap:\n",
        f"  colorFreezeLevel: {cfl}\n",
        "  initialExpandLevel: 2\n",
        "---\n",
    ] + lines
else:
    start, end = fm
    section = find_markmap_section(lines, start, end)

    if section is None:
        insert = [
            "markmap:\n",
            f"  colorFreezeLevel: {cfl}\n",
            "  initialExpandLevel: 2\n",
        ]
        lines = lines[:end] + insert + lines[end:]
    else:
        section_start, section_end = section

        # Add colorFreezeLevel only if it is missing. Existing markdown wins.
        lines, section_end = upsert_key(
            lines,
            section_start,
            section_end,
            "colorFreezeLevel",
            cfl,
            overwrite=False,
        )

        # Always force initialExpandLevel to 2.
        lines, section_end = upsert_key(
            lines,
            section_start,
            section_end,
            "initialExpandLevel",
            "2",
            overwrite=True,
        )

path.write_text("".join(lines), encoding="utf-8")
PY
}
'''

pattern = re.compile(
    r"(?ms)^# ── ensure markdown has markmap\.initialExpandLevel: 2 before rendering ──\n"
    r"ensure_initial_expand_level\(\) \{.*?^\}\n"
)

new_text, count = pattern.subn(new_func + "\n", text, count=1)

if count != 1:
    raise SystemExit(
        "[!] Could not find the old ensure_initial_expand_level() block. "
        "No changes written."
    )

path.write_text(new_text, encoding="utf-8")
print("[✓] Patched ensure_initial_expand_level()")
FIXPY

chmod +x "$script"
echo "[✓] Fixed: $script"
echo "[✓] Backup: $backup"
