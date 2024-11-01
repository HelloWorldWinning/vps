#!/bin/bash

# Define variables
FOLDER="/data/google_todynalist_pdftotxt_instance_d"
#GITHUB_URL="https://raw.githubusercontent.com/HelloWorldWinning/vps/main/docker-compose_google_todynalist_pdftotxt_instance.yml"
GITHUB_URL="https://raw.githubusercontent.com/HelloWorldWinning/vps/main/docker-compose_google_todynalist_pdftotxt_instance_bridge.yml"
CONTAINER1="google_todynalist_pdftotxt_instance"
CONTAINER2="tika-server_instance"

# Check if the folder exists and remove it if it does
if [ -d "$FOLDER" ]; then
    echo "Removing existing folder: $FOLDER"
    rm -rf "$FOLDER"
fi

# Create a new folder
echo "Creating new folder: $FOLDER"
mkdir -p "$FOLDER"

# Change to the new folder
cd "$FOLDER"

# Download the docker-compose file
echo "Downloading docker-compose file"
wget -4 --no-check-certificate  "$GITHUB_URL" -O docker-compose.yml

# Check if the download was successful
if [ $? -eq 0 ]; then
    echo "Docker-compose file downloaded successfully"
    
    docker-compose  pull
    # Run docker-compose
    echo "Running docker-compose up -d"
    docker-compose up -d
    
    # Wait for containers to start
    echo "Waiting for containers to start..."
    sleep 4
    
    # Check if specific containers are running
    echo "Checking if containers are running..."
    
    if docker ps --format '{{.Names}}' | grep -q "$CONTAINER1"; then
        echo "$CONTAINER1 is running."
    else
        echo "Warning: $CONTAINER1 is not running."
    fi
    
    if docker ps --format '{{.Names}}' | grep -q "$CONTAINER2"; then
        echo "$CONTAINER2 is running."
    else
        echo "Warning: $CONTAINER2 is not running."
    fi
    
    # Check overall status
    if docker ps --format '{{.Names}}' | grep -q "$CONTAINER1" && docker ps --format '{{.Names}}' | grep -q "$CONTAINER2"; then
        echo "All specified containers are running successfully!"
    else
        echo "Warning: Not all specified containers are running. Please check 'docker ps' for more information."
    fi
else
    echo "Failed to download docker-compose file"
    exit 1
fi

echo "Script execution completed"
