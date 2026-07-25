#!/usr/bin/env bash
# change_timezone_setting.sh
# Step 0: back up ONLY the files that actually contain the old timedatectl line.
# Step 1: replace "timedatectl set-timezone Asia/Shanghai" -> "... Australia/Perth"
#
# Usage: run from the folder that holds warp3, menu.sh, debian_tools,
#        pre_tcpx.sh, tcp131721.sh (or wherever the matching files live).

set -euo pipefail

OLD_LINE='timedatectl set-timezone Asia/Shanghai'
OLD_TZ='Asia/Shanghai'
NEW_TZ='Australia/Perth'
#BACKUP_DIR="./tz_backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="./tz_backup_$(date +%Y%m%d_%H_Shanghai)"

# Fixed list of exactly the 5 confirmed files. No discovery/searching --
# only these get touched, no matter what else is in the folder.
FILES=(
	warp3
	menu.sh
	debian_tools
	pre_tcpx.sh
	tcp131721.sh
)

for f in "${FILES[@]}"; do
	if [ ! -f "$f" ]; then
		echo "ERROR: expected file not found: $f" >&2
		exit 1
	fi
done

echo "Target files (${#FILES[@]}):"
printf '  - %s\n' "${FILES[@]}"
echo

mkdir -p "$BACKUP_DIR"

echo "Backing up..."
for f in "${FILES[@]}"; do
	cp -p -- "$f" "$BACKUP_DIR/"
	echo "  $f -> $BACKUP_DIR/$f"
done
echo

echo "Replacing $OLD_TZ -> $NEW_TZ ..."
for f in "${FILES[@]}"; do
	sed -i "s|${OLD_LINE}|timedatectl set-timezone ${NEW_TZ}|g" -- "$f"
	echo "  updated: $f"
done
echo

echo "Done. Backups saved in: $BACKUP_DIR"
echo "Diff preview:"
for f in "${FILES[@]}"; do
	echo "--- $f ---"
	diff -u "$BACKUP_DIR/$f" "$f" || true
done
