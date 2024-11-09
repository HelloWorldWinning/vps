#!/bin/bash

#GREEN='\033[0;32m'
BOLD_BRIGHT_YELLOW='\033[1;38;5;226m'
BOLD_AMBER_YELLOW='\033[1;38;5;222m'
BOLD_YELLOW_4='\033[1;38;5;185m' # Golden yellow

GREEN='\033[0;38;5;185m'
BOLD_RED_BACKGROUND='\033[0;45m'
BOLD_RED='\033[1;31m'
CYAN='\033[0;36m'
RED='\033[38;5;88m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to fetch and display details for a given container
get_container_details() {
    local container_name="$1"
    local details=$(docker inspect "$container_name" | jq -r '.[] | "\(.Config.Image):\(.NetworkSettings.Ports)"')
    echo "$details"
}

#get_port_bindings() {
#    local container_name="$1"
#    local port_bindings=$(docker inspect "$container_name" | jq -r '.[] | .NetworkSettings.Ports | to_entries[] | select(.value != null) | "\(.value[0].HostPort):\(.key)"' | head -n 1)
#    echo "$port_bindings"
#}


get_port_bindings() {
    local container_name="$1"
    local port_bindings=$(docker inspect "$container_name" | jq -r '
        .[].NetworkSettings.Ports | 
        to_entries[] | 
        select(.value != null) | 
        "\(.value[0].HostPort):\(.key)"
    ')
    # Join multiple port bindings with commas
    if [ -n "$port_bindings" ]; then
        echo "$port_bindings" | paste -sd "," -
    fi
}



# Function to fetch and display the docker-compose path for a given container
get_docker_compose_path() {
    local container_name="$1"
    docker inspect "$container_name" | jq -r '.[] | .Config.Labels | "\(.["com.docker.compose.project.working_dir"])/\(.["com.docker.compose.project.config_files"])"'
}

# Function to get container status
get_container_status() {
    local container_name="$1"
    docker inspect -f '{{.State.Status}}' "$container_name"
}

# Prompt for filter string
#read -p "Enter filter string (leave empty for no filter): " filter_string

echo -e "\n================= start  =========================\n"

# If a container name is provided as an argument
if [ "$#" -eq 1 ]; then
    container_name="$1"
    details=$(get_container_details "$container_name")
    image_name=$(echo "$details" | cut -d: -f1)
    port_bindings=$(get_port_bindings "$container_name")
    path=$(get_docker_compose_path "$container_name")
    status=$(get_container_status "$container_name")
    item="$image_name   ---   $container_name   ---   $port_bindings   ---   $path   ---   $status"
    if [[ -z "$filter_string" || "$item" =~ $filter_string ]]; then
        echo -e "${BOLD_RED}$port_bindings${NC}  ---  ${YELLOW}$path${NC}  --- ${RED}$status${NC} ---  ${CYAN}$image_name${NC}  ---  ${CYAN}$container_name${NC}"
    fi
else
    # List all containers (including stopped ones) and their details
    docker ps -a --format "{{.Names}}" | while read container_name; do
        details=$(get_container_details "$container_name")
        image_name=$(echo "$details" | cut -d: -f1)
        port_bindings=$(get_port_bindings "$container_name")
        path=$(get_docker_compose_path "$container_name")
        status=$(get_container_status "$container_name")
        item="$image_name   ---   $container_name   ---   $port_bindings   ---   $path   ---   $status"
        if [[ -z "$filter_string" || "$item" =~ $filter_string ]]; then
            if [[ -z "$port_bindings" ]]; then
                echo -e "${YELLOW}$path${NC}  --- ${RED}$status${NC} ---  ${GREEN}$image_name${NC}   ---   ${CYAN}$container_name${NC}"
            else
              # echo -e "${BOLD_RED} 【  $port_bindings  】 ${NC}   ---   ${YELLOW}$path${NC}  --- ${RED}$status${NC} ---   ${GREEN}$image_name${NC}  ---  ${CYAN}$container_name${NC}"
                echo -e "${BOLD_RED}    $port_bindings    ${NC}   ---   ${YELLOW}$path${NC}  --- ${RED}$status${NC} ---   ${GREEN}$image_name${NC}  ---  ${CYAN}$container_name${NC}"
            fi
#           echo " "
printf '\033[1;34m%*s\033[0m\n' "${COLUMNS:-$(tput cols)}" '' | sed 's/ /─/g'
        fi
    done
fi

echo -e "\n================= end  =========================\n"
