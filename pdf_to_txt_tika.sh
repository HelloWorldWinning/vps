#!/bin/bash

# Prompt for folder name with default value
read -p "Input folder name (default 'pdf_to_txt_folder'): " folder_name
folder_name=${folder_name:-pdf_to_txt_folder}

# Create folder if it doesn't exist
mkdir -p "$folder_name"

# Generate a timestamp for the combined output file
current_time=$(date +"%Y-%m-%d_%H-%M-%S")
combined_output="${folder_name}/knowledge_database_${current_time}.txt"

# Initialize file counter
file_counter=1

# Prompt for Tika server URL input
read -p "Input Tika server URL (format '2t.jingyi.today:9998'): " tika_url_input
tika_url="http://${tika_url_input:-2t.jingyi.today:9998}"




# Loop through all PDF files in the current directory
for file in *.pdf; do
    # Replace spaces and hyphens with underscores in the filename
    new_filename=$(echo "$file" | sed 's/ /_/g' | sed 's/-/_/g')

    # Change the file extension to .txt
    new_filename="${new_filename%.pdf}.txt"

    # Echo the conversion progress
    echo "Converting '$file' to text format and appending to '${combined_output}'"

    # Append file number and separator to combined output
#   echo -e "\nFile #$file_counter: $file\n-------------------\n" >> "$combined_output"
    echo -e "\n------------------------------------------------------------\nFile #$file_counter: $file\n" >> "$combined_output"


    # Use curl to send the PDF to the Tika server, append the response to combined output
    curl -H "Content-Disposition: attachment; filename=$file" \
         -H "Content-Type: application/pdf" \
         -H "Accept: text/plain; charset=UTF-8" \
         -T "$file" "$tika_url/tika" >> "$combined_output"

    # Increment file counter
    ((file_counter++))
done

# Clear the screen and display the folder structure
clear
grep -n   "File #" "$combined_output"

