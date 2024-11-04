#!/bin/bash

# Set the desired folder name
#
##folder_name="upload_service_docker_compose_folder"
##folder_name="/data/upload_service_docker_compose_folder"
folder_name="/root/upload_service_docker_compose_folder"

# Check if the folder already exists
#if [ -d "$folder_name" ]; then
#  echo "Error: Folder '$folder_name' already exists."
#  exit 1
#fi

# Create the new folder
mkdir -p  "$folder_name"

# Change to the new folder
cd "$folder_name"

# Download the docker-compose.yml file
curl -4O https://raw.githubusercontent.com/HelloWorldWinning/vps/main/upload_folder_d/docker-compose.yml

# Run docker-compose
docker-compose down
docker-compose pull
docker-compose up -d
echo "sleep 1s ..."
sleep 1
docker ps -a |grep 7777
