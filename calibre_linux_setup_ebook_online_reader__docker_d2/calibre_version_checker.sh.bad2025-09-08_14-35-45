#!/bin/bash

# Calibre Version Checker and Auto-Updater
# This script checks if the Docker image version matches the latest Calibre release
# and rebuilds the image if an update is available

set -e  # Exit on any error

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

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Function to normalize version strings for comparison
normalize_version() {
    local version="$1"
    # Remove any leading/trailing whitespace
    version=$(echo "$version" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Extract version number (remove any text like "calibre" or parentheses)
    version=$(echo "$version" | sed 's/.*calibre[[:space:]]*(//' | sed 's/).*//' | sed 's/calibre[[:space:]]*//')
    
    # Ensure we have a clean version number
    version=$(echo "$version" | grep -oE '[0-9]+(\.[0-9]+)*')
    
    # Pad version components to 3 digits for proper comparison
    # e.g., 8.9 becomes 8.9.0, then 008.009.000 for comparison
    IFS='.' read -ra PARTS <<< "$version"
    normalized=""
    for i in {0..2}; do
        if [ ${#PARTS[@]} -gt $i ]; then
            normalized="${normalized}$(printf "%03d" "${PARTS[$i]}")"
        else
            normalized="${normalized}000"
        fi
        if [ $i -lt 2 ]; then
            normalized="${normalized}."
        fi
    done
    echo "$normalized"
}

# Function to get latest version from Calibre website
get_latest_version() {
    log "Fetching latest Calibre version from website..."
    
    local html_content
    if ! html_content=$(curl -s --max-time 30 "$CALIBRE_DOWNLOAD_URL"); then
        log_error "Failed to fetch Calibre download page"
        return 1
    fi
    
    # Extract version from HTML - looking for "The latest release of calibre is X.X.X"
    local version
    version=$(echo "$html_content" | grep -oE "The latest release of calibre is [0-9]+\.[0-9]+\.[0-9]+" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
    
    if [ -z "$version" ]; then
        log_error "Could not extract version from website"
        return 1
    fi
    
    echo "$version"
}

# Function to get current Docker image version
get_docker_version() {
    log "Checking current Docker image version..."
    
    local docker_output
    if ! docker_output=$(docker run --rm "$DOCKER_IMAGE" calibre --version 2>/dev/null); then
        log_error "Failed to get version from Docker image: $DOCKER_IMAGE"
        return 1
    fi
    
    # Extract version from docker output - looking for "calibre (calibre X.X)"
    local version
    version=$(echo "$docker_output" | grep -oE "calibre \(calibre [0-9]+\.[0-9]+(\.[0-9]+)?\)" | grep -oE "[0-9]+\.[0-9]+(\.[0-9]+)?")
    
    if [ -z "$version" ]; then
        log_error "Could not extract version from Docker output: $docker_output"
        return 1
    fi
    
    echo "$version"
}

# Function to compare versions
version_compare() {
    local v1_norm=$(normalize_version "$1")
    local v2_norm=$(normalize_version "$2")
    
    if [ "$v1_norm" = "$v2_norm" ]; then
        return 0  # Equal
    elif [ "$v1_norm" \< "$v2_norm" ]; then
        return 1  # v1 < v2
    else
        return 2  # v1 > v2
    fi
}

# Function to run the build script
run_build_script() {
    log "Running build script: $BUILD_SCRIPT"
    
    if [ ! -f "$BUILD_SCRIPT" ]; then
        log_error "Build script not found: $BUILD_SCRIPT"
        return 1
    fi
    
    if [ ! -x "$BUILD_SCRIPT" ]; then
        log_warning "Build script is not executable, making it executable..."
        chmod +x "$BUILD_SCRIPT"
    fi
    
    log "Executing build script..."
    if bash "$BUILD_SCRIPT"; then
        log_success "Build script completed successfully"
        return 0
    else
        log_error "Build script failed with exit code $?"
        return 1
    fi
}

# Main execution
main() {
    log "Starting Calibre version check..."
    
    # Get latest version from website
    local latest_version
    if ! latest_version=$(get_latest_version); then
        log_error "Failed to get latest version"
        exit 1
    fi
    log_success "Latest Calibre version: $latest_version"
    
    # Get current Docker image version
    local current_version
    if ! current_version=$(get_docker_version); then
        log_error "Failed to get current Docker version"
        exit 1
    fi
    log_success "Current Docker image version: $current_version"
    
    # Compare versions
    log "Comparing versions..."
    log "  Latest:  $latest_version (normalized: $(normalize_version "$latest_version"))"
    log "  Current: $current_version (normalized: $(normalize_version "$current_version"))"
    
    version_compare "$current_version" "$latest_version"
    local comparison=$?
    
    case $comparison in
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
    esac
    
    log_success "Version check completed successfully"
}

# Check if running as script (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"

fi
