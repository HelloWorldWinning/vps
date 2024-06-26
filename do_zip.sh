#!/bin/bash

# Set the destination directory
destination_dir="/data"

# Get the current directory path
current_path=$(basename "$(pwd)")

# Generate a unique name for the archive
generated_name="${current_path}_$(date +%Y%m%d_%H%M%S).zip"

# Ask for compression option
read -p "Enter compression option (0-9, default: 0): " compression_option

# Set default compression option if no input provided
if [ -z "$compression_option" ]; then
    compression_option=0
fi

# Ask for files/folders to exclude
echo "Enter files/folders to exclude (one per line, press Enter twice to finish):"
exclude_list=()
while IFS= read -r line; do
    [[ $line ]] || break
    exclude_list+=("$line")
done

# Create the exclude options for zip command
exclude_options=""
for item in "${exclude_list[@]}"; do
    exclude_options+=" -x '$item/*' -x '$item'"
done

# Create the archive using zip with the specified compression option and exclude options
eval "zip -r$compression_option '$destination_dir/$generated_name' . $exclude_options"

# Check if the zip command completed successfully
if [ $? -eq 0 ]; then
    echo "Zip completed successfully with compression option $compression_option."
    echo "Archive created: $destination_dir/$generated_name"
else
    echo "Zip failed with compression option $compression_option."
fi
