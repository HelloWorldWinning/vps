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
    echo "Fetching contents of $path"
    
    # Use GitHub API to list files in the directory
    local response=$(curl -s -H "Accept: application/vnd.github.v3+json" "$api_url")
    
    # Check if the response is valid JSON
    if ! echo "$response" | jq empty > /dev/null 2>&1; then
        echo "Error: Invalid response from GitHub API"
        echo "Response: $response"
        return 1
    fi

    # Check if the response is an error message
    if echo "$response" | jq -e 'type == "object" and has("message")' > /dev/null; then
        echo "Error: $(echo "$response" | jq -r '.message')"
        return 1
    fi

    # Ensure the response is an array
    if ! echo "$response" | jq -e 'type == "array"' > /dev/null; then
        echo "Error: Unexpected response format"
        echo "Response: $response"
        return 1
    fi

    echo "$response" | jq -c '.[]' | while read item; do
        local item_type=$(echo $item | jq -r '.type')
        local item_name=$(echo $item | jq -r '.name')
        local item_path=$(echo $item | jq -r '.path')
        local item_url=$(echo $item | jq -r '.download_url')
        
        # Remove 'ft/info_d/' from the beginning of item_path
        local relative_path=${item_path#"$REPO_PATH/"}
        
        if [ "$item_type" = "dir" ]; then
            # If it's a directory, create it locally and recurse
            echo "Creating directory: $LOCAL_DIR/$relative_path"
            mkdir -p "$LOCAL_DIR/$relative_path"
            download_files "$item_path"
        elif [ "$item_type" = "file" ]; then
            # If it's a file, download it
            echo "Downloading $item_url to $LOCAL_DIR/$relative_path"
            curl -L -o "$LOCAL_DIR/$relative_path" "$item_url"
        else
            echo "Unknown item type: $item_type for $item_name"
        fi
    done
}

# Remove existing local directory if it exists
rm -rf "$LOCAL_DIR"

# Create the local directory
mkdir -p "$LOCAL_DIR"

# Start the download process
download_files "$REPO_PATH"

echo "Download completed for $REPO_PATH and all its subdirectories."





