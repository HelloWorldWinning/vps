#!/usr/bin/env sh
# get_v2rayng_latest.sh
# Downloads latest v2rayNG APKs (non-fdroid build) into $ANDROID_DIR using IPv4.
#
# NOTE: Recent v2rayNG releases no longer ship a single "universal.apk".
# Instead there's one APK per ABI: arm64-v8a, armeabi-v7a, x86, x86_64
# (plus "-fdroid" variants and .sig signature files for each).
# This script downloads two ABI variants by default; edit ABIS below to change.

set -euo pipefail

# --- Paths (you can export these before running to override) ---
VPN_BASE_DIR="${VPN_BASE_DIR:-/data/d.share/vpn-tools}"
ANDROID_DIR="${ANDROID_DIR:-$VPN_BASE_DIR/android}"

# --- Config ---
REPO="2dust/v2rayNG"
API="https://api.github.com/repos/${REPO}/releases/latest"

# Which ABI(s) to download. Options: arm64-v8a armeabi-v7a x86 x86_64
ABIS="${ABIS:-arm64-v8a armeabi-v7a}"

# --- Requirements check ---
need() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "Error: '$1' is required but not installed." >&2
		exit 1
	}
}
need curl
need jq
need wget

# Ensure destination exists
mkdir -p "$ANDROID_DIR"

# Fetch latest release JSON
JSON="$(curl -fsSL "$API")"

# Helper to extract asset TSV: "<name>\t<url>" for a given ABI,
# excluding fdroid builds and .sig signature files.
find_asset() {
	abi="$1"
	echo "$JSON" |
		jq -r --arg abi "$abi" '
        .assets[]
        | select(.name | test("^v2rayNG_[0-9.]+_" + $abi + "\\.apk$"))
        | [.name, .browser_download_url] | @tsv
      ' |
		head -n 1
}

echo "Downloading to: $ANDROID_DIR"

FOUND_ANY=0
for abi in $ABIS; do
	LINE="$(find_asset "$abi" || true)"
	if [ -z "${LINE:-}" ]; then
		echo "Warning: no asset found for ABI '$abi'" >&2
		continue
	fi
	FOUND_ANY=1
	NAME="$(printf %s "$LINE" | awk -F '\t' '{print $1}')"
	URL="$(printf %s "$LINE" | awk -F '\t' '{print $2}')"
	echo " - $NAME"
	wget -4 -O "$ANDROID_DIR/$NAME" "$URL"
done

if [ "$FOUND_ANY" -eq 0 ]; then
	echo "Could not find any expected assets in the latest release." >&2
	echo "Available assets:" >&2
	echo "$JSON" | jq -r '.assets[].name' >&2
	exit 1
fi

echo "Done."
echo "Files saved in: $ANDROID_DIR"
