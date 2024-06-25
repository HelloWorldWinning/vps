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


   ##################
   #
   ## GitHub API URL for the content of the directory
   #API_URL="https://api.github.com/repos/HelloWorldWinning/vps/contents/ft/info_d?ref=main"
   #
   ## Local directory where files will be saved
   #LOCAL_DIR="info_d"
   #
   ## Create the local directory if it does not exist
   #mkdir -p "$LOCAL_DIR"
   #
   ## Use GitHub API to list files in the directory and then download each one
   #curl -s $API_URL | jq -r '.[] | .download_url' | while read file_url; do
   #    echo "Downloading $file_url"
   #    curl -L $file_url -o "$LOCAL_DIR/$(basename $file_url)"
   #done
   #
   #echo "info_d Download completed."






# GitHub repository details
REPO_OWNER="HelloWorldWinning"
REPO_NAME="vps"
REPO_PATH="ft/info_d"
BRANCH="main"

# Local directory where files will be saved
LOCAL_DIR="info_d"

# Function to download files recursively
download_files() {
    local path=$1
    local api_url="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$path?ref=$BRANCH"

    # Use GitHub API to list files in the directory
    curl -s $api_url | jq -c '.[]' | while read item; do
        local item_type=$(echo $item | jq -r '.type')
        local item_path=$(echo $item | jq -r '.path')
        local item_url=$(echo $item | jq -r '.download_url')

        if [ "$item_type" = "dir" ]; then
            # If it's a directory, create it locally and recurse
            mkdir -p "$LOCAL_DIR/$item_path"
            download_files "$item_path"
        else
            # If it's a file, download it
            echo "Downloading $item_url"
            curl -L "$item_url" -o "$LOCAL_DIR/$item_path"
        fi
    done
}

# Create the local directory if it does not exist
mkdir -p "$LOCAL_DIR"

# Start the download process
download_files "$REPO_PATH"

echo "Download completed for $REPO_PATH and all its subdirectories."
