#!/bin/bash

# Prompt for folder name with default value
read -p "Input folder name (default 'html_folder'): " folder_name
folder_name=${folder_name:-html_folder}

# Create folder if it doesn't exist
mkdir -p "$folder_name"

# Tika server URL
tika_url="http://2t.jingyi.today:9998/"

# Temporary directory for individual HTML files
temp_folder="temp_html_files"
mkdir -p "$temp_folder"

# Initialize a variable for the final HTML content
final_html="$folder_name/combined.html"
echo "" > "$final_html"

# Loop through all PDF files in the current directory
for file in *.pdf; do
    # Replace spaces and hyphens with underscores in the filename
    new_filename=$(echo "$file" | sed 's/ /_/g' | sed 's/-/_/g')

    # Change the file extension to .html
    temp_html_file="$temp_folder/${new_filename%.pdf}.html"

    # Echo the conversion progress
    echo "Converting '$file' to HTML format"

    # Use curl to send the PDF to the Tika server and save the response
    curl -H "Content-Disposition: attachment; filename=$file" \
         -H "Content-Type: application/pdf" \
         -H "Accept: text/html; charset=UTF-8" \
         -T "$file" "$tika_url/tika" > "$temp_html_file"

    # Append this HTML file to the final combined HTML file
    cat "$temp_html_file" >> "$final_html"
done

# Remove the temporary folder with individual HTML files
rm -rf "$temp_folder"

# Clear the screen and display the folder structure
clear
tree "$folder_name"

