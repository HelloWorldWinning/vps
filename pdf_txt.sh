#!/bin/bash

 
# Prompt for a folder name
read -p "input folder name (default 'pdf_txt_folder'): " folder_name

# Use default folder name if none provided
folder_name=${folder_name:-pdf_txt_folder}

# Create the new folder
mkdir -p "$folder_name"

# Loop through all PDF files in the current directory
for file in *.pdf; do
    # Replace spaces in the filename with underscores
    new_filename=$(echo "$file" | sed 's/ /_/g')

    # Remove the PDF extension and add .txt extension
    new_filename="${new_filename%.pdf}.txt"

    # Convert the PDF to a text file and place it in the specified folder
    pdftotext "$file" "$folder_name/$new_filename"
done

tree "$folder_name"

