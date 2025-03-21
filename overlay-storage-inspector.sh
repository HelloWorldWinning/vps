#!/bin/bash

# Set threshold to 50MB (in bytes)
M=310
THRESHOLD=$((M * 1024 * 1024))

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=== Docker Overlay2 Storage Analysis ===${NC}"
echo -e "Finding overlay directories larger than ${YELLOW}${M}MB${NC}..."
echo

# Step 1: Get all folder names with sizes >= threshold, sorted from small to big
overlay_dirs=$(find /var/lib/docker/overlay2 -maxdepth 1 -type d -not -path "/var/lib/docker/overlay2" | while read dir; do
    size=$(du -sb "$dir" 2>/dev/null | awk '{print $1}')
    if [ "$size" -ge "$THRESHOLD" ]; then
        echo "$size $dir"
    fi
done | sort -n)

# Function to get container names and image names from overlay ID
get_container_and_image_info() {
    overlay_id=$(basename "$1")
    container_info=""
    image_info=""
    
    # Try to find container using this overlay
    container_id=$(docker ps -qa | while read cid; do
        if docker inspect --format='{{.GraphDriver.Data.MergedDir}}' "$cid" 2>/dev/null | grep -q "$overlay_id"; then
            echo "$cid"
            break
        fi
    done)
    
    # If container found, get name and image
    if [ -n "$container_id" ]; then
        container_name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's|^/||')
        image_id=$(docker inspect --format='{{.Image}}' "$container_id" 2>/dev/null)
        image_name=$(docker inspect --format='{{index .Config.Image}}' "$container_id" 2>/dev/null)
        
        container_info="Container: ${GREEN}$container_name${NC}"
        image_info="Image: ${BLUE}$image_name${NC}"
    else
        # Check if it's an image layer
        layer_id=$(cat "$1/link" 2>/dev/null)
        if [ -n "$layer_id" ]; then
            # Try to find image that uses this layer
            image_id=$(grep -l "$layer_id" /var/lib/docker/image/overlay2/imagedb/content/sha256/* 2>/dev/null | head -1)
            if [ -n "$image_id" ]; then
                image_id=$(basename "$image_id")
                image_name=$(docker images --no-trunc --format '{{.Repository}}:{{.Tag}}' | grep "$image_id" | head -1)
                if [ -n "$image_name" ]; then
                    image_info="Image: ${BLUE}$image_name${NC}"
                else
                    image_info="Image: ${BLUE}<untagged>${NC}"
                fi
            else
                image_info="Layer: ${BLUE}(possibly intermediate or dangling)${NC}"
            fi
        fi
    fi
    
    echo -e "$container_info"
    echo -e "$image_info"
}

# Step 2: Process each directory
echo "$overlay_dirs" | while read line; do
    size_bytes=$(echo "$line" | awk '{print $1}')
    dir=$(echo "$line" | awk '{print $2}')
    
    # Convert size to human-readable format without using bc
    if [ "$size_bytes" -ge $((1024*1024*1024)) ]; then
        # Convert to GB with one decimal point using awk
        size=$(awk "BEGIN {printf \"%.1f\", $size_bytes/1024/1024/1024}")
        size_unit="GB"
    else
        # Convert to MB with one decimal point using awk
        size=$(awk "BEGIN {printf \"%.1f\", $size_bytes/1024/1024}")
        size_unit="MB"
    fi
    
    # Get directory basename (overlay ID)
    overlay_id=$(basename "$dir")
    
    echo "╔════════════════════════════════════════════════════════════"
    echo -e "║ Overlay Directory: ${MAGENTA}${size}${size_unit}${NC}"
    echo "║ ID: $overlay_id"
    echo "╠────────────────────────────────────────────────────────────"
    
    # Get container and image info
    info=$(get_container_and_image_info "$dir")
    
    if [ -z "$info" ]; then
        echo "║ No associated container or image found"
    else
        echo -e "$info" | while read info_line; do
            if [ -n "$info_line" ]; then
                echo -e "║ $info_line"
            fi
        done
    fi
    
    echo "╚════════════════════════════════════════════════════════════"
    echo
done

echo "Analysis complete."
