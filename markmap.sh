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

# ── extract title from markdown content ──
# Priority: first "# heading" > YAML frontmatter "title:" > fallback
extract_title() {
	local file="$1"
	local title=""

	# 1) first top-level # heading (highest priority in markmap)
	title=$(grep -m1 '^# ' "$file" | sed 's/^# //' | xargs)

	# 2) fallback: YAML frontmatter title
	if [[ -z "$title" ]]; then
		title=$(sed -n '/^---$/,/^---$/{ s/^title:[[:space:]]*//p }' "$file" | head -1 | xargs)
	fi

	# 3) fallback: timestamp
	if [[ -z "$title" ]]; then
		title="markmap_$(date +%Y%m%d_%H%M%S)"
	fi

	# sanitize: replace / \ : * ? " < > | with _
	title=$(echo "$title" | sed 's/[\/\\:*?"<>|]/_/g' | sed 's/[[:space:]]*$//')

	echo "$title"
}

# ── mode selection ──
echo "=== Markmap Renderer ==="
echo "  1) Type markdown text  (default — just press Enter)"
echo "  2) Provide .md file(s)"
echo ""
read -rp "Choose mode [1]: " mode
mode="${mode:-1}"

if [[ "$mode" == "1" ]]; then
	# ── Mode 1: text input → save in current directory ──
	tmpfile=$(mktemp /tmp/markmap_input_XXXXXX.md)
	echo "Type/paste your markdown below. Press Ctrl-D when done."
	echo "---"
	cat >"$tmpfile"
	echo ""

	title=$(extract_title "$tmpfile")
	outfile="$(pwd)/${title}.html"

	markmap "$tmpfile" -o "$outfile" --no-open
	rm -f "$tmpfile"
	echo -e "[✓] Rendered → ${BR}${outfile}${RS}"

elif [[ "$mode" == "2" ]]; then
	# ── Mode 2: file input ──
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
		outfile="${f%.md}.html"
		markmap "$f" -o "$outfile" --no-open
		echo -e "[✓] ${f} → ${BR}${outfile}${RS}"
	done

else
	echo "Invalid mode. Exiting."
	exit 1
fi
