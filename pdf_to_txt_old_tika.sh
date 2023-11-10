#!/bin/bash

# Prompt for folder name with default value
read -p "Input folder name (default 'txt_folder'): " folder_name
folder_name=${folder_name:-txt_folder}

# Create folder if it doesn't exist
mkdir -p "$folder_name"

# Tika server URL
tika_url="http://2t.jingyi.today:9998/"

# Loop through all PDF files in the current directory
for file in *.pdf; do
    # Replace spaces and hyphens with underscores in the filename
    new_filename=$(echo "$file" | sed 's/ /_/g' | sed 's/-/_/g')

    # Change the file extension to .txt
    new_filename="${new_filename%.pdf}.txt"

    # Echo the conversion progress
    echo "Converting '$file' to text format and saving as '$folder_name/$new_filename'"

    # Use curl to send the PDF to the Tika server and save the response
    curl -H "Content-Disposition: attachment; filename=$file" \
         -H "Content-Type: application/pdf" \
         -H "Accept: text/plain; charset=UTF-8" \
         -T "$file" "$tika_url/tika" > "$folder_name/$new_filename"
done

# Clear the screen and display the folder structure
clear
tree "$folder_name"

