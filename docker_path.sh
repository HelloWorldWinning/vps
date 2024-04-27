#!/bin/bash

echo -e "\n======================================================\n"

GREEN='\033[0;32m'
MAGENTA_BACKGROUND='\033[0;45m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m' # You can choose another color for image_name if you wish
#RED='\033[0;31m'
RED='\033[1;31m'
#RED='\033[0;91m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color






# Function to fetch and display details for a given container
get_container_details() {
    local container_name="$1"
    local details=$(docker inspect "$container_name" | jq -r '.[] | "\(.Config.Image):\(.NetworkSettings.Ports)"')
    echo "$details"
}

get_port_bindings() {
    local container_name="$1"
    local port_bindings=$(docker inspect "$container_name" | jq -r '.[] | .NetworkSettings.Ports | to_entries[] | select(.value != null) | "\(.value[0].HostPort):\(.key)"' | head -n 1)
    echo "$port_bindings"
}

# Function to fetch and display the docker-compose path for a given container
get_docker_compose_path() {
    local container_name="$1"
    docker inspect "$container_name" | jq -r '.[] | .Config.Labels | "\(.["com.docker.compose.project.working_dir"])/\(.["com.docker.compose.project.config_files"])"'
}

# If a container name is provided as an argument
if [ "$#" -eq 1 ]; then
    container_name="$1"
    details=$(get_container_details "$container_name")
    image_name=$(echo "$details" | cut -d: -f1)
    port_bindings=$(get_port_bindings "$container_name")
    path=$(get_docker_compose_path "$container_name")
    echo -e "${CYAN}$image_name${NC}---${CYAN}$container_name${NC}---${RED}$port_bindings${NC}---${YELLOW}$path${NC}"
else
    # If no container name is provided, list all running containers and their details
    docker ps --format "{{.Names}}" | while read container_name; do
        details=$(get_container_details "$container_name")
        image_name=$(echo "$details" | cut -d: -f1)
        port_bindings=$(get_port_bindings "$container_name")
        path=$(get_docker_compose_path "$container_name")
        if [[ -z "$port_bindings" ]]; then
            echo -e "${GREEN}$image_name${NC}---${CYAN}$container_name${NC}---${YELLOW}$path${NC}"
        else
            echo -e "${GREEN}$image_name${NC}---${CYAN}$container_name${NC}---${RED}$port_bindings${NC}---${YELLOW}$path${NC}"
        fi
        echo " "
    done
fi

echo -e "\n======================================================\n"
