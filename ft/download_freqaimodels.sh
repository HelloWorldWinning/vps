#!/bin/bash

# GitHub API URL for the content of the directory
API_URL="https://api.github.com/repos/HelloWorldWinning/vps/contents/ft/freqaimodels_d?ref=main"

# Local directory where files will be saved
LOCAL_DIR="user_data/freqaimodels"

# Create the local directory if it does not exist
mkdir -p "$LOCAL_DIR"

# Use GitHub API to list files in the directory and then download each one
curl -s $API_URL | jq -r '.[] | .download_url' | while read file_url; do
    echo "Downloading $file_url"
    curl -L $file_url -o "$LOCAL_DIR/$(basename $file_url)"
done

echo "freqaimodels_d Download completed."


#################

# GitHub API URL for the content of the directory
API_URL="https://api.github.com/repos/HelloWorldWinning/vps/contents/ft/info_d?ref=main"

# Local directory where files will be saved
LOCAL_DIR="info_d"

# Create the local directory if it does not exist
mkdir -p "$LOCAL_DIR"

# Use GitHub API to list files in the directory and then download each one
curl -s $API_URL | jq -r '.[] | .download_url' | while read file_url; do
    echo "Downloading $file_url"
    curl -L $file_url -o "$LOCAL_DIR/$(basename $file_url)"
done

echo "info_d Download completed."
