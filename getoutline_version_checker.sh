#!/usr/bin/env bash
# Outline Wiki Auto-Updater
# - Pulls latest Docker image
# - Restarts containers only if a new image was downloaded
# - Logs all actions with timestamps

set -Eeuo pipefail

# Configuration
DOCKER_IMAGE="docker.getoutline.com/outlinewiki/outline:latest"
OUTLINE_DIR="/root/Outline_D"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Error trap for unexpected failures
trap 'echo -e "${RED}[$(date "+%Y-%m-%d %H:%M:%S")]${NC} Unexpected error on line $LINENO"; exit 1' ERR

# --- Logging ---
log()         { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
log_success() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
log_error()   { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }

# Get current image ID (before pull)
get_image_id() {
    docker images --no-trunc -q "$DOCKER_IMAGE" 2>/dev/null | head -n1 || true
}

# Pull latest image and check if updated
pull_image() {
    log "Pulling latest Outline image..."
    
    local pull_output
    if ! pull_output=$(docker pull "$DOCKER_IMAGE" 2>&1); then
        log_error "Failed to pull Docker image"
        echo "$pull_output"
        return 1
    fi
    
    echo "$pull_output"
    
    # Check pull output for update status
    if echo "$pull_output" | grep -q "Status: Downloaded newer image"; then
        return 0  # New image downloaded
    elif echo "$pull_output" | grep -q "Status: Image is up to date"; then
        return 1  # Already up to date
    else
        # Fallback: assume update if we see "Pull complete" lines
        if echo "$pull_output" | grep -q "Pull complete"; then
            return 0
        fi
        return 1
    fi
}

# Restart Outline containers
restart_outline() {
    log "Restarting Outline containers..."
    
    if [[ ! -d "$OUTLINE_DIR" ]]; then
        log_error "Outline directory not found: $OUTLINE_DIR"
        return 1
    fi
    
    cd "$OUTLINE_DIR"
    
    log "Stopping containers..."
    if ! docker compose down; then
        log_error "Failed to stop containers"
        return 1
    fi
    
    log "Starting containers..."
    if ! docker compose up -d; then
        log_error "Failed to start containers"
        return 1
    fi
    
    log_success "Containers restarted successfully"
    return 0
}

# Clean up old dangling images (optional)
cleanup_old_images() {
    log "Cleaning up old Outline images..."
    
    # Remove dangling images (old versions marked as <none>)
    local old_images
    old_images=$(docker images --filter "dangling=true" --filter "reference=docker.getoutline.com/outlinewiki/outline" -q 2>/dev/null || true)
    
    if [[ -n "$old_images" ]]; then
        echo "$old_images" | xargs -r docker rmi 2>/dev/null || true
        log_success "Cleaned up old images"
    else
        log "No old images to clean up"
    fi
}

main() {
    log "Starting Outline update check..."
    
    # Get current image ID before pull
    local old_image_id
    old_image_id=$(get_image_id)
    log "Current image ID: ${old_image_id:-none}"
    
    # Pull latest image
    local pull_output
    pull_output=$(docker pull "$DOCKER_IMAGE" 2>&1) || true
    echo "$pull_output"
    
    # Get new image ID after pull
    local new_image_id
    new_image_id=$(get_image_id)
    log "New image ID: ${new_image_id:-none}"
    
    # Determine if update occurred
    local needs_restart=false
    
    # Method 1: Check pull output
    if echo "$pull_output" | grep -q "Status: Downloaded newer image"; then
        needs_restart=true
        log_warning "⚠ New image downloaded"
    elif echo "$pull_output" | grep -q "Status: Image is up to date"; then
        log_success "✓ Image is already up to date"
    # Method 2: Compare image IDs (fallback)
    elif [[ -n "$old_image_id" && -n "$new_image_id" && "$old_image_id" != "$new_image_id" ]]; then
        needs_restart=true
        log_warning "⚠ Image ID changed, new version detected"
    # Method 3: No previous image existed
    elif [[ -z "$old_image_id" && -n "$new_image_id" ]]; then
        needs_restart=true
        log_warning "⚠ Fresh image pulled"
    else
        log_success "✓ No update needed"
    fi
    
    # Restart if needed
    if [[ "$needs_restart" == true ]]; then
        log "Starting update process..."
        
        if restart_outline; then
            log_success "✓ Successfully updated Outline to latest version"
            
            # Optional: cleanup old images
            cleanup_old_images
        else
            log_error "✗ Failed to restart Outline"
            exit 1
        fi
    else
        log "No restart needed. Exiting."
    fi
    
    log_success "Update check completed successfully"
}

# Run if not sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

