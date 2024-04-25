#!/bin/bash
docker ps -a

echo -e "\n==================\n"
MAGENTA_BACKGROUND='\033[1;45m'
MAGENTA='\033[1;35m'
CYAN='\033[1;35m' # You may choose another color for image_name if you wish
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to fetch and display details for a given container
get_container_details() {
    local container_name="$1"
    local details=$(docker inspect "$container_name" | jq -r '.[] | "\(.Config.Image):\(.NetworkSettings.Ports)"')
    echo "$details"
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
    expose_port=$(echo "$details" | cut -d: -f2 | sed -e 's/[^0-9]//g')
    path=$(get_docker_compose_path "$container_name")
    echo -e "${CYAN}$image_name${NC}---${CYAN}$container_name${NC}---${RED}$expose_port${NC}---${YELLOW}$path${NC}"
else
    # If no container name is provided, list all running containers and their details
    docker ps --format "{{.Names}}" | while read container_name; do
        details=$(get_container_details "$container_name")
        image_name=$(echo "$details" | cut -d: -f1)
        expose_port=$(echo "$details" | cut -d: -f2 | sed -e 's/[^0-9]//g')
        path=$(get_docker_compose_path "$container_name")
        if [[ -z "$expose_port" ]]; then
           #echo -e "${CYAN}$image_name${NC}---${CYAN}$container_name${NC}---${YELLOW}$path${NC}"
            echo -e "${YELLOW}$image_name${NC}---${CYAN}$container_name${NC}---${YELLOW}$path${NC}"
        else
           #echo -e "${CYAN}$image_name${NC}---${CYAN}$container_name${NC}---${RED}$expose_port${NC}---${YELLOW}$path${NC}"
            echo -e "${YELLOW}$image_name${NC}---${CYAN}$container_name${NC}---${RED}$expose_port${NC}---${YELLOW}$path${NC}"
        fi
        echo " "
    done
fi

echo -e "\n==================\n"
