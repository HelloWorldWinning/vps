#!/bin/bash

# Check if input file is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 input.py [output.py]"
    echo "If output.py is not specified, will create input_cleaned.py"
    exit 1
fi

input_file="$1"

# Check if input file exists
if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' does not exist"
    exit 1
fi

# Set output filename
if [ $# -eq 2 ]; then
    output_file="$2"
else
    filename="${input_file%.*}"
    output_file="${filename}_cleaned.py"
fi

# Process the Python file:
# 1. Remove single-line comments that start with #
# 2. Remove multi-line comments (docstrings) using sed
# 3. Remove empty lines and lines with only whitespace
# 4. Preserve empty lines that are syntactically important (e.g., between function definitions)
python3 -c "
import re

def remove_comments_and_minimize(content):
    # Remove multi-line strings/comments (docstrings)
    content = re.sub(r'\"\"\"[\s\S]*?\"\"\"|\'\'\'[\s\S]*?\'\'\'', '', content)
    
    # Process line by line
    lines = content.split('\n')
    cleaned_lines = []
    prev_line_empty = False
    
    for line in lines:
        # Remove inline comments (but preserve strings containing #)
        processed_line = ''
        in_string = False
        string_char = None
        i = 0
        
        while i < len(line):
            char = line[i]
            if char in ['\"', \"'\"]:
                if not in_string:
                    in_string = True
                    string_char = char
                elif char == string_char:
                    in_string = False
                processed_line += char
            elif char == '#' and not in_string:
                break
            else:
                processed_line += char
            i += 1
        
        # Strip whitespace
        processed_line = processed_line.rstrip()
        
        # Add non-empty lines or lines that are syntactically important
        if processed_line:
            cleaned_lines.append(processed_line)
            prev_line_empty = False
        elif not prev_line_empty and any(cleaned_lines) and \
             (cleaned_lines[-1].startswith(('def ', 'class ')) or \
              cleaned_lines[-1].endswith(':')):
            cleaned_lines.append('')
            prev_line_empty = True
    
    return '\n'.join(cleaned_lines)

# Read input file
with open('$input_file', 'r') as f:
    content = f.read()

# Process content
minimized = remove_comments_and_minimize(content)

# Write output
with open('$output_file', 'w') as f:
    f.write(minimized)
"

# Check if the process was successful
if [ $? -eq 0 ]; then
    echo "Successfully created minimized file: $output_file"
    # Show size reduction
    original_size=$(wc -c < "$input_file")
    new_size=$(wc -c < "$output_file")
    reduction=$(( (original_size - new_size) * 100 / original_size ))
    echo "Size reduction: $reduction% (from $original_size to $new_size bytes)"
else
    echo "Error occurred while processing the file"
    exit 1
fi
