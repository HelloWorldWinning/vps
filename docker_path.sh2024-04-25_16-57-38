#!/bin/bash
docker ps -a

echo -e "\n==================\n"

# ANSI color codes
CYAN='\033[1;35m'
#YELLOW='\033[1;33m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to fetch and display the docker-compose path for a given container
get_docker_compose_path() {
    local container_name="$1"
    docker inspect "$container_name" | jq -r '.[] | .Config.Labels | "\(.["com.docker.compose.project.working_dir"])/\(.["com.docker.compose.project.config_files"])"'
}

# If a container name is provided as an argument
if [ "$#" -eq 1 ]; then
    container_name="$1"
    path=$(get_docker_compose_path "$container_name")
    echo -e "${CYAN}$container_name${NC}: ${YELLOW}$path${NC}"
else
    # If no container name is provided, list all running containers and their paths
    docker ps --format "{{.Names}}" | while read container_name; do
        path=$(get_docker_compose_path "$container_name")
        echo -e "${CYAN}$container_name${NC}: ${YELLOW}$path${NC}"
    done
fi


echo -e "\n==================\n"
