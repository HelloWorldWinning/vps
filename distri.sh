#!/bin/bash

# Prompt the user for the number of folders to create
read -p "Enter the number of folders to create (default is 3): " num_folders

# Set the default value to 3 if no input is provided
num_folders=${num_folders:-3}

# Get the current folder name
current_folder_name=$(basename "$PWD")

# Create the specified number of folders with meaningful names
for ((i=1; i<=num_folders; i++))
do
    folder_name="${current_folder_name}_segment_part_$i"
    mkdir -p "$folder_name"
done

# Get a list of files and folders, excluding the created folders and the script itself
file_list=$(find . -maxdepth 1 \( -type f -o -type d \) -not -name "${current_folder_name}_segment_part_*" -not -name "$(basename "$0")" -print)

# Initialize a counter for distributing files and folders
counter=1

# Distribute files and folders into the smaller folders
while IFS= read -r item; do
    # Skip the current directory
    if [[ "$item" == "." ]]; then
        continue
    fi

    # Get the folder name based on the counter
    folder_name="${current_folder_name}_segment_part_$counter"

    # Move the file or folder to the corresponding folder
    mv -v "$item" "$folder_name"

    # Increment the counter and reset it if it exceeds the number of folders
    counter=$((counter + 1))
    if ((counter > num_folders)); then
        counter=1
    fi
done <<< "$file_list"

echo "Files and folders have been distributed into $num_folders folders."

