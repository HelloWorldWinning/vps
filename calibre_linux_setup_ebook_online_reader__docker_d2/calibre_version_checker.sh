#!/usr/bin/env bash
# Calibre Version Checker and Auto-Updater (fixed)
# - Writes logs to stderr so command substitutions stay clean
# - Robust version parsing & comparison
# - Safe with `set -e` via guarded comparisons
# - Slightly hardened HTML/CLI extraction

set -Eeuo pipefail

# Configuration
DOCKER_IMAGE="oklove/calibre1"
BUILD_SCRIPT="/data/vps/calibre_linux_setup_ebook_online_reader__docker_d2/build_restart_push.sh"
CALIBRE_DOWNLOAD_URL="https://calibre-ebook.com/download_linux"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Error trap for unexpected failures
trap 'echo -e "${RED}[$(date "+%Y-%m-%d %H:%M:%S")]${NC} Unexpected error on line $LINENO"; exit 1' ERR

# --- Logging (to stderr) ---
log()         { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" >&2; }
log_error()   { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" >&2; }

# Strip ANSI escape sequences (defensive; should be unnecessary once logs go to stderr)
strip_ansi() {
    # Removes CSI sequences like \x1b[0;34m etc.
    sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

# Normalize a version string into zero-padded "DDD.DDD.DDD" for lexicographic compare
normalize_version() {
    local raw="${1:-}"
    # extract the first token that looks like a version "X.Y" or "X.Y.Z"
    local version
    version=$(printf '%s' "$raw" \
        | strip_ansi \
        | grep -oE '[0-9]+(\.[0-9]+)+' \
        | head -n1 || true)

    if [[ -z "${version:-}" ]]; then
        # Signal "no version found" by returning empty string (caller can handle)
        echo ""
        return 0
    fi

    local IFS='.'
    local -a PARTS
    read -r -a PARTS <<< "$version"

    # Pad to three components
    printf "%03d.%03d.%03d" \
        "${PARTS[0]:-0}" \
        "${PARTS[1]:-0}" \
        "${PARTS[2]:-0}"
}

# Get latest version from Calibre website
get_latest_version() {
    log "Fetching latest Calibre version from website..."
    local html
    if ! html=$(curl -fsSL --max-time 30 "$CALIBRE_DOWNLOAD_URL"); then
        log_error "Failed to fetch Calibre download page"
        return 1
    fi

    # Primary pattern on the page
    local version
    version=$(printf '%s' "$html" \
        | grep -oE 'The latest release of calibre is [0-9]+(\.[0-9]+)+' \
        | grep -oE '[0-9]+(\.[0-9]+)+' \
        | head -n1 || true)

    # Fallbacks in case the phrasing changes
    if [[ -z "${version:-}" ]]; then
        version=$(printf '%s' "$html" \
            | grep -oE 'Version[: ]+[0-9]+(\.[0-9]+)+' \
            | grep -oE '[0-9]+(\.[0-9]+)+' \
            | head -n1 || true)
    fi

    if [[ -z "${version:-}" ]]; then
        log_error "Could not extract version from website"
        return 1
    fi

    printf '%s\n' "$version"
}

# Get current Docker image version
get_docker_version() {
    log "Checking current Docker image version..."

    # It's OK if the image isn't local; docker run will pull implicitly.
    local docker_output
    if ! docker_output=$(docker run --rm "$DOCKER_IMAGE" calibre --version 2>/dev/null); then
        log_error "Failed to get version from Docker image: $DOCKER_IMAGE"
        return 1
    fi

    # Extract the first X.Y[.Z] token from the output
    local version
    version=$(printf '%s' "$docker_output" \
        | grep -oE '[0-9]+(\.[0-9]+)+' \
        | head -n1 || true)

    if [[ -z "${version:-}" ]]; then
        log_error "Could not extract version from Docker output: $docker_output"
        return 1
    fi

    printf '%s\n' "$version"
}

# Compare versions
# Returns:
#   0 -> equal
#   1 -> v1 < v2
#   2 -> v1 > v2
#   3 -> parse error (one side missing)
version_compare() {
    local v1_norm v2_norm
    v1_norm=$(normalize_version "${1:-}")
    v2_norm=$(normalize_version "${2:-}")

    if [[ -z "$v1_norm" || -z "$v2_norm" ]]; then
        return 3
    fi

    if [[ "$v1_norm" == "$v2_norm" ]]; then
        return 0
    elif [[ "$v1_norm" < "$v2_norm" ]]; then
        return 1
    else
        return 2
    fi
}

# Run the build script
run_build_script() {
    log "Running build script: $BUILD_SCRIPT"

    if [[ ! -f "$BUILD_SCRIPT" ]]; then
        log_error "Build script not found: $BUILD_SCRIPT"
        return 1
    fi

    if [[ ! -x "$BUILD_SCRIPT" ]]; then
        log_warning "Build script is not executable, making it executable..."
        chmod +x "$BUILD_SCRIPT"
    fi

    log "Executing build script..."
    if bash "$BUILD_SCRIPT"; then
        log_success "Build script completed successfully"
        return 0
    else
        local rc=$?
        log_error "Build script failed with exit code $rc"
        return "$rc"
    fi
}

main() {
    log "Starting Calibre version check..."

    # Latest from website
    local latest_version
    latest_version=$(get_latest_version)
    log_success "Latest Calibre version: $latest_version"

    # Current from Docker image
    local current_version
    current_version=$(get_docker_version)
    log_success "Current Docker image version: $current_version"

    # Compare
    log "Comparing versions..."
    log "  Latest:  $latest_version (normalized: $(normalize_version "$latest_version"))"
    log "  Current: $current_version (normalized: $(normalize_version "$current_version"))"

    local comparison
    if version_compare "$current_version" "$latest_version"; then
        comparison=0
    else
        comparison=$?
    fi

    case "$comparison" in
        0)
            log_success "✓ Docker image is up to date (v$current_version)"
            log "No update needed. Exiting."
            ;;
        1)
            log_warning "⚠ Docker image is outdated"
            log "Current: $current_version, Latest: $latest_version"
            log "Starting update process..."

            if run_build_script; then
                log_success "✓ Successfully updated Docker image to latest version"
            else
                log_error "✗ Failed to update Docker image"
                exit 1
            fi
            ;;
        2)
            log_warning "⚠ Docker image version ($current_version) is newer than website version ($latest_version)"
            log "This might indicate a beta/development version or website update delay."
            log "No action taken."
            ;;
        3)
            log_error "✗ Unable to compare versions (parse error)"
            exit 1
            ;;
    esac

    log_success "Version check completed successfully"
}

# Run if not sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

