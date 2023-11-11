#!/bin/bash

# Prompt for folder name with default value
read -p "Input folder name (default 'pdf_to_html_folder'): " folder_name
folder_name=${folder_name:-pdf_to_html_folder}

# Create folder if it doesn't exist
mkdir -p "$folder_name"

# Initialize file counter
file_counter=1

# Prompt for Tika server URL input
read -p "Input Tika server URL (format '2t.jingyi.today:9998'): " tika_url_input
tika_url="http://${tika_url_input:-2t.jingyi.today:9998}"

# Create the final concatenated HTML file with a timestamp
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
final_html="${folder_name}/000_combined_${timestamp}.html"

# Create or clear the final HTML file
> "$final_html"

# Loop through all PDF files in the current directory
for file in *.pdf; do
    # Format the HTML filename with zero-padded document number and replace hyphens and spaces with underscores
#   padded_number=$(printf "%02d" $file_counter)
    padded_number=$(printf "%03d" $file_counter)
    formatted_file_name=$(echo "${padded_number}#_Document_${file}" | sed 's/[- ]/_/g')
    individual_html="${folder_name}/${formatted_file_name%.pdf}.html"

    # Echo the conversion progress for separate files
    echo "Converting '$file' to HTML format: $individual_html"

    # Use curl to send the PDF to the Tika server and create a separate HTML file
    curl -H "Content-Disposition: attachment; filename=$file" \
         -H "Content-Type: application/pdf" \
         -H "Accept: text/html; charset=UTF-8" \
         -T "$file" "$tika_url/tika" > "$individual_html"

    # Append a numbered header to the final combined HTML file
#   echo "<h1>${file_counter}# Document: $file</h1><hr>" >> "$final_html"
    echo "<h1>${formatted_file_name}# Document: $file</h1><hr>" >> "$final_html"

    # Append the content of the individual HTML file to the final combined HTML file
    cat "$individual_html" >> "$final_html"
    echo "<hr>" >> "$final_html"

    # Increment file counter
    ((file_counter++))
done

# Clear the screen and display the folder structure
clear
grep "# Document:" "$final_html"

