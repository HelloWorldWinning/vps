#!/usr/bin/env sh
# get_v2rayng_latest.sh
# Downloads latest v2rayNG arm64-v8a and universal APKs into $ANDROID_DIR using IPv4.

set -euo pipefail

# --- Paths (you can export these before running to override) ---
VPN_BASE_DIR="${VPN_BASE_DIR:-/data/d.share/vpn-tools}"
ANDROID_DIR="${ANDROID_DIR:-$VPN_BASE_DIR/android}"

# --- Config ---
REPO="2dust/v2rayNG"
API="https://api.github.com/repos/${REPO}/releases/latest"

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

# Helper to extract asset TSV: "<name>\t<url>"
find_asset() {
  echo "$JSON" \
    | jq -r --arg re "$1" '
        .assets[] | select(.name | test($re))
        | [.name, .browser_download_url] | @tsv
      ' \
    | head -n 1
}

ARM64_LINE="$(find_asset "arm64-v8a\\.apk$" || true)"
UNIV_LINE="$(find_asset "universal\\.apk$" || true)"

if [ -z "${ARM64_LINE:-}" ] || [ -z "${UNIV_LINE:-}" ]; then
  echo "Could not find expected assets in the latest release." >&2
  echo "Available assets:" >&2
  echo "$JSON" | jq -r '.assets[].name' >&2
  exit 1
fi

ARM64_NAME="$(printf %s "$ARM64_LINE" | awk -F '\t' '{print $1}')"
ARM64_URL="$(printf %s "$ARM64_LINE" | awk -F '\t' '{print $2}')"
UNIV_NAME="$(printf %s "$UNIV_LINE" | awk -F '\t' '{print $1}')"
UNIV_URL="$(printf %s "$UNIV_LINE" | awk -F '\t' '{print $2}')"

echo "Downloading to: $ANDROID_DIR"
echo " - $ARM64_NAME"
wget -4 -O "$ANDROID_DIR/$ARM64_NAME" "$ARM64_URL"

echo " - $UNIV_NAME"
wget -4 -O "$ANDROID_DIR/$UNIV_NAME" "$UNIV_URL"

echo "Done."
echo "Files saved in: $ANDROID_DIR"

